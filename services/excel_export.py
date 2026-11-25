"""OpenPyXL Excel report generator for daily sessions, multi-day ranges, prixod, and sverka."""

from __future__ import annotations

import io
import re
from typing import Any, Optional, Sequence, Tuple

from openpyxl import Workbook
from openpyxl.chart import BarChart, Reference
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.worksheet import Worksheet

from database.crud import SessionSummary, format_local_dt
from database.models import DailyCashSession, PrixodReport


NAVY = "1F4E78"
HEADER_FILL = PatternFill(start_color=NAVY, end_color=NAVY, fill_type="solid")
HEADER_FONT = Font(color="FFFFFF", bold=True, size=11)
TITLE_FONT = Font(bold=True, size=15, color=NAVY)
SECTION_FONT = Font(bold=True, size=12, color=NAVY)
BOLD_FONT = Font(bold=True, size=11)
LINK_FONT = Font(color="0563C1", underline="single")
LABEL_FILL = PatternFill(start_color="DDEBF7", end_color="DDEBF7", fill_type="solid")
ZEBRA_FILL = PatternFill(start_color="F5F9FD", end_color="F5F9FD", fill_type="solid")
TOTAL_FILL = PatternFill(start_color="FFF2CC", end_color="FFF2CC", fill_type="solid")
GOOD_FILL = PatternFill(start_color="E2EFDA", end_color="E2EFDA", fill_type="solid")
BAD_FILL = PatternFill(start_color="FCE4D6", end_color="FCE4D6", fill_type="solid")
THIN = Side(style="thin", color="BFBFBF")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
MONEY_FORMAT = "#,##0;[Red]-#,##0"

_LEGACY_ROUND_RE = re.compile(r"\bAsli:\s*([\d\s]+?)\s*(?:→|->)\s*[\d\s]+")


def _parse_legacy_original_amount(note: Optional[str]) -> Tuple[Optional[float], str]:
    """Extract legacy 'Asli: 192 640 → 192 000' from note and return cleaned note."""
    raw = (note or "").strip()
    if not raw:
        return None, ""
    m = _LEGACY_ROUND_RE.search(raw)
    if not m:
        return None, raw
    digits = re.sub(r"\s+", "", m.group(1))
    orig = float(digits) if digits.isdigit() else None
    cleaned = (_LEGACY_ROUND_RE.sub("", raw)).strip(" |,-")
    return orig, cleaned


def _pm_label(pm: Optional[str]) -> str:
    """Human-readable Uzbek label for payment_method (cash | card | transfer)."""
    val = (pm or "cash").strip().lower()
    return {"cash": "Naqd", "card": "Karta", "transfer": "Perechesleniya"}.get(val, "Naqd")


def _telegram_group_link(chat_id: Optional[int], msg_id: Optional[int]) -> Optional[str]:
    """Build clickable Telegram message URL for supergroups (-100...)."""
    if not chat_id or not msg_id:
        return None
    s = str(chat_id)
    if s.startswith("-100"):
        return f"https://t.me/c/{s[4:]}/{msg_id}"
    return None


def _title(ws: Worksheet, text: str, last_col: int) -> None:
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=max(last_col, 1))
    cell = ws.cell(row=1, column=1, value=text)
    cell.font = TITLE_FONT
    cell.alignment = Alignment(horizontal="left", vertical="center")
    ws.row_dimensions[1].height = 28


def _header(ws: Worksheet, row: int, headers: Sequence[str]) -> None:
    for col, text in enumerate(headers, start=1):
        c = ws.cell(row=row, column=col, value=text)
        c.fill = HEADER_FILL
        c.font = HEADER_FONT
        c.border = BORDER
        c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    ws.row_dimensions[row].height = 24


def _body_row(
    ws: Worksheet, row: int, values: Sequence[Any], money_cols: Sequence[int], zebra: bool
) -> None:
    for col, val in enumerate(values, start=1):
        c = ws.cell(row=row, column=col, value=val)
        c.border = BORDER
        is_num = col in money_cols and isinstance(val, (int, float, str)) and val != ""
        c.alignment = Alignment(
            vertical="center",
            wrap_text=True,
            horizontal="right" if col in money_cols else "left",
        )
        if col in money_cols and (isinstance(val, (int, float)) or (isinstance(val, str) and val.startswith("="))):
            c.number_format = MONEY_FORMAT
        if zebra:
            c.fill = ZEBRA_FILL
        elif is_num:
            pass


def _total_row(
    ws: Worksheet, row: int, label: str, label_col: int, sums: dict[int, Any], ncols: int
) -> None:
    for col in range(1, ncols + 1):
        c = ws.cell(row=row, column=col)
        c.fill = TOTAL_FILL
        c.border = BORDER
        c.font = BOLD_FONT
    ws.cell(row=row, column=label_col, value=label)
    for col, formula in sums.items():
        c = ws.cell(row=row, column=col, value=formula)
        c.number_format = MONEY_FORMAT
        c.alignment = Alignment(horizontal="right", vertical="center")


def _kv_block(
    ws: Worksheet,
    start_row: int,
    section_title: str,
    rows: Sequence[Tuple[str, Any]],
    diff_label: Optional[str] = None,
    highlight_label: Optional[str] = None,
) -> int:
    """Render a titled 2-column key-value block and return the next free row index."""
    ws.cell(row=start_row, column=1, value=section_title).font = SECTION_FONT
    ws.row_dimensions[start_row].height = 22
    r = start_row + 1
    for label, val in rows:
        lc = ws.cell(row=r, column=1, value=label)
        lc.font = BOLD_FONT
        lc.fill = LABEL_FILL
        lc.border = BORDER
        lc.alignment = Alignment(vertical="center")

        vc = ws.cell(row=r, column=2, value=val)
        vc.border = BORDER
        vc.alignment = Alignment(horizontal="right", vertical="center")
        if isinstance(val, (int, float)):
            vc.number_format = MONEY_FORMAT
        if highlight_label and label == highlight_label:
            vc.font = BOLD_FONT
            vc.fill = TOTAL_FILL
        if diff_label and label == diff_label and isinstance(val, (int, float)):
            vc.fill = GOOD_FILL if round(val) == 0 else BAD_FILL
            vc.font = BOLD_FONT
        r += 1
    return r


def _autowidth(
    ws: Worksheet, minimum: int = 8, maximum: int = 42, skip_rows: int = 0
) -> None:
    widths: dict[int, int] = {}
    for row in ws.iter_rows(min_row=skip_rows + 1):
        for c in row:
            if c.value is None or type(c).__name__ == "MergedCell":
                continue
            if isinstance(c.value, str) and c.value.startswith("="):
                est = 15
            elif isinstance(c.value, (int, float)):
                est = len(f"{c.value:,.0f}")
            else:
                lines = str(c.value).split("\n")
                est = max((len(line) for line in lines), default=0)
            widths[c.column] = max(widths.get(c.column, 0), est)
    for col, w in widths.items():
        ws.column_dimensions[get_column_letter(col)].width = min(max(w + 3, minimum), maximum)


def _finish(
    ws: Worksheet,
    freeze: Optional[str],
    last_col: int,
    header_row: int,
    last_row: int,
    landscape: bool = False,
) -> None:
    if freeze:
        ws.freeze_panes = freeze
    if last_row > header_row:
        ws.auto_filter.ref = f"A{header_row}:{get_column_letter(last_col)}{last_row}"
    ws.sheet_view.showGridLines = False
    ws.page_setup.orientation = "landscape" if landscape else "portrait"
    ws.page_setup.fitToWidth = 1
    ws.page_setup.fitToHeight = 0
    ws.sheet_properties.pageSetUpPr.fitToPage = True


def _ts(dt: Any) -> str:
    return format_local_dt(dt, "%d.%m.%Y %H:%M") if dt else ""


def _to_bytes(wb: Workbook) -> bytes:
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def _write_photo_cell(ws: Worksheet, row: int, col: int, item: Any, zebra: bool) -> None:
    chat_id = getattr(item, "group_chat_id", None)
    msg_id = getattr(item, "group_message_id", None)
    photo_id = getattr(item, "photo_file_id", None)
    link = _telegram_group_link(chat_id, msg_id)
    cell = ws.cell(row=row, column=col)
    cell.border = BORDER
    cell.alignment = Alignment(horizontal="center", vertical="center")
    if zebra:
        cell.fill = ZEBRA_FILL
    if link:
        cell.value = "Ochish"
        cell.hyperlink = link
        cell.font = LINK_FONT
    elif photo_id:
        cell.value = "Telegramda"
    else:
        cell.value = "-"


def _extract_orig_and_note(item: Any) -> Tuple[Any, str]:
    raw_orig = getattr(item, "original_amount", None)
    note = (getattr(item, "note", None) or "").strip()
    parsed_orig, cleaned_note = _parse_legacy_original_amount(note)
    orig = raw_orig if raw_orig is not None else parsed_orig
    amt = getattr(item, "amount", 0) or 0
    if orig is not None and round(orig) != round(amt):
        return round(orig), cleaned_note
    return "", cleaned_note


def build_session_excel(summary: SessionSummary) -> bytes:
    """Export a DailyCashSession into a 3-sheet workbook (Xulosa, Nakladnoylar, Kirim va Qarzlar)."""
    wb = Workbook()

    # Sheet 1: Xulosa
    ws_sum = wb.active
    ws_sum.title = "Xulosa"
    _title(ws_sum, f"KUNLIK HISOB-KITOB — {summary.session.report_date}", 3)
    diff = summary.session.difference or 0
    next_r = _kv_block(
        ws_sum,
        3,
        "Asosiy ko'rsatkichlar",
        [
            ("Holati", "Yopilgan" if summary.session.status == "closed" else "Ochiq"),
            ("Kechadan qoldiq", round(summary.opening_balance)),
            ("Pul oldim (kirim)", round(summary.main_cash_in)),
            ("Kassadan olingan (bugun)", round(summary.kassa_debt_today)),
            ("Kassaga qaytarilgan (bugun)", round(summary.kassa_repay_today)),
            ("Jami kirim (qo'ldagi)", round(summary.total_available_inflow)),
            ("Jami nakladnoy rasxod", round(summary.total_nakladnoy_spent)),
            ("Boshqa xarajatlar (bugun)", round(getattr(summary, "expense_today", 0.0) or 0.0)),
            ("Qo'lda qolishi kerak", round(summary.expected_cash)),
            ("Qo'lda sanalgan pul", round(summary.session.actual_counted_cash or 0)),
            ("Farq", round(diff)),
        ],
        diff_label="Farq",
        highlight_label="Qo'lda qolishi kerak",
    )

    items = list(summary.confirmed_nakladnoys)
    cnt = len(items)
    in_grp = sum(1 for n in items if getattr(n, "group_message_id", None))
    avg_amt = round(summary.total_nakladnoy_spent / cnt) if cnt else 0
    spend_pct = (
        round(summary.total_nakladnoy_spent / summary.total_available_inflow * 100, 1)
        if summary.total_available_inflow > 0
        else 0.0
    )

    debt_items = list(getattr(summary, "debt_nakladnoys", []) or [])
    noncash_items = list(getattr(summary, "noncash_nakladnoys", []) or [])
    total_card = round(getattr(summary, "total_card_spent", 0.0) or 0.0)
    total_transfer = round(getattr(summary, "total_transfer_spent", 0.0) or 0.0)
    stat_rows = [
        ("Umumiy kassa qarzi qoldig'i", round(summary.total_kassa_debt_outstanding)),
        ("Nakladnoylar soni", cnt),
        ("Guruhga yuborilgan / Faqat baza", f"{in_grp} ta / {cnt - in_grp} ta"),
        ("O'rtacha to'lov", avg_amt),
        ("Sarflanish ulushi (%)", spend_pct),
    ]
    if noncash_items:
        if total_card > 0:
            stat_rows.append(("Karta orqali to'lovlar (naqdsiz)", total_card))
        if total_transfer > 0:
            stat_rows.append(("Perechesleniya / o'tkazma (naqdsiz)", total_transfer))
        stat_rows.append(
            (
                "Jami barcha to'lovlar (Naqd+Karta+O'tkazma)",
                round(summary.total_nakladnoy_spent) + total_card + total_transfer,
            )
        )
    if debt_items:
        stat_rows.append(
            (
                "Qarzga nakladnoylar (to'lanmagan)",
                round(getattr(summary, "total_debt_nakladnoy", sum(n.amount for n in debt_items))),
            )
        )

    next_r = _kv_block(
        ws_sum,
        next_r + 1,
        "Kassa qarzi va Statistika",
        stat_rows,
        highlight_label="Umumiy kassa qarzi qoldig'i",
    )
    ws_sum.column_dimensions["A"].width = 34
    ws_sum.column_dimensions["B"].width = 22
    ws_sum.sheet_view.showGridLines = False

    # Sheet 2: Nakladnoylar
    ws = wb.create_sheet("Nakladnoylar")
    ncols = 8
    _title(ws, f"NAKLADNOYLAR — {summary.session.report_date}", ncols)
    _header(
        ws,
        3,
        ["#", "Postavshik", "Summa", "Asl summa", "Guruhga yuborilgan", "Rasm", "Izoh", "Vaqt"],
    )
    for i, item in enumerate(items, start=1):
        r = 3 + i
        zebra = i % 2 == 0
        orig_val, cleaned_note = _extract_orig_and_note(item)
        in_group_lbl = "Ha" if getattr(item, "group_message_id", None) else "Yo'q"
        _body_row(
            ws,
            r,
            [i, item.supplier_name, round(item.amount), orig_val, in_group_lbl, "", cleaned_note, _ts(item.created_at)],
            money_cols=(3, 4),
            zebra=zebra,
        )
        _write_photo_cell(ws, r, 6, item, zebra)
    last = 3 + cnt
    if items:
        _total_row(
            ws,
            last + 1,
            "JAMI",
            2,
            {3: f"=SUM(C4:C{last})"},
            ncols,
        )
    _autowidth(ws, skip_rows=2)
    ws.column_dimensions["A"].width = 7
    _finish(ws, "A4", ncols, 3, last, landscape=True)

    # Sheet 3: Kirim va Qarzlar
    ws2 = wb.create_sheet("Kirim va Qarzlar")
    _title(ws2, f"KIRIM VA QARZLAR — {summary.session.report_date}", 5)
    _header(ws2, 3, ["#", "Turi", "Summa", "Izoh", "Vaqt"])
    type_labels = {
        "main": "Pul oldim",
        "kassa_debt": "Kassadan qarz",
        "kassa_repay": "Kassaga qaytarish",
        "expense": "Xarajat",
    }
    txs = list(summary.cash_transactions)
    for i, tx in enumerate(txs, start=1):
        _body_row(
            ws2,
            3 + i,
            [i, type_labels.get(tx.source_type, tx.source_type), round(tx.amount), tx.note, _ts(tx.created_at)],
            money_cols=(3,),
            zebra=i % 2 == 0,
        )
    if txs:
        _total_row(ws2, 4 + len(txs), "JAMI", 2, {3: f"=SUM(C4:C{3 + len(txs)})"}, 5)
    _autowidth(ws2, skip_rows=2)
    ws2.column_dimensions["A"].width = 7
    _finish(ws2, "A4", 5, 3, 3 + len(txs))

    # Optional Sheet 4: Unpaid credit nakladnoys (Qarzga)
    if debt_items:
        ws_d = wb.create_sheet("Qarzga (To'lanmagan)")
        _title(ws_d, f"QARZGA OLINGAN NAKLADNOYLAR — {summary.session.report_date}", 7)
        _header(ws_d, 3, ["#", "Postavshik", "Summa", "Asl summa", "Guruhga yuborilgan", "Rasm", "Vaqt"])
        for i, item in enumerate(debt_items, start=1):
            r = 3 + i
            zebra = i % 2 == 0
            orig_val, _ = _extract_orig_and_note(item)
            in_grp = "Ha" if getattr(item, "group_message_id", None) else "Yo'q"
            _body_row(
                ws_d,
                r,
                [i, item.supplier_name, round(item.amount), orig_val, in_grp, "", _ts(item.created_at)],
                money_cols=(3, 4),
                zebra=zebra,
            )
            _write_photo_cell(ws_d, r, 6, item, zebra)
        last_d = 3 + len(debt_items)
        _total_row(ws_d, last_d + 1, "JAMI QARZ", 2, {3: f"=SUM(C4:C{last_d})"}, 7)
        _autowidth(ws_d, skip_rows=2)
        ws_d.column_dimensions["A"].width = 7
        _finish(ws_d, "A4", 7, 3, last_d, landscape=True)

    # Optional Sheet 5: Non-cash nakladnoys (Karta / Perechesleniya)
    if noncash_items:
        ws_nc = wb.create_sheet("Karta va Perechesleniya")
        _title(ws_nc, f"KARTA VA PERECHESLENIYA — {summary.session.report_date}", 8)
        _header(
            ws_nc,
            3,
            ["#", "Postavshik", "To'lov turi", "Summa", "Asl summa", "Guruhga yuborilgan", "Rasm", "Vaqt"],
        )
        for i, item in enumerate(noncash_items, start=1):
            r = 3 + i
            zebra = i % 2 == 0
            orig_val, _ = _extract_orig_and_note(item)
            in_grp = "Ha" if getattr(item, "group_message_id", None) else "Yo'q"
            _body_row(
                ws_nc,
                r,
                [
                    i,
                    item.supplier_name,
                    _pm_label(getattr(item, "payment_method", "cash")),
                    round(item.amount),
                    orig_val,
                    in_grp,
                    "",
                    _ts(item.created_at),
                ],
                money_cols=(4, 5),
                zebra=zebra,
            )
            _write_photo_cell(ws_nc, r, 7, item, zebra)
        last_nc = 3 + len(noncash_items)
        _total_row(ws_nc, last_nc + 1, "JAMI (NAQDSIZ)", 3, {4: f"=SUM(D4:D{last_nc})"}, 8)
        _autowidth(ws_nc, skip_rows=2)
        ws_nc.column_dimensions["A"].width = 7
        _finish(ws_nc, "A4", 8, 3, last_nc, landscape=True)

    return _to_bytes(wb)


def build_range_excel(date_from: str, date_to: str, data: dict) -> bytes:
    """Export multi-day period workbook: Xulosa, Nakladnoylar, Kirim va Qarzlar, Postavshiklar."""
    wb = Workbook()
    sessions: Sequence[DailyCashSession] = data.get("sessions", [])
    nak_rows: Sequence[Tuple[Any, str]] = data.get("nakladnoys", [])
    cash_rows: Sequence[Tuple[Any, str]] = data.get("cash_txs", [])
    kassa_stats: dict = data.get("kassa_stats", {})

    total_spent = sum(float(n.amount) for n, _ in nak_rows)
    total_main_in = sum(float(t.amount) for t, _ in cash_rows if t.source_type == "main")
    total_kassa_debt = sum(float(t.amount) for t, _ in cash_rows if t.source_type == "kassa_debt")
    total_kassa_repay = sum(float(t.amount) for t, _ in cash_rows if t.source_type == "kassa_repay")
    total_expense = sum(float(t.amount) for t, _ in cash_rows if t.source_type == "expense")

    # Sheet 1: Xulosa + Kunlik kunlar
    ws_sum = wb.active
    ws_sum.title = "Xulosa"
    _title(ws_sum, f"HISOBOT ({date_from} — {date_to})", 8)
    r_next = _kv_block(
        ws_sum,
        3,
        "Davr bo'yicha umumiy ko'rsatkichlar",
        [
            ("Smena kunlari soni", len(sessions)),
            ("Nakladnoylar soni", len(nak_rows)),
            ("Pul oldim (kirim)", round(total_main_in)),
            ("Kassadan qarz (davr)", round(total_kassa_debt)),
            ("Kassaga qaytarilgan (davr)", round(total_kassa_repay)),
            ("Jami nakladnoy rasxod", round(total_spent)),
            ("Boshqa xarajatlar (davr)", round(total_expense)),
            ("Umumiy kassa qarzi qoldig'i", round(kassa_stats.get("outstanding", 0.0))),
        ],
        highlight_label="Jami nakladnoy rasxod",
    )

    hdr_row = r_next + 2
    ws_sum.cell(row=hdr_row - 1, column=1, value="Kunlar kesimida").font = SECTION_FONT
    _header(
        ws_sum,
        hdr_row,
        ["Sana", "Holati", "Boshlang'ich", "Qolishi kerak", "Sanalgan", "Farq", "Yopilgan vaqt"],
    )
    for i, s in enumerate(sessions, start=1):
        _body_row(
            ws_sum,
            hdr_row + i,
            [
                s.report_date,
                "Yopilgan" if s.status == "closed" else "Ochiq",
                round(s.opening_balance),
                round(s.expected_cash),
                round(s.actual_counted_cash or 0),
                round(s.difference or 0),
                _ts(s.closed_at),
            ],
            money_cols=(3, 4, 5, 6),
            zebra=i % 2 == 0,
        )
        ws_sum.cell(row=hdr_row + i, column=6).fill = (
            GOOD_FILL if round(s.difference or 0) == 0 else BAD_FILL
        )
    _autowidth(ws_sum, skip_rows=2)
    ws_sum.column_dimensions["A"].width = 30
    ws_sum.sheet_view.showGridLines = False

    # Sheet 2: Nakladnoylar
    ws_nak = wb.create_sheet("Nakladnoylar")
    _title(ws_nak, f"NAKLADNOYLAR ({date_from} — {date_to})", 9)
    _header(
        ws_nak,
        3,
        ["#", "Sana", "Vaqt", "Postavshik", "Summa", "Asl summa", "Guruhga yuborilgan", "Rasm", "Izoh"],
    )
    for i, (pay, r_date) in enumerate(nak_rows, start=1):
        row_i = 3 + i
        zebra = i % 2 == 0
        orig_val, cleaned_note = _extract_orig_and_note(pay)
        in_grp = "Ha" if getattr(pay, "group_message_id", None) else "Yo'q"
        tm = format_local_dt(pay.created_at, "%H:%M") if pay.created_at else ""
        _body_row(
            ws_nak,
            row_i,
            [i, r_date, tm, pay.supplier_name, round(pay.amount), orig_val, in_grp, "", cleaned_note],
            money_cols=(5, 6),
            zebra=zebra,
        )
        _write_photo_cell(ws_nak, row_i, 8, pay, zebra)
    last_n = 3 + len(nak_rows)
    if nak_rows:
        _total_row(ws_nak, last_n + 1, "JAMI", 4, {5: f"=SUM(E4:E{last_n})"}, 9)
    _autowidth(ws_nak, skip_rows=2)
    ws_nak.column_dimensions["A"].width = 7
    _finish(ws_nak, "A4", 9, 3, last_n, landscape=True)

    # Sheet 3: Kirim va Qarzlar
    ws_c = wb.create_sheet("Kirim va Qarzlar")
    _title(ws_c, f"KIRIM VA QARZLAR ({date_from} — {date_to})", 6)
    _header(ws_c, 3, ["#", "Sana", "Turi", "Summa", "Izoh", "Vaqt"])
    type_labels = {
        "main": "Pul oldim",
        "kassa_debt": "Kassadan qarz",
        "kassa_repay": "Kassaga qaytarish",
        "expense": "Xarajat",
    }
    for i, (tx, r_date) in enumerate(cash_rows, start=1):
        _body_row(
            ws_c,
            3 + i,
            [i, r_date, type_labels.get(tx.source_type, tx.source_type), round(tx.amount), tx.note, _ts(tx.created_at)],
            money_cols=(4,),
            zebra=i % 2 == 0,
        )
    last_c = 3 + len(cash_rows)
    if cash_rows:
        _total_row(ws_c, last_c + 1, "JAMI", 3, {4: f"=SUM(D4:D{last_c})"}, 6)
    _autowidth(ws_c, skip_rows=2)
    ws_c.column_dimensions["A"].width = 7
    _finish(ws_c, "A4", 6, 3, last_c)

    # Sheet 4: Postavshiklar
    ws_s = wb.create_sheet("Postavshiklar")
    totals: dict[str, list[Any]] = {}
    for pay, _ in nak_rows:
        k = pay.supplier_name.strip().lower()
        e = totals.setdefault(k, [pay.supplier_name.strip(), 0, 0.0])
        e[1] += 1
        e[2] += float(pay.amount)
    ordered = sorted(totals.values(), key=lambda x: -x[2])
    _title(ws_s, f"POSTAVSHIKLAR ({date_from} — {date_to})", 4)
    _header(ws_s, 3, ["#", "Postavshik", "Nakladnoy soni", "Jami summa"])
    for i, (name, cnt, total) in enumerate(ordered, start=1):
        _body_row(ws_s, 3 + i, [i, name, int(cnt), round(total)], money_cols=(3, 4), zebra=i % 2 == 0)
    last_s = 3 + len(ordered)
    if ordered:
        _total_row(ws_s, last_s + 1, "JAMI", 2, {3: f"=SUM(C4:C{last_s})", 4: f"=SUM(D4:D{last_s})"}, 4)
        _add_bar_chart(ws_s, "Top postavshiklar", min(len(ordered), 10), anchor="F3")
    _autowidth(ws_s, skip_rows=2)
    ws_s.column_dimensions["A"].width = 7
    _finish(ws_s, "A4", 4, 3, last_s, landscape=True)

    return _to_bytes(wb)


def _add_bar_chart(ws: Worksheet, title: str, item_count: int, anchor: str = "F3") -> None:
    if item_count <= 0:
        return
    chart = BarChart()
    chart.type = "col"
    chart.title = title
    chart.style = 10
    chart.legend = None
    data_ref = Reference(ws, min_col=4, min_row=3, max_row=3 + item_count)
    cats_ref = Reference(ws, min_col=2, min_row=4, max_row=3 + item_count)
    chart.add_data(data_ref, titles_from_data=True)
    chart.set_categories(cats_ref)
    chart.width = 16
    chart.height = 10
    ws.add_chart(chart, anchor)


def build_history_excel(sessions: Sequence[DailyCashSession]) -> bytes:
    """Export closed session history list into XLSX bytes."""
    wb = Workbook()
    ws = wb.active
    ws.title = "Kunlik Tarix"
    headers = ["ID", "Sana", "Boshlang'ich qoldiq", "Qolishi kerak edi", "Sanalgan pul", "Farq", "Yopilgan vaqt"]
    ncols = len(headers)
    _title(ws, "KUNLIK TARIX", ncols)
    _header(ws, 3, headers)
    for i, sess in enumerate(sessions, start=1):
        _body_row(
            ws,
            3 + i,
            [
                sess.id,
                sess.report_date,
                round(sess.opening_balance),
                round(sess.expected_cash),
                round(sess.actual_counted_cash or 0),
                round(sess.difference or 0),
                _ts(sess.closed_at),
            ],
            money_cols=(3, 4, 5, 6),
            zebra=i % 2 == 0,
        )
        diff_cell = ws.cell(row=3 + i, column=6)
        diff_cell.fill = GOOD_FILL if round(sess.difference or 0) == 0 else BAD_FILL
    _autowidth(ws, minimum=14, skip_rows=2)
    _finish(ws, "A4", ncols, 3, 3 + len(sessions))
    return _to_bytes(wb)


def build_prixod_excel(report: PrixodReport) -> bytes:
    """Export a PrixodReport and its itemized rows into XLSX bytes."""
    wb = Workbook()
    ws = wb.active
    ws.title = f"Prixod {report.report_date}"
    headers = ["#", "Postavshik (YesPOS)", "Ko'rsatiladigan nom", "Toifa", "Izoh", "Tannarx", "Sotuv narx"]
    ncols = len(headers)
    _title(ws, f"PRIXOD (ITOG) — {report.report_date}", ncols)
    _header(ws, 3, headers)
    rows = list(report.rows)
    for i, row in enumerate(rows, start=1):
        _body_row(
            ws,
            3 + i,
            [
                row.row_num,
                row.supplier_raw,
                row.supplier_display,
                row.category,
                row.note_raw,
                round(row.cost),
                round(row.price),
            ],
            money_cols=(6, 7),
            zebra=i % 2 == 0,
        )
    if rows:
        end = 3 + len(rows)
        _total_row(ws, end + 1, "JAMI", 2, {6: f"=SUM(F4:F{end})", 7: f"=SUM(G4:G{end})"}, ncols)
    _autowidth(ws, skip_rows=2)
    ws.column_dimensions["A"].width = 8
    _finish(ws, "A4", ncols, 3, 3 + len(rows))
    return _to_bytes(wb)


def build_sverka_excel(month: str, rows: Sequence[dict]) -> bytes:
    """Supplier reconciliation workbook: Ranking+Chart, Pivot matrix, All payments."""
    wb = Workbook()
    ws = wb.active
    ws.title = "Postavshiklar"
    totals: dict[str, list[Any]] = {}
    for r in rows:
        key = r["supplier"].lower()
        entry = totals.setdefault(key, [r["supplier"], 0, 0.0])
        entry[1] += 1
        entry[2] += r["amount"]
    ordered = sorted(totals.values(), key=lambda e: -e[2])

    _title(ws, f"POSTAVSHIKLAR SVERKASI — {month}", 4)
    _header(ws, 3, ["#", "Postavshik", "Nakladnoylar soni", "Jami summa"])
    for i, (name, cnt, total) in enumerate(ordered, start=1):
        _body_row(ws, 3 + i, [i, name, int(cnt), round(total)], money_cols=(3, 4), zebra=i % 2 == 0)
    if ordered:
        end = 3 + len(ordered)
        _total_row(ws, end + 1, "JAMI", 2, {3: f"=SUM(C4:C{end})", 4: f"=SUM(D4:D{end})"}, 4)
        _add_bar_chart(ws, f"Postavshiklar — {month}", min(len(ordered), 10), anchor="F3")
    _autowidth(ws, skip_rows=2)
    ws.column_dimensions["A"].width = 8
    _finish(ws, "A4", 4, 3, 3 + len(ordered), landscape=True)

    # Sheet 2: Pivot matrix (Kunlar x Postavshiklar)
    ws_piv = wb.create_sheet("Kunlar x Postavshiklar")
    sup_names = [name for name, _, _ in ordered]
    dates = sorted({r["date"] for r in rows})
    pivot_map: dict[Tuple[str, str], float] = {}
    for r in rows:
        k = (r["date"], r["supplier"].lower())
        pivot_map[k] = pivot_map.get(k, 0.0) + r["amount"]

    piv_headers = ["Sana"] + sup_names + ["JAMI"]
    piv_ncols = len(piv_headers)
    _title(ws_piv, f"KUNLAR x POSTAVSHIKLAR — {month}", max(piv_ncols, 2))
    _header(ws_piv, 3, piv_headers)
    money_cols = tuple(range(2, piv_ncols + 1))
    last_sup_letter = get_column_letter(1 + len(sup_names)) if sup_names else "A"
    for i, d_str in enumerate(dates, start=1):
        row_idx = 3 + i
        vals: list[Any] = [d_str]
        for s_name in sup_names:
            amt = pivot_map.get((d_str, s_name.lower()), 0.0)
            vals.append(round(amt) if amt > 0 else "")
        vals.append(f"=SUM(B{row_idx}:{last_sup_letter}{row_idx})" if sup_names else 0)
        _body_row(ws_piv, row_idx, vals, money_cols=money_cols, zebra=i % 2 == 0)

    if dates:
        end_piv = 3 + len(dates)
        sum_cols = {
            col_i: f"=SUM({get_column_letter(col_i)}4:{get_column_letter(col_i)}{end_piv})"
            for col_i in range(2, piv_ncols + 1)
        }
        _total_row(ws_piv, end_piv + 1, "JAMI", 1, sum_cols, piv_ncols)
    _autowidth(ws_piv, minimum=12, skip_rows=2)
    _finish(ws_piv, "B4", max(piv_ncols, 2), 3, 3 + len(dates), landscape=True)

    # Sheet 3: Barcha to'lovlar
    ws2 = wb.create_sheet("Barcha to'lovlar")
    _title(ws2, f"BARCHA TO'LOVLAR — {month}", 8)
    _header(
        ws2,
        3,
        ["Sana", "Vaqt", "Postavshik", "Summa", "Asl summa", "Guruhga yuborilgan", "Izoh", "To'lov turi"],
    )
    for i, r in enumerate(rows, start=1):
        orig = r.get("original_amount")
        orig_cell = round(orig) if (orig is not None and round(orig) != round(r["amount"])) else ""
        _, cleaned_note = _parse_legacy_original_amount(r.get("note", ""))
        in_grp = "Ha" if r.get("in_group") else "Yo'q"
        pm_lbl = _pm_label(r.get("payment_method", "cash"))
        _body_row(
            ws2,
            3 + i,
            [r["date"], r["time"], r["supplier"], round(r["amount"]), orig_cell, in_grp, cleaned_note, pm_lbl],
            money_cols=(4, 5),
            zebra=i % 2 == 0,
        )
    if rows:
        end = 3 + len(rows)
        _total_row(ws2, end + 1, "JAMI", 3, {4: f"=SUM(D4:D{end})"}, 8)
    _autowidth(ws2, skip_rows=2)
    _finish(ws2, "A4", 8, 3, 3 + len(rows), landscape=True)
    return _to_bytes(wb)
