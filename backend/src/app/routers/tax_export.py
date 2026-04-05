import csv
import io
import uuid
import zipfile
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import StreamingResponse
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.database import get_db
from src.app.dependencies.auth import get_current_user
from src.app.models.category import Category
from src.app.models.expense import Expense
from src.app.models.receipt import ReceiptArchive
from src.app.models.user import User

router = APIRouter(prefix="/api/v1/tax", tags=["tax"])


# ─── Annual summary ─────────────────────────────────────────────────────────


@router.get("/summary/{year}")
async def tax_summary(
    year: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Annual spending totals by category for a given year.

    Provides a high-level tax summary showing total spending per category,
    how much of each is tax-deductible, and overall totals. Useful for
    year-end tax preparation.
    """
    # Total spending by category
    stmt = (
        select(
            Expense.category_id,
            Category.name.label("category_name"),
            func.sum(Expense.amount).label("total"),
            func.sum(Expense.tax_amount).label("total_tax"),
            func.count(Expense.id).label("count"),
            func.sum(
                # Sum only amounts that are tax-deductible
                Expense.amount * func.cast(Expense.is_tax_deductible, type_=Expense.amount.type)
            ).label("deductible_total"),
        )
        .outerjoin(Category, Expense.category_id == Category.id)
        .where(
            Expense.user_id == current_user.id,
            func.extract("year", Expense.expense_date) == year,
        )
        .group_by(Expense.category_id, Category.name)
        .order_by(func.sum(Expense.amount).desc())
    )

    result = await db.execute(stmt)
    rows = result.all()

    categories = []
    grand_total = 0.0
    grand_tax = 0.0
    grand_deductible = 0.0
    total_expenses = 0

    for row in rows:
        total = round(float(row.total or 0), 2)
        tax = round(float(row.total_tax or 0), 2)
        deductible = round(float(row.deductible_total or 0), 2)

        grand_total += total
        grand_tax += tax
        grand_deductible += deductible
        total_expenses += row.count

        categories.append({
            "category_id": str(row.category_id) if row.category_id else None,
            "category_name": row.category_name or "Uncategorized",
            "total_spending": total,
            "total_tax_collected": tax,
            "deductible_amount": deductible,
            "expense_count": row.count,
        })

    # Count receipts for the year
    receipt_count_result = await db.execute(
        select(func.count(ReceiptArchive.id)).where(
            ReceiptArchive.user_id == current_user.id,
            ReceiptArchive.tax_year == year,
        )
    )
    receipt_count = receipt_count_result.scalar() or 0

    return {
        "year": year,
        "categories": categories,
        "grand_total": round(grand_total, 2),
        "grand_tax_collected": round(grand_tax, 2),
        "grand_deductible": round(grand_deductible, 2),
        "total_expenses": total_expenses,
        "receipt_count": receipt_count,
    }


# ─── Export CSV ──────────────────────────────────────────────────────────────


@router.get("/export/{year}")
async def export_expenses_csv(
    year: int,
    include_hidden: bool = Query(False, description="Include hidden-category expenses"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Download all expenses for a given year as a CSV file.

    Each row includes date, description, merchant, amount, tax, category,
    and tax-deductible flag. Suitable for importing into tax software or
    spreadsheets.
    """
    stmt = (
        select(
            Expense.expense_date,
            Expense.description,
            Expense.merchant_name,
            Expense.amount,
            Expense.tax_amount,
            Expense.currency,
            Category.name.label("category_name"),
            Expense.is_tax_deductible,
            Expense.is_recurring,
            Expense.notes,
            Expense.tags,
        )
        .outerjoin(Category, Expense.category_id == Category.id)
        .where(
            Expense.user_id == current_user.id,
            func.extract("year", Expense.expense_date) == year,
        )
    )

    if not include_hidden:
        stmt = stmt.where(
            or_(
                Expense.category_id.is_(None),
                Category.is_hidden == False,  # noqa: E712
            )
        )

    stmt = stmt.order_by(Expense.expense_date.asc())

    result = await db.execute(stmt)
    rows = result.all()

    if not rows:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No expenses found for year {year}",
        )

    # Build CSV in memory
    output = io.StringIO()
    writer = csv.DictWriter(
        output,
        fieldnames=[
            "Date",
            "Description",
            "Merchant",
            "Amount",
            "Tax",
            "Currency",
            "Category",
            "Tax Deductible",
            "Recurring",
            "Notes",
            "Tags",
        ],
    )
    writer.writeheader()

    for row in rows:
        writer.writerow({
            "Date": str(row.expense_date),
            "Description": row.description or "",
            "Merchant": row.merchant_name or "",
            "Amount": f"{float(row.amount):.2f}",
            "Tax": f"{float(row.tax_amount):.2f}" if row.tax_amount else "0.00",
            "Currency": row.currency or "USD",
            "Category": row.category_name or "Uncategorized",
            "Tax Deductible": "Yes" if row.is_tax_deductible else "No",
            "Recurring": "Yes" if row.is_recurring else "No",
            "Notes": row.notes or "",
            "Tags": ", ".join(row.tags) if row.tags else "",
        })

    output.seek(0)
    filename = f"expenses_{year}_{current_user.email.split('@')[0]}.csv"

    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ─── Export receipt images as ZIP ────────────────────────────────────────────


@router.get("/receipts/{year}")
async def export_receipts_zip(
    year: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Download all receipt images for a given year as a ZIP archive.

    Each receipt is stored in the ZIP with a descriptive filename including
    the month and original expense details. Only receipts where the image
    file still exists on disk are included.
    """
    # Fetch all receipt archives for the year, joined with expense for metadata
    stmt = (
        select(
            ReceiptArchive.image_path,
            ReceiptArchive.tax_month,
            ReceiptArchive.is_tax_deductible,
            Expense.expense_date,
            Expense.merchant_name,
            Expense.amount,
            Expense.description,
        )
        .join(Expense, ReceiptArchive.expense_id == Expense.id)
        .where(
            ReceiptArchive.user_id == current_user.id,
            ReceiptArchive.tax_year == year,
        )
        .order_by(ReceiptArchive.tax_month.asc(), Expense.expense_date.asc())
    )

    result = await db.execute(stmt)
    rows = result.all()

    if not rows:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No receipts found for year {year}",
        )

    # Build ZIP in memory
    zip_buffer = io.BytesIO()
    files_added = 0

    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        for idx, row in enumerate(rows):
            image_path = Path(row.image_path)
            if not image_path.exists():
                continue

            # Build a descriptive filename inside the ZIP
            month_str = f"{row.tax_month:02d}"
            date_str = str(row.expense_date) if row.expense_date else "unknown"
            merchant = (row.merchant_name or row.description or "receipt")[:30]
            # Clean merchant name for use in filename
            merchant_clean = "".join(
                c if c.isalnum() or c in (" ", "-", "_") else "_" for c in merchant
            ).strip()
            amount_str = f"${float(row.amount):.2f}" if row.amount else ""
            deductible_marker = "_TAX" if row.is_tax_deductible else ""

            zip_filename = (
                f"{month_str}/{date_str}_{merchant_clean}_{amount_str}{deductible_marker}"
                f"_{idx:04d}{image_path.suffix}"
            )

            zf.write(image_path, zip_filename)
            files_added += 1

    if files_added == 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No receipt image files found on disk for year {year}",
        )

    zip_buffer.seek(0)
    filename = f"receipts_{year}_{current_user.email.split('@')[0]}.zip"

    return StreamingResponse(
        iter([zip_buffer.getvalue()]),
        media_type="application/zip",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
