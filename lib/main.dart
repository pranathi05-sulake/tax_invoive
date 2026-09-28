import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/first_run_admin_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth/auth_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const TaxInvoiceApp());
}

class TaxInvoiceApp extends StatelessWidget {
  const TaxInvoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaxInvoice AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F172A),
          primary: const Color(0xFF0F172A),
          secondary: const Color(0xFF10B981),
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
        fontFamily: null,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    if (AuthService.instance.isAuthenticated) {
      return const HomeScreen();
    }

    return FutureBuilder<bool>(
      future: AuthService.instance.isFirstRun(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFF8FAFC),
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF0F172A),
              ),
            ),
          );
        }

        final isFirstRun = snapshot.data ?? true;
        if (isFirstRun) {
          return const FirstRunAdminScreen();
        }

        if (!AuthService.instance.isAuthenticated) {
          return const LoginScreen();
        }

        return const HomeScreen();
      },
    );
  }
}
