// ignore_for_file: avoid_web_libraries_in_flutter, uri_does_not_exist
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:js_util' as js_util;
import 'ocr_engine.dart';

class TesseractWebOcrEngine implements OcrEngine {
  @override
  Future<OcrResult> processImageFile(File imageFile) async {
    debugPrint('[TesseractWebOcrEngine] Executing Web OCR Pipeline for file: ${imageFile.path}');

    try {
      final jsPromise = js_util.callMethod(
        js_util.globalThis,
        'processWebInvoiceOcr',
        [imageFile.path],
      );

      final jsResult = await js_util.promiseToFuture(jsPromise);
      final success = js_util.getProperty(jsResult, 'success') as bool? ?? false;

      if (!success) {
        final err = js_util.getProperty(jsResult, 'error')?.toString() ?? 'Browser Tesseract OCR failed.';
        throw Exception(err);
      }

      final fullText = js_util.getProperty(jsResult, 'fullText')?.toString() ?? '';
      final jsLines = js_util.getProperty(jsResult, 'lines');
      final List<String> lines = [];

      if (jsLines != null) {
        final len = js_util.getProperty(jsLines, 'length') as int? ?? 0;
        for (int i = 0; i < len; i++) {
          final line = js_util.getProperty(jsLines, i)?.toString();
          if (line != null && line.trim().isNotEmpty) {
            lines.add(line.trim());
          }
        }
      }

      final confidence = (js_util.getProperty(jsResult, 'confidence') as num?)?.toDouble() ?? 0.0;
      debugPrint('[TesseractWebOcrEngine] Extracted ${lines.length} lines with ${confidence.toStringAsFixed(1)}% confidence.');

      return OcrResult(
        fullText: fullText,
        lines: lines,
        confidence: confidence,
      );
    } catch (e) {
      debugPrint('[TesseractWebOcrEngine] Web OCR Error: $e');
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {}
}
