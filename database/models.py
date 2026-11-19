"""SQLAlchemy 2.0 ORM models for Hisobot Bot."""

from __future__ import annotations

from datetime import datetime
from typing import List, Optional

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    func,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


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
    opening_balance: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    actual_counted_cash: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    expected_cash: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    difference: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
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


class CashTransaction(Base):
    """Cash-in and kassa debt/repayment movements within a daily session."""

    __tablename__ = "cash_transactions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    session_id: Mapped[int] = mapped_column(
        ForeignKey("daily_cash_sessions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    amount: Mapped[float] = mapped_column(Float, nullable=False)
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
    amount: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    photo_file_id: Mapped[Optional[str]] = mapped_column(String(512), nullable=True)
    note: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending", index=True)
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
    total_cost: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    total_price: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
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
    cost: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    price: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    category: Mapped[str] = mapped_column(String(32), nullable=False, default="nakladnoy")
    old_date_label: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    created_at_str: Mapped[str] = mapped_column(String(64), nullable=False, default="")

    report: Mapped["PrixodReport"] = relationship(back_populates="rows")


class AppSetting(Base):
    """Key-value bot behavior settings (auto_confirm, round_mode, etc.)."""

    __tablename__ = "app_settings"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[str] = mapped_column(String(255), nullable=False, default="")
