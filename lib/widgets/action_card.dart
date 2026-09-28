import 'package:flutter/material.dart';

class ActionCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;

  const ActionCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.isPrimary = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.0),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 18.0),
          decoration: BoxDecoration(
            gradient: isPrimary
                ? const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isPrimary ? null : Colors.white,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(
              color: isPrimary ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: isPrimary
                    ? const Color(0xFF0F172A).withValues(alpha: 0.16)
                    : const Color(0xFF0F172A).withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: isPrimary
                      ? const Color(0xFF10B981).withValues(alpha: 0.18)
                      : const Color(0xFF0284C7).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14.0),
                ),
                child: Icon(
                  icon,
                  size: 26,
                  color: isPrimary ? const Color(0xFF34D399) : const Color(0xFF0284C7),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isPrimary ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isPrimary
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: isPrimary
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
