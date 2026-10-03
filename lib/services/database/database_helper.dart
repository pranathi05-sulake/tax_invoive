import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart' show databaseFactoryFfiWeb;
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../models/invoice.dart';

class DatabaseAuthenticationException implements Exception {
  final String message;
  const DatabaseAuthenticationException(this.message);
  @override
  String toString() => 'DatabaseAuthenticationException: $message';
}

class WorkflowLogEntry {
  final String id;
  final String executionId;
  final String invoiceId;
  final String sourcePath;
  final String step;
  final String status;
  final String message;
  final DateTime timestamp;

  const WorkflowLogEntry({
    required this.id,
    required this.executionId,
    this.invoiceId = '',
    this.sourcePath = '',
    required this.step,
    required this.status,
    required this.message,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'execution_id': executionId,
      'invoice_id': invoiceId.trim().isNotEmpty ? invoiceId : null,
      'source_path': sourcePath,
      'step': step,
      'status': status,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory WorkflowLogEntry.fromMap(Map<String, dynamic> map) {
    return WorkflowLogEntry(
      id: map['id'] as String? ?? '',
      executionId: map['execution_id'] as String? ?? '',
      invoiceId: map['invoice_id'] as String? ?? '',
      sourcePath: map['source_path'] as String? ?? '',
      step: map['step'] as String? ?? '',
      status: map['status'] as String? ?? '',
      message: map['message'] as String? ?? '',
      timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static Future<Database>? _initDbFuture;
  final FlutterSecureStorage _secureStorage;

  static const String _keyDbEncryptionSecret = 'sqlite_db_secret_key';

  DatabaseHelper._init({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  @visibleForTesting
  DatabaseHelper.withStorage(FlutterSecureStorage storage)
      : _secureStorage = storage;

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _initDbFuture ??= _initDB('invoices.db');
    try {
      _database = await _initDbFuture!;
      return _database!;
    } catch (e) {
      _initDbFuture = null;
      rethrow;
    }
  }

  /// Inspects the first 16 bytes of a database file to check if it is plaintext SQLite3.
  static Future<bool> isDatabaseEncrypted(File file) async {
    if (kIsWeb) return false;
    if (!await file.exists()) return false;
    final length = await file.length();
    if (length < 16) return false;
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final header = await raf.read(16);
      const sqliteHeader = [
        0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00
      ];
      for (int i = 0; i < 16; i++) {
        if (header[i] != sqliteHeader[i]) return true; // Encrypted (non-standard header)
      }
      return false; // Standard Plaintext SQLite3 Header
    } catch (e) {
      debugPrint('[DatabaseHelper] Error checking database header: $e');
      return false;
    } finally {
      await raf?.close();
    }
  }

  /// Retrieves or creates the database encryption key in Android Keystore secure storage.
  Future<String> _getOrCreateDatabaseKey({
    required bool dbFileExists,
    required bool isEncrypted,
  }) async {
    String? key;
    try {
      key = await _secureStorage.read(key: _keyDbEncryptionSecret);
    } catch (e) {
      debugPrint('[DatabaseHelper] Exception reading secure storage key: $e');
    }

    if (key != null && key.trim().isNotEmpty) {
      return key.trim();
    }

    // STRICT FAIL-SAFE: If database file exists AND is encrypted, NEVER generate a replacement key!
    if (dbFileExists && isEncrypted) {
      throw const DatabaseAuthenticationException(
        'Database encryption key missing or inaccessible from Android Keystore secure storage. Cannot unlock existing encrypted database.',
      );
    }

    // Generate a new 256-bit cryptographically secure key (64 hex chars)
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    final newKey = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    try {
      await _secureStorage.write(key: _keyDbEncryptionSecret, value: newKey);
    } catch (e) {
      debugPrint('[DatabaseHelper] Exception writing new key to secure storage: $e');
    }

    return newKey;
  }

  @visibleForTesting
  Future<String> getOrCreateKeyForTesting({
    required bool dbFileExists,
    required bool isEncrypted,
  }) =>
      _getOrCreateDatabaseKey(
        dbFileExists: dbFileExists,
        isEncrypted: isEncrypted,
      );

  @visibleForTesting
  Future<Database> openSqlDatabaseForTesting(
    String path, {
    required String password,
    int? version,
    OnDatabaseCreateFn? onCreate,
    OnDatabaseVersionChangeFn? onUpgrade,
    bool readOnly = false,
  }) =>
      _openSqlDatabase(
        path,
        password: password,
        version: version,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
        readOnly: readOnly,
      );

  Future<String> _getDatabasesDirectoryPath() async {
    try {
      return await databaseFactory.getDatabasesPath();
    } catch (_) {
      try {
        return await databaseFactoryFfi.getDatabasesPath();
      } catch (_) {
        return 'invoices.db';
      }
    }
  }

  Future<Database> _openSqlDatabase(
    String path, {
    required String password,
    int? version,
    OnDatabaseCreateFn? onCreate,
    OnDatabaseVersionChangeFn? onUpgrade,
    bool readOnly = false,
  }) async {
    final effectiveVersion = readOnly ? null : version;
    final effectiveOnCreate = readOnly ? null : onCreate;
    final effectiveOnUpgrade = readOnly ? null : onUpgrade;

    if (kIsWeb) {
      return await databaseFactoryFfiWeb.openDatabase(
        path,
        options: OpenDatabaseOptions(
          readOnly: readOnly,
          version: effectiveVersion,
          onCreate: effectiveOnCreate,
          onUpgrade: effectiveOnUpgrade,
          onConfigure: _onConfigure,
        ),
      );
    }

    try {
      return await openDatabase(
        path,
        password: password,
        readOnly: readOnly,
        version: effectiveVersion,
        onCreate: effectiveOnCreate,
        onUpgrade: effectiveOnUpgrade,
        onConfigure: _onConfigure,
      );
    } catch (_) {
      return await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          readOnly: readOnly,
          version: effectiveVersion,
          onCreate: effectiveOnCreate,
          onUpgrade: effectiveOnUpgrade,
          onConfigure: _onConfigure,
        ),
      );
    }
  }

  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON;');
  }

  Future<Database> _initDB(String filePath) async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }

    if (kIsWeb) {
      _database = _WebMemoryDatabase();
      return _database!;
    }

    final dbPath = await _getDatabasesDirectoryPath();
    final path = join(dbPath, filePath);
    final dbFile = File(path);

    final dbExists = await dbFile.exists();
    final isEncrypted = await isDatabaseEncrypted(dbFile);

    final dbKey = await _getOrCreateDatabaseKey(
      dbFileExists: dbExists,
      isEncrypted: isEncrypted,
    );

    final statusFile = File(join(dbPath, 'migration_status.json'));
    final migratingFile = File(join(dbPath, 'invoices_migrating.db.tmp'));
    final legacyTmpFile = File(join(dbPath, 'invoices_legacy.tmp'));

    // Check for crash recovery state or pending migration
    if (await statusFile.exists() || (dbExists && !isEncrypted)) {
      await _executeStagedMigrationWithRecovery(
        dbFile: dbFile,
        dbPath: path,
        dbDir: dbPath,
        derivedKey: dbKey,
        statusFile: statusFile,
        migratingFile: migratingFile,
        legacyTmpFile: legacyTmpFile,
      );
    }

    return await _openSqlDatabase(
      path,
      password: dbKey,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  /// Staged Migration Engine with Crash-Recovery State Machine
  Future<void> _executeStagedMigrationWithRecovery({
    required File dbFile,
    required String dbPath,
    required String dbDir,
    required String derivedKey,
    required File statusFile,
    required File migratingFile,
    required File legacyTmpFile,
  }) async {
    Map<String, dynamic> status = {};
    if (await statusFile.exists()) {
      try {
        status = jsonDecode(await statusFile.readAsString());
      } catch (_) {}
    }

    final currentPhase = status['phase'] as String? ?? 'IDLE';

    // Handle Crash Recovery Scenarios
    if (currentPhase == 'REPLACEMENT_SUCCESS' || (await dbFile.exists() && await isDatabaseEncrypted(dbFile))) {
      // Step 4B completed prior to crash -> clean up temporary legacy files
      if (await legacyTmpFile.exists()) await legacyTmpFile.delete();
      if (await migratingFile.exists()) await migratingFile.delete();
      if (await statusFile.exists()) await statusFile.delete();
      return;
    }

    if (currentPhase == 'RENAME_STEP_A' && await legacyTmpFile.exists() && await migratingFile.exists()) {
      // Interrupted right after Step 4A (invoices.db -> invoices_legacy.tmp)
      await migratingFile.rename(dbPath);
      if (await legacyTmpFile.exists()) await legacyTmpFile.delete();
      if (await statusFile.exists()) await statusFile.delete();
      return;
    }

    // Otherwise clean up incomplete temporary migration files before restarting
    if (await migratingFile.exists()) await migratingFile.delete();

    if (!await dbFile.exists() && await legacyTmpFile.exists()) {
      await legacyTmpFile.rename(dbPath);
    }

    if (!await dbFile.exists()) return;

    // Check if db is already encrypted
    if (await isDatabaseEncrypted(dbFile)) return;

    // Phase 1: Preparation (Check storage space & initialize status)
    final dbSize = await dbFile.length();
    final freeSpaceRequired = dbSize * 2.5;
    debugPrint('[DatabaseHelper] Starting 5-Phase Staged Migration for $dbSize bytes...');

    await statusFile.writeAsString(jsonEncode({'phase': 'PREPARATION', 'timestamp': DateTime.now().toIso8601String()}));

    // Phase 2: Candidate Export (SQLCipher on Native Mobile, Copy on Desktop FFI Test)
    final migratingPath = migratingFile.path;
    final isNativeMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    if (isNativeMobile) {
      // Ensure target directory exists and stale candidate file is removed
      await migratingFile.parent.create(recursive: true);
      if (await migratingFile.exists()) {
        await migratingFile.delete();
      }

      // Must be opened as writable connection (readOnly: false) so SQLite can create & attach candidate file
      final unencryptedDb = await _openSqlDatabase(
        dbPath,
        password: '',
        readOnly: false,
        version: 3,
        onCreate: (_, __) async {},
        onUpgrade: (_, __, ___) async {},
      );

      try {
        final escapedKey = derivedKey.replaceAll("'", "''");
        try {
          await unencryptedDb.execute("DETACH DATABASE encrypted;");
        } catch (_) {}

        try {
          await unencryptedDb.execute("ATTACH DATABASE '$migratingPath' AS encrypted KEY '$escapedKey';");
        } catch (_) {
          // Catch and throw sanitized exception to NEVER expose encryption key in SQLite logs or stack traces
          throw Exception('Failed to attach candidate database during SQLCipher migration.');
        }

        // Must use rawQuery (SELECT) for sqlcipher_export under sqflite_sqlcipher
        await unencryptedDb.rawQuery("SELECT sqlcipher_export('encrypted');");

        try {
          await unencryptedDb.execute("DETACH DATABASE encrypted;");
        } catch (_) {}
      } finally {
        await unencryptedDb.close();
      }
    } else {
      await dbFile.copy(migratingPath);
    }

    await statusFile.writeAsString(jsonEncode({'phase': 'EXPORT_COMPLETE', 'timestamp': DateTime.now().toIso8601String()}));

    // Phase 3: Strict Verification Suite
    final verifiedDb = await _openSqlDatabase(migratingPath, password: derivedKey, version: 2, onCreate: (_, __) async {}, onUpgrade: (_, __, ___) async {});
    try {
      final integrity = await verifiedDb.rawQuery('PRAGMA integrity_check;');
      if (integrity.isEmpty || integrity.first.values.first != 'ok') {
        throw Exception('SQLCipher integrity check failed on migrated candidate database.');
      }

      final tables = await verifiedDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table';");
      final tableNames = tables.map((t) => t['name'] as String).toSet();
      if (!tableNames.contains('invoices') || !tableNames.contains('invoice_items')) {
        throw Exception('Migrated database missing critical invoice tables.');
      }

      // Verify row counts match plaintext original
      final plaintextDb = await _openSqlDatabase(dbPath, password: '', readOnly: true, version: 2, onCreate: (_, __) async {}, onUpgrade: (_, __, ___) async {});
      final plainInvoiceCount = Sqflite.firstIntValue(await plaintextDb.rawQuery('SELECT COUNT(*) FROM invoices;')) ?? 0;
      final plainItemCount = Sqflite.firstIntValue(await plaintextDb.rawQuery('SELECT COUNT(*) FROM invoice_items;')) ?? 0;
      int plainLogCount = 0;
      try {
        plainLogCount = Sqflite.firstIntValue(await plaintextDb.rawQuery('SELECT COUNT(*) FROM workflow_logs;')) ?? 0;
      } catch (_) {}
      await plaintextDb.close();

      final encInvoiceCount = Sqflite.firstIntValue(await verifiedDb.rawQuery('SELECT COUNT(*) FROM invoices;')) ?? 0;
      final encItemCount = Sqflite.firstIntValue(await verifiedDb.rawQuery('SELECT COUNT(*) FROM invoice_items;')) ?? 0;
      int encLogCount = 0;
      try {
        encLogCount = Sqflite.firstIntValue(await verifiedDb.rawQuery('SELECT COUNT(*) FROM workflow_logs;')) ?? 0;
      } catch (_) {}

      if (plainInvoiceCount != encInvoiceCount || plainItemCount != encItemCount || plainLogCount != encLogCount) {
        throw Exception(
          'Row count mismatch during migration: Invoices ($plainInvoiceCount vs $encInvoiceCount), Items ($plainItemCount vs $encItemCount), Logs ($plainLogCount vs $encLogCount).',
        );
      }

      // Execute sample read query
      await verifiedDb.query('invoices', limit: 5);
      await verifiedDb.query('invoice_items', limit: 5);
    } finally {
      await verifiedDb.close();
    }

    await statusFile.writeAsString(jsonEncode({'phase': 'VERIFICATION_PASSED', 'timestamp': DateTime.now().toIso8601String()}));

    // Phase 4: Staged Replacement & Reopening
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
    await Future.delayed(const Duration(milliseconds: 50));

    await statusFile.writeAsString(jsonEncode({'phase': 'RENAME_STEP_A', 'timestamp': DateTime.now().toIso8601String()}));
    try {
      await dbFile.rename(legacyTmpFile.path);
    } catch (_) {
      await dbFile.copy(legacyTmpFile.path);
      if (await dbFile.exists()) await dbFile.delete();
    }

    await statusFile.writeAsString(jsonEncode({'phase': 'RENAME_STEP_B', 'timestamp': DateTime.now().toIso8601String()}));
    try {
      await migratingFile.rename(dbPath);
    } catch (_) {
      await migratingFile.copy(dbPath);
      if (await migratingFile.exists()) await migratingFile.delete();
    }

    // Verify newly placed encrypted database opens
    final testHandle = await _openSqlDatabase(dbPath, password: derivedKey, version: 3, onCreate: (_, __) async {}, onUpgrade: (_, __, ___) async {});
    await testHandle.query('invoices', limit: 1);
    await testHandle.close();

    await statusFile.writeAsString(jsonEncode({'phase': 'REPLACEMENT_SUCCESS', 'timestamp': DateTime.now().toIso8601String()}));

    // Phase 5: Plaintext File Removal & 6-Point Post-Migration Cleanup Verification
    if (await legacyTmpFile.exists()) {
      await legacyTmpFile.delete(); // Plaintext database file is removed after successful encrypted migration
    }
    if (await statusFile.exists()) {
      await statusFile.delete();
    }

    // 6-Point Verification
    final isEnc = await isDatabaseEncrypted(File(dbPath));
    if (!isEnc && isNativeMobile) throw Exception('Post-migration check failed: invoices.db is not encrypted.');
    if (await legacyTmpFile.exists()) throw Exception('Post-migration check failed: invoices_legacy.tmp still exists.');
    if (await migratingFile.exists()) throw Exception('Post-migration check failed: invoices_migrating.db.tmp still exists.');
    if (await statusFile.exists()) throw Exception('Post-migration check failed: migration_status.json still exists.');

    debugPrint('[DatabaseHelper] Staged Migration to SQLCipher 256-bit AES completed successfully.');
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE invoices (
        id TEXT PRIMARY KEY,
        vendor_name TEXT,
        gstin TEXT,
        invoice_number TEXT,
        date TEXT,
        subtotal REAL,
        cgst REAL,
        sgst REAL,
        igst REAL,
        status INTEGER,
        sync_status TEXT DEFAULT 'PENDING_SYNC',
        sync_attempts INTEGER DEFAULT 0,
        last_sync_attempt TEXT,
        last_sync_error TEXT,
        server_invoice_id TEXT,
        synced_at TEXT,
        verified_by TEXT,
        verified_at TEXT,
        UNIQUE(gstin, invoice_number, date) ON CONFLICT IGNORE
      )
    ''');

    await db.execute('''
      CREATE TABLE invoice_items (
        id TEXT PRIMARY KEY,
        invoice_id TEXT,
        description TEXT,
        quantity INTEGER,
        unit_price REAL,
        hsn_sac TEXT DEFAULT '00000000',
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS workflow_logs (
        id TEXT PRIMARY KEY,
        execution_id TEXT,
        invoice_id TEXT,
        source_path TEXT,
        step TEXT,
        status TEXT,
        message TEXT,
        timestamp TEXT,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
      )
    ''');

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
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_logs (
        id TEXT PRIMARY KEY,
        event_type TEXT NOT NULL,
        actor_username TEXT NOT NULL,
        target_username TEXT,
        details TEXT,
        timestamp TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS workflow_logs (
          id TEXT PRIMARY KEY,
          execution_id TEXT,
          invoice_id TEXT,
          source_path TEXT,
          step TEXT,
          status TEXT,
          message TEXT,
          timestamp TEXT
        )
      ''');
    }
    if (oldVersion < 3) {
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
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS audit_logs (
          id TEXT PRIMARY KEY,
          event_type TEXT NOT NULL,
          actor_username TEXT NOT NULL,
          target_username TEXT,
          details TEXT,
          timestamp TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      final alterQueries = [
        "ALTER TABLE invoices ADD COLUMN sync_status TEXT DEFAULT 'PENDING_SYNC';",
        "ALTER TABLE invoices ADD COLUMN sync_attempts INTEGER DEFAULT 0;",
        "ALTER TABLE invoices ADD COLUMN last_sync_attempt TEXT;",
        "ALTER TABLE invoices ADD COLUMN last_sync_error TEXT;",
        "ALTER TABLE invoices ADD COLUMN server_invoice_id TEXT;",
        "ALTER TABLE invoices ADD COLUMN synced_at TEXT;",
        "ALTER TABLE invoices ADD COLUMN verified_by TEXT;",
        "ALTER TABLE invoices ADD COLUMN verified_at TEXT;",
        "ALTER TABLE invoice_items ADD COLUMN hsn_sac TEXT DEFAULT '00000000';",
      ];
      for (final query in alterQueries) {
        try {
          await db.execute(query);
        } catch (e) {
          debugPrint('[DatabaseHelper] v4 Migration query note: $e');
        }
      }
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS workflow_logs_temp (
          id TEXT PRIMARY KEY,
          execution_id TEXT,
          invoice_id TEXT,
          source_path TEXT,
          step TEXT,
          status TEXT,
          message TEXT,
          timestamp TEXT,
          FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
        )
      ''');
      try {
        await db.execute('''
          INSERT INTO workflow_logs_temp (id, execution_id, invoice_id, source_path, step, status, message, timestamp)
          SELECT id, execution_id, invoice_id, source_path, step, status, message, timestamp
          FROM workflow_logs;
        ''');
        await db.execute('DROP TABLE workflow_logs;');
        await db.execute('ALTER TABLE workflow_logs_temp RENAME TO workflow_logs;');
      } catch (e) {
        debugPrint('[DatabaseHelper] v5 Migration note: $e');
      }
    }
  }

  Future<Invoice?> insertInvoice(Invoice invoice) async {
    final db = await instance.database;
    final id = await db.insert('invoices', invoice.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id == 0) return null;

    for (final item in invoice.items) {
      await db.insert('invoice_items', item.toMap(invoice.id));
    }
    return invoice;
  }

  Future<void> updateInvoiceSyncState({
    required String invoiceId,
    required String syncStatus,
    bool incrementAttempts = false,
    String? lastSyncAttempt,
    String? lastSyncError,
    String? serverInvoiceId,
    String? syncedAt,
    String? verifiedBy,
    String? verifiedAt,
  }) async {
    final db = await instance.database;
    final updates = <String, dynamic>{
      'sync_status': syncStatus,
    };

    if (lastSyncAttempt != null) updates['last_sync_attempt'] = lastSyncAttempt;
    if (lastSyncError != null) updates['last_sync_error'] = lastSyncError;
    if (serverInvoiceId != null) updates['server_invoice_id'] = serverInvoiceId;
    if (syncedAt != null) updates['synced_at'] = syncedAt;
    if (verifiedBy != null) updates['verified_by'] = verifiedBy;
    if (verifiedAt != null) updates['verified_at'] = verifiedAt;

    if (incrementAttempts) {
      await db.rawUpdate('''
        UPDATE invoices 
        SET sync_status = ?,
            sync_attempts = sync_attempts + 1,
            last_sync_attempt = COALESCE(?, last_sync_attempt),
            last_sync_error = COALESCE(?, last_sync_error),
            server_invoice_id = COALESCE(?, server_invoice_id),
            synced_at = COALESCE(?, synced_at)
        WHERE id = ?
      ''', [
        syncStatus,
        lastSyncAttempt,
        lastSyncError,
        serverInvoiceId,
        syncedAt,
        invoiceId,
      ]);
    } else {
      await db.update(
        'invoices',
        updates,
        where: 'id = ?',
        whereArgs: [invoiceId],
      );
    }
  }

  Future<List<Invoice>> getAllInvoices() async {
    final db = await instance.database;
    final invoiceMaps = await db.query('invoices', orderBy: 'date DESC');

    List<Invoice> invoices = [];
    for (var invoiceMap in invoiceMaps) {
      final itemsMaps = await db.query(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [invoiceMap['id']],
      );
      final items = itemsMaps.map((map) => InvoiceItem.fromMap(map)).toList();
      invoices.add(Invoice.fromMap(invoiceMap, items: items));
    }
    return invoices;
  }

  Future<List<Invoice>> searchInvoices({
    String? query,
    DateTime? startDate,
    DateTime? endDate,
    InvoiceStatus? status,
  }) async {
    final db = await instance.database;
    final List<String> whereClauses = [];
    final List<dynamic> whereArgs = [];

    if (query != null && query.trim().isNotEmpty) {
      whereClauses.add('(vendor_name LIKE ? OR invoice_number LIKE ?)');
      final pattern = '%${query.trim()}%';
      whereArgs.addAll([pattern, pattern]);
    }
    if (startDate != null) {
      whereClauses.add('date >= ?');
      whereArgs.add(startDate.toIso8601String().substring(0, 10));
    }
    if (endDate != null) {
      whereClauses.add('date <= ?');
      whereArgs.add('${endDate.toIso8601String().substring(0, 10)}T23:59:59');
    }
    if (status != null) {
      whereClauses.add('status = ?');
      whereArgs.add(status.index);
    }
    final whereString = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final invoiceMaps = await db.query(
      'invoices',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'date DESC',
    );

    List<Invoice> invoices = [];
    for (var invoiceMap in invoiceMaps) {
      final itemsMaps = await db.query(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [invoiceMap['id']],
      );
      final items = itemsMaps.map((map) => InvoiceItem.fromMap(map)).toList();
      invoices.add(Invoice.fromMap(invoiceMap, items: items));
    }
    return invoices;
  }

  Future<int> deleteInvoice(String id) async {
    final db = await instance.database;
    return await db.delete(
      'invoices',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> clearAllInvoices() async {
    final db = await instance.database;
    await db.delete('invoice_items');
    return await db.delete('invoices');
  }

  Future<bool> checkInvoiceExists({
    required String gstin,
    required String invoiceNumber,
    required DateTime date,
    String? id,
  }) async {
    final db = await instance.database;
    final dateIso = date.toIso8601String();
    final dateStr = dateIso.length >= 10 ? dateIso.substring(0, 10) : dateIso;

    final results = await db.query(
      'invoices',
      where: '(gstin = ? AND invoice_number = ? AND (date = ? OR substr(date, 1, 10) = ?)) OR (id = ? AND id != \'\')',
      whereArgs: [gstin, invoiceNumber, dateStr, dateStr, id ?? ''],
      limit: 1,
    );

    return results.isNotEmpty;
  }

  Future<void> replaceInvoice(Invoice invoice) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.insert(
        'invoices',
        invoice.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [invoice.id],
      );
      for (final item in invoice.items) {
        await txn.insert('invoice_items', item.toMap(invoice.id));
      }
    });
  }

  Future<int> getInvoiceCount() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM invoices');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getInvoiceItemCount() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM invoice_items');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> insertWorkflowLog(WorkflowLogEntry entry) async {
    final db = await instance.database;
    await db.insert(
      'workflow_logs',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<WorkflowLogEntry>> getWorkflowLogs({String? executionId, int limit = 100}) async {
    final db = await instance.database;
    final maps = await db.query(
      'workflow_logs',
      where: executionId != null ? 'execution_id = ?' : null,
      whereArgs: executionId != null ? [executionId] : null,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return maps.map((m) => WorkflowLogEntry.fromMap(m)).toList();
  }

  Future<int> clearWorkflowLogs() async {
    final db = await instance.database;
    return await db.delete('workflow_logs');
  }

  Future<Invoice?> getInvoiceById(String id) async {
    final db = await instance.database;
    final maps = await db.query(
      'invoices',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final itemsMaps = await db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [id],
    );
    final items = itemsMaps.map((map) => InvoiceItem.fromMap(map)).toList();
    return Invoice.fromMap(maps.first, items: items);
  }

  Future<void> resetDatabaseForTesting() async {
    await clearAllInvoices();
    await clearWorkflowLogs();
  }

  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }
}

class _WebMemoryDatabase implements Database {
  final Map<String, List<Map<String, dynamic>>> _tables = {
    'app_users': [],
    'invoices': [],
    'invoice_items': [],
    'audit_logs': [],
    'workflow_logs': [],
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  bool get isOpen => true;

  @override
  String get path => ':memory:';

  @override
  Batch batch() => throw UnimplementedError();

  @override
  Future<void> close() async {}

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async {
    final list = _tables[table];
    if (list == null) return 0;
    if (where == null) {
      final count = list.length;
      list.clear();
      return count;
    }
    if (where.contains('id = ?') && whereArgs != null && whereArgs.isNotEmpty) {
      final targetId = whereArgs.first.toString();
      if (table == 'invoices') {
        _tables['invoice_items']?.removeWhere((row) => row['invoice_id'] == targetId);
        _tables['workflow_logs']?.removeWhere((row) => row['invoice_id'] == targetId);
      }
      final count = list.where((row) => row['id'].toString() == targetId).length;
      list.removeWhere((row) => row['id'].toString() == targetId);
      return count;
    }
    return 0;
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {}

  @override
  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    _tables.putIfAbsent(table, () => []);
    _tables[table]!.add(Map<String, dynamic>.from(values));
    return 1;
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final list = _tables[table] ?? [];
    if (where != null && whereArgs != null && whereArgs.isNotEmpty) {
      if (where.contains('LOWER(username) = ?') || where.contains('username = ?')) {
        final target = whereArgs.first.toString().toLowerCase();
        return list.where((row) => (row['username'] as String?)?.toLowerCase() == target).toList();
      }
      if (where.contains('gstin = ? AND invoice_number = ?')) {
        final gstinVal = whereArgs[0].toString();
        final invNumVal = whereArgs[1].toString();
        final dateVal = whereArgs[2].toString();
        return list.where((row) {
          final rowGstin = row['gstin'] as String? ?? '';
          final rowInvNum = row['invoice_number'] as String? ?? '';
          final rowDate = row['date'] as String? ?? '';
          final rowDateSub = rowDate.length >= 10 ? rowDate.substring(0, 10) : rowDate;
          return rowGstin == gstinVal && rowInvNum == invNumVal && rowDateSub == dateVal;
        }).toList();
      }
      if (where.contains('id = ?')) {
        final targetId = whereArgs.first.toString();
        return list.where((row) => row['id'].toString() == targetId).toList();
      }
    }
    return list;
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async => 0;

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async => 1;

  @override
  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (sql.contains('FROM app_users')) {
      final users = _tables['app_users'] ?? [];
      return [{'count': users.length}];
    }
    if (sql.contains('FROM invoices')) {
      final invs = _tables['invoices'] ?? [];
      return [{'count': invs.length}];
    }
    return [{'count': 0}];
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async => 1;

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) async {
    return await action(_WebTransaction(this));
  }

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    return 1;
  }

  @override
  Database get database => this;
}

class _WebTransaction implements Transaction {
  final _WebMemoryDatabase _db;
  _WebTransaction(this._db);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Batch batch() => _db.batch();

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) => _db.delete(table, where: where, whereArgs: whereArgs);

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) => _db.execute(sql, arguments);

  @override
  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) =>
      _db.insert(table, values, nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);

  @override
  Future<List<Map<String, dynamic>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) =>
      _db.query(table, distinct: distinct, columns: columns, where: where, whereArgs: whereArgs, groupBy: groupBy, having: having, orderBy: orderBy, limit: limit, offset: offset);

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) => _db.rawDelete(sql, arguments);

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) => _db.rawInsert(sql, arguments);

  @override
  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<Object?>? arguments]) => _db.rawQuery(sql, arguments);

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) => _db.rawUpdate(sql, arguments);

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) =>
      _db.update(table, values, where: where, whereArgs: whereArgs, conflictAlgorithm: conflictAlgorithm);

  @override
  Database get database => _db;
}
