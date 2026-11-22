"""One-time 8-digit Telegram login codes and SHA-256 bearer token authentication for APK."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import re
import secrets
import time
from typing import Optional, Sequence, Tuple

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

# {8_digit_code: (user_id, expires_epoch)}
_LOGIN_CODES: dict[str, tuple[int, float]] = {}
# {client_ip: [fail_epoch, ...]}
_FAILED_ATTEMPTS: dict[str, list[float]] = {}


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
    """Validate and consume a one-time 8-digit code; enforces per-IP brute-force rate limit."""
    now_ts = time.time()
    _prune_expired_codes(now_ts)

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
        return None

    user_id, expires_at = entry
    _LOGIN_CODES.pop(digits, None)
    if expires_at <= now_ts:
        attempts.append(now_ts)
        _FAILED_ATTEMPTS[client_ip] = attempts
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


def _extract_bearer_token(authorization: Optional[str], query_token: Optional[str]) -> str:
    if authorization:
        parts = authorization.strip().split(" ", 1)
        if len(parts) == 2 and parts[0].lower() == "bearer" and parts[1].strip():
            return parts[1].strip()
    if query_token and query_token.strip():
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
    raw_token = _extract_bearer_token(authorization, token)
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
