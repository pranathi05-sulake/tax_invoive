import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, Text
from app.database import Base

def generate_uuid() -> str:
    return str(uuid.uuid4())

class SyncLog(Base):
    __tablename__ = "sync_log"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    local_invoice_id = Column(String(64), nullable=False, index=True)
    server_invoice_id = Column(String(36), nullable=True)
    sync_status = Column(String(32), nullable=False)
    attempted_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    completed_at = Column(DateTime, nullable=True)
    error_code = Column(String(64), nullable=True)
    error_message = Column(Text, nullable=True)
