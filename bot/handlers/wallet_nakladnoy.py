"""Daily cash wallet, Kassa debt, AI Nakladnoy photo/voice/text, Status, Edit confirmed, and Day Close handlers."""

from __future__ import annotations

import asyncio
import html
import io
import logging
import re
from typing import Optional

from aiogram import F, Router
from aiogram.fsm.context import FSMContext
from aiogram.types import CallbackQuery, InlineKeyboardButton, InlineKeyboardMarkup, Message

from bot.auth import can_write_role, deny_if_unauthorized, is_admin_role, is_authorized
from bot.handlers.settings_groups import get_bot_username
from bot.keyboards import (
    auto_confirmed_nakladnoy_kb,
    build_add_to_group_url,
    cancel_reply_keyboard,
    cash_tx_edit_kb,
    close_day_confirm_kb,
    confirmed_nakladnoy_edit_kb,
    debt_nakladnoys_list_kb,
    delete_confirm_kb,
    edit_items_list_kb,
    edit_supplier_pick_kb,
    kassa_debt_actions_kb,
    main_menu_keyboard,
    nakladnoy_confirm_kb,
    nakladnoy_quick_amount_kb,
    quick_amounts_kb,
    quick_suppliers_kb,
    status_actions_kb,
)
from bot.states import WalletStates
from database.crud import (
    SessionSummary,
    add_cash_transaction,
    close_cash_session,
    compute_session_summary,
    confirm_nakladnoy,
    create_pending_nakladnoy,
    delete_cash_transaction,
    delete_nakladnoy,
    find_duplicate_confirmed_nakladnoy,
    find_nakladnoy_by_photo_unique_id,
    format_local_dt,
    get_all_known_suppliers,
    get_app_setting,
    get_group_config,
    get_kassa_debt_stats,
    get_nakladnoy,
    get_nakladnoy_session_seq,
    get_or_create_open_session,
    get_recent_amounts_for_supplier,
    list_unpaid_debt_nakladnoys,
    mark_nakladnoy_as_debt,
    mark_nakladnoy_as_paid,
    record_ai_usage,
    resolve_supplier_name,
    round_nakladnoy_amount,
    set_nakladnoy_group_message,
    set_nakladnoy_payment_method,
    update_cash_transaction,
    update_nakladnoy,
)
from database.models import CashTransaction, NakladnoyPayment
from database.session import async_session_maker
from services.gemini_ai import (
    MAX_VOICE_SECONDS,
    VoiceTooLongError,
    extract_nakladnoy_from_image,
    format_uzs,
    parse_photo_caption,
    parse_uzbek_amount,
    parse_voice_or_text,
)
from services.scheduler import maybe_warn_ai_limit


router = Router(name="wallet_nakladnoy")
logger = logging.getLogger("hisobot_bot.wallet")


async def _safe_edit_text(message: Message, text: str, reply_markup=None) -> None:
    """Edit message cleanly, ignoring Telegram 'message is not modified' noise."""
    try:
        await message.edit_text(text, parse_mode="HTML", reply_markup=reply_markup)
    except Exception as exc:
        if "message is not modified" not in str(exc).lower():
            logger.debug("edit_text fallback: %s", exc)


def render_status_text(summary: SessionSummary) -> str:
    """Format full live daily cash, kassa movements, nakladnoy list with times, and statistics."""
    lines = [
        f"📊 <b>KUNLIK HISOB-KITOB ({summary.session.report_date})</b>",
        "===============================",
        f"⏮ Kechadan qoldiq: <b>{format_uzs(summary.opening_balance)}</b>",
        f"➕ Olingan pul: <b>{format_uzs(summary.main_cash_in)}</b>",
        f"🏦 Kassadan olingan: <b>{format_uzs(summary.kassa_debt_today)}</b>",
        f"↩️ Kassaga berilgan (qaytarilgan): <b>{format_uzs(summary.kassa_repay_today)}</b>",
        f"💵 Jami kirim (Qo'ldagi jami): <b>{format_uzs(summary.total_available_inflow)}</b>",
    ]
    if summary.cash_transactions:
        t_icons = {"main": "➕", "kassa_debt": "🏦", "kassa_repay": "↩️"}
        for tx in summary.cash_transactions:
            tm = format_local_dt(tx.created_at, "%H:%M")
            sign = "-" if tx.source_type == "kassa_repay" else ""
            lines.append(
                f"  • <code>{tm}</code> {t_icons.get(tx.source_type, '💵')} {sign}{format_uzs(tx.amount)}"
            )

    lines.append("===============================")
    lines.append(f"📋 <b>Berilgan pullar ({len(summary.confirmed_nakladnoys)} ta):</b>")

    if not summary.confirmed_nakladnoys:
        lines.append("<i>Hozircha nakladnoy to'lovlari yo'q (0)</i>")
    else:
        for idx, n in enumerate(summary.confirmed_nakladnoys, start=1):
            tm = format_local_dt(n.created_at, "%H:%M")
            where = "" if n.group_message_id else " 💾"
            lines.append(
                f"{idx}) {html.escape(n.supplier_name)} — <b>{format_uzs(n.amount)}</b> <i>({tm})</i>{where}"
            )

    if summary.noncash_nakladnoys:
        lines.append("-------------------------------")
        lines.append(
            f"💳🏦 <b>Karta / Perechesleniya ({len(summary.noncash_nakladnoys)} ta — naqd puldan ayrilmagan):</b>"
        )
        for idx, n in enumerate(summary.noncash_nakladnoys, start=1):
            tm = format_local_dt(n.created_at, "%H:%M")
            pm = (getattr(n, "payment_method", "cash") or "cash").lower()
            pm_icon = "💳" if pm == "card" else "🏦"
            where = "" if n.group_message_id else " 💾"
            lines.append(
                f"{idx}) {pm_icon} {html.escape(n.supplier_name)} — <b>{format_uzs(n.amount)}</b> <i>({tm})</i>{where}"
            )
        if summary.total_card_spent > 0:
            lines.append(f"• Karta jami: <b>{format_uzs(summary.total_card_spent)} so'm</b>")
        if summary.total_transfer_spent > 0:
            lines.append(f"• Perechesleniya jami: <b>{format_uzs(summary.total_transfer_spent)} so'm</b>")

    if summary.debt_nakladnoys:
        lines.append("-------------------------------")
        lines.append(
            f"📌 <b>Qarzga olingan ({len(summary.debt_nakladnoys)} ta — qo'ldagi puldan ayrilmagan):</b>"
        )
        for idx, n in enumerate(summary.debt_nakladnoys, start=1):
            tm = format_local_dt(n.created_at, "%H:%M")
            lines.append(
                f"{idx}) 📌 {html.escape(n.supplier_name)} — <b>{format_uzs(n.amount)}</b> <i>({tm})</i>"
            )
        lines.append(f"• Bugungi qarz jami: <b>{format_uzs(summary.total_debt_nakladnoy)} so'm</b>")

    lines.append("===============================")
    lines.append(f"➖ Jami rasxod (Nakladnoy): <b>{format_uzs(summary.total_nakladnoy_spent)}</b>")
    lines.append(f"💰 <b>Qo'lda qolishi kerak: {format_uzs(summary.expected_cash)} so'm</b>")

    count = len(summary.confirmed_nakladnoys)
    spend_pct = (
        (summary.total_nakladnoy_spent / summary.total_available_inflow * 100)
        if summary.total_available_inflow > 0
        else 0.0
    )
    avg_amt = (summary.total_nakladnoy_spent / count) if count > 0 else 0.0
    in_group_cnt = sum(1 for n in summary.confirmed_nakladnoys if n.group_message_id)
    db_only_cnt = count - in_group_cnt
    top_payment = max(summary.confirmed_nakladnoys, key=lambda n: n.amount, default=None)

    lines.append("\n📈 <b>Statistika:</b>")
    lines.append(f"• Sarflanish: <b>{spend_pct:.1f}%</b> ({count} ta naqd to'lov)")
    if count > 0:
        lines.append(f"• O'rtacha to'lov: <b>{format_uzs(avg_amt)} so'm</b>")
    if top_payment is not None:
        lines.append(
            f"• Eng katta to'lov: <b>{html.escape(top_payment.supplier_name)}</b> — {format_uzs(top_payment.amount)}"
        )
    if count > 0:
        lines.append(f"• Guruhda / Shaxsiy bazada: 📤 {in_group_cnt} ta | 💾 {db_only_cnt} ta")
    if summary.total_card_spent > 0:
        lines.append(f"• Karta orqali: <b>{format_uzs(summary.total_card_spent)} so'm</b>")
    if summary.total_transfer_spent > 0:
        lines.append(f"• Perechesleniya orqali: <b>{format_uzs(summary.total_transfer_spent)} so'm</b>")
    if summary.noncash_nakladnoys:
        all_paid_total = summary.total_nakladnoy_spent + summary.total_card_spent + summary.total_transfer_spent
        lines.append(f"• Barcha to'lovlar jami: <b>{format_uzs(all_paid_total)} so'm</b>")
    lines.append(f"• Kassa qarzi qoldig'i: <b>{format_uzs(summary.total_kassa_debt_outstanding)} so'm</b>")
    if summary.all_unpaid_debt_count > 0:
        lines.append(
            f"• To'lanmagan nakladnoy qarzlari: <b>{summary.all_unpaid_debt_count} ta — {format_uzs(summary.all_unpaid_debt_total)} so'm</b>"
        )

    result = "\n".join(lines)
    if len(result) > 4000:
        result = result[:3940] + "\n<i>...(to'liq ro'yxat Excel'da)</i>"
    return result


def _nakladnoy_num_label(payment_id: int, session_seq: Optional[int] = None) -> str:
    """Format nakladnoy identifier as '#ID / N' within a daily session (or '#ID' fallback)."""
    return f"#{payment_id} / {session_seq}" if session_seq else f"#{payment_id}"


def render_nakladnoy_group_caption(
    payment: NakladnoyPayment, tag: str = "", session_seq: Optional[int] = None
) -> str:
    """Build caption/message sent to the Nakladnoy Telegram group."""
    ts = format_local_dt(payment.created_at, "%d.%m.%Y %H:%M")
    num_lbl = _nakladnoy_num_label(payment.id, session_seq)
    if payment.status == "deleted":
        return (
            f"❌ <b>[O'CHIRILDI / BEKOR QILINDI]</b>\n"
            f"📸 Nakladnoy {num_lbl}\n"
            f"🏢 Postavshik: <s>{html.escape(payment.supplier_name)}</s>\n"
            f"💰 Summa: <s>{format_uzs(payment.amount)} so'm</s>"
        )
    if getattr(payment, "is_debt", False):
        return (
            f"📌 <b>[QARZGA — PUL BERILMADI]</b>\n"
            f"📸 <b>Nakladnoy {num_lbl}</b>\n"
            f"🏢 Postavshik: <b>{html.escape(payment.supplier_name)}</b>\n"
            f"💰 Summa: <b>{format_uzs(payment.amount)} so'm</b>\n"
            f"📌 Holat: <b>QARZGA (to'lanmagan)</b>\n"
            f"📅 Vaqt: {ts}"
        )
    pm = (getattr(payment, "payment_method", "cash") or "cash").strip().lower()
    if getattr(payment, "paid_at", None) is not None and tag.startswith("✅ [QARZ TO'LANDI"):
        paid_ts = format_local_dt(payment.paid_at, "%d.%m.%Y %H:%M")
        if pm == "card":
            paid_head = "✅ <b>[QARZ TO'LANDI — KARTA]</b>"
            paid_state = f"💳 Holat: <b>KARTA ORQALI TO'LANDI ({paid_ts})</b>"
        elif pm == "transfer":
            paid_head = "✅ <b>[QARZ TO'LANDI — O'TKAZMA]</b>"
            paid_state = f"🏦 Holat: <b>PERECHESLENIYA BILAN TO'LANDI ({paid_ts})</b>"
        else:
            paid_head = "✅ <b>[QARZ TO'LANDI]</b>"
            paid_state = f"✅ Holat: <b>TO'LANDI ({paid_ts})</b>"
        return (
            f"{paid_head}\n"
            f"📸 <b>Nakladnoy {num_lbl}</b>\n"
            f"🏢 Postavshik: <b>{html.escape(payment.supplier_name)}</b>\n"
            f"💰 Summa: <b>{format_uzs(payment.amount)} so'm</b>\n"
            f"{paid_state}\n"
            f"📅 Vaqt: {ts}"
        )

    if tag:
        header_tag = f"{tag}\n"
    elif pm == "card":
        header_tag = "💳 <b>[KARTA ORQALI TO'LANDI]</b>\n"
    elif pm == "transfer":
        header_tag = "🏦 <b>[PERECHESLENIYA / O'TKAZMA]</b>\n"
    else:
        header_tag = ""

    pm_line = (
        "\n💳 To'lov turi: <b>Karta (naqdsiz)</b>"
        if pm == "card"
        else ("\n🏦 To'lov turi: <b>Perechesleniya (o'tkazma)</b>" if pm == "transfer" else "")
    )
    return (
        f"{header_tag}📸 <b>Nakladnoy {num_lbl}</b>\n"
        f"🏢 Postavshik: <b>{html.escape(payment.supplier_name)}</b>\n"
        f"💰 Summa: <b>{format_uzs(payment.amount)} so'm</b>"
        f"{pm_line}\n"
        f"📅 Vaqt: {ts}"
    )


_BG_TASKS: set[asyncio.Task] = set()
_PENDING_GROUP_SYNCS: dict[int, asyncio.Task] = {}


async def _safe_cb_answer(
    cb: CallbackQuery, text: Optional[str] = None, show_alert: bool = False
) -> None:
    """Answer Telegram callback query safely, ignoring stale query errors."""
    try:
        await cb.answer(text, show_alert=show_alert)
    except Exception as exc:
        msg_l = str(exc).lower()
        if "query is too old" not in msg_l and "query id is invalid" not in msg_l:
            logger.debug("cb.answer ignored: %s", exc)


async def _sync_nakladnoy_group_message(
    bot,
    payment: NakladnoyPayment,
    tag: str = "✏️ [TAHRIRLANDI]",
    session_seq: Optional[int] = None,
) -> tuple[bool, str]:
    """Update existing message in the Nakladnoy group if a confirmed payment was edited or deleted."""
    if not payment.group_chat_id or not payment.group_message_id:
        return False, "<i>(Bu nakladnoy hali guruhga yuborilmagan)</i>"
    if session_seq is None and payment.status == "confirmed":
        async with async_session_maker() as db:
            session_seq = await get_nakladnoy_session_seq(db, payment)
    new_caption = render_nakladnoy_group_caption(payment, tag=tag, session_seq=session_seq)
    try:
        if payment.photo_file_id:
            await bot.edit_message_caption(
                chat_id=payment.group_chat_id,
                message_id=payment.group_message_id,
                caption=new_caption,
                parse_mode="HTML",
            )
        else:
            await bot.edit_message_text(
                chat_id=payment.group_chat_id,
                message_id=payment.group_message_id,
                text=new_caption,
                parse_mode="HTML",
            )
        return True, "📤 <b>Guruhdagi xabar ham avtomatik yangilandi!</b>"
    except Exception as exc:
        if "message is not modified" in str(exc).lower():
            return True, "📤 Guruhdagi xabar dolzarb holatda."
        logger.warning(
            "Failed to edit group message payment_id=%s chat_id=%s msg_id=%s: %s",
            payment.id,
            payment.group_chat_id,
            payment.group_message_id,
            exc,
        )
        return False, "⚠️ Guruhdagi xabarni tahrirlab bo'lmadi."


def _schedule_group_sync(
    bot,
    payment: NakladnoyPayment,
    tag: str = "✏️ [TAHRIRLANDI]",
    delay: float = 0.0,
) -> str:
    """Coalesce and schedule background group sync so UI button clicks return immediately."""
    if not payment.group_chat_id or not payment.group_message_id:
        return "<i>(Bu nakladnoy hali guruhga yuborilmagan)</i>"
    pid = payment.id
    prev = _PENDING_GROUP_SYNCS.pop(pid, None)
    if prev is not None and not prev.done():
        prev.cancel()

    async def _runner() -> None:
        cur = asyncio.current_task()
        try:
            if delay > 0:
                await asyncio.sleep(delay)
            async with async_session_maker() as db:
                fresh = await get_nakladnoy(db, pid)
                if not fresh or not fresh.group_chat_id or not fresh.group_message_id:
                    return
                seq = await get_nakladnoy_session_seq(db, fresh) if fresh.status == "confirmed" else None
            await _sync_nakladnoy_group_message(bot, fresh, tag=tag, session_seq=seq)
        except asyncio.CancelledError:
            return
        except Exception as exc:
            logger.warning("Background group sync error payment_id=%s: %s", pid, exc)
        finally:
            if cur is not None and _PENDING_GROUP_SYNCS.get(pid) is cur:
                _PENDING_GROUP_SYNCS.pop(pid, None)

    task = asyncio.create_task(_runner())
    _PENDING_GROUP_SYNCS[pid] = task
    _BG_TASKS.add(task)
    task.add_done_callback(_BG_TASKS.discard)
    return "📤 <b>Guruhdagi xabar ham avtomatik yangilanmoqda!</b>"


def _pending_card_text(
    payment: NakladnoyPayment,
    duplicate_warning: Optional[NakladnoyPayment] = None,
    suggested_supplier: Optional[str] = None,
) -> str:
    warn_text = ""
    if duplicate_warning is not None:
        warn_text = (
            f"\n\n⚠️ <b>DIQQAT (Dublikat ehtimoli):</b> Avvalroq #{duplicate_warning.id} — "
            f"<b>{html.escape(duplicate_warning.supplier_name)}</b> "
            f"(<b>{format_uzs(duplicate_warning.amount)} so'm</b>) saqlangan!"
        )
    sug_text = ""
    if suggested_supplier:
        sug_text = f"\n💡 Balki: <b>«{html.escape(suggested_supplier)}»</b> mi?"
    orig_text = ""
    if payment.original_amount is not None and round(payment.original_amount) != round(payment.amount):
        orig_text = f"\n🔄 Asl summa: <i>{format_uzs(payment.original_amount)} so'm</i>"
    note_text = f"\n📝 Izoh: <i>{html.escape(payment.note)}</i>" if payment.note else ""
    return (
        f"🧾 <b>Nakladnoy tasdiqlash (#{payment.id})</b>\n"
        f"🏢 Postavshik: <b>{html.escape(payment.supplier_name or 'Noma\'lum')}</b>"
        f"{sug_text}\n"
        f"💰 Summa: <b>{format_uzs(payment.amount)} so'm</b>"
        f"{orig_text}{note_text}{warn_text}\n\n"
        "Hammasi to'g'rimi?"
    )


async def _send_pending_nakladnoy_card(
    target_message: Message,
    payment: NakladnoyPayment,
    duplicate_warning: Optional[NakladnoyPayment] = None,
    suggested_supplier: Optional[str] = None,
) -> None:
    """Render pending nakladnoy confirmation card."""
    await target_message.answer(
        _pending_card_text(payment, duplicate_warning=duplicate_warning, suggested_supplier=suggested_supplier),
        parse_mode="HTML",
        reply_markup=nakladnoy_confirm_kb(payment.id, suggested_supplier=suggested_supplier),
    )


async def _download_voice_bytes(message: Message) -> tuple[bytes, str]:
    """Download voice or audio file bytes from Telegram, enforcing MAX_VOICE_SECONDS."""
    file_obj = message.voice or message.audio
    dur = getattr(file_obj, "duration", 0) or 0
    if dur > MAX_VOICE_SECONDS:
        raise VoiceTooLongError(f"Voice duration {dur}s > {MAX_VOICE_SECONDS}s")
    mime = "audio/ogg" if message.voice else (file_obj.mime_type or "audio/mpeg")
    buf = io.BytesIO()
    await message.bot.download(file_obj, destination=buf)
    return buf.getvalue(), mime


# ---------------------------------------------------------------------------
# Entry helpers called from navigation.py & settings_groups.py (more:* menu)
# ---------------------------------------------------------------------------


async def handle_status_button(
    message: Message, state: FSMContext, actor_id: Optional[int] = None
) -> None:
    uid = actor_id if actor_id is not None else (message.from_user.id if message.from_user else None)
    if not is_authorized(uid):
        return
    await state.clear()
    async with async_session_maker() as db:
        summary = await compute_session_summary(db)
    await message.answer(
        render_status_text(summary),
        parse_mode="HTML",
        reply_markup=status_actions_kb(
            summary.session.id, unpaid_debt_count=summary.all_unpaid_debt_count
        ),
    )


async def handle_cash_in_button(
    message: Message, state: FSMContext, actor_id: Optional[int] = None
) -> None:
    uid = actor_id if actor_id is not None else (message.from_user.id if message.from_user else None)
    if not can_write_role(uid):
        await message.answer("🔒 Bu amal faqat admin/kassir uchun.")
        return
    await state.set_state(WalletStates.waiting_cash_in_amount)
    await message.answer(
        "➕ <b>Qancha pul oldingiz?</b>\n"
        "Summani yozing yoki 🎤 ovozli xabar yuboring (masalan: <code>21 000 000</code> yoki <i>«21 million»</i>):",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )


@router.message(WalletStates.waiting_cash_in_amount, F.chat.type == "private")
async def process_cash_in_input(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message, ("admin", "kassir")):
        return

    amount: Optional[float] = None
    note = ""
    if message.voice or message.audio:
        try:
            audio_bytes, mime = await _download_voice_bytes(message)
        except VoiceTooLongError:
            await message.answer(
                f"⚠️ Ovozli xabar {MAX_VOICE_SECONDS} soniyadan oshmasligi kerak. Qisqaroq ayting yoki matnda yozing:"
            )
            return
        parsed = await parse_voice_or_text(audio_bytes=audio_bytes, mime_type=mime)
        await maybe_warn_ai_limit(message.bot)
        if parsed.get("error_code") in ("rate_limit", "api_error"):
            await message.answer("⏳ Ovozli xabarni o'qib bo'lmadi. Iltimos summani raqamda yozing:")
            return
        amount = parsed.get("amount")
        note = parsed.get("transcript", "")
    elif message.text:
        amount = parse_uzbek_amount(message.text)
        note = message.text.strip()

    if not amount or amount <= 0:
        await message.answer("⚠️ Summa tushunilmadi. Iltimos, raqamda yozing (masalan: `21 000 000`):")
        return

    async with async_session_maker() as db:
        await add_cash_transaction(db, amount=amount, source_type="main", note=note)
        summary = await compute_session_summary(db)

    await state.clear()
    await message.answer(
        f"✅ Asosiy balansga <b>+{format_uzs(amount)} so'm</b> qo'shildi!\n"
        f"💰 Hozir qo'lda qolishi kerak: <b>{format_uzs(summary.expected_cash)} so'm</b>",
        parse_mode="HTML",
        reply_markup=main_menu_keyboard(),
    )


async def handle_kassa_debt_button(
    message: Message, state: FSMContext, actor_id: Optional[int] = None
) -> None:
    uid = actor_id if actor_id is not None else (message.from_user.id if message.from_user else None)
    if not is_authorized(uid):
        return
    await state.clear()
    async with async_session_maker() as db:
        stats = await get_kassa_debt_stats(db, limit=10)
        summary = await compute_session_summary(db)

    lines = [
        "🏦 <b>Kassadan Olingan va Berilgan Pul Statistikasi</b>",
        "===============================",
        f"📥 Bugun kassadan olingan: <b>{format_uzs(summary.kassa_debt_today)} so'm</b>",
        f"📤 Bugun kassaga berilgan: <b>{format_uzs(summary.kassa_repay_today)} so'm</b>",
        "-------------------------------",
        f"📥 Jami kassadan olingan: <b>{format_uzs(stats['total_borrowed'])} so'm</b>",
        f"📤 Jami kassaga berilgan: <b>{format_uzs(stats['total_repaid'])} so'm</b>",
        f"⚠️ <b>Hozirgi kassa qarzi qoldig'i: {format_uzs(stats['outstanding'])} so'm</b>",
    ]
    recent = stats["recent_txs"]
    if recent:
        lines.append("\n📜 <b>Oxirgi kassa harakatlari:</b>")
        for tx in recent:
            dt_str = format_local_dt(tx.created_at, "%d.%m %H:%M")
            lbl = "🏦 Olingan" if tx.source_type == "kassa_debt" else "↩️ Berilgan"
            lines.append(f"• <code>{dt_str}</code> {lbl}: <b>{format_uzs(tx.amount)}</b>")

    lines.append(
        "\n💡 <i>Maslahat: Matnda «Kassadan 3 million oldim» yoki «Kassaga 3 million qaytardim» deb ham yozishingiz mumkin.</i>"
    )
    await message.answer(
        "\n".join(lines),
        parse_mode="HTML",
        reply_markup=kassa_debt_actions_kb() if can_write_role(uid) else None,
    )


@router.callback_query(F.data == "kassa:borrow")
async def cb_kassa_borrow(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin", "kassir")):
        return
    await state.set_state(WalletStates.waiting_kassa_debt_amount)
    await cb.message.answer(
        "🏦 <b>Kassadan qancha pul oldingiz?</b>\nSummani yozing yoki ovozda ayting:",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.callback_query(F.data == "kassa:repay")
async def cb_kassa_repay(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin", "kassir")):
        return
    await state.set_state(WalletStates.waiting_kassa_repay_amount)
    await cb.message.answer(
        "↩️ <b>Kassaga qancha qarz qaytardingiz?</b>\nSummani yozing yoki ovozda ayting:",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.message(WalletStates.waiting_kassa_debt_amount, F.chat.type == "private")
async def process_kassa_debt_input(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message, ("admin", "kassir")):
        return
    amount = None
    note = ""
    if message.voice or message.audio:
        try:
            audio_bytes, mime = await _download_voice_bytes(message)
        except VoiceTooLongError:
            await message.answer(f"⚠️ Ovozli xabar {MAX_VOICE_SECONDS} soniyadan oshmasligi kerak.")
            return
        parsed = await parse_voice_or_text(audio_bytes=audio_bytes, mime_type=mime)
        await maybe_warn_ai_limit(message.bot)
        amount = parsed.get("amount")
        note = parsed.get("transcript", "")
    elif message.text:
        amount = parse_uzbek_amount(message.text)
        note = message.text.strip()

    if not amount or amount <= 0:
        await message.answer("⚠️ Summa topilmadi. Qayta kiriting:")
        return

    async with async_session_maker() as db:
        await add_cash_transaction(db, amount=amount, source_type="kassa_debt", note=note)
        summary = await compute_session_summary(db)

    await state.clear()
    await message.answer(
        f"🏦 Kassadan <b>+{format_uzs(amount)} so'm</b> olindi (Qarzga yozildi).\n"
        f"⚠️ Jami kassa qarzi: <b>{format_uzs(summary.total_kassa_debt_outstanding)} so'm</b>\n"
        f"💰 Qo'lda qolishi kerak: <b>{format_uzs(summary.expected_cash)} so'm</b>",
        parse_mode="HTML",
        reply_markup=main_menu_keyboard(),
    )


@router.message(WalletStates.waiting_kassa_repay_amount, F.chat.type == "private")
async def process_kassa_repay_input(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message, ("admin", "kassir")):
        return
    amount = None
    note = ""
    if message.voice or message.audio:
        try:
            audio_bytes, mime = await _download_voice_bytes(message)
        except VoiceTooLongError:
            await message.answer(f"⚠️ Ovozli xabar {MAX_VOICE_SECONDS} soniyadan oshmasligi kerak.")
            return
        parsed = await parse_voice_or_text(audio_bytes=audio_bytes, mime_type=mime)
        await maybe_warn_ai_limit(message.bot)
        amount = parsed.get("amount")
        note = parsed.get("transcript", "")
    elif message.text:
        amount = parse_uzbek_amount(message.text)
        note = message.text.strip()

    if not amount or amount <= 0:
        await message.answer("⚠️ Summa topilmadi. Qayta kiriting:")
        return

    async with async_session_maker() as db:
        await add_cash_transaction(db, amount=amount, source_type="kassa_repay", note=note)
        summary = await compute_session_summary(db)

    await state.clear()
    await message.answer(
        f"↩️ Kassaga <b>{format_uzs(amount)} so'm</b> qaytarildi!\n"
        f"⚠️ Qolgan kassa qarzi: <b>{format_uzs(summary.total_kassa_debt_outstanding)} so'm</b>\n"
        f"💰 Qo'lda qolishi kerak: <b>{format_uzs(summary.expected_cash)} so'm</b>",
        parse_mode="HTML",
        reply_markup=main_menu_keyboard(),
    )


# ---------------------------------------------------------------------------
# Add Nakladnoy (Photo / Voice / Text / Recent Supplier Quick Pick)
# ---------------------------------------------------------------------------


@router.callback_query(F.data == "noop")
async def cb_noop(cb: CallbackQuery) -> None:
    """Acknowledge informational pagination counter buttons."""
    await cb.answer()


async def handle_add_nakladnoy_btn(
    message: Message, state: FSMContext, actor_id: Optional[int] = None
) -> None:
    uid = actor_id if actor_id is not None else (message.from_user.id if message.from_user else None)
    if not can_write_role(uid):
        await message.answer("🔒 Bu amal faqat admin/kassir uchun.")
        return

    async with async_session_maker() as db:
        suppliers = await get_all_known_suppliers(db)

    await state.set_state(WalletStates.waiting_nakladnoy_input)
    await state.update_data(quick_suppliers=suppliers)
    prompt = (
        "📸 <b>Nakladnoy rasmini tashlang</b>\n"
        "<i>(Postavshik nomi rasmda bo'lmasa yoki xato bo'lsa, rasm tagiga nomini yozib tashlang — bot o'sha nomni oladi.)</i>\n\n"
        "Yoki matn/ovozda yozing: <i>«Non Oka 1 657 000»</i>\n"
        + (f"👇 Yoki postavshiklardan birini tanlang (jami <b>{len(suppliers)}</b> ta):" if suppliers else "")
    )
    await message.answer(
        prompt,
        parse_mode="HTML",
        reply_markup=quick_suppliers_kb(suppliers, page=0) if suppliers else cancel_reply_keyboard(),
    )


@router.callback_query(F.data == "qsup:cancel")
async def cb_quick_supplier_cancel(cb: CallbackQuery, state: FSMContext) -> None:
    await state.clear()
    await _safe_edit_text(cb.message, "❌ Amal bekor qilindi.")
    await cb.answer("Bekor qilindi")


@router.callback_query(F.data.startswith("qsup:page:"))
async def cb_quick_supplier_page(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin", "kassir")):
        return
    page_str = cb.data.split(":")[-1]
    if not page_str.lstrip("-").isdigit():
        await cb.answer()
        return
    page = int(page_str)
    suppliers = (await state.get_data()).get("quick_suppliers")
    if not suppliers:
        async with async_session_maker() as db:
            suppliers = await get_all_known_suppliers(db)
        await state.update_data(quick_suppliers=suppliers)
    async def _update_markup() -> None:
        try:
            await cb.message.edit_reply_markup(
                reply_markup=quick_suppliers_kb(suppliers, page=page)
            )
        except Exception as exc:
            if "message is not modified" not in str(exc).lower():
                logger.debug("qsup page markup fallback: %s", exc)

    await asyncio.gather(_update_markup(), _safe_cb_answer(cb))


@router.callback_query(F.data.startswith("qsup:"))
async def cb_quick_supplier_pick(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin", "kassir")):
        return
    idx_str = cb.data.split(":", maxsplit=1)[1]
    if not idx_str.isdigit():
        return
    idx = int(idx_str)
    data = await state.get_data()
    recents = data.get("quick_suppliers") or []
    if not recents:
        async with async_session_maker() as db:
            recents = await get_all_known_suppliers(db)
        await state.update_data(quick_suppliers=recents)
    if idx >= len(recents):
        await cb.answer("Ro'yxat eskirgan, qaytadan oching", show_alert=True)
        return
    sup_name = recents[idx]
    async with async_session_maker() as db:
        amounts = await get_recent_amounts_for_supplier(db, sup_name, limit=3)

    await state.set_state(WalletStates.waiting_quick_nakladnoy_amount)
    await state.update_data(selected_supplier=sup_name, quick_amounts=amounts)
    hint = "\n👇 Yoki oxirgi summalardan birini bosing:" if amounts else ""
    await _safe_edit_text(
        cb.message,
        f"🏢 Postavshik: <b>{html.escape(sup_name)}</b>\n"
        f"💰 Summani yozing (masalan: <code>354 000</code>):{hint}",
        reply_markup=quick_amounts_kb(amounts),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("qamt:"))
async def cb_quick_amount_pick(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin", "kassir")):
        return
    idx = int(cb.data.split(":", maxsplit=1)[1])
    data = await state.get_data()
    sup = data.get("selected_supplier")
    amts = data.get("quick_amounts") or []
    if not sup or idx >= len(amts):
        await cb.answer("Ma'lumot topilmadi", show_alert=True)
        return
    amt = float(amts[idx])
    try:
        await cb.message.delete()
    except Exception:
        pass
    await _process_ready_nakladnoy(
        message=cb.message,
        state=state,
        supplier_name=sup,
        raw_amount=amt,
        photo_file_id=None,
        notes="",
        is_confident=True,
        actor_id=cb.from_user.id,
    )
    await cb.answer("✅ Tanlandi!")


@router.message(WalletStates.waiting_quick_nakladnoy_amount, F.chat.type == "private")
async def process_quick_nakladnoy_amount(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message, ("admin", "kassir")):
        return
    data = await state.get_data()
    sup = data.get("selected_supplier")
    if not sup:
        await state.clear()
        if message.photo:
            await _process_nakladnoy_photo(message, state)
        else:
            await handle_any_text(message, state)
        return

    if message.photo:
        await _process_nakladnoy_photo(message, state, override_supplier=sup)
        return

    amt: Optional[float] = None
    note = ""
    if message.voice or message.audio:
        try:
            audio_bytes, mime = await _download_voice_bytes(message)
        except VoiceTooLongError:
            await message.answer(f"⚠️ Ovozli xabar {MAX_VOICE_SECONDS} soniyadan oshmasligi kerak.")
            return
        parsed = await parse_voice_or_text(audio_bytes=audio_bytes, mime_type=mime)
        await maybe_warn_ai_limit(message.bot)
        amt = parsed.get("amount")
        note = parsed.get("transcript", "")
    elif message.text:
        amt = parse_uzbek_amount(message.text)

    if not amt or amt <= 0:
        await message.answer("⚠️ Summa tushunilmadi. Raqam kiriting (masalan: `354 000`):")
        return

    await _process_ready_nakladnoy(
        message=message,
        state=state,
        supplier_name=sup,
        raw_amount=float(amt),
        photo_file_id=None,
        notes=note,
        is_confident=True,
    )


async def _post_payment_to_group(
    bot, payment: NakladnoyPayment, nak_group, session_seq: Optional[int] = None
) -> tuple[bool, str]:
    """Send a confirmed nakladnoy payment to the bound Nakladnoy group and save message ID."""
    if session_seq is None and payment.status == "confirmed":
        async with async_session_maker() as db:
            session_seq = await get_nakladnoy_session_seq(db, payment)
    caption = render_nakladnoy_group_caption(payment, session_seq=session_seq)
    try:
        if payment.photo_file_id:
            sent = await bot.send_photo(
                chat_id=nak_group.chat_id,
                photo=payment.photo_file_id,
                caption=caption,
                parse_mode="HTML",
            )
        else:
            sent = await bot.send_message(
                chat_id=nak_group.chat_id,
                text=caption,
                parse_mode="HTML",
            )
        async with async_session_maker() as db:
            await set_nakladnoy_group_message(db, payment.id, nak_group.chat_id, sent.message_id)
        return True, f"📤 <b>{html.escape(nak_group.title)}</b> guruhiga yuborildi!"
    except Exception:
        return False, "⚠️ Guruhga yuborib bo'lmadi (bot guruhda admin ekanini tekshiring)."


def _format_balance_summary_block(summary: SessionSummary) -> str:
    """Compact balance breakdown shown in confirmation and done messages."""
    lines = [
        "📊 <b>Sizda natija shu:</b>",
        f"💵 Jami pul (kirim): <b>{format_uzs(summary.total_available_inflow)} so'm</b>",
        f"➖ Jami rasxod ({len(summary.confirmed_nakladnoys)} ta): <b>{format_uzs(summary.total_nakladnoy_spent)} so'm</b>",
    ]
    if summary.total_card_spent > 0:
        lines.append(f"💳 Karta (naqdsiz): <b>{format_uzs(summary.total_card_spent)} so'm</b>")
    if summary.total_transfer_spent > 0:
        lines.append(f"🏦 Perechesleniya (naqdsiz): <b>{format_uzs(summary.total_transfer_spent)} so'm</b>")
    lines.append(f"💰 <b>Qo'lda qolgani: {format_uzs(summary.expected_cash)} so'm</b>")
    return "\n".join(lines)


async def _process_ready_nakladnoy(
    message: Message,
    state: FSMContext,
    supplier_name: str,
    raw_amount: float,
    photo_file_id: Optional[str],
    notes: str,
    is_confident: bool,
    prefix_html: str = "",
    photo_unique_id: Optional[str] = None,
    actor_id: Optional[int] = None,
) -> None:
    """Normalize supplier, round amount, check duplicates, and auto-confirm or show card."""
    prev_state = await state.get_state()
    used_cancel_reply_kb = prev_state in (
        WalletStates.waiting_nakladnoy_clarify.state,
        WalletStates.waiting_edit_nakladnoy_amount.state,
        WalletStates.waiting_edit_nakladnoy_supplier.state,
    )
    uid = actor_id if actor_id is not None else (message.from_user.id if message.from_user else None)

    async with async_session_maker() as db:
        auto_confirm = (await get_app_setting(db, "auto_confirm", "on")) == "on"
        round_mode = await get_app_setting(db, "round_mode", "floor_1000")
        rounded_amt = round_nakladnoy_amount(raw_amount, round_mode)
        orig_amt = float(raw_amount) if round(rounded_amt) != round(raw_amount) else None

        canonical_sup, suggested_sup = await resolve_supplier_name(db, supplier_name)
        sess = await get_or_create_open_session(db)
        payment = await create_pending_nakladnoy(
            db,
            supplier_name=canonical_sup,
            amount=rounded_amt,
            photo_file_id=photo_file_id,
            photo_unique_id=photo_unique_id,
            original_amount=orig_amt,
            note=notes,
            session_id=sess.id,
        )
        dup = await find_duplicate_confirmed_nakladnoy(
            db, sess.id, canonical_sup, rounded_amt, exclude_id=payment.id
        )
        nak_group = await get_group_config(db, "nakladnoy")

        can_auto = auto_confirm and is_confident and dup is None and suggested_sup is None
        session_seq: Optional[int] = None
        summary: Optional[SessionSummary] = None
        if can_auto:
            payment = await confirm_nakladnoy(db, payment.id, user_id=uid)
            session_seq = await get_nakladnoy_session_seq(db, payment)
            if payment is not None:
                summary = await compute_session_summary(db, payment.session_id)

    await state.clear()

    if can_auto and payment is not None and summary is not None:
        posted = False
        if nak_group:
            posted, group_notice = await _post_payment_to_group(
                message.bot, payment, nak_group, session_seq=session_seq
            )
        else:
            group_notice = "<i>(Nakladnoy guruhi ulanmagan — faqat bazaga saqlandi)</i>"

        num_lbl = _nakladnoy_num_label(payment.id, session_seq)
        round_line = ""
        if orig_amt is not None:
            round_line = f"🔄 Yaxlitlandi: <i>{format_uzs(orig_amt)} → {format_uzs(payment.amount)}</i>\n"
        await message.answer(
            f"{prefix_html}"
            f"⚡ <b>Avto-tasdiqlandi! ({num_lbl})</b>\n"
            f"🏢 Postavshik: <b>{html.escape(payment.supplier_name)}</b>\n"
            f"💰 Summa: <b>{format_uzs(payment.amount)} so'm</b>\n"
            f"{round_line}"
            f"{group_notice}\n\n"
            f"{_format_balance_summary_block(summary)}",
            parse_mode="HTML",
            reply_markup=auto_confirmed_nakladnoy_kb(payment.id, sent_to_group=posted),
        )
        if used_cancel_reply_kb:
            await message.answer("📋 Asosiy menyu:", reply_markup=main_menu_keyboard())
        return

    await _send_pending_nakladnoy_card(
        message, payment, duplicate_warning=dup, suggested_supplier=suggested_sup
    )
    if used_cancel_reply_kb:
        await message.answer("👇 Tasdiqlang yoki tahrirlang:", reply_markup=main_menu_keyboard())


async def _process_nakladnoy_photo(
    message: Message, state: FSMContext, override_supplier: Optional[str] = None
) -> None:
    """Shared handler for nakladnoy photo processing via dedup cache + Gemini Vision."""
    full_photo = message.photo[-1]
    cap_sup, cap_amt = parse_photo_caption(message.caption)
    effective_sup = override_supplier or cap_sup

    # A6: Zero-token deduplication via Telegram file_unique_id before calling Gemini
    async with async_session_maker() as db:
        cached = await find_nakladnoy_by_photo_unique_id(db, full_photo.file_unique_id)
        if cached is not None:
            await record_ai_usage(db, kind="cache_hit", model_name="cache")
            sess = await get_or_create_open_session(db)
            dup_pending = await create_pending_nakladnoy(
                db,
                supplier_name=effective_sup or cached.supplier_name,
                amount=float(cap_amt) if cap_amt else float(cached.amount),
                original_amount=None if cap_amt else cached.original_amount,
                photo_file_id=full_photo.file_id,
                photo_unique_id=full_photo.file_unique_id,
                note=cached.note,
                session_id=sess.id,
            )
            await state.clear()
            await _send_pending_nakladnoy_card(message, dup_pending, duplicate_warning=cached)
            return

    # A2: Pick smallest photo variant >= 1000px to save bandwidth + AI tokens
    dl_photo = next(
        (p for p in message.photo if max(p.width, p.height) >= 1000),
        full_photo,
    )
    wait_msg = await message.answer("🔍 Nakladnoy rasmi o'qilmoqda...")
    buf = io.BytesIO()
    await message.bot.download(dl_photo, destination=buf)
    effective_caption = (
        f"{override_supplier} {message.caption or ''}".strip()
        if override_supplier
        else message.caption
    )
    extracted = await extract_nakladnoy_from_image(
        image_bytes=buf.getvalue(),
        mime_type="image/jpeg",
        caption=effective_caption,
    )
    await maybe_warn_ai_limit(message.bot)

    supplier_name = effective_sup or extracted.get("supplier_name") or ""
    amount = extracted.get("amount") or 0.0
    notes = extracted.get("notes") or ""
    is_clear = bool(extracted.get("is_clear"))
    err_code = extracted.get("error_code")

    try:
        await wait_msg.delete()
    except Exception:
        pass

    if supplier_name and amount > 0:
        await _process_ready_nakladnoy(
            message=message,
            state=state,
            supplier_name=supplier_name,
            raw_amount=float(amount),
            photo_file_id=full_photo.file_id,
            photo_unique_id=full_photo.file_unique_id,
            notes=notes,
            is_confident=is_clear,
        )
        return

    async with async_session_maker() as db:
        sess = await get_or_create_open_session(db)
        payment = await create_pending_nakladnoy(
            db,
            supplier_name=supplier_name,
            amount=float(amount),
            photo_file_id=full_photo.file_id,
            photo_unique_id=full_photo.file_unique_id,
            note=notes,
            session_id=sess.id,
        )

    await state.set_state(WalletStates.waiting_nakladnoy_clarify)
    await state.update_data(payment_id=payment.id)
    if err_code == "rate_limit":
        lead = "⏳ AI hozir band. Iltimos, ma'lumotni yozib yuboring"
    elif err_code in ("api_error", "no_key"):
        lead = "⚠️ Rasmni o'qib bo'lmadi. Iltimos, ma'lumotni yozib yuboring"
    else:
        missing_parts = []
        if not supplier_name:
            missing_parts.append("postavshik nomi")
        if not amount or amount <= 0:
            missing_parts.append("summa")
        lead = f"🤔 Rasmda <b>{', '.join(missing_parts)}</b> aniq o'qilmadi"

    await message.answer(
        f"{lead}.\n"
        f"Topilgani: Postavshik=<code>{html.escape(supplier_name or '?')}</code>, "
        f"Summa=<code>{format_uzs(amount) if amount else '?'}</code>\n\n"
        "🎤 Ovozli xabar yoki matn yuboring (masalan: <i>«Non Oka 1 657 000»</i>):",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )


@router.message(WalletStates.waiting_nakladnoy_clarify, F.chat.type == "private")
async def process_nakladnoy_clarification(message: Message, state: FSMContext) -> None:
    """Fill missing supplier_name / amount on a pending nakladnoy via voice or deterministic text."""
    if await deny_if_unauthorized(message, ("admin", "kassir")):
        return
    data = await state.get_data()
    payment_id = data.get("payment_id")
    if not payment_id:
        await state.clear()
        return

    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
    if not payment:
        await state.clear()
        return

    parsed_sup = None
    parsed_amt = None
    if message.voice or message.audio:
        try:
            audio_bytes, mime = await _download_voice_bytes(message)
        except VoiceTooLongError:
            await message.answer(f"⚠️ Ovozli xabar {MAX_VOICE_SECONDS} soniyadan oshmasligi kerak.")
            return
        res = await parse_voice_or_text(audio_bytes=audio_bytes, mime_type=mime)
        await maybe_warn_ai_limit(message.bot)
        parsed_sup = res.get("supplier_name")
        parsed_amt = res.get("amount")
        if not parsed_sup and res.get("transcript") and not payment.supplier_name:
            parsed_sup = res["transcript"]
    elif message.text:
        res = await parse_voice_or_text(text=message.text)
        parsed_amt = res.get("amount") or parse_uzbek_amount(message.text)
        parsed_sup = res.get("supplier_name")
        if not parsed_sup and not payment.supplier_name:
            stripped = re.sub(r"\d[\d\s.,+_]*", "", message.text).strip()
            if stripped and stripped.lower() not in ("mln", "ming", "million", "so'm"):
                parsed_sup = stripped

    new_sup = parsed_sup or payment.supplier_name
    new_amt = parsed_amt or payment.amount

    if not new_sup or not new_amt or new_amt <= 0:
        await message.answer(
            "⚠️ Ikkalasi ham aniq bo'lishi kerak (Postavshik va Summa). Qaytadan yozing yoki ovozda ayting:"
        )
        return

    async with async_session_maker() as db:
        canon, sug = await resolve_supplier_name(db, new_sup)
        round_mode = await get_app_setting(db, "round_mode", "floor_1000")
        rounded = round_nakladnoy_amount(float(new_amt), round_mode)
        orig = float(new_amt) if round(rounded) != round(float(new_amt)) else None
        updated = await update_nakladnoy(
            db, payment_id, supplier_name=canon, amount=rounded, original_amount=orig
        )
        dup = await find_duplicate_confirmed_nakladnoy(
            db, updated.session_id, updated.supplier_name, updated.amount, exclude_id=updated.id
        )

    await state.clear()
    await _send_pending_nakladnoy_card(
        message, updated, duplicate_warning=dup, suggested_supplier=sug
    )
    await message.answer("👇 Tasdiqlang:", reply_markup=main_menu_keyboard())


async def _finalize_nakladnoy_confirmation(
    cb: CallbackQuery,
    payment_id: int,
    send_to_group: bool,
    is_debt: bool = False,
    payment_method: str = "cash",
    state: Optional[FSMContext] = None,
) -> None:
    """Confirm a pending nakladnoy payment (cash/card/transfer or debt), optionally posting to group."""
    if await deny_if_unauthorized(cb, ("admin", "kassir")):
        return
    if state is not None:
        await state.clear()
    uid = cb.from_user.id if cb.from_user else None
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
        if not payment or payment.status == "deleted":
            await cb.answer("Nakladnoy topilmadi yoki o'chirilgan", show_alert=True)
            return
        if not payment.supplier_name or payment.amount <= 0:
            await cb.answer("Postavshik nomi va summa to'liq bo'lishi kerak!", show_alert=True)
            return
        nak_group = await get_group_config(db, "nakladnoy") if send_to_group else None
        payment = await confirm_nakladnoy(
            db,
            payment_id,
            user_id=uid,
            is_debt=is_debt,
            payment_method=payment_method,
        )
        session_seq = await get_nakladnoy_session_seq(db, payment)
        summary = await compute_session_summary(db, payment.session_id)

    num_lbl = _nakladnoy_num_label(payment.id, session_seq)
    pm = (getattr(payment, "payment_method", "cash") or "cash").strip().lower()
    if is_debt:
        toast = "📌 Qarzga saqlandi!"
    elif not send_to_group:
        toast = "✅ Saqlandi!"
    elif pm == "card":
        toast = "💳 Karta orqali saqlandi!"
    elif pm == "transfer":
        toast = "🏦 Perechesleniya saqlandi!"
    else:
        toast = "✅ Saqlandi!"
    await _safe_cb_answer(cb, toast)

    posted = False
    reply_kb = None
    if is_debt:
        header = f"📌 <b>Qarzga saqlandi! ({num_lbl})</b>"
        if nak_group and payment:
            posted, group_notice = await _post_payment_to_group(
                cb.bot, payment, nak_group, session_seq=session_seq
            )
        else:
            group_notice = "<i>(Nakladnoy guruhi ulanmagan — faqat bazaga qarzga olindi)</i>"
        group_notice += "\n📌 <i>Holat: Qarzga (qo'ldagi puldan ayrilmadi)</i>"
        reply_kb = auto_confirmed_nakladnoy_kb(
            payment.id, sent_to_group=posted, is_debt=True, payment_method="cash"
        )
    elif not send_to_group:
        header = f"⏭ <b>Bazaga saqlandi! ({num_lbl})</b>"
        group_notice = "<i>(Guruhga yuborilmadi — faqat hisobingizga olindi)</i>"
    elif nak_group and payment:
        if pm == "card":
            header = f"💳 <b>Karta orqali saqlandi! ({num_lbl})</b>"
        elif pm == "transfer":
            header = f"🏦 <b>Perechesleniya saqlandi! ({num_lbl})</b>"
        else:
            header = f"✅ <b>Tasdiqlandi! ({num_lbl})</b>"
        posted, group_notice = await _post_payment_to_group(
            cb.bot, payment, nak_group, session_seq=session_seq
        )
        if pm == "card":
            group_notice += "\n💳 <i>To'lov turi: Karta (qo'ldagi puldan ayrilmadi)</i>"
            reply_kb = auto_confirmed_nakladnoy_kb(
                payment.id, sent_to_group=posted, is_debt=False, payment_method="card"
            )
        elif pm == "transfer":
            group_notice += "\n🏦 <i>To'lov turi: Perechesleniya / o'tkazma (qo'ldagi puldan ayrilmadi)</i>"
            reply_kb = auto_confirmed_nakladnoy_kb(
                payment.id, sent_to_group=posted, is_debt=False, payment_method="transfer"
            )
    else:
        if pm == "card":
            header = f"💳 <b>Karta orqali saqlandi! ({num_lbl})</b>"
            group_notice = (
                "<i>(Nakladnoy guruhi ulanmagan — faqat bazaga saqlandi)</i>\n"
                "💳 <i>To'lov turi: Karta (qo'ldagi puldan ayrilmadi)</i>"
            )
        elif pm == "transfer":
            header = f"🏦 <b>Perechesleniya saqlandi! ({num_lbl})</b>"
            group_notice = (
                "<i>(Nakladnoy guruhi ulanmagan — faqat bazaga saqlandi)</i>\n"
                "🏦 <i>To'lov turi: Perechesleniya / o'tkazma (qo'ldagi puldan ayrilmadi)</i>"
            )
        else:
            header = f"✅ <b>Tasdiqlandi! ({num_lbl})</b>"
            group_notice = "<i>(Nakladnoy guruhi ulanmagan — faqat hisobga olindi)</i>"
        username = await get_bot_username(cb.bot)
        reply_kb = InlineKeyboardMarkup(
            inline_keyboard=[
                [
                    InlineKeyboardButton(
                        text="➕ 📸 Nakladnoy guruhini hozir ulash (Admin)",
                        url=build_add_to_group_url(username, "nakladnoy"),
                    )
                ]
            ]
        )

    await _safe_edit_text(
        cb.message,
        f"{header}\n"
        f"🏢 {html.escape(payment.supplier_name)} — <b>{format_uzs(payment.amount)} so'm</b>\n"
        f"{group_notice}\n\n"
        f"{_format_balance_summary_block(summary)}",
        reply_markup=reply_kb,
    )


@router.callback_query(F.data.startswith("nak:confirm:"))
async def cb_nakladnoy_confirm(cb: CallbackQuery, state: FSMContext) -> None:
    payment_id = int(cb.data.split(":")[-1])
    await _finalize_nakladnoy_confirmation(
        cb, payment_id, send_to_group=True, is_debt=False, state=state
    )


@router.callback_query(F.data.startswith("nak:save_only:"))
async def cb_nakladnoy_save_only(cb: CallbackQuery, state: FSMContext) -> None:
    payment_id = int(cb.data.split(":")[-1])
    await _finalize_nakladnoy_confirmation(
        cb, payment_id, send_to_group=False, is_debt=False, state=state
    )


@router.callback_query(F.data.startswith("nak:save_debt:"))
async def cb_nakladnoy_save_debt(cb: CallbackQuery, state: FSMContext) -> None:
    """Confirm pending nakladnoy as unpaid credit (Qarzga) and post QARZGA label to group."""
    payment_id = int(cb.data.split(":")[-1])
    await _finalize_nakladnoy_confirmation(
        cb, payment_id, send_to_group=True, is_debt=True, state=state
    )


@router.callback_query(F.data.startswith("nak:save_pm:"))
async def cb_nakladnoy_save_pm(cb: CallbackQuery, state: FSMContext) -> None:
    """Confirm pending nakladnoy as card or transfer (does not deduct from cash-on-hand)."""
    parts = cb.data.split(":")
    if len(parts) < 4:
        await cb.answer("Noto'g'ri buyruq", show_alert=True)
        return
    await _finalize_nakladnoy_confirmation(
        cb, int(parts[2]), send_to_group=True, is_debt=False, payment_method=parts[3], state=state
    )


@router.callback_query(F.data.startswith("nak:mark_debt:"))
async def cb_nakladnoy_mark_debt(cb: CallbackQuery) -> None:
    """Convert an already confirmed paid nakladnoy into unpaid credit (Qarzga)."""
    if await deny_if_unauthorized(cb, ("admin", "kassir")):
        return
    payment_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        payment = await mark_nakladnoy_as_debt(db, payment_id, user_id=cb.from_user.id)
        if not payment:
            await cb.answer("Topilmadi", show_alert=True)
            return
        summary = await compute_session_summary(db, payment.session_id)

    in_group = bool(payment.group_chat_id and payment.group_message_id)
    sync_msg = _schedule_group_sync(cb.bot, payment, delay=0.0)
    kb = (
        confirmed_nakladnoy_edit_kb(
            payment.id,
            in_group=in_group,
            is_debt=True,
            is_admin=is_admin_role(cb.from_user.id),
            payment_method="cash",
        )
        if "Tasdiqlangan Nakladnoy" in (cb.message.text or "")
        else auto_confirmed_nakladnoy_kb(payment.id, sent_to_group=in_group, is_debt=True)
    )
    await asyncio.gather(
        _safe_edit_text(
            cb.message,
            f"📌 <b>Qarzga o'tkazildi! (#{payment.id})</b>\n"
            f"🏢 Postavshik: <b>{html.escape(payment.supplier_name)}</b>\n"
            f"💰 Summa: <b>{format_uzs(payment.amount)} so'm</b>\n"
            f"<i>(Qo'ldagi puldan ayrilmadi)</i>\n"
            f"{sync_msg}\n\n"
            f"{_format_balance_summary_block(summary)}",
            reply_markup=kb,
        ),
        _safe_cb_answer(cb, "📌 Qarzga o'tkazildi!"),
    )


async def _handle_set_payment_method(cb: CallbackQuery, payment_id: int, pm: str) -> None:
    """Shared handler for paying off debt or switching payment method (cash | card | transfer)."""
    if await deny_if_unauthorized(cb, ("admin", "kassir")):
        return
    async with async_session_maker() as db:
        existing = await get_nakladnoy(db, payment_id)
        if not existing or existing.status == "deleted":
            await cb.answer("Topilmadi", show_alert=True)
            return
        was_debt = bool(existing.is_debt)
        res = await set_nakladnoy_payment_method(db, payment_id, pm, user_id=cb.from_user.id)
        if not res:
            await cb.answer("Topilmadi", show_alert=True)
            return
        payment, moved_to_today = res
        summary = await compute_session_summary(db, payment.session_id)

    actual_pm = (getattr(payment, "payment_method", "cash") or "cash").strip().lower()
    in_group = bool(payment.group_chat_id and payment.group_message_id)
    if was_debt:
        tag_map = {
            "cash": "✅ [QARZ TO'LANDI]",
            "card": "✅ [QARZ TO'LANDI — KARTA]",
            "transfer": "✅ [QARZ TO'LANDI — O'TKAZMA]",
        }
    else:
        tag_map = {
            "cash": "💵 [NAQD TO'LANDI]",
            "card": "💳 [KARTA ORQALI TO'LANDI]",
            "transfer": "🏦 [PERECHESLENIYA / O'TKAZMA]",
        }
    sync_msg = _schedule_group_sync(cb.bot, payment, tag=tag_map.get(actual_pm, ""), delay=0.0)
    moved_line = "\n📅 <i>O'tgan kundan bugungi kassaga yozildi</i>" if moved_to_today else ""

    if actual_pm == "card":
        heading = (
            f"💳 <b>Qarz karta bilan to'landi! (#{payment.id})</b>"
            if was_debt
            else f"💳 <b>Karta to'lovga o'tkazildi! (#{payment.id})</b>"
        )
        note_line = "\n<i>(Qo'ldagi puldan ayrilmadi)</i>"
        toast = "💳 Karta orqali saqlandi!"
    elif actual_pm == "transfer":
        heading = (
            f"🏦 <b>Qarz o'tkazma bilan to'landi! (#{payment.id})</b>"
            if was_debt
            else f"🏦 <b>Perechesleniyaga o'tkazildi! (#{payment.id})</b>"
        )
        note_line = "\n<i>(Qo'ldagi puldan ayrilmadi)</i>"
        toast = "🏦 Perechesleniya saqlandi!"
    else:
        heading = (
            f"💵 <b>Qarz to'landi! (#{payment.id})</b>"
            if was_debt
            else f"💵 <b>Naqd to'lovga o'tkazildi! (#{payment.id})</b>"
        )
        note_line = ""
        toast = "✅ To'landi!" if was_debt else "💵 Naqd to'lovga o'tkazildi!"

    msg_txt = cb.message.text or ""
    if "Tasdiqlangan Nakladnoy" in msg_txt:
        kb = confirmed_nakladnoy_edit_kb(
            payment.id,
            in_group=in_group,
            is_debt=False,
            is_admin=is_admin_role(cb.from_user.id),
            payment_method=actual_pm,
        )
    else:
        kb = auto_confirmed_nakladnoy_kb(
            payment.id,
            sent_to_group=in_group,
            is_debt=False,
            payment_method=actual_pm,
        )

    await asyncio.gather(
        _safe_edit_text(
            cb.message,
            f"{heading}\n"
            f"🏢 Postavshik: <b>{html.escape(payment.supplier_name)}</b>\n"
            f"💰 Summa: <b>{format_uzs(payment.amount)} so'm</b>{moved_line}{note_line}\n"
            f"{sync_msg}\n\n"
            f"{_format_balance_summary_block(summary)}",
            reply_markup=kb,
        ),
        _safe_cb_answer(cb, toast),
    )


@router.callback_query(F.data.startswith("nak:mark_paid:"))
async def cb_nakladnoy_mark_paid(cb: CallbackQuery) -> None:
    """Mark an unpaid credit nakladnoy as paid by cash (To'landi) and deduct from active cash."""
    payment_id = int(cb.data.split(":")[-1])
    await _handle_set_payment_method(cb, payment_id, "cash")


@router.callback_query(F.data.startswith("nak:set_pm:"))
async def cb_nakladnoy_set_payment_method(cb: CallbackQuery) -> None:
    """Switch confirmed nakladnoy payment method or pay debt via card / transfer / cash."""
    parts = cb.data.split(":")
    if len(parts) < 4:
        await cb.answer("Noto'g'ri buyruq", show_alert=True)
        return
    await _handle_set_payment_method(cb, int(parts[2]), parts[3])


@router.callback_query(F.data == "nak:debts")
async def cb_nakladnoy_debts_list(cb: CallbackQuery) -> None:
    """Display all unpaid credit nakladnoys across all days."""
    if await deny_if_unauthorized(cb):
        return
    async with async_session_maker() as db:
        items = await list_unpaid_debt_nakladnoys(db)
    if not items:
        await cb.answer("✅ To'lanmagan qarz nakladnoylar yo'q!", show_alert=True)
        return
    total = sum(float(p.amount) for p, _ in items)
    lines = [
        f"📌 <b>To'lanmagan qarz nakladnoylar ({len(items)} ta)</b>\n"
        f"💰 Jami qarz: <b>{format_uzs(total)} so'm</b>\n",
        "<i>To'langan deb belgilash uchun ustiga bosing:</i>",
    ]
    text = "\n".join(lines)
    kb = debt_nakladnoys_list_kb(items)
    src_text = cb.message.text or ""
    if "KUNLIK HISOB-KITOB" in src_text or "Nasiya" in src_text:
        await cb.message.answer(text, parse_mode="HTML", reply_markup=kb)
    else:
        await _safe_edit_text(cb.message, text, reply_markup=kb)
    await cb.answer()


@router.callback_query(F.data.startswith("nak:confirm_sup:"))
async def cb_nakladnoy_confirm_suggested(cb: CallbackQuery, state: FSMContext) -> None:
    """One-click: replace OCR supplier with fuzzy Cyrillic/Uzbek suggestion AND confirm to group."""
    if await deny_if_unauthorized(cb, ("admin", "kassir")):
        return
    payment_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
        if not payment or payment.status == "deleted":
            await cb.answer("Topilmadi", show_alert=True)
            return
        _, suggested = await resolve_supplier_name(db, payment.supplier_name)
        if suggested:
            await update_nakladnoy(
                db, payment_id, supplier_name=suggested, user_id=cb.from_user.id
            )
    await _finalize_nakladnoy_confirmation(
        cb, payment_id, send_to_group=True, is_debt=False, state=state
    )


@router.callback_query(F.data.startswith("nak:use_sup:"))
async def cb_nakladnoy_use_suggested(cb: CallbackQuery) -> None:
    """Merge fuzzy-matched supplier name to its canonical name (Y1)."""
    if await deny_if_unauthorized(cb, ("admin", "kassir")):
        return
    payment_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
        if not payment or payment.status == "deleted":
            await cb.answer("Topilmadi", show_alert=True)
            return
        _, suggested = await resolve_supplier_name(db, payment.supplier_name)
        if not suggested:
            await cb.answer("Taklif topilmadi")
            return
        payment = await update_nakladnoy(
            db, payment_id, supplier_name=suggested, user_id=cb.from_user.id
        )
        dup = await find_duplicate_confirmed_nakladnoy(
            db, payment.session_id, payment.supplier_name, payment.amount, exclude_id=payment.id
        )

    if payment.status == "confirmed":
        in_group = bool(payment.group_chat_id and payment.group_message_id)
        sync_msg = _schedule_group_sync(cb.bot, payment, tag="✏️ [NOM TAHRIRLANDI]", delay=0.0)
        await asyncio.gather(
            _safe_edit_text(
                cb.message,
                f"✅ Birlashtirildi: <b>{html.escape(payment.supplier_name)}</b> — {format_uzs(payment.amount)} so'm\n{sync_msg}",
                reply_markup=confirmed_nakladnoy_edit_kb(
                    payment.id,
                    in_group=in_group,
                    is_debt=payment.is_debt,
                    is_admin=is_admin_role(cb.from_user.id),
                    payment_method=getattr(payment, "payment_method", "cash"),
                ),
            ),
            _safe_cb_answer(cb, "✅ Birlashtirildi!"),
        )
    else:
        await asyncio.gather(
            _safe_edit_text(
                cb.message,
                _pending_card_text(payment, duplicate_warning=dup),
                reply_markup=nakladnoy_confirm_kb(payment.id),
            ),
            _safe_cb_answer(cb, "✅ Birlashtirildi!"),
        )


@router.callback_query(F.data.startswith("nak:back_card:"))
async def cb_nakladnoy_back_card(cb: CallbackQuery, state: FSMContext) -> None:
    await state.clear()
    payment_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
        if not payment or payment.status == "deleted":
            await cb.answer("Topilmadi", show_alert=True)
            return
        _, sug = await resolve_supplier_name(db, payment.supplier_name)
        dup = await find_duplicate_confirmed_nakladnoy(
            db, payment.session_id, payment.supplier_name, payment.amount, exclude_id=payment.id
        )
    await asyncio.gather(
        _safe_edit_text(
            cb.message,
            _pending_card_text(payment, duplicate_warning=dup, suggested_supplier=sug),
            reply_markup=nakladnoy_confirm_kb(payment.id, suggested_supplier=sug),
        ),
        _safe_cb_answer(cb),
    )


@router.callback_query(F.data.startswith("nak:unpost_group:"))
async def cb_nakladnoy_unpost_group(cb: CallbackQuery) -> None:
    """Remove auto-sent message from Nakladnoy group while keeping payment saved in DB."""
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    payment_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
        if not payment or payment.status == "deleted":
            await cb.answer("Topilmadi", show_alert=True)
            return
        old_chat = payment.group_chat_id
        old_msg = payment.group_message_id
        await set_nakladnoy_group_message(db, payment.id, None, None)
        summary = await compute_session_summary(db, payment.session_id)

    if old_chat and old_msg:
        try:
            await cb.bot.delete_message(chat_id=old_chat, message_id=old_msg)
        except Exception:
            pass

    await _safe_edit_text(
        cb.message,
        f"✅ <b>Faqat shaxsiy hisobingizda saqlandi! (#{payment.id})</b>\n"
        f"🏢 Postavshik: <b>{html.escape(payment.supplier_name)}</b>\n"
        f"💰 Summa: <b>{format_uzs(payment.amount)} so'm</b>\n"
        f"🙈 <i>(Guruhdan olib tashlandi)</i>\n\n"
        f"{_format_balance_summary_block(summary)}",
        reply_markup=None,
    )
    await cb.answer("✅ Shaxsiy hisobga saqlandi!")


@router.callback_query(F.data.startswith("nak:done:"))
async def cb_nakladnoy_done(cb: CallbackQuery, state: FSMContext) -> None:
    """Collapse quick-edit buttons and show remaining balance summary."""
    await state.clear()
    payment_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
        if not payment or payment.status == "deleted":
            await cb.answer("Topilmadi", show_alert=True)
            return
        summary = await compute_session_summary(db, payment.session_id)

    pm = (getattr(payment, "payment_method", "cash") or "cash").strip().lower()
    where = "📤 Guruhga yuborilgan" if payment.group_message_id else "💾 Faqat shaxsiy hisobda"
    if payment.is_debt:
        status_line = "📌 Qarzga (pul berilmagan)"
        icon = "📌"
    elif pm == "card":
        status_line = f"💳 Karta orqali (naqd puldan ayrilmadi) | {where}"
        icon = "💳"
    elif pm == "transfer":
        status_line = f"🏦 Perechesleniya (naqd puldan ayrilmadi) | {where}"
        icon = "🏦"
    else:
        status_line = where
        icon = "✅"
    done_kb = (
        InlineKeyboardMarkup(
            inline_keyboard=[
                [
                    InlineKeyboardButton(
                        text="💵 To'landi (Pul berildi)",
                        callback_data=f"nak:mark_paid:{payment.id}",
                    )
                ],
                [
                    InlineKeyboardButton(
                        text="💳 Karta",
                        callback_data=f"nak:set_pm:{payment.id}:card",
                    ),
                    InlineKeyboardButton(
                        text="🏦 O'tkazma",
                        callback_data=f"nak:set_pm:{payment.id}:transfer",
                    ),
                ],
            ]
        )
        if payment.is_debt
        else None
    )
    await asyncio.gather(
        _safe_edit_text(
            cb.message,
            f"{icon} <b>Saqlandi! (#{payment.id})</b>\n"
            f"🏢 Postavshik: <b>{html.escape(payment.supplier_name)}</b>\n"
            f"💰 Summa: <b>{format_uzs(payment.amount)} so'm</b>\n"
            f"<i>({status_line})</i>\n\n"
            f"{_format_balance_summary_block(summary)}",
            reply_markup=done_kb,
        ),
        _safe_cb_answer(cb, "✅ Tayyor!"),
    )


@router.callback_query(F.data.startswith("nak:repost_group:"))
async def cb_nakladnoy_repost_group(cb: CallbackQuery) -> None:
    """Post a saved-only confirmed payment to the Nakladnoy group."""
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    payment_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
        nak_group = await get_group_config(db, "nakladnoy")
        if not payment or payment.status != "confirmed":
            await cb.answer("Topilmadi", show_alert=True)
            return
        if not nak_group:
            await cb.answer("Nakladnoy guruhi ulanmagan!", show_alert=True)
            return
        summary = await compute_session_summary(db, payment.session_id)

    posted, notice = await _post_payment_to_group(cb.bot, payment, nak_group)
    pm = (getattr(payment, "payment_method", "cash") or "cash").strip().lower()
    await _safe_edit_text(
        cb.message,
        f"✅ <b>Bazada saqlangan (#{payment.id})</b>\n"
        f"🏢 Postavshik: <b>{html.escape(payment.supplier_name)}</b>\n"
        f"💰 Summa: <b>{format_uzs(payment.amount)} so'm</b>\n"
        f"{notice}\n\n"
        f"💵 Qo'lda qolishi kerak: <b>{format_uzs(summary.expected_cash)} so'm</b>",
        reply_markup=auto_confirmed_nakladnoy_kb(
            payment.id, sent_to_group=posted, is_debt=payment.is_debt, payment_method=pm
        ),
    )
    await cb.answer("📤 Yuborildi!")


@router.callback_query(F.data.startswith("nak:cancel:"))
async def cb_nakladnoy_cancel(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin", "kassir")):
        return
    await state.clear()
    payment_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        await delete_nakladnoy(db, payment_id, user_id=cb.from_user.id)
    await _safe_edit_text(cb.message, "❌ Nakladnoy bekor qilindi (hisobga olinmadi).")
    await cb.answer("Bekor qilindi")


@router.callback_query(F.data.startswith("nak:photo:"))
async def cb_view_nakladnoy_photo(cb: CallbackQuery) -> None:
    """Re-open stored Telegram nakladnoy photo from history/search."""
    if await deny_if_unauthorized(cb):
        return
    payment_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
        session_seq = (
            await get_nakladnoy_session_seq(db, payment)
            if (payment and payment.photo_file_id)
            else None
        )
    if not payment or not payment.photo_file_id:
        await cb.answer("Bu yozuvda rasm saqlanmagan.", show_alert=True)
        return
    caption = render_nakladnoy_group_caption(payment, session_seq=session_seq)
    await cb.bot.send_photo(
        chat_id=cb.from_user.id,
        photo=payment.photo_file_id,
        caption=caption,
        parse_mode="HTML",
    )
    await cb.answer("📸 Rasm yuborildi")


# ---------------------------------------------------------------------------
# Edit Confirmed Payments & Cash Transactions
# ---------------------------------------------------------------------------


async def handle_edit_confirmed_btn(
    message: Message, state: FSMContext, actor_id: Optional[int] = None
) -> None:
    uid = actor_id if actor_id is not None else (message.from_user.id if message.from_user else None)
    if not is_admin_role(uid):
        await message.answer("🔒 Tahrirlash faqat admin uchun.")
        return
    await state.clear()
    async with async_session_maker() as db:
        summary = await compute_session_summary(db)
    if (
        not summary.confirmed_nakladnoys
        and not summary.noncash_nakladnoys
        and not summary.debt_nakladnoys
        and not summary.cash_transactions
    ):
        await message.answer("ℹ️ Bugungi ochiq smenada hali tahrirlanadigan yozuvlar yo'q.")
        return
    await message.answer(
        "✏️ <b>Tasdiqlanganlarni tahrirlash:</b>\n"
        "O'zgartirmoqchi yoki o'chirmoqchi bo'lgan yozuvni tanlang\n"
        "<i>(Nakladnoy o'zgartirilsa, guruhdagi xabar ham avtomat yangilanadi):</i>",
        parse_mode="HTML",
        reply_markup=edit_items_list_kb(
            summary.confirmed_nakladnoys,
            summary.cash_transactions,
            debt_nakladnoys=summary.debt_nakladnoys,
            noncash_nakladnoys=summary.noncash_nakladnoys,
        ),
    )


@router.callback_query(F.data == "edit_menu:open")
async def cb_edit_menu_open(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    await state.clear()
    async with async_session_maker() as db:
        summary = await compute_session_summary(db)
    if (
        not summary.confirmed_nakladnoys
        and not summary.noncash_nakladnoys
        and not summary.debt_nakladnoys
        and not summary.cash_transactions
    ):
        await cb.answer("Bugungi smenada yozuvlar yo'q.", show_alert=True)
        return
    await asyncio.gather(
        _safe_edit_text(
            cb.message,
            "✏️ <b>Tasdiqlanganlarni tahrirlash:</b>\nKerakli qatorni tanlang:",
            reply_markup=edit_items_list_kb(
                summary.confirmed_nakladnoys,
                summary.cash_transactions,
                debt_nakladnoys=summary.debt_nakladnoys,
                noncash_nakladnoys=summary.noncash_nakladnoys,
            ),
        ),
        _safe_cb_answer(cb),
    )


@router.callback_query(F.data == "menu:dismiss")
async def cb_menu_dismiss(cb: CallbackQuery) -> None:
    try:
        await cb.message.delete()
    except Exception:
        pass
    await _safe_cb_answer(cb)


@router.callback_query(F.data.startswith("nak_view:"))
async def cb_nakladnoy_edit_view(cb: CallbackQuery, state: FSMContext) -> None:
    payment_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
    if not payment or payment.status == "deleted":
        await cb.answer("Topilmadi", show_alert=True)
        return
    allowed = ("admin", "kassir") if payment.is_debt else ("admin",)
    if await deny_if_unauthorized(cb, allowed):
        return
    await state.clear()
    in_group = bool(payment.group_chat_id and payment.group_message_id)
    group_state = (
        "📤 Guruhga yuborilgan (tahrirlasangiz u yerda ham yangilanadi)"
        if in_group
        else "💾 Faqat bazada (guruhga yuborilmagan)"
    )
    pm = (getattr(payment, "payment_method", "cash") or "cash").strip().lower()
    if payment.is_debt:
        pay_state = "📌 QARZGA (pul berilmagan)"
    elif pm == "card":
        pay_state = "💳 Karta orqali to'langan (naqdsiz)"
    elif pm == "transfer":
        pay_state = "🏦 Perechesleniya / o'tkazma (naqdsiz)"
    else:
        pay_state = "✅ Naqd to'langan"
    await asyncio.gather(
        _safe_edit_text(
            cb.message,
            f"📸 <b>Tasdiqlangan Nakladnoy #{payment.id}</b>\n"
            f"🏢 Postavshik: <b>{html.escape(payment.supplier_name)}</b>\n"
            f"💰 Summa: <b>{format_uzs(payment.amount)} so'm</b>\n"
            f"💳 To'lov holati: <b>{pay_state}</b>\n"
            f"📍 Guruh: <i>{group_state}</i>",
            reply_markup=confirmed_nakladnoy_edit_kb(
                payment.id,
                in_group=in_group,
                is_debt=payment.is_debt,
                is_admin=is_admin_role(cb.from_user.id),
                payment_method=pm,
            ),
        ),
        _safe_cb_answer(cb),
    )


async def _arm_amount_input_state(
    state: FSMContext, payment_id: int, cb: CallbackQuery, used_cancel_kb: bool = False
) -> None:
    """Keep waiting_edit_nakladnoy_amount active so direct text/voice input works alongside buttons."""
    await state.set_state(WalletStates.waiting_edit_nakladnoy_amount)
    await state.update_data(
        payment_id=payment_id,
        edit_msg_id=cb.message.message_id if cb.message else None,
        used_cancel_kb=used_cancel_kb,
    )


@router.callback_query(F.data.startswith("nak:edit_amt:"))
async def cb_nakladnoy_edit_amt_prompt(cb: CallbackQuery, state: FSMContext) -> None:
    """Open quick-adjust amount buttons while immediately accepting typed/voice amount input."""
    payment_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
    if not payment or payment.status == "deleted":
        await cb.answer("Topilmadi", show_alert=True)
        return
    allowed = ("admin",) if payment.status == "confirmed" else ("admin", "kassir")
    if await deny_if_unauthorized(cb, allowed):
        return
    await _arm_amount_input_state(state, payment_id, cb, used_cancel_kb=False)
    await asyncio.gather(
        _safe_edit_text(
            cb.message,
            f"💰 <b>Summani tahrirlash (#{payment.id})</b>\n"
            f"🏢 Postavshik: <b>{html.escape(payment.supplier_name)}</b>\n"
            f"💵 Hozirgi summa: <b>{format_uzs(payment.amount)} so'm</b>\n\n"
            "👇 Tez tugmalarni bosing yoki to'g'ridan-to'g'ri yangi summani yozib (yoki ovozda aytib) yuboring (masalan: <code>260 000</code>):",
            reply_markup=nakladnoy_quick_amount_kb(payment.id, is_confirmed=(payment.status == "confirmed")),
        ),
        _safe_cb_answer(cb),
    )


async def _apply_quick_amount_change(
    cb: CallbackQuery, state: FSMContext, payment_id: int, mode: str, delta: int = 0
) -> None:
    summary: Optional[SessionSummary] = None
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
        if not payment or payment.status == "deleted":
            await cb.answer("Topilmadi", show_alert=True)
            return
        allowed = ("admin",) if payment.status == "confirmed" else ("admin", "kassir")
        if await deny_if_unauthorized(cb, allowed):
            return
        if mode == "delta":
            new_amt = max(1000.0, float(payment.amount) + delta)
        else:
            new_amt = round_nakladnoy_amount(float(payment.amount), "floor_1000")
            if new_amt <= 0:
                new_amt = float(payment.amount)
        payment = await update_nakladnoy(db, payment_id, amount=new_amt, user_id=cb.from_user.id)
        if payment.status == "confirmed":
            summary = await compute_session_summary(db, payment.session_id)

    await _arm_amount_input_state(state, payment_id, cb, used_cancel_kb=False)

    sync_line = ""
    if payment.status == "confirmed" and summary is not None:
        sync_msg = _schedule_group_sync(
            cb.bot, payment, tag="✏️ [SUMMA TAHRIRLANDI]", delay=0.45
        )
        sync_line = f"\n{sync_msg}\n💵 Qoldiq: <b>{format_uzs(summary.expected_cash)} so'm</b>"

    await asyncio.gather(
        _safe_edit_text(
            cb.message,
            f"✅ <b>Summa yangilandi (#{payment.id})</b>\n"
            f"🏢 Postavshik: <b>{html.escape(payment.supplier_name)}</b>\n"
            f"💰 Summa: <b>{format_uzs(payment.amount)} so'm</b>{sync_line}\n\n"
            "<i>Yana tez tugmalarni bosing yoki yangi summani yozib yuboring:</i>",
            reply_markup=nakladnoy_quick_amount_kb(payment.id, is_confirmed=(payment.status == "confirmed")),
        ),
        _safe_cb_answer(cb, f"💰 {format_uzs(payment.amount)} so'm"),
    )


@router.callback_query(F.data.startswith("nak:adj:"))
async def cb_nakladnoy_quick_delta(cb: CallbackQuery, state: FSMContext) -> None:
    parts = cb.data.split(":")
    await _apply_quick_amount_change(cb, state, int(parts[2]), mode="delta", delta=int(parts[3]))


@router.callback_query(F.data.startswith("nak:adj_round:"))
async def cb_nakladnoy_quick_round(cb: CallbackQuery, state: FSMContext) -> None:
    payment_id = int(cb.data.split(":")[-1])
    await _apply_quick_amount_change(cb, state, payment_id, mode="round")


@router.callback_query(F.data.startswith("nak:edit_amt_manual:"))
async def cb_nakladnoy_edit_amt_manual(cb: CallbackQuery, state: FSMContext) -> None:
    payment_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
    if not payment or payment.status == "deleted":
        await cb.answer("Topilmadi", show_alert=True)
        return
    allowed = ("admin",) if payment.status == "confirmed" else ("admin", "kassir")
    if await deny_if_unauthorized(cb, allowed):
        return
    await _arm_amount_input_state(state, payment_id, cb, used_cancel_kb=True)
    await cb.message.answer(
        "💰 Yangi summani yozing yoki ovozda ayting (masalan: <code>1 657 000</code>):",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.message(
    WalletStates.waiting_edit_nakladnoy_amount,
    F.chat.type == "private",
    F.text | F.voice | F.audio,
)
async def process_edit_nakladnoy_amount(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message, ("admin", "kassir")):
        return
    amount = None
    if message.voice or message.audio:
        try:
            audio_bytes, mime = await _download_voice_bytes(message)
        except VoiceTooLongError:
            await message.answer(f"⚠️ Ovozli xabar {MAX_VOICE_SECONDS} soniyadan oshmasligi kerak.")
            return
        parsed = await parse_voice_or_text(audio_bytes=audio_bytes, mime_type=mime)
        await maybe_warn_ai_limit(message.bot)
        amount = parsed.get("amount")
    elif message.text:
        amount = parse_uzbek_amount(message.text)

    if not amount or amount <= 0:
        await message.answer("⚠️ Summa noto'g'ri. Raqam bilan kiriting:")
        return

    data = await state.get_data()
    payment_id = data["payment_id"]
    edit_msg_id = data.get("edit_msg_id")
    used_cancel_kb = bool(data.get("used_cancel_kb"))
    uid = message.from_user.id if message.from_user else None
    async with async_session_maker() as db:
        existing = await get_nakladnoy(db, payment_id)
        if existing and existing.status == "confirmed" and not is_admin_role(uid):
            await state.clear()
            await message.answer("🔒 Tasdiqlangan summani o'zgartirish faqat admin uchun.", reply_markup=main_menu_keyboard())
            return
        payment = await update_nakladnoy(db, payment_id, amount=amount, user_id=uid)
        if not payment:
            await state.clear()
            await message.answer("⚠️ Nakladnoy topilmadi.", reply_markup=main_menu_keyboard())
            return
        summary = await compute_session_summary(db, payment.session_id)

    await state.clear()
    if edit_msg_id:
        try:
            await message.bot.edit_message_reply_markup(
                chat_id=message.chat.id,
                message_id=edit_msg_id,
                reply_markup=None,
            )
        except Exception:
            pass
    if payment.status == "confirmed":
        in_group = bool(payment.group_chat_id and payment.group_message_id)
        sync_msg = _schedule_group_sync(
            message.bot, payment, tag="✏️ [SUMMA TAHRIRLANDI]", delay=0.0
        )
        await message.answer(
            f"✅ Summa yangilandi: <b>{html.escape(payment.supplier_name)} — {format_uzs(payment.amount)} so'm</b>\n"
            f"{sync_msg}\n"
            f"💰 Qo'lda qolishi kerak: <b>{format_uzs(summary.expected_cash)} so'm</b>",
            parse_mode="HTML",
            reply_markup=confirmed_nakladnoy_edit_kb(
                payment.id,
                in_group=in_group,
                is_debt=payment.is_debt,
                is_admin=is_admin_role(uid),
                payment_method=getattr(payment, "payment_method", "cash"),
            ),
        )
        if used_cancel_kb:
            await message.answer("👇 Asosiy menyu:", reply_markup=main_menu_keyboard())
    else:
        await _send_pending_nakladnoy_card(message, payment)
        if used_cancel_kb:
            await message.answer("👇 Tasdiqlang:", reply_markup=main_menu_keyboard())


def _edit_supplier_prompt_text(payment: NakladnoyPayment, total_suppliers: int) -> str:
    """Prompt shown when choosing or typing a new supplier for a nakladnoy."""
    pick_hint = (
        f"\n👇 Ro'yxatdan tanlang (jami <b>{total_suppliers}</b> ta) yoki yangi nomni yozib (yoki ovozda aytib) yuboring:"
        if total_suppliers > 0
        else "\n👇 Yangi nomni yozib (yoki ovozda aytib) yuboring:"
    )
    return (
        f"🏢 <b>Postavshikni o'zgartirish (#{payment.id})</b>\n"
        f"📌 Hozirgi nom: <b>{html.escape(payment.supplier_name or 'Noma\'lum')}</b>\n"
        f"💰 Summa: <b>{format_uzs(payment.amount)} so'm</b>"
        f"{pick_hint}"
    )


async def _arm_supplier_input_state(
    state: FSMContext, payment_id: int, suppliers: list[str], cb: CallbackQuery
) -> None:
    """Keep waiting_edit_nakladnoy_supplier active so direct text/voice input works alongside buttons."""
    await state.set_state(WalletStates.waiting_edit_nakladnoy_supplier)
    await state.update_data(
        payment_id=payment_id,
        edit_suppliers=suppliers,
        edit_msg_id=cb.message.message_id if cb.message else None,
        used_cancel_kb=False,
    )


async def _render_supplier_picker(
    cb: CallbackQuery, state: FSMContext, payment_id: int, page: int = 0, use_cached: bool = False
) -> None:
    """Shared renderer for opening and paginating the inline supplier picker."""
    cached = (await state.get_data()).get("edit_suppliers") if use_cached else None
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
        if not payment or payment.status == "deleted":
            await cb.answer("Topilmadi", show_alert=True)
            return
        allowed = ("admin",) if payment.status == "confirmed" else ("admin", "kassir")
        if await deny_if_unauthorized(cb, allowed):
            return
        suppliers = list(cached) if cached else await get_all_known_suppliers(db)

    await _arm_supplier_input_state(state, payment_id, suppliers, cb)
    await asyncio.gather(
        _safe_edit_text(
            cb.message,
            _edit_supplier_prompt_text(payment, len(suppliers)),
            reply_markup=edit_supplier_pick_kb(
                payment.id,
                suppliers,
                is_confirmed=(payment.status == "confirmed"),
                page=page,
            ),
        ),
        _safe_cb_answer(cb),
    )


async def _build_supplier_updated_response(
    bot,
    payment: NakladnoyPayment,
    uid: Optional[int],
    dup: Optional[NakladnoyPayment] = None,
) -> tuple[str, InlineKeyboardMarkup]:
    """Schedule background group sync (if confirmed) and build response text + keyboard."""
    if payment.status == "confirmed":
        in_group = bool(payment.group_chat_id and payment.group_message_id)
        sync_msg = _schedule_group_sync(
            bot, payment, tag="✏️ [NOM TAHRIRLANDI]", delay=0.0
        )
        text = (
            f"✅ Postavshik yangilandi: <b>{html.escape(payment.supplier_name)} — {format_uzs(payment.amount)} so'm</b>\n"
            f"{sync_msg}"
        )
        kb = confirmed_nakladnoy_edit_kb(
            payment.id,
            in_group=in_group,
            is_debt=payment.is_debt,
            is_admin=is_admin_role(uid),
            payment_method=getattr(payment, "payment_method", "cash"),
        )
        return text, kb
    return _pending_card_text(payment, duplicate_warning=dup), nakladnoy_confirm_kb(payment.id)


@router.callback_query(F.data.startswith("nak:edit_sup:"))
async def cb_nakladnoy_edit_sup_prompt(cb: CallbackQuery, state: FSMContext) -> None:
    payment_id = int(cb.data.split(":")[-1])
    await _render_supplier_picker(cb, state, payment_id, page=0, use_cached=False)


@router.callback_query(F.data.startswith("nak:sup_page:"))
async def cb_nakladnoy_edit_sup_page(cb: CallbackQuery, state: FSMContext) -> None:
    parts = cb.data.split(":")
    if len(parts) < 4 or not parts[2].isdigit() or not parts[3].lstrip("-").isdigit():
        await cb.answer()
        return
    await _render_supplier_picker(cb, state, int(parts[2]), page=int(parts[3]), use_cached=True)


@router.callback_query(F.data.startswith("nak:pick_sup:"))
async def cb_nakladnoy_pick_supplier(cb: CallbackQuery, state: FSMContext) -> None:
    parts = cb.data.split(":")
    if len(parts) < 4 or not parts[2].isdigit() or not parts[3].isdigit():
        await cb.answer()
        return
    payment_id = int(parts[2])
    idx = int(parts[3])
    uid = cb.from_user.id if cb.from_user else None

    cached = (await state.get_data()).get("edit_suppliers")
    async with async_session_maker() as db:
        existing = await get_nakladnoy(db, payment_id)
        if not existing or existing.status == "deleted":
            await cb.answer("Topilmadi", show_alert=True)
            return
        allowed = ("admin",) if existing.status == "confirmed" else ("admin", "kassir")
        if await deny_if_unauthorized(cb, allowed):
            return
        suppliers = list(cached) if cached else await get_all_known_suppliers(db)
        if idx < 0 or idx >= len(suppliers):
            await cb.answer("Ro'yxat eskirgan, qaytadan oching", show_alert=True)
            return
        canon, _ = await resolve_supplier_name(db, suppliers[idx])
        payment = await update_nakladnoy(db, payment_id, supplier_name=canon, user_id=uid)
        dup = (
            await find_duplicate_confirmed_nakladnoy(
                db, payment.session_id, payment.supplier_name, payment.amount, exclude_id=payment.id
            )
            if payment and payment.status != "confirmed"
            else None
        )

    await state.clear()
    if not payment:
        await cb.answer("Topilmadi", show_alert=True)
        return
    text, kb = await _build_supplier_updated_response(cb.bot, payment, uid, dup=dup)
    await asyncio.gather(
        _safe_edit_text(cb.message, text, reply_markup=kb),
        _safe_cb_answer(cb, f"✅ {payment.supplier_name}"),
    )


@router.message(
    WalletStates.waiting_edit_nakladnoy_supplier,
    F.chat.type == "private",
    F.text | F.voice | F.audio,
)
async def process_edit_nakladnoy_supplier(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message, ("admin", "kassir")):
        return
    new_name = ""
    if message.voice or message.audio:
        try:
            audio_bytes, mime = await _download_voice_bytes(message)
        except VoiceTooLongError:
            await message.answer(f"⚠️ Ovozli xabar {MAX_VOICE_SECONDS} soniyadan oshmasligi kerak.")
            return
        parsed = await parse_voice_or_text(audio_bytes=audio_bytes, mime_type=mime)
        await maybe_warn_ai_limit(message.bot)
        new_name = parsed.get("supplier_name") or parsed.get("transcript") or ""
    elif message.text:
        new_name = message.text.strip()

    if not new_name:
        await message.answer("⚠️ Nom kiriting:")
        return

    data = await state.get_data()
    payment_id = data["payment_id"]
    edit_msg_id = data.get("edit_msg_id")
    used_cancel_kb = bool(data.get("used_cancel_kb", True))
    uid = message.from_user.id if message.from_user else None
    async with async_session_maker() as db:
        existing = await get_nakladnoy(db, payment_id)
        if existing and existing.status == "confirmed" and not is_admin_role(uid):
            await state.clear()
            await message.answer("🔒 Tasdiqlangan nomni o'zgartirish faqat admin uchun.", reply_markup=main_menu_keyboard())
            return
        canon, _ = await resolve_supplier_name(db, new_name)
        payment = await update_nakladnoy(db, payment_id, supplier_name=canon, user_id=uid)
        dup = (
            await find_duplicate_confirmed_nakladnoy(
                db, payment.session_id, payment.supplier_name, payment.amount, exclude_id=payment.id
            )
            if payment and payment.status != "confirmed"
            else None
        )
    await state.clear()

    if edit_msg_id:
        try:
            await message.bot.edit_message_reply_markup(
                chat_id=message.chat.id,
                message_id=edit_msg_id,
                reply_markup=None,
            )
        except Exception:
            pass

    if not payment:
        await message.answer("⚠️ Topilmadi.", reply_markup=main_menu_keyboard())
        return

    text, kb = await _build_supplier_updated_response(message.bot, payment, uid, dup=dup)
    await message.answer(text, parse_mode="HTML", reply_markup=kb)
    if used_cancel_kb:
        hint = "👇 Asosiy menyu:" if payment.status == "confirmed" else "👇 Tasdiqlang:"
        await message.answer(hint, reply_markup=main_menu_keyboard())


@router.callback_query(F.data.startswith("nak:delete_conf:"))
async def cb_nakladnoy_delete_prompt(cb: CallbackQuery) -> None:
    """Ask 2-step confirmation before deleting a confirmed nakladnoy (T4)."""
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    payment_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
    if not payment or payment.status == "deleted":
        await cb.answer("Topilmadi", show_alert=True)
        return
    await _safe_edit_text(
        cb.message,
        f"⚠️ <b>Nakladnoy #{payment.id}</b> ({html.escape(payment.supplier_name)} — "
        f"<b>{format_uzs(payment.amount)} so'm</b>) rostdan ham o'chirilsinmi?",
        reply_markup=delete_confirm_kb(f"nak:delete_yes:{payment.id}", f"nak_view:{payment.id}"),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("nak:delete_yes:"))
async def cb_nakladnoy_delete_confirmed(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    payment_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        payment = await delete_nakladnoy(db, payment_id, user_id=cb.from_user.id)
        if not payment:
            await cb.answer("Topilmadi", show_alert=True)
            return
        summary = await compute_session_summary(db, payment.session_id)

    sync_msg = _schedule_group_sync(cb.bot, payment, delay=0.0)
    await asyncio.gather(
        _safe_edit_text(
            cb.message,
            f"🗑 Nakladnoy #{payment.id} ({html.escape(payment.supplier_name)} — {format_uzs(payment.amount)}) o'chirildi!\n"
            f"{sync_msg}\n"
            f"💰 Yangilangan qoldiq: <b>{format_uzs(summary.expected_cash)} so'm</b>",
        ),
        _safe_cb_answer(cb, "O'chirildi!"),
    )


@router.callback_query(F.data.startswith("cash_view:"))
async def cb_cash_tx_view(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    tx_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        tx = await db.get(CashTransaction, tx_id)
    if not tx or tx.is_deleted:
        await cb.answer("Topilmadi", show_alert=True)
        return
    labels = {"main": "Asosiy pul olish", "kassa_debt": "Kassadan qarz", "kassa_repay": "Kassaga qaytarish"}
    await _safe_edit_text(
        cb.message,
        f"💵 <b>{labels.get(tx.source_type, tx.source_type)}</b>\n"
        f"💰 Summa: <b>{format_uzs(tx.amount)} so'm</b>\n"
        f"📝 Izoh: <i>{html.escape(tx.note or '-')}</i>",
        reply_markup=cash_tx_edit_kb(tx.id),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("cash:edit_amt:"))
async def cb_cash_edit_prompt(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    tx_id = int(cb.data.split(":")[-1])
    await state.set_state(WalletStates.waiting_edit_cash_amount)
    await state.update_data(tx_id=tx_id)
    await cb.message.answer(
        "💰 Yangi summani kiriting:",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.message(WalletStates.waiting_edit_cash_amount, F.chat.type == "private")
async def process_edit_cash_amount(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message, ("admin",)):
        return
    amount = parse_uzbek_amount(message.text or "")
    if not amount or amount <= 0:
        await message.answer("⚠️ To'g'ri summa kiriting:")
        return
    data = await state.get_data()
    uid = message.from_user.id if message.from_user else None
    async with async_session_maker() as db:
        tx = await update_cash_transaction(db, data["tx_id"], new_amount=amount, user_id=uid)
        if not tx:
            await state.clear()
            await message.answer("⚠️ Topilmadi.", reply_markup=main_menu_keyboard())
            return
        summary = await compute_session_summary(db, tx.session_id)
    await state.clear()
    await message.answer(
        f"✅ Summa yangilandi: <b>{format_uzs(tx.amount)} so'm</b>\n"
        f"💰 Qo'lda qolishi kerak: <b>{format_uzs(summary.expected_cash)} so'm</b>",
        parse_mode="HTML",
        reply_markup=main_menu_keyboard(),
    )


@router.callback_query(F.data.startswith("cash:delete:"))
async def cb_cash_delete_prompt(cb: CallbackQuery) -> None:
    """Ask 2-step confirmation before deleting a cash transaction (T4)."""
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    tx_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        tx = await db.get(CashTransaction, tx_id)
    if not tx or tx.is_deleted:
        await cb.answer("Topilmadi", show_alert=True)
        return
    await _safe_edit_text(
        cb.message,
        f"⚠️ Kirim yozuvi (<b>{format_uzs(tx.amount)} so'm</b>) rostdan ham o'chirilsinmi?",
        reply_markup=delete_confirm_kb(f"cash:delete_yes:{tx.id}", f"cash_view:{tx.id}"),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("cash:delete_yes:"))
async def cb_cash_delete(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    tx_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        tx = await delete_cash_transaction(db, tx_id, user_id=cb.from_user.id)
        if not tx:
            await cb.answer("Topilmadi", show_alert=True)
            return
        summary = await compute_session_summary(db, tx.session_id)
    await _safe_edit_text(
        cb.message,
        f"🗑 Kirim yozuvi ({format_uzs(tx.amount)} so'm) o'chirildi!\n"
        f"💰 Yangilangan qoldiq: <b>{format_uzs(summary.expected_cash)} so'm</b>",
    )
    await cb.answer("O'chirildi!")


# ---------------------------------------------------------------------------
# End-of-Day Reconciliation (Sverka & Close Day)
# ---------------------------------------------------------------------------


async def handle_close_day_start(
    message: Message, state: FSMContext, actor_id: Optional[int] = None
) -> None:
    uid = actor_id if actor_id is not None else (message.from_user.id if message.from_user else None)
    if not is_admin_role(uid):
        await message.answer("🔒 Kunni yakunlash faqat admin uchun.")
        return
    async with async_session_maker() as db:
        summary = await compute_session_summary(db)

    await state.set_state(WalletStates.waiting_counted_cash)
    await state.update_data(session_id=summary.session.id)
    await message.answer(
        f"🏁 <b>KUNNI YAKUNLASH ({summary.session.report_date})</b>\n"
        "===============================\n"
        f"⏮ Qanchadan boshlangan (Kechadan): <b>{format_uzs(summary.opening_balance)}</b>\n"
        f"➕ Bugungi kirimlar (Kassa qarzi bn): <b>{format_uzs(summary.main_cash_in + summary.kassa_debt_today - summary.kassa_repay_today)}</b>\n"
        f"💵 Jami summa: <b>{format_uzs(summary.total_available_inflow)}</b>\n"
        f"➖ Umumiy rasxod ({len(summary.confirmed_nakladnoys)} ta nakladnoy): <b>{format_uzs(summary.total_nakladnoy_spent)}</b>\n"
        f"💰 <b>Qo'lda qolishi kerak: {format_uzs(summary.expected_cash)} so'm</b>\n"
        "===============================\n\n"
        "🖐 <b>Qo'lingizdagi pulni sanab kiriting</b> (matn yoki ovozda, masalan: <code>1 500 000</code>):",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )


@router.callback_query(F.data == "close_day:recount")
async def cb_close_day_recount(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    async with async_session_maker() as db:
        summary = await compute_session_summary(db)
    await state.set_state(WalletStates.waiting_counted_cash)
    await state.update_data(session_id=summary.session.id)
    await cb.message.answer(
        "🖐 Qo'lingizdagi pulni qayta sanab kiriting:",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.message(WalletStates.waiting_counted_cash, F.chat.type == "private")
async def process_counted_cash(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message, ("admin",)):
        return
    counted: Optional[float] = None
    if message.voice or message.audio:
        try:
            audio_bytes, mime = await _download_voice_bytes(message)
        except VoiceTooLongError:
            await message.answer(f"⚠️ Ovozli xabar {MAX_VOICE_SECONDS} soniyadan oshmasligi kerak.")
            return
        parsed = await parse_voice_or_text(audio_bytes=audio_bytes, mime_type=mime)
        await maybe_warn_ai_limit(message.bot)
        counted = parsed.get("amount")
    elif message.text:
        txt = message.text.strip()
        if txt == "0":
            counted = 0.0
        else:
            counted = parse_uzbek_amount(txt)

    if counted is None or counted < 0:
        await message.answer(
            "⚠️ Summani tushunmadim. Raqam bilan yozing (masalan: <code>1 500 000</code> yoki <code>0</code>):",
            parse_mode="HTML",
        )
        return

    data = await state.get_data()
    session_id = data.get("session_id")
    async with async_session_maker() as db:
        summary = await compute_session_summary(db, session_id)

    diff = counted - summary.expected_cash
    if abs(diff) < 1:
        diff_msg = "✅ <b>Zo'r! Farq yo'q (0 so'm)</b>"
    elif diff < 0:
        diff_msg = f"⚠️ <b>Kamomad: {format_uzs(diff)} so'm</b>"
    else:
        diff_msg = f"➕ <b>Ortiqcha: +{format_uzs(diff)} so'm</b>"

    await state.clear()
    await message.answer(
        f"📊 <b>SVERKA NATIJASI ({summary.session.report_date})</b>\n"
        "===============================\n"
        f"💰 Qolishi kerak edi: <b>{format_uzs(summary.expected_cash)} so'm</b>\n"
        f"🖐 Siz sanadingiz: <b>{format_uzs(counted)} so'm</b>\n"
        f"⚖️ Farq: {diff_msg}\n"
        "===============================\n\n"
        "Agar xato bo'lsa, <b>✏️ Xatoni to'g'irlash</b> orqali nakladnoylarni tuzating va qayta kiriting. "
        "Hammasi joyida bo'lsa kunni yoping:",
        parse_mode="HTML",
        reply_markup=close_day_confirm_kb(summary.session.id, counted),
    )
    await message.answer("👇 Qaroringizni tanlang:", reply_markup=main_menu_keyboard())


@router.callback_query(F.data.startswith("close_day:confirm:"))
async def cb_close_day_confirm(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    parts = cb.data.split(":")
    sess_id = int(parts[2])
    counted = float(parts[3])

    async with async_session_maker() as db:
        existing = await compute_session_summary(db, sess_id)
        if existing.session.status == "closed":
            await cb.answer("Bu kun allaqachon yopilgan!", show_alert=True)
            return
        closed = await close_cash_session(db, sess_id, counted)
        kassa_group = await get_group_config(db, "kassa")

    diff = closed.session.difference or 0
    diff_line = (
        "✅ Farq yo'q (0)"
        if abs(diff) < 1
        else (f"⚠️ Kamomad: {format_uzs(diff)}" if diff < 0 else f"➕ Ortiqcha: +{format_uzs(diff)}")
    )

    summary_msg = (
        f"🏁 <b>KUN YOPILDI — {closed.session.report_date}</b>\n"
        "===============================\n"
        f"⏮ Boshlang'ich qoldiq: {format_uzs(closed.opening_balance)}\n"
        f"➕ Jami kirim: {format_uzs(closed.total_available_inflow)}\n"
        f"➖ Jami rasxod ({len(closed.confirmed_nakladnoys)} ta): {format_uzs(closed.total_nakladnoy_spent)}\n"
        f"💰 Qolishi kerak edi: {format_uzs(closed.expected_cash)}\n"
        f"🖐 Sanalgan qoldiq: <b>{format_uzs(counted)} so'm</b>\n"
        f"⚖️ {diff_line}\n"
        "==============================="
    )

    if kassa_group:
        try:
            await cb.bot.send_message(kassa_group.chat_id, summary_msg, parse_mode="HTML")
        except Exception:
            pass

    await _safe_edit_text(
        cb.message,
        f"{summary_msg}\n\n"
        f"💾 <b>History (Arxiv)ga saqlandi!</b>\n"
        f"➡️ Ertangi kunga <b>{format_uzs(counted)} so'm</b> qoldiq o'tdi. Nakladnoylar ro'yxati <b>0</b> dan boshlanadi.",
    )
    await cb.answer("✅ Kun yopildi!")


# ---------------------------------------------------------------------------
# Free-form Photo, Voice, and Deterministic Text Handlers (Private Chat Only)
# ---------------------------------------------------------------------------


@router.message(F.chat.type == "private", F.photo)
async def handle_any_photo(message: Message, state: FSMContext) -> None:
    """Any photo sent in private chat is processed as a Nakladnoy via dedup cache + Gemini Vision."""
    if await deny_if_unauthorized(message, ("admin", "kassir")):
        return
    await _process_nakladnoy_photo(message, state)


async def _handle_parsed_command(
    message: Message,
    state: FSMContext,
    intent: str,
    amount: Optional[float],
    supplier: Optional[str],
    raw_note: str,
    is_voice: bool = False,
) -> bool:
    """Execute a parsed voice or text command. Returns True if handled."""
    current_state = await state.get_state()
    if current_state == WalletStates.waiting_nakladnoy_input.state and amount and supplier:
        intent = "pay_supplier"

    voice_header = f"🎤 <i>«{html.escape(raw_note)}»</i>\n\n" if is_voice and raw_note else ""

    if intent == "status":
        await state.clear()
        async with async_session_maker() as db:
            summary = await compute_session_summary(db)
        await message.answer(
            voice_header + render_status_text(summary),
            parse_mode="HTML",
            reply_markup=status_actions_kb(
                summary.session.id, unpaid_debt_count=summary.all_unpaid_debt_count
            ),
        )
        return True

    if intent in ("cash_in", "kassa_debt", "kassa_repay") and amount and amount > 0:
        if await deny_if_unauthorized(message, ("admin", "kassir")):
            return True
        await state.clear()
        src_map = {"cash_in": "main", "kassa_debt": "kassa_debt", "kassa_repay": "kassa_repay"}
        lbl_map = {
            "cash_in": "Asosiy balansga qo'shildi",
            "kassa_debt": "Kassadan qarzga olindi",
            "kassa_repay": "Kassaga qaytarildi",
        }
        async with async_session_maker() as db:
            await add_cash_transaction(db, amount=amount, source_type=src_map[intent], note=raw_note)
            summary = await compute_session_summary(db)
        await message.answer(
            f"{voice_header}"
            f"✅ <b>{lbl_map[intent]}:</b> {format_uzs(amount)} so'm\n"
            f"💰 Qo'lda qolishi kerak: <b>{format_uzs(summary.expected_cash)} so'm</b>"
            + (
                f"\n⚠️ Jami kassa qarzi: <b>{format_uzs(summary.total_kassa_debt_outstanding)} so'm</b>"
                if summary.total_kassa_debt_outstanding > 0
                else ""
            ),
            parse_mode="HTML",
            reply_markup=main_menu_keyboard(),
        )
        return True

    if intent == "pay_supplier" and amount and amount > 0 and supplier:
        if await deny_if_unauthorized(message, ("admin", "kassir")):
            return True
        await _process_ready_nakladnoy(
            message=message,
            state=state,
            supplier_name=supplier,
            raw_amount=float(amount),
            photo_file_id=None,
            notes=raw_note,
            is_confident=True,
            prefix_html=voice_header,
        )
        return True

    return False


@router.message(F.chat.type == "private", F.voice | F.audio)
async def handle_any_voice(message: Message, state: FSMContext) -> None:
    """Understand voice commands naturally via Gemini Audio."""
    if await deny_if_unauthorized(message, ("admin", "kassir")):
        return

    try:
        audio_bytes, mime = await _download_voice_bytes(message)
    except VoiceTooLongError:
        await message.answer(
            f"⚠️ Ovozli xabar {MAX_VOICE_SECONDS} soniyadan oshmasligi kerak. Qisqaroq ayting yoki matnda yozing."
        )
        return

    wait_msg = await message.answer("🎤 Ovozli xabar eshitilmoqda...")
    try:
        parsed = await parse_voice_or_text(audio_bytes=audio_bytes, mime_type=mime)
        await maybe_warn_ai_limit(message.bot)
    finally:
        try:
            await wait_msg.delete()
        except Exception:
            pass

    if parsed.get("error_code") == "rate_limit":
        await message.answer("⏳ AI hozir band. Iltimos, matnda yozib yuboring (masalan: <i>«Non Oka 1 657 000»</i>).", parse_mode="HTML")
        return
    if parsed.get("error_code") in ("api_error", "no_key"):
        await message.answer("⚠️ Ovozli xabarni o'qib bo'lmadi. Iltimos, matnda yozib yuboring.", parse_mode="HTML")
        return

    intent = parsed.get("intent", "unknown")
    amount = parsed.get("amount")
    supplier = parsed.get("supplier_name")
    transcript = parsed.get("transcript", "")

    if await _handle_parsed_command(
        message, state, intent, amount, supplier, transcript, is_voice=True
    ):
        return

    await message.answer(
        f"🎤 Eshitildi: <i>«{html.escape(transcript or 'Tushunilmadi')}»</i>\n"
        "Aniq amal topilmadi. Misol uchun:\n"
        "• <i>«Pul oldim 21 million»</i>\n"
        "• <i>«Kassadan 3 million oldim»</i>\n"
        "• <i>«Non Oka 1 million 657 ming»</i>",
        parse_mode="HTML",
    )


@router.message(F.chat.type == "private", F.text)
async def handle_any_text(message: Message, state: FSMContext) -> None:
    """Understand free-form text commands deterministically (ZERO Gemini tokens)."""
    if not is_authorized(message.from_user.id if message.from_user else None):
        return
    txt = (message.text or "").strip()
    if not txt or txt.startswith("/"):
        return

    parsed = await parse_voice_or_text(text=txt)
    if await _handle_parsed_command(
        message,
        state,
        parsed.get("intent", "unknown"),
        parsed.get("amount"),
        parsed.get("supplier_name"),
        txt,
        is_voice=False,
    ):
        return

    await message.answer(
        "ℹ️ Tushunmadim. Quyidagi tugmalardan foydalaning yoki yozing:\n"
        "• <code>pure milky 354 000</code> (nakladnoy) 📸\n"
        "• <code>Pul oldim 21 000 000</code> (kirim) ➕\n"
        "• <code>Kassadan 3 000 000 oldim</code> (kassa qarz) 🏦\n"
        "• YesPOS CSV/Excel faylini tashlang 👑",
        parse_mode="HTML",
        reply_markup=main_menu_keyboard(),
    )
