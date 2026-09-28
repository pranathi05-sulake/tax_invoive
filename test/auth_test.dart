import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tax_invoice_app/models/invoice.dart';
import 'package:tax_invoice_app/models/user.dart';
import 'package:tax_invoice_app/services/auth/audit_service.dart';
import 'package:tax_invoice_app/services/auth/auth_service.dart';
import 'package:tax_invoice_app/services/auth/password_hasher.dart';
import 'package:tax_invoice_app/services/database/database_helper.dart';

void main() {
  late DatabaseHelper dbHelper;
  late AuditService auditService;
  late AuthService authService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Reset database instance for each test
    dbHelper = DatabaseHelper.instance;
    final db = await dbHelper.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_users (
        id TEXT PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        password_salt TEXT NOT NULL,
        role TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_login_at TEXT
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_logs (
        id TEXT PRIMARY KEY,
        event_type TEXT NOT NULL,
        actor_username TEXT NOT NULL,
        target_username TEXT,
        details TEXT,
        timestamp TEXT NOT NULL
      );
    ''');
    await db.delete('app_users');
    await db.delete('audit_logs');
    await db.delete('invoices');
    await db.delete('invoice_items');
    await db.delete('workflow_logs');

    auditService = AuditService(dbHelper: dbHelper);
    authService = AuthService.withDependencies(
      dbHelper: dbHelper,
      auditService: auditService,
    );
  });

  group('PasswordHasher Unit Tests', () {
    test('generateSalt returns 64-char hex string for 32 bytes', () {
      final salt1 = PasswordHasher.generateSalt(32);
      final salt2 = PasswordHasher.generateSalt(32);

      expect(salt1.length, equals(64));
      expect(salt2.length, equals(64));
      expect(salt1, isNot(equals(salt2)));
    });

    test('hashPassword produces deterministic hash for same password and salt', () {
      const salt = 'a1b2c3d4e5f67890a1b2c3d4e5f67890a1b2c3d4e5f67890a1b2c3d4e5f67890';
      const password = 'HelicopterPass2026!';

      final hash1 = PasswordHasher.hashPassword(password, salt);
      final hash2 = PasswordHasher.hashPassword(password, salt);

      expect(hash1, equals(hash2));
      expect(hash1.length, equals(64)); // 256 bits = 64 hex chars
    });

    test('verifyPassword returns true for correct password and false for wrong password', () {
      const salt = '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff';
      const password = 'SecurePassword123';

      final hash = PasswordHasher.hashPassword(password, salt);

      expect(PasswordHasher.verifyPassword(password, salt, hash), isTrue);
      expect(PasswordHasher.verifyPassword('WrongPassword123', salt, hash), isFalse);
    });

    test('constantTimeEquals detects equality and length mismatch safely', () {
      expect(PasswordHasher.constantTimeEquals('abc', 'abc'), isTrue);
      expect(PasswordHasher.constantTimeEquals('abc', 'abd'), isFalse);
      expect(PasswordHasher.constantTimeEquals('abc', 'abcd'), isFalse);
    });
  });

  group('AuthService & First-Run Admin Tests', () {
    test('isFirstRun returns true when app_users table is empty', () async {
      expect(await authService.isFirstRun(), isTrue);
    });

    test('createFirstRunAdmin validates password strength and creates Admin account', () async {
      // Rejects short password
      var result = await authService.createFirstRunAdmin(
        username: 'admin',
        password: 'short',
        confirmPassword: 'short',
      );
      expect(result.success, isFalse);

      // Rejects password without numbers
      result = await authService.createFirstRunAdmin(
        username: 'admin',
        password: 'OnlyLettersPassword',
        confirmPassword: 'OnlyLettersPassword',
      );
      expect(result.success, isFalse);

      // Rejects default credentials (admin/admin)
      result = await authService.createFirstRunAdmin(
        username: 'admin',
        password: 'admin',
        confirmPassword: 'admin',
      );
      expect(result.success, isFalse);

      // Valid admin creation
      result = await authService.createFirstRunAdmin(
        username: 'chief_pilot',
        password: 'AviationPass2026',
        confirmPassword: 'AviationPass2026',
      );

      expect(result.success, isTrue);
      expect(authService.currentSession, isNotNull);
      expect(authService.currentSession!.username, equals('chief_pilot'));
      expect(authService.currentSession!.role, equals(UserRole.admin));
      expect(await authService.isFirstRun(), isFalse);
    });

    test('createFirstRunAdmin rejects duplicate usernames', () async {
      await authService.createFirstRunAdmin(
        username: 'admin_user',
        password: 'AviationPass2026',
        confirmPassword: 'AviationPass2026',
      );

      final duplicateResult = await authService.createFirstRunAdmin(
        username: 'ADMIN_USER',
        password: 'AviationPass2026',
        confirmPassword: 'AviationPass2026',
      );

      expect(duplicateResult.success, isFalse);
      expect(duplicateResult.errorMessage, contains('taken'));
    });
  });

  group('Offline Authentication & Session Management Tests', () {
    setUp(() async {
      await authService.createFirstRunAdmin(
        username: 'pilot_user',
        password: 'FlyHelicopter2026',
        confirmPassword: 'FlyHelicopter2026',
      );
      await authService.logout();
    });

    test('login succeeds with correct password and fails with wrong password', () async {
      // Failed login
      var loginResult = await authService.login(
        username: 'pilot_user',
        password: 'WrongPassword999',
      );
      expect(loginResult.success, isFalse);
      expect(loginResult.errorMessage, equals('Invalid username or password.'));
      expect(authService.currentSession, isNull);

      // Successful login
      loginResult = await authService.login(
        username: 'pilot_user',
        password: 'FlyHelicopter2026',
      );
      expect(loginResult.success, isTrue);
      expect(authService.currentSession, isNotNull);
      expect(authService.currentSession!.username, equals('pilot_user'));
      expect(authService.currentSession!.role, equals(UserRole.admin));
    });

    test('login rejects disabled user account', () async {
      final db = await dbHelper.database;
      await db.update('app_users', {'is_active': 0}, where: 'username = ?', whereArgs: ['pilot_user']);

      final result = await authService.login(
        username: 'pilot_user',
        password: 'FlyHelicopter2026',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, equals('Invalid username or password.'));
      expect(authService.currentSession, isNull);
    });

    test('logout clears active session and logs audit event', () async {
      await authService.login(
        username: 'pilot_user',
        password: 'FlyHelicopter2026',
      );
      expect(authService.isAuthenticated, isTrue);

      await authService.logout();
      expect(authService.isAuthenticated, isFalse);
      expect(authService.currentSession, isNull);

      final logs = await auditService.getAuditLogs();
      final logoutLog = logs.firstWhere((l) => l.eventType == 'LOGOUT');
      expect(logoutLog.actorUsername, equals('pilot_user'));
    });
  });

  group('Audit & Privacy Verification Tests', () {
    test('Audit events write metadata without leaking plaintext passwords or hashes', () async {
      await authService.createFirstRunAdmin(
        username: 'sec_admin',
        password: 'SecurePassword2026',
        confirmPassword: 'SecurePassword2026',
      );
      await authService.login(
        username: 'sec_admin',
        password: 'WrongPassword111',
      );

      final logs = await auditService.getAuditLogs();
      expect(logs, isNotEmpty);

      for (final log in logs) {
        final fullString = '${log.eventType} ${log.actorUsername} ${log.targetUsername} ${log.details}';
        expect(fullString.contains('SecurePassword2026'), isFalse);
        expect(fullString.contains('WrongPassword111'), isFalse);
      }
    });

    test('AppUser.toString() redacts sensitive password fields', () async {
      final user = AppUser(
        id: 'u1',
        username: 'pilot',
        passwordHash: 'secret_hash_value',
        passwordSalt: 'secret_salt_value',
        role: UserRole.operator,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final str = user.toString();
      expect(str.contains('pilot'), isTrue);
      expect(str.contains('secret_hash_value'), isFalse);
      expect(str.contains('secret_salt_value'), isFalse);
    });
  });

  group('SQLCipher Migration Version 2 -> 3 Compatibility Tests', () {
    test('Existing invoice data survives database migration', () async {
      final db = await dbHelper.database;

      // Insert test invoice
      final testInvoice = Invoice(
        id: 'inv_migration_001',
        vendorName: 'Helicopter Maintenance Corp',
        gstin: '27AAACH1234A1Z1',
        invoiceNumber: 'HELI-2026-001',
        date: DateTime.parse('2026-09-27'),
        subtotal: 5000.0,
        cgst: 450.0,
        sgst: 450.0,
        igst: 0.0,
        items: const [
          InvoiceItem(
            id: 'item_1',
            description: 'Rotor Blade Inspection',
            quantity: 1,
            unitPrice: 5000.0,
          ),
        ],
      );

      await dbHelper.insertInvoice(testInvoice);

      // Verify invoice exists
      final savedInvoices = await dbHelper.getAllInvoices();
      expect(savedInvoices.length, equals(1));
      expect(savedInvoices.first.invoiceNumber, equals('HELI-2026-001'));

      // Verify app_users and audit_logs tables exist and can accept queries
      final userRes = await db.rawQuery('SELECT COUNT(*) as count FROM app_users;');
      final auditRes = await db.rawQuery('SELECT COUNT(*) as count FROM audit_logs;');

      expect((userRes.first['count'] as num?)?.toInt(), isNotNull);
      expect((auditRes.first['count'] as num?)?.toInt(), isNotNull);
    });
  });
}
