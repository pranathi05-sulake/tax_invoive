import 'dart:math';
import 'package:flutter/material.dart';
import '../../services/reports/invoice_report_service.dart';

class TaxBreakdownChart extends StatelessWidget {
  final VisualReportData data;

  const TaxBreakdownChart({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final stats = data.stats;
    final totalTax = stats.totalTax;

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.pie_chart_outline_rounded,
                      size: 20, color: Color(0xFF7C3AED)),
                  SizedBox(width: 8),
                  Text(
                    'CGST vs SGST vs IGST Breakdown',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Text(
                'Total: ${stats.formattedTax}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Color(0xFF7C3AED),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Multi-color segmented progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 16,
              child: totalTax <= 0
                  ? Container(color: const Color(0xFFE2E8F0))
                  : Row(
                      children: [
                        if (data.cgstPercentage > 0)
                          Expanded(
                            flex: max(1, (data.cgstPercentage * 10).round()),
                            child: Container(color: const Color(0xFF0284C7)),
                          ),
                        if (data.sgstPercentage > 0)
                          Expanded(
                            flex: max(1, (data.sgstPercentage * 10).round()),
                            child: Container(color: const Color(0xFF059669)),
                          ),
                        if (data.igstPercentage > 0)
                          Expanded(
                            flex: max(1, (data.igstPercentage * 10).round()),
                            child: Container(color: const Color(0xFFD97706)),
                          ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _buildTaxItem(
                  'CGST',
                  stats.formattedCgst,
                  '${data.cgstPercentage.toStringAsFixed(1)}%',
                  const Color(0xFF0284C7),
                ),
              ),
              Expanded(
                child: _buildTaxItem(
                  'SGST',
                  stats.formattedSgst,
                  '${data.sgstPercentage.toStringAsFixed(1)}%',
                  const Color(0xFF059669),
                ),
              ),
              Expanded(
                child: _buildTaxItem(
                  'IGST',
                  stats.formattedIgst,
                  '${data.igstPercentage.toStringAsFixed(1)}%',
                  const Color(0xFFD97706),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaxItem(
      String title, String amount, String percentage, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            percentage,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}
