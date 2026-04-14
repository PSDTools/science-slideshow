import 'dart:math';
import 'package:flutter/material.dart';

/// A single snowflake particle.
class SnowFlake {
  double x;
  double y;
  double r;
  double spd;
  double drift;
  double op;
  double off;

  SnowFlake({
    required this.x,
    required this.y,
    required this.r,
    required this.spd,
    required this.drift,
    required this.op,
    required this.off,
  });
}

/// Paints 200 snowflakes with sinusoidal drift.
/// Port of initSnow() + drawSnow() from the Svelte source.
class SnowPainter extends CustomPainter {
  /// The list of snowflake particles (mutated each frame by the parent).
  final List<SnowFlake> flakes;

  /// Monotonically increasing time value, incremented 0.008 per frame.
  final double snowT;

  /// Current animation time (triggers repaints).
  final double animationTime;

  SnowPainter({
    required this.flakes,
    required this.snowT,
    required this.animationTime,
  });

  /// Initialize 200 snowflakes for the given canvas size.
  static List<SnowFlake> initFlakes(double width, double height) {
    final rng = Random();
    final flakes = <SnowFlake>[];
    for (int i = 0; i < 200; i++) {
      flakes.add(SnowFlake(
        x: rng.nextDouble() * width,
        y: rng.nextDouble() * height,
        r: 1.2 + rng.nextDouble() * 4.5,
        spd: 0.4 + rng.nextDouble() * 1.1,
        drift: (rng.nextDouble() - 0.5) * 0.5,
        op: 0.35 + rng.nextDouble() * 0.55,
        off: rng.nextDouble() * pi * 2,
      ));
    }
    return flakes;
  }

  /// Advance all flakes by one frame. Call from the animation tick.
  /// Returns the new snowT value.
  static double advanceFlakes(
      List<SnowFlake> flakes, double width, double height, double snowT) {
    snowT += 0.008;
    for (final f in flakes) {
      f.y += f.spd;
      f.x += f.drift + sin(snowT + f.off) * 0.5;
      if (f.y > height + f.r) {
        f.y = -f.r;
        f.x = Random().nextDouble() * width;
      }
      if (f.x > width + f.r) f.x = -f.r;
      if (f.x < -f.r) f.x = width + f.r;
    }
    return snowT;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final f in flakes) {
      // rgba(215,235,252,op)
      paint.color = Color.fromRGBO(215, 235, 252, f.op);
      canvas.drawCircle(Offset(f.x, f.y), f.r, paint);
    }
  }

  @override
  bool shouldRepaint(SnowPainter oldDelegate) {
    return animationTime != oldDelegate.animationTime;
  }
}
