from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.schemas.invoice import InvoiceSyncCreate
from app.schemas.sync import SyncResponse, ErrorResponse
from app.services.invoice_service import InvoiceSyncService

router = APIRouter(prefix="/api/v1", tags=["Invoice Synchronization"])

@router.post(
    "/invoices",
    response_model=SyncResponse,
    status_code=status.HTTP_200_OK,
    summary="Synchronize verified tax invoice from mobile client to central LAN server",
    responses={
        200: {"model": SyncResponse, "description": "Invoice synchronized or already synchronized"},
        400: {"model": ErrorResponse, "description": "Validation error or invalid status"},
        409: {"model": ErrorResponse, "description": "Integrity constraint conflict"},
        500: {"model": ErrorResponse, "description": "Server transaction failure"},
    }
)
def sync_invoice(
    payload: InvoiceSyncCreate,
    db: Session = Depends(get_db)
) -> SyncResponse:
    """
    Receives verified invoice data from mobile app client over Company LAN.
    Validates input and saves invoice, items, sync log, and audit log atomically.
    Idempotent: Duplicate submissions with the same local_invoice_id return ALREADY_SYNCED.
    """
    return InvoiceSyncService.sync_invoice(db, payload)
