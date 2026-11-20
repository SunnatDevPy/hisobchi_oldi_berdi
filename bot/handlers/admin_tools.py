"""Owner-only tools: /backup, /audit and global error alerts."""

from __future__ import annotations

import html
import logging
import traceback

from aiogram import Bot, F, Router
from aiogram.filters import Command
from aiogram.types import ErrorEvent, Message

from config import get_settings
from aiogram.types import BufferedInputFile

from database.crud import format_local_dt, get_supplier_sverka, list_audit_logs, now_local
from services.excel_export import build_sverka_excel
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


def _fmt(n: float) -> str:
    return f"{round(n):,}".replace(",", " ")


@router.message(Command("sverka"), F.chat.type == "private")
async def cmd_sverka(message: Message) -> None:
    """/sverka [YYYY-MM] [postavshik] — monthly totals per supplier + Excel."""
    if not _is_admin(message.from_user.id):
        return
    parts = (message.text or "").split(maxsplit=2)[1:]
    month = now_local().strftime("%Y-%m")
    if parts and len(parts[0]) == 7 and parts[0][4] == "-" and parts[0].replace("-", "").isdigit():
        month = parts.pop(0)
    supplier = " ".join(parts).strip() or None
    async with async_session_maker() as db:
        rows = await get_supplier_sverka(db, month, supplier)
    if not rows:
        await message.answer(
            f"📭 {month} oyida ma'lumot topilmadi."
            "\n<i>Foydalanish: /sverka [2026-11] [postavshik nomi]</i>",
            parse_mode="HTML",
        )
        return
    if supplier:
        lines = [f"🏢 <b>{html.escape(rows[0]['supplier'])}</b> — {month}"]
        for r in rows:
            lines.append(f"{r['date'][8:]}.{r['date'][5:7]} {r['time']} — <b>{_fmt(r['amount'])}</b>")
        lines.append(f"\n💰 Jami: <b>{_fmt(sum(r['amount'] for r in rows))}</b> so'm ({len(rows)} ta)")
    else:
        totals: dict[str, list] = {}
        for r in rows:
            e = totals.setdefault(r["supplier"].lower(), [r["supplier"], 0, 0.0])
            e[1] += 1
            e[2] += r["amount"]
        lines = [f"📊 <b>Postavshiklar sverkasi — {month}</b>"]
        for i, (name, cnt, total) in enumerate(sorted(totals.values(), key=lambda e: -e[2]), 1):
            lines.append(f"{i}) {html.escape(name)} — <b>{_fmt(total)}</b> ({cnt} ta)")
        lines.append(f"\n💰 Jami: <b>{_fmt(sum(r['amount'] for r in rows))}</b> so'm")
    text = "\n".join(lines)
    await message.answer(text[:4000], parse_mode="HTML")
    await message.answer_document(
        BufferedInputFile(build_sverka_excel(month, rows), filename=f"sverka_{month}.xlsx")
    )