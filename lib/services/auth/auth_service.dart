import 'package:flutter/foundation.dart';
import '../../models/user.dart';
import '../database/database_helper.dart';
import 'audit_service.dart';
import 'password_hasher.dart';

class AuthResult {
  final bool success;
  final String errorMessage;
  final UserSession? session;

  const AuthResult._({
    required this.success,
    this.errorMessage = '',
    this.session,
  });

  factory AuthResult.ok(UserSession session) {
    return AuthResult._(success: true, session: session);
  }

  factory AuthResult.failure(String message) {
    return AuthResult._(success: false, errorMessage: message);
  }
}

/// Offline Authentication Service for TaxInvoice AI (Helicopter Division).
///
/// STABILITY & PRIVACY ASSURANCE:
/// - Uses PBKDF2-HMAC-SHA256 password hashing with unique 256-bit salts.
/// - Stores credentials strictly inside encrypted SQLCipher app_users table.
/// - Stores active session ONLY in ephemeral runtime memory.
/// - Provides zero plaintext password storage or log output.
class AuthService {
  static final AuthService instance = AuthService._internal();

  final DatabaseHelper _dbHelper;
  final AuditService _auditService;

  UserSession? _currentSession;

  AuthService._internal({
    DatabaseHelper? dbHelper,
    AuditService? auditService,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _auditService = auditService ?? AuditService.instance;

  @visibleForTesting
  AuthService.withDependencies({
    required DatabaseHelper dbHelper,
    required AuditService auditService,
  })  : _dbHelper = dbHelper,
        _auditService = auditService;

  /// Returns active user session, or null if unauthenticated.
  UserSession? get currentSession => _currentSession;

  /// Returns true if an active user session exists.
  bool get isAuthenticated => _currentSession != null;

  /// ONLY for test suite setup. Allows test runners to inject an authenticated test session.
  @visibleForTesting
  void setTestSession(UserSession? session) {
    _currentSession = session;
  }

  /// Checks if the database contains 0 user accounts (First-Run state).
  Future<bool> isFirstRun() async {
    try {
      final db = await _dbHelper.database;
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM app_users;');
      final count = (result.first['count'] as num?)?.toInt() ?? 0;
      return count == 0;
    } catch (e) {
      debugPrint('[AuthService] Error checking user count: $e');
      return true;
    }
  }

  /// Creates the initial Administrator account on first run.
  Future<AuthResult> createFirstRunAdmin({
    required String username,
    required String password,
    required String confirmPassword,
  }) async {
    final cleanUsername = username.trim();
    if (cleanUsername.isEmpty) {
      return AuthResult.failure('Username is required.');
    }

    if (password.length < 8) {
      return AuthResult.failure('Password must be at least 8 characters long.');
    }

    final hasLetter = password.contains(RegExp(r'[a-zA-Z]'));
    final hasDigit = password.contains(RegExp(r'[0-9]'));
    if (!hasLetter || !hasDigit) {
      return AuthResult.failure('Password must contain both letters and numbers.');
    }

    if (password != confirmPassword) {
      return AuthResult.failure('Passwords do not match.');
    }

    final lowerUser = cleanUsername.toLowerCase();
    final lowerPass = password.toLowerCase();
    if ((lowerUser == 'admin' && lowerPass == 'admin') ||
        (lowerUser == 'administrator' && lowerPass == 'admin') ||
        lowerPass == 'password' ||
        lowerPass == '12345678') {
      return AuthResult.failure('Default or weak credentials are not allowed.');
    }

    try {
      final db = await _dbHelper.database;
      final existing = await db.query(
        'app_users',
        where: 'LOWER(username) = ?',
        whereArgs: [lowerUser],
      );
      if (existing.isNotEmpty) {
        return AuthResult.failure('Username is already taken.');
      }

      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hashPassword(password, salt);
      final now = DateTime.now();

      final adminUser = AppUser(
        id: 'user_${now.microsecondsSinceEpoch}',
        username: cleanUsername,
        passwordHash: hash,
        passwordSalt: salt,
        role: UserRole.admin,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      await db.insert('app_users', adminUser.toMap());

      await _auditService.logEvent(
        eventType: 'USER_CREATED',
        actorUsername: cleanUsername,
        targetUsername: cleanUsername,
        details: 'Initial Admin Created',
      );

      return await login(username: cleanUsername, password: password);
    } catch (e) {
      debugPrint('[AuthService] Exception creating first-run admin: $e');
      return AuthResult.failure('Failed to create Administrator account.');
    }
  }

  /// Authenticates user credentials offline.
  Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    final cleanUsername = username.trim();
    if (cleanUsername.isEmpty || password.isEmpty) {
      return AuthResult.failure('Invalid username or password.');
    }

    try {
      final db = await _dbHelper.database;
      final maps = await db.query(
        'app_users',
        where: 'LOWER(username) = ?',
        whereArgs: [cleanUsername.toLowerCase()],
      );

      if (maps.isEmpty) {
        await _auditService.logEvent(
          eventType: 'LOGIN_FAILED',
          actorUsername: cleanUsername,
          details: 'UNKNOWN_USER',
        );
        return AuthResult.failure('Invalid username or password.');
      }

      final user = AppUser.fromMap(maps.first);

      if (!user.isActive) {
        await _auditService.logEvent(
          eventType: 'LOGIN_FAILED',
          actorUsername: user.username,
          details: 'DISABLED_USER',
        );
        return AuthResult.failure('Invalid username or password.');
      }

      final isValidPassword = PasswordHasher.verifyPassword(password, user.passwordSalt, user.passwordHash);

      if (!isValidPassword) {
        await _auditService.logEvent(
          eventType: 'LOGIN_FAILED',
          actorUsername: user.username,
          details: 'INVALID_PASSWORD',
        );
        return AuthResult.failure('Invalid username or password.');
      }

      final now = DateTime.now();
      await db.update(
        'app_users',
        {'last_login_at': now.toIso8601String()},
        where: 'id = ?',
        whereArgs: [user.id],
      );

      final session = UserSession(
        userId: user.id,
        username: user.username,
        role: user.role,
        loginTimestamp: now,
      );

      _currentSession = session;

      await _auditService.logEvent(
        eventType: 'LOGIN_SUCCESS',
        actorUsername: user.username,
      );

      return AuthResult.ok(session);
    } catch (e) {
      debugPrint('[AuthService] Exception during login: $e');
      return AuthResult.failure('Invalid username or password.');
    }
  }

  /// Terminates the current active session.
  Future<void> logout() async {
    final session = _currentSession;
    if (session != null) {
      await _auditService.logEvent(
        eventType: 'LOGOUT',
        actorUsername: session.username,
      );
    }
    _currentSession = null;
  }

  // --- USER MANAGEMENT (ADMIN / RBAC) ---

  /// Retrieves the list of all local user accounts.
  Future<List<AppUser>> getAllUsers() async {
    try {
      final db = await _dbHelper.database;
      final maps = await db.query('app_users', orderBy: 'created_at ASC');
      return maps.map((map) => AppUser.fromMap(map)).toList();
    } catch (e) {
      debugPrint('[AuthService] Error retrieving user list: $e');
      return [];
    }
  }

  /// Counts the total number of active administrator accounts.
  Future<int> getActiveAdminCount() async {
    try {
      final db = await _dbHelper.database;
      final result = await db.rawQuery(
        "SELECT COUNT(*) as count FROM app_users WHERE role = 'ADMIN' AND is_active = 1;",
      );
      return (result.first['count'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('[AuthService] Error counting active admins: $e');
      return 0;
    }
  }

  /// Creates a new user account (Admin operation).
  Future<AuthResult> createUser({
    required String username,
    required String password,
    required String confirmPassword,
    required UserRole role,
  }) async {
    final cleanUsername = username.trim();
    if (cleanUsername.isEmpty) {
      return AuthResult.failure('Username is required.');
    }

    if (password.length < 8) {
      return AuthResult.failure('Password must be at least 8 characters long.');
    }

    final hasLetter = password.contains(RegExp(r'[a-zA-Z]'));
    final hasDigit = password.contains(RegExp(r'[0-9]'));
    if (!hasLetter || !hasDigit) {
      return AuthResult.failure('Password must contain both letters and numbers.');
    }

    if (password != confirmPassword) {
      return AuthResult.failure('Passwords do not match.');
    }

    try {
      final db = await _dbHelper.database;
      final existing = await db.query(
        'app_users',
        where: 'LOWER(username) = ?',
        whereArgs: [cleanUsername.toLowerCase()],
      );
      if (existing.isNotEmpty) {
        return AuthResult.failure('Username is already taken.');
      }

      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hashPassword(password, salt);
      final now = DateTime.now();

      final newUser = AppUser(
        id: 'user_${now.microsecondsSinceEpoch}',
        username: cleanUsername,
        passwordHash: hash,
        passwordSalt: salt,
        role: role,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      await db.insert('app_users', newUser.toMap());

      await _auditService.logEvent(
        eventType: 'USER_CREATED',
        actorUsername: _currentSession?.username ?? 'SYSTEM',
        targetUsername: cleanUsername,
        details: 'Role: ${role.name.toUpperCase()}',
      );

      return AuthResult.ok(
        UserSession(
          userId: newUser.id,
          username: newUser.username,
          role: newUser.role,
          loginTimestamp: now,
        ),
      );
    } catch (e) {
      debugPrint('[AuthService] Exception creating user: $e');
      return AuthResult.failure('Failed to create user account.');
    }
  }

  /// Enables or disables a user account with Last Admin Protection guard.
  Future<AuthResult> setUserActive({
    required String userId,
    required bool isActive,
  }) async {
    try {
      final db = await _dbHelper.database;
      final maps = await db.query('app_users', where: 'id = ?', whereArgs: [userId]);
      if (maps.isEmpty) {
        return AuthResult.failure('User not found.');
      }

      final targetUser = AppUser.fromMap(maps.first);

      // MANDATORY LAST ADMIN PROTECTION
      if (targetUser.role == UserRole.admin && targetUser.isActive && !isActive) {
        final activeAdminCount = await getActiveAdminCount();
        if (activeAdminCount <= 1) {
          return AuthResult.failure('At least one active Administrator account must remain.');
        }
      }

      final now = DateTime.now();
      await db.update(
        'app_users',
        {
          'is_active': isActive ? 1 : 0,
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [userId],
      );

      await _auditService.logEvent(
        eventType: isActive ? 'USER_ENABLED' : 'USER_DISABLED',
        actorUsername: _currentSession?.username ?? 'SYSTEM',
        targetUsername: targetUser.username,
      );

      return AuthResult.ok(
        UserSession(
          userId: targetUser.id,
          username: targetUser.username,
          role: targetUser.role,
          loginTimestamp: now,
        ),
      );
    } catch (e) {
      debugPrint('[AuthService] Exception updating user active status: $e');
      return AuthResult.failure('Failed to update user account status.');
    }
  }

  /// Updates a user's role with Last Admin Protection guard.
  Future<AuthResult> updateUserRole({
    required String userId,
    required UserRole newRole,
  }) async {
    try {
      final db = await _dbHelper.database;
      final maps = await db.query('app_users', where: 'id = ?', whereArgs: [userId]);
      if (maps.isEmpty) {
        return AuthResult.failure('User not found.');
      }

      final targetUser = AppUser.fromMap(maps.first);

      // MANDATORY LAST ADMIN PROTECTION (demoting the last active Admin)
      if (targetUser.role == UserRole.admin && targetUser.isActive && newRole != UserRole.admin) {
        final activeAdminCount = await getActiveAdminCount();
        if (activeAdminCount <= 1) {
          return AuthResult.failure('At least one active Administrator account must remain.');
        }
      }

      final now = DateTime.now();
      await db.update(
        'app_users',
        {
          'role': newRole.toDbValue(),
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [userId],
      );

      await _auditService.logEvent(
        eventType: 'ROLE_CHANGED',
        actorUsername: _currentSession?.username ?? 'SYSTEM',
        targetUsername: targetUser.username,
        details: 'New Role: ${newRole.name.toUpperCase()}',
      );

      return AuthResult.ok(
        UserSession(
          userId: targetUser.id,
          username: targetUser.username,
          role: newRole,
          loginTimestamp: now,
        ),
      );
    } catch (e) {
      debugPrint('[AuthService] Exception updating user role: $e');
      return AuthResult.failure('Failed to update user role.');
    }
  }

  /// Changes a user's password.
  Future<AuthResult> changeUserPassword({
    required String userId,
    required String newPassword,
    required String confirmPassword,
  }) async {
    if (newPassword.length < 8) {
      return AuthResult.failure('Password must be at least 8 characters long.');
    }

    final hasLetter = newPassword.contains(RegExp(r'[a-zA-Z]'));
    final hasDigit = newPassword.contains(RegExp(r'[0-9]'));
    if (!hasLetter || !hasDigit) {
      return AuthResult.failure('Password must contain both letters and numbers.');
    }

    if (newPassword != confirmPassword) {
      return AuthResult.failure('Passwords do not match.');
    }

    try {
      final db = await _dbHelper.database;
      final maps = await db.query('app_users', where: 'id = ?', whereArgs: [userId]);
      if (maps.isEmpty) {
        return AuthResult.failure('User not found.');
      }

      final targetUser = AppUser.fromMap(maps.first);
      final newSalt = PasswordHasher.generateSalt();
      final newHash = PasswordHasher.hashPassword(newPassword, newSalt);
      final now = DateTime.now();

      await db.update(
        'app_users',
        {
          'password_hash': newHash,
          'password_salt': newSalt,
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [userId],
      );

      await _auditService.logEvent(
        eventType: 'PASSWORD_CHANGED',
        actorUsername: _currentSession?.username ?? 'SYSTEM',
        targetUsername: targetUser.username,
      );

      return AuthResult.ok(
        UserSession(
          userId: targetUser.id,
          username: targetUser.username,
          role: targetUser.role,
          loginTimestamp: now,
        ),
      );
    } catch (e) {
      debugPrint('[AuthService] Exception changing password: $e');
      return AuthResult.failure('Failed to change password.');
    }
  }
}
