import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/auth/auth_service.dart';
import '../widgets/common_helicopter_background.dart';
import 'home_screen.dart';

export '../widgets/common_helicopter_background.dart' show HelicopterOutlineIcon, HelicopterBranding, BottomFeatureStrip;

/// LoginScreen: Uses the shared CommonHelicopterBackground for ALL users and roles
/// (Administrator, Reviewer, Operator, etc.).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text;
    final password = _passwordController.text;

    final result = await AuthService.instance.login(
      username: username,
      password: password,
    );

    if (!mounted) return;

    if (result.success) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = result.errorMessage;
      });
    }
  }

  void _showForgotPasswordNotice() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Please contact your Helicopter Division Administrator to reset credentials.',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Color(0xFF0F172A),
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _showQrCodeNotice() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'QR Code authorization is available for registered Helicopter Division mobile nodes.',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Color(0xFF0F172A),
        duration: Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Uses the ONE common full-screen background shared by ALL user roles
    return CommonHelicopterBackground(
      child: _buildLoginCard(context),
    );
  }

  /// Reusable Frosted Glass Login Panel
  Widget _buildLoginCard(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 1050;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: isWide ? 28 : 20, vertical: 22),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.32),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 32,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Helicopter Icon
                const Center(
                  child: HelicopterOutlineIcon(
                    size: 36,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),

                // "TaxInvoice AI"
                Center(
                  child: RichText(
                    text: const TextSpan(
                      children: [
                        TextSpan(
                          text: 'TaxInvoice ',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        TextSpan(
                          text: 'AI',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFE5A93C),
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 3),

                // "Invoice Processing & Verification"
                const Center(
                  child: Text(
                    'Invoice Processing & Verification',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Gold divider: "HELICOPTER DIVISION"
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 24, height: 1.2, color: const Color(0xFFE5A93C)),
                    const SizedBox(width: 8),
                    const Text(
                      'HELICOPTER DIVISION',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.0,
                        color: Color(0xFFE5A93C),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(width: 24, height: 1.2, color: const Color(0xFFE5A93C)),
                  ],
                ),
                const SizedBox(height: 18),

                // Welcome Back Header
                const Text(
                  'Welcome Back',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Sign in to access your invoice management system.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFFCBD5E1),
                  ),
                ),
                const SizedBox(height: 16),

                // Error Banner if present
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2).withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF991B1B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Username Field
                _buildInputField(
                  controller: _usernameController,
                  icon: Icons.person_outline_rounded,
                  label: 'Username',
                  hint: 'Enter your username',
                  obscureText: false,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),

                // Password Field
                _buildInputField(
                  controller: _passwordController,
                  icon: Icons.lock_outline_rounded,
                  label: 'Password',
                  hint: 'Enter your password',
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleLogin(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 19,
                      color: Colors.white70,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 10),

                // Remember Me + Forgot Password Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _rememberMe = !_rememberMe;
                          });
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: Checkbox(
                                  value: _rememberMe,
                                  onChanged: (val) {
                                    setState(() {
                                      _rememberMe = val ?? false;
                                    });
                                  },
                                  activeColor: const Color(0xFF2563EB),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    width: 1.4,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Flexible(
                                child: Text(
                                  'Remember me',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _showForgotPasswordNotice,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Forgot password?',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF60A5FA),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Primary Login Button
                SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF334155),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.login_rounded, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Login',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded, size: 18),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 12),

                // OR Divider
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'OR',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Secondary Button: Login with QR Code
                InkWell(
                  onTap: _showQrCodeNotice,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.qr_code_scanner_rounded,
                          size: 20,
                          color: Color(0xFF60A5FA),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text(
                                'Login with QR Code',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Scan with authorized device',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Security Information Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.50),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFE5A93C).withValues(alpha: 0.35),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFE5A93C).withValues(alpha: 0.20),
                        ),
                        child: const Icon(
                          Icons.shield_outlined,
                          color: Color(0xFFE5A93C),
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Secure Local Access',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'This system operates in a secured local environment for the Helicopter Division.',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFFCBD5E1),
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Card Footer
                Center(
                  child: Column(
                    children: [
                      Text(
                        'v1.0.0  |  Secure Invoice Processing • Helicopter Division',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'TaxInvoice AI © 2026',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Custom Frosted Translucent Input Field
  Widget _buildInputField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    required String hint,
    required bool obscureText,
    TextInputAction textInputAction = TextInputAction.next,
    void Function(String)? onSubmitted,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          obscureText: obscureText,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          decoration: InputDecoration(
            isDense: true,
            labelText: label,
            labelStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.40),
              fontSize: 12.5,
            ),
            prefixIcon: Icon(
              icon,
              size: 19,
              color: Colors.white70,
            ),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.10),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.28),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.28),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: Color(0xFFE5A93C),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Backwards-compatible HelicopterIcon for other screens
class HelicopterIcon extends StatelessWidget {
  final double size;
  final Color color;

  const HelicopterIcon({
    super.key,
    this.size = 28,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return HelicopterOutlineIcon(
      size: size,
      color: color,
    );
  }
}
