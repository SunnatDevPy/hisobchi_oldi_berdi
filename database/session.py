"""Async SQLAlchemy engine, sessionmaker, idempotent schema upgrade, and initialization."""

from __future__ import annotations

from typing import Tuple

from sqlalchemy import Numeric, inspect, select, text
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from config import get_settings
from database.models import Base, SupplierConfig
from database.sync_state import attach_sync_listeners

attach_sync_listeners()


DEFAULT_SUPPLIERS = [
    {
        "order_num": 1,
        "display_name": "OMBOR",
        "aliases": "OMBOR",
        "default_category": "qarz",
    },
    {
        "order_num": 2,
        "display_name": "QASSOB",
        "aliases": "QASSOB",
        "default_category": "qarz",
    },
    {
        "order_num": 3,
        "display_name": "FOZIL MARINAD (шашлик)",
        "aliases": "FOZIL MARINAD,FOZIL MARINAD (ШАШЛИК),FOZIL",
        "default_category": "qarz",
    },
    {
        "order_num": 4,
        "display_name": "ASADBEK (норин)",
        "aliases": "ASADBEK (НОРИН),ASADBEK",
        "default_category": "qarz",
    },
    {
        "order_num": 5,
        "display_name": "Alisa Pereches",
        "aliases": "SAID AND PARTNERS GRUP ( МАСЛО),SAID AND PARTNERS GRUP,SAID AND PARTNERS,ALISA PERECHES",
        "default_category": "qarz",
    },
    {
        "order_num": 6,
        "display_name": "By Malika",
        "aliases": "BY MALIKA",
        "default_category": "karta",
    },
]

_PG_MONEY_COLUMNS = (
    ("daily_cash_sessions", ("opening_balance", "actual_counted_cash", "expected_cash", "difference")),
    ("cash_transactions", ("amount",)),
    ("nakladnoy_payments", ("amount", "original_amount")),
    ("prixod_reports", ("total_cost", "total_price")),
    ("prixod_rows", ("cost", "price")),
    ("supplier_debts", ("amount",)),
)


def upgrade_existing_schema(sync_conn: Connection) -> None:
    """Safely upgrade existing SQLite/PostgreSQL tables without dropping data."""
    inspector = inspect(sync_conn)
    tables = set(inspector.get_table_names())

    if "nakladnoy_payments" in tables:
        cols = {c["name"] for c in inspector.get_columns("nakladnoy_payments")}
        if "original_amount" not in cols:
            sync_conn.execute(
                text("ALTER TABLE nakladnoy_payments ADD COLUMN original_amount NUMERIC(15, 2)")
            )
        if "photo_unique_id" not in cols:
            sync_conn.execute(
                text("ALTER TABLE nakladnoy_payments ADD COLUMN photo_unique_id VARCHAR(128)")
            )
        if "is_debt" not in cols:
            sync_conn.execute(
                text("ALTER TABLE nakladnoy_payments ADD COLUMN is_debt BOOLEAN NOT NULL DEFAULT FALSE")
            )
        if "paid_at" not in cols:
            col_type = "TIMESTAMPTZ" if sync_conn.dialect.name == "postgresql" else "DATETIME"
            sync_conn.execute(
                text(f"ALTER TABLE nakladnoy_payments ADD COLUMN paid_at {col_type}")
            )
        if "payment_method" not in cols:
            sync_conn.execute(
                text("ALTER TABLE nakladnoy_payments ADD COLUMN payment_method VARCHAR(16) NOT NULL DEFAULT 'cash'")
            )
        indexes = {ix["name"] for ix in inspector.get_indexes("nakladnoy_payments")}
        if "ix_nakladnoy_payments_photo_unique_id" not in indexes:
            sync_conn.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_nakladnoy_payments_photo_unique_id "
                    "ON nakladnoy_payments (photo_unique_id)"
                )
            )
        if "ix_nakladnoy_payments_is_debt" not in indexes:
            sync_conn.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_nakladnoy_payments_is_debt "
                    "ON nakladnoy_payments (is_debt)"
                )
            )
        if "ix_nakladnoy_payments_payment_method" not in indexes:
            sync_conn.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_nakladnoy_payments_payment_method "
                    "ON nakladnoy_payments (payment_method)"
                )
            )

    if "audit_logs" in tables:
        cols = {c["name"] for c in inspector.get_columns("audit_logs")}
        if "user_id" not in cols:
            sync_conn.execute(text("ALTER TABLE audit_logs ADD COLUMN user_id BIGINT"))

    if sync_conn.dialect.name == "postgresql":
        for tbl, money_cols in _PG_MONEY_COLUMNS:
            if tbl not in tables:
                continue
            col_map = {c["name"]: c for c in inspector.get_columns(tbl)}
            for col_name in money_cols:
                col_info = col_map.get(col_name)
                if col_info is None:
                    continue
                if not isinstance(col_info["type"], Numeric):
                    sync_conn.execute(
                        text(
                            f"ALTER TABLE {tbl} ALTER COLUMN {col_name} "
                            f"TYPE NUMERIC(15, 2) USING ROUND({col_name}::numeric, 2)"
                        )
                    )


def create_engine_and_session(
    database_url: str | None = None,
) -> Tuple[AsyncEngine, async_sessionmaker[AsyncSession]]:
    """Create an AsyncEngine and async_sessionmaker for the given URL."""
    url = database_url or get_settings().DATABASE_URL
    kwargs: dict = {"echo": False, "future": True, "pool_pre_ping": True}
    if not url.startswith("sqlite"):
        kwargs.update({"pool_size": 10, "max_overflow": 10, "pool_recycle": 1800})
    eng = create_async_engine(url, **kwargs)
    maker = async_sessionmaker(eng, expire_on_commit=False, class_=AsyncSession)
    return eng, maker


engine, async_session_maker = create_engine_and_session()


async def seed_default_suppliers(session: AsyncSession) -> None:
    """Populate initial supplier configs if table is empty."""
    existing = await session.scalar(select(SupplierConfig.id).limit(1))
    if existing is not None:
        return
    for item in DEFAULT_SUPPLIERS:
        session.add(SupplierConfig(**item, is_active=True))
    await session.commit()


async def init_db(
    engine_override: AsyncEngine | None = None,
    session_maker_override: async_sessionmaker[AsyncSession] | None = None,
) -> None:
    """Create all tables, apply idempotent column upgrades, and seed defaults."""
    target_engine = engine_override or engine
    target_maker = session_maker_override or async_session_maker
    async with target_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await conn.run_sync(upgrade_existing_schema)
    async with target_maker() as session:
        await seed_default_suppliers(session)
