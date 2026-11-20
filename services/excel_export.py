"""OpenPyXL Excel report generator for daily wallet sessions and prixod reports."""

from __future__ import annotations

import io
from typing import Any, Sequence

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.worksheet import Worksheet

from database.crud import SessionSummary, format_local_dt
from database.models import DailyCashSession, PrixodReport


NAVY = "1F4E78"
HEADER_FILL = PatternFill(start_color=NAVY, end_color=NAVY, fill_type="solid")
HEADER_FONT = Font(color="FFFFFF", bold=True, size=11)
TITLE_FONT = Font(bold=True, size=15, color=NAVY)
BOLD_FONT = Font(bold=True, size=11)
LABEL_FILL = PatternFill(start_color="DDEBF7", end_color="DDEBF7", fill_type="solid")
ZEBRA_FILL = PatternFill(start_color="F5F9FD", end_color="F5F9FD", fill_type="solid")
TOTAL_FILL = PatternFill(start_color="FFF2CC", end_color="FFF2CC", fill_type="solid")
GOOD_FILL = PatternFill(start_color="E2EFDA", end_color="E2EFDA", fill_type="solid")
BAD_FILL = PatternFill(start_color="FCE4D6", end_color="FCE4D6", fill_type="solid")
THIN = Side(style="thin", color="BFBFBF")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
MONEY_FORMAT = '#,##0;[Red]-#,##0'


def _title(ws: Worksheet, text: str, last_col: int) -> None:
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=last_col)
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
    ws.row_dimensions[row].height = 22


def _body_row(ws: Worksheet, row: int, values: Sequence[Any], money_cols: Sequence[int], zebra: bool) -> None:
    for col, val in enumerate(values, start=1):
        c = ws.cell(row=row, column=col, value=val)
        c.border = BORDER
        c.alignment = Alignment(vertical="center", wrap_text=True, horizontal="right" if col in money_cols else "left")
        if col in money_cols:
            c.number_format = MONEY_FORMAT
        if zebra:
            c.fill = ZEBRA_FILL


def _total_row(ws: Worksheet, row: int, label: str, label_col: int, sums: dict[int, Any], ncols: int) -> None:
    for col in range(1, ncols + 1):
        c = ws.cell(row=row, column=col)
        c.fill = TOTAL_FILL
        c.border = BORDER
        c.font = BOLD_FONT
    ws.cell(row=row, column=label_col, value=label)
    for col, formula in sums.items():
        c = ws.cell(row=row, column=col, value=formula)
        c.number_format = MONEY_FORMAT
        c.alignment = Alignment(horizontal="right")


def _autowidth(ws: Worksheet, minimum: int = 8, maximum: int = 45, skip_rows: int = 0) -> None:
    widths: dict[int, int] = {}
    for row in ws.iter_rows(min_row=skip_rows + 1):
        for c in row:
            if c.value is None or type(c).__name__ == "MergedCell":
                continue
            text = f"{c.value:,.0f}" if isinstance(c.value, (int, float)) else str(c.value)
            widths[c.column] = max(widths.get(c.column, 0), max(len(line) for line in text.split("\n")))
    for col, w in widths.items():
        ws.column_dimensions[get_column_letter(col)].width = min(max(w + 3, minimum), maximum)


def _finish(ws: Worksheet, freeze: str | None, last_col: int, header_row: int, last_row: int) -> None:
    if freeze:
        ws.freeze_panes = freeze
    if last_row > header_row:
        ws.auto_filter.ref = f"A{header_row}:{get_column_letter(last_col)}{last_row}"
    ws.sheet_view.showGridLines = False
    ws.page_setup.orientation = "portrait"
    ws.page_setup.fitToWidth = 1
    ws.page_setup.fitToHeight = 0
    ws.sheet_properties.pageSetUpPr.fitToPage = True


def _ts(dt: Any) -> str:
    return format_local_dt(dt, "%d.%m.%Y %H:%M") if dt else ""


def _to_bytes(wb: Workbook) -> bytes:
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def build_session_excel(summary: SessionSummary) -> bytes:
    """Export a single DailyCashSession (cash-in & nakladnoy payments) into XLSX bytes."""
    wb = Workbook()
    ws = wb.active
    ws.title = f"Hisob {summary.session.report_date}"
    ncols = 5
    _title(ws, f"KUNLIK HISOB-KITOB — {summary.session.report_date}", ncols)

    diff = summary.session.difference or 0
    overview = [
        ("Holati", "Yopilgan" if summary.session.status == "closed" else "Ochiq"),
        ("Kechadan qoldiq", summary.opening_balance),
        ("Asosiy olingan pul", summary.main_cash_in),
        ("Kassadan olingan (qarz)", summary.kassa_debt_today),
        ("Kassaga qaytarilgan", summary.kassa_repay_today),
        ("Jami kirim", summary.total_available_inflow),
        ("Jami nakladnoy rasxod", summary.total_nakladnoy_spent),
        ("Qo'lda qolishi kerak", summary.expected_cash),
        ("Qo'lda sanalgan pul", summary.session.actual_counted_cash or 0),
        ("Farq", diff),
    ]
    row = 3
    for label, val in overview:
        lc = ws.cell(row=row, column=1, value=label)
        lc.font = BOLD_FONT
        lc.fill = LABEL_FILL
        lc.border = BORDER
        vc = ws.cell(row=row, column=2, value=val)
        vc.border = BORDER
        vc.alignment = Alignment(horizontal="right")
        if isinstance(val, (int, float)):
            vc.number_format = MONEY_FORMAT
        if label == "Qo'lda qolishi kerak":
            vc.font = BOLD_FONT
            vc.fill = TOTAL_FILL
        if label == "Farq":
            vc.fill = GOOD_FILL if round(diff) == 0 else BAD_FILL
            vc.font = BOLD_FONT
        row += 1

    header_row = row + 2
    ws.cell(row=header_row - 1, column=1, value="Nakladnoylar (berilgan pullar)").font = Font(
        bold=True, size=12, color=NAVY
    )
    _header(ws, header_row, ["#", "Postavshik", "Summa", "Izoh", "Vaqt"])
    items = list(summary.confirmed_nakladnoys)
    for i, item in enumerate(items, start=1):
        _body_row(
            ws,
            header_row + i,
            [i, item.supplier_name, round(item.amount), item.note or "", _ts(item.created_at)],
            money_cols=(3,),
            zebra=i % 2 == 0,
        )
    last = header_row + len(items)
    if items:
        _total_row(ws, last + 1, "JAMI", 2, {3: f"=SUM(C{header_row + 1}:C{last})"}, ncols)
    _autowidth(ws, skip_rows=2)
    ws.column_dimensions["A"].width = 26
    _finish(ws, None, ncols, header_row, last)
    ws.auto_filter.ref = None

    ws2 = wb.create_sheet("Kirim va Qarzlar")
    _title(ws2, f"KIRIM VA QARZLAR — {summary.session.report_date}", 5)
    _header(ws2, 3, ["#", "Turi", "Summa", "Izoh", "Vaqt"])
    type_labels = {
        "main": "Asosiy pul olish",
        "kassa_debt": "Kassadan qarz",
        "kassa_repay": "Kassaga qaytarish",
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
    _finish(ws2, "A4", 5, 3, 3 + len(txs))

    return _to_bytes(wb)


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
            [row.row_num, row.supplier_raw, row.supplier_display, row.category, row.note_raw,
             round(row.cost), round(row.price)],
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
    """Supplier reconciliation workbook: summary sheet + all payments sheet."""
    wb = Workbook()
    ws = wb.active
    ws.title = "Postavshiklar"
    totals: dict[str, list[float]] = {}
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
    _autowidth(ws, skip_rows=2)
    ws.column_dimensions["A"].width = 8
    _finish(ws, "A4", 4, 3, 3 + len(ordered))

    ws2 = wb.create_sheet("Barcha to'lovlar")
    _title(ws2, f"BARCHA TO'LOVLAR — {month}", 5)
    _header(ws2, 3, ["Sana", "Vaqt", "Postavshik", "Summa", "Izoh"])
    for i, r in enumerate(rows, start=1):
        _body_row(
            ws2, 3 + i, [r["date"], r["time"], r["supplier"], round(r["amount"]), r["note"]],
            money_cols=(4,), zebra=i % 2 == 0,
        )
    if rows:
        end = 3 + len(rows)
        _total_row(ws2, end + 1, "JAMI", 3, {4: f"=SUM(D4:D{end})"}, 5)
    _autowidth(ws2, skip_rows=2)
    _finish(ws2, "A4", 5, 3, 3 + len(rows))
    return _to_bytes(wb)