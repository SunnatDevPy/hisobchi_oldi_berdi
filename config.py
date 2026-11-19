"""Application configuration loaded from .env file."""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import List

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


BASE_DIR = Path(__file__).resolve().parent


class Settings(BaseSettings):
    """Typed environment settings for Hisobot Bot."""

    model_config = SettingsConfigDict(
        env_file=BASE_DIR / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    BOT_TOKEN: str = "YOUR_TELEGRAM_BOT_TOKEN_HERE"
    ADMIN_IDS: str = ""

    DATABASE_URL: str = f"sqlite+aiosqlite:///{(BASE_DIR / 'data' / 'hisobot_bot.db').as_posix()}"

    GEMINI_API_KEY: str = ""
    GEMINI_MODEL: str = "gemini-flash-latest"

    YESPOS_BASE_URL: str = "https://marketplace.yestask.uz"
    YESPOS_API_KEY: str = ""
    YESPOS_BRANCH_ID: str = "1"
    YESPOS_1C_BASE_URL: str = ""
    YESPOS_1C_API_KEY: str = ""

    TIMEZONE: str = "Asia/Tashkent"

    @field_validator("DATABASE_URL")
    @classmethod
    def ensure_sqlite_dir(cls, value: str) -> str:
        """Ensure parent directory exists when using a local SQLite database file."""
        if value.startswith("sqlite"):
            db_part = value.split("///", maxsplit=1)[-1]
            if db_part and db_part != ":memory:":
                db_path = Path(db_part)
                if not db_path.is_absolute():
                    db_path = BASE_DIR / db_path
                db_path.parent.mkdir(parents=True, exist_ok=True)
        return value

    @property
    def admin_id_list(self) -> List[int]:
        """Parse comma-separated Telegram admin user IDs."""
        if not self.ADMIN_IDS.strip():
            return []
        result: List[int] = []
        for item in self.ADMIN_IDS.split(","):
            item = item.strip()
            if item.isdigit():
                result.append(int(item))
        return result


@lru_cache
def get_settings() -> Settings:
    """Return cached Settings instance."""
    return Settings()
