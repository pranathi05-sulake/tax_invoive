import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/auth/auth_service.dart';
import 'home_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Background Image (Helicopter Hangar / Airfield at sunset)
          Positioned.fill(
            child: Image.asset(
              'assets/images/login_background.png',
              fit: BoxFit.cover,
              alignment: Alignment.center, // Perfect balance for 9:16 clean portrait background
            ),
          ),

          // Light, non-intrusive Overlay (Preserves bright sunset and helicopter visibility)
          Positioned.fill(
            child: Container(
              color: const Color(0xFF0F172A).withValues(alpha: 0.12),
            ),
          ),

          // Main Login Content Container
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Error Banner if present
                      if (_errorMessage != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2).withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF991B1B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Translucent Frosted Glass Login Panel
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22), // Highly translucent frosted white
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.45), // Subtle light glass border
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Helicopter Icon Badge
                                Container(
                                  width: 56,
                                  height: 56,
                                  margin: const EdgeInsets.only(bottom: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF0F172A).withValues(alpha: 0.2),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: HelicopterIcon(
                                      size: 30,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),

                                // Header Titles
                                const Text(
                                  'HELICOPTER DIVISION',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2.2,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'TaxInvoice AI',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  width: 32,
                                  height: 2.5,
                                  margin: const EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2563EB),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const Text(
                                  'Secure Document Processing',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                                const SizedBox(height: 26),

                                // Username Label & Translucent Field
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: const Text(
                                    'Username',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _usernameController,
                                  textInputAction: TextInputAction.next,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F172A),
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Enter username',
                                    hintStyle: const TextStyle(
                                      color: Color(0xFF475569),
                                      fontSize: 14,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.person_outline_rounded,
                                      size: 20,
                                      color: Color(0xFF1E293B),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withValues(alpha: 0.50), // Translucent input background
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.60)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.60)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(color: Color(0xFF0F172A), width: 1.5),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),

                                // Password Label & Translucent Field
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: const Text(
                                    'Password',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _handleLogin(),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F172A),
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Enter password',
                                    hintStyle: const TextStyle(
                                      color: Color(0xFF475569),
                                      fontSize: 14,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                      size: 20,
                                      color: Color(0xFF1E293B),
                                    ),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 20,
                                        color: const Color(0xFF1E293B),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withValues(alpha: 0.50), // Translucent input background
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.60)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.60)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(color: Color(0xFF0F172A), width: 1.5),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Solid Navy SIGN IN Button
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _handleLogin,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0F172A),
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: const Color(0xFF475569),
                                      elevation: 2,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
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
                                              Text(
                                                'SIGN IN',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 1.0,
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              Icon(Icons.arrow_forward_rounded, size: 18),
                                            ],
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Subdued Footer Tagline
                      const Text(
                        'Helicopter Division Enterprise • Offline Secure Node',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              offset: Offset(0, 1),
                              blurRadius: 4.0,
                              color: Colors.black,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HelicopterPainter(color: color),
      ),
    );
  }
}

class _HelicopterPainter extends CustomPainter {
  final Color color;

  _HelicopterPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 32.0;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final thinStroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * scale
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // 1. Top Main Rotor Blade (Horizontal Line)
    canvas.drawLine(
      Offset(3 * scale, 5 * scale),
      Offset(29 * scale, 5 * scale),
      strokePaint,
    );

    // Main Rotor Mast
    canvas.drawLine(
      Offset(16 * scale, 5 * scale),
      Offset(16 * scale, 9 * scale),
      strokePaint,
    );

    // 2. Helicopter Body (Fuselage + Cockpit + Tail Boom)
    final bodyPath = Path();
    bodyPath.moveTo(14 * scale, 9 * scale);
    bodyPath.lineTo(19 * scale, 9 * scale);
    bodyPath.cubicTo(
      24 * scale, 10 * scale,
      25.5 * scale, 14 * scale,
      23 * scale, 17.5 * scale,
    );
    bodyPath.quadraticBezierTo(
      19 * scale, 19 * scale,
      12 * scale, 18.5 * scale,
    );
    bodyPath.lineTo(4 * scale, 14 * scale);
    bodyPath.lineTo(4 * scale, 12 * scale);
    bodyPath.lineTo(14 * scale, 9 * scale);
    bodyPath.close();

    canvas.drawPath(bodyPath, fillPaint);

    // 3. Tail Fin & Tail Rotor
    canvas.drawLine(
      Offset(4 * scale, 8 * scale),
      Offset(4 * scale, 15 * scale),
      strokePaint,
    );
    canvas.drawLine(
      Offset(2 * scale, 7.5 * scale),
      Offset(6 * scale, 10.5 * scale),
      thinStroke,
    );

    // 4. Cockpit Window Cutout (Negative Space)
    final windowPath = Path();
    windowPath.moveTo(17 * scale, 10.5 * scale);
    windowPath.lineTo(21 * scale, 11 * scale);
    windowPath.cubicTo(
      22.5 * scale, 12.5 * scale,
      22 * scale, 14.5 * scale,
      20.5 * scale, 15 * scale,
    );
    windowPath.lineTo(17 * scale, 15 * scale);
    windowPath.close();

    final windowPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawPath(windowPath, windowPaint);

    // 5. Landing Skids
    canvas.drawLine(
      Offset(19 * scale, 18.5 * scale),
      Offset(18 * scale, 23.5 * scale),
      strokePaint,
    );
    canvas.drawLine(
      Offset(13 * scale, 18.5 * scale),
      Offset(12 * scale, 23.5 * scale),
      strokePaint,
    );
    canvas.drawLine(
      Offset(7 * scale, 23.5 * scale),
      Offset(25 * scale, 23.5 * scale),
      strokePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}



