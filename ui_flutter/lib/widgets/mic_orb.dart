import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme.dart';

/// Large animated push-to-talk button whose motion shows what the
/// assistant is doing.
class MicOrb extends StatefulWidget {
  const MicOrb({super.key, required this.mode, required this.onTap});

  final AssistantMode mode;
  final VoidCallback? onTap;

  @override
  State<MicOrb> createState() => _MicOrbState();
}

class _MicOrbState extends State<MicOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.mode) {
      AssistantMode.listening => Palette.listen,
      AssistantMode.speaking => Palette.accentAlt,
      AssistantMode.starting => Palette.muted,
      _ => Palette.accent,
    };
    final icon = switch (widget.mode) {
      AssistantMode.listening => Icons.stop_rounded,
      AssistantMode.thinking => Icons.auto_awesome,
      AssistantMode.speaking => Icons.graphic_eq_rounded,
      AssistantMode.starting => Icons.hourglass_top_rounded,
      AssistantMode.idle => Icons.mic_rounded,
    };
    return Semantics(
      button: true,
      label: widget.mode == AssistantMode.listening
          ? 'Stop listening'
          : 'Talk to the assistant',
      child: GestureDetector(
        onTap: widget.onTap,
        child: MouseRegion(
          cursor: widget.onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: SizedBox.square(
            dimension: 190,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => CustomPaint(
                painter: _OrbPainter(
                  t: _controller.value,
                  mode: widget.mode,
                  color: color,
                ),
                child: child,
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Icon(icon,
                      key: ValueKey(icon), size: 54, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.t, required this.mode, required this.color});

  final double t;
  final AssistantMode mode;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width * 0.30;
    final phase = t * 2 * math.pi;

    // Soft breathing glow behind the core.
    final breathe = 1 + 0.06 * math.sin(phase * (mode == AssistantMode.idle ? 1 : 2));
    canvas.drawCircle(
      center,
      radius * 1.25 * breathe,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
    );

    switch (mode) {
      case AssistantMode.listening:
        // Rings expanding outwards, like sound coming in.
        for (var i = 0; i < 3; i++) {
          final p = (t * 1.5 + i / 3) % 1.0;
          canvas.drawCircle(
            center,
            radius * (1.0 + 0.6 * p),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = color.withValues(alpha: (1 - p) * 0.8),
          );
        }
      case AssistantMode.thinking:
        // Rotating comet arc.
        final rect = Rect.fromCircle(center: center, radius: radius * 1.28);
        canvas.drawArc(
          rect,
          phase * 2,
          math.pi * 0.9,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round
            ..shader = SweepGradient(
              colors: [color.withValues(alpha: 0), color],
              transform: GradientRotation(phase * 2),
            ).createShader(rect),
        );
      case AssistantMode.speaking:
        // Wavy ring, like a voice waveform wrapped around the orb.
        final path = Path();
        for (var a = 0; a <= 360; a += 4) {
          final rad = a * math.pi / 180;
          final r = radius * 1.22 +
              6 * math.sin(rad * 6 + phase * 4) * math.sin(phase * 2 + rad);
          final point = center + Offset(math.cos(rad), math.sin(rad)) * r;
          a == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(
          path..close(),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = color.withValues(alpha: 0.9),
        );
      case AssistantMode.idle:
      case AssistantMode.starting:
        canvas.drawCircle(
          center,
          radius * 1.22,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color.withValues(alpha: 0.5),
        );
    }

    // Glossy core.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [
            Color.lerp(color, Colors.white, 0.45)!,
            color,
            Color.lerp(color, Colors.black, 0.45)!,
          ],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.t != t || old.mode != mode || old.color != color;
}
