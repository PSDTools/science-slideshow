import 'dart:math';
import 'package:flutter/material.dart';

/// A single lightning bolt with optional branch.
class LightningBolt {
  /// Main bolt path points.
  final List<Offset> mainPoints;

  /// Branch bolt path points (from a point on the main bolt).
  final List<Offset> branchPoints;

  /// Time when this bolt was created (elapsed seconds).
  final double spawnTime;

  /// Whether a double flash occurs (40% chance per source: Math.random() > 0.4).
  final bool hasSecondFlash;

  const LightningBolt({
    required this.mainPoints,
    required this.branchPoints,
    required this.spawnTime,
    required this.hasSecondFlash,
  });
}

/// Paints procedural lightning bolts with glow effect and flash overlay.
/// Port of buildLightning() + strike() from the Svelte source.
///
/// Bolt: random walk from top, y increments 28-72px, x jitters +/- 46px.
/// Branch: starts at 35-65% of main bolt, 4 segments.
/// Main bolt: stroke rgba(220,210,255,0.92), width 2, with blur glow.
/// Thin bolts: stroke rgba(255,255,255,0.45), width 0.8.
/// Flash: rgba(210,200,255,0.85), bright flash opacity 0.62, dim 0.26.
/// Double flash: 40% chance (random > 0.4 => ~60% hasSecond... source says `Math.random() > 0.4`).
/// Interval: 3.5-9s between strikes, initial delay 0.8-3s.
class LightningPainter extends CustomPainter {
  /// The current active bolt (null if between strikes).
  final LightningBolt? activeBolt;

  /// Current elapsed time in seconds.
  final double elapsedSeconds;

  /// Viewport reference dimensions for the SVG viewBox (1000x600).
  /// The bolt is generated in this coordinate space and scaled to fit.
  static const double viewBoxWidth = 1000;
  static const double viewBoxHeight = 600;

  LightningPainter({
    this.activeBolt,
    required this.elapsedSeconds,
  });

  /// Generate a new lightning bolt.
  static LightningBolt generateBolt(double currentTime) {
    final rng = Random();

    // Main bolt: random walk from top
    double startX = 300 + rng.nextDouble() * 400;
    double x = startX;
    double y = 0;
    final pts = <Offset>[Offset(x, y)];
    while (y < 490) {
      y += 28 + rng.nextDouble() * 44;
      x += (rng.nextDouble() - 0.48) * 92;
      pts.add(Offset(x, y));
    }

    // Branch bolt: starts at 35-65% of main bolt
    final bi = (pts.length * 0.35 + rng.nextDouble() * pts.length * 0.3).floor();
    double bx = pts[bi].dx;
    double by = pts[bi].dy;
    final branchPts = <Offset>[Offset(bx, by)];
    for (int i = 0; i < 4; i++) {
      bx += (rng.nextDouble() - 0.45) * 72;
      by += 24 + rng.nextDouble() * 40;
      branchPts.add(Offset(bx, by));
    }

    // Double flash: Math.random() > 0.4 => ~60% chance
    final hasSecond = rng.nextDouble() > 0.4;

    return LightningBolt(
      mainPoints: pts,
      branchPoints: branchPts,
      spawnTime: currentTime,
      hasSecondFlash: hasSecond,
    );
  }

  /// Get the next strike interval in seconds.
  static double nextStrikeInterval() {
    return 3.5 + Random().nextDouble() * 5.5; // 3.5-9s
  }

  /// Get the initial delay before first strike.
  static double initialDelay() {
    return 0.8 + Random().nextDouble() * 2.2; // 0.8-3s
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (activeBolt == null) return;

    final bolt = activeBolt!;
    final elapsed = elapsedSeconds - bolt.spawnTime;
    if (elapsed < 0) return;

    // Flash timing:
    // First flash (bright): 0ms, lasts 72ms (0.072s)
    // Second flash (dim): at 130ms (0.13s), lasts 45ms (0.045s)
    // Bolt visible until last flash ends
    final flashEnd = bolt.hasSecondFlash ? 0.175 : 0.072;
    if (elapsed > flashEnd + 0.1) return; // extra margin for fade

    // Scale from viewBox coordinates to actual size
    final scaleX = size.width / viewBoxWidth;
    final scaleY = size.height / viewBoxHeight;

    // -- Flash overlay --
    double flashOpacity = 0.0;
    if (elapsed < 0.072) {
      // First flash: bright, opacity 0.62
      flashOpacity = 0.62;
    } else if (bolt.hasSecondFlash && elapsed >= 0.13 && elapsed < 0.175) {
      // Second flash: dim, opacity 0.26
      flashOpacity = 0.26;
    }

    // Fade out the bolt
    double boltOpacity = 1.0;
    if (elapsed > flashEnd) {
      boltOpacity = (1.0 - (elapsed - flashEnd) / 0.1).clamp(0.0, 1.0);
    }

    if (flashOpacity > 0) {
      // Flash overlay: rgba(210,200,255,0.85) * flashOpacity
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Color.fromRGBO(210, 200, 255, 0.85 * flashOpacity),
      );
    }

    if (boltOpacity <= 0) return;

    // Build main bolt path
    final mainPath = _buildPath(bolt.mainPoints, scaleX, scaleY);
    final branchPath = _buildPath(bolt.branchPoints, scaleX, scaleY);

    // -- Glow bolt (main): blur + stroke --
    final glowPaint = Paint()
      ..color = Color.fromRGBO(220, 210, 255, 0.92 * boltOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * scaleX
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(mainPath, glowPaint);

    // -- Main bolt (crisp on top of glow) --
    final mainPaint = Paint()
      ..color = Color.fromRGBO(220, 210, 255, 0.92 * boltOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * scaleX
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(mainPath, mainPaint);

    // -- Thin bolt (main path duplicate) --
    final thinPaint = Paint()
      ..color = Color.fromRGBO(255, 255, 255, 0.45 * boltOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8 * scaleX
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(mainPath, thinPaint);

    // -- Thin bolt (branch) --
    canvas.drawPath(branchPath, thinPaint);
  }

  Path _buildPath(List<Offset> points, double scaleX, double scaleY) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points[0].dx * scaleX, points[0].dy * scaleY);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx * scaleX, points[i].dy * scaleY);
    }
    return path;
  }

  @override
  bool shouldRepaint(LightningPainter oldDelegate) {
    return elapsedSeconds != oldDelegate.elapsedSeconds ||
        activeBolt != oldDelegate.activeBolt;
  }
}
