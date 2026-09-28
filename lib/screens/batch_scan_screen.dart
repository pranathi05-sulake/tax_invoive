import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/invoice.dart';
import '../services/database/database_helper.dart';
import '../services/ocr/batch_scan_service.dart';
import '../services/ocr/ocr_engine.dart';
import '../services/validation/invoice_validator.dart';

class BatchScanScreen extends StatefulWidget {
  final List<File>? initialImageFiles;
  final BatchScanService? batchScanService;
  final DatabaseHelper? databaseHelper;

  const BatchScanScreen({
    super.key,
    this.initialImageFiles,
    this.batchScanService,
    this.databaseHelper,
  });

  @override
  State<BatchScanScreen> createState() => _BatchScanScreenState();
}

class _BatchScanScreenState extends State<BatchScanScreen> {
  final ImagePicker _picker = ImagePicker();
  late final BatchScanService _batchService;
  final List<BatchInvoiceItem> _items = [];

  bool _isProcessing = false;
  bool _cancelRequested = false;
  int _currentIndex = 0;
  int _totalBatchCount = 0;

  DatabaseHelper get _db => widget.databaseHelper ?? DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _batchService = widget.batchScanService ??
        BatchScanService(
          databaseHelper: _db,
        );

    if (widget.initialImageFiles != null && widget.initialImageFiles!.isNotEmpty) {
      for (final file in widget.initialImageFiles!) {
        _items.add(BatchInvoiceItem(
          id: 'batch-${DateTime.now().microsecondsSinceEpoch}-${_items.length + 1}',
          imageFile: file,
        ));
      }
      _startBatchProcessing();
    }
  }

  Future<void> _pickGalleryImages() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage(
        imageQuality: 100,
      );

      if (pickedFiles.isNotEmpty && mounted) {
        setState(() {
          for (final file in pickedFiles) {
            _items.add(BatchInvoiceItem(
              id: 'batch-${DateTime.now().microsecondsSinceEpoch}-${_items.length + 1}',
              imageFile: File(file.path),
            ));
          }
        });
        _startBatchProcessing();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking images from gallery: $e'),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _captureCameraPhoto() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );

      if (pickedFile != null && mounted) {
        setState(() {
          _items.add(BatchInvoiceItem(
            id: 'batch-${DateTime.now().microsecondsSinceEpoch}-${_items.length + 1}',
            imageFile: File(pickedFile.path),
          ));
        });
        _startBatchProcessing();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error capturing photo from camera: $e'),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _startBatchProcessing() {
    if (_isProcessing) return;

    final pending = _items.where((i) => i.status == BatchItemStatus.pending).toList();
    if (pending.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _cancelRequested = false;
      _currentIndex = 0;
      _totalBatchCount = pending.length;
    });

    _batchService.processBatchItems(
      _items,
      isCancelled: () => _cancelRequested,
      onProgress: (current, total) {
        if (mounted) {
          setState(() {
            _currentIndex = current;
            _totalBatchCount = total;
          });
        }
      },
      onItemUpdated: () {
        if (mounted) {
          setState(() {});
        }
      },
    ).then((_) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    });
  }

  void _cancelProcessing() {
    setState(() {
      _cancelRequested = true;
      _isProcessing = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Batch processing cancelled safely.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  int get _readyCount => _items.where((i) => i.status == BatchItemStatus.ready).length;
  int get _needsReviewCount => _items.where((i) => i.status == BatchItemStatus.needsReview).length;
  int get _duplicateCount => _items.where((i) => i.status == BatchItemStatus.duplicate).length;
  int get _failedCount => _items.where((i) => i.status == BatchItemStatus.ocrFailed).length;
  int get _savedCount => _items.where((i) => i.status == BatchItemStatus.saved).length;

  Future<void> _saveAllReadyInvoices() async {
    final readyItems = _items
        .where((i) =>
            i.status == BatchItemStatus.ready ||
            (i.isReviewed && i.status == BatchItemStatus.needsReview))
        .toList();

    if (readyItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No ready or reviewed invoices to save.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final summary = await _batchService.saveBatchInvoices(readyItems);
    setState(() {});

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Color(0xFF059669), size: 24),
              SizedBox(width: 8),
              Text('Batch Save Complete', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Successfully saved ${summary.savedCount} invoices to SQLite database.'),
              if (summary.skippedDuplicateCount > 0) ...[
                const SizedBox(height: 8),
                Text('${summary.skippedDuplicateCount} duplicates skipped.',
                    style: const TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w600)),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _openReviewModal(BatchInvoiceItem item) {
    if (item.extractedInvoice == null) {
      // Re-create a default invoice from scratch if OCR failed but user wants to manually enter
      item.extractedInvoice = Invoice(
        id: item.id,
        vendorName: '',
        invoiceNumber: '',
        date: DateTime.now(),
        subtotal: 0.0,
      );
    }

    final inv = item.extractedInvoice!;
    final vendorController = TextEditingController(text: inv.vendorName);
    final gstinController = TextEditingController(text: inv.gstin);
    final invoiceNoController = TextEditingController(text: inv.invoiceNumber);
    final subtotalController = TextEditingController(text: inv.subtotal.toStringAsFixed(2));
    final cgstController = TextEditingController(text: inv.cgst.toStringAsFixed(2));
    final sgstController = TextEditingController(text: inv.sgst.toStringAsFixed(2));
    final igstController = TextEditingController(text: inv.igst.toStringAsFixed(2));
    DateTime selectedDate = inv.date;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(modalCtx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.edit_note_rounded, color: Color(0xFF2563EB), size: 24),
                        const SizedBox(width: 8),
                        const Text(
                          'Review Extracted Invoice',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (item.validationWarnings.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFCD34D)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: item.validationWarnings
                              .map((w) => Text('• $w', style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))))
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    TextField(
                      controller: vendorController,
                      decoration: const InputDecoration(labelText: 'Vendor / Supplier Name *'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: gstinController,
                      decoration: const InputDecoration(labelText: 'GSTIN (15-digit)'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: invoiceNoController,
                      decoration: const InputDecoration(labelText: 'Invoice Number *'),
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: subtotalController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Subtotal (Taxable)'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: cgstController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'CGST'),
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
                            decoration: const InputDecoration(labelText: 'SGST'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: igstController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'IGST'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(modalCtx).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final updatedInv = Invoice(
                                id: inv.id,
                                vendorName: vendorController.text.trim(),
                                gstin: gstinController.text.trim().toUpperCase(),
                                invoiceNumber: invoiceNoController.text.trim(),
                                date: selectedDate,
                                subtotal: double.tryParse(subtotalController.text) ?? 0.0,
                                cgst: double.tryParse(cgstController.text) ?? 0.0,
                                sgst: double.tryParse(sgstController.text) ?? 0.0,
                                igst: double.tryParse(igstController.text) ?? 0.0,
                                items: inv.items,
                                status: InvoiceStatus.verified,
                              );

                              item.extractedInvoice = updatedInv;
                              item.isReviewed = true;
                              item.status = BatchItemStatus.ready;

                              Navigator.of(modalCtx).pop();
                              setState(() {});
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Save Changes'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Batch Invoice Scanning',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Color(0xFF0F172A)),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Add Gallery Images',
            onPressed: _isProcessing ? null : _pickGalleryImages,
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: 'Capture Camera Photo',
            onPressed: _isProcessing ? null : _captureCameraPhoto,
          ),
        ],
      ),
      body: Column(
        children: [
          // Offline Banner & Progress Header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isProcessing) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Processing $_currentIndex of $_totalBatchCount invoices...',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2563EB)),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                        label: const Text('Cancel', style: TextStyle(color: Colors.red, fontSize: 12)),
                        onPressed: _cancelProcessing,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: _totalBatchCount > 0 ? _currentIndex / _totalBatchCount : 0,
                    backgroundColor: const Color(0xFFEFF6FF),
                    color: const Color(0xFF2563EB),
                  ),
                  const SizedBox(height: 12),
                ],

                // Status Count Pills
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildCountBadge('Total', '${_items.length}', const Color(0xFF0F172A)),
                      const SizedBox(width: 8),
                      _buildCountBadge('Ready', '$_readyCount', const Color(0xFF059669)),
                      const SizedBox(width: 8),
                      _buildCountBadge('Review', '$_needsReviewCount', const Color(0xFFD97706)),
                      const SizedBox(width: 8),
                      _buildCountBadge('Duplicate', '$_duplicateCount', const Color(0xFF7C3AED)),
                      const SizedBox(width: 8),
                      _buildCountBadge('Failed', '$_failedCount', const Color(0xFFDC2626)),
                      const SizedBox(width: 8),
                      _buildCountBadge('Saved', '$_savedCount', const Color(0xFF0284C7)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Batch Items List
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.collections_outlined, size: 56, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          const Text(
                            'No invoices added to batch',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Select multiple invoice images from gallery or capture with camera.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                icon: const Icon(Icons.photo_library_outlined, size: 18),
                                label: const Text('Pick Gallery'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _pickGalleryImages,
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                                label: const Text('Camera'),
                                onPressed: _captureCameraPhoto,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return _buildBatchItemCard(item, index);
                    },
                  ),
          ),

          // Bottom Action Footer
          if (_items.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                      label: const Text('Add More'),
                      onPressed: _isProcessing ? null : _pickGalleryImages,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: Text('Save Ready (${_readyCount + _needsReviewCount})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _readyCount + _needsReviewCount > 0 ? _saveAllReadyInvoices : null,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCountBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildBatchItemCard(BatchInvoiceItem item, int index) {
    final inv = item.extractedInvoice;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Image Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 54,
              height: 54,
              child: Image.file(
                item.imageFile,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, stack) => Container(
                  color: const Color(0xFFF1F5F9),
                  child: const Icon(Icons.image_not_supported, size: 24, color: Colors.grey),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Invoice Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inv != null && inv.vendorName.isNotEmpty
                      ? inv.vendorName
                      : 'Invoice #${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  inv != null
                      ? '${inv.invoiceNumber.isNotEmpty ? inv.invoiceNumber : "No invoice #"} • ${inv.formattedTotal}'
                      : 'Awaiting OCR processing',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 6),
                _buildStatusPill(item.status),
              ],
            ),
          ),

          // Action Buttons
          Column(
            children: [
              IconButton(
                icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF2563EB)),
                tooltip: 'Review & Edit',
                onPressed: () => _openReviewModal(item),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF94A3B8), size: 20),
                tooltip: 'Remove',
                onPressed: () {
                  setState(() {
                    _items.removeAt(index);
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(BatchItemStatus status) {
    switch (status) {
      case BatchItemStatus.processing:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 6),
            Text('Processing...', style: TextStyle(fontSize: 11, color: Color(0xFF2563EB))),
          ],
        );
      case BatchItemStatus.ready:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
          child: const Text('Ready to Save', style: TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.bold)),
        );
      case BatchItemStatus.needsReview:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(8)),
          child: const Text('Needs Review', style: TextStyle(fontSize: 11, color: Color(0xFFD97706), fontWeight: FontWeight.bold)),
        );
      case BatchItemStatus.duplicate:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFFF3E8FF), borderRadius: BorderRadius.circular(8)),
          child: const Text('Duplicate', style: TextStyle(fontSize: 11, color: Color(0xFF7C3AED), fontWeight: FontWeight.bold)),
        );
      case BatchItemStatus.ocrFailed:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(8)),
          child: const Text('OCR Failed', style: TextStyle(fontSize: 11, color: Color(0xFFDC2626), fontWeight: FontWeight.bold)),
        );
      case BatchItemStatus.saved:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(8)),
          child: const Text('Saved', style: TextStyle(fontSize: 11, color: Color(0xFF0284C7), fontWeight: FontWeight.bold)),
        );
      case BatchItemStatus.pending:
      default:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
          child: const Text('In Queue', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        );
    }
  }
}
