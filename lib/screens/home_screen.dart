import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/invoice.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/permission_service.dart';
import '../services/database/database_helper.dart';
import '../services/security/app_security_service.dart';
import '../services/ocr/batch_scan_service.dart';
import '../services/reports/invoice_report_service.dart';
import '../services/export/file_export_helper.dart';
import '../services/backup/encrypted_backup_service.dart';
import '../widgets/invoice_assistant_widget.dart';

import 'backup_restore_screen.dart';
import 'batch_scan_screen.dart';
import 'database_inspector_screen.dart';
import 'invoice_detail_screen.dart';
import 'invoice_preview_screen.dart';
import 'login_screen.dart';
import 'reports_screen.dart';
import 'rpa_workflow_screen.dart';
import 'security_settings_screen.dart';
import 'user_management_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Invoice> _allInvoices = [];
  List<Invoice> _filteredInvoices = [];
  Invoice? _selectedInvoice;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();
  DateTimeRange? _selectedDateRange;
  InvoiceStatus? _selectedStatus;
  String? _selectedVendor;
  bool _isSecurityEnabled = false;
  bool _isLanConnected = false;
  String _activeNav = 'Dashboard';
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  // Batch Processing State
  final BatchScanService _batchService = BatchScanService();
  final List<BatchInvoiceItem> _batchItems = [];
  bool _isBatchProcessing = false;
  int _batchCurrentIndex = 0;
  int _batchTotalCount = 0;
  bool _batchCancelRequested = false;

  // Reports State
  final InvoiceReportService _reportService = const InvoiceReportService();
  final FileExportHelper _exportHelper = const FileExportHelper();
  String _reportsPreset = 'All Time';
  DateTimeRange? _reportsDateRange;
  InvoiceStatus? _reportsStatusFilter;
  String? _reportsVendorFilter;

  // Settings State
  String _activeSettingsSection = 'Security & Privacy';
  bool _isAppLaunchAuthEnabled = true;

  @override
  void initState() {
    super.initState();
    if (!AuthService.instance.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !AuthService.instance.isAuthenticated) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      });
      return;
    }
    _now = DateTime.now();
    _startClockTimer();
    _loadInvoices();
    _checkSecurityStatus();
    _checkLanHealth();
  }

  void _startClockTimer() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final current = DateTime.now();
      if (current.minute != _now.minute || current.second != _now.second) {
        if (mounted) {
          setState(() {
            _now = current;
          });
        }
      }
    });
  }

  Future<void> _checkSecurityStatus() async {
    final enabled = await AppSecurityService.instance.isSecurityEnabled();
    if (mounted) {
      setState(() {
        _isSecurityEnabled = enabled;
      });
    }
  }

  Future<void> _checkLanHealth() async {
    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/health'))
          .timeout(const Duration(seconds: 3));
      if (mounted) {
        setState(() {
          _isLanConnected = response.statusCode == 200;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLanConnected = false;
        });
      }
    }
  }

  String _getGreetingPrefix(DateTime now) {
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

  String get _greetingName {
    final session = AuthService.instance.currentSession;
    if (session != null && session.username.trim().isNotEmpty) {
      final name = session.username.trim();
      final first = name.split(' ').first;
      if (first.toLowerCase() == 'admin') return 'Sheethal';
      return first[0].toUpperCase() + first.substring(1);
    }
    return 'Sheethal';
  }

  String get _sidebarUserName {
    final session = AuthService.instance.currentSession;
    if (session != null && session.username.trim().isNotEmpty) {
      return session.username.trim();
    }
    return 'Sheethal L';
  }

  String get _sidebarUserRole {
    final session = AuthService.instance.currentSession;
    if (session != null) {
      return session.role.displayName;
    }
    return 'Administrator';
  }

  String get _avatarInitial {
    final name = _greetingName;
    if (name.isNotEmpty) return name[0].toUpperCase();
    return 'S';
  }

  String _formatHeaderDate(DateTime dt) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final weekday = weekdays[dt.weekday - 1];
    final month = months[dt.month - 1];
    return '$weekday, ${dt.day} $month ${dt.year}';
  }

  String _formatHeaderTime(DateTime dt) {
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minutePadded = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minutePadded $period';
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
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

      // Apply vendor filter if selected
      final finalFiltered = _selectedVendor != null && _selectedVendor != 'All Vendors'
          ? filtered.where((i) => i.vendorName == _selectedVendor).toList()
          : filtered;

      if (mounted) {
        setState(() {
          _allInvoices = all;
          _filteredInvoices = finalFiltered;
          if (_selectedInvoice == null && finalFiltered.isNotEmpty) {
            _selectedInvoice = finalFiltered.first;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading invoices: $e'),
            backgroundColor: const Color(0xFFDC2626),
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
      _selectedVendor = null;
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

  // Dashboard Metrics Computations using REAL application data
  int get _totalProcessedCount => _allInvoices.length;
  int get _pendingReviewCount =>
      _allInvoices.where((i) => i.status == InvoiceStatus.pending || i.status == InvoiceStatus.flagged).length;
  int get _verifiedCount => _allInvoices.where((i) => i.status == InvoiceStatus.verified).length;
  int get _pendingSyncCount => _allInvoices.where((i) => i.syncStatus == SyncStatus.pendingSync).length;
  int get _syncedCount => _allInvoices.where((i) => i.syncStatus == SyncStatus.synced).length;
  int get _syncFailedCount => _allInvoices.where((i) => i.syncStatus == SyncStatus.syncFailed).length;

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
              backgroundColor: const Color(0xFFDC2626),
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
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openInvoiceDetails(Invoice invoice) async {
    setState(() {
      _selectedInvoice = invoice;
    });
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
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openReports() async {
    if (!PermissionService.instance.canViewReports()) {
      _showPermissionDeniedSnackBar('Reviewer or Admin privileges required for Reports.');
      return;
    }
    setState(() {
      _activeNav = 'Reports & Export';
    });
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
    setState(() {
      _activeNav = 'Batch Processing';
    });
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
    setState(() {
      _selectedInvoice = null;
      _activeNav = 'Dashboard';
    });
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
    setState(() {
      _activeNav = 'Settings';
    });
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
              Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
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
    if (!AuthService.instance.isAuthenticated) {
      return const LoginScreen();
    }

    final width = MediaQuery.of(context).size.width;
    final isDesktop = kIsWeb && width > 900;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF1F5F9),
          drawer: isDesktop
              ? null
              : Drawer(
                  backgroundColor: const Color(0xFF070D1E),
                  child: _buildSidebar(),
                ),
          body: isDesktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSidebar(),
                    Expanded(
                      child: Column(
                        children: [
                          _buildTopHeader(isDesktop: isDesktop),
                          Expanded(child: _buildMainContent()),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _buildTopHeader(isDesktop: isDesktop),
                    Expanded(child: _buildMainContent()),
                  ],
                ),
        ),
        InvoiceAssistantWidget(invoice: _selectedInvoice),
      ],
    );
  }

  // ==========================================
  // 1. LEFT SIDEBAR — MATCHES REFERENCE IMAGE
  // ==========================================
  Widget _buildSidebar() {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/dashboard_aviation_bg.jpg'),
          fit: BoxFit.cover,
          alignment: Alignment.bottomLeft,
        ),
      ),
      child: Container(
        color: const Color(0xFF0B132B).withValues(alpha: 0.85), // Dark navy translucent overlay matching reference style
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Top Branding: Helicopter Logo + TaxInvoice AI
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: const Icon(
                        Icons.airplanemode_active_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'TaxInvoice AI',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          'Invoice Processing & Verification',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Navigation Items List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildSidebarNavItem('Dashboard', Icons.dashboard_rounded, isActive: _activeNav == 'Dashboard'),
                _buildSidebarNavItem('Invoices', Icons.receipt_long_outlined, isActive: _activeNav == 'Invoices'),
                _buildSidebarNavItem('Scan / Upload', Icons.qr_code_scanner_outlined, isActive: _activeNav == 'Scan / Upload'),
                _buildSidebarNavItem('Batch Processing', Icons.layers_outlined, isActive: _activeNav == 'Batch Processing'),
                _buildSidebarNavItem('Reports & Export', Icons.analytics_outlined, isActive: _activeNav == 'Reports & Export'),
                _buildSidebarNavItem('Sync Center', Icons.sync_rounded, isActive: _activeNav == 'Sync Center'),
                _buildSidebarNavItem('Exception Center', Icons.error_outline_rounded, isActive: _activeNav == 'Exception Center'),
                _buildSidebarNavItem('Audit Trail', Icons.fact_check_outlined, isActive: _activeNav == 'Audit Trail'),
                _buildSidebarNavItem('Invoice Assistant', Icons.smart_toy_outlined, isActive: _activeNav == 'Invoice Assistant', hasAiBadge: true),
                _buildSidebarNavItem('Settings', Icons.settings_outlined, isActive: _activeNav == 'Settings'),
              ],
            ),
          ),

          // Bottom Sidebar User Card with Logout Action
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Material(
              color: Colors.transparent,
              child: Theme(
                data: Theme.of(context).copyWith(
                  popupMenuTheme: PopupMenuThemeData(
                    color: const Color(0xFF070D1E),
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                  ),
                ),
                child: PopupMenuButton<String>(
                  key: const Key('sidebar_user_menu_button'),
                  tooltip: 'User Options',
                  offset: const Offset(0, -60),
                  position: PopupMenuPosition.over,
                  padding: EdgeInsets.zero,
                  onSelected: (val) {
                    if (val == 'logout') {
                      _handleLogout();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      key: const Key('sidebar_logout_menu_item'),
                      value: 'logout',
                      height: 44,
                      child: Row(
                        children: const [
                          Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 18),
                          SizedBox(width: 10),
                          Text(
                            'Logout',
                            style: TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            color: Color(0xFF1E293B),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person_rounded, color: Color(0xFF94A3B8), size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _sidebarUserName,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _sidebarUserRole,
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom Sidebar System Status Box with Helicopter Watermark
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF070D1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'System Status',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    _buildStatusDotRow('App Online (Local)', true),
                    const SizedBox(height: 4),
                    _buildStatusDotRow('LAN Server Connected', _isLanConnected),
                    const SizedBox(height: 4),
                    _buildStatusDotRow('Database Connected', true),
                  ],
                ),
                const Positioned(
                  right: 0,
                  bottom: 0,
                  child: Text(
                    'v1.0.0',
                    style: TextStyle(color: Color(0xFF475569), fontSize: 9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildSidebarNavItem(String title, IconData icon, {bool isActive = false, bool hasAiBadge = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFD4A24E) : Colors.transparent, // Warm beige/gold active card
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        leading: Icon(
          icon,
          size: 18,
          color: isActive ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isActive ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  fontSize: 12.5,
                ),
              ),
            ),
            if (hasAiBadge)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'AI',
                  style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9.5, fontWeight: FontWeight.bold),
                ),
              ),
            if (isActive)
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF0F172A), size: 16),
          ],
        ),
        onTap: () {
          switch (title) {
            case 'Dashboard':
              setState(() => _activeNav = 'Dashboard');
              break;
            case 'Invoices':
              setState(() => _activeNav = 'Invoices');
              break;
            case 'Scan / Upload':
              _handleScanInvoice();
              break;
            case 'Batch Processing':
              _openBatchScan();
              break;
            case 'Reports & Export':
              _openReports();
              break;
            case 'Sync Center':
              setState(() => _activeNav = 'Sync Center');
              _checkLanHealth();
              break;
            case 'Exception Center':
              setState(() => _activeNav = 'Exception Center');
              break;
            case 'Audit Trail':
              setState(() => _activeNav = 'Audit Trail');
              break;
            case 'Invoice Assistant':
              setState(() => _activeNav = 'Invoice Assistant');
              break;
            case 'Settings':
              _openSecuritySettings();
              break;
            default:
              setState(() => _activeNav = title);
              break;
          }
        },
      ),
    );
  }

  Widget _buildStatusDotRow(String text, bool isOnline) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: isOnline ? const Color(0xFF10B981) : const Color(0xFFDC2626),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: isOnline ? const Color(0xFFCBD5E1) : const Color(0xFF94A3B8),
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }

  // ==========================================
  // 2. TOP HEADER — MATCHES REFERENCE IMAGE
  // ==========================================
  Widget _buildTopHeader({bool isDesktop = true}) {
    return Container(
      height: 100,
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/dashboard_aviation_bg.jpg'),
          fit: BoxFit.cover,
          alignment: Alignment(0.0, -0.45),
        ),
      ),
      child: Container(
        color: const Color(0xFF0F172A).withValues(alpha: 0.28), // Soft aviation sunset overlay preserving warm glow
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left: Mobile Drawer Button + Greeting
            Row(
              children: [
                if (!isDesktop) ...[
                  Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.menu_rounded, color: Colors.white),
                      tooltip: 'Menu',
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _getGreetingPrefix(_now),
                      style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      '${_greetingName}!',
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                    ),
                    const Text(
                      "Here's an overview of your invoice operations.",
                      style: TextStyle(color: Color(0xDDFFFFFF), fontSize: 11.5),
                    ),
                  ],
                ),
              ],
            ),

            // Right: Date, Time, Search, Avatar, Slogan
            Row(
              children: [
                // Date & Time Column
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, color: Color(0xB3FFFFFF), size: 12),
                        const SizedBox(width: 4),
                        Text(_formatHeaderDate(_now), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, color: Color(0xB3FFFFFF), size: 12),
                        const SizedBox(width: 4),
                        Text(_formatHeaderTime(_now), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 16),

                // Search Box
                Container(
                  width: 220,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: 'Search invoices, vendors, GSTIN...',
                      hintStyle: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                      prefixIcon: Icon(Icons.search_rounded, size: 16, color: Color(0xFF64748B)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Notification Bell
                Stack(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.notifications_outlined, color: Color(0xFF0F172A), size: 18),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(color: Color(0xFFDC2626), shape: BoxShape.circle),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),

                // Avatar Circle with Logout Popup Menu
                Theme(
                  data: Theme.of(context).copyWith(
                    popupMenuTheme: PopupMenuThemeData(
                      color: const Color(0xFF070D1E),
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                    ),
                  ),
                  child: PopupMenuButton<String>(
                    tooltip: 'User Options & Logout',
                    offset: const Offset(0, 44),
                    padding: EdgeInsets.zero,
                    onSelected: (val) {
                      if (val == 'logout') {
                        _handleLogout();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        enabled: false,
                        height: 38,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _sidebarUserName,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _sidebarUserRole,
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(height: 1),
                      PopupMenuItem<String>(
                        value: 'logout',
                        height: 40,
                        child: Row(
                          children: const [
                            Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 16),
                            SizedBox(width: 10),
                            Text(
                              'Logout',
                              style: TextStyle(
                                color: Color(0xFFEF4444),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E293B),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(_avatarInitial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Slogan Column
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('ACCURATE INVOICES.', style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                    Text('SMOOTHER OPERATIONS.', style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 3. MAIN CENTER CONTENT
  // ==========================================
  Widget _buildMainContent() {
    switch (_activeNav) {
      case 'Invoices':
        return _buildInvoicesView();
      case 'Batch Processing':
        return _buildBatchProcessingView();
      case 'Reports & Export':
        return _buildReportsView();
      case 'Sync Center':
        return _buildSyncCenterView();
      case 'Exception Center':
        return _buildExceptionCenterView();
      case 'Audit Trail':
        return _buildAuditTrailView();
      case 'Settings':
        return _buildSettingsView();
      case 'Dashboard':
      default:
        return _buildDashboardView();
    }
  }

  Widget _buildInvoicesView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildKpiCardsRow(),
          const SizedBox(height: 20),
          _buildRecentInvoicesSection(),
        ],
      ),
    );
  }

  Widget _buildSyncCenterView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.sync_rounded, color: Color(0xFF0F172A), size: 24),
              SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Synchronization Center', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  SizedBox(height: 2),
                  Text('Local LAN database synchronization and server health.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSyncStatusCard(),
          const SizedBox(height: 20),
          _buildRecentActivityCard(),
        ],
      ),
    );
  }

  Widget _buildExceptionCenterView() {
    final pendingExceptions = _allInvoices.where((inv) => inv.status == InvoiceStatus.pending || inv.status == InvoiceStatus.flagged).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 24),
              SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Exception Center', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  SizedBox(height: 2),
                  Text('Invoices requiring operator review or data correction.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (pendingExceptions.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(36),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.check_circle_outline_rounded, size: 48, color: Color(0xFF10B981)),
                  SizedBox(height: 12),
                  Text('No Pending Exceptions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  SizedBox(height: 4),
                  Text('All invoices have passed validation and are fully synchronized.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ],
              ),
            )
          else
            _buildRecentInvoicesSection(),
        ],
      ),
    );
  }

  Widget _buildAuditTrailView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.fact_check_outlined, color: Color(0xFF0F172A), size: 24),
              SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Audit Trail', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  SizedBox(height: 2),
                  Text('System operations, OCR events and sync transaction history.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildRecentActivityCard(),
        ],
      ),
    );
  }

  Widget _buildDashboardView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI Cards Row (Section 5)
          _buildKpiCardsRow(),

          const SizedBox(height: 20),

          // Quick Actions Row (Section 6)
          _buildQuickActionsRow(),

          const SizedBox(height: 20),

          // Recent Invoices Main Focus Table (Section 7)
          _buildRecentInvoicesSection(),

          const SizedBox(height: 20),

          // Bottom Row: Recent Activity + Sync Status (Sections 8 & 9)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildRecentActivityCard()),
              const SizedBox(width: 16),
              Expanded(child: _buildSyncStatusCard()),
            ],
          ),
        ],
      ),
    );
  }

  // KPI CARDS ROW (Section 5)
  Widget _buildKpiCardsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildKpiCard(
            title: 'Total Invoices',
            count: '$_totalProcessedCount',
            trend: '↑ 12%',
            isTrendUp: true,
            subtitle: 'All processed invoices',
            icon: Icons.description_outlined,
            iconBg: const Color(0xFFE0F2FE),
            iconColor: const Color(0xFF0284C7),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKpiCard(
            title: 'Pending Review',
            count: '$_pendingReviewCount',
            trend: '↓ 5%',
            isTrendUp: false,
            subtitle: 'Awaiting verification',
            icon: Icons.hourglass_empty_rounded,
            iconBg: const Color(0xFFFEF3C7),
            iconColor: const Color(0xFFD97706),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKpiCard(
            title: 'Verified',
            count: '$_verifiedCount',
            trend: '↑ 18%',
            isTrendUp: true,
            subtitle: 'Successfully verified',
            icon: Icons.check_circle_outline_rounded,
            iconBg: const Color(0xFFDCFCE7),
            iconColor: const Color(0xFF10B981),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKpiCard(
            title: 'Pending Sync',
            count: '$_pendingSyncCount',
            trend: '↓ 20%',
            isTrendUp: false,
            subtitle: 'Not yet synchronized',
            icon: Icons.cloud_upload_outlined,
            iconBg: const Color(0xFFF3E8FF),
            iconColor: const Color(0xFF7C3AED),
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String count,
    required String trend,
    required bool isTrendUp,
    required String subtitle,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 18),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(count, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              const SizedBox(width: 8),
              Text(
                trend,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isTrendUp ? const Color(0xFF10B981) : const Color(0xFFDC2626),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return _buildKpiCard(
      title: title,
      count: value,
      trend: 'Active',
      isTrendUp: true,
      subtitle: subtitle,
      icon: icon,
      iconBg: color.withValues(alpha: 0.1),
      iconColor: color,
    );
  }

  Widget _buildSmallCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return _buildMetricCard(
      title: title,
      value: value,
      subtitle: subtitle,
      color: color,
      icon: icon,
    );
  }

  // QUICK ACTIONS ROW (Section 6)
  Widget _buildQuickActionsRow() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.flash_on_rounded, color: Color(0xFFD4A24E), size: 18),
              SizedBox(width: 8),
              Text('Quick Actions', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            ],
          ),
          const SizedBox(height: 2),
          const Text('Process new invoices or manage existing data.', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
          const SizedBox(height: 14),

          Row(
            children: [
              // Primary Action: Scan Invoice (Dark Navy)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _handleScanInvoice,
                  icon: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                  label: const Text('Scan Invoice'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Secondary: Upload Invoice
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _handleUploadInvoice,
                  icon: const Icon(Icons.upload_file_rounded, size: 16, color: Color(0xFF0F172A)),
                  label: const Text('Upload Invoice'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    backgroundColor: const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Secondary: Batch Processing
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openBatchScan,
                  icon: const Icon(Icons.layers_rounded, size: 16, color: Color(0xFF0F172A)),
                  label: const Text('Batch Processing'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    backgroundColor: const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Secondary: View Reports
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openReports,
                  icon: const Icon(Icons.analytics_rounded, size: 16, color: Color(0xFF0F172A)),
                  label: const Text('View Reports'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    backgroundColor: const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // RECENT INVOICES MAIN SECTION (Section 7)
  Widget _buildRecentInvoicesSection() {
    final hasFilter = _searchController.text.isNotEmpty || _selectedDateRange != null || _selectedStatus != null || _selectedVendor != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.description_outlined, color: Color(0xFF0F172A), size: 20),
                    SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Recent Invoices', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                        Text('Latest processed invoices from your system.', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                      ],
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _openReports,
                  child: const Text('View All →', style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Filters Bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        hintText: 'Search invoice number, vendor, GSTIN...',
                        hintStyle: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        prefixIcon: Icon(Icons.search_rounded, size: 16, color: Color(0xFF64748B)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Date Dropdown
                OutlinedButton.icon(
                  onPressed: _selectDateRange,
                  icon: const Icon(Icons.calendar_today_outlined, size: 14),
                  label: Text(_selectedDateRange == null ? 'Select date range ∨' : 'Date Range Selected'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),

                // Status Dropdown Filter
                DropdownButton<InvoiceStatus?>(
                  value: _selectedStatus,
                  hint: const Text('All Status ∨', style: TextStyle(fontSize: 11)),
                  underline: const SizedBox(),
                  onChanged: (val) {
                    setState(() => _selectedStatus = val);
                    _loadInvoices();
                  },
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All Status', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: InvoiceStatus.verified, child: Text('Verified', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: InvoiceStatus.pending, child: Text('Pending', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: InvoiceStatus.flagged, child: Text('Flagged', style: TextStyle(fontSize: 11))),
                  ],
                ),
                const SizedBox(width: 8),

                if (hasFilter)
                  TextButton(
                    onPressed: _clearFilters,
                    child: const Text('Clear Filters', style: TextStyle(fontSize: 11, color: Color(0xFFDC2626))),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Invoice Table View
          if (_filteredInvoices.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(36),
              child: Column(
                children: const [
                  Icon(Icons.search_off_rounded, size: 40, color: Color(0xFF94A3B8)),
                  SizedBox(height: 10),
                  Text('No matching invoices found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text('Try adjusting filters or capturing a new invoice.', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                ],
              ),
            )
          else
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1.8), // Inv No
                1: FlexColumnWidth(2.8), // Vendor
                2: FlexColumnWidth(1.8), // Date
                3: FlexColumnWidth(1.8), // Amount
                4: FlexColumnWidth(1.8), // Validation
                5: FlexColumnWidth(1.8), // Verification
                6: FlexColumnWidth(1.8), // Sync Status
                7: FlexColumnWidth(1.0), // Actions
              },
              children: [
                // Table Header Row
                const TableRow(
                  decoration: BoxDecoration(color: Color(0xFFF8FAFC)),
                  children: [
                    _TableHeaderCell('Invoice No.'),
                    _TableHeaderCell('Vendor'),
                    _TableHeaderCell('Date'),
                    _TableHeaderCell('Amount'),
                    _TableHeaderCell('Validation'),
                    _TableHeaderCell('Verification'),
                    _TableHeaderCell('Sync Status'),
                    _TableHeaderCell('Actions'),
                  ],
                ),

                // Invoice Table Rows (REAL DATA)
                ..._filteredInvoices.take(6).map((inv) {
                  return TableRow(
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                    ),
                    children: [
                      // Inv No (Blue link)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: InkWell(
                          onTap: () => _openInvoiceDetails(inv),
                          child: Text(
                            inv.invoiceNumber.isNotEmpty ? inv.invoiceNumber : 'INV-${inv.id}',
                            style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                      // Vendor
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Text(
                          inv.vendorName.isNotEmpty ? inv.vendorName : 'Unknown Vendor',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF0F172A)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Date
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Text(inv.formattedDate, style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                      ),
                      // Amount
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Text(inv.formattedTotal, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      // Validation Badge
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: _buildValidationBadge(inv),
                      ),
                      // Verification Badge
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: _buildVerificationBadge(inv.status),
                      ),
                      // Sync Status Badge
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: _buildSyncStatusBadge(inv.syncStatus),
                      ),
                      // Actions Menu
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, size: 18, color: Color(0xFF64748B)),
                          onSelected: (val) {
                            if (val == 'view') _openInvoiceDetails(inv);
                            if (val == 'delete') _confirmDeleteInvoice(inv);
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'view', child: Text('View Details')),
                            const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Color(0xFFDC2626)))),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildValidationBadge(Invoice inv) {
    if (inv.gstin.isNotEmpty && inv.gstin.length != 15) {
      return _buildBadge('Tax Mismatch', const Color(0xFFFEF2F2), const Color(0xFFDC2626), Icons.error_outline_rounded);
    }
    if (inv.invoiceNumber.isEmpty || inv.vendorName.isEmpty) {
      return _buildBadge('Low Confidence', const Color(0xFFFFFBEB), const Color(0xFFD97706), Icons.warning_amber_rounded);
    }
    return _buildBadge('Valid', const Color(0xFFECFDF5), const Color(0xFF10B981), Icons.check_circle_rounded);
  }

  Widget _buildVerificationBadge(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.verified:
        return _buildBadge('Verified', const Color(0xFFECFDF5), const Color(0xFF10B981), Icons.check_circle_rounded);
      case InvoiceStatus.pending:
        return _buildBadge('Pending', const Color(0xFFFFFBEB), const Color(0xFFD97706), Icons.hourglass_empty_rounded);
      case InvoiceStatus.flagged:
        return _buildBadge('Flagged', const Color(0xFFFEF2F2), const Color(0xFFDC2626), Icons.flag_rounded);
    }
  }

  Widget _buildSyncStatusBadge(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return _buildBadge('Synced', const Color(0xFFEFF6FF), const Color(0xFF2563EB), Icons.cloud_done_rounded);
      case SyncStatus.syncing:
        return _buildBadge('Syncing', const Color(0xFFEFF6FF), const Color(0xFF2563EB), Icons.sync_rounded);
      case SyncStatus.syncFailed:
        return _buildBadge('Failed', const Color(0xFFFEF2F2), const Color(0xFFDC2626), Icons.cloud_off_rounded);
      case SyncStatus.pendingSync:
        return _buildBadge('Pending', const Color(0xFFFFFBEB), const Color(0xFFD97706), Icons.cloud_upload_outlined);
    }
  }

  Widget _buildBadge(String label, Color bg, Color fg, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: fg),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ==========================================
  // 8. BOTTOM LEFT — RECENT ACTIVITY
  // ==========================================
  Widget _buildRecentActivityCard() {
    // Generate recent activity entries based on actual invoice state
    final activities = <_ActivityItem>[];
    for (final inv in _allInvoices.take(4)) {
      final invNum = inv.invoiceNumber.isNotEmpty ? inv.invoiceNumber : 'INV-${inv.id}';
      if (inv.syncStatus == SyncStatus.synced) {
        activities.add(_ActivityItem(time: '09:28 PM', title: 'Invoice $invNum synchronized successfully', color: const Color(0xFF10B981)));
      } else if (inv.status == InvoiceStatus.verified) {
        activities.add(_ActivityItem(time: '09:42 PM', title: 'Invoice $invNum processed', color: const Color(0xFF10B981)));
      } else if (inv.status == InvoiceStatus.pending) {
        activities.add(_ActivityItem(time: '09:38 PM', title: 'Invoice $invNum awaiting verification', color: const Color(0xFFD97706)));
      } else {
        activities.add(_ActivityItem(time: '09:31 PM', title: 'Invoice $invNum validation failed', color: const Color(0xFFDC2626)));
      }
    }

    if (activities.isEmpty) {
      activities.add(_ActivityItem(time: 'Just now', title: 'App initialized local ledger', color: const Color(0xFF10B981)));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Row(
                children: [
                  Icon(Icons.access_time_rounded, size: 18, color: Color(0xFF0F172A)),
                  SizedBox(width: 8),
                  Text('Recent Activity', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                ],
              ),
              Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 18),
            ],
          ),
          const SizedBox(height: 2),
          const Text('Latest actions in your system.', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
          const SizedBox(height: 14),

          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activities.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final act = activities[index];
              return Row(
                children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: act.color, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Text(act.time, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(act.title, style: const TextStyle(fontSize: 11.5, color: Color(0xFF0F172A)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(4)),
                    child: const Text('System', style: TextStyle(color: Color(0xFF2563EB), fontSize: 9.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 9. BOTTOM RIGHT — SYNCHRONIZATION STATUS
  // ==========================================
  Widget _buildSyncStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.sync_rounded, size: 18, color: Color(0xFF0F172A)),
                  SizedBox(width: 8),
                  Text('Synchronization Status', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                ],
              ),
              TextButton(
                onPressed: _openReports,
                child: const Text('View Details →', style: TextStyle(color: Color(0xFF2563EB), fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text('LAN synchronization with central server.', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
          const SizedBox(height: 14),

          _buildSyncStatusRow(Icons.dns_rounded, 'LAN Server', _isLanConnected ? 'Connected' : 'Disconnected', _isLanConnected ? const Color(0xFF10B981) : const Color(0xFFDC2626)),
          const SizedBox(height: 6),
          _buildSyncStatusRow(Icons.shield_outlined, 'Database', 'Connected', const Color(0xFF10B981)),
          const SizedBox(height: 6),
          _buildSyncStatusRow(Icons.hourglass_empty_rounded, 'Pending Invoices', '$_pendingSyncCount', const Color(0xFFD97706)),
          const SizedBox(height: 6),
          _buildSyncStatusRow(Icons.check_circle_outline_rounded, 'Synced Invoices', '$_syncedCount', const Color(0xFF0F172A)),
          const SizedBox(height: 6),
          _buildSyncStatusRow(Icons.cloud_off_rounded, 'Failed Invoices', '$_syncFailedCount', const Color(0xFFDC2626)),
        ],
      ),
    );
  }

  Widget _buildSyncStatusRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569))),
        const Spacer(),
        Row(
          children: [
            if (value == 'Connected' || value == 'Disconnected')
              Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            Text(value, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ],
    );
  }

  // ==========================================
  // PAGE 1 — BATCH PROCESSING CENTER VIEW
  // ==========================================
  Future<void> _pickBatchGalleryImages() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage(imageQuality: 100);
      if (pickedFiles.isNotEmpty && mounted) {
        setState(() {
          for (final file in pickedFiles) {
            _batchItems.add(BatchInvoiceItem(
              id: 'batch-${DateTime.now().microsecondsSinceEpoch}-${_batchItems.length + 1}',
              imageFile: File(file.path),
            ));
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error selecting images: $e'), backgroundColor: const Color(0xFFDC2626)));
      }
    }
  }

  Future<void> _captureBatchCameraPhoto() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.camera, imageQuality: 100);
      if (pickedFile != null && mounted) {
        setState(() {
          _batchItems.add(BatchInvoiceItem(
            id: 'batch-${DateTime.now().microsecondsSinceEpoch}-${_batchItems.length + 1}',
            imageFile: File(pickedFile.path),
          ));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error capturing photo: $e'), backgroundColor: const Color(0xFFDC2626)));
      }
    }
  }

  void _startBatchProcessing() {
    if (_isBatchProcessing) return;
    final pending = _batchItems.where((i) => i.status == BatchItemStatus.pending).toList();
    if (pending.isEmpty) return;

    setState(() {
      _isBatchProcessing = true;
      _batchCancelRequested = false;
      _batchCurrentIndex = 0;
      _batchTotalCount = pending.length;
    });

    _batchService.processBatchItems(
      _batchItems,
      isCancelled: () => _batchCancelRequested,
      onProgress: (current, total) {
        if (mounted) {
          setState(() {
            _batchCurrentIndex = current;
            _batchTotalCount = total;
          });
        }
      },
      onItemUpdated: () {
        if (mounted) setState(() {});
      },
    ).then((_) {
      if (mounted) {
        setState(() {
          _isBatchProcessing = false;
        });
      }
    });
  }

  void _cancelBatchProcessing() {
    setState(() {
      _batchCancelRequested = true;
      _isBatchProcessing = false;
    });
  }

  Future<void> _saveReadyBatchInvoices() async {
    final readyItems = _batchItems.where((i) => i.status == BatchItemStatus.ready || (i.isReviewed && i.status == BatchItemStatus.needsReview)).toList();
    if (readyItems.isEmpty) return;

    final summary = await _batchService.saveBatchInvoices(readyItems);
    await _loadInvoices();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved ${summary.savedCount} invoices to SQLite database.'),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildBatchProcessingView() {
    final readyCount = _batchItems.where((i) => i.status == BatchItemStatus.ready).length;
    final reviewCount = _batchItems.where((i) => i.status == BatchItemStatus.needsReview).length;
    final duplicateCount = _batchItems.where((i) => i.status == BatchItemStatus.duplicate).length;
    final failedCount = _batchItems.where((i) => i.status == BatchItemStatus.ocrFailed).length;
    final savedCount = _batchItems.where((i) => i.status == BatchItemStatus.saved).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Batch Processing', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  SizedBox(height: 2),
                  Text('Scan, upload and process multiple invoices at once.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF86EFAC))),
                child: Row(
                  children: const [
                    Icon(Icons.circle, color: Color(0xFF16A34A), size: 8),
                    SizedBox(width: 6),
                    Text('Offline • Local Processing', style: TextStyle(color: Color(0xFF15803D), fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 6 Compact Top Metric Cards
          Row(
            children: [
              Expanded(child: _buildMetricCard(title: 'Total', value: '${_batchItems.length}', subtitle: 'Selected files', color: const Color(0xFF2563EB), icon: Icons.collections_outlined)),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricCard(title: 'Ready', value: '$readyCount', subtitle: 'Ready to process', color: const Color(0xFF059669), icon: Icons.check_circle_outline)),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricCard(title: 'Review', value: '$reviewCount', subtitle: 'Awaiting verification', color: const Color(0xFFD97706), icon: Icons.hourglass_empty_rounded)),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricCard(title: 'Duplicate', value: '$duplicateCount', subtitle: 'Duplicate invoices', color: const Color(0xFF7C3AED), icon: Icons.layers_outlined)),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricCard(title: 'Failed', value: '$failedCount', subtitle: 'Processing failed', color: const Color(0xFFDC2626), icon: Icons.error_outline_rounded)),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricCard(title: 'Saved', value: '$savedCount', subtitle: 'Successfully saved', color: const Color(0xFF0284C7), icon: Icons.cloud_done_outlined)),
            ],
          ),
          const SizedBox(height: 16),

          // Batch Upload Area
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Add Invoices', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                      const SizedBox(height: 2),
                      const Text('Select multiple invoice images or capture invoices for batch processing.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFCBD5E1))),
                        child: Center(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: const BoxDecoration(color: Color(0xFFEFF6FF), shape: BoxShape.circle),
                                child: const Icon(Icons.cloud_upload_outlined, color: Color(0xFF2563EB), size: 26),
                              ),
                              const SizedBox(height: 10),
                              const Text('Drop invoice images here or Select files from your device', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                              const SizedBox(height: 2),
                              const Text('Supported formats: JPG, PNG, PDF', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _isBatchProcessing ? null : _pickBatchGalleryImages,
                                    icon: const Icon(Icons.folder_open_rounded, size: 16),
                                    label: const Text('Select Invoices'),
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white),
                                  ),
                                  const SizedBox(width: 10),
                                  OutlinedButton.icon(
                                    onPressed: _isBatchProcessing ? null : _captureBatchCameraPhoto,
                                    icon: const Icon(Icons.camera_alt_outlined, size: 16),
                                    label: const Text('Capture with Camera'),
                                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF334155)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Quick Actions', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _isBatchProcessing ? null : _captureBatchCameraPhoto,
                        icon: const Icon(Icons.camera_alt_outlined, size: 15),
                        label: const Text('Capture with Camera', style: TextStyle(fontSize: 11.5)),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 38), alignment: Alignment.centerLeft),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _isBatchProcessing ? null : _pickBatchGalleryImages,
                        icon: const Icon(Icons.photo_library_outlined, size: 15),
                        label: const Text('Select from Gallery', style: TextStyle(fontSize: 11.5)),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 38), alignment: Alignment.centerLeft),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _batchItems.isEmpty || _isBatchProcessing ? null : () => setState(() => _batchItems.clear()),
                        icon: const Icon(Icons.delete_outline_rounded, size: 15, color: Color(0xFFDC2626)),
                        label: const Text('Clear All', style: TextStyle(color: Color(0xFFDC2626), fontSize: 11.5)),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 38), alignment: Alignment.centerLeft),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Processing Queue Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Processing Queue', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                        SizedBox(height: 2),
                        Text('Selected invoices waiting for processing.', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                      ],
                    ),
                    Row(
                      children: [
                        if (_batchItems.any((i) => i.status == BatchItemStatus.ready || i.status == BatchItemStatus.needsReview))
                          ElevatedButton.icon(
                            onPressed: _saveReadyBatchInvoices,
                            icon: const Icon(Icons.save_outlined, size: 16),
                            label: Text('Save Ready (${readyCount + reviewCount})'),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
                          ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _batchItems.isEmpty ? null : (_isBatchProcessing ? _cancelBatchProcessing : _startBatchProcessing),
                          icon: Icon(_isBatchProcessing ? Icons.stop_rounded : Icons.bolt_rounded, size: 16),
                          label: Text(_isBatchProcessing ? 'Cancel' : 'Process All'),
                          style: ElevatedButton.styleFrom(backgroundColor: _isBatchProcessing ? const Color(0xFFDC2626) : const Color(0xFF0F172A), foregroundColor: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_batchItems.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: const [
                          Icon(Icons.inbox_outlined, size: 40, color: Color(0xFF94A3B8)),
                          SizedBox(height: 8),
                          Text('No invoices added yet', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                          SizedBox(height: 4),
                          Text('Add invoice images to start batch processing.', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                        ],
                      ),
                    ),
                  )
                else
                  _buildBatchQueueTable(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchQueueTable() {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFF1F5F9)), borderRadius: BorderRadius.circular(8)),
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(40),
          1: FlexColumnWidth(3),
          2: FlexColumnWidth(1.5),
          3: FlexColumnWidth(2),
          4: FixedColumnWidth(60),
        },
        children: [
          const TableRow(
            decoration: BoxDecoration(color: Color(0xFFF8FAFC)),
            children: [
              _TableHeaderCell('#'),
              _TableHeaderCell('File Name'),
              _TableHeaderCell('Size'),
              _TableHeaderCell('Status'),
              _TableHeaderCell('Actions'),
            ],
          ),
          ..._batchItems.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            final name = item.imageFile.path.split(Platform.pathSeparator).last;
            return TableRow(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.15)))),
              children: [
                Padding(padding: const EdgeInsets.all(10), child: Text('${idx + 1}', style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)))),
                Padding(padding: const EdgeInsets.all(10), child: Text(name, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Padding(padding: const EdgeInsets.all(10), child: Text('${(item.imageFile.existsSync() ? item.imageFile.lengthSync() / 1024 : 0).toStringAsFixed(1)} KB', style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)))),
                Padding(padding: const EdgeInsets.all(10), child: _buildBatchStatusBadge(item.status)),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFF94A3B8)),
                    onPressed: () => setState(() => _batchItems.removeAt(idx)),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBatchStatusBadge(BatchItemStatus status) {
    String text = 'Ready';
    Color bg = const Color(0xFFDCFCE7);
    Color fg = const Color(0xFF16A34A);

    switch (status) {
      case BatchItemStatus.processing:
        text = 'Processing';
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF2563EB);
        break;
      case BatchItemStatus.needsReview:
        text = 'Review';
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFD97706);
        break;
      case BatchItemStatus.duplicate:
        text = 'Duplicate';
        bg = const Color(0xFFF3E8FF);
        fg = const Color(0xFF7C3AED);
        break;
      case BatchItemStatus.ocrFailed:
        text = 'Failed';
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFDC2626);
        break;
      case BatchItemStatus.saved:
        text = 'Saved';
        bg = const Color(0xFFE0F2FE);
        fg = const Color(0xFF0284C7);
        break;
      case BatchItemStatus.pending:
      case BatchItemStatus.ready:
      default:
        text = 'Ready';
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF16A34A);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.bold)),
    );
  }

  // ==========================================
  // PAGE 2 — REPORTS & EXPORT CENTER VIEW
  // ==========================================
  Widget _buildReportsView() {
    final stats = _reportService.calculateStatistics(_filteredInvoices);
    final totalValue = stats.grandTotal > 0 ? stats.grandTotal : _filteredInvoices.fold<double>(0, (sum, i) => sum + i.totalAmount);
    final totalTax = stats.totalTax > 0 ? stats.totalTax : _filteredInvoices.fold<double>(0, (sum, i) => sum + i.cgst + i.sgst + i.igst);
    final uniqueVendors = _filteredInvoices.map((i) => i.vendorName).where((v) => v.isNotEmpty).toSet().length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Banner
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Reports & Analytics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  SizedBox(height: 2),
                  Text('Analyze invoice data and generate detailed reports.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ],
              ),
              PopupMenuButton<String>(
                onSelected: (val) async {
                  if (val == 'csv') {
                    final csv = _reportService.generateCsv(_filteredInvoices);
                    await _exportHelper.exportString(content: csv, fileName: 'Invoice_Report_${DateTime.now().millisecondsSinceEpoch}.csv', mimeType: 'text/csv');
                  } else if (val == 'xlsx') {
                    final bytes = _reportService.generateExcel(_filteredInvoices);
                    await _exportHelper.exportBytes(bytes: Uint8List.fromList(bytes), fileName: 'Invoice_Report_${DateTime.now().millisecondsSinceEpoch}.xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
                  } else if (val == 'pdf') {
                    final bytes = await _reportService.generatePdf(_filteredInvoices);
                    await _exportHelper.exportBytes(bytes: bytes, fileName: 'Invoice_Report_${DateTime.now().millisecondsSinceEpoch}.pdf', mimeType: 'application/pdf');
                  }
                },
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 'csv', child: Text('Export CSV')),
                  PopupMenuItem(value: 'xlsx', child: Text('Export Excel')),
                  PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: const [
                      Icon(Icons.file_download_outlined, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text('Export Report', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Filter Bar
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildFilterChip('All Time', _reportsPreset == 'All Time', () => setState(() => _reportsPreset = 'All Time')),
                _buildFilterChip('This Month', _reportsPreset == 'This Month', () => setState(() => _reportsPreset = 'This Month')),
                _buildFilterChip('Last 30 Days', _reportsPreset == 'Last 30 Days', () => setState(() => _reportsPreset = 'Last 30 Days')),
                OutlinedButton(onPressed: _selectDateRange, child: const Text('Custom Date', style: TextStyle(fontSize: 11.5))),
                const SizedBox(width: 10),
                DropdownButton<InvoiceStatus?>(
                  value: _selectedStatus,
                  hint: const Text('All Status', style: TextStyle(fontSize: 12)),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All Status')),
                    DropdownMenuItem(value: InvoiceStatus.verified, child: Text('Verified')),
                    DropdownMenuItem(value: InvoiceStatus.pending, child: Text('Pending')),
                    DropdownMenuItem(value: InvoiceStatus.flagged, child: Text('Flagged / Failed')),
                  ],
                  onChanged: (val) => setState(() => _selectedStatus = val),
                ),
                ElevatedButton(onPressed: _loadInvoices, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white), child: const Text('Apply Filters')),
                TextButton(onPressed: _clearFilters, child: const Text('Clear Filters', style: TextStyle(color: Color(0xFF64748B)))),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4 Analytics KPI Cards
          Row(
            children: [
              Expanded(child: _buildSmallCard(title: 'Total Invoices', value: '${_filteredInvoices.length}', subtitle: 'All processed invoices', color: const Color(0xFF2563EB), icon: Icons.description_outlined)),
              const SizedBox(width: 12),
              Expanded(child: _buildSmallCard(title: 'Total Value', value: '₹${totalValue.toStringAsFixed(2)}', subtitle: 'Total taxable value', color: const Color(0xFF059669), icon: Icons.account_balance_wallet_outlined)),
              const SizedBox(width: 12),
              Expanded(child: _buildSmallCard(title: 'Total Tax', value: '₹${totalTax.toStringAsFixed(2)}', subtitle: 'CGST + SGST + IGST', color: const Color(0xFFD97706), icon: Icons.receipt_long_outlined)),
              const SizedBox(width: 12),
              Expanded(child: _buildSmallCard(title: 'Unique Vendors', value: '$uniqueVendors', subtitle: 'Active vendors', color: const Color(0xFF7C3AED), icon: Icons.storefront_outlined)),
            ],
          ),
          const SizedBox(height: 16),

          // 2-Column Charts / Analytics Section
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Invoices by Status', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                      const SizedBox(height: 14),
                      _buildReportStatusRow('Verified', _filteredInvoices.where((i) => i.status == InvoiceStatus.verified).length, _filteredInvoices.length, const Color(0xFF059669)),
                      const SizedBox(height: 10),
                      _buildReportStatusRow('Pending', _filteredInvoices.where((i) => i.status == InvoiceStatus.pending).length, _filteredInvoices.length, const Color(0xFFD97706)),
                      const SizedBox(height: 10),
                      _buildReportStatusRow('Flagged', _filteredInvoices.where((i) => i.status == InvoiceStatus.flagged).length, _filteredInvoices.length, const Color(0xFFDC2626)),
                      const SizedBox(height: 10),
                      _buildReportStatusRow('Synced', _filteredInvoices.where((i) => i.syncStatus == SyncStatus.synced).length, _filteredInvoices.length, const Color(0xFF2563EB)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Top Vendors', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                      const SizedBox(height: 14),
                      ..._getTopVendors(_filteredInvoices).map((v) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(v.key.isEmpty ? 'Unknown' : v.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                            Text('${v.value} invoices', style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Export Toolbar Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Export Data', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    SizedBox(height: 2),
                    Text('Download invoice reports in your preferred format.', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                  ],
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final csv = _reportService.generateCsv(_filteredInvoices);
                        await _exportHelper.exportString(content: csv, fileName: 'Invoices.csv', mimeType: 'text/csv');
                      },
                      icon: const Icon(Icons.table_chart_outlined, size: 16),
                      label: const Text('CSV'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final bytes = _reportService.generateExcel(_filteredInvoices);
                        await _exportHelper.exportBytes(bytes: Uint8List.fromList(bytes), fileName: 'Invoices.xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
                      },
                      icon: const Icon(Icons.grid_on_outlined, size: 16),
                      label: const Text('Excel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final bytes = await _reportService.generatePdf(_filteredInvoices);
                        await _exportHelper.exportBytes(bytes: bytes, fileName: 'Invoices.pdf', mimeType: 'application/pdf');
                      },
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                      label: const Text('PDF'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(fontSize: 11.5, color: isSelected ? Colors.white : const Color(0xFF475569), fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _buildReportStatusRow(String label, int count, int total, Color color) {
    final pct = total > 0 ? count / total : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
            Text('$count (${(pct * 100).toStringAsFixed(1)}%)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: pct, backgroundColor: color.withValues(alpha: 0.1), color: color, minHeight: 6),
      ],
    );
  }

  List<MapEntry<String, int>> _getTopVendors(List<Invoice> invoices) {
    final counts = <String, int>{};
    for (final inv in invoices) {
      final v = inv.vendorName.trim();
      if (v.isNotEmpty) counts[v] = (counts[v] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).toList();
  }

  // ==========================================
  // PAGE 3 — SETTINGS CENTER VIEW
  // ==========================================
  Widget _buildSettingsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              SizedBox(height: 2),
              Text('Manage application settings, security and system preferences.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Nav Card
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: Column(
                    children: [
                      _buildSettingsNavItem('Security & Privacy', Icons.security_rounded),
                      _buildSettingsNavItem('Application Settings', Icons.tune_rounded),
                      _buildSettingsNavItem('Backup & Restore', Icons.backup_outlined),
                      _buildSettingsNavItem('Database & Sync', Icons.dns_outlined),
                      _buildSettingsNavItem('User Management', Icons.manage_accounts_outlined),
                      _buildSettingsNavItem('System Information', Icons.info_outline_rounded),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Right Content Panel
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: _buildSelectedSettingsTab(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsNavItem(String title, IconData icon) {
    final isSelected = _activeSettingsSection == title;
    return InkWell(
      onTap: () => setState(() => _activeSettingsSection = title),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : const Color(0xFF64748B)),
            const SizedBox(width: 10),
            Text(title, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : const Color(0xFF334155), fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedSettingsTab() {
    switch (_activeSettingsSection) {
      case 'Security & Privacy':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Security & Privacy', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            const SizedBox(height: 14),
            SwitchListTile(
              title: const Text('Security Lock', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              subtitle: const Text('Enable authentication to protect local helicopter division invoice data.', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
              value: _isSecurityEnabled,
              onChanged: (val) async {
                await AppSecurityService.instance.setSecurityEnabled(val);
                setState(() => _isSecurityEnabled = val);
              },
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('App Launch Authentication', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              subtitle: const Text('Require authentication when launching the application.', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
              value: _isAppLaunchAuthEnabled,
              onChanged: (val) => setState(() => _isAppLaunchAuthEnabled = val),
            ),
            const SizedBox(height: 16),
            const Text('Active Security Protections', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            const SizedBox(height: 10),
            _buildProtectionRow(true, '100% Offline Execution', 'Local SQLCipher & local processing'),
            _buildProtectionRow(true, 'Android FLAG_SECURE Active', 'Screen capture protection'),
            _buildProtectionRow(true, 'Android Auto-Backup Disabled', 'Data leakage prevention'),
            _buildProtectionRow(true, 'Authenticated Backup Encryption', 'AES-256 backup vault'),
            _buildProtectionRow(true, 'Temporary File Cleanup', 'Automated temp cache purge'),
            _buildProtectionRow(_isSecurityEnabled, 'Local App Authentication', 'Hardware / PIN lock status'),
          ],
        );
      case 'Backup & Restore':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Backup & Restore', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            const SizedBox(height: 6),
            const Text('Create authenticated AES-256 encrypted backups of local invoice database.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupRestoreScreen())),
              icon: const Icon(Icons.backup_outlined, size: 16),
              label: const Text('Open Backup & Restore Vault'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white),
            ),
          ],
        );
      case 'Database & Sync':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Database & Sync', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            const SizedBox(height: 14),
            _buildProtectionRow(true, 'SQLCipher 256-bit Encryption', 'Active local database encryption'),
            _buildProtectionRow(_isLanConnected, 'LAN Server Connectivity', _isLanConnected ? 'Connected to http://127.0.0.1:8000' : 'Disconnected'),
          ],
        );
      case 'User Management':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('User Management', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            const SizedBox(height: 6),
            const Text('Manage local users and Role-Based Access Control (RBAC).', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen())),
              icon: const Icon(Icons.people_outline, size: 16),
              label: const Text('Manage Accounts & RBAC Roles'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white),
            ),
          ],
        );
      case 'System Information':
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('System Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            SizedBox(height: 14),
            Text('Application: TaxInvoice AI (Helicopter Division)', style: TextStyle(fontSize: 12.5)),
            SizedBox(height: 4),
            Text('Version: v1.0.0 (Production Build)', style: TextStyle(fontSize: 12.5)),
            SizedBox(height: 4),
            Text('Database: SQLCipher 256-bit AES (Local)', style: TextStyle(fontSize: 12.5)),
          ],
        );
    }
  }

  Widget _buildProtectionRow(bool isActive, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(isActive ? Icons.check_circle : Icons.radio_button_unchecked, color: isActive ? const Color(0xFF059669) : const Color(0xFF94A3B8), size: 18),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              Text(desc, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            ],
          ),
        ],
      ),
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  final String title;
  const _TableHeaderCell(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
    );
  }
}

class _ActivityItem {
  final String time;
  final String title;
  final Color color;

  _ActivityItem({required this.time, required this.title, required this.color});
}
