"""Reply and inline keyboards for Hisobot Bot."""

from __future__ import annotations

from typing import Optional, Sequence

from aiogram.types import (
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    KeyboardButton,
    ReplyKeyboardMarkup,
    WebAppInfo,
)

from bot.auth import ROLE_ADMIN, ROLE_KASSIR, ROLE_LABELS
from config import get_settings
from database.models import (
    CashTransaction,
    DailyCashSession,
    NakladnoyPayment,
    PrixodReport,
    PrixodRow,
    SupplierConfig,
    SupplierDebt,
    UserRole,
)
from services.gemini_ai import format_uzs


# Primary 2x2 bottom menu buttons (T2)
BTN_ADD_NAKLADNOY = "📸 Nakladnoy"
BTN_CASH_IN = "➕ Pul oldim"
BTN_STATUS = "📊 Status"
BTN_MORE = "⚙️ Boshqa"

# Legacy bottom button texts still accepted cleanly by navigation.py
LEGACY_BTN_ADD_NAKLADNOY = "📸 Nakladnoy qo'shish"
LEGACY_BTN_STATUS = "📊 Status (Hisob)"
BTN_EDIT_CONFIRMED = "✏️ Tahrirlash"
BTN_CLOSE_DAY = "🏁 Kunni yakunlash"
BTN_PRIXOD = "👑 Prixod (ITOG)"
BTN_KASSA_DEBT = "🏦 Kassa qarzi"
BTN_SETTINGS = "⚙️ Sozlamalar & History"


def main_menu_keyboard() -> ReplyKeyboardMarkup:
    """Compact 2x2 persistent bottom menu."""
    return ReplyKeyboardMarkup(
        keyboard=[
            [KeyboardButton(text=BTN_ADD_NAKLADNOY), KeyboardButton(text=BTN_CASH_IN)],
            [KeyboardButton(text=BTN_STATUS), KeyboardButton(text=BTN_MORE)],
        ],
        resize_keyboard=True,
    )


def cancel_reply_keyboard() -> ReplyKeyboardMarkup:
    """Simple cancel keyboard during FSM inputs."""
    return ReplyKeyboardMarkup(
        keyboard=[[KeyboardButton(text="❌ Bekor qilish")]],
        resize_keyboard=True,
    )


def delete_confirm_kb(confirm_cb: str, cancel_cb: str) -> InlineKeyboardMarkup:
    """Generic 2-step delete confirmation prompt (T4)."""
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(text="✅ Ha, o'chirilsin", callback_data=confirm_cb),
                InlineKeyboardButton(text="❌ Yo'q, qolsin", callback_data=cancel_cb),
            ]
        ]
    )


def get_webapp_url() -> Optional[str]:
    """Return HTTPS URL of the Telegram Mini App if API_PUBLIC_URL is HTTPS."""
    pub = (get_settings().API_PUBLIC_URL or "").strip().rstrip("/")
    if pub.startswith("https://"):
        return f"{pub}/webapp/"
    return None


def more_menu_kb(role: str = ROLE_ADMIN, show_webapp: bool = False) -> InlineKeyboardMarkup:
    """Streamlined operations & settings hub opened from ⚙️ Boshqa."""
    rows: list[list[InlineKeyboardButton]] = []
    if show_webapp:
        webapp_url = get_webapp_url()
        if webapp_url:
            rows.append(
                [
                    InlineKeyboardButton(
                        text="🚀 Hisobchi ilovasini ochish (Mini App)",
                        web_app=WebAppInfo(url=webapp_url),
                    )
                ]
            )
    if role in (ROLE_ADMIN, ROLE_KASSIR):
        rows.append(
            [
                InlineKeyboardButton(text="👑 Prixod (ITOG)", callback_data="more:prixod"),
                InlineKeyboardButton(text="📥 Excel hisobotlar", callback_data="export:menu"),
            ]
        )
    else:
        rows.append(
            [
                InlineKeyboardButton(text="📥 Excel hisobotlar", callback_data="export:menu"),
            ]
        )
    rows.append(
        [
            InlineKeyboardButton(
                text="⚖️ Kassa sverka (Oraliq / Asosiy)",
                callback_data="more:kassa_sverka",
            )
        ]
    )
    if role == ROLE_ADMIN:
        rows.append(
            [
                InlineKeyboardButton(text="🏁 Kunni yakunlash", callback_data="more:close_day"),
                InlineKeyboardButton(text="🔗 Guruhlar va Sozlamalar", callback_data="more:settings"),
            ]
        )
    rows.append(
        [
            InlineKeyboardButton(text="📱 Mobil ilova (APK)", callback_data="apk:home"),
            InlineKeyboardButton(text="🔙 Yopish", callback_data="menu:dismiss"),
        ]
    )
    return InlineKeyboardMarkup(inline_keyboard=rows)


def nakladnoy_confirm_kb(
    payment_id: int,
    suggested_supplier: Optional[str] = None,
    suggested_calc_amount: Optional[float] = None,
) -> InlineKeyboardMarkup:
    """Confirmation inline keyboard for a pending nakladnoy payment."""
    rows: list[list[InlineKeyboardButton]] = []
    if suggested_calc_amount is not None and suggested_calc_amount > 0:
        calc_int = int(round(suggested_calc_amount))
        calc_lbl = f"{calc_int:,}".replace(",", " ")
        rows.append(
            [
                InlineKeyboardButton(
                    text=f"🧮 To'g'ri summa ({calc_lbl}) bilan tasdiqlash",
                    callback_data=f"nak:use_calc:{payment_id}:{calc_int}",
                )
            ]
        )
        rows.append(
            [
                InlineKeyboardButton(
                    text=f"🔄 Summani {calc_lbl} ga almashtirish",
                    callback_data=f"nak:set_calc:{payment_id}:{calc_int}",
                )
            ]
        )
    if suggested_supplier:
        rows.append(
            [
                InlineKeyboardButton(
                    text=f"✅ «{suggested_supplier[:22]}» qilib tasdiqlash",
                    callback_data=f"nak:confirm_sup:{payment_id}",
                )
            ]
        )
        rows.append(
            [
                InlineKeyboardButton(
                    text=f"✨ «{suggested_supplier[:24]}» ga birlashtirish",
                    callback_data=f"nak:use_sup:{payment_id}",
                )
            ]
        )
    rows.extend(
        [
            [
                InlineKeyboardButton(
                    text="✅ Tasdiqlash (Guruhga yuborish)",
                    callback_data=f"nak:confirm:{payment_id}",
                )
            ],
            [
                InlineKeyboardButton(
                    text="⏭ O'tkazib yuborish (Faqat bazaga saqlash)",
                    callback_data=f"nak:save_only:{payment_id}",
                )
            ],
            [
                InlineKeyboardButton(
                    text="📌 Qarzga",
                    callback_data=f"nak:save_debt:{payment_id}",
                ),
                InlineKeyboardButton(
                    text="💳 Karta",
                    callback_data=f"nak:save_pm:{payment_id}:card",
                ),
                InlineKeyboardButton(
                    text="🏦 O'tkazma",
                    callback_data=f"nak:save_pm:{payment_id}:transfer",
                ),
            ],
            [
                InlineKeyboardButton(
                    text="💰 Summani o'zgartirish",
                    callback_data=f"nak:edit_amt:{payment_id}",
                ),
                InlineKeyboardButton(
                    text="🏢 Postavshikni o'zgartirish",
                    callback_data=f"nak:edit_sup:{payment_id}",
                ),
            ],
            [
                InlineKeyboardButton(
                    text="❌ Bekor qilish",
                    callback_data=f"nak:cancel:{payment_id}",
                )
            ],
        ]
    )
    return InlineKeyboardMarkup(inline_keyboard=rows)


def _payment_method_row(
    payment_id: int, current_pm: str = "cash", include_cash: bool = True
) -> list[InlineKeyboardButton]:
    """Row of payment-mode selector buttons with active-state checkmark."""
    cur = (current_pm or "cash").strip().lower()
    items = (
        [("cash", "💵 Naqd"), ("card", "💳 Karta"), ("transfer", "🏦 O'tkazma")]
        if include_cash
        else [("card", "💳 Karta"), ("transfer", "🏦 O'tkazma")]
    )
    return [
        InlineKeyboardButton(
            text=(f"✅ {lbl}" if include_cash and cur == key else lbl),
            callback_data=f"nak:set_pm:{payment_id}:{key}",
        )
        for key, lbl in items
    ]


def auto_confirmed_nakladnoy_kb(
    payment_id: int,
    sent_to_group: bool = True,
    suggested_supplier: Optional[str] = None,
    is_debt: bool = False,
    payment_method: str = "cash",
) -> InlineKeyboardMarkup:
    """Quick edit/undo/debt/payment-mode controls shown after instant auto-confirmation."""
    rows: list[list[InlineKeyboardButton]] = []
    if suggested_supplier:
        rows.append(
            [
                InlineKeyboardButton(
                    text=f"✨ «{suggested_supplier[:24]}» ga birlashtirish",
                    callback_data=f"nak:use_sup:{payment_id}",
                )
            ]
        )
    rows.extend(
        [
            [
                InlineKeyboardButton(
                    text="💰 Summa",
                    callback_data=f"nak:edit_amt:{payment_id}",
                ),
                InlineKeyboardButton(
                    text="🏢 Postavshik",
                    callback_data=f"nak:edit_sup:{payment_id}",
                ),
            ],
            [
                InlineKeyboardButton(
                    text="🙈 Guruhdan olish (Faqat baza)" if sent_to_group else "📤 Guruhga yuborish",
                    callback_data=f"nak:unpost_group:{payment_id}"
                    if sent_to_group
                    else f"nak:repost_group:{payment_id}",
                ),
                InlineKeyboardButton(
                    text="🗑 O'chirish",
                    callback_data=f"nak:delete_conf:{payment_id}",
                ),
            ],
        ]
    )
    if is_debt:
        rows.append(
            [
                InlineKeyboardButton(
                    text="💵 To'landi (Pul berildi)",
                    callback_data=f"nak:mark_paid:{payment_id}",
                )
            ]
        )
        rows.append(_payment_method_row(payment_id, payment_method, include_cash=False))
    else:
        rows.append(_payment_method_row(payment_id, payment_method, include_cash=True))
        rows.append(
            [
                InlineKeyboardButton(
                    text="📌 Qarzga (Pul berilmadi)",
                    callback_data=f"nak:mark_debt:{payment_id}",
                )
            ]
        )
    rows.append(
        [
            InlineKeyboardButton(
                text="✅ Tayyor",
                callback_data=f"nak:done:{payment_id}",
            )
        ]
    )
    return InlineKeyboardMarkup(inline_keyboard=rows)


def nakladnoy_quick_amount_kb(payment_id: int, is_confirmed: bool = True) -> InlineKeyboardMarkup:
    """Quick step adjustments (-10k/-1k/+1k/+10k/round) with direct manual/voice input (T5)."""
    back_cb = f"nak_view:{payment_id}" if is_confirmed else f"nak:back_card:{payment_id}"
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(text="−10 000", callback_data=f"nak:adj:{payment_id}:-10000"),
                InlineKeyboardButton(text="−1 000", callback_data=f"nak:adj:{payment_id}:-1000"),
                InlineKeyboardButton(text="+1 000", callback_data=f"nak:adj:{payment_id}:1000"),
                InlineKeyboardButton(text="+10 000", callback_data=f"nak:adj:{payment_id}:10000"),
            ],
            [
                InlineKeyboardButton(text="🔄 Yaxlitlash", callback_data=f"nak:adj_round:{payment_id}"),
                InlineKeyboardButton(text="⬅️ Orqaga", callback_data=back_cb),
            ],
        ]
    )


SUPPLIERS_PAGE_SIZE = 16


def _paginated_supplier_rows(
    suppliers: Sequence[str],
    page: int,
    item_cb_prefix: str,
    page_cb_prefix: str,
    page_size: int = SUPPLIERS_PAGE_SIZE,
) -> list[list[InlineKeyboardButton]]:
    """Render 2-column supplier picker grid with pagination controls when needed."""
    rows: list[list[InlineKeyboardButton]] = []
    if not suppliers:
        return rows
    total_pages = max(1, (len(suppliers) + page_size - 1) // page_size)
    page = max(0, min(page, total_pages - 1))
    start = page * page_size
    end = min(start + page_size, len(suppliers))

    pair: list[InlineKeyboardButton] = []
    for offset, name in enumerate(suppliers[start:end]):
        idx = start + offset
        pair.append(
            InlineKeyboardButton(
                text=f"🏢 {name[:20]}",
                callback_data=f"{item_cb_prefix}:{idx}",
            )
        )
        if len(pair) == 2:
            rows.append(pair)
            pair = []
    if pair:
        rows.append(pair)

    if total_pages > 1:
        nav: list[InlineKeyboardButton] = []
        if page > 0:
            nav.append(InlineKeyboardButton(text="⬅️ Oldingi", callback_data=f"{page_cb_prefix}:{page - 1}"))
        nav.append(InlineKeyboardButton(text=f"{page + 1}/{total_pages}", callback_data="noop"))
        if page < total_pages - 1:
            nav.append(InlineKeyboardButton(text="Keyingi ➡️", callback_data=f"{page_cb_prefix}:{page + 1}"))
        rows.append(nav)
    return rows


def quick_suppliers_kb(
    suppliers: Sequence[str],
    page: int = 0,
    page_size: int = SUPPLIERS_PAGE_SIZE,
) -> InlineKeyboardMarkup:
    """Paginated known-supplier quick-pick buttons when adding a nakladnoy."""
    rows = _paginated_supplier_rows(
        suppliers,
        page=page,
        item_cb_prefix="qsup",
        page_cb_prefix="qsup:page",
        page_size=page_size,
    )
    rows.append([InlineKeyboardButton(text="❌ Bekor qilish", callback_data="qsup:cancel")])
    return InlineKeyboardMarkup(inline_keyboard=rows)


def edit_supplier_pick_kb(
    payment_id: int,
    suppliers: Sequence[str],
    is_confirmed: bool = True,
    page: int = 0,
    page_size: int = SUPPLIERS_PAGE_SIZE,
) -> InlineKeyboardMarkup:
    """Paginated supplier selector for editing a nakladnoy alongside direct text/voice input."""
    back_cb = f"nak_view:{payment_id}" if is_confirmed else f"nak:back_card:{payment_id}"
    rows = _paginated_supplier_rows(
        suppliers,
        page=page,
        item_cb_prefix=f"nak:pick_sup:{payment_id}",
        page_cb_prefix=f"nak:sup_page:{payment_id}",
        page_size=page_size,
    )
    rows.append([InlineKeyboardButton(text="⬅️ Orqaga", callback_data=back_cb)])
    return InlineKeyboardMarkup(inline_keyboard=rows)


def quick_amounts_kb(amounts: Sequence[float]) -> InlineKeyboardMarkup:
    """Last 3 historical amounts for a quick-picked supplier (Y2)."""
    rows: list[list[InlineKeyboardButton]] = []
    if amounts:
        rows.append(
            [
                InlineKeyboardButton(
                    text=f"💰 {format_uzs(amt)}",
                    callback_data=f"qamt:{idx}",
                )
                for idx, amt in enumerate(amounts)
            ]
        )
    rows.append([InlineKeyboardButton(text="❌ Bekor qilish", callback_data="qsup:cancel")])
    return InlineKeyboardMarkup(inline_keyboard=rows)


def status_actions_kb(session_id: int, unpaid_debt_count: int = 0) -> InlineKeyboardMarkup:
    """Inline buttons under Status message."""
    debt_lbl = (
        f"📌 Qarz nakladnoylar ({unpaid_debt_count})"
        if unpaid_debt_count > 0
        else "📌 Qarz nakladnoylar"
    )
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(
                    text="✏️ Tasdiqlanganlarni tahrirlash",
                    callback_data="edit_menu:open",
                ),
                InlineKeyboardButton(
                    text="📥 Excel yuklash",
                    callback_data=f"export:session:{session_id}",
                ),
            ],
            [
                InlineKeyboardButton(
                    text="📆 Boshqa davr Excel",
                    callback_data="export:menu",
                ),
                InlineKeyboardButton(
                    text="📜 History & Qidiruv",
                    callback_data="set:history",
                ),
            ],
            [
                InlineKeyboardButton(
                    text=debt_lbl,
                    callback_data="nak:debts",
                )
            ],
        ]
    )


def export_range_kb() -> InlineKeyboardMarkup:
    """Period selection menu for multi-day Excel exports (E1)."""
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(text="📅 Bugun (ochiq smena)", callback_data="export:range:today"),
                InlineKeyboardButton(text="📆 Oxirgi 7 kun", callback_data="export:range:week"),
            ],
            [
                InlineKeyboardButton(text="🗓 Joriy oy", callback_data="export:range:month"),
                InlineKeyboardButton(text="🗓 O'tgan oy", callback_data="export:range:prev_month"),
            ],
            [
                InlineKeyboardButton(text="✍️ Sana oralig'i tanlash", callback_data="export:range:custom"),
                InlineKeyboardButton(text="📜 Yopilganlar tarixi", callback_data="export:history"),
            ],
            [InlineKeyboardButton(text="⬅️ Orqaga", callback_data="more:open")],
        ]
    )


def stats_menu_kb() -> InlineKeyboardMarkup:
    """Statistics & monthly sverka picker (Y5)."""
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(text="📊 Oxirgi 7 kun", callback_data="stats:7"),
                InlineKeyboardButton(text="📊 Joriy oy", callback_data="stats:month"),
            ],
            [
                InlineKeyboardButton(text="📋 Sverka (Joriy oy)", callback_data="sverka:month:current"),
                InlineKeyboardButton(text="📋 Sverka (O'tgan oy)", callback_data="sverka:month:prev"),
            ],
            [InlineKeyboardButton(text="⬅️ Orqaga", callback_data="more:open")],
        ]
    )


def kassa_debt_actions_kb() -> InlineKeyboardMarkup:
    """Actions for borrowing from or repaying to Kassa."""
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(
                    text="🏦 Kassadan qarz olish",
                    callback_data="kassa:borrow",
                ),
                InlineKeyboardButton(
                    text="↩️ Kassaga qaytarish",
                    callback_data="kassa:repay",
                ),
            ]
        ]
    )


def edit_items_list_kb(
    nakladnoys: Sequence[NakladnoyPayment],
    cash_txs: Sequence[CashTransaction],
    debt_nakladnoys: Sequence[NakladnoyPayment] = (),
    noncash_nakladnoys: Sequence[NakladnoyPayment] = (),
) -> InlineKeyboardMarkup:
    """Inline list of confirmed nakladnoy payments, noncash/debt items, and cash transactions."""
    buttons = []
    for n in nakladnoys:
        sup = n.supplier_name[:20]
        where = "📤" if n.group_message_id else "💾"
        buttons.append(
            [
                InlineKeyboardButton(
                    text=f"{where} {sup} — {format_uzs(n.amount)}",
                    callback_data=f"nak_view:{n.id}",
                )
            ]
        )

    for n in noncash_nakladnoys:
        sup = n.supplier_name[:16]
        pm = (getattr(n, "payment_method", "cash") or "cash").lower()
        icon = "💳" if pm == "card" else "🏦"
        tag = "KARTA" if pm == "card" else "O'TKAZMA"
        buttons.append(
            [
                InlineKeyboardButton(
                    text=f"{icon} {sup} — {format_uzs(n.amount)} [{tag}]",
                    callback_data=f"nak_view:{n.id}",
                )
            ]
        )

    for n in debt_nakladnoys:
        sup = n.supplier_name[:18]
        buttons.append(
            [
                InlineKeyboardButton(
                    text=f"📌 {sup} — {format_uzs(n.amount)} [QARZ]",
                    callback_data=f"nak_view:{n.id}",
                )
            ]
        )

    type_icons = {
        "main": "➕ Pul oldim",
        "kassa_debt": "🏦 Kassa qarz",
        "kassa_repay": "↩️ Qaytarish",
        "expense": "💸 Xarajat",
    }
    for tx in cash_txs:
        lbl = type_icons.get(tx.source_type, "💵")
        buttons.append(
            [
                InlineKeyboardButton(
                    text=f"{lbl}: {format_uzs(tx.amount)}",
                    callback_data=f"cash_view:{tx.id}",
                )
            ]
        )

    buttons.append([InlineKeyboardButton(text="🔙 Yopish", callback_data="menu:dismiss")])
    return InlineKeyboardMarkup(inline_keyboard=buttons)


def confirmed_nakladnoy_edit_kb(
    payment_id: int,
    in_group: bool = False,
    is_debt: bool = False,
    is_admin: bool = True,
    payment_method: str = "cash",
) -> InlineKeyboardMarkup:
    """Edit options for an already confirmed nakladnoy (or paying an unpaid debt nakladnoy)."""
    if not is_admin:
        rows: list[list[InlineKeyboardButton]] = []
        if is_debt:
            rows.append(
                [
                    InlineKeyboardButton(
                        text="💵 To'landi (Pul berildi)",
                        callback_data=f"nak:mark_paid:{payment_id}",
                    )
                ]
            )
            rows.append(_payment_method_row(payment_id, payment_method, include_cash=False))
        rows.append([InlineKeyboardButton(text="⬅️ Qarzlar ro'yxati", callback_data="nak:debts")])
        return InlineKeyboardMarkup(inline_keyboard=rows)

    group_btn = (
        InlineKeyboardButton(
            text="🙈 Guruhdan olish (Faqat baza)",
            callback_data=f"nak:unpost_group:{payment_id}",
        )
        if in_group
        else InlineKeyboardButton(
            text="📤 Guruhga yuborish",
            callback_data=f"nak:repost_group:{payment_id}",
        )
    )
    rows = []
    if is_debt:
        rows.append(
            [
                InlineKeyboardButton(
                    text="💵 To'landi (Pul berildi)",
                    callback_data=f"nak:mark_paid:{payment_id}",
                )
            ]
        )
        rows.append(_payment_method_row(payment_id, payment_method, include_cash=False))
    rows.extend(
        [
            [
                InlineKeyboardButton(
                    text="💰 Summani o'zgartirish",
                    callback_data=f"nak:edit_amt:{payment_id}",
                ),
                InlineKeyboardButton(
                    text="🏢 Postavshikni o'zgartirish",
                    callback_data=f"nak:edit_sup:{payment_id}",
                ),
            ],
            [
                group_btn,
                InlineKeyboardButton(
                    text="🗑 O'chirish",
                    callback_data=f"nak:delete_conf:{payment_id}",
                ),
            ],
        ]
    )
    if not is_debt:
        rows.append(_payment_method_row(payment_id, payment_method, include_cash=True))
        rows.append(
            [
                InlineKeyboardButton(
                    text="📌 Qarzga o'tkazish",
                    callback_data=f"nak:mark_debt:{payment_id}",
                )
            ]
        )
        rows.append(
            [
                InlineKeyboardButton(
                    text="⬅️ Ro'yxatga qaytish",
                    callback_data="edit_menu:open",
                )
            ]
        )
    else:
        rows.append(
            [
                InlineKeyboardButton(
                    text="⬅️ Qarzlar ro'yxati",
                    callback_data="nak:debts",
                )
            ]
        )
    return InlineKeyboardMarkup(inline_keyboard=rows)


def debt_nakladnoys_list_kb(items: Sequence[tuple[NakladnoyPayment, str]]) -> InlineKeyboardMarkup:
    """List of all unpaid debt nakladnoys across all days."""
    rows: list[list[InlineKeyboardButton]] = []
    for pay, report_date in items[:25]:
        rows.append(
            [
                InlineKeyboardButton(
                    text=f"📌 {report_date} | {pay.supplier_name[:18]} — {format_uzs(pay.amount)}",
                    callback_data=f"nak_view:{pay.id}",
                )
            ]
        )
    rows.append([InlineKeyboardButton(text="🔙 Yopish", callback_data="menu:dismiss")])
    return InlineKeyboardMarkup(inline_keyboard=rows)


def cash_tx_edit_kb(tx_id: int) -> InlineKeyboardMarkup:
    """Edit options for a cash-in / kassa-debt transaction."""
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(
                    text="💰 Summani o'zgartirish",
                    callback_data=f"cash:edit_amt:{tx_id}",
                ),
                InlineKeyboardButton(
                    text="🗑 O'chirish",
                    callback_data=f"cash:delete:{tx_id}",
                ),
            ],
            [
                InlineKeyboardButton(
                    text="⬅️ Ro'yxatga qaytish",
                    callback_data="edit_menu:open",
                )
            ],
        ]
    )


def close_day_confirm_kb(session_id: int, counted: float) -> InlineKeyboardMarkup:
    """Confirmation keyboard after user enters counted physical cash."""
    counted_int = round(counted)
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(
                    text="✅ Kunni yopish va History'ga saqlash",
                    callback_data=f"close_day:confirm:{session_id}:{counted_int}",
                )
            ],
            [
                InlineKeyboardButton(
                    text="💾 Oraliq sverka saqlash (yopmasdan)",
                    callback_data=f"close_day:interim:{session_id}:{counted_int}",
                )
            ],
            [
                InlineKeyboardButton(
                    text="🔄 Qayta sanab kiritish",
                    callback_data="close_day:recount",
                ),
                InlineKeyboardButton(
                    text="✏️ Xatoni to'g'irlash",
                    callback_data="edit_menu:open",
                ),
            ],
        ]
    )


def kassa_sverka_kb(can_write: bool = True) -> InlineKeyboardMarkup:
    """Inline keyboard for viewing/creating interim and closing cash reconciliations."""
    rows: list[list[InlineKeyboardButton]] = []
    if can_write:
        rows.append(
            [
                InlineKeyboardButton(
                    text="➕ Yangi oraliq sverka",
                    callback_data="kassa_sverka:new",
                )
            ]
        )
    rows.append(
        [
            InlineKeyboardButton(text="🔄 Yangilash", callback_data="more:kassa_sverka"),
            InlineKeyboardButton(text="🔙 Yopish", callback_data="menu:dismiss"),
        ]
    )
    return InlineKeyboardMarkup(inline_keyboard=rows)


def settings_menu_kb() -> InlineKeyboardMarkup:
    """Streamlined Admin Settings & Tools inline menu."""
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(text="🔗 Guruhlarni sozlash", callback_data="set:groups"),
                InlineKeyboardButton(text="👑 Prixod (ITOG) tarixi", callback_data="set:prixod_history"),
            ],
            [
                InlineKeyboardButton(text="🏢 Ta'minotchilar", callback_data="set:suppliers"),
                InlineKeyboardButton(text="👥 Foydalanuvchi rollari", callback_data="set:roles"),
            ],
            [
                InlineKeyboardButton(text="💾 Backup olish", callback_data="set:backup"),
                InlineKeyboardButton(text="⬅️ Bosh menyu", callback_data="more:open"),
            ],
        ]
    )


def ai_prefs_kb(auto_confirm: bool, round_mode: str) -> InlineKeyboardMarkup:
    """Toggle auto-confirm speed mode and nakladnoy amount rounding mode."""
    auto_lbl = (
        "⚡ Tez rejim (Avto-guruhga): ✅ YOQILGAN"
        if auto_confirm
        else "⚡ Tez rejim (Avto-guruhga): ❌ O'CHIQ"
    )
    r_floor = "✅ 1 000 ga pastga (192 620 → 192 000)" if round_mode == "floor_1000" else "1 000 ga pastga (192 620 → 192 000)"
    r_near = "✅ Yaqin 1 000 ga (192 620 → 193 000)" if round_mode == "nearest_1000" else "Yaqin 1 000 ga (192 620 → 193 000)"
    r_none = "✅ Yaxlitlamaslik (192 620 → 192 620)" if round_mode == "none" else "Yaxlitlamaslik (192 620 → 192 620)"
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [InlineKeyboardButton(text=auto_lbl, callback_data="pref:toggle_auto")],
            [InlineKeyboardButton(text=r_floor, callback_data="pref:round:floor_1000")],
            [InlineKeyboardButton(text=r_near, callback_data="pref:round:nearest_1000")],
            [InlineKeyboardButton(text=r_none, callback_data="pref:round:none")],
            [InlineKeyboardButton(text="⬅️ Orqaga", callback_data="set:back")],
        ]
    )


def auto_report_kb(enabled: bool, time_str: str) -> InlineKeyboardMarkup:
    """Configure daily auto-status notification schedule (Y3)."""
    toggle_lbl = "✅ Yoqilgan (O'chirish)" if enabled else "❌ O'chiq (Yoqish)"
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [InlineKeyboardButton(text=f"⏰ Avto-hisobot: {toggle_lbl}", callback_data="ar:toggle")],
            [
                InlineKeyboardButton(
                    text=f"{'✅ ' if time_str == '21:00' else ''}21:00", callback_data="ar:time:21:00"
                ),
                InlineKeyboardButton(
                    text=f"{'✅ ' if time_str == '22:00' else ''}22:00", callback_data="ar:time:22:00"
                ),
                InlineKeyboardButton(
                    text=f"{'✅ ' if time_str == '23:00' else ''}23:00", callback_data="ar:time:23:00"
                ),
            ],
            [InlineKeyboardButton(text="⬅️ Orqaga", callback_data="set:back")],
        ]
    )


def roles_list_kb(roles: Sequence[UserRole], super_admins: Sequence[int]) -> InlineKeyboardMarkup:
    """Manage user roles (Y6)."""
    rows: list[list[InlineKeyboardButton]] = []
    for ur in roles:
        if ur.user_id in super_admins:
            continue
        icon = "👑" if ur.role == "admin" else ("💼" if ur.role == "kassir" else "👁")
        lbl = ur.label or str(ur.user_id)
        rows.append(
            [
                InlineKeyboardButton(
                    text=f"{icon} {lbl} ({ur.user_id}) — 🗑",
                    callback_data=f"role:del:{ur.user_id}",
                )
            ]
        )
    rows.append([InlineKeyboardButton(text="➕ Foydalanuvchi qo'shish", callback_data="role:add")])
    rows.append([InlineKeyboardButton(text="⬅️ Orqaga", callback_data="set:back")])
    return InlineKeyboardMarkup(inline_keyboard=rows)


def role_pick_kb(user_id: int) -> InlineKeyboardMarkup:
    """Pick role for a newly added Telegram user_id."""
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [InlineKeyboardButton(text=ROLE_LABELS[r], callback_data=f"role:pick:{user_id}:{r}")]
            for r in (ROLE_ADMIN, ROLE_KASSIR, "viewer")
        ]
        + [[InlineKeyboardButton(text="❌ Bekor qilish", callback_data="set:roles")]]
    )


def nasiya_main_kb(balances: Sequence[dict], can_write: bool = True) -> InlineKeyboardMarkup:
    """Main supplier credit (nasiya) ledger keyboard (Y7)."""
    rows: list[list[InlineKeyboardButton]] = []
    for idx, item in enumerate(balances[:15]):
        bal = item["balance"]
        icon = "🔴" if bal > 0 else "✅"
        rows.append(
            [
                InlineKeyboardButton(
                    text=f"{icon} {item['supplier'][:20]}: {format_uzs(bal)}",
                    callback_data=f"nasiya:sup:{idx}",
                )
            ]
        )
    if can_write:
        rows.append([InlineKeyboardButton(text="➕ Yangi nasiya (qarz) yozish", callback_data="nasiya:add_debt")])
    rows.append([InlineKeyboardButton(text="📌 Qarz nakladnoylar", callback_data="nak:debts")])
    rows.append(
        [
            InlineKeyboardButton(text="📜 Oxirgi yozuvlar", callback_data="nasiya:hist"),
            InlineKeyboardButton(text="⬅️ Orqaga", callback_data="more:open"),
        ]
    )
    return InlineKeyboardMarkup(inline_keyboard=rows)


def nasiya_supplier_kb(idx: int, can_write: bool = True) -> InlineKeyboardMarkup:
    """Actions for a specific supplier's nasiya balance."""
    rows: list[list[InlineKeyboardButton]] = []
    if can_write:
        rows.append(
            [
                InlineKeyboardButton(text="➕ Qarz qo'shish", callback_data=f"nasiya:sup_debt:{idx}"),
                InlineKeyboardButton(text="💵 To'lov yozish", callback_data=f"nasiya:sup_pay:{idx}"),
            ]
        )
    rows.append([InlineKeyboardButton(text="⬅️ Nasiya ro'yxati", callback_data="nasiya:home")])
    return InlineKeyboardMarkup(inline_keyboard=rows)


def nasiya_history_kb(entries: Sequence[SupplierDebt], is_admin: bool = False) -> InlineKeyboardMarkup:
    """Recent nasiya entries with optional delete for admins."""
    rows: list[list[InlineKeyboardButton]] = []
    if is_admin:
        for e in entries[:10]:
            sign = "+" if e.entry_type == "debt" else "-"
            rows.append(
                [
                    InlineKeyboardButton(
                        text=f"🗑 {e.supplier_name[:16]} {sign}{format_uzs(e.amount)}",
                        callback_data=f"nasiya:del:{e.id}",
                    )
                ]
            )
    rows.append([InlineKeyboardButton(text="⬅️ Nasiya ro'yxati", callback_data="nasiya:home")])
    return InlineKeyboardMarkup(inline_keyboard=rows)


GROUP_ADMIN_RIGHTS = "change_info+delete_messages+invite_users+pin_messages+manage_chat"


def build_add_to_group_url(bot_username: str, role: str) -> str:
    """Build Telegram deep-link that opens group picker with admin permission prompt and auto-binds role."""
    clean_username = bot_username.lstrip("@") or "hisobchi_my_bot"
    return f"https://t.me/{clean_username}?startgroup=bind_{role}&admin={GROUP_ADMIN_RIGHTS}"


def groups_config_kb(bot_username: str = "hisobchi_my_bot") -> InlineKeyboardMarkup:
    """Group binding menu with 1-click Telegram Admin Picker + manual ID fallback."""
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(
                    text="➕ 📸 Nakladnoy guruhiga qo'shish (Admin)",
                    url=build_add_to_group_url(bot_username, "nakladnoy"),
                )
            ],
            [
                InlineKeyboardButton(
                    text="➕ 👑 Prixod (ITOG) guruhiga qo'shish (Admin)",
                    url=build_add_to_group_url(bot_username, "prixod"),
                )
            ],
            [
                InlineKeyboardButton(
                    text="➕ 💰 Kassa guruhiga qo'shish (Admin)",
                    url=build_add_to_group_url(bot_username, "kassa"),
                )
            ],
            [
                InlineKeyboardButton(text="🆔 Nakladnoy", callback_data="grp:set_id:nakladnoy"),
                InlineKeyboardButton(text="🆔 Prixod", callback_data="grp:set_id:prixod"),
                InlineKeyboardButton(text="🆔 Kassa", callback_data="grp:set_id:kassa"),
            ],
            [
                InlineKeyboardButton(
                    text="🧪 Guruhlarga test xabar yuborish",
                    callback_data="grp:test_ping",
                )
            ],
            [InlineKeyboardButton(text="⬅️ Orqaga", callback_data="set:back")],
        ]
    )


def quick_bind_group_kb(chat_id: int) -> InlineKeyboardMarkup:
    """One-tap role assignment when bot is added to a group manually."""
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(
                    text="📸 Nakladnoy guruhi",
                    callback_data=f"grp:qbind:nakladnoy:{chat_id}",
                )
            ],
            [
                InlineKeyboardButton(
                    text="👑 Prixod (ITOG) guruhi",
                    callback_data=f"grp:qbind:prixod:{chat_id}",
                )
            ],
            [
                InlineKeyboardButton(
                    text="💰 Kassa / Rahbariyat guruhi",
                    callback_data=f"grp:qbind:kassa:{chat_id}",
                )
            ],
        ]
    )


def suppliers_list_kb(suppliers: Sequence[SupplierConfig]) -> InlineKeyboardMarkup:
    """Supplier configuration list keyboard."""
    rows = []
    for s in suppliers:
        cat_icon = "📌 Qarz" if s.default_category == "qarz" else "💳 Karta"
        rows.append(
            [
                InlineKeyboardButton(
                    text=f"{s.order_num}) {s.display_name} [{cat_icon}]",
                    callback_data=f"sup:view:{s.id}",
                )
            ]
        )
    rows.append(
        [
            InlineKeyboardButton(text="➕ Yangi ta'minotchi", callback_data="sup:add"),
            InlineKeyboardButton(text="⬅️ Orqaga", callback_data="set:back"),
        ]
    )
    return InlineKeyboardMarkup(inline_keyboard=rows)


def supplier_detail_kb(supplier_id: int) -> InlineKeyboardMarkup:
    """Detail actions for a configured supplier."""
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(
                    text="🔗 YesPOS nomini (sinonim) qo'shish",
                    callback_data=f"sup:alias:{supplier_id}",
                )
            ],
            [
                InlineKeyboardButton(
                    text="🗑 O'chirish",
                    callback_data=f"sup:del:{supplier_id}",
                ),
                InlineKeyboardButton(
                    text="⬅️ Ro'yxatga",
                    callback_data="set:suppliers",
                ),
            ],
        ]
    )


def history_sessions_kb(sessions: Sequence[DailyCashSession]) -> InlineKeyboardMarkup:
    """List open & closed daily sessions plus quick Nakladnoy / Cash / Search views."""
    rows = [
        [
            InlineKeyboardButton(text="📸 Barcha Nakladnoylar", callback_data="hist:all_nak:0"),
            InlineKeyboardButton(text="💵 Oldi-berdi tarixi", callback_data="hist:all_cash:0"),
        ],
        [
            InlineKeyboardButton(text="🔍 Qidirish (Postavshik / Sana)", callback_data="hist:search"),
        ],
    ]
    for s in sessions:
        if s.status == "open":
            label = f"🟢 {s.report_date} (Ochiq) | Qolishi: {format_uzs(s.expected_cash)}"
        else:
            diff = s.difference or 0
            icon = "✅" if abs(diff) < 1 else ("⚠️" if diff < 0 else "➕")
            label = f"{icon} {s.report_date} | Qoldiq: {format_uzs(s.actual_counted_cash or 0)}"
        rows.append([InlineKeyboardButton(text=label, callback_data=f"hist:view:{s.id}")])
    rows.append([InlineKeyboardButton(text="⬅️ Orqaga", callback_data="more:open")])
    return InlineKeyboardMarkup(inline_keyboard=rows)


def history_detail_kb(
    session_id: int, is_closed: bool = True, is_admin: bool = True
) -> InlineKeyboardMarkup:
    """Actions on a daily session in history."""
    top_row = [
        InlineKeyboardButton(
            text="📥 Excel yuklash",
            callback_data=f"export:session:{session_id}",
        )
    ]
    if is_closed and is_admin:
        top_row.append(
            InlineKeyboardButton(
                text="🔓 Qayta ochib to'g'irlash",
                callback_data=f"hist:reopen:{session_id}",
            )
        )
    return InlineKeyboardMarkup(
        inline_keyboard=[
            top_row,
            [InlineKeyboardButton(text="⬅️ History ga qaytish", callback_data="set:history")],
        ]
    )


def history_feed_kb(
    kind: str,
    page: int,
    has_next: bool,
    photo_items: Sequence[tuple[int, str]] = (),
) -> InlineKeyboardMarkup:
    """Pagination keyboard for all-nakladnoys / all-cash-transactions / search results."""
    rows: list[list[InlineKeyboardButton]] = []
    if photo_items:
        p_row: list[InlineKeyboardButton] = []
        for pid, label in photo_items[:6]:
            p_row.append(InlineKeyboardButton(text=f"📸 {label[:14]}", callback_data=f"nak:photo:{pid}"))
            if len(p_row) == 2:
                rows.append(p_row)
                p_row = []
        if p_row:
            rows.append(p_row)

    nav = []
    if page > 0:
        nav.append(InlineKeyboardButton(text="⬅️ Oldingi", callback_data=f"hist:{kind}:{page - 1}"))
    if has_next:
        nav.append(InlineKeyboardButton(text="Keyingi ➡️", callback_data=f"hist:{kind}:{page + 1}"))
    if nav:
        rows.append(nav)
    rows.append([InlineKeyboardButton(text="⬅️ History ga qaytish", callback_data="set:history")])
    return InlineKeyboardMarkup(inline_keyboard=rows)


def prixod_report_kb(report_id: int, is_published: bool = False) -> InlineKeyboardMarkup:
    """Inline controls for a parsed ITOG Prixod report."""
    pub_text = "🔄 Prixod guruhidagi xabarni yangilash" if is_published else "✅ Prixod guruhiga yuborish"
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(
                    text=pub_text,
                    callback_data=f"prx:publish:{report_id}",
                )
            ],
            [
                InlineKeyboardButton(
                    text="🎛 Qatorlarni sozlash (Karta/Sana/Qarz)",
                    callback_data=f"prx:rows:{report_id}:0",
                )
            ],
            [
                InlineKeyboardButton(
                    text="📅 Sanani o'zgartirish",
                    callback_data=f"prx:date:{report_id}",
                ),
                InlineKeyboardButton(
                    text="📥 Excel yuklash",
                    callback_data=f"export:prixod:{report_id}",
                ),
            ],
        ]
    )


def prixod_rows_kb(
    report_id: int, rows: Sequence[PrixodRow], page: int = 0, page_size: int = 10
) -> InlineKeyboardMarkup:
    """Paginated list of Prixod rows for toggling categories."""
    total = len(rows)
    start = page * page_size
    end = min(start + page_size, total)
    cat_icons = {
        "qarz": "📌",
        "nakladnoy": "📋",
        "karta": "💳",
        "old_date": "📅",
    }
    buttons = []
    for r in rows[start:end]:
        icon = cat_icons.get(r.category, "📋")
        label = f"{icon} {r.supplier_display[:20]} — {format_uzs(r.cost)}"
        buttons.append(
            [InlineKeyboardButton(text=label, callback_data=f"prx:row:{report_id}:{r.id}:{page}")]
        )

    nav = []
    if page > 0:
        nav.append(InlineKeyboardButton(text="⬅️ Oldingi", callback_data=f"prx:rows:{report_id}:{page - 1}"))
    if end < total:
        nav.append(InlineKeyboardButton(text="Keyingi ➡️", callback_data=f"prx:rows:{report_id}:{page + 1}"))
    if nav:
        buttons.append(nav)

    buttons.append(
        [InlineKeyboardButton(text="🔙 Hisobotga qaytish", callback_data=f"prx:view:{report_id}")]
    )
    return InlineKeyboardMarkup(inline_keyboard=buttons)


def prixod_row_category_kb(report_id: int, row_id: int, page: int) -> InlineKeyboardMarkup:
    """Category picker for a single PrixodRow."""
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(
                    text="📋 Nakladnoy",
                    callback_data=f"prx:setcat:{report_id}:{row_id}:nakladnoy:{page}",
                ),
                InlineKeyboardButton(
                    text="💳 Karta",
                    callback_data=f"prx:setcat:{report_id}:{row_id}:karta:{page}",
                ),
            ],
            [
                InlineKeyboardButton(
                    text="📌 Qarz ro'yxatiga",
                    callback_data=f"prx:setcat:{report_id}:{row_id}:qarz:{page}",
                ),
                InlineKeyboardButton(
                    text="📅 Eski sana",
                    callback_data=f"prx:setold:{report_id}:{row_id}:{page}",
                ),
            ],
            [
                InlineKeyboardButton(
                    text="⬅️ Qatorlarga qaytish",
                    callback_data=f"prx:rows:{report_id}:{page}",
                )
            ],
        ]
    )


def prixod_history_kb(reports: Sequence[PrixodReport]) -> InlineKeyboardMarkup:
    """Recent Prixod reports list."""
    rows = []
    for r in reports:
        status_icon = "✅" if r.status == "published" else "📝"
        rows.append(
            [
                InlineKeyboardButton(
                    text=f"{status_icon} ITOG {r.report_date} — {format_uzs(r.total_cost)} so'm",
                    callback_data=f"prx:view:{r.id}",
                )
            ]
        )
    rows.append([InlineKeyboardButton(text="⬅️ Orqaga", callback_data="set:back")])
    return InlineKeyboardMarkup(inline_keyboard=rows)
