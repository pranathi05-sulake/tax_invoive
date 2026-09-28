from datetime import date, datetime
from decimal import Decimal
from enum import Enum
from typing import List, Optional
from pydantic import BaseModel, Field, field_validator, model_validator

class VerificationStatusEnum(str, Enum):
    VERIFIED = "VERIFIED"
    REJECTED = "REJECTED"

class InvoiceItemCreate(BaseModel):
    hsn_sac: Optional[str] = Field(default=None, max_length=32)
    description: str = Field(..., min_length=1, max_length=255)
    quantity: Decimal = Field(default=Decimal("1.000"), gt=Decimal("0"))
    unit_price: Decimal = Field(default=Decimal("0.00"), ge=Decimal("0"))
    taxable_value: Decimal = Field(..., ge=Decimal("0"))
    cgst: Decimal = Field(default=Decimal("0.00"), ge=Decimal("0"))
    sgst: Decimal = Field(default=Decimal("0.00"), ge=Decimal("0"))
    igst: Decimal = Field(default=Decimal("0.00"), ge=Decimal("0"))
    total_amount: Decimal = Field(..., ge=Decimal("0"))

    @field_validator("quantity", "unit_price", "taxable_value", "cgst", "sgst", "igst", "total_amount", mode="before")
    @classmethod
    def parse_decimals(cls, value):
        if value is None:
            return Decimal("0.00")
        return Decimal(str(value))

class InvoiceSyncCreate(BaseModel):
    local_invoice_id: str = Field(..., min_length=1, max_length=64)
    invoice_number: str = Field(..., min_length=1, max_length=64)
    invoice_date: date
    vendor_name: str = Field(..., min_length=1, max_length=255)
    gstin: str = Field(..., min_length=15, max_length=15)
    
    taxable_value: Decimal = Field(..., ge=Decimal("0"))
    cgst: Decimal = Field(default=Decimal("0.00"), ge=Decimal("0"))
    sgst: Decimal = Field(default=Decimal("0.00"), ge=Decimal("0"))
    igst: Decimal = Field(default=Decimal("0.00"), ge=Decimal("0"))
    total_amount: Decimal = Field(..., ge=Decimal("0"))
    
    verification_status: str = Field(...)
    verified_by: str = Field(..., min_length=1, max_length=64)
    verified_at: datetime
    
    invoice_items: List[InvoiceItemCreate] = Field(..., min_length=1)

    @field_validator("taxable_value", "cgst", "sgst", "igst", "total_amount", mode="before")
    @classmethod
    def parse_decimals(cls, value):
        if value is None:
            return Decimal("0.00")
        return Decimal(str(value))

    @field_validator("verification_status")
    @classmethod
    def validate_status(cls, value: str) -> str:
        clean = value.strip().upper()
        if clean != "VERIFIED":
            raise ValueError("Only invoices with status 'VERIFIED' are accepted for backend synchronization.")
        return clean

    @field_validator("gstin")
    @classmethod
    def validate_gstin_format(cls, value: str) -> str:
        clean = value.strip().upper()
        if len(clean) != 15:
            raise ValueError("GSTIN must be exactly 15 characters long.")
        return clean
