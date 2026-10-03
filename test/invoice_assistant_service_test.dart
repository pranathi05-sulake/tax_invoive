import 'package:flutter_test/flutter_test.dart';
import 'package:tax_invoice_app/models/invoice.dart';
import 'package:tax_invoice_app/services/assistant/invoice_assistant_service.dart';

void main() {
  group('InvoiceAssistantService Tests', () {
    final sampleInvoice = Invoice(
      id: 'inv-101',
      vendorName: 'AERO TURBINE SPARES LTD',
      gstin: '29ABCDE1234F1Z5',
      invoiceNumber: 'INV001',
      date: DateTime(2026, 9, 20),
      subtotal: 10000.0,
      cgst: 900.0,
      sgst: 900.0,
      igst: 0.0,
      status: InvoiceStatus.verified,
      syncStatus: SyncStatus.synced,
      syncAttempts: 1,
      syncedAt: DateTime(2026, 9, 21, 14, 30),
      verifiedBy: 'Inspector Smith',
      verifiedAt: DateTime(2026, 9, 20, 16, 0),
      items: const [
        InvoiceItem(
          id: 'item-1',
          description: 'Turbine Blade Seal',
          quantity: 2,
          unitPrice: 5000.0,
          hsnSac: '84119100',
        ),
      ],
    );

    final missingDataInvoice = Invoice(
      id: 'inv-102',
      vendorName: '',
      gstin: '',
      invoiceNumber: '',
      date: DateTime(2026, 9, 20),
      subtotal: 0.0,
      cgst: 0.0,
      sgst: 0.0,
      igst: 0.0,
      status: InvoiceStatus.pending,
      syncStatus: SyncStatus.syncFailed,
      lastSyncError: 'Connection refused',
      items: const [],
    );

    // 1. Invoice Number
    test('1. What is the invoice number', () {
      final res = InvoiceAssistantService.processQuery(
        'What is the invoice number?',
        invoice: sampleInvoice,
      );
      expect(res, equals('Invoice number: INV001'));
    });

    // 2. GSTIN
    test('2. What is the GSTIN', () {
      final res = InvoiceAssistantService.processQuery(
        'What is the GSTIN?',
        invoice: sampleInvoice,
      );
      expect(res, equals('GSTIN: 29ABCDE1234F1Z5'));
    });

    // 3. Vendor
    test('3. What is the vendor name', () {
      final res = InvoiceAssistantService.processQuery(
        'What is the vendor name?',
        invoice: sampleInvoice,
      );
      expect(res, equals('Vendor name: AERO TURBINE SPARES LTD'));
    });

    // 4. Total Amount
    test('4. What is the total amount', () {
      final res = InvoiceAssistantService.processQuery(
        'What is the total amount?',
        invoice: sampleInvoice,
      );
      expect(res, contains('Total amount: ₹11800.00'));
    });

    // 5. CGST / SGST / IGST
    test('5. CGST, SGST, IGST queries', () {
      final cgstRes = InvoiceAssistantService.processQuery('What is the CGST?', invoice: sampleInvoice);
      expect(cgstRes, contains('CGST: ₹900.00'));

      final sgstRes = InvoiceAssistantService.processQuery('What is the SGST?', invoice: sampleInvoice);
      expect(sgstRes, contains('SGST: ₹900.00'));

      final igstRes = InvoiceAssistantService.processQuery('What is the IGST?', invoice: sampleInvoice);
      expect(igstRes, contains('IGST: ₹0.00'));
    });

    // 6. Item count & list
    test('6. Item count and items summary', () {
      final countRes = InvoiceAssistantService.processQuery(
        'How many items are in this invoice?',
        invoice: sampleInvoice,
      );
      expect(countRes, equals('This invoice contains 1 item(s).'));

      final itemsRes = InvoiceAssistantService.processQuery('Show the items', invoice: sampleInvoice);
      expect(itemsRes, contains('Turbine Blade Seal'));
      expect(itemsRes, contains('84119100'));
    });

    // 7. Validation status
    test('7. Validation status query', () {
      final res = InvoiceAssistantService.processQuery(
        'Is this invoice valid?',
        invoice: sampleInvoice,
      );
      expect(res, contains('Yes, this invoice is valid'));
    });

    // 8. Missing fields
    test('8. Missing fields query', () {
      final res = InvoiceAssistantService.processQuery(
        'Are there any missing fields?',
        invoice: sampleInvoice,
      );
      expect(res, equals('No critical fields are missing.'));
    });

    // 9. Sync status & sync error
    test('9. Sync status query', () {
      final res = InvoiceAssistantService.processQuery(
        'What is the sync status?',
        invoice: sampleInvoice,
      );
      expect(res, contains('Sync status: SYNCED'));

      final errRes = InvoiceAssistantService.processQuery(
        'Why did sync fail?',
        invoice: missingDataInvoice,
      );
      expect(errRes, equals('Sync error: Connection refused'));
    });

    // 10. Unknown question (Out of bounds)
    test('10. Unknown or external question', () {
      final res = InvoiceAssistantService.processQuery(
        'What is the weather in Bengaluru?',
        invoice: sampleInvoice,
      );
      expect(res, equals('This information is not available in the current invoice data.'));
    });

    // 11. No invoice selected
    test('11. No invoice selected', () {
      final res = InvoiceAssistantService.processQuery(
        'What is the invoice number?',
        invoice: null,
      );
      expect(res, equals('Please select an invoice first so I can answer questions about it.'));
    });

    // 12. Invoice with missing data
    test('12. Invoice with missing data', () {
      final invNumRes = InvoiceAssistantService.processQuery(
        'What is the invoice number?',
        invoice: missingDataInvoice,
      );
      expect(invNumRes, equals('Invoice number is not available in the current invoice data.'));

      final gstinRes = InvoiceAssistantService.processQuery(
        'What is the GSTIN?',
        invoice: missingDataInvoice,
      );
      expect(gstinRes, equals('GSTIN is not available in the current invoice data.'));

      final missingFieldsRes = InvoiceAssistantService.processQuery(
        'Are there any missing fields?',
        invoice: missingDataInvoice,
      );
      expect(missingFieldsRes, contains('Vendor Name'));
      expect(missingFieldsRes, contains('Invoice Number'));
      expect(missingFieldsRes, contains('GSTIN'));
      expect(missingFieldsRes, contains('Line Items'));
    });
  });
}
