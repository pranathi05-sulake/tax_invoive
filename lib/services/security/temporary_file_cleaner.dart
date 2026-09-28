import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class TemporaryFileCleaner {
  const TemporaryFileCleaner();

  /// Safely deletes a single temporary invoice processing file from local disk.
  Future<bool> cleanFile(File? file) async {
    if (file == null) return false;
    try {
      if (await file.exists()) {
        await file.delete();
        debugPrint('[TemporaryFileCleaner] Successfully cleaned temporary file: ${file.path}');
        return true;
      }
    } catch (e) {
      debugPrint('[TemporaryFileCleaner] Error cleaning file ${file.path}: $e');
    }
    return false;
  }

  /// Cleans a list of temporary processing image files.
  Future<int> cleanBatchFiles(List<File> files) async {
    int count = 0;
    for (final f in files) {
      if (await cleanFile(f)) {
        count++;
      }
    }
    return count;
  }

  /// Performs temporary cache cleanup on the application's temporary directory.
  Future<int> cleanAppTempDir() async {
    int deletedCount = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        final entities = tempDir.listSync(recursive: true);
        for (final entity in entities) {
          if (entity is File) {
            try {
              await entity.delete();
              deletedCount++;
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[TemporaryFileCleaner] Error during temp dir cleanup: $e');
    }
    return deletedCount;
  }
}
