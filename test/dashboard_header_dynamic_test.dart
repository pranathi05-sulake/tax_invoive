import 'package:flutter_test/flutter_test.dart';
import 'package:tax_invoice_app/models/user.dart';
import 'package:tax_invoice_app/services/auth/auth_service.dart';

String getGreetingPrefix(DateTime now) {
  final hour = now.hour;
  if (hour >= 5 && hour < 12) {
    return 'Good Morning,';
  } else if (hour >= 12 && hour < 17) {
    return 'Good Afternoon,';
  } else if (hour >= 17 && hour < 21) {
    return 'Good Evening,';
  } else {
    return 'Good Night,';
  }
}

String formatHeaderDate(DateTime dt) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final weekday = weekdays[dt.weekday - 1];
  final month = months[dt.month - 1];
  return '$weekday, ${dt.day} $month ${dt.year}';
}

String formatHeaderTime(DateTime dt) {
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minutePadded = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  return '$hour12:$minutePadded $period';
}

void main() {
  group('Dynamic Dashboard Header Greeting & Time Tests', () {
    test('Calculates greeting correctly across all time ranges', () {
      expect(getGreetingPrefix(DateTime(2026, 10, 2, 5, 0)), equals('Good Morning,'));
      expect(getGreetingPrefix(DateTime(2026, 10, 2, 8, 0)), equals('Good Morning,'));
      expect(getGreetingPrefix(DateTime(2026, 10, 2, 11, 59)), equals('Good Morning,'));

      expect(getGreetingPrefix(DateTime(2026, 10, 2, 12, 0)), equals('Good Afternoon,'));
      expect(getGreetingPrefix(DateTime(2026, 10, 2, 15, 30)), equals('Good Afternoon,'));
      expect(getGreetingPrefix(DateTime(2026, 10, 2, 16, 59)), equals('Good Afternoon,'));

      expect(getGreetingPrefix(DateTime(2026, 10, 2, 17, 0)), equals('Good Evening,'));
      expect(getGreetingPrefix(DateTime(2026, 10, 2, 19, 45)), equals('Good Evening,'));
      expect(getGreetingPrefix(DateTime(2026, 10, 2, 20, 59)), equals('Good Evening,'));

      expect(getGreetingPrefix(DateTime(2026, 10, 2, 21, 0)), equals('Good Night,'));
      expect(getGreetingPrefix(DateTime(2026, 10, 2, 23, 0)), equals('Good Night,'));
      expect(getGreetingPrefix(DateTime(2026, 10, 2, 3, 0)), equals('Good Night,'));
      expect(getGreetingPrefix(DateTime(2026, 10, 2, 4, 59)), equals('Good Night,'));
    });

    test('Formats date and time correctly', () {
      final dt = DateTime(2026, 10, 2, 21, 45);
      expect(formatHeaderDate(dt), equals('Fri, 2 Oct 2026'));
      expect(formatHeaderTime(dt), equals('9:45 PM'));

      final morningDt = DateTime(2026, 10, 3, 9, 5);
      expect(formatHeaderDate(morningDt), equals('Sat, 3 Oct 2026'));
      expect(formatHeaderTime(morningDt), equals('9:05 AM'));
    });

    test('User session and role fallbacks', () {
      final session = UserSession(
        userId: 'u1',
        username: 'Operator One',
        role: UserRole.operator,
        loginTimestamp: DateTime.now(),
      );
      AuthService.instance.setTestSession(session);

      expect(AuthService.instance.currentSession?.username, equals('Operator One'));
      expect(AuthService.instance.currentSession?.role.displayName, equals('Operator'));
    });
  });
}
