import 'package:flutter/material.dart';
import '../models/invoice.dart';

class InvoiceListTile extends StatelessWidget {
  final Invoice invoice;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const InvoiceListTile({
    super.key,
    required this.invoice,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusConfig = _getStatusConfig(invoice.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.0),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16.0),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                // Vendor Avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    invoice.vendorName.isNotEmpty
                        ? invoice.vendorName.substring(0, 1).toUpperCase()
                        : '?',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF334155),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Vendor and Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        invoice.vendorName.isNotEmpty ? invoice.vendorName : 'Unknown Vendor',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            flex: 2,
                            child: Text(
                              invoice.invoiceNumber.isNotEmpty ? invoice.invoiceNumber : 'No Inv #',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 5.0),
                            child: Text(
                              '•',
                              style: TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 10,
                              ),
                            ),
                          ),
                          Flexible(
                            flex: 2,
                            child: Text(
                              invoice.formattedDate,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: const Color(0xFF94A3B8),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Amount & Status Badge
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      invoice.formattedTotal,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6.0,
                            vertical: 2.0,
                          ),
                          decoration: BoxDecoration(
                            color: statusConfig.backgroundColor,
                            borderRadius: BorderRadius.circular(6.0),
                          ),
                          child: Text(
                            statusConfig.label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: statusConfig.textColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 10.0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _buildSyncBadge(context, invoice.syncStatus),
                      ],
                    ),
                  ],
                ),

                // Delete Icon button if onDelete provided
                if (onDelete != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFF94A3B8)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    splashRadius: 20,
                    tooltip: 'Delete Invoice',
                    onPressed: onDelete,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSyncBadge(BuildContext context, SyncStatus status) {
    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (status) {
      case SyncStatus.synced:
        bg = const Color(0xFFF0FDF4);
        fg = const Color(0xFF166534);
        icon = Icons.cloud_done_rounded;
        label = 'Synced';
        break;
      case SyncStatus.syncing:
        bg = const Color(0xFFEFF6FF);
        fg = const Color(0xFF1D4ED8);
        icon = Icons.sync_rounded;
        label = 'Syncing';
        break;
      case SyncStatus.syncFailed:
        bg = const Color(0xFFFEF2F2);
        fg = const Color(0xFF991B1B);
        icon = Icons.cloud_off_rounded;
        label = 'Sync Failed';
        break;
      case SyncStatus.pendingSync:
        bg = const Color(0xFFFFFBEB);
        fg = const Color(0xFFB45309);
        icon = Icons.cloud_upload_outlined;
        label = 'Pending Sync';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: fg),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 9.5,
            ),
          ),
        ],
      ),
    );
  }

  _StatusConfig _getStatusConfig(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.verified:
        return const _StatusConfig(
          label: 'Verified',
          backgroundColor: Color(0xFFECFDF5),
          textColor: Color(0xFF059669),
        );
      case InvoiceStatus.pending:
        return const _StatusConfig(
          label: 'Pending',
          backgroundColor: Color(0xFFFFFBEB),
          textColor: Color(0xFFD97706),
        );
      case InvoiceStatus.flagged:
        return const _StatusConfig(
          label: 'Review',
          backgroundColor: Color(0xFFFEF2F2),
          textColor: Color(0xFFDC2626),
        );
    }
  }
}

class _StatusConfig {
  final String label;
  final Color backgroundColor;
  final Color textColor;

  const _StatusConfig({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });
}
