import 'package:flutter_test/flutter_test.dart';
import 'package:tax_invoice_app/services/ocr/tax_invoice_parser.dart';
import 'package:tax_invoice_app/models/invoice.dart';

void main() {
  group('TaxInvoiceParserService Offline Unit Tests', () {
    final parser = TaxInvoiceParserService();

    test('Parses GSTIN, Vendor, Date, and Amounts correctly from Indian retail tax invoice OCR text', () {
      const sampleOcrText = '''
SUPERMART GROCERY STORES LTD
GSTIN: 29AAACB1234C1Z5
TAX INVOICE
Invoice No: INV/2026/09941
Date: 15-09-2026

Item Description      Qty    Amount
1  Aashirvaad Atta 5kg  1    285.00
2  Amul Butter 500g     1    275.00

CGST (9%): Rs. 25.20
SGST (9%): Rs. 25.20
SUBTOTAL: Rs. 560.00
GRAND TOTAL: Rs. 610.40
THANK YOU FOR SHOPPING!
''';

      final result = parser.parse(sampleOcrText);

      expect(result.gstin, equals('29AAACB1234C1Z5'));
      expect(result.vendorName, contains('SUPERMART GROCERY STORES'));
      expect(result.invoiceNumber, equals('INV/2026/09941'));
      expect(result.date, equals(DateTime(2026, 9, 15)));
      expect(result.cgst, equals(25.20));
      expect(result.sgst, equals(25.20));
      expect(result.totalAmount, equals(610.40));
      expect(result.subtotal, equals(560.00));

      final invoice = result.toInvoice();
      expect(invoice.status, equals(InvoiceStatus.verified));
      expect(invoice.gstin, equals('29AAACB1234C1Z5'));
    });

    test('Handles missing GSTIN gracefully by setting pending status', () {
      const sampleOcrText = '''
LOCAL CORNER KIRANA STORE
Bill No: 8812
Date: 10/09/2026

Rice 1kg  75.00
Sugar 1kg  45.00

TOTAL: 120.00
''';

      final result = parser.parse(sampleOcrText);

      expect(result.gstin, isEmpty);
      expect(result.vendorName, contains('LOCAL CORNER KIRANA STORE'));
      expect(result.totalAmount, equals(120.00));

      final invoice = result.toInvoice();
      expect(invoice.status, equals(InvoiceStatus.pending));
    });

    test('Returns empty strings for undetected fields instead of invented fallbacks', () {
      const sampleOcrText = '''
TOTAL: 100.00
''';
      final result = parser.parse(sampleOcrText);
      final invoice = result.toInvoice();

      expect(invoice.vendorName, isEmpty);
      expect(invoice.invoiceNumber, isEmpty);
      expect(invoice.gstin, isEmpty);
      expect(invoice.totalAmount, equals(100.00));
    });

    test('Calculates Levenshtein edit distance for string accuracy evaluation', () {
      final dist1 = levenshteinDistance('29AAACB1234C1Z5', '29AAACB1234C1Z5');
      final dist2 = levenshteinDistance('29AAACB1234C1Z5', '29AAACB1234C1Z6');

      expect(dist1, equals(0));
      expect(dist2, equals(1));
    });
  });
}

/// Helper function to compute Levenshtein distance for CER/WER evaluation.
int levenshteinDistance(String s1, String s2) {
  if (s1 == s2) return 0;
  if (s1.isEmpty) return s2.length;
  if (s2.isEmpty) return s1.length;

  List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
  List<int> v1 = List<int>.filled(s2.length + 1, 0);

  for (int i = 0; i < s1.length; i++) {
    v1[0] = i + 1;
    for (int j = 0; j < s2.length; j++) {
      int cost = (s1.codeUnitAt(i) == s2.codeUnitAt(j)) ? 0 : 1;
      v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost].reduce((a, b) => a < b ? a : b);
    }
    for (int j = 0; j <= s2.length; j++) {
      v0[j] = v1[j];
    }
  }
  return v1[s2.length];
}
