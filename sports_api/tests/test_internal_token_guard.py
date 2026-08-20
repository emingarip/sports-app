"""Guard tests for the internal-endpoint token.

The guard used to fail *open*: an unset token meant "let everyone in", which
left every POST sync endpoint and the whole /ui router reachable from the
internet. These tests pin the three behaviours that matter.
"""

from __future__ import annotations

import pytest
from fastapi import HTTPException

from app.api.deps import verify_internal_token
from app.core.config import Settings


def _settings(**overrides) -> Settings:
    base = {
        "environment": "development",
        "internal_api_token": None,
        "_env_file": None,
    }
    base.update(overrides)
    env_file = base.pop("_env_file")
    return Settings(_env_file=env_file, **base)


async def test_missing_token_in_production_fails_closed() -> None:
    with pytest.raises(HTTPException) as excinfo:
        await verify_internal_token(
            x_internal_token=None,
            authorization=None,
            settings=_settings(environment="production"),
        )
    assert excinfo.value.status_code == 500


async def test_missing_token_in_development_stays_open() -> None:
    # Local development should not need a token to hit /ui.
    await verify_internal_token(
        x_internal_token=None,
        authorization=None,
        settings=_settings(environment="development"),
    )


async def test_correct_token_accepted_from_either_header() -> None:
    settings = _settings(environment="production", internal_api_token="s3cret")
    await verify_internal_token(
        x_internal_token="s3cret", authorization=None, settings=settings
    )
    # The Supabase edge functions send Authorization: Bearer, not
    # X-Internal-Token; both must be accepted or the token is decorative.
    await verify_internal_token(
        x_internal_token=None, authorization="Bearer s3cret", settings=settings
    )


@pytest.mark.parametrize(
    ("header", "authorization"),
    [
        (None, None),
        ("wrong", None),
        (None, "Bearer wrong"),
        (None, "Basic s3cret"),
        (None, "s3cret"),
    ],
)
async def test_wrong_or_missing_token_rejected(header, authorization) -> None:
    with pytest.raises(HTTPException) as excinfo:
        await verify_internal_token(
            x_internal_token=header,
            authorization=authorization,
            settings=_settings(
                environment="production", internal_api_token="s3cret"
            ),
        )
    assert excinfo.value.status_code == 401
