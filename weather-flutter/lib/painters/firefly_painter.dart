import 'dart:math';
import 'package:flutter/material.dart';

/// A single firefly with drift + pulse.
class Firefly {
  /// Position as fraction of screen.
  final double xFrac; // 8..92vw -> 0.08..0.92
  final double yFrac; // 22..77vh -> 0.22..0.77

  /// Drift duration in seconds (3.5..10.0).
  final double driftDuration;

  /// Pulse duration in seconds (2.2..6.4).
  final double pulseDuration;

  /// Drift offset in px.
  final double driftDx; // -65..65
  final double driftDy; // -45..45

  /// Random animation delay offset in seconds (0..9).
  final double delayOffset;

  const Firefly({
    required this.xFrac,
    required this.yFrac,
    required this.driftDuration,
    required this.pulseDuration,
    required this.driftDx,
    required this.driftDy,
    required this.delayOffset,
  });
}

/// Paints 22 fireflies with drift and pulse animation.
/// Port of buildFireflies() from the Svelte source.
///
/// Color: rgba(165, 220, 70, 0.75), size: 3px diameter.
/// Drift: ease-in-out alternate between (0,0) and (dx,dy).
/// Pulse keyframes: 0%,18%,82%,100% -> opacity:0; 42%,58% -> opacity:1.
class FireflyPainter extends CustomPainter {
  /// Pre-built list of 22 fireflies.
  final List<Firefly> fireflies;

  /// Current elapsed time in seconds.
  final double elapsedSeconds;

  FireflyPainter({
    required this.fireflies,
    required this.elapsedSeconds,
  });

  /// Build 22 fireflies with random properties matching the source.
  static List<Firefly> buildFireflies() {
    final rng = Random();
    final flies = <Firefly>[];
    for (int i = 0; i < 22; i++) {
      flies.add(Firefly(
        xFrac: 0.08 + rng.nextDouble() * 0.84,
        yFrac: 0.22 + rng.nextDouble() * 0.55,
        driftDuration: 3.5 + rng.nextDouble() * 6.5,
        pulseDuration: 2.2 + rng.nextDouble() * 4.2,
        driftDx: rng.nextDouble() * 130 - 65,
        driftDy: rng.nextDouble() * 90 - 45,
        delayOffset: rng.nextDouble() * 9,
      ));
    }
    return flies;
  }

  /// Compute the pulse opacity from the exact keyframe values:
  /// 0%   -> 0
  /// 18%  -> 0
  /// 42%  -> 1
  /// 58%  -> 1
  /// 82%  -> 0
  /// 100% -> 0
  static double _pulseOpacity(double phase) {
    // phase is 0..1 within one cycle
    if (phase <= 0.18) return 0.0;
    if (phase <= 0.42) {
      // Ramp up from 0 to 1 over 18%->42%
      return (phase - 0.18) / (0.42 - 0.18);
    }
    if (phase <= 0.58) return 1.0;
    if (phase <= 0.82) {
      // Ramp down from 1 to 0 over 58%->82%
      return 1.0 - (phase - 0.58) / (0.82 - 0.58);
    }
    return 0.0;
  }

  /// Ease-in-out function for drift (alternate).
  static double _easeInOut(double t) {
    return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final ff in fireflies) {
      final t = elapsedSeconds + ff.delayOffset;

      // Drift: ease-in-out infinite alternate
      // Full cycle = 2 * driftDuration (forward + back)
      final driftCycle = ff.driftDuration * 2;
      final driftPhase = (t % driftCycle) / driftCycle;
      // alternate: 0..0.5 is forward, 0.5..1 is backward
      double driftT;
      if (driftPhase < 0.5) {
        driftT = _easeInOut(driftPhase * 2);
      } else {
        driftT = _easeInOut((1.0 - driftPhase) * 2);
      }

      final dx = ff.driftDx * driftT;
      final dy = ff.driftDy * driftT;

      // Pulse: infinite (not alternate)
      final pulsePhase = (t % ff.pulseDuration) / ff.pulseDuration;
      final opacity = _pulseOpacity(pulsePhase);

      if (opacity <= 0.001) continue;

      final x = ff.xFrac * size.width + dx;
      final y = ff.yFrac * size.height + dy;

      // rgba(165, 220, 70, 0.75) * pulse opacity
      paint.color = Color.fromRGBO(165, 220, 70, 0.75 * opacity);
      canvas.drawCircle(Offset(x, y), 1.5, paint);
    }
  }

  @override
  bool shouldRepaint(FireflyPainter oldDelegate) {
    return elapsedSeconds != oldDelegate.elapsedSeconds;
  }
}
