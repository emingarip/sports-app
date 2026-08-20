"""add match player appearances

Revision ID: 20260407_000005
Revises: 20260406_000004
Create Date: 2026-04-07 14:10:00
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

# revision identifiers, used by Alembic.
revision = "20260407_000005"
down_revision = "20260406_000004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "match_player_appearances",
        sa.Column("provider_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("match_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("player_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("team_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("side", sa.String(length=8), nullable=False),
        sa.Column("is_starter", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("is_substitute", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("played", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("minutes_played", sa.Integer(), nullable=True),
        sa.Column("position", sa.String(length=32), nullable=True),
        sa.Column("squad_number", sa.Integer(), nullable=True),
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
            ["match_id"],
            ["matches.id"],
            name=op.f("fk_match_player_appearances_match_id_matches"),
        ),
        sa.ForeignKeyConstraint(
            ["player_id"],
            ["players.id"],
            name=op.f("fk_match_player_appearances_player_id_players"),
        ),
        sa.ForeignKeyConstraint(
            ["provider_id"],
            ["providers.id"],
            name=op.f("fk_match_player_appearances_provider_id_providers"),
        ),
        sa.ForeignKeyConstraint(
            ["team_id"],
            ["teams.id"],
            name=op.f("fk_match_player_appearances_team_id_teams"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_match_player_appearances")),
        sa.UniqueConstraint(
            "provider_id",
            "match_id",
            "player_id",
            name=op.f("uq_match_player_appearances_provider_id"),
        ),
    )
    op.create_index(
        "ix_match_player_appearances_provider_match_side",
        "match_player_appearances",
        ["provider_id", "match_id", "side"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_match_player_appearances_provider_match_side",
        table_name="match_player_appearances",
    )
    op.drop_table("match_player_appearances")
