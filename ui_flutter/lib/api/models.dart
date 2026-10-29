/// Typed views over the JSON returned by the EV assistant backend
/// (MATLAB `evcharge.api.request`, served by the Python bridge).
library;

double _num(Object? v, [double fallback = 0]) =>
    v is num ? v.toDouble() : fallback;

List<double> _nums(Object? v) =>
    v is List ? v.map((e) => _num(e)).toList() : const [];

class ChargingStop {
  ChargingStop.fromJson(Map<String, dynamic> j)
      : name = j['name']?.toString() ?? 'Charger',
        latitude = _num(j['latitude']),
        longitude = _num(j['longitude']),
        kmFromStart = _num(j['km_from_start']),
        driveMinutesToStop = _num(j['drive_minutes_to_stop']),
        chargerKw = _num(j['charger_kw']),
        arrivePercent = _num(j['arrive_percent']),
        leavePercent = _num(j['leave_percent']),
        chargeMinutes = _num(j['charge_minutes']);

  final String name;
  final double latitude;
  final double longitude;
  final double kmFromStart;
  final double driveMinutesToStop;
  final double chargerKw;
  final double arrivePercent;
  final double leavePercent;
  final double chargeMinutes;
}

class TripPlan {
  TripPlan.fromJson(Map<String, dynamic> j)
      : canReach = j['can_reach_destination'] == true,
        from = j['from']?.toString() ?? '',
        to = j['to']?.toString() ?? '',
        nextAction = j['next_action']?.toString() ?? '',
        tripTimeText = j['trip_time_text']?.toString() ?? '',
        distanceKm = _num(j['distance_km']),
        arrivalPercent = _num(j['arrival_battery_percent']),
        marginPercent = _num(j['margin_percent'], 10),
        destinationPercent = _num(j['destination_percent'], 10),
        stops = (j['stops'] is List ? j['stops'] as List : const [])
            .whereType<Map<String, dynamic>>()
            .map(ChargingStop.fromJson)
            .toList(),
        profileKm = _nums((j['soc_profile'] as Map?)?['distance_km']),
        profileSoc = _nums((j['soc_profile'] as Map?)?['soc_percent']),
        routeLat = _nums((j['route'] as Map?)?['latitude']),
        routeLon = _nums((j['route'] as Map?)?['longitude']);

  /// The backend sends `[]` when there is no plan yet.
  static TripPlan? maybe(Object? json) =>
      json is Map<String, dynamic> ? TripPlan.fromJson(json) : null;

  final bool canReach;
  final String from;
  final String to;
  final String nextAction;
  final String tripTimeText;
  final double distanceKm;
  final double arrivalPercent;
  final double marginPercent;
  final double destinationPercent;
  final List<ChargingStop> stops;
  final List<double> profileKm;
  final List<double> profileSoc;
  final List<double> routeLat;
  final List<double> routeLon;
}

class CarState {
  CarState.fromJson(Map<String, dynamic> j)
      : socPercent = _num(j['soc_percent'], 72),
        arrivalPercent = _num(j['arrival_percent'], 10),
        location = j['location']?.toString() ?? 'Helsinki',
        outsideTempC = j['outside_temp_c'] is num
            ? (j['outside_temp_c'] as num).toDouble()
            : null,
        batteryTempC = _num(j['battery_temp_c'], 12),
        vehicleId = j['vehicle_id']?.toString() ?? '',
        vehicleName = j['vehicle_name']?.toString() ?? '',
        preconditioningOn = j['preconditioning_on'] == true,
        preconditioningTarget = j['preconditioning_target']?.toString() ?? '';

  const CarState.initial()
      : socPercent = 72,
        arrivalPercent = 10,
        location = 'Helsinki',
        outsideTempC = null,
        batteryTempC = 12,
        vehicleId = '',
        vehicleName = '',
        preconditioningOn = false,
        preconditioningTarget = '';

  final double socPercent;
  final double arrivalPercent;
  final String location;

  /// FMI forecast; null when unavailable.
  final double? outsideTempC;
  final double batteryTempC;
  final String vehicleId;
  final String vehicleName;
  final bool preconditioningOn;
  final String preconditioningTarget;
}

class Place {
  Place.fromJson(Map<String, dynamic> j)
      : name = j['name']?.toString() ?? '',
        latitude = _num(j['latitude']),
        longitude = _num(j['longitude']);

  final String name;
  final double latitude;
  final double longitude;
}

class Vehicle {
  Vehicle.fromJson(Map<String, dynamic> j)
      : id = j['id']?.toString() ?? '',
        name = j['name']?.toString() ?? '';

  final String id;
  final String name;
}

enum Speaker { driver, assistant }

class ChatMessage {
  const ChatMessage(this.speaker, this.text);

  final Speaker speaker;
  final String text;
}
