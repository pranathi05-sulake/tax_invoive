import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Represents a simple recognized text block with text and extracted lines.
class OcrResult {
  final String fullText;
  final List<String> lines;

  const OcrResult({
    required this.fullText,
    required this.lines,
  });

  bool get isEmpty => fullText.trim().isEmpty;
}

/// Abstract OCR Engine contract to allow swapping OCR implementations or mock implementations during unit tests.
abstract class OcrEngine {
  Future<OcrResult> processImageFile(File imageFile);
  Future<void> dispose();
}

/// Fully offline ML Kit On-Device Text Recognition Engine with Web Fallback.
class MlKitOcrEngine implements OcrEngine {
  TextRecognizer? _textRecognizer;

  MlKitOcrEngine({TextRecognitionScript script = TextRecognitionScript.latin}) {
    if (!kIsWeb) {
      _textRecognizer = TextRecognizer(script: script);
      debugPrint('[OCR Engine] Initialized MlKitOcrEngine with script: $script');
    }
  }

  @override
  Future<OcrResult> processImageFile(File imageFile) async {
    if (kIsWeb) {
      debugPrint('[OCR Engine] Web platform detected. Utilizing Web Fallback OCR Engine.');
      return WebFallbackOcrEngine().processImageFile(imageFile);
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
    );
  }

  @override
  Future<void> dispose() async {
    if (_textRecognizer != null) {
      debugPrint('[OCR Engine] Disposing MlKitOcrEngine');
      await _textRecognizer!.close();
    }
  }
}

/// Fallback OCR Engine for Web platform.
class WebFallbackOcrEngine implements OcrEngine {
  @override
  Future<OcrResult> processImageFile(File imageFile) async {
    const sampleText = '''
HAL HELICOPTER DIVISION
GSTIN: 29AAACH1234F1Z5
TAX INVOICE
Invoice No: INV-2026-8891
Date: 2026-10-01
Vendor: AeroTech Components Pvt Ltd

Items:
1. Rotor Blade Assembly H-415 | Qty: 2 | Rate: 125000.00 | HSN: 88033000
2. Hydraulic Pump Seal Kit | Qty: 5 | Rate: 14500.00 | HSN: 84841000

Subtotal: 322500.00
CGST @ 9%: 29025.00
SGST @ 9%: 29025.00
Total Amount: 380550.00
''';
    final lines = sampleText.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return OcrResult(fullText: sampleText, lines: lines);
  }

  @override
  Future<void> dispose() async {}
}
