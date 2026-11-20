"""Supplier credit/nasiya ledger handlers (/nasiya)."""

from __future__ import annotations

import html
from typing import Optional

from aiogram import F, Router
from aiogram.filters import Command
from aiogram.fsm.context import FSMContext
from aiogram.types import CallbackQuery, Message

from bot.auth import can_write_role, deny_if_unauthorized, is_admin_role
from bot.keyboards import (
    cancel_reply_keyboard,
    delete_confirm_kb,
    main_menu_keyboard,
    nasiya_history_kb,
    nasiya_main_kb,
    nasiya_supplier_kb,
)
from bot.states import NasiyaStates
from database.crud import (
    add_supplier_debt,
    delete_supplier_debt,
    format_local_dt,
    get_supplier_debt_balances,
    list_supplier_debt_entries,
)
from database.session import async_session_maker
from services.gemini_ai import format_uzs, parse_uzbek_amount


router = Router(name="nasiya")


async def _resolve_nasiya_supplier(state: FSMContext, idx: int) -> Optional[str]:
    data = await state.get_data()
    sups = data.get("nasiya_suppliers")
    if isinstance(sups, list) and 0 <= idx < len(sups):
        return sups[idx]
    async with async_session_maker() as db:
        balances = await get_supplier_debt_balances(db)
    if 0 <= idx < len(balances):
        return balances[idx]["supplier"]
    return None


async def _render_nasiya_home(user_id: int | None, state: FSMContext):
    async with async_session_maker() as db:
        balances = await get_supplier_debt_balances(db)
    await state.update_data(nasiya_suppliers=[b["supplier"] for b in balances])
    total_bal = sum(b["balance"] for b in balances)
    lines = ["📒 <b>Postavshiklarga Nasiya (Qarz) Daftari</b>\n"]
    if not balances:
        lines.append("<i>Hozircha nasiya yozuvlari yo'q.</i>")
    else:
        for b in balances[:15]:
            icon = "🔴" if b["balance"] > 0 else "✅"
            lines.append(
                f"{icon} <b>{html.escape(b['supplier'])}</b>: <b>{format_uzs(b['balance'])} so'm</b> "
                f"(olindi {format_uzs(b['debt'])} / berildi {format_uzs(b['paid'])})"
            )
        lines.append(f"\n💰 Jami qarz qoldig'i: <b>{format_uzs(total_bal)} so'm</b>")
    return "\n".join(lines), nasiya_main_kb(balances, can_write=can_write_role(user_id))


async def show_nasiya_home(target: Message | CallbackQuery, state: FSMContext) -> None:
    """Open Nasiya ledger from /nasiya or menu button."""
    if await deny_if_unauthorized(target):
        return
    uid = target.from_user.id if target.from_user else None
    text, kb = await _render_nasiya_home(uid, state)
    if isinstance(target, CallbackQuery):
        try:
            await target.message.edit_text(text, parse_mode="HTML", reply_markup=kb)
        except Exception:
            await target.message.answer(text, parse_mode="HTML", reply_markup=kb)
        await target.answer()
    else:
        await target.answer(text, parse_mode="HTML", reply_markup=kb)


@router.message(Command("nasiya"), F.chat.type == "private")
async def cmd_nasiya(message: Message, state: FSMContext) -> None:
    await state.clear()
    await show_nasiya_home(message, state)


@router.callback_query(F.data == "nasiya:home")
async def cb_nasiya_home(cb: CallbackQuery, state: FSMContext) -> None:
    await show_nasiya_home(cb, state)


@router.callback_query(F.data == "nasiya:add_debt")
async def cb_nasiya_add_debt(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin", "kassir")):
        return
    await state.set_state(NasiyaStates.waiting_debt_supplier)
    await state.update_data(nasiya_entry_type="debt")
    await cb.message.answer(
        "📒 Qaysi postavshikdan nasiyaga tovar oldingiz?\nNomini yozing (masalan: <code>OMBOR</code>):",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.message(NasiyaStates.waiting_debt_supplier, F.chat.type == "private")
async def process_nasiya_supplier(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message, ("admin", "kassir")):
        return
    sup = (message.text or "").strip()
    if len(sup) < 2:
        await message.answer("⚠️ Postavshik nomini kiriting:")
        return
    await state.update_data(nasiya_supplier=sup)
    await state.set_state(NasiyaStates.waiting_debt_amount)
    await message.answer(
        f"💰 <b>{html.escape(sup)}</b> uchun nasiya summasini kiriting (masalan: <code>2 500 000</code>):",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )


@router.callback_query(F.data.startswith("nasiya:sup:"))
async def cb_nasiya_supplier_detail(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb):
        return
    idx = int(cb.data.split(":")[-1])
    sup = await _resolve_nasiya_supplier(state, idx)
    if not sup:
        await cb.answer("Topilmadi", show_alert=True)
        return
    async with async_session_maker() as db:
        balances = await get_supplier_debt_balances(db)
        entries = await list_supplier_debt_entries(db, sup, limit=8)
    bal_item = next((b for b in balances if b["supplier"].lower() == sup.lower()), None)
    debt = bal_item["debt"] if bal_item else 0.0
    paid = bal_item["paid"] if bal_item else 0.0
    balance = bal_item["balance"] if bal_item else 0.0

    lines = [
        f"🏢 <b>{html.escape(sup)}</b> — Nasiya",
        f"📥 Jami qarzga olingan: <b>{format_uzs(debt)} so'm</b>",
        f"💵 Jami to'langan: <b>{format_uzs(paid)} so'm</b>",
        f"⚖️ <b>Qolgan qarz: {format_uzs(balance)} so'm</b>\n",
    ]
    if entries:
        lines.append("📜 <b>Oxirgi yozuvlar:</b>")
        for e in entries:
            icon = "➕" if e.entry_type == "debt" else "💵"
            note = f" ({html.escape(e.note[:25])})" if e.note else ""
            lines.append(f"• {format_local_dt(e.created_at, '%d.%m %H:%M')} {icon} <b>{format_uzs(e.amount)}</b>{note}")

    await cb.message.edit_text(
        "\n".join(lines),
        parse_mode="HTML",
        reply_markup=nasiya_supplier_kb(idx, can_write=can_write_role(cb.from_user.id)),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("nasiya:sup_debt:"))
async def cb_nasiya_sup_add_debt(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin", "kassir")):
        return
    idx = int(cb.data.split(":")[-1])
    sup = await _resolve_nasiya_supplier(state, idx)
    if not sup:
        await cb.answer("Topilmadi", show_alert=True)
        return
    await state.set_state(NasiyaStates.waiting_debt_amount)
    await state.update_data(nasiya_supplier=sup, nasiya_entry_type="debt")
    await cb.message.answer(
        f"➕ <b>{html.escape(sup)}</b> ga qancha nasiya (qarz) qo'shilsin?",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("nasiya:sup_pay:"))
async def cb_nasiya_sup_add_pay(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin", "kassir")):
        return
    idx = int(cb.data.split(":")[-1])
    sup = await _resolve_nasiya_supplier(state, idx)
    if not sup:
        await cb.answer("Topilmadi", show_alert=True)
        return
    await state.set_state(NasiyaStates.waiting_pay_amount)
    await state.update_data(nasiya_supplier=sup, nasiya_entry_type="payment")
    await cb.message.answer(
        f"💵 <b>{html.escape(sup)}</b> qarzidan qancha to'lov qilindi?",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.message(NasiyaStates.waiting_debt_amount, F.chat.type == "private")
@router.message(NasiyaStates.waiting_pay_amount, F.chat.type == "private")
async def process_nasiya_amount(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message, ("admin", "kassir")):
        return
    amt = parse_uzbek_amount(message.text or "")
    if not amt or amt <= 0:
        await message.answer("⚠️ Summa noto'g'ri. Raqam kiriting (masalan: `1 500 000`):")
        return
    await state.update_data(nasiya_amount=float(amt))
    await state.set_state(NasiyaStates.waiting_debt_note)
    await message.answer(
        "📝 Qisqa izoh yozing (yoki bo'sh qoldirish uchun <code>-</code> yozing):",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )


@router.message(NasiyaStates.waiting_debt_note, F.chat.type == "private")
async def process_nasiya_note(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message, ("admin", "kassir")):
        return
    note_raw = (message.text or "").strip()
    note = "" if note_raw in ("-", "yo'q", "yoq") else note_raw
    data = await state.get_data()
    sup = data.get("nasiya_supplier", "")
    amt = float(data.get("nasiya_amount", 0.0))
    entry_type = data.get("nasiya_entry_type", "debt")
    uid = message.from_user.id if message.from_user else None

    async with async_session_maker() as db:
        entry = await add_supplier_debt(db, sup, entry_type, amt, note=note, user_id=uid)
    await state.clear()

    lbl = "Nasiya (qarz) qo'shildi" if entry_type == "debt" else "Qarz to'lovi yozildi"
    await message.answer(
        f"✅ <b>{lbl}!</b>\n"
        f"🏢 Postavshik: <b>{html.escape(entry.supplier_name)}</b>\n"
        f"💰 Summa: <b>{format_uzs(entry.amount)} so'm</b>",
        parse_mode="HTML",
        reply_markup=main_menu_keyboard(),
    )
    await show_nasiya_home(message, state)


@router.callback_query(F.data == "nasiya:hist")
async def cb_nasiya_history(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb):
        return
    async with async_session_maker() as db:
        entries = await list_supplier_debt_entries(db, limit=15)
    if not entries:
        await cb.answer("Nasiya yozuvlari yo'q.", show_alert=True)
        return
    lines = ["📜 <b>Oxirgi Nasiya Yozuvlari:</b>\n"]
    for e in entries:
        icon = "➕ Qarz" if e.entry_type == "debt" else "💵 To'lov"
        note = f" — <i>{html.escape(e.note[:25])}</i>" if e.note else ""
        lines.append(
            f"• <code>{format_local_dt(e.created_at, '%d.%m %H:%M')}</code> "
            f"{icon}: <b>{html.escape(e.supplier_name)}</b> {format_uzs(e.amount)}{note}"
        )
    await cb.message.edit_text(
        "\n".join(lines),
        parse_mode="HTML",
        reply_markup=nasiya_history_kb(entries, is_admin=is_admin_role(cb.from_user.id)),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("nasiya:del:"))
async def cb_nasiya_delete_prompt(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    entry_id = int(cb.data.split(":")[-1])
    await cb.message.edit_text(
        f"⚠️ Nasiya yozuvi #{entry_id} ni rostdan ham o'chirilsinmi?",
        reply_markup=delete_confirm_kb(f"nasiya:del_yes:{entry_id}", "nasiya:hist"),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("nasiya:del_yes:"))
async def cb_nasiya_delete_confirm(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    entry_id = int(cb.data.split(":")[-1])
    uid = cb.from_user.id if cb.from_user else None
    async with async_session_maker() as db:
        deleted = await delete_supplier_debt(db, entry_id, user_id=uid)
    if not deleted:
        await cb.answer("Topilmadi", show_alert=True)
        return
    await cb.answer("🗑 O'chirildi")
    await cb_nasiya_history(cb)
