import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// mulberry32 seeded PRNG, ported exactly from the Svelte source.
/// Returns a function that produces pseudo-random doubles in [0, 1).
typedef PRNGFunction = double Function();

PRNGFunction mulberry32(int seed) {
  int a = seed;
  return () {
    a = (a + 0x6d2b79f5) & 0xFFFFFFFF;
    // Emulate JS: a |= 0 is implicit via & 0xFFFFFFFF
    // t = Math.imul(a ^ (a >>> 15), 1 | a)
    int t = a ^ (a >>> 15);
    t = ((BigInt.from(t & 0xFFFFFFFF) * BigInt.from(1 | (a & 0xFFFFFFFF))) &
            BigInt.from(0xFFFFFFFF))
        .toInt();
    // t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    int t2 = t ^ (t >>> 7);
    int mul2 = ((BigInt.from(t2 & 0xFFFFFFFF) *
                BigInt.from(61 | (t & 0xFFFFFFFF))) &
            BigInt.from(0xFFFFFFFF))
        .toInt();
    t = ((t + mul2) & 0xFFFFFFFF) ^ t;
    final result = (t ^ (t >>> 14)) & 0xFFFFFFFF;
    return result / 4294967296;
  };
}

/// Theme-colored fill values for treeline, matching the source exactly.
const Map<String, String> _treeFills = {
  'day': '#142a48',
  'rise': '#1a0908',
  'golden': '#180e06',
  'sunset': '#120618',
  'night': '#0e1322',
  'rain': '#0e1520',
  'storm': '#0a0918',
  'snow': '#101828',
};

/// Parses a hex color string (#RRGGBB) to RGB components.
(int, int, int) _parseHex(String hex) {
  hex = hex.replaceFirst('#', '');
  return (
    int.parse(hex.substring(0, 2), radix: 16),
    int.parse(hex.substring(2, 4), radix: 16),
    int.parse(hex.substring(4, 6), radix: 16),
  );
}

/// Paints two layers of procedural pine trees and a ground plane.
/// Port of buildTreeline() from the Svelte source.
///
/// Back layer: seed 42, trees 50-110px tall, alpha 0.6.
/// Front layer: seed 77, trees 88-208px tall, alpha 1.0.
/// Ground plane at 62% of canvas height.
/// Fog gradient from 38% to 62% height.
///
/// This painter caches its output to a [ui.Picture] for performance.
class TreelinePainter extends CustomPainter {
  /// Current theme name.
  final String theme;

  /// Cached picture (set externally after first paint or theme change).
  final ui.Picture? cachedPicture;

  TreelinePainter({
    required this.theme,
    this.cachedPicture,
  });

  /// Render the treeline to a [ui.Picture] for caching.
  /// The caller should store this and pass it back via [cachedPicture].
  static ui.Picture renderToPicture(String theme, double width, double height) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    _paintTreeline(canvas, Size(width, height), theme);
    return recorder.endRecording();
  }

  static void _paintTreeline(Canvas canvas, Size size, String theme) {
    final hexStr = _treeFills[theme] ?? '#0e1520';
    final (r, g, b) = _parseHex(hexStr);
    final w = size.width;
    final h = size.height;
    final gndY = h * 0.62;

    // Ground plane
    final groundPaint = Paint()..color = Color.fromRGBO(r, g, b, 1.0);
    canvas.drawRect(
      Rect.fromLTWH(0, gndY, w, h - gndY + 4),
      groundPaint,
    );

    // Draw tree helper
    void drawTree(double x, double baseY, double treeH, double alpha) {
      final n = (6 + treeH / 20).round();
      final maxHW = treeH * 0.12;
      final tierH = treeH * 0.28;
      final treePaint = Paint()
        ..color = Color.fromRGBO(r, g, b, alpha)
        ..style = PaintingStyle.fill;

      for (int i = 0; i < n; i++) {
        final t = i / (n - 1);
        final apexY = baseY - treeH * (1 - t * 0.82);
        final tw = maxHW * math.pow(t + 0.05, 0.52);
        final path = Path()
          ..moveTo(x, apexY)
          ..lineTo(x - tw, apexY + tierH)
          ..lineTo(x + tw, apexY + tierH)
          ..close();
        canvas.drawPath(path, treePaint);
      }

      // Trunk
      final trW = math.max(1.5, treeH * 0.016);
      final trunkPaint = Paint()
        ..color = Color.fromRGBO(r, g, b, alpha)
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(
          x - trW / 2,
          baseY - treeH * 0.09,
          trW,
          treeH * 0.09 + 3,
        ),
        trunkPaint,
      );
    }

    // Back layer: seed 42
    var rng = mulberry32(42);
    double px = -30;
    while (px < w + 40) {
      final th = 50 + rng() * 60;
      drawTree(px, gndY, th, 0.6);
      px += th * 0.19 + rng() * 26 + 5;
    }

    // Front layer: seed 77
    rng = mulberry32(77);
    px = -20;
    while (px < w + 30) {
      final th = 88 + rng() * 120;
      drawTree(px, gndY, th, 1.0);
      px += th * 0.16 + rng() * 22 + 4;
    }

    // Fog gradient from 38% to 62% of canvas height
    final fogGradient = ui.Gradient.linear(
      Offset(0, gndY * 0.38),
      Offset(0, gndY),
      [
        Color.fromRGBO(r, g, b, 0),
        Color.fromRGBO(r, g, b, 0.28),
      ],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, gndY * 0.38, w, gndY * 0.62),
      Paint()..shader = fogGradient,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (cachedPicture != null) {
      canvas.drawPicture(cachedPicture!);
    } else {
      _paintTreeline(canvas, size, theme);
    }
  }

  @override
  bool shouldRepaint(TreelinePainter oldDelegate) {
    return theme != oldDelegate.theme ||
        cachedPicture != oldDelegate.cachedPicture;
  }
}
