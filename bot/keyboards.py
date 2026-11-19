"""Reply and inline keyboards for Hisobot Bot."""

from __future__ import annotations

from typing import Sequence

from aiogram.types import (
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    KeyboardButton,
    ReplyKeyboardMarkup,
)

from database.models import (
    CashTransaction,
    DailyCashSession,
    NakladnoyPayment,
    PrixodReport,
    PrixodRow,
    SupplierConfig,
)
from services.gemini_ai import format_uzs


BTN_ADD_NAKLADNOY = "📸 Nakladnoy qo'shish"
BTN_CASH_IN = "➕ Pul oldim"
BTN_STATUS = "📊 Status (Hisob)"
BTN_EDIT_CONFIRMED = "✏️ Tahrirlash"
BTN_CLOSE_DAY = "🏁 Kunni yakunlash"
BTN_PRIXOD = "👑 Prixod (ITOG)"
BTN_KASSA_DEBT = "🏦 Kassa qarzi"
BTN_SETTINGS = "⚙️ Sozlamalar & History"


def main_menu_keyboard() -> ReplyKeyboardMarkup:
    """Main persistent bottom menu."""
    return ReplyKeyboardMarkup(
        keyboard=[
            [KeyboardButton(text=BTN_ADD_NAKLADNOY), KeyboardButton(text=BTN_CASH_IN)],
            [KeyboardButton(text=BTN_STATUS), KeyboardButton(text=BTN_EDIT_CONFIRMED)],
            [KeyboardButton(text=BTN_CLOSE_DAY), KeyboardButton(text=BTN_PRIXOD)],
            [KeyboardButton(text=BTN_KASSA_DEBT), KeyboardButton(text=BTN_SETTINGS)],
        ],
        resize_keyboard=True,
    )


def cancel_reply_keyboard() -> ReplyKeyboardMarkup:
    """Simple cancel keyboard during FSM inputs."""
    return ReplyKeyboardMarkup(
        keyboard=[[KeyboardButton(text="❌ Bekor qilish")]],
        resize_keyboard=True,
    )


def nakladnoy_confirm_kb(payment_id: int) -> InlineKeyboardMarkup:
    """Confirmation inline keyboard for a pending nakladnoy payment."""
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(
                    text="✅ Tasdiqlash (Guruhga yuborish)",
                    callback_data=f"nak:confirm:{payment_id}",
                )
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


def status_actions_kb(session_id: int) -> InlineKeyboardMarkup:
    """Inline buttons under Status message."""
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
            ]
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
) -> InlineKeyboardMarkup:
    """Inline list of confirmed nakladnoy payments and cash transactions for editing."""
    buttons = []
    for n in nakladnoys:
        sup = n.supplier_name[:22]
        buttons.append(
            [
                InlineKeyboardButton(
                    text=f"📸 {sup} — {format_uzs(n.amount)}",
                    callback_data=f"nak_view:{n.id}",
                )
            ]
        )

    type_icons = {"main": "➕ Pul", "kassa_debt": "🏦 Kassa qarz", "kassa_repay": "↩️ Qaytarish"}
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


def confirmed_nakladnoy_edit_kb(payment_id: int) -> InlineKeyboardMarkup:
    """Edit options for an already confirmed nakladnoy."""
    return InlineKeyboardMarkup(
        inline_keyboard=[
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
                    text="🗑 O'chirish (Bekor qilish)",
                    callback_data=f"nak:delete_conf:{payment_id}",
                )
            ],
            [
                InlineKeyboardButton(
                    text="⬅️ Ro'yxatga qaytish",
                    callback_data="edit_menu:open",
                )
            ],
        ]
    )


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


def settings_menu_kb() -> InlineKeyboardMarkup:
    """Settings & History inline menu."""
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(
                    text="🔗 Guruhlarni sozlash",
                    callback_data="set:groups",
                ),
                InlineKeyboardButton(
                    text="🏢 Ta'minotchilar (Qarz/Karta)",
                    callback_data="set:suppliers",
                ),
            ],
            [
                InlineKeyboardButton(
                    text="📜 Arxiv / History (Kassa)",
                    callback_data="set:history",
                ),
                InlineKeyboardButton(
                    text="👑 Prixod (ITOG) tarixi",
                    callback_data="set:prixod_history",
                ),
            ],
            [
                InlineKeyboardButton(
                    text="📥 Tarixni Excel yuklash",
                    callback_data="export:history",
                )
            ],
        ]
    )


def groups_config_kb() -> InlineKeyboardMarkup:
    """Group binding menu."""
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(
                    text="📸 Nakladnoy guruhi ID kiritish",
                    callback_data="grp:set_id:nakladnoy",
                )
            ],
            [
                InlineKeyboardButton(
                    text="👑 Prixod (ITOG) guruhi ID kiritish",
                    callback_data="grp:set_id:prixod",
                )
            ],
            [
                InlineKeyboardButton(
                    text="💰 Kassa / Rahbariyat guruhi ID kiritish",
                    callback_data="grp:set_id:kassa",
                )
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
    """List closed daily sessions for inspection or reopening."""
    rows = []
    for s in sessions:
        diff = s.difference or 0
        icon = "✅" if abs(diff) < 1 else ("⚠️" if diff < 0 else "➕")
        rows.append(
            [
                InlineKeyboardButton(
                    text=f"{icon} {s.report_date} | Qoldiq: {format_uzs(s.actual_counted_cash or 0)}",
                    callback_data=f"hist:view:{s.id}",
                )
            ]
        )
    rows.append([InlineKeyboardButton(text="⬅️ Orqaga", callback_data="set:back")])
    return InlineKeyboardMarkup(inline_keyboard=rows)


def history_detail_kb(session_id: int) -> InlineKeyboardMarkup:
    """Actions on a closed historical session."""
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [
                InlineKeyboardButton(
                    text="📥 Excel yuklash",
                    callback_data=f"export:session:{session_id}",
                ),
                InlineKeyboardButton(
                    text="🔓 Qayta ochib to'g'irlash",
                    callback_data=f"hist:reopen:{session_id}",
                ),
            ],
            [InlineKeyboardButton(text="⬅️ Arxivga qaytish", callback_data="set:history")],
        ]
    )


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
