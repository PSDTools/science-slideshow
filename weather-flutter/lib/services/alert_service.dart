import 'dart:convert';
import 'package:http/http.dart' as http;

/// Severity levels for NWS alerts.
enum AlertSeverity { extreme, severe, moderate, minor, unknown }

/// A simplified NWS weather alert.
class WeatherAlert {
  final String event;
  final String headline;
  final AlertSeverity severity;
  final int totalCount;

  const WeatherAlert({
    required this.event,
    required this.headline,
    required this.severity,
    this.totalCount = 1,
  });
}

class AlertService {
  static Future<WeatherAlert?> fetchAlerts(double lat, double lon) async {
    try {
      final url = Uri.parse(
        'https://api.weather.gov/alerts/active'
        '?point=${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}',
      );
      final resp = await http.get(url, headers: {
        'Accept': 'application/geo+json',
      });
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      final features = (data['features'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final active = features
          .where((f) => f['properties']?['status'] == 'Actual')
          .toList();

      if (active.isEmpty) return null;

      const ordMap = {
        'Extreme': 0,
        'Severe': 1,
        'Moderate': 2,
        'Minor': 3,
        'Unknown': 4,
      };
      active.sort((a, b) {
        final sa = ordMap[a['properties']?['severity'] ?? 'Unknown'] ?? 4;
        final sb = ordMap[b['properties']?['severity'] ?? 'Unknown'] ?? 4;
        return sa.compareTo(sb);
      });

      final p = active[0]['properties'] as Map<String, dynamic>;
      final sevStr = (p['severity'] ?? 'Unknown') as String;
      final severity = switch (sevStr.toLowerCase()) {
        'extreme' => AlertSeverity.extreme,
        'severe' => AlertSeverity.severe,
        'moderate' => AlertSeverity.moderate,
        'minor' => AlertSeverity.minor,
        _ => AlertSeverity.unknown,
      };

      // Strip prefix before dash/en-dash from headline
      var headline = (p['headline'] ?? '') as String;
      final dashIdx = headline.indexOf(RegExp(r'[\u2013\-]'));
      if (dashIdx >= 0 && dashIdx < headline.length - 2) {
        headline = headline.substring(dashIdx + 1).trim();
      }
      if (headline.length > 150) headline = headline.substring(0, 150);

      return WeatherAlert(
        event: p['event'] as String? ?? 'Weather Alert',
        headline: headline,
        severity: severity,
        totalCount: active.length,
      );
    } catch (_) {
      return null;
    }
  }
}
