"""add half-time score to matches

Without these columns every half-time market (IY, IY_AU_0_5, IY_AU_1_5,
IY_MS) is voided on settlement - resolve-coupons says so in its own comment -
so those markets never accumulate a track record and never appear in the
calibration or backtest reports.

Revision ID: 20260820_000008
Revises: 20260711_000007
Create Date: 2026-08-20 06:00:00
"""

import sqlalchemy as sa

from alembic import op

revision = "20260820_000008"
down_revision = "20260711_000007"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("matches", sa.Column("score_home_ht", sa.Integer(), nullable=True))
    op.add_column("matches", sa.Column("score_away_ht", sa.Integer(), nullable=True))


def downgrade() -> None:
    op.drop_column("matches", "score_away_ht")
    op.drop_column("matches", "score_home_ht")
