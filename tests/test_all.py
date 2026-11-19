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
