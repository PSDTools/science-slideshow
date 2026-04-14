import 'dart:math';
import 'package:flutter/material.dart';
import '../models/weather_theme.dart';
import '../logic/theme_engine.dart';
import '../logic/celestial_engine.dart';

// ─── Particle data classes ───
class RainDrop {
  double x, y, len, spd, op, ang;
  RainDrop({
    required this.x,
    required this.y,
    required this.len,
    required this.spd,
    required this.op,
    required this.ang,
  });
}

class SnowFlake {
  double x, y, r, spd, drift, op, off;
  SnowFlake({
    required this.x,
    required this.y,
    required this.r,
    required this.spd,
    required this.drift,
    required this.op,
    required this.off,
  });
}

class Star {
  final double x, y, size, baseOpacity, pulseDuration, pulseOffset;
  const Star({
    required this.x,
    required this.y,
    required this.size,
    required this.baseOpacity,
    required this.pulseDuration,
    required this.pulseOffset,
  });
}

class Firefly {
  final double x, y, driftDur, pulseDur, dx, dy, delay;
  const Firefly({
    required this.x,
    required this.y,
    required this.driftDur,
    required this.pulseDur,
    required this.dx,
    required this.dy,
    required this.delay,
  });
}

class MistBand {
  final double bottom, height, opacity, duration, delay;
  final Color color;
  const MistBand({
    required this.bottom,
    required this.height,
    required this.opacity,
    required this.duration,
    required this.delay,
    required this.color,
  });
}

class WindStreak {
  final double top, left, width, duration, angle, opacity, delay;
  const WindStreak({
    required this.top,
    required this.left,
    required this.width,
    required this.duration,
    required this.angle,
    required this.opacity,
    required this.delay,
  });
}

// ─── Lightning bolt data ───
class LightningBolt {
  final List<Offset> mainBolt;
  final List<Offset> branch;
  final double flashOpacity;
  LightningBolt({
    required this.mainBolt,
    required this.branch,
    this.flashOpacity = 0,
  });
}

// ─── Sky Gradient Painter ───
class _SkyPainter extends CustomPainter {
  final List<Color> gradientColors;
  final List<Color>? prevGradientColors;
  final double crossFade; // 0=prev fully visible, 1=current fully visible

  _SkyPainter({
    required this.gradientColors,
    this.prevGradientColors,
    this.crossFade = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Draw previous gradient fading out
    if (prevGradientColors != null && crossFade < 1.0) {
      final prevPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: prevGradientColors!,
        ).createShader(rect);
      canvas.drawRect(rect, prevPaint);
    }
    // Draw current gradient
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: gradientColors,
      ).createShader(rect);
    if (prevGradientColors != null && crossFade < 1.0) {
      paint.color = Color.fromRGBO(255, 255, 255, crossFade);
    }
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_SkyPainter old) =>
      old.gradientColors != gradientColors ||
      old.crossFade != crossFade;
}

// ─── Rain Painter ───
class _RainPainter extends CustomPainter {
  final List<RainDrop> drops;
  final bool heavy;

  _RainPainter({required this.drops, this.heavy = false});

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in drops) {
      final paint = Paint()
        ..color = heavy
            ? Color.fromRGBO(160, 200, 245, d.op)
            : Color.fromRGBO(120, 175, 225, d.op)
        ..strokeWidth = heavy ? 1.4 : 0.9
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(d.x, d.y),
        Offset(d.x + sin(d.ang) * d.len, d.y + cos(d.ang) * d.len),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RainPainter old) => true; // particles move every frame
}

// ─── Snow Painter ───
class _SnowPainter extends CustomPainter {
  final List<SnowFlake> flakes;

  _SnowPainter({required this.flakes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final f in flakes) {
      final paint = Paint()..color = Color.fromRGBO(215, 235, 252, f.op);
      canvas.drawCircle(Offset(f.x, f.y), f.r, paint);
    }
  }

  @override
  bool shouldRepaint(_SnowPainter old) => true;
}

// ─── Stars Painter ───
class _StarsPainter extends CustomPainter {
  final List<Star> stars;
  final double time;

  _StarsPainter({required this.stars, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in stars) {
      // Pulse: sin-based oscillation between 0.05 and base opacity
      final phase = ((time + s.pulseOffset) / s.pulseDuration * 2 * pi);
      final pulse = (sin(phase) + 1) / 2; // 0..1
      final opacity = (s.baseOpacity * pulse).clamp(0.05, 1.0);
      final scale = 0.2 + 0.8 * pulse;
      final paint = Paint()..color = const Color(0xFFd8eaff).withValues(alpha: opacity);
      canvas.drawCircle(
        Offset(s.x * size.width / 100, s.y * size.height / 100),
        s.size * scale,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => old.time != time;
}

// ─── Firefly Painter ───
class _FireflyPainter extends CustomPainter {
  final List<Firefly> fireflies;
  final double time;

  _FireflyPainter({required this.fireflies, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    for (final f in fireflies) {
      final t = time + f.delay;
      // Drift: alternate between origin and (dx,dy)
      final driftPhase = sin(t / f.driftDur * pi);
      final x = f.x * size.width / 100 + f.dx * driftPhase;
      final y = f.y * size.height / 100 + f.dy * driftPhase;
      // Pulse: firefly-style (mostly off, brief on)
      final pulsePhase = (t % f.pulseDur) / f.pulseDur;
      double opacity;
      if (pulsePhase < 0.18 || pulsePhase > 0.82) {
        opacity = 0;
      } else if (pulsePhase < 0.42) {
        opacity = (pulsePhase - 0.18) / 0.24;
      } else if (pulsePhase > 0.58) {
        opacity = (0.82 - pulsePhase) / 0.24;
      } else {
        opacity = 1.0;
      }
      if (opacity > 0) {
        final paint = Paint()
          ..color = Color.fromRGBO(165, 220, 70, 0.75 * opacity);
        canvas.drawCircle(Offset(x, y), 1.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_FireflyPainter old) => old.time != time;
}

// ─── Haze Painter ───
class _HazePainter extends CustomPainter {
  final double alpha;
  _HazePainter({required this.alpha});

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0) return;
    final paint = Paint()..color = Color.fromRGBO(200, 220, 240, alpha);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_HazePainter old) => old.alpha != alpha;
}

// ─── Treeline Painter ───
class _TreelinePainter extends CustomPainter {
  final Color fillColor;
  final bool isPrecip;

  _TreelinePainter({
    required this.fillColor,
    this.isPrecip = false,
  });

  // Mulberry32 PRNG matching the Svelte source
  static double Function() _mulberry32(int a) {
    return () {
      a = (a + 0x6D2B79F5) & 0xFFFFFFFF;
      int t = ((a ^ (a >> 15)) * (1 | a)) & 0xFFFFFFFF;
      t = ((t + ((t ^ (t >> 7)) * (61 | t))) ^ t) & 0xFFFFFFFF;
      return ((t ^ (t >> 14)) & 0x7FFFFFFF) / 2147483648;
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final gndY = h * 0.62;
    final r = (fillColor.r * 255).round().clamp(0, 255);
    final g = (fillColor.g * 255).round().clamp(0, 255);
    final b = (fillColor.b * 255).round().clamp(0, 255);

    // Ground fill
    final groundPaint = Paint()..color = fillColor;
    canvas.drawRect(Rect.fromLTWH(0, gndY, w, h - gndY + 4), groundPaint);

    void drawTree(double x, double baseY, double treeH, double alpha) {
      final n = (6 + treeH / 20).round();
      final maxHW = treeH * 0.12;
      final tierH = treeH * 0.28;
      final paint = Paint()..color = Color.fromRGBO(r, g, b, alpha);
      for (var i = 0; i < n; i++) {
        final t = i / (n - 1);
        final apexY = baseY - treeH * (1 - t * 0.82);
        final tw = maxHW * pow(t + 0.05, 0.52);
        final path = Path()
          ..moveTo(x, apexY)
          ..lineTo(x - tw, apexY + tierH)
          ..lineTo(x + tw, apexY + tierH)
          ..close();
        canvas.drawPath(path, paint);
      }
      // Trunk
      final trW = max(1.5, treeH * 0.016);
      canvas.drawRect(
        Rect.fromLTWH(x - trW / 2, baseY - treeH * 0.09, trW, treeH * 0.09 + 3),
        paint,
      );
    }

    // Background trees (smaller, dimmer)
    var rng = _mulberry32(42);
    var px = -30.0;
    while (px < w + 40) {
      final th = 50 + rng() * 60;
      drawTree(px, gndY, th, 0.6);
      px += th * 0.19 + rng() * 26 + 5;
    }

    // Foreground trees (taller, full opacity)
    rng = _mulberry32(77);
    px = -20;
    while (px < w + 30) {
      final th = 88 + rng() * 120;
      drawTree(px, gndY, th, 1.0);
      px += th * 0.16 + rng() * 22 + 4;
    }

    // Fog gradient at base of trees
    final grad = Paint()
      ..shader = LinearGradient(
        begin: Alignment(0, -1 + 2 * gndY * 0.38 / h),
        end: Alignment(0, -1 + 2 * gndY / h),
        colors: [
          Color.fromRGBO(r, g, b, 0),
          Color.fromRGBO(r, g, b, 0.28),
        ],
      ).createShader(Rect.fromLTWH(0, gndY * 0.38, w, gndY * 0.62));
    canvas.drawRect(Rect.fromLTWH(0, gndY * 0.38, w, gndY * 0.62), grad);
  }

  @override
  bool shouldRepaint(_TreelinePainter old) =>
      old.fillColor != fillColor || old.isPrecip != isPrecip;
}

// ─── Mist Painter ───
class _MistPainter extends CustomPainter {
  final List<MistBand> bands;
  final double time;

  _MistPainter({required this.bands, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bands) {
      final phase = sin((time + b.delay) / b.duration * pi);
      final dx = 30 * phase;
      final rect = Rect.fromLTWH(
        -size.width * 0.15 + dx,
        size.height - b.bottom - b.height,
        size.width * 1.3,
        b.height,
      );
      final paint = Paint()
        ..color = b.color.withValues(alpha: b.opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 32);
      canvas.drawOval(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_MistPainter old) => old.time != time;
}

// ─── Wind Streak Painter ───
class _WindStreakPainter extends CustomPainter {
  final List<WindStreak> streaks;
  final double time;

  _WindStreakPainter({required this.streaks, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in streaks) {
      final elapsed = (time + s.delay) % s.duration;
      final progress = elapsed / s.duration;
      // Translate from -20% to 110% of width
      final translateX = (-0.2 + 1.3 * progress) * size.width;
      final opacity = progress < 0.1
          ? progress / 0.1
          : progress > 0.8
              ? (1 - progress) / 0.2
              : 1.0;
      if (opacity <= 0) continue;

      canvas.save();
      final y = s.top * size.height / 100;
      canvas.translate(translateX, y);
      canvas.rotate(s.angle * pi / 180);

      final rect = Rect.fromLTWH(0, -0.5, s.width, 1);
      final paint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            Color.fromRGBO(200, 225, 255, 0.75 * s.opacity * opacity),
            Colors.transparent,
          ],
          stops: const [0, 0.4, 1],
        ).createShader(rect);
      canvas.drawRect(rect, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_WindStreakPainter old) => old.time != time;
}

// ─── Lightning Painter ───
class _LightningPainter extends CustomPainter {
  final LightningBolt? bolt;

  _LightningPainter({this.bolt});

  @override
  void paint(Canvas canvas, Size size) {
    if (bolt == null || bolt!.mainBolt.isEmpty) return;

    // Scale bolt coordinates to canvas size (bolt generated in 1000x600 viewBox)
    Offset scale(Offset p) => Offset(
          p.dx * size.width / 1000,
          p.dy * size.height / 600,
        );

    // Main bolt glow
    final glowPaint = Paint()
      ..color = const Color(0xEBDCD2FF) // rgba(220,210,255,0.92)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final mainPath = Path();
    mainPath.moveTo(scale(bolt!.mainBolt[0]).dx, scale(bolt!.mainBolt[0]).dy);
    for (var i = 1; i < bolt!.mainBolt.length; i++) {
      final p = scale(bolt!.mainBolt[i]);
      mainPath.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(mainPath, glowPaint);

    // Main bolt thin overlay
    final thinPaint = Paint()
      ..color = const Color(0x73FFFFFF)
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(mainPath, thinPaint);

    // Branch
    if (bolt!.branch.isNotEmpty) {
      final branchPath = Path();
      branchPath.moveTo(scale(bolt!.branch[0]).dx, scale(bolt!.branch[0]).dy);
      for (var i = 1; i < bolt!.branch.length; i++) {
        final p = scale(bolt!.branch[i]);
        branchPath.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(branchPath, thinPaint);
    }
  }

  @override
  bool shouldRepaint(_LightningPainter old) => old.bolt != bolt;
}

// ─── Flash Overlay Painter ───
class _FlashPainter extends CustomPainter {
  final double opacity;
  _FlashPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final paint = Paint()..color = Color.fromRGBO(210, 200, 255, 0.85 * opacity);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_FlashPainter old) => old.opacity != opacity;
}

// ─── Sun Painter (canvas-based for blur support) ───
class _SunCorePainter extends CustomPainter {
  final double uvFactor;
  final double time;

  _SunCorePainter({required this.uvFactor, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Breathing animation: 4s cycle, scale 1.0-1.07
    final breathe = 1.0 + 0.07 * sin(time / 4 * 2 * pi);

    // Halo (outermost, large soft glow)
    final haloR = size.width * 0.5 * breathe * (1 + uvFactor * 0.55);
    final haloPaint = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0x38FFE650),
          Color(0x14FFC828),
          Color(0x00FFC828),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: haloR))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(Offset(cx, cy), haloR, haloPaint);

    // Corona: 36 alternating bright/dim wedges with blur and rotation
    final coronaR = size.width * 0.28;
    final rotation = (time / 16) * 2 * pi; // 16s full rotation
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(rotation);
    for (var i = 0; i < 36; i++) {
      final startAngle = i * (2 * pi / 36);
      final sweepAngle = 2 * pi / 36;
      final bright = i % 2 == 0;
      final paint = Paint()
        ..color = bright
            ? const Color(0x38FFE150) // rgba(255,225,80,0.22)
            : const Color(0x0AFFE150) // rgba(255,225,80,0.04)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: coronaR),
        startAngle,
        sweepAngle,
        true,
        paint,
      );
    }
    canvas.restore();

    // Core: radial gradient with blur
    final coreR = size.width * 0.14 * breathe * (1 + uvFactor * 0.35);
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0xFFfff8c0),
          Color(0xFFffd840),
          Color(0x00ffd840),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: coreR))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(Offset(cx, cy), coreR, corePaint);
  }

  @override
  bool shouldRepaint(_SunCorePainter old) =>
      old.uvFactor != uvFactor || old.time != time;
}

class SunWidget extends StatelessWidget {
  final CelestialPosition position;
  final double uvFactor;
  final double time;

  const SunWidget({
    super.key,
    required this.position,
    this.uvFactor = 0,
    this.time = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (position.alpha <= 0) return const SizedBox.shrink();

    final vw = MediaQuery.of(context).size.width;
    final vh = MediaQuery.of(context).size.height;

    final haloSize = (vw * 0.42).clamp(220.0, 400.0);

    final x = position.xPercent * vw / 100;
    final y = position.yPercent * vh / 100;

    return Positioned(
      left: x - haloSize / 2,
      top: y - haloSize / 2,
      width: haloSize,
      height: haloSize,
      child: Opacity(
        opacity: position.alpha,
        child: CustomPaint(
          size: Size(haloSize, haloSize),
          painter: _SunCorePainter(uvFactor: uvFactor, time: time),
        ),
      ),
    );
  }
}

// ─── Moon Widget ───
class MoonWidget extends StatelessWidget {
  final CelestialPosition position;
  final double phase;

  const MoonWidget({super.key, required this.position, required this.phase});

  @override
  Widget build(BuildContext context) {
    if (position.alpha <= 0) return const SizedBox.shrink();

    final vw = MediaQuery.of(context).size.width;
    final vh = MediaQuery.of(context).size.height;
    const moonSize = 180.0;

    final x = position.xPercent * vw / 100;
    final y = position.yPercent * vh / 100;

    return Positioned(
      left: x - moonSize / 2,
      top: y - moonSize / 2,
      width: moonSize,
      height: moonSize,
      child: Opacity(
        opacity: position.alpha,
        child: CustomPaint(
          size: const Size(moonSize, moonSize),
          painter: _MoonPhasePainter(phase: phase),
        ),
      ),
    );
  }
}

class _MoonPhasePainter extends CustomPainter {
  final double phase;
  _MoonPhasePainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const discR = 34.0;

    if (phase <= 0.025 || phase >= 0.975) {
      // New moon -- barely visible ring
      final paint = Paint()
        ..color = const Color(0x1E96AAC8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(cx, cy), discR, paint);
      return;
    }

    // Clip to disc
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: discR)));

    // Lit face
    final waxing = phase < 0.5;
    final tx = cos(phase * 2 * pi) * discR;
    final litPaint = Paint()..color = const Color(0xF5E8F0FF);

    final litPath = Path();
    if (waxing) {
      litPath.addArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: discR),
        -pi / 2,
        pi,
      );
      // Elliptical terminator
      final eRect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: tx.abs() * 2,
        height: discR * 2,
      );
      if (tx > 0) {
        litPath.arcTo(eRect, pi / 2, -pi, false);
      } else {
        litPath.arcTo(eRect, pi / 2, pi, false);
      }
    } else {
      litPath.addArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: discR),
        -pi / 2,
        -pi,
      );
      final eRect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: tx.abs() * 2,
        height: discR * 2,
      );
      if (tx < 0) {
        litPath.arcTo(eRect, pi / 2, pi, false);
      } else {
        litPath.arcTo(eRect, pi / 2, -pi, false);
      }
    }
    canvas.drawPath(litPath, litPaint);
    canvas.restore();

    // Glow layers
    final g1Paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0x47B4D2FF),
          const Color(0x00B4D2FF),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: discR * 1.7));
    canvas.drawCircle(Offset(cx, cy), discR * 1.7, g1Paint);

    final g2Paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0x24A0C3FF),
          const Color(0x0F8CB4FF),
          const Color(0x008CB4FF),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: size.width * 0.48));
    canvas.drawCircle(Offset(cx, cy), size.width * 0.48, g2Paint);
  }

  @override
  bool shouldRepaint(_MoonPhasePainter old) => old.phase != phase;
}

/// The compositor widget that stacks all canvas layers in z-order.
class WeatherCanvas extends StatelessWidget {
  // Sky
  final WeatherTheme skyTheme;
  final WeatherTheme? prevSkyTheme;
  final double crossFade;

  // Precipitation particles
  final List<RainDrop> rainDrops;
  final List<SnowFlake> snowFlakes;
  final bool isHeavyRain;

  // Night particles
  final List<Star> stars;
  final List<Firefly> fireflies;
  final double particleTime;

  // Mist
  final List<MistBand> mistBands;

  // Wind
  final List<WindStreak> windStreaks;

  // Haze
  final double hazeAlpha;

  // Treeline
  final Color treelineColor;
  final bool isPrecip;

  // Celestials
  final CelestialPosition sunPosition;
  final CelestialPosition moonPosition;
  final double moonPhase;
  final double uvFactor;

  // Lightning
  final LightningBolt? lightning;
  final double flashOpacity;

  const WeatherCanvas({
    super.key,
    required this.skyTheme,
    this.prevSkyTheme,
    this.crossFade = 1.0,
    this.rainDrops = const [],
    this.snowFlakes = const [],
    this.isHeavyRain = false,
    this.stars = const [],
    this.fireflies = const [],
    this.particleTime = 0,
    this.mistBands = const [],
    this.windStreaks = const [],
    this.hazeAlpha = 0,
    required this.treelineColor,
    this.isPrecip = false,
    this.sunPosition = CelestialPosition.hidden,
    this.moonPosition = CelestialPosition.hidden,
    this.moonPhase = 0,
    this.uvFactor = 0,
    this.lightning,
    this.flashOpacity = 0,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final treeHeight = size.height * 0.44;
    final gradColors = themeGradients[skyTheme] ?? themeGradients[WeatherTheme.night]!;
    final prevColors = prevSkyTheme != null ? themeGradients[prevSkyTheme!] : null;

    return SizedBox.expand(
      child: Stack(
        children: [
          // Z=0: Sky gradient
          RepaintBoundary(
            child: CustomPaint(
              size: size,
              painter: _SkyPainter(
                gradientColors: gradColors,
                prevGradientColors: prevColors,
                crossFade: crossFade,
              ),
            ),
          ),

          // Z=2: Rain/Snow canvas
          if (rainDrops.isNotEmpty)
            RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: _RainPainter(drops: rainDrops, heavy: isHeavyRain),
              ),
            ),
          if (snowFlakes.isNotEmpty)
            RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: _SnowPainter(flakes: snowFlakes),
              ),
            ),

          // Z=3: Stars, fireflies, mist, wind
          if (stars.isNotEmpty)
            RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: _StarsPainter(stars: stars, time: particleTime),
              ),
            ),
          if (fireflies.isNotEmpty)
            RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: _FireflyPainter(
                    fireflies: fireflies, time: particleTime),
              ),
            ),
          if (mistBands.isNotEmpty)
            RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: _MistPainter(bands: mistBands, time: particleTime),
              ),
            ),
          if (windStreaks.isNotEmpty)
            RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: _WindStreakPainter(
                    streaks: windStreaks, time: particleTime),
              ),
            ),

          // Z=4: Haze
          RepaintBoundary(
            child: CustomPaint(
              size: size,
              painter: _HazePainter(alpha: hazeAlpha),
            ),
          ),

          // Z=5: Sun (behind trees)
          SunWidget(position: sunPosition, uvFactor: uvFactor, time: particleTime),

          // Z=5: Moon (behind trees)
          MoonWidget(position: moonPosition, phase: moonPhase),

          // Z=6: Treeline (in front of celestials)
          Positioned(
            bottom: -2,
            left: -20,
            child: RepaintBoundary(
              child: Opacity(
                opacity: isPrecip ? 0.45 : 1.0,
                child: CustomPaint(
                  size: Size(size.width + 40, treeHeight),
                  painter: _TreelinePainter(
                    fillColor: treelineColor,
                    isPrecip: isPrecip,
                  ),
                ),
              ),
            ),
          ),

          // Z=19: Lightning flash overlay
          if (flashOpacity > 0)
            RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: _FlashPainter(opacity: flashOpacity),
              ),
            ),

          // Z=20: Lightning bolts
          if (lightning != null)
            RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: _LightningPainter(bolt: lightning),
              ),
            ),
        ],
      ),
    );
  }
}
