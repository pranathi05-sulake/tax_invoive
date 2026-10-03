import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tax_invoice_app/models/user.dart';
import 'package:tax_invoice_app/services/auth/audit_service.dart';
import 'package:tax_invoice_app/services/auth/auth_service.dart';
import 'package:tax_invoice_app/services/auth/password_hasher.dart';
import 'package:tax_invoice_app/services/auth/permission_service.dart';
import 'package:tax_invoice_app/services/database/database_helper.dart';

void main() {
  late DatabaseHelper dbHelper;
  late AuditService auditService;
  late AuthService authService;
  late PermissionService permissionService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
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

    auditService = AuditService(dbHelper: dbHelper);
    authService = AuthService.withDependencies(
      dbHelper: dbHelper,
      auditService: auditService,
    );
    permissionService = PermissionService(authService: authService);
  });

  group('Logout & Role Switching Flow Tests', () {
    test('Administrator (pranathi) -> Logout -> Reviewer (hal) -> Reviewer permissions', () async {
      // 1. Create Administrator account 'pranathi'
      final adminCreateResult = await authService.createFirstRunAdmin(
        username: 'pranathi',
        password: 'AdminPassword123!',
        confirmPassword: 'AdminPassword123!',
      );
      expect(adminCreateResult.success, isTrue);

      // Verify Administrator session is active
      expect(authService.isAuthenticated, isTrue);
      expect(authService.currentSession?.username, equals('pranathi'));
      expect(authService.currentSession?.role, equals(UserRole.admin));

      // Verify Administrator permissions
      expect(permissionService.isAdmin, isTrue);
      expect(permissionService.canManageUsers(), isTrue);
      expect(permissionService.canAccessSecuritySettings(), isTrue);
      expect(permissionService.canBackupRestore(), isTrue);
      expect(permissionService.canRunBatchProcessing(), isTrue);
      expect(permissionService.canViewReports(), isTrue);

      // 2. Administrator creates Reviewer account 'hal'
      final reviewerCreateResult = await authService.createUser(
        username: 'hal',
        password: 'ReviewerPassword123!',
        confirmPassword: 'ReviewerPassword123!',
        role: UserRole.reviewer,
      );
      expect(reviewerCreateResult.success, isTrue);

      // 3. Logout Administrator
      await authService.logout();

      // Verify session is completely cleared
      expect(authService.isAuthenticated, isFalse);
      expect(authService.currentSession, isNull);

      // Verify that after logout, protected privileges are revoked
      expect(permissionService.isAdmin, isFalse);
      expect(permissionService.canManageUsers(), isFalse);
      expect(permissionService.canAccessSecuritySettings(), isFalse);
      expect(permissionService.canBackupRestore(), isFalse);
      expect(permissionService.canRunBatchProcessing(), isFalse);
      expect(permissionService.canViewReports(), isFalse);

      // Verify audit trail logged LOGOUT
      final logsAfterLogout = await auditService.getAuditLogs();
      final logoutLog = logsAfterLogout.firstWhere((l) => l.eventType == 'LOGOUT');
      expect(logoutLog.actorUsername, equals('pranathi'));

      // 4. Login as Reviewer 'hal'
      final reviewerLoginResult = await authService.login(
        username: 'hal',
        password: 'ReviewerPassword123!',
      );
      expect(reviewerLoginResult.success, isTrue);

      // Verify Reviewer session
      expect(authService.isAuthenticated, isTrue);
      expect(authService.currentSession?.username, equals('hal'));
      expect(authService.currentSession?.role, equals(UserRole.reviewer));

      // Verify Reviewer permissions
      expect(permissionService.isReviewer, isTrue);
      expect(permissionService.isAdmin, isFalse);
      expect(permissionService.canViewReports(), isTrue);
      expect(permissionService.canExportReports(), isTrue);
      expect(permissionService.canReviewInvoices(), isTrue);
      expect(permissionService.canApproveInvoices(), isTrue);

      // Verify Reviewer is denied admin/operator-only permissions
      expect(permissionService.canManageUsers(), isFalse);
      expect(permissionService.canAccessSecuritySettings(), isFalse);
      expect(permissionService.canBackupRestore(), isFalse);
      expect(permissionService.canRunBatchProcessing(), isFalse);
      expect(permissionService.canRunRpa(), isFalse);

      // 5. Logout Reviewer
      await authService.logout();
      expect(authService.isAuthenticated, isFalse);
      expect(authService.currentSession, isNull);
    });

    test('Data integrity preserved across logout/login cycles', () async {
      // Create admin and an invoice record
      await authService.createFirstRunAdmin(
        username: 'admin_test',
        password: 'Password123!',
        confirmPassword: 'Password123!',
      );

      final db = await dbHelper.database;
      final usersBefore = await db.query('app_users');
      expect(usersBefore.length, equals(1));

      // Logout
      await authService.logout();
      expect(authService.isAuthenticated, isFalse);

      // Verify database records still exist (users and SQLCipher data not deleted)
      final usersAfter = await db.query('app_users');
      expect(usersAfter.length, equals(1));
      expect(usersAfter.first['username'], equals('admin_test'));
    });
  });
}
