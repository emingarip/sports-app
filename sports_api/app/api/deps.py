import secrets
from collections.abc import AsyncIterator

from fastapi import Depends, Header, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.db.session import async_session_factory

_PROTECTED_ENVIRONMENTS = {"production", "prod", "staging"}


async def get_db_session() -> AsyncIterator[AsyncSession]:
    async with async_session_factory() as session:
        yield session


def get_app_settings() -> Settings:
    return get_settings()


async def verify_internal_token(
    x_internal_token: str | None = Header(default=None),
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_app_settings),
) -> None:
    """Guard for internal endpoints (sync triggers, prediction runs, /ui).

    Fails **closed** in production: an unset token used to mean "let everyone
    in", which left every POST sync endpoint open on api.boskale.com. Outside
    production an unset token still skips the check so local development does
    not need one.

    The token is accepted from ``X-Internal-Token`` or from an
    ``Authorization: Bearer`` header - the Supabase edge functions send the
    latter, and quietly disagreeing about the header name made the token
    decorative rather than protective.
    """
    if not settings.internal_api_token:
        if settings.environment.strip().lower() in _PROTECTED_ENVIRONMENTS:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=(
                    "SPORTS_API_INTERNAL_API_TOKEN is not configured; "
                    "internal endpoints are disabled."
                ),
            )
        return

    presented = x_internal_token
    if not presented and authorization:
        scheme, _, value = authorization.partition(" ")
        if scheme.strip().lower() == "bearer":
            presented = value.strip()

    if not presented or not secrets.compare_digest(
        presented, settings.internal_api_token
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid internal token.",
        )
