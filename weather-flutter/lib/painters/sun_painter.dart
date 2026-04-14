import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Paints the sun with core, corona, and halo.
/// Port of the CSS sun rendering from the Svelte source.
///
/// Core: radial gradient (#fff8c0 -> #ffd840 45% -> transparent 72%),
///   size clamp(60,11vw,105)px, blur 2px, breathing animation (scale 1..1.07).
/// Corona: conic gradient with 36 wedges alternating
///   rgba(255,225,80,0.22) and rgba(255,225,80,0.04) every 10deg,
///   size clamp(110,22vw,200)px, blur 8px, rotating at 16s/revolution.
/// Halo: radial gradient (rgba(255,230,80,0.22) -> rgba(255,200,40,0.08) 45% -> transparent 70%),
///   size clamp(200,38vw,360)px, blur 20px, same breathing as core.
/// UV boost: core scale += uvFactor * 0.35, halo scale += uvFactor * 0.55,
///   halo opacity = 0.6 + uvFactor * 0.4.
class SunPainter extends CustomPainter {
  /// Current elapsed time in seconds (drives rotation and breathing).
  final double elapsedSeconds;

  /// UV factor (0..1), derived from uv/11 clamped to 1.
  final double uvFactor;

  SunPainter({
    required this.elapsedSeconds,
    required this.uvFactor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final shortSide = math.min(size.width, size.height);

    // Size calculations (using shortSide as vw reference)
    final coreR = shortSide * 0.15; // ~11vw mapped to radius
    final coronaR = shortSide * 0.30; // ~22vw mapped to radius
    final haloR = shortSide * 0.50; // ~38vw mapped to radius

    // Breathing animation: 4s ease-in-out, scale 1..1.07
    final breathPhase = (math.sin(elapsedSeconds * 2 * math.pi / 4) + 1) / 2;
    final breathScale = 1.0 + 0.07 * breathPhase;
    // breathBrightness: 1.0 + 0.1 * breathPhase (reserved for filter emulation)

    // UV boost
    final coreScale = (1.0 + uvFactor * 0.35) * breathScale;
    final haloScale = (1.0 + uvFactor * 0.55) * breathScale;
    final haloBaseOpacity = 0.6 + uvFactor * 0.4;

    // -- Halo (back layer) --
    _paintHalo(canvas, cx, cy, haloR, haloScale, haloBaseOpacity);

    // -- Corona (middle layer) --
    _paintCorona(canvas, cx, cy, coronaR);

    // -- Core (front layer) --
    _paintCore(canvas, cx, cy, coreR, coreScale);
  }

  void _paintHalo(Canvas canvas, double cx, double cy, double baseR,
      double scale, double baseOpacity) {
    final r = baseR * scale;
    // Radial gradient: rgba(255,230,80,0.22) -> rgba(255,200,40,0.08) at 45% -> transparent at 70%
    final gradient = ui.Gradient.radial(
      Offset(cx, cy),
      r,
      [
        Color.fromRGBO(255, 230, 80, 0.22 * baseOpacity),
        Color.fromRGBO(255, 200, 40, 0.08 * baseOpacity),
        Colors.transparent,
      ],
      [0.0, 0.45, 0.70],
    );
    // Simulate blur(20px) with MaskFilter
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..shader = gradient
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );
  }

  void _paintCorona(Canvas canvas, double cx, double cy, double baseR) {
    // Conic gradient: 36 wedges, alternating colors every 10deg
    // Rotates: 16s per revolution
    final rotation = (elapsedSeconds / 16.0) * 2 * math.pi;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(rotation);

    // Build sweep gradient with 36 alternating stops
    final colors = <Color>[];
    final stops = <double>[];
    for (int i = 0; i <= 36; i++) {
      final isHigh = i % 2 == 0;
      colors.add(isHigh
          ? const Color.fromRGBO(255, 225, 80, 0.22)
          : const Color.fromRGBO(255, 225, 80, 0.04));
      stops.add(i / 36.0);
    }

    final gradient = SweepGradient(
      colors: colors,
      stops: stops,
    );

    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: Offset.zero, radius: baseR),
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawCircle(Offset.zero, baseR, paint);
    canvas.restore();
  }

  void _paintCore(
      Canvas canvas, double cx, double cy, double baseR, double scale) {
    final r = baseR * scale;
    // Radial gradient: #fff8c0 -> #ffd840 at 45% -> rgba(255,180,0,0) at 72%
    final gradient = ui.Gradient.radial(
      Offset(cx, cy),
      r,
      [
        const Color(0xFFFFF8C0),
        const Color(0xFFFFD840),
        const Color(0x00FFB400),
      ],
      [0.0, 0.45, 0.72],
    );
    // Simulate blur(2px)
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..shader = gradient
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(SunPainter oldDelegate) {
    return elapsedSeconds != oldDelegate.elapsedSeconds ||
        uvFactor != oldDelegate.uvFactor;
  }
}
