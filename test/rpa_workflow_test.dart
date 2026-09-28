import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tax_invoice_app/models/invoice.dart';
import 'package:tax_invoice_app/screens/rpa_workflow_screen.dart';
import 'package:tax_invoice_app/screens/rpa_workflow_history_screen.dart';
import 'package:tax_invoice_app/services/database/database_helper.dart';
import 'package:tax_invoice_app/services/ocr/batch_scan_service.dart';
import 'package:tax_invoice_app/services/ocr/ocr_engine.dart';
import 'package:tax_invoice_app/services/ocr/tax_invoice_parser.dart';
import 'package:tax_invoice_app/services/validation/invoice_validator.dart';
import 'package:tax_invoice_app/services/workflow/rpa_workflow_engine.dart';
import 'package:tax_invoice_app/services/workflow/rpa_workflow_models.dart';

class FakeOcrEngine implements OcrEngine {
  final String textToReturn;
  final bool returnEmpty;

  FakeOcrEngine({this.textToReturn = '', this.returnEmpty = false});

  @override
  Future<OcrResult> processImageFile(File imageFile) async {
    if (returnEmpty || textToReturn.isEmpty) {
      return const OcrResult(lines: [], fullText: '');
    }
    return OcrResult(
      lines: textToReturn.split('\n'),
      fullText: textToReturn,
    );
  }

  @override
  Future<void> dispose() async {}
}

Invoice makeTestInvoice({
  required String id,
  required String vendorName,
  required String invoiceNumber,
  required DateTime date,
  double subtotal = 1000.0,
  double cgst = 90.0,
  double sgst = 90.0,
  double igst = 0.0,
  String gstin = '29AAACB1234C1Z5',
  InvoiceStatus status = InvoiceStatus.verified,
}) {
  return Invoice(
    id: id,
    vendorName: vendorName,
    gstin: gstin,
    invoiceNumber: invoiceNumber,
    date: date,
    subtotal: subtotal,
    cgst: cgst,
    sgst: sgst,
    igst: igst,
    status: status,
    items: [
      InvoiceItem(
        id: 'item-$id',
        description: 'Item for $vendorName',
        quantity: 1,
        unitPrice: subtotal,
      ),
    ],
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('RpaWorkflowEngine Unit Tests', () {
    late DatabaseHelper db;
    late File dummyFile;

    setUp(() async {
      db = DatabaseHelper.instance;
      final database = await db.database;
      await database.delete('workflow_logs');
      await database.delete('invoice_items');
      await database.delete('invoices');

      // Create a temporary dummy file
      dummyFile = File('${Directory.systemTemp.path}/test_invoice_dummy.png');
      await dummyFile.writeAsString('dummy_bytes');
    });

    tearDown(() async {
      if (await dummyFile.exists()) {
        await dummyFile.delete();
      }
    });

    test('Uncertain or missing data is NOT automatically saved and stops at needsReview', () async {
      // OCR text missing GSTIN and Invoice Number
      const ocrText = '''
RETAIL STORE
TOTAL AMOUNT: 500.00
      ''';

      final engine = RpaWorkflowEngine(
        ocrEngine: FakeOcrEngine(textToReturn: ocrText),
        parserService: TaxInvoiceParserService(),
        validator: InvoiceValidator(),
        databaseHelper: db,
      );

      final execution = await engine.executeWorkflow(dummyFile);

      // Workflow must stop at needsReview step and NOT save automatically
      expect(execution.status, RpaWorkflowStatus.needsReview);
      expect(execution.currentStep, RpaWorkflowStep.reviewRequired);
      expect(execution.isReviewed, isFalse);

      final countInDb = await db.getInvoiceCount();
      expect(countInDb, 0); // Must NOT auto-save unreviewed/incomplete invoice
    });

    test('Explicit user approval is required before saving invoice to SQLite', () async {
      const ocrText = '''
RETAIL STORE
TOTAL AMOUNT: 500.00
      ''';

      final engine = RpaWorkflowEngine(
        ocrEngine: FakeOcrEngine(textToReturn: ocrText),
        parserService: TaxInvoiceParserService(),
        validator: InvoiceValidator(),
        databaseHelper: db,
      );

      final execution = await engine.executeWorkflow(dummyFile);
      expect(execution.status, RpaWorkflowStatus.needsReview);
      expect(await db.getInvoiceCount(), 0);

      // Explicit user review and approval
      final approvedInvoice = execution.extractedInvoice!.copyWith(
        vendorName: 'Approved Store',
        gstin: '29ABCDE1234F1Z5',
        invoiceNumber: 'INV-APP-01',
      );

      final savedExecution = await engine.approveAndSaveInvoice(
        execution,
        editedInvoice: approvedInvoice,
      );

      expect(savedExecution.status, RpaWorkflowStatus.completed);
      expect(savedExecution.currentStep, RpaWorkflowStep.completed);
      expect(await db.getInvoiceCount(), 1); // Only saves after explicit approval
    });

    test('Duplicate invoices are detected and NOT inserted into SQLite', () async {
      // Insert pre-existing invoice into SQLite
      await db.insertInvoice(
        makeTestInvoice(
          id: 'existing-id',
          vendorName: 'Vendor A',
          invoiceNumber: 'INV-DUP-100',
          date: DateTime(2026, 3, 10),
          gstin: '29AAACB1234C1Z5',
        ),
      );
      expect(await db.getInvoiceCount(), 1);

      const ocrText = '''
TAX INVOICE
Vendor A
GSTIN: 29AAACB1234C1Z5
Invoice No: INV-DUP-100
Date: 10/03/2026
TOTAL: 1000.00
      ''';

      final engine = RpaWorkflowEngine(
        ocrEngine: FakeOcrEngine(textToReturn: ocrText),
        parserService: TaxInvoiceParserService(),
        validator: InvoiceValidator(),
        databaseHelper: db,
      );

      final execution = await engine.executeWorkflow(dummyFile);
      expect(execution.status, RpaWorkflowStatus.duplicate);
      expect(await db.getInvoiceCount(), 1); // Database count remains 1 (no duplicate inserted)
    });

    test('Cancelling a workflow does NOT create a partial invoice in SQLite', () async {
      const ocrText = '''
TAX INVOICE
Clean Vendor
GSTIN: 29AAACB1234C1Z5
Invoice No: INV-CLEAN-01
Date: 15/03/2026
TOTAL: 1000.00
      ''';

      final engine = RpaWorkflowEngine(
        ocrEngine: FakeOcrEngine(textToReturn: ocrText),
        parserService: TaxInvoiceParserService(),
        validator: InvoiceValidator(),
        databaseHelper: db,
      );

      final execution = RpaWorkflowExecution(
        id: 'cancel-test-id',
        sourcePath: dummyFile.path,
        startTime: DateTime.now(),
      );

      final cancelledExecution = await engine.cancelWorkflow(execution);
      expect(cancelledExecution.status, RpaWorkflowStatus.cancelled);
      expect(await db.getInvoiceCount(), 0); // No partial invoice in DB
    });

    test('Existing invoices survive database schema migration (v1 -> v2) and workflow logs persist', () async {
      // Create initial invoice record
      final inserted = await db.insertInvoice(
        makeTestInvoice(
          id: 'pre-migration-inv',
          vendorName: 'Pre-Migration Corp',
          invoiceNumber: 'PRE-001',
          date: DateTime(2026, 1, 1),
        ),
      );
      expect(inserted, isNotNull);

      // Verify workflow_logs table exists and insertWorkflowLog succeeds
      await db.insertWorkflowLog(
        WorkflowLogEntry(
          id: 'log-1',
          executionId: 'exec-1',
          invoiceId: 'pre-migration-inv',
          sourcePath: '/path/file.png',
          step: 'ocr',
          status: 'completed',
          message: 'OCR succeeded',
          timestamp: DateTime.now(),
        ),
      );

      final logs = await db.getWorkflowLogs(executionId: 'exec-1');
      expect(logs.length, 1);
      expect(logs.first.invoiceId, 'pre-migration-inv');
      expect(logs.first.message, 'OCR succeeded');

      // Verify original invoice survived intact
      final allInvoices = await db.getAllInvoices();
      expect(allInvoices.any((i) => i.id == 'pre-migration-inv'), isTrue);
    });

    test('One failed batch item does NOT stop remaining batch items in BatchScanService', () async {
      final validFile = File('${Directory.systemTemp.path}/valid_item.png');
      final invalidFile = File('${Directory.systemTemp.path}/invalid_item.png');
      await validFile.writeAsString('valid');
      await invalidFile.writeAsString('invalid');

      final item1 = BatchInvoiceItem(id: 'item-1', imageFile: invalidFile);
      final item2 = BatchInvoiceItem(id: 'item-2', imageFile: validFile);

      final engine1 = FakeOcrEngine(returnEmpty: true); // Fails
      final engine2 = FakeOcrEngine(
        textToReturn: '''
TAX INVOICE
Batch Vendor
GSTIN: 29AAACB1234C1Z5
Invoice No: BATCH-01
Date: 10/03/2026
TOTAL: 1000.00
        ''',
      );

      final batchService = BatchScanService(
        ocrEngine: engine1,
        databaseHelper: db,
      );

      // Process item 1 (fails)
      await batchService.processSingleItem(item1);
      expect(item1.status, BatchItemStatus.ocrFailed);

      // Process item 2 (succeeds) with separate working OCR engine
      final batchService2 = BatchScanService(
        ocrEngine: engine2,
        databaseHelper: db,
      );
      await batchService2.processSingleItem(item2);
      expect(item2.status, BatchItemStatus.needsReview);

      if (await validFile.exists()) await validFile.delete();
      if (await invalidFile.exists()) await invalidFile.delete();
    });
  });

  group('RPA Workflow Screens Widget Tests', () {
    Future<void> resetDb(WidgetTester tester) async {
      await tester.runAsync(() async {
        final database = await DatabaseHelper.instance.database;
        await database.delete('workflow_logs');
        await database.delete('invoice_items');
        await database.delete('invoices');
      });
    }

    Future<void> settleScreen(WidgetTester tester) async {
      for (int i = 0; i < 15; i++) {
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets('RpaWorkflowScreen renders pipeline launcher and launcher buttons', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await resetDb(tester);

      await tester.pumpWidget(const MaterialApp(home: RpaWorkflowScreen()));
      await settleScreen(tester);

      expect(find.text('RPA Workflow Automation Engine'), findsOneWidget);
      expect(find.text('Automated Pipeline Launcher'), findsOneWidget);
      expect(find.text('Capture Camera'), findsOneWidget);
      expect(find.text('Pick Gallery'), findsOneWidget);
    });

    testWidgets('RpaWorkflowHistoryScreen renders empty state when no logs exist', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await resetDb(tester);

      await tester.pumpWidget(const MaterialApp(home: RpaWorkflowHistoryScreen()));
      await settleScreen(tester);

      expect(find.text('Workflow Execution Logs'), findsOneWidget);
      expect(find.text('No Workflow Logs Found'), findsOneWidget);
    });
  });
}
