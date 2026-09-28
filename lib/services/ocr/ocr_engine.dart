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

/// Fully offline ML Kit On-Device Text Recognition Engine.
/// Operates 100% locally on Android/iOS without any cloud or internet connections.
class MlKitOcrEngine implements OcrEngine {
  late final TextRecognizer _textRecognizer;

  MlKitOcrEngine({TextRecognitionScript script = TextRecognitionScript.latin}) {
    _textRecognizer = TextRecognizer(script: script);
    debugPrint('[OCR Engine] Initialized MlKitOcrEngine with script: $script');
  }

  @override
  Future<OcrResult> processImageFile(File imageFile) async {
    debugPrint('[OCR Engine] Processing image: ${imageFile.path}');
    final inputImage = InputImage.fromFile(imageFile);
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

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
    debugPrint('[OCR Engine] Disposing MlKitOcrEngine');
    await _textRecognizer.close();
  }
}
