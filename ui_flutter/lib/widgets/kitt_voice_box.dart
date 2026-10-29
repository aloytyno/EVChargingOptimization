import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../state/app_state.dart';

/// Push-to-talk button styled after KITT's voice modulator from Knight
/// Rider: three columns of red segments, the middle one taller, lighting up
/// symmetrically from the center as the assistant speaks.
///
/// The UI gets no audio levels from the backend, so speech is imitated
/// with a syllable-like envelope rather than the real waveform.
class KittVoiceBox extends StatefulWidget {
  const KittVoiceBox({super.key, required this.mode, required this.onTap});

  final AssistantMode mode;
  final VoidCallback? onTap;

  @override
  State<KittVoiceBox> createState() => _KittVoiceBoxState();
}

class _KittVoiceBoxState extends State<KittVoiceBox>
    with SingleTickerProviderStateMixin {
  /// Smoothed lit level (0..1) of the left, middle and right column.
  final _levels = ValueNotifier<List<double>>(const [0, 0, 0]);
  late final Ticker _ticker;
  double _lastSeconds = 0;

  /// VU-meter style smoothing: rise quickly, fall back more slowly.
  static const _attackSeconds = 0.035;
  static const _releaseSeconds = 0.14;

  @override
  void initState() {
    super.initState();
    // Start the animation clock here; a lazy field initializer would only
    // run when first read, leaving the panel frozen on one frame.
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final dt = (t - _lastSeconds).clamp(0.0, 0.1);
    _lastSeconds = t;
    final previous = _levels.value;
    _levels.value = [
      for (var c = 0; c < 3; c++)
        _smooth(previous[c], _targetLevel(widget.mode, c, t), dt),
    ];
  }

  static double _smooth(double current, double target, double dt) {
    final tau = target > current ? _attackSeconds : _releaseSeconds;
    final k = 1 - math.exp(-dt / tau);
    return current + (target - current) * k;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _levels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          child: SizedBox(
            width: 230,
            height: 190,
            child: CustomPaint(painter: _VoiceBoxPainter(levels: _levels)),
          ),
        ),
      ),
    );
  }

  /// Unsmoothed level (0..1) of column [c] at time [t] in [mode].
  static double _targetLevel(AssistantMode mode, int c, double t) {
    switch (mode) {
      case AssistantMode.speaking:
        // Outer columns echo the middle one a moment later, a bit smaller.
        final delay = c == 1 ? 0.0 : 0.05;
        final scale = c == 1 ? 1.0 : 0.9;
        return _voice(t - delay) * scale;
      case AssistantMode.listening:
        final flicker = 0.16 + 0.14 * _noise(t * 6 + c * 7.1);
        return c == 1 ? flicker + 0.08 : flicker;
      case AssistantMode.thinking:
        final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi / 1.4);
        return c == 1 ? 0.12 + 0.35 * pulse : 0.08 * pulse;
      case AssistantMode.starting:
        return c == 1 ? 0.1 + 0.1 * math.sin(t * 2) : 0;
      case AssistantMode.idle:
        return 0;
    }
  }

  /// Speech-like envelope: syllables of random loudness with occasional
  /// quiet ones between words. Each syllable rises and falls smoothly, so
  /// the envelope is continuous at syllable boundaries.
  static double _voice(double t) {
    const syllablesPerSecond = 5.0;
    // Overall amplitude; values above 1 let loud syllables light the
    // outermost segments (the level is capped at 1).
    const gain = 1.3;
    final x = t * syllablesPerSecond;
    final n = x.floor();
    final phase = x - n;
    final isPause = _hash(n * 3.7 + 1) < 0.18;
    final loudness = isPause ? 0.1 : 0.55 + 0.45 * _hash(n.toDouble());
    // The exponent < 1 broadens each syllable's peak.
    final shape = math.pow(math.sin(math.pi * phase), 0.6).toDouble();
    return math.min(1.0, gain * loudness * shape);
  }

  /// Smooth value noise in 0..1.
  static double _noise(double x) {
    final i = x.floor();
    final f = x - i;
    final a = _hash(i.toDouble());
    final b = _hash(i + 1.0);
    return a + (b - a) * (f * f * (3 - 2 * f));
  }

  static double _hash(double n) {
    final s = math.sin(n * 12.9898) * 43758.5453;
    return s - s.floorToDouble();
  }
}

class _VoiceBoxPainter extends CustomPainter {
  _VoiceBoxPainter({required this.levels}) : super(repaint: levels);

  final ValueNotifier<List<double>> levels;

  static const _lit = Color(0xFFFF2B14);
  static const _litCore = Color(0xFFFFB199);
  static const _unlit = Color(0xFF2A0804);

  /// Segments per column: outer columns are shorter than the middle one.
  static const _rows = [11, 17, 11];

  /// How much dimmer the outermost lit segments are than the middle ones.
  static const _edgeDimming = 0.65;

  @override
  void paint(Canvas canvas, Size size) {
    _paintPanel(canvas, size);

    final inner = Rect.fromLTWH(26, 18, size.width - 52, size.height - 36);
    final gap = inner.width * 0.09;
    final columnWidth = (inner.width - 2 * gap) / 3;
    final segmentPitch = inner.height / _rows[1];
    final segmentHeight = segmentPitch * 0.58;

    for (var c = 0; c < 3; c++) {
      final rows = _rows[c];
      final level = levels.value[c].clamp(0.0, 1.0);
      // Fade everything out smoothly as the column goes quiet.
      final presence = (level / 0.06).clamp(0.0, 1.0);
      final left = inner.left + c * (columnWidth + gap);
      final mid = (rows - 1) / 2;
      final rowStep = 1 / (mid + 0.5);
      for (var r = 0; r < rows; r++) {
        final top =
            inner.center.dy + (r - mid) * segmentPitch - segmentHeight / 2;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, columnWidth, segmentHeight),
          const Radius.circular(1.5),
        );
        // Segments light from the middle row outwards, up and down at once.
        // The outermost lit one fades in proportionally, so the column grows
        // smoothly instead of jumping a whole segment at a time.
        final distance = (r - mid).abs() / (mid + 0.5);
        final coverage =
            ((level - distance) / rowStep + 1).clamp(0.0, 1.0) * presence;
        canvas.drawRRect(rect, Paint()..color = _unlit);
        if (coverage <= 0.01) continue;

        // Dimmer toward the top and bottom ends (quadratic falloff).
        final brightness = 1 - _edgeDimming * distance * distance;
        final intensity = brightness * coverage;
        final lit = Color.lerp(_unlit, _lit, intensity)!;
        final core = Color.lerp(_unlit, _litCore, intensity)!;
        canvas.drawRRect(
          rect.inflate(2.5),
          Paint()
            ..color = _lit.withValues(alpha: 0.55 * intensity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawRRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [lit, core, lit],
              stops: const [0, 0.5, 1],
            ).createShader(rect.outerRect),
        );
      }
    }
  }

  void _paintPanel(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    // Brushed-metal bezel.
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5A5F63), Color(0xFF1E2124), Color(0xFF45494D)],
        ).createShader(outer.outerRect),
    );
    // Black face.
    final face = outer.deflate(5);
    canvas.drawRRect(face, Paint()..color = const Color(0xFF070707));
    canvas.drawRRect(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF000000),
    );
  }

  @override
  bool shouldRepaint(_VoiceBoxPainter old) => old.levels != levels;
}
