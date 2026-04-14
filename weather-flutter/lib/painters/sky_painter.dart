import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Background gradient colors per theme (bg0, bg1).
class ThemeColors {
  final Color bg0;
  final Color bg1;

  const ThemeColors(this.bg0, this.bg1);

  static const Map<String, ThemeColors> gradients = {
    'night': ThemeColors(Color(0xFF111827), Color(0xFF1a2540)),
    'day': ThemeColors(Color(0xFF1c4a7a), Color(0xFF2a6aaa)),
    'rise': ThemeColors(Color(0xFF2a1008), Color(0xFF6a2808)),
    'golden': ThemeColors(Color(0xFF251408), Color(0xFF5a3010)),
    'sunset': ThemeColors(Color(0xFF1a0820), Color(0xFF4a1230)),
    'rain': ThemeColors(Color(0xFF101820), Color(0xFF182838)),
    'storm': ThemeColors(Color(0xFF0e0c1e), Color(0xFF181430)),
    'snow': ThemeColors(Color(0xFF141c2c), Color(0xFF1e2c44)),
  };
}

/// Atmospheric radial overlay definitions per theme.
class _AtmosLayer {
  final Offset centerFrac; // center as fraction of width/height
  final double radiusXFrac; // ellipse x-radius as fraction of width
  final double radiusYFrac; // ellipse y-radius as fraction of height
  final Color color;
  final double stopEnd; // gradient stop end (0..1)

  const _AtmosLayer({
    required this.centerFrac,
    required this.radiusXFrac,
    required this.radiusYFrac,
    required this.color,
    required this.stopEnd,
  });
}

final Map<String, List<_AtmosLayer>> _atmosLayers = {
  'night': [
    _AtmosLayer(
      centerFrac: Offset(0.75, 0.08),
      radiusXFrac: 0.80,
      radiusYFrac: 0.50,
      color: Color.fromRGBO(55, 82, 190, 0.18),
      stopEnd: 0.60,
    ),
    _AtmosLayer(
      centerFrac: Offset(0.50, 0.0),
      radiusXFrac: 1.00,
      radiusYFrac: 0.45,
      color: Color.fromRGBO(12, 22, 80, 0.25),
      stopEnd: 0.55,
    ),
  ],
  'day': [
    _AtmosLayer(
      centerFrac: Offset(0.50, 0.0),
      radiusXFrac: 1.20,
      radiusYFrac: 0.60,
      color: Color.fromRGBO(120, 190, 255, 0.30),
      stopEnd: 0.65,
    ),
    _AtmosLayer(
      centerFrac: Offset(0.85, 0.20),
      radiusXFrac: 0.80,
      radiusYFrac: 0.40,
      color: Color.fromRGBO(255, 240, 140, 0.18),
      stopEnd: 0.50,
    ),
  ],
  'rise': [
    _AtmosLayer(
      centerFrac: Offset(0.22, 1.10),
      radiusXFrac: 1.40,
      radiusYFrac: 0.60,
      color: Color.fromRGBO(230, 95, 30, 0.55),
      stopEnd: 0.52,
    ),
    _AtmosLayer(
      centerFrac: Offset(0.72, 1.08),
      radiusXFrac: 0.90,
      radiusYFrac: 0.58,
      color: Color.fromRGBO(165, 40, 70, 0.28),
      stopEnd: 0.50,
    ),
  ],
  'golden': [
    _AtmosLayer(
      centerFrac: Offset(0.80, 1.12),
      radiusXFrac: 1.40,
      radiusYFrac: 0.62,
      color: Color.fromRGBO(215, 115, 25, 0.52),
      stopEnd: 0.52,
    ),
    _AtmosLayer(
      centerFrac: Offset(0.12, 1.10),
      radiusXFrac: 0.70,
      radiusYFrac: 0.58,
      color: Color.fromRGBO(130, 45, 18, 0.24),
      stopEnd: 0.50,
    ),
  ],
  'sunset': [
    _AtmosLayer(
      centerFrac: Offset(0.55, 1.14),
      radiusXFrac: 1.25,
      radiusYFrac: 0.64,
      color: Color.fromRGBO(195, 50, 18, 0.58),
      stopEnd: 0.52,
    ),
    _AtmosLayer(
      centerFrac: Offset(0.05, 1.12),
      radiusXFrac: 0.78,
      radiusYFrac: 0.68,
      color: Color.fromRGBO(110, 18, 90, 0.35),
      stopEnd: 0.50,
    ),
  ],
  'rain': [
    _AtmosLayer(
      centerFrac: Offset(0.50, 0.0),
      radiusXFrac: 1.00,
      radiusYFrac: 0.65,
      color: Color.fromRGBO(22, 50, 95, 0.28),
      stopEnd: 0.65,
    ),
  ],
  'storm': [
    _AtmosLayer(
      centerFrac: Offset(0.50, 0.0),
      radiusXFrac: 1.00,
      radiusYFrac: 0.70,
      color: Color.fromRGBO(38, 18, 108, 0.40),
      stopEnd: 0.65,
    ),
    _AtmosLayer(
      centerFrac: Offset(0.12, 1.00),
      radiusXFrac: 0.80,
      radiusYFrac: 0.58,
      color: Color.fromRGBO(18, 5, 75, 0.25),
      stopEnd: 0.55,
    ),
  ],
  'snow': [
    _AtmosLayer(
      centerFrac: Offset(0.50, 0.0),
      radiusXFrac: 1.00,
      radiusYFrac: 0.58,
      color: Color.fromRGBO(120, 165, 230, 0.14),
      stopEnd: 0.60,
    ),
  ],
};

/// Paints the sky background: 165deg linear gradient from bg0 to bg1,
/// atmospheric radial overlays, cross-fade between themes, and
/// precipitation darkening overlay.
class SkyPainter extends CustomPainter {
  /// Current theme name (night, day, rise, golden, sunset, rain, storm, snow).
  final String theme;

  /// Previous theme for cross-fade (null if no transition).
  final String? previousTheme;

  /// Cross-fade progress: 0.0 = fully previous, 1.0 = fully current.
  final double crossFadeProgress;

  /// Whether precipitation is active (adds darkening overlay).
  final bool isPrecip;

  SkyPainter({
    required this.theme,
    this.previousTheme,
    this.crossFadeProgress = 1.0,
    this.isPrecip = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // -- Paint old theme layer (fading out) during cross-fade --
    if (previousTheme != null &&
        previousTheme != theme &&
        crossFadeProgress < 1.0) {
      _paintThemeLayer(
        canvas,
        size,
        previousTheme!,
        1.0 - crossFadeProgress,
      );
    }

    // -- Paint current theme layer --
    _paintThemeLayer(
      canvas,
      size,
      theme,
      crossFadeProgress < 1.0 ? crossFadeProgress : 1.0,
    );

    // -- Precipitation darkening overlay: rgba(0,0,0,0.45) --
    if (isPrecip) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color.fromRGBO(0, 0, 0, 0.45),
      );
    }
  }

  void _paintThemeLayer(
      Canvas canvas, Size size, String themeName, double opacity) {
    final colors = ThemeColors.gradients[themeName];
    if (colors == null) return;

    // 165deg linear gradient from bg0 to bg1.
    // 165deg = from top-left area toward bottom-right area.
    // CSS 165deg: 0deg is to-top, 165deg is almost to-bottom, slightly left.
    // Convert: angle from positive Y axis clockwise.
    // 165deg CSS = gradient line at 165deg from top.
    const angleRad = 165.0 * math.pi / 180.0;
    final dx = math.sin(angleRad);
    final dy = -math.cos(angleRad); // CSS gradient direction

    // Compute start/end points on the rect
    final halfW = size.width / 2;
    final halfH = size.height / 2;
    final t = (dx.abs() * halfW + dy.abs() * halfH);
    final startX = halfW - dx * t;
    final startY = halfH - dy * t;
    final endX = halfW + dx * t;
    final endY = halfH + dy * t;

    final bg0 = colors.bg0.withValues(alpha: colors.bg0.a * opacity);
    final bg1 = colors.bg1.withValues(alpha: colors.bg1.a * opacity);

    final gradientPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(startX, startY),
        Offset(endX, endY),
        [bg0, bg1],
        [0.0, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), gradientPaint);

    // -- Atmospheric radial overlays --
    final layers = _atmosLayers[themeName];
    if (layers != null) {
      for (final layer in layers) {
        _paintAtmosLayer(canvas, size, layer, opacity);
      }
    }
  }

  void _paintAtmosLayer(
      Canvas canvas, Size size, _AtmosLayer layer, double opacity) {
    final cx = layer.centerFrac.dx * size.width;
    final cy = layer.centerFrac.dy * size.height;
    // Use the larger ellipse radius for the radial gradient radius
    final rx = layer.radiusXFrac * size.width;
    final ry = layer.radiusYFrac * size.height;
    final r = math.max(rx, ry);

    final color = layer.color.withValues(alpha: layer.color.a * opacity);

    // Scale the canvas to create an elliptical gradient
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(rx / r, ry / r);

    final gradient = ui.Gradient.radial(
      Offset.zero,
      r,
      [color, color.withValues(alpha: 0)],
      [0.0, layer.stopEnd],
      TileMode.clamp,
    );

    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()..shader = gradient,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(SkyPainter oldDelegate) {
    return theme != oldDelegate.theme ||
        previousTheme != oldDelegate.previousTheme ||
        crossFadeProgress != oldDelegate.crossFadeProgress ||
        isPrecip != oldDelegate.isPrecip;
  }
}
