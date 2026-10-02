import 'package:flutter/foundation.dart';

class ApiConfig {
  static String _baseUrl = 'http://127.0.0.1:8000';

  /// Base URL for FastAPI Company LAN backend server.
  static String get baseUrl => _baseUrl;

  /// Updates the Company LAN backend server URL.
  static void setBaseUrl(String url) {
    if (url.trim().isEmpty) return;
    String formatted = url.trim();
    if (!formatted.startsWith('http://') && !formatted.startsWith('https://')) {
      formatted = 'http://$formatted';
    }
    _baseUrl = formatted.replaceAll(RegExp(r'/$'), '');
    debugPrint('[ApiConfig] Base URL updated to: $_baseUrl');
  }

  /// LAN Endpoint for Invoice Synchronization
  static String get syncInvoiceUrl => '$_baseUrl/api/v1/invoices';

  /// LAN Endpoint for Server Health Check
  static String get healthUrl => '$_baseUrl/health';
}
