import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.config import settings
from app.database import engine, Base
from app.routers import health_router, invoices_router

# Configure Application Logger
logging.basicConfig(
    level=getattr(logging, settings.LOG_LEVEL.upper(), logging.INFO),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("tax_invoice_backend")

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting TaxInvoice AI Company LAN Backend Server...")
    if engine is not None:
        try:
            Base.metadata.create_all(bind=engine)
            logger.info("Database tables verified/created successfully.")
        except Exception as e:
            logger.warning(f"Startup table auto-creation skipped or failed: {e}")
    yield

app = FastAPI(
    title="TaxInvoice AI — Company LAN Backend",
    description="Internal Helicopter Division LAN Backend for Invoice Verification & Central Storage.",
    version="1.0.0",
    docs_url="/docs" if settings.ENVIRONMENT == "development" else None,
    redoc_url="/redoc" if settings.ENVIRONMENT == "development" else None,
    lifespan=lifespan,
)

# CORS Configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

# Include API Routers
app.include_router(health_router)
app.include_router(invoices_router)

# Custom Validation Exception Handler (Sanitizes validation error format)
@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    logger.warning(f"Validation error on {request.method} {request.url.path}: {exc.errors()}")
    # Format simplified error message for client without stack trace
    first_err = exc.errors()[0] if exc.errors() else {}
    msg = first_err.get("msg", "Invalid request body or parameters.")
    loc = " -> ".join([str(l) for l in first_err.get("loc", []) if l != "body"])
    detail_msg = f"{loc}: {msg}" if loc else msg
    
    return JSONResponse(
        status_code=status.HTTP_400_BAD_REQUEST,
        content={
            "status_code": 400,
            "error_code": "VALIDATION_ERROR",
            "message": detail_msg,
        },
    )

# General Exception Handler (Hides internal stack traces from clients)
@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled exception on {request.method} {request.url.path}: {exc}", exc_info=False)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "status_code": 500,
            "error_code": "INTERNAL_SERVER_ERROR",
            "message": "An internal server error occurred while processing the request.",
        },
    )


