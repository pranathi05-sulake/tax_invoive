import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tax_invoice_app/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen renders helicopter branding, bottom features, and login card', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(),
      ),
    );
    await tester.pump();

    // Verify Title & Subtitle Branding
    expect(find.text('Invoice Processing & Verification'), findsWidgets);
    expect(find.text('HELICOPTER DIVISION'), findsWidgets);

    // Verify 4 Bottom Feature Strip items
    expect(find.text('Automated'), findsOneWidget);
    expect(find.text('Invoice Processing'), findsOneWidget);

    expect(find.text('Secure & Offline'), findsOneWidget);
    expect(find.text('Data Handling'), findsOneWidget);

    expect(find.text('Role-Based'), findsOneWidget);
    expect(find.text('Access Control'), findsOneWidget);

    expect(find.text('Comprehensive'), findsOneWidget);
    expect(find.text('Reports & Analytics'), findsOneWidget);

    // Verify Login Form elements
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Sign in to access your invoice management system.'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Remember me'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Login with QR Code'), findsOneWidget);
    expect(find.text('Secure Local Access'), findsOneWidget);
    expect(find.text('v1.0.0  |  Secure Invoice Processing • Helicopter Division'), findsOneWidget);
    expect(find.text('TaxInvoice AI © 2026'), findsOneWidget);
  });

  testWidgets('LoginScreen renders cleanly on compact / mobile viewport without overflow', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915); // Standard Android viewport
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(),
      ),
    );
    await tester.pump();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Automated'), findsOneWidget);
    expect(find.text('Secure & Offline'), findsOneWidget);
    expect(find.text('Role-Based'), findsOneWidget);
    expect(find.text('Comprehensive'), findsOneWidget);
  });
}
