import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tax_invoice_app/models/invoice.dart';
import 'package:tax_invoice_app/models/user.dart';
import 'package:tax_invoice_app/screens/user_management_screen.dart';
import 'package:tax_invoice_app/services/auth/audit_service.dart';
import 'package:tax_invoice_app/services/auth/auth_service.dart';
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
    await db.delete('invoices');
    await db.delete('invoice_items');
    await db.delete('workflow_logs');

    auditService = AuditService(dbHelper: dbHelper);
    authService = AuthService.withDependencies(
      dbHelper: dbHelper,
      auditService: auditService,
    );
    permissionService = PermissionService(authService: authService);
  });

  group('PermissionService Matrix Tests', () {
    test('ADMIN role has full application permissions', () {
      authService.setTestSession(
        UserSession(
          userId: 'admin_1',
          username: 'admin',
          role: UserRole.admin,
          loginTimestamp: DateTime.now(),
        ),
      );

      expect(permissionService.canManageUsers(), isTrue);
      expect(permissionService.canProcessInvoices(), isTrue);
      expect(permissionService.canCaptureInvoices(), isTrue);
      expect(permissionService.canEditInvoices(), isTrue);
      expect(permissionService.canRunBatchProcessing(), isTrue);
      expect(permissionService.canRunRpa(), isTrue);
      expect(permissionService.canReviewInvoices(), isTrue);
      expect(permissionService.canApproveInvoices(), isTrue);
      expect(permissionService.canViewHistory(), isTrue);
      expect(permissionService.canViewReports(), isTrue);
      expect(permissionService.canExportReports(), isTrue);
      expect(permissionService.canBackupRestore(), isTrue);
      expect(permissionService.canAccessSecuritySettings(), isTrue);
    });

    test('OPERATOR role has processing permissions but cannot manage users or backup', () {
      authService.setTestSession(
        UserSession(
          userId: 'op_1',
          username: 'operator',
          role: UserRole.operator,
          loginTimestamp: DateTime.now(),
        ),
      );

      expect(permissionService.canManageUsers(), isFalse);
      expect(permissionService.canProcessInvoices(), isTrue);
      expect(permissionService.canCaptureInvoices(), isTrue);
      expect(permissionService.canEditInvoices(), isTrue);
      expect(permissionService.canRunBatchProcessing(), isTrue);
      expect(permissionService.canRunRpa(), isTrue);
      expect(permissionService.canReviewInvoices(), isTrue);
      expect(permissionService.canApproveInvoices(), isFalse);
      expect(permissionService.canViewHistory(), isTrue);
      expect(permissionService.canViewReports(), isFalse);
      expect(permissionService.canExportReports(), isFalse);
      expect(permissionService.canBackupRestore(), isFalse);
      expect(permissionService.canAccessSecuritySettings(), isFalse);
    });

    test('REVIEWER role has review/report permissions but cannot capture or process invoices', () {
      authService.setTestSession(
        UserSession(
          userId: 'rev_1',
          username: 'reviewer',
          role: UserRole.reviewer,
          loginTimestamp: DateTime.now(),
        ),
      );

      expect(permissionService.canManageUsers(), isFalse);
      expect(permissionService.canProcessInvoices(), isFalse);
      expect(permissionService.canCaptureInvoices(), isFalse);
      expect(permissionService.canEditInvoices(), isFalse);
      expect(permissionService.canRunBatchProcessing(), isFalse);
      expect(permissionService.canRunRpa(), isFalse);
      expect(permissionService.canReviewInvoices(), isTrue);
      expect(permissionService.canApproveInvoices(), isTrue);
      expect(permissionService.canViewHistory(), isTrue);
      expect(permissionService.canViewReports(), isTrue);
      expect(permissionService.canExportReports(), isTrue);
      expect(permissionService.canBackupRestore(), isFalse);
      expect(permissionService.canAccessSecuritySettings(), isFalse);
    });

    test('Service guards throw UnauthorizedException when unauthorized', () {
      authService.setTestSession(
        UserSession(
          userId: 'op_1',
          username: 'operator',
          role: UserRole.operator,
          loginTimestamp: DateTime.now(),
        ),
      );

      expect(() => permissionService.checkManageUsers(), throwsA(isA<UnauthorizedException>()));
      expect(() => permissionService.checkBackupRestore(), throwsA(isA<UnauthorizedException>()));
      expect(() => permissionService.checkAccessSecuritySettings(), throwsA(isA<UnauthorizedException>()));
    });
  });

  group('User Management CRUD & Last Admin Protection Tests', () {
    setUp(() async {
      await authService.createFirstRunAdmin(
        username: 'admin_primary',
        password: 'AdminPassword123',
        confirmPassword: 'AdminPassword123',
      );
    });

    test('Admin can create User, Operator, and Reviewer accounts', () async {
      final createOpRes = await authService.createUser(
        username: 'op_john',
        password: 'OpPassword123',
        confirmPassword: 'OpPassword123',
        role: UserRole.operator,
      );
      expect(createOpRes.success, isTrue);

      final createRevRes = await authService.createUser(
        username: 'rev_mary',
        password: 'RevPassword123',
        confirmPassword: 'RevPassword123',
        role: UserRole.reviewer,
      );
      expect(createRevRes.success, isTrue);

      final users = await authService.getAllUsers();
      expect(users.length, equals(3));
    });

    test('Admin can disable user and disabled user login is rejected', () async {
      await authService.createUser(
        username: 'op_to_disable',
        password: 'OpPassword123',
        confirmPassword: 'OpPassword123',
        role: UserRole.operator,
      );

      final users = await authService.getAllUsers();
      final target = users.firstWhere((u) => u.username == 'op_to_disable');

      final disableRes = await authService.setUserActive(userId: target.id, isActive: false);
      expect(disableRes.success, isTrue);

      final loginRes = await authService.login(username: 'op_to_disable', password: 'OpPassword123');
      expect(loginRes.success, isFalse);
      expect(loginRes.errorMessage, equals('Invalid username or password.'));

      // Admin re-enables user
      final enableRes = await authService.setUserActive(userId: target.id, isActive: true);
      expect(enableRes.success, isTrue);

      final reloginRes = await authService.login(username: 'op_to_disable', password: 'OpPassword123');
      expect(reloginRes.success, isTrue);
    });

    test('MANDATORY LAST ADMIN PROTECTION prevents disabling or demoting the last active Admin', () async {
      final users = await authService.getAllUsers();
      final lastAdmin = users.firstWhere((u) => u.role == UserRole.admin);

      // Attempt to disable last Admin
      final disableRes = await authService.setUserActive(userId: lastAdmin.id, isActive: false);
      expect(disableRes.success, isFalse);
      expect(disableRes.errorMessage, contains('At least one active Administrator account must remain'));

      // Attempt to demote last Admin to Operator
      final demoteRes = await authService.updateUserRole(userId: lastAdmin.id, newRole: UserRole.operator);
      expect(demoteRes.success, isFalse);
      expect(demoteRes.errorMessage, contains('At least one active Administrator account must remain'));
    });

    test('Multiple Admin accounts allow disabling or demoting when >1 active admin exists', () async {
      final createSecondAdminRes = await authService.createUser(
        username: 'admin_secondary',
        password: 'Admin2Password123',
        confirmPassword: 'Admin2Password123',
        role: UserRole.admin,
      );
      expect(createSecondAdminRes.success, isTrue);

      final users = await authService.getAllUsers();
      final secondAdmin = users.firstWhere((u) => u.username == 'admin_secondary');

      // Now 2 active admins exist -> demoting second admin succeeds
      final demoteRes = await authService.updateUserRole(userId: secondAdmin.id, newRole: UserRole.reviewer);
      expect(demoteRes.success, isTrue);

      // Now 1 active admin remains -> demoting or disabling first admin fails
      final firstAdmin = users.firstWhere((u) => u.username == 'admin_primary');
      final disableRes = await authService.setUserActive(userId: firstAdmin.id, isActive: false);
      expect(disableRes.success, isFalse);
    });

    test('Password change updates hash and allows login with new password', () async {
      final users = await authService.getAllUsers();
      final admin = users.firstWhere((u) => u.username == 'admin_primary');

      final changeRes = await authService.changeUserPassword(
        userId: admin.id,
        newPassword: 'NewPassword999',
        confirmPassword: 'NewPassword999',
      );
      expect(changeRes.success, isTrue);

      await authService.logout();

      final oldLoginRes = await authService.login(username: 'admin_primary', password: 'AdminPassword123');
      expect(oldLoginRes.success, isFalse);

      final newLoginRes = await authService.login(username: 'admin_primary', password: 'NewPassword999');
      expect(newLoginRes.success, isTrue);
    });

    test('Audit events write metadata for USER_CREATED, USER_DISABLED, USER_ENABLED, PASSWORD_CHANGED, ROLE_CHANGED', () async {
      await authService.createUser(
        username: 'audit_test_user',
        password: 'Password123',
        confirmPassword: 'Password123',
        role: UserRole.operator,
      );

      final users = await authService.getAllUsers();
      final user = users.firstWhere((u) => u.username == 'audit_test_user');

      await authService.setUserActive(userId: user.id, isActive: false);
      await authService.setUserActive(userId: user.id, isActive: true);
      await authService.updateUserRole(userId: user.id, newRole: UserRole.reviewer);
      await authService.changeUserPassword(userId: user.id, newPassword: 'NewPass123', confirmPassword: 'NewPass123');

      final logs = await auditService.getAuditLogs(limit: 100);
      final eventTypes = logs.map((l) => l.eventType).toSet();

      expect(eventTypes.contains('USER_CREATED'), isTrue);
      expect(eventTypes.contains('USER_DISABLED'), isTrue);
      expect(eventTypes.contains('USER_ENABLED'), isTrue);
      expect(eventTypes.contains('ROLE_CHANGED'), isTrue);
      expect(eventTypes.contains('PASSWORD_CHANGED'), isTrue);
    });
  });

  group('UserManagementScreen Widget Tests', () {
    testWidgets('Renders Access Denied for non-admin user', (WidgetTester tester) async {
      authService.setTestSession(
        UserSession(
          userId: 'op_1',
          username: 'operator',
          role: UserRole.operator,
          loginTimestamp: DateTime.now(),
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: UserManagementScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsOneWidget);
      expect(find.text('Administrator privileges are required to access User Management.'), findsOneWidget);
    });

    testWidgets('Renders user list for Admin user', (WidgetTester tester) async {
      await authService.createFirstRunAdmin(
        username: 'admin_ui',
        password: 'AdminPassword123',
        confirmPassword: 'AdminPassword123',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: UserManagementScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('User Management'), findsOneWidget);
      expect(find.text('admin_ui'), findsOneWidget);
      expect(find.text('Administrator'), findsOneWidget);
    });
  });

  group('Existing Invoice Functionality Integration Test', () {
    test('Invoice saving and retrieval works seamlessly with RBAC active', () async {
      final testInvoice = Invoice(
        id: 'rbac_inv_001',
        vendorName: 'Helicopter Spares Pvt Ltd',
        gstin: '27AAACH9999B1Z1',
        invoiceNumber: 'HELI-RBAC-001',
        date: DateTime.parse('2026-09-27'),
        subtotal: 12000.0,
        cgst: 1080.0,
        sgst: 1080.0,
        igst: 0.0,
        items: const [
          InvoiceItem(
            id: 'item_rbac_1',
            description: 'Avionics Calibration Service',
            quantity: 1,
            unitPrice: 12000.0,
          ),
        ],
      );

      final inserted = await dbHelper.insertInvoice(testInvoice);
      expect(inserted, isNotNull);

      final list = await dbHelper.getAllInvoices();
      expect(list.length, equals(1));
      expect(list.first.vendorName, equals('Helicopter Spares Pvt Ltd'));
    });
  });
}
