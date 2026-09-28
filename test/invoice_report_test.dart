import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tax_invoice_app/models/invoice.dart';
import 'package:tax_invoice_app/screens/reports_screen.dart';
import 'package:tax_invoice_app/services/database/database_helper.dart';
import 'package:tax_invoice_app/services/export/file_export_helper.dart';
import 'package:tax_invoice_app/services/reports/invoice_report_service.dart';
import 'package:tax_invoice_app/widgets/charts/monthly_count_chart.dart';
import 'package:tax_invoice_app/widgets/charts/monthly_value_chart.dart';
import 'package:tax_invoice_app/widgets/charts/tax_breakdown_chart.dart';
import 'package:tax_invoice_app/widgets/charts/taxable_vs_total_chart.dart';

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

  @override
  Future<ExportResult> exportBytes({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    String? shareSubject,
  }) async {
    lastExportedBytes = bytes;
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
        description: 'Test Item for $vendorName',
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

  const reportService = InvoiceReportService();

  group('InvoiceReportService Calculation Unit Tests', () {
    test('calculateStatistics returns all zeros on empty invoice list', () {
      final stats = reportService.calculateStatistics([]);
      expect(stats.invoiceCount, 0);
      expect(stats.totalTaxableAmount, 0.0);
      expect(stats.totalCgst, 0.0);
      expect(stats.totalSgst, 0.0);
      expect(stats.totalIgst, 0.0);
      expect(stats.totalTax, 0.0);
      expect(stats.grandTotal, 0.0);
      expect(stats.formattedTaxable, '₹0.00');
      expect(stats.formattedGrandTotal, '₹0.00');
    });

    test('calculateStatistics sums taxable, taxes, and grand total correctly for multiple invoices', () {
      final invoices = [
        makeTestInvoice(
          id: '1',
          vendorName: 'Vendor A',
          invoiceNumber: 'INV-1',
          date: DateTime(2026, 3, 1),
          subtotal: 1000.0,
          cgst: 90.0,
          sgst: 90.0,
          igst: 0.0,
        ),
        makeTestInvoice(
          id: '2',
          vendorName: 'Vendor B',
          invoiceNumber: 'INV-2',
          date: DateTime(2026, 3, 2),
          subtotal: 2500.0,
          cgst: 0.0,
          sgst: 0.0,
          igst: 450.0,
        ),
      ];

      final stats = reportService.calculateStatistics(invoices);
      expect(stats.invoiceCount, 2);
      expect(stats.totalTaxableAmount, 3500.0);
      expect(stats.totalCgst, 90.0);
      expect(stats.totalSgst, 90.0);
      expect(stats.totalIgst, 450.0);
      expect(stats.totalTax, 630.0);
      expect(stats.grandTotal, 4130.0);
      expect(stats.formattedTaxable, '₹3500.00');
      expect(stats.formattedCgst, '₹90.00');
      expect(stats.formattedSgst, '₹90.00');
      expect(stats.formattedIgst, '₹450.00');
      expect(stats.formattedTax, '₹630.00');
      expect(stats.formattedGrandTotal, '₹4130.00');
    });
  });

  group('Visual Reports & Charts Aggregation Unit Tests', () {
    test('generateVisualReportData returns empty VisualReportData for empty invoice list', () {
      final visual = reportService.generateVisualReportData([]);
      expect(visual.stats.invoiceCount, 0);
      expect(visual.monthlyPoints, isEmpty);
      expect(visual.cgstPercentage, 0.0);
      expect(visual.sgstPercentage, 0.0);
      expect(visual.igstPercentage, 0.0);
      expect(visual.taxablePercentage, 0.0);
    });

    test('generateVisualReportData correctly groups across multiple months and computes tax ratios', () {
      final invoices = [
        makeTestInvoice(
          id: '1',
          vendorName: 'Jan Vendor',
          invoiceNumber: 'INV-JAN-1',
          date: DateTime(2026, 1, 15),
          subtotal: 1000.0,
          cgst: 90.0,
          sgst: 90.0,
          igst: 0.0,
        ),
        makeTestInvoice(
          id: '2',
          vendorName: 'Jan Vendor 2',
          invoiceNumber: 'INV-JAN-2',
          date: DateTime(2026, 1, 20),
          subtotal: 2000.0,
          cgst: 180.0,
          sgst: 180.0,
          igst: 0.0,
        ),
        makeTestInvoice(
          id: '3',
          vendorName: 'Feb Vendor',
          invoiceNumber: 'INV-FEB-1',
          date: DateTime(2026, 2, 10),
          subtotal: 5000.0,
          cgst: 0.0,
          sgst: 0.0,
          igst: 900.0,
        ),
      ];

      final visual = reportService.generateVisualReportData(invoices);
      expect(visual.stats.invoiceCount, 3);
      expect(visual.monthlyPoints.length, 2);

      // January point
      final jan = visual.monthlyPoints.firstWhere((p) => p.monthKey == '2026-01');
      expect(jan.label, 'Jan 2026');
      expect(jan.count, 2);
      expect(jan.taxableAmount, 3000.0);
      expect(jan.taxAmount, 540.0);
      expect(jan.totalAmount, 3540.0);

      // February point
      final feb = visual.monthlyPoints.firstWhere((p) => p.monthKey == '2026-02');
      expect(feb.label, 'Feb 2026');
      expect(feb.count, 1);
      expect(feb.taxableAmount, 5000.0);
      expect(feb.taxAmount, 900.0);
      expect(feb.totalAmount, 5900.0);

      // Tax Percentages (Total tax = 540 + 900 = 1440. CGST = 270, SGST = 270, IGST = 900)
      expect(visual.cgstPercentage, closeTo(18.75, 0.01));
      expect(visual.sgstPercentage, closeTo(18.75, 0.01));
      expect(visual.igstPercentage, closeTo(62.5, 0.01));
    });

    test('generateVisualReportData safely handles zero tax values without throwing division by zero', () {
      final invoices = [
        makeTestInvoice(
          id: '1',
          vendorName: 'Zero Tax Vendor',
          invoiceNumber: 'INV-000',
          date: DateTime(2026, 3, 1),
          subtotal: 500.0,
          cgst: 0.0,
          sgst: 0.0,
          igst: 0.0,
        ),
      ];

      final visual = reportService.generateVisualReportData(invoices);
      expect(visual.stats.totalTax, 0.0);
      expect(visual.cgstPercentage, 0.0);
      expect(visual.sgstPercentage, 0.0);
      expect(visual.igstPercentage, 0.0);
      expect(visual.taxablePercentage, 100.0);
      expect(visual.taxPercentage, 0.0);
    });
  });

  group('InvoiceReportService CSV Export Unit Tests', () {
    test('generateCsv outputs RFC-compliant CSV with header and records', () {
      final invoices = [
        makeTestInvoice(
          id: '1',
          vendorName: 'A & B Retail, LLC',
          invoiceNumber: 'INV/2026/001',
          date: DateTime(2026, 3, 15),
          subtotal: 500.0,
          cgst: 25.0,
          sgst: 25.0,
          igst: 0.0,
          gstin: '29ABCDE1234F1Z5',
        ),
        makeTestInvoice(
          id: '2',
          vendorName: '',
          invoiceNumber: '',
          date: DateTime(2026, 3, 16),
          subtotal: 100.0,
          cgst: 0.0,
          sgst: 0.0,
          igst: 18.0,
          gstin: '',
        ),
      ];

      final csv = reportService.generateCsv(invoices);
      expect(csv.contains('Supplier/Vendor Name'), isTrue);
      expect(csv.contains('GSTIN'), isTrue);
      expect(csv.contains('Taxable Value (INR)'), isTrue);
      expect(csv.contains('"A & B Retail, LLC"'), isTrue);
      expect(csv.contains('29ABCDE1234F1Z5'), isTrue);
      expect(csv.contains('INV/2026/001'), isTrue);
      expect(csv.contains('500.00'), isTrue);
      expect(csv.contains('Not detected'), isTrue);
    });
  });

  group('InvoiceReportService Excel Export Unit Tests', () {
    test('generateExcel produces valid .xlsx binary workbook', () {
      final invoices = [
        makeTestInvoice(
          id: '1',
          vendorName: 'Reliance Digital',
          invoiceNumber: 'RD-101',
          date: DateTime(2026, 3, 10),
          subtotal: 1200.0,
          cgst: 108.0,
          sgst: 108.0,
        ),
      ];

      final bytes = reportService.generateExcel(invoices);
      expect(bytes.isNotEmpty, isTrue);

      final excel = Excel.decodeBytes(bytes);
      expect(excel.tables.containsKey('Tax_Invoices_Report'), isTrue);
      final sheet = excel.tables['Tax_Invoices_Report']!;
      expect(sheet.maxRows >= 2, isTrue);
    });
  });

  group('InvoiceReportService PDF Export Unit Tests', () {
    test('generatePdf produces valid PDF byte buffer starting with PDF magic bytes', () async {
      final invoices = [
        makeTestInvoice(
          id: '1',
          vendorName: 'Tata Motors',
          invoiceNumber: 'TM-999',
          date: DateTime(2026, 3, 5),
          subtotal: 50000.0,
          cgst: 4500.0,
          sgst: 4500.0,
        ),
      ];

      final pdfBytes = await reportService.generatePdf(
        invoices,
        dateRange: DateTimeRange(
          start: DateTime(2026, 3, 1),
          end: DateTime(2026, 3, 31),
        ),
      );

      expect(pdfBytes.isNotEmpty, isTrue);
      expect(pdfBytes[0], 0x25); // %
      expect(pdfBytes[1], 0x50); // P
      expect(pdfBytes[2], 0x44); // D
      expect(pdfBytes[3], 0x46); // F
      expect(pdfBytes[4], 0x2D); // -
    });
  });

  group('ReportsScreen & Visual Charts Widget Tests', () {
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

    testWidgets('ReportsScreen renders summary metric cards and empty state on empty database', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await resetDb(tester);

      await tester.pumpWidget(const MaterialApp(home: ReportsScreen()));
      await settleScreen(tester);

      expect(find.text('Visual Reports & Charts'), findsWidgets);
      expect(find.text('Summary Metrics'), findsOneWidget);
      expect(find.text('Number of Invoices'), findsOneWidget);
      expect(find.text('Taxable Value'), findsOneWidget);
      expect(find.text('Total Tax'), findsOneWidget);
      expect(find.text('Grand Total'), findsOneWidget);
      expect(find.text('No Invoice Data Available'), findsOneWidget);
    });

    testWidgets('ReportsScreen renders visual charts when SQLite invoices exist', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await resetDb(tester);

      await tester.runAsync(() async {
        await DatabaseHelper.instance.insertInvoice(
          makeTestInvoice(
            id: '1',
            vendorName: 'Acme Supermarket',
            invoiceNumber: 'ACME-01',
            date: DateTime(2026, 3, 10),
            subtotal: 1000.0,
            cgst: 90.0,
            sgst: 90.0,
            igst: 0.0,
          ),
        );
      });

      await tester.pumpWidget(const MaterialApp(home: ReportsScreen()));
      await settleScreen(tester);

      expect(find.byType(MonthlyCountChart), findsOneWidget);
      expect(find.byType(MonthlyValueChart), findsOneWidget);
      expect(find.byType(TaxBreakdownChart), findsOneWidget);
      expect(find.byType(TaxableVsTotalChart), findsOneWidget);

      expect(find.text('Monthly Invoice Count'), findsOneWidget);
      expect(find.text('Monthly Total Invoice Value'), findsOneWidget);
      expect(find.text('CGST vs SGST vs IGST Breakdown'), findsOneWidget);
      expect(find.text('Taxable Value vs Total Invoice Value'), findsOneWidget);
    });

    testWidgets('ReportsScreen date range preset chip filtering updates data', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await resetDb(tester);

      final oldDate = DateTime(2020, 1, 1);
      final currentDate = DateTime.now();

      await tester.runAsync(() async {
        await DatabaseHelper.instance.insertInvoice(
          makeTestInvoice(
            id: 'old-inv',
            vendorName: 'Old Vendor',
            invoiceNumber: 'OLD-01',
            date: oldDate,
            subtotal: 5000.0,
          ),
        );
        await DatabaseHelper.instance.insertInvoice(
          makeTestInvoice(
            id: 'recent-inv',
            vendorName: 'Recent Vendor',
            invoiceNumber: 'REC-01',
            date: currentDate,
            subtotal: 1500.0,
          ),
        );
      });

      await tester.pumpWidget(const MaterialApp(home: ReportsScreen()));
      await settleScreen(tester);

      // All Time should see 2 invoices
      expect(find.text('2 invoices'), findsWidgets);

      // Tap 'This Month' chip
      await tester.tap(find.text('This Month'));
      await settleScreen(tester);

      // Should filter to 1 invoice for current month
      expect(find.text('1 invoices'), findsWidgets);
    });

    testWidgets('ReportsScreen triggers CSV, Excel, and PDF exports with fake helper', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await resetDb(tester);

      final fakeExport = FakeExportHelper(shouldSucceed: true);

      await tester.runAsync(() async {
        await DatabaseHelper.instance.insertInvoice(
          makeTestInvoice(
            id: '1',
            vendorName: 'Infosys BPM',
            invoiceNumber: 'INF-100',
            date: DateTime(2026, 3, 10),
            subtotal: 2000.0,
            cgst: 180.0,
            sgst: 180.0,
          ),
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ReportsScreen(
            exportHelper: fakeExport,
          ),
        ),
      );
      await settleScreen(tester);

      // Export CSV
      await tester.ensureVisible(find.text('Export CSV Format (.csv)'));
      await tester.tap(find.text('Export CSV Format (.csv)'));
      await settleScreen(tester);

      expect(fakeExport.lastFileName?.endsWith('.csv'), isTrue);
      expect(fakeExport.lastExportedString?.contains('Infosys BPM'), isTrue);

      // Export Excel
      await tester.ensureVisible(find.text('Export Excel Spreadsheet (.xlsx)'));
      await tester.tap(find.text('Export Excel Spreadsheet (.xlsx)'));
      await settleScreen(tester);

      expect(fakeExport.lastFileName?.endsWith('.xlsx'), isTrue);
      expect(fakeExport.lastExportedBytes?.isNotEmpty, isTrue);

      // Export PDF
      await tester.ensureVisible(find.text('Generate PDF Report (.pdf)'));
      await tester.tap(find.text('Generate PDF Report (.pdf)'));
      await settleScreen(tester);

      expect(fakeExport.lastFileName?.endsWith('.pdf'), isTrue);
      expect(fakeExport.lastExportedBytes?[0], 0x25); // %PDF-
    });
  });
}
