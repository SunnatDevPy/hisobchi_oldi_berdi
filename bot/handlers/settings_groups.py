"""Settings, group binding, supplier config, history/search, Excel ranges, RBAC roles & more hub."""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta
import html
import logging
import re
import time
from typing import Optional

from aiogram import F, Router
from aiogram.filters import Command, CommandObject, CommandStart
from aiogram.fsm.context import FSMContext
from aiogram.types import (
    BufferedInputFile,
    CallbackQuery,
    ChatMemberUpdated,
    MenuButtonWebApp,
    Message,
    WebAppInfo,
)

from bot.auth import (
    ANONYMOUS_ADMIN_BOT_ID,
    ROLE_ADMIN,
    ROLE_LABELS,
    deny_if_unauthorized,
    get_user_role,
    is_admin_role,
    is_authorized,  # re-exported for backward compatibility
    is_webapp_allowed,
    refresh_role_cache,
    set_cached_role,
)
from bot.keyboards import (
    ai_prefs_kb,
    auto_report_kb,
    cancel_reply_keyboard,
    delete_confirm_kb,
    export_range_kb,
    get_webapp_url,
    groups_config_kb,
    history_detail_kb,
    history_feed_kb,
    history_sessions_kb,
    main_menu_keyboard,
    more_menu_kb,
    prixod_history_kb,
    quick_bind_group_kb,
    role_pick_kb,
    roles_list_kb,
    settings_menu_kb,
    supplier_detail_kb,
    suppliers_list_kb,
)
from bot.states import SettingsStates, WalletStates
from config import get_settings
from database.crud import (
    add_or_update_supplier,
    append_supplier_alias,
    compute_session_summary,
    delete_supplier,
    delete_user_role,
    format_local_dt,
    get_ai_usage_stats,
    get_all_group_configs,
    get_app_setting,
    get_period_statistics,
    get_prixod_report,
    get_range_report_data,
    list_all_sessions,
    list_closed_sessions,
    list_prixod_reports,
    list_recent_cash_transactions,
    list_recent_nakladnoys,
    list_suppliers,
    list_user_roles,
    now_local,
    reopen_cash_session,
    search_nakladnoys,
    set_app_setting,
    set_group_config,
    set_user_role,
)
from database.models import DailyCashSession
from database.session import async_session_maker
from services.backup import send_backup
from services.excel_export import (
    build_history_excel,
    build_prixod_excel,
    build_range_excel,
    build_session_excel,
)
from services.gemini_ai import format_uzs


router = Router(name="settings_groups")
logger = logging.getLogger("hisobot_bot.groups")

ROLE_TITLES = {
    "nakladnoy": "📸 Nakladnoy guruhi",
    "prixod": "👑 Prixod (ITOG) guruhi",
    "kassa": "💰 Kassa / Rahbariyat guruhi",
}

DEEP_LINK_ROLE_MAP = {
    "bind_nakladnoy": "nakladnoy",
    "bind_prixod": "prixod",
    "bind_kassa": "kassa",
}

_BOT_USERNAME: str | None = None
_recently_bound_chats: dict[int, float] = {}


async def get_bot_username(bot) -> str:
    """Fetch and cache the bot username."""
    global _BOT_USERNAME
    if not _BOT_USERNAME:
        me = await bot.get_me()
        _BOT_USERNAME = me.username or "hisobchi_my_bot"
    return _BOT_USERNAME


async def _safe_edit(message: Message, text: str, reply_markup=None) -> None:
    try:
        await message.edit_text(text, parse_mode="HTML", reply_markup=reply_markup)
    except Exception as exc:
        if "message is not modified" not in str(exc).lower():
            logger.debug("edit fallback: %s", exc)


async def cmd_start(message: Message, state: FSMContext, start_arg: str = "") -> None:
    """Handle /start in private chat."""
    uid = message.from_user.id if message.from_user else None
    if not is_authorized(uid):
        await message.answer(
            "⛔ Sizda ushbu botdan foydalanish huquqi yo'q.\n"
            f"🆔 Sizning ID: <code>{uid or 0}</code> (adminga yuboring)",
            parse_mode="HTML",
        )
        return
    await state.clear()
    if start_arg.strip().lower() in {"apk_login", "apk", "login"} and uid:
        from bot.handlers.apk_link import _render_apk_home

        text, kb = await _render_apk_home(uid)
        await message.answer(text, parse_mode="HTML", reply_markup=kb)
        return
    role = get_user_role(uid) or "viewer"
    webapp_allowed = is_webapp_allowed(uid)
    webapp_url = get_webapp_url() if webapp_allowed else None
    if webapp_url and uid and message.bot is not None and hasattr(message.bot, "set_chat_menu_button"):
        try:
            await message.bot.set_chat_menu_button(
                chat_id=uid,
                menu_button=MenuButtonWebApp(
                    text="📱 Hisobchi",
                    web_app=WebAppInfo(url=webapp_url),
                ),
            )
        except Exception:
            logger.debug("set_chat_menu_button skipped on /start for %s", uid)

    webapp_hint = "\n• 📱 <b>/app</b> — Telegram ichida Mini App'ni ochish" if webapp_allowed else ""
    await message.answer(
        "👋 <b>Assalomu alaykum! Hisobot va Nakladnoy nazorat botiga xush kelibsiz.</b>\n\n"
        "Botda quyidagilarni bajarishingiz mumkin:\n"
        "• 📸 <b>Nakladnoy</b> — rasm/ovoz/matn yoki tez tugma bilan kiritish\n"
        "• ➕ <b>Pul oldim</b> — kirim va kassa qarzini yuritish\n"
        "• 📊 <b>Status</b> — jonli kassa qoldig'i va Excel eksport\n"
        "• ⚙️ <b>Boshqa</b> — tahrirlash, kunni yopish, nasiya, sverka va sozlamalar"
        f"{webapp_hint}\n\n"
        f"👤 Rol: <b>{ROLE_LABELS.get(role, role)}</b>\n"
        f"🆔 Sizning Telegram ID: <code>{uid}</code>",
        parse_mode="HTML",
        reply_markup=main_menu_keyboard(),
    )


async def open_more_menu(
    target: Message | CallbackQuery, state: FSMContext, actor_id: Optional[int] = None
) -> None:
    """Open ⚙️ Boshqa inline hub."""
    uid = actor_id if actor_id is not None else (target.from_user.id if target.from_user else None)
    if not is_authorized(uid):
        return
    await state.clear()
    role = get_user_role(uid) or "viewer"
    text = "⚙️ <b>Qo'shimcha bo'limlar va hisobotlar:</b>"
    kb = more_menu_kb(role, show_webapp=is_webapp_allowed(uid))
    if isinstance(target, CallbackQuery):
        await _safe_edit(target.message, text, reply_markup=kb)
        await target.answer()
    else:
        await target.answer(text, parse_mode="HTML", reply_markup=kb)


async def open_settings_menu(
    message: Message, state: FSMContext, actor_id: Optional[int] = None
) -> None:
    """Open Admin settings menu."""
    uid = actor_id if actor_id is not None else (message.from_user.id if message.from_user else None)
    if not is_admin_role(uid):
        await message.answer("🔒 Sozlamalar faqat admin uchun.")
        return
    await state.clear()
    await message.answer(
        "⚙️ <b>Sozlamalar va Boshqaruv:</b>\nKerakli bo'limni tanlang:",
        parse_mode="HTML",
        reply_markup=settings_menu_kb(),
    )


# ---------------------------------------------------------------------------
# ⚙️ Boshqa Hub Callbacks
# ---------------------------------------------------------------------------


@router.callback_query(F.data == "more:open")
async def cb_more_open(cb: CallbackQuery, state: FSMContext) -> None:
    await open_more_menu(cb, state, actor_id=cb.from_user.id)


@router.callback_query(F.data == "more:edit")
async def cb_more_edit(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    from bot.handlers.wallet_nakladnoy import handle_edit_confirmed_btn

    await cb.answer()
    await handle_edit_confirmed_btn(cb.message, state, actor_id=cb.from_user.id)


@router.callback_query(F.data == "more:close_day")
async def cb_more_close_day(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    from bot.handlers.wallet_nakladnoy import handle_close_day_start

    await cb.answer()
    await handle_close_day_start(cb.message, state, actor_id=cb.from_user.id)


@router.callback_query(F.data == "more:kassa_debt")
async def cb_more_kassa_debt(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin", "kassir")):
        return
    from bot.handlers.wallet_nakladnoy import handle_kassa_debt_button

    await cb.answer()
    await handle_kassa_debt_button(cb.message, state, actor_id=cb.from_user.id)


@router.callback_query(F.data == "more:kassa_sverka")
async def cb_more_kassa_sverka(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin", "kassir", "viewer")):
        return
    from bot.handlers.wallet_nakladnoy import handle_kassa_sverka_view

    await cb.answer()
    await handle_kassa_sverka_view(cb.message, actor_id=cb.from_user.id, edit=True)


@router.callback_query(F.data == "more:prixod")
async def cb_more_prixod(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin", "kassir")):
        return
    from bot.handlers.prixod_itog import start_prixod_flow

    await cb.answer()
    await start_prixod_flow(cb.message, state, actor_id=cb.from_user.id)


@router.callback_query(F.data == "more:nasiya")
async def cb_more_nasiya(cb: CallbackQuery, state: FSMContext) -> None:
    from bot.handlers.nasiya import show_nasiya_home

    await show_nasiya_home(cb, state)


@router.callback_query(F.data == "more:stats")
async def cb_more_stats(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb):
        return
    from bot.handlers.admin_tools import _render_period_stats_text
    from bot.keyboards import stats_menu_kb

    today = now_local().date()
    week_start = (today - timedelta(days=6)).strftime("%Y-%m-%d")
    async with async_session_maker() as db:
        st = await get_period_statistics(db, week_start, today.strftime("%Y-%m-%d"))
    await _safe_edit(
        cb.message,
        _render_period_stats_text("Oxirgi 7 kunlik statistika", st),
        reply_markup=stats_menu_kb(),
    )
    await cb.answer()


@router.callback_query(F.data == "more:settings")
async def cb_more_settings(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    await state.clear()
    await _safe_edit(
        cb.message,
        "⚙️ <b>Sozlamalar va Boshqaruv:</b>\nKerakli bo'limni tanlang:",
        reply_markup=settings_menu_kb(),
    )
    await cb.answer()


# ---------------------------------------------------------------------------
# Group Binding Commands (work inside Telegram Groups!)
# ---------------------------------------------------------------------------


async def _bind_group_command(message: Message, role: str) -> None:
    if not is_admin_role(
        message.from_user.id if message.from_user else None,
        allow_group_anon=(message.chat.type != "private"),
    ):
        return
    if message.chat.type == "private":
        await message.answer(
            f"ℹ️ <b>{ROLE_TITLES[role]}</b> ni ulash uchun botni kerakli Telegram guruhiga qo'shing "
            f"va o'sha guruh ichida <code>/set_{role}_group</code> buyrug'ini yuboring.\n\n"
            "Yoki <b>⚙️ Boshqa -> ⚙️ Sozlamalar -> 🔗 Guruhlarni sozlash</b> orqali guruh ID sini kiriting.",
            parse_mode="HTML",
        )
        return

    title = message.chat.title or f"Group {message.chat.id}"
    async with async_session_maker() as db:
        await set_group_config(db, role=role, chat_id=message.chat.id, title=title)

    await message.answer(
        f"✅ Ushbu guruh muvaffaqiyatli <b>{ROLE_TITLES[role]}</b> sifatida biriktirildi!\n"
        f"🆔 Chat ID: <code>{message.chat.id}</code>",
        parse_mode="HTML",
    )


@router.message(Command("set_nakladnoy_group"))
async def cmd_set_nakladnoy_group(message: Message) -> None:
    await _bind_group_command(message, "nakladnoy")


@router.message(Command("set_prixod_group"))
async def cmd_set_prixod_group(message: Message) -> None:
    await _bind_group_command(message, "prixod")


@router.message(Command("set_kassa_group"))
async def cmd_set_kassa_group(message: Message) -> None:
    await _bind_group_command(message, "kassa")


@router.message(Command("group_id"))
async def cmd_group_id(message: Message) -> None:
    if not is_authorized(message.from_user.id if message.from_user else None):
        return
    await message.answer(f"🆔 Chat ID: <code>{message.chat.id}</code>", parse_mode="HTML")


@router.message(CommandStart(deep_link=True), F.chat.type.in_({"group", "supergroup"}))
async def cmd_start_group_bind(message: Message, command: CommandObject) -> None:
    """Auto-bind group when bot is added via Telegram startgroup=<role>&admin=... deep link."""
    user_id = message.from_user.id if message.from_user else None
    if not is_admin_role(user_id, allow_group_anon=True):
        return

    role = DEEP_LINK_ROLE_MAP.get((command.args or "").strip())
    if not role:
        return

    title = message.chat.title or f"Group {message.chat.id}"
    _recently_bound_chats[message.chat.id] = time.monotonic()

    async with async_session_maker() as db:
        await set_group_config(db, role=role, chat_id=message.chat.id, title=title)

    await message.answer(
        f"✅ Ushbu guruh avtomatik <b>{ROLE_TITLES[role]}</b> sifatida ulandi!\n"
        f"🆔 Chat ID: <code>{message.chat.id}</code>",
        parse_mode="HTML",
    )

    if user_id and user_id != ANONYMOUS_ADMIN_BOT_ID:
        try:
            status_text = await _render_groups_status()
            username = await get_bot_username(message.bot)
            await message.bot.send_message(
                chat_id=user_id,
                text=(
                    f"✅ <b>{html.escape(title)}</b> guruhi avtomatik "
                    f"<b>{ROLE_TITLES[role]}</b> sifatida saqlandi! (<code>{message.chat.id}</code>)\n\n"
                    + status_text
                ),
                parse_mode="HTML",
                reply_markup=groups_config_kb(username),
            )
        except Exception:
            pass


@router.my_chat_member(F.chat.type.in_({"group", "supergroup"}))
async def on_bot_added_to_group(event: ChatMemberUpdated) -> None:
    """Auto-detect when bot is added to or promoted in a group and offer 1-tap role binding in DM."""
    new_status = event.new_chat_member.status
    old_status = event.old_chat_member.status
    if new_status not in ("member", "administrator") or new_status == old_status:
        return

    user_id = event.from_user.id if event.from_user else None
    if not is_admin_role(user_id) or not user_id:
        return

    await asyncio.sleep(1.5)
    bound_ts = _recently_bound_chats.get(event.chat.id, 0.0)
    if time.monotonic() - bound_ts < 10.0:
        return

    title = event.chat.title or f"Guruh ({event.chat.id})"
    async with async_session_maker() as db:
        groups = await get_all_group_configs(db)
        existing_role = next((r for r, cfg in groups.items() if cfg.chat_id == event.chat.id), None)
        if existing_role and new_status == "administrator":
            await set_group_config(db, role=existing_role, chat_id=event.chat.id, title=title)
            try:
                await event.bot.send_message(
                    chat_id=user_id,
                    text=(
                        f"✅ <b>{html.escape(title)}</b> (<code>{event.chat.id}</code>) "
                        f"<b>{ROLE_TITLES[existing_role]}</b> da botga admin huquqi berildi!"
                    ),
                    parse_mode="HTML",
                )
            except Exception:
                pass
            return

    admin_note = (
        "✅ Bot guruhga <b>admin</b> sifatida qo'shildi."
        if new_status == "administrator"
        else "ℹ️ Bot guruhga qo'shildi (xabarlarni o'zgartirish uchun admin huquqi tavsiya etiladi)."
    )
    try:
        await event.bot.send_message(
            chat_id=user_id,
            text=(
                f"🆕 <b>Yangi guruh aniqlandi!</b>\n"
                f"📌 Nomi: <b>{html.escape(title)}</b>\n"
                f"🆔 Chat ID: <code>{event.chat.id}</code>\n"
                f"{admin_note}\n\n"
                "Ushbu guruhni qaysi vazifa uchun saqlaymiz?"
            ),
            parse_mode="HTML",
            reply_markup=quick_bind_group_kb(event.chat.id),
        )
    except Exception:
        pass


@router.callback_query(F.data.startswith("grp:qbind:"))
async def cb_group_quick_bind(cb: CallbackQuery) -> None:
    """Save auto-detected group role from quick-bind DM prompt."""
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    parts = cb.data.split(":")
    role = parts[2]
    chat_id = int(parts[3])

    title = f"Guruh ({chat_id})"
    try:
        chat = await cb.bot.get_chat(chat_id)
        if chat.title:
            title = chat.title
    except Exception:
        pass

    async with async_session_maker() as db:
        await set_group_config(db, role=role, chat_id=chat_id, title=title)

    username = await get_bot_username(cb.bot)
    status_text = await _render_groups_status()
    await _safe_edit(
        cb.message,
        f"✅ <b>{html.escape(title)}</b> (<code>{chat_id}</code>) — "
        f"<b>{ROLE_TITLES.get(role, role)}</b> sifatida saqlandi!\n\n{status_text}",
        reply_markup=groups_config_kb(username),
    )
    await cb.answer("✅ Guruh saqlandi!")


# ---------------------------------------------------------------------------
# Settings Menu & Admin Tools (AI Prefs, AI Stats, Auto-Report, Roles, Audit, Backup)
# ---------------------------------------------------------------------------


@router.callback_query(F.data == "set:back")
async def cb_settings_back(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    await state.clear()
    await _safe_edit(
        cb.message,
        "⚙️ <b>Sozlamalar va Boshqaruv:</b>\nKerakli bo'limni tanlang:",
        reply_markup=settings_menu_kb(),
    )
    await cb.answer()


@router.callback_query(F.data == "set:ai_stats")
async def cb_ai_stats(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    async with async_session_maker() as db:
        st = await get_ai_usage_stats(db)
    text = (
        f"🤖 <b>AI Sarfi Hisoblagichi</b>\n"
        f"===============================\n"
        f"📅 <b>Bugun ({st['date']}):</b>\n"
        f"• Jami AI chaqiruv: <b>{st['calls']} ta</b> (📸 {st['photo_calls']} | 🎤 {st['audio_calls']})\n"
        f"• Keshdan tejalgan (dublikat rasm): <b>{st['cache_hits']} ta</b>\n"
        f"• Jami token: <b>{format_uzs(st['total_tokens'])}</b> "
        f"(kirish {format_uzs(st['prompt_tokens'])} / chiqish {format_uzs(st['output_tokens'])})\n\n"
        f"🗓 <b>Joriy oy jami:</b>\n"
        f"• AI chaqiruvlar: <b>{st['month_calls']} ta</b> | Kesh: <b>{st['month_cache_hits']} ta</b>\n"
        f"• Oylik token: <b>{format_uzs(st['month_tokens'])}</b>\n\n"
        "<i>Eslatma: Matn, Status, Excel va Sverka 0 token sarflaydi.</i>"
    )
    from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

    kb = InlineKeyboardMarkup(
        inline_keyboard=[[InlineKeyboardButton(text="⬅️ Orqaga", callback_data="set:back")]]
    )
    await _safe_edit(cb.message, text, reply_markup=kb)
    await cb.answer()


async def _render_auto_report() -> tuple[str, bool, str]:
    async with async_session_maker() as db:
        enabled = (await get_app_setting(db, "auto_report_enabled", "on")) == "on"
        t_str = await get_app_setting(db, "auto_report_time", "22:00")
    text = (
        "⏰ <b>Avtomatik Kunlik Status Hisoboti</b>\n\n"
        f"• Holat: <b>{'✅ Yoqilgan' if enabled else '❌ O‘chiq'}</b>\n"
        f"• Yuborish vaqti (Toshkent): <b>{t_str}</b>\n\n"
        "<i>Har kuni belgilangan vaqtda kunlik status adminlarga shaxsiy chatga yuboriladi.</i>"
    )
    return text, enabled, t_str


@router.callback_query(F.data == "set:auto_report")
async def cb_auto_report_menu(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    text, enabled, t_str = await _render_auto_report()
    await _safe_edit(cb.message, text, reply_markup=auto_report_kb(enabled, t_str))
    await cb.answer()


@router.callback_query(F.data == "ar:toggle")
async def cb_auto_report_toggle(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    async with async_session_maker() as db:
        cur = await get_app_setting(db, "auto_report_enabled", "on")
        await set_app_setting(db, "auto_report_enabled", "off" if cur == "on" else "on")
    text, enabled, t_str = await _render_auto_report()
    await _safe_edit(cb.message, text, reply_markup=auto_report_kb(enabled, t_str))
    await cb.answer("✅ Saqlandi")


@router.callback_query(F.data.startswith("ar:time:"))
async def cb_auto_report_time(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    new_time = cb.data[len("ar:time:") :]
    if new_time not in ("21:00", "22:00", "23:00"):
        await cb.answer("Noto'g'ri vaqt")
        return
    async with async_session_maker() as db:
        await set_app_setting(db, "auto_report_time", new_time)
    text, enabled, t_str = await _render_auto_report()
    await _safe_edit(cb.message, text, reply_markup=auto_report_kb(enabled, t_str))
    await cb.answer(f"⏰ {new_time} saqlandi")


@router.callback_query(F.data == "set:audit")
async def cb_settings_audit(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    from bot.handlers.admin_tools import send_audit_view

    await send_audit_view(cb)


@router.callback_query(F.data == "set:backup")
async def cb_settings_backup(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    await cb.answer("💾 Zaxira tayyorlanmoqda...")
    ok = await send_backup(cb.bot, [cb.from_user.id])
    if not ok:
        await cb.message.answer("❌ Zaxira yuborilmadi (logni tekshiring).")


# ---------------------------------------------------------------------------
# User Roles (RBAC) Management (Y6)
# ---------------------------------------------------------------------------


async def _render_roles_view():
    async with async_session_maker() as db:
        roles = await list_user_roles(db)
    super_admins = get_settings().admin_id_list
    text = (
        "👥 <b>Foydalanuvchi rollari:</b>\n"
        f"• Super-adminlar (.env): <code>{', '.join(str(x) for x in super_admins) or '-'}</code>\n\n"
        "👑 Admin — hamma amal | 💼 Kassir — qo'shish | 👁 Ko'ruvchi — faqat status:"
    )
    return text, roles_list_kb(roles, super_admins)


@router.callback_query(F.data == "set:roles")
async def cb_roles_menu(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    await state.clear()
    text, kb = await _render_roles_view()
    await _safe_edit(cb.message, text, reply_markup=kb)
    await cb.answer()


@router.callback_query(F.data == "role:add")
async def cb_role_add_prompt(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    await state.set_state(SettingsStates.waiting_role_user_id)
    await cb.message.answer(
        "👤 Yangi foydalanuvchining <b>Telegram ID</b> sini (va xohlasangiz ismini) yuboring.\n"
        "Masalan: <code>123456789 Ali kassir</code>\n"
        "<i>(Foydalanuvchi botga /start bosganda o'z ID sini ko'radi.)</i>",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.message(SettingsStates.waiting_role_user_id, F.chat.type == "private")
async def process_role_user_id(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message, ("admin",)):
        return
    raw = (message.text or "").strip().split(maxsplit=1)
    if not raw or not raw[0].isdigit():
        await message.answer("⚠️ ID raqam bo'lishi kerak (masalan: <code>123456789 Ali</code>):", parse_mode="HTML")
        return
    uid = int(raw[0])
    label = raw[1].strip() if len(raw) > 1 else ""
    await state.update_data(new_role_uid=uid, new_role_label=label)
    await message.answer(
        f"👤 ID: <code>{uid}</code> {html.escape(label)}\nRolni tanlang:",
        parse_mode="HTML",
        reply_markup=role_pick_kb(uid),
    )


@router.callback_query(F.data.startswith("role:pick:"))
async def cb_role_pick(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    parts = cb.data.split(":")
    uid = int(parts[2])
    role = parts[3]
    data = await state.get_data()
    label = str(data.get("new_role_label") or "")
    async with async_session_maker() as db:
        await set_user_role(db, uid, role, label=label)
        await refresh_role_cache(db)
    await state.clear()
    text, kb = await _render_roles_view()
    await _safe_edit(cb.message, f"✅ Saqlandi: <code>{uid}</code> → {ROLE_LABELS.get(role, role)}\n\n{text}", reply_markup=kb)
    await cb.message.answer("📋 Asosiy menyu:", reply_markup=main_menu_keyboard())
    await cb.answer("✅ Saqlandi")


@router.callback_query(F.data.startswith("role:del:"))
async def cb_role_del_prompt(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    uid = int(cb.data.split(":")[-1])
    await _safe_edit(
        cb.message,
        f"⚠️ Foydalanuvchi <code>{uid}</code> ruxsatini olib tashlaysizmi?",
        reply_markup=delete_confirm_kb(f"role:del_yes:{uid}", "set:roles"),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("role:del_yes:"))
async def cb_role_del_confirm(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    uid = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        await delete_user_role(db, uid)
        set_cached_role(uid, None)
    text, kb = await _render_roles_view()
    await _safe_edit(cb.message, text, reply_markup=kb)
    await cb.answer("🗑 O'chirildi")


# ---------------------------------------------------------------------------
# AI Prefs & Group Config
# ---------------------------------------------------------------------------


async def _render_ai_prefs() -> tuple[str, bool, str]:
    async with async_session_maker() as db:
        auto_str = await get_app_setting(db, "auto_confirm", "on")
        round_mode = await get_app_setting(db, "round_mode", "floor_1000")
    auto_on = auto_str == "on"
    round_desc = {
        "floor_1000": "1 000 ga pastga (192 620 → 192 000)",
        "nearest_1000": "Eng yaqin 1 000 ga (192 620 → 193 000)",
        "none": "Yaxlitlamaslik (aniq summa)",
    }.get(round_mode, round_mode)
    text = (
        "⚡ <b>Tez rejim va Summani yaxlitlash</b>\n\n"
        f"• <b>Avto-tasdiqlash:</b> {'✅ YOQILGAN (aniq o‘qilsa darhol guruhga yuboradi)' if auto_on else '❌ O‘CHIQ (har gal tasdiqlash so‘raydi)'}\n"
        f"• <b>Yaxlitlash (Okruglit):</b> <b>{round_desc}</b>\n\n"
        "<i>Eslatma: Asl summa Excel'da alohida ustunda saqlanadi.</i>"
    )
    return text, auto_on, round_mode


@router.callback_query(F.data == "set:ai_prefs")
async def cb_ai_prefs_menu(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    text, auto_on, round_mode = await _render_ai_prefs()
    await _safe_edit(cb.message, text, reply_markup=ai_prefs_kb(auto_on, round_mode))
    await cb.answer()


@router.callback_query(F.data == "pref:toggle_auto")
async def cb_toggle_auto_confirm(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    async with async_session_maker() as db:
        cur = await get_app_setting(db, "auto_confirm", "on")
        await set_app_setting(db, "auto_confirm", "off" if cur == "on" else "on")
    text, auto_on, round_mode = await _render_ai_prefs()
    await _safe_edit(cb.message, text, reply_markup=ai_prefs_kb(auto_on, round_mode))
    await cb.answer("✅ Saqlandi")


@router.callback_query(F.data.startswith("pref:round:"))
async def cb_set_round_mode(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    mode = cb.data.split(":")[-1]
    if mode not in ("floor_1000", "nearest_1000", "none"):
        await cb.answer("Noto'g'ri rejim")
        return
    async with async_session_maker() as db:
        await set_app_setting(db, "round_mode", mode)
    text, auto_on, round_mode = await _render_ai_prefs()
    await _safe_edit(cb.message, text, reply_markup=ai_prefs_kb(auto_on, round_mode))
    await cb.answer("✅ Yaxlitlash saqlandi")


async def _render_groups_status() -> str:
    async with async_session_maker() as db:
        groups = await get_all_group_configs(db)
    lines = ["🔗 <b>Ulangan Telegram Guruhlar:</b>\n"]
    for role, title in ROLE_TITLES.items():
        cfg = groups.get(role)
        if cfg:
            lines.append(
                f"• <b>{title}:</b> {html.escape(cfg.title)} (<code>{cfg.chat_id}</code>)"
            )
        else:
            lines.append(f"• <b>{title}:</b> <i>Ulanmagan</i>")
    lines.append(
        "\n💡 <b>1 bosishda oson ulash:</b> Pastdagi tugmani bosing — bot guruh ID sini avtomatik saqlaydi."
    )
    return "\n".join(lines)


@router.callback_query(F.data == "set:groups")
async def cb_groups_menu(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    text = await _render_groups_status()
    username = await get_bot_username(cb.bot)
    await _safe_edit(cb.message, text, reply_markup=groups_config_kb(username))
    await cb.answer()


@router.callback_query(F.data.startswith("grp:set_id:"))
async def cb_group_set_id_prompt(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    role = cb.data.split(":")[-1]
    await state.set_state(SettingsStates.waiting_group_chat_id)
    await state.update_data(group_role=role)
    await cb.message.answer(
        f"🆔 <b>{ROLE_TITLES.get(role, role)}</b> uchun Chat ID ni yuboring\n"
        "(masalan: <code>-1001234567890</code>):",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.message(SettingsStates.waiting_group_chat_id, F.chat.type == "private")
async def process_group_chat_id(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message, ("admin",)):
        return
    raw = (message.text or "").strip()
    try:
        chat_id = int(raw)
    except ValueError:
        await message.answer("⚠️ Noto'g'ri format! Guruh ID raqam bo'lishi kerak (masalan: `-1001234567890`).")
        return

    data = await state.get_data()
    role = data.get("group_role", "nakladnoy")
    title = f"Guruh ({chat_id})"
    try:
        chat = await message.bot.get_chat(chat_id)
        if chat.title:
            title = chat.title
    except Exception:
        pass

    async with async_session_maker() as db:
        await set_group_config(db, role=role, chat_id=chat_id, title=title)

    await state.clear()
    await message.answer(
        f"✅ <b>{ROLE_TITLES.get(role, role)}</b> saqlandi: {html.escape(title)} (<code>{chat_id}</code>)",
        parse_mode="HTML",
        reply_markup=main_menu_keyboard(),
    )


@router.callback_query(F.data == "grp:test_ping")
async def cb_groups_test_ping(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    async with async_session_maker() as db:
        groups = await get_all_group_configs(db)
    if not groups:
        await cb.answer("Hali birorta ham guruh ulanmagan!", show_alert=True)
        return

    results = []
    for role, cfg in groups.items():
        try:
            await cb.bot.send_message(
                cfg.chat_id,
                f"✅ Test xabar: Ushbu guruh <b>{ROLE_TITLES.get(role, role)}</b> sifatida ulangan.",
                parse_mode="HTML",
            )
            results.append(f"✅ {ROLE_TITLES.get(role, role)}: yuborildi")
        except Exception as exc:
            results.append(f"❌ {ROLE_TITLES.get(role, role)}: xato ({exc})")

    await cb.message.answer("\n".join(results), parse_mode="HTML")
    await cb.answer()


# ---------------------------------------------------------------------------
# Supplier Configuration
# ---------------------------------------------------------------------------


@router.callback_query(F.data == "set:suppliers")
async def cb_suppliers_menu(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    async with async_session_maker() as db:
        suppliers = await list_suppliers(db, active_only=True)
    await _safe_edit(
        cb.message,
        "🏢 <b>Ta'minotchilar ro'yxati (ITOG & Sinonimlar):</b>\n"
        "YesPOS nomlarini bog'lash yoki yangi ta'minotchi qo'shish uchun tanlang:",
        reply_markup=suppliers_list_kb(suppliers),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("sup:view:"))
async def cb_supplier_detail(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    sup_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        suppliers = await list_suppliers(db, active_only=False)
        sup = next((s for s in suppliers if s.id == sup_id), None)
    if not sup:
        await cb.answer("Topilmadi", show_alert=True)
        return
    await _safe_edit(
        cb.message,
        f"🏢 <b>{html.escape(sup.display_name)}</b>\n"
        f"📌 Toifa: <b>{sup.default_category.upper()}</b>\n"
        f"🔗 Sinonimlar:\n<code>{html.escape(sup.aliases or 'yoq')}</code>",
        reply_markup=supplier_detail_kb(sup.id),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("sup:alias:"))
async def cb_supplier_alias_prompt(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    sup_id = int(cb.data.split(":")[-1])
    await state.set_state(SettingsStates.waiting_append_alias)
    await state.update_data(supplier_id=sup_id)
    await cb.message.answer(
        "🔗 Sinonim / YesPOS nomini yozib yuboring\n"
        "(masalan: <code>SAID AND PARTNERS GRUP ( масло)</code>):",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.message(SettingsStates.waiting_append_alias, F.chat.type == "private")
async def process_append_alias(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message, ("admin",)):
        return
    data = await state.get_data()
    sup_id = data.get("supplier_id")
    alias = (message.text or "").strip()
    if not alias or not sup_id:
        await message.answer("⚠️ Nom bo'sh bo'lmasligi kerak.")
        return

    async with async_session_maker() as db:
        sup = await append_supplier_alias(db, sup_id, alias)
    await state.clear()
    if sup:
        await message.answer(
            f"✅ Sinonim qo'shildi! <b>{html.escape(sup.display_name)}</b> -> <code>{html.escape(sup.aliases)}</code>",
            parse_mode="HTML",
            reply_markup=main_menu_keyboard(),
        )
    else:
        await message.answer("⚠️ Ta'minotchi topilmadi.", reply_markup=main_menu_keyboard())


@router.callback_query(F.data.startswith("sup:del:"))
async def cb_supplier_delete_prompt(cb: CallbackQuery) -> None:
    """2-step delete confirmation for SupplierConfig (T4)."""
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    sup_id = int(cb.data.split(":")[-1])
    await _safe_edit(
        cb.message,
        "⚠️ Ushbu ta'minotchini ro'yxatdan o'chirasizmi?",
        reply_markup=delete_confirm_kb(f"sup:del_yes:{sup_id}", f"sup:view:{sup_id}"),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("sup:del_yes:"))
async def cb_supplier_delete(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    sup_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        await delete_supplier(db, sup_id)
        suppliers = await list_suppliers(db, active_only=True)
    await cb.answer("🗑 O'chirildi")
    await _safe_edit(
        cb.message,
        "🏢 <b>Ta'minotchilar ro'yxati:</b>",
        reply_markup=suppliers_list_kb(suppliers),
    )


@router.callback_query(F.data == "sup:add")
async def cb_supplier_add_start(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    await state.set_state(SettingsStates.waiting_supplier_name)
    await cb.message.answer(
        "➕ Yangi ta'minotchi nomini yozing (masalan: <code>HOCHLAND</code>):",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.message(SettingsStates.waiting_supplier_name, F.chat.type == "private")
async def process_new_supplier_name(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message, ("admin",)):
        return
    name = (message.text or "").strip()
    if not name:
        await message.answer("⚠️ Nom kiriting.")
        return
    await state.update_data(new_supplier_name=name)
    await state.set_state(SettingsStates.waiting_supplier_category)
    await message.answer(
        "Toifani yozing:\n"
        "<code>qarz</code> — ITOG Qarz bo'limida alohida chiqadi\n"
        "<code>karta</code> — ITOG Karta qatoriga tushadi",
        parse_mode="HTML",
    )


@router.message(SettingsStates.waiting_supplier_category, F.chat.type == "private")
async def process_new_supplier_category(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message, ("admin",)):
        return
    cat = (message.text or "").strip().lower()
    if cat not in ("qarz", "karta"):
        cat = "qarz"
    data = await state.get_data()
    name = data["new_supplier_name"]
    async with async_session_maker() as db:
        sup = await add_or_update_supplier(db, display_name=name, default_category=cat)
    await state.clear()
    await message.answer(
        f"✅ Ta'minotchi qo'shildi: <b>{html.escape(sup.display_name)}</b> ({sup.default_category})",
        parse_mode="HTML",
        reply_markup=main_menu_keyboard(),
    )


# ---------------------------------------------------------------------------
# History, Search (Y4), and Excel Export (E1, E6, E7)
# ---------------------------------------------------------------------------


@router.callback_query(F.data == "set:history")
async def cb_history_list(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb):
        return
    async with async_session_maker() as db:
        sessions = await list_all_sessions(db, limit=12)
    if not sessions:
        await cb.answer("Hozircha kunlik tarix yo'q.", show_alert=True)
        return
    await _safe_edit(
        cb.message,
        "📜 <b>Pul oldi-berdi va Nakladnoylar History (Arxiv):</b>\n"
        "Kunni tanlang, ro'yxatni oching yoki qidiring:",
        reply_markup=history_sessions_kb(sessions),
    )
    await cb.answer()


@router.callback_query(F.data == "hist:search")
async def cb_history_search_prompt(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb):
        return
    await state.set_state(SettingsStates.waiting_history_search)
    await cb.message.answer(
        "🔍 <b>Qidirish</b>\n"
        "Postavshik nomi yoki sanani yozing (masalan: <code>Nafis</code>, <code>2026-11-20</code> yoki <code>20.11.2026</code>):",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.message(SettingsStates.waiting_history_search, F.chat.type == "private")
async def process_history_search(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message):
        return
    q = (message.text or "").strip()
    if not q:
        await message.answer("⚠️ Qidiruv so'zini kiriting:")
        return
    async with async_session_maker() as db:
        matches = await search_nakladnoys(db, q, limit=20)
    await state.clear()
    if not matches:
        await message.answer(
            f"📭 <code>{html.escape(q)}</code> bo'yicha nakladnoy topilmadi.",
            parse_mode="HTML",
            reply_markup=main_menu_keyboard(),
        )
        return

    lines = [f"🔍 <b>Qidiruv natijasi: «{html.escape(q)}»</b> ({len(matches)} ta)\n"]
    photo_items: list[tuple[int, str]] = []
    total = 0.0
    for idx, (pay, r_date) in enumerate(matches, start=1):
        where = "📤" if pay.group_message_id else "💾"
        tm = format_local_dt(pay.created_at, "%H:%M") if pay.created_at else ""
        lines.append(
            f"{idx}) <code>{r_date} {tm}</code> {where} <b>{html.escape(pay.supplier_name)}</b> — "
            f"<b>{format_uzs(pay.amount)}</b> so'm"
        )
        total += float(pay.amount)
        if pay.photo_file_id:
            photo_items.append((pay.id, pay.supplier_name))
    lines.append(f"\n💰 Jami: <b>{format_uzs(total)} so'm</b>")
    await message.answer(
        "\n".join(lines)[:4000],
        parse_mode="HTML",
        reply_markup=history_feed_kb("all_nak", 0, False, photo_items=photo_items),
    )
    await message.answer("👇 Menyu:", reply_markup=main_menu_keyboard())


@router.callback_query(F.data.startswith("hist:view:"))
async def cb_history_detail(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb):
        return
    sess_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        summary = await compute_session_summary(db, sess_id)

    sess: DailyCashSession = summary.session
    is_closed = sess.status == "closed"
    lines = [
        f"📜 <b>KUNLIK HISTORY — {sess.report_date}</b> ({'Yopilgan' if is_closed else '🟢 Ochiq'})",
        "===============================",
        f"⏮ Boshlang'ich qoldiq: <b>{format_uzs(summary.opening_balance)}</b>",
        f"➕ Olingan pul: <b>{format_uzs(summary.main_cash_in)}</b>",
    ]
    if getattr(summary, "main_return_today", 0.0) > 0:
        lines.append(f"↩️ Pul oldimdan qaytarilgan: <b>-{format_uzs(summary.main_return_today)}</b>")
    if summary.kassa_debt_today > 0:
        lines.append(f"🏦 Kassadan qarz: <b>{format_uzs(summary.kassa_debt_today)}</b>")
    if summary.kassa_repay_today > 0:
        lines.append(f"↩️ Kassaga qaytarilgan: <b>-{format_uzs(summary.kassa_repay_today)}</b>")
    if summary.expense_today > 0:
        lines.append(f"💸 Xarajatlar: <b>-{format_uzs(summary.expense_today)}</b>")
    lines.append(f"💵 Jami kirim: <b>{format_uzs(summary.total_available_inflow)}</b>")
    lines.append(f"➖ Jami rasxod ({len(summary.confirmed_nakladnoys)} ta): <b>{format_uzs(summary.total_nakladnoy_spent)}</b>")
    lines.append(f"💰 Qolishi kerak: <b>{format_uzs(summary.expected_cash)}</b>")

    if is_closed:
        counted = sess.actual_counted_cash or 0
        diff = sess.difference or 0
        diff_str = "✅ To'g'ri (0)" if abs(diff) < 1 else (f"⚠️ Kamomad: {format_uzs(diff)}" if diff < 0 else f"➕ Ortiqcha: +{format_uzs(diff)}")
        lines.append(f"🖐 Sanalgan pul: <b>{format_uzs(counted)}</b>")
        lines.append(f"📊 Farq: <b>{diff_str}</b>")

    if summary.cash_transactions:
        lines.append("\n💵 <b>Pul oldi-berdi:</b>")
        t_icons = {
            "main": "➕",
            "main_return": "↩️",
            "kassa_debt": "🏦",
            "kassa_repay": "↩️",
            "expense": "💸",
        }
        for tx in summary.cash_transactions[:15]:
            tm = format_local_dt(tx.created_at, "%H:%M")
            note_part = f" ({html.escape(tx.note[:28])})" if tx.note else ""
            lines.append(f"• <code>{tm}</code> {t_icons.get(tx.source_type, '💵')} <b>{format_uzs(tx.amount)}</b>{note_part}")

    if summary.confirmed_nakladnoys:
        lines.append("\n📸 <b>Nakladnoylar:</b>")
        for idx, n in enumerate(summary.confirmed_nakladnoys[:25], start=1):
            tm = format_local_dt(n.created_at, "%H:%M")
            where = "📤" if n.group_message_id else "💾"
            lines.append(
                f"{idx}) <code>{tm}</code> {where} {html.escape(n.supplier_name)} — <b>{format_uzs(n.amount)}</b>"
            )
        if len(summary.confirmed_nakladnoys) > 25:
            lines.append(f"<i>...yana {len(summary.confirmed_nakladnoys) - 25} ta (to'liq ro'yxat Excel'da)</i>")

    text = "\n".join(lines)
    if len(text) > 3900:
        text = text[:3850] + "\n<i>...(to'liq ro'yxat Excel yuklashda)</i>"

    await _safe_edit(
        cb.message,
        text,
        reply_markup=history_detail_kb(
            sess_id, is_closed=is_closed, is_admin=is_admin_role(cb.from_user.id)
        ),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("hist:all_nak:"))
async def cb_history_all_nakladnoys(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb):
        return
    page = int(cb.data.split(":")[-1])
    page_size = 15
    async with async_session_maker() as db:
        items = await list_recent_nakladnoys(db, limit=page_size + 1, offset=page * page_size)
    has_next = len(items) > page_size
    items = items[:page_size]
    if not items and page == 0:
        await cb.answer("Hali tasdiqlangan nakladnoylar yo'q.", show_alert=True)
        return

    lines = [f"📸 <b>Nakladnoylar Tarixi (Sahifa {page + 1})</b>\n"]
    photo_items: list[tuple[int, str]] = []
    for idx, n in enumerate(items, start=page * page_size + 1):
        dt_str = format_local_dt(n.created_at, "%d.%m %H:%M")
        where = "📤" if n.group_message_id else "💾"
        lines.append(
            f"{idx}) <code>{dt_str}</code> {where} <b>{html.escape(n.supplier_name)}</b> — {format_uzs(n.amount)} so'm"
        )
        if n.photo_file_id:
            photo_items.append((n.id, n.supplier_name))
    lines.append("\n<i>📤 = Guruhga yuborilgan | 💾 = Faqat bazada</i>")
    await _safe_edit(
        cb.message,
        "\n".join(lines),
        reply_markup=history_feed_kb("all_nak", page, has_next, photo_items=photo_items),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("hist:all_cash:"))
async def cb_history_all_cash(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb):
        return
    page = int(cb.data.split(":")[-1])
    page_size = 15
    async with async_session_maker() as db:
        items = await list_recent_cash_transactions(db, limit=page_size + 1, offset=page * page_size)
    has_next = len(items) > page_size
    items = items[:page_size]
    if not items and page == 0:
        await cb.answer("Hali pul oldi-berdi yozuvlari yo'q.", show_alert=True)
        return

    labels = {
        "main": "➕ Pul oldim",
        "main_return": "↩️ Pul oldim qaytarildi",
        "kassa_debt": "🏦 Kassadan qarz",
        "kassa_repay": "↩️ Kassaga qaytarildi",
        "expense": "💸 Xarajat",
    }
    lines = [f"💵 <b>Pul Oldi-Berdi Tarixi (Sahifa {page + 1})</b>\n"]
    for idx, tx in enumerate(items, start=page * page_size + 1):
        dt_str = format_local_dt(tx.created_at, "%d.%m %H:%M")
        lbl = labels.get(tx.source_type, tx.source_type)
        note_part = f" — <i>{html.escape(tx.note[:30])}</i>" if tx.note else ""
        lines.append(
            f"{idx}) <code>{dt_str}</code> {lbl}: <b>{format_uzs(tx.amount)}</b>{note_part}"
        )
    await _safe_edit(
        cb.message,
        "\n".join(lines),
        reply_markup=history_feed_kb("all_cash", page, has_next),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("hist:reopen:"))
async def cb_history_reopen(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb, ("admin",)):
        return
    sess_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        sess = await reopen_cash_session(db, sess_id)
    if not sess:
        await cb.answer("Topilmadi", show_alert=True)
        return
    await _safe_edit(
        cb.message,
        f"🔓 <b>{sess.report_date}</b> kuni qayta ochildi!\n"
        "Endi <b>✏️ Tahrirlash</b> orqali to'g'irlashingiz va <b>🏁 Kunni yakunlash</b> orqali qayta yopishingiz mumkin.",
    )
    await cb.answer("Qayta ochildi")


@router.callback_query(F.data == "set:prixod_history")
async def cb_prixod_history(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb):
        return
    async with async_session_maker() as db:
        reports = await list_prixod_reports(db, limit=10)
    if not reports:
        await cb.answer("Hozircha saqlangan ITOG hisobotlar yo'q.", show_alert=True)
        return
    await _safe_edit(
        cb.message,
        "👑 <b>Saqlangan Prixod (ITOG) hisobotlari:</b>",
        reply_markup=prixod_history_kb(reports),
    )
    await cb.answer()


async def _send_private_excel(
    bot, chat_id: int, user_id: int, is_private: bool, data: bytes, filename: str
) -> None:
    """Deliver Excel strictly to private chat (E7)."""
    target = chat_id if is_private else user_id
    await bot.send_document(
        target,
        BufferedInputFile(data, filename=filename),
        caption=f"📥 Tayyor Excel hisobot: <code>{filename}</code>",
        parse_mode="HTML",
    )


def _parse_date_token(token: str) -> Optional[str]:
    t = token.strip()
    m_dmy = re.fullmatch(r"(\d{2})\.(\d{2})\.(\d{4})", t)
    if m_dmy:
        iso = f"{m_dmy.group(3)}-{m_dmy.group(2)}-{m_dmy.group(1)}"
    elif re.fullmatch(r"\d{4}-\d{2}-\d{2}", t):
        iso = t
    else:
        return None
    try:
        datetime.strptime(iso, "%Y-%m-%d")
        return iso
    except ValueError:
        return None


@router.callback_query(F.data == "export:menu")
async def cb_export_menu(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb):
        return
    await _safe_edit(
        cb.message,
        "📥 <b>Excel hisobot davrini tanlang:</b>\n"
        "<i>(Fayl shaxsiy chatingizga yuboriladi)</i>",
        reply_markup=export_range_kb(),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("export:range:"))
async def cb_export_range(cb: CallbackQuery, state: FSMContext) -> None:
    if await deny_if_unauthorized(cb):
        return
    kind = cb.data.split(":")[-1]
    today = now_local().date()
    if kind == "custom":
        await state.set_state(WalletStates.waiting_excel_date_range)
        await cb.message.answer(
            "📆 Sana oralig'ini yozing:\n"
            "Masalan: <code>01.11.2026 - 20.11.2026</code> yoki <code>2026-11-01 2026-11-20</code>",
            parse_mode="HTML",
            reply_markup=cancel_reply_keyboard(),
        )
        await cb.answer()
        return

    if kind == "today":
        await cb.answer("⏳ Excel tayyorlanmoqda...")
        async with async_session_maker() as db:
            summary = await compute_session_summary(db)
        data = await asyncio.to_thread(build_session_excel, summary)
        fname = f"Hisob_{summary.session.report_date}.xlsx"
    else:
        if kind == "week":
            d_from = (today - timedelta(days=6)).strftime("%Y-%m-%d")
            d_to = today.strftime("%Y-%m-%d")
        elif kind == "month":
            d_from = today.replace(day=1).strftime("%Y-%m-%d")
            d_to = today.strftime("%Y-%m-%d")
        elif kind == "prev_month":
            prev_end = today.replace(day=1) - timedelta(days=1)
            d_from = prev_end.replace(day=1).strftime("%Y-%m-%d")
            d_to = prev_end.strftime("%Y-%m-%d")
        else:
            await cb.answer("Noma'lum davr")
            return
        async with async_session_maker() as db:
            range_data = await get_range_report_data(db, d_from, d_to)
        if not range_data["sessions"] and not range_data["nakladnoys"]:
            await cb.answer(f"{d_from} — {d_to} oralig'ida ma'lumot yo'q.", show_alert=True)
            return
        await cb.answer("⏳ Excel tayyorlanmoqda...")
        data = await asyncio.to_thread(build_range_excel, d_from, d_to, range_data)
        fname = f"Hisob_{d_from}_{d_to}.xlsx"

    await _send_private_excel(
        cb.bot,
        cb.message.chat.id,
        cb.from_user.id,
        cb.message.chat.type == "private",
        data,
        fname,
    )


@router.message(WalletStates.waiting_excel_date_range, F.chat.type == "private")
async def process_custom_excel_range(message: Message, state: FSMContext) -> None:
    if await deny_if_unauthorized(message):
        return
    raw = (message.text or "").strip()
    tokens = [p for p in re.split(r"[\s,—–]+|(?<!\d)-|-(?!\d)", raw) if p]
    if len(tokens) == 1:
        d_from = _parse_date_token(tokens[0])
        d_to = d_from
    elif len(tokens) >= 2:
        d_from = _parse_date_token(tokens[0])
        d_to = _parse_date_token(tokens[1])
    else:
        d_from = d_to = None

    if not d_from or not d_to:
        await message.answer(
            "⚠️ Sana formati noto'g'ri. Misol: <code>01.11.2026 20.11.2026</code>:",
            parse_mode="HTML",
        )
        return
    if d_from > d_to:
        d_from, d_to = d_to, d_from

    async with async_session_maker() as db:
        range_data = await get_range_report_data(db, d_from, d_to)
    await state.clear()
    if not range_data["sessions"] and not range_data["nakladnoys"]:
        await message.answer(
            f"📭 {d_from} — {d_to} oralig'ida ma'lumot yo'q.",
            reply_markup=main_menu_keyboard(),
        )
        return
    fname = f"Hisob_{d_from}_{d_to}.xlsx"
    excel_bytes = await asyncio.to_thread(build_range_excel, d_from, d_to, range_data)
    await message.answer_document(
        BufferedInputFile(excel_bytes, filename=fname),
        caption=f"📥 Tayyor Excel hisobot: <code>{fname}</code>",
        parse_mode="HTML",
        reply_markup=main_menu_keyboard(),
    )


@router.callback_query(F.data.startswith("export:"))
async def cb_export_excel(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb):
        return
    parts = cb.data.split(":")
    kind = parts[1]
    async with async_session_maker() as db:
        if kind == "session":
            await cb.answer("⏳ Excel tayyorlanmoqda...")
            sess_id = int(parts[2])
            summary = await compute_session_summary(db, sess_id)
            data = await asyncio.to_thread(build_session_excel, summary)
            filename = f"Hisob_{summary.session.report_date}.xlsx"
        elif kind == "history":
            sessions = await list_closed_sessions(db, limit=60)
            if not sessions:
                await cb.answer("Eksport uchun yopilgan kunlar yo'q.", show_alert=True)
                return
            await cb.answer("⏳ Excel tayyorlanmoqda...")
            data = await asyncio.to_thread(build_history_excel, sessions)
            filename = "Kunlik_Hisob_Tarix.xlsx"
        elif kind == "prixod":
            rep_id = int(parts[2])
            report = await get_prixod_report(db, rep_id)
            if not report:
                await cb.answer("Hisobot topilmadi.", show_alert=True)
                return
            await cb.answer("⏳ Excel tayyorlanmoqda...")
            data = await asyncio.to_thread(build_prixod_excel, report)
            filename = f"Prixod_{report.report_date}.xlsx"
        else:
            await cb.answer("Noma'lum eksport turi")
            return

    await _send_private_excel(
        cb.bot,
        cb.message.chat.id,
        cb.from_user.id,
        cb.message.chat.type == "private",
        data,
        filename,
    )
