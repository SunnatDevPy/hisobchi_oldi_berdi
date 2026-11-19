"""Settings, group binding, supplier configuration, history, and Excel export handlers."""

from __future__ import annotations

import asyncio
import html
import time

from aiogram import F, Router
from aiogram.filters import Command, CommandObject, CommandStart
from aiogram.fsm.context import FSMContext
from aiogram.types import BufferedInputFile, CallbackQuery, ChatMemberUpdated, Message

from bot.keyboards import (
    BTN_SETTINGS,
    cancel_reply_keyboard,
    groups_config_kb,
    history_detail_kb,
    history_sessions_kb,
    main_menu_keyboard,
    prixod_history_kb,
    quick_bind_group_kb,
    settings_menu_kb,
    supplier_detail_kb,
    suppliers_list_kb,
)
from bot.states import SettingsStates
from config import get_settings
from database.crud import (
    add_or_update_supplier,
    append_supplier_alias,
    compute_session_summary,
    delete_supplier,
    get_all_group_configs,
    get_prixod_report,
    list_closed_sessions,
    list_prixod_reports,
    list_suppliers,
    reopen_cash_session,
    set_group_config,
)
from database.models import DailyCashSession
from database.session import async_session_maker
from services.excel_export import (
    build_history_excel,
    build_prixod_excel,
    build_session_excel,
)
from services.gemini_ai import format_uzs


router = Router(name="settings_groups")

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


def is_authorized(user_id: int | None) -> bool:
    """Check if Telegram user is permitted when ADMIN_IDS is configured."""
    admins = get_settings().admin_id_list
    if not admins:
        return True
    return user_id in admins


@router.message(CommandStart(), F.chat.type == "private")
async def cmd_start(message: Message, state: FSMContext) -> None:
    """Handle /start in private chat."""
    if not is_authorized(message.from_user.id if message.from_user else None):
        await message.answer("⛔ Sizda ushbu botdan foydalanish huquqi yo'q.")
        return
    await state.clear()
    uid = message.from_user.id if message.from_user else 0
    await message.answer(
        "👋 <b>Assalomu alaykum! Hisobot va Nakladnoy nazorat botiga xush kelibsiz.</b>\n\n"
        "Botda quyidagilarni bajarishingiz mumkin:\n"
        "• 📸 <b>Nakladnoy rasmi</b> tashlash (Gemini AI avtomatik o'qiydi va guruhga yuboradi)\n"
        "• ➕ <b>Pul olish / Kassadan qarz</b> yozish (ovozda, matnda yoki tugmada)\n"
        "• ✏️ <b>Tasdiqlanganlarni tahrirlash</b> (guruhdagi xabar ham avtomat yangilanadi)\n"
        "• 🏁 <b>Kunni yakunlash</b> (qo'ldagi pulni sanab sverka qilish va ertangi kunga o'tkazish)\n"
        "• 👑 <b>Prixod (ITOG)</b> — YesPOS Excel/CSV fayldan 1 soniyada hisobot tayyorlash\n\n"
        f"🆔 Sizning Telegram ID: <code>{uid}</code>",
        parse_mode="HTML",
        reply_markup=main_menu_keyboard(),
    )


@router.message(F.text == "❌ Bekor qilish", F.chat.type == "private")
async def cancel_any_state(message: Message, state: FSMContext) -> None:
    """Cancel current FSM operation and return to main menu."""
    if not is_authorized(message.from_user.id if message.from_user else None):
        return
    await state.clear()
    await message.answer("❌ Amal bekor qilindi.", reply_markup=main_menu_keyboard())


# ---------------------------------------------------------------------------
# Group Binding Commands (work inside Telegram Groups!)
# ---------------------------------------------------------------------------


async def _bind_group_command(message: Message, role: str) -> None:
    if not is_authorized(message.from_user.id if message.from_user else None):
        return
    if message.chat.type == "private":
        await message.answer(
            f"ℹ️ <b>{ROLE_TITLES[role]}</b> ni ulash uchun botni kerakli Telegram guruhiga qo'shing "
            f"va o'sha guruh ichida <code>/set_{role}_group</code> buyrug'ini yuboring.\n\n"
            "Yoki <b>⚙️ Sozlamalar & History -> 🔗 Guruhlarni sozlash</b> orqali guruh ID sini kiriting.",
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
    if not is_authorized(user_id):
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

    if user_id:
        try:
            status_text = await _render_groups_status()
            username = await get_bot_username(message.bot)
            await message.bot.send_message(
                chat_id=user_id,
                text=(
                    f"✅ <b>{html.escape(title)}</b> guruhi avtomatik "
                    f"<b>{ROLE_TITLES[role]}</b> sifatida bazaga saqlandi! (<code>{message.chat.id}</code>)\n\n"
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
    if not is_authorized(user_id) or not user_id:
        return

    # Allow startgroup deep-link handler to complete first if both updates arrive together
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
    await cb.message.edit_text(
        f"✅ <b>{html.escape(title)}</b> (<code>{chat_id}</code>) — "
        f"<b>{ROLE_TITLES.get(role, role)}</b> sifatida saqlandi!\n\n{status_text}",
        parse_mode="HTML",
        reply_markup=groups_config_kb(username),
    )
    await cb.answer("✅ Guruh saqlandi!")


# ---------------------------------------------------------------------------
# Settings & History Menu
# ---------------------------------------------------------------------------


@router.message(F.text == BTN_SETTINGS, F.chat.type == "private")
async def open_settings_menu(message: Message, state: FSMContext) -> None:
    if not is_authorized(message.from_user.id if message.from_user else None):
        return
    await state.clear()
    await message.answer(
        "⚙️ <b>Sozlamalar va Arxiv (History)</b>\nKerakli bo'limni tanlang:",
        parse_mode="HTML",
        reply_markup=settings_menu_kb(),
    )


@router.callback_query(F.data == "set:back")
async def cb_settings_back(cb: CallbackQuery, state: FSMContext) -> None:
    await state.clear()
    await cb.message.edit_text(
        "⚙️ <b>Sozlamalar va Arxiv (History)</b>\nKerakli bo'limni tanlang:",
        parse_mode="HTML",
        reply_markup=settings_menu_kb(),
    )
    await cb.answer()


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
        "\n💡 <b>1 bosishda oson ulash:</b> Pastdagi <b>«➕ ... guruhiga qo'shish (Admin)»</b> "
        "tugmasini bosing — Telegram guruh tanlash va admin qilish oynasini ochadi, "
        "bot esa guruh ID sini avtomatik bazaga saqlab oladi!"
    )
    return "\n".join(lines)


@router.callback_query(F.data == "set:groups")
async def cb_groups_menu(cb: CallbackQuery) -> None:
    text = await _render_groups_status()
    username = await get_bot_username(cb.bot)
    await cb.message.edit_text(text, parse_mode="HTML", reply_markup=groups_config_kb(username))
    await cb.answer()


@router.callback_query(F.data.startswith("grp:set_id:"))
async def cb_group_set_id_prompt(cb: CallbackQuery, state: FSMContext) -> None:
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
    if not is_authorized(message.from_user.id if message.from_user else None):
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
    async with async_session_maker() as db:
        suppliers = await list_suppliers(db, active_only=True)
    await cb.message.edit_text(
        "🏢 <b>Ta'minotchilar ro'yxati (ITOG Qarz & Karta):</b>\n"
        "YesPOS dagi nomlarni bog'lash yoki yangi ta'minotchi qo'shish uchun tanlang:",
        parse_mode="HTML",
        reply_markup=suppliers_list_kb(suppliers),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("sup:view:"))
async def cb_supplier_detail(cb: CallbackQuery) -> None:
    sup_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        suppliers = await list_suppliers(db, active_only=False)
        sup = next((s for s in suppliers if s.id == sup_id), None)
    if not sup:
        await cb.answer("Topilmadi", show_alert=True)
        return
    await cb.message.edit_text(
        f"🏢 <b>{html.escape(sup.display_name)}</b>\n"
        f"📌 Toifa: <b>{sup.default_category.upper()}</b>\n"
        f"🔗 YesPOS nomlari (sinonimlar):\n<code>{html.escape(sup.aliases or 'yoq')}</code>",
        parse_mode="HTML",
        reply_markup=supplier_detail_kb(sup.id),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("sup:alias:"))
async def cb_supplier_alias_prompt(cb: CallbackQuery, state: FSMContext) -> None:
    sup_id = int(cb.data.split(":")[-1])
    await state.set_state(SettingsStates.waiting_append_alias)
    await state.update_data(supplier_id=sup_id)
    await cb.message.answer(
        "🔗 YesPOS jadvalidagi aynan nomini yozib yuboring\n"
        "(masalan: <code>SAID AND PARTNERS GRUP ( масло)</code>):",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.message(SettingsStates.waiting_append_alias, F.chat.type == "private")
async def process_append_alias(message: Message, state: FSMContext) -> None:
    if not is_authorized(message.from_user.id if message.from_user else None):
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
async def cb_supplier_delete(cb: CallbackQuery) -> None:
    sup_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        await delete_supplier(db, sup_id)
        suppliers = await list_suppliers(db, active_only=True)
    await cb.answer("🗑 O'chirildi")
    await cb.message.edit_text(
        "🏢 <b>Ta'minotchilar ro'yxati:</b>",
        parse_mode="HTML",
        reply_markup=suppliers_list_kb(suppliers),
    )


@router.callback_query(F.data == "sup:add")
async def cb_supplier_add_start(cb: CallbackQuery, state: FSMContext) -> None:
    await state.set_state(SettingsStates.waiting_supplier_name)
    await cb.message.answer(
        "➕ Yangi ta'minotchi nomini yozing (ITOG hisobotida qanday ko'rinsin):\n"
        "Masalan: <code>HOCHLAND</code>",
        parse_mode="HTML",
        reply_markup=cancel_reply_keyboard(),
    )
    await cb.answer()


@router.message(SettingsStates.waiting_supplier_name, F.chat.type == "private")
async def process_new_supplier_name(message: Message, state: FSMContext) -> None:
    if not is_authorized(message.from_user.id if message.from_user else None):
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
    if not is_authorized(message.from_user.id if message.from_user else None):
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
# History & Excel Export
# ---------------------------------------------------------------------------


@router.callback_query(F.data == "set:history")
async def cb_history_list(cb: CallbackQuery) -> None:
    async with async_session_maker() as db:
        sessions = await list_closed_sessions(db, limit=10)
    if not sessions:
        await cb.answer("Hozircha yopilgan kunlar tarixi yo'q.", show_alert=True)
        return
    await cb.message.edit_text(
        "📜 <b>Yopilgan kunlar arxivi (History):</b>\nBatafsil ko'rish yoki to'g'irlash uchun tanlang:",
        parse_mode="HTML",
        reply_markup=history_sessions_kb(sessions),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("hist:view:"))
async def cb_history_detail(cb: CallbackQuery) -> None:
    sess_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        summary = await compute_session_summary(db, sess_id)

    sess: DailyCashSession = summary.session
    counted = sess.actual_counted_cash or 0
    diff = sess.difference or 0
    diff_str = "✅ To'g'ri (0)" if abs(diff) < 1 else (f"⚠️ Kamomad: {format_uzs(diff)}" if diff < 0 else f"➕ Ortiqcha: +{format_uzs(diff)}")

    lines = [
        f"📜 <b>KUNLIK ARXIV — {sess.report_date}</b>",
        "===============================",
        f"⏮ Boshlang'ich qoldiq: <b>{format_uzs(summary.opening_balance)}</b>",
        f"➕ Olingan pul: <b>{format_uzs(summary.main_cash_in)}</b>",
        f"🏦 Kassadan qarz: <b>{format_uzs(summary.kassa_debt_today)}</b>",
        f"💵 Jami kirim: <b>{format_uzs(summary.total_available_inflow)}</b>",
        f"➖ Jami rasxod ({len(summary.confirmed_nakladnoys)} ta): <b>{format_uzs(summary.total_nakladnoy_spent)}</b>",
        f"💰 Qolishi kerak edi: <b>{format_uzs(summary.expected_cash)}</b>",
        f"🖐 Sanalgan pul: <b>{format_uzs(counted)}</b>",
        f"📊 Farq: <b>{diff_str}</b>",
    ]
    await cb.message.edit_text(
        "\n".join(lines),
        parse_mode="HTML",
        reply_markup=history_detail_kb(sess_id),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("hist:reopen:"))
async def cb_history_reopen(cb: CallbackQuery) -> None:
    sess_id = int(cb.data.split(":")[-1])
    async with async_session_maker() as db:
        sess = await reopen_cash_session(db, sess_id)
    if not sess:
        await cb.answer("Topilmadi", show_alert=True)
        return
    await cb.message.edit_text(
        f"🔓 <b>{sess.report_date}</b> kuni qayta ochildi!\n"
        "Endi <b>✏️ Tahrirlash</b> tugmasi orqali nakladnoy yoki pullarni to'g'irlashingiz va "
        "<b>🏁 Kunni yakunlash</b> orqali qayta yopishingiz mumkin.",
        parse_mode="HTML",
    )
    await cb.answer("Qayta ochildi")


@router.callback_query(F.data == "set:prixod_history")
async def cb_prixod_history(cb: CallbackQuery) -> None:
    async with async_session_maker() as db:
        reports = await list_prixod_reports(db, limit=10)
    if not reports:
        await cb.answer("Hozircha saqlangan ITOG hisobotlar yo'q.", show_alert=True)
        return
    await cb.message.edit_text(
        "👑 <b>Saqlangan Prixod (ITOG) hisobotlari:</b>",
        parse_mode="HTML",
        reply_markup=prixod_history_kb(reports),
    )
    await cb.answer()


@router.callback_query(F.data.startswith("export:"))
async def cb_export_excel(cb: CallbackQuery) -> None:
    parts = cb.data.split(":")
    kind = parts[1]
    async with async_session_maker() as db:
        if kind == "session":
            sess_id = int(parts[2])
            summary = await compute_session_summary(db, sess_id)
            data = build_session_excel(summary)
            filename = f"Hisob_{summary.session.report_date}.xlsx"
        elif kind == "history":
            sessions = await list_closed_sessions(db, limit=60)
            if not sessions:
                await cb.answer("Eksport uchun yopilgan kunlar yo'q.", show_alert=True)
                return
            data = build_history_excel(sessions)
            filename = "Kunlik_Hisob_Tarix.xlsx"
        elif kind == "prixod":
            rep_id = int(parts[2])
            report = await get_prixod_report(db, rep_id)
            if not report:
                await cb.answer("Hisobot topilmadi.", show_alert=True)
                return
            data = build_prixod_excel(report)
            filename = f"Prixod_{report.report_date}.xlsx"
        else:
            await cb.answer("Noma'lum eksport turi")
            return

    await cb.message.answer_document(
        BufferedInputFile(data, filename=filename),
        caption=f"📥 Tayyor Excel hisobot: <code>{filename}</code>",
        parse_mode="HTML",
    )
    await cb.answer("Excel tayyor!")
