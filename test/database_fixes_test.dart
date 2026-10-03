import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tax_invoice_app/models/invoice.dart';
import 'package:tax_invoice_app/services/database/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('FIX 1 — Local Duplicate Date Format Tests', () {
    test('Detects duplicate invoice with same GSTIN, invoice number, and YYYY-MM-DD date', () async {
      final db = DatabaseHelper.instance;
      await db.resetDatabaseForTesting();

      final invDate = DateTime(2026, 10, 2);
      final initialInvoice = Invoice(
        id: 'inv_dup_001',
        vendorName: 'Helicopter Spares Pvt Ltd',
        gstin: '29ABCDE1234F1Z5',
        invoiceNumber: 'INV-2026-001',
        date: invDate,
        subtotal: 1000.0,
        cgst: 90.0,
        sgst: 90.0,
        igst: 0.0,
      );

      await db.insertInvoice(initialInvoice);

      // Check same GSTIN + Inv# + Date (YYYY-MM-DD)
      final isDuplicate = await db.checkInvoiceExists(
        gstin: '29ABCDE1234F1Z5',
        invoiceNumber: 'INV-2026-001',
        date: invDate,
      );

      expect(isDuplicate, isTrue);

      await db.resetDatabaseForTesting();
    });

    test('Same invoice number on DIFFERENT date is NOT treated as duplicate', () async {
      final db = DatabaseHelper.instance;
      await db.resetDatabaseForTesting();

      final originalDate = DateTime(2026, 10, 2);
      final differentDate = DateTime(2026, 10, 3);

      final initialInvoice = Invoice(
        id: 'inv_dup_002',
        vendorName: 'Helicopter Spares Pvt Ltd',
        gstin: '29ABCDE1234F1Z5',
        invoiceNumber: 'INV-2026-001',
        date: originalDate,
        subtotal: 1000.0,
        cgst: 90.0,
        sgst: 90.0,
        igst: 0.0,
      );

      await db.insertInvoice(initialInvoice);

      // Check same GSTIN + Inv# but DIFFERENT date
      final isDuplicate = await db.checkInvoiceExists(
        gstin: '29ABCDE1234F1Z5',
        invoiceNumber: 'INV-2026-001',
        date: differentDate,
      );

      expect(isDuplicate, isFalse);

      await db.resetDatabaseForTesting();
    });
  });

  group('FIX 2 — Money Precision Before Sync Tests', () {
    test('Invoice.roundMoney rounds values deterministically to 2 decimal places', () {
      expect(Invoice.roundMoney(100.005), equals(100.01));
      expect(Invoice.roundMoney(100.004), equals(100.00));
      expect(Invoice.roundMoney(99.999), equals(100.00));
      expect(Invoice.roundMoney(1250.50), equals(1250.50));
    });

    test('toSyncPayload rounds monetary fields to 2 decimals while preserving quantities', () {
      final testInvoice = Invoice(
        id: 'inv_sync_001',
        vendorName: 'Aero Dynamics',
        gstin: '29ABCDE1234F1Z5',
        invoiceNumber: 'INV-ROUND-101',
        date: DateTime(2026, 10, 2),
        subtotal: 100.005, // Should round to 100.01
        cgst: 9.004,       // Should round to 9.00
        sgst: 9.004,       // Should round to 9.00
        igst: 0.0,
        items: const [
          InvoiceItem(
            id: 'item_01',
            description: 'Turbine Blade Precision Part',
            quantity: 2, // Quantity preserved
            unitPrice: 50.0025, // Should round to 50.00
            hsnSac: '88033000',
          ),
        ],
      );

      final payload = testInvoice.toSyncPayload();

      expect(payload['taxable_value'], equals(100.01));
      expect(payload['cgst'], equals(9.00));
      expect(payload['sgst'], equals(9.00));
      expect(payload['igst'], equals(0.00));
      expect(payload['total_amount'], equals(118.01));

      final payloadItems = payload['invoice_items'] as List<dynamic>;
      expect(payloadItems.length, equals(1));
      expect(payloadItems[0]['unit_price'], equals(50.00));
      expect(payloadItems[0]['quantity'], equals(2.0));
    });
  });

  group('FIX 3 — Workflow Log Foreign Key & V5 Migration Tests', () {
    test('Workflow logs cascade delete when parent invoice is deleted', () async {
      final db = DatabaseHelper.instance;
      await db.resetDatabaseForTesting();

      final testInvoice1 = Invoice(
        id: 'inv_fk_test_001',
        vendorName: 'Helicopter Maintenance Corp',
        gstin: '29ABCDE1234F1Z5',
        invoiceNumber: 'INV-FK-001',
        date: DateTime(2026, 10, 2),
        subtotal: 5000.0,
      );

      final testInvoice2 = Invoice(
        id: 'inv_unrelated_002',
        vendorName: 'Aero Avionics Ltd',
        gstin: '29ABCDE1234F1Z5',
        invoiceNumber: 'INV-FK-002',
        date: DateTime(2026, 10, 2),
        subtotal: 3000.0,
      );

      await db.insertInvoice(testInvoice1);
      await db.insertInvoice(testInvoice2);

      // Insert associated workflow log for Invoice 1
      final logLinked = WorkflowLogEntry(
        id: 'log_linked_01',
        executionId: 'exec_001',
        invoiceId: 'inv_fk_test_001',
        sourcePath: '/docs/invoice1.pdf',
        step: 'OCR_PREPROCESSING',
        status: 'SUCCESS',
        message: 'Preprocessing completed',
        timestamp: DateTime.now(),
      );

      // Insert workflow log for Invoice 2
      final logUnrelated = WorkflowLogEntry(
        id: 'log_unrelated_02',
        executionId: 'exec_002',
        invoiceId: 'inv_unrelated_002',
        sourcePath: '/docs/invoice2.pdf',
        step: 'OCR_PREPROCESSING',
        status: 'SUCCESS',
        message: 'Unrelated log entry',
        timestamp: DateTime.now(),
      );

      // Insert standalone workflow log with empty invoiceId
      final logNullInvoice = WorkflowLogEntry(
        id: 'log_null_03',
        executionId: 'exec_003',
        invoiceId: '',
        sourcePath: '/docs/general.pdf',
        step: 'SYSTEM_STARTUP',
        status: 'INFO',
        message: 'System started',
        timestamp: DateTime.now(),
      );

      await db.insertWorkflowLog(logLinked);
      await db.insertWorkflowLog(logUnrelated);
      await db.insertWorkflowLog(logNullInvoice);

      // Verify logs exist before deletion
      var logs = await db.getWorkflowLogs();
      expect(logs.length, equals(3));

      // Delete Invoice 1
      await db.deleteInvoice('inv_fk_test_001');

      // Verify logLinked was cascade deleted, while logUnrelated and logNullInvoice remain
      logs = await db.getWorkflowLogs();
      expect(logs.length, equals(2));
      final remainingIds = logs.map((l) => l.id).toSet();
      expect(remainingIds.contains('log_linked_01'), isFalse);
      expect(remainingIds.contains('log_unrelated_02'), isTrue);
      expect(remainingIds.contains('log_null_03'), isTrue);

      await db.resetDatabaseForTesting();
    });
  }
);
}
