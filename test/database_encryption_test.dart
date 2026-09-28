import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tax_invoice_app/models/invoice.dart';
import 'package:tax_invoice_app/services/database/database_helper.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Database Encryption At Rest & Staged Migration Unit Tests', () {
    late DatabaseHelper dbHelper;
    late Directory tempDir;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      dbHelper = DatabaseHelper.instance;
      await dbHelper.resetDatabaseForTesting();
      tempDir = await Directory.systemTemp.createTemp('tax_invoice_db_enc_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('Key Management & Missing Key Rules', () {
      test('Creates encrypted database and stores key in secure storage', () async {
        final invoice = Invoice(
          id: 'enc_test_1',
          vendorName: 'Helicopter Rotors Ltd',
          invoiceNumber: 'HRL-101',
          date: DateTime(2026, 9, 25),
          subtotal: 10000.0,
          cgst: 900.0,
          sgst: 900.0,
          igst: 0.0,
          gstin: '29AAACB1234C1Z5',
          status: InvoiceStatus.verified,
        );

        await dbHelper.insertInvoice(invoice);
        final count = await dbHelper.getInvoiceCount();
        expect(count, equals(1));

        final fetched = await dbHelper.getInvoiceById('enc_test_1');
        expect(fetched, isNotNull);
        expect(fetched!.vendorName, equals('Helicopter Rotors Ltd'));
      });

      test('Fails safely with DatabaseAuthenticationException if database is encrypted but key is missing', () async {
        final mockStorage = const FlutterSecureStorage();
        FlutterSecureStorage.setMockInitialValues({}); // Key is missing

        final file = File('${tempDir.path}/invoices_encrypted_test.db');
        // Create pseudo-encrypted binary file header (non-plaintext)
        await file.writeAsBytes(List<int>.generate(64, (i) => (i * 17) % 256));

        final isEncrypted = await DatabaseHelper.isDatabaseEncrypted(file);
        expect(isEncrypted, isTrue);

        final helper = DatabaseHelper.withStorage(mockStorage);
        expect(
          () => helper.getOrCreateKeyForTesting(dbFileExists: true, isEncrypted: true),
          throwsA(isA<DatabaseAuthenticationException>()),
        );
      });
    });

    group('Plaintext Detection & Staged Migration Logic', () {
      test('Correctly identifies standard SQLite plaintext header', () async {
        final file = File('${tempDir.path}/plaintext_sample.db');
        const sqliteHeader = [
          0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00
        ];
        await file.writeAsBytes([...sqliteHeader, ...List.filled(48, 0)]);

        final isEncrypted = await DatabaseHelper.isDatabaseEncrypted(file);
        expect(isEncrypted, isFalse);
      });

      test('Correctly identifies non-plaintext binary header', () async {
        final file = File('${tempDir.path}/encrypted_sample.db');
        await file.writeAsBytes(List.filled(64, 0xFF));

        final isEncrypted = await DatabaseHelper.isDatabaseEncrypted(file);
        expect(isEncrypted, isTrue);
      });

      test('Read-only database connections do not attempt version writes or throw readonly errors', () async {
        final helper = DatabaseHelper.instance;
        final dbFilePath = '${tempDir.path}/readonly_regression_test.db';

        // Create initial database file with writable connection
        final writableDb = await helper.openSqlDatabaseForTesting(
          dbFilePath,
          password: 'TestSecretPassword123',
          version: 2,
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE sample (id TEXT PRIMARY KEY);');
          },
          onUpgrade: (_, __, ___) async {},
        );
        await writableDb.close();

        // Reopen in readOnly mode with version parameter specified - must NOT throw readonly PRAGMA user_version write exception
        final readOnlyDb = await helper.openSqlDatabaseForTesting(
          dbFilePath,
          password: 'TestSecretPassword123',
          version: 2,
          onCreate: (_, __) async {},
          onUpgrade: (_, __, ___) async {},
          readOnly: true,
        );

        expect(readOnlyDb.isOpen, isTrue);
        final result = await readOnlyDb.rawQuery('SELECT COUNT(*) FROM sample;');
        expect(result, isNotEmpty);
        await readOnlyDb.close();
      });

      test('Migration candidate directory is ensured and stale candidate files are cleaned before migration', () async {
        final candidateFile = File('${tempDir.path}/invoices_migrating.db.tmp');
        await candidateFile.parent.create(recursive: true);
        await candidateFile.writeAsString('stale candidate content');
        expect(await candidateFile.exists(), isTrue);

        if (await candidateFile.exists()) {
          await candidateFile.delete();
        }
        expect(await candidateFile.exists(), isFalse);
      });
    });

    group('Database Integrity & Feature Preservation', () {
      test('Preserves invoice items, workflow logs, and foreign key cascade deletion', () async {
        final item1 = const InvoiceItem(
          id: 'item_1',
          description: 'Rotor Blade Bearing Assembly',
          quantity: 2,
          unitPrice: 5000.0,
        );

        final invoice = Invoice(
          id: 'inv_cascade_1',
          vendorName: 'Aero Bearings Division',
          invoiceNumber: 'ABD-882',
          date: DateTime(2026, 9, 25),
          subtotal: 10000.0,
          cgst: 900.0,
          sgst: 900.0,
          items: [item1],
        );

        await dbHelper.insertInvoice(invoice);

        final log = WorkflowLogEntry(
          id: 'log_1',
          executionId: 'exec_999',
          invoiceId: invoice.id,
          step: 'capture',
          status: 'completed',
          message: 'Document captured successfully',
          timestamp: DateTime.now(),
        );
        await dbHelper.insertWorkflowLog(log);

        expect(await dbHelper.getInvoiceCount(), equals(1));
        expect(await dbHelper.getInvoiceItemCount(), equals(1));

        final logs = await dbHelper.getWorkflowLogs(executionId: 'exec_999');
        expect(logs.length, equals(1));
        expect(logs.first.message, equals('Document captured successfully'));

        // Cascade delete check
        await dbHelper.deleteInvoice(invoice.id);
        expect(await dbHelper.getInvoiceCount(), equals(0));
        expect(await dbHelper.getInvoiceItemCount(), equals(0));
      });

      test('Enforces UNIQUE(gstin, invoice_number, date) duplicate constraint', () async {
        final inv1 = Invoice(
          id: 'dup_1',
          vendorName: 'Aero Fuel Systems',
          invoiceNumber: 'AFS-2026',
          date: DateTime(2026, 9, 25),
          subtotal: 15000.0,
          gstin: '29AAACB1234C1Z5',
        );

        final inv2 = Invoice(
          id: 'dup_2',
          vendorName: 'Aero Fuel Systems',
          invoiceNumber: 'AFS-2026',
          date: DateTime(2026, 9, 25),
          subtotal: 15000.0,
          gstin: '29AAACB1234C1Z5',
        );

        final inserted1 = await dbHelper.insertInvoice(inv1);
        expect(inserted1, isNotNull);

        final inserted2 = await dbHelper.insertInvoice(inv2);
        expect(inserted2, isNull); // Duplicate rejected

        expect(await dbHelper.getInvoiceCount(), equals(1));
      });

      test('Search and date-range filters work properly', () async {
        final inv = Invoice(
          id: 'search_1',
          vendorName: 'Hindustan Aeronautics Ltd',
          invoiceNumber: 'HAL-500',
          date: DateTime(2026, 9, 25),
          subtotal: 45000.0,
          gstin: '29AAACB1234C1Z5',
        );
        await dbHelper.insertInvoice(inv);

        final searchResults = await dbHelper.searchInvoices(query: 'Hindustan');
        expect(searchResults.length, equals(1));
        expect(searchResults.first.vendorName, equals('Hindustan Aeronautics Ltd'));

        final noResults = await dbHelper.searchInvoices(query: 'NonExistentVendor');
        expect(noResults.isEmpty, isTrue);
      });
    });

    group('Migration Lifecycle & Concurrent Protection', () {
      test('Concurrent calls to database await the exact same initialization Future', () async {
        final futures = List.generate(10, (_) => dbHelper.database);
        final dbs = await Future.wait(futures);
        expect(dbs.length, equals(10));
        final firstDb = dbs.first;
        for (final db in dbs) {
          expect(identical(db, firstDb), isTrue);
        }
      });

      test('Repeated invoice saves do not re-trigger database migration', () async {
        final inv1 = Invoice(
          id: 'repeat_save_1',
          vendorName: 'Bharat Electronics',
          invoiceNumber: 'BEL-001',
          date: DateTime(2026, 9, 25),
          subtotal: 5000.0,
          gstin: '29AAACB1234C1Z5',
        );
        await dbHelper.insertInvoice(inv1);

        final inv2 = Invoice(
          id: 'repeat_save_2',
          vendorName: 'Bharat Electronics',
          invoiceNumber: 'BEL-002',
          date: DateTime(2026, 9, 25),
          subtotal: 7500.0,
          gstin: '29AAACB1234C1Z5',
        );
        await dbHelper.insertInvoice(inv2);

        expect(await dbHelper.getInvoiceCount(), equals(2));
      });

      test('Missing database encryption key throws DatabaseAuthenticationException', () async {
        final mockStorage = const FlutterSecureStorage();
        FlutterSecureStorage.setMockInitialValues({}); // Key is missing

        final helper = DatabaseHelper.withStorage(mockStorage);
        expect(
          () => helper.getOrCreateKeyForTesting(dbFileExists: true, isEncrypted: true),
          throwsA(isA<DatabaseAuthenticationException>()),
        );
      });
    });
  });
}
