"""Generate a clean 1-page A4 PDF Akt-Sverka statement for a supplier using Pillow."""

from __future__ import annotations

from datetime import datetime
import io
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

_FONT_CANDIDATES_BOLD = (
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
    "C:/Windows/Fonts/segoeuib.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
)
_FONT_CANDIDATES_REGULAR = (
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans.ttf",
    "C:/Windows/Fonts/segoeui.ttf",
    "C:/Windows/Fonts/arial.ttf",
)


def _load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = _FONT_CANDIDATES_BOLD if bold else _FONT_CANDIDATES_REGULAR
    for path in candidates:
        if Path(path).is_file():
            try:
                return ImageFont.truetype(path, size=size)
            except Exception:
                continue
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def _clean_text(text: Any) -> str:
    s = str(text or "")
    for ch in ("ʻ", "ʼ", "‘", "’", "`"):
        s = s.replace(ch, "'")
    return s


def _fmt_uzs(val: Any, with_currency: bool = False) -> str:
    try:
        num = int(round(float(val or 0)))
    except Exception:
        num = 0
    formatted = f"{num:,}".replace(",", " ")
    return f"{formatted} so'm" if with_currency else formatted


def generate_supplier_sverka_pdf(profile: dict[str, Any]) -> bytes:
    """Render a crisp A4 (1240x1754 @ 150 DPI) supplier reconciliation PDF."""
    width, height = 1240, 1754
    img = Image.new("RGB", (width, height), (248, 250, 252))
    draw = ImageDraw.Draw(img)

    f_title = _load_font(34, bold=True)
    f_sub = _load_font(20, bold=False)
    f_sec = _load_font(22, bold=True)
    f_kpi_lbl = _load_font(17, bold=True)
    f_kpi_val = _load_font(25, bold=True)
    f_th = _load_font(17, bold=True)
    f_td = _load_font(17, bold=False)
    f_td_bold = _load_font(17, bold=True)
    f_foot = _load_font(16, bold=False)

    supplier = _clean_text(profile.get("supplier_name") or "Ta'minotchi")
    d_from = profile.get("date_from")
    d_to = profile.get("date_to")
    if d_from and d_to:
        period_str = f"{d_from} — {d_to}"
    elif d_from:
        period_str = f"{d_from} dan"
    elif d_to:
        period_str = f"{d_to} gacha"
    else:
        period_str = "Barcha davr"
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M")

    # 1. Header Banner
    draw.rounded_rectangle((48, 42, width - 48, 205), radius=24, fill=(30, 27, 75))
    draw.text((84, 70), "HISOBCHI — AKT SVERKA", font=f_title, fill=(255, 255, 255))
    draw.text(
        (84, 122),
        _clean_text(f"Ta'minotchi: {supplier}"),
        font=f_sec,
        fill=(199, 210, 254),
    )
    draw.text(
        (84, 158),
        _clean_text(f"Davr: {period_str}   |   Sana: {now_str}"),
        font=f_sub,
        fill=(165, 180, 252),
    )

    # 2. KPI Summary Cards (4 across)
    total_amt = float(profile.get("total_amount") or 0)
    total_cnt = int(profile.get("total_count") or 0)
    cash_amt = float(profile.get("cash_amount") or 0)
    card_tr_amt = float(profile.get("card_amount") or 0) + float(
        profile.get("transfer_amount") or 0
    )
    debt_amt = float(profile.get("unpaid_debt_amount") or 0)
    nasiya_bal = float(profile.get("nasiya_balance") or 0)

    kpis = [
        ("Jami xarid", f"{_fmt_uzs(total_amt)} ({total_cnt})", (67, 56, 202), (238, 242, 255)),
        ("Naqd to'langan", _fmt_uzs(cash_amt), (5, 150, 105), (236, 253, 245)),
        ("Karta / O'tkazma", _fmt_uzs(card_tr_amt), (37, 99, 235), (239, 246, 255)),
        (
            "Qarz qoldig'i",
            _fmt_uzs(debt_amt + max(0.0, nasiya_bal)),
            (217, 119, 6) if (debt_amt + nasiya_bal) > 0 else (5, 150, 105),
            (255, 251, 235) if (debt_amt + nasiya_bal) > 0 else (236, 253, 245),
        ),
    ]

    gap = 18
    card_w = (width - 96 - gap * 3) // 4
    y_kpi = 232
    for idx, (lbl, val, fg, bg) in enumerate(kpis):
        x0 = 48 + idx * (card_w + gap)
        x1 = x0 + card_w
        draw.rounded_rectangle((x0, y_kpi, x1, y_kpi + 112), radius=16, fill=bg, outline=fg, width=2)
        draw.text((x0 + 18, y_kpi + 18), _clean_text(lbl), font=f_kpi_lbl, fill=fg)
        draw.text((x0 + 18, y_kpi + 56), _clean_text(val), font=f_kpi_val, fill=(15, 23, 42))

    # 3. Table Section
    y_tbl = 374
    draw.text((52, y_tbl), "Amallar ro'yxati (so'm)", font=f_sec, fill=(15, 23, 42))
    y_tbl += 38

    col_x = [56, 145, 360, 620, 860]  # #, Sana, Usul, Holat, Summa
    draw.rounded_rectangle((48, y_tbl, width - 48, y_tbl + 46), radius=10, fill=(226, 232, 240))
    headers = ["#", "Sana", "To'lov usuli", "Holati", "Summa"]
    for cx, h_txt in zip(col_x, headers):
        draw.text((cx + 10, y_tbl + 12), h_txt, font=f_th, fill=(30, 41, 59))
    y_row = y_tbl + 52

    items: list[dict[str, Any]] = list(profile.get("items") or [])
    max_rows = 21
    shown = items[:max_rows]
    method_labels = {
        "cash": "Naqd",
        "card": "Karta",
        "transfer": "O'tkazma",
    }

    if not shown:
        draw.rounded_rectangle(
            (48, y_row, width - 48, y_row + 64),
            radius=10,
            fill=(255, 255, 255),
            outline=(226, 232, 240),
        )
        draw.text(
            (72, y_row + 20),
            "Tanlangan davrda nakladnoylar mavjud emas.",
            font=f_td,
            fill=(100, 116, 139),
        )
        y_row += 76
    else:
        for idx, it in enumerate(shown, start=1):
            row_bg = (255, 255, 255) if idx % 2 == 1 else (241, 245, 249)
            draw.rectangle((48, y_row, width - 48, y_row + 46), fill=row_bg)
            is_debt = bool(it.get("is_debt"))
            pm = str(it.get("payment_method") or "cash").lower()
            m_lbl = "Qarzga" if is_debt else method_labels.get(pm, "Naqd")
            st_lbl = "To'lanmagan" if is_debt else "To'langan"
            st_color = (217, 119, 6) if is_debt else (5, 150, 105)
            r_date = _clean_text(it.get("report_date") or str(it.get("created_at") or "")[:10])
            amt_txt = _fmt_uzs(it.get("amount"), with_currency=True)

            draw.text((col_x[0] + 10, y_row + 12), str(idx), font=f_td, fill=(71, 85, 105))
            draw.text((col_x[1] + 10, y_row + 12), r_date, font=f_td, fill=(15, 23, 42))
            draw.text((col_x[2] + 10, y_row + 12), _clean_text(m_lbl), font=f_td, fill=(51, 65, 85))
            draw.text((col_x[3] + 10, y_row + 12), _clean_text(st_lbl), font=f_td_bold, fill=st_color)
            draw.text((col_x[4] + 10, y_row + 12), amt_txt, font=f_td_bold, fill=(15, 23, 42))
            y_row += 46

        if len(items) > max_rows:
            rest = len(items) - max_rows
            draw.text(
                (64, y_row + 10),
                _clean_text(f"... va yana {rest} ta amal umumiy summaga kiritilgan."),
                font=f_foot,
                fill=(100, 116, 139),
            )
            y_row += 40

    # 4. Signature Footer
    sig_y = max(y_row + 48, height - 170)
    draw.line((48, sig_y - 22, width - 48, sig_y - 22), fill=(203, 213, 225), width=2)
    draw.text(
        (60, sig_y),
        _clean_text("Topshirdi (Ta'minotchi): __________________________"),
        font=f_td,
        fill=(51, 65, 85),
    )
    draw.text(
        (660, sig_y),
        _clean_text("Qabul qildi (Do'kon): __________________________"),
        font=f_td,
        fill=(51, 65, 85),
    )
    draw.text(
        (60, sig_y + 52),
        _clean_text("Hisobchi tizimi orqali avtomatik shakllantirildi."),
        font=f_foot,
        fill=(148, 163, 184),
    )

    out = io.BytesIO()
    img.save(out, format="PDF", resolution=150.0)
    return out.getvalue()
