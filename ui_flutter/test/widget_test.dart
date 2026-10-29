import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ev_assistant/api/models.dart';
import 'package:ev_assistant/state/app_state.dart';
import 'package:ev_assistant/theme.dart';
import 'package:ev_assistant/widgets/kitt_voice_box.dart';
import 'package:ev_assistant/widgets/next_card.dart';
import 'package:ev_assistant/widgets/stat_tiles.dart';

/// Shape of a plan as sent by MATLAB evcharge.api.planToStruct.
Map<String, dynamic> planJson({List<Map<String, dynamic>>? stops}) => {
      'can_reach_destination': true,
      'from': 'Helsinki, Finland',
      'to': 'Oulu, Finland',
      'next_action': 'Charge at Lahti HPC in 1 h 05 min\n20 min, up to 60%',
      'trip_time_text': '7 h 30 min',
      'distance_km': 610,
      'arrival_battery_percent': 12,
      'margin_percent': 10,
      'destination_percent': 10,
      'stops': stops ??
          [
            {
              'name': 'Lahti HPC',
              'latitude': 60.98,
              'longitude': 25.66,
              'km_from_start': 103,
              'drive_minutes_to_stop': 65,
              'charger_kw': 180,
              'arrive_percent': 18,
              'leave_percent': 60,
              'charge_minutes': 20,
            }
          ],
      'soc_profile': {
        'distance_km': [0, 103, 103, 610],
        'soc_percent': [72, 18, 60, 12],
      },
      'route': {'latitude': [], 'longitude': []},
    };

Widget host(Widget child) => MaterialApp(
      theme: buildTheme(googleFonts: false),
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(8), child: child)),
    );

void main() {
  test('plan parsing handles stops, profile and an empty plan', () {
    final plan = TripPlan.fromJson(planJson());
    expect(plan.stops.single.name, 'Lahti HPC');
    expect(plan.stops.single.chargerKw, 180);
    expect(plan.profileSoc, [72, 18, 60, 12]);
    expect(plan.routeLat, isEmpty);
    // The backend sends [] before any trip is planned.
    expect(TripPlan.maybe(<dynamic>[]), isNull);
  });

  test('car state treats a missing FMI temperature as unknown', () {
    final car = CarState.fromJson({
      'soc_percent': 55,
      'location': 'Oulu',
      'outside_temp_c': null,
      'vehicle_name': 'Kia EV6 Long Range 2WD',
    });
    expect(car.socPercent, 55);
    expect(car.outsideTempC, isNull);
  });

  testWidgets('Next card shows the prompt, then the next action', (tester) async {
    await tester.pumpWidget(host(const NextCard(plan: null, status: 'Ready')));
    expect(find.text('Where would you like to go?'), findsOneWidget);

    await tester.pumpWidget(
        host(NextCard(plan: TripPlan.fromJson(planJson()), status: 'Ready')));
    await tester.pumpAndSettle();
    expect(find.text('Charge at Lahti HPC in 1 h 05 min'), findsOneWidget);
    expect(find.text('20 min, up to 60%'), findsOneWidget);
    expect(find.text('Helsinki  →  Oulu'), findsOneWidget);
  });

  testWidgets('KITT voice box keeps animating', (tester) async {
    await tester.pumpWidget(host(
        KittVoiceBox(mode: AssistantMode.speaking, onTap: () {})));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    // A running animation clock keeps requesting frames; a frozen one
    // (ticker never started) does not.
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('stat tiles show dashes without a plan and values with one',
      (tester) async {
    const car = CarState.initial();
    await tester.pumpWidget(host(const StatTiles(plan: null, car: car)));
    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('Off'), findsOneWidget);

    await tester.pumpWidget(
        host(StatTiles(plan: TripPlan.fromJson(planJson()), car: car)));
    await tester.pumpAndSettle();
    expect(find.text('12%'), findsOneWidget);
    expect(find.text('7 h 30 min'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });
}
