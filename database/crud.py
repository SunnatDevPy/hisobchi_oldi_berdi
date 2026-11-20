"""Async CRUD operations for wallet sessions, nakladnoy payments, groups, suppliers, and prixod reports."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Dict, List, Optional
from zoneinfo import ZoneInfo

from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from config import get_settings
from database.models import (
    AppSetting,
    AuditLog,
    CashTransaction,
    DailyCashSession,
    GroupConfig,
    NakladnoyPayment,
    PrixodReport,
    PrixodRow,
    SupplierConfig,
)


def now_local() -> datetime:
    """Return current datetime in configured local timezone."""
    tz = ZoneInfo(get_settings().TIMEZONE)
    return datetime.now(tz)


def to_local_dt(dt: Optional[datetime]) -> datetime:
    """Convert any UTC/naive/aware datetime into configured local timezone."""
    tz = ZoneInfo(get_settings().TIMEZONE)
    if dt is None:
        return datetime.now(tz)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(tz)


def format_local_dt(dt: Optional[datetime], fmt: str = "%d.%m.%Y %H:%M") -> str:
    """Format a datetime in local timezone."""
    return to_local_dt(dt).strftime(fmt)


def today_iso() -> str:
    """Return today's date as YYYY-MM-DD in local timezone."""
    return now_local().strftime("%Y-%m-%d")


@dataclass
class SessionSummary:
    """Calculated balances and line items for a DailyCashSession."""

    session: DailyCashSession
    opening_balance: float
    main_cash_in: float
    kassa_debt_today: float
    kassa_repay_today: float
    total_available_inflow: float
    total_nakladnoy_spent: float
    expected_cash: float
    total_kassa_debt_outstanding: float
    cash_transactions: List[CashTransaction]
    confirmed_nakladnoys: List[NakladnoyPayment]


# ---------------------------------------------------------------------------
# Group configuration
# ---------------------------------------------------------------------------


async def set_group_config(
    db: AsyncSession, role: str, chat_id: int, title: str
) -> GroupConfig:
    """Bind or update a Telegram group chat_id for a given role."""
    stmt = select(GroupConfig).where(GroupConfig.role == role)
    obj = await db.scalar(stmt)
    if obj is None:
        obj = GroupConfig(role=role, chat_id=chat_id, title=title)
        db.add(obj)
    else:
        obj.chat_id = chat_id
        obj.title = title
    await db.commit()
    await db.refresh(obj)
    return obj


async def get_group_config(db: AsyncSession, role: str) -> Optional[GroupConfig]:
    """Return configured group for a role."""
    return await db.scalar(select(GroupConfig).where(GroupConfig.role == role))


async def get_all_group_configs(db: AsyncSession) -> Dict[str, GroupConfig]:
    """Return all configured groups keyed by role."""
    rows = (await db.scalars(select(GroupConfig))).all()
    return {row.role: row for row in rows}


# ---------------------------------------------------------------------------
# Supplier configuration
# ---------------------------------------------------------------------------


async def list_suppliers(db: AsyncSession, active_only: bool = True) -> List[SupplierConfig]:
    """List configured suppliers ordered by order_num and id."""
    stmt = select(SupplierConfig)
    if active_only:
        stmt = stmt.where(SupplierConfig.is_active.is_(True))
    stmt = stmt.order_by(SupplierConfig.order_num, SupplierConfig.id)
    return list((await db.scalars(stmt)).all())


async def add_or_update_supplier(
    db: AsyncSession,
    display_name: str,
    aliases: str = "",
    default_category: str = "qarz",
    order_num: Optional[int] = None,
) -> SupplierConfig:
    """Add a new supplier config or update an existing one by display_name."""
    existing = await db.scalar(
        select(SupplierConfig).where(SupplierConfig.display_name == display_name)
    )
    if existing is None:
        if order_num is None:
            current = await list_suppliers(db, active_only=False)
            order_num = max((s.order_num for s in current), default=0) + 1
        alias_str = aliases.strip() or display_name.upper()
        existing = SupplierConfig(
            order_num=order_num,
            display_name=display_name.strip(),
            aliases=alias_str,
            default_category=default_category,
            is_active=True,
        )
        db.add(existing)
    else:
        if aliases.strip():
            existing.aliases = aliases.strip()
        existing.default_category = default_category
        if order_num is not None:
            existing.order_num = order_num
        existing.is_active = True
    await db.commit()
    await db.refresh(existing)
    return existing


async def append_supplier_alias(
    db: AsyncSession, supplier_id: int, new_alias: str
) -> Optional[SupplierConfig]:
    """Append an uppercase alias to an existing supplier configuration."""
    supplier = await db.get(SupplierConfig, supplier_id)
    if supplier is None:
        return None
    alias_clean = new_alias.strip().upper()
    if not alias_clean:
        return supplier
    parts = [p.strip() for p in supplier.aliases.split(",") if p.strip()]
    if alias_clean not in [p.upper() for p in parts]:
        parts.append(alias_clean)
    supplier.aliases = ",".join(parts)
    await db.commit()
    await db.refresh(supplier)
    return supplier


async def delete_supplier(db: AsyncSession, supplier_id: int) -> bool:
    """Deactivate/remove a supplier config."""
    supplier = await db.get(SupplierConfig, supplier_id)
    if supplier is None:
        return False
    await db.delete(supplier)
    await db.commit()
    return True


# ---------------------------------------------------------------------------
# Daily cash wallet sessions & transactions
# ---------------------------------------------------------------------------


async def get_open_session(db: AsyncSession) -> Optional[DailyCashSession]:
    """Fetch the most recent open DailyCashSession."""
    stmt = (
        select(DailyCashSession)
        .where(DailyCashSession.status == "open")
        .order_by(desc(DailyCashSession.id))
        .limit(1)
    )
    return await db.scalar(stmt)


async def get_last_closed_session(db: AsyncSession) -> Optional[DailyCashSession]:
    """Fetch the most recent closed DailyCashSession."""
    stmt = (
        select(DailyCashSession)
        .where(DailyCashSession.status == "closed")
        .order_by(desc(DailyCashSession.id))
        .limit(1)
    )
    return await db.scalar(stmt)


async def get_or_create_open_session(
    db: AsyncSession, report_date: str | None = None
) -> DailyCashSession:
    """Return active open session or create one carrying over last closed counted cash."""
    open_sess = await get_open_session(db)
    if open_sess is not None:
        return open_sess

    last_closed = await get_last_closed_session(db)
    opening_balance = float(last_closed.actual_counted_cash or 0.0) if last_closed else 0.0

    new_sess = DailyCashSession(
        report_date=report_date or today_iso(),
        status="open",
        opening_balance=opening_balance,
        expected_cash=opening_balance,
    )
    db.add(new_sess)
    await db.commit()
    await db.refresh(new_sess)
    return new_sess


async def get_outstanding_kassa_debt(db: AsyncSession) -> float:
    """Compute cumulative unpaid debt borrowed from Kassa across all non-deleted records."""
    txs = (
        await db.scalars(
            select(CashTransaction).where(
                CashTransaction.is_deleted.is_(False),
                CashTransaction.source_type.in_(["kassa_debt", "kassa_repay"]),
            )
        )
    ).all()
    debt = sum(t.amount for t in txs if t.source_type == "kassa_debt")
    repaid = sum(t.amount for t in txs if t.source_type == "kassa_repay")
    return debt - repaid


async def get_kassa_debt_stats(db: AsyncSession, limit: int = 10) -> dict:
    """Return total borrowed from Kassa, total repaid/given back, balance, and recent history."""
    txs = list(
        (
            await db.scalars(
                select(CashTransaction)
                .where(
                    CashTransaction.is_deleted.is_(False),
                    CashTransaction.source_type.in_(["kassa_debt", "kassa_repay"]),
                )
                .order_by(desc(CashTransaction.id))
            )
        ).all()
    )
    total_borrowed = sum(t.amount for t in txs if t.source_type == "kassa_debt")
    total_repaid = sum(t.amount for t in txs if t.source_type == "kassa_repay")
    return {
        "total_borrowed": total_borrowed,
        "total_repaid": total_repaid,
        "outstanding": total_borrowed - total_repaid,
        "recent_txs": txs[:limit],
    }


async def compute_session_summary(
    db: AsyncSession, session_id: Optional[int] = None
) -> SessionSummary:
    """Compute full live balance, transactions, and confirmed nakladnoy payments for a session."""
    if session_id is None:
        sess = await get_or_create_open_session(db)
        session_id = sess.id
    else:
        sess = await db.get(DailyCashSession, session_id)
        if sess is None:
            raise ValueError(f"Session {session_id} not found")

    txs = list(
        (
            await db.scalars(
                select(CashTransaction)
                .where(
                    CashTransaction.session_id == session_id,
                    CashTransaction.is_deleted.is_(False),
                )
                .order_by(CashTransaction.id)
            )
        ).all()
    )

    nakladnoys = list(
        (
            await db.scalars(
                select(NakladnoyPayment)
                .where(
                    NakladnoyPayment.session_id == session_id,
                    NakladnoyPayment.status == "confirmed",
                )
                .order_by(NakladnoyPayment.id)
            )
        ).all()
    )

    opening = float(sess.opening_balance or 0.0)
    main_in = sum(t.amount for t in txs if t.source_type == "main")
    kassa_debt_today = sum(t.amount for t in txs if t.source_type == "kassa_debt")
    kassa_repay_today = sum(t.amount for t in txs if t.source_type == "kassa_repay")
    total_available_inflow = opening + main_in + kassa_debt_today - kassa_repay_today
    total_nakladnoy_spent = sum(n.amount for n in nakladnoys)
    expected_cash = total_available_inflow - total_nakladnoy_spent

    if abs(sess.expected_cash - expected_cash) > 0.001:
        sess.expected_cash = expected_cash
        if sess.actual_counted_cash is not None:
            sess.difference = sess.actual_counted_cash - expected_cash
        await db.commit()
        await db.refresh(sess)

    outstanding_debt = await get_outstanding_kassa_debt(db)

    return SessionSummary(
        session=sess,
        opening_balance=opening,
        main_cash_in=main_in,
        kassa_debt_today=kassa_debt_today,
        kassa_repay_today=kassa_repay_today,
        total_available_inflow=total_available_inflow,
        total_nakladnoy_spent=total_nakladnoy_spent,
        expected_cash=expected_cash,
        total_kassa_debt_outstanding=outstanding_debt,
        cash_transactions=txs,
        confirmed_nakladnoys=nakladnoys,
    )


async def add_cash_transaction(
    db: AsyncSession,
    amount: float,
    source_type: str = "main",
    note: str = "",
    session_id: Optional[int] = None,
) -> CashTransaction:
    """Record a cash-in, kassa debt, or kassa repayment transaction in the active session."""
    if session_id is None:
        sess = await get_or_create_open_session(db)
        session_id = sess.id
    tx = CashTransaction(
        session_id=session_id,
        amount=float(amount),
        source_type=source_type,
        note=note.strip(),
        is_deleted=False,
    )
    db.add(tx)
    await db.commit()
    await db.refresh(tx)
    await compute_session_summary(db, session_id)
    return tx


async def update_cash_transaction(
    db: AsyncSession, tx_id: int, new_amount: Optional[float] = None, new_note: Optional[str] = None
) -> Optional[CashTransaction]:
    """Edit an existing cash transaction and recalculate session balance."""
    tx = await db.get(CashTransaction, tx_id)
    if tx is None or tx.is_deleted:
        return None
    old = f"summa={tx.amount:.0f}, izoh={tx.note}"
    if new_amount is not None:
        tx.amount = float(new_amount)
    if new_note is not None:
        tx.note = new_note.strip()
    await db.commit()
    await db.refresh(tx)
    await log_action(db, "edit", "cash", tx.id, f"{old} -> summa={tx.amount:.0f}, izoh={tx.note}")
    await compute_session_summary(db, tx.session_id)
    return tx


async def delete_cash_transaction(db: AsyncSession, tx_id: int) -> Optional[CashTransaction]:
    """Soft-delete a cash transaction and recalculate session balance."""
    tx = await db.get(CashTransaction, tx_id)
    if tx is None or tx.is_deleted:
        return None
    tx.is_deleted = True
    await db.commit()
    await db.refresh(tx)
    await log_action(db, "delete", "cash", tx.id, f"summa={tx.amount:.0f}, izoh={tx.note}")
    await compute_session_summary(db, tx.session_id)
    return tx


# ---------------------------------------------------------------------------
# Nakladnoy payments (pending, confirmed, editing confirmed)
# ---------------------------------------------------------------------------


async def create_pending_nakladnoy(
    db: AsyncSession,
    supplier_name: str = "",
    amount: float = 0.0,
    photo_file_id: Optional[str] = None,
    note: Optional[str] = None,
    session_id: Optional[int] = None,
) -> NakladnoyPayment:
    """Create a pending nakladnoy awaiting user confirmation."""
    if session_id is None:
        sess = await get_or_create_open_session(db)
        session_id = sess.id
    payment = NakladnoyPayment(
        session_id=session_id,
        supplier_name=supplier_name.strip(),
        amount=float(amount),
        photo_file_id=photo_file_id,
        note=note,
        status="pending",
    )
    db.add(payment)
    await db.commit()
    await db.refresh(payment)
    return payment


async def get_nakladnoy(db: AsyncSession, payment_id: int) -> Optional[NakladnoyPayment]:
    """Fetch a single NakladnoyPayment by id."""
    return await db.get(NakladnoyPayment, payment_id)


async def find_duplicate_confirmed_nakladnoy(
    db: AsyncSession, session_id: int, supplier_name: str, amount: float, exclude_id: Optional[int] = None
) -> Optional[NakladnoyPayment]:
    """Check if a confirmed nakladnoy with same supplier and amount already exists in this session."""
    stmt = select(NakladnoyPayment).where(
        NakladnoyPayment.session_id == session_id,
        NakladnoyPayment.status == "confirmed",
        NakladnoyPayment.amount == float(amount),
    )
    rows = (await db.scalars(stmt)).all()
    target = supplier_name.strip().lower()
    for row in rows:
        if exclude_id is not None and row.id == exclude_id:
            continue
        if row.supplier_name.strip().lower() == target:
            return row
    return None


async def confirm_nakladnoy(
    db: AsyncSession,
    payment_id: int,
    group_chat_id: Optional[int] = None,
    group_message_id: Optional[int] = None,
) -> Optional[NakladnoyPayment]:
    """Confirm a pending nakladnoy payment and attach group message metadata."""
    payment = await db.get(NakladnoyPayment, payment_id)
    if payment is None or payment.status == "deleted":
        return None
    payment.status = "confirmed"
    await log_action(db, "confirm", "nakladnoy", payment.id, f"{payment.supplier_name} / {payment.amount:.0f}")
    if group_chat_id is not None:
        payment.group_chat_id = group_chat_id
    if group_message_id is not None:
        payment.group_message_id = group_message_id
    await db.commit()
    await db.refresh(payment)
    await compute_session_summary(db, payment.session_id)
    return payment


async def set_nakladnoy_group_message(
    db: AsyncSession, payment_id: int, group_chat_id: Optional[int], group_message_id: Optional[int]
) -> Optional[NakladnoyPayment]:
    """Store or clear Telegram group chat_id and message_id after posting nakladnoy."""
    payment = await db.get(NakladnoyPayment, payment_id)
    if payment is None:
        return None
    payment.group_chat_id = group_chat_id
    payment.group_message_id = group_message_id
    await db.commit()
    await db.refresh(payment)
    return payment


async def update_nakladnoy(
    db: AsyncSession,
    payment_id: int,
    supplier_name: Optional[str] = None,
    amount: Optional[float] = None,
    note: Optional[str] = None,
) -> Optional[NakladnoyPayment]:
    """Update a pending or confirmed nakladnoy payment and recalculate session balance."""
    payment = await db.get(NakladnoyPayment, payment_id)
    if payment is None or payment.status == "deleted":
        return None
    old = f"{payment.supplier_name} / {payment.amount:.0f}"
    if supplier_name is not None:
        payment.supplier_name = supplier_name.strip()
    if amount is not None:
        payment.amount = float(amount)
    if note is not None:
        payment.note = note
    await db.commit()
    await db.refresh(payment)
    await log_action(db, "edit", "nakladnoy", payment.id, f"{old} -> {payment.supplier_name} / {payment.amount:.0f}")
    if payment.status == "confirmed":
        await compute_session_summary(db, payment.session_id)
    return payment


async def delete_nakladnoy(db: AsyncSession, payment_id: int) -> Optional[NakladnoyPayment]:
    """Soft-delete a pending or confirmed nakladnoy payment and recalculate session balance."""
    payment = await db.get(NakladnoyPayment, payment_id)
    if payment is None or payment.status == "deleted":
        return None
    was_confirmed = payment.status == "confirmed"
    payment.status = "deleted"
    await db.commit()
    await db.refresh(payment)
    await log_action(db, "delete", "nakladnoy", payment.id, f"{payment.supplier_name} / {payment.amount:.0f}")
    if was_confirmed:
        await compute_session_summary(db, payment.session_id)
    return payment


async def close_cash_session(
    db: AsyncSession, session_id: int, actual_counted_cash: float
) -> SessionSummary:
    """Close a cash session with actual counted cash, recording discrepancy into history."""
    summary = await compute_session_summary(db, session_id)
    sess = summary.session
    sess.actual_counted_cash = float(actual_counted_cash)
    sess.expected_cash = summary.expected_cash
    sess.difference = float(actual_counted_cash) - summary.expected_cash
    sess.status = "closed"
    sess.closed_at = now_local()
    await db.commit()
    await db.refresh(sess)
    return await compute_session_summary(db, session_id)


async def reopen_cash_session(db: AsyncSession, session_id: int) -> Optional[DailyCashSession]:
    """Reopen a closed session if user notices a mistake later and wants to edit."""
    current_open = await get_open_session(db)
    if current_open is not None and current_open.id != session_id:
        # Only reopen if current open session has no transactions yet, or keep open session intact
        current_summary = await compute_session_summary(db, current_open.id)
        if not current_summary.cash_transactions and not current_summary.confirmed_nakladnoys:
            await db.delete(current_open)
            await db.commit()
    sess = await db.get(DailyCashSession, session_id)
    if sess is None:
        return None
    sess.status = "open"
    sess.closed_at = None
    await db.commit()
    await db.refresh(sess)
    return sess


async def list_closed_sessions(db: AsyncSession, limit: int = 10) -> List[DailyCashSession]:
    """Return recent closed sessions for history viewing."""
    stmt = (
        select(DailyCashSession)
        .where(DailyCashSession.status == "closed")
        .order_by(desc(DailyCashSession.id))
        .limit(limit)
    )
    return list((await db.scalars(stmt)).all())


async def list_all_sessions(db: AsyncSession, limit: int = 15) -> List[DailyCashSession]:
    """Return recent open and closed daily sessions ordered newest first."""
    stmt = select(DailyCashSession).order_by(desc(DailyCashSession.id)).limit(limit)
    return list((await db.scalars(stmt)).all())


async def list_recent_nakladnoys(
    db: AsyncSession, limit: int = 50, offset: int = 0
) -> List[NakladnoyPayment]:
    """Return recent confirmed nakladnoy payments across all days."""
    stmt = (
        select(NakladnoyPayment)
        .where(NakladnoyPayment.status == "confirmed")
        .order_by(desc(NakladnoyPayment.id))
        .offset(offset)
        .limit(limit)
    )
    return list((await db.scalars(stmt)).all())


async def list_recent_cash_transactions(
    db: AsyncSession, limit: int = 50, offset: int = 0
) -> List[CashTransaction]:
    """Return recent non-deleted cash-in and kassa-debt transactions across all days."""
    stmt = (
        select(CashTransaction)
        .where(CashTransaction.is_deleted.is_(False))
        .order_by(desc(CashTransaction.id))
        .offset(offset)
        .limit(limit)
    )
    return list((await db.scalars(stmt)).all())


# ---------------------------------------------------------------------------
# Prixod (ITOG) Reports
# ---------------------------------------------------------------------------


async def save_prixod_report(
    db: AsyncSession,
    report_date: str,
    total_cost: float,
    total_price: float,
    formatted_text: str,
    rows_data: List[dict],
) -> PrixodReport:
    """Persist a draft PrixodReport and its parsed line items."""
    report = PrixodReport(
        report_date=report_date,
        total_cost=float(total_cost),
        total_price=float(total_price),
        formatted_text=formatted_text,
        status="draft",
    )
    db.add(report)
    await db.flush()

    for idx, r in enumerate(rows_data, start=1):
        db.add(
            PrixodRow(
                report_id=report.id,
                row_num=r.get("row_num", idx),
                supplier_raw=r.get("supplier_raw", ""),
                supplier_display=r.get("supplier_display", ""),
                note_raw=r.get("note_raw", ""),
                cost=float(r.get("cost", 0.0)),
                price=float(r.get("price", 0.0)),
                category=r.get("category", "nakladnoy"),
                old_date_label=r.get("old_date_label"),
                created_at_str=r.get("created_at_str", ""),
            )
        )
    await db.commit()
    return await get_prixod_report(db, report.id)  # type: ignore[return-value]


async def get_prixod_report(db: AsyncSession, report_id: int) -> Optional[PrixodReport]:
    """Fetch PrixodReport eager-loading its rows."""
    stmt = (
        select(PrixodReport)
        .options(selectinload(PrixodReport.rows))
        .where(PrixodReport.id == report_id)
    )
    return await db.scalar(stmt)


async def list_prixod_reports(db: AsyncSession, limit: int = 10) -> List[PrixodReport]:
    """Fetch recent PrixodReports."""
    stmt = (
        select(PrixodReport)
        .options(selectinload(PrixodReport.rows))
        .order_by(desc(PrixodReport.id))
        .limit(limit)
    )
    return list((await db.scalars(stmt)).all())


async def mark_prixod_published(
    db: AsyncSession,
    report_id: int,
    formatted_text: str,
    group_chat_id: Optional[int] = None,
    group_message_id: Optional[int] = None,
) -> Optional[PrixodReport]:
    """Mark PrixodReport as published and save group message reference."""
    report = await get_prixod_report(db, report_id)
    if report is None:
        return None
    report.status = "published"
    report.formatted_text = formatted_text
    if group_chat_id is not None:
        report.group_chat_id = group_chat_id
    if group_message_id is not None:
        report.group_message_id = group_message_id
    await db.commit()
    return await get_prixod_report(db, report_id)


# ---------------------------------------------------------------------------
# App Preferences & Amount Rounding
# ---------------------------------------------------------------------------


async def get_app_setting(db: AsyncSession, key: str, default: str = "") -> str:
    """Read a bot preference value from app_settings."""
    obj = await db.get(AppSetting, key)
    return obj.value if obj is not None else default


async def set_app_setting(db: AsyncSession, key: str, value: str) -> AppSetting:
    """Persist a bot preference value in app_settings."""
    obj = await db.get(AppSetting, key)
    if obj is None:
        obj = AppSetting(key=key, value=value)
        db.add(obj)
    else:
        obj.value = value
    await db.commit()
    await db.refresh(obj)
    return obj


def round_nakladnoy_amount(amount: float, mode: str = "floor_1000") -> float:
    """
    Round AI-extracted nakladnoy amount according to user preference.

    Modes:
    - "floor_1000": 192 620 -> 192 000 (default, drops odd hundreds/so'm)
    - "nearest_1000": 192 620 -> 193 000
    - "none": 192 620 -> 192 620
    """
    val = float(amount)
    if val <= 0:
        return 0.0
    if mode == "floor_1000" and val >= 1000:
        return float((int(val) // 1000) * 1000)
    if mode == "nearest_1000" and val >= 1000:
        return float(round(val / 1000.0) * 1000)
    return float(round(val))


# ---------------------------------------------------------------------------
# Audit log
# ---------------------------------------------------------------------------


async def log_action(
    db: AsyncSession, action: str, entity: str, entity_id: int, details: str = ""
) -> None:
    """Persist an audit record (own commit; failures never break the main flow)."""
    try:
        db.add(AuditLog(action=action, entity=entity, entity_id=int(entity_id), details=details[:2000]))
        await db.commit()
    except Exception:
        await db.rollback()


async def list_audit_logs(db: AsyncSession, limit: int = 20) -> List[AuditLog]:
    """Return the most recent audit records."""
    stmt = select(AuditLog).order_by(desc(AuditLog.id)).limit(limit)
    return list((await db.scalars(stmt)).all())