import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tax_invoice_app/main.dart';
import 'package:tax_invoice_app/screens/invoice_preview_screen.dart';
import 'package:tax_invoice_app/screens/ocr_results_screen.dart';
import 'package:tax_invoice_app/models/user.dart';
import 'package:tax_invoice_app/services/auth/auth_service.dart';
import 'package:tax_invoice_app/services/ocr/ocr_engine.dart';

class FakeOcrEngine implements OcrEngine {
  final OcrResult resultToReturn;

  FakeOcrEngine({
    this.resultToReturn = const OcrResult(
      fullText: 'TAX INVOICE\nGSTIN: 27AAAAA0000A1Z5\nTOTAL: 1500.00',
      lines: ['TAX INVOICE', 'GSTIN: 27AAAAA0000A1Z5', 'TOTAL: 1500.00'],
    ),
  });

  @override
  Future<OcrResult> processImageFile(File imageFile) async {
    return resultToReturn;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  setUpAll(() {
    // Initialize sqflite FFI for desktop/test environments
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    AuthService.instance.setTestSession(
      UserSession(
        userId: 'test_admin_id',
        username: 'admin',
        role: UserRole.admin,
        loginTimestamp: DateTime.now(),
      ),
    );

    final testFile = File('test/assets/sample_invoice.png');
    if (!testFile.existsSync()) {
      testFile.createSync(recursive: true);
    }
  });
  testWidgets('Home screen smoke test: verifies key elements', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TaxInvoiceApp());
    await tester.pumpAndSettle();

    expect(find.text('TaxInvoice AI'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Scan Invoice'), findsOneWidget);
    expect(find.text('RPA Workflow Engine'), findsWidgets);
    expect(find.text('Batch Scan Invoices'), findsWidgets);
    expect(find.text('Upload Invoice'), findsOneWidget);
    expect(find.text('Reports & Export'), findsWidgets);
    expect(find.text('Backup & Restore'), findsWidgets);
    expect(find.text('Total Processed'), findsOneWidget);
    expect(find.text('Invoice History'), findsOneWidget);
    expect(find.text('No invoices processed yet'), findsOneWidget);
  });

  testWidgets('InvoicePreviewScreen displays selected image preview and runs OCR on Process Invoice tap', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fakeEngine = FakeOcrEngine();

    await tester.pumpWidget(
      MaterialApp(
        home: InvoicePreviewScreen(
          imageFile: File('test/assets/sample_invoice.png'),
          ocrEngine: fakeEngine,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invoice Preview'), findsOneWidget);
    expect(find.text('Selected Document Image'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Process Invoice'), findsOneWidget);

    // Tap Process Invoice
    await tester.tap(find.text('Process Invoice'));
    await tester.pumpAndSettle();

    // Verify navigation to OcrResultsScreen and text display
    expect(find.text('OCR Recognition Result'), findsOneWidget);
    expect(find.textContaining('TAX INVOICE'), findsWidgets);
  });

  testWidgets('OcrResultsScreen renders extracted text and line by line toggle', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const testResult = OcrResult(
      fullText: 'RETAIL INVOICE\nGSTIN: 29ABCDE1234F1Z9\nGRAND TOTAL: INR 450.00',
      lines: ['RETAIL INVOICE', 'GSTIN: 29ABCDE1234F1Z9', 'GRAND TOTAL: INR 450.00'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OcrResultsScreen(
          imageFile: File('test/assets/sample_invoice.png'),
          ocrResult: testResult,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OCR Recognition Result'), findsOneWidget);
    expect(find.text('3 lines detected'), findsOneWidget);

    // Verify Tab toggling
    expect(find.text('Full Text View'), findsOneWidget);
    expect(find.text('Line-by-Line (3)'), findsOneWidget);

    // Switch to Line-by-Line tab
    await tester.tap(find.text('Line-by-Line (3)'));
    await tester.pumpAndSettle();

    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('#3'), findsOneWidget);

    // Verify Extract Invoice Data button
    expect(find.text('Extract Invoice Data'), findsOneWidget);
    
    // Tap Extract button
    await tester.tap(find.text('Extract Invoice Data'));
    await tester.pumpAndSettle();

    // Should navigate to InvoiceDetailScreen in edit mode
    expect(find.text('Edit Invoice'), findsOneWidget);
    expect(find.text('Vendor & Invoice Info'), findsOneWidget);
  });
}
