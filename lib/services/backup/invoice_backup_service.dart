import 'dart:convert';
import '../../models/invoice.dart';
import '../database/database_helper.dart';

enum RestoreStrategy {
  skipDuplicates,
  overwriteExisting,
  replaceAll,
}

class BackupInspectionResult {
  final bool isValid;
  final String? errorMessage;
  final int schemaVersion;
  final DateTime? createdAt;
  final int invoiceCountInBackup;
  final List<Invoice> invoices;

  const BackupInspectionResult({
    required this.isValid,
    this.errorMessage,
    this.schemaVersion = 1,
    this.createdAt,
    this.invoiceCountInBackup = 0,
    this.invoices = const [],
  });

  factory BackupInspectionResult.invalid(String message) {
    return BackupInspectionResult(
      isValid: false,
      errorMessage: message,
      invoiceCountInBackup: 0,
      invoices: const [],
    );
  }
}

class RestoreResult {
  final bool success;
  final String? errorMessage;
  final int addedCount;
  final int updatedCount;
  final int skippedCount;
  final int totalProcessed;

  const RestoreResult({
    required this.success,
    this.errorMessage,
    this.addedCount = 0,
    this.updatedCount = 0,
    this.skippedCount = 0,
    this.totalProcessed = 0,
  });

  factory RestoreResult.failure(String message) {
    return RestoreResult(
      success: false,
      errorMessage: message,
    );
  }
}

class InvoiceBackupService {
  static const String appSignature = 'TaxInvoiceAI';
  static const int currentSchemaVersion = 1;

  const InvoiceBackupService();

  /// Serializes a list of Invoices into a formatted JSON backup string.
  String createBackupJson(List<Invoice> invoices) {
    final Map<String, dynamic> backupMap = {
      'app': appSignature,
      'schemaVersion': currentSchemaVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'invoiceCount': invoices.length,
      'invoices': invoices.map((inv) => inv.toJson()).toList(),
    };

    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(backupMap);
  }

  /// Parses and validates a JSON backup string without modifying the database.
  BackupInspectionResult inspectBackupJson(String jsonString) {
    if (jsonString.trim().isEmpty) {
      return BackupInspectionResult.invalid('The selected backup file is empty.');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(jsonString);
    } catch (e) {
      return BackupInspectionResult.invalid('Corrupted or invalid JSON format: $e');
    }

    if (decoded is! Map<String, dynamic>) {
      return BackupInspectionResult.invalid(
        'Invalid backup format: root element must be a JSON object.',
      );
    }

    final app = decoded['app'];
    if (app != appSignature) {
      return BackupInspectionResult.invalid(
        'Incompatible backup file. Expected signature "$appSignature", found "$app".',
      );
    }

    final schemaVersion = decoded['schemaVersion'] as int? ?? 1;
    if (schemaVersion > currentSchemaVersion) {
      return BackupInspectionResult.invalid(
        'Unsupported backup schema version ($schemaVersion). Please update the app.',
      );
    }

    final createdAtStr = decoded['createdAt'] as String?;
    final createdAt = createdAtStr != null ? DateTime.tryParse(createdAtStr) : null;

    final rawInvoices = decoded['invoices'];
    if (rawInvoices is! List) {
      return BackupInspectionResult.invalid(
        'Invalid backup format: "invoices" list is missing or corrupted.',
      );
    }

    final List<Invoice> parsedInvoices = [];
    for (int i = 0; i < rawInvoices.length; i++) {
      final item = rawInvoices[i];
      if (item is! Map<String, dynamic>) {
        return BackupInspectionResult.invalid(
          'Invoice record at index $i is malformed.',
        );
      }

      // Check required header fields
      if (!item.containsKey('id') ||
          !item.containsKey('vendor_name') ||
          !item.containsKey('invoice_number') ||
          !item.containsKey('date')) {
        return BackupInspectionResult.invalid(
          'Invoice record at index $i is missing required fields (id, vendor_name, invoice_number, date).',
        );
      }

      try {
        final invoice = Invoice.fromJson(item);
        parsedInvoices.add(invoice);
      } catch (e) {
        return BackupInspectionResult.invalid(
          'Failed to parse invoice at index $i: $e',
        );
      }
    }

    return BackupInspectionResult(
      isValid: true,
      schemaVersion: schemaVersion,
      createdAt: createdAt,
      invoiceCountInBackup: parsedInvoices.length,
      invoices: parsedInvoices,
    );
  }

  /// Restores a validated list of invoices to SQLite with the specified strategy.
  Future<RestoreResult> performRestore({
    required List<Invoice> invoicesToRestore,
    required RestoreStrategy strategy,
    DatabaseHelper? dbHelper,
  }) async {
    final db = dbHelper ?? DatabaseHelper.instance;

    if (invoicesToRestore.isEmpty) {
      if (strategy == RestoreStrategy.replaceAll) {
        await db.clearAllInvoices();
      }
      return const RestoreResult(
        success: true,
        addedCount: 0,
        updatedCount: 0,
        skippedCount: 0,
        totalProcessed: 0,
      );
    }

    int added = 0;
    int updated = 0;
    int skipped = 0;

    try {
      if (strategy == RestoreStrategy.replaceAll) {
        await db.clearAllInvoices();
        for (final inv in invoicesToRestore) {
          final inserted = await db.insertInvoice(inv);
          if (inserted != null) {
            added++;
          }
        }
      } else if (strategy == RestoreStrategy.overwriteExisting) {
        for (final inv in invoicesToRestore) {
          final exists = await db.checkInvoiceExists(
            gstin: inv.gstin,
            invoiceNumber: inv.invoiceNumber,
            date: inv.date,
            id: inv.id,
          );
          if (exists) {
            await db.replaceInvoice(inv);
            updated++;
          } else {
            final inserted = await db.insertInvoice(inv);
            if (inserted != null) {
              added++;
            } else {
              updated++;
            }
          }
        }
      } else {
        // Default: skipDuplicates
        for (final inv in invoicesToRestore) {
          final exists = await db.checkInvoiceExists(
            gstin: inv.gstin,
            invoiceNumber: inv.invoiceNumber,
            date: inv.date,
            id: inv.id,
          );
          if (exists) {
            skipped++;
          } else {
            final inserted = await db.insertInvoice(inv);
            if (inserted != null) {
              added++;
            } else {
              skipped++;
            }
          }
        }
      }

      return RestoreResult(
        success: true,
        addedCount: added,
        updatedCount: updated,
        skippedCount: skipped,
        totalProcessed: invoicesToRestore.length,
      );
    } catch (e) {
      return RestoreResult.failure('Database restore error: $e');
    }
  }
}
