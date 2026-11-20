"""Fail-closed authorization and RBAC helpers (admin, kassir, viewer)."""

from __future__ import annotations

from typing import Optional

from aiogram.types import CallbackQuery, Message
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from config import get_settings
from database.models import UserRole


ROLE_ADMIN = "admin"
ROLE_KASSIR = "kassir"
ROLE_VIEWER = "viewer"
ALL_ROLES = (ROLE_ADMIN, ROLE_KASSIR, ROLE_VIEWER)
ANONYMOUS_ADMIN_BOT_ID = 1087968824

ROLE_LABELS = {
    ROLE_ADMIN: "👑 Admin (Hammasi)",
    ROLE_KASSIR: "💼 Kassir (Qo'shish)",
    ROLE_VIEWER: "👁 Ko'ruvchi (Faqat status)",
}

_ROLE_CACHE: dict[int, str] = {}


async def refresh_role_cache(db: AsyncSession) -> None:
    """Reload dynamic user_roles from database into in-memory lookup cache."""
    rows = (await db.scalars(select(UserRole))).all()
    _ROLE_CACHE.clear()
    for row in rows:
        if row.role in ALL_ROLES:
            _ROLE_CACHE[int(row.user_id)] = row.role


def set_cached_role(user_id: int, role: Optional[str]) -> None:
    """Update cached role after create/update/delete."""
    if role is None:
        _ROLE_CACHE.pop(int(user_id), None)
    elif role in ALL_ROLES:
        _ROLE_CACHE[int(user_id)] = role


def clear_role_cache() -> None:
    """Clear in-memory dynamic role cache (mainly for isolated tests)."""
    _ROLE_CACHE.clear()


def get_user_role(user_id: int | None, allow_group_anon: bool = False) -> Optional[str]:
    """Resolve effective role. Fails closed (returns None) when ADMIN_IDS is empty and not in user_roles."""
    if allow_group_anon and user_id == ANONYMOUS_ADMIN_BOT_ID:
        return ROLE_ADMIN
    if not user_id:
        return None
    if int(user_id) in get_settings().admin_id_list:
        return ROLE_ADMIN
    return _ROLE_CACHE.get(int(user_id))


def is_authorized(user_id: int | None, allow_group_anon: bool = False) -> bool:
    """True if user holds any recognized role (admin, kassir, or viewer)."""
    return get_user_role(user_id, allow_group_anon=allow_group_anon) is not None


def is_admin_role(user_id: int | None, allow_group_anon: bool = False) -> bool:
    """True only for ADMIN_IDS or DB users with role='admin'."""
    return get_user_role(user_id, allow_group_anon=allow_group_anon) == ROLE_ADMIN


def can_write_role(user_id: int | None) -> bool:
    """True for roles permitted to record cash inflows, nakladnoys, and nasiya entries."""
    return get_user_role(user_id) in (ROLE_ADMIN, ROLE_KASSIR)


def has_role(user_id: int | None, *roles: str, allow_group_anon: bool = False) -> bool:
    """True if user's role is one of the given allowed roles."""
    role = get_user_role(user_id, allow_group_anon=allow_group_anon)
    return role is not None and role in roles


async def deny_if_unauthorized(
    event: Message | CallbackQuery,
    allowed_roles: tuple[str, ...] = ALL_ROLES,
) -> bool:
    """Send polite denial if actor lacks required role. Returns True when denied."""
    uid = event.from_user.id if event.from_user else None
    role = get_user_role(uid)
    if role is not None and role in allowed_roles:
        return False

    if role is None:
        text = (
            f"⛔ Sizda ushbu botdan foydalanish huquqi yo'q.\n"
            f"🆔 ID: <code>{uid or 0}</code> (adminga yuboring)"
        )
        alert = "⛔ Sizda ushbu botdan foydalanish huquqi yo'q."
    else:
        text = "🔒 Bu amal faqat admin/kassir huquqiga ega foydalanuvchilar uchun."
        alert = "🔒 Sizning rolingizda bu amalga ruxsat yo'q."

    if isinstance(event, CallbackQuery):
        await event.answer(alert, show_alert=True)
    else:
        await event.answer(text, parse_mode="HTML")
    return True
