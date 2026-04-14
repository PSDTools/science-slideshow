import 'dart:math';

/// Compute today's sunrise and sunset as fractional local hours (e.g. 6.75 = 6:45 AM).
/// Uses the USNO/Almanac for Computers algorithm -- accurate to ~1 minute.
/// Returns null for each if the sun doesn't rise/set (polar extremes).
class SunTimes {
  final double? sunrise;
  final double? sunset;

  const SunTimes({this.sunrise, this.sunset});

  static SunTimes calculate(double lat, double lon) {
    const toRad = pi / 180;
    const toDeg = 180 / pi;
    final now = DateTime.now();
    final jan1 = DateTime(now.year, 1, 1);
    final n = now.difference(jan1).inDays + 1;
    final lngHour = lon / 15;
    final localOffsetHours = now.timeZoneOffset.inMinutes / 60;

    double? calc(bool isSunrise) {
      final t = n + ((isSunrise ? 6 : 18) - lngHour) / 24;
      final m = (0.9856 * t - 3.289 + 360) % 360;
      var l = (m +
              1.916 * sin(m * toRad) +
              0.020 * sin(2 * m * toRad) +
              282.634 +
              360) %
          360;
      var ra = (toDeg * atan(0.91764 * tan(l * toRad)) + 360) % 360;
      ra = (ra + ((l ~/ 90) * 90 - (ra ~/ 90) * 90)) / 15;
      final sinDec = 0.39782 * sin(l * toRad);
      final cosDec = cos(asin(sinDec));
      final cosH = (cos(90.833 * toRad) - sinDec * sin(lat * toRad)) /
          (cosDec * cos(lat * toRad));
      if (cosH > 1 || cosH < -1) return null;
      final h = isSunrise
          ? (360 - toDeg * acos(cosH)) / 15
          : (toDeg * acos(cosH)) / 15;
      final bigT = h + ra - 0.06571 * t - 6.622;
      return (((bigT - lngHour + localOffsetHours) % 24) + 24) % 24;
    }

    return SunTimes(sunrise: calc(true), sunset: calc(false));
  }
}
