import 'package:flutter/material.dart';
import '../services/security/app_security_service.dart';

class SecuritySettingsScreen extends StatefulWidget {
  final AppSecurityService? securityService;

  const SecuritySettingsScreen({
    super.key,
    this.securityService,
  });

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  late final AppSecurityService _securityService;
  bool _isSecurityEnabled = false;
  bool _isHardwareSupported = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _securityService = widget.securityService ?? AppSecurityService();
    _loadSecurityStatus();
  }

  Future<void> _loadSecurityStatus() async {
    setState(() => _isLoading = true);
    final isSupported = await _securityService.isHardwareSupported();
    final isEnabled = await _securityService.isSecurityEnabled();

    if (mounted) {
      setState(() {
        _isHardwareSupported = isSupported;
        _isSecurityEnabled = isEnabled;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleSecurity(bool value) async {
    if (value) {
      // Test authentication before enabling
      final result = await _securityService.authenticate(
        reason: 'Authenticate to enable local app security lock',
      );

      if (result == SecurityAuthResult.success || result == SecurityAuthResult.disabled) {
        await _securityService.setSecurityEnabled(true);
        if (mounted) {
          setState(() => _isSecurityEnabled = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Local app authentication enabled.'),
              backgroundColor: Color(0xFF059669),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Authentication failed. Security lock not enabled.'),
              backgroundColor: Color(0xFFDC2626),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } else {
      await _securityService.setSecurityEnabled(false);
      if (mounted) {
        setState(() => _isSecurityEnabled = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local app authentication disabled.'),
            backgroundColor: Color(0xFF64748B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text(
          'Security & Privacy Settings',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App Security Status Banner
                  Container(
                    padding: const EdgeInsets.all(16),
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
                            Icon(
                              _isSecurityEnabled ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
                              size: 22,
                              color: _isSecurityEnabled ? const Color(0xFF059669) : const Color(0xFFD97706),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _isSecurityEnabled ? 'Security Lock Active' : 'Security Lock Disabled',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isSecurityEnabled
                              ? 'Biometric/Device authentication is required upon app launch and resume.'
                              : 'Enable authentication to protect local helicopter division invoice data.',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Setting Controls
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text(
                            'App Launch Authentication',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                          ),
                          subtitle: Text(
                            _isHardwareSupported
                                ? 'Use Android biometric fingerprint/face or device passcode.'
                                : 'Hardware authentication unavailable on this environment.',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                          value: _isSecurityEnabled,
                          activeColor: const Color(0xFF0F172A),
                          onChanged: _isHardwareSupported ? _toggleSecurity : null,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Real Security Audit Protections Checklist
                  const Text(
                    'Active Privacy & Security Protections',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 10),

                  _buildProtectionItem('100% Offline Execution', 'Zero internet/network permissions requested in Android Manifest.', true),
                  _buildProtectionItem('Android FLAG_SECURE Active', 'Screenshots, screen recording, and task switcher thumbnails blocked.', true),
                  _buildProtectionItem('Android Auto-Backup Disabled', 'android:allowBackup="false" prevents raw database extraction.', true),
                  _buildProtectionItem('Authenticated Backup Encryption', 'JSON exports encrypted with user-defined password.', true),
                  _buildProtectionItem('Temporary File Cleanup', 'Processing cache auto-sanitized after workflow completion.', true),
                  _buildProtectionItem('Local App Authentication', 'Biometric / passcode protection upon startup & resume.', _isSecurityEnabled),
                ],
              ),
            ),
    );
  }

  Widget _buildProtectionItem(String title, String subtitle, bool isActive) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.check_circle_outline_rounded : Icons.radio_button_unchecked_rounded,
            size: 20,
            color: isActive ? const Color(0xFF059669) : const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isActive ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
