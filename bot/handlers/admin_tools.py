"""Owner-only tools: /backup, /audit and global error alerts."""

from __future__ import annotations

import html
import logging
import traceback

from aiogram import Bot, F, Router
from aiogram.filters import Command
from aiogram.types import ErrorEvent, Message

from config import get_settings
from database.crud import format_local_dt, list_audit_logs
from database.session import async_session_maker
from services.backup import send_backup

logger = logging.getLogger("hisobot_bot.admin")
router = Router(name="admin_tools")

ACTION_ICONS = {"edit": "✏️", "delete": "🗑", "confirm": "✅"}


def _is_admin(user_id: int | None) -> bool:
    ids = get_settings().admin_id_list
    return bool(user_id) and user_id in ids


@router.message(Command("backup"), F.chat.type == "private")
async def cmd_backup(message: Message) -> None:
    """Send a database backup to the requesting admin right now."""
    if not _is_admin(message.from_user.id):
        return
    await message.answer("💾 Zaxira tayyorlanmoqda...")
    ok = await send_backup(message.bot, [message.from_user.id])
    if not ok:
        await message.answer("❌ Zaxira yuborilmadi (logni tekshiring).")


@router.message(Command("audit"), F.chat.type == "private")
async def cmd_audit(message: Message) -> None:
    """Show the last 20 edits/deletes/confirmations."""
    if not _is_admin(message.from_user.id):
        return
    async with async_session_maker() as db:
        logs = await list_audit_logs(db, 20)
    if not logs:
        await message.answer("Hozircha o'zgarishlar yo'q.")
        return
    lines = ["🧾 <b>Oxirgi o'zgarishlar:</b>"]
    for item in logs:
        icon = ACTION_ICONS.get(item.action, "•")
        lines.append(
            f"{icon} {format_local_dt(item.created_at)} — {item.entity} #{item.entity_id}: "
            f"<i>{html.escape(item.details)}</i>"
        )
    await message.answer("\n".join(lines), parse_mode="HTML")


@router.errors()
async def on_error(event: ErrorEvent, bot: Bot) -> bool:
    """Log the exception and alert admins so a silent failure is noticed."""
    logger.error("Unhandled error", exc_info=event.exception)
    tb = "".join(traceback.format_exception_only(type(event.exception), event.exception)).strip()
    for admin_id in get_settings().admin_id_list:
        try:
            await bot.send_message(admin_id, f"⚠️ Botda xatolik:\n<code>{html.escape(tb[:800])}</code>", parse_mode="HTML")
        except Exception:
            pass
    return True
