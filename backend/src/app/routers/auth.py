import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.config import settings
from src.app.database import get_db
from src.app.dependencies.auth import (
    authenticate_user,
    create_access_token,
    create_refresh_token,
    get_current_user,
    hash_password,
    revoke_user_tokens,
    store_refresh_token,
    validate_refresh_token,
)
from src.app.models.category import Category
from src.app.models.user import User
from src.app.schemas.auth import (
    RefreshRequest,
    TokenResponse,
    UserLogin,
    UserRegister,
    UserResponse,
    UserUpdate,
)

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])

DEFAULT_CATEGORIES = [
    {"name": "Food & Dining", "icon": "utensils", "color": "#EF4444"},
    {"name": "Transportation", "icon": "car", "color": "#F59E0B"},
    {"name": "Shopping", "icon": "shopping-bag", "color": "#8B5CF6"},
    {"name": "Entertainment", "icon": "film", "color": "#EC4899"},
    {"name": "Bills & Utilities", "icon": "zap", "color": "#6366F1"},
    {"name": "Health", "icon": "heart", "color": "#10B981"},
    {"name": "Education", "icon": "book", "color": "#3B82F6"},
    {"name": "Personal", "icon": "user", "color": "#F97316"},
    {"name": "Other", "icon": "receipt", "color": "#6B7280"},
]


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def register(data: UserRegister, db: AsyncSession = Depends(get_db)):
    """Create a new user account, seed default categories, and return tokens."""
    # Check if email already exists
    result = await db.execute(select(User).where(User.email == data.email))
    if result.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A user with this email already exists",
        )

    # Create user
    user = User(
        email=data.email,
        hashed_password=hash_password(data.password),
        display_name=data.display_name,
        currency=data.currency,
        timezone=data.timezone,
    )
    db.add(user)
    await db.flush()  # Get user.id assigned before creating categories

    # Seed default categories
    for idx, cat_data in enumerate(DEFAULT_CATEGORIES):
        category = Category(
            user_id=user.id,
            name=cat_data["name"],
            icon=cat_data["icon"],
            color=cat_data["color"],
            sort_order=idx,
        )
        db.add(category)

    await db.commit()
    await db.refresh(user)

    # Generate tokens
    access_token = create_access_token(user)
    raw_refresh, refresh_hash = create_refresh_token()
    await store_refresh_token(db, user.id, refresh_hash)

    return TokenResponse(
        access_token=access_token,
        refresh_token=raw_refresh,
        expires_in=settings.access_token_expire_minutes * 60,
    )


@router.post("/login", response_model=TokenResponse)
async def login(data: UserLogin, db: AsyncSession = Depends(get_db)):
    """Authenticate a user with email and password, return tokens."""
    user = await authenticate_user(db, data.email, data.password)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    access_token = create_access_token(user)
    raw_refresh, refresh_hash = create_refresh_token()
    await store_refresh_token(db, user.id, refresh_hash)

    return TokenResponse(
        access_token=access_token,
        refresh_token=raw_refresh,
        expires_in=settings.access_token_expire_minutes * 60,
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh(data: RefreshRequest, db: AsyncSession = Depends(get_db)):
    """Exchange a valid refresh token for a new access token pair."""
    user = await validate_refresh_token(db, data.refresh_token)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )

    # Revoke old tokens and issue fresh ones
    await revoke_user_tokens(db, user.id)

    access_token = create_access_token(user)
    raw_refresh, refresh_hash = create_refresh_token()
    await store_refresh_token(db, user.id, refresh_hash)

    return TokenResponse(
        access_token=access_token,
        refresh_token=raw_refresh,
        expires_in=settings.access_token_expire_minutes * 60,
    )


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Revoke all refresh tokens for the current user."""
    await revoke_user_tokens(db, current_user.id)


@router.get("/me", response_model=UserResponse)
async def get_me(current_user: User = Depends(get_current_user)):
    """Return the current authenticated user's profile."""
    return current_user


@router.patch("/me", response_model=UserResponse)
async def update_me(
    data: UserUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update the current user's profile fields (display_name, currency, timezone)."""
    update_data = data.model_dump(exclude_unset=True)
    if not update_data:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="No fields provided to update",
        )

    for field, value in update_data.items():
        setattr(current_user, field, value)

    db.add(current_user)
    await db.commit()
    await db.refresh(current_user)

    return current_user
