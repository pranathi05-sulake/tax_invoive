import 'dart:io';
import 'ocr_engine.dart';

class TesseractWebOcrEngine implements OcrEngine {
  @override
  Future<OcrResult> processImageFile(File imageFile) async {
    throw UnsupportedError('TesseractWebOcrEngine is only available on Web platform.');
  }

  @override
  Future<void> dispose() async {}
}
