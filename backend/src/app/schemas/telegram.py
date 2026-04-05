import uuid
from datetime import datetime

from pydantic import BaseModel


class TelegramLinkRequest(BaseModel):
    pass  # user_id comes from auth


class TelegramLinkResponse(BaseModel):
    code: str
    expires_at: datetime


class TelegramVerifyRequest(BaseModel):
    link_code: str
    telegram_user_id: int
    telegram_username: str | None = None


class TelegramVerifyResponse(BaseModel):
    success: bool
    user_id: uuid.UUID | None = None


class TelegramUserResponse(BaseModel):
    user_id: uuid.UUID
    linked: bool
    telegram_username: str | None = None


class TelegramUnlinkResponse(BaseModel):
    success: bool


class TelegramStatusResponse(BaseModel):
    linked: bool
    telegram_username: str | None = None
    linked_at: datetime | None = None
