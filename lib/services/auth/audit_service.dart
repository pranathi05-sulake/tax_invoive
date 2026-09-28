import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';

class AuditLogEntry {
  final String id;
  final String eventType;
  final String actorUsername;
  final String? targetUsername;
  final String? details;
  final DateTime timestamp;

  const AuditLogEntry({
    required this.id,
    required this.eventType,
    required this.actorUsername,
    this.targetUsername,
    this.details,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'event_type': eventType,
      'actor_username': actorUsername,
      'target_username': targetUsername,
      'details': details,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory AuditLogEntry.fromMap(Map<String, dynamic> map) {
    return AuditLogEntry(
      id: map['id'] as String? ?? '',
      eventType: map['event_type'] as String? ?? '',
      actorUsername: map['actor_username'] as String? ?? '',
      targetUsername: map['target_username'] as String?,
      details: map['details'] as String?,
      timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Service responsible for recording metadata-only authentication and security audit logs into SQLCipher.
///
/// STABILITY & PRIVACY ASSURANCE:
/// - Never records passwords, hashes, salts, SQLCipher keys, invoice contents, OCR text, or financial values.
class AuditService {
  static final AuditService instance = AuditService();

  final DatabaseHelper _dbHelper;

  AuditService({DatabaseHelper? dbHelper}) : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  /// Records an audit log entry.
  Future<void> logEvent({
    required String eventType,
    required String actorUsername,
    String? targetUsername,
    String? details,
  }) async {
    try {
      final db = await _dbHelper.database;
      final entry = AuditLogEntry(
        id: 'audit_${DateTime.now().microsecondsSinceEpoch}',
        eventType: eventType,
        actorUsername: actorUsername,
        targetUsername: targetUsername,
        details: details,
        timestamp: DateTime.now(),
      );
      await db.insert('audit_logs', entry.toMap());
    } catch (e) {
      debugPrint('[AuditService] Failed to record audit log: $e');
    }
  }

  /// Retrieves recent audit log entries (metadata only).
  Future<List<AuditLogEntry>> getAuditLogs({int limit = 100}) async {
    try {
      final db = await _dbHelper.database;
      final maps = await db.query(
        'audit_logs',
        orderBy: 'timestamp DESC',
        limit: limit,
      );
      return maps.map((map) => AuditLogEntry.fromMap(map)).toList();
    } catch (e) {
      debugPrint('[AuditService] Failed to query audit logs: $e');
      return [];
    }
  }
}
