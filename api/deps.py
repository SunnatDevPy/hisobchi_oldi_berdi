"""Shared Telegram Bot reference and group posting/sync helpers for the mobile REST API."""

from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path
from typing import Optional

from aiogram import Bot
from aiogram.types import BufferedInputFile

from bot.handlers.wallet_nakladnoy import (
    _schedule_group_sync,
    _sync_nakladnoy_group_message,
    render_nakladnoy_group_caption,
)
from database.crud import (
    get_app_setting,
    get_group_config,
    get_nakladnoy,
    get_nakladnoy_session_seq,
    set_nakladnoy_group_message,
)
from database.models import NakladnoyPayment
from database.session import async_session_maker
from services.gemini_ai import compress_image_for_ocr


logger = logging.getLogger("hisobot_bot.api.deps")

APK_PHOTOS_DIR = Path("data/apk_photos")
APK_BINARY_PATH = Path("data/hisobchi.apk")
APK_VERSION_PATH = Path("data/apk_version.json")
_ACTIVE_BOT: Optional[Bot] = None


def get_apk_version_metadata() -> dict:
    """Read current deployed APK version and build number from data/apk_version.json."""
    meta = {
        "version": "1.0.0",
        "build": 1,
        "full": "1.0.0+1",
        "built_at": "",
        "size_bytes": 0,
        "available": False,
    }
    if APK_VERSION_PATH.is_file():
        try:
            loaded = json.loads(APK_VERSION_PATH.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                meta["version"] = str(loaded.get("version") or meta["version"])
                meta["build"] = int(loaded.get("build") or meta["build"])
                meta["full"] = str(loaded.get("full") or f"{meta['version']}+{meta['build']}")
                meta["built_at"] = str(loaded.get("built_at") or "")
        except Exception:
            pass
    if APK_BINARY_PATH.is_file():
        st = APK_BINARY_PATH.stat()
        meta["size_bytes"] = int(st.st_size)
        meta["available"] = True
    return meta


def set_bot(bot: Optional[Bot]) -> None:
    """Register the active aiogram Bot instance so REST endpoints can post/edit group messages."""
    global _ACTIVE_BOT
    _ACTIVE_BOT = bot


def get_bot() -> Optional[Bot]:
    """Return the active aiogram Bot instance (or None in unit tests without a live bot)."""
    return _ACTIVE_BOT


def get_local_photo_path(payment_id: int) -> Path:
    """Return deterministic local path for an APK-uploaded nakladnoy photo."""
    APK_PHOTOS_DIR.mkdir(parents=True, exist_ok=True)
    return APK_PHOTOS_DIR / f"nak_{int(payment_id)}.jpg"


def save_local_photo(payment_id: int, photo_bytes: bytes) -> Path:
    """Normalize (strip broken Xiaomi/MediaTek EXIF) and persist photo bytes to data/apk_photos/nak_<id>.jpg."""
    clean_bytes, _ = compress_image_for_ocr(photo_bytes, max_side=1600, quality=88)
    path = get_local_photo_path(payment_id)
    path.write_bytes(clean_bytes)
    return path


def has_local_photo(payment_id: int) -> bool:
    """Check whether a local APK photo file exists on disk for payment_id."""
    return get_local_photo_path(payment_id).is_file()


async def is_apk_group_post_enabled() -> bool:
    """Return True if `/apk` setting allows posting APK nakladnoys to the bound Telegram group."""
    async with async_session_maker() as db:
        val = await get_app_setting(db, "apk_post_to_group", "on")
    return (val or "on").strip().lower() != "off"


async def post_nakladnoy_to_telegram_group(
    payment_id: int,
    photo_bytes: Optional[bytes] = None,
    force: bool = False,
) -> tuple[bool, str]:
    """Send a confirmed nakladnoy from APK to the bound Telegram Nakladnoy group.

    Stores ``group_chat_id``, ``group_message_id``, and (when a photo was sent) Telegram's
    ``photo_file_id`` so future edits sync captions seamlessly.
    """
    bot = get_bot()
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
        if payment is None or payment.status != "confirmed":
            return False, "Nakladnoy topilmadi"
        grp = await get_group_config(db, "nakladnoy")
        apk_toggle = await get_app_setting(db, "apk_post_to_group", "on")
        session_seq = await get_nakladnoy_session_seq(db, payment)

    if not force and (apk_toggle or "on").strip().lower() == "off":
        return False, "Botda APK guruhga yuborish o'chirilgan (/apk)"

    if grp is None or not grp.chat_id:
        return False, "Nakladnoy guruhi bog'lanmagan"

    if bot is None:
        return False, "Telegram bot ulanmagan"

    # If already posted to group and not forced as new, update existing message
    if payment.group_chat_id and payment.group_message_id:
        ok, msg = await _sync_nakladnoy_group_message(
            bot, payment, tag="", session_seq=session_seq
        )
        return ok, msg

    if photo_bytes is None and has_local_photo(payment_id):
        try:
            photo_bytes = get_local_photo_path(payment_id).read_bytes()
        except Exception:
            photo_bytes = None

    if photo_bytes:
        photo_bytes, _ = await asyncio.to_thread(
            compress_image_for_ocr, photo_bytes, 1600, 88
        )

    caption = render_nakladnoy_group_caption(payment, tag="", session_seq=session_seq)
    try:
        tg_file_id: Optional[str] = None
        if photo_bytes:
            inp = BufferedInputFile(photo_bytes, filename=f"nakladnoy_{payment.id}.jpg")
            try:
                sent = await bot.send_photo(
                    chat_id=grp.chat_id,
                    photo=inp,
                    caption=caption,
                    parse_mode="HTML",
                )
                if sent.photo:
                    tg_file_id = sent.photo[-1].file_id
            except Exception as photo_exc:
                logger.warning(
                    "send_photo failed for payment_id=%s (%s), falling back to text message",
                    payment.id,
                    photo_exc,
                )
                sent = await bot.send_message(
                    chat_id=grp.chat_id,
                    text=caption,
                    parse_mode="HTML",
                )
        elif payment.photo_file_id:
            sent = await bot.send_photo(
                chat_id=grp.chat_id,
                photo=payment.photo_file_id,
                caption=caption,
                parse_mode="HTML",
            )
        else:
            sent = await bot.send_message(
                chat_id=grp.chat_id,
                text=caption,
                parse_mode="HTML",
            )

        async with async_session_maker() as db:
            row = await get_nakladnoy(db, payment.id)
            if row is not None:
                row.group_chat_id = grp.chat_id
                row.group_message_id = sent.message_id
                if tg_file_id and not row.photo_file_id:
                    row.photo_file_id = tg_file_id
                await db.commit()
        return True, f"Guruhga yuborildi ({grp.title or grp.chat_id})"
    except Exception as exc:
        logger.warning("APK group post failed payment_id=%s: %s", payment.id, exc)
        return False, f"Guruhga yuborishda xatolik: {exc}"


def sync_existing_group_message(
    payment: NakladnoyPayment, tag: str = "✏️ [TAHRIRLANDI]"
) -> Optional[str]:
    """Schedule non-blocking group message caption/text update if bot is active."""
    bot = get_bot()
    if bot is None or not payment.group_chat_id or not payment.group_message_id:
        return None
    return _schedule_group_sync(bot, payment, tag=tag)
