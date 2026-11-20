"""Add is_debt and paid_at columns to nakladnoy_payments.

Revision ID: 0002_nakladnoy_debt
Revises: 0001_schema_upgrade
Create Date: 2026-11-20 11:00:00
"""

from __future__ import annotations

from alembic import op

from database.session import upgrade_existing_schema

revision = "0002_nakladnoy_debt"
down_revision = "0001_schema_upgrade"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply idempotent schema upgrade adding is_debt & paid_at."""
    upgrade_existing_schema(op.get_bind())


def downgrade() -> None:
    """Drop debt tracking columns from nakladnoy_payments."""
    op.drop_index("ix_nakladnoy_payments_is_debt", table_name="nakladnoy_payments")
    op.drop_column("nakladnoy_payments", "paid_at")
    op.drop_column("nakladnoy_payments", "is_debt")
