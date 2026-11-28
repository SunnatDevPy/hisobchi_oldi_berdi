"""Add cash_reconciliations snapshot columns and supplier_merge_logs table.

Revision ID: 0005_reconciliation_and_merge_logs
Revises: 0004_api_tokens
Create Date: 2026-11-28 12:45:00
"""

from __future__ import annotations

from alembic import op

from database.models import Base
from database.session import upgrade_existing_schema

revision = "0005_reconciliation_and_merge_logs"
down_revision = "0004_api_tokens"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Create missing tables (supplier_merge_logs) and reconciliation cashflow snapshot columns."""
    bind = op.get_bind()
    Base.metadata.create_all(bind=bind)
    upgrade_existing_schema(bind)


def downgrade() -> None:
    """Drop supplier_merge_logs table."""
    op.drop_table("supplier_merge_logs")
