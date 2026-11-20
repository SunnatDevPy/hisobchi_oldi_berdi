"""Daily database backup (JSON + gzip) sent to the owner's private chat.

Works with both SQLite and PostgreSQL (no pg_dump needed). Restore with
``python scripts/restore_backup.py <file.json.gz>`` (see README).
"""

from __future__ import annotations

import asyncio
import gzip
import io
import json
import logging
from datetime import datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from aiogram import Bot
from aiogram.types import BufferedInputFile
from sqlalchemy import select

from config import get_settings
from database.models import Base
from database.session import async_session_maker

logger = logging.getLogger("hisobot_bot.backup")

BACKUP_HOUR = 23
BACKUP_MINUTE = 30
MAX_TELEGRAM_FILE = 49 * 1024 * 1024


def _json_default(value: Any) -> str:
    if isinstance(value, datetime):
        return value.isoformat()
    return str(value)


async def build_backup_bytes() -> bytes:
    """Dump every table to a gzip-compressed JSON document."""
    dump: dict[str, list[dict[str, Any]]] = {}
    async with async_session_maker() as db:
        for table in Base.metadata.sorted_tables:
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
    """Send a fresh backup file to admins' private chats. Returns True if sent to anyone."""
    targets = chat_ids or get_settings().admin_id_list
    if not targets:
        logger.warning("Backup skipped: ADMIN_IDS is empty.")
        return False
    data = await build_backup_bytes()
    if len(data) > MAX_TELEGRAM_FILE:
        for cid in targets:
            await bot.send_message(cid, "⚠️ Backup fayli Telegram limitidan katta, yuborilmadi.")
        return False
    stamp = datetime.now(ZoneInfo(get_settings().TIMEZONE)).strftime("%Y-%m-%d_%H%M")
    sent = False
    for cid in targets:
        try:
            await bot.send_document(
                cid,
                BufferedInputFile(data, filename=f"hisobchi_backup_{stamp}.json.gz"),
                caption=f"💾 Baza zaxirasi ({stamp}). Shaxsiy saqlang, hech kimga yubormang.",
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
