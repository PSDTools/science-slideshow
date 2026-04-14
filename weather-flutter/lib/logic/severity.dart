/// Severity levels for data strip color coding.
enum Severity { low, mid, high, extreme }

Severity humiditySeverity(double h) {
  if (h >= 90) return Severity.extreme;
  if (h >= 75) return Severity.high;
  if (h <= 30) return Severity.low;
  return Severity.mid;
}

Severity uvSeverity(double u) {
  if (u >= 8) return Severity.extreme;
  if (u >= 6) return Severity.high;
  if (u >= 3) return Severity.mid;
  return Severity.low;
}

Severity windSeverity(double s) {
  if (s >= 30) return Severity.extreme;
  if (s >= 20) return Severity.high;
  if (s >= 10) return Severity.mid;
  return Severity.low;
}

Severity tempSeverity(double t) {
  if (t >= 100) return Severity.extreme;
  if (t >= 86) return Severity.high;
  if (t <= 32) return Severity.low;
  return Severity.mid;
}

/// Convert compass degrees to direction label.
String windDirection(double deg) {
  const dirs = [
    'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
    'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
  ];
  return dirs[(deg / 22.5).round() % 16];
}
