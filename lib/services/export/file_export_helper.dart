import 'dart:typed_data';
import 'export_platform_stub.dart'
    if (dart.library.io) 'export_platform_io.dart'
    if (dart.library.html) 'export_platform_web.dart';

class ExportResult {
  final bool success;
  final String? filePath;
  final String? fileName;
  final String? errorMessage;

  const ExportResult({
    required this.success,
    this.filePath,
    this.fileName,
    this.errorMessage,
  });
}

class FileExportHelper {
  const FileExportHelper();

  Future<ExportResult> exportBytes({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    String? shareSubject,
  }) async {
    return await platformExportBytes(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      shareSubject: shareSubject,
    );
  }

  Future<ExportResult> exportString({
    required String content,
    required String fileName,
    String? mimeType,
    String? shareSubject,
  }) async {
    return await platformExportString(
      content: content,
      fileName: fileName,
      mimeType: mimeType,
      shareSubject: shareSubject,
    );
  }
}
