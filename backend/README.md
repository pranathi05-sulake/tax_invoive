# TaxInvoice AI — Company LAN Backend Foundation (Phase 1)

> **Important Architecture & LAN Notice:**
> **Internet access is not required. The backend is intended to communicate with clients over the company LAN.**
> 
> The mobile Flutter app operates completely offline for OCR, parsing, local SQLCipher storage, RPA, and verification. Verified invoices are transmitted strictly over the internal Company LAN to this FastAPI backend server, which stores central records in the company MySQL database.
>
> **Flutter App → Company LAN → FastAPI Backend → MySQL Database**

---

## 1. Overview & Architecture

This backend serves as the central server repository for the Helicopter Division's TaxInvoice AI application.

### Key Features:
- **Offline-First Integration**: Designed to receive verified tax invoice payloads over the company's local area network (LAN).
- **Idempotency & Duplicate Protection**: Built-in `local_invoice_id` unique constraints and transactional logic prevent double-entry even if mobile clients retry network connections.
- **Strict Data Integrity**: Financial fields use `DECIMAL(15, 2)` (never floating-point numbers) for exact tax calculations.
- **Server-Side Status Guards**: Accepts invoice records for central storage only when the verification status is explicitly `VERIFIED`.
- **Security & Privacy**: No passwords, tokens, or encryption keys are logged or returned. Database credentials are read from environment variables and masked in application logs.

---

## 2. Prerequisites & System Requirements

- **Python Version**: Python `3.10` or higher (Tested on `3.10.11`)
- **MySQL Database**: MySQL Server `8.0` or MariaDB `10.5+` running on the company LAN server.
- **Pip & Virtualenv**: `pip` package manager.

---

## 3. Installation & Setup

### Step 1: Create a Python Virtual Environment
Navigate to the `backend/` directory:
```bash
cd backend
python -m venv venv
```

Activate the virtual environment:
- **Windows (PowerShell)**:
  ```powershell
  .\venv\Scripts\Activate.ps1
  ```
- **Linux / macOS**:
  ```bash
  source venv/bin/activate
  ```

### Step 2: Install Required Dependencies
```bash
pip install -r requirements.txt
```

---

## 4. Environment Configuration

Copy `.env.example` to `.env`:
```bash
cp .env.example .env
```

Edit `.env` with your company LAN MySQL database credentials:

```ini
# FastAPI Server Settings
BACKEND_HOST=0.0.0.0
BACKEND_PORT=8000
ENVIRONMENT=development
LOG_LEVEL=INFO

# Company LAN MySQL Database Credentials
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306
MYSQL_DATABASE=tax_invoice_db
MYSQL_USER=tax_admin
MYSQL_PASSWORD=YourSecureLanPasswordHere!

# Connection Pool Settings
DB_POOL_SIZE=10
DB_MAX_OVERFLOW=20
DB_POOL_TIMEOUT=30
DB_POOL_RECYCLE=1800

# CORS Configuration (LAN Origins)
CORS_ORIGINS=http://localhost:8000,http://127.0.0.1:8000
```

*Note: Never commit `.env` to version control.*

---

## 5. MySQL Database Setup & Migrations

### Step 1: Create Database & User in MySQL
Log into MySQL Server on the LAN host and create the database:
```sql
CREATE DATABASE tax_invoice_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'tax_admin'@'%' IDENTIFIED BY 'YourSecureLanPasswordHere!';
GRANT ALL PRIVILEGES ON tax_invoice_db.* TO 'tax_admin'@'%';
FLUSH PRIVILEGES;
```

### Step 2: Run Alembic Database Migrations
Apply database schema migrations using Alembic:
```bash
alembic upgrade head
```

This creates the following tables:
1. `verified_invoices` (Central verified invoices with `DECIMAL` financial fields and `local_invoice_id` UNIQUE index)
2. `invoice_items` (Line items linked to `verified_invoices.id` via foreign key cascade)
3. `sync_log` (Idempotency and synchronization history log)
4. `audit_log` (Security and operation audit events)

---

## 6. Running the FastAPI Server

Start the Uvicorn ASGI server bound to all LAN network interfaces (`0.0.0.0`):

```bash
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

---

## 7. Verifying Company LAN Accessibility

### Check Local Health Endpoint:
```bash
curl http://localhost:8000/health
```

Expected Response:
```json
{
  "status": "ok",
  "database": "connected"
}
```

### Check Access from another LAN Device:
Find the host server's local LAN IP address (e.g. `192.168.1.150`):
```bash
# Windows:
ipconfig
# Linux/macOS:
ifconfig
```
From mobile client or secondary PC on the same LAN:
```bash
curl http://192.168.1.150:8000/health
```

---

## 8. API Endpoint Reference

### 1. `GET /health`
- **Purpose**: Health check for server and MySQL database connection ping.
- **Response (200 OK)**:
  ```json
  {
    "status": "ok",
    "database": "connected"
  }
  ```

### 2. `POST /api/v1/invoices`
- **Purpose**: Synchronize a verified invoice from a mobile client over LAN.
- **Request Headers**: `Content-Type: application/json`
- **Example Request Body**:
  ```json
  {
    "local_invoice_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
    "invoice_number": "INV-2026-0042",
    "invoice_date": "2026-03-25",
    "vendor_name": "Helicopter Components Pvt Ltd",
    "gstin": "29AAACB1234C1Z5",
    "taxable_value": 10000.50,
    "cgst": 900.04,
    "sgst": 900.04,
    "igst": 0.00,
    "total_amount": 11800.58,
    "verification_status": "VERIFIED",
    "verified_by": "admin_user",
    "verified_at": "2026-03-25T14:30:00Z",
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
        "total_amount": 11800.58
      }
    ]
  }
  ```
- **Response (200 OK - First Sync)**:
  ```json
  {
    "status": "SYNCED",
    "server_invoice_id": "e4a2c1b8-7f91-4d32-8a10-9b62e457f921",
    "local_invoice_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"
  }
  ```
- **Response (200 OK - Network Retry / Duplicate Submission)**:
  ```json
  {
    "status": "ALREADY_SYNCED",
    "server_invoice_id": "e4a2c1b8-7f91-4d32-8a10-9b62e457f921",
    "local_invoice_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"
  }
  ```

---

## 9. Running Tests

Run the Pytest suite from the `backend/` directory:

```bash
pytest -v
```

This runs unit and integration tests covering:
1. Database health.
2. Valid verified invoice insertion.
3. Invalid verification status rejection.
4. Missing required field rejection.
5. Duplicate `local_invoice_id` idempotency protection.
6. Multi-item invoice processing.
7. Transaction rollback on failure.
8. Exact `DECIMAL` financial precision.
9. `sync_log` and `audit_log` creation.
10. Log secret masking verification.
