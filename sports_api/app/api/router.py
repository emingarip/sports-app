from fastapi import APIRouter

from app.api.routes import bulletin, catalog, health, matches, predictions, sync

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(catalog.router)
api_router.include_router(matches.router)
api_router.include_router(bulletin.router)
api_router.include_router(predictions.router)
api_router.include_router(sync.router)
