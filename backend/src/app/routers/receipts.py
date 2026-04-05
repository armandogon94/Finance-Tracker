import uuid
from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, status
from fastapi.responses import FileResponse
from pathlib import Path
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.config import settings
from src.app.database import get_db
from src.app.dependencies.auth import get_current_user
from src.app.models.category import Category
from src.app.models.expense import Expense
from src.app.models.receipt import PendingReceipt, ReceiptArchive
from src.app.models.user import User
from src.app.services.image_processor import process_receipt_image
from src.app.services.ocr import extract_receipt

router = APIRouter(prefix="/api/v1/receipts", tags=["receipts"])

ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp", "image/heic"}


# ─── Scan receipt image ─────────────────────────────────────────────────────


@router.post("/scan")
async def scan_receipt(
    file: UploadFile,
    current_user: User = Depends(get_current_user),
):
    """Upload a receipt image, process it, run OCR, and return extracted data.

    The image is preprocessed (EXIF correction, resize, thumbnail) and then
    passed through the OCR pipeline (Claude Vision or Tesseract depending on
    configuration). The returned data is a preview that the user can confirm
    via POST /confirm.
    """
    if file.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported image type '{file.content_type}'. Allowed: {', '.join(ALLOWED_IMAGE_TYPES)}",
        )

    raw_bytes = await file.read()
    if len(raw_bytes) == 0:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Uploaded file is empty",
        )

    # Use a temporary expense ID for file storage until confirmed
    temp_id = str(uuid.uuid4())

    # Process image: resize, thumbnail, base64
    try:
        image_result = process_receipt_image(
            raw_bytes=raw_bytes,
            user_id=str(current_user.id),
            expense_id=temp_id,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        )

    # Run OCR on the processed image
    ocr_result = extract_receipt(
        image_path=image_result["original_path"],
        image_base64=image_result["base64"],
        mode=settings.ocr_mode,
    )

    return {
        "temp_id": temp_id,
        "image_path": image_result["original_path"],
        "thumbnail_path": image_result["thumb_path"],
        "file_size": image_result["file_size"],
        "ocr_data": ocr_result,
        "ocr_method": ocr_result.get("method", "unknown"),
        "needs_review": ocr_result.get("needs_review", True),
    }


# ─── Confirm scanned receipt ────────────────────────────────────────────────


from pydantic import BaseModel


class ReceiptConfirm(BaseModel):
    temp_id: str
    image_path: str
    thumbnail_path: str | None = None
    file_size: int | None = None
    category_id: uuid.UUID | None = None
    amount: float
    tax_amount: float = 0
    currency: str = "USD"
    description: str | None = None
    merchant_name: str | None = None
    expense_date: date | None = None
    notes: str | None = None
    is_tax_deductible: bool = False
    ocr_data: dict | None = None
    ocr_method: str | None = None
    ocr_confidence: float | None = None


def _validate_receipt_path(path: str) -> bool:
    """Validate that a receipt image path is within the allowed storage directory.

    Prevents path traversal attacks by ensuring the resolved path starts with
    the configured receipt storage path.
    """
    if not path:
        return False
    resolved = Path(path).resolve()
    allowed = Path(settings.receipt_storage_path).resolve()
    return str(resolved).startswith(str(allowed))


@router.post("/confirm", status_code=status.HTTP_201_CREATED)
async def confirm_receipt(
    data: ReceiptConfirm,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Confirm OCR-extracted receipt data and create an Expense + ReceiptArchive record.

    This endpoint is called after the user reviews the OCR output from /scan
    and makes any corrections. It creates the expense record and archives the
    receipt image for tax purposes.
    """
    # Validate receipt image path is within allowed storage (prevent path traversal)
    if not _validate_receipt_path(data.image_path):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid receipt image path",
        )
    if data.thumbnail_path and not _validate_receipt_path(data.thumbnail_path):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid thumbnail image path",
        )

    # Validate category belongs to user if provided
    if data.category_id is not None:
        cat_result = await db.execute(
            select(Category).where(
                Category.id == data.category_id,
                Category.user_id == current_user.id,
                Category.is_active == True,  # noqa: E712
            )
        )
        if cat_result.scalar_one_or_none() is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Category not found or inactive",
            )

    expense_date = data.expense_date or date.today()

    # Create the expense
    expense = Expense(
        user_id=current_user.id,
        category_id=data.category_id,
        amount=data.amount,
        tax_amount=data.tax_amount,
        currency=data.currency,
        description=data.description,
        merchant_name=data.merchant_name,
        expense_date=expense_date,
        notes=data.notes,
        is_tax_deductible=data.is_tax_deductible,
        receipt_image_path=data.image_path,
        receipt_ocr_data=data.ocr_data,
        ocr_method=data.ocr_method,
        ocr_confidence=data.ocr_confidence,
    )
    db.add(expense)
    await db.flush()  # Get expense.id before creating archive

    # Create the receipt archive record
    archive = ReceiptArchive(
        expense_id=expense.id,
        user_id=current_user.id,
        image_path=data.image_path,
        thumbnail_path=data.thumbnail_path,
        file_size_bytes=data.file_size,
        mime_type="image/jpeg",
        tax_year=expense_date.year,
        tax_month=expense_date.month,
        is_tax_deductible=data.is_tax_deductible,
    )
    db.add(archive)

    await db.commit()
    await db.refresh(expense)
    await db.refresh(archive)

    return {
        "expense_id": expense.id,
        "archive_id": archive.id,
        "amount": float(expense.amount),
        "merchant_name": expense.merchant_name,
        "expense_date": str(expense.expense_date),
        "image_path": archive.image_path,
    }


# ─── Browse archived receipts ───────────────────────────────────────────────


@router.get("/archive")
async def list_archived_receipts(
    year: int | None = Query(None, ge=2000, le=2100, description="Filter by tax year"),
    month: int | None = Query(None, ge=1, le=12, description="Filter by month"),
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Browse archived receipts with optional year/month filtering.

    Returns paginated receipt archive records, most recent first.
    """
    stmt = select(ReceiptArchive).where(ReceiptArchive.user_id == current_user.id)

    if year is not None:
        stmt = stmt.where(ReceiptArchive.tax_year == year)
    if month is not None:
        stmt = stmt.where(ReceiptArchive.tax_month == month)

    # Count total
    from sqlalchemy import func

    count_stmt = select(func.count()).select_from(stmt.subquery())
    total = (await db.execute(count_stmt)).scalar_one()

    # Paginate
    offset = (page - 1) * per_page
    rows_stmt = stmt.order_by(ReceiptArchive.uploaded_at.desc()).offset(offset).limit(per_page)
    result = await db.execute(rows_stmt)
    items = result.scalars().all()

    return {
        "items": [
            {
                "id": str(r.id),
                "expense_id": str(r.expense_id),
                "image_path": r.image_path,
                "thumbnail_path": r.thumbnail_path,
                "file_size_bytes": r.file_size_bytes,
                "mime_type": r.mime_type,
                "tax_year": r.tax_year,
                "tax_month": r.tax_month,
                "is_tax_deductible": r.is_tax_deductible,
                "uploaded_at": r.uploaded_at.isoformat() if r.uploaded_at else None,
            }
            for r in items
        ],
        "total": total,
        "page": page,
        "per_page": per_page,
    }


# ─── Serve receipt image ────────────────────────────────────────────────────


@router.get("/{receipt_id}/image")
async def get_receipt_image(
    receipt_id: uuid.UUID,
    thumbnail: bool = Query(False, description="Return thumbnail instead of full image"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Serve a receipt image file by archive ID.

    Returns the full-size image by default, or the thumbnail if ?thumbnail=true.
    Only the receipt owner can access the image.
    """
    result = await db.execute(
        select(ReceiptArchive).where(
            ReceiptArchive.id == receipt_id,
            ReceiptArchive.user_id == current_user.id,
        )
    )
    archive = result.scalar_one_or_none()
    if archive is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Receipt not found",
        )

    image_path = archive.thumbnail_path if (thumbnail and archive.thumbnail_path) else archive.image_path
    file_path = Path(image_path)

    if not file_path.exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Receipt image file not found on disk",
        )

    return FileResponse(
        path=str(file_path),
        media_type=archive.mime_type or "image/jpeg",
        filename=file_path.name,
    )


# ─── Queue receipt for later analysis ──────────────────────────────────────


@router.post("/queue", status_code=status.HTTP_201_CREATED)
async def queue_receipt(
    file: UploadFile,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Save a receipt image to the pending queue for later OCR analysis.

    The image is processed and stored immediately, but OCR is deferred.
    """
    if file.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported image type '{file.content_type}'. Allowed: {', '.join(ALLOWED_IMAGE_TYPES)}",
        )

    raw_bytes = await file.read()
    if len(raw_bytes) == 0:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Uploaded file is empty",
        )

    pending_id = str(uuid.uuid4())

    try:
        image_result = process_receipt_image(
            raw_bytes=raw_bytes,
            user_id=str(current_user.id),
            expense_id=pending_id,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        )

    pending = PendingReceipt(
        id=uuid.UUID(pending_id),
        user_id=current_user.id,
        image_path=image_result["original_path"],
        thumbnail_path=image_result["thumb_path"],
        file_size_bytes=image_result["file_size"],
        status="pending",
    )
    db.add(pending)
    await db.commit()
    await db.refresh(pending)

    return {
        "id": str(pending.id),
        "status": pending.status,
        "thumbnail_path": pending.thumbnail_path,
        "created_at": pending.created_at.isoformat(),
    }


# ─── List pending receipts ─────────────────────────────────────────────────


@router.get("/pending")
async def list_pending_receipts(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List all pending/analyzed receipts for the current user, newest first."""
    result = await db.execute(
        select(PendingReceipt)
        .where(PendingReceipt.user_id == current_user.id)
        .order_by(PendingReceipt.created_at.desc())
    )
    items = result.scalars().all()

    return [
        {
            "id": str(r.id),
            "status": r.status,
            "image_path": r.image_path,
            "thumbnail_path": r.thumbnail_path,
            "file_size_bytes": r.file_size_bytes,
            "ocr_data": r.ocr_data,
            "ocr_method": r.ocr_method,
            "error_message": r.error_message,
            "created_at": r.created_at.isoformat() if r.created_at else None,
            "analyzed_at": r.analyzed_at.isoformat() if r.analyzed_at else None,
        }
        for r in items
    ]


# ─── Serve pending receipt image ───────────────────────────────────────────


@router.get("/pending/{pending_id}/image")
async def get_pending_receipt_image(
    pending_id: uuid.UUID,
    thumbnail: bool = Query(False),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Serve a pending receipt image."""
    result = await db.execute(
        select(PendingReceipt).where(
            PendingReceipt.id == pending_id,
            PendingReceipt.user_id == current_user.id,
        )
    )
    pending = result.scalar_one_or_none()
    if pending is None:
        raise HTTPException(status_code=404, detail="Pending receipt not found")

    image_path = pending.thumbnail_path if (thumbnail and pending.thumbnail_path) else pending.image_path
    file_path = Path(image_path)
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Image file not found on disk")

    return FileResponse(path=str(file_path), media_type="image/jpeg")


# ─── Delete pending receipt ────────────────────────────────────────────────


@router.delete("/pending/{pending_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_pending_receipt(
    pending_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Remove a pending receipt from the queue."""
    result = await db.execute(
        select(PendingReceipt).where(
            PendingReceipt.id == pending_id,
            PendingReceipt.user_id == current_user.id,
        )
    )
    pending = result.scalar_one_or_none()
    if pending is None:
        raise HTTPException(status_code=404, detail="Pending receipt not found")

    # Remove image files
    for path_str in [pending.image_path, pending.thumbnail_path]:
        if path_str:
            p = Path(path_str)
            if p.exists():
                p.unlink()

    await db.delete(pending)
    await db.commit()
