import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../models/invoice.dart';
import '../database/database_helper.dart';
import '../validation/invoice_validator.dart';
import 'ocr_engine.dart';
import 'tax_invoice_parser.dart';

enum BatchItemStatus {
  pending,
  processing,
  ready,
  needsReview,
  duplicate,
  ocrFailed,
  saved,
}

class BatchInvoiceItem {
  final String id;
  final File imageFile;
  BatchItemStatus status;
  Invoice? extractedInvoice;
  List<String> validationWarnings;
  String? rawOcrText;
  String? errorMessage;
  bool isReviewed;

  BatchInvoiceItem({
    required this.id,
    required this.imageFile,
    this.status = BatchItemStatus.pending,
    this.extractedInvoice,
    List<String>? validationWarnings,
    this.rawOcrText,
    this.errorMessage,
    this.isReviewed = false,
  }) : validationWarnings = validationWarnings ?? [];

  BatchInvoiceItem copyWith({
    BatchItemStatus? status,
    Invoice? extractedInvoice,
    List<String>? validationWarnings,
    String? rawOcrText,
    String? errorMessage,
    bool? isReviewed,
  }) {
    return BatchInvoiceItem(
      id: id,
      imageFile: imageFile,
      status: status ?? this.status,
      extractedInvoice: extractedInvoice ?? this.extractedInvoice,
      validationWarnings: validationWarnings ?? this.validationWarnings,
      rawOcrText: rawOcrText ?? this.rawOcrText,
      errorMessage: errorMessage ?? this.errorMessage,
      isReviewed: isReviewed ?? this.isReviewed,
    );
  }
}

class BatchSaveSummary {
  final int savedCount;
  final int skippedDuplicateCount;
  final int errorCount;

  const BatchSaveSummary({
    required this.savedCount,
    required this.skippedDuplicateCount,
    required this.errorCount,
  });
}

class BatchScanService {
  final OcrEngine ocrEngine;
  final TaxInvoiceParserService parserService;
  final InvoiceValidator validator;
  final DatabaseHelper? databaseHelper;

  BatchScanService({
    OcrEngine? ocrEngine,
    TaxInvoiceParserService? parserService,
    InvoiceValidator? validator,
    this.databaseHelper,
  })  : ocrEngine = ocrEngine ?? MlKitOcrEngine(),
        parserService = parserService ?? TaxInvoiceParserService(),
        validator = validator ?? InvoiceValidator();

  DatabaseHelper get _db => databaseHelper ?? DatabaseHelper.instance;

  /// Processes a single batch item using offline OCR, rule-based parsing, validation, and duplicate checking.
  Future<void> processSingleItem(
    BatchInvoiceItem item, {
    VoidCallback? onItemUpdated,
  }) async {
    item.status = BatchItemStatus.processing;
    onItemUpdated?.call();

    try {
      final ocrResult = await ocrEngine.processImageFile(item.imageFile);
      item.rawOcrText = ocrResult.fullText;

      if (ocrResult.isEmpty) {
        item.status = BatchItemStatus.ocrFailed;
        item.errorMessage = 'No readable text extracted from invoice image.';
        onItemUpdated?.call();
        return;
      }

      final parsedResult = parserService.parse(ocrResult.fullText);
      final invoice = parsedResult.toInvoice(id: item.id);
      item.extractedInvoice = invoice;

      final validation = InvoiceValidator.validate(invoice);
      item.validationWarnings = validation.warnings;

      // Check duplicate in SQLite database
      final exists = await _db.checkInvoiceExists(
        gstin: invoice.gstin,
        invoiceNumber: invoice.invoiceNumber,
        date: invoice.date,
        id: invoice.id,
      );

      if (exists) {
        item.status = BatchItemStatus.duplicate;
      } else if (validation.warnings.isNotEmpty || invoice.gstin.isEmpty) {
        item.status = BatchItemStatus.needsReview;
      } else {
        item.status = BatchItemStatus.ready;
      }
    } catch (e) {
      item.status = BatchItemStatus.ocrFailed;
      item.errorMessage = 'OCR processing error: $e';
    }

    onItemUpdated?.call();
  }

  /// Iterates through all pending batch items sequentially to minimize memory consumption.
  /// Supports graceful cancellation via [isCancelled] check.
  Future<void> processBatchItems(
    List<BatchInvoiceItem> items, {
    required bool Function() isCancelled,
    required void Function(int currentIndex, int totalCount) onProgress,
    VoidCallback? onItemUpdated,
  }) async {
    final pendingItems = items.where((i) => i.status == BatchItemStatus.pending).toList();
    final total = pendingItems.length;

    for (int i = 0; i < total; i++) {
      if (isCancelled()) {
        debugPrint('[BatchScanService] Batch processing cancelled by user.');
        break;
      }

      onProgress(i + 1, total);
      await processSingleItem(pendingItems[i], onItemUpdated: onItemUpdated);
    }
  }

  /// Saves reviewed or ready invoices into SQLite in batch with duplicate protection.
  Future<BatchSaveSummary> saveBatchInvoices(
    List<BatchInvoiceItem> itemsToSave,
  ) async {
    int saved = 0;
    int skipped = 0;
    int errors = 0;

    for (final item in itemsToSave) {
      if (item.extractedInvoice == null) continue;

      final invoice = item.extractedInvoice!;

      try {
        final exists = await _db.checkInvoiceExists(
          gstin: invoice.gstin,
          invoiceNumber: invoice.invoiceNumber,
          date: invoice.date,
          id: invoice.id,
        );

        if (exists) {
          item.status = BatchItemStatus.duplicate;
          skipped++;
        } else {
          final inserted = await _db.insertInvoice(invoice);
          if (inserted != null) {
            item.status = BatchItemStatus.saved;
            saved++;
          } else {
            item.status = BatchItemStatus.duplicate;
            skipped++;
          }
        }
      } catch (e) {
        item.errorMessage = 'Database save error: $e';
        errors++;
      }
    }

    return BatchSaveSummary(
      savedCount: saved,
      skippedDuplicateCount: skipped,
      errorCount: errors,
    );
  }
}
