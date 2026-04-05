"""
Receipt image processing service.

Handles EXIF correction, resizing, thumbnail generation, and organized
filesystem storage for receipt images. Produces base64 output for the
OCR pipeline.
"""

import base64
import io
import logging
from datetime import datetime
from pathlib import Path

from PIL import Image, ImageOps

from src.app.config import settings

logger = logging.getLogger(__name__)

# Maximum dimensions for processed receipt images
MAX_IMAGE_WIDTH = 1200
MAX_IMAGE_HEIGHT = 1200
THUMBNAIL_WIDTH = 200
JPEG_QUALITY = 80


def _build_storage_dir(user_id: str, now: datetime | None = None) -> Path:
    """Build the storage directory path: {receipt_storage_path}/{user_id}/{year}/{month}/"""
    if now is None:
        now = datetime.now()
    return (
        Path(settings.receipt_storage_path)
        / str(user_id)
        / str(now.year)
        / f"{now.month:02d}"
    )


def _resize_to_max(img: Image.Image, max_width: int, max_height: int) -> Image.Image:
    """Resize image so its longest side does not exceed the given limits.

    Maintains aspect ratio. Returns the image unchanged if already within bounds.
    """
    width, height = img.size
    if width <= max_width and height <= max_height:
        return img

    ratio = min(max_width / width, max_height / height)
    new_size = (int(width * ratio), int(height * ratio))
    return img.resize(new_size, Image.LANCZOS)


def _make_thumbnail(img: Image.Image, thumb_width: int = THUMBNAIL_WIDTH) -> Image.Image:
    """Create a proportionally-scaled thumbnail from the given image."""
    width, height = img.size
    ratio = thumb_width / width
    thumb_size = (thumb_width, int(height * ratio))
    thumb = img.copy()
    thumb.thumbnail(thumb_size, Image.LANCZOS)
    return thumb


def _image_to_base64(img: Image.Image, fmt: str = "JPEG", quality: int = JPEG_QUALITY) -> str:
    """Encode a PIL Image to a base64 string (no data-URI prefix)."""
    buffer = io.BytesIO()
    img.save(buffer, format=fmt, quality=quality)
    return base64.b64encode(buffer.getvalue()).decode("utf-8")


def process_receipt_image(
    raw_bytes: bytes,
    user_id: str,
    expense_id: str,
) -> dict:
    """Process a raw receipt image upload.

    Pipeline:
        1. Open image and apply EXIF orientation transpose.
        2. Resize to a max of 1200px on the longest side.
        3. Generate a 200px-wide thumbnail.
        4. Save both original and thumbnail as JPEG to the organized
           filesystem path: {receipt_storage_path}/{user_id}/{year}/{month}/
        5. Return metadata including paths, file size, and base64 of the
           processed original (for immediate OCR use).

    Args:
        raw_bytes:  Raw image bytes from the upload.
        user_id:    Authenticated user's ID (string UUID).
        expense_id: The expense this receipt belongs to (string UUID).

    Returns:
        dict with:
            original_path  - filesystem path to the saved original
            thumb_path     - filesystem path to the saved thumbnail
            file_size      - size of the saved original in bytes
            width          - pixel width of processed image
            height         - pixel height of processed image
            base64         - base64-encoded JPEG of the processed original
    """
    try:
        # Open and fix orientation
        img = Image.open(io.BytesIO(raw_bytes))
        img = ImageOps.exif_transpose(img)

        # Convert to RGB if necessary (handles RGBA, palette, etc.)
        if img.mode not in ("RGB", "L"):
            img = img.convert("RGB")

        # Resize
        img = _resize_to_max(img, MAX_IMAGE_WIDTH, MAX_IMAGE_HEIGHT)

        # Generate thumbnail
        thumb = _make_thumbnail(img, THUMBNAIL_WIDTH)

        # Prepare storage directory
        now = datetime.now()
        storage_dir = _build_storage_dir(user_id, now)
        storage_dir.mkdir(parents=True, exist_ok=True)

        # File paths
        original_filename = f"{expense_id}_original.jpg"
        thumb_filename = f"{expense_id}_thumb.jpg"
        original_path = storage_dir / original_filename
        thumb_path = storage_dir / thumb_filename

        # Save original
        img.save(str(original_path), format="JPEG", quality=JPEG_QUALITY)

        # Save thumbnail
        thumb.save(str(thumb_path), format="JPEG", quality=JPEG_QUALITY)

        # Get file size
        file_size = original_path.stat().st_size

        # Generate base64 for OCR
        img_base64 = _image_to_base64(img)

        logger.info(
            "Processed receipt image for user=%s expense=%s -> %s (%d bytes)",
            user_id,
            expense_id,
            original_path,
            file_size,
        )

        return {
            "original_path": str(original_path),
            "thumb_path": str(thumb_path),
            "file_size": file_size,
            "width": img.size[0],
            "height": img.size[1],
            "base64": img_base64,
        }

    except Exception as exc:
        logger.error(
            "Failed to process receipt image for user=%s expense=%s: %s",
            user_id,
            expense_id,
            exc,
            exc_info=True,
        )
        raise ValueError(f"Image processing failed: {str(exc)}") from exc
