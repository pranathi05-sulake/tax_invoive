import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/invoice.dart';
import '../services/workflow/rpa_workflow_engine.dart';
import '../services/workflow/rpa_workflow_models.dart';
import 'rpa_workflow_history_screen.dart';

class RpaWorkflowScreen extends StatefulWidget {
  final RpaWorkflowEngine? workflowEngine;

  const RpaWorkflowScreen({
    super.key,
    this.workflowEngine,
  });

  @override
  State<RpaWorkflowScreen> createState() => _RpaWorkflowScreenState();
}

class _DefaultEngine extends RpaWorkflowEngine {
  _DefaultEngine();
}

class _RpaWorkflowScreenState extends State<RpaWorkflowScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedFile;
  RpaWorkflowExecution? _activeExecution;
  bool _isCancelled = false;

  RpaWorkflowEngine get _engine => widget.workflowEngine ?? RpaWorkflowEngine();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? photo = await _picker.pickImage(source: source);
      if (photo != null) {
        setState(() {
          _selectedFile = File(photo.path);
          _activeExecution = null;
          _isCancelled = false;
        });
        _startWorkflow();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting image: $e'),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _startWorkflow() async {
    if (_selectedFile == null) return;

    setState(() {
      _isCancelled = false;
    });

    final execution = await _engine.executeWorkflow(
      _selectedFile!,
      onExecutionUpdated: () {
        if (mounted) setState(() {});
      },
      isCancelled: () => _isCancelled,
    );

    if (mounted) {
      setState(() {
        _activeExecution = execution;
      });
    }
  }

  void _cancelWorkflow() {
    setState(() {
      _isCancelled = true;
    });
    if (_activeExecution != null) {
      _engine.cancelWorkflow(
        _activeExecution!,
        onExecutionUpdated: () {
          if (mounted) setState(() {});
        },
      );
    }
  }

  Future<void> _approveAndSave() async {
    if (_activeExecution?.extractedInvoice == null) return;

    final execution = await _engine.approveAndSaveInvoice(
      _activeExecution!,
      onExecutionUpdated: () {
        if (mounted) setState(() {});
      },
    );

    if (mounted) {
      setState(() {
        _activeExecution = execution;
      });

      if (execution.status == RpaWorkflowStatus.completed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invoice saved successfully to SQLite!'),
            backgroundColor: Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (execution.status == RpaWorkflowStatus.duplicate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Duplicate invoice skipped.'),
            backgroundColor: Color(0xFF7C3AED),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _openReviewModal() {
    if (_activeExecution?.extractedInvoice == null) return;

    final invoice = _activeExecution!.extractedInvoice!;
    final vendorController = TextEditingController(text: invoice.vendorName);
    final gstinController = TextEditingController(text: invoice.gstin);
    final invNumController = TextEditingController(text: invoice.invoiceNumber);
    final subtotalController = TextEditingController(text: invoice.subtotal.toString());
    final cgstController = TextEditingController(text: invoice.cgst.toString());
    final sgstController = TextEditingController(text: invoice.sgst.toString());
    final igstController = TextEditingController(text: invoice.igst.toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Review Extracted Invoice',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: vendorController,
                  decoration: const InputDecoration(labelText: 'Vendor Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: gstinController,
                  decoration: const InputDecoration(labelText: 'GSTIN', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: invNumController,
                  decoration: const InputDecoration(labelText: 'Invoice Number', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: subtotalController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Subtotal (₹)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: cgstController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'CGST (₹)', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: sgstController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'SGST (₹)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: igstController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'IGST (₹)', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      final updated = invoice.copyWith(
                        vendorName: vendorController.text.trim(),
                        gstin: gstinController.text.trim(),
                        invoiceNumber: invNumController.text.trim(),
                        subtotal: double.tryParse(subtotalController.text) ?? invoice.subtotal,
                        cgst: double.tryParse(cgstController.text) ?? invoice.cgst,
                        sgst: double.tryParse(sgstController.text) ?? invoice.sgst,
                        igst: double.tryParse(igstController.text) ?? invoice.igst,
                      );
                      setState(() {
                        _activeExecution!.extractedInvoice = updated;
                        _activeExecution!.isReviewed = true;
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Save Edits & Confirm'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final execution = _activeExecution;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text(
          'RPA Workflow Automation Engine',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: Color(0xFF0F172A),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, color: Color(0xFF0F172A)),
            tooltip: 'Workflow Logs',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RpaWorkflowHistoryScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Process Invoice Action Header Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.precision_manufacturing_rounded, size: 22, color: Color(0xFF0284C7)),
                      SizedBox(width: 8),
                      Text(
                        'Automated Pipeline Launcher',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Select or capture an invoice to execute full offline OCR, rule parsing, validation, duplicate check, and save steps.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.camera_alt_outlined, size: 18),
                          label: const Text('Capture Camera'),
                          onPressed: () => _pickImage(ImageSource.camera),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0F172A),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          icon: const Icon(Icons.photo_library_outlined, size: 18),
                          label: const Text('Pick Gallery'),
                          onPressed: () => _pickImage(ImageSource.gallery),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            if (execution != null) ...[
              // Live Workflow Execution Card
              _buildExecutionCard(execution),
              const SizedBox(height: 16),

              // Step Checklist Timeline
              _buildStepChecklist(execution),
              const SizedBox(height: 20),

              // Action buttons based on state
              if (execution.status == RpaWorkflowStatus.needsReview) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD97706),
                          side: const BorderSide(color: Color(0xFFFCD34D)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.edit_note_rounded),
                        label: const Text('Review & Edit Fields'),
                        onPressed: _openReviewModal,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: const Text('Approve & Save'),
                        onPressed: _approveAndSave,
                      ),
                    ),
                  ],
                ),
              ] else if (execution.status == RpaWorkflowStatus.processing) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red[700],
                      side: BorderSide(color: Colors.red[300]!),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel Workflow Execution'),
                    onPressed: _cancelWorkflow,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExecutionCard(RpaWorkflowExecution execution) {
    Color statusColor;
    String statusText;

    switch (execution.status) {
      case RpaWorkflowStatus.completed:
        statusColor = const Color(0xFF059669);
        statusText = 'Completed & Saved';
        break;
      case RpaWorkflowStatus.needsReview:
        statusColor = const Color(0xFFD97706);
        statusText = 'Needs User Review';
        break;
      case RpaWorkflowStatus.duplicate:
        statusColor = const Color(0xFF7C3AED);
        statusText = 'Duplicate Detected';
        break;
      case RpaWorkflowStatus.failed:
        statusColor = const Color(0xFFDC2626);
        statusText = 'Workflow Failed';
        break;
      case RpaWorkflowStatus.cancelled:
        statusColor = const Color(0xFF64748B);
        statusText = 'Cancelled';
        break;
      case RpaWorkflowStatus.processing:
      default:
        statusColor = const Color(0xFF0284C7);
        statusText = 'Processing...';
        break;
    }

    final totalSteps = RpaWorkflowStep.values.length;
    final progressRatio = (execution.completedStepsCount / totalSteps).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Execution ID: ${execution.id}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progressRatio,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            backgroundColor: const Color(0xFFF1F5F9),
            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
          ),
          if (execution.errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              execution.errorMessage!,
              style: TextStyle(fontSize: 12, color: Colors.red[800], fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepChecklist(RpaWorkflowExecution execution) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Workflow Execution Checklist',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 12),
          ...RpaWorkflowStep.values.map((step) {
            final isCurrent = execution.currentStep == step;
            final isPast = step.index < execution.currentStep.index || execution.status == RpaWorkflowStatus.completed;

            String symbol = '○';
            Color symbolColor = const Color(0xFF94A3B8);

            if (isPast) {
              symbol = '✓';
              symbolColor = const Color(0xFF059669);
            } else if (isCurrent) {
              if (execution.status == RpaWorkflowStatus.needsReview) {
                symbol = '⚠';
                symbolColor = const Color(0xFFD97706);
              } else if (execution.status == RpaWorkflowStatus.failed) {
                symbol = '✗';
                symbolColor = const Color(0xFFDC2626);
              } else if (execution.status == RpaWorkflowStatus.duplicate) {
                symbol = '⎘';
                symbolColor = const Color(0xFF7C3AED);
              } else {
                symbol = '→';
                symbolColor = const Color(0xFF0284C7);
              }
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      symbol,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: symbolColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    step.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                      color: isCurrent ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
