import 'package:flutter/material.dart';

/// ONE COMMON FULL-SCREEN HELICOPTER DIVISION BACKGROUND
/// Shared by all users and all roles (Administrator, Reviewer, Operator, First-Run Setup).
class CommonHelicopterBackground extends StatelessWidget {
  final Widget child;

  const CommonHelicopterBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. One Common Full-Screen Photographic Background (100% width & height, no margins)
          Positioned.fill(
            child: Image.asset(
              'assets/images/helicopter_division_sunset.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              width: double.infinity,
              height: double.infinity,
            ),
          ),

          // 2. Subtle Cinematic Atmospheric Vignette (preserves sunset warmth & contrast)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF070B14).withValues(alpha: 0.28),
                    Colors.transparent,
                    const Color(0xFF070B14).withValues(alpha: 0.35),
                  ],
                ),
              ),
            ),
          ),

          // 3. Responsive Content Layer
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 1050 && constraints.maxHeight >= 640;

                if (isWide) {
                  return _buildDesktopLayout(child);
                } else {
                  return _buildCompactLayout(child);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Widescreen / Desktop Layout matching reference Image 2:
  /// Left side: Upper branding centered over helicopter + Lower 4-feature strip sitting directly on hangar floor.
  /// Right side: Frosted glass login card.
  Widget _buildDesktopLayout(Widget loginCard) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 36),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: const [
                SizedBox(height: 18),
                HelicopterBranding(isCenter: true),
                Spacer(),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: BottomFeatureStrip(),
                ),
                SizedBox(height: 8),
              ],
            ),
          ),

          const SizedBox(width: 44),

          // Right Column: Centered Reusable Login Card
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 440,
                maxHeight: 740,
              ),
              child: loginCard,
            ),
          ),
        ],
      ),
    );
  }

  /// Compact / Mobile Layout:
  /// Single scrollable view with scaled branding, card, and bottom features.
  Widget _buildCompactLayout(Widget loginCard) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              const Center(child: HelicopterBranding(isCenter: true)),
              const SizedBox(height: 24),
              loginCard,
              const SizedBox(height: 28),
              const BottomFeatureStrip(isCompact: true),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Upper Left Branding Component
class HelicopterBranding extends StatelessWidget {
  final bool isCenter;

  const HelicopterBranding({
    super.key,
    this.isCenter = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: isCenter ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // White Helicopter Outline Icon
        const HelicopterOutlineIcon(
          size: 52,
          color: Colors.white,
        ),
        const SizedBox(height: 14),

        // "TaxInvoice AI"
        RichText(
          textAlign: isCenter ? TextAlign.center : TextAlign.left,
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'TaxInvoice ',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                  shadows: [
                    Shadow(offset: Offset(0, 2), blurRadius: 10, color: Colors.black87),
                  ],
                ),
              ),
              TextSpan(
                text: 'AI',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFE5A93C),
                  letterSpacing: -0.5,
                  shadows: [
                    Shadow(offset: Offset(0, 2), blurRadius: 10, color: Colors.black87),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // Subtitle
        const Text(
          'Invoice Processing & Verification',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Color(0xFFF1F5F9),
            letterSpacing: 0.3,
            shadows: [
              Shadow(offset: Offset(0, 1), blurRadius: 8, color: Colors.black87),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Gold Decorative Line with "HELICOPTER DIVISION"
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 44, height: 1.5, color: const Color(0xFFE5A93C)),
              const SizedBox(width: 10),
              const Text(
                'HELICOPTER DIVISION',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3.0,
                  color: Color(0xFFE5A93C),
                  shadows: [
                    Shadow(offset: Offset(0, 1), blurRadius: 8, color: Colors.black87),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(width: 44, height: 1.5, color: const Color(0xFFE5A93C)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Four Bottom Feature Items Strip (Shared by all login views)
class BottomFeatureStrip extends StatelessWidget {
  final bool isCompact;

  const BottomFeatureStrip({
    super.key,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildItem(
                  icon: Icons.description_outlined,
                  line1: 'Automated',
                  line2: 'Invoice Processing',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildItem(
                  icon: Icons.shield_outlined,
                  line1: 'Secure & Offline',
                  line2: 'Data Handling',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildItem(
                  icon: Icons.groups_outlined,
                  line1: 'Role-Based',
                  line2: 'Access Control',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildItem(
                  icon: Icons.bar_chart_rounded,
                  line1: 'Comprehensive',
                  line2: 'Reports & Analytics',
                ),
              ),
            ],
          ),
        ],
      );
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildItem(
            icon: Icons.description_outlined,
            line1: 'Automated',
            line2: 'Invoice Processing',
          ),
          _buildSeparator(),
          _buildItem(
            icon: Icons.shield_outlined,
            line1: 'Secure & Offline',
            line2: 'Data Handling',
          ),
          _buildSeparator(),
          _buildItem(
            icon: Icons.groups_outlined,
            line1: 'Role-Based',
            line2: 'Access Control',
          ),
          _buildSeparator(),
          _buildItem(
            icon: Icons.bar_chart_rounded,
            line1: 'Comprehensive',
            line2: 'Reports & Analytics',
          ),
        ],
      ),
    );
  }

  Widget _buildSeparator() {
    return Container(
      height: 38,
      width: 1,
      color: Colors.white.withValues(alpha: 0.22),
      margin: const EdgeInsets.symmetric(horizontal: 22),
    );
  }

  Widget _buildItem({
    required IconData icon,
    required String line1,
    required String line2,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFE5A93C).withValues(alpha: 0.80),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: const Color(0xFFE5A93C),
            size: 22,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          line1,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
            shadows: [
              Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black87),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          line2,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFCBD5E1),
            fontSize: 11,
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black87),
            ],
          ),
        ),
      ],
    );
  }
}

/// Outline Helicopter Icon matching reference Image 2
class HelicopterOutlineIcon extends StatelessWidget {
  final double size;
  final Color color;

  const HelicopterOutlineIcon({
    super.key,
    this.size = 36,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.5,
      height: size,
      child: CustomPaint(
        painter: _HelicopterOutlinePainter(color: color),
      ),
    );
  }
}

class _HelicopterOutlinePainter extends CustomPainter {
  final Color color;

  _HelicopterOutlinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / 32.0;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final thinStroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * scale
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // 1. Top Main Rotor Blade (Wide Horizontal Line)
    canvas.drawLine(
      Offset(4 * scale, 5 * scale),
      Offset(44 * scale, 5 * scale),
      strokePaint,
    );

    // Main Rotor Hub / Mast
    canvas.drawLine(
      Offset(24 * scale, 5 * scale),
      Offset(24 * scale, 9 * scale),
      strokePaint,
    );

    // 2. Helicopter Fuselage (Outline)
    final fuselage = Path();
    fuselage.moveTo(21 * scale, 9 * scale);
    fuselage.lineTo(29 * scale, 9 * scale);
    fuselage.cubicTo(
      36 * scale, 10 * scale,
      38 * scale, 15 * scale,
      35 * scale, 19 * scale,
    );
    fuselage.quadraticBezierTo(
      29 * scale, 21 * scale,
      19 * scale, 20 * scale,
    );
    fuselage.lineTo(6 * scale, 15 * scale); // Tail boom
    fuselage.lineTo(6 * scale, 13 * scale);
    fuselage.lineTo(21 * scale, 9 * scale);
    fuselage.close();

    canvas.drawPath(fuselage, strokePaint);

    // 3. Cockpit Windshield (Outline)
    final cockpit = Path();
    cockpit.moveTo(26 * scale, 11 * scale);
    cockpit.lineTo(32 * scale, 11.5 * scale);
    cockpit.cubicTo(
      34.5 * scale, 13 * scale,
      34 * scale, 16 * scale,
      31 * scale, 17 * scale,
    );
    cockpit.lineTo(26 * scale, 17 * scale);
    cockpit.close();

    canvas.drawPath(cockpit, thinStroke);

    // 4. Tail Fin & Tail Rotor
    canvas.drawLine(
      Offset(6 * scale, 9 * scale),
      Offset(6 * scale, 17 * scale),
      strokePaint,
    );
    canvas.drawLine(
      Offset(3.5 * scale, 8 * scale),
      Offset(8.5 * scale, 12 * scale),
      thinStroke,
    );

    // 5. Landing Skids (Struts and Skid)
    canvas.drawLine(
      Offset(29 * scale, 20 * scale),
      Offset(28 * scale, 25 * scale),
      strokePaint,
    );
    canvas.drawLine(
      Offset(21 * scale, 20 * scale),
      Offset(20 * scale, 25 * scale),
      strokePaint,
    );
    canvas.drawLine(
      Offset(12 * scale, 25 * scale),
      Offset(36 * scale, 25 * scale),
      strokePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
