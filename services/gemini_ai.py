"""Gemini 2.5 Flash multimodal AI client (Nakladnoy OCR + Voice/Text understanding) & Uzbek amount parser."""

from __future__ import annotations

import base64
import json
import re
from typing import Any, Dict, Optional

import httpx

from config import get_settings


UZBEK_UNITS = {
    "nol": 0,
    "bir": 1,
    "ikki": 2,
    "uch": 3,
    "to'rt": 4,
    "tort": 4,
    "besh": 5,
    "olti": 6,
    "yetti": 7,
    "sakkiz": 8,
    "to'qqiz": 9,
    "toqqiz": 9,
    "o'n": 10,
    "on": 10,
}


def format_uzs(amount: float) -> str:
    """Format an amount in UZS with space thousands separators."""
    rounded = round(float(amount))
    return f"{rounded:,}".replace(",", " ")


def parse_uzbek_amount(text: str) -> Optional[float]:
    """
    Parse monetary amounts from Uzbek/Russian text or arithmetic expressions.

    Supports:
    - "21 000 000", "21,000,000", "21000000"
    - "12 895 000 + 2 109 750"
    - "21 mln", "21 million", "1.5 mln", "450 ming", "450k"
    """
    if not text:
        return None

    cleaned = text.lower().strip()
    cleaned = cleaned.replace("so'm", "").replace("som", "").replace("sum", "").replace("сўм", "")

    # Check if there is an arithmetic addition expression like "12 895 000 + 2 109 750"
    if "+" in cleaned and not re.search(r"[a-zа-яё]", cleaned.replace("mln", "").replace("ming", "").replace("million", "")):
        parts = cleaned.split("+")
        total = 0.0
        found_any = False
        for part in parts:
            val = parse_uzbek_amount(part)
            if val is not None:
                total += val
                found_any = True
        return total if found_any else None

    # Handle multiplier words: million / mln / mlrd / ming / k
    multiplier_patterns = [
        (r"(\d+(?:[.,]\d+)?)\s*(?:mlrd|milliard|миллиард)\b", 1_000_000_000),
        (r"(\d+(?:[.,]\d+)?)\s*(?:mln|million|миллион|млн)\b", 1_000_000),
        (r"(\d+(?:[.,]\d+)?)\s*(?:ming|тысяч|тыс|k)\b", 1_000),
    ]
    total_multi = 0.0
    matched_multi = False
    remainder = cleaned
    for pattern, mult in multiplier_patterns:
        for match in re.finditer(pattern, remainder):
            num_str = match.group(1).replace(",", ".")
            try:
                total_multi += float(num_str) * mult
                matched_multi = True
            except ValueError:
                pass
        remainder = re.sub(pattern, " ", remainder)

    if matched_multi:
        # Also pick up trailing standalone numbers if user said "1 million 500 ming" -> already matched both,
        # or "1 million 500" -> treat trailing small digits if needed
        return total_multi

    # Extract standard grouped number like "21 000 000" or "161899.98"
    # Normalize spaces/underscores inside digit groups
    digit_match = re.search(r"(\d[\d\s\u00a0_]*(?:[.,]\d+)?)", cleaned)
    if digit_match:
        raw_num = digit_match.group(1)
        # Remove spaces/underscores
        compact = re.sub(r"[\s\u00a0_]+", "", raw_num)
        # Distinguish decimal comma/dot vs thousand separator comma/dot
        if "," in compact and "." not in compact:
            # If 3 digits after comma and multiple commas or >= 1000 pattern, e.g. 12,895,000
            parts = compact.split(",")
            if len(parts) > 2 or (len(parts) == 2 and len(parts[1]) == 3 and len(parts[0]) <= 3):
                compact = "".join(parts)
            else:
                compact = compact.replace(",", ".")
        elif "," in compact and "." in compact:
            compact = compact.replace(",", "")
        try:
            return float(compact)
        except ValueError:
            return None

    return None


def _extract_json_object(raw_text: str) -> Dict[str, Any]:
    """Parse JSON safely from Gemini response text."""
    text = raw_text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    try:
        data = json.loads(text)
        if isinstance(data, dict):
            return data
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", text, flags=re.DOTALL)
        if match:
            try:
                data = json.loads(match.group(0))
                if isinstance(data, dict):
                    return data
            except json.JSONDecodeError:
                pass
    return {}


async def _call_gemini(parts: list[dict[str, Any]]) -> Dict[str, Any]:
    """Send multimodal content to Gemini generateContent endpoint with model fallback on 404/503."""
    settings = get_settings()
    if not settings.GEMINI_API_KEY:
        return {"error": "GEMINI_API_KEY sozlanmagan"}

    payload = {
        "contents": [{"parts": parts}],
        "generationConfig": {
            "temperature": 0.1,
            "responseMimeType": "application/json",
        },
    }

    candidates_order: list[str] = []
    for model_name in (
        settings.GEMINI_MODEL,
        "gemini-flash-latest",
        "gemini-3.8-flash",
        "gemini-flash-lite-latest",
    ):
        if model_name and model_name not in candidates_order:
            candidates_order.append(model_name)

    last_exc: Optional[Exception] = None
    body: Dict[str, Any] = {}
    async with httpx.AsyncClient(timeout=20.0) as client:
        for model_name in candidates_order:
            url = (
                f"https://generativelanguage.googleapis.com/v1beta/models/"
                f"{model_name}:generateContent"
            )
            try:
                resp = await client.post(
                    url,
                    params={"key": settings.GEMINI_API_KEY},
                    json=payload,
                )
                if resp.status_code in (404, 429, 503):
                    last_exc = httpx.HTTPStatusError(
                        f"Model {model_name} returned {resp.status_code}",
                        request=resp.request,
                        response=resp,
                    )
                    continue
                resp.raise_for_status()
                body = resp.json()
                last_exc = None
                break
            except httpx.HTTPError as exc:
                last_exc = exc
                continue

    if last_exc is not None:
        raise last_exc

    candidates = body.get("candidates") or []
    if not candidates:
        return {}
    content_parts = candidates[0].get("content", {}).get("parts", [])
    raw_text = "".join(p.get("text", "") for p in content_parts)
    return _extract_json_object(raw_text)


async def extract_nakladnoy_from_image(
    image_bytes: bytes,
    mime_type: str = "image/jpeg",
    caption: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Analyze a supplier nakladnoy/receipt image using Gemini 2.5 Flash.

    Returns dict:
        {
            "supplier_name": str | None,
            "amount": float | None,
            "is_clear": bool,
            "notes": str
        }
    """
    prompt = (
        "Siz O'zbekistondagi oziq-ovqat do'konining buxgalteriya yordamchisisiz. "
        "Sizga ta'minotchi (postavshik) nakladnoyi yoki chek rasmi yuborildi.\n"
        "Vazifa: Rasmdan quyidagi maydonlarni aniq ajratib JSON qaytaring:\n"
        '1. "supplier_name": Ta\'minotchi/firma/yetkazib beruvchi nomi (masalan: "QASSOB", "OMBOR", "Non Oka", "Coca-Cola", "NAFIS"). '
        "Agar do'kon nomi (masalan IFTIQOR 80) oluvchi sifatida yozilgan bo'lsa, uni EMAS, mahsulot beruvchi postavshik nomini oling. Topilmasa null.\n"
        '2. "amount": Nakladnoyning yakuniy umumiy summasi (faqat raqam, so\'mda, masalan 1657000). '
        "Agar tiyin/vergul bo'lmasa butun son qiling. Agar o'qib bo'lmasa null.\n"
        '3. "is_clear": agar ham supplier_name ham amount aniq o\'qilgan bo\'lsa true, aks holda false.\n'
        '4. "notes": qisqa izoh (masalan nima mahsulotlar ekanligi yoki nimasi ko\'rinmagani).\n'
    )
    if caption:
        prompt += f"\nFoydalanuvchi rasm ostiga yozgan izoh: {caption}\n"

    prompt += (
        '\nFaqat JSON qaytaring: {"supplier_name": ..., "amount": ..., "is_clear": true/false, "notes": "..."}'
    )

    encoded = base64.b64encode(image_bytes).decode("ascii")
    parts: list[dict[str, Any]] = [
        {"text": prompt},
        {"inlineData": {"mimeType": mime_type, "data": encoded}},
    ]

    try:
        data = await _call_gemini(parts)
    except Exception as exc:
        return {
            "supplier_name": caption.strip() if caption else None,
            "amount": parse_uzbek_amount(caption) if caption else None,
            "is_clear": False,
            "notes": f"Gemini ulanish xatosi: {exc}",
        }

    supplier = data.get("supplier_name")
    if isinstance(supplier, str):
        supplier = supplier.strip() or None
    else:
        supplier = None

    raw_amount = data.get("amount")
    amount: Optional[float] = None
    if isinstance(raw_amount, (int, float)) and raw_amount > 0:
        amount = float(raw_amount)
    elif isinstance(raw_amount, str):
        amount = parse_uzbek_amount(raw_amount)

    # Fallback: check caption if Gemini missed something user explicitly wrote
    if caption:
        if amount is None:
            amount = parse_uzbek_amount(caption)
        if supplier is None:
            caption_clean = re.sub(r"\d[\d\s.,]*", "", caption).strip()
            if caption_clean:
                supplier = caption_clean

    is_clear = bool(data.get("is_clear")) and supplier is not None and amount is not None and amount > 0
    return {
        "supplier_name": supplier,
        "amount": amount,
        "is_clear": is_clear,
        "notes": str(data.get("notes") or ""),
    }


def _heuristic_parse_text(text: str) -> Optional[Dict[str, Any]]:
    """Fast deterministic parser for straightforward Uzbek/Russian text commands."""
    raw = text.strip()
    low = raw.lower()
    amount = parse_uzbek_amount(raw)

    if any(k in low for k in ("status", "статус", "hisob", "qoldiq")):
        if amount is None:
            return {"intent": "status", "amount": None, "supplier_name": None, "transcript": raw}

    if (
        ("kassaga" in low or "кассага" in low)
        and any(w in low for w in ("qaytardim", "qaytar", "berdim", "yop", "қайтардим"))
    ) or "kassa qarzini yop" in low:
        if amount:
            return {"intent": "kassa_repay", "amount": amount, "supplier_name": None, "transcript": raw}

    if any(k in low for k in ("kassadan", "кассадан")) and amount:
        return {"intent": "kassa_debt", "amount": amount, "supplier_name": None, "transcript": raw}

    if any(k in low for k in ("pul oldim", "oldim", "kirim", "приход", "олдим")) and amount:
        return {"intent": "cash_in", "amount": amount, "supplier_name": None, "transcript": raw}

    # Pure number (when not specifying supplier) -> unknown intent with parsed amount so caller context decides
    stripped_num = re.sub(r"[\d\s.,+_mlnmingmillionkso'msomсўм-]+", "", low).strip()
    if amount is not None and not stripped_num:
        return {"intent": "number_only", "amount": amount, "supplier_name": None, "transcript": raw}

    return None


async def parse_voice_or_text(
    audio_bytes: Optional[bytes] = None,
    text: Optional[str] = None,
    mime_type: str = "audio/ogg",
) -> Dict[str, Any]:
    """
    Understand an Uzbek/Russian voice message or free-form text via Gemini 2.5 Flash.

    Returns dict:
        {
            "intent": "cash_in" | "kassa_debt" | "kassa_repay" | "pay_supplier" | "count_cash" | "status" | "number_only" | "unknown",
            "amount": float | None,
            "supplier_name": str | None,
            "transcript": str
        }
    """
    if text and not audio_bytes:
        heuristic = _heuristic_parse_text(text)
        if heuristic is not None:
            return heuristic

    prompt = (
        "Siz O'zbekistondagi do'konning moliyaviy yordamchi botisiz. "
        "Foydalanuvchi o'zbek yoki rus tilida ovozli xabar yoki matn yubordi.\n"
        "Vazifa: Xabarni tushunib, quyidagi JSON formatda qaytaring:\n"
        '- "transcript": Xabarning matni (agar audio bo\'lsa o\'zbek/rus tilida yozilgan matni).\n'
        '- "intent": Quyidagilardan BITTA qiymat:\n'
        '  * "cash_in": Agar "pul oldim 21 million", "30 mln oldim", "asosiy pul qo\'sh" desa.\n'
        '  * "kassa_debt": Agar "kassadan 3 million oldim", "kassadan qarz oldim" desa.\n'
        '  * "kassa_repay": Agar "kassaga 3 million qaytardim", "kassa qarzini berdim" desa.\n'
        '  * "pay_supplier": Agar biror ta\'minotchiga (postavshikka) pul berilgani aytilsa (masalan "Non Oka 1 million 657 ming", "Qassobga 5 million berdim").\n'
        '  * "count_cash": Agar "qo\'limda 1 million 500 ming qoldi", "sanadim shuncha chiqdi" desa.\n'
        '  * "status": Agar "status", "hisob-kitobni ko\'rsat", "qancha pul qoldi" desa.\n'
        '  * "unknown": Agar boshqa narsa bo\'lsa.\n'
        '- "amount": Aytilgan pul summasi (raqamda, so\'mda; masalan "21 million" -> 21000000, "bir yarim million" -> 1500000). Topilmasa null.\n'
        '- "supplier_name": Agar "pay_supplier" bo\'lsa ta\'minotchi nomi (masalan "Non Oka", "Qassob"), bo\'lmasa null.\n'
        'Faqat JSON qaytaring: {"transcript": "...", "intent": "...", "amount": ..., "supplier_name": ...}'
    )

    parts: list[dict[str, Any]] = [{"text": prompt}]
    if text:
        parts.append({"text": f"Foydalanuvchi matni: {text}"})
    if audio_bytes:
        encoded = base64.b64encode(audio_bytes).decode("ascii")
        parts.append({"inlineData": {"mimeType": mime_type, "data": encoded}})

    try:
        data = await _call_gemini(parts)
    except Exception as exc:
        fallback_amount = parse_uzbek_amount(text or "") if text else None
        return {
            "intent": "unknown",
            "amount": fallback_amount,
            "supplier_name": None,
            "transcript": text or f"Audio xatolik: {exc}",
        }

    raw_amount = data.get("amount")
    amount: Optional[float] = None
    if isinstance(raw_amount, (int, float)) and raw_amount > 0:
        amount = float(raw_amount)
    elif isinstance(raw_amount, str):
        amount = parse_uzbek_amount(raw_amount)

    supplier = data.get("supplier_name")
    if isinstance(supplier, str):
        supplier = supplier.strip() or None
    else:
        supplier = None

    transcript = str(data.get("transcript") or text or "")
    intent = str(data.get("intent") or "unknown")
    return {
        "intent": intent,
        "amount": amount,
        "supplier_name": supplier,
        "transcript": transcript,
    }
