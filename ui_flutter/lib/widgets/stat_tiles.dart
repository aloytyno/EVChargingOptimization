import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';

/// Arrival battery gauge, trip time, number of stops and battery warming.
class StatTiles extends StatelessWidget {
  const StatTiles({super.key, required this.plan, required this.car});

  final TripPlan? plan;
  final CarState car;

  @override
  Widget build(BuildContext context) {
    final p = plan;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: _Tile(
              caption: 'Arrive with',
              child: _RingGauge(
                percent: p?.arrivalPercent,
                warn: p != null && !p.canReach,
              ),
            ),
          ),
          Expanded(
            child: _Tile(
              caption: 'Trip time',
              child: _BigValue(p?.tripTimeText ?? '—'),
            ),
          ),
          Expanded(
            child: _Tile(
              caption: 'Charging stops',
              child: _BigValue(p == null ? '—' : '${p.stops.length}'),
            ),
          ),
          Expanded(
            child: _Tile(
              caption: 'Battery warming',
              child: _WarmingBadge(
                on: car.preconditioningOn,
                target: car.preconditioningTarget,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.caption, required this.child});

  final String caption;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Caption(caption),
          const SizedBox(height: 10),
          SizedBox(height: 72, child: Center(child: child)),
        ],
      );
}

class _BigValue extends StatelessWidget {
  const _BigValue(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      );
}

class _WarmingBadge extends StatelessWidget {
  const _WarmingBadge({required this.on, required this.target});

  final bool on;
  final String target;

  @override
  Widget build(BuildContext context) {
    final color = on ? Palette.warn : Palette.muted;
    return Tooltip(
      message: on && target.isNotEmpty ? 'Warming for $target' : '',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: color.withValues(alpha: 0.6)),
          color: color.withValues(alpha: on ? 0.18 : 0.05),
          boxShadow: [
            if (on) BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 18),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department_rounded, size: 18, color: color),
            const SizedBox(width: 6),
            Text(on ? 'On' : 'Off',
                style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _RingGauge extends StatelessWidget {
  const _RingGauge({required this.percent, required this.warn});

  final double? percent;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final value = percent;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: (value ?? 0).clamp(0, 100) / 100),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, fraction, _) => SizedBox.square(
        dimension: 72,
        child: CustomPaint(
          painter: _RingPainter(
            fraction: fraction,
            color: warn ? Palette.warn : Palette.accent,
          ),
          child: Center(
            child: Text(
              value == null ? '—' : '${value.round()}%',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ring = rect.deflate(5);
    canvas.drawArc(
      ring,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Palette.glassBorder,
    );
    canvas.drawArc(
      ring,
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color;
}
