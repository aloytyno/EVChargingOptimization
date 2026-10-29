import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';

/// Slide-out drawer standing in for the real car's signals.
class CarPanel extends StatefulWidget {
  const CarPanel({
    super.key,
    required this.car,
    required this.vehicles,
    required this.locations,
    required this.onChange,
  });

  final CarState car;
  final List<Vehicle> vehicles;
  final List<Place> locations;
  final Future<void> Function(Map<String, dynamic> changes) onChange;

  @override
  State<CarPanel> createState() => _CarPanelState();
}

class _CarPanelState extends State<CarPanel> {
  double? _dragSoc;

  @override
  Widget build(BuildContext context) {
    final car = widget.car;
    final text = Theme.of(context).textTheme;
    final soc = _dragSoc ?? car.socPercent;
    return Drawer(
      width: 380,
      backgroundColor: const Color(0xF20A1114),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          children: [
            Text('Simulated car', style: text.titleLarge),
            const SizedBox(height: 4),
            Text('Stands in for the signals a real car would send.',
                style: text.bodySmall?.copyWith(color: Palette.muted)),
            const SizedBox(height: 28),
            _Row(
              label: 'Battery',
              trailing: Text('${soc.round()} %',
                  style: text.titleMedium?.copyWith(color: Palette.accent)),
            ),
            Slider(
              value: soc.clamp(5, 100),
              min: 5,
              max: 100,
              divisions: 95,
              onChanged: (v) => setState(() => _dragSoc = v),
              onChangeEnd: (v) async {
                await widget.onChange({'soc_percent': v.roundToDouble()});
                if (mounted) setState(() => _dragSoc = null);
              },
            ),
            const SizedBox(height: 12),
            _Row(
              label: 'Arrive with',
              trailing: _Stepper(
                value: car.arrivalPercent,
                suffix: ' %',
                step: 5,
                min: 5,
                max: 80,
                onChanged: (v) => widget.onChange({'arrival_percent': v}),
              ),
            ),
            const SizedBox(height: 18),
            _Row(
              label: 'Location',
              trailing: _Dropdown(
                value: car.location,
                items: {for (final p in widget.locations) p.name: p.name},
                onChanged: (v) => widget.onChange({'location': v}),
              ),
            ),
            const SizedBox(height: 18),
            _Row(
              label: 'Outside',
              trailing: Text(
                car.outsideTempC == null
                    ? 'Unavailable'
                    : '${car.outsideTempC!.round()} °C  (FMI forecast)',
                style: text.bodyMedium,
              ),
            ),
            const SizedBox(height: 18),
            _Row(
              label: 'Battery temp',
              trailing: _Stepper(
                value: car.batteryTempC,
                suffix: ' °C',
                step: 1,
                min: -30,
                max: 45,
                onChanged: (v) => widget.onChange({'battery_temp_c': v}),
              ),
            ),
            const SizedBox(height: 18),
            _Row(
              label: 'Vehicle',
              trailing: _Dropdown(
                value: car.vehicleId,
                items: {for (final v in widget.vehicles) v.id: v.name},
                onChanged: (v) => widget.onChange({'vehicle_id': v}),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.trailing});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Palette.muted)),
          ),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: trailing),
          ),
        ],
      );
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.suffix,
    required this.step,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double value;
  final String suffix;
  final double step;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_rounded),
            onPressed: value - step < min ? null : () => onChanged(value - step),
          ),
          SizedBox(
            width: 64,
            child: Text('${value.round()}$suffix',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: value + step > max ? null : () => onChanged(value + step),
          ),
        ],
      );
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String value;

  /// Value -> label.
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButton<String>(
        value: items.containsKey(value) ? value : null,
        // Fill the row and truncate long names like "Kia EV6 Long Range 2WD".
        isExpanded: true,
        alignment: AlignmentDirectional.centerEnd,
        selectedItemBuilder: (context) => [
          for (final label in items.values)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
        ],
        underline: const SizedBox.shrink(),
        borderRadius: BorderRadius.circular(14),
        dropdownColor: const Color(0xFF101A1D),
        items: [
          for (final e in items.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null && v != value) onChanged(v);
        },
      );
}
