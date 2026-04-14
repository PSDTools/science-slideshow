import 'dart:math';
import 'package:flutter/material.dart';

/// A single raindrop particle.
class RainDrop {
  double x;
  double y;
  double len;
  double spd;
  double op;
  double ang;

  RainDrop({
    required this.x,
    required this.y,
    required this.len,
    required this.spd,
    required this.op,
    required this.ang,
  });
}

/// Paints rain particles. Normal rain: 150 drops. Storm: 320 drops.
/// Port of initRain() + drawRain() from the Svelte source.
class RainPainter extends CustomPainter {
  /// The list of rain drop particles (mutated each frame by the parent).
  final List<RainDrop> drops;

  /// Whether this is heavy/storm rain.
  final bool heavy;

  /// Current animation time (used to trigger repaints).
  final double animationTime;

  RainPainter({
    required this.drops,
    required this.heavy,
    required this.animationTime,
  });

  /// Initialize rain drops for the given canvas size.
  /// Normal: 150 drops, angle 7deg. Storm: 320 drops, angle 18deg.
  static List<RainDrop> initDrops(double width, double height, bool heavy) {
    final rng = Random();
    final count = heavy ? 320 : 150;
    final angle = heavy ? 18.0 : 7.0;
    final drops = <RainDrop>[];
    for (int i = 0; i < count; i++) {
      drops.add(RainDrop(
        x: rng.nextDouble() * (width + 200) - 100,
        y: rng.nextDouble() * height,
        len: heavy
            ? 22 + rng.nextDouble() * 20
            : 14 + rng.nextDouble() * 12,
        spd: heavy
            ? 18 + rng.nextDouble() * 14
            : 11 + rng.nextDouble() * 8,
        op: 0.18 + rng.nextDouble() * 0.48,
        ang: (angle + (rng.nextDouble() - 0.5) * 6) * pi / 180,
      ));
    }
    return drops;
  }

  /// Advance all drops by one frame. Call this from the animation tick.
  static void advanceDrops(
      List<RainDrop> drops, double width, double height) {
    for (final d in drops) {
      d.y += d.spd;
      d.x += sin(d.ang) * d.spd;
      if (d.y > height) {
        d.y = -d.len;
        d.x = Random().nextDouble() * (width + 200) - 100;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final d in drops) {
      // Storm: rgba(160,200,245,op), Normal: rgba(120,175,225,op)
      paint.color = heavy
          ? Color.fromRGBO(160, 200, 245, d.op)
          : Color.fromRGBO(120, 175, 225, d.op);
      paint.strokeWidth = heavy ? 1.4 : 0.9;

      canvas.drawLine(
        Offset(d.x, d.y),
        Offset(d.x + sin(d.ang) * d.len, d.y + cos(d.ang) * d.len),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(RainPainter oldDelegate) {
    return animationTime != oldDelegate.animationTime ||
        heavy != oldDelegate.heavy;
  }
}
