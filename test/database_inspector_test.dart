import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tax_invoice_app/screens/database_inspector_screen.dart';
import 'package:tax_invoice_app/services/auth/auth_service.dart';
import 'package:tax_invoice_app/services/database/database_helper.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({
      'sqlite_db_secret_key': 'test_mock_secret_key_32_bytes_len_0123456789abcdef',
    });
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseInspectorScreen Unit & Widget Tests', () {
    setUp(() async {
      final db = await DatabaseHelper.instance.database;
      await db.delete('invoice_items');
      await db.delete('invoices');
      await db.delete('app_users');
    });

    testWidgets('DatabaseInspectorScreen renders debug inspector for Admin user', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        await AuthService.instance.createFirstRunAdmin(
          username: 'admin',
          password: 'AdminPassword123!',
          confirmPassword: 'AdminPassword123!',
        );
        await AuthService.instance.login(username: 'admin', password: 'AdminPassword123!');
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: DatabaseInspectorScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('SQLCipher Debug Inspector'), findsOneWidget);
      expect(find.textContaining('Read-Only Development Database Tool'), findsOneWidget);
      expect(find.text('DEBUG ONLY'), findsOneWidget);
    });

    testWidgets('DatabaseInspectorScreen loads tables and displays records', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        await AuthService.instance.createFirstRunAdmin(
          username: 'admin_test',
          password: 'AdminPassword123!',
          confirmPassword: 'AdminPassword123!',
        );
        await AuthService.instance.login(username: 'admin_test', password: 'AdminPassword123!');
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: DatabaseInspectorScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Dropdown should show selected table
      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });
  });
}
