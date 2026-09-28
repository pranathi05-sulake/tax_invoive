import 'package:flutter/material.dart';
import '../../services/reports/invoice_report_service.dart';

class TaxableVsTotalChart extends StatelessWidget {
  final VisualReportData data;

  const TaxableVsTotalChart({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final stats = data.stats;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.compare_arrows_rounded,
                  size: 20, color: Color(0xFF0F172A)),
              SizedBox(width: 8),
              Text(
                'Taxable Value vs Total Invoice Value',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildComparisonRow(
            label: 'Taxable Subtotal',
            amount: stats.formattedTaxable,
            percentage: '${data.taxablePercentage.toStringAsFixed(1)}%',
            color: const Color(0xFF059669),
            fraction: data.taxablePercentage / 100.0,
          ),
          const SizedBox(height: 12),
          _buildComparisonRow(
            label: 'Total Tax Amount',
            amount: stats.formattedTax,
            percentage: '${data.taxPercentage.toStringAsFixed(1)}%',
            color: const Color(0xFF7C3AED),
            fraction: data.taxPercentage / 100.0,
          ),
          const SizedBox(height: 12),
          _buildComparisonRow(
            label: 'Grand Total Value',
            amount: stats.formattedGrandTotal,
            percentage: '100.0%',
            color: const Color(0xFF0F172A),
            fraction: 1.0,
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonRow({
    required String label,
    required String amount,
    required String percentage,
    required Color color,
    required double fraction,
  }) {
    final clampedFraction = fraction.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  amount,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '($percentage)',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: clampedFraction,
            minHeight: 8,
            backgroundColor: const Color(0xFFF1F5F9),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
