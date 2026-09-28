enum UserRole {
  admin,
  operator,
  reviewer;

  String toDbValue() {
    switch (this) {
      case UserRole.admin:
        return 'ADMIN';
      case UserRole.operator:
        return 'OPERATOR';
      case UserRole.reviewer:
        return 'REVIEWER';
    }
  }

  static UserRole fromDbValue(String value) {
    switch (value.toUpperCase()) {
      case 'ADMIN':
        return UserRole.admin;
      case 'OPERATOR':
        return UserRole.operator;
      case 'REVIEWER':
        return UserRole.reviewer;
      default:
        return UserRole.reviewer;
    }
  }

  String get displayName {
    switch (this) {
      case UserRole.admin:
        return 'Administrator';
      case UserRole.operator:
        return 'Operator';
      case UserRole.reviewer:
        return 'Reviewer';
    }
  }
}

class AppUser {
  final String id;
  final String username;
  final String passwordHash;
  final String passwordSalt;
  final UserRole role;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLoginAt;

  const AppUser({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.passwordSalt,
    required this.role,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.lastLoginAt,
  });

  AppUser copyWith({
    String? id,
    String? username,
    String? passwordHash,
    String? passwordSalt,
    UserRole? role,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastLoginAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      passwordSalt: passwordSalt ?? this.passwordSalt,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'password_hash': passwordHash,
      'password_salt': passwordSalt,
      'role': role.toDbValue(),
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_login_at': lastLoginAt?.toIso8601String(),
    };
  }

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] as String? ?? '',
      username: map['username'] as String? ?? '',
      passwordHash: map['password_hash'] as String? ?? '',
      passwordSalt: map['password_salt'] as String? ?? '',
      role: UserRole.fromDbValue(map['role'] as String? ?? 'REVIEWER'),
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
      lastLoginAt: map['last_login_at'] != null ? DateTime.tryParse(map['last_login_at'] as String) : null,
    );
  }

  @override
  String toString() {
    return 'AppUser(id: $id, username: $username, role: ${role.name}, isActive: $isActive)';
  }
}

class UserSession {
  final String userId;
  final String username;
  final UserRole role;
  final DateTime loginTimestamp;

  const UserSession({
    required this.userId,
    required this.username,
    required this.role,
    required this.loginTimestamp,
  });

  @override
  String toString() {
    return 'UserSession(username: $username, role: ${role.name}, loginTime: $loginTimestamp)';
  }
}
