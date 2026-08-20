"""add unresolved live matches negative cache

Revision ID: 20260406_000003
Revises: 20260406_000002
Create Date: 2026-04-06 15:40:00
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

# revision identifiers, used by Alembic.
revision = "20260406_000003"
down_revision = "20260406_000002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "unresolved_live_matches",
        sa.Column("provider_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("provider_match_id", sa.String(length=180), nullable=False),
        sa.Column("first_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_attempt_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("next_retry_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("attempt_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("last_error_status", sa.Integer(), nullable=True),
        sa.Column("last_error_message", sa.Text(), nullable=True),
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column(
            "metadata",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'{}'::jsonb"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["provider_id"],
            ["providers.id"],
            name=op.f("fk_unresolved_live_matches_provider_id_providers"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_unresolved_live_matches")),
        sa.UniqueConstraint(
            "provider_id",
            "provider_match_id",
            name=op.f("uq_unresolved_live_matches_provider_id"),
        ),
    )
    op.create_index(
        "ix_unresolved_live_matches_next_retry_at",
        "unresolved_live_matches",
        ["next_retry_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_unresolved_live_matches_next_retry_at", table_name="unresolved_live_matches")
    op.drop_table("unresolved_live_matches")
