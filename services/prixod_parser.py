"""YesPOS 'Документы о приемке товара' CSV/XLSX parser and ITOG 👑 formatter."""

from __future__ import annotations

import csv
import io
import re
from dataclasses import dataclass, field
from datetime import datetime
from typing import Dict, List, Optional, Sequence, Tuple
from zoneinfo import ZoneInfo

from openpyxl import load_workbook

from config import get_settings
from database.models import PrixodRow, SupplierConfig
from services.gemini_ai import format_uzs, parse_uzbek_amount


DATE_NOTE_PATTERN = re.compile(r"\b(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?\b")
PERIOD_PATTERN = re.compile(r"Период\s+(\d{2}\.\d{2}\.\d{4})", re.IGNORECASE)


@dataclass
class ParsedRowItem:
    """Single parsed incoming receipt document row."""

    row_num: int
    supplier_raw: str
    supplier_display: str
    note_raw: str
    cost: float
    price: float
    category: str  # "qarz" | "nakladnoy" | "karta" | "old_date"
    old_date_label: Optional[str] = None
    created_at_str: str = ""


@dataclass
class ParsedPrixodResult:
    """Complete parsed result ready for DB persistence and formatting."""

    report_date: str  # DD.MM.YY
    rows: List[ParsedRowItem] = field(default_factory=list)
    total_cost: float = 0.0
    total_price: float = 0.0
    formatted_text: str = ""


def _parse_number(val: object) -> float:
    """Convert cell/string number into float safely."""
    if val is None:
        return 0.0
    if isinstance(val, (int, float)):
        return float(val)
    text = str(val).strip().replace("\u00a0", "").replace(" ", "")
    if not text:
        return 0.0
    # Handle 161899.98 or 161899,98
    if "," in text and "." not in text:
        parts = text.split(",")
        if len(parts) == 2 and len(parts[1]) <= 2:
            text = text.replace(",", ".")
        else:
            text = text.replace(",", "")
    try:
        return float(text)
    except ValueError:
        return 0.0


def _match_supplier(
    supplier_name: str, supplier_configs: Sequence[SupplierConfig]
) -> Optional[SupplierConfig]:
    """Match a raw YesPOS supplier string against configured suppliers and aliases."""
    norm = " ".join(supplier_name.strip().upper().split())
    if not norm:
        return None

    # First exact match on display_name or alias
    for cfg in supplier_configs:
        if not cfg.is_active:
            continue
        disp_norm = " ".join(cfg.display_name.strip().upper().split())
        if norm == disp_norm:
            return cfg
        aliases = [" ".join(a.strip().upper().split()) for a in cfg.aliases.split(",") if a.strip()]
        if norm in aliases:
            return cfg

    # Second substring match (longest alias first to avoid false positives)
    best_cfg: Optional[SupplierConfig] = None
    best_len = 0
    for cfg in supplier_configs:
        if not cfg.is_active:
            continue
        candidates = [cfg.display_name] + [a for a in cfg.aliases.split(",") if a.strip()]
        for cand in candidates:
            cand_norm = " ".join(cand.strip().upper().split())
            if len(cand_norm) >= 4 and (cand_norm in norm or norm in cand_norm):
                if len(cand_norm) > best_len:
                    best_len = len(cand_norm)
                    best_cfg = cfg
    return best_cfg


def _extract_date_from_note(note: str) -> Optional[str]:
    """Extract DD.MM label if note contains a date like 16.11.2026 or 16.11."""
    if not note:
        return None
    m = DATE_NOTE_PATTERN.search(note.strip())
    if not m:
        return None
    day, month = int(m.group(1)), int(m.group(2))
    if 1 <= day <= 31 and 1 <= month <= 12:
        return f"{day:02d}.{month:02d}"
    return None


def _categorize_row(
    supplier_raw: str,
    note_raw: str,
    supplier_configs: Sequence[SupplierConfig],
) -> Tuple[str, str, Optional[str]]:
    """Determine (category, supplier_display, old_date_label) for a single row."""
    date_label = _extract_date_from_note(note_raw)
    if date_label:
        return "old_date", supplier_raw.strip(), date_label

    note_low = note_raw.lower()
    if any(k in note_low for k in ("karta", "карта", "card", "click", "payme")):
        return "karta", supplier_raw.strip(), None

    matched = _match_supplier(supplier_raw, supplier_configs)
    if matched is not None:
        if matched.default_category == "karta":
            return "karta", matched.display_name, None
        if matched.default_category == "qarz":
            return "qarz", matched.display_name, None
        return matched.default_category, matched.display_name, None

    return "nakladnoy", supplier_raw.strip(), None


def _decode_csv_bytes(file_bytes: bytes) -> str:
    """Decode CSV bytes trying UTF-8-SIG, UTF-8, and CP1251."""
    for enc in ("utf-8-sig", "utf-8", "cp1251"):
        try:
            return file_bytes.decode(enc)
        except UnicodeDecodeError:
            continue
    return file_bytes.decode("utf-8", errors="replace")


def _extract_table_from_csv(file_bytes: bytes) -> List[List[str]]:
    """Read CSV bytes into a 2D list of strings."""
    text = _decode_csv_bytes(file_bytes)
    reader = csv.reader(io.StringIO(text))
    return [[str(c).strip() for c in row] for row in reader]


def _extract_table_from_xlsx(file_bytes: bytes) -> List[List[str]]:
    """Read XLSX bytes into a 2D list of strings."""
    wb = load_workbook(io.BytesIO(file_bytes), data_only=True)
    ws = wb.active
    table: List[List[str]] = []
    for row in ws.iter_rows(values_only=True):
        table.append(["" if c is None else str(c).strip() for c in row])
    return table


def _find_report_date_from_table(table: List[List[str]], created_dates: List[str]) -> str:
    """Extract DD.MM.YY from Period header or first document creation date."""
    for row in table[:10]:
        joined = " ".join(row)
        m = PERIOD_PATTERN.search(joined)
        if m:
            try:
                dt = datetime.strptime(m.group(1), "%d.%m.%Y")
                return dt.strftime("%d.%m.%y")
            except ValueError:
                pass
    for dt_str in created_dates:
        for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d", "%d.%m.%Y %H:%M:%S", "%d.%m.%Y"):
            try:
                dt = datetime.strptime(dt_str.strip(), fmt)
                return dt.strftime("%d.%m.%y")
            except ValueError:
                continue
    return datetime.now(ZoneInfo(get_settings().TIMEZONE)).strftime("%d.%m.%y")


def parse_yespos_table(
    file_bytes: bytes,
    filename: str,
    supplier_configs: Sequence[SupplierConfig],
) -> ParsedPrixodResult:
    """Parse YesPOS 'Документы о приемке товара' (.csv or .xlsx) into ParsedPrixodResult."""
    low_name = filename.lower()
    if low_name.endswith((".xlsx", ".xlsm")):
        table = _extract_table_from_xlsx(file_bytes)
    else:
        table = _extract_table_from_csv(file_bytes)

    header_idx: Optional[int] = None
    col_map: Dict[str, int] = {}
    for idx, row in enumerate(table):
        lowered = [c.lower() for c in row]
        if "поставщик" in lowered and ("стоимость" in lowered or "сумма" in lowered):
            header_idx = idx
            for col_i, col_name in enumerate(lowered):
                if col_name in ("№", "no", "n"):
                    col_map["num"] = col_i
                elif "статус" in col_name:
                    col_map["status"] = col_i
                elif "дата" in col_name:
                    col_map["date"] = col_i
                elif "примечание" in col_name or "izoh" in col_name:
                    col_map["note"] = col_i
                elif "поставщик" in col_name:
                    col_map["supplier"] = col_i
                elif "стоимость" in col_name or "сумма" in col_name:
                    col_map["cost"] = col_i
                elif "цена" in col_name:
                    col_map["price"] = col_i
            break

    if header_idx is None or "supplier" not in col_map or "cost" not in col_map:
        raise ValueError(
            "Fayl ichida YesPOS jadval ustunlari (Поставщик, Стоимость) topilmadi."
        )

    parsed_rows: List[ParsedRowItem] = []
    created_dates: List[str] = []

    for seq, row in enumerate(table[header_idx + 1 :], start=1):
        if not any(row):
            continue
        joined_row = " ".join(row).lower()
        if "жами" in joined_row or "итого" in joined_row or "total" in joined_row:
            break

        supplier_raw = row[col_map["supplier"]] if col_map["supplier"] < len(row) else ""
        if not supplier_raw:
            continue

        status_val = (
            row[col_map["status"]].lower() if "status" in col_map and col_map["status"] < len(row) else ""
        )
        if status_val and status_val not in ("выполненный", "completed", "done", "tasdiqlangan"):
            continue

        cost = _parse_number(row[col_map["cost"]] if col_map["cost"] < len(row) else 0)
        price = _parse_number(
            row[col_map["price"]] if "price" in col_map and col_map["price"] < len(row) else 0
        )
        note_raw = (
            row[col_map["note"]] if "note" in col_map and col_map["note"] < len(row) else ""
        )
        created_at_str = (
            row[col_map["date"]] if "date" in col_map and col_map["date"] < len(row) else ""
        )
        if created_at_str:
            created_dates.append(created_at_str)

        num_val = seq
        if "num" in col_map and col_map["num"] < len(row) and row[col_map["num"]].isdigit():
            num_val = int(row[col_map["num"]])

        category, supplier_display, old_date_label = _categorize_row(
            supplier_raw, note_raw, supplier_configs
        )

        parsed_rows.append(
            ParsedRowItem(
                row_num=num_val,
                supplier_raw=supplier_raw,
                supplier_display=supplier_display,
                note_raw=note_raw,
                cost=cost,
                price=price,
                category=category,
                old_date_label=old_date_label,
                created_at_str=created_at_str,
            )
        )

    if not parsed_rows:
        raise ValueError("Jadvalda bitta ham bajarilgan (Выполненный) qator topilmadi.")

    report_date = _find_report_date_from_table(table, created_dates)
    total_cost = sum(r.cost for r in parsed_rows)
    total_price = sum(r.price for r in parsed_rows)
    formatted_text = format_itog_report(report_date, parsed_rows, supplier_configs)

    return ParsedPrixodResult(
        report_date=report_date,
        rows=parsed_rows,
        total_cost=total_cost,
        total_price=total_price,
        formatted_text=formatted_text,
    )


def format_itog_report(
    report_date: str,
    rows: Sequence[ParsedRowItem | PrixodRow],
    supplier_configs: Sequence[SupplierConfig],
) -> str:
    """Format rows into the exact ITOG 👑DD.MM.YY template."""
    qarz_suppliers = [
        s for s in sorted(supplier_configs, key=lambda x: (x.order_num, x.id))
        if s.is_active and s.default_category == "qarz"
    ]

    # Group Qarz amounts per display_name preserving chronological order when timestamps exist,
    # otherwise preserving input row_num order.
    qarz_buckets: Dict[str, List[float]] = {s.display_name: [] for s in qarz_suppliers}

    def sort_key(item: ParsedRowItem | PrixodRow) -> Tuple[int, str, int]:
        created = getattr(item, "created_at_str", "")
        if created:
            return (0, created, item.row_num)
        return (1, "", item.row_num)

    ordered_rows = sorted(rows, key=sort_key)

    nakladnoy_sum = 0.0
    karta_sum = 0.0
    old_date_totals: Dict[str, float] = {}

    for r in ordered_rows:
        if r.category == "qarz":
            if r.supplier_display not in qarz_buckets:
                qarz_buckets[r.supplier_display] = []
            qarz_buckets[r.supplier_display].append(r.cost)
        elif r.category == "karta":
            karta_sum += r.cost
        elif r.category == "old_date":
            lbl = r.old_date_label or _extract_date_from_note(r.note_raw) or "Eski sana"
            old_date_totals[lbl] = old_date_totals.get(lbl, 0.0) + r.cost
        else:
            nakladnoy_sum += r.cost

    lines: List[str] = [
        f"ITOG 👑{report_date}",
        "===============================",
        "Qarz",
    ]

    idx = 1
    seen_names = set()
    for s in qarz_suppliers:
        seen_names.add(s.display_name)
        vals = qarz_buckets.get(s.display_name, [])
        if vals:
            expr = " + ".join(format_uzs(v) for v in vals)
            sep = ": " if s.display_name.lower() == "alisa pereches" else " "
            if s.display_name.upper() == "QASSOB":
                sep = "  "
            lines.append(f"{idx}) {s.display_name}{sep}{expr}")
        else:
            lines.append(f"{idx}) {s.display_name} ")
        idx += 1

    # Any extra Qarz suppliers dynamically toggled in draft
    for disp_name, vals in qarz_buckets.items():
        if disp_name in seen_names or not vals:
            continue
        expr = " + ".join(format_uzs(v) for v in vals)
        lines.append(f"{idx}) {disp_name} {expr}")
        idx += 1

    lines.append("===============================")
    lines.append(f"Nakladnoy {format_uzs(nakladnoy_sum)}")
    if karta_sum > 0:
        lines.append(f"karta: {format_uzs(karta_sum)}")
    for lbl, amt in old_date_totals.items():
        lines.append(f"{lbl}: {format_uzs(amt)}")
    lines.append("===============================")

    total_cost = sum(r.cost for r in rows)
    lines.append(f"Umumiy {format_uzs(total_cost)}")
    return "\n".join(lines)


def parse_manual_itog_text(
    text: str,
    supplier_configs: Sequence[SupplierConfig],
) -> ParsedPrixodResult:
    """
    Parse manually typed ITOG or supplier line list into structured ParsedPrixodResult.

    Example supported input:
        ITOG 👑18.11.26
        1) OMBOR 12 895 000 + 2 109 750
        2) QASSOB 18 985 900
        Nakladnoy 23 263 000
        karta: 525 000
        16.11: 409 400
    """
    now_tz = datetime.now(ZoneInfo(get_settings().TIMEZONE))
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    report_date = now_tz.strftime("%d.%m.%y")
    rows: List[ParsedRowItem] = []
    row_counter = 1

    for ln in lines:
        if ln.startswith("==="):
            continue
        low = ln.lower()
        if low.startswith("itog"):
            m = DATE_NOTE_PATTERN.search(ln)
            if m:
                yr = m.group(3) or now_tz.strftime("%y")
                if len(yr) == 4:
                    yr = yr[2:]
                report_date = f"{int(m.group(1)):02d}.{int(m.group(2)):02d}.{yr}"
            continue
        if low in ("qarz", "qarz:") or low.startswith("umumiy"):
            continue

        # Check numbered line: "1) OMBOR 12 895 000 + 2 109 750"
        num_line = re.match(r"^\d+\)\s*(.+)$", ln)
        if num_line:
            body = num_line.group(1).strip()
            # Split supplier name vs numeric expression at first digit
            m_digit = re.search(r"[:\s]+(\d[\d\s.+]*)$", body)
            if m_digit:
                sup_part = body[: m_digit.start()].strip(" :")
                expr_part = m_digit.group(1).strip()
                matched = _match_supplier(sup_part, supplier_configs)
                disp = matched.display_name if matched else sup_part
                # Split '+' expressions into individual rows so totals & expressions remain faithful
                sub_parts = [p.strip() for p in expr_part.split("+") if p.strip()]
                for sp in sub_parts:
                    amt = parse_uzbek_amount(sp) or 0.0
                    if amt > 0:
                        rows.append(
                            ParsedRowItem(
                                row_num=row_counter,
                                supplier_raw=sup_part,
                                supplier_display=disp,
                                note_raw="",
                                cost=amt,
                                price=0.0,
                                category="qarz",
                            )
                        )
                        row_counter += 1
            continue

        # Check "karta: 525 000"
        if low.startswith("karta"):
            amt = parse_uzbek_amount(ln)
            if amt and amt > 0:
                rows.append(
                    ParsedRowItem(
                        row_num=row_counter,
                        supplier_raw="Karta",
                        supplier_display="Karta",
                        note_raw="karta",
                        cost=amt,
                        price=0.0,
                        category="karta",
                    )
                )
                row_counter += 1
            continue

        # Check "nakladnoy 23 263 000"
        if low.startswith("nakladnoy"):
            amt = parse_uzbek_amount(ln)
            if amt and amt > 0:
                rows.append(
                    ParsedRowItem(
                        row_num=row_counter,
                        supplier_raw="Nakladnoy",
                        supplier_display="Nakladnoy",
                        note_raw="",
                        cost=amt,
                        price=0.0,
                        category="nakladnoy",
                    )
                )
                row_counter += 1
            continue

        # Check old date line like "16.11: 409 400"
        date_lbl = _extract_date_from_note(ln)
        if date_lbl:
            after_colon = ln.split(":", 1)[1] if ":" in ln else ln
            amt = parse_uzbek_amount(after_colon)
            if amt and amt > 0:
                rows.append(
                    ParsedRowItem(
                        row_num=row_counter,
                        supplier_raw=date_lbl,
                        supplier_display=date_lbl,
                        note_raw=date_lbl,
                        cost=amt,
                        price=0.0,
                        category="old_date",
                        old_date_label=date_lbl,
                    )
                )
                row_counter += 1
            continue

        # Generic "Supplier 500 000" line
        m_gen = re.search(r"(\d[\d\s.+]*)$", ln)
        if m_gen:
            sup_part = ln[: m_gen.start()].strip(" :-")
            amt = parse_uzbek_amount(m_gen.group(1))
            if sup_part and amt and amt > 0:
                cat, disp, old_lbl = _categorize_row(sup_part, "", supplier_configs)
                rows.append(
                    ParsedRowItem(
                        row_num=row_counter,
                        supplier_raw=sup_part,
                        supplier_display=disp,
                        note_raw="",
                        cost=amt,
                        price=0.0,
                        category=cat,
                        old_date_label=old_lbl,
                    )
                )
                row_counter += 1

    if not rows:
        raise ValueError("Matndan birorta ham summa yoki ta'minotchi ajratib bo'lmadi.")

    total_cost = sum(r.cost for r in rows)
    formatted_text = format_itog_report(report_date, rows, supplier_configs)
    return ParsedPrixodResult(
        report_date=report_date,
        rows=rows,
        total_cost=total_cost,
        total_price=0.0,
        formatted_text=formatted_text,
    )
