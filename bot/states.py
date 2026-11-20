"""Aiogram FSM states for Hisobot Bot."""

from aiogram.fsm.state import State, StatesGroup


class WalletStates(StatesGroup):
    waiting_cash_in_amount = State()
    waiting_kassa_debt_amount = State()
    waiting_kassa_repay_amount = State()
    waiting_nakladnoy_input = State()
    waiting_quick_nakladnoy_amount = State()
    waiting_nakladnoy_clarify = State()
    waiting_edit_nakladnoy_amount = State()
    waiting_edit_nakladnoy_supplier = State()
    waiting_edit_cash_amount = State()
    waiting_counted_cash = State()
    waiting_excel_date_range = State()


class SettingsStates(StatesGroup):
    waiting_group_chat_id = State()
    waiting_supplier_name = State()
    waiting_supplier_category = State()
    waiting_supplier_aliases = State()
    waiting_append_alias = State()
    waiting_history_search = State()
    waiting_role_user_id = State()


class PrixodStates(StatesGroup):
    waiting_prixod_input = State()
    waiting_row_old_date = State()
    waiting_report_date = State()


class NasiyaStates(StatesGroup):
    waiting_debt_supplier = State()
    waiting_debt_amount = State()
    waiting_debt_note = State()
    waiting_pay_amount = State()
