import 'package:flutter/material.dart';
import 'sun_times.dart';
import '../models/weather_data.dart';
import '../models/weather_theme.dart';

/// Condition labels for each theme.
const Map<WeatherTheme, String> themeLabels = {
  WeatherTheme.rise: 'sunrise',
  WeatherTheme.day: 'clear',
  WeatherTheme.golden: 'golden hour',
  WeatherTheme.sunset: 'dusk',
  WeatherTheme.night: 'clear night',
  WeatherTheme.rain: 'rain',
  WeatherTheme.storm: 'thunderstorm',
  WeatherTheme.snow: 'snow',
};

/// Interpolated theme colors for cross-fade transitions.
class LerpableThemeColors {
  final Color bg0;
  final Color bg1;
  final Color text;
  final Color sub;
  final Color tempCol;
  final Color glowCol;
  final Color accent;

  const LerpableThemeColors({
    required this.bg0,
    required this.bg1,
    required this.text,
    required this.sub,
    required this.tempCol,
    required this.glowCol,
    required this.accent,
  });

  factory LerpableThemeColors.fromThemeColors(ThemeColors tc) {
    return LerpableThemeColors(
      bg0: tc.bg0,
      bg1: tc.bg1,
      text: tc.text,
      sub: tc.sub,
      tempCol: tc.tempCol,
      glowCol: tc.glowCol,
      accent: tc.accent,
    );
  }

  static LerpableThemeColors lerp(LerpableThemeColors a, LerpableThemeColors b, double t) {
    return LerpableThemeColors(
      bg0: Color.lerp(a.bg0, b.bg0, t)!,
      bg1: Color.lerp(a.bg1, b.bg1, t)!,
      text: Color.lerp(a.text, b.text, t)!,
      sub: Color.lerp(a.sub, b.sub, t)!,
      tempCol: Color.lerp(a.tempCol, b.tempCol, t)!,
      glowCol: Color.lerp(a.glowCol, b.glowCol, t)!,
      accent: Color.lerp(a.accent, b.accent, t)!,
    );
  }
}

/// All theme color palettes ported from the Svelte CSS variables.
/// This map provides quick access without the atmos/treeFill fields.
final Map<WeatherTheme, LerpableThemeColors> themeColorMap = {
  for (final entry in themeColors.entries)
    entry.key: LerpableThemeColors.fromThemeColors(entry.value),
};

/// Background gradients (the two stops for each theme at 165deg).
final Map<WeatherTheme, List<Color>> themeGradients = {
  for (final entry in bgGradients.entries)
    entry.key: [entry.value.$1, entry.value.$2],
};

/// Treeline fill colors for each theme.
final Map<WeatherTheme, Color> treelineFills = {
  for (final entry in themeColors.entries)
    entry.key: entry.value.treeFill,
};

class ThemeEngine {
  /// Infer the weather/condition theme (includes precipitation overrides).
  static WeatherTheme inferTheme(WeatherData? w, {double? timeOverride}) {
    final imp = w?.imperial ?? const ImperialData();
    final rate = imp.precipRate;
    final temp = imp.temp;
    final gust = imp.windGust;

    // Precipitation overrides everything
    if (rate != null && rate > 0) {
      if (temp != null && temp <= 33) return WeatherTheme.snow;
      if ((gust != null && gust > 20) || rate > 0.08) return WeatherTheme.storm;
      return WeatherTheme.rain;
    }

    return inferSkyTheme(w, timeOverride: timeOverride);
  }

  /// Infer the time-of-day sky theme (ignores precipitation).
  static WeatherTheme inferSkyTheme(WeatherData? w, {double? timeOverride}) {
    final now = DateTime.now();
    final h = timeOverride ?? (now.hour + now.minute / 60);
    final lat = w?.lat;
    final lon = w?.lon;

    if (lat != null && lon != null) {
      final sun = SunTimes.calculate(lat, lon);
      if (sun.sunrise != null && sun.sunset != null) {
        final sunrise = sun.sunrise!;
        final sunset = sun.sunset!;
        if (h >= sunrise - 0.33 && h < sunrise + 0.83) return WeatherTheme.rise;
        if (h >= sunrise + 0.83 && h < sunset - 1.5) return WeatherTheme.day;
        if (h >= sunset - 1.5 && h < sunset - 0.5) return WeatherTheme.golden;
        if (h >= sunset - 0.5 && h < sunset + 0.5) return WeatherTheme.sunset;
        return WeatherTheme.night;
      }
    }

    // Fallback: fixed thresholds
    if (h >= 5 && h < 7) return WeatherTheme.rise;
    if (h >= 7 && h < 17) return WeatherTheme.day;
    if (h >= 17 && h < 19) return WeatherTheme.golden;
    if (h >= 19 && h < 21) return WeatherTheme.sunset;
    return WeatherTheme.night;
  }

  /// Whether a theme represents active precipitation.
  static bool isPrecip(WeatherTheme theme) {
    return theme == WeatherTheme.rain ||
        theme == WeatherTheme.storm ||
        theme == WeatherTheme.snow;
  }
}
