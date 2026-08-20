"""add match predictions table

Revision ID: 20260711_000007
Revises: 20260407_000006
Create Date: 2026-07-11 10:00:00
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "20260711_000007"
down_revision = "20260407_000006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    snapshot_phase_enum = postgresql.ENUM(
        "pre", "live", "finalized", name="snapshot_phase", create_type=False
    )

    op.create_table(
        "match_predictions",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("match_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("model_version", sa.String(length=64), nullable=False),
        sa.Column("phase", snapshot_phase_enum, nullable=False),
        sa.Column("generated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("lambda_home", sa.Float(), nullable=True),
        sa.Column("lambda_away", sa.Float(), nullable=True),
        sa.Column("rho", sa.Float(), nullable=True),
        sa.Column(
            "market_probs",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "value_picks",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "metadata",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(
            ["match_id"], ["matches.id"], name="fk_match_predictions_match_id_matches"
        ),
        sa.PrimaryKeyConstraint("id", name="pk_match_predictions"),
        sa.UniqueConstraint(
            "match_id", "model_version", "phase", name="uq_match_predictions_match_id"
        ),
    )
    op.create_index(
        "ix_match_predictions_generated_at",
        "match_predictions",
        ["generated_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_match_predictions_generated_at", table_name="match_predictions")
    op.drop_table("match_predictions")
