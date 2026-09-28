import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../services/auth/permission_service.dart';
import '../services/database/database_helper.dart';

/// DEVELOPMENT-ONLY SQLCipher Database Inspection Tool.
/// Strictly available in DEBUG builds for ADMIN users only.
class DatabaseInspectorScreen extends StatefulWidget {
  const DatabaseInspectorScreen({super.key});

  @override
  State<DatabaseInspectorScreen> createState() => _DatabaseInspectorScreenState();
}

class _DatabaseInspectorScreenState extends State<DatabaseInspectorScreen> {
  bool _isLoading = true;
  List<String> _tables = [];
  String? _selectedTable;

  // Table Details & Records
  List<Map<String, dynamic>> _columns = [];
  List<Map<String, dynamic>> _records = [];
  int _totalRowCount = 0;
  int _activeTab = 0; // 0: Data Records, 1: Table Schema

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const List<String> _sensitiveFields = [
    'password_hash',
    'password',
    'salt',
    'secret',
    'encryption_key',
    'key',
    'token',
  ];

  @override
  void initState() {
    super.initState();
    if (kDebugMode && PermissionService.instance.canManageUsers()) {
      _loadTables();
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTables() async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name ASC;",
      );

      final tableNames = result.map((r) => r['name'] as String).toList();
      setState(() {
        _tables = tableNames;
        _selectedTable = tableNames.contains('invoices')
            ? 'invoices'
            : (tableNames.isNotEmpty ? tableNames.first : null);
      });

      if (_selectedTable != null) {
        await _loadTableDetails(_selectedTable!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reading database schema: $e'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTableDetails(String tableName) async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;

      // 1. Fetch Column Schema
      final schemaResult = await db.rawQuery('PRAGMA table_info("$tableName");');
      final cols = schemaResult.map((col) {
        return {
          'name': col['name'].toString(),
          'type': col['type'].toString(),
          'pk': col['pk'] == 1,
          'notnull': col['notnull'] == 1,
        };
      }).toList();

      // 2. Fetch Total Row Count
      final countResult = await db.rawQuery('SELECT COUNT(*) as cnt FROM "$tableName";');
      final count = Sqflite.firstIntValue(countResult) ?? 0;

      // 3. Fetch Read-Only Records (Filtered or Unlimited up to 200 rows for preview)
      List<Map<String, dynamic>> records;
      if (_searchQuery.trim().isNotEmpty) {
        final textCols = cols.map((c) => c['name'] as String).toList();
        if (textCols.isNotEmpty) {
          final whereClause = textCols.map((c) => 'CAST("$c" AS TEXT) LIKE ?').join(' OR ');
          final whereArgs = List.generate(textCols.length, (_) => '%${_searchQuery.trim()}%');
          records = await db.rawQuery(
            'SELECT * FROM "$tableName" WHERE $whereClause LIMIT 200;',
            whereArgs,
          );
        } else {
          records = await db.rawQuery('SELECT * FROM "$tableName" LIMIT 200;');
        }
      } else {
        records = await db.rawQuery('SELECT * FROM "$tableName" LIMIT 200;');
      }

      if (mounted) {
        setState(() {
          _columns = cols;
          _records = records;
          _totalRowCount = count;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error querying table "$tableName": $e'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isSensitiveField(String columnName) {
    final lower = columnName.toLowerCase();
    return _sensitiveFields.any((s) => lower == s || lower.endsWith('_$s') || lower.startsWith('${s}_'));
  }

  String _formatCellValue(String colName, dynamic rawValue) {
    if (rawValue == null) return 'NULL';
    if (_isSensitiveField(colName)) {
      return '[MASKED]';
    }
    final str = rawValue.toString();
    if (str.length > 50) {
      return '${str.substring(0, 47)}...';
    }
    return str;
  }

  @override
  Widget build(BuildContext context) {
    // 1. Hard Gate: DEBUG Mode Check
    if (!kDebugMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.gpp_bad_rounded, size: 64, color: Colors.red),
                SizedBox(height: 16),
                Text(
                  'Database Inspector Disabled',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                SizedBox(height: 8),
                Text(
                  'This development tool is strictly disabled in production release builds.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 2. Hard Gate: ADMIN Role Check
    if (!PermissionService.instance.canManageUsers()) {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_person_rounded, size: 64, color: Colors.amber),
                SizedBox(height: 16),
                Text(
                  'Admin Privileges Required',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                SizedBox(height: 8),
                Text(
                  'Only authenticated Admin users can access the SQLCipher Debug Inspector.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.developer_mode_rounded, size: 20, color: Color(0xFFD97706)),
                const SizedBox(width: 8),
                Text(
                  'SQLCipher Debug Inspector',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const Text(
              'Read-Only Development Database Tool',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Tables',
            onPressed: _loadTables,
          ),
        ],
      ),
      body: Column(
        children: [
          // Warning Banner (DEBUG ONLY)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFFFFFBEB),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD97706),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'DEBUG ONLY',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'SQLCipher Encrypted DB (Read-Only). Secrets & Hashes are automatically masked.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF92400E), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

          // Table Selector Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      'Table:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedTable,
                            isExpanded: true,
                            hint: const Text('Select Table'),
                            items: _tables.map((table) {
                              return DropdownMenuItem<String>(
                                value: table,
                                child: Text(
                                  table,
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                ),
                              );
                            }).toList(),
                            onChanged: (newTable) {
                              if (newTable != null && newTable != _selectedTable) {
                                setState(() {
                                  _selectedTable = newTable;
                                  _searchQuery = '';
                                  _searchController.clear();
                                });
                                _loadTableDetails(newTable);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Table Stats & View Mode Toggle Bar
                if (_selectedTable != null)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$_totalRowCount records  •  ${_columns.length} columns',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                        ),
                      ),
                      const Spacer(),
                      // Tab Toggle (Records vs Schema)
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(
                            value: 0,
                            label: Text('Data'),
                            icon: Icon(Icons.table_chart_outlined, size: 16),
                          ),
                          ButtonSegment(
                            value: 1,
                            label: Text('Schema'),
                            icon: Icon(Icons.schema_outlined, size: 16),
                          ),
                        ],
                        selected: {_activeTab},
                        onSelectionChanged: (set) {
                          setState(() {
                            _activeTab = set.first;
                          });
                        },
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Search Bar for Data Records
          if (_activeTab == 0 && _selectedTable != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Filter records in "$_selectedTable"...',
                    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFF64748B)),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                              _loadTableDetails(_selectedTable!);
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onSubmitted: (query) {
                    setState(() => _searchQuery = query);
                    _loadTableDetails(_selectedTable!);
                  },
                ),
              ),
            ),

          const SizedBox(height: 12),

          // Main View Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F172A)))
                : _selectedTable == null
                    ? const Center(child: Text('No tables found in SQLite database.'))
                    : _activeTab == 1
                        ? _buildSchemaView()
                        : _buildRecordsView(),
          ),
        ],
      ),
    );
  }

  Widget _buildSchemaView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(14.0),
              child: Text(
                'Schema Structure: $_selectedTable',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
              ),
            ),
            const Divider(height: 1),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _columns.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) {
                final col = _columns[index];
                final colName = col['name'] as String;
                final colType = col['type'] as String;
                final isPk = col['pk'] as bool;
                final isNotNull = col['notnull'] as bool;
                final isSensitive = _isSensitiveField(colName);

                return ListTile(
                  dense: true,
                  leading: Icon(
                    isPk ? Icons.key_rounded : (isSensitive ? Icons.lock_outlined : Icons.table_chart_outlined),
                    size: 18,
                    color: isPk
                        ? const Color(0xFFD97706)
                        : (isSensitive ? const Color(0xFFDC2626) : const Color(0xFF64748B)),
                  ),
                  title: Row(
                    children: [
                      Text(
                        colName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSensitive ? const Color(0xFFDC2626) : const Color(0xFF0F172A),
                        ),
                      ),
                      if (isPk) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('PK', style: TextStyle(fontSize: 10, color: Color(0xFFB45309), fontWeight: FontWeight.bold)),
                        ),
                      ],
                      if (isSensitive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('MASKED', style: TextStyle(fontSize: 10, color: Color(0xFFDC2626), fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text('Data Type: $colType  •  ${isNotNull ? "NOT NULL" : "NULLABLE"}'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordsView() {
    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.table_rows_outlined, size: 48, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty ? 'No records match "$_searchQuery"' : 'Table "$_selectedTable" is empty',
              style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    final colNames = _columns.map((c) => c['name'] as String).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 20,
            horizontalMargin: 16,
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
            columns: colNames.map((name) {
              final isSensitive = _isSensitiveField(name);
              return DataColumn(
                label: Row(
                  children: [
                    if (isSensitive) ...[
                      const Icon(Icons.lock_outlined, size: 14, color: Color(0xFFDC2626)),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: isSensitive ? const Color(0xFFDC2626) : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            rows: _records.map((row) {
              return DataRow(
                cells: colNames.map((colName) {
                  final rawVal = row[colName];
                  final formattedVal = _formatCellValue(colName, rawVal);
                  final isSensitive = _isSensitiveField(colName);

                  return DataCell(
                    Text(
                      formattedVal,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: isSensitive ? 'monospace' : null,
                        color: isSensitive
                            ? const Color(0xFFDC2626)
                            : (rawVal == null ? const Color(0xFF94A3B8) : const Color(0xFF334155)),
                        fontWeight: isSensitive ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
