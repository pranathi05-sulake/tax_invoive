import logging
from datetime import datetime
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from fastapi import HTTPException, status

from app.models.invoice import VerifiedInvoice, InvoiceItem
from app.models.sync_log import SyncLog
from app.models.audit_log import AuditLog
from app.schemas.invoice import InvoiceSyncCreate
from app.schemas.sync import SyncResponse

logger = logging.getLogger("tax_invoice_backend")

class InvoiceSyncService:
    @staticmethod
    def sync_invoice(db: Session, payload: InvoiceSyncCreate) -> SyncResponse:
        """
        Synchronizes a verified invoice idempotently within a single SQL transaction.
        """
        # 1. Idempotency Check: Existing local_invoice_id check
        existing = db.query(VerifiedInvoice).filter(
            VerifiedInvoice.local_invoice_id == payload.local_invoice_id
        ).first()

        if existing:
            logger.info(f"Duplicate sync attempt for local_invoice_id: {payload.local_invoice_id}. Returning ALREADY_SYNCED.")
            
            # Log idempotency event to sync_log
            try:
                already_log = SyncLog(
                    local_invoice_id=payload.local_invoice_id,
                    server_invoice_id=existing.id,
                    sync_status="ALREADY_SYNCED",
                    attempted_at=datetime.utcnow(),
                    completed_at=datetime.utcnow(),
                )
                db.add(already_log)
                db.commit()
            except Exception as log_err:
                db.rollback()
                logger.warning(f"Could not record ALREADY_SYNCED in sync_log: {log_err}")

            return SyncResponse(
                status="ALREADY_SYNCED",
                server_invoice_id=existing.id,
                local_invoice_id=existing.local_invoice_id,
            )

        # 2. Begin Transactional Save for New Verified Invoice
        try:
            new_invoice = VerifiedInvoice(
                local_invoice_id=payload.local_invoice_id,
                invoice_number=payload.invoice_number,
                invoice_date=payload.invoice_date,
                vendor_name=payload.vendor_name,
                gstin=payload.gstin,
                taxable_value=payload.taxable_value,
                cgst=payload.cgst,
                sgst=payload.sgst,
                igst=payload.igst,
                total_amount=payload.total_amount,
                verification_status=payload.verification_status,
                verified_by=payload.verified_by,
                verified_at=payload.verified_at,
            )
            db.add(new_invoice)
            db.flush()  # Generates new_invoice.id for foreign key relationship

            # Insert Invoice Items
            for item in payload.invoice_items:
                db_item = InvoiceItem(
                    invoice_id=new_invoice.id,
                    hsn_sac=item.hsn_sac,
                    description=item.description,
                    quantity=item.quantity,
                    unit_price=item.unit_price,
                    taxable_value=item.taxable_value,
                    cgst=item.cgst,
                    sgst=item.sgst,
                    igst=item.igst,
                    total_amount=item.total_amount,
                )
                db.add(db_item)

            # Insert Sync Log
            sync_log_entry = SyncLog(
                local_invoice_id=payload.local_invoice_id,
                server_invoice_id=new_invoice.id,
                sync_status="SYNCED",
                attempted_at=datetime.utcnow(),
                completed_at=datetime.utcnow(),
            )
            db.add(sync_log_entry)

            # Insert Audit Log
            audit_entry = AuditLog(
                event_type="INVOICE_SYNCED",
                user_identifier=payload.verified_by,
                invoice_id=new_invoice.id,
                timestamp=datetime.utcnow(),
                details=f"Verified invoice synced from local ID {payload.local_invoice_id}",
            )
            db.add(audit_entry)

            # Commit entire atomic transaction
            db.commit()

            logger.info(f"Successfully synced invoice local_id: {payload.local_invoice_id} -> server_id: {new_invoice.id}")

            return SyncResponse(
                status="SYNCED",
                server_invoice_id=new_invoice.id,
                local_invoice_id=new_invoice.local_invoice_id,
            )

        except IntegrityError as ie:
            db.rollback()
            logger.warning(f"IntegrityError during invoice sync: {ie}")
            
            # Re-check if race condition caused local_invoice_id duplicate
            existing_after_race = db.query(VerifiedInvoice).filter(
                VerifiedInvoice.local_invoice_id == payload.local_invoice_id
            ).first()
            if existing_after_race:
                return SyncResponse(
                    status="ALREADY_SYNCED",
                    server_invoice_id=existing_after_race.id,
                    local_invoice_id=existing_after_race.local_invoice_id,
                )

            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Database integrity constraint violation during invoice synchronization.",
            )
        except Exception as e:
            db.rollback()
            logger.error(f"Unexpected error during invoice transaction rollback: {e}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to process invoice synchronization due to a server transaction error.",
            )
