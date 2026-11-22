"""FastAPI application providing mobile APK endpoints sharing the bot database and Telegram group."""

from __future__ import annotations

import asyncio
from datetime import timedelta
import html
import io
from typing import Optional

from fastapi import Depends, FastAPI, File, Form, HTTPException, Query, Request, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, Response, StreamingResponse

from api.auth import (
    AuthenticatedUser,
    consume_login_code,
    get_current_user,
    issue_api_token,
    require_write_user,
    revoke_raw_token,
)
from api.deps import (
    APK_BINARY_PATH,
    get_apk_version_metadata,
    get_bot,
    get_local_photo_path,
    has_local_photo,
    post_nakladnoy_to_telegram_group,
    save_local_photo,
    sync_existing_group_message,
)
from api.schemas import (
    CashCreateRequest,
    CashTxOut,
    CashUpdateRequest,
    DayCloseRequest,
    DayCloseResponse,
    GroupConfigInfo,
    LoginRequest,
    LoginResponse,
    NakladnoyOut,
    NakladnoyUpdateRequest,
    NasiyaCreateRequest,
    PaymentMethodRequest,
    PrixodTextCreateRequest,
    RoundModeUpdateRequest,
    StatusSummaryResponse,
    SupplierConfigCreateRequest,
    UserProfileResponse,
)
from bot.auth import ROLE_ADMIN, can_write_role, get_user_role, is_admin_role
from database.crud import (
    add_cash_transaction,
    add_or_update_supplier,
    add_supplier_debt,
    close_cash_session,
    compute_session_summary,
    confirm_nakladnoy,
    create_pending_nakladnoy,
    delete_cash_transaction,
    delete_nakladnoy,
    delete_supplier,
    delete_supplier_debt,
    find_similar_suppliers,
    format_local_dt,
    get_all_known_suppliers,
    get_app_setting,
    get_group_config,
    get_nakladnoy,
    get_nakladnoy_session_seq,
    get_or_create_open_session,
    get_period_statistics,
    get_prixod_report,
    get_range_report_data,
    get_recent_amounts_for_supplier,
    get_supplier_debt_balances,
    get_supplier_sverka,
    list_all_sessions,
    list_prixod_reports,
    list_recent_nakladnoys,
    list_supplier_debt_entries,
    list_suppliers,
    list_unpaid_debt_nakladnoys,
    mark_nakladnoy_as_debt,
    mark_nakladnoy_as_paid,
    mark_prixod_published,
    normalize_payment_method,
    now_local,
    reopen_cash_session,
    resolve_supplier_name,
    round_nakladnoy_amount,
    save_prixod_report,
    search_nakladnoys,
    set_app_setting,
    set_nakladnoy_payment_method,
    today_iso,
    update_cash_transaction,
    update_nakladnoy,
)
from database.models import CashTransaction, NakladnoyPayment
from database.session import async_session_maker
from services.excel_export import build_range_excel, build_session_excel, build_sverka_excel
from services.gemini_ai import extract_nakladnoy_from_image
from services.prixod_parser import parse_manual_itog_text, parse_yespos_table


def _serialize_cash_tx(tx: CashTransaction) -> CashTxOut:
    return CashTxOut(
        id=int(tx.id),
        session_id=int(tx.session_id),
        amount=float(tx.amount),
        source_type=tx.source_type,
        note=tx.note or "",
        created_at=format_local_dt(tx.created_at, "%Y-%m-%d %H:%M"),
        time_hm=format_local_dt(tx.created_at, "%H:%M"),
    )


def _serialize_nakladnoy(
    n: NakladnoyPayment,
    session_seq: Optional[int] = None,
    report_date: Optional[str] = None,
) -> NakladnoyOut:
    pm = normalize_payment_method(getattr(n, "payment_method", "cash"))
    has_ph = bool(n.photo_file_id) or has_local_photo(int(n.id))
    in_grp = bool(n.group_chat_id and n.group_message_id)
    disp = f"#{n.id} / {session_seq}" if session_seq else f"#{n.id}"
    return NakladnoyOut(
        id=int(n.id),
        session_id=int(n.session_id),
        session_seq=session_seq,
        display_num=disp,
        supplier_name=n.supplier_name,
        amount=float(n.amount),
        original_amount=float(n.original_amount) if n.original_amount is not None else None,
        payment_method=pm,
        is_debt=bool(getattr(n, "is_debt", False)),
        note=n.note or "",
        has_photo=has_ph,
        in_group=in_grp,
        group_chat_id=n.group_chat_id,
        group_message_id=n.group_message_id,
        created_at=format_local_dt(n.created_at, "%Y-%m-%d %H:%M"),
        time_hm=format_local_dt(n.created_at, "%H:%M"),
        report_date=report_date,
    )


async def _load_group_info(db) -> GroupConfigInfo:
    grp = await get_group_config(db, "nakladnoy")
    apk_toggle = await get_app_setting(db, "apk_post_to_group", "on")
    post_enabled = (apk_toggle or "on").strip().lower() != "off"
    if grp and grp.chat_id:
        return GroupConfigInfo(
            bound=True,
            chat_id=int(grp.chat_id),
            title=grp.title or str(grp.chat_id),
            apk_post_to_group=post_enabled,
        )
    return GroupConfigInfo(bound=False, chat_id=None, title="", apk_post_to_group=post_enabled)


def create_api_app() -> FastAPI:
    """Create and configure the FastAPI application for Hisobot Mobile APK."""
    app = FastAPI(
        title="Hisobchi Mobile API",
        version="1.0.0",
        docs_url=None,
        redoc_url=None,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.get("/health")
    async def health() -> dict:
        meta = get_apk_version_metadata()
        return {
            "status": "ok",
            "service": "hisobchi-api",
            "apk_version": meta["version"],
            "apk_build": meta["build"],
        }

    @app.get("/apk/version")
    async def get_apk_version() -> dict:
        meta = get_apk_version_metadata()
        return {
            **meta,
            "download_path": "/download/hisobchi.apk",
        }

    @app.get("/download/hisobchi.apk")
    async def download_apk_binary():
        if not APK_BINARY_PATH.is_file():
            raise HTTPException(
                status_code=404,
                detail="APK fayli serverda topilmadi (data/hisobchi.apk)",
            )
        meta = get_apk_version_metadata()
        fname = f"Hisobchi_v{meta['version']}.apk"
        return FileResponse(
            APK_BINARY_PATH,
            media_type="application/vnd.android.package-archive",
            filename=fname,
            headers={"Cache-Control": "no-cache, no-store, must-revalidate"},
        )

    @app.post("/auth/login", response_model=LoginResponse)
    async def auth_login(payload: LoginRequest, request: Request) -> LoginResponse:
        client_ip = request.client.host if request.client else "unknown"
        user_id = consume_login_code(payload.code, client_ip=client_ip)
        if user_id is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Kod noto'g'ri yoki muddati tugagan. Telegram botga /apk yozib yangi kod oling.",
            )
        role = get_user_role(user_id)
        if role is None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Ushbu foydalanuvchiga ruxsat berilmagan.",
            )
        async with async_session_maker() as db:
            raw_token, _ = await issue_api_token(db, user_id=user_id, device_name=payload.device_name)

        return LoginResponse(
            access_token=raw_token,
            user_id=user_id,
            role=role,
            can_write=can_write_role(user_id),
            is_admin=is_admin_role(user_id) or role == ROLE_ADMIN,
        )

    @app.post("/auth/logout")
    async def auth_logout(user: AuthenticatedUser = Depends(get_current_user)) -> dict:
        async with async_session_maker() as db:
            await revoke_raw_token(db, user.raw_token)
        return {"ok": True}

    @app.get("/me", response_model=UserProfileResponse)
    async def get_me(user: AuthenticatedUser = Depends(get_current_user)) -> UserProfileResponse:
        return UserProfileResponse(
            user_id=user.user_id,
            role=user.role,
            can_write=user.can_write,
            is_admin=user.is_admin,
        )

    @app.get("/config", response_model=GroupConfigInfo)
    async def get_config(user: AuthenticatedUser = Depends(get_current_user)) -> GroupConfigInfo:
        async with async_session_maker() as db:
            return await _load_group_info(db)

    @app.get("/status", response_model=StatusSummaryResponse)
    async def get_status(user: AuthenticatedUser = Depends(get_current_user)) -> StatusSummaryResponse:
        async with async_session_maker() as db:
            summary = await compute_session_summary(db)
            grp_info = await _load_group_info(db)

        all_naks = sorted(
            [
                *summary.confirmed_nakladnoys,
                *summary.noncash_nakladnoys,
                *summary.debt_nakladnoys,
            ],
            key=lambda x: x.id,
        )
        nak_outs = [
            _serialize_nakladnoy(n, session_seq=idx, report_date=summary.session.report_date)
            for idx, n in enumerate(all_naks, start=1)
        ]
        cash_outs = [_serialize_cash_tx(tx) for tx in summary.cash_transactions]

        return StatusSummaryResponse(
            session_id=int(summary.session.id),
            report_date=summary.session.report_date,
            session_status=summary.session.status,
            opening_balance=float(summary.opening_balance),
            main_cash_in=float(summary.main_cash_in),
            kassa_debt_today=float(summary.kassa_debt_today),
            kassa_repay_today=float(summary.kassa_repay_today),
            total_available_inflow=float(summary.total_available_inflow),
            total_nakladnoy_spent=float(summary.total_nakladnoy_spent),
            total_card_spent=float(summary.total_card_spent),
            total_transfer_spent=float(summary.total_transfer_spent),
            total_debt_nakladnoy=float(summary.total_debt_nakladnoy),
            expected_cash=float(summary.expected_cash),
            total_kassa_debt_outstanding=float(summary.total_kassa_debt_outstanding),
            all_unpaid_debt_count=int(summary.all_unpaid_debt_count),
            all_unpaid_debt_total=float(summary.all_unpaid_debt_total),
            group_info=grp_info,
            cash_transactions=cash_outs,
            nakladnoys=nak_outs,
        )

    @app.post("/cash", response_model=CashTxOut)
    async def create_cash(
        payload: CashCreateRequest,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> CashTxOut:
        async with async_session_maker() as db:
            tx = await add_cash_transaction(
                db,
                amount=payload.amount,
                source_type=payload.source_type,
                note=payload.note,
            )
        return _serialize_cash_tx(tx)

    @app.patch("/cash/{tx_id}", response_model=CashTxOut)
    async def edit_cash(
        tx_id: int,
        payload: CashUpdateRequest,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> CashTxOut:
        async with async_session_maker() as db:
            tx = await update_cash_transaction(
                db,
                tx_id=tx_id,
                new_amount=payload.amount,
                new_note=payload.note,
                user_id=user.user_id,
            )
        if tx is None:
            raise HTTPException(status_code=404, detail="Kassa amali topilmadi")
        return _serialize_cash_tx(tx)

    @app.delete("/cash/{tx_id}")
    async def remove_cash(
        tx_id: int,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        async with async_session_maker() as db:
            tx = await delete_cash_transaction(db, tx_id=tx_id, user_id=user.user_id)
        if tx is None:
            raise HTTPException(status_code=404, detail="Kassa amali topilmadi")
        return {"ok": True, "deleted_id": tx_id}

    @app.get("/suppliers")
    async def get_suppliers(
        q: str = Query(default=""),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        async with async_session_maker() as db:
            names = await get_all_known_suppliers(db, limit=250)
        if q.strip():
            needle = q.strip().lower()
            names = [n for n in names if needle in n.lower()]
        return {"suppliers": names}

    @app.get("/suppliers/amounts")
    async def get_supplier_amounts(
        supplier: str = Query(..., min_length=1),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        async with async_session_maker() as db:
            canonical, _ = await resolve_supplier_name(db, supplier.strip())
            amounts = await get_recent_amounts_for_supplier(db, canonical, limit=6)
        return {"supplier": canonical, "amounts": [float(a) for a in amounts]}

    @app.get("/suppliers/similar")
    async def get_similar_suppliers_endpoint(
        q: str = Query(..., min_length=1),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        async with async_session_maker() as db:
            similar = await find_similar_suppliers(db, q.strip(), limit=4, cutoff=0.60)
        return {"query": q.strip(), "similar": similar}

    @app.post("/ai/extract")
    async def ai_extract_nakladnoy(
        photo: UploadFile = File(...),
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        """Read supplier & total amount from a nakladnoy photo via Gemini Vision (same engine as bot)."""
        raw = await photo.read()
        if not raw:
            raise HTTPException(status_code=400, detail="Rasm bo'sh")
        if len(raw) > 15 * 1024 * 1024:
            raise HTTPException(status_code=400, detail="Rasm hajmi 15 MB dan oshmasligi kerak")

        res = await extract_nakladnoy_from_image(raw, mime_type=photo.content_type or "image/jpeg")
        err = res.get("error_code")
        supplier_raw = res.get("supplier_name")
        amount_raw = res.get("amount")

        canonical: Optional[str] = None
        suggestion: Optional[str] = None
        similar_list: list[str] = []
        amounts: list[float] = []
        rounded: Optional[float] = None
        async with async_session_maker() as db:
            if supplier_raw:
                canonical, suggestion = await resolve_supplier_name(db, str(supplier_raw))
                similar_list = await find_similar_suppliers(
                    db, str(supplier_raw), limit=4, cutoff=0.60
                )
                if suggestion and suggestion not in similar_list:
                    similar_list.insert(0, suggestion)
                target_for_amts = suggestion or canonical
                if target_for_amts:
                    amounts = [
                        float(a)
                        for a in await get_recent_amounts_for_supplier(
                            db, target_for_amts, limit=6
                        )
                    ]
            if amount_raw:
                r_mode = await get_app_setting(db, "round_mode", "floor_1000")
                rounded = round_nakladnoy_amount(float(amount_raw), r_mode)

        messages = {
            "no_key": "AI kaliti sozlanmagan",
            "rate_limit": "AI limiti tugadi, birozdan keyin urinib ko'ring",
            "api_error": "AI javob bermadi, qo'lda kiriting",
        }
        return {
            "ok": err is None and bool(canonical or rounded),
            "supplier_name": canonical or (str(supplier_raw) if supplier_raw else None),
            "supplier_suggestion": suggestion,
            "similar_suppliers": similar_list,
            "amount": rounded,
            "original_amount": float(amount_raw) if amount_raw else None,
            "is_clear": bool(res.get("is_clear")),
            "recent_amounts": amounts,
            "error_code": err,
            "message": messages.get(err or "", ""),
        }

    @app.post("/nakladnoy")
    async def create_nakladnoy(
        supplier_name: str = Form(...),
        amount: float = Form(...),
        payment_mode: str = Form(default="cash"),  # cash | card | transfer | debt
        note: str = Form(default=""),
        send_to_group: bool = Form(default=True),
        original_amount: Optional[float] = Form(default=None),
        photo: Optional[UploadFile] = File(default=None),
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        clean_supplier = supplier_name.strip()
        if not clean_supplier:
            raise HTTPException(status_code=400, detail="Postavshik nomini kiriting")
        if amount <= 0:
            raise HTTPException(status_code=400, detail="Summa 0 dan katta bo'lishi kerak")

        mode = (payment_mode or "cash").strip().lower()
        is_debt = mode == "debt"
        pm = "cash" if is_debt else normalize_payment_method(mode)

        photo_bytes: Optional[bytes] = None
        if photo is not None:
            raw = await photo.read()
            if raw:
                if len(raw) > 15 * 1024 * 1024:
                    raise HTTPException(status_code=400, detail="Rasm hajmi 15 MB dan oshmasligi kerak")
                photo_bytes = raw

        async with async_session_maker() as db:
            canonical, _ = await resolve_supplier_name(db, clean_supplier)
            pending = await create_pending_nakladnoy(
                db,
                supplier_name=canonical,
                amount=amount,
                note=note.strip() or None,
                original_amount=(
                    original_amount
                    if original_amount and round(original_amount) != round(amount)
                    else None
                ),
            )
            confirmed = await confirm_nakladnoy(
                db,
                payment_id=pending.id,
                user_id=user.user_id,
                is_debt=is_debt,
                payment_method=pm,
            )
            if confirmed is None:
                raise HTTPException(status_code=500, detail="Nakladnoy tasdiqlashda xatolik")
            seq = await get_nakladnoy_session_seq(db, confirmed)

        if photo_bytes:
            await asyncio.to_thread(save_local_photo, confirmed.id, photo_bytes)

        grp_ok = False
        grp_msg = "Faqat bazaga saqlandi"
        if send_to_group:
            grp_ok, grp_msg = await post_nakladnoy_to_telegram_group(
                confirmed.id, photo_bytes=photo_bytes, force=False
            )
            if grp_ok:
                async with async_session_maker() as db:
                    refreshed = await get_nakladnoy(db, confirmed.id)
                    if refreshed is not None:
                        confirmed = refreshed

        return {
            "nakladnoy": _serialize_nakladnoy(confirmed, session_seq=seq),
            "group_posted": grp_ok,
            "group_message": grp_msg,
        }

    @app.get("/nakladnoy")
    async def list_nakladnoys(
        scope: str = Query(default="today"),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        async with async_session_maker() as db:
            if scope == "recent":
                rows = await list_recent_nakladnoys(db, limit=60)
                items = [_serialize_nakladnoy(r) for r in rows]
            else:
                summary = await compute_session_summary(db)
                all_naks = sorted(
                    [
                        *summary.confirmed_nakladnoys,
                        *summary.noncash_nakladnoys,
                        *summary.debt_nakladnoys,
                    ],
                    key=lambda x: x.id,
                )
                items = [
                    _serialize_nakladnoy(
                        n, session_seq=idx, report_date=summary.session.report_date
                    )
                    for idx, n in enumerate(all_naks, start=1)
                ]
        return {"items": items}

    @app.get("/nakladnoy/{payment_id}/photo")
    async def get_nakladnoy_photo(
        payment_id: int,
        user: AuthenticatedUser = Depends(get_current_user),
    ):
        local_path = get_local_photo_path(payment_id)
        if local_path.is_file():
            return FileResponse(local_path, media_type="image/jpeg")

        async with async_session_maker() as db:
            payment = await get_nakladnoy(db, payment_id)
        if payment is None or not payment.photo_file_id:
            raise HTTPException(status_code=404, detail="Rasm topilmadi")

        bot = get_bot()
        if bot is None:
            raise HTTPException(status_code=404, detail="Telegram rasm yuklab bo'lmadi")
        try:
            tg_file = await bot.get_file(payment.photo_file_id)
            buf = io.BytesIO()
            await bot.download_file(tg_file.file_path, destination=buf)
            data = buf.getvalue()
            if data:
                await asyncio.to_thread(save_local_photo, payment_id, data)
                return Response(content=data, media_type="image/jpeg")
        except Exception as exc:
            raise HTTPException(status_code=404, detail=f"Rasmni yuklab bo'lmadi: {exc}") from exc
        raise HTTPException(status_code=404, detail="Rasm bo'sh")

    @app.patch("/nakladnoy/{payment_id}", response_model=NakladnoyOut)
    async def edit_nakladnoy_endpoint(
        payment_id: int,
        payload: NakladnoyUpdateRequest,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> NakladnoyOut:
        async with async_session_maker() as db:
            if payload.round_amount:
                cur_pay = await get_nakladnoy(db, payment_id)
                if cur_pay is None or cur_pay.status == "deleted":
                    raise HTTPException(status_code=404, detail="Nakladnoy topilmadi")
                r_mode = await get_app_setting(db, "round_mode", "floor_1000")
                if r_mode == "none":
                    r_mode = "floor_1000"
                new_amt = round_nakladnoy_amount(float(cur_pay.amount), r_mode)
                updated = await update_nakladnoy(
                    db,
                    payment_id=payment_id,
                    amount=new_amt,
                    user_id=user.user_id,
                    original_amount=(
                        float(cur_pay.original_amount)
                        if cur_pay.original_amount is not None
                        else float(cur_pay.amount)
                    ),
                )
            else:
                canonical_sup = None
                if payload.supplier_name is not None:
                    canonical_sup, _ = await resolve_supplier_name(db, payload.supplier_name.strip())
                updated = await update_nakladnoy(
                    db,
                    payment_id=payment_id,
                    supplier_name=canonical_sup,
                    amount=payload.amount,
                    note=payload.note,
                    user_id=user.user_id,
                )
            if updated is None:
                raise HTTPException(status_code=404, detail="Nakladnoy topilmadi")
            seq = await get_nakladnoy_session_seq(db, updated)

        sync_existing_group_message(updated, tag="✏️ [TAHRIRLANDI]")
        return _serialize_nakladnoy(updated, session_seq=seq)

    @app.post("/nakladnoy/{payment_id}/payment-method", response_model=NakladnoyOut)
    async def change_nakladnoy_payment_method(
        payment_id: int,
        payload: PaymentMethodRequest,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> NakladnoyOut:
        async with async_session_maker() as db:
            res = await set_nakladnoy_payment_method(
                db,
                payment_id=payment_id,
                payment_method=payload.payment_method,
                user_id=user.user_id,
            )
            if res is None:
                raise HTTPException(status_code=404, detail="Nakladnoy topilmadi")
            updated, _ = res
            seq = await get_nakladnoy_session_seq(db, updated)

        sync_existing_group_message(updated, tag="")
        return _serialize_nakladnoy(updated, session_seq=seq)

    @app.post("/nakladnoy/{payment_id}/debt", response_model=NakladnoyOut)
    async def convert_nakladnoy_to_debt(
        payment_id: int,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> NakladnoyOut:
        async with async_session_maker() as db:
            updated = await mark_nakladnoy_as_debt(db, payment_id=payment_id, user_id=user.user_id)
            if updated is None:
                raise HTTPException(status_code=404, detail="Nakladnoy topilmadi")
            seq = await get_nakladnoy_session_seq(db, updated)

        sync_existing_group_message(updated, tag="📌 [QARZGA O'TKAZILDI]")
        return _serialize_nakladnoy(updated, session_seq=seq)

    @app.post("/nakladnoy/{payment_id}/paid", response_model=NakladnoyOut)
    async def pay_debt_nakladnoy(
        payment_id: int,
        payload: PaymentMethodRequest,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> NakladnoyOut:
        async with async_session_maker() as db:
            res = await mark_nakladnoy_as_paid(
                db,
                payment_id=payment_id,
                user_id=user.user_id,
                payment_method=payload.payment_method,
            )
            if res is None:
                raise HTTPException(status_code=404, detail="Nakladnoy topilmadi")
            updated, _ = res
            seq = await get_nakladnoy_session_seq(db, updated)

        sync_existing_group_message(updated, tag="✅ [QARZ TO'LANDI]")
        return _serialize_nakladnoy(updated, session_seq=seq)

    @app.post("/nakladnoy/{payment_id}/group")
    async def send_nakladnoy_to_group_endpoint(
        payment_id: int,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        ok, msg = await post_nakladnoy_to_telegram_group(payment_id, force=True)
        if not ok:
            raise HTTPException(status_code=400, detail=msg)
        async with async_session_maker() as db:
            updated = await get_nakladnoy(db, payment_id)
            seq = await get_nakladnoy_session_seq(db, updated) if updated else None
        return {
            "ok": True,
            "message": msg,
            "nakladnoy": _serialize_nakladnoy(updated, session_seq=seq) if updated else None,
        }

    @app.delete("/nakladnoy/{payment_id}")
    async def remove_nakladnoy(
        payment_id: int,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        async with async_session_maker() as db:
            deleted = await delete_nakladnoy(db, payment_id=payment_id, user_id=user.user_id)
        if deleted is None:
            raise HTTPException(status_code=404, detail="Nakladnoy topilmadi")
        sync_existing_group_message(deleted, tag="❌ [O'CHIRILDI]")
        return {"ok": True, "deleted_id": payment_id}

    @app.get("/debts")
    async def get_unpaid_debts(
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        async with async_session_maker() as db:
            rows = await list_unpaid_debt_nakladnoys(db)
        items = [_serialize_nakladnoy(pay, report_date=r_date) for pay, r_date in rows]
        total = sum(i.amount for i in items)
        return {"count": len(items), "total_amount": total, "items": items}

    @app.post("/day/close", response_model=DayCloseResponse)
    async def close_day_endpoint(
        payload: DayCloseRequest,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> DayCloseResponse:
        async with async_session_maker() as db:
            open_sess = await get_or_create_open_session(db)
            closed_summary = await close_cash_session(
                db,
                session_id=open_sess.id,
                actual_counted_cash=payload.actual_counted_cash,
            )
            next_sess = await get_or_create_open_session(db)

        return DayCloseResponse(
            closed_session_id=int(closed_summary.session.id),
            report_date=closed_summary.session.report_date,
            expected_cash=float(closed_summary.expected_cash),
            actual_counted_cash=float(closed_summary.session.actual_counted_cash or 0),
            difference=float(closed_summary.session.difference or 0),
            next_session_id=int(next_sess.id),
            next_opening_balance=float(next_sess.opening_balance),
        )

    @app.get("/export/session")
    async def export_current_session_excel(
        session_id: Optional[int] = Query(default=None),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> StreamingResponse:
        async with async_session_maker() as db:
            summary = await compute_session_summary(db, session_id=session_id)
        xlsx_bytes = await asyncio.to_thread(build_session_excel, summary)
        filename = f"Hisobot_{summary.session.report_date}.xlsx"
        return StreamingResponse(
            io.BytesIO(xlsx_bytes),
            media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            headers={"Content-Disposition": f'attachment; filename="{filename}"'},
        )

    @app.get("/export/range")
    async def export_range_excel(
        date_from: str = Query(..., pattern=r"^\d{4}-\d{2}-\d{2}$"),
        date_to: str = Query(..., pattern=r"^\d{4}-\d{2}-\d{2}$"),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> StreamingResponse:
        if date_from > date_to:
            date_from, date_to = date_to, date_from
        async with async_session_maker() as db:
            data = await get_range_report_data(db, date_from, date_to)
        xlsx_bytes = await asyncio.to_thread(build_range_excel, date_from, date_to, data)
        filename = f"Hisobot_{date_from}_{date_to}.xlsx"
        return StreamingResponse(
            io.BytesIO(xlsx_bytes),
            media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            headers={"Content-Disposition": f'attachment; filename="{filename}"'},
        )

    @app.get("/export/sverka")
    async def export_sverka_excel(
        month: Optional[str] = Query(default=None),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> StreamingResponse:
        target_month = (month or today_iso()[:7]).strip()[:7]
        async with async_session_maker() as db:
            rows = await get_supplier_sverka(db, target_month)
        xlsx_bytes = await asyncio.to_thread(build_sverka_excel, target_month, rows)
        filename = f"Sverka_{target_month}.xlsx"
        return StreamingResponse(
            io.BytesIO(xlsx_bytes),
            media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            headers={"Content-Disposition": f'attachment; filename="{filename}"'},
        )

    # -----------------------------------------------------------------------
    # Stage 1: History Sessions, Global Search & Session Reopen
    # -----------------------------------------------------------------------

    @app.get("/history/sessions")
    async def get_history_sessions(
        limit: int = Query(default=25, ge=1, le=60),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        async with async_session_maker() as db:
            sessions = await list_all_sessions(db, limit=limit)
        items = [
            {
                "id": int(s.id),
                "report_date": s.report_date,
                "status": s.status,
                "opening_balance": float(s.opening_balance or 0.0),
                "expected_cash": float(s.expected_cash or 0.0),
                "actual_counted_cash": (
                    float(s.actual_counted_cash) if s.actual_counted_cash is not None else None
                ),
                "difference": float(s.difference) if s.difference is not None else None,
                "closed_at": format_local_dt(s.closed_at, "%Y-%m-%d %H:%M") if s.closed_at else "",
            }
            for s in sessions
        ]
        return {"sessions": items}

    @app.get("/history/sessions/{session_id}", response_model=StatusSummaryResponse)
    async def get_history_session_detail(
        session_id: int,
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> StatusSummaryResponse:
        async with async_session_maker() as db:
            try:
                summary = await compute_session_summary(db, session_id=session_id)
            except ValueError as exc:
                raise HTTPException(status_code=404, detail="Smena topilmadi") from exc
            grp_info = await _load_group_info(db)

        all_naks = sorted(
            [
                *summary.confirmed_nakladnoys,
                *summary.noncash_nakladnoys,
                *summary.debt_nakladnoys,
            ],
            key=lambda x: x.id,
        )
        nak_outs = [
            _serialize_nakladnoy(n, session_seq=idx, report_date=summary.session.report_date)
            for idx, n in enumerate(all_naks, start=1)
        ]
        cash_outs = [_serialize_cash_tx(tx) for tx in summary.cash_transactions]
        return StatusSummaryResponse(
            session_id=int(summary.session.id),
            report_date=summary.session.report_date,
            session_status=summary.session.status,
            opening_balance=float(summary.opening_balance),
            main_cash_in=float(summary.main_cash_in),
            kassa_debt_today=float(summary.kassa_debt_today),
            kassa_repay_today=float(summary.kassa_repay_today),
            total_available_inflow=float(summary.total_available_inflow),
            total_nakladnoy_spent=float(summary.total_nakladnoy_spent),
            total_card_spent=float(summary.total_card_spent),
            total_transfer_spent=float(summary.total_transfer_spent),
            total_debt_nakladnoy=float(summary.total_debt_nakladnoy),
            expected_cash=float(summary.expected_cash),
            total_kassa_debt_outstanding=float(summary.total_kassa_debt_outstanding),
            all_unpaid_debt_count=int(summary.all_unpaid_debt_count),
            all_unpaid_debt_total=float(summary.all_unpaid_debt_total),
            group_info=grp_info,
            cash_transactions=cash_outs,
            nakladnoys=nak_outs,
        )

    @app.post("/history/sessions/{session_id}/reopen")
    async def reopen_history_session_endpoint(
        session_id: int,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        async with async_session_maker() as db:
            reopened = await reopen_cash_session(db, session_id=session_id)
            if reopened is None:
                raise HTTPException(status_code=404, detail="Smena topilmadi")
        return {
            "ok": True,
            "session_id": int(reopened.id),
            "report_date": reopened.report_date,
            "status": reopened.status,
        }

    @app.get("/history/search")
    async def search_history_nakladnoys(
        q: str = Query(..., min_length=1),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        async with async_session_maker() as db:
            rows = await search_nakladnoys(db, q.strip(), limit=40)
        items = [_serialize_nakladnoy(pay, report_date=r_date) for pay, r_date in rows]
        return {"query": q.strip(), "count": len(items), "items": items}

    # -----------------------------------------------------------------------
    # Stage 2: In-App Live Sverka & Period Statistics
    # -----------------------------------------------------------------------

    @app.get("/stats/period")
    async def get_period_stats_endpoint(
        days: int = Query(default=7, ge=1, le=365),
        date_from: Optional[str] = Query(default=None),
        date_to: Optional[str] = Query(default=None),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        d_to = (date_to or today_iso()).strip()
        d_from = (
            date_from.strip()
            if date_from
            else (now_local() - timedelta(days=max(days - 1, 0))).strftime("%Y-%m-%d")
        )
        if d_from > d_to:
            d_from, d_to = d_to, d_from
        async with async_session_maker() as db:
            st = await get_period_statistics(db, d_from, d_to)
        top_sups = [
            {"supplier": name, "count": int(cnt), "total": float(tot), "percent": float(pct)}
            for name, cnt, tot, pct in st.get("top_suppliers", [])
        ]
        busiest = st.get("busiest_day")
        return {
            "date_from": st["date_from"],
            "date_to": st["date_to"],
            "total_spent": float(st["total_spent"]),
            "cash_spent": float(st.get("cash_spent", 0.0)),
            "card_spent": float(st.get("card_spent", 0.0)),
            "transfer_spent": float(st.get("transfer_spent", 0.0)),
            "cash_count": int(st.get("cash_count", 0)),
            "card_count": int(st.get("card_count", 0)),
            "transfer_count": int(st.get("transfer_count", 0)),
            "payment_count": int(st["payment_count"]),
            "active_days": int(st["active_days"]),
            "avg_daily_spend": float(st["avg_daily_spend"]),
            "avg_payment": float(st["avg_payment"]),
            "total_cash_in": float(st.get("total_cash_in", 0.0)),
            "kassa_borrowed": float(st.get("kassa_borrowed", 0.0)),
            "kassa_repaid": float(st.get("kassa_repaid", 0.0)),
            "busiest_day_date": busiest[0] if busiest else None,
            "busiest_day_total": float(busiest[1]) if busiest else 0.0,
            "top_suppliers": top_sups,
            "daily_series": st.get("daily_series", []),
        }

    @app.get("/sverka")
    async def get_live_sverka_endpoint(
        month: Optional[str] = Query(default=None),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        target_month = (month or today_iso()[:7]).strip()[:7]
        async with async_session_maker() as db:
            rows = await get_supplier_sverka(db, target_month)

        by_sup: dict[str, dict] = {}
        for r in rows:
            sup = r["supplier"]
            key = sup.lower()
            entry = by_sup.setdefault(
                key,
                {
                    "supplier": sup,
                    "count": 0,
                    "total": 0.0,
                    "cash_total": 0.0,
                    "card_total": 0.0,
                    "transfer_total": 0.0,
                },
            )
            amt = float(r["amount"])
            pm = (r.get("payment_method") or "cash").lower()
            entry["count"] += 1
            entry["total"] += amt
            if pm == "card":
                entry["card_total"] += amt
            elif pm == "transfer":
                entry["transfer_total"] += amt
            else:
                entry["cash_total"] += amt

        ranked = sorted(by_sup.values(), key=lambda x: -x["total"])
        grand_total = sum(x["total"] for x in ranked)
        return {
            "month": target_month,
            "supplier_count": len(ranked),
            "payment_count": len(rows),
            "grand_total": grand_total,
            "suppliers": ranked,
        }

    # -----------------------------------------------------------------------
    # Stage 3: Attach / Replace Photo on Existing Nakladnoy
    # -----------------------------------------------------------------------

    @app.post("/nakladnoy/{payment_id}/photo", response_model=NakladnoyOut)
    async def attach_nakladnoy_photo(
        payment_id: int,
        photo: UploadFile = File(...),
        send_to_group: bool = Form(default=True),
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> NakladnoyOut:
        raw = await photo.read()
        if not raw:
            raise HTTPException(status_code=400, detail="Rasm bo'sh")
        if len(raw) > 15 * 1024 * 1024:
            raise HTTPException(status_code=400, detail="Rasm 15 MB dan oshmasligi kerak")

        async with async_session_maker() as db:
            payment = await get_nakladnoy(db, payment_id)
            if payment is None or payment.status == "deleted":
                raise HTTPException(status_code=404, detail="Nakladnoy topilmadi")

        await asyncio.to_thread(save_local_photo, payment_id, raw)

        if send_to_group:
            await post_nakladnoy_to_telegram_group(
                payment_id,
                photo_bytes=raw,
                force=False,
                replace_photo=True,
            )

        async with async_session_maker() as db:
            refreshed = await get_nakladnoy(db, payment_id)
            seq = await get_nakladnoy_session_seq(db, refreshed) if refreshed else None
        if refreshed is None:
            raise HTTPException(status_code=404, detail="Nakladnoy topilmadi")
        return _serialize_nakladnoy(refreshed, session_seq=seq)

    # -----------------------------------------------------------------------
    # Stage 4: Nasiya Ledger (/nasiya) & Prixod (ITOG 👑)
    # -----------------------------------------------------------------------

    @app.get("/nasiya")
    async def get_nasiya_overview(
        supplier: Optional[str] = Query(default=None),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        async with async_session_maker() as db:
            balances = await get_supplier_debt_balances(db)
            entries = await list_supplier_debt_entries(
                db, supplier_name=supplier.strip() if supplier else None, limit=35
            )
        total_balance = sum(float(b["balance"]) for b in balances)
        return {
            "total_balance": total_balance,
            "balances": [
                {
                    "supplier": b["supplier"],
                    "debt": float(b["debt"]),
                    "paid": float(b["paid"]),
                    "balance": float(b["balance"]),
                }
                for b in balances
            ],
            "entries": [
                {
                    "id": int(e.id),
                    "supplier_name": e.supplier_name,
                    "entry_type": e.entry_type,
                    "amount": float(e.amount),
                    "note": e.note or "",
                    "created_at": format_local_dt(e.created_at, "%Y-%m-%d %H:%M"),
                }
                for e in entries
            ],
        }

    @app.post("/nasiya")
    async def create_nasiya_entry(
        payload: NasiyaCreateRequest,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        async with async_session_maker() as db:
            entry = await add_supplier_debt(
                db,
                supplier_name=payload.supplier_name,
                entry_type=payload.entry_type,
                amount=payload.amount,
                note=payload.note,
                user_id=user.user_id,
            )
        return {
            "id": int(entry.id),
            "supplier_name": entry.supplier_name,
            "entry_type": entry.entry_type,
            "amount": float(entry.amount),
            "note": entry.note or "",
            "created_at": format_local_dt(entry.created_at, "%Y-%m-%d %H:%M"),
        }

    @app.delete("/nasiya/{entry_id}")
    async def remove_nasiya_entry(
        entry_id: int,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        async with async_session_maker() as db:
            deleted = await delete_supplier_debt(db, entry_id=entry_id, user_id=user.user_id)
        if deleted is None:
            raise HTTPException(status_code=404, detail="Nasiya yozuvi topilmadi")
        return {"ok": True, "deleted_id": entry_id}

    def _serialize_prixod(rep) -> dict:
        loaded_rows = rep.__dict__.get("rows") if hasattr(rep, "__dict__") else None
        return {
            "id": int(rep.id),
            "report_date": rep.report_date,
            "total_cost": float(rep.total_cost or 0.0),
            "total_price": float(rep.total_price or 0.0),
            "formatted_text": rep.formatted_text or "",
            "status": rep.status,
            "in_group": bool(rep.group_chat_id and rep.group_message_id),
            "row_count": len(loaded_rows) if loaded_rows is not None else 0,
            "created_at": format_local_dt(rep.created_at, "%Y-%m-%d %H:%M"),
        }

    @app.get("/prixod")
    async def get_prixod_list(
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        async with async_session_maker() as db:
            reports = await list_prixod_reports(db, limit=15)
        return {"items": [_serialize_prixod(r) for r in reports]}

    @app.post("/prixod/text")
    async def create_prixod_from_text(
        payload: PrixodTextCreateRequest,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        async with async_session_maker() as db:
            suppliers = await list_suppliers(db, active_only=True)
            try:
                parsed = parse_manual_itog_text(payload.text.strip(), suppliers)
            except Exception as exc:
                raise HTTPException(
                    status_code=400, detail=f"Matnni tushunib bo'lmadi: {exc}"
                ) from exc
            rows_data = [
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
                for r in parsed.rows
            ]
            report = await save_prixod_report(
                db,
                report_date=parsed.report_date,
                total_cost=parsed.total_cost,
                total_price=parsed.total_price,
                formatted_text=parsed.formatted_text,
                rows_data=rows_data,
            )

        published = False
        pub_msg = "Bazaga saqlandi"
        if payload.publish_to_group:
            published, pub_msg, report = await _publish_prixod_to_group(report.id)

        return {
            "report": _serialize_prixod(report),
            "published": published,
            "message": pub_msg,
        }

    async def _publish_prixod_to_group(report_id: int):
        bot = get_bot()
        async with async_session_maker() as db:
            rep = await get_prixod_report(db, report_id)
            if rep is None:
                raise HTTPException(status_code=404, detail="Prixod hisoboti topilmadi")
            grp = await get_group_config(db, "prixod")
        if grp is None or not grp.chat_id:
            return False, "Prixod guruhi bog'lanmagan (/set_prixod_group)", rep
        if bot is None:
            return False, "Telegram bot ulanmagan", rep
        try:
            text_html = f"<pre>{html.escape(rep.formatted_text)}</pre>"
            if rep.group_chat_id and rep.group_message_id:
                await bot.edit_message_text(
                    chat_id=rep.group_chat_id,
                    message_id=rep.group_message_id,
                    text=text_html,
                    parse_mode="HTML",
                )
                msg_id = rep.group_message_id
                chat_id = rep.group_chat_id
            else:
                sent = await bot.send_message(
                    chat_id=grp.chat_id,
                    text=text_html,
                    parse_mode="HTML",
                )
                msg_id = sent.message_id
                chat_id = grp.chat_id
            async with async_session_maker() as db:
                updated = await mark_prixod_published(
                    db,
                    report_id=rep.id,
                    formatted_text=rep.formatted_text,
                    group_chat_id=chat_id,
                    group_message_id=msg_id,
                )
            return True, f"Prixod guruhiga yuborildi ({grp.title or grp.chat_id})", updated or rep
        except Exception as exc:
            return False, f"Guruhga yuborishda xatolik: {exc}", rep

    @app.post("/prixod/{report_id}/publish")
    async def publish_prixod_endpoint(
        report_id: int,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        ok, msg, rep = await _publish_prixod_to_group(report_id)
        if not ok:
            raise HTTPException(status_code=400, detail=msg)
        return {"ok": True, "message": msg, "report": _serialize_prixod(rep)}

    @app.post("/prixod/file")
    async def create_prixod_from_file(
        file: UploadFile = File(...),
        publish_to_group: bool = Form(default=False),
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        raw = await file.read()
        if not raw:
            raise HTTPException(status_code=400, detail="Fayl bo'sh")
        async with async_session_maker() as db:
            suppliers = await list_suppliers(db, active_only=True)
            try:
                parsed = parse_yespos_table(raw, file.filename or "yespos.xlsx", suppliers)
            except Exception as exc:
                raise HTTPException(
                    status_code=400, detail=f"Faylni tahlil qilib bo'lmadi: {exc}"
                ) from exc
            rows_data = [
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
                for r in parsed.rows
            ]
            report = await save_prixod_report(
                db,
                report_date=parsed.report_date,
                total_cost=parsed.total_cost,
                total_price=parsed.total_price,
                formatted_text=parsed.formatted_text,
                rows_data=rows_data,
            )

        published = False
        pub_msg = "Fayldan ITOG 👑 yaratildi va bazaga saqlandi"
        if publish_to_group:
            published, pub_msg, report = await _publish_prixod_to_group(report.id)

        return {
            "report": _serialize_prixod(report),
            "published": published,
            "message": pub_msg,
        }

    # -----------------------------------------------------------------------
    # Suppliers & AI Rounding Settings Management (/settings/...)
    # -----------------------------------------------------------------------

    @app.get("/settings/suppliers")
    async def get_supplier_configs_endpoint(
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        async with async_session_maker() as db:
            cfgs = await list_suppliers(db, active_only=True)
            all_known = await get_all_known_suppliers(db)
        return {
            "configs": [
                {
                    "id": int(c.id),
                    "order_num": int(c.order_num),
                    "display_name": c.display_name,
                    "aliases": c.aliases or "",
                    "default_category": c.default_category or "qarz",
                }
                for c in cfgs
            ],
            "all_known": all_known,
        }

    @app.post("/settings/suppliers")
    async def save_supplier_config_endpoint(
        payload: SupplierConfigCreateRequest,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        async with async_session_maker() as db:
            cfg = await add_or_update_supplier(
                db,
                display_name=payload.display_name.strip(),
                aliases=payload.aliases.strip(),
                default_category=payload.default_category.strip() or "qarz",
            )
        return {
            "id": int(cfg.id),
            "order_num": int(cfg.order_num),
            "display_name": cfg.display_name,
            "aliases": cfg.aliases or "",
            "default_category": cfg.default_category or "qarz",
        }

    @app.delete("/settings/suppliers/{supplier_id}")
    async def delete_supplier_config_endpoint(
        supplier_id: int,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        async with async_session_maker() as db:
            ok = await delete_supplier(db, supplier_id=supplier_id)
        if not ok:
            raise HTTPException(status_code=404, detail="Postavshik topilmadi")
        return {"ok": True, "deleted_id": supplier_id}

    @app.get("/settings/round-mode")
    async def get_round_mode_endpoint(
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        async with async_session_maker() as db:
            mode = await get_app_setting(db, "round_mode", "floor_1000")
        return {"round_mode": mode}

    @app.post("/settings/round-mode")
    async def update_round_mode_endpoint(
        payload: RoundModeUpdateRequest,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        async with async_session_maker() as db:
            await set_app_setting(db, "round_mode", payload.round_mode)
        return {"ok": True, "round_mode": payload.round_mode}

    return app
