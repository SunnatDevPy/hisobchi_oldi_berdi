"""Add payment_method column to nakladnoy_payments.

Revision ID: 0003_payment_method
Revises: 0002_nakladnoy_debt
Create Date: 2026-11-20 20:40:00
"""

from __future__ import annotations

from alembic import op

from database.session import upgrade_existing_schema

revision = "0003_payment_method"
down_revision = "0002_nakladnoy_debt"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply idempotent schema upgrade adding payment_method."""
    upgrade_existing_schema(op.get_bind())


def downgrade() -> None:
    """Drop payment_method column from nakladnoy_payments."""
    op.drop_index("ix_nakladnoy_payments_payment_method", table_name="nakladnoy_payments")
    op.drop_column("nakladnoy_payments", "payment_method")
