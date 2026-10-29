"""Credentials, rotating refresh tokens and versioned cooking sessions."""
from alembic import op
from service.database import Credential, RefreshToken, SessionRow
revision = '0002_auth_sessions'
down_revision = '0001'
branch_labels = None
depends_on = None


def upgrade():
    for model in (Credential, RefreshToken, SessionRow):
        model.__table__.create(op.get_bind(), checkfirst=True)


def downgrade():
    for model in (SessionRow, RefreshToken, Credential):
        model.__table__.drop(op.get_bind(), checkfirst=True)
