import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

/// HTTP + WebSocket client for the Python bridge (`backend/run.ps1`).
class BackendClient {
  BackendClient({this.host = '127.0.0.1', this.port = 8765});

  final String host;
  final int port;
  final _http = http.Client();

  Uri _uri(String path) => Uri.http('$host:$port', path);

  Future<dynamic> _decode(Future<http.Response> request) async {
    final response = await request;
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<Map<String, dynamic>> health() async =>
      await _decode(_http.get(_uri('/health'))
          .timeout(const Duration(seconds: 3))) as Map<String, dynamic>;

  Future<Map<String, dynamic>> getState() async =>
      await _decode(_http.get(_uri('/state'))) as Map<String, dynamic>;

  Future<Map<String, dynamic>> patchState(Map<String, dynamic> changes) async =>
      await _decode(_http.patch(_uri('/state'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(changes))) as Map<String, dynamic>;

  Future<List<dynamic>> vehicles() async =>
      await _decode(_http.get(_uri('/vehicles'))) as List<dynamic>;

  Future<List<dynamic>> locations() async =>
      await _decode(_http.get(_uri('/locations'))) as List<dynamic>;

  Future<Map<String, dynamic>> ask(String text) async =>
      await _decode(_http.post(_uri('/ask'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'text': text}))) as Map<String, dynamic>;

  Future<Map<String, dynamic>> startListening() async =>
      await _decode(_http.post(_uri('/listen/start'))) as Map<String, dynamic>;

  Future<Map<String, dynamic>> stopListening() async =>
      await _decode(_http.post(_uri('/listen/stop'))) as Map<String, dynamic>;

  Future<void> stopSpeaking() => _http.post(_uri('/speak/stop'));

  /// Server-pushed events: busy/idle, progress, speaking, listening,
  /// stateChanged.
  Stream<Map<String, dynamic>> events() {
    final channel =
        WebSocketChannel.connect(Uri.parse('ws://$host:$port/events'));
    return channel.stream
        .map((raw) => jsonDecode(raw as String) as Map<String, dynamic>);
  }

  void close() => _http.close();
}
