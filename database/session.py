"""Async SQLAlchemy engine, sessionmaker, and database initialization."""

from __future__ import annotations

from typing import Tuple

from sqlalchemy import select
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from config import get_settings
from database.models import Base, SupplierConfig


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


def create_engine_and_session(
    database_url: str | None = None,
) -> Tuple[AsyncEngine, async_sessionmaker[AsyncSession]]:
    """Create an AsyncEngine and async_sessionmaker for the given URL."""
    url = database_url or get_settings().DATABASE_URL
    eng = create_async_engine(url, echo=False, future=True)
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
    """Create all tables and seed initial configuration data."""
    target_engine = engine_override or engine
    target_maker = session_maker_override or async_session_maker
    async with target_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    async with target_maker() as session:
        await seed_default_suppliers(session)
