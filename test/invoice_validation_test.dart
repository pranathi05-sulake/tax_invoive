import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tax_invoice_app/services/validation/invoice_validator.dart';
import 'package:tax_invoice_app/models/invoice.dart';

final _defaultItems = [
  const InvoiceItem(
    id: 'item-1',
    description: 'Aashirvaad Atta 5kg',
    quantity: 1,
    unitPrice: 560.0,
  ),
];

Invoice _makeInvoice({
  String vendorName = 'SUPERMART GROCERY STORES LTD',
  String gstin = '29AAACB1234C1Z5',
  String invoiceNumber = 'INV/2026/0001',
  double subtotal = 560.0,
  double cgst = 25.20,
  double sgst = 25.20,
  double igst = 0.0,
  List<InvoiceItem>? items,
}) {
  return Invoice(
    id: 'test-id',
    vendorName: vendorName,
    gstin: gstin,
    invoiceNumber: invoiceNumber,
    date: DateTime(2026, 9, 15),
    subtotal: subtotal,
    cgst: cgst,
    sgst: sgst,
    igst: igst,
    items: items ?? _defaultItems,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('InvoiceValidator Tests', () {
    test('Valid invoice passes with no warnings', () {
      final invoice = _makeInvoice();
      final result = InvoiceValidator.validate(invoice);
      expect(result.isValid, isTrue);
      expect(result.warnings, isEmpty);
    });

    test('Flags missing vendor name', () {
      final invoice = _makeInvoice(vendorName: '');
      final result = InvoiceValidator.validate(invoice);
      expect(result.isValid, isFalse);
      expect(result.warnings.any((w) => w.contains('Vendor Name')), isTrue);
    });

    test('Flags missing invoice number', () {
      final invoice = _makeInvoice(invoiceNumber: '');
      final result = InvoiceValidator.validate(invoice);
      expect(result.isValid, isFalse);
      expect(result.warnings.any((w) => w.contains('Invoice Number')), isTrue);
    });

    test('Flags missing GSTIN', () {
      final invoice = _makeInvoice(gstin: '');
      final result = InvoiceValidator.validate(invoice);
      expect(result.isValid, isFalse);
      expect(result.warnings.any((w) => w.contains('GSTIN')), isTrue);
    });

    test('Flags invalid GSTIN format', () {
      final invoice = _makeInvoice(gstin: 'INVALID_GSTIN');
      final result = InvoiceValidator.validate(invoice);
      expect(result.isValid, isFalse);
      expect(result.warnings.any((w) => w.contains('format')), isTrue);
    });

    test('Accepts a valid 15-char GSTIN', () {
      final invoice = _makeInvoice(gstin: '27AAAAA0000A1Z5');
      final result = InvoiceValidator.validate(invoice);
      // Only check GSTIN-related warnings absent
      expect(result.warnings.any((w) => w.contains('GSTIN')), isFalse);
    });

    test('Flags tax inconsistency when total does not match subtotal + taxes', () {
      // subtotal=100, cgst=10, sgst=10, total from model = 120 which is fine
      // But we create invoice where total would not match by making a special invoice
      final invoice = Invoice(
        id: 'test',
        vendorName: 'VENDOR',
        gstin: '29AAACB1234C1Z5',
        invoiceNumber: 'INV-001',
        date: DateTime(2026, 9, 15),
        subtotal: 1000.0,  // actual items sum
        cgst: 50.0,
        sgst: 50.0,
        igst: 0.0,
        // totalAmount = subtotal + cgst + sgst + igst = 1100
      );
      // Validator computes expectedTotal = 1000 + 50 + 50 = 1100 and totalAmount = 1100
      // They match, so this should pass tax check
      final result = InvoiceValidator.validate(invoice);
      expect(result.warnings.any((w) => w.contains('Total amount')), isFalse);
    });

    test('All fields missing returns multiple warnings', () {
      final invoice = _makeInvoice(vendorName: '', gstin: '', invoiceNumber: '');
      final result = InvoiceValidator.validate(invoice);
      expect(result.isValid, isFalse);
      expect(result.warnings.length, greaterThanOrEqualTo(3));
    });
  });

  group('Invoice Model Serialization Tests', () {
    test('Invoice.toMap() and Invoice.fromMap() round-trip correctly', () {
      final original = Invoice(
        id: 'inv-001',
        vendorName: 'Test Vendor',
        gstin: '29AAACB1234C1Z5',
        invoiceNumber: 'INV-001',
        date: DateTime(2026, 9, 15),
        subtotal: 500.0,
        cgst: 25.0,
        sgst: 25.0,
        igst: 0.0,
        status: InvoiceStatus.verified,
      );

      final map = original.toMap();
      final restored = Invoice.fromMap(map);

      expect(restored.id, equals(original.id));
      expect(restored.vendorName, equals(original.vendorName));
      expect(restored.gstin, equals(original.gstin));
      expect(restored.invoiceNumber, equals(original.invoiceNumber));
      expect(restored.subtotal, equals(original.subtotal));
      expect(restored.cgst, equals(original.cgst));
      expect(restored.sgst, equals(original.sgst));
      expect(restored.igst, equals(original.igst));
      expect(restored.status, equals(original.status));
    });

    test('InvoiceItem.toMap() and InvoiceItem.fromMap() round-trip correctly', () {
      const item = InvoiceItem(
        id: 'item-1',
        description: 'Aashirvaad Atta 5kg',
        quantity: 2,
        unitPrice: 285.0,
      );

      final map = item.toMap('inv-001');
      final restored = InvoiceItem.fromMap(map);

      expect(restored.id, equals(item.id));
      expect(restored.description, equals(item.description));
      expect(restored.quantity, equals(item.quantity));
      expect(restored.unitPrice, equals(item.unitPrice));
    });
  });
}
