import os
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Set test environment
os.environ["ENVIRONMENT"] = "testing"
os.environ["MYSQL_DATABASE"] = "tax_invoice_test_db"

from app.config import settings
from app.database import Base, get_db
from app.main import app

# Create in-memory or file-based SQLite database for unit test runner if MySQL is unavailable
TEST_DATABASE_URL = os.getenv("TEST_DATABASE_URL", "sqlite:///./test_backend.db")

test_engine = create_engine(
    TEST_DATABASE_URL,
    connect_args={"check_same_thread": False} if "sqlite" in TEST_DATABASE_URL else {}
)

TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=test_engine)

@pytest.fixture(scope="session", autouse=True)
def setup_test_database():
    """Create all test database tables before test suite and drop after."""
    Base.metadata.create_all(bind=test_engine)
    yield
    Base.metadata.drop_all(bind=test_engine)
    if os.path.exists("./test_backend.db"):
        try:
            os.remove("./test_backend.db")
        except Exception:
            pass

@pytest.fixture(scope="function")
def db_session():
    """Provides a clean transactional session for each test function."""
    connection = test_engine.connect()
    transaction = connection.begin()
    session = TestingSessionLocal(bind=connection)

    yield session

    session.close()
    transaction.rollback()
    connection.close()

@pytest.fixture(scope="function")
def client(db_session):
    """FastAPI TestClient with overridden get_db dependency."""
    def override_get_db():
        try:
            yield db_session
        finally:
            pass

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
