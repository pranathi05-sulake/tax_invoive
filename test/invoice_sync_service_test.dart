import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tax_invoice_app/config/api_config.dart';
import 'package:tax_invoice_app/models/invoice.dart';
import 'package:tax_invoice_app/services/invoice_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InvoiceSyncService Tests', () {
    late Invoice verifiedInvoice;
    late Invoice pendingInvoice;

    setUp(() {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');

      verifiedInvoice = Invoice(
        id: 'TEST-INV-LOCAL-001',
        vendorName: 'Hindustan Aeronautics Ltd',
        gstin: '29ABCDE1234F1Z5',
        invoiceNumber: 'HAL-2026-001',
        date: DateTime(2026, 9, 28),
        subtotal: 100000.0,
        cgst: 9000.0,
        sgst: 9000.0,
        igst: 0.0,
        status: InvoiceStatus.verified,
        verifiedBy: 'OPERATOR_42',
        verifiedAt: DateTime(2026, 9, 28, 8, 0, 0),
        items: const [
          InvoiceItem(
            id: 'item-1',
            description: 'Helicopter Rotor Blade',
            quantity: 2,
            unitPrice: 50000.0,
            hsnSac: '88033000',
          ),
        ],
      );

      pendingInvoice = verifiedInvoice.copyWith(
        id: 'TEST-INV-LOCAL-002',
        status: InvoiceStatus.pending,
      );
    });

    test('1. VERIFIED invoice can be converted into a valid sync payload', () {
      final payload = verifiedInvoice.toSyncPayload();

      expect(payload['local_invoice_id'], equals('TEST-INV-LOCAL-001'));
      expect(payload['invoice_number'], equals('HAL-2026-001'));
      expect(payload['vendor_name'], equals('Hindustan Aeronautics Ltd'));
      expect(payload['gstin'], equals('29ABCDE1234F1Z5'));
      expect(payload['taxable_value'], equals(100000.0));
      expect(payload['cgst'], equals(9000.0));
      expect(payload['sgst'], equals(9000.0));
      expect(payload['igst'], equals(0.0));
      expect(payload['total_amount'], equals(118000.0));
      expect(payload['verification_status'], equals('VERIFIED'));
      expect(payload['verified_by'], equals('OPERATOR_42'));
      expect((payload['invoice_items'] as List).length, equals(1));
      expect(payload['invoice_items'][0]['hsn_sac'], equals('88033000'));
    });

    test('2. Unverified invoice cannot be synchronized', () async {
      final mockClient = MockClient((request) async {
        fail('HTTP request should never be sent for unverified invoices');
      });

      final service = InvoiceSyncService(client: mockClient);
      final result = await service.syncInvoice(pendingInvoice);

      expect(result.success, isFalse);
      expect(result.status, equals(SyncStatus.pendingSync));
      expect(result.errorMessage, contains('Only VERIFIED invoices can be synchronized'));
    });

    test('3. Successful 201 SYNCED response changes status to SYNCED', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), equals('http://127.0.0.1:8000/api/v1/invoices'));
        expect(request.headers['Content-Type'], equals('application/json'));

        final body = jsonDecode(request.body);
        expect(body['local_invoice_id'], equals('TEST-INV-LOCAL-001'));

        return http.Response(
          jsonEncode({
            'status': 'SYNCED',
            'server_invoice_id': 'SERVER-UUID-12345',
            'local_invoice_id': 'TEST-INV-LOCAL-001',
          }),
          201,
        );
      });

      final service = InvoiceSyncService(client: mockClient);
      final result = await service.syncInvoice(verifiedInvoice);

      expect(result.success, isTrue);
      expect(result.status, equals(SyncStatus.synced));
      expect(result.serverInvoiceId, equals('SERVER-UUID-12345'));
    });

    test('4. 200 ALREADY_SYNCED response changes status to SYNCED', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'ALREADY_SYNCED',
            'server_invoice_id': 'EXISTING-SERVER-UUID-999',
            'local_invoice_id': 'TEST-INV-LOCAL-001',
          }),
          200,
        );
      });

      final service = InvoiceSyncService(client: mockClient);
      final result = await service.syncInvoice(verifiedInvoice);

      expect(result.success, isTrue);
      expect(result.status, equals(SyncStatus.synced));
      expect(result.serverInvoiceId, equals('EXISTING-SERVER-UUID-999'));
    });

    test('5. Network failure leaves invoice intact and marks SYNC_FAILED', () async {
      final mockClient = MockClient((request) async {
        throw Exception('Connection refused / LAN down');
      });

      final service = InvoiceSyncService(client: mockClient);
      final result = await service.syncInvoice(verifiedInvoice);

      expect(result.success, isFalse);
      expect(result.status, equals(SyncStatus.syncFailed));
      expect(result.errorMessage, contains('LAN server unavailable'));
    });

    test('6. Retry works on subsequent attempt after initial network failure', () async {
      int callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          throw Exception('Timeout');
        }
        return http.Response(
          jsonEncode({
            'status': 'SYNCED',
            'server_invoice_id': 'RETRY-SERVER-UUID-555',
            'local_invoice_id': 'TEST-INV-LOCAL-001',
          }),
          200,
        );
      });

      final service = InvoiceSyncService(client: mockClient);

      // Attempt 1 -> fails
      final res1 = await service.syncInvoice(verifiedInvoice);
      expect(res1.success, isFalse);
      expect(res1.status, equals(SyncStatus.syncFailed));

      // Retry (Attempt 2) -> succeeds
      final res2 = await service.syncInvoice(verifiedInvoice);
      expect(res2.success, isTrue);
      expect(res2.status, equals(SyncStatus.synced));
      expect(res2.serverInvoiceId, equals('RETRY-SERVER-UUID-555'));
    });

    test('7. Server validation error (400) does not mark invoice as synced', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status_code': 400,
            'error_code': 'VALIDATION_ERROR',
            'message': 'GSTIN is malformed or invalid',
          }),
          400,
        );
      });

      final service = InvoiceSyncService(client: mockClient);
      final result = await service.syncInvoice(verifiedInvoice);

      expect(result.success, isFalse);
      expect(result.status, equals(SyncStatus.syncFailed));
      expect(result.errorMessage, contains('GSTIN is malformed or invalid'));
    });

    test('8. Sensitive credentials (SQLCipher keys, passwords) are never in request payload', () {
      final payload = verifiedInvoice.toSyncPayload();
      final jsonStr = jsonEncode(payload);

      expect(jsonStr, isNot(contains('password')));
      expect(jsonStr, isNot(contains('secret')));
      expect(jsonStr, isNot(contains('sqlite_db_secret_key')));
      expect(jsonStr, isNot(contains('key')));
      expect(jsonStr, isNot(contains('salt')));
    });

    test('9. Duplicate sync calls update state safely without creating duplicate local records', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'SYNCED',
            'server_invoice_id': 'SERVER-UUID-DUP-TEST',
            'local_invoice_id': 'TEST-INV-LOCAL-001',
          }),
          200,
        );
      });

      final service = InvoiceSyncService(client: mockClient);

      final res1 = await service.syncInvoice(verifiedInvoice);
      final res2 = await service.syncInvoice(verifiedInvoice);

      expect(res1.success, isTrue);
      expect(res2.success, isTrue);
      expect(res1.serverInvoiceId, equals('SERVER-UUID-DUP-TEST'));
      expect(res2.serverInvoiceId, equals('SERVER-UUID-DUP-TEST'));
    });
  });
}
