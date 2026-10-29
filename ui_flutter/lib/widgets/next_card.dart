import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';

/// The one thing the driver needs to know next, in big type.
class NextCard extends StatelessWidget {
  const NextCard({super.key, required this.plan, required this.status});

  final TripPlan? plan;
  final String status;

  @override
  Widget build(BuildContext context) {
    final p = plan;
    final lines = (p == null ? 'Where would you like to go?' : p.nextAction)
        .split('\n');
    final text = Theme.of(context).textTheme;
    final ok = p == null || p.canReach;
    return GlassCard(
      glow: p == null ? null : (ok ? Palette.accent : Palette.warn),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Caption('Next'),
              const Spacer(),
              if (p != null)
                Text('${_shortPlace(p.from)}  →  ${_shortPlace(p.to)}',
                    style: text.bodySmall?.copyWith(color: Palette.muted)),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.15), end: Offset.zero)
                    .animate(animation),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey(lines.join()),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lines.first,
                  style: text.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ok ? Palette.text : Palette.warn,
                  ),
                ),
                if (lines.length > 1) ...[
                  const SizedBox(height: 8),
                  Text(lines.skip(1).join(' '),
                      style: text.titleMedium?.copyWith(color: Palette.accent)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _shortPlace(String place) => place.split(',').first;
}
