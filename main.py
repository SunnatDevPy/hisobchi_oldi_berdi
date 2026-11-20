"""Entry point for Hisobot Bot (Aiogram 3 + SQLAlchemy Async + Gemini 2.5 Flash)."""

from __future__ import annotations

import asyncio
import logging
import socket

from aiogram import Bot, Dispatcher
from aiogram.client.default import DefaultBotProperties
from aiogram.client.session.aiohttp import AiohttpSession
from aiogram.enums import ParseMode
from aiogram.fsm.storage.memory import MemoryStorage

from bot.handlers import get_main_router
from config import get_settings
from database.session import init_db
from services.backup import backup_scheduler


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
)
logger = logging.getLogger("hisobot_bot")


class IPv4AiohttpSession(AiohttpSession):
    """Force IPv4 connections to api.telegram.org to avoid IPv6 timeout stalls on VPS."""

    def __init__(self, **kwargs) -> None:
        super().__init__(**kwargs)
        self._connector_init["family"] = socket.AF_INET


async def run_bot() -> None:
    """Initialize database and start long polling."""
    settings = get_settings()
    if not settings.BOT_TOKEN or settings.BOT_TOKEN == "YOUR_TELEGRAM_BOT_TOKEN_HERE":
        raise RuntimeError(
            "BOT_TOKEN sozlanmagan! .env fayliga @BotFather dan olingan tokenni kiriting."
        )

    await init_db()
    logger.info("Database initialized successfully.")

    bot = Bot(
        token=settings.BOT_TOKEN,
        session=IPv4AiohttpSession(timeout=60),
        default=DefaultBotProperties(parse_mode=ParseMode.HTML),
    )
    dp = Dispatcher(storage=MemoryStorage())
    dp.include_router(get_main_router())

    logger.info("Starting Hisobot Bot polling...")
    backup_task = asyncio.create_task(backup_scheduler(bot))
    await bot.delete_webhook(drop_pending_updates=True)
    await dp.start_polling(
        bot,
        polling_timeout=20,
        allowed_updates=dp.resolve_used_update_types(),
    )


if __name__ == "__main__":
    asyncio.run(run_bot())
