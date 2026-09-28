import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tax_invoice_app/models/invoice.dart';
import 'package:tax_invoice_app/screens/batch_scan_screen.dart';
import 'package:tax_invoice_app/services/database/database_helper.dart';
import 'package:tax_invoice_app/services/ocr/batch_scan_service.dart';
import 'package:tax_invoice_app/services/ocr/ocr_engine.dart';

class FakeOcrEngine implements OcrEngine {
  final Map<String, OcrResult> responses;
  final bool shouldThrow;

  FakeOcrEngine({this.responses = const {}, this.shouldThrow = false});

  @override
  Future<OcrResult> processImageFile(File imageFile) async {
    if (shouldThrow) {
      throw Exception('Simulated OCR Engine Exception');
    }
    return responses[imageFile.path] ??
        const OcrResult(
          fullText: '''
Acme Enterprise Ltd
GSTIN: 29AAACB1234C1Z5
TAX INVOICE
Invoice No: ACME-100
Date: 10/03/2026

Item Description      Amount
1  Grocery Item 1L    1000.00

CGST (9%): Rs. 90.00
SGST (9%): Rs. 90.00
SUBTOTAL: Rs. 1000.00
GRAND TOTAL: Rs. 1180.00
''',
          lines: [
            'Acme Enterprise Ltd',
            'GSTIN: 29AAACB1234C1Z5',
            'TAX INVOICE',
            'Invoice No: ACME-100',
            'Date: 10/03/2026',
            'Item Description      Amount',
            '1  Grocery Item 1L    1000.00',
            'CGST (9%): Rs. 90.00',
            'SGST (9%): Rs. 90.00',
            'SUBTOTAL: Rs. 1000.00',
            'GRAND TOTAL: Rs. 1180.00',
          ],
        );
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('BatchScanService Unit Tests', () {
    late File dummyFile1;
    late File dummyFile2;

    setUp(() async {
      final db = await DatabaseHelper.instance.database;
      await db.delete('invoice_items');
      await db.delete('invoices');

      dummyFile1 = File('test/assets/sample_invoice.png');
      dummyFile2 = File('test/assets/sample_invoice2.png');
    });

    test('processBatchItems processes items sequentially and updates status to ready', () async {
      final fakeOcr = FakeOcrEngine();
      final batchService = BatchScanService(
        ocrEngine: fakeOcr,
        databaseHelper: DatabaseHelper.instance,
      );

      final items = [
        BatchInvoiceItem(id: 'item-1', imageFile: dummyFile1),
        BatchInvoiceItem(id: 'item-2', imageFile: dummyFile2),
      ];

      int progressCount = 0;
      await batchService.processBatchItems(
        items,
        isCancelled: () => false,
        onProgress: (current, total) {
          progressCount = current;
        },
      );

      expect(progressCount, 2);
      expect(items[0].status, BatchItemStatus.ready);
      expect(items[0].extractedInvoice, isNotNull);
      expect(items[0].extractedInvoice!.vendorName, 'Acme Enterprise Ltd');
      expect(items[1].status, BatchItemStatus.ready);
    });

    test('processBatchItems handles OCR failure without crashing', () async {
      final fakeOcr = FakeOcrEngine(shouldThrow: true);
      final batchService = BatchScanService(
        ocrEngine: fakeOcr,
        databaseHelper: DatabaseHelper.instance,
      );

      final items = [
        BatchInvoiceItem(id: 'fail-1', imageFile: dummyFile1),
      ];

      await batchService.processBatchItems(
        items,
        isCancelled: () => false,
        onProgress: (_, __) {},
      );

      expect(items[0].status, BatchItemStatus.ocrFailed);
      expect(items[0].errorMessage, contains('Simulated OCR Engine Exception'));
    });

    test('processBatchItems flags duplicates when invoice already exists in SQLite', () async {
      final fakeOcr = FakeOcrEngine();
      final batchService = BatchScanService(
        ocrEngine: fakeOcr,
        databaseHelper: DatabaseHelper.instance,
      );

      // Pre-insert duplicate invoice into DB
      await DatabaseHelper.instance.insertInvoice(
        Invoice(
          id: 'item-dup',
          vendorName: 'Acme Enterprise Ltd',
          gstin: '29AAACB1234C1Z5',
          invoiceNumber: 'ACME-100',
          date: DateTime(2026, 3, 10),
          subtotal: 1000.0,
        ),
      );

      final items = [
        BatchInvoiceItem(id: 'item-dup', imageFile: dummyFile1),
      ];

      await batchService.processBatchItems(
        items,
        isCancelled: () => false,
        onProgress: (_, __) {},
      );

      expect(items[0].status, BatchItemStatus.duplicate);
    });

    test('processBatchItems respects cancellation safely', () async {
      final fakeOcr = FakeOcrEngine();
      final batchService = BatchScanService(
        ocrEngine: fakeOcr,
        databaseHelper: DatabaseHelper.instance,
      );

      final items = [
        BatchInvoiceItem(id: 'c1', imageFile: dummyFile1),
        BatchInvoiceItem(id: 'c2', imageFile: dummyFile2),
      ];

      int count = 0;
      await batchService.processBatchItems(
        items,
        isCancelled: () => count > 0, // Cancel after first item
        onProgress: (current, _) {
          count = current;
        },
      );

      expect(items[0].status, BatchItemStatus.ready);
      expect(items[1].status, BatchItemStatus.pending); // second item skipped
    });

    test('saveBatchInvoices saves ready items and skips duplicates', () async {
      final fakeOcr = FakeOcrEngine();
      final batchService = BatchScanService(
        ocrEngine: fakeOcr,
        databaseHelper: DatabaseHelper.instance,
      );

      final items = [
        BatchInvoiceItem(
          id: 's1',
          imageFile: dummyFile1,
          status: BatchItemStatus.ready,
          extractedInvoice: Invoice(
            id: 'inv-save-1',
            vendorName: 'Vendor One',
            invoiceNumber: 'V-1',
            date: DateTime(2026, 3, 1),
            subtotal: 500.0,
          ),
        ),
        BatchInvoiceItem(
          id: 's2',
          imageFile: dummyFile2,
          status: BatchItemStatus.ready,
          extractedInvoice: Invoice(
            id: 'inv-save-2',
            vendorName: 'Vendor Two',
            invoiceNumber: 'V-2',
            date: DateTime(2026, 3, 2),
            subtotal: 800.0,
          ),
        ),
      ];

      final summary = await batchService.saveBatchInvoices(items);
      expect(summary.savedCount, 2);
      expect(summary.skippedDuplicateCount, 0);

      final allInDb = await DatabaseHelper.instance.getAllInvoices();
      expect(allInDb.length, 2);
      expect(items[0].status, BatchItemStatus.saved);
      expect(items[1].status, BatchItemStatus.saved);
    });
  });

  group('BatchScanScreen Widget Tests', () {
    testWidgets('BatchScanScreen renders empty state and action buttons', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: BatchScanScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Batch Invoice Scanning'), findsOneWidget);
      expect(find.text('No invoices added to batch'), findsOneWidget);
      expect(find.text('Pick Gallery'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
    });

    testWidgets('BatchScanScreen renders invoice item list with status pills when provided initial images', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final dummyFile = File('test/assets/sample_invoice.png');
      final fakeOcr = FakeOcrEngine();
      final batchService = BatchScanService(
        ocrEngine: fakeOcr,
        databaseHelper: DatabaseHelper.instance,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BatchScanScreen(
            initialImageFiles: [dummyFile],
            batchScanService: batchService,
          ),
        ),
      );

      for (int i = 0; i < 15; i++) {
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('Acme Enterprise Ltd'), findsOneWidget);
      expect(find.text('Ready to Save'), findsOneWidget);
    });
  });
}
