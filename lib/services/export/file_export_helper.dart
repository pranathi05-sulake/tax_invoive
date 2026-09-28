import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
    try {
      final dir = await getTemporaryDirectory();
      final filePath = p.join(dir.path, fileName);
      final file = File(filePath);

      await file.writeAsBytes(bytes, flush: true);

      // Trigger native Android share/save sheet
      final xFile = XFile(filePath, mimeType: mimeType, name: fileName);
      final shareResult = await Share.shareXFiles(
        [xFile],
        text: shareSubject ?? 'Tax Invoice Export — $fileName',
      );

      return ExportResult(
        success: true,
        filePath: filePath,
        fileName: fileName,
      );
    } catch (e) {
      return ExportResult(
        success: false,
        errorMessage: 'Failed to export file: $e',
      );
    }
  }

  Future<ExportResult> exportString({
    required String content,
    required String fileName,
    String? mimeType,
    String? shareSubject,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final filePath = p.join(dir.path, fileName);
      final file = File(filePath);

      await file.writeAsString(content, flush: true);

      // Trigger native Android share/save sheet
      final xFile = XFile(filePath, mimeType: mimeType, name: fileName);
      await Share.shareXFiles(
        [xFile],
        text: shareSubject ?? 'Tax Invoice Export — $fileName',
      );

      return ExportResult(
        success: true,
        filePath: filePath,
        fileName: fileName,
      );
    } catch (e) {
      return ExportResult(
        success: false,
        errorMessage: 'Failed to export file: $e',
      );
    }
  }
}
