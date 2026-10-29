import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'api/backend_client.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'widgets/car_panel.dart';
import 'widgets/chat_view.dart';
import 'widgets/kitt_voice_box.dart';
import 'widgets/next_card.dart';
import 'widgets/route_map.dart';
import 'widgets/soc_chart.dart';
import 'widgets/stat_tiles.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(BackendClient())..connect(),
      child: const EvAssistantApp(),
    ),
  );
}

class EvAssistantApp extends StatelessWidget {
  const EvAssistantApp({super.key, this.googleFonts = true});

  final bool googleFonts;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'EV Assistant',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(googleFonts: googleFonts),
        home: const HomeScreen(),
      );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final start = s.placeNamed(s.car.location);
    return Scaffold(
      drawer: CarPanel(
        car: s.car,
        vehicles: s.vehicles,
        locations: s.locations,
        onChange: s.updateCar,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.8, -0.9),
            radius: 1.6,
            colors: [Palette.backgroundGlow, Palette.background],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const _TopBar(),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(width: 380, child: _ConversationColumn()),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            NextCard(plan: s.plan, status: s.status),
                            const SizedBox(height: 16),
                            StatTiles(plan: s.plan, car: s.car),
                            const SizedBox(height: 16),
                            Expanded(child: SocChart(plan: s.plan)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 440,
                        child: RouteMap(
                          plan: s.plan,
                          start: start == null
                              ? null
                              : LatLng(start.latitude, start.longitude),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Builder(
          builder: (context) => IconButton.filledTonal(
            tooltip: 'Simulated car',
            icon: const Icon(Icons.directions_car_filled_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        const SizedBox(width: 14),
        Text('EV ASSIST',
            style: text.titleLarge?.copyWith(
              letterSpacing: 4,
              fontWeight: FontWeight.w700,
              shadows: const [Shadow(color: Palette.accent, blurRadius: 16)],
            )),
        const SizedBox(width: 24),
        if (s.car.vehicleName.isNotEmpty)
          _Chip(icon: Icons.ev_station_rounded, text: s.car.vehicleName),
        _Chip(
          icon: Icons.battery_charging_full_rounded,
          text: '${s.car.socPercent.round()} %',
        ),
        _Chip(icon: Icons.place_rounded, text: s.car.location),
        if (s.car.outsideTempC != null)
          _Chip(
            icon: Icons.thermostat_rounded,
            text: '${s.car.outsideTempC!.round()} °C',
          ),
        const Spacer(),
        if (s.problem != null)
          Flexible(
            child: Text(s.problem!,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: Palette.warn)),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Palette.glass,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Palette.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Palette.accent),
              const SizedBox(width: 6),
              Text(text, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
}

class _ConversationColumn extends StatefulWidget {
  const _ConversationColumn();

  @override
  State<_ConversationColumn> createState() => _ConversationColumnState();
}

class _ConversationColumnState extends State<_ConversationColumn> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send(AppState s) {
    s.send(_input.text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final canTalk = s.backendReady && s.speechAvailable && !s.busy;
    return GlassCard(
      glow: s.mode == AssistantMode.listening ? Palette.listen : null,
      child: Column(
        children: [
          const SizedBox(height: 4),
          KittVoiceBox(
            mode: s.mode,
            onTap: canTalk || s.listening ? s.toggleListening : null,
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              s.mode == AssistantMode.idle && s.speechAvailable
                  ? 'Tap and tell me where to go'
                  : s.status,
              key: ValueKey(s.status + s.mode.name),
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: Palette.muted),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(color: Palette.glassBorder, height: 1),
          Expanded(child: ChatView(messages: List.of(s.messages))),
          const SizedBox(height: 8),
          TextField(
            controller: _input,
            enabled: s.backendReady && !s.busy,
            onSubmitted: (_) => _send(s),
            decoration: InputDecoration(
              hintText: "Or type, e.g. 'Take me to Oulu'",
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.send_rounded, color: Palette.accent),
                onPressed: () => _send(s),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
