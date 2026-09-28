import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tax_invoice_app/models/invoice.dart';
import 'package:tax_invoice_app/screens/backup_restore_screen.dart';
import 'package:tax_invoice_app/services/backup/invoice_backup_service.dart';
import 'package:tax_invoice_app/services/database/database_helper.dart';
import 'package:tax_invoice_app/services/export/file_export_helper.dart';

class FakeExportHelper extends FileExportHelper {
  String? lastExportedString;
  Uint8List? lastExportedBytes;
  String? lastFileName;
  String? lastMimeType;
  bool shouldSucceed;

  FakeExportHelper({this.shouldSucceed = true});

  @override
  Future<ExportResult> exportString({
    required String content,
    required String fileName,
    String? mimeType,
    String? shareSubject,
  }) async {
    lastExportedString = content;
    lastFileName = fileName;
    lastMimeType = mimeType;

    if (!shouldSucceed) {
      return const ExportResult(
        success: false,
        errorMessage: 'Mock export failure',
      );
    }

    return ExportResult(
      success: true,
      filePath: '/mock/path/$fileName',
      fileName: fileName,
    );
  }
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
  List<InvoiceItem>? items,
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
    items: items ??
        [
          InvoiceItem(
            id: 'item-$id-1',
            description: 'Item 1 for $vendorName',
            quantity: 2,
            unitPrice: subtotal / 2,
          ),
        ],
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({'sqlite_db_secret_key': 'test_mock_secret_key_32_bytes_len_0123456789abcdef'});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const backupService = InvoiceBackupService();

  group('InvoiceBackupService JSON Generation Unit Tests', () {
    test('createBackupJson produces valid JSON with correct app signature and fields', () {
      final invoices = [
        makeTestInvoice(
          id: 'inv-1',
          vendorName: 'Infosys BPM',
          invoiceNumber: 'INF-101',
          date: DateTime(2026, 3, 15),
          subtotal: 1500.0,
          cgst: 135.0,
          sgst: 135.0,
        ),
        makeTestInvoice(
          id: 'inv-2',
          vendorName: 'Wipro Limited',
          invoiceNumber: 'WIP-202',
          date: DateTime(2026, 3, 16),
          subtotal: 2500.0,
          cgst: 0.0,
          sgst: 0.0,
          igst: 450.0,
          status: InvoiceStatus.pending,
        ),
      ];

      final jsonStr = backupService.createBackupJson(invoices);
      expect(jsonStr.isNotEmpty, isTrue);

      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(decoded['app'], 'TaxInvoiceAI');
      expect(decoded['schemaVersion'], 1);
      expect(decoded['invoiceCount'], 2);
      expect(decoded['invoices'], isA<List>());

      final list = decoded['invoices'] as List;
      expect(list.length, 2);

      final inv1 = list[0] as Map<String, dynamic>;
      expect(inv1['id'], 'inv-1');
      expect(inv1['vendor_name'], 'Infosys BPM');
      expect(inv1['invoice_number'], 'INF-101');
      expect(inv1['subtotal'], 1500.0);
      expect(inv1['cgst'], 135.0);
      expect(inv1['items'], isA<List>());
      expect((inv1['items'] as List).length, 1);

      final inv2 = list[1] as Map<String, dynamic>;
      expect(inv2['id'], 'inv-2');
      expect(inv2['status'], InvoiceStatus.pending.index);
    });

    test('createBackupJson handles empty invoice list gracefully', () {
      final jsonStr = backupService.createBackupJson([]);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(decoded['app'], 'TaxInvoiceAI');
      expect(decoded['invoiceCount'], 0);
      expect((decoded['invoices'] as List).isEmpty, isTrue);
    });
  });

  group('InvoiceBackupService JSON Validation & Inspection Unit Tests', () {
    test('inspectBackupJson validates genuine backup and extracts invoices', () {
      final invoices = [
        makeTestInvoice(
          id: 'test-1',
          vendorName: 'Reliance Fresh',
          invoiceNumber: 'REL-001',
          date: DateTime(2026, 2, 20),
        ),
      ];
      final jsonStr = backupService.createBackupJson(invoices);

      final inspection = backupService.inspectBackupJson(jsonStr);
      expect(inspection.isValid, isTrue);
      expect(inspection.errorMessage, isNull);
      expect(inspection.invoiceCountInBackup, 1);
      expect(inspection.invoices.length, 1);
      expect(inspection.invoices.first.vendorName, 'Reliance Fresh');
      expect(inspection.invoices.first.items.length, 1);
    });

    test('inspectBackupJson rejects empty string', () {
      final inspection = backupService.inspectBackupJson('');
      expect(inspection.isValid, isFalse);
      expect(inspection.errorMessage, contains('empty'));
    });

    test('inspectBackupJson rejects corrupted non-JSON content', () {
      final inspection = backupService.inspectBackupJson('<<< NOT JSON >>>');
      expect(inspection.isValid, isFalse);
      expect(inspection.errorMessage, contains('Corrupted'));
    });

    test('inspectBackupJson rejects wrong app signature', () {
      final invalidJson = jsonEncode({
        'app': 'WrongApp',
        'schemaVersion': 1,
        'invoices': [],
      });
      final inspection = backupService.inspectBackupJson(invalidJson);
      expect(inspection.isValid, isFalse);
      expect(inspection.errorMessage, contains('Incompatible backup'));
    });

    test('inspectBackupJson rejects future schema version', () {
      final invalidJson = jsonEncode({
        'app': 'TaxInvoiceAI',
        'schemaVersion': 99,
        'invoices': [],
      });
      final inspection = backupService.inspectBackupJson(invalidJson);
      expect(inspection.isValid, isFalse);
      expect(inspection.errorMessage, contains('Unsupported backup schema'));
    });

    test('inspectBackupJson rejects missing required fields in invoice record', () {
      final invalidJson = jsonEncode({
        'app': 'TaxInvoiceAI',
        'schemaVersion': 1,
        'invoices': [
          {'id': 'inv-1'}, // missing vendor_name, invoice_number, date
        ],
      });
      final inspection = backupService.inspectBackupJson(invalidJson);
      expect(inspection.isValid, isFalse);
      expect(inspection.errorMessage, contains('missing required fields'));
    });
  });

  group('InvoiceBackupService Restore Strategies Unit Tests', () {
    setUp(() async {
      final db = await DatabaseHelper.instance.database;
      await db.delete('invoice_items');
      await db.delete('invoices');
    });

    test('RestoreStrategy.skipDuplicates adds new and skips existing', () async {
      // 1. Pre-populate DB with 1 invoice
      final existing = makeTestInvoice(
        id: 'existing-1',
        vendorName: 'Initial Vendor',
        invoiceNumber: 'INV-100',
        date: DateTime(2026, 3, 1),
      );
      await DatabaseHelper.instance.insertInvoice(existing);

      // 2. Prepare backup with the duplicate + 1 new invoice
      final backupInvoices = [
        makeTestInvoice(
          id: 'existing-1',
          vendorName: 'Initial Vendor Updated (should be skipped)',
          invoiceNumber: 'INV-100',
          date: DateTime(2026, 3, 1),
        ),
        makeTestInvoice(
          id: 'new-2',
          vendorName: 'New Vendor',
          invoiceNumber: 'INV-200',
          date: DateTime(2026, 3, 2),
        ),
      ];

      final result = await backupService.performRestore(
        invoicesToRestore: backupInvoices,
        strategy: RestoreStrategy.skipDuplicates,
      );

      expect(result.success, isTrue);
      expect(result.addedCount, 1);
      expect(result.skippedCount, 1);
      expect(result.updatedCount, 0);

      final allInDb = await DatabaseHelper.instance.getAllInvoices();
      expect(allInDb.length, 2);
      expect(allInDb.any((i) => i.id == 'existing-1' && i.vendorName == 'Initial Vendor'), isTrue);
      expect(allInDb.any((i) => i.id == 'new-2'), isTrue);
    });

    test('RestoreStrategy.overwriteExisting updates existing and adds new', () async {
      final existing = makeTestInvoice(
        id: 'existing-1',
        vendorName: 'Old Vendor Name',
        invoiceNumber: 'INV-100',
        date: DateTime(2026, 3, 1),
      );
      await DatabaseHelper.instance.insertInvoice(existing);

      final backupInvoices = [
        makeTestInvoice(
          id: 'existing-1',
          vendorName: 'Updated Vendor Name',
          invoiceNumber: 'INV-100',
          date: DateTime(2026, 3, 1),
          subtotal: 9999.0,
        ),
      ];

      final result = await backupService.performRestore(
        invoicesToRestore: backupInvoices,
        strategy: RestoreStrategy.overwriteExisting,
      );

      expect(result.success, isTrue);
      expect(result.updatedCount, 1);
      expect(result.addedCount, 0);

      final allInDb = await DatabaseHelper.instance.getAllInvoices();
      expect(allInDb.length, 1);
      expect(allInDb.first.vendorName, 'Updated Vendor Name');
      expect(allInDb.first.subtotal, 9999.0);
    });

    test('RestoreStrategy.replaceAll clears database and restores fresh records', () async {
      // Pre-populate with 2 invoices
      await DatabaseHelper.instance.insertInvoice(
        makeTestInvoice(id: 'old-1', vendorName: 'Old 1', invoiceNumber: '1', date: DateTime(2026, 1, 1)),
      );
      await DatabaseHelper.instance.insertInvoice(
        makeTestInvoice(id: 'old-2', vendorName: 'Old 2', invoiceNumber: '2', date: DateTime(2026, 1, 2)),
      );

      final backupInvoices = [
        makeTestInvoice(id: 'restored-1', vendorName: 'Restored 1', invoiceNumber: '10', date: DateTime(2026, 2, 1)),
      ];

      final result = await backupService.performRestore(
        invoicesToRestore: backupInvoices,
        strategy: RestoreStrategy.replaceAll,
      );

      expect(result.success, isTrue);
      expect(result.addedCount, 1);

      final allInDb = await DatabaseHelper.instance.getAllInvoices();
      expect(allInDb.length, 1);
      expect(allInDb.first.id, 'restored-1');
      expect(allInDb.first.vendorName, 'Restored 1');
    });
  });

  group('BackupRestoreScreen Widget Tests', () {
    Future<void> resetDb(WidgetTester tester) async {
      await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        await db.delete('invoice_items');
        await db.delete('invoices');
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

    testWidgets('BackupRestoreScreen renders database stats and action cards', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await resetDb(tester);

      await tester.runAsync(() async {
        await DatabaseHelper.instance.insertInvoice(
          makeTestInvoice(
            id: '1',
            vendorName: 'Airtel Broadband',
            invoiceNumber: 'AIR-100',
            date: DateTime(2026, 3, 1),
          ),
        );
      });

      await tester.pumpWidget(const MaterialApp(home: BackupRestoreScreen()));
      await settleScreen(tester);

      expect(find.text('Backup & Restore'), findsOneWidget);
      expect(find.text('1 Invoices Stored'), findsOneWidget);
      expect(find.text('Export Encrypted Backup (.json)'), findsOneWidget);
      expect(find.text('Restore Database from Backup'), findsOneWidget);
      expect(find.text('Export Password-Protected Backup'), findsOneWidget);
      expect(find.text('Select & Restore Backup File'), findsOneWidget);
    });

    testWidgets('BackupRestoreScreen creates backup using fake export helper', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await resetDb(tester);

      final fakeExport = FakeExportHelper(shouldSucceed: true);

      await tester.runAsync(() async {
        await DatabaseHelper.instance.insertInvoice(
          makeTestInvoice(
            id: '1',
            vendorName: 'Infosys Ltd',
            invoiceNumber: 'INF-999',
            date: DateTime(2026, 3, 5),
          ),
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: BackupRestoreScreen(
            exportHelper: fakeExport,
          ),
        ),
      );
      await settleScreen(tester);

      await tester.ensureVisible(find.text('Export Plaintext Backup'));
      await tester.tap(find.text('Export Plaintext Backup'));
      await settleScreen(tester);

      expect(fakeExport.lastExportedString, isNotNull);
      expect(fakeExport.lastFileName, contains('TaxInvoice_Backup_'));
      expect(fakeExport.lastFileName, endsWith('.json'));

      final decoded = jsonDecode(fakeExport.lastExportedString!) as Map<String, dynamic>;
      expect(decoded['app'], 'TaxInvoiceAI');
      expect(decoded['invoiceCount'], 1);
    });
  });
}
