"""Gemini Flash multimodal AI client (Nakladnoy OCR + Audio only) & Uzbek amount parser."""

from __future__ import annotations

import asyncio
import base64
import io
import json
import logging
import re
from typing import Any, Dict, Optional, Tuple

import httpx
from PIL import Image, ImageOps

from config import get_settings


logger = logging.getLogger("hisobot_bot.ai")

MAX_VOICE_SECONDS = 60

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


class GeminiRateLimitError(RuntimeError):
    """Raised when Gemini returns HTTP 429 after a single retry."""


class VoiceTooLongError(ValueError):
    """Raised when an audio/voice message exceeds MAX_VOICE_SECONDS."""


OCR_SCHEMA: Dict[str, Any] = {
    "type": "OBJECT",
    "properties": {
        "supplier_name": {"type": "STRING", "nullable": True},
        "amount": {"type": "NUMBER", "nullable": True},
        "is_clear": {"type": "BOOLEAN"},
        "notes": {"type": "STRING"},
    },
    "required": ["supplier_name", "amount", "is_clear", "notes"],
}

AUDIO_SCHEMA: Dict[str, Any] = {
    "type": "OBJECT",
    "properties": {
        "transcript": {"type": "STRING"},
        "intent": {
            "type": "STRING",
            "enum": [
                "cash_in",
                "kassa_debt",
                "kassa_repay",
                "pay_supplier",
                "count_cash",
                "status",
                "unknown",
            ],
        },
        "amount": {"type": "NUMBER", "nullable": True},
        "supplier_name": {"type": "STRING", "nullable": True},
    },
    "required": ["transcript", "intent", "amount", "supplier_name"],
}

OCR_PROMPT = (
    "O'zbekiston do'koni nakladnoy/cheki. Oluvchi (masalan IFTIQOR 80) EMAS, yetkazib beruvchi "
    "postavshik nomini (supplier_name), yakuniy umumiy summani so'mda butun son qilib (amount), "
    "ikkalasi aniq bo'lsa is_clear=true va qisqa mahsulot izohi (notes) qaytaring."
)

AUDIO_PROMPT = (
    "O'zbek/rus tilidagi do'kon kassa ovozli xabarini tahlil qiling. "
    "transcript: xabar matni; intent: cash_in (pul oldim), kassa_debt (kassadan oldim), "
    "kassa_repay (kassaga qaytardim), pay_supplier (postavshikka pul berdim), "
    "count_cash (qo'limda sanadim), status (hisob/qoldiq), unknown; "
    "amount: summa so'mda (raqamda); supplier_name: postavshik nomi."
)


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

    if "+" in cleaned and not re.search(
        r"[a-zа-яё]", cleaned.replace("mln", "").replace("ming", "").replace("million", "")
    ):
        parts = cleaned.split("+")
        total = 0.0
        found_any = False
        for part in parts:
            val = parse_uzbek_amount(part)
            if val is not None:
                total += val
                found_any = True
        return total if found_any else None

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
        return total_multi

    digit_match = re.search(r"(\d[\d\s\u00a0_]*(?:[.,]\d+)?)", cleaned)
    if digit_match:
        raw_num = digit_match.group(1)
        compact = re.sub(r"[\s\u00a0_]+", "", raw_num)
        if "," in compact and "." not in compact:
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


def compress_image_for_ocr(
    image_bytes: bytes, max_side: int = 1280, quality: int = 82
) -> Tuple[bytes, str]:
    """Resize large images down to ``max_side`` px JPEG to cut Gemini vision tokens."""
    try:
        with Image.open(io.BytesIO(image_bytes)) as img:
            img = ImageOps.exif_transpose(img)
            if img.mode != "RGB":
                img = img.convert("RGB")
            w, h = img.size
            if max(w, h) > max_side:
                img.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)
            out = io.BytesIO()
            img.save(out, format="JPEG", quality=quality, optimize=True)
            compressed = out.getvalue()
            if len(compressed) > 0:
                return compressed, "image/jpeg"
    except Exception:
        pass
    return image_bytes, "image/jpeg"


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


_HTTP_CLIENT: Optional[httpx.AsyncClient] = None


def _get_http_client() -> httpx.AsyncClient:
    """Reuse a persistent IPv4 keep-alive AsyncClient to avoid IPv6 timeouts and TLS handshakes."""
    global _HTTP_CLIENT
    if _HTTP_CLIENT is None or _HTTP_CLIENT.is_closed:
        _HTTP_CLIENT = httpx.AsyncClient(
            timeout=15.0,
            limits=httpx.Limits(max_connections=10, max_keepalive_connections=5),
            transport=httpx.AsyncHTTPTransport(local_address="0.0.0.0"),
        )
    return _HTTP_CLIENT


async def _log_ai_usage_safe(
    kind: str, model_name: str, usage: Dict[str, Any]
) -> None:
    """Persist AI call metadata without ever failing the caller if DB isn't ready."""
    try:
        from database.crud import record_ai_usage
        from database.session import async_session_maker

        async with async_session_maker() as db:
            await record_ai_usage(
                db,
                kind=kind,
                model_name=model_name,
                prompt_tokens=int(usage.get("promptTokenCount") or 0),
                output_tokens=int(usage.get("candidatesTokenCount") or 0),
                total_tokens=int(usage.get("totalTokenCount") or 0),
            )
    except Exception:
        pass


async def _post_gemini_request(
    client: httpx.AsyncClient,
    model_name: str,
    api_key: str,
    parts: list[dict[str, Any]],
    response_schema: Optional[Dict[str, Any]] = None,
) -> httpx.Response:
    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model_name}:generateContent"
    )
    gen_cfg: Dict[str, Any] = {
        "temperature": 0.1,
        "maxOutputTokens": 200,
        "responseMimeType": "application/json",
        "thinkingConfig": {"thinkingBudget": 0},
    }
    if response_schema is not None:
        gen_cfg["responseSchema"] = response_schema

    resp = await client.post(
        url, params={"key": api_key}, json={"contents": [{"parts": parts}], "generationConfig": gen_cfg}
    )
    if resp.status_code == 400 and "thinkingConfig" in gen_cfg:
        gen_cfg.pop("thinkingConfig", None)
        resp = await client.post(
            url, params={"key": api_key}, json={"contents": [{"parts": parts}], "generationConfig": gen_cfg}
        )
    if resp.status_code == 400 and "responseSchema" in gen_cfg:
        gen_cfg.pop("responseSchema", None)
        resp = await client.post(
            url, params={"key": api_key}, json={"contents": [{"parts": parts}], "generationConfig": gen_cfg}
        )
    return resp


async def _call_gemini(
    parts: list[dict[str, Any]],
    response_schema: Optional[Dict[str, Any]] = None,
) -> Tuple[Dict[str, Any], Dict[str, Any], str]:
    """Send multimodal content to Gemini with single-retry on 429 and 404-only fallback."""
    settings = get_settings()
    if not settings.GEMINI_API_KEY:
        raise RuntimeError("GEMINI_API_KEY missing")

    models: list[str] = []
    for m in (settings.GEMINI_MODEL, "gemini-flash-lite-latest"):
        if m and m not in models:
            models.append(m)

    client = _get_http_client()
    body: Dict[str, Any] = {}
    used_model = models[0]
    last_exc: Optional[Exception] = None

    for model_name in models:
        used_model = model_name
        resp = await _post_gemini_request(
            client, model_name, settings.GEMINI_API_KEY, parts, response_schema=response_schema
        )
        if resp.status_code == 404:
            last_exc = httpx.HTTPStatusError(
                f"Model {model_name} not found", request=resp.request, response=resp
            )
            continue
        if resp.status_code == 429:
            await asyncio.sleep(2.0)
            resp = await _post_gemini_request(
                client, model_name, settings.GEMINI_API_KEY, parts, response_schema=response_schema
            )
            if resp.status_code == 429:
                raise GeminiRateLimitError("Gemini rate limit (429)")
        resp.raise_for_status()
        body = resp.json()
        last_exc = None
        break

    if last_exc is not None:
        raise last_exc

    candidates = body.get("candidates") or []
    usage = body.get("usageMetadata") or {}
    if not candidates:
        return {}, usage, used_model
    content_parts = candidates[0].get("content", {}).get("parts", [])
    raw_text = "".join(p.get("text", "") for p in content_parts)
    return _extract_json_object(raw_text), usage, used_model


def parse_photo_caption(caption: Optional[str]) -> Tuple[Optional[str], Optional[float]]:
    """Extract explicit supplier override and/or amount (>= 500) from a photo caption."""
    if not caption or not caption.strip():
        return None, None
    raw = " ".join(caption.strip().split())
    amt = parse_uzbek_amount(raw)
    cap_amount: Optional[float] = float(amt) if (amt is not None and amt >= 500) else None

    if cap_amount is not None:
        cleaned = re.sub(
            r"(?i)\b(?:so'm|som|sum|сўм|mln|million|ming|mlrd|milliard|млн|миллион|тыс|тысяч)\b",
            " ",
            raw,
        )
        cleaned = re.sub(r"(?i)(?<![A-Za-zА-Яа-яЁё])\d+(?:[.,]\d+)?\s*k\b", " ", cleaned)
        cleaned = re.sub(
            r"(?<![A-Za-zА-Яа-яЁё])\d[\d\s.,+_]*(?![A-Za-zА-Яа-яЁё])",
            " ",
            cleaned,
        )
        cleaned = " ".join(cleaned.strip(" :-").split())
    else:
        cleaned = raw

    cap_supplier = cleaned if re.search(r"[A-Za-zА-Яа-яЁё]{2,}", cleaned) else None
    return cap_supplier, cap_amount


async def extract_nakladnoy_from_image(
    image_bytes: bytes,
    mime_type: str = "image/jpeg",
    caption: Optional[str] = None,
) -> Dict[str, Any]:
    """Analyze a supplier nakladnoy image via Gemini Vision after client-side resize."""
    cap_supplier, cap_amount = parse_photo_caption(caption)

    # Zero-token shortcut when user already wrote both supplier & amount under the photo
    if cap_supplier and cap_amount is not None and cap_amount > 0:
        return {
            "supplier_name": cap_supplier,
            "amount": float(cap_amount),
            "is_clear": True,
            "notes": "",
            "error_code": None,
        }

    settings = get_settings()
    if not settings.GEMINI_API_KEY:
        return {
            "supplier_name": cap_supplier,
            "amount": cap_amount,
            "is_clear": False,
            "notes": "",
            "error_code": "no_key",
        }

    resized_bytes, out_mime = await asyncio.to_thread(
        compress_image_for_ocr, image_bytes, 1280, 82
    )
    prompt = OCR_PROMPT
    if cap_supplier:
        prompt += (
            f" Postavshik nomi aniq belgilangan: '{cap_supplier}'. "
            "Rasmdan faqat yakuniy summani (amount) o'qing; summa aniq o'qilsa is_clear=true qaytaring."
        )
    elif caption:
        prompt += f" Izoh: {caption}"

    encoded = base64.b64encode(resized_bytes).decode("ascii")
    parts: list[dict[str, Any]] = [
        {"text": prompt},
        {"inlineData": {"mimeType": out_mime, "data": encoded}},
    ]

    try:
        data, usage, used_model = await _call_gemini(parts, response_schema=OCR_SCHEMA)
        await _log_ai_usage_safe("photo", used_model, usage)
    except GeminiRateLimitError as exc:
        logger.warning("Gemini rate limit on OCR: %s", exc)
        return {
            "supplier_name": cap_supplier,
            "amount": cap_amount,
            "is_clear": False,
            "notes": "",
            "error_code": "rate_limit",
        }
    except Exception as exc:
        logger.warning("Gemini OCR error: %s", exc)
        return {
            "supplier_name": cap_supplier,
            "amount": cap_amount,
            "is_clear": False,
            "notes": "",
            "error_code": "api_error",
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

    # Strict caption precedence over OCR
    if cap_supplier:
        supplier = cap_supplier
    if cap_amount is not None:
        amount = float(cap_amount)

    if supplier is not None and amount is not None and amount > 0:
        is_clear = True if cap_supplier else bool(data.get("is_clear"))
    else:
        is_clear = False

    return {
        "supplier_name": supplier,
        "amount": amount,
        "is_clear": is_clear,
        "notes": str(data.get("notes") or ""),
        "error_code": None,
    }


def parse_text_deterministic(text: str) -> Dict[str, Any]:
    """Deterministic parser for all Uzbek/Russian text commands — never calls Gemini."""
    raw = (text or "").strip()
    low = raw.lower()
    amount = parse_uzbek_amount(raw)

    if any(k in low for k in ("status", "статус", "hisob", "qoldiq", "ҳисоб", "қолдиқ")):
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

    name_candidate = re.sub(
        r"(?i)\b(?:berdim|to'ladim|toladim|berildi|o'tkazdim|otkazdim|tashladim|"
        r"бердим|оплатил|nakladnoy|накладной|"
        r"so'm|som|sum|сўм|mln|million|ming|mlrd|milliard|млн|миллион|тыс|тысяч|миллиард)\b",
        " ",
        raw,
    )
    name_candidate = re.sub(r"(?i)\b\d+(?:[.,]\d+)?\s*k\b", " ", name_candidate)
    name_candidate = re.sub(r"[\d\s.,+_:-]+", " ", name_candidate).strip()
    name_candidate = re.sub(r"\s+ga$", "", name_candidate, flags=re.IGNORECASE).strip()

    if amount is not None and amount > 0:
        if not name_candidate:
            return {"intent": "number_only", "amount": amount, "supplier_name": None, "transcript": raw}
        if re.search(r"[A-Za-zА-Яа-яЁё]{2,}", name_candidate):
            return {
                "intent": "pay_supplier",
                "amount": amount,
                "supplier_name": name_candidate,
                "transcript": raw,
            }

    return {"intent": "unknown", "amount": amount, "supplier_name": None, "transcript": raw}


def _heuristic_parse_text(text: str) -> Dict[str, Any]:
    """Backward-compatible alias for parse_text_deterministic."""
    return parse_text_deterministic(text)


async def parse_voice_or_text(
    audio_bytes: Optional[bytes] = None,
    text: Optional[str] = None,
    mime_type: str = "audio/ogg",
) -> Dict[str, Any]:
    """Parse text deterministically (zero AI tokens) or transcribe voice via Gemini Audio."""
    if not audio_bytes:
        return parse_text_deterministic(text or "")

    settings = get_settings()
    if not settings.GEMINI_API_KEY:
        return {
            "intent": "unknown",
            "amount": None,
            "supplier_name": None,
            "transcript": "",
            "error_code": "no_key",
        }

    encoded = base64.b64encode(audio_bytes).decode("ascii")
    parts: list[dict[str, Any]] = [
        {"text": AUDIO_PROMPT},
        {"inlineData": {"mimeType": mime_type, "data": encoded}},
    ]

    try:
        data, usage, used_model = await _call_gemini(parts, response_schema=AUDIO_SCHEMA)
        await _log_ai_usage_safe("audio", used_model, usage)
    except GeminiRateLimitError as exc:
        logger.warning("Gemini rate limit on audio: %s", exc)
        return {
            "intent": "unknown",
            "amount": None,
            "supplier_name": None,
            "transcript": "",
            "error_code": "rate_limit",
        }
    except Exception as exc:
        logger.warning("Gemini audio error: %s", exc)
        return {
            "intent": "unknown",
            "amount": None,
            "supplier_name": None,
            "transcript": "",
            "error_code": "api_error",
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

    transcript = str(data.get("transcript") or "")
    intent = str(data.get("intent") or "unknown")
    return {
        "intent": intent,
        "amount": amount,
        "supplier_name": supplier,
        "transcript": transcript,
        "error_code": None,
    }
