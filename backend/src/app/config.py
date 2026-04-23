from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Database
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/finance_db"
    db_pool_size: int = 20
    db_max_overflow: int = 10

    # JWT
    jwt_secret: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 15
    refresh_token_expire_days: int = 7

    # API Keys
    anthropic_api_key: str = ""

    # OCR
    ocr_mode: str = "auto"  # auto, cloud, ollama, offline, manual

    # Ollama (local LLM for OCR)
    ollama_base_url: str = "http://localhost:11434"
    ollama_model: str = "gemma4"

    # Storage
    receipt_storage_path: str = "/data/receipts"

    # Telegram
    telegram_bot_token: str = ""
    telegram_bot_internal_secret: str = ""  # Shared secret for bot -> API calls

    # App
    app_name: str = "Finance Tracker"
    debug: bool = False
    cors_origins: list[str] = ["http://localhost:3000"]

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
