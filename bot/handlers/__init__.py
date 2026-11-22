"""Handlers router assembly for Hisobot Bot."""

from aiogram import Router

from bot.handlers.admin_tools import router as admin_router
from bot.handlers.apk_link import router as apk_router
from bot.handlers.nasiya import router as nasiya_router
from bot.handlers.navigation import router as navigation_router
from bot.handlers.prixod_itog import router as prixod_router
from bot.handlers.settings_groups import router as settings_router
from bot.handlers.wallet_nakladnoy import router as wallet_router


def get_main_router() -> Router:
    """Combine all feature routers in strict priority order."""
    root = Router()
    # navigation_router MUST come first so menu buttons & /cancel override any active FSM wait state.
    root.include_router(navigation_router)
    root.include_router(admin_router)
    root.include_router(apk_router)
    root.include_router(nasiya_router)
    root.include_router(settings_router)
    root.include_router(prixod_router)
    # wallet_router contains FSM text handlers & fallback photo/voice/text handlers, so include last.
    root.include_router(wallet_router)
    return root
