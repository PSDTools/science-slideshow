import 'dart:ui';

/// All weather display themes, matching the Svelte t-* CSS classes.
enum WeatherTheme {
  night,
  day,
  rise,
  golden,
  sunset,
  rain,
  storm,
  snow,
}

/// Atmospheric gradient layer specification.
class AtmosGradient {
  /// CSS-style spec: 'ellipse' or 'radial'
  final String shape;

  /// e.g. '80% 50%'
  final String size;

  /// e.g. '75% 8%'
  final String at;

  final List<AtmosStop> stops;

  const AtmosGradient({
    required this.shape,
    required this.size,
    required this.at,
    required this.stops,
  });
}

class AtmosStop {
  final Color color;
  final double stop; // 0.0 - 1.0

  const AtmosStop(this.color, this.stop);
}

/// All color properties for a given theme, ported from the CSS :global(.wx-root.t-*) blocks.
class ThemeColors {
  final Color bg0;
  final Color bg1;
  final Color text;
  final Color sub;
  final Color tempCol;
  final Color glowCol;
  final Color accent;

  /// Tree fill color for the treeline silhouette.
  final Color treeFill;

  /// Atmospheric gradient layers for the theme.
  final List<AtmosGradient> atmos;

  const ThemeColors({
    required this.bg0,
    required this.bg1,
    required this.text,
    required this.sub,
    required this.tempCol,
    required this.glowCol,
    required this.accent,
    required this.treeFill,
    this.atmos = const [],
  });
}

/// Background gradient specs for sky cross-fade, matching BG_GRADIENTS.
/// Each entry is (bg0Color, bg1Color) at 165deg.
const Map<WeatherTheme, (Color, Color)> bgGradients = {
  WeatherTheme.night: (Color(0xFF111827), Color(0xFF1a2540)),
  WeatherTheme.day: (Color(0xFF1c4a7a), Color(0xFF2a6aaa)),
  WeatherTheme.rise: (Color(0xFF2a1008), Color(0xFF6a2808)),
  WeatherTheme.golden: (Color(0xFF251408), Color(0xFF5a3010)),
  WeatherTheme.sunset: (Color(0xFF1a0820), Color(0xFF4a1230)),
  WeatherTheme.rain: (Color(0xFF101820), Color(0xFF182838)),
  WeatherTheme.storm: (Color(0xFF0e0c1e), Color(0xFF181430)),
  WeatherTheme.snow: (Color(0xFF141c2c), Color(0xFF1e2c44)),
};

/// Complete theme color definitions, ported exactly from the Svelte CSS.
const Map<WeatherTheme, ThemeColors> themeColors = {
  // Default / fallback (matches :global(.wx-root) base)
  // Used as night fallback but night has its own entry below.

  WeatherTheme.night: ThemeColors(
    bg0: Color(0xFF111827),
    bg1: Color(0xFF1a2540),
    text: Color(0xFFd4e4f8),
    sub: Color(0x6BB4CDF0), // rgba(180, 205, 240, 0.42)
    tempCol: Color(0xFFc8dcf4),
    glowCol: Color(0x525A78C8), // rgba(90, 120, 200, 0.32)
    accent: Color(0xB378A5EB), // rgba(120, 165, 235, 0.7)
    treeFill: Color(0xFF0e1322),
    atmos: [
      AtmosGradient(
        shape: 'ellipse',
        size: '80% 50%',
        at: '75% 8%',
        stops: [
          AtmosStop(Color(0x2E3752BE), 0.0), // rgba(55, 82, 190, 0.18)
          AtmosStop(Color(0x00000000), 0.60),
        ],
      ),
      AtmosGradient(
        shape: 'ellipse',
        size: '100% 45%',
        at: '50% 0%',
        stops: [
          AtmosStop(Color(0x400C1650), 0.0), // rgba(12, 22, 80, 0.25)
          AtmosStop(Color(0x00000000), 0.55),
        ],
      ),
    ],
  ),

  WeatherTheme.day: ThemeColors(
    bg0: Color(0xFF1c4a7a),
    bg1: Color(0xFF2a6aaa),
    text: Color(0xFFffffff),
    sub: Color(0x8CFFFFFF), // rgba(255, 255, 255, 0.55)
    tempCol: Color(0xFFffffff),
    glowCol: Color(0x66FFF0A0), // rgba(255, 240, 160, 0.4)
    accent: Color(0xCCFFF278), // rgba(255, 242, 120, 0.8)
    treeFill: Color(0xFF142a48),
    atmos: [
      AtmosGradient(
        shape: 'ellipse',
        size: '120% 60%',
        at: '50% 0%',
        stops: [
          AtmosStop(Color(0x4D78BEFF), 0.0), // rgba(120, 190, 255, 0.3)
          AtmosStop(Color(0x00000000), 0.65),
        ],
      ),
      AtmosGradient(
        shape: 'ellipse',
        size: '80% 40%',
        at: '85% 20%',
        stops: [
          AtmosStop(Color(0x2EFFF08C), 0.0), // rgba(255, 240, 140, 0.18)
          AtmosStop(Color(0x00000000), 0.50),
        ],
      ),
    ],
  ),

  WeatherTheme.rise: ThemeColors(
    bg0: Color(0xFF2a1008),
    bg1: Color(0xFF6a2808),
    text: Color(0xFFfce8d0),
    sub: Color(0x7AF5C382), // rgba(245, 195, 130, 0.48)
    tempCol: Color(0xFFfdd8a0),
    glowCol: Color(0x73F58C32), // rgba(245, 140, 50, 0.45)
    accent: Color(0xCCFFAA46), // rgba(255, 170, 70, 0.8)
    treeFill: Color(0xFF1a0908),
    atmos: [
      AtmosGradient(
        shape: 'ellipse',
        size: '140% 60%',
        at: '22% 110%',
        stops: [
          AtmosStop(Color(0x8CE65F1E), 0.0), // rgba(230, 95, 30, 0.55)
          AtmosStop(Color(0x00000000), 0.52),
        ],
      ),
      AtmosGradient(
        shape: 'ellipse',
        size: '90% 58%',
        at: '72% 108%',
        stops: [
          AtmosStop(Color(0x47A52846), 0.0), // rgba(165, 40, 70, 0.28)
          AtmosStop(Color(0x00000000), 0.50),
        ],
      ),
    ],
  ),

  WeatherTheme.golden: ThemeColors(
    bg0: Color(0xFF251408),
    bg1: Color(0xFF5a3010),
    text: Color(0xFFf8e0b0),
    sub: Color(0x75F0B964), // rgba(240, 185, 100, 0.46)
    tempCol: Color(0xFFf8d080),
    glowCol: Color(0x7AEB9B2D), // rgba(235, 155, 45, 0.48)
    accent: Color(0xCCFFC33C), // rgba(255, 195, 60, 0.8)
    treeFill: Color(0xFF180e06),
    atmos: [
      AtmosGradient(
        shape: 'ellipse',
        size: '140% 62%',
        at: '80% 112%',
        stops: [
          AtmosStop(Color(0x85D77319), 0.0), // rgba(215, 115, 25, 0.52)
          AtmosStop(Color(0x00000000), 0.52),
        ],
      ),
      AtmosGradient(
        shape: 'ellipse',
        size: '70% 58%',
        at: '12% 110%',
        stops: [
          AtmosStop(Color(0x3D822D12), 0.0), // rgba(130, 45, 18, 0.24)
          AtmosStop(Color(0x00000000), 0.50),
        ],
      ),
    ],
  ),

  WeatherTheme.sunset: ThemeColors(
    bg0: Color(0xFF1a0820),
    bg1: Color(0xFF4a1230),
    text: Color(0xFFf4cce0),
    sub: Color(0x6BEBA5B9), // rgba(235, 165, 185, 0.42)
    tempCol: Color(0xFFf4c0c8),
    glowCol: Color(0x61D75064), // rgba(215, 80, 100, 0.38)
    accent: Color(0xBFFF788C), // rgba(255, 120, 140, 0.75)
    treeFill: Color(0xFF120618),
    atmos: [
      AtmosGradient(
        shape: 'ellipse',
        size: '125% 64%',
        at: '55% 114%',
        stops: [
          AtmosStop(Color(0x94C33212), 0.0), // rgba(195, 50, 18, 0.58)
          AtmosStop(Color(0x00000000), 0.52),
        ],
      ),
      AtmosGradient(
        shape: 'ellipse',
        size: '78% 68%',
        at: '5% 112%',
        stops: [
          AtmosStop(Color(0x596E125A), 0.0), // rgba(110, 18, 90, 0.35)
          AtmosStop(Color(0x00000000), 0.50),
        ],
      ),
    ],
  ),

  WeatherTheme.rain: ThemeColors(
    bg0: Color(0xFF101820),
    bg1: Color(0xFF182838),
    text: Color(0xFFbcd0e8),
    sub: Color(0x6BA0C3E6), // rgba(160, 195, 230, 0.42)
    tempCol: Color(0xFFa8c8e8),
    glowCol: Color(0x4D4682C3), // rgba(70, 130, 195, 0.3)
    accent: Color(0xB364A5E1), // rgba(100, 165, 225, 0.7)
    treeFill: Color(0xFF0e1520),
    atmos: [
      AtmosGradient(
        shape: 'ellipse',
        size: '100% 65%',
        at: '50% 0%',
        stops: [
          AtmosStop(Color(0x4716325F), 0.0), // rgba(22, 50, 95, 0.28)
          AtmosStop(Color(0x00000000), 0.65),
        ],
      ),
    ],
  ),

  WeatherTheme.storm: ThemeColors(
    bg0: Color(0xFF0e0c1e),
    bg1: Color(0xFF181430),
    text: Color(0xFFc8c0e8),
    sub: Color(0x66B9AFE1), // rgba(185, 175, 225, 0.4)
    tempCol: Color(0xFFc4bcec),
    glowCol: Color(0x59785ADC), // rgba(120, 90, 220, 0.35)
    accent: Color(0xC7A58CFF), // rgba(165, 140, 255, 0.78)
    treeFill: Color(0xFF0a0918),
    atmos: [
      AtmosGradient(
        shape: 'ellipse',
        size: '100% 70%',
        at: '50% 0%',
        stops: [
          AtmosStop(Color(0x6626126C), 0.0), // rgba(38, 18, 108, 0.4)
          AtmosStop(Color(0x00000000), 0.65),
        ],
      ),
      AtmosGradient(
        shape: 'ellipse',
        size: '80% 58%',
        at: '12% 100%',
        stops: [
          AtmosStop(Color(0x4012054B), 0.0), // rgba(18, 5, 75, 0.25)
          AtmosStop(Color(0x00000000), 0.55),
        ],
      ),
    ],
  ),

  WeatherTheme.snow: ThemeColors(
    bg0: Color(0xFF141c2c),
    bg1: Color(0xFF1e2c44),
    text: Color(0xFFd8e8f8),
    sub: Color(0x73C8DCF5), // rgba(200, 220, 245, 0.45)
    tempCol: Color(0xFFe4eff8),
    glowCol: Color(0x4DA0C8F5), // rgba(160, 200, 245, 0.3)
    accent: Color(0xBFBEDCFF), // rgba(190, 220, 255, 0.75)
    treeFill: Color(0xFF101828),
    atmos: [
      AtmosGradient(
        shape: 'ellipse',
        size: '100% 58%',
        at: '50% 0%',
        stops: [
          AtmosStop(Color(0x2478A5E6), 0.0), // rgba(120, 165, 230, 0.14)
          AtmosStop(Color(0x00000000), 0.60),
        ],
      ),
    ],
  ),
};
