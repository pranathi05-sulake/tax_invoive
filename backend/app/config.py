import os
from typing import List
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    # Server configuration
    BACKEND_HOST: str = "0.0.0.0"
    BACKEND_PORT: int = 8000
    ENVIRONMENT: str = "development"
    LOG_LEVEL: str = "INFO"

    # Company LAN MySQL Database Credentials
    MYSQL_HOST: str = "127.0.0.1"
    MYSQL_PORT: int = 3306
    MYSQL_DATABASE: str = "tax_invoice_db"
    MYSQL_USER: str = "tax_admin"
    MYSQL_PASSWORD: str = "SecureLanPassword123!"

    # Database Connection Pool Settings
    DB_POOL_SIZE: int = 10
    DB_MAX_OVERFLOW: int = 20
    DB_POOL_TIMEOUT: int = 30
    DB_POOL_RECYCLE: int = 1800

    # CORS Allowed Origins
    CORS_ORIGINS: str = "http://localhost:8080,http://127.0.0.1:8080,http://localhost:8000,http://127.0.0.1:8000"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )

    @property
    def database_url(self) -> str:
        """Constructs MySQL SQLAlchemy connection string safely with URL-encoded credentials."""
        from urllib.parse import quote_plus
        user = quote_plus(self.MYSQL_USER)
        password = quote_plus(self.MYSQL_PASSWORD)
        return (
            f"mysql+pymysql://{user}:{password}"
            f"@{self.MYSQL_HOST}:{self.MYSQL_PORT}/{self.MYSQL_DATABASE}"
        )

    @property
    def safe_database_url(self) -> str:
        """Returns database connection string with password masked for safe logging."""
        return (
            f"mysql+pymysql://{self.MYSQL_USER}:[MASKED]"
            f"@{self.MYSQL_HOST}:{self.MYSQL_PORT}/{self.MYSQL_DATABASE}"
        )

    @property
    def cors_origins_list(self) -> List[str]:
        """Parses comma-separated CORS origins for FastAPI middleware."""
        default_origins = [
            "http://localhost:8080",
            "http://127.0.0.1:8080",
            "http://localhost:8000",
            "http://127.0.0.1:8000",
        ]
        if not self.CORS_ORIGINS or self.CORS_ORIGINS.strip() == "*":
            return default_origins
        origins = [origin.strip() for origin in self.CORS_ORIGINS.split(",") if origin.strip() and origin.strip() != "*"]
        return origins if origins else default_origins

settings = Settings()
