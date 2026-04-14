import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/weather_data.dart';

/// Fetches weather data from Weather Underground PWS API.
class WeatherService {
  Timer? _timer;
  final Duration refreshInterval;
  final void Function(WeatherData data)? onData;

  WeatherService({
    this.refreshInterval = const Duration(minutes: 10),
    this.onData,
  });

  String get _apiKey => dotenv.env['WEATHER_API_KEY'] ?? '';
  String get _stationId => dotenv.env['WEATHER_STATION_ID'] ?? '';

  Future<WeatherData?> fetch() async {
    final key = _apiKey;
    final station = _stationId;
    if (key.isEmpty || station.isEmpty) {
      debugPrint('[weather] Missing API key or station ID (key=${key.length} chars, station=$station)');
      return null;
    }

    try {
      final url = Uri.parse(
        'https://api.weather.com/v2/pws/observations/current'
        '?stationId=$station&format=json&units=e&apiKey=$key',
      );
      debugPrint('[weather] Fetching $station...');
      final resp = await http.get(url);
      debugPrint('[weather] Status: ${resp.statusCode}');
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        final obs = json['observations'];
        if (obs is List && obs.isNotEmpty) {
          debugPrint('[weather] Got data: temp=${obs[0]['imperial']?['temp']}');
          return WeatherData.fromJson(obs[0] as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('[weather] Error: $e');
    }
    return null;
  }

  void start() {
    _fetchAndNotify();
    _timer = Timer.periodic(refreshInterval, (_) => _fetchAndNotify());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _fetchAndNotify() async {
    final data = await fetch();
    if (data != null) {
      onData?.call(data);
    }
  }
}
