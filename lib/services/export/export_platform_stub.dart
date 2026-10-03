import 'dart:typed_data';
import 'file_export_helper.dart';

Future<ExportResult> platformExportBytes({
  required Uint8List bytes,
  required String fileName,
  String? mimeType,
  String? shareSubject,
}) {
  throw UnimplementedError('Platform export not implemented.');
}

Future<ExportResult> platformExportString({
  required String content,
  required String fileName,
  String? mimeType,
  String? shareSubject,
}) {
  throw UnimplementedError('Platform export not implemented.');
}
