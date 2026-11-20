"""Entry point for Hisobot Bot (Aiogram 3 + SQLAlchemy Async + Gemini Flash)."""

from __future__ import annotations

import asyncio
from contextlib import suppress
import logging
import socket

from aiogram import Bot, Dispatcher
from aiogram.client.default import DefaultBotProperties
from aiogram.client.session.aiohttp import AiohttpSession
from aiogram.enums import ParseMode
from aiogram.types import BotCommand, BotCommandScopeAllPrivateChats

from bot.auth import refresh_role_cache
from bot.handlers import get_main_router
from bot.storage import DatabaseFSMStorage
from config import get_settings
from database.session import async_session_maker, init_db
from services.backup import backup_scheduler
from services.scheduler import daily_report_scheduler


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


async def _register_bot_commands(bot: Bot) -> None:
    """Register quick "/" commands in Telegram's private chat menu (T8)."""
    commands = [
        BotCommand(command="start", description="Bosh menyu"),
        BotCommand(command="cancel", description="Amalni bekor qilish"),
        BotCommand(command="nasiya", description="Postavshiklarga nasiya (qarz)"),
        BotCommand(command="sverka", description="Oylik postavshiklar sverkasi"),
        BotCommand(command="stats", description="Haftalik / oylik statistika"),
        BotCommand(command="audit", description="O'zgarishlar va AI sarfi"),
        BotCommand(command="roles", description="Foydalanuvchi rollari"),
        BotCommand(command="backup", description="Hozir backup olish"),
    ]
    try:
        await bot.set_my_commands(commands, scope=BotCommandScopeAllPrivateChats())
    except Exception:
        logger.debug("set_my_commands skipped")


async def run_bot() -> None:
    """Initialize database, load role cache, register commands, and start polling."""
    settings = get_settings()
    if not settings.BOT_TOKEN or settings.BOT_TOKEN == "YOUR_TELEGRAM_BOT_TOKEN_HERE":
        raise RuntimeError(
            "BOT_TOKEN sozlanmagan! .env fayliga @BotFather dan olingan tokenni kiriting."
        )

    await init_db()
    async with async_session_maker() as db:
        await refresh_role_cache(db)
    logger.info("Database initialized successfully.")

    bot = Bot(
        token=settings.BOT_TOKEN,
        session=IPv4AiohttpSession(timeout=60),
        default=DefaultBotProperties(parse_mode=ParseMode.HTML),
    )
    dp = Dispatcher(storage=DatabaseFSMStorage(async_session_maker))
    dp.include_router(get_main_router())

    await _register_bot_commands(bot)
    backup_task = asyncio.create_task(backup_scheduler(bot))
    report_task = asyncio.create_task(daily_report_scheduler(bot))

    logger.info("Starting Hisobot Bot polling...")
    try:
        await bot.delete_webhook(drop_pending_updates=True)
        await dp.start_polling(
            bot,
            polling_timeout=20,
            allowed_updates=dp.resolve_used_update_types(),
        )
    finally:
        for task in (backup_task, report_task):
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task


if __name__ == "__main__":
    asyncio.run(run_bot())
