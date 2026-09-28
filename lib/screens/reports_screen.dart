import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/invoice.dart';
import '../services/database/database_helper.dart';
import '../services/export/file_export_helper.dart';
import '../services/reports/invoice_report_service.dart';
import '../widgets/metric_card.dart';
import '../widgets/charts/monthly_count_chart.dart';
import '../widgets/charts/monthly_value_chart.dart';
import '../widgets/charts/tax_breakdown_chart.dart';
import '../widgets/charts/taxable_vs_total_chart.dart';

class ReportsScreen extends StatefulWidget {
  final InvoiceReportService reportService;
  final FileExportHelper exportHelper;

  const ReportsScreen({
    super.key,
    this.reportService = const InvoiceReportService(),
    this.exportHelper = const FileExportHelper(),
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<Invoice> _invoices = [];
  DateTimeRange? _selectedDateRange;
  InvoiceReportStatistics _stats = InvoiceReportStatistics.empty();
  VisualReportData _visualData = VisualReportData.empty();
  bool _isExporting = false;
  String _activePreset = 'All Time';

  @override
  void initState() {
    super.initState();
    _loadReportData();
  }

  Future<void> _loadReportData() async {
    try {
      final invoices = await DatabaseHelper.instance.searchInvoices(
        startDate: _selectedDateRange?.start,
        endDate: _selectedDateRange?.end,
      );

      if (mounted) {
        setState(() {
          _invoices = invoices;
          _stats = widget.reportService.calculateStatistics(invoices);
          _visualData = widget.reportService.generateVisualReportData(invoices);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading report data: $e'),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _applyPreset(String preset) {
    final now = DateTime.now();
    DateTimeRange? range;

    switch (preset) {
      case 'This Month':
        range = DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
        );
        break;
      case 'Last 30 Days':
        range = DateTimeRange(
          start: now.subtract(const Duration(days: 30)),
          end: now,
        );
        break;
      case 'All Time':
      default:
        range = null;
        break;
    }

    setState(() {
      _activePreset = preset;
      _selectedDateRange = range;
    });
    _loadReportData();
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _selectedDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 30)),
            end: DateTime.now(),
          ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0F172A),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _activePreset = 'Custom';
        _selectedDateRange = picked;
      });
      _loadReportData();
    }
  }

  String _generateTimestamp() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _exportCsv() async {
    if (_invoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No invoices to export for the selected date range.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final csvContent = widget.reportService.generateCsv(_invoices);
      final fileName = 'TaxInvoices_${_generateTimestamp()}.csv';

      final result = await widget.exportHelper.exportString(
        content: csvContent,
        fileName: fileName,
        mimeType: 'text/csv',
        shareSubject: 'Tax Invoices CSV Report ($fileName)',
      );

      if (mounted) {
        setState(() => _isExporting = false);
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Exported: $fileName'),
              backgroundColor: const Color(0xFF059669),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? 'Export failed'),
              backgroundColor: Colors.red[800],
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CSV Export error: $e'),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _exportExcel() async {
    if (_invoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No invoices to export for the selected date range.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final bytes = widget.reportService.generateExcel(_invoices);
      final fileName = 'TaxInvoices_${_generateTimestamp()}.xlsx';

      final result = await widget.exportHelper.exportBytes(
        bytes: Uint8List.fromList(bytes),
        fileName: fileName,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        shareSubject: 'Tax Invoices Excel Report ($fileName)',
      );

      if (mounted) {
        setState(() => _isExporting = false);
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Exported: $fileName'),
              backgroundColor: const Color(0xFF059669),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? 'Export failed'),
              backgroundColor: Colors.red[800],
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Excel Export error: $e'),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_invoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No invoices to export for the selected date range.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final pdfBytes = await widget.reportService.generatePdf(
        _invoices,
        dateRange: _selectedDateRange,
      );
      final fileName = 'TaxInvoices_Report_${_generateTimestamp()}.pdf';

      final result = await widget.exportHelper.exportBytes(
        bytes: pdfBytes,
        fileName: fileName,
        mimeType: 'application/pdf',
        shareSubject: 'Tax Invoices PDF Report ($fileName)',
      );

      if (mounted) {
        setState(() => _isExporting = false);
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Exported: $fileName'),
              backgroundColor: const Color(0xFF059669),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? 'Export failed'),
              backgroundColor: Colors.red[800],
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF Export error: $e'),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text(
          'Visual Reports & Charts',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Color(0xFF0F172A),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded, size: 14, color: Color(0xFF059669)),
                  SizedBox(width: 4),
                  Text(
                    'Offline Analytics',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF059669),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Filter Section
            Text(
              'Date Range Filter',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F172A),
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 10),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildPresetChip('All Time'),
                  const SizedBox(width: 8),
                  _buildPresetChip('This Month'),
                  const SizedBox(width: 8),
                  _buildPresetChip('Last 30 Days'),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: Icon(
                      Icons.calendar_month_outlined,
                      size: 16,
                      color: _activePreset == 'Custom'
                          ? Colors.white
                          : const Color(0xFF2563EB),
                    ),
                    label: Text(
                      _activePreset == 'Custom' && _selectedDateRange != null
                          ? '${_selectedDateRange!.start.day}/${_selectedDateRange!.start.month} - ${_selectedDateRange!.end.day}/${_selectedDateRange!.end.month}'
                          : 'Custom Date',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _activePreset == 'Custom'
                            ? Colors.white
                            : const Color(0xFF1E40AF),
                      ),
                    ),
                    backgroundColor: _activePreset == 'Custom'
                        ? const Color(0xFF2563EB)
                        : const Color(0xFFDBEAFE),
                    onPressed: _pickCustomDateRange,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Summary Cards Overview (4 Required KPI Cards)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Summary Metrics',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                    letterSpacing: 0.2,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_stats.invoiceCount} invoices',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Card Grid Row 1: Number of Invoices & Taxable Value
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    title: 'Number of Invoices',
                    value: '${_stats.invoiceCount}',
                    subtitle: 'Total Count',
                    icon: Icons.receipt_long_outlined,
                    accentColor: const Color(0xFF0284C7),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricCard(
                    title: 'Taxable Value',
                    value: _stats.formattedTaxable,
                    subtitle: 'Base Subtotal',
                    icon: Icons.account_balance_wallet_outlined,
                    accentColor: const Color(0xFF059669),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Card Grid Row 2: Total Tax & Grand Total
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    title: 'Total Tax',
                    value: _stats.formattedTax,
                    subtitle: 'CGST + SGST + IGST',
                    icon: Icons.pie_chart_outline_rounded,
                    accentColor: const Color(0xFF7C3AED),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricCard(
                    title: 'Grand Total',
                    value: _stats.formattedGrandTotal,
                    subtitle: 'Taxable + Total Tax',
                    icon: Icons.savings_outlined,
                    accentColor: const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // Visual Charts Section
            Text(
              'Visual Reports & Charts',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F172A),
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 12),

            if (_invoices.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.insert_chart_outlined_rounded,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No Invoice Data Available',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'No invoice records found for the selected date range. Scan or import invoices to view visual analytics.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              // Chart 1: Monthly Invoice Count
              MonthlyCountChart(points: _visualData.monthlyPoints),
              const SizedBox(height: 16),

              // Chart 2: Monthly Total Invoice Value
              MonthlyValueChart(points: _visualData.monthlyPoints),
              const SizedBox(height: 16),

              // Chart 3: CGST vs SGST vs IGST Breakdown
              TaxBreakdownChart(data: _visualData),
              const SizedBox(height: 16),

              // Chart 4: Taxable Value vs Total Invoice Value
              TaxableVsTotalChart(data: _visualData),
            ],

            const SizedBox(height: 28),

            // Export Actions Section
            Text(
              'Export Invoices & Reports',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F172A),
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Generate offline reports and share or save directly to device storage.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),

            if (_isExporting)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(
                        'Generating and preparing export file...',
                        style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              )
            else
              Column(
                children: [
                  _buildExportButton(
                    title: 'Export CSV Format (.csv)',
                    subtitle: 'Comma-separated values for spreadsheet software',
                    icon: Icons.table_chart_outlined,
                    color: const Color(0xFF0284C7),
                    onTap: _exportCsv,
                  ),
                  const SizedBox(height: 10),
                  _buildExportButton(
                    title: 'Export Excel Spreadsheet (.xlsx)',
                    subtitle: 'Native Excel workbook with formatted headers & totals',
                    icon: Icons.grid_on_rounded,
                    color: const Color(0xFF059669),
                    onTap: _exportExcel,
                  ),
                  const SizedBox(height: 10),
                  _buildExportButton(
                    title: 'Generate PDF Report (.pdf)',
                    subtitle: 'Printable invoice register with summary cards & tables',
                    icon: Icons.picture_as_pdf_outlined,
                    color: const Color(0xFFDC2626),
                    onTap: _exportPdf,
                  ),
                ],
              ),

            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(String preset) {
    final isSelected = _activePreset == preset;
    return ChoiceChip(
      label: Text(preset),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? Colors.white : const Color(0xFF475569),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF0F172A),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
      ),
      onSelected: (selected) {
        if (selected) {
          _applyPreset(preset);
        }
      },
    );
  }

  Widget _buildExportButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final hasData = _invoices.isNotEmpty;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: hasData ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: hasData
                            ? const Color(0xFF0F172A)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: hasData ? const Color(0xFF94A3B8) : const Color(0xFFCBD5E1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
