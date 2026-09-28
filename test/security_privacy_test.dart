import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tax_invoice_app/models/invoice.dart';
import 'package:tax_invoice_app/services/backup/encrypted_backup_service.dart';
import 'package:tax_invoice_app/services/backup/invoice_backup_service.dart';
import 'package:tax_invoice_app/services/database/database_helper.dart';
import 'package:tax_invoice_app/services/export/file_export_helper.dart';
import 'package:tax_invoice_app/services/security/temporary_file_cleaner.dart';

class FakeExportHelper extends FileExportHelper {
  String? lastExportedString;
  String? lastFileName;
  bool shouldSucceed;

  FakeExportHelper({this.shouldSucceed = true});

  @override
  Future<ExportResult> exportString({
    required String content,
    required String fileName,
    String? mimeType,
    String? shareSubject,
  }) async {
    lastExportedString = content;
    lastFileName = fileName;

    if (!shouldSucceed) {
      return const ExportResult(
        success: false,
        errorMessage: 'Mock export failure',
      );
    }

    return ExportResult(
      success: true,
      filePath: '/mock/path/$fileName',
      fileName: fileName,
    );
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Security & Privacy Audit Tests', () {
    late DatabaseHelper dbHelper;
    late Directory tempDir;

    setUp(() async {
      dbHelper = DatabaseHelper.instance;
      await dbHelper.resetDatabaseForTesting();
      tempDir = await Directory.systemTemp.createTemp('tax_invoice_security_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('Encrypted Backup Service Tests', () {
      test('Encrypts and decrypts backup payload correctly with valid password', () async {
        const plainPayload = '{"version":2,"invoices":[{"id":"inv_001","vendorName":"Helicopter Spares Ltd"}]}';
        const password = 'HelicopterSecret123!';

        final encryptedString = EncryptedBackupService.instance.encryptBackupContent(plainPayload, password);
        expect(encryptedString.startsWith('ENC_BACKUP_v1:'), isTrue);
        expect(encryptedString, isNot(equals(plainPayload)));

        final decryptedPayload = EncryptedBackupService.instance.decryptBackupContent(encryptedString, password);
        expect(decryptedPayload, equals(plainPayload));
      });

      test('Rejects decryption with incorrect password', () {
        const plainPayload = '{"version":2,"invoices":[]}';
        const correctPassword = 'RightPassword123';
        const wrongPassword = 'WrongPassword456';

        final encryptedString = EncryptedBackupService.instance.encryptBackupContent(plainPayload, correctPassword);

        expect(
          () => EncryptedBackupService.instance.decryptBackupContent(encryptedString, wrongPassword),
          throwsA(isA<FormatException>()),
        );
      });

      test('Transparently handles legacy unencrypted JSON backup files', () {
        const plainJson = '{"version":1,"invoices":[{"id":"legacy_1","vendorName":"Aero Fuel Systems"}]}';
        const password = 'AnyPassword';

        final result = EncryptedBackupService.instance.decryptBackupContent(plainJson, password);
        expect(result, equals(plainJson));
      });

      test('exportEncryptedBackup exports password-encrypted backup file', () async {
        final invoice = Invoice(
          id: 'sec_inv_1',
          vendorName: 'Skyline Rotor Parts',
          invoiceNumber: 'SRP-9988',
          date: DateTime(2026, 9, 25),
          subtotal: 5000.0,
          cgst: 450.0,
          sgst: 450.0,
          igst: 0.0,
          gstin: '29AAACB1234C1Z5',
          status: InvoiceStatus.verified,
        );
        await dbHelper.insertInvoice(invoice);

        final fakeExport = FakeExportHelper();
        const backupService = InvoiceBackupService();

        final result = await EncryptedBackupService.instance.exportEncryptedBackup(
          password: 'SecureHelicopterKey',
          backupService: backupService,
          exportHelper: fakeExport,
        );

        expect(result.success, isTrue);
        expect(fakeExport.lastExportedString, isNotNull);
        expect(fakeExport.lastExportedString!.startsWith('ENC_BACKUP_v1:'), isTrue);
        expect(fakeExport.lastExportedString!.contains('Skyline Rotor Parts'), isFalse);
      });

      test('restoreEncryptedBackup validates password and imports records', () async {
        final invoice = Invoice(
          id: 'sec_inv_2',
          vendorName: 'Turbine Maintenance Inc',
          invoiceNumber: 'TMI-1024',
          date: DateTime(2026, 9, 25),
          subtotal: 12000.0,
          cgst: 1080.0,
          sgst: 1080.0,
          igst: 0.0,
          gstin: '29AAACB1234C1Z5',
          status: InvoiceStatus.verified,
        );

        const backupService = InvoiceBackupService();
        final jsonPayload = backupService.createBackupJson([invoice]);
        const password = 'HelicopterAuthPass';
        final encryptedContent = EncryptedBackupService.instance.encryptBackupContent(jsonPayload, password);
        final restoreResult = await EncryptedBackupService.instance.restoreEncryptedBackup(
          encryptedContent: encryptedContent,
          password: password,
          backupService: backupService,
        );

        expect(restoreResult.success, isTrue);
        expect(restoreResult.addedCount, equals(1));

        final restoredInvoice = await dbHelper.getInvoiceById('sec_inv_2');
        expect(restoredInvoice, isNotNull);
        expect(restoredInvoice!.vendorName, equals('Turbine Maintenance Inc'));
      });
    });

    group('Temporary File Cleaner Tests', () {
      const cleaner = TemporaryFileCleaner();

      test('cleanFile deletes single temporary file', () async {
        final file = File('${tempDir.path}/temp_invoice_photo.jpg');
        await file.writeAsString('sample image binary bytes');
        expect(await file.exists(), isTrue);

        final result = await cleaner.cleanFile(file);
        expect(result, isTrue);
        expect(await file.exists(), isFalse);
      });

      test('cleanFile handles non-existent file gracefully', () async {
        final file = File('${tempDir.path}/non_existent_file.jpg');
        final result = await cleaner.cleanFile(file);
        expect(result, isFalse);
      });

      test('cleanBatchFiles deletes list of processing files', () async {
        final f1 = File('${tempDir.path}/temp1.png');
        final f2 = File('${tempDir.path}/temp2.png');
        await f1.writeAsString('f1');
        await f2.writeAsString('f2');

        final cleanedCount = await cleaner.cleanBatchFiles([f1, f2]);
        expect(cleanedCount, equals(2));
        expect(await f1.exists(), isFalse);
        expect(await f2.exists(), isFalse);
      });
    });
  });
}
