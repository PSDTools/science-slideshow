import 'dart:math';
import '../models/arc_config.dart';
import '../services/moon_phase.dart';
import 'sun_times.dart';

/// Computed position and alpha for a celestial body (sun or moon).
class CelestialPosition {
  /// Screen position as percentage (0-100 vw/vh equivalent).
  final double xPercent;
  final double yPercent;

  /// Opacity (0 = hidden, 1 = fully visible).
  final double alpha;

  const CelestialPosition({
    required this.xPercent,
    required this.yPercent,
    required this.alpha,
  });

  static const hidden = CelestialPosition(xPercent: 50, yPercent: 120, alpha: 0);
}

class CelestialEngine {
  final ArcConfig arcConfig;

  CelestialEngine({this.arcConfig = const ArcConfig()});

  /// Map a 0-1 arc progress to screen position percentages.
  /// Screen faces NORTH: east = right, west = left, south = low-center.
  /// The sun/moon arc is a LOW arc: rises right, peaks center-low, sets left.
  ({double x, double y}) celestialScreenPos(double t) {
    final x = arcConfig.xRight -
        (arcConfig.xRight - arcConfig.xLeft) * t;
    final y = arcConfig.yHorizon -
        (arcConfig.yHorizon - arcConfig.yPeak) *
            pow(sin(pi * t), arcConfig.arcExp);
    return (x: x, y: y);
  }

  /// Compute sun and moon positions based on real time.
  ///
  /// Sun: rises right (east), sets left (west), arcs low (north-facing screen).
  /// Moon: same arc geometry, timed by lunar phase offset from sunrise.
  ({CelestialPosition sun, CelestialPosition moon, double moonPhase})
      positionCelestialBodies({
    required double lat,
    required double lon,
    required bool isPrecip,
    double? timeOverride,
  }) {
    final now = DateTime.now();
    final h = timeOverride ?? (now.hour + now.minute / 60.0);
    final sun = SunTimes.calculate(lat, lon);
    if (sun.sunrise == null || sun.sunset == null) {
      return (
        sun: CelestialPosition.hidden,
        moon: CelestialPosition.hidden,
        moonPhase: getMoonPhase(),
      );
    }

    final sunrise = sun.sunrise!;
    final sunset = sun.sunset!;

    // ── SUN ──
    final sunT = (h - sunrise) / (sunset - sunrise); // 0 at sunrise, 1 at sunset
    // Fade in/out over 4% of the day (~35 min) near each horizon
    const fade = 0.04;
    final sunAlpha = isPrecip
        ? 0.0
        : max(0.0, min(1.0, min(sunT / fade, (1 - sunT) / fade)));

    CelestialPosition sunPos;
    if (sunAlpha > 0) {
      final pos = celestialScreenPos(sunT.clamp(0.0, 1.0));
      sunPos = CelestialPosition(
        xPercent: pos.x,
        yPercent: pos.y,
        alpha: sunAlpha,
      );
    } else {
      sunPos = CelestialPosition.hidden;
    }

    // ── MOON ──
    CelestialPosition moonPos;
    if (isPrecip) {
      moonPos = CelestialPosition.hidden;
    } else {
      // Moon spans the deep night — it must be gone before the sun's glow appears
      // at either end of the day.
      //   moonrise = sunset + 0.5h  (after the sunset theme clears — full dark)
      //   moonset  = sunrise - 0.33h (before the rise glow begins)
      final moonrise = sunset + 0.5;
      final moonset = sunrise - 0.33;
      // Night duration between those two anchors (handles midnight wraparound)
      final moonDurHrs = (moonset - moonrise + 24) % 24;

      // Fractional arc position (handles midnight wraparound)
      double? moonT;
      if (moonrise < moonset) {
        if (h >= moonrise && h < moonset) {
          moonT = (h - moonrise) / moonDurHrs;
        }
      } else {
        if (h >= moonrise) {
          moonT = (h - moonrise) / moonDurHrs;
        } else if (h < moonset) {
          moonT = (h + 24 - moonrise) / moonDurHrs;
        }
      }

      final moonAlpha = moonT != null
          ? max(0.0, min(1.0, min(moonT / fade, (1 - moonT) / fade)))
          : 0.0;

      if (moonAlpha > 0 && moonT != null) {
        final pos = celestialScreenPos(moonT.clamp(0.0, 1.0));
        moonPos = CelestialPosition(
          xPercent: pos.x,
          yPercent: pos.y,
          alpha: moonAlpha,
        );
      } else {
        moonPos = CelestialPosition.hidden;
      }
    }

    return (
      sun: sunPos,
      moon: moonPos,
      moonPhase: getMoonPhase(),
    );
  }
}
