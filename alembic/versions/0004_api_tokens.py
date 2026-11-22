"""Create api_tokens table for Mobile APK authentication.

Revision ID: 0004_api_tokens
Revises: 0003_payment_method
Create Date: 2026-11-22 13:00:00
"""

from __future__ import annotations

from alembic import op

from database.session import upgrade_existing_schema

revision = "0004_api_tokens"
down_revision = "0003_payment_method"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply idempotent schema upgrade creating api_tokens."""
    upgrade_existing_schema(op.get_bind())


def downgrade() -> None:
    """Drop api_tokens table."""
    op.drop_table("api_tokens")
