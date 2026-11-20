"""Scheduled daily status auto-sender and AI quota threshold warnings."""

from __future__ import annotations

import asyncio
import logging

from aiogram import Bot

from config import get_settings
from database.crud import (
    compute_session_summary,
    get_ai_usage_stats,
    get_app_setting,
    now_local,
    set_app_setting,
    today_iso,
)
from database.session import async_session_maker


logger = logging.getLogger("hisobot_bot.scheduler")

DEFAULT_DAILY_REPORT_TIME = "22:00"
DEFAULT_AI_DAILY_WARN_LIMIT = 80


async def maybe_send_daily_auto_report(bot: Bot) -> bool:
    """Send today's status report once per day after configured HH:MM."""
    settings = get_settings()
    admins = settings.admin_id_list
    if not admins:
        return False

    today = today_iso()
    now_hhmm = now_local().strftime("%H:%M")

    async with async_session_maker() as db:
        enabled = await get_app_setting(db, "auto_report_enabled", "on")
        if enabled != "on":
            return False
        target_time = await get_app_setting(db, "auto_report_time", DEFAULT_DAILY_REPORT_TIME)
        last_sent = await get_app_setting(db, "auto_report_last_sent_date", "")
        if last_sent == today or now_hhmm < target_time:
            return False

        summary = await compute_session_summary(db)
        if (
            not summary.confirmed_nakladnoys
            and not summary.cash_transactions
            and summary.opening_balance == 0
        ):
            await set_app_setting(db, "auto_report_last_sent_date", today)
            return False

    from bot.handlers.wallet_nakladnoy import render_status_text
    from bot.keyboards import status_actions_kb

    text = "⏰ <b>Avtomatik kunlik hisobot</b>\n\n" + render_status_text(summary)
    sent_any = False
    for admin_id in admins:
        try:
            await bot.send_message(
                admin_id,
                text,
                parse_mode="HTML",
                reply_markup=status_actions_kb(summary.session.id),
            )
            sent_any = True
        except Exception:
            logger.exception("Auto daily report failed for %s", admin_id)

    if sent_any:
        async with async_session_maker() as db:
            await set_app_setting(db, "auto_report_last_sent_date", today)
    return sent_any


async def daily_report_scheduler(bot: Bot) -> None:
    """Background loop checking every 45s whether the daily auto-report should fire."""
    while True:
        try:
            await maybe_send_daily_auto_report(bot)
        except Exception:
            logger.exception("Auto daily report check failed")
        await asyncio.sleep(45)


async def maybe_warn_ai_limit(bot: Bot) -> None:
    """Alert admins once per day if Gemini AI calls exceed the daily threshold."""
    admins = get_settings().admin_id_list
    if not admins:
        return
    today = today_iso()
    async with async_session_maker() as db:
        warned = await get_app_setting(db, "ai_limit_warned_date", "")
        if warned == today:
            return
        stats = await get_ai_usage_stats(db, today)
        if stats["calls"] < DEFAULT_AI_DAILY_WARN_LIMIT:
            return
        await set_app_setting(db, "ai_limit_warned_date", today)

    msg = (
        f"⚠️ <b>AI kunlik limit ogohlantirishi</b>\n"
        f"Bugun Gemini'ga <b>{stats['calls']} ta</b> so'rov yuborildi "
        f"(rasm: {stats['photo_calls']}, ovoz: {stats['audio_calls']}, "
        f"keshdan tejalgan: {stats['cache_hits']})."
    )
    for admin_id in admins:
        try:
            await bot.send_message(admin_id, msg, parse_mode="HTML")
        except Exception:
            pass
