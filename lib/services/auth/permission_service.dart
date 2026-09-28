import '../../models/user.dart';
import 'auth_service.dart';

class UnauthorizedException implements Exception {
  final String message;
  const UnauthorizedException([this.message = 'Access denied. You do not have permission to perform this action.']);

  @override
  String toString() => 'UnauthorizedException: $message';
}

/// Central Role-Based Access Control (RBAC) Permission Service for TaxInvoice AI.
///
/// STABILITY & PRIVACY ASSURANCE:
/// - Evaluates permissions strictly based on the currently authenticated UserSession.
/// - Enforces permission checks at the service and business-logic layer.
class PermissionService {
  static final PermissionService instance = PermissionService();

  final AuthService _authService;

  PermissionService({AuthService? authService}) : _authService = authService ?? AuthService.instance;

  UserRole? get currentRole => _authService.currentSession?.role;

  bool get isAdmin => currentRole == UserRole.admin;
  bool get isOperator => currentRole == UserRole.operator;
  bool get isReviewer => currentRole == UserRole.reviewer;

  // --- Permission Evaluators ---

  bool canManageUsers() => isAdmin;

  bool canProcessInvoices() => isAdmin || isOperator;

  bool canCaptureInvoices() => isAdmin || isOperator;

  bool canEditInvoices() => isAdmin || isOperator;

  bool canRunBatchProcessing() => isAdmin || isOperator;

  bool canRunRpa() => isAdmin || isOperator;

  bool canReviewInvoices() => isAdmin || isOperator || isReviewer;

  bool canApproveInvoices() => isAdmin || isReviewer;

  bool canViewHistory() => isAdmin || isOperator || isReviewer;

  bool canViewReports() => isAdmin || isReviewer;

  bool canExportReports() => isAdmin || isReviewer;

  bool canBackupRestore() => isAdmin;

  bool canAccessSecuritySettings() => isAdmin;

  // --- Service-Layer Guards ---

  void checkManageUsers() {
    if (!canManageUsers()) {
      throw const UnauthorizedException('Admin privileges required for User Management.');
    }
  }

  void checkProcessInvoices() {
    if (!canProcessInvoices()) {
      throw const UnauthorizedException('Operator or Admin privileges required to process invoices.');
    }
  }

  void checkCaptureInvoices() {
    if (!canCaptureInvoices()) {
      throw const UnauthorizedException('Operator or Admin privileges required to capture invoices.');
    }
  }

  void checkEditInvoices() {
    if (!canEditInvoices()) {
      throw const UnauthorizedException('Operator or Admin privileges required to edit invoices.');
    }
  }

  void checkRunBatchProcessing() {
    if (!canRunBatchProcessing()) {
      throw const UnauthorizedException('Operator or Admin privileges required for Batch Scanning.');
    }
  }

  void checkRunRpa() {
    if (!canRunRpa()) {
      throw const UnauthorizedException('Operator or Admin privileges required for RPA Workflows.');
    }
  }

  void checkReviewInvoices() {
    if (!canReviewInvoices()) {
      throw const UnauthorizedException('Privileges required to review invoices.');
    }
  }

  void checkApproveInvoices() {
    if (!canApproveInvoices()) {
      throw const UnauthorizedException('Reviewer or Admin privileges required to approve invoices.');
    }
  }

  void checkViewReports() {
    if (!canViewReports()) {
      throw const UnauthorizedException('Reviewer or Admin privileges required to view Reports.');
    }
  }

  void checkExportReports() {
    if (!canExportReports()) {
      throw const UnauthorizedException('Reviewer or Admin privileges required to export Reports.');
    }
  }

  void checkBackupRestore() {
    if (!canBackupRestore()) {
      throw const UnauthorizedException('Admin privileges required for Backup & Restore.');
    }
  }

  void checkAccessSecuritySettings() {
    if (!canAccessSecuritySettings()) {
      throw const UnauthorizedException('Admin privileges required for Security Settings.');
    }
  }
}
