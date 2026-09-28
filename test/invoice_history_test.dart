import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tax_invoice_app/models/invoice.dart';
import 'package:tax_invoice_app/screens/home_screen.dart';
import 'package:tax_invoice_app/screens/invoice_detail_screen.dart';
import 'package:tax_invoice_app/services/database/database_helper.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({'sqlite_db_secret_key': 'test_mock_secret_key_32_bytes_len_0123456789abcdef'});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Invoice makeTestInvoice({
    required String id,
    required String vendorName,
    required String invoiceNumber,
    required DateTime date,
    double subtotal = 1000.0,
    double cgst = 90.0,
    double sgst = 90.0,
  }) {
    return Invoice(
      id: id,
      vendorName: vendorName,
      gstin: '29AAACB1234C1Z5',
      invoiceNumber: invoiceNumber,
      date: date,
      subtotal: subtotal,
      cgst: cgst,
      sgst: sgst,
      igst: 0.0,
      status: InvoiceStatus.verified,
      items: [
        InvoiceItem(
          id: 'item-$id',
          description: 'Consulting Services',
          quantity: 1,
          unitPrice: subtotal,
        ),
      ],
    );
  }

  group('DatabaseHelper Search, Filter & Delete Unit Tests', () {
    setUp(() async {
      final db = await DatabaseHelper.instance.database;
      await db.delete('invoice_items');
      await db.delete('invoices');
    });

    test('searchInvoices finds by vendor name case-insensitively', () async {
      final inv1 = makeTestInvoice(
        id: '1',
        vendorName: 'Acme Solutions Ltd',
        invoiceNumber: 'INV-101',
        date: DateTime(2026, 3, 10),
      );
      final inv2 = makeTestInvoice(
        id: '2',
        vendorName: 'Beta Retailers Pvt',
        invoiceNumber: 'INV-202',
        date: DateTime(2026, 3, 15),
      );
      await DatabaseHelper.instance.insertInvoice(inv1);
      await DatabaseHelper.instance.insertInvoice(inv2);

      final resultsAcme = await DatabaseHelper.instance.searchInvoices(query: 'acme');
      expect(resultsAcme.length, 1);
      expect(resultsAcme.first.vendorName, 'Acme Solutions Ltd');

      final resultsBeta = await DatabaseHelper.instance.searchInvoices(query: 'BETA');
      expect(resultsBeta.length, 1);
      expect(resultsBeta.first.vendorName, 'Beta Retailers Pvt');
    });

    test('searchInvoices finds by invoice number', () async {
      final inv1 = makeTestInvoice(
        id: '1',
        vendorName: 'Acme Solutions Ltd',
        invoiceNumber: 'INV-101',
        date: DateTime(2026, 3, 10),
      );
      final inv2 = makeTestInvoice(
        id: '2',
        vendorName: 'Beta Retailers Pvt',
        invoiceNumber: 'INV-202',
        date: DateTime(2026, 3, 15),
      );
      await DatabaseHelper.instance.insertInvoice(inv1);
      await DatabaseHelper.instance.insertInvoice(inv2);

      final results = await DatabaseHelper.instance.searchInvoices(query: '202');
      expect(results.length, 1);
      expect(results.first.invoiceNumber, 'INV-202');
    });

    test('searchInvoices filters by date range', () async {
      final invOld = makeTestInvoice(
        id: '1',
        vendorName: 'Old Vendor',
        invoiceNumber: 'INV-001',
        date: DateTime(2026, 1, 15),
      );
      final invMid = makeTestInvoice(
        id: '2',
        vendorName: 'Mid Vendor',
        invoiceNumber: 'INV-002',
        date: DateTime(2026, 2, 15),
      );
      final invNew = makeTestInvoice(
        id: '3',
        vendorName: 'New Vendor',
        invoiceNumber: 'INV-003',
        date: DateTime(2026, 3, 15),
      );
      await DatabaseHelper.instance.insertInvoice(invOld);
      await DatabaseHelper.instance.insertInvoice(invMid);
      await DatabaseHelper.instance.insertInvoice(invNew);

      final filtered = await DatabaseHelper.instance.searchInvoices(
        startDate: DateTime(2026, 2, 1),
        endDate: DateTime(2026, 2, 28),
      );
      expect(filtered.length, 1);
      expect(filtered.first.id, '2');
    });

    test('deleteInvoice removes invoice and its cascade items', () async {
      final inv = makeTestInvoice(
        id: 'del-1',
        vendorName: 'To Delete',
        invoiceNumber: 'INV-DEL',
        date: DateTime(2026, 3, 1),
      );
      await DatabaseHelper.instance.insertInvoice(inv);

      final before = await DatabaseHelper.instance.getAllInvoices();
      expect(before.length, 1);

      final count = await DatabaseHelper.instance.deleteInvoice('del-1');
      expect(count, 1);

      final after = await DatabaseHelper.instance.getAllInvoices();
      expect(after.length, 0);
    });
  });

  group('HomeScreen Invoice History & Management Widget Tests', () {
    Future<void> resetDb(WidgetTester tester) async {
      await tester.runAsync(() async {
        await DatabaseHelper.instance.resetDatabaseForTesting();
      });
    }

    Future<void> settleScreen(WidgetTester tester) async {
      for (int i = 0; i < 15; i++) {
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets('Renders invoice list from SQLite and shows search bar', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await resetDb(tester);

      final inv = makeTestInvoice(
        id: 'inv-widget-1',
        vendorName: 'Tata Power Ltd',
        invoiceNumber: 'TP-9988',
        date: DateTime(2026, 3, 10),
      );
      await tester.runAsync(() async {
        await DatabaseHelper.instance.insertInvoice(inv);
      });

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await settleScreen(tester);

      expect(find.text('Invoice History'), findsOneWidget);
      expect(find.text('Tata Power Ltd', skipOffstage: false), findsWidgets);
      expect(find.text('TP-9988', skipOffstage: false), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Filters invoices when typing in search bar', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await resetDb(tester);

      await tester.runAsync(() async {
        await DatabaseHelper.instance.insertInvoice(
          makeTestInvoice(
            id: '1',
            vendorName: 'Infosys BPM',
            invoiceNumber: 'INF-111',
            date: DateTime(2026, 3, 1),
          ),
        );
        await DatabaseHelper.instance.insertInvoice(
          makeTestInvoice(
            id: '2',
            vendorName: 'Wipro Limited',
            invoiceNumber: 'WIP-222',
            date: DateTime(2026, 3, 2),
          ),
        );
      });

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await settleScreen(tester);

      expect(find.text('Infosys BPM', skipOffstage: false), findsWidgets);
      expect(find.text('Wipro Limited', skipOffstage: false), findsWidgets);

      // Search for Wipro
      await tester.enterText(find.byType(TextField), 'Wipro');
      await settleScreen(tester);

      expect(find.text('Infosys BPM', skipOffstage: false), findsNothing);
      expect(find.text('Wipro Limited', skipOffstage: false), findsWidgets);

      // Search for non-existent
      await tester.enterText(find.byType(TextField), 'NonExistent');
      await settleScreen(tester);

      expect(find.text('No matching invoices found', skipOffstage: false), findsOneWidget);
      expect(find.text('Clear Filters', skipOffstage: false), findsOneWidget);

      // Tap Clear Filters
      await tester.ensureVisible(find.text('Clear Filters'));
      await tester.tap(find.text('Clear Filters'));
      await settleScreen(tester);

      expect(find.text('Infosys BPM', skipOffstage: false), findsWidgets);
      expect(find.text('Wipro Limited', skipOffstage: false), findsWidgets);
    });

    testWidgets('Tapping invoice opens InvoiceDetailScreen', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await resetDb(tester);

      await tester.runAsync(() async {
        await DatabaseHelper.instance.insertInvoice(
          makeTestInvoice(
            id: '1',
            vendorName: 'Reliance Retail',
            invoiceNumber: 'REL-555',
            date: DateTime(2026, 3, 5),
          ),
        );
      });

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await settleScreen(tester);

      await tester.ensureVisible(find.text('Reliance Retail'));
      await tester.tap(find.text('Reliance Retail'));
      await settleScreen(tester);

      expect(find.byType(InvoiceDetailScreen), findsOneWidget);
      expect(find.text('Invoice Details'), findsOneWidget);
    });

    testWidgets('Delete invoice shows confirmation dialog and deletes on confirm', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await resetDb(tester);

      await tester.runAsync(() async {
        await DatabaseHelper.instance.insertInvoice(
          makeTestInvoice(
            id: '1',
            vendorName: 'Airtel Broadband',
            invoiceNumber: 'AIR-999',
            date: DateTime(2026, 3, 5),
          ),
        );
      });

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await settleScreen(tester);

      expect(find.text('Airtel Broadband'), findsOneWidget);

      // Find delete button on the list tile
      final deleteBtnFinder = find.byIcon(Icons.delete_outline_rounded);
      expect(deleteBtnFinder, findsOneWidget);

      await tester.ensureVisible(deleteBtnFinder);
      await tester.tap(deleteBtnFinder);
      await settleScreen(tester);

      // Dialog should appear
      expect(find.text('Delete Invoice'), findsOneWidget);
      expect(find.textContaining('Are you sure you want to permanently delete invoice'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      // Tap Delete to confirm
      await tester.tap(find.text('Delete'));
      await settleScreen(tester);

      // Invoice should be deleted
      expect(find.text('Airtel Broadband'), findsNothing);
      expect(find.text('No invoices processed yet'), findsOneWidget);

      await tester.runAsync(() async {
        final inDb = await DatabaseHelper.instance.getAllInvoices();
        expect(inDb.isEmpty, isTrue);
      });
    });
  });
}
