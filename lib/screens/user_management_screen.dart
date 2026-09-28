import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/permission_service.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<AppUser> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    if (!PermissionService.instance.canManageUsers()) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final users = await AuthService.instance.getAllUsers();

    if (mounted) {
      setState(() {
        _users = users;
        _isLoading = false;
      });
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade800 : const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openCreateUserDialog() async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    UserRole selectedRole = UserRole.operator;
    bool obscurePass = true;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.person_add_outlined, color: Color(0xFF0F172A)),
                  SizedBox(width: 10),
                  Text('Create New User', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Username', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        hintText: 'Enter username',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Password (min 8 chars, letters & numbers)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePass,
                      decoration: InputDecoration(
                        hintText: 'Enter password',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(obscurePass ? Icons.visibility_off : Icons.visibility, size: 18),
                          onPressed: () => setDialogState(() => obscurePass = !obscurePass),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Confirm Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: obscurePass,
                      decoration: const InputDecoration(
                        hintText: 'Re-enter password',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Assigned Role', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<UserRole>(
                      value: selectedRole,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      items: UserRole.values.map((role) {
                        return DropdownMenuItem(
                          value: role,
                          child: Text('${role.displayName} (${role.name.toUpperCase()})'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedRole = val);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final res = await AuthService.instance.createUser(
                      username: usernameController.text,
                      password: passwordController.text,
                      confirmPassword: confirmPasswordController.text,
                      role: selectedRole,
                    );
                    if (context.mounted) Navigator.pop(context);
                    if (res.success) {
                      _showSnackBar('User account created successfully.');
                      _loadUsers();
                    } else {
                      _showSnackBar(res.errorMessage, isError: true);
                    }
                  },
                  child: const Text('Create User'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toggleUserStatus(AppUser user) async {
    final newStatus = !user.isActive;
    final res = await AuthService.instance.setUserActive(
      userId: user.id,
      isActive: newStatus,
    );

    if (res.success) {
      _showSnackBar('User account ${newStatus ? 'enabled' : 'disabled'} successfully.');
      _loadUsers();
    } else {
      _showSnackBar(res.errorMessage, isError: true);
    }
  }

  Future<void> _openChangePasswordDialog(AppUser user) async {
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscurePass = true;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.key_outlined, color: Color(0xFF0F172A)),
                  const SizedBox(width: 10),
                  Text('Change Password: ${user.username}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('New Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePass,
                    decoration: InputDecoration(
                      hintText: 'Enter new password',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(obscurePass ? Icons.visibility_off : Icons.visibility, size: 18),
                        onPressed: () => setDialogState(() => obscurePass = !obscurePass),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Confirm New Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: obscurePass,
                    decoration: const InputDecoration(
                      hintText: 'Re-enter new password',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final res = await AuthService.instance.changeUserPassword(
                      userId: user.id,
                      newPassword: passwordController.text,
                      confirmPassword: confirmPasswordController.text,
                    );
                    if (context.mounted) Navigator.pop(context);
                    if (res.success) {
                      _showSnackBar('Password changed successfully for ${user.username}.');
                    } else {
                      _showSnackBar(res.errorMessage, isError: true);
                    }
                  },
                  child: const Text('Update Password'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openEditRoleDialog(AppUser user) async {
    UserRole selectedRole = user.role;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Change Role: ${user.username}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select New Role', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<UserRole>(
                    value: selectedRole,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    items: UserRole.values.map((role) {
                      return DropdownMenuItem(
                        value: role,
                        child: Text('${role.displayName} (${role.name.toUpperCase()})'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedRole = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final res = await AuthService.instance.updateUserRole(
                      userId: user.id,
                      newRole: selectedRole,
                    );
                    if (context.mounted) Navigator.pop(context);
                    if (res.success) {
                      _showSnackBar('User role updated to ${selectedRole.name.toUpperCase()}.');
                      _loadUsers();
                    } else {
                      _showSnackBar(res.errorMessage, isError: true);
                    }
                  },
                  child: const Text('Save Role'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!PermissionService.instance.canManageUsers()) {
      return Scaffold(
        appBar: AppBar(title: const Text('User Management')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.gpp_maybe_outlined, size: 64, color: Colors.red.shade700),
              const SizedBox(height: 16),
              const Text(
                'Access Denied',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 8),
              const Text(
                'Administrator privileges are required to access User Management.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('User Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadUsers,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Create User'),
        onPressed: _openCreateUserDialog,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F172A)))
          : RefreshIndicator(
              onRefresh: _loadUsers,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _users.length,
                itemBuilder: (context, index) {
                  final user = _users[index];
                  final isCurrentSessionUser = user.id == AuthService.instance.currentSession?.userId;

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: user.isActive ? const Color(0xFF0F172A) : Colors.grey.shade400,
                        foregroundColor: Colors.white,
                        child: Text(
                          user.username.isNotEmpty ? user.username[0].toUpperCase() : 'U',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(
                            user.username,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              decoration: user.isActive ? null : TextDecoration.lineThrough,
                              color: user.isActive ? const Color(0xFF0F172A) : Colors.grey,
                            ),
                          ),
                          if (isCurrentSessionUser) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('YOU', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: user.role == UserRole.admin
                                      ? Colors.purple.shade50
                                      : user.role == UserRole.operator
                                          ? Colors.blue.shade50
                                          : Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: user.role == UserRole.admin
                                        ? Colors.purple.shade200
                                        : user.role == UserRole.operator
                                            ? Colors.blue.shade200
                                            : Colors.amber.shade200,
                                  ),
                                ),
                                child: Text(
                                  user.role.displayName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: user.role == UserRole.admin
                                        ? Colors.purple.shade900
                                        : user.role == UserRole.operator
                                            ? Colors.blue.shade900
                                            : Colors.amber.shade900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                user.isActive ? Icons.check_circle_outline : Icons.block,
                                size: 14,
                                color: user.isActive ? Colors.green : Colors.red,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                user.isActive ? 'Active' : 'Disabled',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: user.isActive ? Colors.green.shade800 : Colors.red.shade800,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Created: ${user.createdAt.toIso8601String().split('T').first}'
                            '${user.lastLoginAt != null ? ' • Last Login: ${user.lastLoginAt!.toIso8601String().split('T').first}' : ''}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (val) {
                          if (val == 'toggle_status') {
                            _toggleUserStatus(user);
                          } else if (val == 'change_role') {
                            _openEditRoleDialog(user);
                          } else if (val == 'change_password') {
                            _openChangePasswordDialog(user);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'toggle_status',
                            child: Row(
                              children: [
                                Icon(user.isActive ? Icons.block : Icons.check_circle_outline, size: 18),
                                const SizedBox(width: 8),
                                Text(user.isActive ? 'Disable User' : 'Enable User'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'change_role',
                            child: Row(
                              children: [
                                Icon(Icons.manage_accounts_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Change Role'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'change_password',
                            child: Row(
                              children: [
                                Icon(Icons.key_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Reset Password'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
