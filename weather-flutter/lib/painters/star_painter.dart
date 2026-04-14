import 'dart:math';
import 'package:flutter/material.dart';

/// A single star with pulsing opacity.
class Star {
  /// Position as fraction of screen (0..1).
  final double xFrac;
  final double yFrac;

  /// Star diameter in logical pixels.
  final double size;

  /// Base opacity (0.12 .. 1.0).
  final double baseOpacity;

  /// Pulse animation duration in seconds (1.5 .. 6.5).
  final double pulseDuration;

  /// Random phase offset for the pulse (0 .. 7).
  final double phaseOffset;

  const Star({
    required this.xFrac,
    required this.yFrac,
    required this.size,
    required this.baseOpacity,
    required this.pulseDuration,
    required this.phaseOffset,
  });
}

/// A shooting star with gradient trail.
class ShootingStar {
  /// Position as fraction of screen.
  final double xFrac;
  final double yFrac;

  /// Angle in degrees from horizontal.
  final double angleDeg;

  /// Progress 0..1 over the 1.4s lifetime.
  double progress;

  /// Time in seconds when this star was spawned.
  final double spawnTime;

  ShootingStar({
    required this.xFrac,
    required this.yFrac,
    required this.angleDeg,
    this.progress = 0.0,
    required this.spawnTime,
  });
}

/// Paints 115 pulsing stars and shooting stars with gradient trails.
/// Port of buildStars() and shooting star logic from the Svelte source.
///
/// Stars: 115 total, color #d8eaff, pulsing between full opacity and 0.05.
/// Shooting stars: appear every 7-27s, 160px trail with gradient,
///   angle 20-75deg from horizontal, random left/right flip.
class StarPainter extends CustomPainter {
  /// Pre-built list of 115 stars.
  final List<Star> stars;

  /// Active shooting stars.
  final List<ShootingStar> shootingStars;

  /// Current elapsed time in seconds (drives pulse animation).
  final double elapsedSeconds;

  StarPainter({
    required this.stars,
    required this.shootingStars,
    required this.elapsedSeconds,
  });

  /// Build 115 stars with random properties matching the source.
  static List<Star> buildStars() {
    final rng = Random();
    final stars = <Star>[];
    for (int i = 0; i < 115; i++) {
      stars.add(Star(
        xFrac: rng.nextDouble(),
        yFrac: rng.nextDouble() * 0.72, // top:0..72vh
        size: 0.5 + rng.nextDouble() * 2.4,
        baseOpacity: 0.12 + rng.nextDouble() * 0.88,
        pulseDuration: 1.5 + rng.nextDouble() * 5.0,
        phaseOffset: rng.nextDouble() * 7.0,
      ));
    }
    return stars;
  }

  /// Create a new shooting star. Interval: 7-27s between stars.
  static ShootingStar spawnShootingStar(double currentTime) {
    final rng = Random();
    final baseAng = 20 + rng.nextDouble() * 55; // 20-75 deg
    final flip = rng.nextDouble() > 0.5 ? 1.0 : -1.0;
    return ShootingStar(
      xFrac: rng.nextDouble() * 0.80 + 0.05, // 5..85vw
      yFrac: rng.nextDouble() * 0.55 + 0.03, // 3..58vh
      angleDeg: flip * baseAng,
      spawnTime: currentTime,
    );
  }

  /// Get the next shooting star interval in seconds.
  static double nextShootingInterval() {
    return 7.0 + Random().nextDouble() * 20.0; // 7-27s
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintStars(canvas, size);
    _paintShootingStars(canvas, size);
  }

  void _paintStars(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    // Star color: #d8eaff
    const baseColor = Color(0xFFd8eaff);

    for (final star in stars) {
      // Pulse: keyframes go 0%,100% -> opacity:1, scale:1; 50% -> opacity:0.05, scale:0.2
      // Use sinusoidal interpolation
      final t = elapsedSeconds + star.phaseOffset;
      final phase = (t / star.pulseDuration) % 1.0;
      // Map phase to the keyframe: cos goes 1 -> -1 -> 1
      // At phase 0 & 1: full, at phase 0.5: minimum
      final pulse = (cos(phase * 2 * pi) + 1.0) / 2.0; // 1 at 0, 0 at 0.5, 1 at 1
      final opacity = (star.baseOpacity * (0.05 + 0.95 * pulse)).clamp(0.0, 1.0);
      final scale = 0.2 + 0.8 * pulse;

      paint.color = baseColor.withValues(alpha: opacity);
      final r = star.size * scale / 2.0;
      canvas.drawCircle(
        Offset(star.xFrac * size.width, star.yFrac * size.height),
        r,
        paint,
      );
    }
  }

  void _paintShootingStars(Canvas canvas, Size size) {
    for (final shoot in shootingStars) {
      final elapsed = elapsedSeconds - shoot.spawnTime;
      if (elapsed < 0 || elapsed > 1.4) continue;

      final progress = (elapsed / 1.4).clamp(0.0, 1.0);
      // Ease out: cubic
      final eased = 1.0 - pow(1.0 - progress, 3).toDouble();

      // Opacity: 0 at start, 1 at 15%, fade to 0 by end
      double opacity;
      if (progress < 0.15) {
        opacity = progress / 0.15;
      } else {
        opacity = 1.0 - ((progress - 0.15) / 0.85);
      }
      opacity = opacity.clamp(0.0, 1.0);

      final angleRad = shoot.angleDeg * pi / 180;
      final startX = shoot.xFrac * size.width;
      final startY = shoot.yFrac * size.height;

      // Trail length: 160px, scale grows from 0 to 1, translates by 35vw
      final trailLen = 160.0 * eased;
      final translateX = 0.35 * size.width * eased;

      final cosA = cos(angleRad);
      final sinA = sin(angleRad);

      // Start point (translated along the angle)
      final sx = startX + cosA * translateX;
      final sy = startY + sinA * translateX;

      // End point of the trail
      final ex = sx + cosA * trailLen;
      final ey = sy + sinA * trailLen;

      // Gradient trail: white at head, transparent at tail
      final trailPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            Color.fromRGBO(255, 255, 255, 0.0),
            Color.fromRGBO(255, 255, 255, 0.9 * opacity),
          ],
        ).createShader(Rect.fromPoints(Offset(sx, sy), Offset(ex, ey)))
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(sx, sy), Offset(ex, ey), trailPaint);
    }
  }

  @override
  bool shouldRepaint(StarPainter oldDelegate) {
    return elapsedSeconds != oldDelegate.elapsedSeconds ||
        shootingStars.length != oldDelegate.shootingStars.length;
  }
}
