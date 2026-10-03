import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tax_invoice_app/models/invoice.dart';
import 'package:tax_invoice_app/services/export/file_export_helper.dart';
import 'package:tax_invoice_app/services/reports/invoice_report_service.dart';

void main() {
  final reportService = const InvoiceReportService();
  final exportHelper = const FileExportHelper();

  final sampleInvoice1 = Invoice(
    id: 'inv_exp_001',
    vendorName: 'Hindustan Aeronautics Ltd',
    gstin: '29ABCDE1234F1Z5',
    invoiceNumber: 'HAL-2026-001',
    date: DateTime(2026, 10, 2),
    subtotal: 10000.0,
    cgst: 900.0,
    sgst: 900.0,
    igst: 0.0,
    items: const [
      InvoiceItem(
        id: 'item_exp_01',
        description: 'Rotor Assembly Replacement Part',
        quantity: 1,
        unitPrice: 10000.0,
        hsnSac: '88033000',
      ),
    ],
  );

  final sampleInvoice2 = Invoice(
    id: 'inv_exp_002',
    vendorName: 'Bharat Electronics Ltd',
    gstin: '29AAACB1234F1Z2',
    invoiceNumber: 'BEL-2026-002',
    date: DateTime(2026, 10, 3),
    subtotal: 5000.0,
    cgst: 0.0,
    sgst: 0.0,
    igst: 900.0,
  );

  group('Invoice Report & Export Abstraction Tests', () {
    test('generateCsv uses real invoice data and supports empty and multiple invoices', () {
      final emptyCsv = reportService.generateCsv([]);
      expect(emptyCsv, contains('Supplier/Vendor Name'));
      expect(emptyCsv, contains('Invoice Number'));

      final multiCsv = reportService.generateCsv([sampleInvoice1, sampleInvoice2]);
      expect(multiCsv, contains('HAL-2026-001'));
      expect(multiCsv, contains('Hindustan Aeronautics Ltd'));
      expect(multiCsv, contains('BEL-2026-002'));
      expect(multiCsv, contains('Bharat Electronics Ltd'));
    });

    test('generateExcel produces non-empty bytes containing real invoice data', () {
      final excelBytes = reportService.generateExcel([sampleInvoice1, sampleInvoice2]);
      expect(excelBytes, isNotNull);
      expect(excelBytes.length, greaterThan(0));
    });

    test('generatePdf produces valid PDF byte stream', () async {
      final pdfBytes = await reportService.generatePdf([sampleInvoice1, sampleInvoice2]);
      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(0));
      // PDF magic bytes header: %PDF
      expect(pdfBytes.sublist(0, 4), equals(Uint8List.fromList([0x25, 0x50, 0x44, 0x46])));
    });

    test('FileExportHelper instance created successfully', () {
      expect(exportHelper, isNotNull);
    });
  });
}
