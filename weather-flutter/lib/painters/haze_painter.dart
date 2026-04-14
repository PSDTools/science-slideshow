import 'package:flutter/material.dart';

/// Paints a humidity haze overlay.
/// Port of the #wx-haze CSS from the Svelte source.
///
/// Color: rgba(200, 220, 240, alpha).
/// Alpha formula: max(0, (humidity - 40) / 60) * 0.2.
/// Also applies a conceptual blur effect (backdrop-filter: blur(alpha * 3px)).
/// Note: True backdrop blur requires BackdropFilter widget in the widget tree;
/// this painter only renders the color overlay.
class HazePainter extends CustomPainter {
  /// Current humidity value (0-100).
  final double humidity;

  HazePainter({required this.humidity});

  /// Compute the haze alpha from humidity, matching the source formula exactly.
  double get _hazeAlpha {
    if (humidity <= 40) return 0.0;
    return ((humidity - 40) / 60).clamp(0.0, 1.0) * 0.2;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = _hazeAlpha;
    if (alpha <= 0.001) return;

    // rgba(200, 220, 240, alpha)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Color.fromRGBO(200, 220, 240, alpha),
    );
  }

  @override
  bool shouldRepaint(HazePainter oldDelegate) {
    return humidity != oldDelegate.humidity;
  }
}
