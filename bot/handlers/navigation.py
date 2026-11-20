"""Priority navigation router overriding any active FSM waiting state (X1, T2, T3)."""

from __future__ import annotations

from aiogram import F, Router
from aiogram.filters import Command, CommandStart, StateFilter
from aiogram.fsm.context import FSMContext
from aiogram.types import Message

from bot.auth import deny_if_unauthorized
from bot.handlers.prixod_itog import start_prixod_flow
from bot.handlers.settings_groups import cmd_start, open_more_menu, open_settings_menu
from bot.handlers.wallet_nakladnoy import (
    handle_add_nakladnoy_btn,
    handle_cash_in_button,
    handle_close_day_start,
    handle_edit_confirmed_btn,
    handle_kassa_debt_button,
    handle_status_button,
)
from bot.keyboards import (
    BTN_ADD_NAKLADNOY,
    BTN_CASH_IN,
    BTN_CLOSE_DAY,
    BTN_EDIT_CONFIRMED,
    BTN_KASSA_DEBT,
    BTN_MORE,
    BTN_PRIXOD,
    BTN_SETTINGS,
    BTN_STATUS,
    LEGACY_BTN_ADD_NAKLADNOY,
    LEGACY_BTN_STATUS,
    main_menu_keyboard,
)


router = Router(name="navigation")


@router.message(StateFilter("*"), CommandStart(), F.chat.type == "private")
async def nav_start(message: Message, state: FSMContext) -> None:
    await cmd_start(message, state)


@router.message(StateFilter("*"), Command("cancel"), F.chat.type == "private")
@router.message(StateFilter("*"), F.text == "❌ Bekor qilish", F.chat.type == "private")
async def nav_cancel(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message):
        return
    await state.clear()
    await message.answer("❌ Amal bekor qilindi.", reply_markup=main_menu_keyboard())


@router.message(StateFilter("*"), F.text.in_({BTN_ADD_NAKLADNOY, LEGACY_BTN_ADD_NAKLADNOY}), F.chat.type == "private")
async def nav_add_nakladnoy(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message):
        return
    await state.clear()
    await handle_add_nakladnoy_btn(message, state)


@router.message(StateFilter("*"), F.text == BTN_CASH_IN, F.chat.type == "private")
async def nav_cash_in(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message):
        return
    await state.clear()
    await handle_cash_in_button(message, state)


@router.message(StateFilter("*"), F.text.in_({BTN_STATUS, LEGACY_BTN_STATUS}), F.chat.type == "private")
async def nav_status(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message):
        return
    await handle_status_button(message, state)


@router.message(StateFilter("*"), F.text == BTN_MORE, F.chat.type == "private")
async def nav_more(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message):
        return
    await open_more_menu(message, state)


# Backward compatibility for users who still have old 8-button ReplyKeyboard cached
@router.message(StateFilter("*"), F.text == BTN_EDIT_CONFIRMED, F.chat.type == "private")
async def nav_legacy_edit(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message):
        return
    await handle_edit_confirmed_btn(message, state)


@router.message(StateFilter("*"), F.text == BTN_CLOSE_DAY, F.chat.type == "private")
async def nav_legacy_close_day(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message):
        return
    await state.clear()
    await handle_close_day_start(message, state)


@router.message(StateFilter("*"), F.text == BTN_PRIXOD, F.chat.type == "private")
async def nav_legacy_prixod(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message):
        return
    await state.clear()
    await start_prixod_flow(message, state)


@router.message(StateFilter("*"), F.text == BTN_KASSA_DEBT, F.chat.type == "private")
async def nav_legacy_kassa(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message):
        return
    await handle_kassa_debt_button(message, state)


@router.message(StateFilter("*"), F.text == BTN_SETTINGS, F.chat.type == "private")
async def nav_legacy_settings(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message):
        return
    await open_settings_menu(message, state)
