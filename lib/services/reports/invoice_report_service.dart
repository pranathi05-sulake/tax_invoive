import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../models/invoice.dart';

class InvoiceReportStatistics {
  final int invoiceCount;
  final double totalTaxableAmount;
  final double totalCgst;
  final double totalSgst;
  final double totalIgst;
  final double totalTax;
  final double grandTotal;

  const InvoiceReportStatistics({
    required this.invoiceCount,
    required this.totalTaxableAmount,
    required this.totalCgst,
    required this.totalSgst,
    required this.totalIgst,
    required this.totalTax,
    required this.grandTotal,
  });

  factory InvoiceReportStatistics.empty() {
    return const InvoiceReportStatistics(
      invoiceCount: 0,
      totalTaxableAmount: 0.0,
      totalCgst: 0.0,
      totalSgst: 0.0,
      totalIgst: 0.0,
      totalTax: 0.0,
      grandTotal: 0.0,
    );
  }

  String get formattedTaxable => '₹${totalTaxableAmount.toStringAsFixed(2)}';
  String get formattedCgst => '₹${totalCgst.toStringAsFixed(2)}';
  String get formattedSgst => '₹${totalSgst.toStringAsFixed(2)}';
  String get formattedIgst => '₹${totalIgst.toStringAsFixed(2)}';
  String get formattedTax => '₹${totalTax.toStringAsFixed(2)}';
  String get formattedGrandTotal => '₹${grandTotal.toStringAsFixed(2)}';
}

class MonthlyReportPoint {
  final String monthKey;
  final String label;
  final int count;
  final double totalAmount;
  final double taxableAmount;
  final double taxAmount;

  const MonthlyReportPoint({
    required this.monthKey,
    required this.label,
    required this.count,
    required this.totalAmount,
    required this.taxableAmount,
    required this.taxAmount,
  });

  String get formattedTotal => '₹${totalAmount.toStringAsFixed(2)}';
  String get formattedTaxable => '₹${taxableAmount.toStringAsFixed(2)}';
  String get formattedTax => '₹${taxAmount.toStringAsFixed(2)}';
}

class VisualReportData {
  final InvoiceReportStatistics stats;
  final List<MonthlyReportPoint> monthlyPoints;
  final double cgstPercentage;
  final double sgstPercentage;
  final double igstPercentage;
  final double taxablePercentage;
  final double taxPercentage;

  const VisualReportData({
    required this.stats,
    required this.monthlyPoints,
    required this.cgstPercentage,
    required this.sgstPercentage,
    required this.igstPercentage,
    required this.taxablePercentage,
    required this.taxPercentage,
  });

  factory VisualReportData.empty() {
    return VisualReportData(
      stats: InvoiceReportStatistics.empty(),
      monthlyPoints: const [],
      cgstPercentage: 0.0,
      sgstPercentage: 0.0,
      igstPercentage: 0.0,
      taxablePercentage: 0.0,
      taxPercentage: 0.0,
    );
  }
}

class InvoiceReportService {
  const InvoiceReportService();

  InvoiceReportStatistics calculateStatistics(List<Invoice> invoices) {
    if (invoices.isEmpty) {
      return InvoiceReportStatistics.empty();
    }

    double taxable = 0.0;
    double cgst = 0.0;
    double sgst = 0.0;
    double igst = 0.0;
    double totalTax = 0.0;
    double grandTotal = 0.0;

    for (final inv in invoices) {
      taxable += inv.subtotal;
      cgst += inv.cgst;
      sgst += inv.sgst;
      igst += inv.igst;
      totalTax += inv.taxAmount;
      grandTotal += inv.totalAmount;
    }

    return InvoiceReportStatistics(
      invoiceCount: invoices.length,
      totalTaxableAmount: taxable,
      totalCgst: cgst,
      totalSgst: sgst,
      totalIgst: igst,
      totalTax: totalTax,
      grandTotal: grandTotal,
    );
  }

  VisualReportData generateVisualReportData(List<Invoice> invoices) {
    if (invoices.isEmpty) {
      return VisualReportData.empty();
    }

    final stats = calculateStatistics(invoices);

    final Map<String, List<Invoice>> monthGroups = {};
    for (final inv in invoices) {
      final monthKey =
          '${inv.date.year}-${inv.date.month.toString().padLeft(2, '0')}';
      monthGroups.putIfAbsent(monthKey, () => []).add(inv);
    }

    final sortedKeys = monthGroups.keys.toList()..sort();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];

    final List<MonthlyReportPoint> points = [];
    for (final key in sortedKeys) {
      final group = monthGroups[key]!;
      final year = key.split('-')[0];
      final monthNum = int.parse(key.split('-')[1]);
      final label = '${months[monthNum - 1]} $year';

      double groupTotal = 0.0;
      double groupTaxable = 0.0;
      double groupTax = 0.0;
      for (final inv in group) {
        groupTotal += inv.totalAmount;
        groupTaxable += inv.subtotal;
        groupTax += inv.taxAmount;
      }

      points.add(
        MonthlyReportPoint(
          monthKey: key,
          label: label,
          count: group.length,
          totalAmount: groupTotal,
          taxableAmount: groupTaxable,
          taxAmount: groupTax,
        ),
      );
    }

    double cgstPct = 0.0;
    double sgstPct = 0.0;
    double igstPct = 0.0;
    if (stats.totalTax > 0) {
      cgstPct = (stats.totalCgst / stats.totalTax) * 100.0;
      sgstPct = (stats.totalSgst / stats.totalTax) * 100.0;
      igstPct = (stats.totalIgst / stats.totalTax) * 100.0;
    }

    double taxablePct = 0.0;
    double taxPct = 0.0;
    if (stats.grandTotal > 0) {
      taxablePct = (stats.totalTaxableAmount / stats.grandTotal) * 100.0;
      taxPct = (stats.totalTax / stats.grandTotal) * 100.0;
    }

    return VisualReportData(
      stats: stats,
      monthlyPoints: points,
      cgstPercentage: cgstPct,
      sgstPercentage: sgstPct,
      igstPercentage: igstPct,
      taxablePercentage: taxablePct,
      taxPercentage: taxPct,
    );
  }

  String generateCsv(List<Invoice> invoices) {
    final List<List<dynamic>> rows = [];

    // Header row
    rows.add([
      'Supplier/Vendor Name',
      'GSTIN',
      'Invoice Number',
      'Invoice Date',
      'HSN/SAC',
      'Taxable Value (INR)',
      'CGST (INR)',
      'SGST (INR)',
      'IGST (INR)',
      'Total Tax (INR)',
      'Grand Total (INR)',
      'Status',
    ]);

    for (final inv in invoices) {
      final dateStr =
          '${inv.date.year}-${inv.date.month.toString().padLeft(2, '0')}-${inv.date.day.toString().padLeft(2, '0')}';

      rows.add([
        inv.vendorName.isNotEmpty ? inv.vendorName : 'Not detected',
        inv.gstin.isNotEmpty ? inv.gstin : 'Not detected',
        inv.invoiceNumber.isNotEmpty ? inv.invoiceNumber : 'Not detected',
        dateStr,
        '', // HSN/SAC empty if undetected
        inv.subtotal.toStringAsFixed(2),
        inv.cgst.toStringAsFixed(2),
        inv.sgst.toStringAsFixed(2),
        inv.igst.toStringAsFixed(2),
        inv.taxAmount.toStringAsFixed(2),
        inv.totalAmount.toStringAsFixed(2),
        inv.status.name.toUpperCase(),
      ]);
    }

    const converter = ListToCsvConverter();
    return converter.convert(rows);
  }

  List<int> generateExcel(List<Invoice> invoices) {
    final excel = Excel.createExcel();
    const sheetName = 'Tax_Invoices_Report';
    excel.rename('Sheet1', sheetName);
    final sheet = excel[sheetName];

    final headers = [
      'Supplier/Vendor Name',
      'GSTIN',
      'Invoice Number',
      'Invoice Date',
      'HSN/SAC',
      'Taxable Value (INR)',
      'CGST (INR)',
      'SGST (INR)',
      'IGST (INR)',
      'Total Tax (INR)',
      'Grand Total (INR)',
      'Status',
    ];

    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    double totalTaxable = 0.0;
    double totalCgst = 0.0;
    double totalSgst = 0.0;
    double totalIgst = 0.0;
    double totalTax = 0.0;
    double totalGrand = 0.0;

    for (final inv in invoices) {
      final dateStr =
          '${inv.date.year}-${inv.date.month.toString().padLeft(2, '0')}-${inv.date.day.toString().padLeft(2, '0')}';

      totalTaxable += inv.subtotal;
      totalCgst += inv.cgst;
      totalSgst += inv.sgst;
      totalIgst += inv.igst;
      totalTax += inv.taxAmount;
      totalGrand += inv.totalAmount;

      sheet.appendRow([
        TextCellValue(inv.vendorName.isNotEmpty ? inv.vendorName : 'Not detected'),
        TextCellValue(inv.gstin.isNotEmpty ? inv.gstin : 'Not detected'),
        TextCellValue(inv.invoiceNumber.isNotEmpty ? inv.invoiceNumber : 'Not detected'),
        TextCellValue(dateStr),
        TextCellValue(''),
        DoubleCellValue(inv.subtotal),
        DoubleCellValue(inv.cgst),
        DoubleCellValue(inv.sgst),
        DoubleCellValue(inv.igst),
        DoubleCellValue(inv.taxAmount),
        DoubleCellValue(inv.totalAmount),
        TextCellValue(inv.status.name.toUpperCase()),
      ]);
    }

    // Totals row
    if (invoices.isNotEmpty) {
      sheet.appendRow([
        TextCellValue('TOTAL'),
        TextCellValue(''),
        TextCellValue('${invoices.length} invoices'),
        TextCellValue(''),
        TextCellValue(''),
        DoubleCellValue(totalTaxable),
        DoubleCellValue(totalCgst),
        DoubleCellValue(totalSgst),
        DoubleCellValue(totalIgst),
        DoubleCellValue(totalTax),
        DoubleCellValue(totalGrand),
        TextCellValue(''),
      ]);
    }

    return excel.encode() ?? [];
  }

  Future<Uint8List> generatePdf(
    List<Invoice> invoices, {
    DateTimeRange? dateRange,
  }) async {
    final stats = calculateStatistics(invoices);
    final pdf = pw.Document();

    String dateRangeText = 'All Time';
    if (dateRange != null) {
      dateRangeText =
          '${dateRange.start.day}/${dateRange.start.month}/${dateRange.start.year} - ${dateRange.end.day}/${dateRange.end.month}/${dateRange.end.year}';
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'TaxInvoice AI - Tax Report',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blueGrey900,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        '100% Offline Local Mobile Report | Generated: ${DateTime.now().toIso8601String().substring(0, 10)}',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text(
                      'Date Range: $dateRangeText',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blueGrey800,
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(color: PdfColors.grey300, thickness: 1),
              pw.SizedBox(height: 6),
            ],
          );
        },
        footer: (context) {
          return pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Confidential Tax Document - Stored locally on device',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ],
          );
        },
        build: (context) {
          return [
            // KPI Summary Cards
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _buildPdfStatItem('Invoices', '${stats.invoiceCount}'),
                  _buildPdfStatItem('Taxable Value', 'Rs. ${stats.totalTaxableAmount.toStringAsFixed(2)}'),
                  _buildPdfStatItem('CGST', 'Rs. ${stats.totalCgst.toStringAsFixed(2)}'),
                  _buildPdfStatItem('SGST', 'Rs. ${stats.totalSgst.toStringAsFixed(2)}'),
                  _buildPdfStatItem('IGST', 'Rs. ${stats.totalIgst.toStringAsFixed(2)}'),
                  _buildPdfStatItem('Total Tax', 'Rs. ${stats.totalTax.toStringAsFixed(2)}'),
                  _buildPdfStatItem('Grand Total', 'Rs. ${stats.grandTotal.toStringAsFixed(2)}', isBold: true),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // Invoices Data Table
            if (invoices.isEmpty)
              pw.Center(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.all(20),
                  child: pw.Text(
                    'No invoice records found for the selected period.',
                    style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
                  ),
                ),
              )
            else
              pw.TableHelper.fromTextArray(
                headers: [
                  '#',
                  'Date',
                  'Vendor Name',
                  'GSTIN',
                  'Invoice #',
                  'Taxable (Rs.)',
                  'CGST (Rs.)',
                  'SGST (Rs.)',
                  'IGST (Rs.)',
                  'Total Tax (Rs.)',
                  'Grand Total (Rs.)',
                ],
                data: List<List<dynamic>>.generate(invoices.length, (index) {
                  final inv = invoices[index];
                  final dateStr =
                      '${inv.date.year}-${inv.date.month.toString().padLeft(2, '0')}-${inv.date.day.toString().padLeft(2, '0')}';
                  return [
                    '${index + 1}',
                    dateStr,
                    inv.vendorName.isNotEmpty ? inv.vendorName : '-',
                    inv.gstin.isNotEmpty ? inv.gstin : '-',
                    inv.invoiceNumber.isNotEmpty ? inv.invoiceNumber : '-',
                    inv.subtotal.toStringAsFixed(2),
                    inv.cgst.toStringAsFixed(2),
                    inv.sgst.toStringAsFixed(2),
                    inv.igst.toStringAsFixed(2),
                    inv.taxAmount.toStringAsFixed(2),
                    inv.totalAmount.toStringAsFixed(2),
                  ];
                }),
                headerStyle: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF0F172A),
                ),
                cellStyle: const pw.TextStyle(fontSize: 7.5),
                cellAlignment: pw.Alignment.centerLeft,
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.center,
                  5: pw.Alignment.centerRight,
                  6: pw.Alignment.centerRight,
                  7: pw.Alignment.centerRight,
                  8: pw.Alignment.centerRight,
                  9: pw.Alignment.centerRight,
                  10: pw.Alignment.centerRight,
                },
                rowDecoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5)),
                ),
              ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildPdfStatItem(String label, String value, {bool isBold = false}) {
    return pw.Column(
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: PdfColors.blueGrey900,
          ),
        ),
      ],
    );
  }
}
