import 'dart:io';
import 'package:flutter/material.dart';
import '../services/ocr/ocr_engine.dart';
import 'ocr_results_screen.dart';

class InvoicePreviewScreen extends StatefulWidget {
  final File imageFile;
  final OcrEngine? ocrEngine;
  final VoidCallback? onProcessInvoice;

  const InvoicePreviewScreen({
    super.key,
    required this.imageFile,
    this.ocrEngine,
    this.onProcessInvoice,
  });

  @override
  State<InvoicePreviewScreen> createState() => _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends State<InvoicePreviewScreen> {
  bool _isProcessing = false;

  String get _fileName => widget.imageFile.path.split(Platform.pathSeparator).last;

  String get _fileSizeFormatted {
    try {
      final bytes = widget.imageFile.lengthSync();
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } catch (_) {
      return 'Image file';
    }
  }

  Future<void> _processInvoiceOcr() async {
    if (_isProcessing) return;

    if (!widget.imageFile.existsSync()) {
      debugPrint('[OCR] Error: Image file does not exist at path: ${widget.imageFile.path}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: Image file not found. Path: ${widget.imageFile.path}'),
          backgroundColor: Colors.red[800],
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    debugPrint('[OCR] Starting OCR processing for image: ${widget.imageFile.path}');

    final engine = widget.ocrEngine ?? MlKitOcrEngine();

    try {
      final OcrResult result = await engine.processImageFile(widget.imageFile);
      debugPrint('[OCR] OCR processing successful. Extracted ${result.lines.length} lines.');

      if (widget.ocrEngine == null) {
        await engine.dispose();
      }

      if (!mounted) return;

      setState(() {
        _isProcessing = false;
      });

      if (widget.onProcessInvoice != null) {
        widget.onProcessInvoice!();
      }

      // Navigate to OCR Results Screen displaying the recognized text
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => OcrResultsScreen(
            imageFile: widget.imageFile,
            ocrResult: result,
          ),
        ),
      );
    } catch (e) {
      if (widget.ocrEngine == null) {
        try {
          await engine.dispose();
        } catch (_) {}
      }

      if (!mounted) return;

      setState(() {
        _isProcessing = false;
      });

      debugPrint('[OCR] OCR Text Extraction failed: ${e.toString()}');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text('OCR Text Extraction failed: ${e.toString()}'),
              ),
            ],
          ),
          backgroundColor: Colors.red[800],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Invoice Preview',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF0F172A),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 14,
                    color: Color(0xFF059669),
                  ),
                  SizedBox(width: 5),
                  Text(
                    'Offline',
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
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Document File Details Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.image_outlined,
                                  color: Color(0xFF0F172A),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _fileName,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F172A),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          _fileSizeFormatted,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF64748B),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Text('•', style: TextStyle(color: Color(0xFF94A3B8))),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Gallery Image',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF059669),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        Text(
                          'Selected Document Image',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Image Display Canvas
                        Container(
                          width: double.infinity,
                          constraints: BoxConstraints(
                            maxHeight: mediaQuery.size.height * 0.48,
                            minHeight: 220,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF334155)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 15,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.file(
                                  widget.imageFile,
                                  fit: BoxFit.contain,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
                                          SizedBox(height: 8),
                                          Text(
                                            'Unable to render image preview',
                                            style: TextStyle(color: Colors.white70, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                Positioned(
                                  top: 12,
                                  right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.65),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.crop_free_rounded, color: Colors.white70, size: 14),
                                        SizedBox(width: 4),
                                        Text(
                                          'Full View',
                                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Privacy Assurance Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.lock_outline_rounded, size: 16, color: Color(0xFF059669)),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Image loaded from local device. No internet transmission.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF475569),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Action Buttons Footer
                Container(
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Cancel Button
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            foregroundColor: const Color(0xFF475569),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.close_rounded, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Process Invoice Button
                      Expanded(
                        flex: 3,
                        child: ElevatedButton(
                          onPressed: _isProcessing ? null : _processInvoiceOcr,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.document_scanner_outlined, size: 18, color: Color(0xFF34D399)),
                              SizedBox(width: 8),
                              Text(
                                'Process Invoice',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Loading Indicator Overlay during ML Kit OCR Processing
            if (_isProcessing)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.65),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: CircularProgressIndicator(
                              strokeWidth: 3.5,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 20),
                          Text(
                            'Extracting Text via ML Kit...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Running 100% offline text recognition on device',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
