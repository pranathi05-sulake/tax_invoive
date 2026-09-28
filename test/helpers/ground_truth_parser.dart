import 'dart:convert';
import 'dart:io';

/// Standard Ground Truth annotation object for evaluating local Kaggle dataset invoice OCR extractions.
class GroundTruthAnnotation {
  final String imageFileName;
  final String? imageFullPath;
  final String expectedGstin;
  final String expectedInvoiceNumber;
  final String expectedVendorName;
  final String expectedDate;
  final double? expectedTotalAmount;
  final double? expectedSubtotal;

  const GroundTruthAnnotation({
    required this.imageFileName,
    this.imageFullPath,
    required this.expectedGstin,
    required this.expectedInvoiceNumber,
    required this.expectedVendorName,
    required this.expectedDate,
    this.expectedTotalAmount,
    this.expectedSubtotal,
  });

  factory GroundTruthAnnotation.fromJson(Map<String, dynamic> json, {String? baseDirPath}) {
    final fileName = json['image_name'] ?? json['image'] ?? json['file_name'] ?? '';
    final fullPath = baseDirPath != null && fileName.isNotEmpty ? '$baseDirPath/$fileName' : null;

    return GroundTruthAnnotation(
      imageFileName: fileName,
      imageFullPath: fullPath,
      expectedGstin: json['gstin'] ?? json['gst_number'] ?? '',
      expectedInvoiceNumber: json['invoice_number'] ?? json['invoice_no'] ?? json['bill_no'] ?? '',
      expectedVendorName: json['vendor_name'] ?? json['store_name'] ?? json['vendor'] ?? '',
      expectedDate: json['date'] ?? json['invoice_date'] ?? '',
      expectedTotalAmount: (json['total_amount'] ?? json['total'] ?? json['grand_total']) != null
          ? double.tryParse((json['total_amount'] ?? json['total'] ?? json['grand_total']).toString())
          : null,
      expectedSubtotal: (json['subtotal'] ?? json['taxable_amount']) != null
          ? double.tryParse((json['subtotal'] ?? json['taxable_amount']).toString())
          : null,
    );
  }
}

/// Utility for parsing local dataset annotations (JSON / CSV formats).
class GroundTruthParser {
  /// Loads annotations from a directory containing `.json` annotation files or a `ground_truth.csv` / `annotations.json`.
  static Future<List<GroundTruthAnnotation>> loadFromDirectory(Directory datasetDir) async {
    final annotations = <GroundTruthAnnotation>[];
    if (!await datasetDir.exists()) {
      return annotations;
    }

    final entities = await datasetDir.list(recursive: true).toList();

    // 1. Look for a single combined annotations.json
    final combinedJsonFile = entities.whereType<File>().firstWhere(
      (f) => f.path.endsWith('annotations.json') || f.path.endsWith('ground_truth.json'),
      orElse: () => File(''),
    );

    if (combinedJsonFile.path.isNotEmpty) {
      try {
        final content = await combinedJsonFile.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              annotations.add(GroundTruthAnnotation.fromJson(item, baseDirPath: datasetDir.path));
            }
          }
          return annotations;
        }
      } catch (_) {}
    }

    // 2. Look for individual *.json files per image
    for (final entity in entities) {
      if (entity is File && entity.path.endsWith('.json') && !entity.path.endsWith('package_config.json')) {
        try {
          final content = await entity.readAsString();
          final decoded = jsonDecode(content);
          if (decoded is Map<String, dynamic>) {
            final imgName = decoded['image_name'] ??
                entity.path.split(Platform.pathSeparator).last.replaceAll('.json', '.jpg');
            annotations.add(
              GroundTruthAnnotation.fromJson(
                {...decoded, 'image_name': imgName},
                baseDirPath: datasetDir.path,
              ),
            );
          }
        } catch (_) {}
      }
    }

    // 3. Look for ground_truth.csv
    final csvFile = entities.whereType<File>().firstWhere(
      (f) => f.path.endsWith('ground_truth.csv') || f.path.endsWith('annotations.csv'),
      orElse: () => File(''),
    );

    if (csvFile.path.isNotEmpty && annotations.isEmpty) {
      try {
        final lines = await csvFile.readAsLines();
        if (lines.length > 1) {
          final header = lines.first.split(',').map((h) => h.trim().toLowerCase()).toList();
          final imgIdx = header.indexWhere((h) => h.contains('image') || h.contains('file'));
          final gstinIdx = header.indexWhere((h) => h.contains('gst'));
          final invIdx = header.indexWhere((h) => h.contains('inv') || h.contains('bill'));
          final vendorIdx = header.indexWhere((h) => h.contains('vendor') || h.contains('store'));
          final totalIdx = header.indexWhere((h) => h.contains('total') || h.contains('amount'));
          final dateIdx = header.indexWhere((h) => h.contains('date'));

          for (int i = 1; i < lines.length; i++) {
            final row = lines[i].split(',').map((c) => c.trim()).toList();
            if (row.length > imgIdx && imgIdx != -1) {
              final imgName = row[imgIdx];
              annotations.add(
                GroundTruthAnnotation(
                  imageFileName: imgName,
                  imageFullPath: '${datasetDir.path}/$imgName',
                  expectedGstin: gstinIdx != -1 && row.length > gstinIdx ? row[gstinIdx] : '',
                  expectedInvoiceNumber: invIdx != -1 && row.length > invIdx ? row[invIdx] : '',
                  expectedVendorName: vendorIdx != -1 && row.length > vendorIdx ? row[vendorIdx] : '',
                  expectedDate: dateIdx != -1 && row.length > dateIdx ? row[dateIdx] : '',
                  expectedTotalAmount: totalIdx != -1 && row.length > totalIdx
                      ? double.tryParse(row[totalIdx].replaceAll(RegExp(r'[^\d\.]'), ''))
                      : null,
                ),
              );
            }
          }
        }
      } catch (_) {}
    }

    return annotations;
  }
}
