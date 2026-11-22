"""Comprehensive automated tests for Hisobot Bot."""

from __future__ import annotations

import asyncio
from pathlib import Path

from sqlalchemy.ext.asyncio import AsyncSession

from database.crud import (
    add_cash_transaction,
    close_cash_session,
    compute_session_summary,
    confirm_nakladnoy,
    create_pending_nakladnoy,
    delete_nakladnoy,
    get_group_config,
    get_or_create_open_session,
    list_suppliers,
    reopen_cash_session,
    save_prixod_report,
    set_group_config,
    set_nakladnoy_group_message,
    update_nakladnoy,
)
from database.session import create_engine_and_session, init_db
from services.excel_export import build_history_excel, build_prixod_excel, build_session_excel
from services.gemini_ai import format_uzs, parse_uzbek_amount, parse_voice_or_text
from services.prixod_parser import parse_manual_itog_text, parse_yespos_table


USER_YESPOS_CSV = """,,,,,,,,,
,Документы о приемке товара,,,,,,,,
,Период 18.11.2026 - 18.11.2026,,,,,,,,
,,,,,,,,,
,№,Статус,Дата создания,Автор,Примечание,Поставщик,Филиал,Стоимость,Цена
,1,Выполненный,2026-11-18 22:25:34,Sunnatilla Yoqubov,,QASSOB,IFTIQOR 80,18985900,19552400
,2,Выполненный,2026-11-18 20:44:25,Sunnatilla Yoqubov,,S4 dan kelgan mahsulot,IFTIQOR 80,382130,413440
,3,Выполненный,2026-11-18 20:40:48,Sunnatilla Yoqubov,,ISMAT AKA KEPAK NON,IFTIQOR 80,325000,425000
,4,Выполненный,2026-11-18 20:06:24,Sunnatilla Yoqubov,,Mirsaid aka shokolad,IFTIQOR 80,350000,385000
,5,Выполненный,2026-11-18 18:58:55,Olimjon Mansurov,,Non Oka,IFTIQOR 80,1657000,1955000
,6,Выполненный,2026-11-18 17:43:33,Olimjon Mansurov,,NAFIS,IFTIQOR 80,450000,525000
,7,Выполненный,2026-11-18 16:29:59,Olimjon Mansurov,,ASADBEK (норин),IFTIQOR 80,1307350,1485625
,8,Выполненный,2026-11-18 16:24:38,Olimjon Mansurov,,BALIQ RM MART,IFTIQOR 80,8700000,9600000
,9,Выполненный,2026-11-18 15:55:04,Olimjon Mansurov,,NAFIS,IFTIQOR 80,208000,240000
,10,Выполненный,2026-11-18 15:54:35,Olimjon Mansurov,,PORT DE KALLEH,IFTIQOR 80,932000,1140000
,11,Выполненный,2026-11-18 15:50:53,Olimjon Mansurov,,LURPAK (сут махсулотлари),IFTIQOR 80,1735100,2350000
,12,Выполненный,2026-11-18 15:49:35,Olimjon Mansurov,,OMBOR,IFTIQOR 80,2109750,2910000
,13,Выполненный,2026-11-18 15:04:08,Sunnatilla Yoqubov,,OMBOR,IFTIQOR 80,12895000,15466500
,14,Выполненный,2026-11-18 14:14:13,Olimjon Mansurov,,NIGORA OPA  (тухум),IFTIQOR 80,330000,440000
,15,Выполненный,2026-11-18 14:13:11,Olimjon Mansurov,,TRAYFEL,IFTIQOR 80,180000,230000
,16,Выполненный,2026-11-18 13:55:49,Olimjon Mansurov,,ACTIVE,IFTIQOR 80,378400,540000
,17,Выполненный,2026-11-18 13:53:19,Olimjon Mansurov,,UMMUN SOMSA,IFTIQOR 80,3030000,3935000
,18,Выполненный,2026-11-18 12:51:54,Olimjon Mansurov,,DILSHOD (товук),IFTIQOR 80,935000,1124000
,19,Выполненный,2026-11-18 12:43:27,Olimjon Mansurov,16.11.2026,HOCHLAND,IFTIQOR 80,409400,491000
,20,Выполненный,2026-11-18 12:40:59,Olimjon Mansurov,,SAID AND PARTNERS GRUP ( масло),IFTIQOR 80,11560732,13313300
,21,Выполненный,2026-11-18 12:39:28,Olimjon Mansurov,,RUSTAM SIR,IFTIQOR 80,420000,480000
,22,Выполненный,2026-11-18 12:05:20,Olimjon Mansurov,,NAFIS,IFTIQOR 80,1500000,1630000
,23,Выполненный,2026-11-18 12:04:16,Olimjon Mansurov,,NIGORA OPA  (тухум),IFTIQOR 80,175000,280000
,24,Выполненный,2026-11-18 12:03:45,Olimjon Mansurov,,IBRAGIMOV NARIMON,IFTIQOR 80,406000,522000
,25,Выполненный,2026-11-18 11:13:43,Olimjon Mansurov,,JUVA TRADE (майонез),IFTIQOR 80,298290,378000
,26,Выполненный,2026-11-18 11:09:56,Olimjon Mansurov,,MOLOCHNIY KRAY,IFTIQOR 80,560000,800000
,27,Выполненный,2026-11-18 08:31:56,Olimjon Mansurov,,By Malika,IFTIQOR 80,525000,575000
,28,Выполненный,2026-11-18 08:07:37,Olimjon Mansurov,,IZZAT BARAKA (нон),IFTIQOR 80,148300,186000
,29,Выполненный,2026-11-18 08:05:44,Olimjon Mansurov,,PUREMILKY ,IFTIQOR 80,161899.98,198000
,Жами,,,,,,,,
"""


async def _run_with_db(tmp_path: Path, fn) -> None:
    """Run an async coroutine with a fresh isolated SQLite database."""
    db_file = tmp_path / "test_hisobot.db"
    eng, maker = create_engine_and_session(f"sqlite+aiosqlite:///{db_file.as_posix()}")
    try:
        await init_db(engine_override=eng, session_maker_override=maker)
        async with maker() as session:
            await fn(session)
    finally:
        await eng.dispose()


def test_parse_uzbek_amounts():
    assert parse_uzbek_amount("21 000 000") == 21_000_000
    assert parse_uzbek_amount("12 895 000 + 2 109 750") == 15_004_750
    assert parse_uzbek_amount("21 million so'm") == 21_000_000
    assert parse_uzbek_amount("1.5 mln") == 1_500_000
    assert parse_uzbek_amount("450 ming") == 450_000
    assert parse_uzbek_amount("30 mln") == 30_000_000
    assert format_uzs(71_055_251.98) == "71 055 252"


def test_yespos_csv_itog_exact_match(tmp_path: Path):
    async def scenario(db_session: AsyncSession) -> None:
        suppliers = await list_suppliers(db_session)
        result = parse_yespos_table(
            USER_YESPOS_CSV.encode("utf-8"),
            "prixod_18_11.csv",
            suppliers,
        )

        assert result.report_date == "18.11.26"
        assert len(result.rows) == 29
        assert round(result.total_cost) == 71_055_252
        assert round(result.total_price) == 81_570_265

        text = result.formatted_text
        assert "ITOG 👑18.11.26" in text
        assert "1) OMBOR 12 895 000 + 2 109 750" in text
        assert "2) QASSOB  18 985 900" in text
        assert "3) FOZIL MARINAD (шашлик)" in text
        assert "4) ASADBEK (норин) 1 307 350" in text
        assert "5) Alisa Pereches: 11 560 732" in text
        assert "Nakladnoy 23 262 120" in text
        assert "karta: 525 000" in text
        assert "16.11: 409 400" in text
        assert "Umumiy 71 055 252" in text

        saved = await save_prixod_report(
            db_session,
            report_date=result.report_date,
            total_cost=result.total_cost,
            total_price=result.total_price,
            formatted_text=result.formatted_text,
            rows_data=[
                {
                    "row_num": r.row_num,
                    "supplier_raw": r.supplier_raw,
                    "supplier_display": r.supplier_display,
                    "note_raw": r.note_raw,
                    "cost": r.cost,
                    "price": r.price,
                    "category": r.category,
                    "old_date_label": r.old_date_label,
                    "created_at_str": r.created_at_str,
                }
                for r in result.rows
            ],
        )
        xlsx_bytes = build_prixod_excel(saved)
        assert len(xlsx_bytes) > 1000

    asyncio.run(_run_with_db(tmp_path, scenario))


def test_manual_itog_text_parsing(tmp_path: Path):
    async def scenario(db_session: AsyncSession) -> None:
        suppliers = await list_suppliers(db_session)
        manual = """
        ITOG 👑18.11.26
        ===============================
        Qarz
        1) OMBOR 12 895 000 + 2 109 750
        2) QASSOB  18 985 900
        3) FOZIL MARINAD (шашлик)
        4) ASADBEK (норин) 1 307 350
        5) Alisa Pereches: 11 560 732
        ===============================
        Nakladnoy 23 263 000
        karta: 525 000
        16.11: 409 400
        """
        parsed = parse_manual_itog_text(manual, suppliers)
        assert parsed.report_date == "18.11.26"
        assert round(parsed.total_cost) == 71_056_132
        assert "1) OMBOR 12 895 000 + 2 109 750" in parsed.formatted_text
        assert "karta: 525 000" in parsed.formatted_text
        assert "16.11: 409 400" in parsed.formatted_text

    asyncio.run(_run_with_db(tmp_path, scenario))


def test_wallet_lifecycle_edit_confirmed_and_carry_over(tmp_path: Path):
    async def scenario(db_session: AsyncSession) -> None:
        # 1. Bind groups
        await set_group_config(db_session, "nakladnoy", -100111, "Nakladnoy Guruh")
        await set_group_config(db_session, "prixod", -100222, "Prixod Guruh")
        await set_group_config(db_session, "kassa", -100333, "Kassa Guruh")
        assert (await get_group_config(db_session, "nakladnoy")).chat_id == -100111

        # 2. Day 1 starts with 0 opening balance; take 21,000,000 main + 3,000,000 kassa debt
        sess1 = await get_or_create_open_session(db_session, report_date="2026-11-18")
        assert sess1.opening_balance == 0.0

        await add_cash_transaction(
            db_session, 21_000_000, source_type="main", note="Pul oldim 21 mln", session_id=sess1.id
        )
        await add_cash_transaction(
            db_session, 3_000_000, source_type="kassa_debt", note="Kassadan", session_id=sess1.id
        )

        # 3. Add two nakladnoy payments, confirm them and attach group message IDs
        n1 = await create_pending_nakladnoy(
            db_session, "Non Oka", 1_657_000, photo_file_id="file_1", session_id=sess1.id
        )
        n2 = await create_pending_nakladnoy(
            db_session, "QASSOB", 18_985_900, photo_file_id="file_2", session_id=sess1.id
        )
        await confirm_nakladnoy(db_session, n1.id, group_chat_id=-100111, group_message_id=501)
        await confirm_nakladnoy(db_session, n2.id, group_chat_id=-100111, group_message_id=502)

        summary = await compute_session_summary(db_session, sess1.id)
        assert summary.total_available_inflow == 24_000_000
        assert summary.total_nakladnoy_spent == 20_642_900
        assert summary.expected_cash == 3_357_100
        assert summary.total_kassa_debt_outstanding == 3_000_000

        # 4. Edit an ALREADY CONFIRMED nakladnoy (e.g. Non Oka was actually 1,857,000 -> +200,000)
        updated_n1 = await update_nakladnoy(db_session, n1.id, amount=1_857_000)
        assert updated_n1.group_message_id == 501
        summary_after_edit = await compute_session_summary(db_session, sess1.id)
        assert summary_after_edit.expected_cash == 3_157_100

        # 5. Delete a confirmed nakladnoy
        n3 = await create_pending_nakladnoy(db_session, "Temp", 500_000, session_id=sess1.id)
        await confirm_nakladnoy(db_session, n3.id)
        await set_nakladnoy_group_message(db_session, n3.id, -100111, 503)
        await delete_nakladnoy(db_session, n3.id)

        summary_before_close = await compute_session_summary(db_session, sess1.id)
        assert summary_before_close.expected_cash == 3_157_100

        # Close with discrepancy, verify Excel exports, reopen, fix, and re-close with 0 diff
        closed1 = await close_cash_session(db_session, sess1.id, actual_counted_cash=1_500_000)
        assert closed1.session.difference == 1_500_000 - 3_157_100
        assert len(build_session_excel(closed1)) > 1000
        assert len(build_history_excel([closed1.session])) > 1000

        await reopen_cash_session(db_session, sess1.id)
        n4 = await create_pending_nakladnoy(db_session, "BALIQ", 1_657_100, session_id=sess1.id)
        await confirm_nakladnoy(db_session, n4.id)
        closed1_fixed = await close_cash_session(db_session, sess1.id, actual_counted_cash=1_500_000)
        assert closed1_fixed.session.difference == 0.0

        # 6. Day 2 starts automatically with 1,500,000 opening balance and 0 nakladnoys!
        sess2 = await get_or_create_open_session(db_session, report_date="2026-11-19")
        assert sess2.id != sess1.id
        assert sess2.opening_balance == 1_500_000

        await add_cash_transaction(db_session, 30_000_000, source_type="main", session_id=sess2.id)
        summary2 = await compute_session_summary(db_session, sess2.id)
        assert len(summary2.confirmed_nakladnoys) == 0
        assert summary2.expected_cash == 31_500_000

    asyncio.run(_run_with_db(tmp_path, scenario))


def test_heuristic_text_intents():
    async def scenario() -> None:
        res1 = await parse_voice_or_text(text="Pul oldim 21 000 000")
        assert res1["intent"] == "cash_in"
        assert res1["amount"] == 21_000_000

        res2 = await parse_voice_or_text(text="Kassadan 3 million oldim")
        assert res2["intent"] == "kassa_debt"
        assert res2["amount"] == 3_000_000

        res3 = await parse_voice_or_text(text="Kassaga 3 mln qaytardim")
        assert res3["intent"] == "kassa_repay"
        assert res3["amount"] == 3_000_000

        res4 = await parse_voice_or_text(text="Status")
        assert res4["intent"] == "status"

        res5 = await parse_voice_or_text(text="Marimalako ga 820 000 berdim")
        assert res5["intent"] == "pay_supplier"
        assert res5["supplier_name"] == "Marimalako"
        assert res5["amount"] == 820_000

    asyncio.run(scenario())


def test_group_admin_deeplinks_and_quick_bind_kb():
    from bot.keyboards import GROUP_ADMIN_RIGHTS, groups_config_kb, quick_bind_group_kb

    kb = groups_config_kb("hisobchi_my_bot")
    urls = [row[0].url for row in kb.inline_keyboard[:3]]
    assert urls[0] == f"https://t.me/hisobchi_my_bot?startgroup=bind_nakladnoy&admin={GROUP_ADMIN_RIGHTS}"
    assert urls[1] == f"https://t.me/hisobchi_my_bot?startgroup=bind_prixod&admin={GROUP_ADMIN_RIGHTS}"
    assert urls[2] == f"https://t.me/hisobchi_my_bot?startgroup=bind_kassa&admin={GROUP_ADMIN_RIGHTS}"

    qkb = quick_bind_group_kb(-100999)
    cbs = [row[0].callback_data for row in qkb.inline_keyboard]
    assert cbs == [
        "grp:qbind:nakladnoy:-100999",
        "grp:qbind:prixod:-100999",
        "grp:qbind:kassa:-100999",
    ]


def test_utc_to_tashkent_local_formatting():
    from datetime import datetime, timezone
    from database.crud import format_local_dt

    utc_dt = datetime(2026, 11, 19, 6, 29, tzinfo=timezone.utc)
    assert format_local_dt(utc_dt, "%d.%m.%Y %H:%M") == "19.11.2026 11:29"

    naive_utc_dt = datetime(2026, 11, 19, 6, 29)
    assert format_local_dt(naive_utc_dt, "%d.%m.%Y %H:%M") == "19.11.2026 11:29"


def test_nakladnoy_confirm_keyboard_has_skip_group_button():
    from bot.keyboards import auto_confirmed_nakladnoy_kb, nakladnoy_confirm_kb

    kb = nakladnoy_confirm_kb(42)
    callbacks = [btn.callback_data for row in kb.inline_keyboard for btn in row]
    assert "nak:confirm:42" in callbacks
    assert "nak:save_only:42" in callbacks

    akb = auto_confirmed_nakladnoy_kb(42, sent_to_group=True)
    acbs = [btn.callback_data for row in akb.inline_keyboard for btn in row]
    assert "nak:unpost_group:42" in acbs
    assert "nak:delete_conf:42" in acbs


def test_nakladnoy_amount_rounding_and_app_settings(tmp_path: Path):
    from database.crud import get_app_setting, round_nakladnoy_amount, set_app_setting

    assert round_nakladnoy_amount(192_620, "floor_1000") == 192_000
    assert round_nakladnoy_amount(192_000, "floor_1000") == 192_000
    assert round_nakladnoy_amount(192_620, "nearest_1000") == 193_000
    assert round_nakladnoy_amount(192_620, "none") == 192_620

    async def scenario(db_session: AsyncSession) -> None:
        from bot.handlers.wallet_nakladnoy import render_status_text
        from database.crud import (
            get_kassa_debt_stats,
            list_all_sessions,
            list_recent_cash_transactions,
            list_recent_nakladnoys,
        )

        assert await get_app_setting(db_session, "auto_confirm", "on") == "on"
        await set_app_setting(db_session, "auto_confirm", "off")
        assert await get_app_setting(db_session, "auto_confirm", "on") == "off"

        sess = await get_or_create_open_session(db_session, report_date="2026-11-19")
        await add_cash_transaction(db_session, 1_000_000, source_type="main", note="Test", session_id=sess.id)
        await add_cash_transaction(db_session, 500_000, source_type="kassa_debt", note="Kassa", session_id=sess.id)
        await add_cash_transaction(db_session, 200_000, source_type="kassa_repay", note="Qaytar", session_id=sess.id)
        p = await create_pending_nakladnoy(db_session, "Nafis", 330_000, session_id=sess.id)
        await confirm_nakladnoy(db_session, p.id)

        assert len(await list_all_sessions(db_session)) == 1
        assert len(await list_recent_nakladnoys(db_session)) == 1
        assert len(await list_recent_cash_transactions(db_session)) == 3

        kstats = await get_kassa_debt_stats(db_session)
        assert kstats["total_borrowed"] == 500_000
        assert kstats["total_repaid"] == 200_000
        assert kstats["outstanding"] == 300_000

        summary = await compute_session_summary(db_session, sess.id)
        st_text = render_status_text(summary)
        assert "Kassadan olingan:" in st_text
        assert "Kassaga berilgan (qaytarilgan):" in st_text
        assert "Statistika:" in st_text
        assert "Nafis" in st_text
        assert "(" in st_text  # timestamp at end of payment row

    asyncio.run(_run_with_db(tmp_path, scenario))


def test_database_fsm_storage_persistence(tmp_path: Path):
    from aiogram.fsm.storage.base import StorageKey
    from bot.storage import DatabaseFSMStorage
    from bot.states import WalletStates

    db_file = tmp_path / "fsm_test.db"
    eng, maker = create_engine_and_session(f"sqlite+aiosqlite:///{db_file.as_posix()}")

    async def scenario() -> None:
        await init_db(engine_override=eng, session_maker_override=maker)
        key = StorageKey(bot_id=1, chat_id=100, user_id=100)
        s1 = DatabaseFSMStorage(maker)
        await s1.set_state(key, WalletStates.waiting_cash_in_amount)
        await s1.set_data(key, {"supplier": "Nafis", "step": 2})

        # Simulate process restart with a brand new storage instance
        s2 = DatabaseFSMStorage(maker)
        assert await s2.get_state(key) == WalletStates.waiting_cash_in_amount.state
        assert await s2.get_data(key) == {"supplier": "Nafis", "step": 2}

    try:
        asyncio.run(scenario())
    finally:
        asyncio.run(eng.dispose())


def test_role_auth_fail_closed_and_roles(tmp_path: Path, monkeypatch):
    from bot.auth import (
        ROLE_ADMIN,
        ROLE_KASSIR,
        ROLE_VIEWER,
        can_write_role,
        clear_role_cache,
        get_user_role,
        is_admin_role,
        is_authorized,
        refresh_role_cache,
    )
    from config import get_settings
    from database.crud import delete_user_role, set_user_role

    monkeypatch.setenv("ADMIN_IDS", "")
    get_settings.cache_clear()
    clear_role_cache()

    async def scenario(db_session: AsyncSession) -> None:
        # Fail-closed when ADMIN_IDS is empty and DB roles empty
        assert is_authorized(999999) is False
        assert get_user_role(999999) is None

        await set_user_role(db_session, 1001, ROLE_KASSIR, "Ali")
        await set_user_role(db_session, 1002, ROLE_VIEWER, "Vali")
        await refresh_role_cache(db_session)

        assert is_authorized(1001) is True
        assert can_write_role(1001) is True
        assert is_admin_role(1001) is False

        assert is_authorized(1002) is True
        assert can_write_role(1002) is False
        assert is_admin_role(1002) is False

        assert await delete_user_role(db_session, 1002) is True
        await refresh_role_cache(db_session)
        assert is_authorized(1002) is False

    try:
        asyncio.run(_run_with_db(tmp_path, scenario))
    finally:
        clear_role_cache()
        get_settings.cache_clear()


def test_text_never_calls_gemini_and_parses_without_verb(monkeypatch):
    import services.gemini_ai as ai_mod

    async def _boom(*args, **kwargs):
        raise AssertionError("Gemini AI must never be called for text messages")

    monkeypatch.setattr(ai_mod, "_call_gemini", _boom)

    async def scenario() -> None:
        r1 = await parse_voice_or_text(text="pure milky 354 000")
        assert r1["intent"] == "pay_supplier"
        assert r1["supplier_name"] == "pure milky"
        assert r1["amount"] == 354_000

        r2 = await parse_voice_or_text(text="Nafis 1.5 mln")
        assert r2["intent"] == "pay_supplier"
        assert r2["supplier_name"] == "Nafis"
        assert r2["amount"] == 1_500_000

        r3 = await parse_voice_or_text(text="450k")
        assert r3["intent"] == "number_only"
        assert r3["amount"] == 450_000

        r4 = await parse_voice_or_text(text="Salom qalesiz")
        assert r4["intent"] == "unknown"

    asyncio.run(scenario())


def test_image_resize_dedup_and_ai_usage_counter(tmp_path: Path):
    import io
    from PIL import Image
    from database.crud import find_nakladnoy_by_photo_unique_id, get_ai_usage_stats, record_ai_usage
    from services.gemini_ai import compress_image_for_ocr

    img = Image.new("RGB", (2600, 1800), color=(240, 240, 240))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=95)
    resized, mime = compress_image_for_ocr(buf.getvalue(), max_side=1280)
    assert mime == "image/jpeg"
    with Image.open(io.BytesIO(resized)) as out_im:
        assert max(out_im.size) == 1280

    async def scenario(db_session: AsyncSession) -> None:
        sess = await get_or_create_open_session(db_session, report_date="2026-11-20")
        p = await create_pending_nakladnoy(
            db_session,
            "Nafis",
            330_000,
            photo_file_id="f1",
            photo_unique_id="uniq_img_123",
            original_amount=330_620,
            session_id=sess.id,
        )
        await confirm_nakladnoy(db_session, p.id)
        found = await find_nakladnoy_by_photo_unique_id(db_session, "uniq_img_123")
        assert found is not None and found.id == p.id

        await record_ai_usage(db_session, "photo", "gemini-flash-lite-latest", 300, 40, 340, usage_date="2026-11-20")
        await record_ai_usage(db_session, "cache_hit", "cache", 0, 0, 0, usage_date="2026-11-20")
        stats = await get_ai_usage_stats(db_session, date_iso="2026-11-20")
        assert stats["calls"] == 1
        assert stats["cache_hits"] == 1
        assert stats["total_tokens"] == 340

    asyncio.run(_run_with_db(tmp_path, scenario))


def test_navigation_router_overrides_active_fsm_state(tmp_path: Path, monkeypatch):
    from datetime import datetime, timezone
    from unittest.mock import AsyncMock
    from aiogram import Bot, Dispatcher
    from aiogram.fsm.storage.base import StorageKey
    from aiogram.types import Chat, Message, Update, User
    from bot.auth import clear_role_cache
    from bot.handlers import get_main_router
    from bot.keyboards import BTN_STATUS
    from bot.states import WalletStates
    from bot.storage import DatabaseFSMStorage
    from config import get_settings

    monkeypatch.setenv("ADMIN_IDS", "555111")
    get_settings.cache_clear()
    clear_role_cache()

    db_file = tmp_path / "nav_test.db"
    eng, maker = create_engine_and_session(f"sqlite+aiosqlite:///{db_file.as_posix()}")

    async def scenario() -> None:
        import bot.handlers.wallet_nakladnoy as wn
        import bot.handlers.navigation as nav
        from database.session import init_db as _init

        await _init(engine_override=eng, session_maker_override=maker)
        monkeypatch.setattr(wn, "async_session_maker", maker)

        storage = DatabaseFSMStorage(maker)
        dp = Dispatcher(storage=storage)
        dp.include_router(get_main_router())

        key = StorageKey(bot_id=123, chat_id=555111, user_id=555111)
        await storage.set_state(key, WalletStates.waiting_cash_in_amount)

        called = {"status": False, "cancel": False}
        orig_status = wn.handle_status_button

        async def spy_status(msg, state, actor_id=None):
            called["status"] = True
            await state.clear()

        monkeypatch.setattr(nav, "handle_status_button", spy_status)

        bot = AsyncMock(spec=Bot)
        bot.id = 123
        user = User(id=555111, is_bot=False, first_name="Admin")
        chat = Chat(id=555111, type="private")
        msg = Message(message_id=10, date=datetime.now(timezone.utc), chat=chat, from_user=user, text=BTN_STATUS)
        await dp.feed_update(bot, Update(update_id=1, message=msg))

        assert called["status"] is True
        assert await storage.get_state(key) is None

        # Verify "❌ Bekor qilish" also clears active state without getting swallowed
        await storage.set_state(key, WalletStates.waiting_cash_in_amount)
        monkeypatch.setattr(Message, "answer", AsyncMock())
        cancel_msg = Message(
            message_id=11, date=datetime.now(timezone.utc), chat=chat, from_user=user, text="❌ Bekor qilish"
        )
        await dp.feed_update(bot, Update(update_id=2, message=cancel_msg))
        assert await storage.get_state(key) is None
        monkeypatch.setattr(nav, "handle_status_button", orig_status)

    try:
        asyncio.run(scenario())
    finally:
        asyncio.run(eng.dispose())


def test_supplier_normalization_fuzzy_and_recent_suggestions(tmp_path: Path):
    from database.crud import (
        get_recent_amounts_for_supplier,
        get_recent_suppliers,
        get_supplier_sverka,
        resolve_supplier_name,
    )

    async def scenario(db_session: AsyncSession) -> None:
        # Alias mapping from seed defaults
        canon, sug = await resolve_supplier_name(db_session, "SAID AND PARTNERS")
        assert canon == "Alisa Pereches" and sug is None

        sess = await get_or_create_open_session(db_session, report_date="2026-11-20")
        p1 = await create_pending_nakladnoy(db_session, "Nafis", 330_000, session_id=sess.id)
        p2 = await create_pending_nakladnoy(db_session, "Nafis", 450_000, session_id=sess.id)
        await confirm_nakladnoy(db_session, p1.id)
        await confirm_nakladnoy(db_session, p2.id)

        # Case normalization
        c2, s2 = await resolve_supplier_name(db_session, "nafis")
        assert c2 == "Nafis" and s2 is None

        # Fuzzy suggestion for close typo
        c3, s3 = await resolve_supplier_name(db_session, "Nafiss")
        assert c3 == "Nafiss" and s3 == "Nafis"

        recents = await get_recent_suppliers(db_session, 6)
        assert "Nafis" in recents
        amts = await get_recent_amounts_for_supplier(db_session, "nafis", 3)
        assert amts == [450_000.0, 330_000.0]

        sv = await get_supplier_sverka(db_session, "2026-11")
        assert len(sv) == 2

    asyncio.run(_run_with_db(tmp_path, scenario))


def test_supplier_debt_nasiya_and_statistics_and_search(tmp_path: Path):
    from database.crud import (
        add_supplier_debt,
        delete_supplier_debt,
        get_period_statistics,
        get_supplier_debt_balances,
        search_nakladnoys,
    )

    async def scenario(db_session: AsyncSession) -> None:
        sess = await get_or_create_open_session(db_session, report_date="2026-11-20")
        p1 = await create_pending_nakladnoy(db_session, "Non Oka", 1_000_000, session_id=sess.id)
        await confirm_nakladnoy(db_session, p1.id)

        found_name = await search_nakladnoys(db_session, "non")
        assert len(found_name) == 1
        found_date = await search_nakladnoys(db_session, "20.11.2026")
        assert len(found_date) == 1

        st = await get_period_statistics(db_session, "2026-11-01", "2026-11-30")
        assert st["total_spent"] == 1_000_000
        assert st["active_days"] == 1

        d1 = await add_supplier_debt(db_session, "OMBOR", "debt", 5_000_000, "Yog'")
        await add_supplier_debt(db_session, "ombor", "payment", 2_000_000, "Karta")
        d3 = await add_supplier_debt(db_session, "Nafis", "debt", 500_000)
        await delete_supplier_debt(db_session, d3.id)

        bals = await get_supplier_debt_balances(db_session)
        assert len(bals) == 1
        assert bals[0]["balance"] == 3_000_000
        assert d1.id > 0

    asyncio.run(_run_with_db(tmp_path, scenario))


def test_excel_xulosa_range_and_sverka_pivot_chart(tmp_path: Path):
    import io
    from openpyxl import load_workbook
    from database.crud import get_range_report_data, get_supplier_sverka
    from services.excel_export import build_range_excel, build_sverka_excel

    async def scenario(db_session: AsyncSession) -> None:
        sess = await get_or_create_open_session(db_session, report_date="2026-11-20")
        await add_cash_transaction(db_session, 2_000_000, source_type="main", session_id=sess.id)
        p = await create_pending_nakladnoy(
            db_session, "Nafis", 192_000, original_amount=192_640, photo_file_id="pf1", session_id=sess.id
        )
        await confirm_nakladnoy(db_session, p.id, group_chat_id=-100123456, group_message_id=77)
        summary = await compute_session_summary(db_session, sess.id)

        wb1 = load_workbook(io.BytesIO(build_session_excel(summary)))
        assert wb1.sheetnames == ["Xulosa", "Nakladnoylar", "Kirim va Qarzlar"]
        assert wb1["Nakladnoylar"].cell(4, 4).value == 192640
        assert wb1["Nakladnoylar"].cell(4, 5).value == "Ha"
        assert wb1["Nakladnoylar"].cell(4, 6).hyperlink.target == "https://t.me/c/123456/77"

        rdata = await get_range_report_data(db_session, "2026-11-01", "2026-11-30")
        wb2 = load_workbook(io.BytesIO(build_range_excel("2026-11-01", "2026-11-30", rdata)))
        assert wb2.sheetnames == ["Xulosa", "Nakladnoylar", "Kirim va Qarzlar", "Postavshiklar"]

        sv_rows = await get_supplier_sverka(db_session, "2026-11")
        wb3 = load_workbook(io.BytesIO(build_sverka_excel("2026-11", sv_rows)))
        assert wb3.sheetnames == ["Postavshiklar", "Kunlar x Postavshiklar", "Barcha to'lovlar"]
        assert len(wb3["Postavshiklar"]._charts) == 1

    asyncio.run(_run_with_db(tmp_path, scenario))


def test_backup_encryption_roundtrip():
    from services.backup import decrypt_backup_bytes, encrypt_backup_bytes

    plain = b"hisobot-backup-payload-123"
    enc = encrypt_backup_bytes(plain, "strong-parol-99")
    assert enc != plain
    assert decrypt_backup_bytes(enc, "strong-parol-99") == plain

    try:
        decrypt_backup_bytes(enc, "wrong-parol")
        raise AssertionError("Wrong password should raise InvalidToken")
    except Exception:
        pass


def test_idempotent_schema_upgrade_from_legacy_db(tmp_path: Path):
    import sqlite3
    from sqlalchemy import inspect

    db_file = tmp_path / "legacy.db"
    con = sqlite3.connect(db_file)
    con.executescript(
        """
        CREATE TABLE daily_cash_sessions (id INTEGER PRIMARY KEY, report_date VARCHAR(16), status VARCHAR(16), opening_balance FLOAT, actual_counted_cash FLOAT, expected_cash FLOAT, difference FLOAT, created_at DATETIME, closed_at DATETIME);
        CREATE TABLE nakladnoy_payments (id INTEGER PRIMARY KEY, session_id INTEGER, supplier_name VARCHAR(255), amount FLOAT, photo_file_id VARCHAR(512), note TEXT, status VARCHAR(16), group_chat_id BIGINT, group_message_id INTEGER, created_at DATETIME, updated_at DATETIME);
        CREATE TABLE audit_logs (id INTEGER PRIMARY KEY, action VARCHAR(32), entity VARCHAR(32), entity_id INTEGER, details TEXT, created_at DATETIME);
        INSERT INTO daily_cash_sessions VALUES (1, '2026-11-01', 'open', 0, NULL, 0, NULL, NULL, NULL);
        INSERT INTO nakladnoy_payments VALUES (1, 1, 'OMBOR', 500000, NULL, '', 'confirmed', NULL, NULL, NULL, NULL);
        """
    )
    con.close()

    eng, maker = create_engine_and_session(f"sqlite+aiosqlite:///{db_file.as_posix()}")

    async def scenario() -> None:
        await init_db(engine_override=eng, session_maker_override=maker)
        async with eng.connect() as conn:
            def _check(sync_conn):
                insp = inspect(sync_conn)
                nak_cols = {c["name"] for c in insp.get_columns("nakladnoy_payments")}
                audit_cols = {c["name"] for c in insp.get_columns("audit_logs")}
                tables = set(insp.get_table_names())
                return nak_cols, audit_cols, tables

            nak_cols, audit_cols, tables = await conn.run_sync(_check)
            assert "photo_unique_id" in nak_cols
            assert "original_amount" in nak_cols
            assert "user_id" in audit_cols
            assert {"fsm_states", "ai_usage_logs", "user_roles", "supplier_debts"}.issubset(tables)

    try:
        asyncio.run(scenario())
    finally:
        asyncio.run(eng.dispose())


def test_photo_caption_overrides_ocr_supplier_and_zero_token_shortcut(monkeypatch):
    from config import get_settings
    import services.gemini_ai as ai_mod

    monkeypatch.setenv("GEMINI_API_KEY", "test-key")
    get_settings.cache_clear()

    assert ai_mod.parse_photo_caption("Nafis") == ("Nafis", None)
    assert ai_mod.parse_photo_caption("Dilshod Tovuq") == ("Dilshod Tovuq", None)
    assert ai_mod.parse_photo_caption("S4 dan kelgan") == ("S4 dan kelgan", None)
    assert ai_mod.parse_photo_caption("500 000 Nafis") == ("Nafis", 500_000.0)
    assert ai_mod.parse_photo_caption("Nafis 330 000") == ("Nafis", 330_000.0)
    assert ai_mod.parse_photo_caption("330 000") == (None, 330_000.0)

    async def scenario() -> None:
        # 1. Caption supplier strictly overrides wrong/unclear OCR supplier and sets is_clear=True
        async def fake_gemini(parts, response_schema=None):
            return (
                {"supplier_name": "Wrong Co", "amount": 450000, "is_clear": False, "notes": ""},
                {"promptTokenCount": 10, "candidatesTokenCount": 5, "totalTokenCount": 15},
                "gemini-flash-lite-latest",
            )

        monkeypatch.setattr(ai_mod, "_call_gemini", fake_gemini)
        res1 = await ai_mod.extract_nakladnoy_from_image(b"img", caption="Nafis")
        assert res1["supplier_name"] == "Nafis"
        assert res1["amount"] == 450_000.0
        assert res1["is_clear"] is True

        # 2. Zero-token fast path when caption has both supplier and amount
        async def boom_gemini(*args, **kwargs):
            raise AssertionError("Gemini must not be called when caption provides both supplier and amount")

        monkeypatch.setattr(ai_mod, "_call_gemini", boom_gemini)
        res2 = await ai_mod.extract_nakladnoy_from_image(b"img", caption="Nafis 330 000")
        assert res2["supplier_name"] == "Nafis"
        assert res2["amount"] == 330_000.0
        assert res2["is_clear"] is True

    try:
        asyncio.run(scenario())
    finally:
        get_settings.cache_clear()


def test_nakladnoy_debt_and_mark_paid_same_day_and_next_day(tmp_path: Path):
    from bot.handlers.wallet_nakladnoy import render_nakladnoy_group_caption, render_status_text
    from bot.keyboards import auto_confirmed_nakladnoy_kb, nakladnoy_confirm_kb
    from database.crud import (
        list_unpaid_debt_nakladnoys,
        mark_nakladnoy_as_debt,
        mark_nakladnoy_as_paid,
    )

    assert any(
        "nak:save_debt:1" in (b.callback_data or "")
        for row in nakladnoy_confirm_kb(1).inline_keyboard
        for b in row
    )
    assert any(
        "nak:mark_debt:1" in (b.callback_data or "")
        for row in auto_confirmed_nakladnoy_kb(1, is_debt=False).inline_keyboard
        for b in row
    )
    assert any(
        "nak:mark_paid:1" in (b.callback_data or "")
        for row in auto_confirmed_nakladnoy_kb(1, is_debt=True).inline_keyboard
        for b in row
    )

    async def scenario(db_session: AsyncSession) -> None:
        sess1 = await get_or_create_open_session(db_session, report_date="2026-11-20")
        await add_cash_transaction(db_session, 10_000_000, source_type="main", session_id=sess1.id)

        p1 = await create_pending_nakladnoy(
            db_session, "Иброхимов В. Х.", 1_300_000, session_id=sess1.id
        )
        await confirm_nakladnoy(db_session, p1.id, group_chat_id=-1001, group_message_id=10)

        sum_paid = await compute_session_summary(db_session, sess1.id)
        assert sum_paid.expected_cash == 8_700_000

        # Toggle paid nakladnoy -> Qarzga: cash-on-hand restored, group caption marked QARZGA
        debt_pay = await mark_nakladnoy_as_debt(db_session, p1.id, user_id=555)
        assert debt_pay is not None and debt_pay.is_debt is True
        assert "QARZGA" in render_nakladnoy_group_caption(debt_pay)

        sum_debt = await compute_session_summary(db_session, sess1.id)
        assert sum_debt.expected_cash == 10_000_000
        assert sum_debt.total_nakladnoy_spent == 0.0
        assert len(sum_debt.debt_nakladnoys) == 1
        assert sum_debt.all_unpaid_debt_count == 1
        assert "Qarzga olingan" in render_status_text(sum_debt)
        assert len(await list_unpaid_debt_nakladnoys(db_session)) == 1

        # Close Day 1 cleanly (10,000,000 counted -> diff 0), then open Day 2
        closed1 = await close_cash_session(db_session, sess1.id, actual_counted_cash=10_000_000)
        assert closed1.session.difference == 0.0

        sess2 = await get_or_create_open_session(db_session, report_date="2026-11-21")
        assert sess2.id != sess1.id

        # Pay yesterday's debt on Day 2 -> moves payout into Day 2, leaves Day 1 untouched!
        paid_res = await mark_nakladnoy_as_paid(db_session, p1.id, user_id=555)
        assert paid_res is not None
        paid_pay, moved = paid_res
        assert moved is True
        assert paid_pay.is_debt is False
        assert paid_pay.session_id == sess2.id
        assert "TO'LANDI" in render_nakladnoy_group_caption(paid_pay, tag="✅ [QARZ TO'LANDI]")

        day2_sum = await compute_session_summary(db_session, sess2.id)
        assert day2_sum.expected_cash == 8_700_000
        assert day2_sum.all_unpaid_debt_count == 0
        assert len(await list_unpaid_debt_nakladnoys(db_session)) == 0

        day1_check = await db_session.get(type(sess1), sess1.id)
        assert day1_check.expected_cash == 10_000_000
        assert day1_check.difference == 0.0

    asyncio.run(_run_with_db(tmp_path, scenario))


def test_nakladnoy_card_and_transfer_do_not_deduct_cash_and_show_in_stats(tmp_path: Path):
    import io
    from openpyxl import load_workbook
    from bot.handlers.admin_tools import _render_period_stats_text
    from bot.handlers.wallet_nakladnoy import render_nakladnoy_group_caption, render_status_text
    from bot.keyboards import (
        auto_confirmed_nakladnoy_kb,
        confirmed_nakladnoy_edit_kb,
        nakladnoy_confirm_kb,
    )
    from database.crud import (
        get_period_statistics,
        get_supplier_sverka,
        set_nakladnoy_payment_method,
    )
    from services.excel_export import build_session_excel, build_sverka_excel

    confirm_cbs = [b.callback_data for row in nakladnoy_confirm_kb(1).inline_keyboard for b in row]
    assert "nak:confirm:1" in confirm_cbs
    assert "nak:save_pm:1:card" in confirm_cbs
    assert "nak:save_pm:1:transfer" in confirm_cbs
    assert "nak:save_debt:1" in confirm_cbs

    auto_cbs = [
        b.callback_data
        for row in auto_confirmed_nakladnoy_kb(1, is_debt=False, payment_method="cash").inline_keyboard
        for b in row
    ]
    assert "nak:set_pm:1:card" in auto_cbs
    assert "nak:set_pm:1:transfer" in auto_cbs
    assert "nak:set_pm:1:cash" in auto_cbs

    debt_edit_cbs = [
        b.callback_data
        for row in confirmed_nakladnoy_edit_kb(1, is_debt=True, is_admin=False).inline_keyboard
        for b in row
    ]
    assert "nak:mark_paid:1" in debt_edit_cbs
    assert "nak:set_pm:1:card" in debt_edit_cbs
    assert "nak:set_pm:1:transfer" in debt_edit_cbs

    async def scenario(db_session: AsyncSession) -> None:
        sess1 = await get_or_create_open_session(db_session, report_date="2026-11-22")
        await add_cash_transaction(db_session, 10_000_000, source_type="main", session_id=sess1.id)

        p_cash = await create_pending_nakladnoy(db_session, "Naqd Supplier", 1_000_000, session_id=sess1.id)
        p_card = await create_pending_nakladnoy(db_session, "Karta Supplier", 2_000_000, session_id=sess1.id)
        p_xfer = await create_pending_nakladnoy(db_session, "Otkazma Supplier", 3_000_000, session_id=sess1.id)
        p_debt = await create_pending_nakladnoy(db_session, "Qarz Supplier", 500_000, session_id=sess1.id)

        # Default payment_method is cash
        confirmed_cash = await confirm_nakladnoy(db_session, p_cash.id)
        assert confirmed_cash.payment_method == "cash"
        confirmed_card = await confirm_nakladnoy(db_session, p_card.id, payment_method="card")
        confirmed_xfer = await confirm_nakladnoy(db_session, p_xfer.id, payment_method="transfer")
        await confirm_nakladnoy(db_session, p_debt.id, is_debt=True)

        assert "KARTA" in render_nakladnoy_group_caption(confirmed_card)
        assert "PERECHESLENIYA" in render_nakladnoy_group_caption(confirmed_xfer)

        # Only cash nakladnoy (1,000,000) deducts from expected_cash (9,000,000)!
        s1 = await compute_session_summary(db_session, sess1.id)
        assert s1.total_nakladnoy_spent == 1_000_000.0
        assert s1.total_card_spent == 2_000_000.0
        assert s1.total_transfer_spent == 3_000_000.0
        assert s1.expected_cash == 9_000_000.0
        assert len(s1.confirmed_nakladnoys) == 1
        assert len(s1.noncash_nakladnoys) == 2

        status_txt = render_status_text(s1)
        assert "Karta / Perechesleniya" in status_txt
        assert "9 000 000" in status_txt

        # Switch cash -> card restores cash-on-hand to 10,000,000; switch back restores 9,000,000
        await set_nakladnoy_payment_method(db_session, p_cash.id, "card", user_id=777)
        s_after_switch = await compute_session_summary(db_session, sess1.id)
        assert s_after_switch.expected_cash == 10_000_000.0
        assert s_after_switch.total_card_spent == 3_000_000.0

        await set_nakladnoy_payment_method(db_session, p_cash.id, "cash", user_id=777)
        s_restored = await compute_session_summary(db_session, sess1.id)
        assert s_restored.expected_cash == 9_000_000.0

        # Period statistics breakdown & Sverka + Session Excel
        st = await get_period_statistics(db_session, "2026-11-22", "2026-11-22")
        assert st["cash_spent"] == 1_000_000.0
        assert st["card_spent"] == 2_000_000.0
        assert st["transfer_spent"] == 3_000_000.0
        assert st["total_spent"] == 6_000_000.0
        stats_txt = _render_period_stats_text("Statistika", st)
        assert "Karta" in stats_txt and "Perechesleniya" in stats_txt

        sverka_rows = await get_supplier_sverka(db_session, "2026-11")
        pm_by_sup = {r["supplier"]: r["payment_method"] for r in sverka_rows}
        assert pm_by_sup["Naqd Supplier"] == "cash"
        assert pm_by_sup["Karta Supplier"] == "card"
        assert pm_by_sup["Otkazma Supplier"] == "transfer"

        wb_sess = load_workbook(io.BytesIO(build_session_excel(s_restored)))
        assert "Karta va Perechesleniya" in wb_sess.sheetnames
        assert wb_sess["Nakladnoylar"].cell(4, 3).value == 1_000_000

        wb_sv = load_workbook(io.BytesIO(build_sverka_excel("2026-11", sverka_rows)))
        assert wb_sv["Barcha to'lovlar"].cell(3, 8).value == "To'lov turi"
        methods_col = [
            wb_sv["Barcha to'lovlar"].cell(r, 8).value
            for r in range(4, 4 + len(sverka_rows))
        ]
        assert {"Naqd", "Karta", "Perechesleniya"}.issubset(set(methods_col))

        # Close Day 1 and pay unpaid debt using transfer on Day 2 -> moves to Day 2 without deducting cash!
        await close_cash_session(db_session, sess1.id, actual_counted_cash=9_000_000)
        sess2 = await get_or_create_open_session(db_session, report_date="2026-11-23")
        await add_cash_transaction(db_session, 1_000_000, source_type="main", session_id=sess2.id)

        paid_debt, moved = await set_nakladnoy_payment_method(db_session, p_debt.id, "transfer", user_id=777)
        assert moved is True
        assert paid_debt.is_debt is False
        assert paid_debt.payment_method == "transfer"
        assert paid_debt.session_id == sess2.id
        cap = render_nakladnoy_group_caption(paid_debt, tag="✅ [QARZ TO'LANDI — O'TKAZMA]")
        assert "QARZ TO'LANDI" in cap and "PERECHESLENIYA" in cap

        s2 = await compute_session_summary(db_session, sess2.id)
        assert s2.opening_balance == 9_000_000.0
        assert s2.expected_cash == 10_000_000.0
        assert s2.total_nakladnoy_spent == 0.0
        assert s2.total_transfer_spent == 500_000.0

    asyncio.run(_run_with_db(tmp_path, scenario))


def test_quick_amount_direct_input_and_benign_error_filter(tmp_path: Path, monkeypatch):
    from types import SimpleNamespace
    from aiogram.exceptions import TelegramBadRequest
    from aiogram.methods import AnswerCallbackQuery
    from bot.handlers import admin_tools as admin_mod
    from bot.handlers import wallet_nakladnoy as wallet_mod
    from bot.keyboards import nakladnoy_quick_amount_kb
    from bot.states import WalletStates
    from config import get_settings

    # 1. Quick-amount keyboard removes redundant manual button & retains adjustments + back
    kb = nakladnoy_quick_amount_kb(27, is_confirmed=True)
    cbs = [b.callback_data for row in kb.inline_keyboard for b in row]
    assert cbs == [
        "nak:adj:27:-10000",
        "nak:adj:27:-1000",
        "nak:adj:27:1000",
        "nak:adj:27:10000",
        "nak:adj_round:27",
        "nak_view:27",
    ]
    assert "nak:edit_amt_manual:27" not in cbs

    # 2. Global error handler ignores stale Telegram callback timeout errors, alerts on real ones
    monkeypatch.setenv("BOT_TOKEN", "test-token")
    monkeypatch.setenv("GEMINI_API_KEY", "test-key")
    monkeypatch.setenv("ADMIN_IDS", "111")
    get_settings.cache_clear()

    sent_alerts: list[str] = []

    class DummyBot:
        def __init__(self) -> None:
            self.cleared_markups: list[tuple[int, int]] = []

        async def send_message(self, chat_id: int, text: str, **kwargs) -> None:
            sent_alerts.append(text)

        async def edit_message_reply_markup(self, chat_id: int, message_id: int, reply_markup=None) -> None:
            self.cleared_markups.append((chat_id, message_id))

    class FakeState:
        def __init__(self) -> None:
            self.cur_state = None
            self.data: dict = {}

        async def get_state(self):
            return self.cur_state

        async def set_state(self, st) -> None:
            self.cur_state = st.state if hasattr(st, "state") else st

        async def update_data(self, **kwargs) -> None:
            self.data.update(kwargs)

        async def get_data(self) -> dict:
            return dict(self.data)

        async def clear(self) -> None:
            self.cur_state = None
            self.data.clear()

    async def scenario() -> None:
        dummy_bot = DummyBot()
        stale_exc = TelegramBadRequest(
            method=AnswerCallbackQuery(callback_query_id="1"),
            message="Bad Request: query is too old and response timeout expired or query ID is invalid",
        )
        assert await admin_mod.on_error(SimpleNamespace(exception=stale_exc), dummy_bot) is True
        assert sent_alerts == []

        assert await admin_mod.on_error(SimpleNamespace(exception=RuntimeError("boom")), dummy_bot) is True
        assert len(sent_alerts) == 1 and "boom" in sent_alerts[0]

        # 3. Direct amount typing works immediately after clicking nak:edit_amt:<id> without extra button
        db_file = tmp_path / "direct_amt.db"
        eng, maker = create_engine_and_session(f"sqlite+aiosqlite:///{db_file.as_posix()}")
        monkeypatch.setattr(wallet_mod, "async_session_maker", maker)
        try:
            await init_db(engine_override=eng, session_maker_override=maker)
            async with maker() as db:
                sess = await get_or_create_open_session(db, report_date="2026-11-24")
                p = await create_pending_nakladnoy(db, "ISMAT KEPAK NON", 130_000, session_id=sess.id)
                await confirm_nakladnoy(db, p.id, user_id=111)

            state = FakeState()
            user = SimpleNamespace(id=111, full_name="Admin")
            chat = SimpleNamespace(id=111, type="private")
            replies: list[str] = []

            class FakeMsg:
                def __init__(self, msg_id: int = 50, text: str = "") -> None:
                    self.message_id = msg_id
                    self.chat = chat
                    self.from_user = user
                    self.text = text
                    self.voice = None
                    self.audio = None
                    self.bot = dummy_bot

                async def edit_text(self, text: str, **kwargs) -> None:
                    replies.append(text)

                async def answer(self, text: str, **kwargs) -> None:
                    replies.append(text)

            class FakeCb:
                def __init__(self, data: str, msg: FakeMsg) -> None:
                    self.data = data
                    self.from_user = user
                    self.message = msg
                    self.bot = dummy_bot

                async def answer(self, *args, **kwargs) -> None:
                    return None

            prompt_msg = FakeMsg(msg_id=50)
            await wallet_mod.cb_nakladnoy_edit_amt_prompt(FakeCb(f"nak:edit_amt:{p.id}", prompt_msg), state)
            assert state.cur_state == WalletStates.waiting_edit_nakladnoy_amount.state
            assert state.data["payment_id"] == p.id
            assert state.data["edit_msg_id"] == 50

            # User types "260000" directly below without tapping another button
            await wallet_mod.process_edit_nakladnoy_amount(FakeMsg(msg_id=51, text="260000"), state)
            assert state.cur_state is None
            assert (111, 50) in dummy_bot.cleared_markups
            assert any("260 000" in r for r in replies)

            async with maker() as db:
                updated = await db.get(type(p), p.id)
                assert float(updated.amount) == 260_000.0

            # Opening quick-adjust then pressing Back clears FSM state
            await wallet_mod.cb_nakladnoy_edit_amt_prompt(FakeCb(f"nak:edit_amt:{p.id}", prompt_msg), state)
            assert state.cur_state == WalletStates.waiting_edit_nakladnoy_amount.state
            await wallet_mod.cb_nakladnoy_edit_view(FakeCb(f"nak_view:{p.id}", prompt_msg), state)
            assert state.cur_state is None
        finally:
            await eng.dispose()

    try:
        asyncio.run(scenario())
    finally:
        get_settings.cache_clear()


def test_all_known_suppliers_pagination_and_inline_supplier_edit(tmp_path: Path, monkeypatch):
    from types import SimpleNamespace
    from bot.handlers import wallet_nakladnoy as wallet_mod
    from bot.keyboards import SUPPLIERS_PAGE_SIZE, edit_supplier_pick_kb, quick_suppliers_kb
    from bot.states import WalletStates
    from config import get_settings
    from database.crud import (
        add_or_update_supplier,
        add_supplier_debt,
        delete_supplier_debt,
        get_all_known_suppliers,
    )

    monkeypatch.setenv("BOT_TOKEN", "test-token")
    monkeypatch.setenv("GEMINI_API_KEY", "test-key")
    monkeypatch.setenv("ADMIN_IDS", "111")
    get_settings.cache_clear()

    class DummyBot:
        def __init__(self) -> None:
            self.cleared_markups: list[tuple[int, int]] = []

        async def edit_message_reply_markup(self, chat_id: int, message_id: int, reply_markup=None) -> None:
            self.cleared_markups.append((chat_id, message_id))

    class FakeState:
        def __init__(self) -> None:
            self.cur_state = None
            self.data: dict = {}

        async def get_state(self):
            return self.cur_state

        async def set_state(self, st) -> None:
            self.cur_state = st.state if hasattr(st, "state") else st

        async def update_data(self, **kwargs) -> None:
            self.data.update(kwargs)

        async def get_data(self) -> dict:
            return dict(self.data)

        async def clear(self) -> None:
            self.cur_state = None
            self.data.clear()

    async def scenario() -> None:
        db_file = tmp_path / "all_suppliers.db"
        eng, maker = create_engine_and_session(f"sqlite+aiosqlite:///{db_file.as_posix()}")
        monkeypatch.setattr(wallet_mod, "async_session_maker", maker)
        try:
            await init_db(engine_override=eng, session_maker_override=maker)
            async with maker() as db:
                seeded_cfgs = await list_suppliers(db)
                expected_total = len(seeded_cfgs) + 22
                sess = await get_or_create_open_session(db, report_date="2026-11-25")
                await add_or_update_supplier(db, "Config Only Brand", aliases="confalias")
                for i in range(1, 21):
                    p = await create_pending_nakladnoy(db, f"Supplier {i:02d}", 100_000, session_id=sess.id)
                    await confirm_nakladnoy(db, p.id, user_id=111)
                # Duplicate via alias resolves cleanly to canonical name
                p_alias = await create_pending_nakladnoy(db, "confalias", 150_000, session_id=sess.id)
                await confirm_nakladnoy(db, p_alias.id, user_id=111)

                await add_supplier_debt(db, "Debt Only Vendor", "debt", 200_000, user_id=111)
                del_debt = await add_supplier_debt(db, "Deleted Debt Vendor", "debt", 50_000, user_id=111)
                await delete_supplier_debt(db, del_debt.id, user_id=111)

                all_sups = await get_all_known_suppliers(db)
                assert len(all_sups) == expected_total
                assert all_sups[0] == "Config Only Brand"
                assert all_sups[1] == "Supplier 20"
                assert "Debt Only Vendor" in all_sups
                assert "Deleted Debt Vendor" not in all_sups
                assert "confalias" not in all_sups

            # Pagination keyboard checks
            assert SUPPLIERS_PAGE_SIZE == 16
            q0 = quick_suppliers_kb(all_sups, page=0)
            q0_cbs = [b.callback_data for row in q0.inline_keyboard for b in row]
            assert "qsup:0" in q0_cbs and "qsup:15" in q0_cbs and "qsup:16" not in q0_cbs
            assert "qsup:page:1" in q0_cbs and "noop" in q0_cbs and "qsup:cancel" in q0_cbs

            q1 = quick_suppliers_kb(all_sups, page=1)
            q1_cbs = [b.callback_data for row in q1.inline_keyboard for b in row]
            assert "qsup:16" in q1_cbs and f"qsup:{expected_total - 1}" in q1_cbs and "qsup:page:0" in q1_cbs

            e0 = edit_supplier_pick_kb(p_alias.id, all_sups, is_confirmed=True, page=0)
            e0_cbs = [b.callback_data for row in e0.inline_keyboard for b in row]
            assert f"nak:pick_sup:{p_alias.id}:0" in e0_cbs
            assert f"nak:pick_sup:{p_alias.id}:15" in e0_cbs
            assert f"nak:sup_page:{p_alias.id}:1" in e0_cbs
            assert f"nak_view:{p_alias.id}" in e0_cbs

            e1_pend = edit_supplier_pick_kb(p_alias.id, all_sups, is_confirmed=False, page=1)
            e1_cbs = [b.callback_data for row in e1_pend.inline_keyboard for b in row]
            assert f"nak:pick_sup:{p_alias.id}:16" in e1_cbs
            assert f"nak:sup_page:{p_alias.id}:0" in e1_cbs
            assert f"nak:back_card:{p_alias.id}" in e1_cbs

            # End-to-end handlers: Add Nakladnoy pagination + Edit Supplier pick + Direct type
            dummy_bot = DummyBot()
            user = SimpleNamespace(id=111, full_name="Admin")
            chat = SimpleNamespace(id=111, type="private")
            markups_log = []
            texts_log = []

            class FakeMsg:
                def __init__(self, msg_id: int = 80, text: str = "") -> None:
                    self.message_id = msg_id
                    self.chat = chat
                    self.from_user = user
                    self.text = text
                    self.voice = None
                    self.audio = None
                    self.bot = dummy_bot

                async def answer(self, text: str, reply_markup=None, **kwargs) -> None:
                    texts_log.append(text)
                    markups_log.append(reply_markup)

                async def edit_text(self, text: str, reply_markup=None, **kwargs) -> None:
                    texts_log.append(text)
                    markups_log.append(reply_markup)

                async def edit_reply_markup(self, reply_markup=None, **kwargs) -> None:
                    markups_log.append(reply_markup)

            class FakeCb:
                def __init__(self, data: str, msg: FakeMsg) -> None:
                    self.data = data
                    self.from_user = user
                    self.message = msg
                    self.bot = dummy_bot

                async def answer(self, *args, **kwargs) -> None:
                    return None

            state = FakeState()
            msg = FakeMsg(msg_id=80)
            await wallet_mod.handle_add_nakladnoy_btn(msg, state, actor_id=111)
            assert len(state.data["quick_suppliers"]) == expected_total
            assert any("qsup:page:1" in (b.callback_data or "") for r in markups_log[-1].inline_keyboard for b in r)

            await wallet_mod.cb_quick_supplier_page(FakeCb("qsup:page:1", msg), state)
            assert any("qsup:16" in (b.callback_data or "") for r in markups_log[-1].inline_keyboard for b in r)

            # Open Edit Supplier picker -> flips to page 1 -> clicks item 17
            await wallet_mod.cb_nakladnoy_edit_sup_prompt(FakeCb(f"nak:edit_sup:{p_alias.id}", msg), state)
            assert state.cur_state == WalletStates.waiting_edit_nakladnoy_supplier.state
            assert any(f"nak:sup_page:{p_alias.id}:1" in (b.callback_data or "") for r in markups_log[-1].inline_keyboard for b in r)

            await wallet_mod.cb_nakladnoy_edit_sup_page(FakeCb(f"nak:sup_page:{p_alias.id}:1", msg), state)
            assert any(f"nak:pick_sup:{p_alias.id}:17" in (b.callback_data or "") for r in markups_log[-1].inline_keyboard for b in r)

            await wallet_mod.cb_nakladnoy_pick_supplier(FakeCb(f"nak:pick_sup:{p_alias.id}:17", msg), state)
            assert state.cur_state is None
            async with maker() as db:
                updated1 = await db.get(type(p_alias), p_alias.id)
                assert updated1.supplier_name == all_sups[17]

            # Re-open Edit Supplier picker and type a new name directly below
            await wallet_mod.cb_nakladnoy_edit_sup_prompt(FakeCb(f"nak:edit_sup:{p_alias.id}", msg), state)
            await wallet_mod.process_edit_nakladnoy_supplier(FakeMsg(msg_id=81, text="Manual Custom Oka"), state)
            assert state.cur_state is None
            assert (111, 80) in dummy_bot.cleared_markups
            async with maker() as db:
                updated2 = await db.get(type(p_alias), p_alias.id)
                assert updated2.supplier_name == "Manual Custom Oka"
        finally:
            await eng.dispose()

    try:
        asyncio.run(scenario())
    finally:
        get_settings.cache_clear()


def test_nakladnoy_session_seq_numbering_and_daily_reset(tmp_path: Path):
    from bot.handlers.wallet_nakladnoy import render_nakladnoy_group_caption
    from database.crud import get_nakladnoy_session_seq

    async def scenario(db_session: AsyncSession) -> None:
        s1 = await get_or_create_open_session(db_session, report_date="2026-11-26")
        await add_cash_transaction(db_session, 5_000_000, source_type="main", session_id=s1.id)

        p1 = await create_pending_nakladnoy(db_session, "RDB Yunusobod 1", 1_554_000, session_id=s1.id)
        # Pending draft has no confirmed session sequence yet
        assert await get_nakladnoy_session_seq(db_session, p1) is None
        await confirm_nakladnoy(db_session, p1.id)

        # Deleted draft between confirmed payments must not consume sequence numbers
        p_del = await create_pending_nakladnoy(db_session, "Deleted Draft", 100_000, session_id=s1.id)
        await delete_nakladnoy(db_session, p_del.id)

        p2 = await create_pending_nakladnoy(db_session, "Karta Vendor", 400_000, session_id=s1.id)
        await confirm_nakladnoy(db_session, p2.id, payment_method="card")

        p3 = await create_pending_nakladnoy(db_session, "Qarz Vendor", 250_000, session_id=s1.id)
        await confirm_nakladnoy(db_session, p3.id, is_debt=True)

        assert await get_nakladnoy_session_seq(db_session, p_del) is None
        assert await get_nakladnoy_session_seq(db_session, p1) == 1
        assert await get_nakladnoy_session_seq(db_session, p2) == 2
        assert await get_nakladnoy_session_seq(db_session, p3) == 3

        assert f"Nakladnoy #{p1.id} / 1" in render_nakladnoy_group_caption(p1, session_seq=1)
        assert f"Nakladnoy #{p2.id} / 2" in render_nakladnoy_group_caption(p2, session_seq=2)
        assert f"Nakladnoy #{p3.id} / 3" in render_nakladnoy_group_caption(p3, session_seq=3)

        # Close Day 1 -> Open Day 2 -> daily ordinal resets cleanly to 1
        await close_cash_session(db_session, s1.id, actual_counted_cash=3_446_000)
        s2 = await get_or_create_open_session(db_session, report_date="2026-11-27")
        p4 = await create_pending_nakladnoy(db_session, "Next Day Supplier", 300_000, session_id=s2.id)
        await confirm_nakladnoy(db_session, p4.id)

        assert p4.id > p3.id
        assert await get_nakladnoy_session_seq(db_session, p4) == 1
        assert f"Nakladnoy #{p4.id} / 1" in render_nakladnoy_group_caption(p4, session_seq=1)

    asyncio.run(_run_with_db(tmp_path, scenario))


def test_fsm_storage_cache_and_fast_expected_cash_sync(tmp_path: Path, monkeypatch):
    from aiogram.fsm.state import State
    from aiogram.fsm.storage.base import StorageKey
    from bot.handlers import wallet_nakladnoy as wallet_mod
    from bot.storage import DatabaseFSMStorage
    from database.crud import _sync_session_expected_cash, set_nakladnoy_payment_method

    async def scenario() -> None:
        db_file = tmp_path / "perf_test.db"
        eng, maker = create_engine_and_session(f"sqlite+aiosqlite:///{db_file.as_posix()}")
        monkeypatch.setattr(wallet_mod, "async_session_maker", maker)
        try:
            await init_db(engine_override=eng, session_maker_override=maker)

            # 1. FSM storage write-through RAM cache + DB persistence across instances
            st1 = DatabaseFSMStorage(maker)
            key = StorageKey(bot_id=1, chat_id=22, user_id=22)
            sample_state = State(state="edit_amt", group_name="Wallet")

            await st1.set_state(key, sample_state)
            await st1.set_data(key, {"payment_id": 99, "items": ["a", "b"]})
            assert await st1.get_state(key) == "Wallet:edit_amt"

            cached_view = await st1.get_data(key)
            cached_view["mutated"] = True
            assert "mutated" not in await st1.get_data(key)

            # Identical repeat writes are skipped cleanly & fresh instance reads persisted state
            await st1.set_state(key, sample_state)
            await st1.set_data(key, {"payment_id": 99, "items": ["a", "b"]})
            st2 = DatabaseFSMStorage(maker)
            assert await st2.get_state(key) == "Wallet:edit_amt"
            assert await st2.get_data(key) == {"payment_id": 99, "items": ["a", "b"]}

            # 2. Fast _sync_session_expected_cash stays 100% consistent with compute_session_summary
            async with maker() as db:
                sess = await get_or_create_open_session(db, report_date="2026-11-28")
                await add_cash_transaction(db, 5_000_000, source_type="main", session_id=sess.id)
                await add_cash_transaction(db, 1_000_000, source_type="kassa_debt", session_id=sess.id)
                await add_cash_transaction(db, 500_000, source_type="kassa_repay", session_id=sess.id)

                p_cash = await create_pending_nakladnoy(
                    db, "Cash Co", 1_200_000, photo_file_id="fake-photo-id", session_id=sess.id
                )
                await confirm_nakladnoy(
                    db, p_cash.id, group_chat_id=-1009, group_message_id=77, payment_method="cash"
                )
                p_card = await create_pending_nakladnoy(db, "Card Co", 800_000, session_id=sess.id)
                await confirm_nakladnoy(db, p_card.id, payment_method="card")
                p_debt = await create_pending_nakladnoy(db, "Debt Co", 400_000, session_id=sess.id)
                await confirm_nakladnoy(db, p_debt.id, is_debt=True)

                await db.refresh(sess)
                full = await compute_session_summary(db, sess.id)
                assert sess.expected_cash == full.expected_cash == 4_300_000.0

                await update_nakladnoy(db, p_cash.id, amount=777_000)
                await set_nakladnoy_payment_method(db, p_card.id, "transfer")
                await _sync_session_expected_cash(db, sess.id)
                await db.refresh(sess)
                full2 = await compute_session_summary(db, sess.id)
                assert sess.expected_cash == full2.expected_cash == 4_723_000.0

            # 3. Coalesced background group sync triggers only 1 edit after rapid burst
            edited_captions: list[str] = []

            class FakeGroupBot:
                async def edit_message_caption(self, chat_id: int, message_id: int, caption: str, **kwargs) -> None:
                    edited_captions.append(caption)

            fake_bot = FakeGroupBot()
            async with maker() as db:
                fresh = await db.get(type(p_cash), p_cash.id)

            wallet_mod._schedule_group_sync(fake_bot, fresh, tag="✏️ [SUMMA TAHRIRLANDI]", delay=0.05)
            wallet_mod._schedule_group_sync(fake_bot, fresh, tag="✏️ [SUMMA TAHRIRLANDI]", delay=0.05)
            wallet_mod._schedule_group_sync(fake_bot, fresh, tag="✏️ [SUMMA TAHRIRLANDI]", delay=0.05)
            pending = wallet_mod._PENDING_GROUP_SYNCS.get(fresh.id)
            assert pending is not None
            await pending
            assert len(edited_captions) == 1
            assert "777 000" in edited_captions[0]
        finally:
            await eng.dispose()

    asyncio.run(scenario())


def test_mobile_apk_rest_api_and_group_posting(tmp_path: Path, monkeypatch):
    from types import SimpleNamespace
    import httpx
    from api import app as api_app_mod
    from api import auth as api_auth_mod
    from api import deps as api_deps_mod
    from config import get_settings
    from database.crud import set_group_config

    monkeypatch.setenv("BOT_TOKEN", "test-token")
    monkeypatch.setenv("GEMINI_API_KEY", "test-key")
    monkeypatch.setenv("ADMIN_IDS", "111")
    get_settings.cache_clear()
    api_auth_mod.clear_auth_memory_state()
    monkeypatch.setattr(api_deps_mod, "APK_PHOTOS_DIR", tmp_path / "apk_photos")

    class FakeGroupBot:
        def __init__(self) -> None:
            self.sent_messages: list[tuple[int, str, bool]] = []
            self.edited_messages: list[tuple[int, int, str]] = []

        async def send_photo(self, chat_id: int, photo, caption: str, **kwargs):
            self.sent_messages.append((chat_id, caption, True))
            return SimpleNamespace(
                message_id=901,
                photo=[SimpleNamespace(file_id="tg-apk-photo-901")],
            )

        async def send_message(self, chat_id: int, text: str, **kwargs):
            self.sent_messages.append((chat_id, text, False))
            return SimpleNamespace(message_id=902, photo=None)

        async def edit_message_caption(self, chat_id: int, message_id: int, caption: str, **kwargs):
            self.edited_messages.append((chat_id, message_id, caption))

        async def edit_message_text(self, chat_id: int, message_id: int, text: str, **kwargs):
            self.edited_messages.append((chat_id, message_id, text))

    async def scenario():
        db_file = tmp_path / "test_apk_api.db"
        eng, maker = create_engine_and_session(f"sqlite+aiosqlite:///{db_file.as_posix()}")
        await init_db(engine_override=eng, session_maker_override=maker)
        monkeypatch.setattr(api_auth_mod, "async_session_maker", maker)
        monkeypatch.setattr(api_deps_mod, "async_session_maker", maker)
        monkeypatch.setattr(api_app_mod, "async_session_maker", maker)

        fake_bot = FakeGroupBot()
        api_deps_mod.set_bot(fake_bot)
        try:
            async with maker() as db:
                await set_group_config(db, "nakladnoy", -100777888, "Test Nakladnoy Group")

            app = api_app_mod.create_api_app()
            transport = httpx.ASGITransport(app=app)
            async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as client:
                # 1. Health check
                r_health = await client.get("/health")
                assert r_health.status_code == 200
                assert r_health.json()["status"] == "ok"

                # 2. One-time code login
                code = api_auth_mod.create_login_code(111)
                r_login = await client.post(
                    "/auth/login",
                    json={"code": code, "device_name": "Samsung S24"},
                )
                assert r_login.status_code == 200
                token = r_login.json()["access_token"]
                assert r_login.json()["role"] == "admin"

                # Reusing one-time code fails
                r_reuse = await client.post("/auth/login", json={"code": code})
                assert r_reuse.status_code == 401

                headers = {"Authorization": f"Bearer {token}"}

                # 3. Cash transaction
                r_cash = await client.post(
                    "/cash",
                    headers=headers,
                    json={"amount": 5_000_000, "source_type": "main", "note": "Seyfdan"},
                )
                assert r_cash.status_code == 200
                tx_id = r_cash.json()["id"]

                # 4. Create cash nakladnoy with photo -> posts to bound Telegram group
                r_nak1 = await client.post(
                    "/nakladnoy",
                    headers=headers,
                    data={
                        "supplier_name": "Coca Cola",
                        "amount": "1200000",
                        "payment_mode": "cash",
                        "send_to_group": "true",
                    },
                    files={"photo": ("check.jpg", b"\xff\xd8\xff\xe0fakejpeg", "image/jpeg")},
                )
                assert r_nak1.status_code == 200
                nak1 = r_nak1.json()["nakladnoy"]
                assert r_nak1.json()["group_posted"] is True
                assert nak1["display_num"] == f"#{nak1['id']} / 1"
                assert len(fake_bot.sent_messages) == 1
                assert "Coca Cola" in fake_bot.sent_messages[0][1]

                # 5. Create card & debt nakladnoys (card/debt do not reduce expected_cash)
                r_nak2 = await client.post(
                    "/nakladnoy",
                    headers=headers,
                    data={
                        "supplier_name": "Card Supplier",
                        "amount": "800000",
                        "payment_mode": "card",
                        "send_to_group": "false",
                    },
                )
                assert r_nak2.status_code == 200

                r_nak3 = await client.post(
                    "/nakladnoy",
                    headers=headers,
                    data={
                        "supplier_name": "Debt Supplier",
                        "amount": "500000",
                        "payment_mode": "debt",
                        "send_to_group": "false",
                    },
                )
                assert r_nak3.status_code == 200
                debt_id = r_nak3.json()["nakladnoy"]["id"]

                # 6. Check /status balance
                r_status = await client.get("/status", headers=headers)
                assert r_status.status_code == 200
                st = r_status.json()
                assert st["expected_cash"] == 3_800_000.0
                assert st["total_card_spent"] == 800_000.0
                assert st["total_debt_nakladnoy"] == 500_000.0
                assert len(st["nakladnoys"]) == 3

                # 7. Pay debt nakladnoy via transfer -> does not reduce cash
                r_pay = await client.post(
                    f"/nakladnoy/{debt_id}/paid",
                    headers=headers,
                    json={"payment_method": "transfer"},
                )
                assert r_pay.status_code == 200
                assert r_pay.json()["is_debt"] is False
                assert r_pay.json()["payment_method"] == "transfer"

                # 8. Excel export
                r_xlsx = await client.get("/export/session", headers=headers)
                assert r_xlsx.status_code == 200
                assert len(r_xlsx.content) > 1000

                # 8b. AI photo extraction resolves canonical supplier & rounds amount
                async def fake_extract(raw, mime_type="image/jpeg", caption=None):
                    return {
                        "supplier_name": "coca cola",
                        "amount": 192_640.0,
                        "is_clear": True,
                        "notes": "",
                        "error_code": None,
                    }

                monkeypatch.setattr(api_app_mod, "extract_nakladnoy_from_image", fake_extract)
                r_ai = await client.post(
                    "/ai/extract",
                    headers=headers,
                    files={"photo": ("n.jpg", b"\xff\xd8\xff\xe0fake", "image/jpeg")},
                )
                assert r_ai.status_code == 200
                ai = r_ai.json()
                assert ai["ok"] is True
                assert ai["supplier_name"] == "Coca Cola"
                assert ai["amount"] == 192_000.0
                assert ai["original_amount"] == 192_640.0
                assert 1_200_000.0 in ai["recent_amounts"]

                # 8c. Round amount via PATCH (sync rounding helper)
                r_edit = await client.patch(
                    f"/nakladnoy/{nak1['id']}", headers=headers, json={"amount": 1_200_640}
                )
                assert r_edit.status_code == 200
                r_round = await client.patch(
                    f"/nakladnoy/{nak1['id']}", headers=headers, json={"round_amount": True}
                )
                assert r_round.status_code == 200
                assert r_round.json()["amount"] == 1_200_000.0

                # 9. Close day
                r_close = await client.post(
                    "/day/close",
                    headers=headers,
                    json={"actual_counted_cash": 3_800_000},
                )
                assert r_close.status_code == 200
                assert r_close.json()["difference"] == 0.0
                assert r_close.json()["next_opening_balance"] == 3_800_000.0

                # 10. Logout revokes token
                r_out = await client.post("/auth/logout", headers=headers)
                assert r_out.status_code == 200
                r_after = await client.get("/me", headers=headers)
                assert r_after.status_code == 401
        finally:
            api_deps_mod.set_bot(None)
            await eng.dispose()

    try:
        asyncio.run(scenario())
    finally:
        get_settings.cache_clear()

