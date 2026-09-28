import logging
from typing import Generator
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, declarative_base, Session
from app.config import settings

logger = logging.getLogger("tax_invoice_backend")

# Create SQLAlchemy MySQL Engine with pooling & pre-ping health checks
try:
    engine = create_engine(
        settings.database_url,
        pool_size=settings.DB_POOL_SIZE,
        max_overflow=settings.DB_MAX_OVERFLOW,
        pool_timeout=settings.DB_POOL_TIMEOUT,
        pool_recycle=settings.DB_POOL_RECYCLE,
        pool_pre_ping=True,  # Health check before handing connection out
        echo=False,          # Disable raw SQL log dumping to prevent password/data leaks
    )
    logger.info(f"Initialized MySQL SQLAlchemy Engine for {settings.safe_database_url}")
except Exception as e:
    logger.error("Failed to initialize database engine (credentials masked for security).")
    engine = None

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine) if engine else None
Base = declarative_base()

def get_db() -> Generator[Session, None, None]:
    """Provides a transactional database session per HTTP request lifecycle."""
    if SessionLocal is None:
        raise RuntimeError("Database engine is not initialized.")
    db = SessionLocal()
    try:
        yield db
    except Exception as e:
        db.rollback()
        raise
    finally:
        db.close()

def check_database_health() -> bool:
    """Performs a lightweight ping query (SELECT 1) to test MySQL connectivity."""
    if engine is None:
        return False
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1;"))
        return True
    except Exception as e:
        logger.warning("MySQL Database health check ping failed.")
        return False
