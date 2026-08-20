"""initial schema

Revision ID: 20260405_000001
Revises:
Create Date: 2026-04-05 17:15:00
"""

from alembic import op
from app.db.base import Base

# revision identifiers, used by Alembic.
revision = "20260405_000001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    Base.metadata.create_all(bind)


def downgrade() -> None:
    bind = op.get_bind()
    Base.metadata.drop_all(bind)
