"""Daily database backup (JSON + gzip + optional PBKDF2-Fernet encryption) sent to admins."""

from __future__ import annotations

import asyncio
import base64
import gzip
import hashlib
import io
import json
import logging
import os
from datetime import datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from aiogram import Bot
from aiogram.types import BufferedInputFile
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from sqlalchemy import select

from config import get_settings
from database.models import Base
from database.session import async_session_maker

logger = logging.getLogger("hisobot_bot.backup")

BACKUP_HOUR = 23
BACKUP_MINUTE = 30
MAX_TELEGRAM_FILE = 49 * 1024 * 1024
ENC_MAGIC = b"HENC1"
SALT_LEN = 16


def _json_default(value: Any) -> str:
    if isinstance(value, datetime):
        return value.isoformat()
    return str(value)


def _derive_fernet_key(password: str, salt: bytes) -> bytes:
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=390_000,
    )
    return base64.urlsafe_b64encode(kdf.derive(password.encode("utf-8")))


def encrypt_backup_bytes(raw_gz: bytes, password: str) -> bytes:
    """Encrypt gzip backup payload using PBKDF2-HMAC-SHA256 + Fernet (AES-128-CBC + HMAC)."""
    salt = os.urandom(SALT_LEN)
    token = Fernet(_derive_fernet_key(password, salt)).encrypt(raw_gz)
    return ENC_MAGIC + salt + token


def decrypt_backup_bytes(blob: bytes, password: str) -> bytes:
    """Decrypt backup bytes created by ``encrypt_backup_bytes``."""
    if not blob.startswith(ENC_MAGIC):
        return blob
    salt = blob[len(ENC_MAGIC) : len(ENC_MAGIC) + SALT_LEN]
    token = blob[len(ENC_MAGIC) + SALT_LEN :]
    return Fernet(_derive_fernet_key(password, salt)).decrypt(token)


async def build_backup_bytes() -> bytes:
    """Dump all persistent tables (excluding transient FSM states) to gzip-compressed JSON."""
    dump: dict[str, list[dict[str, Any]]] = {}
    async with async_session_maker() as db:
        for table in Base.metadata.sorted_tables:
            if table.name == "fsm_states":
                continue
            result = await db.execute(select(table))
            dump[table.name] = [dict(row._mapping) for row in result]
    payload = json.dumps(
        {"created_at": datetime.now(ZoneInfo(get_settings().TIMEZONE)).isoformat(), "tables": dump},
        ensure_ascii=False,
        default=_json_default,
    ).encode("utf-8")
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb") as gz:
        gz.write(payload)
    return buf.getvalue()


async def send_backup(bot: Bot, chat_ids: list[int] | None = None) -> bool:
    """Send a fresh (optionally encrypted) backup file to admins' private chats."""
    settings = get_settings()
    targets = chat_ids or settings.admin_id_list
    if not targets:
        logger.warning("Backup skipped: ADMIN_IDS is empty.")
        return False
    raw_gz = await build_backup_bytes()
    pwd = (settings.BACKUP_PASSWORD or "").strip()
    if pwd:
        data = encrypt_backup_bytes(raw_gz, pwd)
        ext = "json.gz.enc"
        caption_prefix = "🔐 Shifrlangan baza zaxirasi"
    else:
        data = raw_gz
        ext = "json.gz"
        caption_prefix = "💾 Baza zaxirasi (parolsiz)"

    if len(data) > MAX_TELEGRAM_FILE:
        for cid in targets:
            await bot.send_message(cid, "⚠️ Backup fayli Telegram limitidan katta, yuborilmadi.")
        return False

    stamp = datetime.now(ZoneInfo(settings.TIMEZONE)).strftime("%Y-%m-%d_%H%M")
    sent = False
    for cid in targets:
        try:
            await bot.send_document(
                cid,
                BufferedInputFile(data, filename=f"hisobchi_backup_{stamp}.{ext}"),
                caption=f"{caption_prefix} ({stamp}). Shaxsiy saqlang, hech kimga yubormang.",
            )
            sent = True
        except Exception:
            logger.exception("Backup send failed for %s", cid)
    return sent


def _seconds_until_next_run() -> float:
    tz = ZoneInfo(get_settings().TIMEZONE)
    now = datetime.now(tz)
    nxt = now.replace(hour=BACKUP_HOUR, minute=BACKUP_MINUTE, second=0, microsecond=0)
    if nxt <= now:
        nxt += timedelta(days=1)
    return (nxt - now).total_seconds()


async def backup_scheduler(bot: Bot) -> None:
    """Background loop: send a backup every day at BACKUP_HOUR:BACKUP_MINUTE."""
    while True:
        await asyncio.sleep(_seconds_until_next_run())
        try:
            await send_backup(bot)
        except Exception:
            logger.exception("Scheduled backup failed")
        await asyncio.sleep(60)
