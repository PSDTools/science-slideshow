import 'dart:math';
import 'package:flutter/material.dart';

/// A single horizontal mist band.
class MistBand {
  /// Height of the band in px (55..140).
  final double height;

  /// Bottom position as fraction of screen height (from `i*6.5 + random*10` vh).
  final double bottomFrac;

  /// Base alpha (0.024..0.060).
  final double alpha;

  /// Animation duration in seconds (8..20).
  final double duration;

  /// Animation delay offset in seconds (0..10).
  final double delayOffset;

  const MistBand({
    required this.height,
    required this.bottomFrac,
    required this.alpha,
    required this.duration,
    required this.delayOffset,
  });
}

/// Paints 6 horizontal mist bands with low opacity and drift animation.
/// Port of buildMist() from the Svelte source.
///
/// Each band: width 130% of screen, offset left -15%, border-radius 50%,
/// blur 32px, drifts 0..30px horizontally (ease-in-out alternate).
/// Color: rgba(r,g,b, alpha) where r,g,b come from the theme.
class MistPainter extends CustomPainter {
  /// Pre-built list of 6 mist bands.
  final List<MistBand> bands;

  /// Theme-colored RGB values.
  final int colorR;
  final int colorG;
  final int colorB;

  /// Current elapsed time in seconds.
  final double elapsedSeconds;

  MistPainter({
    required this.bands,
    required this.colorR,
    required this.colorG,
    required this.colorB,
    required this.elapsedSeconds,
  });

  /// Build 6 mist bands matching the source.
  static List<MistBand> buildBands() {
    final rng = Random();
    final bands = <MistBand>[];
    for (int i = 0; i < 6; i++) {
      bands.add(MistBand(
        height: 55 + rng.nextDouble() * 85,
        bottomFrac: (i * 6.5 + rng.nextDouble() * 10) / 100.0,
        alpha: 0.024 + rng.nextDouble() * 0.036,
        duration: 8 + rng.nextDouble() * 12,
        delayOffset: rng.nextDouble() * 10,
      ));
    }
    return bands;
  }

  /// Ease-in-out for alternate drift.
  static double _easeInOut(double t) {
    return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final band in bands) {
      final t = elapsedSeconds + band.delayOffset;

      // Drift: ease-in-out infinite alternate, translates 0..30px
      final cycle = band.duration * 2; // full forward+back cycle
      final phase = (t % cycle) / cycle;
      double driftT;
      if (phase < 0.5) {
        driftT = _easeInOut(phase * 2);
      } else {
        driftT = _easeInOut((1.0 - phase) * 2);
      }
      final dx = 30.0 * driftT;

      // Band position: left=-15%, width=130%, bottom from bottomFrac
      final bandWidth = size.width * 1.3;
      final bandLeft = -size.width * 0.15 + dx;
      final bandBottom = band.bottomFrac * size.height;
      final bandTop = size.height - bandBottom - band.height;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(bandLeft, bandTop, bandWidth, band.height),
        Radius.circular(band.height / 2), // border-radius: 50% on a wide rect
      );

      // The CSS uses filter:blur(32px). We simulate with MaskFilter.
      final paint = Paint()
        ..color = Color.fromRGBO(colorR, colorG, colorB, band.alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 32);

      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(MistPainter oldDelegate) {
    return elapsedSeconds != oldDelegate.elapsedSeconds ||
        colorR != oldDelegate.colorR ||
        colorG != oldDelegate.colorG ||
        colorB != oldDelegate.colorB;
  }
}
