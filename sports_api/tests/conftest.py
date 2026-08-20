"""Test-wide settings isolation.

``Settings`` reads ``sports_api/.env``, which now carries production values
(``SPORTS_API_ENVIRONMENT=production`` and a real internal token). Without this
module the whole suite would exercise the production configuration: ``/ui`` and
every internal endpoint would demand a token that the tests do not send, and
``/docs`` assertions would flip. Environment variables take precedence over the
``.env`` file in pydantic-settings, so setting them here - before any test
module imports ``app.main`` - pins the suite to a known configuration.
"""

from __future__ import annotations

import os

os.environ["SPORTS_API_ENVIRONMENT"] = "test"
os.environ["SPORTS_API_DEBUG"] = "true"
# Empty means "guard disabled"; the fail-closed branch only trips for the
# environments listed in app.api.deps._PROTECTED_ENVIRONMENTS.
os.environ["SPORTS_API_INTERNAL_API_TOKEN"] = ""

from app.core.config import get_settings  # noqa: E402

get_settings.cache_clear()
