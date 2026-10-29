import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';

/// Battery level along the trip with charging stops and safety lines.
class SocChart extends StatelessWidget {
  const SocChart({super.key, required this.plan});

  final TripPlan? plan;

  @override
  Widget build(BuildContext context) {
    final p = plan;
    final text = Theme.of(context).textTheme;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Caption('Battery along the trip'),
          const SizedBox(height: 16),
          Expanded(
            child: p == null || p.profileKm.isEmpty
                ? Center(
                    child: Text('Your battery forecast appears here.',
                        style: text.bodyMedium?.copyWith(color: Palette.muted)),
                  )
                : LineChart(_data(p), duration: const Duration(milliseconds: 600)),
          ),
        ],
      ),
    );
  }

  LineChartData _data(TripPlan p) {
    final spots = [
      for (var i = 0; i < p.profileKm.length && i < p.profileSoc.length; i++)
        FlSpot(p.profileKm[i], p.profileSoc[i]),
    ];
    final labelStyle = const TextStyle(color: Palette.muted, fontSize: 11);
    return LineChartData(
      minY: 0,
      maxY: 100,
      minX: 0,
      maxX: p.profileKm.isEmpty ? 1 : p.profileKm.last,
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: 25,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: Palette.glassBorder, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 25,
            reservedSize: 40,
            getTitlesWidget: (v, _) => Text('${v.round()}%', style: labelStyle),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 26,
            interval: _niceInterval(p.profileKm.last),
            getTitlesWidget: (v, meta) {
              // fl_chart always labels the max; skip it when it would crowd
              // the last regular tick (e.g. "600 km" next to "610 km").
              final interval = _niceInterval(p.profileKm.last);
              final offGrid = (v % interval).abs() > 1e-6;
              if (v == meta.max && offGrid) return const SizedBox.shrink();
              return Text('${v.round()} km', style: labelStyle);
            },
          ),
        ),
      ),
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          HorizontalLine(
            y: p.marginPercent,
            color: Palette.warn.withValues(alpha: 0.7),
            strokeWidth: 1.5,
            dashArray: [6, 4],
          ),
        ],
        verticalLines: [
          for (final s in p.stops)
            VerticalLine(
              x: s.kmFromStart,
              color: Palette.accentAlt.withValues(alpha: 0.5),
              strokeWidth: 1,
              dashArray: [3, 3],
              label: VerticalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                style: const TextStyle(color: Palette.accentAlt, fontSize: 11),
                labelResolver: (_) => '⚡ ${s.chargeMinutes.round()} min',
              ),
            ),
        ],
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Palette.background.withValues(alpha: 0.9),
          getTooltipItems: (spots) => [
            for (final s in spots)
              LineTooltipItem('${s.y.round()}% at ${s.x.round()} km',
                  const TextStyle(color: Palette.text)),
          ],
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          barWidth: 3,
          color: Palette.accent,
          dotData: const FlDotData(show: false),
          shadow: const Shadow(color: Palette.accent, blurRadius: 10),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Palette.accent.withValues(alpha: 0.35),
                Palette.accent.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static double _niceInterval(double totalKm) {
    for (final step in [25.0, 50.0, 100.0, 200.0]) {
      if (totalKm / step <= 7) return step;
    }
    return 500;
  }
}
