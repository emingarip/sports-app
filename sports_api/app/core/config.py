from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        env_prefix="SPORTS_API_",
    )

    app_name: str = Field(default="Sports API")
    environment: str = Field(default="development")
    # Debug varsayilani False: True kaldigi surece /docs ve /redoc
    # api.boskale.com uzerinden internete aciktir. Gelistirmede
    # SPORTS_API_DEBUG=true ile acilir.
    debug: bool = Field(default=False)
    api_v1_prefix: str = "/api/v1"
    database_url: str = Field(default="postgresql+asyncpg://postgres:postgres@localhost:5432/sports_api")
    internal_api_token: str | None = Field(default=None)
    # Tarayicidan cagiran kaynaklar (Flutter web boskale.com -> sports-agent.boskale.com).
    # .env'de virgulle ayrilmis liste olarak override edilebilir:
    #   SPORTS_API_CORS_ORIGINS=https://boskale.com,https://www.boskale.com
    cors_origins: str = Field(
        default="https://boskale.com,https://www.boskale.com,https://games.boskale.com"
    )
    sportsapipro_v1_base_url: str = Field(default="https://v1.football.sportsapipro.com")
    sportsapipro_base_url: str = Field(default="https://v2.football.sportsapipro.com")
    sportsapipro_api_key: str | None = Field(default=None)
    sportsapipro_timeout_seconds: float = Field(default=30.0)
    sportsapipro_request_delay_seconds: float = Field(default=1.0)
    sportsapipro_max_retries: int = Field(default=10)
    sportsapipro_retry_backoff_seconds: float = Field(default=5.0)
    feature_snapshot_version: str = Field(default="v1")
    iddaa_bulletin_base_url: str = Field(default="https://cdnbulten.nesine.com")
    iddaa_bulletin_program_path: str = Field(default="/api/bulten/getprebultenfull")
    iddaa_bulletin_api_key: str | None = Field(default=None)
    iddaa_bulletin_timeout_seconds: float = Field(default=30.0)
    iddaa_bulletin_max_retries: int = Field(default=3)
    iddaa_bulletin_retry_backoff_seconds: float = Field(default=5.0)
    sofascore_base_url: str = Field(default="https://www.sofascore.com")
    sofascore_browser_headless: bool = Field(default=True)
    sofascore_browser_wait_seconds: float = Field(default=3.0)
    sofascore_request_delay_seconds: float = Field(default=2.0)
    sofascore_request_jitter_seconds: float = Field(default=1.0)
    sofascore_max_retries: int = Field(default=4)
    sofascore_retry_backoff_seconds: float = Field(default=15.0)
    sofascore_forbidden_backoff_seconds: float = Field(default=60.0)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
