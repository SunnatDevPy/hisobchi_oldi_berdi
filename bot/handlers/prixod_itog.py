"""Handlers for YesPOS Prixod (CSV/XLSX/Text) parsing and ITOG 👑 report management."""

from __future__ import annotations

import html
import io

from aiogram import F, Router
from aiogram.fsm.context import FSMContext
from aiogram.types import CallbackQuery, Message

from bot.handlers.settings_groups import is_authorized
from bot.keyboards import (
    BTN_PRIXOD,
    cancel_reply_keyboard,
    main_menu_keyboard,
    prixod_report_kb,
    prixod_row_category_kb,
    prixod_rows_kb,
)
from bot.states import PrixodStates
from database.crud import (
    get_group_config,
    get_prixod_report,
    list_suppliers,
    mark_prixod_published,
    save_prixod_report,
)
from database.models import PrixodReport, PrixodRow
from database.session import async_session_maker
from services.gemini_ai import format_uzs
from services.prixod_parser import (
    format_itog_report,
    parse_manual_itog_text,
    parse_yespos_table,
)


router = Router(name="prixod_itog")


def _build_prixod_preview_message(report: PrixodReport) -> str:
    """Format the full bot preview message for a PrixodReport."""
    margin_abs = (report.total_price or 0) - report.total_cost
    margin_info = ""
    if report.total_price and report.total_price > 0:
        pct = (margin_abs / report.total_cost * 100) if report.total_cost > 0 else 0
        margin_info = (
            f"\n\n📊 <b>Qo'shimcha tahlil (YesPOS):</b>\n"
            f"• Tannarx (Стоимость): <b>{format_uzs(report.total_cost)}</b> so'm\n"
            f"• Sotuv narx (Цена): <b>{format_uzs(report.total_price)}</b> so'm\n"
            f"• Kutilayotgan ustama: <b>+{format_uzs(margin_abs)}</b> so'm ({pct:.1f}%)"
        )
    status_badge = "✅ <i>Prixod guruhiga yuborilgan</i>" if report.status == "published" else "📝 <i>Tasdiqlash kutilmoqda</i>"
    return (
        f"👑 <b>Tayyor Prixod Hisoboti</b> ({status_badge})\n\n"
        f"<pre>{html.escape(report.formatted_text)}</pre>"
        f"{margin_info}"
    )


async def _recompute_and_save_report(report_id: int) -> PrixodReport | None:
    """Re-format ITOG text from DB rows and persist."""
    async with async_session_maker() as db:
        report = await get_prixod_report(db, report_id)
        if not report:
            return None
        suppliers = await list_suppliers(db, active_only=True)
        new_text = format_itog_report(report.report_date, report.rows, suppliers)
        report.formatted_text = new_text
        report.total_cost = sum(r.cost for r in report.rows)
        report.total_price = sum(r.price for r in report.rows)
        await db.commit()
        return await get_prixod_report(db, report_id)


@router.message(F.text == BTN_PRIXOD, F.chat.type == "private")
async def start_prixod_flow(message: Message, state: FSMContext) -> None:
    """Prompt user to upload YesPOS CSV/XLSX or paste manual text."""
    if not is_authorized(message.from_user.id if message.from_user else None):
        return
    await state.set_state(PrixodStates.waiting_prixod_input)
    await message.answer(
        "👑 <b>Kunlik Prixod (ITOG) tayyorlash</b>\n\n"
        "1️⃣ YesPOS'dan yuklangan <b>«Документы о приемке товара»</b> faylini (<code>.csv</code> yoki <code>.xlsx</code>) shu yerga tashlang.\n"
        "2️⃣ Yoki qo'lda yozilgan matnni yuboring (masalan: <code>1) OMBOR 12 895 000 + 2 109 750</code> ...).\n\n"
        "Bot o'zi asosiy qarz ta'minotchilarini, karta va eski sanalarni ajratib hisoblab beradi!",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )


def _rows_to_payload(rows) -> list[dict]:
    """Convert ParsedRowItem sequence into dict payloads for DB persistence."""
    return [
        {
            "row_num": r.row_num,
            "supplier_raw": r.supplier_raw,
            "supplier_display": r.supplier_display,
            "note_raw": r.note_raw,
            "cost": r.cost,
            "price": r.price,
            "category": r.category,
            "old_date_label": r.old_date_label,
            "created_at_str": r.created_at_str,
        }
        for r in rows
    ]


@router.message(
    F.chat.type == "private",
    F.document,
    F.document.file_name.lower().endswith((".csv", ".xlsx", ".xlsm")),
)
async def handle_yespos_document(message: Message, state: FSMContext) -> None:
    """Accept YesPOS CSV/XLSX file anytime in private chat or in PrixodStates."""
    if not is_authorized(message.from_user.id if message.from_user else None):
        return

    doc = message.document
    filename = doc.file_name or "prixod.csv"
    buf = io.BytesIO()
    await message.bot.download(doc, destination=buf)
    file_bytes = buf.getvalue()

    async with async_session_maker() as db:
        suppliers = await list_suppliers(db, active_only=True)
        try:
            parsed = parse_yespos_table(file_bytes, filename, suppliers)
        except Exception as exc:
            await message.answer(f"⚠️ Faylni o'qishda xatolik: {exc}")
            return

        report = await save_prixod_report(
            db,
            report_date=parsed.report_date,
            total_cost=parsed.total_cost,
            total_price=parsed.total_price,
            formatted_text=parsed.formatted_text,
            rows_data=_rows_to_payload(parsed.rows),
        )

    await state.clear()
    await message.answer(
        _build_prixod_preview_message(report),
        parse_mode="HTML",
        reply_markup=prixod_report_kb(report.id, is_published=False),
    )
    await message.answer(
        "👆 Agar <b>karta</b> yoki <b>boshqa sana</b>ga o'tkaziladigan qator bo'lsa, "
        "<b>«🎛 Qatorlarni sozlash»</b> tugmasini bosing. Hammasi to'g'ri bo'lsa guruhga yuboring.",
        parse_mode="HTML",
        reply_markup=main_menu_keyboard(),
    )


@router.message(PrixodStates.waiting_prixod_input, F.chat.type == "private", F.text)
async def handle_manual_prixod_text(message: Message, state: FSMContext) -> None:
    """Parse manually typed or pasted ITOG text."""
    if not is_authorized(message.from_user.id if message.from_user else None):
        return
    raw_text = (message.text or "").strip()
    if not raw_text:
        return

    async with async_session_maker() as db:
        suppliers = await list_suppliers(db, active_only=True)
        try:
            parsed = parse_manual_itog_text(raw_text, suppliers)
        except Exception as exc:
            await message.answer(f"⚠️ Matnni tushunib bo'lmadi: {exc}")
            return

        report = await save_prixod_report(
            db,
            report_date=parsed.report_date,
            total_cost=parsed.total_cost,
            total_price=parsed.total_price,
            formatted_text=parsed.formatted_text,
            rows_data=_rows_to_payload(parsed.rows),
        )

    await state.clear()
    await message.answer(
        _build_prixod_preview_message(report),
        parse_mode="HTML",
        reply_markup=prixod_report_kb(report.id, is_published=False),
    )
    await message.answer("👇 Kerakli tugmani tanlang:", reply_markup=main_menu_keyboard())


@router.callback_query(F.data.startswith("prx:view:"))
async def cb_prixod_view(cb: CallbackQuery) -> None:
    rep_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        report = await get_prixod_report(db, rep_id)
    if not report:
        await cb.answer("Hisobot topilmadi", show_alert=True)
        return
    await cb.message.edit_text(
        _build_prixod_preview_message(report),
        parse_mode="HTML",
        reply_markup=prixod_report_kb(report.id, is_published=(report.status == "published")),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("prx:rows:"))
async def cb_prixod_rows_page(cb: CallbackQuery) -> None:
    parts = cb.data.split(":")
    rep_id = int(parts[2])
    page = int(parts[3])
    async with async_session_maker() as db:
        report = await get_prixod_report(db, rep_id)
    if not report:
        await cb.answer("Topilmadi", show_alert=True)
        return
    await cb.message.edit_text(
        f"🎛 <b>Prixod qatorlari ({report.report_date})</b>\n"
        "📌 = Qarz | 📋 = Nakladnoy | 💳 = Karta | 📅 = Eski sana\n"
        "Toifasini o'zgartirish uchun qatorni bosing:",
        parse_mode="HTML",
        reply_markup=prixod_rows_kb(rep_id, report.rows, page=page),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("prx:row:"))
async def cb_prixod_row_detail(cb: CallbackQuery) -> None:
    parts = cb.data.split(":")
    rep_id, row_id, page = int(parts[2]), int(parts[3]), int(parts[4])
    async with async_session_maker() as db:
        row = await db.get(PrixodRow, row_id)
    if not row:
        await cb.answer("Qator topilmadi", show_alert=True)
        return
    await cb.message.edit_text(
        f"📦 <b>{html.escape(row.supplier_raw)}</b>\n"
        f"💰 Tannarx: <b>{format_uzs(row.cost)}</b> so'm\n"
        f"📝 Izoh: <i>{html.escape(row.note_raw or '-')}</i>\n"
        f"🏷 Hozirgi toifa: <b>{row.category.upper()}</b>"
        + (f" ({row.old_date_label})" if row.old_date_label else ""),
        parse_mode="HTML",
        reply_markup=prixod_row_category_kb(rep_id, row_id, page),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("prx:setcat:"))
async def cb_prixod_set_row_cat(cb: CallbackQuery) -> None:
    parts = cb.data.split(":")
    rep_id, row_id, new_cat, page = int(parts[2]), int(parts[3]), parts[4], int(parts[5])
    async with async_session_maker() as db:
        row = await db.get(PrixodRow, row_id)
        if not row:
            await cb.answer("Qator topilmadi", show_alert=True)
            return
        row.category = new_cat
        if new_cat != "old_date":
            row.old_date_label = None
        await db.commit()

    report = await _recompute_and_save_report(rep_id)
    if not report:
        return
    await cb.answer(f"✅ Toifa o'zgartirildi: {new_cat}")
    await cb.message.edit_text(
        f"🎛 <b>Prixod qatorlari ({report.report_date})</b>\n"
        "Qator yangilandi! Yana o'zgartirishingiz yoki hisobotga qaytishingiz mumkin:",
        parse_mode="HTML",
        reply_markup=prixod_rows_kb(rep_id, report.rows, page=page),
    )


@router.callback_query(F.data.startswith("prx:setold:"))
async def cb_prixod_set_old_date_prompt(cb: CallbackQuery, state: FSMContext) -> None:
    parts = cb.data.split(":")
    rep_id, row_id, page = int(parts[2]), int(parts[3]), int(parts[4])
    await state.set_state(PrixodStates.waiting_row_old_date)
    await state.update_data(rep_id=rep_id, row_id=row_id, page=page)
    await cb.message.answer(
        "📅 Qaysi sanaga tegishli? Qisqa sana yozing (masalan: <code>16.11</code>):",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.message(PrixodStates.waiting_row_old_date, F.chat.type == "private")
async def process_row_old_date(message: Message, state: FSMContext) -> None:
    if not is_authorized(message.from_user.id if message.from_user else None):
        return
    lbl = (message.text or "").strip()
    if not lbl:
        await message.answer("⚠️ Sana kiriting (masalan: 16.11).")
        return
    data = await state.get_data()
    rep_id, row_id = data["rep_id"], data["row_id"]

    async with async_session_maker() as db:
        row = await db.get(PrixodRow, row_id)
        if row:
            row.category = "old_date"
            row.old_date_label = lbl
            await db.commit()

    await state.clear()
    report = await _recompute_and_save_report(rep_id)
    if report:
        await message.answer(
            _build_prixod_preview_message(report),
            parse_mode="HTML",
            reply_markup=prixod_report_kb(report.id, is_published=(report.status == "published")),
        )
    await message.answer("✅ Sana qo'shildi.", reply_markup=main_menu_keyboard())


@router.callback_query(F.data.startswith("prx:date:"))
async def cb_prixod_change_date_prompt(cb: CallbackQuery, state: FSMContext) -> None:
    rep_id = int(cb.data.split(":")[-1])
    await state.set_state(PrixodStates.waiting_report_date)
    await state.update_data(rep_id=rep_id)
    await cb.message.answer(
        "📅 Yangi hisobot sanasini yozing (masalan: <code>17.11.26</code>):",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.message(PrixodStates.waiting_report_date, F.chat.type == "private")
async def process_prixod_change_date(message: Message, state: FSMContext) -> None:
    if not is_authorized(message.from_user.id if message.from_user else None):
        return
    new_date = (message.text or "").strip()
    if not new_date:
        return
    data = await state.get_data()
    rep_id = data["rep_id"]

    async with async_session_maker() as db:
        report = await get_prixod_report(db, rep_id)
        if report:
            report.report_date = new_date
            await db.commit()

    await state.clear()
    report = await _recompute_and_save_report(rep_id)
    if report:
        await message.answer(
            _build_prixod_preview_message(report),
            parse_mode="HTML",
            reply_markup=prixod_report_kb(report.id, is_published=(report.status == "published")),
        )
    await message.answer("✅ Sana yangilandi.", reply_markup=main_menu_keyboard())


@router.callback_query(F.data.startswith("prx:publish:"))
async def cb_prixod_publish(cb: CallbackQuery) -> None:
    rep_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        report = await get_prixod_report(db, rep_id)
        prixod_group = await get_group_config(db, "prixod")
    if not report:
        await cb.answer("Hisobot topilmadi", show_alert=True)
        return
    if not prixod_group:
        await cb.answer(
            "Prixod guruhi ulanmagan! Guruhga botni qo'shib /set_prixod_group yozing.",
            show_alert=True,
        )
        return

    text_to_send = report.formatted_text
    try:
        if report.group_chat_id and report.group_message_id and report.group_chat_id == prixod_group.chat_id:
            await cb.bot.edit_message_text(
                chat_id=report.group_chat_id,
                message_id=report.group_message_id,
                text=text_to_send,
            )
            msg_id = report.group_message_id
        else:
            sent = await cb.bot.send_message(chat_id=prixod_group.chat_id, text=text_to_send)
            msg_id = sent.message_id
    except Exception as exc:
        await cb.answer(f"Guruhga yuborishda xato: {exc}", show_alert=True)
        return

    async with async_session_maker() as db:
        updated = await mark_prixod_published(
            db,
            report_id=rep_id,
            formatted_text=text_to_send,
            group_chat_id=prixod_group.chat_id,
            group_message_id=msg_id,
        )

    await cb.message.edit_text(
        _build_prixod_preview_message(updated),
        parse_mode="HTML",
        reply_markup=prixod_report_kb(rep_id, is_published=True),
    )
    await cb.answer("✅ Prixod guruhiga yuborildi!")
