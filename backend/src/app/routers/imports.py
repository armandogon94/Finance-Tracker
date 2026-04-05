import io
import logging
import re
import uuid
from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, UploadFile, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.database import get_db
from src.app.dependencies.auth import get_current_user
from src.app.models.auto_label import AutoLabelRule
from src.app.models.category import Category
from src.app.models.expense import Expense
from src.app.models.import_history import ImportHistory
from src.app.models.user import User
from src.app.schemas.imports import (
    ImportConfirm,
    ImportPreview,
    ImportResult,
    ParsedTransaction,
)
from src.app.services.csv_parser import BANK_COLUMN_MAPS, _parse_date, parse_bank_csv

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/import", tags=["imports"])

ALLOWED_CONTENT_TYPES = {
    "text/csv",
    "application/csv",
    "application/vnd.ms-excel",
    "application/pdf",
    "text/plain",  # Some systems send CSV as text/plain
}


# ─── Auto-labeling helper ───────────────────────────────────────────────────


async def _auto_label_transactions(
    transactions: list[dict],
    user_id: uuid.UUID,
    db: AsyncSession,
) -> list[dict]:
    """Apply the user's auto-label rules to parsed transactions.

    For each transaction, check its description against all active rules
    (sorted by priority). First match wins -- sets suggested_category_id,
    auto_labeled flag, and optionally is_hidden.
    """
    result = await db.execute(
        select(AutoLabelRule)
        .where(
            AutoLabelRule.user_id == user_id,
            AutoLabelRule.is_active == True,  # noqa: E712
        )
        .order_by(AutoLabelRule.priority.asc())
    )
    rules = result.scalars().all()

    if not rules:
        return transactions

    for txn in transactions:
        desc_lower = txn.get("description", "").lower()
        for rule in rules:
            if rule.keyword.lower() in desc_lower:
                txn["suggested_category_id"] = str(rule.category_id)
                txn["auto_labeled"] = True
                txn["label_rule_name"] = rule.keyword
                txn["is_hidden"] = rule.assign_hidden
                break

    return transactions


# ─── Duplicate detection helper ──────────────────────────────────────────────


async def _detect_duplicates(
    transactions: list[dict],
    user_id: uuid.UUID,
    db: AsyncSession,
) -> list[dict]:
    """Flag transactions that are likely duplicates of existing expenses.

    Checks for existing expenses with the same date and amount. When found,
    uses fuzzy string matching on descriptions to determine confidence.
    """
    try:
        from rapidfuzz import fuzz
    except ImportError:
        logger.warning("rapidfuzz not installed, skipping duplicate detection")
        return transactions

    for txn in transactions:
        txn_date_str = txn.get("date", "")
        txn_amount = txn.get("amount", 0)
        txn_desc = txn.get("description", "")

        if not txn_date_str or not txn_amount:
            continue

        # Parse the transaction date
        try:
            if isinstance(txn_date_str, str):
                txn_date = datetime.strptime(txn_date_str, "%Y-%m-%d").date()
            else:
                txn_date = txn_date_str
        except (ValueError, TypeError):
            continue

        # Query existing expenses with same date and amount
        existing_result = await db.execute(
            select(Expense).where(
                Expense.user_id == user_id,
                Expense.expense_date == txn_date,
                Expense.amount == txn_amount,
            )
        )
        existing = existing_result.scalars().all()

        if existing:
            # Check description similarity
            best_score = 0.0
            for exp in existing:
                exp_desc = exp.description or exp.merchant_name or ""
                score = fuzz.token_set_ratio(txn_desc.lower(), exp_desc.lower())
                best_score = max(best_score, score)

            if best_score >= 85:
                txn["possible_duplicate"] = True
                txn["duplicate_confidence"] = round(best_score / 100, 2)
                txn["include"] = False  # Default to excluding duplicates

    return transactions


# ─── Upload and parse ────────────────────────────────────────────────────────


@router.post("/upload", response_model=ImportPreview)
async def upload_statement(
    file: UploadFile,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Upload a bank statement (CSV or PDF), parse transactions, auto-label, and detect duplicates.

    Returns a preview of parsed transactions with suggested categories and
    duplicate flags. The user reviews this preview and then calls POST /confirm
    to actually import the selected transactions.
    """
    if file.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=(
                f"Unsupported file type '{file.content_type}'. "
                f"Upload a CSV or PDF bank statement."
            ),
        )

    raw_bytes = await file.read()
    if len(raw_bytes) == 0:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Uploaded file is empty",
        )

    filename = file.filename or "unknown"
    source_type: str
    transactions: list[dict]
    bank_detected: str | None = None

    # Determine format and parse
    is_pdf = (
        file.content_type == "application/pdf"
        or filename.lower().endswith(".pdf")
    )

    if is_pdf:
        source_type = "pdf"
        transactions, bank_detected = await _parse_pdf_statement(raw_bytes)
    else:
        source_type = "csv"
        content = raw_bytes.decode("utf-8", errors="replace")
        try:
            transactions = parse_bank_csv(content, bank_preset="auto")
        except ValueError as exc:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=str(exc),
            )
        # Detect bank from the parsed result metadata
        from src.app.services.csv_parser import detect_bank_format
        import pandas as pd
        try:
            df = pd.read_csv(io.StringIO(content))
            bank_detected = detect_bank_format([col.strip() for col in df.columns.tolist()])
            if bank_detected == "generic":
                bank_detected = None
        except Exception:
            bank_detected = None

    # Auto-label using user's rules
    transactions = await _auto_label_transactions(transactions, current_user.id, db)

    # Detect duplicates
    transactions = await _detect_duplicates(transactions, current_user.id, db)

    # Convert to ParsedTransaction schema
    parsed = []
    for txn in transactions:
        cat_id = txn.get("suggested_category_id")
        parsed.append(ParsedTransaction(
            date=txn.get("date", str(date.today())),
            description=txn.get("description", ""),
            amount=txn.get("amount", 0),
            is_expense=txn.get("is_expense", True),
            suggested_category_id=uuid.UUID(cat_id) if cat_id else None,
            auto_labeled=txn.get("auto_labeled", False),
            label_rule_name=txn.get("label_rule_name"),
            is_hidden=txn.get("is_hidden", False),
            possible_duplicate=txn.get("possible_duplicate", False),
            duplicate_confidence=txn.get("duplicate_confidence"),
            include=txn.get("include", True),
        ))

    return ImportPreview(
        transactions=parsed,
        total_parsed=len(parsed),
        bank_detected=bank_detected,
        source_type=source_type,
        filename=filename,
    )


async def _parse_pdf_statement(raw_bytes: bytes) -> tuple[list[dict], str | None]:
    """Parse a PDF bank statement using pdfplumber.

    Extracts tables from each page and attempts to identify date, description,
    and amount columns. Returns (transactions, detected_bank).
    """
    try:
        import pdfplumber
    except ImportError:
        raise HTTPException(
            status_code=status.HTTP_501_NOT_IMPLEMENTED,
            detail="PDF parsing requires pdfplumber. Install with: pip install pdfplumber",
        )

    transactions: list[dict] = []
    bank_detected: str | None = None

    try:
        pdf = pdfplumber.open(io.BytesIO(raw_bytes))
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Could not open PDF: {str(exc)}",
        )

    try:
        for page in pdf.pages:
            tables = page.extract_tables()
            for table in tables:
                if not table or len(table) < 2:
                    continue

                # Use first row as headers
                headers = [str(cell).strip().lower() if cell else "" for cell in table[0]]

                # Try to identify column indices
                date_idx = None
                desc_idx = None
                amount_idx = None

                for i, h in enumerate(headers):
                    if any(kw in h for kw in ("date", "fecha", "trans")):
                        date_idx = i
                    elif any(kw in h for kw in ("description", "desc", "payee", "detail", "memo")):
                        desc_idx = i
                    elif any(kw in h for kw in ("amount", "debit", "withdrawal", "monto")):
                        amount_idx = i

                # Fallback: assume columns 0=date, 1=description, 2=amount
                if date_idx is None and len(headers) >= 3:
                    date_idx = 0
                if desc_idx is None and len(headers) >= 3:
                    desc_idx = 1
                if amount_idx is None and len(headers) >= 3:
                    amount_idx = 2

                if date_idx is None or desc_idx is None or amount_idx is None:
                    continue

                # Parse rows (skip header)
                for row in table[1:]:
                    if not row or len(row) <= max(date_idx, desc_idx, amount_idx):
                        continue

                    raw_date = str(row[date_idx] or "").strip()
                    raw_desc = str(row[desc_idx] or "").strip()
                    raw_amount = str(row[amount_idx] or "").strip()

                    if not raw_date or not raw_amount:
                        continue

                    # Parse amount
                    cleaned = re.sub(r"[$ ,]", "", raw_amount)
                    try:
                        amount = float(cleaned)
                    except ValueError:
                        continue

                    # Parse date
                    parsed_date = _parse_date(raw_date)

                    transactions.append({
                        "date": parsed_date,
                        "description": raw_desc,
                        "amount": round(abs(amount), 2),
                        "is_expense": amount < 0,  # Negative amounts are debits/expenses in bank statements
                        "needs_categorization": True,
                    })
    finally:
        pdf.close()

    return transactions, bank_detected


# ─── Confirm import ──────────────────────────────────────────────────────────


@router.post("/confirm", response_model=ImportResult)
async def confirm_import(
    data: ImportConfirm,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Confirm and import selected transactions from a previously uploaded statement.

    Creates Expense records for each included transaction and records the
    import in ImportHistory.
    """
    # Filter to only included transactions
    to_import = [t for t in data.transactions if t.include]
    if not to_import:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="No transactions selected for import",
        )

    # Validate all referenced categories belong to the user
    category_ids = {t.suggested_category_id for t in to_import if t.suggested_category_id}
    if category_ids:
        cat_result = await db.execute(
            select(Category.id).where(
                Category.id.in_(category_ids),
                Category.user_id == current_user.id,
            )
        )
        valid_cat_ids = {row for row in cat_result.scalars().all()}
        invalid = category_ids - valid_cat_ids
        if invalid:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Categories not found: {[str(c) for c in invalid]}",
            )

    # Create import history record first
    import_record = ImportHistory(
        user_id=current_user.id,
        source_type=data.source_type,
        bank_preset=data.bank_preset,
        original_filename=data.original_filename,
        transactions_parsed=len(data.transactions),
        transactions_imported=len(to_import),
    )
    db.add(import_record)
    await db.flush()

    # Bulk create expenses
    imported_count = 0
    for txn in to_import:
        expense = Expense(
            user_id=current_user.id,
            category_id=txn.suggested_category_id,
            amount=txn.amount,
            description=txn.description,
            expense_date=txn.date,
            currency=current_user.currency,
            import_id=import_record.id,
        )
        db.add(expense)
        imported_count += 1

    await db.commit()
    await db.refresh(import_record)

    skipped = len(data.transactions) - imported_count

    return ImportResult(
        imported=imported_count,
        skipped=skipped,
        import_id=import_record.id,
    )


# ─── Import history ─────────────────────────────────────────────────────────


@router.get("/history")
async def list_import_history(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List past import operations for the current user, most recent first."""
    result = await db.execute(
        select(ImportHistory)
        .where(ImportHistory.user_id == current_user.id)
        .order_by(ImportHistory.import_date.desc())
    )
    imports = result.scalars().all()

    return [
        {
            "id": str(imp.id),
            "source_type": imp.source_type,
            "bank_preset": imp.bank_preset,
            "original_filename": imp.original_filename,
            "transactions_parsed": imp.transactions_parsed,
            "transactions_imported": imp.transactions_imported,
            "import_date": imp.import_date.isoformat() if imp.import_date else None,
        }
        for imp in imports
    ]


# ─── Bank templates ──────────────────────────────────────────────────────────


@router.get("/templates")
async def list_bank_templates():
    """Return available bank presets for CSV import.

    Each preset describes the expected column mappings so the frontend can
    display supported banks and let users select one manually if auto-detection
    fails.
    """
    templates = []
    for bank_key, col_map in BANK_COLUMN_MAPS.items():
        if bank_key == "generic":
            continue
        templates.append({
            "key": bank_key,
            "name": bank_key.replace("_", " ").title(),
            "date_column": col_map.get("date"),
            "description_column": col_map.get("description"),
            "amount_column": col_map.get("amount"),
            "date_format": col_map.get("date_format"),
        })

    # Always include generic as the last option
    templates.append({
        "key": "generic",
        "name": "Generic / Other",
        "date_column": "Column 1",
        "description_column": "Column 2",
        "amount_column": "Column 3",
        "date_format": "auto-detect",
    })

    return {"templates": templates}
