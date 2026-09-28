import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/invoice.dart';
import '../services/backup/encrypted_backup_service.dart';
import '../services/backup/invoice_backup_service.dart';
import '../services/database/database_helper.dart';
import '../services/export/file_export_helper.dart';

class BackupRestoreScreen extends StatefulWidget {
  final InvoiceBackupService backupService;
  final EncryptedBackupService encryptedBackupService;
  final FileExportHelper exportHelper;
  final DatabaseHelper? databaseHelper;

  const BackupRestoreScreen({
    super.key,
    this.backupService = const InvoiceBackupService(),
    this.encryptedBackupService = const EncryptedBackupService(),
    this.exportHelper = const FileExportHelper(),
    this.databaseHelper,
  });

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  int _invoiceCount = 0;
  int _itemCount = 0;
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _statusMessage;

  DatabaseHelper get _db => widget.databaseHelper ?? DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _loadDatabaseStats();
  }

  Future<void> _loadDatabaseStats() async {
    try {
      final invCount = await _db.getInvoiceCount();
      final itmCount = await _db.getInvoiceItemCount();
      if (mounted) {
        setState(() {
          _invoiceCount = invCount;
          _itemCount = itmCount;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading database info: $e'),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatTimestamp() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _handleCreateBackup({bool useEncryption = true}) async {
    final invoices = await _db.getAllInvoices();
    if (invoices.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No invoices in database to back up.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    String password = '';
    if (useEncryption) {
      final pwd = await _promptPasswordDialog(isExport: true);
      if (pwd == null || pwd.trim().isEmpty) return;
      password = pwd;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Fetching invoice records from SQLite...';
    });

    try {
      String jsonContent;
      String fileName;

      if (useEncryption && password.isNotEmpty) {
        setState(() => _statusMessage = 'Encrypting backup with PBKDF2 + AES authentication...');
        final encResult = widget.encryptedBackupService.createEncryptedBackup(
          invoices: invoices,
          password: password,
        );

        if (!encResult.success || encResult.encryptedOutput == null) {
          setState(() => _isProcessing = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(encResult.errorMessage ?? 'Encryption failed'),
                backgroundColor: Colors.red[800],
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }

        jsonContent = encResult.encryptedOutput!;
        fileName = 'TaxInvoice_EncryptedBackup_${_formatTimestamp()}.json';
      } else {
        setState(() => _statusMessage = 'Generating structured JSON backup...');
        jsonContent = widget.backupService.createBackupJson(invoices);
        fileName = 'TaxInvoice_Backup_${_formatTimestamp()}.json';
      }

      setState(() => _statusMessage = 'Saving backup file...');
      final result = await widget.exportHelper.exportString(
        content: jsonContent,
        fileName: fileName,
        mimeType: 'application/json',
        shareSubject: 'TaxInvoiceAI Backup ($fileName)',
      );

      if (mounted) {
        setState(() => _isProcessing = false);
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Backup exported successfully: $fileName'),
              backgroundColor: const Color(0xFF059669),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? 'Backup export failed'),
              backgroundColor: Colors.red[800],
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup error: $e'),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<String?> _promptPasswordDialog({required bool isExport}) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isExport ? 'Set Backup Password' : 'Enter Decryption Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isExport
                  ? 'Set a password to encrypt this backup file. You will need this password to restore data.'
                  : 'This backup file is encrypted. Enter the password used during export.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(isExport ? 'Encrypt & Export' : 'Decrypt'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSelectBackupFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;
      String? content;

      if (file.bytes != null) {
        content = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        final ioFile = File(file.path!);
        content = await ioFile.readAsString();
      }

      if (content == null || content.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selected file is empty or could not be read.'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      _processAndPreviewBackup(content, file.name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reading file: $e'),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _processAndPreviewBackup(String jsonContent, String fileName) async {
    BackupInspectionResult inspection = widget.encryptedBackupService.inspectEncryptedBackup(
      encryptedJsonString: jsonContent,
      password: '',
    );

    // If password is required for encrypted format
    if (!inspection.isValid && jsonContent.contains('encrypted_v1')) {
      final password = await _promptPasswordDialog(isExport: false);
      if (password == null) return;

      inspection = widget.encryptedBackupService.inspectEncryptedBackup(
        encryptedJsonString: jsonContent,
        password: password,
      );
    }

    if (!inspection.isValid) {
      if (mounted) {
        _showInvalidBackupDialog(inspection.errorMessage ?? 'Invalid backup file.');
      }
      return;
    }

    int duplicateCount = 0;
    for (final inv in inspection.invoices) {
      final exists = await _db.checkInvoiceExists(
        gstin: inv.gstin,
        invoiceNumber: inv.invoiceNumber,
        date: inv.date,
        id: inv.id,
      );
      if (exists) {
        duplicateCount++;
      }
    }

    if (mounted) {
      _showRestoreConfirmationSheet(
        fileName: fileName,
        inspection: inspection,
        duplicateCount: duplicateCount,
      );
    }
  }

  void _showInvalidBackupDialog(String error) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Invalid Backup File', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The selected file could not be restored:',
              style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(
                error,
                style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B), fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  void _showRestoreConfirmationSheet({
    required String fileName,
    required BackupInspectionResult inspection,
    required int duplicateCount,
  }) {
    RestoreStrategy selectedStrategy = RestoreStrategy.skipDuplicates;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final newCount = inspection.invoiceCountInBackup - duplicateCount;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                20,
                24,
                MediaQuery.of(modalContext).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.settings_backup_restore, color: Color(0xFF2563EB), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Restore Backup Preview',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                            ),
                            Text(
                              fileName,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 14),

                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Expanded(child: _buildSummaryColumn('In Backup', '${inspection.invoiceCountInBackup}', const Color(0xFF2563EB))),
                        Container(width: 1, height: 36, color: const Color(0xFFE2E8F0)),
                        Expanded(child: _buildSummaryColumn('New Invoices', '$newCount', const Color(0xFF059669))),
                        Container(width: 1, height: 36, color: const Color(0xFFE2E8F0)),
                        Expanded(child: _buildSummaryColumn('Existing', '$duplicateCount', const Color(0xFFD97706))),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Text(
                    'Choose Restore Mode',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 8),

                  RadioListTile<RestoreStrategy>(
                    title: const Text('Merge & Skip Duplicates (Safe)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Adds $newCount new invoices and preserves your existing $_invoiceCount invoices.',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    value: RestoreStrategy.skipDuplicates,
                    groupValue: selectedStrategy,
                    activeColor: const Color(0xFF2563EB),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedStrategy = val);
                    },
                  ),

                  RadioListTile<RestoreStrategy>(
                    title: const Text('Merge & Update Existing', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Updates $duplicateCount existing invoices and adds $newCount new ones.',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    value: RestoreStrategy.overwriteExisting,
                    groupValue: selectedStrategy,
                    activeColor: const Color(0xFF2563EB),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedStrategy = val);
                    },
                  ),

                  RadioListTile<RestoreStrategy>(
                    title: const Text('Replace Entire Database', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFDC2626))),
                    subtitle: const Text(
                      'Wipes all current SQLite records and restores only the backup file.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
                    ),
                    value: RestoreStrategy.replaceAll,
                    groupValue: selectedStrategy,
                    activeColor: const Color(0xFFDC2626),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedStrategy = val);
                    },
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(modalContext).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(modalContext).pop();
                            _executeRestore(
                              invoices: inspection.invoices,
                              strategy: selectedStrategy,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: selectedStrategy == RestoreStrategy.replaceAll
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Confirm Restore', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _executeRestore({
    required List<Invoice> invoices,
    required RestoreStrategy strategy,
  }) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Restoring invoices into SQLite...';
    });

    final result = await widget.backupService.performRestore(
      invoicesToRestore: invoices,
      strategy: strategy,
      dbHelper: _db,
    );

    await _loadDatabaseStats();

    if (mounted) {
      setState(() => _isProcessing = false);
      _showRestoreResultDialog(result);
    }
  }

  void _showRestoreResultDialog(RestoreResult result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              result.success ? Icons.check_circle_outline : Icons.error_outline,
              color: result.success ? const Color(0xFF059669) : Colors.red,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              result.success ? 'Restore Complete' : 'Restore Failed',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: result.success
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Database restore operation finished successfully:'),
                  const SizedBox(height: 12),
                  _buildResultRow('Invoices Added', '${result.addedCount}', const Color(0xFF059669)),
                  const SizedBox(height: 6),
                  _buildResultRow('Invoices Updated', '${result.updatedCount}', const Color(0xFF2563EB)),
                  const SizedBox(height: 6),
                  _buildResultRow('Invoices Skipped', '${result.skippedCount}', const Color(0xFFD97706)),
                  const SizedBox(height: 6),
                  _buildResultRow('Total Processed', '${result.totalProcessed}', const Color(0xFF0F172A)),
                ],
              )
            : Text(result.errorMessage ?? 'An unexpected error occurred during database restoration.'),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryColumn(String title, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildResultRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF475569))),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Backup & Restore',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Color(0xFF0F172A)),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh database status',
            onPressed: _loadDatabaseStats,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Security Data Warning Banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFCD34D)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 20, color: Color(0xFFD97706)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'WARNING: Backup files contain sensitive helicopter division business data. Use password protection when exporting to external channels.',
                            style: TextStyle(fontSize: 11, color: Color(0xFFB45309), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Database Overview Card
                  Text(
                    'SQLite Database Status',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 10),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.storage_rounded, color: Color(0xFF2563EB), size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$_invoiceCount Invoices Stored',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$_itemCount line items across all records',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  Text(
                    'Backup & Restore Actions',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_isProcessing)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24.0),
                        child: Column(
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(
                              _statusMessage ?? 'Processing database operation...',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        // Encrypted Backup Card (Recommended)
                        _buildActionCard(
                          title: 'Export Encrypted Backup (.json)',
                          subtitle: 'Create a password-protected authenticated backup file (AES-256).',
                          icon: Icons.lock_outline_rounded,
                          accentColor: const Color(0xFF059669),
                          buttonText: 'Export Password-Protected Backup',
                          onTap: () => _handleCreateBackup(useEncryption: true),
                        ),

                        const SizedBox(height: 14),

                        // Unencrypted Backup Card (Legacy)
                        _buildActionCard(
                          title: 'Export Unencrypted Backup (.json)',
                          subtitle: 'Standard unencrypted JSON backup. Use with caution.',
                          icon: Icons.upload_file_rounded,
                          accentColor: const Color(0xFF2563EB),
                          buttonText: 'Export Plaintext Backup',
                          onTap: () => _handleCreateBackup(useEncryption: false),
                        ),

                        const SizedBox(height: 14),

                        // Restore Backup Card
                        _buildActionCard(
                          title: 'Restore Database from Backup',
                          subtitle: 'Select and validate an encrypted or plain JSON backup file.',
                          icon: Icons.download_rounded,
                          accentColor: const Color(0xFF0F172A),
                          buttonText: 'Select & Restore Backup File',
                          onTap: _handleSelectBackupFile,
                        ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required String buttonText,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text(
                buttonText,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
