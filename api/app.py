"""FastAPI application providing mobile APK endpoints sharing the bot database and Telegram group."""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
import html
import io
import json
import mimetypes
from typing import Optional

from aiogram.types import BufferedInputFile
from fastapi import Depends, FastAPI, File, Form, HTTPException, Query, Request, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse, Response, StreamingResponse
from sqlalchemy import desc, func, select
from sqlalchemy.exc import IntegrityError

mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/javascript", ".mjs")
mimetypes.add_type("font/otf", ".otf")
mimetypes.add_type("font/ttf", ".ttf")

from api.auth import (
    AuthenticatedUser,
    check_rate_limit,
    consume_login_code,
    extract_client_ip,
    get_current_user,
    issue_api_token,
    issue_webapp_token,
    require_write_user,
    revoke_raw_token,
    verify_telegram_webapp_init_data,
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
    BotPrefsUpdateRequest,
    CashCreateRequest,
    CashReconciliationCreateRequest,
    CashReconciliationOut,
    CashTxOut,
    CashUpdateRequest,
    DayCloseRequest,
    DayCloseResponse,
    ExcelSendTelegramRequest,
    GroupBindRequest,
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
    SupplierAliasesUpdateRequest,
    SupplierConfigCreateRequest,
    SupplierMergeRequest,
    SupplierSplitRequest,
    TelegramWebAppAuthRequest,
    UserProfileResponse,
    UserRoleSaveRequest,
)
from bot.auth import (
    ROLE_ADMIN,
    ROLE_LABELS,
    can_write_role,
    get_user_role,
    is_admin_role,
    is_webapp_allowed,
    refresh_role_cache,
)
from bot.keyboards import build_add_to_group_url
from config import BASE_DIR, get_settings
from database.crud import (
    add_cash_transaction,
    add_or_update_supplier,
    add_supplier_debt,
    close_cash_session,
    compute_session_summary,
    confirm_nakladnoy,
    create_cash_reconciliation,
    create_pending_nakladnoy,
    delete_cash_reconciliation,
    delete_cash_transaction,
    delete_group_config,
    delete_nakladnoy,
    delete_supplier,
    delete_supplier_debt,
    delete_user_role,
    effective_tx_local_date,
    find_duplicate_supplier_groups,
    find_similar_suppliers,
    format_local_dt,
    get_ai_usage_stats,
    get_all_group_configs,
    get_all_known_suppliers,
    get_app_setting,
    get_cash_reconciliations_report,
    get_group_config,
    get_kassa_debt_stats,
    get_nakladnoy,
    get_nakladnoy_session_seq,
    get_or_create_open_session,
    get_period_statistics,
    get_prixod_report,
    get_range_report_data,
    get_recent_amounts_for_supplier,
    get_supplier_aliases_map,
    get_supplier_debt_balances,
    get_supplier_sverka,
    list_all_sessions,
    list_cash_reconciliations,
    list_prixod_reports,
    list_recent_cash_transactions,
    list_recent_nakladnoys,
    list_supplier_debt_entries,
    list_supplier_merge_logs,
    list_suppliers,
    list_unpaid_debt_nakladnoys,
    list_user_roles,
    mark_nakladnoy_as_debt,
    mark_nakladnoy_as_paid,
    mark_prixod_published,
    merge_suppliers,
    normalize_payment_method,
    now_local,
    reopen_cash_session,
    resolve_supplier_name,
    restore_cash_transaction,
    restore_nakladnoy,
    round_nakladnoy_amount,
    save_prixod_report,
    search_nakladnoys,
    set_app_setting,
    set_group_config,
    set_nakladnoy_payment_method,
    set_user_role,
    split_supplier,
    today_iso,
    undo_supplier_merge,
    update_cash_transaction,
    update_nakladnoy,
    update_supplier_aliases,
)
from database.models import (
    ApiIdempotencyRecord,
    CashReconciliation,
    CashTransaction,
    DailyCashSession,
    NakladnoyPayment,
)
from database.session import async_session_maker
from database.sync_state import get_sync_snapshot
from services.backup import send_backup
from services.excel_export import build_range_excel, build_session_excel, build_sverka_excel
from services.gemini_ai import extract_nakladnoy_from_image, parse_voice_or_text
from services.pdf_sverka import generate_supplier_sverka_pdf
from services.prixod_parser import parse_manual_itog_text, parse_yespos_table

WEBAPP_DIR = BASE_DIR / "data" / "webapp"
_WEBAPP_NO_CACHE_FILES = {
    "index.html",
    "flutter_bootstrap.js",
    "version.json",
    "manifest.json",
    "flutter_service_worker.js",
    "precache_manifest.json",
}
_WEBAPP_NO_CACHE_HEADERS = {"Cache-Control": "no-cache, no-store, must-revalidate"}
_WEBAPP_STATIC_CACHE_HEADERS = {"Cache-Control": "public, max-age=86400"}


def _reconciliation_to_out(rec: CashReconciliation, report_date: str) -> CashReconciliationOut:
    return CashReconciliationOut(
        id=int(rec.id),
        session_id=int(rec.session_id),
        report_date=report_date,
        kind=rec.kind,
        opening_balance=float(getattr(rec, "opening_balance", 0.0) or 0.0),
        cash_in_total=float(getattr(rec, "cash_in_total", 0.0) or 0.0),
        cash_out_total=float(getattr(rec, "cash_out_total", 0.0) or 0.0),
        expected_cash=float(rec.expected_cash),
        counted_cash=float(rec.counted_cash),
        difference=float(rec.difference),
        note=rec.note or "",
        created_at=format_local_dt(rec.created_at, "%Y-%m-%d %H:%M"),
        time_hm=format_local_dt(rec.created_at, "%H:%M"),
    )


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
    session_status: str = "open",
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
        session_status=session_status,
    )


async def _batch_session_statuses(db, payments: list[NakladnoyPayment]) -> dict[int, str]:
    """Batch-fetch DailyCashSession.status keyed by session_id for serialized nakladnoys."""
    sids = {int(p.session_id) for p in payments if getattr(p, "session_id", None) is not None}
    if not sids:
        return {}
    rows = (
        await db.execute(
            select(DailyCashSession.id, DailyCashSession.status).where(
                DailyCashSession.id.in_(sids)
            )
        )
    ).all()
    return {int(sid): str(st or "open") for sid, st in rows}


async def _assert_payment_editable(db, payment_id: int, allow_if_debt: bool = False) -> NakladnoyPayment:
    """Ensure payment exists, is not deleted, and does not belong to a closed session."""
    pay = await get_nakladnoy(db, payment_id)
    if pay is None or pay.status == "deleted":
        raise HTTPException(status_code=404, detail="Nakladnoy topilmadi")
    sess = await db.get(DailyCashSession, pay.session_id)
    if sess is not None and sess.status == "closed":
        if not (allow_if_debt and bool(getattr(pay, "is_debt", False))):
            raise HTTPException(
                status_code=400,
                detail="Yopilgan kunning nakladnoyini tahrirlash yoki o'chirish mumkin emas (faqat ko'rish rejimi)",
            )
    return pay


async def _assert_cash_tx_editable(db, tx_id: int) -> None:
    """Ensure cash transaction exists and does not belong to a closed session."""
    tx = await db.get(CashTransaction, tx_id)
    if tx is None or getattr(tx, "is_deleted", False):
        raise HTTPException(status_code=404, detail="Kassa amali topilmadi")
    sess = await db.get(DailyCashSession, tx.session_id)
    if sess is not None and sess.status == "closed":
        raise HTTPException(
            status_code=400,
            detail="Yopilgan smenadagi kassa amalini o'zgartirish mumkin emas",
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


_GROUP_ROLES: tuple[tuple[str, str], ...] = (
    ("nakladnoy", "📸 Nakladnoy guruhi"),
    ("prixod", "👑 Prixod (ITOG) guruhi"),
    ("kassa", "💰 Kassa / Rahbariyat guruhi"),
)
_GROUP_ROLE_TITLES = dict(_GROUP_ROLES)


def _require_admin_user(user: AuthenticatedUser) -> None:
    if not user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Ushbu bo'lim faqat admin huquqiga ega foydalanuvchi uchun.",
        )


def _compute_supplier_anomaly(
    amount: Optional[float], recent_amounts: list[float]
) -> Optional[str]:
    """Return a concise Uzbek warning if amount spikes >=1.75x above supplier's recent average."""
    if amount is None or amount <= 0 or len(recent_amounts) < 2:
        return None
    valid = [float(x) for x in recent_amounts if float(x) > 0]
    if len(valid) < 2:
        return None
    avg = sum(valid) / len(valid)
    if avg <= 0:
        return None
    if amount >= avg * 1.75 and (amount - avg) >= 150_000:
        pct = int(round((amount / avg - 1.0) * 100))
        avg_str = f"{int(round(avg)):,}".replace(",", " ")
        return f"Odatdagidan +{pct}% ko'p (o'rtacha {avg_str} so'm)"
    return None


def create_api_app() -> FastAPI:
    """Create and configure the FastAPI application for Hisobot Mobile APK."""
    app = FastAPI(
        title="Hisobchi Mobile API",
        version="1.0.0",
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
    )
    public_url = (get_settings().API_PUBLIC_URL or "").strip().rstrip("/")
    allowed_origins = [
        "https://hisobchi.okaposai.uz",
        "https://web.telegram.org",
        "https://webk.telegram.org",
        "https://webz.telegram.org",
        "http://localhost:8088",
        "http://127.0.0.1:8088",
    ]
    if public_url and public_url not in allowed_origins:
        allowed_origins.append(public_url)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=allowed_origins,
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "Accept", "X-Idempotency-Key"],
    )
    app.add_middleware(GZipMiddleware, minimum_size=1024)

    @app.middleware("http")
    async def _security_headers_middleware(request: Request, call_next):
        response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        response.headers.setdefault("Permissions-Policy", "geolocation=(), payment=(), usb=()")
        response.headers.setdefault(
            "Strict-Transport-Security", "max-age=31536000; includeSubDomains"
        )
        if not request.url.path.startswith("/webapp"):
            response.headers.setdefault("X-Frame-Options", "DENY")
        return response

    cached_bot_username: Optional[str] = None
    idempotency_locks: dict[str, asyncio.Lock] = {}
    user_create_locks: dict[int, asyncio.Lock] = {}
    prixod_publish_locks: dict[int, asyncio.Lock] = {}

    def _get_lock(pool: dict, key) -> asyncio.Lock:
        lock = pool.get(key)
        if lock is None:
            if len(pool) > 2048:
                pool.clear()
            lock = asyncio.Lock()
            pool[key] = lock
        return lock

    def _extract_idempotency_key(
        request: Optional[Request],
        form_key: Optional[str] = None,
    ) -> Optional[str]:
        raw = ""
        if request is not None:
            raw = (request.headers.get("x-idempotency-key") or "").strip()
        if not raw and form_key:
            raw = form_key.strip()
        if not raw:
            return None
        return raw[:120]

    async def _execute_idempotent(
        scope: str,
        user_id: int,
        raw_key: Optional[str],
        fn,
    ) -> dict:
        if not raw_key:
            return await fn()
        composite_key = f"{scope}:{int(user_id)}:{raw_key}"[:160]
        async with _get_lock(idempotency_locks, composite_key):
            async with async_session_maker() as db:
                existing = await db.get(ApiIdempotencyRecord, composite_key)
                if existing is not None:
                    return json.loads(existing.response_json)
            result = await fn()
            payload_str = json.dumps(result, ensure_ascii=False)
            async with async_session_maker() as db:
                existing = await db.get(ApiIdempotencyRecord, composite_key)
                if existing is None:
                    db.add(
                        ApiIdempotencyRecord(
                            key=composite_key,
                            endpoint=scope,
                            user_id=int(user_id),
                            response_json=payload_str,
                        )
                    )
                    try:
                        await db.commit()
                    except IntegrityError:
                        await db.rollback()
            return result

    async def _resolve_bot_username() -> str:
        nonlocal cached_bot_username
        if cached_bot_username:
            return cached_bot_username
        bot = get_bot()
        if bot is not None and hasattr(bot, "get_me"):
            try:
                me = await bot.get_me()
                uname = (getattr(me, "username", None) or "").strip().lstrip("@")
                if uname:
                    cached_bot_username = uname
                    return uname
            except Exception:
                pass
        return "hisobchi_my_own_bot"

    @app.get("/health")
    async def health() -> dict:
        meta = get_apk_version_metadata()
        return {
            "status": "ok",
            "service": "hisobchi-api",
            "apk_version": meta["version"],
            "apk_build": meta["build"],
            "bot_username": await _resolve_bot_username(),
        }

    @app.get("/apk/version")
    async def get_apk_version() -> dict:
        meta = get_apk_version_metadata()
        return {
            **meta,
            "download_path": "/download/hisobchi.apk",
        }

    def _compute_web_version() -> str:
        bootstrap = WEBAPP_DIR / "flutter_bootstrap.js"
        try:
            st = bootstrap.stat()
            return f"{int(st.st_mtime_ns)}-{int(st.st_size)}"
        except OSError:
            return ""

    @app.get("/sync/version")
    async def get_sync_version(
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> JSONResponse:
        snap = get_sync_snapshot()
        meta = get_apk_version_metadata()
        payload = {
            **snap,
            "apk_version": meta["version"],
            "apk_build": meta["build"],
            "web_version": _compute_web_version(),
        }
        return JSONResponse(
            content=payload,
            headers={"Cache-Control": "no-cache, no-store, must-revalidate"},
        )

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

    def _webapp_file_response(rel_path: str) -> FileResponse:
        webapp_root = WEBAPP_DIR.resolve()
        clean_rel = (rel_path or "").lstrip("/")
        if not clean_rel:
            clean_rel = "index.html"
        target = (webapp_root / clean_rel).resolve()
        if not target.is_relative_to(webapp_root) or not target.is_file():
            raise HTTPException(status_code=404, detail="Mini App fayli topilmadi")
        media_type, _ = mimetypes.guess_type(str(target))
        if target.suffix.lower() == ".html":
            media_type = "text/html; charset=utf-8"
        elif target.suffix.lower() == ".js":
            media_type = "application/javascript; charset=utf-8"
        elif target.suffix.lower() == ".css":
            media_type = "text/css; charset=utf-8"
        elif target.suffix.lower() == ".json":
            media_type = "application/json; charset=utf-8"
        headers = (
            _WEBAPP_NO_CACHE_HEADERS
            if clean_rel in _WEBAPP_NO_CACHE_FILES
            else _WEBAPP_STATIC_CACHE_HEADERS
        )
        return FileResponse(
            target,
            media_type=media_type or "application/octet-stream",
            headers=headers,
        )

    @app.get("/webapp", include_in_schema=False)
    async def redirect_webapp_root():
        return RedirectResponse(url="/webapp/", status_code=302)

    @app.get("/webapp/", include_in_schema=False)
    async def serve_webapp_index():
        return _webapp_file_response("index.html")

    @app.get("/webapp/{asset_path:path}", include_in_schema=False)
    async def serve_webapp_asset(asset_path: str):
        return _webapp_file_response(asset_path)

    @app.post("/auth/login", response_model=LoginResponse)
    async def auth_login(payload: LoginRequest, request: Request) -> LoginResponse:
        client_ip = extract_client_ip(request)
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

    @app.post("/auth/telegram-webapp", response_model=LoginResponse)
    async def auth_telegram_webapp(
        payload: TelegramWebAppAuthRequest,
        request: Request,
    ) -> LoginResponse:
        check_rate_limit("webapp_auth", extract_client_ip(request), max_hits=20, window_seconds=300)
        tg_user = verify_telegram_webapp_init_data(
            payload.init_data, get_settings().BOT_TOKEN
        )
        user_id = int(tg_user["user_id"])
        if not is_webapp_allowed(user_id):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="🔒 Mini App hozircha faqat asosiy admin uchun ochiq.",
            )
        role = get_user_role(user_id) or ROLE_ADMIN
        async with async_session_maker() as db:
            raw_token, _ = await issue_webapp_token(
                db, user_id=user_id, device_name="Telegram Mini App"
            )
        return LoginResponse(
            access_token=raw_token,
            user_id=user_id,
            role=role,
            can_write=True,
            is_admin=True,
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
            _serialize_nakladnoy(
                n,
                session_seq=idx,
                report_date=effective_tx_local_date(n.paid_at or n.created_at, summary.session),
                session_status=summary.session.status,
            )
            for idx, n in enumerate(all_naks, start=1)
        ]
        cash_outs = [_serialize_cash_tx(tx) for tx in summary.cash_transactions]

        return StatusSummaryResponse(
            session_id=int(summary.session.id),
            report_date=summary.session.report_date,
            session_status=summary.session.status,
            opened_at=(
                format_local_dt(summary.session.created_at, "%Y-%m-%d %H:%M")
                if summary.session.created_at
                else ""
            ),
            closed_at=(
                format_local_dt(summary.session.closed_at, "%Y-%m-%d %H:%M")
                if summary.session.closed_at
                else ""
            ),
            opening_balance=float(summary.opening_balance),
            main_cash_in=float(summary.main_cash_in),
            main_return_today=float(getattr(summary, "main_return_today", 0.0)),
            kassa_debt_today=float(summary.kassa_debt_today),
            kassa_repay_today=float(summary.kassa_repay_today),
            expense_today=float(summary.expense_today),
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
        request: Request,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> CashTxOut:
        idem_key = _extract_idempotency_key(request)

        async def _op() -> dict:
            async with _get_lock(user_create_locks, int(user.user_id)):
                async with async_session_maker() as db:
                    # Rapid double-tap / retry fallback guard when X-Idempotency-Key is absent
                    if not idem_key:
                        open_sess = await get_or_create_open_session(db)
                        recent = await db.scalar(
                            select(CashTransaction)
                            .where(
                                CashTransaction.session_id == open_sess.id,
                                CashTransaction.is_deleted.is_(False),
                            )
                            .order_by(desc(CashTransaction.id))
                            .limit(1)
                        )
                        if recent is not None and recent.created_at is not None:
                            created_naive = recent.created_at.replace(tzinfo=None)
                            now_naive = datetime.now(timezone.utc).replace(tzinfo=None)
                            age_sec = (now_naive - created_naive).total_seconds()
                            if (
                                0 <= age_sec <= 30.0
                                and recent.source_type == payload.source_type
                                and abs(float(recent.amount) - float(payload.amount)) < 0.5
                                and (recent.note or "").strip() == (payload.note or "").strip()
                            ):
                                return _serialize_cash_tx(recent).model_dump()

                    tx = await add_cash_transaction(
                        db,
                        amount=payload.amount,
                        source_type=payload.source_type,
                        note=payload.note,
                    )
                    return _serialize_cash_tx(tx).model_dump()

        data = await _execute_idempotent("cash", user.user_id, idem_key, _op)
        return CashTxOut.model_validate(data)

    @app.patch("/cash/{tx_id}", response_model=CashTxOut)
    async def edit_cash(
        tx_id: int,
        payload: CashUpdateRequest,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> CashTxOut:
        async with async_session_maker() as db:
            await _assert_cash_tx_editable(db, tx_id)
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
            await _assert_cash_tx_editable(db, tx_id)
            tx = await delete_cash_transaction(db, tx_id=tx_id, user_id=user.user_id)
        if tx is None:
            raise HTTPException(status_code=404, detail="Kassa amali topilmadi")
        return {"ok": True, "deleted_id": tx_id}

    @app.post("/cash/{tx_id}/restore", response_model=CashTxOut)
    async def restore_cash_endpoint(
        tx_id: int,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> CashTxOut:
        async with async_session_maker() as db:
            tx = await restore_cash_transaction(db, tx_id=tx_id, user_id=user.user_id)
        if tx is None:
            raise HTTPException(status_code=404, detail="Kassa amali topilmadi")
        return _serialize_cash_tx(tx)

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

    @app.get("/suppliers/directory")
    async def get_suppliers_directory_endpoint(
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        from database.crud import _cyr_to_lat, _norm_key, _supplier_alias_lookup

        async with async_session_maker() as db:
            stmt = (
                select(NakladnoyPayment, DailyCashSession)
                .join(DailyCashSession, DailyCashSession.id == NakladnoyPayment.session_id)
                .where(NakladnoyPayment.status == "confirmed")
                .order_by(NakladnoyPayment.id.desc())
            )
            rows = (await db.execute(stmt)).all()
            nasiya_rows = await get_supplier_debt_balances(db)
            configured = await list_suppliers(db, active_only=True)
            alias_lookup = await _supplier_alias_lookup(db)
            aliases_map = await get_supplier_aliases_map(db)
            duplicate_groups = await find_duplicate_supplier_groups(db)

        buckets: dict[str, dict] = {}

        def _canonical_for(raw: str) -> str:
            clean = " ".join((raw or "").strip().split())
            if not clean:
                return ""
            nk = _norm_key(clean)
            if nk in alias_lookup:
                return alias_lookup[nk]
            lat = _cyr_to_lat(clean)
            if len(lat) >= 2 and lat in alias_lookup:
                return alias_lookup[lat]
            return clean

        def _ensure_bucket(raw_name: str) -> dict:
            canon = _canonical_for(raw_name)
            key = _norm_key(canon)
            entry = buckets.get(key)
            if entry is None:
                entry = {
                    "supplier_name": canon,
                    "aliases": list(aliases_map.get(key, [])),
                    "total_count": 0,
                    "total_amount": 0.0,
                    "cash_amount": 0.0,
                    "card_amount": 0.0,
                    "transfer_amount": 0.0,
                    "unpaid_debt_count": 0,
                    "unpaid_debt_amount": 0.0,
                    "nasiya_balance": 0.0,
                    "first_date": None,
                    "last_date": None,
                }
                buckets[key] = entry
            return entry

        for cfg in configured:
            if cfg.display_name and cfg.display_name.strip():
                _ensure_bucket(cfg.display_name.strip())

        for pay, sess in rows:
            raw_name = (pay.supplier_name or "").strip()
            if not raw_name:
                continue
            b = _ensure_bucket(raw_name)
            amt = float(pay.amount or 0.0)
            b["total_count"] += 1
            b["total_amount"] += amt
            rdate = getattr(sess, "report_date", None)
            if rdate:
                rdate_s = str(rdate)
                if b["first_date"] is None or rdate_s < b["first_date"]:
                    b["first_date"] = rdate_s
                if b["last_date"] is None or rdate_s > b["last_date"]:
                    b["last_date"] = rdate_s
            if bool(getattr(pay, "is_debt", False)):
                b["unpaid_debt_count"] += 1
                b["unpaid_debt_amount"] += amt
            else:
                pm = normalize_payment_method(getattr(pay, "payment_method", "cash"))
                if pm == "card":
                    b["card_amount"] += amt
                elif pm == "transfer":
                    b["transfer_amount"] += amt
                else:
                    b["cash_amount"] += amt

        for nb in nasiya_rows:
            sname = str(nb.get("supplier") or "").strip()
            if not sname:
                continue
            b = _ensure_bucket(sname)
            b["nasiya_balance"] += float(nb.get("balance") or 0.0)

        suppliers_list = sorted(
            buckets.values(),
            key=lambda x: (
                -(x["total_amount"] + x["nasiya_balance"]),
                x["supplier_name"].lower(),
            ),
        )
        grand_total = sum(s["total_amount"] for s in suppliers_list)
        total_unpaid_debt = sum(s["unpaid_debt_amount"] for s in suppliers_list)
        total_nasiya_balance = sum(
            s["nasiya_balance"] for s in suppliers_list if s["nasiya_balance"] > 0
        )

        return {
            "suppliers_count": len(suppliers_list),
            "grand_total": grand_total,
            "total_unpaid_debt": total_unpaid_debt,
            "total_nasiya_balance": total_nasiya_balance,
            "duplicate_groups": duplicate_groups,
            "suppliers": suppliers_list,
        }

    @app.get("/suppliers/duplicates")
    async def get_supplier_duplicates_endpoint(
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        async with async_session_maker() as db:
            groups = await find_duplicate_supplier_groups(db)
        return {"count": len(groups), "groups": groups}

    @app.post("/suppliers/merge")
    async def merge_suppliers_endpoint(
        payload: SupplierMergeRequest,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        try:
            async with async_session_maker() as db:
                return await merge_suppliers(
                    db,
                    target_name=payload.target_name,
                    source_names=payload.source_names,
                    extra_aliases=payload.extra_aliases,
                    user_id=user.user_id,
                )
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))

    @app.get("/suppliers/merge-history")
    async def get_supplier_merge_history_endpoint(
        limit: int = Query(default=20, ge=1, le=50),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        async with async_session_maker() as db:
            items = await list_supplier_merge_logs(db, limit=limit)
        return {"count": len(items), "items": items}

    @app.post("/suppliers/merge/{merge_id}/undo")
    async def undo_supplier_merge_endpoint(
        merge_id: int,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        try:
            async with async_session_maker() as db:
                return await undo_supplier_merge(db, merge_id=merge_id, user_id=user.user_id)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))

    @app.post("/suppliers/split")
    async def split_supplier_endpoint(
        payload: SupplierSplitRequest,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        try:
            async with async_session_maker() as db:
                return await split_supplier(
                    db,
                    from_supplier=payload.from_supplier,
                    new_supplier_name=payload.new_supplier_name,
                    payment_ids=payload.payment_ids,
                    debt_ids=payload.debt_ids,
                    remove_aliases=payload.remove_aliases,
                    user_id=user.user_id,
                )
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))

    @app.post("/suppliers/aliases")
    async def update_supplier_aliases_endpoint(
        payload: SupplierAliasesUpdateRequest,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        try:
            async with async_session_maker() as db:
                return await update_supplier_aliases(
                    db,
                    supplier_name=payload.supplier_name,
                    aliases=payload.aliases,
                    user_id=user.user_id,
                )
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))

    async def _build_supplier_profile_data(
        supplier: str,
        limit: int = 60,
        date_from: Optional[str] = None,
        date_to: Optional[str] = None,
    ) -> dict:
        from database.crud import _norm_key

        if date_from and date_to and date_from > date_to:
            date_from, date_to = date_to, date_from

        async with async_session_maker() as db:
            canonical, _ = await resolve_supplier_name(db, supplier.strip())
            aliases_map = await get_supplier_aliases_map(db)
            canon_key = _norm_key(canonical)
            supplier_aliases = list(aliases_map.get(canon_key, []))
            match_lowers = {canonical.lower(), *(a.lower() for a in supplier_aliases)}
            stmt = (
                select(NakladnoyPayment, DailyCashSession)
                .join(DailyCashSession, DailyCashSession.id == NakladnoyPayment.session_id)
                .where(
                    func.lower(NakladnoyPayment.supplier_name).in_(list(match_lowers)),
                    NakladnoyPayment.status == "confirmed",
                )
                .order_by(NakladnoyPayment.id.desc())
            )
            all_rows = (await db.execute(stmt)).all()
            nasiya_rows = await get_supplier_debt_balances(db)
            nasiya_entries_raw = await list_supplier_debt_entries(db, supplier_name=canonical, limit=100)

        nasiya_entries = [
            {
                "id": int(d.id),
                "supplier_name": d.supplier_name,
                "entry_type": d.entry_type,
                "amount": float(d.amount),
                "note": d.note or "",
                "created_at": format_local_dt(d.created_at, "%Y-%m-%d %H:%M"),
            }
            for d in nasiya_entries_raw
        ]

        rows: list[tuple[NakladnoyPayment, DailyCashSession, str]] = []
        for pay, sess in all_rows:
            eff_date = effective_tx_local_date(pay.paid_at or pay.created_at, sess)
            if date_from and eff_date < date_from:
                continue
            if date_to and eff_date > date_to:
                continue
            rows.append((pay, sess, eff_date))

        total_amount = 0.0
        cash_amount = 0.0
        cash_count = 0
        card_amount = 0.0
        card_count = 0
        transfer_amount = 0.0
        transfer_count = 0
        unpaid_debt_amount = 0.0
        unpaid_debt_count = 0
        dates: list[str] = []

        for pay, sess, eff_date in rows:
            amt = float(pay.amount or 0.0)
            total_amount += amt
            if eff_date:
                dates.append(eff_date)
            if bool(getattr(pay, "is_debt", False)):
                unpaid_debt_amount += amt
                unpaid_debt_count += 1
            else:
                pm = normalize_payment_method(getattr(pay, "payment_method", "cash"))
                if pm == "card":
                    card_amount += amt
                    card_count += 1
                elif pm == "transfer":
                    transfer_amount += amt
                    transfer_count += 1
                else:
                    cash_amount += amt
                    cash_count += 1

        nasiya_balance = 0.0
        for nb in nasiya_rows:
            if str(nb.get("supplier") or "").strip().lower() in match_lowers:
                nasiya_balance += float(nb.get("balance") or 0.0)

        items = [
            _serialize_nakladnoy(
                pay,
                report_date=eff_date,
                session_status=str(sess.status or "open"),
            ).model_dump()
            for pay, sess, eff_date in rows[:limit]
        ]

        return {
            "supplier_name": canonical,
            "aliases": supplier_aliases,
            "date_from": date_from,
            "date_to": date_to,
            "total_count": len(rows),
            "total_amount": total_amount,
            "cash_amount": cash_amount,
            "cash_count": cash_count,
            "card_amount": card_amount,
            "card_count": card_count,
            "transfer_amount": transfer_amount,
            "transfer_count": transfer_count,
            "unpaid_debt_amount": unpaid_debt_amount,
            "unpaid_debt_count": unpaid_debt_count,
            "nasiya_balance": nasiya_balance,
            "first_date": min(dates) if dates else None,
            "last_date": max(dates) if dates else None,
            "items": items,
            "nasiya_entries": nasiya_entries,
        }

    @app.get("/suppliers/profile")
    async def get_supplier_profile_endpoint(
        supplier: str = Query(..., min_length=1),
        limit: int = Query(default=60, ge=1, le=200),
        date_from: Optional[str] = Query(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$"),
        date_to: Optional[str] = Query(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$"),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        return await _build_supplier_profile_data(
            supplier=supplier,
            limit=limit,
            date_from=date_from,
            date_to=date_to,
        )

    @app.get("/suppliers/sverka-pdf")
    async def export_supplier_sverka_pdf_endpoint(
        supplier: str = Query(..., min_length=1),
        date_from: Optional[str] = Query(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$"),
        date_to: Optional[str] = Query(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$"),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> StreamingResponse:
        profile = await _build_supplier_profile_data(
            supplier=supplier,
            limit=100,
            date_from=date_from,
            date_to=date_to,
        )
        pdf_bytes = await asyncio.to_thread(generate_supplier_sverka_pdf, profile)
        safe_sup = "".join(
            ch if ch.isalnum() or ch in ("_", "-") else "_"
            for ch in str(profile.get("supplier_name") or "postavshik")
        ).strip("_") or "postavshik"
        filename = f"Sverka_{safe_sup}_{today_iso()}.pdf"
        return StreamingResponse(
            io.BytesIO(pdf_bytes),
            media_type="application/pdf",
            headers={"Content-Disposition": f'attachment; filename="{filename}"'},
        )

    @app.post("/ai/extract")
    async def ai_extract_nakladnoy(
        photo: UploadFile = File(...),
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        """Read supplier & total amount from a nakladnoy photo via Gemini Vision (same engine as bot)."""
        check_rate_limit("ai_ops", str(user.user_id), max_hits=25, window_seconds=300)
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
        r_mode = "floor_1000"
        async with async_session_maker() as db:
            r_mode = await get_app_setting(db, "round_mode", "floor_1000")
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
                rounded = round_nakladnoy_amount(float(amount_raw), r_mode)

        raw_mc = res.get("math_check")
        math_check: dict = (
            dict(raw_mc)
            if isinstance(raw_mc, dict)
            else {
                "status": "skipped",
                "items_count": 0,
                "written_total": float(amount_raw) if amount_raw else None,
                "calculated_total": None,
                "difference": None,
                "line_errors": [],
                "warning_text": "",
            }
        )
        calc_tot = math_check.get("calculated_total")
        math_check["rounded_calculated_total"] = (
            round_nakladnoy_amount(float(calc_tot), r_mode)
            if calc_tot is not None and float(calc_tot) > 0
            else None
        )

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
            "anomaly_warning": _compute_supplier_anomaly(rounded, amounts),
            "math_check": math_check,
            "error_code": err,
            "message": messages.get(err or "", ""),
        }

    @app.post("/ai/voice")
    async def ai_parse_voice_command(
        audio: Optional[UploadFile] = File(default=None),
        text: str = Form(default=""),
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        """Parse spoken Uzbek voice clip or text command into cash/nakladnoy intent."""
        check_rate_limit("ai_ops", str(user.user_id), max_hits=25, window_seconds=300)
        raw_audio: Optional[bytes] = None
        mime_type = "audio/mp4"
        if audio is not None:
            raw_audio = await audio.read()
            if raw_audio and len(raw_audio) > 10 * 1024 * 1024:
                raise HTTPException(status_code=400, detail="Ovoz fayli 10 MB dan oshmasligi kerak")
            fname = (audio.filename or "").lower()
            ctype = (audio.content_type or "").lower()
            if fname.endswith((".m4a", ".mp4", ".aac")) or "mp4" in ctype or "aac" in ctype:
                mime_type = "audio/mp4"
            elif fname.endswith(".wav") or "wav" in ctype:
                mime_type = "audio/wav"
            elif ctype.startswith("audio/"):
                mime_type = ctype
            else:
                mime_type = "audio/ogg"

        if not raw_audio and not text.strip():
            raise HTTPException(status_code=400, detail="Ovoz yoki matn yuborilmadi")

        res = await parse_voice_or_text(
            audio_bytes=raw_audio if raw_audio else None,
            text=text.strip() or None,
            mime_type=mime_type,
        )
        err = res.get("error_code")
        intent = str(res.get("intent") or "unknown")
        amount = res.get("amount")
        sup_raw = res.get("supplier_name")
        resolved_sup: Optional[str] = None
        if sup_raw:
            async with async_session_maker() as db:
                canonical, suggestion = await resolve_supplier_name(db, str(sup_raw))
                resolved_sup = suggestion or canonical or str(sup_raw)

        messages = {
            "no_key": "AI kaliti sozlanmagan",
            "rate_limit": "AI limiti tugadi, matn bilan yozing",
            "api_error": "Ovozni tushunib bo'lmadi",
        }
        return {
            "ok": err is None and intent != "unknown",
            "intent": intent,
            "amount": float(amount) if amount is not None else None,
            "supplier_name": resolved_sup,
            "transcript": str(res.get("transcript") or text.strip()),
            "error_code": err,
            "message": messages.get(err or "", ""),
        }

    @app.post("/nakladnoy")
    async def create_nakladnoy(
        request: Request,
        supplier_name: str = Form(...),
        amount: float = Form(...),
        payment_mode: str = Form(default="cash"),  # cash | card | transfer | debt
        note: str = Form(default=""),
        send_to_group: bool = Form(default=True),
        original_amount: Optional[float] = Form(default=None),
        client_request_id: Optional[str] = Form(default=None),
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
        clean_note = note.strip()

        photo_bytes: Optional[bytes] = None
        if photo is not None:
            raw = await photo.read()
            if raw:
                if len(raw) > 15 * 1024 * 1024:
                    raise HTTPException(status_code=400, detail="Rasm hajmi 15 MB dan oshmasligi kerak")
                photo_bytes = raw

        idem_key = _extract_idempotency_key(request, client_request_id)

        async def _op() -> dict:
            async with _get_lock(user_create_locks, int(user.user_id)):
                async with async_session_maker() as db:
                    canonical, _ = await resolve_supplier_name(db, clean_supplier)
                    r_mode = await get_app_setting(db, "round_mode", "floor_1000")
                    rounded_amt = round_nakladnoy_amount(float(amount), r_mode)
                    if round(rounded_amt) != round(amount):
                        eff_amt = rounded_amt
                        eff_orig: Optional[float] = (
                            float(original_amount) if original_amount else float(amount)
                        )
                    else:
                        eff_amt = float(amount)
                        eff_orig = (
                            float(original_amount)
                            if original_amount and round(original_amount) != round(amount)
                            else None
                        )

                    # Rapid double-tap fallback guard for clients without X-Idempotency-Key
                    if not idem_key:
                        open_sess = await get_or_create_open_session(db)
                        recent = await db.scalar(
                            select(NakladnoyPayment)
                            .where(
                                NakladnoyPayment.session_id == open_sess.id,
                                NakladnoyPayment.status == "confirmed",
                            )
                            .order_by(desc(NakladnoyPayment.id))
                            .limit(1)
                        )
                        if recent is not None and recent.created_at is not None:
                            created_naive = recent.created_at.replace(tzinfo=None)
                            now_naive = datetime.now(timezone.utc).replace(tzinfo=None)
                            age_sec = (now_naive - created_naive).total_seconds()
                            if (
                                -5 <= age_sec <= 12
                                and recent.supplier_name == canonical
                                and abs(float(recent.amount) - eff_amt) < 0.01
                                and normalize_payment_method(recent.payment_method) == pm
                                and bool(recent.is_debt) == is_debt
                                and (recent.note or "").strip() == clean_note
                            ):
                                dup_seq = await get_nakladnoy_session_seq(db, recent)
                                return {
                                    "nakladnoy": _serialize_nakladnoy(
                                        recent, session_seq=dup_seq
                                    ).model_dump(),
                                    "group_posted": bool(
                                        recent.group_chat_id and recent.group_message_id
                                    ),
                                    "group_message": "Takroriy yuborish bloklandi",
                                }

                    pending = await create_pending_nakladnoy(
                        db,
                        supplier_name=canonical,
                        amount=eff_amt,
                        note=clean_note or None,
                        original_amount=eff_orig,
                    )
                    confirmed = await confirm_nakladnoy(
                        db,
                        payment_id=pending.id,
                        user_id=user.user_id,
                        is_debt=is_debt,
                        payment_method=pm,
                    )
                    if confirmed is None:
                        raise HTTPException(
                            status_code=500, detail="Nakladnoy tasdiqlashda xatolik"
                        )
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
                    "nakladnoy": _serialize_nakladnoy(confirmed, session_seq=seq).model_dump(),
                    "group_posted": grp_ok,
                    "group_message": grp_msg,
                }

        return await _execute_idempotent("nakladnoy", user.user_id, idem_key, _op)

    @app.get("/nakladnoy")
    async def list_nakladnoys(
        scope: str = Query(default="today"),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        async with async_session_maker() as db:
            if scope == "recent":
                rows = await list_recent_nakladnoys(db, limit=60)
                st_map = await _batch_session_statuses(db, rows)
                items = [
                    _serialize_nakladnoy(
                        r, session_status=st_map.get(int(r.session_id), "open")
                    )
                    for r in rows
                ]
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
                        n,
                        session_seq=idx,
                        report_date=summary.session.report_date,
                        session_status=summary.session.status,
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
            cur_pay = await _assert_payment_editable(db, payment_id, allow_if_debt=False)
            canonical_sup = None
            if payload.supplier_name is not None:
                canonical_sup, _ = await resolve_supplier_name(
                    db, payload.supplier_name.strip()
                )
            base_amt = (
                float(payload.amount)
                if payload.amount is not None
                else float(cur_pay.amount)
            )
            new_amt: Optional[float] = (
                float(payload.amount) if payload.amount is not None else None
            )
            orig_amt: Optional[float] = None
            if payload.round_amount:
                r_mode = await get_app_setting(db, "round_mode", "floor_1000")
                if payload.amount is None and r_mode == "none":
                    r_mode = "floor_1000"
                rounded_amt = round_nakladnoy_amount(base_amt, r_mode)
                new_amt = rounded_amt
                if round(rounded_amt) != round(base_amt):
                    orig_amt = (
                        float(cur_pay.original_amount)
                        if (payload.amount is None and cur_pay.original_amount is not None)
                        else base_amt
                    )
            updated = await update_nakladnoy(
                db,
                payment_id=payment_id,
                supplier_name=canonical_sup,
                amount=new_amt,
                note=payload.note,
                user_id=user.user_id,
                original_amount=orig_amt,
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
            await _assert_payment_editable(db, payment_id, allow_if_debt=True)
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
            await _assert_payment_editable(db, payment_id, allow_if_debt=False)
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
        request: Request,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> NakladnoyOut:
        async def _op() -> dict:
            async with async_session_maker() as db:
                res = await mark_nakladnoy_as_paid(
                    db,
                    payment_id=payment_id,
                    user_id=user.user_id,
                    payment_method=payload.payment_method,
                    partial_amount=payload.amount,
                )
                if res is None:
                    raise HTTPException(status_code=404, detail="Nakladnoy topilmadi")
                updated, _ = res
                seq = await get_nakladnoy_session_seq(db, updated)

            tag = "💸 [QISMAN TO'LANDI]" if updated.is_debt else "✅ [QARZ TO'LANDI]"
            sync_existing_group_message(updated, tag=tag)
            return _serialize_nakladnoy(updated, session_seq=seq).model_dump()

        idem_key = _extract_idempotency_key(request)
        data = await _execute_idempotent("pay_debt", user.user_id, idem_key, _op)
        return NakladnoyOut.model_validate(data)

    @app.post("/nakladnoy/{payment_id}/group")
    async def send_nakladnoy_to_group_endpoint(
        payment_id: int,
        request: Request,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        async def _op() -> dict:
            ok, msg = await post_nakladnoy_to_telegram_group(payment_id, force=True)
            if not ok:
                raise HTTPException(status_code=400, detail=msg)
            async with async_session_maker() as db:
                updated = await get_nakladnoy(db, payment_id)
                seq = await get_nakladnoy_session_seq(db, updated) if updated else None
            return {
                "ok": True,
                "message": msg,
                "nakladnoy": _serialize_nakladnoy(updated, session_seq=seq).model_dump()
                if updated
                else None,
            }

        idem_key = _extract_idempotency_key(request)
        return await _execute_idempotent("send_group", user.user_id, idem_key, _op)

    @app.delete("/nakladnoy/{payment_id}")
    async def remove_nakladnoy(
        payment_id: int,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        async with async_session_maker() as db:
            await _assert_payment_editable(db, payment_id, allow_if_debt=False)
            deleted = await delete_nakladnoy(db, payment_id=payment_id, user_id=user.user_id)
        if deleted is None:
            raise HTTPException(status_code=404, detail="Nakladnoy topilmadi")
        sync_existing_group_message(deleted, tag="❌ [O'CHIRILDI]")
        return {"ok": True, "deleted_id": payment_id}

    @app.post("/nakladnoy/{payment_id}/restore", response_model=NakladnoyOut)
    async def restore_nakladnoy_endpoint(
        payment_id: int,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> NakladnoyOut:
        async with async_session_maker() as db:
            restored = await restore_nakladnoy(
                db, payment_id=payment_id, user_id=user.user_id
            )
            if restored is None:
                raise HTTPException(status_code=404, detail="Nakladnoy topilmadi")
            seq = await get_nakladnoy_session_seq(db, restored)
        sync_existing_group_message(restored, tag="")
        return _serialize_nakladnoy(restored, session_seq=seq)

    @app.get("/debts")
    async def get_unpaid_debts(
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        async with async_session_maker() as db:
            rows = await list_unpaid_debt_nakladnoys(db)
            st_map = await _batch_session_statuses(db, [pay for pay, _ in rows])
        items = [
            _serialize_nakladnoy(
                pay,
                report_date=r_date,
                session_status=st_map.get(int(pay.session_id), "open"),
            )
            for pay, r_date in rows
        ]
        total = sum(i.amount for i in items)
        return {"count": len(items), "total_amount": total, "items": items}

    @app.get("/cash/reconciliations")
    async def list_cash_reconciliations_endpoint(
        session_id: Optional[int] = Query(default=None),
        kind: Optional[str] = Query(default=None),
        limit: int = Query(default=80, ge=1, le=200),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        async with async_session_maker() as db:
            return await get_cash_reconciliations_report(
                db, session_id=session_id, kind=kind, limit=limit
            )

    @app.post("/cash/reconciliations", response_model=CashReconciliationOut)
    async def create_interim_reconciliation_endpoint(
        payload: CashReconciliationCreateRequest,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> CashReconciliationOut:
        async with async_session_maker() as db:
            rec, r_date = await create_cash_reconciliation(
                db,
                counted_cash=payload.counted_cash,
                kind="interim",
                note=payload.note,
                user_id=user.user_id,
            )
        return _reconciliation_to_out(rec, r_date)

    @app.delete("/cash/reconciliations/{rec_id}")
    async def delete_interim_reconciliation_endpoint(
        rec_id: int,
        user: AuthenticatedUser = Depends(require_write_user),
    ) -> dict:
        async with async_session_maker() as db:
            ok, reason = await delete_cash_reconciliation(db, rec_id)
        if not ok:
            if reason == "closing_protected":
                raise HTTPException(
                    status_code=400,
                    detail="Asosiy kun yopish sverkasini o'chirib bo'lmaydi",
                )
            raise HTTPException(status_code=404, detail="Sverka yozuvi topilmadi")
        return {"ok": True, "deleted_id": rec_id}

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
                note=payload.note,
                user_id=user.user_id,
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

    @app.post("/export/send-telegram")
    async def send_excel_to_telegram_endpoint(
        payload: ExcelSendTelegramRequest,
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        bot = get_bot()
        if bot is None:
            raise HTTPException(status_code=503, detail="Telegram bot ulanmagan")

        if payload.report_type == "session":
            async with async_session_maker() as db:
                summary = await compute_session_summary(db, session_id=payload.session_id)
            xlsx_bytes = await asyncio.to_thread(build_session_excel, summary)
            filename = f"Hisobot_{summary.session.report_date}.xlsx"
            caption = (
                f"📊 <b>Kunlik Excel hisobot</b>\n"
                f"📅 Sana: <b>{summary.session.report_date}</b> (Smena #{summary.session.id})"
            )
        elif payload.report_type == "range":
            d_to = (payload.date_to or today_iso()).strip()
            d_from = (payload.date_from or d_to).strip()
            if d_from > d_to:
                d_from, d_to = d_to, d_from
            async with async_session_maker() as db:
                data = await get_range_report_data(db, d_from, d_to)
            xlsx_bytes = await asyncio.to_thread(build_range_excel, d_from, d_to, data)
            filename = f"Hisobot_{d_from}_{d_to}.xlsx"
            caption = f"📅 <b>Davr Excel hisoboti</b>\n🗓 {d_from} — {d_to}"
        else:
            target_month = (payload.month or today_iso()[:7]).strip()[:7]
            async with async_session_maker() as db:
                rows = await get_supplier_sverka(db, target_month)
            xlsx_bytes = await asyncio.to_thread(build_sverka_excel, target_month, rows)
            filename = f"Sverka_{target_month}.xlsx"
            caption = f"🏢 <b>Postavshiklar Sverkasi</b>\n🗓 Oy: <b>{target_month}</b>"

        try:
            await bot.send_document(
                chat_id=user.user_id,
                document=BufferedInputFile(xlsx_bytes, filename=filename),
                caption=caption,
                parse_mode="HTML",
            )
        except Exception as exc:
            raise HTTPException(
                status_code=502,
                detail=f"Telegram botga yuborishda xatolik: {exc}",
            ) from exc

        return {
            "ok": True,
            "filename": filename,
            "message": f"📤 {filename} Telegram botga yuborildi!",
        }

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

        by_date: dict[str, list[int]] = {}
        for s in sorted(sessions, key=lambda x: x.id):
            by_date.setdefault(s.report_date, []).append(int(s.id))

        items = []
        for s in sessions:
            same_day_ids = by_date.get(s.report_date, [int(s.id)])
            seq_in_day = same_day_ids.index(int(s.id)) + 1
            items.append(
                {
                    "id": int(s.id),
                    "report_date": s.report_date,
                    "status": s.status,
                    "opening_balance": float(s.opening_balance or 0.0),
                    "expected_cash": float(s.expected_cash or 0.0),
                    "actual_counted_cash": (
                        float(s.actual_counted_cash)
                        if s.actual_counted_cash is not None
                        else None
                    ),
                    "difference": (
                        float(s.difference) if s.difference is not None else None
                    ),
                    "created_at": (
                        format_local_dt(s.created_at, "%Y-%m-%d %H:%M")
                        if s.created_at
                        else ""
                    ),
                    "closed_at": (
                        format_local_dt(s.closed_at, "%Y-%m-%d %H:%M")
                        if s.closed_at
                        else ""
                    ),
                    "shift_seq": seq_in_day,
                    "shift_total": len(same_day_ids),
                }
            )
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
            _serialize_nakladnoy(
                n,
                session_seq=idx,
                report_date=effective_tx_local_date(n.paid_at or n.created_at, summary.session),
                session_status=summary.session.status,
            )
            for idx, n in enumerate(all_naks, start=1)
        ]
        cash_outs = [_serialize_cash_tx(tx) for tx in summary.cash_transactions]
        return StatusSummaryResponse(
            session_id=int(summary.session.id),
            report_date=summary.session.report_date,
            session_status=summary.session.status,
            opened_at=(
                format_local_dt(summary.session.created_at, "%Y-%m-%d %H:%M")
                if summary.session.created_at
                else ""
            ),
            closed_at=(
                format_local_dt(summary.session.closed_at, "%Y-%m-%d %H:%M")
                if summary.session.closed_at
                else ""
            ),
            opening_balance=float(summary.opening_balance),
            main_cash_in=float(summary.main_cash_in),
            main_return_today=float(getattr(summary, "main_return_today", 0.0)),
            kassa_debt_today=float(summary.kassa_debt_today),
            kassa_repay_today=float(summary.kassa_repay_today),
            expense_today=float(summary.expense_today),
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
        clean_q = q.strip()
        low_q = clean_q.lower()
        digits_q = "".join(ch for ch in clean_q if ch.isdigit())
        async with async_session_maker() as db:
            rows = await search_nakladnoys(db, clean_q, limit=40)
            st_map = await _batch_session_statuses(db, [pay for pay, _ in rows])
            recent_cash = await list_recent_cash_transactions(db, limit=120)
        items = [
            _serialize_nakladnoy(
                pay,
                report_date=r_date,
                session_status=st_map.get(int(pay.session_id), "open"),
            )
            for pay, r_date in rows
        ]
        src_labels = {
            "main": "pul oldim kirim",
            "main_return": "pul oldim qaytarish qaytardim",
            "kassa_debt": "kassadan qarz oldim",
            "kassa_repay": "kassaga qaytardim qaytarish",
            "expense": "xarajat chiqim rasxod",
        }
        cash_matches = []
        for tx in recent_cash:
            amt_str = f"{int(round(float(tx.amount)))}"
            haystack = f"{tx.note or ''} {src_labels.get(tx.source_type, tx.source_type)}".lower()
            if low_q in haystack or (digits_q and digits_q in amt_str):
                cash_matches.append(_serialize_cash_tx(tx))
                if len(cash_matches) >= 25:
                    break
        return {
            "query": clean_q,
            "count": len(items) + len(cash_matches),
            "items": items,
            "cash_items": cash_matches,
        }

    @app.get("/kassa-debt/history")
    async def get_kassa_debt_history_endpoint(
        limit: int = Query(default=40, ge=1, le=100),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        async with async_session_maker() as db:
            stats = await get_kassa_debt_stats(db, limit=limit)
        return {
            "total_borrowed": float(stats["total_borrowed"]),
            "total_repaid": float(stats["total_repaid"]),
            "outstanding": float(stats["outstanding"]),
            "items": [_serialize_cash_tx(tx) for tx in stats["recent_txs"]],
        }

    # -----------------------------------------------------------------------
    # Stage 2: In-App Live Sverka & Period Statistics
    # -----------------------------------------------------------------------

    @app.get("/stats/period")
    async def get_period_stats_endpoint(
        days: int = Query(default=7, ge=1, le=365),
        date_from: Optional[str] = Query(default=None),
        date_to: Optional[str] = Query(default=None),
        preset: Optional[str] = Query(default=None),
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        clean_preset = (preset or "").strip().lower()
        if not date_from and not date_to and clean_preset == "today":
            d_from = d_to = today_iso()
        elif not date_from and not date_to and clean_preset == "yesterday":
            d_from = d_to = (now_local() - timedelta(days=1)).strftime("%Y-%m-%d")
        else:
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
            "granularity": st.get("granularity", "daily"),
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
            payment = await _assert_payment_editable(db, payment_id, allow_if_debt=False)

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
        async with _get_lock(prixod_publish_locks, int(report_id)):
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

    # -----------------------------------------------------------------------
    # Telegram Groups, Bot Preferences, RBAC Roles & Backup (/settings/...)
    # -----------------------------------------------------------------------

    @app.get("/settings/telegram-hub")
    async def get_telegram_hub_endpoint(
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        _require_admin_user(user)
        bot_username = await _resolve_bot_username()

        async with async_session_maker() as db:
            all_groups = await get_all_group_configs(db)
            apk_post = await get_app_setting(db, "apk_post_to_group", "on")
            auto_confirm = await get_app_setting(db, "auto_confirm", "on")
            ar_enabled = await get_app_setting(db, "auto_report_enabled", "1")
            ar_time = await get_app_setting(db, "auto_report_time", "23:00")
            round_mode = await get_app_setting(db, "round_mode", "floor_1000")
            ai_stats = await get_ai_usage_stats(db)
            db_roles = await list_user_roles(db)

        groups = []
        for role_key, role_title in _GROUP_ROLES:
            cfg = all_groups.get(role_key)
            bound = bool(cfg and cfg.chat_id)
            groups.append(
                {
                    "role": role_key,
                    "role_title": role_title,
                    "bound": bound,
                    "chat_id": int(cfg.chat_id) if bound else None,
                    "title": (cfg.title or str(cfg.chat_id)) if bound else "",
                    "bind_url": build_add_to_group_url(bot_username, role_key),
                }
            )

        super_admins = set(get_settings().admin_id_list)
        users = [
            {
                "user_id": int(aid),
                "role": ROLE_ADMIN,
                "role_label": "👑 Asosiy Admin",
                "label": "Asosiy Admin",
                "is_super_admin": True,
            }
            for aid in get_settings().admin_id_list
        ]
        for ur in db_roles:
            uid = int(ur.user_id)
            if uid in super_admins:
                continue
            users.append(
                {
                    "user_id": uid,
                    "role": ur.role,
                    "role_label": ROLE_LABELS.get(ur.role, ur.role),
                    "label": ur.label or str(uid),
                    "is_super_admin": False,
                }
            )

        return {
            "bot_username": bot_username,
            "groups": groups,
            "prefs": {
                "apk_post_to_group": (apk_post or "on").strip().lower() != "off",
                "auto_confirm": (auto_confirm or "on").strip().lower() != "off",
                "auto_report_enabled": (ar_enabled or "1").strip() == "1",
                "auto_report_time": ar_time or "23:00",
                "round_mode": round_mode or "floor_1000",
            },
            "ai_stats": ai_stats,
            "users": users,
        }

    @app.post("/settings/groups")
    async def bind_telegram_group_endpoint(
        payload: GroupBindRequest,
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        _require_admin_user(user)
        resolved_title = payload.title.strip()
        if not resolved_title:
            bot = get_bot()
            if bot is not None and hasattr(bot, "get_chat"):
                try:
                    chat = await bot.get_chat(payload.chat_id)
                    if getattr(chat, "title", None):
                        resolved_title = str(chat.title).strip()
                except Exception:
                    pass
        if not resolved_title:
            resolved_title = f"Guruh ({payload.chat_id})"

        async with async_session_maker() as db:
            await set_group_config(
                db,
                role=payload.role,
                chat_id=payload.chat_id,
                title=resolved_title,
            )

        return {
            "ok": True,
            "role": payload.role,
            "chat_id": payload.chat_id,
            "title": resolved_title,
            "message": f"✅ «{resolved_title}» ulandi!",
        }

    @app.delete("/settings/groups/{role}")
    async def unbind_telegram_group_endpoint(
        role: str,
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        _require_admin_user(user)
        if role not in _GROUP_ROLE_TITLES:
            raise HTTPException(status_code=400, detail="Noto'g'ri guruh turi")
        async with async_session_maker() as db:
            deleted = await delete_group_config(db, role)
        if not deleted:
            raise HTTPException(status_code=404, detail="Guruh avval ham bog'lanmagan")
        return {"ok": True, "role": role, "message": "Guruh ulanishi uzildi"}

    @app.post("/settings/groups/{role}/test")
    async def test_telegram_group_endpoint(
        role: str,
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        _require_admin_user(user)
        if role not in _GROUP_ROLE_TITLES:
            raise HTTPException(status_code=400, detail="Noto'g'ri guruh turi")
        bot = get_bot()
        if bot is None:
            raise HTTPException(status_code=503, detail="Telegram bot ulanmagan")
        async with async_session_maker() as db:
            grp = await get_group_config(db, role)
        if grp is None or not grp.chat_id:
            raise HTTPException(status_code=400, detail="Ushbu vazifa uchun guruh bog'lanmagan")

        role_title = _GROUP_ROLE_TITLES[role]
        try:
            await bot.send_message(
                chat_id=grp.chat_id,
                text=(
                    f"🔔 <b>Hisobchi APK / Mini App test xabari</b>\n"
                    f"📌 Vazifa: <b>{html.escape(role_title)}</b>\n"
                    f"✅ Aloqa va yozish huquqi 100% ishlayapti!"
                ),
                parse_mode="HTML",
            )
        except Exception as exc:
            raise HTTPException(
                status_code=502,
                detail=f"Guruhga test xabar yuborib bo'lmadi: {exc}",
            ) from exc

        return {
            "ok": True,
            "message": f"✅ Test xabar «{grp.title or grp.chat_id}» guruhiga yuborildi!",
        }

    @app.post("/settings/bot-prefs")
    async def update_bot_prefs_endpoint(
        payload: BotPrefsUpdateRequest,
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        _require_admin_user(user)
        async with async_session_maker() as db:
            if payload.apk_post_to_group is not None:
                await set_app_setting(
                    db, "apk_post_to_group", "on" if payload.apk_post_to_group else "off"
                )
            if payload.auto_confirm is not None:
                await set_app_setting(
                    db, "auto_confirm", "on" if payload.auto_confirm else "off"
                )
            if payload.auto_report_enabled is not None:
                await set_app_setting(
                    db, "auto_report_enabled", "1" if payload.auto_report_enabled else "0"
                )
            if payload.auto_report_time is not None:
                await set_app_setting(db, "auto_report_time", payload.auto_report_time)
        return {"ok": True, "message": "✅ Bot sozlamalari saqlandi"}

    @app.post("/settings/roles")
    async def save_user_role_endpoint(
        payload: UserRoleSaveRequest,
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        _require_admin_user(user)
        async with async_session_maker() as db:
            await set_user_role(
                db,
                user_id=payload.user_id,
                role=payload.role,
                label=payload.label.strip(),
            )
            await refresh_role_cache(db)
        return {
            "ok": True,
            "user_id": payload.user_id,
            "role": payload.role,
            "message": "✅ Foydalanuvchi roli saqlandi",
        }

    @app.delete("/settings/roles/{target_user_id}")
    async def delete_user_role_endpoint(
        target_user_id: int,
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        _require_admin_user(user)
        if target_user_id in get_settings().admin_id_list:
            raise HTTPException(
                status_code=400,
                detail="Asosiy adminni o'chirib bo'lmaydi",
            )
        async with async_session_maker() as db:
            deleted = await delete_user_role(db, target_user_id)
            if not deleted:
                raise HTTPException(status_code=404, detail="Foydalanuvchi roli topilmadi")
            await refresh_role_cache(db)
        return {
            "ok": True,
            "deleted_user_id": target_user_id,
            "message": "Foydalanuvchi huquqi olib tashlandi",
        }

    @app.post("/settings/backup-now")
    async def trigger_backup_now_endpoint(
        user: AuthenticatedUser = Depends(get_current_user),
    ) -> dict:
        _require_admin_user(user)
        bot = get_bot()
        if bot is None:
            raise HTTPException(status_code=503, detail="Telegram bot ulanmagan")
        ok = await send_backup(
            bot,
            chat_ids=[user.user_id],
            session_maker_override=async_session_maker,
        )
        if not ok:
            raise HTTPException(
                status_code=502,
                detail="Backup yaratish yoki Telegramga yuborishda xatolik",
            )
        return {"ok": True, "message": "💾 Backup Telegram botingizga yuborildi!"}

    return app
