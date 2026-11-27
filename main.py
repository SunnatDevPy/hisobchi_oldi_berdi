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
from aiogram.exceptions import TelegramUnauthorizedError
from aiogram.types import BotCommand, BotCommandScopeAllPrivateChats, MenuButtonWebApp, WebAppInfo

from bot.auth import refresh_role_cache
from bot.handlers import get_main_router
from bot.keyboards import get_webapp_url
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
    """Force IPv4 to api.telegram.org and recycle idle sockets to avoid silent NAT stalls on VPS."""

    def __init__(self, **kwargs) -> None:
        super().__init__(**kwargs)
        self._connector_init["family"] = socket.AF_INET
        # Short keep-alive: stale pooled sockets silently dropped by NAT caused 60s+ polling hangs.
        self._connector_init["keepalive_timeout"] = 8
        self._connector_init["enable_cleanup_closed"] = True


async def _register_bot_commands(bot: Bot) -> None:
    """Register quick "/" commands in Telegram's private chat menu (T8)."""
    commands = [
        BotCommand(command="start", description="Bosh menyu"),
        BotCommand(command="cancel", description="Amalni bekor qilish"),
        BotCommand(command="nasiya", description="Postavshiklarga nasiya (qarz)"),
        BotCommand(command="sverka", description="Oylik postavshiklar sverkasi"),
        BotCommand(command="kassa_sverka", description="Oraliq va asosiy kassa sverkalari"),
        BotCommand(command="stats", description="Haftalik / oylik statistika"),
        BotCommand(command="audit", description="O'zgarishlar va AI sarfi"),
        BotCommand(command="roles", description="Foydalanuvchi rollari"),
        BotCommand(command="apk", description="Mobil ilova (APK) ulash"),
        BotCommand(command="backup", description="Hozir backup olish"),
    ]
    try:
        await bot.set_my_commands(commands, scope=BotCommandScopeAllPrivateChats())
    except Exception:
        logger.debug("set_my_commands skipped")


async def _register_admin_webapp_menu(bot: Bot) -> None:
    """Attach the Telegram Mini App menu button exclusively for configured primary admins."""
    webapp_url = get_webapp_url()
    if not webapp_url:
        return
    for admin_id in get_settings().admin_id_list:
        try:
            await bot.set_chat_menu_button(
                chat_id=admin_id,
                menu_button=MenuButtonWebApp(
                    text="📱 Hisobchi",
                    web_app=WebAppInfo(url=webapp_url),
                ),
            )
        except Exception:
            logger.debug("set_chat_menu_button skipped for admin_id=%s", admin_id)


async def _run_api_server(host: str, port: int) -> None:
    """Run embedded FastAPI mobile API server inside the bot asyncio loop."""
    import uvicorn
    from api.app import create_api_app

    config = uvicorn.Config(
        create_api_app(),
        host=host,
        port=port,
        log_level="warning",
        access_log=False,
    )
    server = uvicorn.Server(config)
    logger.info("Starting Hisobchi Mobile REST API on %s:%s", host, port)
    await server.serve()


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

    from api.deps import set_bot

    set_bot(bot)
    await _register_bot_commands(bot)
    await _register_admin_webapp_menu(bot)
    bg_tasks = [
        asyncio.create_task(backup_scheduler(bot)),
        asyncio.create_task(daily_report_scheduler(bot)),
    ]
    if settings.API_ENABLED:
        bg_tasks.append(asyncio.create_task(_run_api_server(settings.API_HOST, settings.API_PORT)))

    logger.info("Starting Hisobot Bot polling...")
    try:
        await bot.delete_webhook(drop_pending_updates=True)
        await dp.start_polling(
            bot,
            polling_timeout=20,
            allowed_updates=dp.resolve_used_update_types(),
        )
    except TelegramUnauthorizedError:
        logger.error(
            "BOT_TOKEN yaroqsiz yoki @BotFather da bekor qilingan (401 Unauthorized)! "
            "Yangi token olgach .env ni yangilang. Mobil REST API ishlashda davom etadi."
        )
        set_bot(None)
        with suppress(Exception):
            await bot.session.close()
        if settings.API_ENABLED and bg_tasks:
            await asyncio.gather(*bg_tasks)
        else:
            raise
    finally:
        set_bot(None)
        with suppress(Exception):
            await bot.session.close()
        for task in bg_tasks:
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task


if __name__ == "__main__":
    asyncio.run(run_bot())
