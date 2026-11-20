"""Owner/admin tools: /backup, /audit, /sverka, /stats, /roles, and error alerts."""

from __future__ import annotations

from datetime import timedelta
import html
import logging
import re
import traceback

from aiogram import Bot, F, Router
from aiogram.filters import Command
from aiogram.types import BufferedInputFile, CallbackQuery, ErrorEvent, Message

from bot.auth import deny_if_unauthorized, is_admin_role, is_authorized
from bot.keyboards import roles_list_kb, stats_menu_kb
from config import get_settings
from database.crud import (
    format_local_dt,
    get_ai_usage_stats,
    get_period_statistics,
    get_supplier_sverka,
    list_audit_logs,
    list_user_roles,
    now_local,
    today_iso,
)
from database.session import async_session_maker
from services.backup import send_backup
from services.excel_export import build_sverka_excel
from services.gemini_ai import format_uzs


logger = logging.getLogger("hisobot_bot.admin")
router = Router(name="admin_tools")

ACTION_ICONS = {"edit": "✏️", "delete": "🗑", "confirm": "✅", "debt": "📒", "payment": "💵"}


def _safe_filename_part(text: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]+", "_", text).strip("_") or "all"


async def send_audit_view(target: Message | CallbackQuery) -> None:
    """Render last 20 audit entries + today's AI token usage stats."""
    async with async_session_maker() as db:
        logs = await list_audit_logs(db, 20)
        ai = await get_ai_usage_stats(db)
    lines = [
        f"🤖 <b>Bugungi AI sarfi ({ai['date']}):</b> "
        f"{ai['calls']} ta chaqiruv (📸 {ai['photo_calls']} | 🎤 {ai['audio_calls']} | ♻️ kesh: {ai['cache_hits']}) — "
        f"<b>{format_uzs(ai['total_tokens'])}</b> token\n",
        "🧾 <b>Oxirgi o'zgarishlar:</b>",
    ]
    if not logs:
        lines.append("<i>Hozircha o'zgarishlar yo'q.</i>")
    else:
        for item in logs:
            icon = ACTION_ICONS.get(item.action, "•")
            who = f" [<code>{item.user_id}</code>]" if item.user_id else ""
            lines.append(
                f"{icon} {format_local_dt(item.created_at)}{who} — {item.entity} #{item.entity_id}: "
                f"<i>{html.escape(item.details)}</i>"
            )
    text = "\n".join(lines)[:4000]
    if isinstance(target, CallbackQuery):
        try:
            await target.message.edit_text(text, parse_mode="HTML")
        except Exception:
            await target.message.answer(text, parse_mode="HTML")
        await target.answer()
    else:
        await target.answer(text, parse_mode="HTML")


async def _send_sverka_report(
    bot: Bot,
    reply_target: Message,
    user_id: int,
    month: str,
    supplier: str | None = None,
) -> None:
    """Generate and deliver supplier reconciliation text + Excel privately."""
    async with async_session_maker() as db:
        rows = await get_supplier_sverka(db, month, supplier)
    if not rows:
        await reply_target.answer(
            f"📭 {month} oyida ma'lumot topilmadi.\n"
            "<i>Foydalanish: /sverka [2026-11] [postavshik nomi]</i>",
            parse_mode="HTML",
        )
        return

    if supplier:
        lines = [f"🏢 <b>{html.escape(rows[0]['supplier'])}</b> — {month}"]
        for r in rows[:50]:
            lines.append(f"{r['date'][8:]}.{r['date'][5:7]} {r['time']} — <b>{format_uzs(r['amount'])}</b>")
        if len(rows) > 50:
            lines.append(f"<i>...yana {len(rows) - 50} ta (to'liq ro'yxat Excel'da)</i>")
        lines.append(f"\n💰 Jami: <b>{format_uzs(sum(r['amount'] for r in rows))}</b> so'm ({len(rows)} ta)")
        fname = f"Sverka_{month}_{_safe_filename_part(rows[0]['supplier'])}.xlsx"
    else:
        totals: dict[str, list] = {}
        for r in rows:
            e = totals.setdefault(r["supplier"].lower(), [r["supplier"], 0, 0.0])
            e[1] += 1
            e[2] += r["amount"]
        lines = [f"📊 <b>Postavshiklar sverkasi — {month}</b>"]
        for i, (name, cnt, total) in enumerate(sorted(totals.values(), key=lambda e: -e[2]), 1):
            lines.append(f"{i}) {html.escape(name)} — <b>{format_uzs(total)}</b> ({cnt} ta)")
        lines.append(f"\n💰 Jami: <b>{format_uzs(sum(r['amount'] for r in rows))}</b> so'm")
        fname = f"Sverka_{month}.xlsx"

    await reply_target.answer("\n".join(lines)[:4000], parse_mode="HTML")
    doc = BufferedInputFile(build_sverka_excel(month, rows), filename=fname)
    # E7: Always deliver Excel to private DM
    dest_chat = user_id if reply_target.chat.type != "private" else reply_target.chat.id
    await bot.send_document(dest_chat, doc, caption=f"📥 <code>{fname}</code>", parse_mode="HTML")


def _render_period_stats_text(title: str, st: dict) -> str:
    lines = [
        f"📈 <b>{title}</b> (<code>{st['date_from']}</code> → <code>{st['date_to']}</code>)",
        "===============================",
        f"💸 Jami rasxod ({st['payment_count']} ta nakladnoy): <b>{format_uzs(st['total_spent'])} so'm</b>",
        f"📅 Faol kunlar: <b>{st['active_days']} kun</b> | Kunlik o'rtacha: <b>{format_uzs(st['avg_daily_spend'])} so'm</b>",
        f"🧾 O'rtacha to'lov: <b>{format_uzs(st['avg_payment'])} so'm</b>",
        f"➕ Asosiy kirim: <b>{format_uzs(st['total_cash_in'])} so'm</b>",
    ]
    if st["busiest_day"]:
        bd, bt = st["busiest_day"]
        lines.append(f"🔥 Eng katta rasxod kuni: <code>{bd}</code> — <b>{format_uzs(bt)} so'm</b>")
    if st["top_suppliers"]:
        lines.append("\n🏆 <b>Top postavshiklar:</b>")
        for idx, (name, cnt, tot, pct) in enumerate(st["top_suppliers"], start=1):
            lines.append(
                f"{idx}) {html.escape(name)} — <b>{format_uzs(tot)}</b> ({cnt} ta, {pct:.1f}%)"
            )
    return "\n".join(lines)


@router.message(Command("backup"), F.chat.type == "private")
async def cmd_backup(message: Message) -> None:
    """Send a database backup to the requesting admin right now."""
    if not is_admin_role(message.from_user.id if message.from_user else None):
        return
    await message.answer("💾 Zaxira tayyorlanmoqda...")
    ok = await send_backup(message.bot, [message.from_user.id])
    if not ok:
        await message.answer("❌ Zaxira yuborilmadi (logni tekshiring).")


@router.message(Command("audit"), F.chat.type == "private")
async def cmd_audit(message: Message) -> None:
    """Show the last 20 edits/deletes/confirmations + AI stats."""
    if not is_admin_role(message.from_user.id if message.from_user else None):
        return
    await send_audit_view(message)


@router.message(Command("sverka"), F.chat.type == "private")
async def cmd_sverka(message: Message) -> None:
    """/sverka [YYYY-MM] [postavshik] — monthly totals per supplier + Excel."""
    if await deny_if_unauthorized(message):
        return
    parts = (message.text or "").split(maxsplit=2)[1:]
    month = now_local().strftime("%Y-%m")
    if parts and len(parts[0]) == 7 and parts[0][4] == "-" and parts[0].replace("-", "").isdigit():
        month = parts.pop(0)
    supplier = " ".join(parts).strip() or None
    await _send_sverka_report(message.bot, message, message.from_user.id, month, supplier)


@router.message(Command("stats"), F.chat.type == "private")
async def cmd_stats(message: Message) -> None:
    """Show weekly/monthly spending statistics menu (Y5)."""
    if await deny_if_unauthorized(message):
        return
    today = now_local().date()
    week_start = (today - timedelta(days=6)).strftime("%Y-%m-%d")
    async with async_session_maker() as db:
        st = await get_period_statistics(db, week_start, today.strftime("%Y-%m-%d"))
    await message.answer(
        _render_period_stats_text("Oxirgi 7 kunlik statistika", st),
        parse_mode="HTML",
        reply_markup=stats_menu_kb(),
    )


@router.callback_query(F.data == "stats:7")
async def cb_stats_7(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb):
        return
    today = now_local().date()
    week_start = (today - timedelta(days=6)).strftime("%Y-%m-%d")
    async with async_session_maker() as db:
        st = await get_period_statistics(db, week_start, today.strftime("%Y-%m-%d"))
    await cb.message.edit_text(
        _render_period_stats_text("Oxirgi 7 kunlik statistika", st),
        parse_mode="HTML",
        reply_markup=stats_menu_kb(),
    )
    await cb.answer()


@router.callback_query(F.data == "stats:month")
async def cb_stats_month(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb):
        return
    today = now_local().date()
    month_start = today.replace(day=1).strftime("%Y-%m-%d")
    async with async_session_maker() as db:
        st = await get_period_statistics(db, month_start, today.strftime("%Y-%m-%d"))
    await cb.message.edit_text(
        _render_period_stats_text("Joriy oylik statistika", st),
        parse_mode="HTML",
        reply_markup=stats_menu_kb(),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("sverka:month:"))
async def cb_sverka_month(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb):
        return
    which = cb.data.split(":")[-1]
    now_d = now_local().date()
    if which == "prev":
        prev_last = now_d.replace(day=1) - timedelta(days=1)
        month = prev_last.strftime("%Y-%m")
    else:
        month = now_d.strftime("%Y-%m")
    await cb.answer("⏳ Sverka tayyorlanmoqda...")
    await _send_sverka_report(cb.bot, cb.message, cb.from_user.id, month, None)


@router.message(Command("roles"), F.chat.type == "private")
async def cmd_roles(message: Message) -> None:
    """Open RBAC user role management menu (Y6)."""
    if await deny_if_unauthorized(message, ("admin",)):
        return
    async with async_session_maker() as db:
        roles = await list_user_roles(db)
    super_admins = get_settings().admin_id_list
    await message.answer(
        "👥 <b>Foydalanuvchi rollari:</b>\n"
        f"• Super-adminlar (.env): <code>{', '.join(str(x) for x in super_admins) or '-'}</code>\n\n"
        "👑 Admin — hamma amal | 💼 Kassir — qo'shish | 👁 Ko'ruvchi — faqat status:",
        parse_mode="HTML",
        reply_markup=roles_list_kb(roles, super_admins),
    )


@router.errors()
async def on_error(event: ErrorEvent, bot: Bot) -> bool:
    """Log full traceback and send concise alert to admins so silent failures are noticed."""
    logger.error("Unhandled error", exc_info=event.exception)
    tb = "".join(traceback.format_exception_only(type(event.exception), event.exception)).strip()
    for admin_id in get_settings().admin_id_list:
        try:
            await bot.send_message(
                admin_id,
                f"⚠️ Botda kutilmagan xato:\n<code>{html.escape(tb[:600])}</code>",
                parse_mode="HTML",
            )
        except Exception:
            pass
    return True
