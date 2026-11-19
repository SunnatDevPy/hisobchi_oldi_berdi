"""OpenPyXL Excel report generator for daily wallet sessions and prixod reports."""

from __future__ import annotations

import io
from typing import Sequence

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill

from database.crud import SessionSummary
from database.models import DailyCashSession, PrixodReport


HEADER_FILL = PatternFill(start_color="1F4E78", end_color="1F4E78", fill_type="solid")
HEADER_FONT = Font(color="FFFFFF", bold=True, size=11)
BOLD_FONT = Font(bold=True, size=11)
MONEY_FORMAT = "#,##0"


def build_session_excel(summary: SessionSummary) -> bytes:
    """Export a single DailyCashSession (cash-in & nakladnoy payments) into XLSX bytes."""
    wb = Workbook()
    ws = wb.active
    ws.title = f"Hisob {summary.session.report_date}"

    ws["A1"] = f"KUNLIK HISOB-KITOB ({summary.session.report_date})"
    ws["A1"].font = Font(bold=True, size=13)

    overview = [
        ("Holati:", "Yopilgan" if summary.session.status == "closed" else "Ochiq"),
        ("Kechadan qoldiq:", summary.opening_balance),
        ("Asosiy olingan pul:", summary.main_cash_in),
        ("Kassadan olingan (Qarz):", summary.kassa_debt_today),
        ("Kassaga qaytarilgan:", summary.kassa_repay_today),
        ("Jami kirim:", summary.total_available_inflow),
        ("Jami nakladnoy rasxod:", summary.total_nakladnoy_spent),
        ("Qo'lda qolishi kerak:", summary.expected_cash),
        ("Qo'lda sanalgan pul:", summary.session.actual_counted_cash or 0),
        ("Farq:", summary.session.difference or 0),
    ]
    for row_idx, (label, val) in enumerate(overview, start=3):
        ws.cell(row=row_idx, column=1, value=label).font = BOLD_FONT
        c = ws.cell(row=row_idx, column=2, value=val)
        if isinstance(val, (int, float)):
            c.number_format = MONEY_FORMAT

    start_row = 15
    headers = ["#", "Postavshik", "Summa", "Izoh", "Vaqt"]
    for col_idx, h in enumerate(headers, start=1):
        cell = ws.cell(row=start_row, column=col_idx, value=h)
        cell.fill = HEADER_FILL
        cell.font = HEADER_FONT
        cell.alignment = Alignment(horizontal="center")

    for i, item in enumerate(summary.confirmed_nakladnoys, start=1):
        r = start_row + i
        ws.cell(row=r, column=1, value=i)
        ws.cell(row=r, column=2, value=item.supplier_name)
        amt_cell = ws.cell(row=r, column=3, value=round(item.amount))
        amt_cell.number_format = MONEY_FORMAT
        ws.cell(row=r, column=4, value=item.note or "")
        ts = item.created_at.strftime("%Y-%m-%d %H:%M") if item.created_at else ""
        ws.cell(row=r, column=5, value=ts)

    # Cash transactions sheet
    ws2 = wb.create_sheet("Kirim va Qarzlar")
    tx_headers = ["#", "Turi", "Summa", "Izoh", "Vaqt"]
    for col_idx, h in enumerate(tx_headers, start=1):
        cell = ws2.cell(row=1, column=col_idx, value=h)
        cell.fill = HEADER_FILL
        cell.font = HEADER_FONT

    type_labels = {
        "main": "Asosiy pul olish",
        "kassa_debt": "Kassadan qarz",
        "kassa_repay": "Kassaga qaytarish",
    }
    for i, tx in enumerate(summary.cash_transactions, start=1):
        r = i + 1
        ws2.cell(row=r, column=1, value=i)
        ws2.cell(row=r, column=2, value=type_labels.get(tx.source_type, tx.source_type))
        c = ws2.cell(row=r, column=3, value=round(tx.amount))
        c.number_format = MONEY_FORMAT
        ws2.cell(row=r, column=4, value=tx.note)
        ws2.cell(row=r, column=5, value=tx.created_at.strftime("%Y-%m-%d %H:%M") if tx.created_at else "")

    for sheet in (ws, ws2):
        sheet.column_dimensions["A"].width = 26
        sheet.column_dimensions["B"].width = 28
        sheet.column_dimensions["C"].width = 18
        sheet.column_dimensions["D"].width = 24
        sheet.column_dimensions["E"].width = 20

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def build_history_excel(sessions: Sequence[DailyCashSession]) -> bytes:
    """Export closed session history list into XLSX bytes."""
    wb = Workbook()
    ws = wb.active
    ws.title = "Kunlik Tarix"

    headers = [
        "ID",
        "Sana",
        "Boshlang'ich qoldiq",
        "Qolishi kerak edi",
        "Sanalgan pul",
        "Farq",
        "Yopilgan vaqt",
    ]
    for col_idx, h in enumerate(headers, start=1):
        cell = ws.cell(row=1, column=col_idx, value=h)
        cell.fill = HEADER_FILL
        cell.font = HEADER_FONT

    for i, sess in enumerate(sessions, start=2):
        ws.cell(row=i, column=1, value=sess.id)
        ws.cell(row=i, column=2, value=sess.report_date)
        for col_i, val in (
            (3, sess.opening_balance),
            (4, sess.expected_cash),
            (5, sess.actual_counted_cash or 0),
            (6, sess.difference or 0),
        ):
            c = ws.cell(row=i, column=col_i, value=round(val))
            c.number_format = MONEY_FORMAT
        ws.cell(
            row=i,
            column=7,
            value=sess.closed_at.strftime("%Y-%m-%d %H:%M") if sess.closed_at else "",
        )

    for col_letter in ("A", "B", "C", "D", "E", "F", "G"):
        ws.column_dimensions[col_letter].width = 20

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def build_prixod_excel(report: PrixodReport) -> bytes:
    """Export a PrixodReport and its itemized rows into XLSX bytes."""
    wb = Workbook()
    ws = wb.active
    ws.title = f"Prixod {report.report_date}"

    headers = ["#", "Postavshik (YesPOS)", "Ko'rsatiladigan nom", "Toifa", "Izoh", "Tannarx", "Sotuv narx"]
    for col_idx, h in enumerate(headers, start=1):
        cell = ws.cell(row=1, column=col_idx, value=h)
        cell.fill = HEADER_FILL
        cell.font = HEADER_FONT

    for idx, row in enumerate(report.rows, start=2):
        ws.cell(row=idx, column=1, value=row.row_num)
        ws.cell(row=idx, column=2, value=row.supplier_raw)
        ws.cell(row=idx, column=3, value=row.supplier_display)
        ws.cell(row=idx, column=4, value=row.category)
        ws.cell(row=idx, column=5, value=row.note_raw)
        c1 = ws.cell(row=idx, column=6, value=round(row.cost))
        c1.number_format = MONEY_FORMAT
        c2 = ws.cell(row=idx, column=7, value=round(row.price))
        c2.number_format = MONEY_FORMAT

    for col_letter, width in (("A", 8), ("B", 30), ("C", 26), ("D", 14), ("E", 18), ("F", 18), ("G", 18)):
        ws.column_dimensions[col_letter].width = width

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()
