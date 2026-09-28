from fastapi import APIRouter, status
from fastapi.responses import JSONResponse
from app.database import check_database_health

router = APIRouter(tags=["Health Check"])

@router.get("/health", summary="Health check endpoint for company LAN server & MySQL database")
def health_check():
    db_connected = check_database_health()
    if db_connected:
        return {
            "status": "ok",
            "database": "connected"
        }
    else:
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "status": "degraded",
                "database": "disconnected"
            }
        )
