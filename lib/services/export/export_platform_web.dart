// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'file_export_helper.dart';

Future<ExportResult> platformExportBytes({
  required Uint8List bytes,
  required String fileName,
  String? mimeType,
  String? shareSubject,
}) async {
  try {
    final type = mimeType ?? 'application/octet-stream';
    final blob = html.Blob([bytes], type);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..target = '_blank'
      ..download = fileName;

    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);

    return ExportResult(
      success: true,
      filePath: fileName,
      fileName: fileName,
    );
  } catch (e) {
    return ExportResult(
      success: false,
      errorMessage: 'Failed to download file in browser: $e',
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
    final bytes = Uint8List.fromList(utf8.encode(content));
    final type = mimeType ?? 'text/plain;charset=utf-8';
    return await platformExportBytes(
      bytes: bytes,
      fileName: fileName,
      mimeType: type,
      shareSubject: shareSubject,
    );
  } catch (e) {
    return ExportResult(
      success: false,
      errorMessage: 'Failed to download file in browser: $e',
    );
  }
}
