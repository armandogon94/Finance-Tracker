import uuid

from fastapi import Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.database import get_db
from src.app.dependencies.auth import get_current_user
from src.app.models.feature_flag import UserFeatureFlag
from src.app.models.user import User


async def get_user_features(user_id: uuid.UUID, db: AsyncSession) -> dict[str, bool]:
    result = await db.execute(
        select(UserFeatureFlag).where(UserFeatureFlag.user_id == user_id)
    )
    return {f.feature_name: f.is_enabled for f in result.scalars().all()}


def require_feature(feature_name: str):
    """FastAPI dependency that gates an endpoint behind a feature flag."""

    async def check_feature(
        current_user: User = Depends(get_current_user),
        db: AsyncSession = Depends(get_db),
    ) -> User:
        features = await get_user_features(current_user.id, db)
        if not features.get(feature_name, False):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Feature '{feature_name}' not enabled for your account",
            )
        return current_user

    return check_feature
