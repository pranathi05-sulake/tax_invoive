import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'web_ocr_stub.dart'
    if (dart.library.js_util) 'web_ocr_impl.dart';

/// Represents a recognized text block with text, extracted lines, and OCR confidence.
class OcrResult {
  final String fullText;
  final List<String> lines;
  final double confidence;

  const OcrResult({
    required this.fullText,
    required this.lines,
    this.confidence = 100.0,
  });

  bool get isEmpty => fullText.trim().isEmpty;
}

/// Abstract OCR Engine contract to allow swapping OCR implementations or mock implementations during unit tests.
abstract class OcrEngine {
  Future<OcrResult> processImageFile(File imageFile);
  Future<void> dispose();
}

/// Fully offline ML Kit On-Device Text Recognition Engine.
/// Operates 100% locally on Android/iOS.
/// On Web browser, delegates to client-side Tesseract.js & Canvas preprocessing engine.
class MlKitOcrEngine implements OcrEngine {
  TextRecognizer? _textRecognizer;
  final TesseractWebOcrEngine? _webOcrEngine;

  MlKitOcrEngine({TextRecognitionScript script = TextRecognitionScript.latin})
      : _webOcrEngine = kIsWeb ? TesseractWebOcrEngine() : null {
    if (!kIsWeb) {
      _textRecognizer = TextRecognizer(script: script);
      debugPrint('[OCR Engine] Initialized MlKitOcrEngine with script: $script');
    }
  }

  @override
  Future<OcrResult> processImageFile(File imageFile) async {
    if (kIsWeb) {
      debugPrint('[MlKitOcrEngine] Web platform detected. Executing browser TesseractWebOcrEngine...');
      return await _webOcrEngine!.processImageFile(imageFile);
    }

    debugPrint('[OCR Engine] Processing image: ${imageFile.path}');
    final inputImage = InputImage.fromFile(imageFile);
    final RecognizedText recognizedText = await _textRecognizer!.processImage(inputImage);

    debugPrint('[OCR Engine] Text recognition completed. Total characters: ${recognizedText.text.length}');

    final List<String> extractedLines = [];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        if (line.text.trim().isNotEmpty) {
          extractedLines.add(line.text.trim());
        }
      }
    }

    debugPrint('[OCR Engine] Extracted ${extractedLines.length} non-empty lines.');

    return OcrResult(
      fullText: recognizedText.text,
      lines: extractedLines,
      confidence: 95.0,
    );
  }

  @override
  Future<void> dispose() async {
    if (_textRecognizer != null) {
      debugPrint('[OCR Engine] Disposing MlKitOcrEngine');
      await _textRecognizer!.close();
    }
    await _webOcrEngine?.dispose();
  }
}
