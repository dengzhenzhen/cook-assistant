"""Server-only configuration. Secrets never appear in API response models."""
from pathlib import Path
from functools import lru_cache
from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

ROOT = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=ROOT / '.env', extra='ignore', env_prefix='COOK_')
    database_url: str = f'sqlite+aiosqlite:///{ROOT / ".data" / "cook.db"}'
    development_mode: bool = True
    allow_development_login: bool = False
    jwt_secret: SecretStr = SecretStr('')
    deepseek_api_key: SecretStr = SecretStr('')
    deepseek_base_url: str = 'https://api.deepseek.com'
    deepseek_model: str = 'deepseek-flash'
    ai_daily_limit: int = 10
    ai_minute_limit: int = 2
    ai_global_daily_limit: int = 100
    cors_origins: list[str] = ['http://localhost:8080', 'http://127.0.0.1:8080']


@lru_cache
def get_settings():
    return Settings()
