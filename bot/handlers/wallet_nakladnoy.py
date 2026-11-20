"""Daily cash wallet, Kassa debt, AI Nakladnoy photo/voice/text, Status, Edit confirmed, and Day Close handlers."""

from __future__ import annotations

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
    delete_confirm_kb,
    edit_items_list_kb,
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
    get_app_setting,
    get_group_config,
    get_kassa_debt_stats,
    get_nakladnoy,
    get_or_create_open_session,
    get_recent_amounts_for_supplier,
    get_recent_suppliers,
    record_ai_usage,
    resolve_supplier_name,
    round_nakladnoy_amount,
    set_nakladnoy_group_message,
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
    lines.append(f"• Sarflanish: <b>{spend_pct:.1f}%</b> ({count} ta to'lov)")
    if count > 0:
        lines.append(f"• O'rtacha to'lov: <b>{format_uzs(avg_amt)} so'm</b>")
    if top_payment is not None:
        lines.append(
            f"• Eng katta to'lov: <b>{html.escape(top_payment.supplier_name)}</b> — {format_uzs(top_payment.amount)}"
        )
    if count > 0:
        lines.append(f"• Guruhda / Shaxsiy bazada: 📤 {in_group_cnt} ta | 💾 {db_only_cnt} ta")
    lines.append(f"• Kassa qarzi qoldig'i: <b>{format_uzs(summary.total_kassa_debt_outstanding)} so'm</b>")

    result = "\n".join(lines)
    if len(result) > 4000:
        result = result[:3940] + "\n<i>...(to'liq ro'yxat Excel'da)</i>"
    return result


def render_nakladnoy_group_caption(
    payment: NakladnoyPayment, tag: str = ""
) -> str:
    """Build caption/message sent to the Nakladnoy Telegram group."""
    ts = format_local_dt(payment.created_at, "%d.%m.%Y %H:%M")
    prefix = f"{tag}\n" if tag else ""
    if payment.status == "deleted":
        return (
            f"❌ <b>[O'CHIRILDI / BEKOR QILINDI]</b>\n"
            f"📸 Nakladnoy #{payment.id}\n"
            f"🏢 Postavshik: <s>{html.escape(payment.supplier_name)}</s>\n"
            f"💰 Summa: <s>{format_uzs(payment.amount)} so'm</s>"
        )
    return (
        f"{prefix}📸 <b>Nakladnoy #{payment.id}</b>\n"
        f"🏢 Postavshik: <b>{html.escape(payment.supplier_name)}</b>\n"
        f"💰 Summa: <b>{format_uzs(payment.amount)} so'm</b>\n"
        f"📅 Vaqt: {ts}"
    )


async def _sync_nakladnoy_group_message(
    bot, payment: NakladnoyPayment, tag: str = "✏️ [TAHRIRLANDI]"
) -> tuple[bool, str]:
    """Update existing message in the Nakladnoy group if a confirmed payment was edited or deleted."""
    if not payment.group_chat_id or not payment.group_message_id:
        return False, "<i>(Bu nakladnoy hali guruhga yuborilmagan)</i>"
    new_caption = render_nakladnoy_group_caption(payment, tag=tag)
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
        reply_markup=status_actions_kb(summary.session.id),
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


async def handle_add_nakladnoy_btn(
    message: Message, state: FSMContext, actor_id: Optional[int] = None
) -> None:
    uid = actor_id if actor_id is not None else (message.from_user.id if message.from_user else None)
    if not can_write_role(uid):
        await message.answer("🔒 Bu amal faqat admin/kassir uchun.")
        return

    async with async_session_maker() as db:
        recents = await get_recent_suppliers(db, limit=6)

    await state.set_state(WalletStates.waiting_nakladnoy_input)
    await state.update_data(quick_suppliers=recents)
    prompt = (
        "📸 <b>Nakladnoy rasmini tashlang</b>\n"
        "<i>(Postavshik nomi rasmda bo'lmasa yoki xato bo'lsa, rasm tagiga nomini yozib tashlang — bot o'sha nomni oladi.)</i>\n\n"
        "Yoki matn/ovozda yozing: <i>«Non Oka 1 657 000»</i>\n"
        + ("👇 Yoki oxirgi postavshiklardan birini tanlang:" if recents else "")
    )
    await message.answer(
        prompt,
        parse_mode="HTML",
        reply_markup=quick_suppliers_kb(recents) if recents else cancel_reply_keyboard(),
    )


@router.callback_query(F.data == "qsup:cancel")
async def cb_quick_supplier_cancel(cb: CallbackQuery, state: FSMContext) -> None:
    await state.clear()
    await _safe_edit_text(cb.message, "❌ Amal bekor qilindi.")
    await cb.answer("Bekor qilindi")


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


async def _post_payment_to_group(bot, payment: NakladnoyPayment, nak_group) -> tuple[bool, str]:
    """Send a confirmed nakladnoy payment to the bound Nakladnoy group and save message ID."""
    caption = render_nakladnoy_group_caption(payment)
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
    return (
        f"📊 <b>Sizda natija shu:</b>\n"
        f"💵 Jami pul (kirim): <b>{format_uzs(summary.total_available_inflow)} so'm</b>\n"
        f"➖ Jami rasxod ({len(summary.confirmed_nakladnoys)} ta): <b>{format_uzs(summary.total_nakladnoy_spent)} so'm</b>\n"
        f"💰 <b>Qo'lda qolgani: {format_uzs(summary.expected_cash)} so'm</b>"
    )


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
        if can_auto:
            payment = await confirm_nakladnoy(db, payment.id, user_id=uid)

    await state.clear()

    if can_auto and payment is not None:
        posted = False
        if nak_group:
            posted, group_notice = await _post_payment_to_group(message.bot, payment, nak_group)
        else:
            group_notice = "<i>(Nakladnoy guruhi ulanmagan — faqat bazaga saqlandi)</i>"

        async with async_session_maker() as db:
            summary = await compute_session_summary(db, payment.session_id)

        round_line = ""
        if orig_amt is not None:
            round_line = f"🔄 Yaxlitlandi: <i>{format_uzs(orig_amt)} → {format_uzs(payment.amount)}</i>\n"
        await message.answer(
            f"{prefix_html}"
            f"⚡ <b>Avto-tasdiqlandi! (#{payment.id})</b>\n"
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
    cb: CallbackQuery, payment_id: int, send_to_group: bool
) -> None:
    """Confirm a pending nakladnoy payment, optionally posting it to the Nakladnoy group."""
    if await deny_if_unauthorized(cb, ("admin", "kassir")):
        return
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
        payment = await confirm_nakladnoy(db, payment_id, user_id=uid)

    missing_group_kb = None
    if not send_to_group:
        header = f"⏭ <b>Bazaga saqlandi! (#{payment.id})</b>"
        group_notice = "<i>(Guruhga yuborilmadi — faqat hisobingizga olindi)</i>"
    elif nak_group and payment:
        header = f"✅ <b>Tasdiqlandi! (#{payment.id})</b>"
        _, group_notice = await _post_payment_to_group(cb.bot, payment, nak_group)
    else:
        header = f"✅ <b>Tasdiqlandi! (#{payment.id})</b>"
        group_notice = "<i>(Nakladnoy guruhi ulanmagan — faqat hisobga olindi)</i>"
        username = await get_bot_username(cb.bot)
        missing_group_kb = InlineKeyboardMarkup(
            inline_keyboard=[
                [
                    InlineKeyboardButton(
                        text="➕ 📸 Nakladnoy guruhini hozir ulash (Admin)",
                        url=build_add_to_group_url(username, "nakladnoy"),
                    )
                ]
            ]
        )

    async with async_session_maker() as db:
        summary = await compute_session_summary(db, payment.session_id)

    await _safe_edit_text(
        cb.message,
        f"{header}\n"
        f"🏢 {html.escape(payment.supplier_name)} — <b>{format_uzs(payment.amount)} so'm</b>\n"
        f"{group_notice}\n\n"
        f"{_format_balance_summary_block(summary)}",
        reply_markup=missing_group_kb,
    )
    await cb.answer("✅ Saqlandi!")


@router.callback_query(F.data.startswith("nak:confirm:"))
async def cb_nakladnoy_confirm(cb: CallbackQuery) -> None:
    payment_id = int(cb.data.split(":")[-1])
    await _finalize_nakladnoy_confirmation(cb, payment_id, send_to_group=True)


@router.callback_query(F.data.startswith("nak:save_only:"))
async def cb_nakladnoy_save_only(cb: CallbackQuery) -> None:
    payment_id = int(cb.data.split(":")[-1])
    await _finalize_nakladnoy_confirmation(cb, payment_id, send_to_group=False)


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
        await _sync_nakladnoy_group_message(cb.bot, payment, tag="✏️ [NOM TAHRIRLANDI]")
        await _safe_edit_text(
            cb.message,
            f"✅ Birlashtirildi: <b>{html.escape(payment.supplier_name)}</b> — {format_uzs(payment.amount)} so'm",
            reply_markup=confirmed_nakladnoy_edit_kb(payment.id, in_group=in_group),
        )
    else:
        await _safe_edit_text(
            cb.message,
            _pending_card_text(payment, duplicate_warning=dup),
            reply_markup=nakladnoy_confirm_kb(payment.id),
        )
    await cb.answer("✅ Birlashtirildi!")


@router.callback_query(F.data.startswith("nak:back_card:"))
async def cb_nakladnoy_back_card(cb: CallbackQuery) -> None:
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
    await _safe_edit_text(
        cb.message,
        _pending_card_text(payment, duplicate_warning=dup, suggested_supplier=sug),
        reply_markup=nakladnoy_confirm_kb(payment.id, suggested_supplier=sug),
    )
    await cb.answer()


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
async def cb_nakladnoy_done(cb: CallbackQuery) -> None:
    """Collapse quick-edit buttons and show remaining balance summary."""
    payment_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
        if not payment or payment.status == "deleted":
            await cb.answer("Topilmadi", show_alert=True)
            return
        summary = await compute_session_summary(db, payment.session_id)

    where = "📤 Guruhga yuborilgan" if payment.group_message_id else "💾 Faqat shaxsiy hisobda"
    await _safe_edit_text(
        cb.message,
        f"✅ <b>Saqlandi! (#{payment.id})</b>\n"
        f"🏢 Postavshik: <b>{html.escape(payment.supplier_name)}</b>\n"
        f"💰 Summa: <b>{format_uzs(payment.amount)} so'm</b>\n"
        f"<i>({where})</i>\n\n"
        f"{_format_balance_summary_block(summary)}",
        reply_markup=None,
    )
    await cb.answer("✅ Tayyor!")


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
    await _safe_edit_text(
        cb.message,
        f"✅ <b>Bazada saqlangan (#{payment.id})</b>\n"
        f"🏢 Postavshik: <b>{html.escape(payment.supplier_name)}</b>\n"
        f"💰 Summa: <b>{format_uzs(payment.amount)} so'm</b>\n"
        f"{notice}\n\n"
        f"💵 Qo'lda qolishi kerak: <b>{format_uzs(summary.expected_cash)} so'm</b>",
        reply_markup=auto_confirmed_nakladnoy_kb(payment.id, sent_to_group=posted),
    )
    await cb.answer("📤 Yuborildi!")


@router.callback_query(F.data.startswith("nak:cancel:"))
async def cb_nakladnoy_cancel(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin", "kassir")):
        return
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
    if not payment or not payment.photo_file_id:
        await cb.answer("Bu yozuvda rasm saqlanmagan.", show_alert=True)
        return
    caption = render_nakladnoy_group_caption(payment)
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
    if not summary.confirmed_nakladnoys and not summary.cash_transactions:
        await message.answer("ℹ️ Bugungi ochiq smenada hali tahrirlanadigan yozuvlar yo'q.")
        return
    await message.answer(
        "✏️ <b>Tasdiqlanganlarni tahrirlash:</b>\n"
        "O'zgartirmoqchi yoki o'chirmoqchi bo'lgan yozuvni tanlang\n"
        "<i>(Nakladnoy o'zgartirilsa, guruhdagi xabar ham avtomat yangilanadi):</i>",
        parse_mode="HTML",
        reply_markup=edit_items_list_kb(summary.confirmed_nakladnoys, summary.cash_transactions),
    )


@router.callback_query(F.data == "edit_menu:open")
async def cb_edit_menu_open(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    async with async_session_maker() as db:
        summary = await compute_session_summary(db)
    if not summary.confirmed_nakladnoys and not summary.cash_transactions:
        await cb.answer("Bugungi smenada yozuvlar yo'q.", show_alert=True)
        return
    await _safe_edit_text(
        cb.message,
        "✏️ <b>Tasdiqlanganlarni tahrirlash:</b>\nKerakli qatorni tanlang:",
        reply_markup=edit_items_list_kb(summary.confirmed_nakladnoys, summary.cash_transactions),
    )
    await cb.answer()


@router.callback_query(F.data == "menu:dismiss")
async def cb_menu_dismiss(cb: CallbackQuery) -> None:
    try:
        await cb.message.delete()
    except Exception:
        pass
    await cb.answer()


@router.callback_query(F.data.startswith("nak_view:"))
async def cb_nakladnoy_edit_view(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    payment_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
    if not payment or payment.status == "deleted":
        await cb.answer("Topilmadi", show_alert=True)
        return
    in_group = bool(payment.group_chat_id and payment.group_message_id)
    group_state = (
        "📤 Guruhga yuborilgan (tahrirlasangiz u yerda ham yangilanadi)"
        if in_group
        else "💾 Faqat bazada (guruhga yuborilmagan)"
    )
    await _safe_edit_text(
        cb.message,
        f"📸 <b>Tasdiqlangan Nakladnoy #{payment.id}</b>\n"
        f"🏢 Postavshik: <b>{html.escape(payment.supplier_name)}</b>\n"
        f"💰 Summa: <b>{format_uzs(payment.amount)} so'm</b>\n"
        f"📍 Holat: <i>{group_state}</i>",
        reply_markup=confirmed_nakladnoy_edit_kb(payment.id, in_group=in_group),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("nak:edit_amt:"))
async def cb_nakladnoy_edit_amt_prompt(cb: CallbackQuery) -> None:
    """Open T5 quick-adjust amount buttons (-10k / -1k / +1k / +10k / Round / Manual)."""
    payment_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
    if not payment or payment.status == "deleted":
        await cb.answer("Topilmadi", show_alert=True)
        return
    allowed = ("admin",) if payment.status == "confirmed" else ("admin", "kassir")
    if await deny_if_unauthorized(cb, allowed):
        return
    await _safe_edit_text(
        cb.message,
        f"💰 <b>Summani tahrirlash (#{payment.id})</b>\n"
        f"🏢 Postavshik: <b>{html.escape(payment.supplier_name)}</b>\n"
        f"💵 Hozirgi summa: <b>{format_uzs(payment.amount)} so'm</b>\n\n"
        "Tez tugmalardan foydalaning yoki qo'lda kiriting:",
        reply_markup=nakladnoy_quick_amount_kb(payment.id, is_confirmed=(payment.status == "confirmed")),
    )
    await cb.answer()


async def _apply_quick_amount_change(cb: CallbackQuery, payment_id: int, mode: str, delta: int = 0) -> None:
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
        summary = await compute_session_summary(db, payment.session_id)

    sync_line = ""
    if payment.status == "confirmed":
        _, sync_msg = await _sync_nakladnoy_group_message(
            cb.bot, payment, tag="✏️ [SUMMA TAHRIRLANDI]"
        )
        sync_line = f"\n{sync_msg}\n💵 Qoldiq: <b>{format_uzs(summary.expected_cash)} so'm</b>"

    await _safe_edit_text(
        cb.message,
        f"✅ <b>Summa yangilandi (#{payment.id})</b>\n"
        f"🏢 Postavshik: <b>{html.escape(payment.supplier_name)}</b>\n"
        f"💰 Summa: <b>{format_uzs(payment.amount)} so'm</b>{sync_line}",
        reply_markup=nakladnoy_quick_amount_kb(payment.id, is_confirmed=(payment.status == "confirmed")),
    )
    await cb.answer(f"💰 {format_uzs(payment.amount)} so'm")


@router.callback_query(F.data.startswith("nak:adj:"))
async def cb_nakladnoy_quick_delta(cb: CallbackQuery) -> None:
    parts = cb.data.split(":")
    await _apply_quick_amount_change(cb, int(parts[2]), mode="delta", delta=int(parts[3]))


@router.callback_query(F.data.startswith("nak:adj_round:"))
async def cb_nakladnoy_quick_round(cb: CallbackQuery) -> None:
    payment_id = int(cb.data.split(":")[-1])
    await _apply_quick_amount_change(cb, payment_id, mode="round")


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
    await state.set_state(WalletStates.waiting_edit_nakladnoy_amount)
    await state.update_data(payment_id=payment_id)
    await cb.message.answer(
        "💰 Yangi summani yozing yoki ovozda ayting (masalan: <code>1 657 000</code>):",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.message(WalletStates.waiting_edit_nakladnoy_amount, F.chat.type == "private")
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
    if payment.status == "confirmed":
        in_group = bool(payment.group_chat_id and payment.group_message_id)
        _, sync_msg = await _sync_nakladnoy_group_message(
            message.bot, payment, tag="✏️ [SUMMA TAHRIRLANDI]"
        )
        await message.answer(
            f"✅ Summa yangilandi: <b>{html.escape(payment.supplier_name)} — {format_uzs(payment.amount)} so'm</b>\n"
            f"{sync_msg}\n"
            f"💰 Qo'lda qolishi kerak: <b>{format_uzs(summary.expected_cash)} so'm</b>",
            parse_mode="HTML",
            reply_markup=confirmed_nakladnoy_edit_kb(payment.id, in_group=in_group),
        )
        await message.answer("👇 Asosiy menyu:", reply_markup=main_menu_keyboard())
    else:
        await _send_pending_nakladnoy_card(message, payment)
        await message.answer("👇 Tasdiqlang:", reply_markup=main_menu_keyboard())


@router.callback_query(F.data.startswith("nak:edit_sup:"))
async def cb_nakladnoy_edit_sup_prompt(cb: CallbackQuery, state: FSMContext) -> None:
    payment_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        payment = await get_nakladnoy(db, payment_id)
    if not payment or payment.status == "deleted":
        await cb.answer("Topilmadi", show_alert=True)
        return
    allowed = ("admin",) if payment.status == "confirmed" else ("admin", "kassir")
    if await deny_if_unauthorized(cb, allowed):
        return
    await state.set_state(WalletStates.waiting_edit_nakladnoy_supplier)
    await state.update_data(payment_id=payment_id)
    await cb.message.answer(
        "🏢 Postavshikning yangi nomini yozing (masalan: <code>Non Oka</code>):",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.message(WalletStates.waiting_edit_nakladnoy_supplier, F.chat.type == "private")
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
    uid = message.from_user.id if message.from_user else None
    async with async_session_maker() as db:
        existing = await get_nakladnoy(db, payment_id)
        if existing and existing.status == "confirmed" and not is_admin_role(uid):
            await state.clear()
            await message.answer("🔒 Tasdiqlangan nomni o'zgartirish faqat admin uchun.", reply_markup=main_menu_keyboard())
            return
        canon, _ = await resolve_supplier_name(db, new_name)
        payment = await update_nakladnoy(db, payment_id, supplier_name=canon, user_id=uid)
    await state.clear()

    if not payment:
        await message.answer("⚠️ Topilmadi.", reply_markup=main_menu_keyboard())
        return

    if payment.status == "confirmed":
        in_group = bool(payment.group_chat_id and payment.group_message_id)
        _, sync_msg = await _sync_nakladnoy_group_message(
            message.bot, payment, tag="✏️ [NOM TAHRIRLANDI]"
        )
        await message.answer(
            f"✅ Postavshik yangilandi: <b>{html.escape(payment.supplier_name)} — {format_uzs(payment.amount)} so'm</b>\n"
            f"{sync_msg}",
            parse_mode="HTML",
            reply_markup=confirmed_nakladnoy_edit_kb(payment.id, in_group=in_group),
        )
        await message.answer("👇 Asosiy menyu:", reply_markup=main_menu_keyboard())
    else:
        await _send_pending_nakladnoy_card(message, payment)
        await message.answer("👇 Tasdiqlang:", reply_markup=main_menu_keyboard())


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

    _, sync_msg = await _sync_nakladnoy_group_message(cb.bot, payment)
    await _safe_edit_text(
        cb.message,
        f"🗑 Nakladnoy #{payment.id} ({html.escape(payment.supplier_name)} — {format_uzs(payment.amount)}) o'chirildi!\n"
        f"{sync_msg}\n"
        f"💰 Yangilangan qoldiq: <b>{format_uzs(summary.expected_cash)} so'm</b>",
    )
    await cb.answer("O'chirildi!")


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
            reply_markup=status_actions_kb(summary.session.id),
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
