"""One-time 8-digit Telegram login codes and SHA-256 bearer token authentication for APK."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import hmac
import json
import re
import secrets
import time
from typing import Optional, Sequence, Tuple
from urllib.parse import parse_qsl

from fastapi import Depends, Header, HTTPException, Query, Request, status
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from bot.auth import ROLE_ADMIN, can_write_role, get_user_role, is_admin_role
from database.crud import now_local
from database.models import ApiToken
from database.session import async_session_maker


CODE_TTL_SECONDS = 300  # 5 minutes
RATE_WINDOW_SECONDS = 300
MAX_FAILED_ATTEMPTS = 8
MAX_GLOBAL_FAILED_ATTEMPTS = 30

# {8_digit_code: (user_id, expires_epoch)}
_LOGIN_CODES: dict[str, tuple[int, float]] = {}
# {client_ip: [fail_epoch, ...]}
_FAILED_ATTEMPTS: dict[str, list[float]] = {}
_GLOBAL_FAILED_ATTEMPTS: list[float] = []
# {bucket: {key: [hit_epoch, ...]}}
_RATE_LIMIT_BUCKETS: dict[str, dict[str, list[float]]] = {}


@dataclass(slots=True)
class AuthenticatedUser:
    """Resolved authenticated mobile API caller."""

    user_id: int
    role: str
    can_write: bool
    is_admin: bool
    token_id: int
    raw_token: str


def _hash_token(raw_token: str) -> str:
    return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()


def _prune_expired_codes(now_ts: float) -> None:
    expired = [c for c, (_, exp) in _LOGIN_CODES.items() if exp <= now_ts]
    for c in expired:
        _LOGIN_CODES.pop(c, None)


def clear_auth_memory_state() -> None:
    """Clear in-memory one-time codes and rate-limit state (used in tests)."""
    _LOGIN_CODES.clear()
    _FAILED_ATTEMPTS.clear()
    _GLOBAL_FAILED_ATTEMPTS.clear()
    _RATE_LIMIT_BUCKETS.clear()


def extract_client_ip(request: Request) -> str:
    """Resolve client IP, trusting reverse-proxy headers only from loopback Nginx."""
    peer_ip = request.client.host if request.client else "unknown"
    if peer_ip in ("127.0.0.1", "::1", "::ffff:127.0.0.1"):
        x_real = (request.headers.get("x-real-ip") or "").strip()
        if x_real:
            return x_real
        xff = (request.headers.get("x-forwarded-for") or "").strip()
        if xff:
            first = xff.split(",")[0].strip()
            if first:
                return first
    return peer_ip


def check_rate_limit(
    bucket: str,
    key: str,
    max_hits: int,
    window_seconds: int = RATE_WINDOW_SECONDS,
) -> None:
    """Enforce a sliding-window per-key rate limit in memory."""
    now_ts = time.time()
    store = _RATE_LIMIT_BUCKETS.setdefault(bucket, {})
    hits = [t for t in store.get(key, []) if now_ts - t < window_seconds]
    if len(hits) >= max_hits:
        store[key] = hits
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Juda ko'p so'rov yuborildi. Biroz kutib qayta urinib ko'ring.",
        )
    hits.append(now_ts)
    store[key] = hits


def create_login_code(user_id: int, ttl_seconds: int = CODE_TTL_SECONDS) -> str:
    """Generate a fresh 8-digit one-time login code valid for 5 minutes for ``user_id``."""
    now_ts = time.time()
    _prune_expired_codes(now_ts)
    for existing_code, (uid, _) in list(_LOGIN_CODES.items()):
        if uid == int(user_id):
            _LOGIN_CODES.pop(existing_code, None)

    for _ in range(20):
        code = f"{secrets.randbelow(90_000_000) + 10_000_000:08d}"
        if code not in _LOGIN_CODES:
            _LOGIN_CODES[code] = (int(user_id), now_ts + ttl_seconds)
            return code
    raise RuntimeError("Could not allocate unique login code")


def format_login_code_display(code: str) -> str:
    """Format 8-digit code as '1234-5678' for easier reading in Telegram."""
    digits = re.sub(r"\D+", "", code)
    if len(digits) == 8:
        return f"{digits[:4]}-{digits[4:]}"
    return code


def consume_login_code(raw_code: str, client_ip: str = "unknown") -> Optional[int]:
    """Validate and consume a one-time 8-digit code; enforces per-IP and global brute-force rate limits."""
    global _GLOBAL_FAILED_ATTEMPTS
    now_ts = time.time()
    _prune_expired_codes(now_ts)

    _GLOBAL_FAILED_ATTEMPTS = [t for t in _GLOBAL_FAILED_ATTEMPTS if now_ts - t < RATE_WINDOW_SECONDS]
    if len(_GLOBAL_FAILED_ATTEMPTS) >= MAX_GLOBAL_FAILED_ATTEMPTS:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Xavfsizlik cheklovi: 5 daqiqadan keyin qayta urinib ko'ring.",
        )

    attempts = [t for t in _FAILED_ATTEMPTS.get(client_ip, []) if now_ts - t < RATE_WINDOW_SECONDS]
    if len(attempts) >= MAX_FAILED_ATTEMPTS:
        _FAILED_ATTEMPTS[client_ip] = attempts
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Juda ko'p xato urinish. 5 daqiqadan keyin qayta urinib ko'ring.",
        )

    digits = re.sub(r"\D+", "", raw_code or "")
    entry = _LOGIN_CODES.get(digits)
    if entry is None:
        attempts.append(now_ts)
        _FAILED_ATTEMPTS[client_ip] = attempts
        _GLOBAL_FAILED_ATTEMPTS.append(now_ts)
        return None

    user_id, expires_at = entry
    _LOGIN_CODES.pop(digits, None)
    if expires_at <= now_ts:
        attempts.append(now_ts)
        _FAILED_ATTEMPTS[client_ip] = attempts
        _GLOBAL_FAILED_ATTEMPTS.append(now_ts)
        return None

    _FAILED_ATTEMPTS.pop(client_ip, None)
    return user_id


async def issue_api_token(
    db: AsyncSession, user_id: int, device_name: str = "Android"
) -> Tuple[str, ApiToken]:
    """Create and persist a new SHA-256 hashed bearer token for ``user_id``."""
    raw_token = secrets.token_urlsafe(36)
    clean_device = (device_name or "Android").strip()[:120] or "Android"
    row = ApiToken(
        token_hash=_hash_token(raw_token),
        user_id=int(user_id),
        device_name=clean_device,
        revoked=False,
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return raw_token, row


async def issue_webapp_token(
    db: AsyncSession, user_id: int, device_name: str = "Telegram Mini App"
) -> Tuple[str, ApiToken]:
    """Replace any previous active Mini App token for this user with a fresh token."""
    clean_device = (device_name or "Telegram Mini App").strip()[:120] or "Telegram Mini App"
    existing_rows = (
        await db.scalars(
            select(ApiToken).where(
                ApiToken.user_id == int(user_id),
                ApiToken.device_name == clean_device,
                ApiToken.revoked.is_(False),
            )
        )
    ).all()
    for existing in existing_rows:
        existing.revoked = True
    return await issue_api_token(db, user_id=user_id, device_name=clean_device)


def verify_telegram_webapp_init_data(
    init_data: str, bot_token: str, max_age_seconds: int = 86400
) -> dict:
    """Verify Telegram WebApp initData HMAC-SHA256 signature and extract caller user info."""
    if not bot_token or bot_token == "YOUR_TELEGRAM_BOT_TOKEN_HERE":
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Bot tokeni sozlanmagan.",
        )
    if not init_data or not init_data.strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Telegram initData topilmadi.",
        )

    params = dict(parse_qsl(init_data, keep_blank_values=True))
    received_hash = params.pop("hash", "").strip().lower()
    if not received_hash:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Telegram imzosi (hash) topilmadi.",
        )

    raw_auth_date = params.get("auth_date", "")
    try:
        auth_ts = int(raw_auth_date)
    except (TypeError, ValueError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Telegram auth_date yaroqsiz.",
        ) from exc

    now_ts = time.time()
    if now_ts - auth_ts > max_age_seconds or auth_ts - now_ts > 300:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Telegram sessiyasi eskirgan. Mini App'ni qaytadan oching.",
        )

    data_check_string = "\n".join(f"{k}={v}" for k, v in sorted(params.items()))
    secret_key = hmac.new(
        b"WebAppData", bot_token.encode("utf-8"), hashlib.sha256
    ).digest()
    expected_hash = hmac.new(
        secret_key, data_check_string.encode("utf-8"), hashlib.sha256
    ).hexdigest().lower()

    if not hmac.compare_digest(expected_hash, received_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Telegram imzosi tasdiqlanmadi.",
        )

    raw_user = params.get("user")
    if not raw_user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Telegram foydalanuvchi ma'lumoti topilmadi.",
        )
    try:
        user_obj = json.loads(raw_user)
    except json.JSONDecodeError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Telegram user JSON yaroqsiz.",
        ) from exc

    uid = user_obj.get("id") if isinstance(user_obj, dict) else None
    if not isinstance(uid, int) or isinstance(uid, bool) or uid <= 0:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Telegram foydalanuvchi ID yaroqsiz.",
        )

    return {
        "user_id": int(uid),
        "first_name": str(user_obj.get("first_name") or ""),
        "username": str(user_obj.get("username") or ""),
    }


async def list_active_tokens(
    db: AsyncSession, user_id: Optional[int] = None
) -> Sequence[ApiToken]:
    """List active non-revoked mobile device tokens (filtered by user_id if provided)."""
    stmt = select(ApiToken).where(ApiToken.revoked.is_(False)).order_by(desc(ApiToken.id))
    if user_id is not None:
        stmt = stmt.where(ApiToken.user_id == int(user_id))
    return list((await db.scalars(stmt)).all())


async def revoke_token_by_id(
    db: AsyncSession, token_id: int, actor_user_id: int, is_admin: bool = False
) -> bool:
    """Revoke an active device token by its database id."""
    row = await db.get(ApiToken, int(token_id))
    if row is None or row.revoked:
        return False
    if not is_admin and int(row.user_id) != int(actor_user_id):
        return False
    row.revoked = True
    await db.commit()
    return True


async def revoke_raw_token(db: AsyncSession, raw_token: str) -> bool:
    """Revoke a token by its raw bearer value."""
    if not raw_token:
        return False
    th = _hash_token(raw_token)
    row = await db.scalar(
        select(ApiToken).where(ApiToken.token_hash == th, ApiToken.revoked.is_(False))
    )
    if row is None:
        return False
    row.revoked = True
    await db.commit()
    return True


def _is_query_token_allowed_path(path: str) -> bool:
    return (
        path.startswith("/export/")
        or path.endswith("/photo")
        or path == "/suppliers/sverka-pdf"
    )


def _extract_bearer_token(
    authorization: Optional[str],
    query_token: Optional[str],
    request_path: str = "",
) -> str:
    if authorization:
        parts = authorization.strip().split(" ", 1)
        if len(parts) == 2 and parts[0].lower() == "bearer" and parts[1].strip():
            return parts[1].strip()
    if query_token and query_token.strip():
        if not _is_query_token_allowed_path(request_path):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Query token faqat yuklab olish (export/rasm) yo'llarida ruxsat etilgan.",
            )
        return query_token.strip()
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Avtorizatsiya tokeni topilmadi. Ilovaga qaytadan kiring.",
    )


async def get_current_user(
    request: Request,
    authorization: Optional[str] = Header(default=None),
    token: Optional[str] = Query(default=None),
) -> AuthenticatedUser:
    """FastAPI dependency validating Bearer token and active RBAC user role."""
    raw_token = _extract_bearer_token(authorization, token, request.url.path)
    th = _hash_token(raw_token)
    async with async_session_maker() as db:
        row = await db.scalar(
            select(ApiToken).where(ApiToken.token_hash == th, ApiToken.revoked.is_(False))
        )
        if row is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token yaroqsiz yoki bekor qilingan. Botdan /apk orqali yangi kod oling.",
            )
        role = get_user_role(int(row.user_id))
        if role is None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Foydalanuvchi huquqi bekor qilingan.",
            )
        now_dt = now_local()
        try:
            if row.last_used_at is None or (now_dt - row.last_used_at).total_seconds() > 60:
                row.last_used_at = now_dt
                await db.commit()
        except Exception:
            row.last_used_at = now_dt
            await db.commit()

        return AuthenticatedUser(
            user_id=int(row.user_id),
            role=role,
            can_write=can_write_role(int(row.user_id)),
            is_admin=is_admin_role(int(row.user_id)) or role == ROLE_ADMIN,
            token_id=int(row.id),
            raw_token=raw_token,
        )


async def require_write_user(
    user: AuthenticatedUser = Depends(get_current_user),
) -> AuthenticatedUser:
    """FastAPI dependency requiring admin or kassir write permissions."""
    if not user.can_write:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Sizning rolingizda (Ko'ruvchi) ma'lumot qo'shish yoki tahrirlash huquqi yo'q.",
        )
    return user
