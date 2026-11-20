"""Handlers router assembly for Hisobot Bot."""

from aiogram import Router

from bot.handlers.admin_tools import router as admin_router
from bot.handlers.prixod_itog import router as prixod_router
from bot.handlers.settings_groups import router as settings_router
from bot.handlers.wallet_nakladnoy import router as wallet_router


def get_main_router() -> Router:
    """Combine all feature routers in priority order."""
    root = Router()
    root.include_router(admin_router)
    root.include_router(settings_router)
    root.include_router(prixod_router)
    # wallet_router contains fallback photo/voice/text handlers, so include last
    root.include_router(wallet_router)
    return root
