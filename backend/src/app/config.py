from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Database
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/finance_db"

    # JWT
    jwt_secret: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 15
    refresh_token_expire_days: int = 7

    # API Keys
    anthropic_api_key: str = ""

    # OCR
    ocr_mode: str = "auto"  # auto, cloud, offline, manual

    # Storage
    receipt_storage_path: str = "/data/receipts"

    # Telegram
    telegram_bot_token: str = ""

    # App
    app_name: str = "Finance Tracker"
    debug: bool = False
    cors_origins: list[str] = ["http://localhost:3000"]

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
