# sports_api

Provider-agnostic sports data API for SportsApp.

This service is the future ingestion and canonicalization layer between raw sports providers and Supabase. The initial scaffold is built around:

- `FastAPI` for HTTP endpoints
- `SQLAlchemy` for the canonical sports domain
- `Alembic` for schema migrations
- `PostgreSQL` as the source of truth

## Goals

- Pull raw payloads from external sports providers
- Normalize them into canonical entities
- Build knowledge-base relations between countries, competitions, seasons, teams, players, and matches
- Expose stable API endpoints so Supabase no longer talks to providers directly

## Current Scope

This scaffold includes:

- application bootstrap
- environment-based config
- async database session setup
- canonical sports domain models
- basic knowledge-base relation draft helpers
- health endpoint
- match listing endpoint
- internal sync trigger placeholder
- Alembic configuration

## Project Layout

```text
sports_api/
  app/
    api/
    core/
    db/
    knowledge_base/
    providers/
    schemas/
    services/
  alembic/
  tests/
```

## Quick Start

### Local Python

```bash
cd sports_api
python -m venv .venv
.venv\Scripts\activate
pip install -e .[dev]
alembic upgrade head
uvicorn app.main:app --reload
```

### Docker

```bash
cd sports_api
docker compose up --build
```

The app will be available at:

- `http://localhost:8000/ui`
- `http://localhost:8000/api/v1/health`

Use the stage buttons in the UI to load data into PostgreSQL:

- countries
- tournaments
- seasons for a specific tournament id

Full catalog bootstrap is intentionally disabled to protect request-based provider quotas.

## Environment

Copy `.env.example` to `.env` and update values.

## First Implementation Steps

1. Add the new provider client under `app/providers/`
2. Create the first Alembic migration from the canonical models
3. Implement provider -> canonical sync in `app/services/sync_service.py`
4. Point Supabase to this API instead of the external provider
