"""Idempotent initial + v2 schema upgrade.

Revision ID: 0001_schema_upgrade
Revises:
Create Date: 2026-11-20 10:15:00
"""

from __future__ import annotations

from alembic import op

from database.models import Base
from database.session import upgrade_existing_schema

revision = "0001_schema_upgrade"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Create missing tables and upgrade existing columns idempotently."""
    conn = op.get_bind()
    Base.metadata.create_all(conn)
    upgrade_existing_schema(conn)


def downgrade() -> None:
    """Drop newly introduced v2 tables (preserving core financial data)."""
    for tbl in ("supplier_debts", "user_roles", "ai_usage_logs", "fsm_states"):
        op.drop_table(tbl)
