import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, Text
from app.database import Base

def generate_uuid() -> str:
    return str(uuid.uuid4())

class AuditLog(Base):
    __tablename__ = "audit_log"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    event_type = Column(String(64), nullable=False)
    user_identifier = Column(String(64), nullable=False)
    invoice_id = Column(String(36), nullable=True)
    timestamp = Column(DateTime, nullable=False, default=datetime.utcnow)
    details = Column(Text, nullable=True)
