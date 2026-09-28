import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/invoice.dart';
import '../services/database/database_helper.dart';
import '../widgets/action_card.dart';
import '../widgets/invoice_list_tile.dart';
import '../widgets/metric_card.dart';
import 'invoice_detail_screen.dart';
import 'invoice_preview_screen.dart';
import 'reports_screen.dart';
import 'backup_restore_screen.dart';
import 'batch_scan_screen.dart';
import 'rpa_workflow_screen.dart';
import 'security_settings_screen.dart';
import 'login_screen.dart';
import 'user_management_screen.dart';
import '../services/security/app_security_service.dart';

import '../services/auth/auth_service.dart';
import '../services/auth/permission_service.dart';
import 'package:flutter/foundation.dart';
import 'database_inspector_screen.dart';





class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Invoice> _allInvoices = [];
  List<Invoice> _filteredInvoices = [];
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();
  DateTimeRange? _selectedDateRange;
  InvoiceStatus? _selectedStatus;
  bool _isSecurityEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadInvoices();
    _checkSecurityStatus();
  }

  Future<void> _checkSecurityStatus() async {
    final enabled = await AppSecurityService.instance.isSecurityEnabled();
    if (mounted) {
      setState(() {
        _isSecurityEnabled = enabled;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInvoices() async {
    try {
      final all = await DatabaseHelper.instance.getAllInvoices();
      final filtered = await DatabaseHelper.instance.searchInvoices(
        query: _searchController.text.trim().isNotEmpty
            ? _searchController.text.trim()
            : null,
        startDate: _selectedDateRange?.start,
        endDate: _selectedDateRange?.end,
        status: _selectedStatus,
      );

      if (mounted) {
        setState(() {
          _allInvoices = all;
          _filteredInvoices = filtered;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading invoices: $e'),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _onSearchChanged(String query) {
    _loadInvoices();
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _selectedDateRange = null;
      _selectedStatus = null;
    });
    _loadInvoices();
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _selectedDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 30)),
            end: DateTime.now(),
          ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0F172A),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
      });
      _loadInvoices();
    }
  }

  int get _totalProcessedCount => _allInvoices.length;

  double get _totalTaxAmount =>
      _allInvoices.fold(0.0, (sum, item) => sum + item.taxAmount);

  double get _totalProcessedAmount =>
      _allInvoices.fold(0.0, (sum, item) => sum + item.totalAmount);

  Future<void> _handleScanInvoice() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );

      if (pickedFile != null && mounted) {
        final imageFile = File(pickedFile.path);
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => InvoicePreviewScreen(
              imageFile: imageFile,
            ),
          ),
        );
        _loadInvoices();
      }
    } catch (e) {
      if (mounted) {
        try {
          final XFile? galleryFile = await _picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 100,
          );
          if (galleryFile != null && mounted) {
            final imageFile = File(galleryFile.path);
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => InvoicePreviewScreen(
                  imageFile: imageFile,
                ),
              ),
            );
            _loadInvoices();
          }
        } catch (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Camera/Gallery unavailable: $e'),
              backgroundColor: Colors.red[800],
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleUploadInvoice() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (pickedFile != null && mounted) {
        final imageFile = File(pickedFile.path);
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => InvoicePreviewScreen(
              imageFile: imageFile,
            ),
          ),
        );
        _loadInvoices();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening image gallery: $e'),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openInvoiceDetails(Invoice invoice) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => InvoiceDetailScreen(
          invoice: invoice,
          isEditingInitially: false,
        ),
      ),
    );
    _loadInvoices();
  }

  void _showPermissionDeniedSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.gpp_maybe_outlined, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openReports() async {
    if (!PermissionService.instance.canViewReports()) {
      _showPermissionDeniedSnackBar('Reviewer or Admin privileges required for Reports.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ReportsScreen(),
      ),
    );
    _loadInvoices();
  }

  Future<void> _openBackupRestore() async {
    if (!PermissionService.instance.canBackupRestore()) {
      _showPermissionDeniedSnackBar('Admin privileges required for Backup & Restore.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const BackupRestoreScreen(),
      ),
    );
    _loadInvoices();
  }

  Future<void> _openBatchScan() async {
    if (!PermissionService.instance.canRunBatchProcessing()) {
      _showPermissionDeniedSnackBar('Operator or Admin privileges required for Batch Scanning.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const BatchScanScreen(),
      ),
    );
    _loadInvoices();
  }

  Future<void> _openRpaWorkflow() async {
    if (!PermissionService.instance.canRunRpa()) {
      _showPermissionDeniedSnackBar('Operator or Admin privileges required for RPA Workflows.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const RpaWorkflowScreen(),
      ),
    );
    _loadInvoices();
  }

  Future<void> _openUserManagement() async {
    if (!PermissionService.instance.canManageUsers()) {
      _showPermissionDeniedSnackBar('Admin privileges required for User Management.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const UserManagementScreen(),
      ),
    );
    _loadInvoices();
  }

  Future<void> _openDatabaseInspector() async {
    if (!kDebugMode) return;
    if (!PermissionService.instance.canManageUsers()) {
      _showPermissionDeniedSnackBar('Admin privileges required for DB Inspector.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const DatabaseInspectorScreen(),
      ),
    );
  }


  Future<void> _handleLogout() async {
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _openSecuritySettings() async {
    if (!PermissionService.instance.canAccessSecuritySettings()) {
      _showPermissionDeniedSnackBar('Admin privileges required for Security Settings.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SecuritySettingsScreen(),
      ),
    );
    _checkSecurityStatus();
  }

  Future<void> _confirmDeleteInvoice(Invoice invoice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
              SizedBox(width: 8),
              Text(
                'Delete Invoice',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to permanently delete invoice "${invoice.invoiceNumber.isNotEmpty ? invoice.invoiceNumber : invoice.vendorName}"?\n\nThis action cannot be undone.',
            style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      try {
        await DatabaseHelper.instance.deleteInvoice(invoice.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted invoice "${invoice.invoiceNumber.isNotEmpty ? invoice.invoiceNumber : invoice.vendorName}"'),
              backgroundColor: const Color(0xFF0F172A),
              behavior: SnackBarBehavior.floating,
            ),
          );
          _loadInvoices();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting invoice: $e'),
              backgroundColor: Colors.red[800],
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasActiveFilter =
        _searchController.text.trim().isNotEmpty || _selectedDateRange != null || _selectedStatus != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleSpacing: 16,
        toolbarHeight: 64,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.flight_land_rounded,
                color: Color(0xFF38BDF8),
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'TaxInvoice AI',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                      letterSpacing: -0.3,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'Helicopter Division Ledger',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Security Status Badge
          Padding(
            padding: const EdgeInsets.only(right: 2.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: _isSecurityEnabled ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isSecurityEnabled ? const Color(0xFFA7F3D0) : const Color(0xFFCBD5E1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isSecurityEnabled ? Icons.verified_user_rounded : Icons.shield_outlined,
                    size: 13,
                    color: _isSecurityEnabled ? const Color(0xFF059669) : const Color(0xFF475569),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isSecurityEnabled ? 'Security Active' : 'Offline',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: _isSecurityEnabled ? const Color(0xFF059669) : const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Division Tools & Navigation Popup Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF0F172A), size: 22),
            tooltip: 'Division Tools',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) {
              switch (value) {
                case 'users':
                  _openUserManagement();
                  break;
                case 'security':
                  _openSecuritySettings();
                  break;
                case 'rpa':
                  _openRpaWorkflow();
                  break;
                case 'batch':
                  _openBatchScan();
                  break;
                case 'reports':
                  _openReports();
                  break;
                case 'backup':
                  _openBackupRestore();
                  break;
                case 'db_inspector':
                  _openDatabaseInspector();
                  break;
                case 'logout':
                  _handleLogout();
                  break;
              }
            },
            itemBuilder: (context) => [
              if (PermissionService.instance.canManageUsers())
                const PopupMenuItem<String>(
                  value: 'users',
                  child: Row(
                    children: [
                      Icon(Icons.manage_accounts_rounded, size: 20, color: Color(0xFF0F172A)),
                      SizedBox(width: 12),
                      Text('User Management'),
                    ],
                  ),
                ),
              if (PermissionService.instance.canAccessSecuritySettings())
                const PopupMenuItem<String>(
                  value: 'security',
                  child: Row(
                    children: [
                      Icon(Icons.security_rounded, size: 20, color: Color(0xFF0F172A)),
                      SizedBox(width: 12),
                      Text('Security & Privacy'),
                    ],
                  ),
                ),
              if (PermissionService.instance.canRunRpa())
                const PopupMenuItem<String>(
                  value: 'rpa',
                  child: Row(
                    children: [
                      Icon(Icons.precision_manufacturing_rounded, size: 20, color: Color(0xFF0F172A)),
                      SizedBox(width: 12),
                      Text('RPA Workflow'),
                    ],
                  ),
                ),
              if (PermissionService.instance.canRunBatchProcessing())
                const PopupMenuItem<String>(
                  value: 'batch',
                  child: Row(
                    children: [
                      Icon(Icons.collections_bookmark_outlined, size: 20, color: Color(0xFF0F172A)),
                      SizedBox(width: 12),
                      Text('Batch Scan'),
                    ],
                  ),
                ),
              if (PermissionService.instance.canViewReports())
                const PopupMenuItem<String>(
                  value: 'reports',
                  child: Row(
                    children: [
                      Icon(Icons.assessment_outlined, size: 20, color: Color(0xFF0F172A)),
                      SizedBox(width: 12),
                      Text('Reports & Export'),
                    ],
                  ),
                ),
              if (PermissionService.instance.canBackupRestore())
                const PopupMenuItem<String>(
                  value: 'backup',
                  child: Row(
                    children: [
                      Icon(Icons.settings_backup_restore_rounded, size: 20, color: Color(0xFF0F172A)),
                      SizedBox(width: 12),
                      Text('Backup & Restore'),
                    ],
                  ),
                ),
              if (kDebugMode && PermissionService.instance.canManageUsers()) ...[
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'db_inspector',
                  child: Row(
                    children: [
                      Icon(Icons.developer_mode_rounded, size: 20, color: Color(0xFFD97706)),
                      SizedBox(width: 12),
                      Text(
                        'DB Inspector (Debug)',
                        style: TextStyle(
                          color: Color(0xFFD97706),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 20, color: Color(0xFFDC2626)),
                    SizedBox(width: 12),
                    Text(
                      'Logout',
                      style: TextStyle(
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Direct Logout Button
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Color(0xFFDC2626), size: 20),
            tooltip: 'Logout',
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: _handleLogout,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 0.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Offline-First Privacy Banner
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 18,
                          color: Color(0xFF475569),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Helicopter Division Secure Ledger: 100% offline document processing.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Section: Actions
                  Text(
                    'Actions',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Action Button: Scan Invoice
                  ActionCard(
                    title: 'Scan Invoice',
                    description: 'Capture tax invoice directly with camera',
                    icon: Icons.camera_alt_outlined,
                    isPrimary: true,
                    onTap: _handleScanInvoice,
                  ),

                  const SizedBox(height: 12),

                  // Action Button: RPA Workflow Engine
                  ActionCard(
                    title: 'RPA Workflow Engine',
                    description: 'Automated pipeline: capture → OCR → parse → validate → save',
                    icon: Icons.precision_manufacturing_rounded,
                    isPrimary: true,
                    onTap: _openRpaWorkflow,
                  ),

                  const SizedBox(height: 12),

                  // Action Button: Security & Privacy Settings
                  ActionCard(
                    title: 'Security & Privacy Settings',
                    description: 'Biometric lock, hardware FLAG_SECURE & encrypted backups',
                    icon: Icons.security_rounded,
                    isPrimary: false,
                    onTap: _openSecuritySettings,
                  ),

                  const SizedBox(height: 12),

                  // Action Button: Batch Scan Invoices
                  ActionCard(
                    title: 'Batch Scan Invoices',
                    description: 'Process multiple gallery or camera images sequentially',
                    icon: Icons.collections_outlined,
                    isPrimary: false,
                    onTap: _openBatchScan,
                  ),

                  const SizedBox(height: 12),

                  // Action Button: Upload Invoice
                  ActionCard(
                    title: 'Upload Invoice',
                    description: 'Import PDF or image document from storage',
                    icon: Icons.upload_file_rounded,
                    isPrimary: false,
                    onTap: _handleUploadInvoice,
                  ),

                  const SizedBox(height: 12),

                  // Action Button: Reports & Export
                  ActionCard(
                    title: 'Reports & Export',
                    description: 'Tax breakdown & offline CSV, Excel, PDF export',
                    icon: Icons.analytics_outlined,
                    isPrimary: false,
                    onTap: _openReports,
                  ),

                  const SizedBox(height: 12),

                  // Action Button: Backup & Restore
                  ActionCard(
                    title: 'Backup & Restore',
                    description: 'Offline database backup, restore, & migration',
                    icon: Icons.settings_backup_restore_rounded,
                    isPrimary: false,
                    onTap: _openBackupRestore,
                  ),

                  const SizedBox(height: 28),

                  // Section: Total Processed
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Processed',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                          letterSpacing: 0.2,
                        ),
                      ),
                      Text(
                        'All-time summary',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: MetricCard(
                          title: 'Invoices Processed',
                          value: '$_totalProcessedCount',
                          subtitle: 'Count',
                          icon: Icons.description_outlined,
                          accentColor: const Color(0xFF0284C7),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MetricCard(
                          title: 'Tax Tracked',
                          value: '₹${(_totalTaxAmount / 1000).toStringAsFixed(1)}k',
                          subtitle: 'Extracted',
                          icon: Icons.account_balance_wallet_outlined,
                          accentColor: const Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  MetricCard(
                    title: 'Total Invoiced Amount',
                    value: '₹${_totalProcessedAmount.toStringAsFixed(2)}',
                    subtitle: 'Local Ledger',
                    icon: Icons.savings_outlined,
                    accentColor: const Color(0xFF7C3AED),
                  ),

                  const SizedBox(height: 28),

                  // Section: Invoice History Header & Search/Filters
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Invoice History',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                          letterSpacing: 0.2,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_filteredInvoices.length} entries',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Search and Date Filter Bar
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: TextField(
                            controller: _searchController,
                            onChanged: _onSearchChanged,
                            decoration: InputDecoration(
                              hintText: 'Search vendor or invoice #...',
                              hintStyle: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF94A3B8),
                              ),
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 18,
                                color: Color(0xFF64748B),
                              ),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      color: const Color(0xFF94A3B8),
                                      onPressed: () {
                                        _searchController.clear();
                                        _loadInvoices();
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 8,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Date Filter Button
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: _selectedDateRange != null
                              ? const Color(0xFFEFF6FF)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedDateRange != null
                                ? const Color(0xFF3B82F6)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.calendar_month_outlined,
                            size: 20,
                            color: _selectedDateRange != null
                                ? const Color(0xFF2563EB)
                                : const Color(0xFF64748B),
                          ),
                          tooltip: 'Filter by date range',
                          onPressed: _selectDateRange,
                        ),
                      ),
                    ],
                  ),

                  // Status Filter Chips
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          selected: _selectedStatus == null,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedStatus = null;
                              });
                              _loadInvoices();
                            }
                          },
                          visualDensity: VisualDensity.compact,
                          selectedColor: const Color(0xFF0F172A),
                          labelStyle: TextStyle(color: _selectedStatus == null ? Colors.white : const Color(0xFF475569)),
                          showCheckmark: false,
                        ),
                        const SizedBox(width: 6),
                        FilterChip(
                          label: const Text('Verified', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          selected: _selectedStatus == InvoiceStatus.verified,
                          onSelected: (selected) {
                            setState(() {
                              _selectedStatus = selected ? InvoiceStatus.verified : null;
                            });
                            _loadInvoices();
                          },
                          visualDensity: VisualDensity.compact,
                          selectedColor: const Color(0xFF059669),
                          labelStyle: TextStyle(color: _selectedStatus == InvoiceStatus.verified ? Colors.white : const Color(0xFF059669)),
                          showCheckmark: false,
                        ),
                        const SizedBox(width: 6),
                        FilterChip(
                          label: const Text('Pending', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          selected: _selectedStatus == InvoiceStatus.pending,
                          onSelected: (selected) {
                            setState(() {
                              _selectedStatus = selected ? InvoiceStatus.pending : null;
                            });
                            _loadInvoices();
                          },
                          visualDensity: VisualDensity.compact,
                          selectedColor: const Color(0xFFD97706),
                          labelStyle: TextStyle(color: _selectedStatus == InvoiceStatus.pending ? Colors.white : const Color(0xFFD97706)),
                          showCheckmark: false,
                        ),
                        const SizedBox(width: 6),
                        FilterChip(
                          label: const Text('Flagged', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          selected: _selectedStatus == InvoiceStatus.flagged,
                          onSelected: (selected) {
                            setState(() {
                              _selectedStatus = selected ? InvoiceStatus.flagged : null;
                            });
                            _loadInvoices();
                          },
                          visualDensity: VisualDensity.compact,
                          selectedColor: const Color(0xFFDC2626),
                          labelStyle: TextStyle(color: _selectedStatus == InvoiceStatus.flagged ? Colors.white : const Color(0xFFDC2626)),
                          showCheckmark: false,
                        ),
                      ],
                    ),
                  ),

                  // Active Filter Chip (Date)
                  if (_selectedDateRange != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Chip(
                          avatar: const Icon(Icons.date_range, size: 14, color: Color(0xFF2563EB)),
                          label: Text(
                            '${_selectedDateRange!.start.day}/${_selectedDateRange!.start.month}/${_selectedDateRange!.start.year} - ${_selectedDateRange!.end.day}/${_selectedDateRange!.end.month}/${_selectedDateRange!.end.year}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF1E40AF), fontWeight: FontWeight.w600),
                          ),
                          backgroundColor: const Color(0xFFDBEAFE),
                          deleteIcon: const Icon(Icons.close, size: 14, color: Color(0xFF1E40AF)),
                          onDeleted: () {
                            setState(() {
                              _selectedDateRange = null;
                            });
                            _loadInvoices();
                          },
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),

          // Invoices List Items
          if (_allInvoices.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.receipt_outlined,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No invoices processed yet',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Scan or upload an invoice to get started offline.',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_filteredInvoices.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No matching invoices found',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Try adjusting your search query or date filter.',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (hasActiveFilter)
                        TextButton.icon(
                          icon: const Icon(Icons.clear_all_rounded, size: 18),
                          label: const Text('Clear Filters'),
                          onPressed: _clearFilters,
                        ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final invoice = _filteredInvoices[index];
                    return InvoiceListTile(
                      invoice: invoice,
                      onTap: () => _openInvoiceDetails(invoice),
                      onDelete: () => _confirmDeleteInvoice(invoice),
                    );
                  },
                  childCount: _filteredInvoices.length,
                ),
              ),
            ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 24),
          ),
        ],
      ),
    );
  }
}
