import uuid
import logging
from decimal import Decimal
import pytest
from app.models import VerifiedInvoice, InvoiceItem, SyncLog, AuditLog

def make_sample_payload(local_id: str = None, status: str = "VERIFIED"):
    if not local_id:
        local_id = str(uuid.uuid4())
    return {
        "local_invoice_id": local_id,
        "invoice_number": "INV-2026-888",
        "invoice_date": "2026-03-25",
        "vendor_name": "Helicopter Components Pvt Ltd",
        "gstin": "29AAACB1234C1Z5",
        "taxable_value": 10000.50,
        "cgst": 900.04,
        "sgst": 900.04,
        "igst": 0.00,
        "total_amount": 11800.58,
        "verification_status": status,
        "verified_by": "admin_user",
        "verified_at": "2026-03-25T14:30:00",
        "invoice_items": [
            {
                "hsn_sac": "88033000",
                "description": "Rotor Blade Assembly Bushing",
                "quantity": 2.000,
                "unit_price": 5000.25,
                "taxable_value": 10000.50,
                "cgst": 900.04,
                "sgst": 900.04,
                "igst": 0.00,
                "total_amount": 11800.58,
            }
        ]
    }

def test_valid_verified_invoice_insertion(client, db_session):
    """Scenario 2: Valid verified invoice insertion."""
    payload = make_sample_payload()
    response = client.post("/api/v1/invoices", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "SYNCED"
    assert data["local_invoice_id"] == payload["local_invoice_id"]
    assert "server_invoice_id" in data

    # Verify database persistence
    db_inv = db_session.query(VerifiedInvoice).filter(
        VerifiedInvoice.local_invoice_id == payload["local_invoice_id"]
    ).first()
    assert db_inv is not None
    assert db_inv.vendor_name == "Helicopter Components Pvt Ltd"
    assert db_inv.verification_status == "VERIFIED"

def test_invalid_verification_status_rejected(client):
    """Scenario 3: Invalid verification status rejected (only VERIFIED accepted)."""
    payload = make_sample_payload(status="PENDING")
    response = client.post("/api/v1/invoices", json=payload)
    assert response.status_code == 400
    data = response.json()
    assert data["error_code"] == "VALIDATION_ERROR"
    assert "VERIFIED" in data["message"]

def test_missing_required_field_rejected(client):
    """Scenario 4: Missing required field rejected."""
    payload = make_sample_payload()
    del payload["invoice_number"]
    response = client.post("/api/v1/invoices", json=payload)
    assert response.status_code == 400
    data = response.json()
    assert data["error_code"] == "VALIDATION_ERROR"

def test_duplicate_local_invoice_id_idempotency(client, db_session):
    """Scenario 5: Duplicate local_invoice_id handled safely with ALREADY_SYNCED."""
    payload = make_sample_payload()
    
    # First sync call
    res1 = client.post("/api/v1/invoices", json=payload)
    assert res1.status_code == 200
    data1 = res1.json()
    assert data1["status"] == "SYNCED"
    server_id = data1["server_invoice_id"]

    # Second sync call with exact same local_invoice_id
    res2 = client.post("/api/v1/invoices", json=payload)
    assert res2.status_code == 200
    data2 = res2.json()
    assert data2["status"] == "ALREADY_SYNCED"
    assert data2["server_invoice_id"] == server_id
    assert data2["local_invoice_id"] == payload["local_invoice_id"]

    # Verify only ONE invoice record exists in database
    count = db_session.query(VerifiedInvoice).filter(
        VerifiedInvoice.local_invoice_id == payload["local_invoice_id"]
    ).count()
    assert count == 1

def test_invoice_with_multiple_items(client, db_session):
    """Scenario 6: Invoice with multiple invoice_items."""
    payload = make_sample_payload()
    payload["invoice_items"] = [
        {
            "hsn_sac": "88031000",
            "description": "Main Rotor Blade Tip",
            "quantity": 1.000,
            "unit_price": 6000.00,
            "taxable_value": 6000.00,
            "cgst": 540.00,
            "sgst": 540.00,
            "igst": 0.00,
            "total_amount": 7080.00,
        },
        {
            "hsn_sac": "88032000",
            "description": "Tail Rotor Hub Pin",
            "quantity": 4.000,
            "unit_price": 1000.00,
            "taxable_value": 4000.00,
            "cgst": 360.00,
            "sgst": 360.00,
            "igst": 0.00,
            "total_amount": 4720.00,
        }
    ]
    
    res = client.post("/api/v1/invoices", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "SYNCED"

    items = db_session.query(InvoiceItem).filter(
        InvoiceItem.invoice_id == data["server_invoice_id"]
    ).all()
    assert len(items) == 2
    descriptions = [item.description for item in items]
    assert "Main Rotor Blade Tip" in descriptions
    assert "Tail Rotor Hub Pin" in descriptions

def test_decimal_financial_values_preserved(client, db_session):
    """Scenario 8: Decimal financial values preserved accurately."""
    payload = make_sample_payload()
    payload["taxable_value"] = 1234567.89
    payload["cgst"] = 111111.11
    payload["sgst"] = 111111.11
    payload["total_amount"] = 1456790.11

    res = client.post("/api/v1/invoices", json=payload)
    assert res.status_code == 200
    server_id = res.json()["server_invoice_id"]

    inv = db_session.query(VerifiedInvoice).filter(VerifiedInvoice.id == server_id).first()
    assert Decimal(str(inv.taxable_value)) == Decimal("1234567.89")
    assert Decimal(str(inv.total_amount)) == Decimal("1456790.11")

def test_sync_log_creation(client, db_session):
    """Scenario 9: sync_log creation."""
    payload = make_sample_payload()
    res = client.post("/api/v1/invoices", json=payload)
    assert res.status_code == 200

    sync_logs = db_session.query(SyncLog).filter(
        SyncLog.local_invoice_id == payload["local_invoice_id"]
    ).all()
    assert len(sync_logs) >= 1
    assert sync_logs[0].sync_status == "SYNCED"

def test_audit_log_creation(client, db_session):
    """Audit log creation during sync."""
    payload = make_sample_payload()
    res = client.post("/api/v1/invoices", json=payload)
    assert res.status_code == 200

    server_id = res.json()["server_invoice_id"]
    audit_entries = db_session.query(AuditLog).filter(
        AuditLog.invoice_id == server_id
    ).all()
    assert len(audit_entries) >= 1
    assert audit_entries[0].event_type == "INVOICE_SYNCED"
    assert audit_entries[0].user_identifier == payload["verified_by"]

def test_no_sensitive_credentials_in_application_logs(caplog):
    """Scenario 10: Verify no DB passwords or secrets leak into log output."""
    from app.config import settings
    logger = logging.getLogger("tax_invoice_backend")
    
    with caplog.at_level(logging.INFO):
        logger.info(f"Connecting to database at {settings.safe_database_url}")
    
    log_text = caplog.text
    assert settings.MYSQL_PASSWORD not in log_text
    assert "[MASKED]" in log_text
