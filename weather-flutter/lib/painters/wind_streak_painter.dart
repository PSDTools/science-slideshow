import 'dart:math';
import 'package:flutter/material.dart';

/// A single wind streak particle.
class WindStreak {
  /// Vertical position as fraction of screen (0..0.9).
  final double topFrac;

  /// Horizontal start position as fraction (-0.1..0.7).
  final double leftFrac;

  /// Length in pixels (60..260 depending on speed).
  final double length;

  /// Animation duration in seconds.
  final double duration;

  /// Angle in degrees (negative: slight downward-right, -8..-20).
  final double angleDeg;

  /// Base opacity (0.06..0.24).
  final double opacity;

  /// Random delay offset in seconds.
  final double delayOffset;

  const WindStreak({
    required this.topFrac,
    required this.leftFrac,
    required this.length,
    required this.duration,
    required this.angleDeg,
    required this.opacity,
    required this.delayOffset,
  });
}

/// Paints wind streaks as gradient opacity lines.
/// Port of buildWindStreaks() from the Svelte source.
///
/// Count = min(windSpeed / 2.5, 22), no streaks below 5 mph.
/// Each streak: 1px height, gradient (transparent -> rgba(200,225,255,0.75) -> transparent),
/// animates from -20vw to 110vw along its angle.
class WindStreakPainter extends CustomPainter {
  /// Pre-built list of wind streaks.
  final List<WindStreak> streaks;

  /// Current elapsed time in seconds.
  final double elapsedSeconds;

  WindStreakPainter({
    required this.streaks,
    required this.elapsedSeconds,
  });

  /// Build wind streaks based on wind speed.
  /// Returns empty list if windSpeed < 5.
  static List<WindStreak> buildStreaks(double windSpeed) {
    if (windSpeed < 5) return [];
    final rng = Random();
    final count = (windSpeed / 2.5).round().clamp(0, 22);
    final speedFactor = (windSpeed / 30).clamp(0.0, 1.0);
    final streaks = <WindStreak>[];

    for (int i = 0; i < count; i++) {
      final len = 60 + rng.nextDouble() * 120 + speedFactor * 80;
      final dur = 1.8 - speedFactor * 1.1 + rng.nextDouble() * 0.9;
      final ang = -(8 + rng.nextDouble() * 12);
      final op = 0.06 + rng.nextDouble() * 0.18 * speedFactor;
      streaks.add(WindStreak(
        topFrac: rng.nextDouble() * 0.9,
        leftFrac: -0.1 + rng.nextDouble() * 0.8,
        length: len,
        duration: dur,
        angleDeg: ang,
        opacity: op,
        delayOffset: rng.nextDouble() * dur,
      ));
    }
    return streaks;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final streak in streaks) {
      final t = elapsedSeconds + streak.delayOffset;
      // Animation: linear infinite, full cycle = duration
      final phase = (t % streak.duration) / streak.duration;

      // Opacity keyframes: 0%->0, 10%->1, 80%->0.9, 100%->0
      double animOpacity;
      if (phase < 0.10) {
        animOpacity = phase / 0.10;
      } else if (phase < 0.80) {
        animOpacity = 1.0 - 0.1 * ((phase - 0.10) / 0.70);
      } else {
        animOpacity = 0.9 * (1.0 - (phase - 0.80) / 0.20);
      }
      animOpacity = (animOpacity * streak.opacity).clamp(0.0, 1.0);
      if (animOpacity < 0.001) continue;

      // Position: translateX from -20vw to 110vw
      final translateX = (-0.2 + 1.3 * phase) * size.width;

      final angleRad = streak.angleDeg * pi / 180;
      final baseX = streak.leftFrac * size.width + translateX;
      final baseY = streak.topFrac * size.height;

      final cosA = cos(angleRad);
      final sinA = sin(angleRad);

      // Line start and end
      final startX = baseX;
      final startY = baseY;
      final endX = baseX + cosA * streak.length;
      final endY = baseY + sinA * streak.length;

      // Gradient: transparent -> rgba(200,225,255,0.75) at 40% -> transparent
      final paint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            Color.fromRGBO(200, 225, 255, 0.75 * animOpacity),
            Colors.transparent,
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(Rect.fromPoints(
          Offset(startX, startY),
          Offset(endX, endY),
        ))
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(startX, startY),
        Offset(endX, endY),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WindStreakPainter oldDelegate) {
    return elapsedSeconds != oldDelegate.elapsedSeconds ||
        streaks.length != oldDelegate.streaks.length;
  }
}
