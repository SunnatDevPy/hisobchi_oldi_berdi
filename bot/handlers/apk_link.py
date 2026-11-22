"""Telegram bot /apk command for generating 8-digit mobile APK login codes and managing devices."""

from __future__ import annotations

import html
import logging
from typing import Optional

from aiogram import F, Router
from aiogram.filters import Command
from aiogram.types import (
    CallbackQuery,
    FSInputFile,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    Message,
)

from pathlib import Path

from api.auth import (
    create_login_code,
    format_login_code_display,
    list_active_tokens,
    revoke_token_by_id,
)

APK_BINARY_PATH = Path("data/hisobchi.apk")
from bot.auth import ROLE_LABELS, deny_if_unauthorized, get_user_role, is_admin_role
from bot.handlers.wallet_nakladnoy import _safe_cb_answer, _safe_edit_text
from config import get_settings
from database.crud import format_local_dt, get_app_setting, get_group_config, set_app_setting
from database.session import async_session_maker


router = Router(name="apk_link")
logger = logging.getLogger("hisobot_bot.apk_link")


def _apk_panel_kb(post_to_group_on: bool, device_count: int, is_admin: bool) -> InlineKeyboardMarkup:
    grp_label = (
        "📤 Guruhga yuborish: ✅ Yoqilgan"
        if post_to_group_on
        else "📤 Guruhga yuborish: 🔕 O'chirilgan"
    )
    pub_url = (get_settings().API_PUBLIC_URL or "https://hisobchi.okaposai.uz").strip().rstrip("/")
    rows: list[list[InlineKeyboardButton]] = [
        [
            InlineKeyboardButton(
                text="📥 APK ilovani yuklab olish (Telegramda)",
                callback_data="apk:download_file",
            )
        ],
    ]
    if pub_url.startswith("https://") or pub_url.startswith("http://"):
        rows.append(
            [
                InlineKeyboardButton(
                    text="🌐 Brauzerdan yuklab olish (Tezkor)",
                    url=f"{pub_url}/download/hisobchi.apk",
                )
            ]
        )
    rows.extend(
        [
            [InlineKeyboardButton(text="🔑 Yangi kod olish", callback_data="apk:new_code")],
            [
                InlineKeyboardButton(
                    text=f"📱 Ulangan qurilmalar ({device_count})",
                    callback_data="apk:devices",
                )
            ],
        ]
    )
    if is_admin:
        rows.append([InlineKeyboardButton(text=grp_label, callback_data="apk:toggle_grp")])
        rows.append(
            [InlineKeyboardButton(text="🔗 Nakladnoy guruhini sozlash", callback_data="set:groups")]
        )
    return InlineKeyboardMarkup(inline_keyboard=rows)


async def _render_apk_home(user_id: int, code: Optional[str] = None) -> tuple[str, InlineKeyboardMarkup]:
    role = get_user_role(user_id) or "viewer"
    is_adm = is_admin_role(user_id)
    async with async_session_maker() as db:
        grp = await get_group_config(db, "nakladnoy")
        apk_toggle = await get_app_setting(db, "apk_post_to_group", "on")
        tokens = await list_active_tokens(db, user_id=None if is_adm else user_id)

    post_on = (apk_toggle or "on").strip().lower() != "off"
    if grp and grp.chat_id:
        grp_line = f"✅ <b>{html.escape(grp.title or str(grp.chat_id))}</b> (<code>{grp.chat_id}</code>)"
    else:
        grp_line = "⚠️ <i>Bog'lanmagan (Guruhda /set_nakladnoy_group yuboring)</i>"

    pub_url = (get_settings().API_PUBLIC_URL or "").strip()
    url_hint = (
        f"\n🌐 Server manzili: <code>{html.escape(pub_url)}</code>"
        if pub_url
        else ""
    )

    if code is None:
        code = create_login_code(user_id)
    disp_code = format_login_code_display(code)

    text = (
        "📱 <b>Hisobchi Mobil Ilova (APK) ulash</b>\n"
        "===============================\n"
        f"🔑 Bir martalik kirish kodi (5 daqiqa amal qiladi):\n\n"
        f"👉  <code>{code}</code>   <i>({disp_code})</i>\n"
        f"{url_hint}\n"
        "===============================\n"
        f"👤 Sizning rolingiz: <b>{ROLE_LABELS.get(role, role)}</b>\n"
        f"👥 Nakladnoy guruhi: {grp_line}\n"
        f"📤 APK dan guruhga yuborish: <b>{'✅ Yoqilgan' if post_on else '🔕 O`chirilgan'}</b>\n"
        f"📲 Ulangan qurilmalar: <b>{len(tokens)} ta</b>\n\n"
        "<i>Ilovada 8 xonali kodni kiriting. Kod faqat 1 marta ishlaydi.</i>"
    )
    return text, _apk_panel_kb(post_on, len(tokens), is_adm)


@router.message(Command("apk"), F.chat.type == "private")
async def cmd_apk(message: Message) -> None:
    """Handle /apk command to issue an 8-digit one-time mobile login code."""
    if await deny_if_unauthorized(message):
        return
    uid = message.from_user.id if message.from_user else 0
    text, kb = await _render_apk_home(uid)
    await message.answer(text, parse_mode="HTML", reply_markup=kb)


@router.callback_query(F.data == "apk:home")
async def cb_apk_home(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb):
        return
    uid = cb.from_user.id if cb.from_user else 0
    await _safe_cb_answer(cb)
    text, kb = await _render_apk_home(uid)
    if cb.message:
        await _safe_edit_text(cb.message, text, reply_markup=kb)


@router.callback_query(F.data == "apk:new_code")
async def cb_apk_new_code(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb):
        return
    uid = cb.from_user.id if cb.from_user else 0
    code = create_login_code(uid)
    await _safe_cb_answer(cb, f"🔑 Yangi kod: {format_login_code_display(code)}")
    text, kb = await _render_apk_home(uid, code=code)
    if cb.message:
        await _safe_edit_text(cb.message, text, reply_markup=kb)


@router.callback_query(F.data == "apk:download_file")
async def cb_apk_download_file(cb: CallbackQuery) -> None:
    """Send Hisobchi.apk directly in Telegram chat (with cached file_id for instant delivery)."""
    if await deny_if_unauthorized(cb):
        return
    pub_url = (get_settings().API_PUBLIC_URL or "https://hisobchi.okaposai.uz").strip().rstrip("/")
    dl_link = f"{pub_url}/download/hisobchi.apk"
    if not APK_BINARY_PATH.is_file():
        await _safe_cb_answer(cb, "APK fayli yuklanmoqda...", show_alert=False)
        if cb.message:
            await cb.message.answer(
                f"📥 <b>Hisobchi APK yuklab olish:</b>\n👉 <a href=\"{html.escape(dl_link)}\">{html.escape(dl_link)}</a>",
                parse_mode="HTML",
            )
        return

    await _safe_cb_answer(cb, "📥 APK yuborilmoqda...")
    stat = APK_BINARY_PATH.stat()
    sig = f"{stat.st_size}:{int(stat.st_mtime)}"

    async with async_session_maker() as db:
        cached_sig = await get_app_setting(db, "apk_tg_file_sig", "")
        cached_fid = await get_app_setting(db, "apk_tg_file_id", "")

    uid = cb.from_user.id if cb.from_user else 0
    code = create_login_code(uid)
    caption = (
        "📱 <b>Hisobchi Mobil Ilovasi (Android APK)</b>\n\n"
        f"🌐 Server: <code>{html.escape(pub_url)}</code>\n"
        f"🔑 Kirish kodi (5 daqiqa): <code>{code}</code>\n\n"
        "<i>Faylni yuklab olib telefoningizga o'rnating va yuqoridagi 8 xonali kodni kiriting.</i>"
    )

    if cb.message:
        try:
            if cached_fid and cached_sig == sig:
                await cb.message.answer_document(
                    document=cached_fid,
                    caption=caption,
                    parse_mode="HTML",
                )
                return
        except Exception:
            pass

        try:
            wait_msg = await cb.message.answer("⏳ <i>APK fayli Telegramga yuklanmoqda (10-15 soniya)...</i>", parse_mode="HTML")
            sent = await cb.message.answer_document(
                document=FSInputFile(APK_BINARY_PATH, filename="Hisobchi.apk"),
                caption=caption,
                parse_mode="HTML",
            )
            try:
                await wait_msg.delete()
            except Exception:
                pass
            if sent.document and sent.document.file_id:
                async with async_session_maker() as db:
                    await set_app_setting(db, "apk_tg_file_sig", sig)
                    await set_app_setting(db, "apk_tg_file_id", sent.document.file_id)
        except Exception as exc:
            logger.warning("Failed to send APK document via Telegram: %s", exc)
            await cb.message.answer(
                f"📥 <b>Hisobchi APK to'g'ridan-to'g'ri yuklab olish havolasi:</b>\n"
                f"👉 <a href=\"{html.escape(dl_link)}\">{html.escape(dl_link)}</a>\n\n"
                f"🔑 Kirish kodi: <code>{code}</code>",
                parse_mode="HTML",
            )


@router.callback_query(F.data == "apk:toggle_grp")
async def cb_apk_toggle_grp(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb):
        return
    uid = cb.from_user.id if cb.from_user else 0
    if not is_admin_role(uid):
        await _safe_cb_answer(cb, "🔒 Faqat admin o'zgartira oladi", show_alert=True)
        return
    async with async_session_maker() as db:
        cur = await get_app_setting(db, "apk_post_to_group", "on")
        new_val = "off" if (cur or "on").strip().lower() != "off" else "on"
        await set_app_setting(db, "apk_post_to_group", new_val)

    await _safe_cb_answer(
        cb,
        "📤 APK guruhga yuborish yoqildi" if new_val == "on" else "🔕 APK guruhga yuborish o'chirildi",
    )
    text, kb = await _render_apk_home(uid)
    if cb.message:
        await _safe_edit_text(cb.message, text, reply_markup=kb)


async def _render_devices_view(uid: int) -> tuple[str, InlineKeyboardMarkup]:
    is_adm = is_admin_role(uid)
    async with async_session_maker() as db:
        tokens = await list_active_tokens(db, user_id=None if is_adm else uid)

    lines = [
        "📱 <b>Ulangan mobil qurilmalar (APK)</b>",
        "===============================",
    ]
    rows: list[list[InlineKeyboardButton]] = []
    if not tokens:
        lines.append("<i>Hozircha ulangan faol qurilmalar yo'q.</i>")
    else:
        for idx, t in enumerate(tokens, start=1):
            last_dt = format_local_dt(t.last_used_at, "%d.%m %H:%M")
            dev = html.escape(t.device_name or "Android")
            lines.append(
                f"{idx}. 📲 <b>{dev}</b> — ID: <code>{t.user_id}</code> (oxirgi: {last_dt})"
            )
            rows.append(
                [
                    InlineKeyboardButton(
                        text=f"❌ Uzish: {t.device_name[:22]} (#{t.id})",
                        callback_data=f"apk:revoke:{t.id}",
                    )
                ]
            )
    rows.append([InlineKeyboardButton(text="⬅️ Orqaga (/apk)", callback_data="apk:home")])
    return "\n".join(lines), InlineKeyboardMarkup(inline_keyboard=rows)


@router.callback_query(F.data == "apk:devices")
async def cb_apk_devices(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb):
        return
    uid = cb.from_user.id if cb.from_user else 0
    await _safe_cb_answer(cb)
    text, kb = await _render_devices_view(uid)
    if cb.message:
        await _safe_edit_text(cb.message, text, reply_markup=kb)


@router.callback_query(F.data.startswith("apk:revoke:"))
async def cb_apk_revoke(cb: CallbackQuery) -> None:
    if await deny_if_unauthorized(cb):
        return
    uid = cb.from_user.id if cb.from_user else 0
    is_adm = is_admin_role(uid)
    token_id_str = (cb.data or "").split(":")[-1]
    if not token_id_str.isdigit():
        await _safe_cb_answer(cb, "Xato ID", show_alert=True)
        return
    async with async_session_maker() as db:
        ok = await revoke_token_by_id(db, int(token_id_str), actor_user_id=uid, is_admin=is_adm)
    await _safe_cb_answer(
        cb,
        "✅ Qurilma uzildi!" if ok else "⚠️ Qurilma topilmadi",
    )
    text, kb = await _render_devices_view(uid)
    if cb.message:
        await _safe_edit_text(cb.message, text, reply_markup=kb)
