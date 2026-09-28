"""initial_schema

Revision ID: 001_initial_schema
Revises: 
Create Date: 2026-09-28 00:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = '001_initial_schema'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

def upgrade() -> None:
    # 1. verified_invoices
    op.create_table(
        'verified_invoices',
        sa.Column('id', sa.String(length=36), nullable=False),
        sa.Column('local_invoice_id', sa.String(length=64), nullable=False),
        sa.Column('invoice_number', sa.String(length=64), nullable=False),
        sa.Column('invoice_date', sa.Date(), nullable=False),
        sa.Column('vendor_name', sa.String(length=255), nullable=False),
        sa.Column('gstin', sa.String(length=15), nullable=False),
        sa.Column('taxable_value', sa.Numeric(precision=15, scale=2), nullable=False),
        sa.Column('cgst', sa.Numeric(precision=15, scale=2), nullable=False, server_default='0.00'),
        sa.Column('sgst', sa.Numeric(precision=15, scale=2), nullable=False, server_default='0.00'),
        sa.Column('igst', sa.Numeric(precision=15, scale=2), nullable=False, server_default='0.00'),
        sa.Column('total_amount', sa.Numeric(precision=15, scale=2), nullable=False),
        sa.Column('verification_status', sa.String(length=16), nullable=False),
        sa.Column('verified_by', sa.String(length=64), nullable=False),
        sa.Column('verified_at', sa.DateTime(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('local_invoice_id')
    )
    op.create_index('idx_local_invoice_id', 'verified_invoices', ['local_invoice_id'])
    op.create_index('idx_gstin_invnum', 'verified_invoices', ['gstin', 'invoice_number'])
    op.create_index('idx_invoice_date', 'verified_invoices', ['invoice_date'])

    # 2. invoice_items
    op.create_table(
        'invoice_items',
        sa.Column('id', sa.String(length=36), nullable=False),
        sa.Column('invoice_id', sa.String(length=36), nullable=False),
        sa.Column('hsn_sac', sa.String(length=32), nullable=True),
        sa.Column('description', sa.String(length=255), nullable=False),
        sa.Column('quantity', sa.Numeric(precision=12, scale=3), nullable=False, server_default='1.000'),
        sa.Column('unit_price', sa.Numeric(precision=15, scale=2), nullable=False, server_default='0.00'),
        sa.Column('taxable_value', sa.Numeric(precision=15, scale=2), nullable=False),
        sa.Column('cgst', sa.Numeric(precision=15, scale=2), nullable=False, server_default='0.00'),
        sa.Column('sgst', sa.Numeric(precision=15, scale=2), nullable=False, server_default='0.00'),
        sa.Column('igst', sa.Numeric(precision=15, scale=2), nullable=False, server_default='0.00'),
        sa.Column('total_amount', sa.Numeric(precision=15, scale=2), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.ForeignKeyConstraint(['invoice_id'], ['verified_invoices.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index('idx_items_invoice_id', 'invoice_items', ['invoice_id'])

    # 3. sync_log
    op.create_table(
        'sync_log',
        sa.Column('id', sa.String(length=36), nullable=False),
        sa.Column('local_invoice_id', sa.String(length=64), nullable=False),
        sa.Column('server_invoice_id', sa.String(length=36), nullable=True),
        sa.Column('sync_status', sa.String(length=32), nullable=False),
        sa.Column('attempted_at', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('completed_at', sa.DateTime(), nullable=True),
        sa.Column('error_code', sa.String(length=64), nullable=True),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index('idx_synclog_local_id', 'sync_log', ['local_invoice_id'])

    # 4. audit_log
    op.create_table(
        'audit_log',
        sa.Column('id', sa.String(length=36), nullable=False),
        sa.Column('event_type', sa.String(length=64), nullable=False),
        sa.Column('user_identifier', sa.String(length=64), nullable=False),
        sa.Column('invoice_id', sa.String(length=36), nullable=True),
        sa.Column('timestamp', sa.DateTime(), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('details', sa.Text(), nullable=True),
        sa.PrimaryKeyConstraint('id')
    )

def downgrade() -> None:
    op.drop_table('audit_log')
    op.drop_table('sync_log')
    op.drop_table('invoice_items')
    op.drop_table('verified_invoices')
