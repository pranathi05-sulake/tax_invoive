import 'package:flutter/material.dart';
import '../services/database/database_helper.dart';

class RpaWorkflowHistoryScreen extends StatefulWidget {
  final DatabaseHelper? databaseHelper;

  const RpaWorkflowHistoryScreen({
    super.key,
    this.databaseHelper,
  });

  @override
  State<RpaWorkflowHistoryScreen> createState() => _RpaWorkflowHistoryScreenState();
}

class _RpaWorkflowHistoryScreenState extends State<RpaWorkflowHistoryScreen> {
  DatabaseHelper get _db => widget.databaseHelper ?? DatabaseHelper.instance;
  List<WorkflowLogEntry> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    try {
      final logs = await _db.getWorkflowLogs(limit: 200);
      if (mounted) {
        setState(() {
          _logs = logs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading workflow logs: $e'),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _clearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Workflow Logs?'),
        content: const Text('This will delete all local RPA execution logs from database.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _db.clearWorkflowLogs();
      _loadLogs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text(
          'Workflow Execution Logs',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Color(0xFF0F172A),
          ),
        ),
        actions: [
          if (_logs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              tooltip: 'Clear Logs',
              onPressed: _clearLogs,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.assignment_outlined, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      const Text(
                        'No Workflow Logs Found',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Process an invoice using RPA Workflow Engine to generate execution logs.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _logs.length,
                  separatorBuilder: (ctx, idx) => const SizedBox(height: 8),
                  itemBuilder: (ctx, idx) {
                    final log = _logs[idx];
                    return _buildLogTile(log);
                  },
                ),
    );
  }

  Widget _buildLogTile(WorkflowLogEntry log) {
    Color statusColor;
    IconData icon;

    switch (log.status) {
      case 'completed':
        statusColor = const Color(0xFF059669);
        icon = Icons.check_circle_outline_rounded;
        break;
      case 'needsReview':
        statusColor = const Color(0xFFD97706);
        icon = Icons.warning_amber_rounded;
        break;
      case 'duplicate':
        statusColor = const Color(0xFF7C3AED);
        icon = Icons.copy_rounded;
        break;
      case 'failed':
        statusColor = const Color(0xFFDC2626);
        icon = Icons.error_outline_rounded;
        break;
      case 'cancelled':
        statusColor = const Color(0xFF64748B);
        icon = Icons.cancel_outlined;
        break;
      default:
        statusColor = const Color(0xFF0284C7);
        icon = Icons.sync_rounded;
        break;
    }

    final dateStr =
        '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')} (${log.timestamp.day}/${log.timestamp.month}/${log.timestamp.year})';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: statusColor),
                  const SizedBox(width: 6),
                  Text(
                    log.step.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
              Text(
                dateStr,
                style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            log.message,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Execution ID: ${log.executionId}',
            style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}
