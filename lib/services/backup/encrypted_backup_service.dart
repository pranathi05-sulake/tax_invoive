import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../../models/invoice.dart';
import '../database/database_helper.dart';
import '../export/file_export_helper.dart';
import 'invoice_backup_service.dart';

class EncryptedBackupResult {
  final bool success;
  final String? errorMessage;
  final String? encryptedOutput;

  const EncryptedBackupResult({
    required this.success,
    this.errorMessage,
    this.encryptedOutput,
  });
}

class EncryptedBackupService {
  static final EncryptedBackupService instance = EncryptedBackupService();

  static const String encryptedAppSignature = 'TaxInvoiceAI';
  static const String formatIdentifier = 'encrypted_v1';
  final InvoiceBackupService baseBackupService;

  const EncryptedBackupService({
    this.baseBackupService = const InvoiceBackupService(),
  });

  /// Derives a 256-bit cryptographic key from a user password and salt using PBKDF2-HMAC-SHA256.
  Uint8List _deriveKey(String password, Uint8List salt, {int iterations = 2000}) {
    final passwordBytes = utf8.encode(password);
    Uint8List derivedKey = Uint8List(32);
    
    var hmac = Hmac(sha256, passwordBytes);
    var block = Uint8List(salt.length + 4);
    block.setAll(0, salt);
    block[salt.length + 3] = 1;

    var u = Uint8List.fromList(hmac.convert(block).bytes);
    for (int i = 0; i < derivedKey.length; i++) {
      derivedKey[i] = u[i];
    }

    for (int iter = 1; iter < iterations; iter++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (int i = 0; i < derivedKey.length; i++) {
        derivedKey[i] ^= u[i];
      }
    }

    return derivedKey;
  }

  /// Generates a random byte sequence for IV / Salt.
  Uint8List _generateRandomBytes(int length) {
    final rnd = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => rnd.nextInt(256)));
  }

  /// Encrypts data bytes using XOR stream with derived key + IV and HMAC SHA-256 signature.
  Uint8List _cipherProcess(Uint8List input, Uint8List key, Uint8List iv) {
    final output = Uint8List(input.length);
    var currentBlock = Uint8List.fromList(iv);

    for (int i = 0; i < input.length; i++) {
      if (i % 32 == 0) {
        final blockDigest = sha256.convert([...key, ...currentBlock]);
        currentBlock = Uint8List.fromList(blockDigest.bytes);
      }
      output[i] = input[i] ^ currentBlock[i % 32];
    }

    return output;
  }

  /// Creates a password-protected, authenticated encrypted backup JSON string.
  EncryptedBackupResult createEncryptedBackup({
    required List<Invoice> invoices,
    required String password,
  }) {
    if (password.trim().isEmpty) {
      return const EncryptedBackupResult(
        success: false,
        errorMessage: 'Encryption password cannot be empty.',
      );
    }

    try {
      final plaintextJson = baseBackupService.createBackupJson(invoices);
      final plaintextBytes = utf8.encode(plaintextJson);

      final salt = _generateRandomBytes(16);
      final iv = _generateRandomBytes(16);
      final key = _deriveKey(password, salt);

      final ciphertextBytes = _cipherProcess(Uint8List.fromList(plaintextBytes), key, iv);

      // HMAC SHA-256 signature over (salt + iv + ciphertext)
      final hmacKey = Hmac(sha256, key);
      final signature = hmacKey.convert([...salt, ...iv, ...ciphertextBytes]).toString();

      final Map<String, dynamic> envelope = {
        'app': encryptedAppSignature,
        'format': formatIdentifier,
        'salt': base64Encode(salt),
        'iv': base64Encode(iv),
        'ciphertext': base64Encode(ciphertextBytes),
        'hmac': signature,
      };

      const encoder = JsonEncoder.withIndent('  ');
      return EncryptedBackupResult(
        success: true,
        encryptedOutput: encoder.convert(envelope),
      );
    } catch (e) {
      return EncryptedBackupResult(
        success: false,
        errorMessage: 'Backup encryption error: $e',
      );
    }
  }

  /// Inspects and decrypts a password-protected backup file.
  BackupInspectionResult inspectEncryptedBackup({
    required String encryptedJsonString,
    required String password,
  }) {
    if (encryptedJsonString.trim().isEmpty) {
      return BackupInspectionResult.invalid('The selected backup file is empty.');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(encryptedJsonString);
    } catch (e) {
      return BackupInspectionResult.invalid('Invalid JSON format: $e');
    }

    if (decoded is! Map<String, dynamic>) {
      return BackupInspectionResult.invalid('Invalid envelope format.');
    }

    // Check if it's legacy unencrypted JSON backup
    if (decoded.containsKey('app') && decoded['app'] == InvoiceBackupService.appSignature && decoded.containsKey('invoices')) {
      return baseBackupService.inspectBackupJson(encryptedJsonString);
    }

    if (decoded['format'] != formatIdentifier) {
      return BackupInspectionResult.invalid('Unsupported or unrecognized backup file format.');
    }

    if (password.trim().isEmpty) {
      return BackupInspectionResult.invalid('Password required to decrypt backup.');
    }

    try {
      final salt = base64Decode(decoded['salt'] as String);
      final iv = base64Decode(decoded['iv'] as String);
      final ciphertextBytes = base64Decode(decoded['ciphertext'] as String);
      final expectedHmac = decoded['hmac'] as String;

      final key = _deriveKey(password, salt);

      // Verify HMAC-SHA256 signature
      final hmacKey = Hmac(sha256, key);
      final calculatedHmac = hmacKey.convert([...salt, ...iv, ...ciphertextBytes]).toString();

      if (calculatedHmac != expectedHmac) {
        return BackupInspectionResult.invalid('Incorrect decryption password or corrupted file.');
      }

      final plaintextBytes = _cipherProcess(ciphertextBytes, key, iv);
      final plaintextJson = utf8.decode(plaintextBytes);

      return baseBackupService.inspectBackupJson(plaintextJson);
    } catch (e) {
      return BackupInspectionResult.invalid('Decryption failure: $e');
    }
  }

  /// Exports password-encrypted backup file using FileExportHelper.
  Future<ExportResult> exportEncryptedBackup({
    required String password,
    required InvoiceBackupService backupService,
    FileExportHelper? exportHelper,
    DatabaseHelper? databaseHelper,
  }) async {
    final db = databaseHelper ?? DatabaseHelper.instance;
    final exp = exportHelper ?? const FileExportHelper();
    final invoices = await db.getAllInvoices();
    final encryptedResult = createEncryptedBackup(invoices: invoices, password: password);
    if (!encryptedResult.success || encryptedResult.encryptedOutput == null) {
      return ExportResult(
        success: false,
        errorMessage: encryptedResult.errorMessage ?? 'Failed to encrypt backup payload.',
      );
    }
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
    final fileName = 'tax_invoice_backup_enc_$timestamp.json';
    return await exp.exportString(
      content: 'ENC_BACKUP_v1:' + encryptedResult.encryptedOutput!,
      fileName: fileName,
      mimeType: 'application/json',
      shareSubject: 'TaxInvoice AI Encrypted Backup ($fileName)',
    );
  }

  /// Restores password-encrypted backup into SQLite database.
  Future<RestoreResult> restoreEncryptedBackup({
    required String encryptedContent,
    required String password,
    required InvoiceBackupService backupService,
    DatabaseHelper? databaseHelper,
    RestoreStrategy strategy = RestoreStrategy.skipDuplicates,
  }) async {
    final db = databaseHelper ?? DatabaseHelper.instance;
    final cleanInput = encryptedContent.startsWith('ENC_BACKUP_v1:')
        ? encryptedContent.substring('ENC_BACKUP_v1:'.length)
        : encryptedContent;
    final inspection = inspectEncryptedBackup(encryptedJsonString: cleanInput, password: password);
    if (!inspection.isValid) {
      return RestoreResult.failure(inspection.errorMessage ?? 'Invalid encrypted backup file.');
    }

    int added = 0;
    int updated = 0;
    int skipped = 0;

    if (strategy == RestoreStrategy.replaceAll) {
      await db.clearAllInvoices();
    }

    for (final invoice in inspection.invoices) {
      final exists = await db.checkInvoiceExists(
        gstin: invoice.gstin,
        invoiceNumber: invoice.invoiceNumber,
        date: invoice.date,
        id: invoice.id,
      );

      if (exists) {
        if (strategy == RestoreStrategy.overwriteExisting || strategy == RestoreStrategy.replaceAll) {
          await db.replaceInvoice(invoice);
          updated++;
        } else {
          skipped++;
        }
      } else {
        await db.insertInvoice(invoice);
        added++;
      }
    }

    return RestoreResult(
      success: true,
      addedCount: added,
      updatedCount: updated,
      skippedCount: skipped,
      totalProcessed: inspection.invoices.length,
    );
  }

  /// Direct helper method to encrypt backup payload string with header tag for unit testing.
  String encryptBackupContent(String plainJson, String password) {
    final salt = _generateRandomBytes(16);
    final iv = _generateRandomBytes(16);
    final key = _deriveKey(password, salt);
    final ciphertextBytes = _cipherProcess(Uint8List.fromList(utf8.encode(plainJson)), key, iv);
    final hmacKey = Hmac(sha256, key);
    final signature = hmacKey.convert([...salt, ...iv, ...ciphertextBytes]).toString();

    final Map<String, dynamic> envelope = {
      'app': encryptedAppSignature,
      'format': formatIdentifier,
      'salt': base64Encode(salt),
      'iv': base64Encode(iv),
      'ciphertext': base64Encode(ciphertextBytes),
      'hmac': signature,
    };

    return 'ENC_BACKUP_v1:' + jsonEncode(envelope);
  }

  /// Direct helper method to decrypt backup payload string for unit testing.
  String decryptBackupContent(String input, String password) {
    if (!input.startsWith('ENC_BACKUP_v1:')) {
      return input;
    }
    final rawJson = input.substring('ENC_BACKUP_v1:'.length);
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final salt = base64Decode(decoded['salt'] as String);
    final iv = base64Decode(decoded['iv'] as String);
    final ciphertextBytes = base64Decode(decoded['ciphertext'] as String);
    final expectedHmac = decoded['hmac'] as String;

    final key = _deriveKey(password, salt);
    final hmacKey = Hmac(sha256, key);
    final calculatedHmac = hmacKey.convert([...salt, ...iv, ...ciphertextBytes]).toString();

    if (calculatedHmac != expectedHmac) {
      throw const FormatException('Invalid backup password or corrupted file.');
    }

    final plaintextBytes = _cipherProcess(ciphertextBytes, key, iv);
    return utf8.decode(plaintextBytes);
  }
}
