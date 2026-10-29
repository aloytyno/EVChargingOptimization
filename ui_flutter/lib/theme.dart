import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colors of the futuristic dark theme.
class Palette {
  static const background = Color(0xFF05080B);
  static const backgroundGlow = Color(0xFF0B2A2E);
  static const glass = Color(0x1AFFFFFF);
  static const glassBorder = Color(0x26FFFFFF);
  static const text = Color(0xFFE6F1EE);
  static const muted = Color(0xFF8FA6A0);
  static const accent = Color(0xFF00E0C6);
  static const accentAlt = Color(0xFF2BB8FF);
  static const warn = Color(0xFFFFA43A);
  static const listen = Color(0xFFFF4D6D);
}

/// Builds the app theme. [googleFonts] is off in widget tests, which have no
/// network access to download fonts.
ThemeData buildTheme({bool googleFonts = true}) {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Palette.accent,
      brightness: Brightness.dark,
      surface: Palette.background,
    ),
    scaffoldBackgroundColor: Palette.background,
  );
  var textTheme = base.textTheme.apply(
    bodyColor: Palette.text,
    displayColor: Palette.text,
  );
  if (googleFonts) {
    // Apply fonts by family name: google_fonts' TextTheme helpers return the
    // standalone material_ui TextTheme, not Flutter's built-in one.
    final body = GoogleFonts.inter().fontFamily;
    final display = GoogleFonts.orbitron().fontFamily;
    textTheme = textTheme.apply(fontFamily: body).copyWith(
          displaySmall: textTheme.displaySmall?.copyWith(fontFamily: display),
          headlineMedium:
              textTheme.headlineMedium?.copyWith(fontFamily: display),
          titleLarge: textTheme.titleLarge?.copyWith(fontFamily: display),
          labelSmall: textTheme.labelSmall?.copyWith(fontFamily: display),
        );
  }
  return base.copyWith(
    textTheme: textTheme,
    sliderTheme: const SliderThemeData(
      activeTrackColor: Palette.accent,
      thumbColor: Palette.accent,
      inactiveTrackColor: Palette.glassBorder,
    ),
  );
}

/// Frosted-glass panel used for every card in the UI.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.glow,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Optional colored glow around the card, e.g. while listening.
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          if (glow != null)
            BoxShadow(color: glow!.withValues(alpha: 0.35), blurRadius: 32),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Palette.glass,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Palette.glassBorder),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.07),
                  Colors.white.withValues(alpha: 0.02),
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Small uppercase caption above a value.
class Caption extends StatelessWidget {
  const Caption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Palette.muted,
            letterSpacing: 2,
          ),
    );
  }
}
