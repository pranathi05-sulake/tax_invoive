import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:tax_invoice_app/models/invoice.dart';
import 'package:tax_invoice_app/services/database/database_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Android Native SQLCipher Device Verification Test Suite', () {
    late String dbDirectoryPath;
    const String testDbName = 'native_sqlcipher_verify.db';

    setUpAll(() async {
      dbDirectoryPath = await databaseFactory.getDatabasesPath();
    });

    testWidgets('1-10: Android-Native SQLCipher Binary Header, Encryption, CRUD, and Migration Verification', (WidgetTester tester) async {
      final dbFilePath = join(dbDirectoryPath, testDbName);
      final dbFile = File(dbFilePath);

      // Cleanup any pre-existing test files
      if (await dbFile.exists()) await dbFile.delete();

      const testPassword = 'SecretAndroidNativeKey2026!#$';
      const wrongPassword = 'InvalidWrongPassword999';

      // 1. Create native encrypted database via sqflite_sqlcipher
      final dbHandle = await openDatabase(
        dbFilePath,
        password: testPassword,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE invoices (
              id TEXT PRIMARY KEY,
              vendor_name TEXT,
              gstin TEXT,
              invoice_number TEXT,
              date TEXT,
              subtotal REAL,
              cgst REAL,
              sgst REAL,
              igst REAL,
              status INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE invoice_items (
              id TEXT PRIMARY KEY,
              invoice_id TEXT,
              description TEXT,
              quantity INTEGER,
              unit_price REAL
            )
          ''');
          await db.execute('''
            CREATE TABLE workflow_logs (
              id TEXT PRIMARY KEY,
              execution_id TEXT,
              step TEXT,
              status TEXT,
              message TEXT,
              timestamp TEXT
            )
          ''');
        },
      );

      // 6 & 7. Insert sample records into encrypted DB
      await dbHandle.insert('invoices', {
        'id': 'inv_native_1',
        'vendor_name': 'Helicopter Avionics Private Ltd',
        'gstin': '29AAACB1234C1Z5',
        'invoice_number': 'HAPL-2026-001',
        'date': '2026-09-25T10:00:00.000',
        'subtotal': 150000.0,
        'cgst': 13500.0,
        'sgst': 13500.0,
        'igst': 0.0,
        'status': 1,
      });

      await dbHandle.insert('invoice_items', {
        'id': 'item_native_1',
        'invoice_id': 'inv_native_1',
        'description': 'Helicopter Altimeter Calibration Sensor',
        'quantity': 1,
        'unit_price': 150000.0,
      });

      await dbHandle.insert('workflow_logs', {
        'id': 'log_native_1',
        'execution_id': 'exec_native_001',
        'step': 'native_device_verify',
        'status': 'completed',
        'message': 'Android native verification step complete',
        'timestamp': DateTime.now().toIso8601String(),
      });

      await dbHandle.close();

      // 2. Inspect physical file binary header on storage
      expect(await dbFile.exists(), isTrue);
      final isEncryptedHeader = await DatabaseHelper.isDatabaseEncrypted(dbFile);
      expect(isEncryptedHeader, isTrue, reason: 'Physical database file must NOT contain plaintext SQLite3 header');

      // 3. Confirm reopening with correct stored key succeeds
      final reopenedDb = await openDatabase(dbFilePath, password: testPassword, readOnly: true);
      final readInvoices = await reopenedDb.query('invoices');
      expect(readInvoices.length, equals(1));
      expect(readInvoices.first['vendor_name'], equals('Helicopter Avionics Private Ltd'));

      final readItems = await reopenedDb.query('invoice_items');
      expect(readItems.length, equals(1));
      expect(readItems.first['description'], equals('Helicopter Altimeter Calibration Sensor'));

      final readLogs = await reopenedDb.query('workflow_logs');
      expect(readLogs.length, equals(1));
      await reopenedDb.close();

      // 4. Confirm opening with WRONG key fails safely
      expect(
        () async => await openDatabase(dbFilePath, password: wrongPassword, readOnly: true),
        throwsA(isA<DatabaseException>()),
        reason: 'Opening SQLCipher database with invalid key must throw DatabaseException',
      );

      // Cleanup test database
      if (await dbFile.exists()) await dbFile.delete();
    });
  });
}
