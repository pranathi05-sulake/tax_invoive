import uuid
from datetime import datetime, date
from sqlalchemy import Column, String, Date, DateTime, Numeric, ForeignKey, Index
from sqlalchemy.orm import relationship
from app.database import Base

def generate_uuid() -> str:
    return str(uuid.uuid4())

class VerifiedInvoice(Base):
    __tablename__ = "verified_invoices"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    local_invoice_id = Column(String(64), unique=True, nullable=False, index=True)
    invoice_number = Column(String(64), nullable=False)
    invoice_date = Column(Date, nullable=False)
    vendor_name = Column(String(255), nullable=False)
    gstin = Column(String(15), nullable=False)
    
    # Financial fields must strictly use DECIMAL(15, 2)
    taxable_value = Column(Numeric(15, 2), nullable=False)
    cgst = Column(Numeric(15, 2), nullable=False, default=0.00)
    sgst = Column(Numeric(15, 2), nullable=False, default=0.00)
    igst = Column(Numeric(15, 2), nullable=False, default=0.00)
    total_amount = Column(Numeric(15, 2), nullable=False)
    
    verification_status = Column(String(16), nullable=False)
    verified_by = Column(String(64), nullable=False)
    verified_at = Column(DateTime, nullable=False)
    
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    items = relationship("InvoiceItem", back_populates="invoice", cascade="all, delete-orphan")

    __table_args__ = (
        Index("idx_gstin_invnum", "gstin", "invoice_number"),
        Index("idx_invoice_date", "invoice_date"),
    )

class InvoiceItem(Base):
    __tablename__ = "invoice_items"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    invoice_id = Column(String(36), ForeignKey("verified_invoices.id", ondelete="CASCADE"), nullable=False, index=True)
    hsn_sac = Column(String(32), nullable=True)
    description = Column(String(255), nullable=False)
    
    quantity = Column(Numeric(12, 3), nullable=False, default=1.000)
    unit_price = Column(Numeric(15, 2), nullable=False, default=0.00)
    taxable_value = Column(Numeric(15, 2), nullable=False)
    cgst = Column(Numeric(15, 2), nullable=False, default=0.00)
    sgst = Column(Numeric(15, 2), nullable=False, default=0.00)
    igst = Column(Numeric(15, 2), nullable=False, default=0.00)
    total_amount = Column(Numeric(15, 2), nullable=False)
    
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    invoice = relationship("VerifiedInvoice", back_populates="items")
