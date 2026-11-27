"""SQLAlchemy 2.0 ORM models for Hisobot Bot."""

from __future__ import annotations

from datetime import datetime
from typing import List, Optional

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    func,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


# Store UZS money accurately with Numeric(15, 2) while returning Python floats
# so existing arithmetic remains seamless without Decimal/float mismatches.
MONEY = Numeric(15, 2, asdecimal=False)


class Base(DeclarativeBase):
    """Base declarative class."""


class GroupConfig(Base):
    """Telegram group binding by role (nakladnoy, prixod, kassa)."""

    __tablename__ = "group_configs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    role: Mapped[str] = mapped_column(String(32), unique=True, nullable=False)
    chat_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    title: Mapped[str] = mapped_column(String(255), nullable=False, default="")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class SupplierConfig(Base):
    """Configured suppliers for Qarz / Karta / Nakladnoy mapping and aliases."""

    __tablename__ = "supplier_configs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    order_num: Mapped[int] = mapped_column(Integer, nullable=False, default=100)
    display_name: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    aliases: Mapped[str] = mapped_column(Text, nullable=False, default="")
    default_category: Mapped[str] = mapped_column(String(32), nullable=False, default="qarz")
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


class DailyCashSession(Base):
    """Daily cash wallet session tracking opening balance, expenses, and reconciliation."""

    __tablename__ = "daily_cash_sessions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    report_date: Mapped[str] = mapped_column(String(16), nullable=False, index=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="open", index=True)
    opening_balance: Mapped[float] = mapped_column(MONEY, nullable=False, default=0.0)
    actual_counted_cash: Mapped[Optional[float]] = mapped_column(MONEY, nullable=True)
    expected_cash: Mapped[float] = mapped_column(MONEY, nullable=False, default=0.0)
    difference: Mapped[Optional[float]] = mapped_column(MONEY, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    closed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    cash_transactions: Mapped[List["CashTransaction"]] = relationship(
        back_populates="session", cascade="all, delete-orphan"
    )
    nakladnoy_payments: Mapped[List["NakladnoyPayment"]] = relationship(
        back_populates="session", cascade="all, delete-orphan"
    )
    reconciliations: Mapped[List["CashReconciliation"]] = relationship(
        back_populates="session", cascade="all, delete-orphan"
    )


class CashReconciliation(Base):
    """Interim or end-of-day cash reconciliation snapshot without mutating cash balance."""

    __tablename__ = "cash_reconciliations"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    session_id: Mapped[int] = mapped_column(
        ForeignKey("daily_cash_sessions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    kind: Mapped[str] = mapped_column(String(16), nullable=False, default="interim", index=True)
    opening_balance: Mapped[float] = mapped_column(MONEY, nullable=False, default=0.0)
    cash_in_total: Mapped[float] = mapped_column(MONEY, nullable=False, default=0.0)
    cash_out_total: Mapped[float] = mapped_column(MONEY, nullable=False, default=0.0)
    expected_cash: Mapped[float] = mapped_column(MONEY, nullable=False)
    counted_cash: Mapped[float] = mapped_column(MONEY, nullable=False)
    difference: Mapped[float] = mapped_column(MONEY, nullable=False)
    note: Mapped[str] = mapped_column(String(500), nullable=False, default="")
    created_by: Mapped[Optional[int]] = mapped_column(BigInteger, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )

    session: Mapped["DailyCashSession"] = relationship(back_populates="reconciliations")


class CashTransaction(Base):
    """Cash-in and kassa debt/repayment movements within a daily session."""

    __tablename__ = "cash_transactions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    session_id: Mapped[int] = mapped_column(
        ForeignKey("daily_cash_sessions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    amount: Mapped[float] = mapped_column(MONEY, nullable=False)
    source_type: Mapped[str] = mapped_column(String(32), nullable=False, default="main")
    note: Mapped[str] = mapped_column(String(500), nullable=False, default="")
    is_deleted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    session: Mapped["DailyCashSession"] = relationship(back_populates="cash_transactions")


class NakladnoyPayment(Base):
    """Supplier invoice (nakladnoy) payments made during a daily session."""

    __tablename__ = "nakladnoy_payments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    session_id: Mapped[int] = mapped_column(
        ForeignKey("daily_cash_sessions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    supplier_name: Mapped[str] = mapped_column(String(255), nullable=False, default="")
    amount: Mapped[float] = mapped_column(MONEY, nullable=False, default=0.0)
    original_amount: Mapped[Optional[float]] = mapped_column(MONEY, nullable=True)
    photo_file_id: Mapped[Optional[str]] = mapped_column(String(512), nullable=True)
    photo_unique_id: Mapped[Optional[str]] = mapped_column(String(128), nullable=True, index=True)
    note: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending", index=True)
    is_debt: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, index=True)
    paid_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    payment_method: Mapped[str] = mapped_column(String(16), nullable=False, default="cash", index=True)
    group_chat_id: Mapped[Optional[int]] = mapped_column(BigInteger, nullable=True)
    group_message_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    session: Mapped["DailyCashSession"] = relationship(back_populates="nakladnoy_payments")


class PrixodReport(Base):
    """Daily ITOG prixod report parsed from YesPOS CSV/XLSX or manual text."""

    __tablename__ = "prixod_reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    report_date: Mapped[str] = mapped_column(String(16), nullable=False, index=True)
    total_cost: Mapped[float] = mapped_column(MONEY, nullable=False, default=0.0)
    total_price: Mapped[float] = mapped_column(MONEY, nullable=False, default=0.0)
    formatted_text: Mapped[str] = mapped_column(Text, nullable=False, default="")
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="draft")
    group_chat_id: Mapped[Optional[int]] = mapped_column(BigInteger, nullable=True)
    group_message_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    rows: Mapped[List["PrixodRow"]] = relationship(
        back_populates="report", cascade="all, delete-orphan", order_by="PrixodRow.row_num"
    )


class PrixodRow(Base):
    """Individual line item belonging to a PrixodReport."""

    __tablename__ = "prixod_rows"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    report_id: Mapped[int] = mapped_column(
        ForeignKey("prixod_reports.id", ondelete="CASCADE"), nullable=False, index=True
    )
    row_num: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    supplier_raw: Mapped[str] = mapped_column(String(255), nullable=False)
    supplier_display: Mapped[str] = mapped_column(String(255), nullable=False)
    note_raw: Mapped[str] = mapped_column(String(255), nullable=False, default="")
    cost: Mapped[float] = mapped_column(MONEY, nullable=False, default=0.0)
    price: Mapped[float] = mapped_column(MONEY, nullable=False, default=0.0)
    category: Mapped[str] = mapped_column(String(32), nullable=False, default="nakladnoy")
    old_date_label: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    created_at_str: Mapped[str] = mapped_column(String(64), nullable=False, default="")

    report: Mapped["PrixodReport"] = relationship(back_populates="rows")


class AppSetting(Base):
    """Key-value bot behavior settings (auto_confirm, round_mode, auto_report, etc.)."""

    __tablename__ = "app_settings"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[str] = mapped_column(String(255), nullable=False, default="")


class AuditLog(Base):
    """Immutable log of edits/deletes/confirmations for money-related records."""

    __tablename__ = "audit_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    action: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    entity: Mapped[str] = mapped_column(String(32), nullable=False)
    entity_id: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    user_id: Mapped[Optional[int]] = mapped_column(BigInteger, nullable=True)
    details: Mapped[str] = mapped_column(Text, nullable=False, default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class FSMState(Base):
    """Persistent Aiogram FSM state and context data surviving bot restarts."""

    __tablename__ = "fsm_states"

    storage_key: Mapped[str] = mapped_column(String(255), primary_key=True)
    state: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    data_json: Mapped[str] = mapped_column(Text, nullable=False, default="{}")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class AIUsageLog(Base):
    """Daily tracking of Gemini AI calls, cache hits, and token consumption."""

    __tablename__ = "ai_usage_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    usage_date: Mapped[str] = mapped_column(String(16), nullable=False, index=True)
    kind: Mapped[str] = mapped_column(String(16), nullable=False)  # photo | audio | cache_hit
    model_name: Mapped[str] = mapped_column(String(64), nullable=False, default="")
    prompt_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    output_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    total_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class UserRole(Base):
    """Telegram user access roles (admin, kassir, viewer)."""

    __tablename__ = "user_roles"

    user_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    role: Mapped[str] = mapped_column(String(16), nullable=False, default="viewer")
    label: Mapped[str] = mapped_column(String(128), nullable=False, default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class SupplierDebt(Base):
    """Supplier credit/nasiya ledger tracking goods taken on credit and repayments."""

    __tablename__ = "supplier_debts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    supplier_name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    entry_type: Mapped[str] = mapped_column(String(16), nullable=False)  # debt | payment
    amount: Mapped[float] = mapped_column(MONEY, nullable=False)
    note: Mapped[str] = mapped_column(String(500), nullable=False, default="")
    is_deleted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class ApiToken(Base):
    """Mobile APK bearer tokens hashed with SHA-256."""

    __tablename__ = "api_tokens"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    token_hash: Mapped[str] = mapped_column(
        String(128), unique=True, nullable=False, index=True
    )
    user_id: Mapped[int] = mapped_column(BigInteger, nullable=False, index=True)
    device_name: Mapped[str] = mapped_column(String(128), nullable=False, default="Android")
    revoked: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    last_used_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class ApiIdempotencyRecord(Base):
    """Cached responses for idempotent mutating REST calls (prevents duplicate sends on retries)."""

    __tablename__ = "api_idempotency_records"

    key: Mapped[str] = mapped_column(String(160), primary_key=True)
    endpoint: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    user_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    response_json: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )

