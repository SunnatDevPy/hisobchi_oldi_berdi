"""Async CRUD operations for wallet sessions, nakladnoy payments, groups, suppliers, and prixod reports."""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
import difflib
import re
from typing import Dict, List, Optional, Tuple
from zoneinfo import ZoneInfo

from sqlalchemy import desc, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from config import get_settings
from database.models import (
    AIUsageLog,
    AppSetting,
    AuditLog,
    CashReconciliation,
    CashTransaction,
    DailyCashSession,
    GroupConfig,
    NakladnoyPayment,
    PrixodReport,
    PrixodRow,
    SupplierConfig,
    SupplierDebt,
    UserRole,
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


VALID_PAYMENT_METHODS = ("cash", "card", "transfer")


def normalize_payment_method(payment_method: Optional[str]) -> str:
    """Normalize payment_method to one of cash | card | transfer (defaults to cash)."""
    val = (payment_method or "cash").strip().lower()
    return val if val in VALID_PAYMENT_METHODS else "cash"


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
    debt_nakladnoys: List[NakladnoyPayment] = field(default_factory=list)
    total_debt_nakladnoy: float = 0.0
    all_unpaid_debt_count: int = 0
    all_unpaid_debt_total: float = 0.0
    noncash_nakladnoys: List[NakladnoyPayment] = field(default_factory=list)
    total_card_spent: float = 0.0
    total_transfer_spent: float = 0.0
    expense_today: float = 0.0
    main_return_today: float = 0.0
    reconciliations: List[CashReconciliation] = field(default_factory=list)


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


async def delete_group_config(db: AsyncSession, role: str) -> bool:
    """Remove a configured Telegram group binding for a role."""
    obj = await db.scalar(select(GroupConfig).where(GroupConfig.role == role))
    if obj is None:
        return False
    await db.delete(obj)
    await db.commit()
    return True


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
        today_str = today_iso()
        if report_date is None and open_sess.report_date != today_str:
            has_tx = await db.scalar(
                select(func.count(CashTransaction.id)).where(
                    CashTransaction.session_id == open_sess.id,
                    CashTransaction.is_deleted.is_(False),
                )
            )
            has_nak = await db.scalar(
                select(func.count(NakladnoyPayment.id)).where(
                    NakladnoyPayment.session_id == open_sess.id,
                    NakladnoyPayment.status != "deleted",
                )
            )
            if not has_tx and not has_nak:
                open_sess.report_date = today_str
                open_sess.created_at = now_local()
                await db.commit()
                await db.refresh(open_sess)
        return open_sess

    last_closed = await get_last_closed_session(db)
    opening_balance = float(last_closed.actual_counted_cash or 0.0) if last_closed else 0.0

    new_sess = DailyCashSession(
        report_date=report_date or today_iso(),
        status="open",
        opening_balance=opening_balance,
        expected_cash=opening_balance,
        created_at=now_local(),
    )
    db.add(new_sess)
    await db.commit()
    await db.refresh(new_sess)
    return new_sess


def effective_tx_local_date(
    tx_dt: Optional[datetime], session: DailyCashSession
) -> str:
    """Return true local YYYY-MM-DD of a transaction, preserving synthetic report_date in tests."""
    sess_created = (
        format_local_dt(session.created_at, "%Y-%m-%d")
        if getattr(session, "created_at", None)
        else ""
    )
    if sess_created and sess_created != session.report_date:
        return session.report_date
    tx_date = format_local_dt(tx_dt, "%Y-%m-%d") if tx_dt else ""
    return tx_date or session.report_date


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


async def _sync_session_expected_cash(db: AsyncSession, session_id: int) -> None:
    """Lightweight recalculation of DailyCashSession.expected_cash without extra debt/history queries."""
    sess = await db.get(DailyCashSession, session_id)
    if sess is None:
        return
    tx_sums = dict(
        (
            await db.execute(
                select(
                    CashTransaction.source_type,
                    func.coalesce(func.sum(CashTransaction.amount), 0),
                )
                .where(
                    CashTransaction.session_id == session_id,
                    CashTransaction.is_deleted.is_(False),
                )
                .group_by(CashTransaction.source_type)
            )
        ).all()
    )
    cash_spent = float(
        await db.scalar(
            select(func.coalesce(func.sum(NakladnoyPayment.amount), 0)).where(
                NakladnoyPayment.session_id == session_id,
                NakladnoyPayment.status == "confirmed",
                NakladnoyPayment.is_debt.is_(False),
                or_(
                    NakladnoyPayment.payment_method == "cash",
                    NakladnoyPayment.payment_method.is_(None),
                ),
            )
        )
        or 0.0
    )
    opening = float(sess.opening_balance or 0.0)
    main_in = float(tx_sums.get("main") or 0.0)
    main_return = float(tx_sums.get("main_return") or 0.0)
    kassa_debt = float(tx_sums.get("kassa_debt") or 0.0)
    kassa_repay = float(tx_sums.get("kassa_repay") or 0.0)
    expense_out = float(tx_sums.get("expense") or 0.0)
    expected_cash = opening + main_in - main_return + kassa_debt - kassa_repay - expense_out - cash_spent

    if abs(float(sess.expected_cash or 0.0) - expected_cash) > 0.001:
        sess.expected_cash = expected_cash
        if sess.actual_counted_cash is not None:
            sess.difference = float(sess.actual_counted_cash) - expected_cash
        await db.commit()
        await db.refresh(sess)


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

    all_confirmed = list(
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
    nakladnoys = [
        n
        for n in all_confirmed
        if not n.is_debt and normalize_payment_method(getattr(n, "payment_method", "cash")) == "cash"
    ]
    noncash_nakladnoys = [
        n
        for n in all_confirmed
        if not n.is_debt and normalize_payment_method(getattr(n, "payment_method", "cash")) in ("card", "transfer")
    ]
    debt_nakladnoys = [n for n in all_confirmed if n.is_debt]

    opening = float(sess.opening_balance or 0.0)
    main_in = sum(t.amount for t in txs if t.source_type == "main")
    main_return_today = sum(t.amount for t in txs if t.source_type == "main_return")
    kassa_debt_today = sum(t.amount for t in txs if t.source_type == "kassa_debt")
    kassa_repay_today = sum(t.amount for t in txs if t.source_type == "kassa_repay")
    expense_today = sum(t.amount for t in txs if t.source_type == "expense")
    total_available_inflow = opening + main_in - main_return_today + kassa_debt_today - kassa_repay_today
    total_nakladnoy_spent = sum(n.amount for n in nakladnoys)
    total_card_spent = sum(
        n.amount
        for n in noncash_nakladnoys
        if normalize_payment_method(getattr(n, "payment_method", "cash")) == "card"
    )
    total_transfer_spent = sum(
        n.amount
        for n in noncash_nakladnoys
        if normalize_payment_method(getattr(n, "payment_method", "cash")) == "transfer"
    )
    total_debt_nakladnoy = sum(n.amount for n in debt_nakladnoys)
    expected_cash = total_available_inflow - total_nakladnoy_spent - expense_today

    if abs(sess.expected_cash - expected_cash) > 0.001:
        sess.expected_cash = expected_cash
        if sess.actual_counted_cash is not None:
            sess.difference = sess.actual_counted_cash - expected_cash
        await db.commit()
        await db.refresh(sess)

    outstanding_debt = await get_outstanding_kassa_debt(db)
    unpaid_cnt, unpaid_tot = (
        await db.execute(
            select(
                func.count(NakladnoyPayment.id),
                func.coalesce(func.sum(NakladnoyPayment.amount), 0),
            ).where(
                NakladnoyPayment.status == "confirmed",
                NakladnoyPayment.is_debt.is_(True),
            )
        )
    ).one()

    recs = list(
        (
            await db.scalars(
                select(CashReconciliation)
                .where(CashReconciliation.session_id == session_id)
                .order_by(CashReconciliation.created_at, CashReconciliation.id)
            )
        ).all()
    )

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
        debt_nakladnoys=debt_nakladnoys,
        total_debt_nakladnoy=total_debt_nakladnoy,
        all_unpaid_debt_count=int(unpaid_cnt or 0),
        all_unpaid_debt_total=float(unpaid_tot or 0),
        noncash_nakladnoys=noncash_nakladnoys,
        total_card_spent=total_card_spent,
        total_transfer_spent=total_transfer_spent,
        expense_today=expense_today,
        main_return_today=main_return_today,
        reconciliations=recs,
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
    await _sync_session_expected_cash(db, session_id)
    return tx


async def update_cash_transaction(
    db: AsyncSession,
    tx_id: int,
    new_amount: Optional[float] = None,
    new_note: Optional[str] = None,
    user_id: Optional[int] = None,
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
    await log_action(db, "edit", "cash", tx.id, f"{old} -> summa={tx.amount:.0f}, izoh={tx.note}", user_id=user_id)
    await _sync_session_expected_cash(db, tx.session_id)
    return tx


async def delete_cash_transaction(
    db: AsyncSession, tx_id: int, user_id: Optional[int] = None
) -> Optional[CashTransaction]:
    """Soft-delete a cash transaction and recalculate session balance."""
    tx = await db.get(CashTransaction, tx_id)
    if tx is None or tx.is_deleted:
        return None
    tx.is_deleted = True
    await db.commit()
    await db.refresh(tx)
    await log_action(db, "delete", "cash", tx.id, f"summa={tx.amount:.0f}, izoh={tx.note}", user_id=user_id)
    await _sync_session_expected_cash(db, tx.session_id)
    return tx


async def restore_cash_transaction(
    db: AsyncSession, tx_id: int, user_id: Optional[int] = None
) -> Optional[CashTransaction]:
    """Undo soft-delete on a CashTransaction and recalculate session balance."""
    tx = await db.get(CashTransaction, tx_id)
    if tx is None:
        return None
    if tx.is_deleted:
        tx.is_deleted = False
        await db.commit()
        await db.refresh(tx)
        await log_action(db, "restore", "cash", tx.id, f"summa={tx.amount:.0f}", user_id=user_id)
        await _sync_session_expected_cash(db, tx.session_id)
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
    photo_unique_id: Optional[str] = None,
    original_amount: Optional[float] = None,
) -> NakladnoyPayment:
    """Create a pending nakladnoy awaiting user confirmation."""
    if session_id is None:
        sess = await get_or_create_open_session(db)
        session_id = sess.id
    payment = NakladnoyPayment(
        session_id=session_id,
        supplier_name=supplier_name.strip(),
        amount=float(amount),
        original_amount=float(original_amount) if original_amount is not None else None,
        photo_file_id=photo_file_id,
        photo_unique_id=photo_unique_id,
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


async def get_nakladnoy_session_seq(
    db: AsyncSession, payment: Optional[NakladnoyPayment]
) -> Optional[int]:
    """Return 1-based ordinal of a confirmed nakladnoy within its daily session."""
    if payment is None or payment.status != "confirmed":
        return None
    cnt = await db.scalar(
        select(func.count(NakladnoyPayment.id)).where(
            NakladnoyPayment.session_id == payment.session_id,
            NakladnoyPayment.status == "confirmed",
            NakladnoyPayment.id <= payment.id,
        )
    )
    return int(cnt) if cnt else 1


async def find_nakladnoy_by_photo_unique_id(
    db: AsyncSession, photo_unique_id: str
) -> Optional[NakladnoyPayment]:
    """Find latest non-deleted nakladnoy sharing a Telegram photo_unique_id (confirmed preferred)."""
    if not photo_unique_id:
        return None
    stmt = (
        select(NakladnoyPayment)
        .where(
            NakladnoyPayment.photo_unique_id == photo_unique_id,
            NakladnoyPayment.status != "deleted",
        )
        .order_by(desc(NakladnoyPayment.id))
        .limit(10)
    )
    rows = list((await db.scalars(stmt)).all())
    for row in rows:
        if row.status == "confirmed":
            return row
    return rows[0] if rows else None


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
    user_id: Optional[int] = None,
    is_debt: bool = False,
    payment_method: str = "cash",
) -> Optional[NakladnoyPayment]:
    """Confirm a pending nakladnoy payment (cash/card/transfer or debt) and attach group metadata."""
    payment = await db.get(NakladnoyPayment, payment_id)
    if payment is None or payment.status == "deleted":
        return None
    pm = "cash" if is_debt else normalize_payment_method(payment_method)
    payment.status = "confirmed"
    payment.is_debt = bool(is_debt)
    payment.payment_method = pm
    payment.paid_at = None if is_debt else now_local()
    if group_chat_id is not None:
        payment.group_chat_id = group_chat_id
    if group_message_id is not None:
        payment.group_message_id = group_message_id
    await db.commit()
    await db.refresh(payment)
    if is_debt:
        action = "confirm_debt"
        tag = " [QARZ]"
    elif pm == "card":
        action = "confirm_card"
        tag = " [KARTA]"
    elif pm == "transfer":
        action = "confirm_transfer"
        tag = " [O'TKAZMA]"
    else:
        action = "confirm"
        tag = ""
    await log_action(
        db,
        action,
        "nakladnoy",
        payment.id,
        f"{payment.supplier_name} / {payment.amount:.0f}" + tag,
        user_id=user_id,
    )
    await _sync_session_expected_cash(db, payment.session_id)
    return payment


async def list_unpaid_debt_nakladnoys(
    db: AsyncSession,
) -> List[Tuple[NakladnoyPayment, str]]:
    """Return all confirmed unpaid credit nakladnoys (newest first) across all sessions."""
    stmt = (
        select(NakladnoyPayment, DailyCashSession.report_date)
        .join(DailyCashSession, DailyCashSession.id == NakladnoyPayment.session_id)
        .where(
            NakladnoyPayment.status == "confirmed",
            NakladnoyPayment.is_debt.is_(True),
        )
        .order_by(desc(NakladnoyPayment.id))
    )
    return list((await db.execute(stmt)).all())


async def mark_nakladnoy_as_debt(
    db: AsyncSession, payment_id: int, user_id: Optional[int] = None
) -> Optional[NakladnoyPayment]:
    """Convert a confirmed paid nakladnoy into unpaid debt and restore cash-on-hand."""
    payment = await db.get(NakladnoyPayment, payment_id)
    if payment is None or payment.status == "deleted":
        return None
    payment.status = "confirmed"
    payment.is_debt = True
    payment.payment_method = "cash"
    payment.paid_at = None
    await db.commit()
    await db.refresh(payment)
    await log_action(
        db,
        "mark_debt",
        "nakladnoy",
        payment.id,
        f"{payment.supplier_name} / {payment.amount:.0f}",
        user_id=user_id,
    )
    await _sync_session_expected_cash(db, payment.session_id)
    return payment


async def mark_nakladnoy_as_paid(
    db: AsyncSession,
    payment_id: int,
    user_id: Optional[int] = None,
    payment_method: str = "cash",
    partial_amount: Optional[float] = None,
) -> Optional[Tuple[NakladnoyPayment, bool]]:
    """Mark an unpaid debt nakladnoy as paid in full or partially (cash/card/transfer)."""
    payment = await db.get(NakladnoyPayment, payment_id)
    if payment is None or payment.status == "deleted":
        return None
    pm = normalize_payment_method(payment_method)

    if (
        payment.is_debt
        and partial_amount is not None
        and 0 < float(partial_amount) < float(payment.amount) - 0.01
    ):
        pay_amt = round(float(partial_amount), 2)
        rem_amt = round(float(payment.amount) - pay_amt, 2)
        if payment.original_amount is None:
            payment.original_amount = float(payment.amount)
        payment.amount = rem_amt
        stamp = format_local_dt(now_local(), "%d.%m %H:%M")
        part_tag = f"Qisman to'landi: {pay_amt:,.0f} ({stamp})".replace(",", " ")
        cur_note = (payment.note or "").strip()
        payment.note = f"{cur_note} | {part_tag}".strip(" |")

        active_sess = await get_or_create_open_session(db)
        paid_entry = NakladnoyPayment(
            session_id=active_sess.id,
            supplier_name=payment.supplier_name,
            amount=pay_amt,
            original_amount=pay_amt,
            note=f"Qisman to'lov (#{payment.id} qarzidan)",
            status="confirmed",
            is_debt=False,
            payment_method=pm,
            paid_at=now_local(),
            created_at=now_local(),
        )
        db.add(paid_entry)
        await db.commit()
        await db.refresh(payment)
        await db.refresh(paid_entry)
        await log_action(
            db,
            "partial_pay",
            "nakladnoy",
            payment.id,
            f"{payment.supplier_name}: -{pay_amt:.0f}, qoldiq={rem_amt:.0f} [{pm.upper()}]",
            user_id=user_id,
        )
        await _sync_session_expected_cash(db, active_sess.id)
        if payment.session_id != active_sess.id:
            await _sync_session_expected_cash(db, payment.session_id)
        return payment, True

    orig_sess = await db.get(DailyCashSession, payment.session_id)
    moved_to_today = False
    if orig_sess is not None and orig_sess.status == "closed":
        active_sess = await get_or_create_open_session(db)
        if active_sess.id != payment.session_id:
            payment.session_id = active_sess.id
            tag_note = f"Qarz ({orig_sess.report_date}) to'landi"
            cur_note = (payment.note or "").strip()
            if tag_note not in cur_note:
                payment.note = f"{cur_note} | {tag_note}".strip(" |")
            moved_to_today = True

    payment.status = "confirmed"
    payment.is_debt = False
    payment.payment_method = pm
    payment.paid_at = now_local()
    await db.commit()
    await db.refresh(payment)
    pm_suffix = " [KARTA]" if pm == "card" else (" [O'TKAZMA]" if pm == "transfer" else "")
    await log_action(
        db,
        "mark_paid",
        "nakladnoy",
        payment.id,
        f"{payment.supplier_name} / {payment.amount:.0f}"
        + pm_suffix
        + (" (bugunga o'tkazildi)" if moved_to_today else ""),
        user_id=user_id,
    )
    await _sync_session_expected_cash(db, payment.session_id)
    return payment, moved_to_today


async def set_nakladnoy_payment_method(
    db: AsyncSession,
    payment_id: int,
    payment_method: str,
    user_id: Optional[int] = None,
) -> Optional[Tuple[NakladnoyPayment, bool]]:
    """Switch a confirmed nakladnoy's payment method (cash | card | transfer).

    If it was currently an unpaid debt, delegates to ``mark_nakladnoy_as_paid`` so
    closed-day debts roll into today's open session. Returns ``(payment, moved_to_today)``.
    """
    pm = normalize_payment_method(payment_method)
    payment = await db.get(NakladnoyPayment, payment_id)
    if payment is None or payment.status == "deleted":
        return None
    if payment.is_debt:
        return await mark_nakladnoy_as_paid(db, payment_id, user_id=user_id, payment_method=pm)

    old_pm = normalize_payment_method(getattr(payment, "payment_method", "cash"))
    payment.status = "confirmed"
    payment.payment_method = pm
    if payment.paid_at is None:
        payment.paid_at = now_local()
    await db.commit()
    await db.refresh(payment)
    if old_pm != pm:
        pm_tags = {"cash": "NAQD", "card": "KARTA", "transfer": "O'TKAZMA"}
        await log_action(
            db,
            f"confirm_{pm}" if pm != "cash" else "confirm_cash",
            "nakladnoy",
            payment.id,
            f"{payment.supplier_name} / {payment.amount:.0f} [{pm_tags.get(pm, pm.upper())}]",
            user_id=user_id,
        )
    await _sync_session_expected_cash(db, payment.session_id)
    return payment, False


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
    user_id: Optional[int] = None,
    original_amount: Optional[float] = None,
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
    if original_amount is not None:
        payment.original_amount = float(original_amount)
    if note is not None:
        payment.note = note
    await db.commit()
    await db.refresh(payment)
    await log_action(
        db, "edit", "nakladnoy", payment.id, f"{old} -> {payment.supplier_name} / {payment.amount:.0f}", user_id=user_id
    )
    if payment.status == "confirmed":
        await _sync_session_expected_cash(db, payment.session_id)
    return payment


async def delete_nakladnoy(
    db: AsyncSession, payment_id: int, user_id: Optional[int] = None
) -> Optional[NakladnoyPayment]:
    """Soft-delete a pending or confirmed nakladnoy payment and recalculate session balance."""
    payment = await db.get(NakladnoyPayment, payment_id)
    if payment is None or payment.status == "deleted":
        return None
    was_confirmed = payment.status == "confirmed"
    payment.status = "deleted"
    await db.commit()
    await db.refresh(payment)
    await log_action(
        db, "delete", "nakladnoy", payment.id, f"{payment.supplier_name} / {payment.amount:.0f}", user_id=user_id
    )
    if was_confirmed:
        await _sync_session_expected_cash(db, payment.session_id)
    return payment


async def restore_nakladnoy(
    db: AsyncSession, payment_id: int, user_id: Optional[int] = None
) -> Optional[NakladnoyPayment]:
    """Undo soft-delete on a NakladnoyPayment and recalculate session balance."""
    payment = await db.get(NakladnoyPayment, payment_id)
    if payment is None:
        return None
    if payment.status == "deleted":
        payment.status = "confirmed"
        await db.commit()
        await db.refresh(payment)
        await log_action(
            db, "restore", "nakladnoy", payment.id, f"{payment.supplier_name} / {payment.amount:.0f}", user_id=user_id
        )
        await _sync_session_expected_cash(db, payment.session_id)
    return payment


VALID_RECONCILIATION_KINDS = ("interim", "closing")


async def create_cash_reconciliation(
    db: AsyncSession,
    counted_cash: float,
    *,
    kind: str = "interim",
    note: str = "",
    session_id: Optional[int] = None,
    user_id: Optional[int] = None,
) -> Tuple[CashReconciliation, str]:
    """Save an interim (non-mutating) or closing cash count snapshot for audit history."""
    summary = await compute_session_summary(db, session_id=session_id)
    norm_kind = "closing" if (kind or "").strip().lower() == "closing" else "interim"
    expected = float(summary.expected_cash)
    counted = float(counted_cash)
    rec = CashReconciliation(
        session_id=summary.session.id,
        kind=norm_kind,
        expected_cash=expected,
        counted_cash=counted,
        difference=counted - expected,
        note=(note or "").strip()[:500],
        created_by=user_id,
        created_at=now_local(),
    )
    db.add(rec)
    await db.commit()
    await db.refresh(rec)
    return rec, summary.session.report_date


async def list_cash_reconciliations(
    db: AsyncSession,
    *,
    session_id: Optional[int] = None,
    kind: Optional[str] = None,
    limit: int = 60,
) -> List[Tuple[CashReconciliation, str]]:
    """Return cash reconciliation snapshots ordered newest-first alongside session report_date."""
    stmt = (
        select(CashReconciliation, DailyCashSession.report_date)
        .join(DailyCashSession, DailyCashSession.id == CashReconciliation.session_id)
        .order_by(desc(CashReconciliation.created_at), desc(CashReconciliation.id))
        .limit(max(1, min(limit, 200)))
    )
    if session_id is not None:
        stmt = stmt.where(CashReconciliation.session_id == session_id)
    clean_kind = (kind or "").strip().lower()
    if clean_kind in VALID_RECONCILIATION_KINDS:
        stmt = stmt.where(CashReconciliation.kind == clean_kind)
    rows = (await db.execute(stmt)).all()
    return [(rec, str(report_date or "")) for rec, report_date in rows]


async def delete_cash_reconciliation(
    db: AsyncSession, rec_id: int
) -> Tuple[bool, str]:
    """Delete a temporary interim reconciliation; closing snapshots are protected."""
    rec = await db.get(CashReconciliation, rec_id)
    if rec is None:
        return False, "not_found"
    if rec.kind != "interim":
        return False, "closing_protected"
    await db.delete(rec)
    await db.commit()
    return True, "deleted"


async def close_cash_session(
    db: AsyncSession,
    session_id: int,
    actual_counted_cash: float,
    *,
    note: str = "",
    user_id: Optional[int] = None,
) -> SessionSummary:
    """Close a cash session with actual counted cash and persist the closing sverka."""
    summary = await compute_session_summary(db, session_id)
    sess = summary.session
    closed_ts = now_local()
    expected = float(summary.expected_cash)
    counted = float(actual_counted_cash)
    diff = counted - expected
    sess.actual_counted_cash = counted
    sess.expected_cash = expected
    sess.difference = diff
    sess.status = "closed"
    sess.closed_at = closed_ts
    db.add(
        CashReconciliation(
            session_id=sess.id,
            kind="closing",
            expected_cash=expected,
            counted_cash=counted,
            difference=diff,
            note=(note or "").strip()[:500],
            created_by=user_id,
            created_at=closed_ts,
        )
    )
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
    db: AsyncSession,
    action: str,
    entity: str,
    entity_id: int,
    details: str = "",
    user_id: Optional[int] = None,
) -> None:
    """Persist an audit record (own commit; failures never break the main flow)."""
    try:
        db.add(
            AuditLog(
                action=action,
                entity=entity,
                entity_id=int(entity_id),
                user_id=user_id,
                details=details[:2000],
            )
        )
        await db.commit()
    except Exception:
        await db.rollback()


async def list_audit_logs(db: AsyncSession, limit: int = 20) -> List[AuditLog]:
    """Return the most recent audit records."""
    stmt = select(AuditLog).order_by(desc(AuditLog.id)).limit(limit)
    return list((await db.scalars(stmt)).all())


# ---------------------------------------------------------------------------
# Supplier normalization, suggestions & reconciliation (sverka)
# ---------------------------------------------------------------------------


def _norm_key(name: str) -> str:
    return " ".join(name.strip().lower().split())


_CYR_TO_LAT_MAP: dict[str, str] = {
    "а": "a",
    "б": "b",
    "в": "v",
    "г": "g",
    "ғ": "g",
    "д": "d",
    "е": "e",
    "ё": "yo",
    "ж": "j",
    "з": "z",
    "и": "i",
    "й": "y",
    "к": "k",
    "қ": "q",
    "л": "l",
    "м": "m",
    "н": "n",
    "о": "o",
    "п": "p",
    "р": "r",
    "с": "s",
    "т": "t",
    "у": "u",
    "ў": "o",
    "ф": "f",
    "х": "x",
    "ҳ": "h",
    "ц": "ts",
    "ч": "ch",
    "ш": "sh",
    "щ": "sh",
    "ъ": "",
    "ы": "i",
    "ь": "",
    "э": "e",
    "ю": "yu",
    "я": "ya",
}

# Cursive handwritten lookalikes between Cyrillic & Latin (e.g. handwritten "Ummun" -> "Иттин" / "Ittin")
_CURSIVE_CHAR_MAP: dict[str, str] = {
    # Cyrillic cursive lookalikes -> Latin stroke class
    "и": "u",
    "й": "u",
    "у": "u",
    "ы": "u",
    "ю": "u",
    "т": "m",
    "м": "m",
    "п": "m",
    "н": "m",
    "ш": "m",
    "щ": "m",
    "а": "a",
    "о": "a",
    "ў": "a",
    "я": "a",
    "е": "e",
    "э": "e",
    "ё": "e",
    "р": "p",
    "с": "c",
    "х": "x",
    "ҳ": "x",
    "в": "b",
    "б": "b",
    "к": "k",
    "қ": "k",
    "г": "g",
    "ғ": "g",
    "д": "g",
    "л": "l",
    "з": "z",
    "ж": "j",
    "ч": "r",
    "ф": "f",
    "ц": "u",
    "ъ": "",
    "ь": "",
    # Latin cursive lookalikes -> unified stroke class
    "i": "u",
    "u": "u",
    "y": "u",
    "t": "m",
    "m": "m",
    "n": "m",
    "o": "a",
    "a": "a",
    "s": "c",
    "c": "c",
    "r": "p",
    "p": "p",
    "v": "b",
    "b": "b",
    "q": "k",
    "k": "k",
    "d": "g",
    "g": "g",
    "h": "x",
    "x": "x",
}


def _cyr_to_lat(text: str) -> str:
    """Transliterate Uzbek/Russian Cyrillic string into normalized Latin lowercase."""
    low = _norm_key(text)
    out: list[str] = []
    for ch in low:
        if ch in _CYR_TO_LAT_MAP:
            out.append(_CYR_TO_LAT_MAP[ch])
        elif ch.isalnum() or ch == " ":
            out.append(ch)
    return " ".join("".join(out).split())


def _cursive_skeleton(text: str) -> str:
    """Normalize Cyrillic/Latin text into a handwritten cursive stroke skeleton.

    Example: 'Ummun', 'Уммун', 'Иттин', and 'Ittin' all map to 'ummum'.
    """
    low = _norm_key(text)
    out: list[str] = []
    for ch in low:
        if ch in _CURSIVE_CHAR_MAP:
            out.append(_CURSIVE_CHAR_MAP[ch])
        elif ch.isalnum() or ch == " ":
            out.append(ch)
    return " ".join("".join(out).split())


def _cross_script_similarity(a: str, b: str) -> float:
    """Compute similarity score [0.0..1.0] across raw, Cyrillic<->Latin phonetic, and cursive handwriting."""
    a_low = _norm_key(a)
    b_low = _norm_key(b)
    if not a_low or not b_low:
        return 0.0
    if a_low == b_low:
        return 1.0

    direct = difflib.SequenceMatcher(None, a_low, b_low).ratio()

    a_lat = _cyr_to_lat(a_low)
    b_lat = _cyr_to_lat(b_low)
    phonetic = (
        0.99
        if (a_lat and a_lat == b_lat)
        else difflib.SequenceMatcher(None, a_lat, b_lat).ratio()
    )

    a_cur = _cursive_skeleton(a_low)
    b_cur = _cursive_skeleton(b_low)
    cursive = 0.0
    if len(a_cur) >= 3 and len(b_cur) >= 3:
        raw_cur = difflib.SequenceMatcher(None, a_cur, b_cur).ratio()
        # Penalize if length differs sharply so tiny words don't match long ones
        len_ratio = min(len(a_cur), len(b_cur)) / max(len(a_cur), len(b_cur))
        cursive = raw_cur * (0.75 + 0.21 * len_ratio)

    return max(direct, phonetic, cursive)


def parse_supplier_aliases(raw: str) -> List[str]:
    """Split comma/semicolon/newline-separated supplier aliases into clean unique strings."""
    if not raw:
        return []
    parts = re.split(r"[,;\n]+", raw)
    seen: set[str] = set()
    out: List[str] = []
    for p in parts:
        clean = " ".join(p.strip().split())
        key = _norm_key(clean)
        if clean and key and key not in seen:
            seen.add(key)
            out.append(clean)
    return out


async def _supplier_alias_lookup(db: AsyncSession) -> Dict[str, str]:
    """Map normalized lowercase & Cyrillic->Latin display names and aliases -> canonical display_name."""
    cfgs = await list_suppliers(db, active_only=True)
    mapping: Dict[str, str] = {}
    lat_mapping: Dict[str, str] = {}
    for cfg in cfgs:
        disp = " ".join((cfg.display_name or "").strip().split())
        if disp:
            dk = _norm_key(disp)
            mapping[dk] = disp
            dlat = _cyr_to_lat(disp)
            if len(dlat) >= 2:
                lat_mapping.setdefault(dlat, disp)
        for alias in parse_supplier_aliases(cfg.aliases or ""):
            ak = _norm_key(alias)
            if ak:
                mapping[ak] = disp
            alat = _cyr_to_lat(alias)
            if len(alat) >= 2:
                lat_mapping.setdefault(alat, disp)
    for k, v in lat_mapping.items():
        mapping.setdefault(k, v)
    return mapping


async def get_supplier_aliases_map(db: AsyncSession) -> Dict[str, List[str]]:
    """Return {_norm_key(display_name): [alias, ...]} for all active SupplierConfig records."""
    cfgs = await list_suppliers(db, active_only=True)
    result: Dict[str, List[str]] = {}
    for cfg in cfgs:
        disp = " ".join((cfg.display_name or "").strip().split())
        if not disp:
            continue
        dk = _norm_key(disp)
        aliases = [
            a for a in parse_supplier_aliases(cfg.aliases or "")
            if _norm_key(a) != dk
        ]
        result[dk] = aliases
    return result


async def update_supplier_aliases(
    db: AsyncSession,
    supplier_name: str,
    aliases: List[str],
    user_id: Optional[int] = None,
) -> dict:
    """Set the full list of alternative names (aliases) for a supplier."""
    clean_name = " ".join((supplier_name or "").strip().split())
    if not clean_name:
        raise ValueError("Postavshik nomini kiriting")
    target_key = _norm_key(clean_name)

    cfgs = await list_suppliers(db, active_only=False)
    target_cfg = next(
        (c for c in cfgs if _norm_key(c.display_name) == target_key),
        None,
    )
    cleaned_aliases: List[str] = []
    seen_keys: set[str] = {target_key}
    for raw_a in aliases:
        for part in parse_supplier_aliases(raw_a):
            pk = _norm_key(part)
            if pk and pk not in seen_keys:
                seen_keys.add(pk)
                cleaned_aliases.append(part)

    alias_str = ", ".join(cleaned_aliases)
    if target_cfg is None:
        order_num = max((c.order_num for c in cfgs), default=0) + 1
        target_cfg = SupplierConfig(
            order_num=order_num,
            display_name=clean_name,
            aliases=alias_str,
            default_category="qarz",
            is_active=True,
        )
        db.add(target_cfg)
    else:
        target_cfg.aliases = alias_str
        target_cfg.is_active = True

    await db.commit()
    await db.refresh(target_cfg)
    await log_action(
        db,
        "edit",
        "supplier_aliases",
        target_cfg.id,
        f"{target_cfg.display_name}: [{alias_str}]",
        user_id=user_id,
    )
    return {
        "id": int(target_cfg.id),
        "supplier_name": target_cfg.display_name,
        "aliases": cleaned_aliases,
        "aliases_str": alias_str,
    }


async def find_duplicate_supplier_groups(db: AsyncSession) -> List[dict]:
    """Detect unmerged supplier name duplicates (case & Cyrillic<->Latin variants like Nafis/nafis/нафис)."""
    raw_counts: Counter[str] = Counter()

    nak_names = (
        await db.scalars(
            select(NakladnoyPayment.supplier_name).where(
                NakladnoyPayment.status == "confirmed"
            )
        )
    ).all()
    for s in nak_names:
        clean = " ".join((s or "").strip().split())
        if clean:
            raw_counts[clean] += 1

    debt_names = (
        await db.scalars(
            select(SupplierDebt.supplier_name).where(
                SupplierDebt.is_deleted.is_(False)
            )
        )
    ).all()
    for s in debt_names:
        clean = " ".join((s or "").strip().split())
        if clean:
            raw_counts[clean] += 1

    cfgs = await list_suppliers(db, active_only=True)
    cfg_display_by_norm: Dict[str, str] = {}
    alias_to_cfg_lat: Dict[str, str] = {}
    for c in cfgs:
        disp = " ".join((c.display_name or "").strip().split())
        if not disp:
            continue
        raw_counts.setdefault(disp, 0)
        cfg_display_by_norm[_norm_key(disp)] = disp
        dlat = _cyr_to_lat(disp) or _norm_key(disp)
        for a in parse_supplier_aliases(c.aliases or ""):
            alat = _cyr_to_lat(a) or _norm_key(a)
            if alat:
                alias_to_cfg_lat[alat] = dlat

    groups: Dict[str, List[str]] = {}
    for raw_name in raw_counts:
        lat_key = _cyr_to_lat(raw_name) or _norm_key(raw_name)
        cluster_key = alias_to_cfg_lat.get(lat_key, lat_key)
        groups.setdefault(cluster_key, []).append(raw_name)

    def _is_latin_preferred(name: str) -> int:
        has_cyr = any("а" <= ch.lower() <= "я" or ch.lower() in "ёўқғҳ" for ch in name)
        has_upper = any(ch.isupper() for ch in name)
        return (0 if has_cyr else 2) + (1 if has_upper else 0)

    out: List[dict] = []
    for variants in groups.values():
        if len(variants) < 2:
            continue
        # Pick best suggested canonical name
        cfg_match = next(
            (cfg_display_by_norm[_norm_key(v)] for v in variants if _norm_key(v) in cfg_display_by_norm),
            None,
        )
        ranked = sorted(
            variants,
            key=lambda v: (-raw_counts[v], -_is_latin_preferred(v), v.lower()),
        )
        suggested = cfg_match or ranked[0]
        total_cnt = sum(raw_counts[v] for v in variants)
        out.append(
            {
                "suggested_target": suggested,
                "variants": [{"name": v, "count": int(raw_counts[v])} for v in ranked],
                "total_count": int(total_cnt),
            }
        )

    out.sort(key=lambda g: (-g["total_count"], g["suggested_target"].lower()))
    return out


async def merge_suppliers(
    db: AsyncSession,
    target_name: str,
    source_names: List[str],
    extra_aliases: Optional[List[str]] = None,
    user_id: Optional[int] = None,
) -> dict:
    """Merge multiple supplier names into one canonical target, rewriting history & saving aliases."""
    target = " ".join((target_name or "").strip().split())
    if not target:
        raise ValueError("Asosiy postavshik nomini kiriting")
    target_key = _norm_key(target)

    cleaned_sources: List[str] = []
    merge_keys: set[str] = {target_key}
    for s in source_names:
        cs = " ".join((s or "").strip().split())
        sk = _norm_key(cs)
        if cs and sk:
            merge_keys.add(sk)
            if cs != target and cs not in cleaned_sources:
                cleaned_sources.append(cs)

    # 1. Consolidate SupplierConfig records and collect all aliases
    all_cfgs = await list_suppliers(db, active_only=False)
    matched_cfgs = [c for c in all_cfgs if _norm_key(c.display_name) in merge_keys]

    alias_candidates: List[str] = []
    for c in matched_cfgs:
        if c.display_name:
            alias_candidates.append(c.display_name)
        alias_candidates.extend(parse_supplier_aliases(c.aliases or ""))
    alias_candidates.extend(cleaned_sources)
    for ea in extra_aliases or []:
        alias_candidates.extend(parse_supplier_aliases(ea))

    final_aliases: List[str] = []
    seen_alias_keys: set[str] = {target_key}
    for cand in alias_candidates:
        cc = " ".join(cand.strip().split())
        ck = _norm_key(cc)
        if cc and ck and ck not in seen_alias_keys:
            seen_alias_keys.add(ck)
            final_aliases.append(cc)

    target_cfg: Optional[SupplierConfig] = next(
        (c for c in matched_cfgs if c.display_name == target),
        None,
    )
    if target_cfg is None:
        target_cfg = next(
            (c for c in matched_cfgs if _norm_key(c.display_name) == target_key),
            matched_cfgs[0] if matched_cfgs else None,
        )

    removed_cfg_count = 0
    for c in matched_cfgs:
        if target_cfg is not None and c.id != target_cfg.id:
            await db.delete(c)
            removed_cfg_count += 1
    if removed_cfg_count > 0:
        await db.flush()

    alias_str = ", ".join(final_aliases)
    if target_cfg is None:
        order_num = max((c.order_num for c in all_cfgs), default=0) + 1
        target_cfg = SupplierConfig(
            order_num=order_num,
            display_name=target,
            aliases=alias_str,
            default_category="qarz",
            is_active=True,
        )
        db.add(target_cfg)
        await db.flush()
    else:
        target_cfg.display_name = target
        target_cfg.aliases = alias_str
        target_cfg.is_active = True

    # 2. Rewrite NakladnoyPayment rows matching any merged key to target_name
    nak_rows = (
        await db.scalars(
            select(NakladnoyPayment).where(
                NakladnoyPayment.status.in_(["confirmed", "pending"])
            )
        )
    ).all()
    updated_nak = 0
    for pay in nak_rows:
        if _norm_key(pay.supplier_name or "") in merge_keys and pay.supplier_name != target:
            pay.supplier_name = target
            updated_nak += 1

    # 3. Rewrite SupplierDebt rows matching any merged key to target_name
    debt_rows = (
        await db.scalars(
            select(SupplierDebt).where(SupplierDebt.is_deleted.is_(False))
        )
    ).all()
    updated_debts = 0
    for debt in debt_rows:
        if _norm_key(debt.supplier_name or "") in merge_keys and debt.supplier_name != target:
            debt.supplier_name = target
            updated_debts += 1

    await db.commit()
    await db.refresh(target_cfg)
    await log_action(
        db,
        "merge",
        "supplier",
        target_cfg.id,
        f"{cleaned_sources} -> {target} (nak={updated_nak}, debts={updated_debts})",
        user_id=user_id,
    )
    return {
        "ok": True,
        "target_name": target_cfg.display_name,
        "aliases": final_aliases,
        "aliases_str": alias_str,
        "merged_sources": cleaned_sources,
        "updated_nakladnoys": updated_nak,
        "updated_debts": updated_debts,
        "removed_configs": removed_cfg_count,
    }


async def find_similar_suppliers(
    db: AsyncSession,
    raw_name: str,
    limit: int = 4,
    cutoff: float = 0.64,
) -> List[str]:
    """Find top similar suppliers in DB using Cyrillic<->Latin phonetic + cursive handwriting matching."""
    cleaned = " ".join((raw_name or "").strip().split())
    if not cleaned:
        return []
    low = cleaned.lower()

    alias_map = await _supplier_alias_lookup(db)
    known = await get_all_known_suppliers(db)

    # Candidate key -> canonical display name
    all_lookup: Dict[str, str] = {}
    for k in reversed(known):
        all_lookup[_norm_key(k)] = k
    all_lookup.update(alias_map)

    scored_by_canon: Dict[str, float] = {}
    for cand_key, canon_name in all_lookup.items():
        if canon_name.lower() == low:
            continue
        score = _cross_script_similarity(low, cand_key)
        # Also check first word similarity for multi-word supplier names
        first_word = cand_key.split()[0] if cand_key.split() else ""
        if len(first_word) >= 4 and len(low.split()) == 1:
            score = max(score, _cross_script_similarity(low, first_word) * 0.93)
        if score >= cutoff:
            prev = scored_by_canon.get(canon_name, 0.0)
            if score > prev:
                scored_by_canon[canon_name] = score

    ranked = sorted(scored_by_canon.items(), key=lambda kv: (-kv[1], kv[0]))
    return [name for name, _ in ranked[:limit]]


async def resolve_supplier_name(
    db: AsyncSession, raw_name: str
) -> Tuple[str, Optional[str]]:
    """Normalize supplier name via SupplierConfig aliases & history, returning (canonical, fuzzy_suggestion)."""
    cleaned = " ".join(raw_name.strip().split())
    if not cleaned:
        return "", None
    low = cleaned.lower()

    alias_map = await _supplier_alias_lookup(db)
    if low in alias_map:
        return alias_map[low], None
    lat = _cyr_to_lat(cleaned)
    if len(lat) >= 2 and lat in alias_map:
        return alias_map[lat], None

    hist_rows = (
        await db.scalars(
            select(NakladnoyPayment.supplier_name).where(
                NakladnoyPayment.status == "confirmed"
            )
        )
    ).all()
    casing_counts: Dict[str, Counter[str]] = {}
    lat_counts: Dict[str, Counter[str]] = {}
    for s in hist_rows:
        s_clean = " ".join(s.strip().split())
        if s_clean:
            casing_counts.setdefault(s_clean.lower(), Counter())[s_clean] += 1
            s_lat = _cyr_to_lat(s_clean)
            if len(s_lat) >= 2:
                lat_counts.setdefault(s_lat, Counter())[s_clean] += 1
    hist_canonical = {k: cnt.most_common(1)[0][0] for k, cnt in casing_counts.items()}

    if low in hist_canonical:
        return hist_canonical[low], None

    if len(lat) >= 2 and lat in lat_counts:
        return lat_counts[lat].most_common(1)[0][0], None

    similar = await find_similar_suppliers(db, cleaned, limit=1, cutoff=0.68)
    if similar:
        return cleaned, similar[0]
    return cleaned, None


async def get_recent_suppliers(db: AsyncSession, limit: int = 6) -> List[str]:
    """Return distinct recently paid suppliers ordered most recent first."""
    stmt = (
        select(NakladnoyPayment.supplier_name)
        .where(NakladnoyPayment.status == "confirmed")
        .order_by(desc(NakladnoyPayment.id))
        .limit(limit * 8)
    )
    seen: set[str] = set()
    result: List[str] = []
    for raw in (await db.scalars(stmt)).all():
        name = " ".join(raw.strip().split())
        if name and name.lower() not in seen:
            seen.add(name.lower())
            result.append(name)
            if len(result) >= limit:
                break
    return result


async def get_all_known_suppliers(
    db: AsyncSession, limit: Optional[int] = None
) -> List[str]:
    """Return all distinct canonical suppliers (confirmed history, configs, debts), most recent first."""
    alias_map = await _supplier_alias_lookup(db)
    seen: set[str] = set()
    result: List[str] = []

    def _add(raw_name: str) -> None:
        cleaned = " ".join((raw_name or "").strip().split())
        if not cleaned:
            return
        canon = alias_map.get(_norm_key(cleaned), cleaned)
        key = _norm_key(canon)
        if key and key not in seen:
            seen.add(key)
            result.append(canon)

    paid_rows = (
        await db.scalars(
            select(NakladnoyPayment.supplier_name)
            .where(NakladnoyPayment.status == "confirmed")
            .order_by(desc(NakladnoyPayment.id))
        )
    ).all()
    for sup in paid_rows:
        _add(sup)

    for cfg in await list_suppliers(db, active_only=True):
        _add(cfg.display_name)

    debt_rows = (
        await db.scalars(
            select(SupplierDebt.supplier_name)
            .where(SupplierDebt.is_deleted.is_(False))
            .order_by(desc(SupplierDebt.id))
        )
    ).all()
    for sup in debt_rows:
        _add(sup)

    return result[:limit] if limit is not None else result


async def get_recent_amounts_for_supplier(
    db: AsyncSession, supplier_name: str, limit: int = 3
) -> List[float]:
    """Return last ``limit`` distinct confirmed amounts paid to ``supplier_name``."""
    target = _norm_key(supplier_name)
    if not target:
        return []
    stmt = (
        select(NakladnoyPayment.supplier_name, NakladnoyPayment.amount)
        .where(NakladnoyPayment.status == "confirmed")
        .order_by(desc(NakladnoyPayment.id))
        .limit(120)
    )
    seen: set[int] = set()
    amounts: List[float] = []
    for sup, amt in (await db.execute(stmt)).all():
        if _norm_key(sup) != target:
            continue
        rounded = round(float(amt))
        if rounded > 0 and rounded not in seen:
            seen.add(rounded)
            amounts.append(float(rounded))
            if len(amounts) >= limit:
                break
    return amounts


async def get_supplier_sverka(
    db: AsyncSession, month: str, supplier: Optional[str] = None
) -> List[dict]:
    """Confirmed nakladnoys for ``month`` (YYYY-MM), optionally filtered by supplier."""
    stmt = (
        select(NakladnoyPayment, DailyCashSession.report_date)
        .join(DailyCashSession, DailyCashSession.id == NakladnoyPayment.session_id)
        .where(
            NakladnoyPayment.status == "confirmed",
            NakladnoyPayment.is_debt.is_(False),
            DailyCashSession.report_date.like(f"{month}-%"),
        )
        .order_by(DailyCashSession.report_date, NakladnoyPayment.id)
    )
    rows = (await db.execute(stmt)).all()
    alias_map = await _supplier_alias_lookup(db)
    target = _norm_key(supplier) if supplier else None
    target_canon = alias_map.get(target, target) if target else None

    result: List[dict] = []
    for pay, report_date in rows:
        raw_name = " ".join(pay.supplier_name.strip().split())
        canon_name = alias_map.get(raw_name.lower(), raw_name)
        if target and _norm_key(canon_name) != _norm_key(target_canon or target) and _norm_key(raw_name) != target:
            continue
        result.append(
            {
                "supplier": canon_name,
                "amount": float(pay.amount),
                "original_amount": float(pay.original_amount) if pay.original_amount is not None else None,
                "payment_method": normalize_payment_method(getattr(pay, "payment_method", "cash")),
                "in_group": bool(pay.group_message_id),
                "photo_file_id": pay.photo_file_id,
                "group_chat_id": pay.group_chat_id,
                "group_message_id": pay.group_message_id,
                "date": report_date,
                "time": format_local_dt(pay.created_at, "%H:%M") if pay.created_at else "",
                "note": pay.note or "",
            }
        )
    return result


# ---------------------------------------------------------------------------
# History Search, Range Queries & Period Statistics
# ---------------------------------------------------------------------------


async def search_nakladnoys(
    db: AsyncSession, query: str, limit: int = 25
) -> List[Tuple[NakladnoyPayment, str]]:
    """Search confirmed nakladnoys by date (YYYY-MM-DD / YYYY-MM / DD.MM.YYYY) or supplier/note substring."""
    q = query.strip()
    if not q:
        return []

    date_iso_prefix: Optional[str] = None
    m_dmy = re.fullmatch(r"(\d{2})\.(\d{2})\.(\d{4})", q)
    if m_dmy:
        date_iso_prefix = f"{m_dmy.group(3)}-{m_dmy.group(2)}-{m_dmy.group(1)}"
    elif re.fullmatch(r"\d{4}-\d{2}(?:-\d{2})?", q):
        date_iso_prefix = q

    stmt = (
        select(NakladnoyPayment, DailyCashSession.report_date)
        .join(DailyCashSession, DailyCashSession.id == NakladnoyPayment.session_id)
        .where(NakladnoyPayment.status == "confirmed")
        .order_by(desc(NakladnoyPayment.id))
    )
    if date_iso_prefix:
        stmt = stmt.where(DailyCashSession.report_date.like(f"{date_iso_prefix}%")).limit(limit)
        return list((await db.execute(stmt)).all())

    low = q.lower()
    all_rows = (await db.execute(stmt.limit(500))).all()
    matched: List[Tuple[NakladnoyPayment, str]] = []
    for pay, r_date in all_rows:
        if low in (pay.supplier_name or "").lower() or low in (pay.note or "").lower():
            matched.append((pay, r_date))
            if len(matched) >= limit:
                break
    return matched


async def get_range_report_data(
    db: AsyncSession, date_from: str, date_to: str
) -> dict:
    """Collect sessions, confirmed nakladnoys, cash transactions, and kassa debt across [date_from, date_to]."""
    try:
        lower_bound = (
            datetime.strptime(date_from, "%Y-%m-%d").date() - timedelta(days=7)
        ).strftime("%Y-%m-%d")
    except Exception:
        lower_bound = date_from

    cand_sessions = list(
        (
            await db.scalars(
                select(DailyCashSession)
                .where(
                    DailyCashSession.report_date >= lower_bound,
                    DailyCashSession.report_date <= date_to,
                )
                .order_by(DailyCashSession.report_date, DailyCashSession.id)
            )
        ).all()
    )

    cand_naks = list(
        (
            await db.execute(
                select(NakladnoyPayment, DailyCashSession)
                .join(DailyCashSession, DailyCashSession.id == NakladnoyPayment.session_id)
                .where(
                    NakladnoyPayment.status == "confirmed",
                    NakladnoyPayment.is_debt.is_(False),
                    DailyCashSession.report_date >= lower_bound,
                    DailyCashSession.report_date <= date_to,
                )
                .order_by(NakladnoyPayment.id)
            )
        ).all()
    )
    nak_rows: List[Tuple[NakladnoyPayment, str]] = []
    active_sess_ids: set[int] = set()
    for pay, sess in cand_naks:
        eff_date = effective_tx_local_date(pay.paid_at or pay.created_at, sess)
        if date_from <= eff_date <= date_to:
            nak_rows.append((pay, eff_date))
            active_sess_ids.add(int(sess.id))

    cand_cash = list(
        (
            await db.execute(
                select(CashTransaction, DailyCashSession)
                .join(DailyCashSession, DailyCashSession.id == CashTransaction.session_id)
                .where(
                    CashTransaction.is_deleted.is_(False),
                    DailyCashSession.report_date >= lower_bound,
                    DailyCashSession.report_date <= date_to,
                )
                .order_by(CashTransaction.id)
            )
        ).all()
    )
    cash_rows: List[Tuple[CashTransaction, str]] = []
    for tx, sess in cand_cash:
        eff_date = effective_tx_local_date(tx.created_at, sess)
        if date_from <= eff_date <= date_to:
            cash_rows.append((tx, eff_date))
            active_sess_ids.add(int(sess.id))

    cand_recs = list(
        (
            await db.execute(
                select(CashReconciliation, DailyCashSession)
                .join(DailyCashSession, DailyCashSession.id == CashReconciliation.session_id)
                .where(
                    DailyCashSession.report_date >= lower_bound,
                    DailyCashSession.report_date <= date_to,
                )
                .order_by(CashReconciliation.created_at, CashReconciliation.id)
            )
        ).all()
    )
    rec_rows: List[Tuple[CashReconciliation, str]] = []
    for rec, sess in cand_recs:
        eff_date = effective_tx_local_date(rec.created_at, sess)
        if date_from <= eff_date <= date_to:
            rec_rows.append((rec, eff_date))
            active_sess_ids.add(int(sess.id))

    sessions = [
        s
        for s in cand_sessions
        if (date_from <= s.report_date <= date_to) or (int(s.id) in active_sess_ids)
    ]

    kassa_stats = await get_kassa_debt_stats(db, limit=10)
    return {
        "sessions": sessions,
        "nakladnoys": nak_rows,
        "cash_txs": cash_rows,
        "reconciliations": rec_rows,
        "kassa_stats": kassa_stats,
    }


async def get_period_statistics(db: AsyncSession, date_from: str, date_to: str) -> dict:
    """Compute aggregated spending & top suppliers statistics for [date_from, date_to]."""
    data = await get_range_report_data(db, date_from, date_to)
    nak_rows: List[Tuple[NakladnoyPayment, str]] = data["nakladnoys"]
    cash_rows: List[Tuple[CashTransaction, str]] = data["cash_txs"]
    alias_map = await _supplier_alias_lookup(db)

    total_spent = sum(float(n.amount) for n, _ in nak_rows)
    count = len(nak_rows)
    pm_totals = {"cash": 0.0, "card": 0.0, "transfer": 0.0}
    pm_counts = {"cash": 0, "card": 0, "transfer": 0}
    by_day: Dict[str, float] = {}
    by_day_count: Dict[str, int] = {}
    by_day_cash_in: Dict[str, float] = {}
    by_sup: Dict[str, list] = {}

    for pay, r_date in nak_rows:
        pm = normalize_payment_method(getattr(pay, "payment_method", "cash"))
        pm_totals[pm] += float(pay.amount)
        pm_counts[pm] += 1
        by_day[r_date] = by_day.get(r_date, 0.0) + float(pay.amount)
        by_day_count[r_date] = by_day_count.get(r_date, 0) + 1
        raw_name = " ".join(pay.supplier_name.strip().split())
        canon = alias_map.get(raw_name.lower(), raw_name)
        entry = by_sup.setdefault(canon.lower(), [canon, 0, 0.0])
        entry[1] += 1
        entry[2] += float(pay.amount)

    expense_spent = 0.0
    for tx, r_date in cash_rows:
        if tx.source_type == "main":
            by_day_cash_in[r_date] = by_day_cash_in.get(r_date, 0.0) + float(tx.amount)
        elif tx.source_type == "main_return":
            by_day_cash_in[r_date] = by_day_cash_in.get(r_date, 0.0) - float(tx.amount)
        elif tx.source_type == "expense":
            expense_spent += float(tx.amount)
            by_day[r_date] = by_day.get(r_date, 0.0) + float(tx.amount)

    is_single_day = date_from == date_to
    if is_single_day:
        by_hour_spent: Dict[int, float] = {}
        by_hour_count: Dict[int, int] = {}
        by_hour_cash_in: Dict[int, float] = {}
        for pay, _ in nak_rows:
            hr_str = format_local_dt(pay.created_at, "%H")
            hr = int(hr_str) if hr_str.isdigit() else 12
            by_hour_spent[hr] = by_hour_spent.get(hr, 0.0) + float(pay.amount)
            by_hour_count[hr] = by_hour_count.get(hr, 0) + 1
        for tx, _ in cash_rows:
            hr_str = format_local_dt(tx.created_at, "%H")
            hr = int(hr_str) if hr_str.isdigit() else 12
            if tx.source_type == "main":
                by_hour_cash_in[hr] = by_hour_cash_in.get(hr, 0.0) + float(tx.amount)
            elif tx.source_type == "main_return":
                by_hour_cash_in[hr] = by_hour_cash_in.get(hr, 0.0) - float(tx.amount)
            elif tx.source_type == "expense":
                by_hour_spent[hr] = by_hour_spent.get(hr, 0.0) + float(tx.amount)

        active_hours = set(by_hour_spent.keys()) | set(by_hour_cash_in.keys())
        is_today = date_from == today_iso()
        if active_hours:
            start_hr = max(0, min(8, min(active_hours)))
            end_hr = (
                min(23, max(max(active_hours), now_local().hour))
                if is_today
                else min(23, max(max(active_hours), 20))
            )
            if end_hr - start_hr < 5:
                end_hr = min(23, start_hr + 5)
            if end_hr - start_hr < 5:
                start_hr = max(0, end_hr - 5)
        else:
            start_hr = 8
            end_hr = max(14, min(20, now_local().hour)) if is_today else 20

        daily_series = [
            {
                "date": f"{h:02d}:00",
                "label": f"{h:02d}:00–{h:02d}:59",
                "full_date": date_from,
                "spent": float(by_hour_spent.get(h, 0.0)),
                "cash_in": round(max(0.0, float(by_hour_cash_in.get(h, 0.0))), 2),
                "count": int(by_hour_count.get(h, 0)),
            }
            for h in range(start_hr, end_hr + 1)
        ]
        granularity = "hourly"
    else:
        cal_keys: set[str] = set(by_day.keys()) | set(by_day_cash_in.keys())
        try:
            d_start = datetime.strptime(date_from, "%Y-%m-%d").date()
            d_end = datetime.strptime(date_to, "%Y-%m-%d").date()
            span = (d_end - d_start).days
            if 0 <= span <= 90:
                for offset in range(span + 1):
                    cal_keys.add((d_start + timedelta(days=offset)).strftime("%Y-%m-%d"))
        except Exception:
            pass
        all_day_keys = sorted(cal_keys)
        daily_series = [
            {
                "date": d,
                "spent": float(by_day.get(d, 0.0)),
                "cash_in": round(max(0.0, float(by_day_cash_in.get(d, 0.0))), 2),
                "count": int(by_day_count.get(d, 0)),
            }
            for d in all_day_keys
        ]
        granularity = "daily"

    active_days = len(by_day)
    avg_daily = (total_spent / active_days) if active_days else 0.0
    avg_payment = (total_spent / count) if count else 0.0
    busiest_day = max(by_day.items(), key=lambda kv: kv[1]) if by_day else None

    top_suppliers = []
    for name, cnt, tot in sorted(by_sup.values(), key=lambda x: -x[2])[:10]:
        pct = (tot / total_spent * 100.0) if total_spent > 0 else 0.0
        top_suppliers.append((name, cnt, tot, pct))

    return {
        "date_from": date_from,
        "date_to": date_to,
        "granularity": granularity,
        "total_spent": total_spent,
        "expense_spent": expense_spent,
        "cash_spent": pm_totals["cash"],
        "card_spent": pm_totals["card"],
        "transfer_spent": pm_totals["transfer"],
        "cash_count": pm_counts["cash"],
        "card_count": pm_counts["card"],
        "transfer_count": pm_counts["transfer"],
        "payment_count": count,
        "active_days": active_days,
        "avg_daily_spend": avg_daily,
        "avg_payment": avg_payment,
        "total_cash_in": (
            sum(float(t.amount) for t, _ in cash_rows if t.source_type == "main")
            - sum(float(t.amount) for t, _ in cash_rows if t.source_type == "main_return")
        ),
        "main_returned": sum(float(t.amount) for t, _ in cash_rows if t.source_type == "main_return"),
        "kassa_borrowed": sum(float(t.amount) for t, _ in cash_rows if t.source_type == "kassa_debt"),
        "kassa_repaid": sum(float(t.amount) for t, _ in cash_rows if t.source_type == "kassa_repay"),
        "top_suppliers": top_suppliers,
        "busiest_day": busiest_day,
        "daily_series": daily_series,
    }


# ---------------------------------------------------------------------------
# AI Usage Tracking
# ---------------------------------------------------------------------------


async def record_ai_usage(
    db: AsyncSession,
    kind: str,
    model_name: str = "",
    prompt_tokens: int = 0,
    output_tokens: int = 0,
    total_tokens: int = 0,
    usage_date: Optional[str] = None,
) -> None:
    """Persist one Gemini call or cache hit for daily/monthly cost monitoring."""
    db.add(
        AIUsageLog(
            usage_date=usage_date or today_iso(),
            kind=kind,
            model_name=model_name[:64],
            prompt_tokens=int(prompt_tokens),
            output_tokens=int(output_tokens),
            total_tokens=int(total_tokens),
        )
    )
    await db.commit()


async def get_ai_usage_stats(db: AsyncSession, date_iso: Optional[str] = None) -> dict:
    """Return today's and current month's Gemini call counts and token usage."""
    target = date_iso or today_iso()
    month_prefix = target[:7]

    month_rows = list(
        (
            await db.scalars(
                select(AIUsageLog).where(AIUsageLog.usage_date.like(f"{month_prefix}-%"))
            )
        ).all()
    )
    day_rows = [r for r in month_rows if r.usage_date == target]

    return {
        "date": target,
        "calls": sum(1 for r in day_rows if r.kind in ("photo", "audio")),
        "photo_calls": sum(1 for r in day_rows if r.kind == "photo"),
        "audio_calls": sum(1 for r in day_rows if r.kind == "audio"),
        "cache_hits": sum(1 for r in day_rows if r.kind == "cache_hit"),
        "prompt_tokens": sum(r.prompt_tokens for r in day_rows),
        "output_tokens": sum(r.output_tokens for r in day_rows),
        "total_tokens": sum(r.total_tokens for r in day_rows),
        "month_calls": sum(1 for r in month_rows if r.kind in ("photo", "audio")),
        "month_cache_hits": sum(1 for r in month_rows if r.kind == "cache_hit"),
        "month_tokens": sum(r.total_tokens for r in month_rows),
    }


# ---------------------------------------------------------------------------
# User Roles (RBAC)
# ---------------------------------------------------------------------------


async def list_user_roles(db: AsyncSession) -> List[UserRole]:
    """List dynamically configured user roles."""
    return list((await db.scalars(select(UserRole).order_by(UserRole.created_at))).all())


async def set_user_role(
    db: AsyncSession, user_id: int, role: str, label: str = ""
) -> UserRole:
    """Create or update a Telegram user's role."""
    obj = await db.get(UserRole, int(user_id))
    if obj is None:
        obj = UserRole(user_id=int(user_id), role=role, label=label.strip()[:128])
        db.add(obj)
    else:
        obj.role = role
        if label.strip():
            obj.label = label.strip()[:128]
    await db.commit()
    await db.refresh(obj)
    return obj


async def delete_user_role(db: AsyncSession, user_id: int) -> bool:
    """Remove a dynamically assigned user role."""
    obj = await db.get(UserRole, int(user_id))
    if obj is None:
        return False
    await db.delete(obj)
    await db.commit()
    return True


# ---------------------------------------------------------------------------
# Supplier Debts (Nasiya)
# ---------------------------------------------------------------------------


async def add_supplier_debt(
    db: AsyncSession,
    supplier_name: str,
    entry_type: str,
    amount: float,
    note: str = "",
    user_id: Optional[int] = None,
) -> SupplierDebt:
    """Record goods taken on credit ('debt') or debt repayment ('payment')."""
    canon, _ = await resolve_supplier_name(db, supplier_name)
    entry = SupplierDebt(
        supplier_name=canon or supplier_name.strip(),
        entry_type=entry_type,
        amount=float(amount),
        note=note.strip()[:500],
        is_deleted=False,
    )
    db.add(entry)
    await db.commit()
    await db.refresh(entry)
    await log_action(
        db,
        entry_type,
        "nasiya",
        entry.id,
        f"{entry.supplier_name} / {entry.amount:.0f} ({entry.note})",
        user_id=user_id,
    )
    return entry


async def delete_supplier_debt(
    db: AsyncSession, entry_id: int, user_id: Optional[int] = None
) -> Optional[SupplierDebt]:
    """Soft-delete a supplier debt/payment entry."""
    entry = await db.get(SupplierDebt, entry_id)
    if entry is None or entry.is_deleted:
        return None
    entry.is_deleted = True
    await db.commit()
    await db.refresh(entry)
    await log_action(
        db,
        "delete",
        "nasiya",
        entry.id,
        f"{entry.supplier_name} / {entry.amount:.0f}",
        user_id=user_id,
    )
    return entry


async def get_supplier_debt_balances(db: AsyncSession) -> List[dict]:
    """Compute net nasiya balance (debt - payment) per supplier ordered by highest balance."""
    rows = (
        await db.scalars(
            select(SupplierDebt).where(SupplierDebt.is_deleted.is_(False)).order_by(SupplierDebt.id)
        )
    ).all()
    buckets: Dict[str, dict] = {}
    for row in rows:
        key = _norm_key(row.supplier_name)
        item = buckets.setdefault(
            key, {"supplier": row.supplier_name.strip(), "debt": 0.0, "paid": 0.0, "balance": 0.0}
        )
        if row.entry_type == "debt":
            item["debt"] += float(row.amount)
        else:
            item["paid"] += float(row.amount)
        item["balance"] = item["debt"] - item["paid"]
    return sorted(buckets.values(), key=lambda b: -b["balance"])


async def list_supplier_debt_entries(
    db: AsyncSession, supplier_name: Optional[str] = None, limit: int = 20
) -> List[SupplierDebt]:
    """List recent non-deleted supplier debt/payment entries."""
    stmt = (
        select(SupplierDebt)
        .where(SupplierDebt.is_deleted.is_(False))
        .order_by(desc(SupplierDebt.id))
        .limit(limit * 4 if supplier_name else limit)
    )
    rows = list((await db.scalars(stmt)).all())
    if not supplier_name:
        return rows[:limit]
    target = _norm_key(supplier_name)
    return [r for r in rows if _norm_key(r.supplier_name) == target][:limit]
