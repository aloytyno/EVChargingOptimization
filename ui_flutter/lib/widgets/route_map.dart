import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api/models.dart';
import '../theme.dart';

/// Dark route map with a glowing route line and charging-stop markers.
class RouteMap extends StatefulWidget {
  const RouteMap({super.key, required this.plan, required this.start});

  final TripPlan? plan;

  /// The car's current location, used when the plan has no route geometry
  /// (offline routes only know the chargers).
  final LatLng? start;

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  final _controller = MapController();
  bool _ready = false;

  static const _finland = LatLng(62.6, 25.5);

  List<LatLng> get _routePoints {
    final p = widget.plan;
    if (p == null) return const [];
    if (p.routeLat.isNotEmpty) {
      return [
        for (var i = 0; i < p.routeLat.length && i < p.routeLon.length; i++)
          LatLng(p.routeLat[i], p.routeLon[i]),
      ];
    }
    // Offline plans: connect the start to the chargers in order.
    return [
      if (widget.start != null) widget.start!,
      for (final s in p.stops) LatLng(s.latitude, s.longitude),
    ];
  }

  @override
  void didUpdateWidget(RouteMap old) {
    super.didUpdateWidget(old);
    if (old.plan != widget.plan) _fit();
  }

  void _fit() {
    final points = [
      ..._routePoints,
      if (widget.start != null) widget.start!,
    ];
    if (!_ready || points.length < 2) return;
    _controller.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points),
      padding: const EdgeInsets.all(48),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final route = _routePoints;
    final stops = widget.plan?.stops ?? const <ChargingStop>[];
    return GlassCard(
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: widget.start ?? _finland,
            initialZoom: 5.2,
            backgroundColor: Palette.background,
            onMapReady: () {
              _ready = true;
              _fit();
            },
          ),
          children: [
            // Esri World Dark Gray Canvas: keyless, and the same dark style
            // as the MATLAB app's "streets-dark" basemap. A production app
            // needs an ArcGIS (or other tile provider) account.
            TileLayer(
              urlTemplate:
                  'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}',
              userAgentPackageName: 'com.evcharge.ev_assistant',
              maxNativeZoom: 16,
            ),
            TileLayer(
              urlTemplate:
                  'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
              userAgentPackageName: 'com.evcharge.ev_assistant',
              maxNativeZoom: 16,
            ),
            if (route.length >= 2)
              PolylineLayer(
                polylines: [
                  // Wide translucent stroke under a thin bright one = glow.
                  Polyline(
                    points: route,
                    strokeWidth: 12,
                    color: Palette.accent.withValues(alpha: 0.18),
                  ),
                  Polyline(
                    points: route,
                    strokeWidth: 3.5,
                    color: Palette.accent,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (widget.start != null)
                  Marker(
                    point: widget.start!,
                    width: 22,
                    height: 22,
                    child: const _Dot(color: Palette.accentAlt),
                  ),
                if (widget.plan != null && widget.plan!.routeLat.isNotEmpty)
                  Marker(
                    point: route.last,
                    width: 22,
                    height: 22,
                    child: const _Dot(color: Palette.warn),
                  ),
                for (final s in stops)
                  Marker(
                    point: LatLng(s.latitude, s.longitude),
                    width: 36,
                    height: 36,
                    child: Tooltip(
                      message:
                          '${s.name}\n${s.chargerKw.round()} kW · ${s.chargeMinutes.round()} min to ${s.leavePercent.round()}%',
                      child: const _ChargerPin(),
                    ),
                  ),
              ],
            ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('Esri, HERE, Garmin, OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [BoxShadow(color: color, blurRadius: 14)],
        ),
      );
}

class _ChargerPin extends StatelessWidget {
  const _ChargerPin();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Palette.background,
          border: Border.all(color: const Color(0xFFFFD84D), width: 2),
          boxShadow: const [
            BoxShadow(color: Color(0xAAFFD84D), blurRadius: 16),
          ],
        ),
        child: const Icon(Icons.bolt_rounded, color: Color(0xFFFFD84D), size: 20),
      );
}
