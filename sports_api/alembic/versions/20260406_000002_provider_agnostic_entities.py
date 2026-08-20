"""add provider agnostic sport and category entities

Revision ID: 20260406_000002
Revises: 20260405_000001
Create Date: 2026-04-06 09:45:00
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

# revision identifiers, used by Alembic.
revision = "20260406_000002"
down_revision = "20260405_000001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TYPE entity_type ADD VALUE IF NOT EXISTS 'sport'")
    op.execute("ALTER TYPE entity_type ADD VALUE IF NOT EXISTS 'category'")
    op.execute("ALTER TYPE raw_payload_entity_type ADD VALUE IF NOT EXISTS 'sport'")
    op.execute("ALTER TYPE raw_payload_entity_type ADD VALUE IF NOT EXISTS 'category'")

    op.create_table(
        "sports",
        sa.Column("entity_uid", sa.String(length=150), nullable=False),
        sa.Column("name", sa.String(length=80), nullable=False),
        sa.Column("slug", sa.String(length=80), nullable=False),
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column("metadata", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_sports")),
        sa.UniqueConstraint("entity_uid", name=op.f("uq_sports_entity_uid")),
        sa.UniqueConstraint("slug", name=op.f("uq_sports_slug")),
    )

    op.create_table(
        "categories",
        sa.Column("entity_uid", sa.String(length=255), nullable=False),
        sa.Column("name", sa.String(length=150), nullable=False),
        sa.Column("slug", sa.String(length=255), nullable=False),
        sa.Column("sport_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("country_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("priority", sa.Integer(), nullable=True),
        sa.Column("flag", sa.String(length=80), nullable=True),
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.text("now()"), nullable=False),
        sa.Column("metadata", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.ForeignKeyConstraint(["country_id"], ["countries.id"], name=op.f("fk_categories_country_id_countries")),
        sa.ForeignKeyConstraint(["sport_id"], ["sports.id"], name=op.f("fk_categories_sport_id_sports")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_categories")),
        sa.UniqueConstraint("entity_uid", name=op.f("uq_categories_entity_uid")),
        sa.UniqueConstraint("slug", name=op.f("uq_categories_slug")),
    )

    op.add_column("competitions", sa.Column("category_id", postgresql.UUID(as_uuid=True), nullable=True))
    op.create_foreign_key(
        op.f("fk_competitions_category_id_categories"),
        "competitions",
        "categories",
        ["category_id"],
        ["id"],
    )

    op.add_column("teams", sa.Column("sport_id", postgresql.UUID(as_uuid=True), nullable=True))
    op.add_column("teams", sa.Column("gender", sa.String(length=24), nullable=True))
    op.add_column("teams", sa.Column("is_national", sa.Boolean(), nullable=True))
    op.add_column("teams", sa.Column("team_type", sa.Integer(), nullable=True))
    op.create_foreign_key(
        op.f("fk_teams_sport_id_sports"),
        "teams",
        "sports",
        ["sport_id"],
        ["id"],
    )

    op.alter_column("categories", "entity_uid", type_=sa.String(length=255), existing_nullable=False)
    op.alter_column("categories", "slug", type_=sa.String(length=255), existing_nullable=False)
    op.alter_column("competitions", "entity_uid", type_=sa.String(length=255), existing_nullable=False)
    op.alter_column("competitions", "slug", type_=sa.String(length=255), existing_nullable=False)
    op.alter_column("competition_seasons", "entity_uid", type_=sa.String(length=255), existing_nullable=False)
    op.alter_column("teams", "entity_uid", type_=sa.String(length=255), existing_nullable=False)
    op.alter_column("teams", "slug", type_=sa.String(length=255), existing_nullable=False)
    op.alter_column("matches", "entity_uid", type_=sa.String(length=255), existing_nullable=False)
    op.alter_column(
        "provider_entity_mappings",
        "canonical_entity_uid",
        type_=sa.String(length=255),
        existing_nullable=False,
    )
    op.alter_column(
        "entity_relations",
        "source_entity_uid",
        type_=sa.String(length=255),
        existing_nullable=False,
    )
    op.alter_column(
        "entity_relations",
        "target_entity_uid",
        type_=sa.String(length=255),
        existing_nullable=False,
    )


def downgrade() -> None:
    op.alter_column(
        "entity_relations",
        "target_entity_uid",
        type_=sa.String(length=180),
        existing_nullable=False,
    )
    op.alter_column(
        "entity_relations",
        "source_entity_uid",
        type_=sa.String(length=180),
        existing_nullable=False,
    )
    op.alter_column(
        "provider_entity_mappings",
        "canonical_entity_uid",
        type_=sa.String(length=180),
        existing_nullable=False,
    )
    op.alter_column("matches", "entity_uid", type_=sa.String(length=180), existing_nullable=False)
    op.alter_column("teams", "slug", type_=sa.String(length=180), existing_nullable=False)
    op.alter_column("teams", "entity_uid", type_=sa.String(length=150), existing_nullable=False)
    op.alter_column("competition_seasons", "entity_uid", type_=sa.String(length=180), existing_nullable=False)
    op.alter_column("competitions", "slug", type_=sa.String(length=180), existing_nullable=False)
    op.alter_column("competitions", "entity_uid", type_=sa.String(length=150), existing_nullable=False)

    op.drop_constraint(op.f("fk_teams_sport_id_sports"), "teams", type_="foreignkey")
    op.drop_column("teams", "team_type")
    op.drop_column("teams", "is_national")
    op.drop_column("teams", "gender")
    op.drop_column("teams", "sport_id")

    op.drop_constraint(op.f("fk_competitions_category_id_categories"), "competitions", type_="foreignkey")
    op.drop_column("competitions", "category_id")

    op.drop_table("categories")
    op.drop_table("sports")
