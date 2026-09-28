from pydantic import BaseModel, Field

class SyncResponse(BaseModel):
    status: str = Field(..., description="SYNCED or ALREADY_SYNCED")
    server_invoice_id: str = Field(..., description="UUID of server invoice record")
    local_invoice_id: str = Field(..., description="UUID of mobile client invoice record")

class ErrorResponse(BaseModel):
    status_code: int
    error_code: str
    message: str
