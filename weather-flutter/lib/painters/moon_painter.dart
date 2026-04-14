import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Paints the moon phase exactly as renderMoonPhase() in the Svelte source.
///
/// 180px canvas, 34px disc radius. Phase 0=new, 0.25=first quarter,
/// 0.5=full, 0.75=last quarter.
///
/// Phase terminator: half-circle + ellipse approach.
/// Lit face color: rgba(232,240,255,0.96).
/// Limb softening: radial gradient from 72% to 100% of discR.
/// Inner halo: radial gradient from 0.8*discR to 1.7*discR.
/// Outer glow: radial gradient from 0.5*discR to 48% of canvas size.
/// New moon (phase <= 0.025 or >= 0.975): barely visible ring.
class MoonPainter extends CustomPainter {
  /// Moon phase: 0=new, 0.25=first quarter, 0.5=full, 0.75=last quarter.
  final double phase;

  MoonPainter({required this.phase});

  /// Canvas size matching the source.
  static const double canvasSize = 180.0;

  /// Disc radius matching the source.
  static const double discR = 34.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Scale to fit the provided size while maintaining the 180x180 coordinate space
    final scale = math.min(size.width, size.height) / canvasSize;
    canvas.save();
    canvas.scale(scale, scale);

    final cx = canvasSize / 2;
    final cy = canvasSize / 2;

    // New moon: barely visible ring
    if (phase <= 0.025 || phase >= 0.975) {
      final paint = Paint()
        ..color = const Color.fromRGBO(150, 170, 200, 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(cx, cy), discR, paint);
      canvas.restore();
      return;
    }

    // -- Lit face --
    // Clip to disc
    canvas.save();
    final clipPath = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: discR));
    canvas.clipPath(clipPath);

    final waxing = phase < 0.5;
    final tx = math.cos(phase * math.pi * 2) * discR;

    // Lit surface color: rgba(232,240,255,0.96)
    final litPaint = Paint()
      ..color = const Color.fromRGBO(232, 240, 255, 0.96)
      ..style = PaintingStyle.fill;

    // Build the terminator path
    final litPath = Path();
    if (waxing) {
      // Right half-circle (from -PI/2 to PI/2)
      litPath.addArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: discR),
        -math.pi / 2,
        math.pi,
      );
      // Ellipse from PI/2 back to -PI/2
      // The ellipse has rx = |tx|, ry = discR
      // anticlockwise if tx > 0
      _addEllipseArc(litPath, cx, cy, tx.abs(), discR,
          math.pi / 2, -math.pi / 2, tx > 0);
    } else {
      // Left half-circle (from -PI/2 to PI/2, anticlockwise)
      litPath.addArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: discR),
        -math.pi / 2,
        -math.pi,
      );
      // Ellipse from PI/2 back to -PI/2
      // anticlockwise if tx < 0
      _addEllipseArc(litPath, cx, cy, tx.abs(), discR,
          math.pi / 2, -math.pi / 2, tx < 0);
    }
    litPath.close();

    canvas.drawPath(litPath, litPaint);
    canvas.restore();

    // -- Atmospheric limb softening --
    canvas.save();
    canvas.clipPath(clipPath);
    final limbGradient = ui.Gradient.radial(
      Offset(cx, cy),
      discR,
      [
        const Color.fromRGBO(0, 0, 0, 0),
        const Color.fromRGBO(0, 0, 20, 0.28),
      ],
      [0.72, 1.0],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, canvasSize, canvasSize),
      Paint()..shader = limbGradient,
    );
    canvas.restore();

    // -- Inner halo (bleeds past disc edge) --
    final innerHaloGradient = ui.Gradient.radial(
      Offset(cx, cy),
      discR * 1.7,
      [
        const Color.fromRGBO(180, 210, 255, 0.28),
        const Color.fromRGBO(180, 210, 255, 0),
      ],
      [discR * 0.8 / (discR * 1.7), 1.0],
    );
    canvas.drawCircle(
      Offset(cx, cy),
      discR * 1.7,
      Paint()..shader = innerHaloGradient,
    );

    // -- Outer diffuse glow --
    final outerR = canvasSize * 0.48;
    final outerGlowGradient = ui.Gradient.radial(
      Offset(cx, cy),
      outerR,
      [
        const Color.fromRGBO(160, 195, 255, 0.14),
        const Color.fromRGBO(140, 180, 255, 0.06),
        const Color.fromRGBO(140, 180, 255, 0),
      ],
      [discR * 0.5 / outerR, 0.5, 1.0],
    );
    canvas.drawCircle(
      Offset(cx, cy),
      outerR,
      Paint()..shader = outerGlowGradient,
    );

    canvas.restore();
  }

  /// Draw an elliptical arc, mimicking the HTML Canvas ellipse() call.
  /// Adds points along the ellipse from startAngle to endAngle.
  void _addEllipseArc(Path path, double cx, double cy, double rx, double ry,
      double startAngle, double endAngle, bool anticlockwise) {
    // Sample the ellipse with sufficient points for smoothness
    const segments = 40;
    double sweep;
    if (anticlockwise) {
      sweep = startAngle - endAngle;
      if (sweep < 0) sweep += 2 * math.pi;
      sweep = -sweep;
    } else {
      sweep = endAngle - startAngle;
      if (sweep < 0) sweep += 2 * math.pi;
    }

    for (int i = 0; i <= segments; i++) {
      final t = i / segments;
      final angle = startAngle + sweep * t;
      final x = cx + rx * math.cos(angle);
      final y = cy + ry * math.sin(angle);
      if (i == 0) {
        path.lineTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
  }

  @override
  bool shouldRepaint(MoonPainter oldDelegate) {
    return phase != oldDelegate.phase;
  }
}
