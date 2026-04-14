import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../models/weather_data.dart';
import '../models/weather_theme.dart';
import '../models/arc_config.dart';
import '../logic/theme_engine.dart';
import '../logic/celestial_engine.dart';
import '../services/weather_service.dart';
import '../services/alert_service.dart';

import 'weather_canvas.dart';
import 'clock_widget.dart';
import 'condition_label.dart';
import 'temperature_hero.dart';
import 'data_strip.dart';
import 'meta_bar.dart';
import 'alert_bar.dart';

/// Main orchestrator widget for the weather display.
/// Manages animations, data fetching, theme transitions, particles, and celestials.
class WeatherDisplay extends StatefulWidget {
  final ArcConfig arcConfig;

  /// When non-null, this data is used instead of fetching from the weather service.
  final WeatherData? overrideData;

  /// When non-null, this fractional hour (0-24) is passed to the theme engine
  /// instead of using the real clock.
  final double? timeOverride;

  /// Whether triple-tap to open the dev page is enabled.
  final bool enableTripleTap;

  const WeatherDisplay({
    super.key,
    this.arcConfig = const ArcConfig(),
    this.overrideData,
    this.timeOverride,
    this.enableTripleTap = true,
  });

  @override
  State<WeatherDisplay> createState() => _WeatherDisplayState();
}

class _WeatherDisplayState extends State<WeatherDisplay>
    with TickerProviderStateMixin {
  // ── Data ──
  WeatherData? _data;
  WeatherAlert? _alert;
  late WeatherService _weatherService;

  // ── Theme ──
  WeatherTheme _precipTheme = WeatherTheme.night;
  WeatherTheme _skyTheme = WeatherTheme.night;
  WeatherTheme? _prevSkyTheme;
  late LerpableThemeColors _colors;
  LerpableThemeColors? _prevColors;

  // ── Theme transition animation (3s color lerp) ──
  late AnimationController _themeTransCtrl;
  double _themeLerp = 1.0;

  // ── 60fps render loop ──
  late AnimationController _renderCtrl;
  double _particleTime = 0;
  double _snowT = 0;

  // ── Celestial ──
  late CelestialEngine _celestialEngine;
  CelestialPosition _sunPos = CelestialPosition.hidden;
  CelestialPosition _moonPos = CelestialPosition.hidden;
  double _moonPhase = 0;
  double _uvFactor = 0;

  // ── Particles ──
  List<RainDrop> _rainDrops = [];
  List<SnowFlake> _snowFlakes = [];
  bool _isHeavyRain = false;
  List<Star> _stars = [];
  List<Firefly> _fireflies = [];
  List<MistBand> _mistBands = [];
  List<WindStreak> _windStreaks = [];
  double _hazeAlpha = 0;

  // ── Lightning ──
  LightningBolt? _lightning;
  double _flashOpacity = 0;
  Timer? _lightningTimer;
  Timer? _flashTimer;

  // ── Cross-fade ──
  late AnimationController _crossFadeCtrl;

  final _rng = Random();

  @override
  void initState() {
    super.initState();

    _celestialEngine = CelestialEngine(arcConfig: widget.arcConfig);
    _colors = themeColorMap[WeatherTheme.night]!;

    // Theme transition: 3s
    _themeTransCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addListener(() {
        setState(() {
          _themeLerp = _themeTransCtrl.value;
        });
      });

    // Sky cross-fade: 3s
    _crossFadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
      value: 1.0,
    );

    // 60fps render loop
    _renderCtrl = AnimationController(
      vsync: this,
      duration: const Duration(days: 365), // effectively infinite
    )..addListener(_onFrame);
    _renderCtrl.forward();

    // Weather data service
    _weatherService = WeatherService(
      refreshInterval: const Duration(minutes: 10),
      onData: _onWeatherData,
    );
    // Only fetch live data if no override is provided
    if (widget.overrideData == null) {
      _weatherService.start();
    } else {
      // Defer override data until after first frame (MediaQuery not available in initState)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onWeatherData(widget.overrideData!);
      });
    }
  }

  @override
  void didUpdateWidget(covariant WeatherDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // React to override data changes from the dev page
    if (widget.overrideData != null &&
        widget.overrideData != oldWidget.overrideData) {
      _onWeatherData(widget.overrideData!);
    }
    // Update celestial engine if arc config changed
    if (widget.arcConfig != oldWidget.arcConfig) {
      _celestialEngine = CelestialEngine(arcConfig: widget.arcConfig);
    }
  }

  @override
  void dispose() {
    _renderCtrl.dispose();
    _themeTransCtrl.dispose();
    _crossFadeCtrl.dispose();
    _weatherService.stop();
    _lightningTimer?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }

  // ── Frame callback (60fps) ──
  void _onFrame() {
    if (!mounted) return;
    final dt = 1 / 60; // approximately
    _particleTime += dt;

    // Advance rain drops
    if (_rainDrops.isNotEmpty) {
      final w = MediaQuery.of(context).size.width;
      final h = MediaQuery.of(context).size.height;
      for (final d in _rainDrops) {
        d.y += d.spd;
        d.x += sin(d.ang) * d.spd;
        if (d.y > h) {
          d.y = -d.len;
          d.x = _rng.nextDouble() * (w + 200) - 100;
        }
      }
    }

    // Advance snowflakes
    if (_snowFlakes.isNotEmpty) {
      _snowT += 0.008;
      final w = MediaQuery.of(context).size.width;
      final h = MediaQuery.of(context).size.height;
      for (final f in _snowFlakes) {
        f.y += f.spd;
        f.x += f.drift + sin(_snowT + f.off) * 0.5;
        if (f.y > h + f.r) {
          f.y = -f.r;
          f.x = _rng.nextDouble() * w;
        }
        if (f.x > w + f.r) f.x = -f.r;
        if (f.x < -f.r) f.x = w + f.r;
      }
    }

    // Reposition celestials every frame
    _updateCelestials();

    setState(() {}); // trigger rebuild
  }

  // ── Weather data callback ──
  void _onWeatherData(WeatherData data) {
    setState(() {
      _data = data;
    });
    _applyTheme(data);
    _fetchAlerts(data);
  }

  // ── Theme engine ──
  void _applyTheme(WeatherData data) {
    final newPrecipTheme = ThemeEngine.inferTheme(data, timeOverride: widget.timeOverride);
    final newSkyTheme = ThemeEngine.inferSkyTheme(data, timeOverride: widget.timeOverride);
    final isPrecip = ThemeEngine.isPrecip(newPrecipTheme);

    // Haze
    final humidity = data.humidity ?? 0;
    _hazeAlpha = humidity > 40 ? ((humidity - 40) / 60).clamp(0, 1) * 0.2 : 0;

    // UV factor
    _uvFactor = data.uv != null ? (data.uv! / 11).clamp(0, 1).toDouble() : 0;

    // Theme color transition
    if (newSkyTheme != _skyTheme) {
      _prevSkyTheme = _skyTheme;
      _prevColors = _currentLerpedColors;
      _crossFadeCtrl.forward(from: 0);
    }

    final newColors = themeColorMap[isPrecip ? newSkyTheme : newPrecipTheme] ??
        themeColorMap[newSkyTheme]!;

    if (newColors != _colors) {
      _prevColors = _currentLerpedColors;
      _themeTransCtrl.forward(from: 0);
    }

    _precipTheme = newPrecipTheme;
    _skyTheme = newSkyTheme;
    _colors = newColors;

    // Rebuild particles
    _rebuildParticles(newPrecipTheme, newSkyTheme, data);
  }

  LerpableThemeColors get _currentLerpedColors {
    if (_prevColors != null && _themeLerp < 1.0) {
      return LerpableThemeColors.lerp(_prevColors!, _colors, _themeLerp);
    }
    return _colors;
  }

  // ── Particles ──
  void _rebuildParticles(WeatherTheme precipTheme, WeatherTheme skyTheme, WeatherData data) {
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;
    final windSpeed = data.imperial.windSpeed ?? 0;
    final isPrecip = ThemeEngine.isPrecip(precipTheme);

    // Clear all
    _rainDrops = [];
    _snowFlakes = [];
    _stars = [];
    _fireflies = [];
    _mistBands = [];
    _windStreaks = [];
    _lightning = null;
    _lightningTimer?.cancel();
    _flashTimer?.cancel();
    _flashOpacity = 0;
    _isHeavyRain = false;

    if (precipTheme == WeatherTheme.rain || precipTheme == WeatherTheme.storm) {
      final heavy = precipTheme == WeatherTheme.storm;
      _isHeavyRain = heavy;
      final count = heavy ? 320 : 150;
      final angle = heavy ? 18.0 : 7.0;
      _rainDrops = List.generate(count, (_) {
        return RainDrop(
          x: _rng.nextDouble() * (w + 200) - 100,
          y: _rng.nextDouble() * h,
          len: heavy ? 22 + _rng.nextDouble() * 20 : 14 + _rng.nextDouble() * 12,
          spd: heavy ? 18 + _rng.nextDouble() * 14 : 11 + _rng.nextDouble() * 8,
          op: 0.18 + _rng.nextDouble() * 0.48,
          ang: (angle + (_rng.nextDouble() - 0.5) * 6) * pi / 180,
        );
      });
      if (heavy) _startLightning();
    } else if (precipTheme == WeatherTheme.snow) {
      _snowFlakes = List.generate(200, (_) {
        return SnowFlake(
          x: _rng.nextDouble() * w,
          y: _rng.nextDouble() * h,
          r: 1.2 + _rng.nextDouble() * 4.5,
          spd: 0.4 + _rng.nextDouble() * 1.1,
          drift: (_rng.nextDouble() - 0.5) * 0.5,
          op: 0.35 + _rng.nextDouble() * 0.55,
          off: _rng.nextDouble() * pi * 2,
        );
      });
    } else if (skyTheme == WeatherTheme.night) {
      // Stars
      _stars = List.generate(115, (_) {
        return Star(
          x: _rng.nextDouble() * 100,
          y: _rng.nextDouble() * 72,
          size: 0.5 + _rng.nextDouble() * 2.4,
          baseOpacity: 0.12 + _rng.nextDouble() * 0.88,
          pulseDuration: 1.5 + _rng.nextDouble() * 5,
          pulseOffset: _rng.nextDouble() * 7,
        );
      });
      // Fireflies
      _fireflies = List.generate(22, (_) {
        return Firefly(
          x: 8 + _rng.nextDouble() * 84,
          y: 22 + _rng.nextDouble() * 55,
          driftDur: 3.5 + _rng.nextDouble() * 6.5,
          pulseDur: 2.2 + _rng.nextDouble() * 4.2,
          dx: _rng.nextDouble() * 130 - 65,
          dy: _rng.nextDouble() * 90 - 45,
          delay: _rng.nextDouble() * 9,
        );
      });
    } else if (skyTheme == WeatherTheme.rise) {
      _buildMist(235, 142, 68, h);
    } else if (skyTheme == WeatherTheme.golden) {
      _buildMist(215, 132, 48, h);
    } else if (skyTheme == WeatherTheme.sunset) {
      _buildMist(195, 60, 30, h);
    }

    // Wind streaks (skip during precip)
    if (!isPrecip && windSpeed >= 5) {
      final speedFactor = (windSpeed / 30).clamp(0.0, 1.0);
      final count = (windSpeed / 2.5).round().clamp(2, 22);
      _windStreaks = List.generate(count, (_) {
        final len = 60 + _rng.nextDouble() * 120 + speedFactor * 80;
        final dur = 1.8 - speedFactor * 1.1 + _rng.nextDouble() * 0.9;
        final ang = -(8 + _rng.nextDouble() * 12);
        return WindStreak(
          top: _rng.nextDouble() * 90,
          left: -10 + _rng.nextDouble() * 80,
          width: len,
          duration: dur,
          angle: ang,
          opacity: 0.06 + _rng.nextDouble() * 0.18 * speedFactor,
          delay: _rng.nextDouble() * dur,
        );
      });
    }
  }

  void _buildMist(int r, int g, int b, double screenHeight) {
    _mistBands = List.generate(6, (i) {
      return MistBand(
        bottom: i * 6.5 + _rng.nextDouble() * 10,
        height: 55 + _rng.nextDouble() * 85,
        opacity: 0.024 + _rng.nextDouble() * 0.036,
        duration: 8 + _rng.nextDouble() * 12,
        delay: _rng.nextDouble() * 10,
        color: Color.fromRGBO(r, g, b, 1),
      );
    });
  }

  // ── Lightning ──
  void _startLightning() {
    _scheduleLightning(0.8 + _rng.nextDouble() * 2.2);
  }

  void _scheduleLightning(double delaySec) {
    _lightningTimer?.cancel();
    _lightningTimer = Timer(
      Duration(milliseconds: (delaySec * 1000).round()),
      _strike,
    );
  }

  void _strike() {
    // Generate bolt
    double startX = 300 + _rng.nextDouble() * 400;
    double x = startX, y = 0;
    final pts = <Offset>[Offset(x, y)];
    while (y < 490) {
      y += 28 + _rng.nextDouble() * 44;
      x += (_rng.nextDouble() - 0.48) * 92;
      pts.add(Offset(x, y));
    }

    // Branch
    final bi = (pts.length * 0.35 + _rng.nextDouble() * pts.length * 0.3).floor();
    double bx = pts[bi].dx, by = pts[bi].dy;
    final branch = <Offset>[Offset(bx, by)];
    for (var i = 0; i < 4; i++) {
      bx += (_rng.nextDouble() - 0.45) * 72;
      by += 24 + _rng.nextDouble() * 40;
      branch.add(Offset(bx, by));
    }

    setState(() {
      _lightning = LightningBolt(mainBolt: pts, branch: branch);
      _flashOpacity = 0.62;
    });

    // Flash sequence
    final hasSecond = _rng.nextDouble() > 0.4;
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 72), () {
      setState(() => _flashOpacity = 0);
      if (hasSecond) {
        _flashTimer = Timer(const Duration(milliseconds: 130), () {
          setState(() => _flashOpacity = 0.26);
          _flashTimer = Timer(const Duration(milliseconds: 45), () {
            setState(() {
              _flashOpacity = 0;
              _lightning = null;
            });
          });
        });
      } else {
        setState(() => _lightning = null);
      }
    });

    // Schedule next
    _scheduleLightning(3.5 + _rng.nextDouble() * 9);
  }

  // ── Celestials ──
  void _updateCelestials() {
    if (_data?.lat == null || _data?.lon == null) return;
    final isPrecip = ThemeEngine.isPrecip(_precipTheme);
    final result = _celestialEngine.positionCelestialBodies(
      lat: _data!.lat!,
      lon: _data!.lon!,
      isPrecip: isPrecip,
      timeOverride: widget.timeOverride,
    );
    _sunPos = result.sun;
    _moonPos = result.moon;
    _moonPhase = result.moonPhase;
  }

  // ── Alerts ──
  void _fetchAlerts(WeatherData data) async {
    if (data.lat == null || data.lon == null) return;
    final alert = await AlertService.fetchAlerts(data.lat!, data.lon!);
    if (mounted) {
      setState(() {
        _alert = alert;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _currentLerpedColors;
    final isPrecip = ThemeEngine.isPrecip(_precipTheme);
    final treeColor = treelineFills[_skyTheme] ?? const Color(0xFF0e1520);
    final conditionLabel = themeLabels[_precipTheme] ?? themeLabels[_skyTheme] ?? '';

    final temp = _data?.imperial.temp;
    final hi = _data?.imperial.heatIndex;
    final wc = _data?.imperial.windChill;

    return Scaffold(
      body: _TripleTapDetector(
        enabled: widget.enableTripleTap,
        onTripleTap: () {
          Navigator.of(context).pushNamed('/dev');
        },
        child: Stack(
        children: [
          // Background canvas with all visual layers
          WeatherCanvas(
            skyTheme: _skyTheme,
            prevSkyTheme: _prevSkyTheme,
            crossFade: _crossFadeCtrl.value,
            rainDrops: _rainDrops,
            snowFlakes: _snowFlakes,
            isHeavyRain: _isHeavyRain,
            stars: _stars,
            fireflies: _fireflies,
            particleTime: _particleTime,
            mistBands: _mistBands,
            windStreaks: _windStreaks,
            hazeAlpha: _hazeAlpha,
            treelineColor: treeColor,
            isPrecip: isPrecip,
            sunPosition: _sunPos,
            moonPosition: _moonPos,
            moonPhase: _moonPhase,
            uvFactor: _uvFactor,
            lightning: _lightning,
            flashOpacity: _flashOpacity,
          ),

          // Alert bar (z=30)
          AlertBar(alert: _alert),

          // Clock (z=11)
          ClockWidget(
            textColor: colors.text,
            subColor: colors.sub,
            hasAlert: _alert != null,
          ),

          // Center content: condition + temperature (z=10)
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).size.height * 0.18,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ConditionLabel(
                    text: conditionLabel,
                    accentColor: colors.accent,
                  ),
                  TemperatureHero(
                    temperature: temp?.round(),
                    heatIndex: hi?.round(),
                    windChill: wc?.round(),
                    tempColor: colors.tempCol,
                    glowColor: colors.glowCol,
                    subColor: colors.sub,
                  ),
                ],
              ),
            ),
          ),

          // Data strip (z=11)
          DataStrip(
            data: _data,
            textColor: colors.text,
            subColor: colors.sub,
          ),

          // Meta bar (z=11)
          MetaBar(
            data: _data,
            subColor: colors.sub,
          ),
        ],
      ),
      ),
    );
  }
}

/// Detects triple-taps by counting taps within a time window.
class _TripleTapDetector extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTripleTap;
  final Widget child;

  const _TripleTapDetector({
    required this.enabled,
    required this.onTripleTap,
    required this.child,
  });

  @override
  State<_TripleTapDetector> createState() => _TripleTapDetectorState();
}

class _TripleTapDetectorState extends State<_TripleTapDetector> {
  int _tapCount = 0;
  DateTime _lastTap = DateTime(2000);

  void _onTap() {
    if (!widget.enabled) return;
    final now = DateTime.now();
    if (now.difference(_lastTap).inMilliseconds > 500) {
      _tapCount = 0;
    }
    _tapCount++;
    _lastTap = now;
    if (_tapCount >= 3) {
      _tapCount = 0;
      widget.onTripleTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _onTap,
      child: widget.child,
    );
  }
}
