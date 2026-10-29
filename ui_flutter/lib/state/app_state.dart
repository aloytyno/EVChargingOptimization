import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/backend_client.dart';
import '../api/models.dart';

enum AssistantMode { starting, idle, listening, thinking, speaking }

/// Everything the UI shows, fed by the backend's HTTP replies and events.
class AppState extends ChangeNotifier {
  AppState(this.client);

  final BackendClient client;

  final List<ChatMessage> messages = [];
  TripPlan? plan;
  CarState car = const CarState.initial();
  List<Vehicle> vehicles = [];
  List<Place> locations = [];

  bool backendReady = false;
  bool speechAvailable = false;
  bool listening = false;
  bool busy = false;
  bool speaking = false;
  String status = 'Connecting to the assistant...';
  String? problem;

  StreamSubscription<Map<String, dynamic>>? _events;
  bool _disposed = false;

  AssistantMode get mode {
    if (!backendReady) return AssistantMode.starting;
    if (listening) return AssistantMode.listening;
    if (busy) return AssistantMode.thinking;
    if (speaking) return AssistantMode.speaking;
    return AssistantMode.idle;
  }

  /// Waits for the backend (MATLAB can take a while to start), then loads
  /// the car, vehicles and locations and subscribes to events.
  Future<void> connect() async {
    while (!_disposed) {
      try {
        final h = await client.health();
        if (h['starting'] == true) {
          _setStatus('Starting MATLAB and loading models...');
        } else if (h['error'] != null) {
          problem = h['error'].toString();
          _setStatus('Backend failed to start');
          return;
        } else {
          speechAvailable = h['speech_ok'] == true;
          final messagesFromBackend =
              (h['messages'] as List? ?? const []).join(' ');
          if (h['model_ok'] != true) {
            problem = 'Language model unavailable. $messagesFromBackend';
          } else if (!speechAvailable) {
            problem = 'Speech unavailable, type instead. $messagesFromBackend';
          }
          break;
        }
      } catch (_) {
        _setStatus('Waiting for the backend at ${client.host}:${client.port}...');
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (_disposed) return;

    final results = await Future.wait([
      client.getState(),
      client.vehicles(),
      client.locations(),
    ]);
    car = CarState.fromJson(results[0] as Map<String, dynamic>);
    vehicles = (results[1] as List)
        .whereType<Map<String, dynamic>>()
        .map(Vehicle.fromJson)
        .toList();
    locations = (results[2] as List)
        .whereType<Map<String, dynamic>>()
        .map(Place.fromJson)
        .toList();
    _events = client.events().listen(_onEvent, onError: (_) {});
    backendReady = true;
    messages.add(const ChatMessage(
        Speaker.assistant, 'Hi! Where would you like to go?'));
    _setStatus('Ready');
  }

  void _onEvent(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'busy':
        busy = true;
      case 'idle':
        busy = false;
      case 'progress':
        status = e['text']?.toString() ?? status;
      case 'speaking':
        speaking = e['on'] == true;
      case 'listening':
        listening = e['on'] == true;
      case 'stateChanged':
        if (e['state'] is Map<String, dynamic>) {
          car = CarState.fromJson(e['state'] as Map<String, dynamic>);
        }
    }
    _notify();
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || busy) return;
    messages.add(ChatMessage(Speaker.driver, trimmed));
    busy = true;
    _setStatus('Thinking...');
    try {
      final r = await client.ask(trimmed);
      if (r['error'] != null) {
        messages.add(ChatMessage(Speaker.assistant, 'Sorry: ${r['error']}'));
      } else {
        messages.add(ChatMessage(
            Speaker.assistant, r['reply']?.toString() ?? '...'));
        plan = TripPlan.maybe(r['plan']) ?? plan;
        if (r['state'] is Map<String, dynamic>) {
          car = CarState.fromJson(r['state'] as Map<String, dynamic>);
        }
      }
      _setStatus(r['llm_error'] != null ? r['llm_error'].toString() : 'Ready');
    } catch (e) {
      messages.add(const ChatMessage(
          Speaker.assistant, "I can't reach the backend right now."));
      _setStatus('Backend error: $e');
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> toggleListening() async {
    if (!speechAvailable || busy) return;
    if (!listening) {
      final r = await client.startListening();
      if (r['error'] != null) {
        _setStatus(r['error'].toString());
        return;
      }
      listening = true;
      _setStatus('Listening... tap when done');
      return;
    }
    listening = false;
    _setStatus('Recognizing speech...');
    final r = await client.stopListening();
    final transcript = r['transcript']?.toString() ?? '';
    if (transcript.isEmpty) {
      _setStatus("I didn't catch that. Tap and try again.");
      return;
    }
    await send(transcript);
  }

  Future<void> updateCar(Map<String, dynamic> changes) async {
    final r = await client.patchState(changes);
    if (r['error'] != null) {
      _setStatus(r['error'].toString());
    } else {
      car = CarState.fromJson(r);
      _notify();
    }
  }

  Future<void> stopSpeaking() => client.stopSpeaking();

  Place? placeNamed(String name) {
    for (final p in locations) {
      if (p.name == name) return p;
    }
    return null;
  }

  void _setStatus(String text) {
    status = text;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    client.close();
    super.dispose();
  }
}
