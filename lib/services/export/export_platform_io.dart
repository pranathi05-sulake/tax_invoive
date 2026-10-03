import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'file_export_helper.dart';

Future<ExportResult> platformExportBytes({
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

Future<ExportResult> platformExportString({
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
