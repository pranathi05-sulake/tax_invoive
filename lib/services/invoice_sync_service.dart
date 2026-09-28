import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/invoice.dart';
import '../services/database/database_helper.dart';

class SyncResult {
  final bool success;
  final SyncStatus status;
  final String? serverInvoiceId;
  final String? errorMessage;

  const SyncResult({
    required this.success,
    required this.status,
    this.serverInvoiceId,
    this.errorMessage,
  });

  @override
  String toString() =>
      'SyncResult(success: $success, status: $status, serverInvoiceId: $serverInvoiceId, error: $errorMessage)';
}

class InvoiceSyncService {
  final http.Client _client;

  InvoiceSyncService({http.Client? client}) : _client = client ?? http.Client();

  /// Synchronizes a VERIFIED invoice with the FastAPI LAN backend server.
  Future<SyncResult> syncInvoice(Invoice invoice, {String verifiedBy = 'OPERATOR'}) async {
    // 1. Verify invoice is VERIFIED
    if (invoice.status != InvoiceStatus.verified) {
      debugPrint('[InvoiceSyncService] Skipped sync: Invoice ${invoice.id} is not VERIFIED.');
      return const SyncResult(
        success: false,
        status: SyncStatus.pendingSync,
        errorMessage: 'Only VERIFIED invoices can be synchronized to LAN server.',
      );
    }

    final now = DateTime.now();

    // 2. Mark sync status as SYNCING locally
    try {
      await DatabaseHelper.instance.updateInvoiceSyncState(
        invoiceId: invoice.id,
        syncStatus: SyncStatus.syncing.toServerString(),
        lastSyncAttempt: now.toIso8601String(),
        verifiedBy: invoice.verifiedBy.isNotEmpty ? invoice.verifiedBy : verifiedBy,
        verifiedAt: (invoice.verifiedAt ?? now).toIso8601String(),
      );
    } catch (e) {
      debugPrint('[InvoiceSyncService] Local DB update warning: $e');
    }

    // 3. Build API request payload
    final payload = invoice.toSyncPayload(verifiedByFallback: verifiedBy);

    try {
      final response = await _client.post(
        Uri.parse(ApiConfig.syncInvoiceUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final serverStatus = data['status'] as String?;
        final serverInvoiceId = data['server_invoice_id'] as String?;

        if (serverStatus == 'SYNCED' || serverStatus == 'ALREADY_SYNCED') {
          await DatabaseHelper.instance.updateInvoiceSyncState(
            invoiceId: invoice.id,
            syncStatus: SyncStatus.synced.toServerString(),
            serverInvoiceId: serverInvoiceId,
            syncedAt: DateTime.now().toIso8601String(),
            lastSyncAttempt: DateTime.now().toIso8601String(),
          );

          debugPrint('[InvoiceSyncService] Successfully synchronized invoice ${invoice.id} ($serverStatus).');

          return SyncResult(
            success: true,
            status: SyncStatus.synced,
            serverInvoiceId: serverInvoiceId,
          );
        }
      }

      // HTTP Error or unexpected payload
      String errorMsg = 'Server response error (${response.statusCode})';
      try {
        final errJson = jsonDecode(response.body);
        if (errJson is Map && errJson.containsKey('message')) {
          errorMsg = errJson['message'].toString();
        }
      } catch (_) {}

      await DatabaseHelper.instance.updateInvoiceSyncState(
        invoiceId: invoice.id,
        syncStatus: SyncStatus.syncFailed.toServerString(),
        incrementAttempts: true,
        lastSyncAttempt: DateTime.now().toIso8601String(),
        lastSyncError: errorMsg,
      );

      return SyncResult(
        success: false,
        status: SyncStatus.syncFailed,
        errorMessage: errorMsg,
      );
    } catch (e) {
      // Connection timeout or offline LAN
      final errorMsg = 'LAN server unavailable or network error ($e)';
      debugPrint('[InvoiceSyncService] Network error syncing invoice ${invoice.id}: $errorMsg');

      await DatabaseHelper.instance.updateInvoiceSyncState(
        invoiceId: invoice.id,
        syncStatus: SyncStatus.syncFailed.toServerString(),
        incrementAttempts: true,
        lastSyncAttempt: DateTime.now().toIso8601String(),
        lastSyncError: errorMsg,
      );

      return SyncResult(
        success: false,
        status: SyncStatus.syncFailed,
        errorMessage: errorMsg,
      );
    }
  }
}
