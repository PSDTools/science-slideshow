import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/weather_data.dart';
import '../models/arc_config.dart';
import '../logic/theme_engine.dart';
import '../services/weather_service.dart';
import 'weather_display.dart';

/// Debug/dev page for testing weather display with synthetic data.
/// Ported from the Svelte dev page.
class DevPage extends StatefulWidget {
  const DevPage({super.key});

  @override
  State<DevPage> createState() => _DevPageState();
}

class _DevPageState extends State<DevPage> with SingleTickerProviderStateMixin {
  // ── Live data ──
  bool _useLive = false;
  WeatherData? _liveData;
  late WeatherService _weatherService;

  // ── Slider state ──
  double _temp = 65;
  double _precipRate = 0;
  double _windSpeed = 0;
  double _windGust = 0;
  double _humidity = 55;
  double _dewPt = 45;
  double _pressure = 29.92;
  double _uv = 3;

  // ── Time control ──
  bool _useLiveTime = true;
  int _manualHour = 12;
  int _manualMinute = 0;
  bool _playing = false;
  double _playSpeed = 30; // simulated minutes per real second
  double _playFrac = 0; // precise accumulator
  DateTime? _lastPlayTime;
  Timer? _playTimer;

  // ── Arc config ──
  double _arcXRight = ArcConfig.defaults.xRight;
  double _arcXLeft = ArcConfig.defaults.xLeft;
  double _arcYHorizon = ArcConfig.defaults.yHorizon;
  double _arcYPeak = ArcConfig.defaults.yPeak;
  double _arcExp = ArcConfig.defaults.arcExp;
  bool _arcOpen = false;
  String? _dragging; // 'rise', 'set', 'peak', or null

  // ── Sheet controller ──
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _manualHour = now.hour;
    _manualMinute = now.minute;

    _weatherService = WeatherService(
      refreshInterval: const Duration(minutes: 1),
      onData: (data) {
        if (mounted) setState(() => _liveData = data);
      },
    );
    _weatherService.start();
  }

  @override
  void dispose() {
    _weatherService.stop();
    _playTimer?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  // ── Computed data ──
  double? get _timeOverride =>
      _useLiveTime ? null : _manualHour + _manualMinute / 60.0;

  ArcConfig get _arcConfig => ArcConfig(
        xRight: _arcXRight,
        xLeft: _arcXLeft,
        yHorizon: _arcYHorizon,
        yPeak: _arcYPeak,
        arcExp: _arcExp,
      );

  WeatherData get _syntheticData {
    final t = _temp;
    final ws = _windSpeed;
    final h = _humidity;

    double? windChill;
    if (t < 50 && ws > 3) {
      windChill = (35.74 +
              0.6215 * t -
              35.75 * pow(ws, 0.16) +
              0.4275 * t * pow(ws, 0.16))
          .roundToDouble();
    }

    double? heatIndex;
    if (t >= 80) {
      heatIndex = (-42.379 +
              2.04901523 * t +
              10.14333127 * h -
              0.22475541 * t * h -
              6.83783e-3 * t * t -
              5.481717e-2 * h * h +
              1.22874e-3 * t * t * h +
              8.5282e-4 * t * h * h -
              1.99e-6 * t * t * h * h)
          .roundToDouble();
    }

    return WeatherData(
      imperial: ImperialData(
        temp: t,
        windSpeed: ws,
        windGust: _windGust,
        windChill: windChill,
        heatIndex: heatIndex,
        precipRate: _precipRate,
        pressure: _pressure,
        dewpt: _dewPt,
        elev: 820,
      ),
      humidity: h,
      uv: _uv,
      winddir: 225,
      stationID: 'DEV-MODE',
      neighborhood: 'Test Panel',
      lat: _liveData?.lat ?? 38.9,
      lon: _liveData?.lon ?? -92.3,
      obsTimeLocal: DateTime.now().toIso8601String(),
    );
  }

  WeatherData get _displayData =>
      _useLive ? (_liveData ?? const WeatherData()) : _syntheticData;

  String get _activeTheme {
    final theme = ThemeEngine.inferTheme(_displayData, timeOverride: _timeOverride);
    return theme.name;
  }

  // ── Time playback ──
  void _togglePlay() {
    if (_playing) {
      _playing = false;
      _playTimer?.cancel();
      _playTimer = null;
      _lastPlayTime = null;
      setState(() {});
    } else {
      _useLiveTime = false;
      _playFrac = _manualHour * 60.0 + _manualMinute;
      _playing = true;
      _lastPlayTime = null;
      _playTimer = Timer.periodic(const Duration(milliseconds: 16), _onPlayTick);
      setState(() {});
    }
  }

  void _onPlayTick(Timer timer) {
    final now = DateTime.now();
    if (_lastPlayTime != null) {
      final dt = now.difference(_lastPlayTime!).inMilliseconds / 1000.0;
      _playFrac = ((_playFrac + _playSpeed * dt) % 1440 + 1440) % 1440;
      _manualHour = (_playFrac / 60).floor();
      _manualMinute = (_playFrac % 60).floor();
      setState(() {});
    }
    _lastPlayTime = now;
  }

  // ── Presets ──
  void _applyPreset({
    required double temp,
    required double windSpeed,
    required double windGust,
    required double precipRate,
    required String time,
  }) {
    final parts = time.split(':');
    setState(() {
      _temp = temp;
      _windSpeed = windSpeed;
      _windGust = windGust;
      _precipRate = precipRate;
      _useLiveTime = false;
      _manualHour = int.parse(parts[0]);
      _manualMinute = int.parse(parts[1]);
      if (_playing) {
        _playFrac = _manualHour * 60.0 + _manualMinute;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Full-screen weather display behind the sheet
          WeatherDisplay(
            arcConfig: _arcConfig,
            overrideData: _displayData,
            timeOverride: _timeOverride,
            enableTripleTap: false,
          ),

          // Draggable bottom sheet
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.45,
            minChildSize: 0.08,
            maxChildSize: 0.92,
            snap: true,
            snapSizes: const [0.08, 0.45, 0.92],
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xD1080A14), // rgba(8,10,20,0.82)
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(18)),
                  border: Border.all(
                    color: const Color(0x1AFFFFFF),
                    width: 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x8C000000),
                      blurRadius: 40,
                      offset: Offset(0, -8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildSheetContent(scrollController),
              );
            },
          ),

          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: _GlassButton(
              onTap: () => Navigator.of(context).pop(),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_ios_new, size: 14, color: Color(0xFFdde8f8)),
                  SizedBox(width: 4),
                  Text('Live',
                      style: TextStyle(
                          color: Color(0xFFdde8f8),
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetContent(ScrollController scrollController) {
    final textStyle = GoogleFonts.outfit(
      color: const Color(0xFFdde8f8),
      fontSize: 13,
    );
    final subStyle = GoogleFonts.outfit(
      color: const Color(0x99C8DCFF),
      fontSize: 11,
      letterSpacing: 0.4,
    );
    final labelStyle = GoogleFonts.outfit(
      color: const Color(0x61C8DCFF),
      fontSize: 10,
      letterSpacing: 2,
    );

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      children: [
        // Drag handle
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0x3DFFFFFF),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Header
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Weather Tester',
            style: GoogleFonts.outfit(
              color: const Color(0xFFdde8f8),
              fontSize: 15,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ),

        // Live toggle
        _buildToggleRow('Use live weather', _useLive, (v) {
          setState(() => _useLive = v);
        }, textStyle),

        if (!_useLive) ...[
          _divider(),

          // Time controls
          _buildToggleRow('Live time', _useLiveTime, (v) {
            setState(() => _useLiveTime = v);
          }, textStyle),

          if (!_useLiveTime) ...[
            const SizedBox(height: 4),
            // Time display and picker
            _buildTimeRow(subStyle),
            const SizedBox(height: 4),
            // Play controls
            _buildPlayRow(subStyle),
            const SizedBox(height: 4),
            // Speed slider
            _buildSliderRow(
              'Speed: ${_playSpeed.round()} min/s  --  full day in ${(1440 / _playSpeed).round()}s',
              _playSpeed,
              1,
              120,
              1,
              (v) => setState(() => _playSpeed = v),
              subStyle,
            ),
          ],

          _divider(),

          // Weather sliders
          _buildSliderRow(
            'Temp: ${_temp.round()}\u00B0F',
            _temp, -10, 115, 1,
            (v) => setState(() => _temp = v),
            subStyle,
          ),
          _buildSliderRow(
            'Precip: ${_precipRate.toStringAsFixed(2)} in/hr',
            _precipRate, 0, 0.5, 0.01,
            (v) => setState(() => _precipRate = v),
            subStyle,
          ),
          _buildSliderRow(
            'Wind: ${_windSpeed.round()} mph',
            _windSpeed, 0, 80, 1,
            (v) => setState(() => _windSpeed = v),
            subStyle,
          ),
          _buildSliderRow(
            'Gust: ${_windGust.round()} mph',
            _windGust, 0, 80, 1,
            (v) => setState(() => _windGust = v),
            subStyle,
          ),
          _buildSliderRow(
            'Humidity: ${_humidity.round()}%',
            _humidity, 0, 100, 1,
            (v) => setState(() => _humidity = v),
            subStyle,
          ),
          _buildSliderRow(
            'Dew Pt: ${_dewPt.round()}\u00B0F',
            _dewPt, -20, 80, 1,
            (v) => setState(() => _dewPt = v),
            subStyle,
          ),
          _buildSliderRow(
            'Pressure: ${_pressure.toStringAsFixed(2)}"',
            _pressure, 28.0, 31.5, 0.01,
            (v) => setState(() => _pressure = v),
            subStyle,
          ),
          _buildSliderRow(
            'UV: ${_uv.round()}',
            _uv, 0, 11, 1,
            (v) => setState(() => _uv = v),
            subStyle,
          ),

          _divider(),

          // Quick presets
          Text('QUICK PRESETS', style: labelStyle),
          const SizedBox(height: 6),
          _buildPresets(),
        ],

        _divider(),

        // Arc editor
        _buildArcSection(subStyle, labelStyle),

        _divider(),

        // Theme badge
        Row(
          children: [
            Text('Theme: ', style: subStyle),
            Text(
              _activeTheme,
              style: GoogleFonts.outfit(
                color: const Color(0xFFa8d0f8),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // ── Build helpers ──

  Widget _divider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: const Color(0x12FFFFFF),
    );
  }

  Widget _buildToggleRow(String label, bool value, ValueChanged<bool> onChanged,
      TextStyle style) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF7AB8F5),
            activeTrackColor: const Color(0x557AB8F5),
            inactiveThumbColor: const Color(0xFF888888),
            inactiveTrackColor: const Color(0x33FFFFFF),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRow(TextStyle subStyle) {
    final timeStr =
        '${_manualHour.toString().padLeft(2, '0')}:${_manualMinute.toString().padLeft(2, '0')}';
    return Row(
      children: [
        Expanded(
          child: Text('Time: $timeStr', style: subStyle),
        ),
        _GlassButton(
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: _manualHour, minute: _manualMinute),
              builder: (context, child) {
                return Theme(
                  data: ThemeData.dark().copyWith(
                    colorScheme: const ColorScheme.dark(
                      primary: Color(0xFF7AB8F5),
                      surface: Color(0xFF1a1e2e),
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (picked != null) {
              setState(() {
                _manualHour = picked.hour;
                _manualMinute = picked.minute;
                if (_playing) {
                  _playFrac = _manualHour * 60.0 + _manualMinute;
                }
              });
            }
          },
          child: Text('Set Time',
              style: GoogleFonts.outfit(
                  color: const Color(0xFFc8daf4), fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildPlayRow(TextStyle subStyle) {
    return Row(
      children: [
        _GlassButton(
          onTap: _togglePlay,
          highlight: _playing,
          child: Icon(
            _playing ? Icons.pause : Icons.play_arrow,
            size: 18,
            color: _playing
                ? const Color(0xFFa8d4ff)
                : const Color(0xFFc8daf4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _playing ? 'Playing...' : 'Paused',
          style: subStyle,
        ),
      ],
    );
  }

  Widget _buildSliderRow(
    String label,
    double value,
    double min,
    double max,
    double step,
    ValueChanged<double> onChanged,
    TextStyle subStyle,
  ) {
    // Calculate divisions from step
    final divisions = ((max - min) / step).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: subStyle),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF7AB8F5),
              inactiveTrackColor: const Color(0x33FFFFFF),
              thumbColor: const Color(0xFFdde8f8),
              overlayColor: const Color(0x227AB8F5),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresets() {
    final presets = [
      ('Night', 58.0, 4.0, 6.0, 0.0, '02:00'),
      ('Day', 72.0, 8.0, 12.0, 0.0, '12:00'),
      ('Rise', 62.0, 3.0, 5.0, 0.0, '06:30'),
      ('Golden', 68.0, 5.0, 8.0, 0.0, '18:00'),
      ('Rain', 55.0, 10.0, 18.0, 0.04, '14:00'),
      ('Storm', 60.0, 25.0, 38.0, 0.12, '14:00'),
      ('Snow', 28.0, 8.0, 14.0, 0.05, '14:00'),
      ('Sunset', 66.0, 4.0, 7.0, 0.0, '19:30'),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: presets.map((p) {
        return _PresetChip(
          label: p.$1,
          onTap: () => _applyPreset(
            temp: p.$2,
            windSpeed: p.$3,
            windGust: p.$4,
            precipRate: p.$5,
            time: p.$6,
          ),
        );
      }).toList(),
    );
  }

  // ── Arc editor ──

  Widget _buildArcSection(TextStyle subStyle, TextStyle labelStyle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _arcOpen = !_arcOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Arc Editor',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFFc8daf4),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _arcOpen ? '\u2212' : '+',
                  style: const TextStyle(
                    color: Color(0xFFc8daf4),
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_arcOpen) ...[
          const SizedBox(height: 6),
          // Arc preview using CustomPainter with gesture detection
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = width * 130 / 100;
              return GestureDetector(
                onPanStart: (details) =>
                    _onArcPanStart(details, width, height),
                onPanUpdate: (details) =>
                    _onArcPanUpdate(details, width, height),
                onPanEnd: (_) => _dragging = null,
                child: Container(
                  width: width,
                  height: height,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0x1AFFFFFF),
                    ),
                    borderRadius: BorderRadius.circular(4),
                    color: const Color(0x26000000),
                  ),
                  child: CustomPaint(
                    size: Size(width, height),
                    painter: _ArcEditorPainter(
                      xRight: _arcXRight,
                      xLeft: _arcXLeft,
                      yHorizon: _arcYHorizon,
                      yPeak: _arcYPeak,
                      arcExp: _arcExp,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          _buildSliderRow(
            'Exponent: ${_arcExp.toStringAsFixed(2)} (flat \u2190 \u2192 pointy)',
            _arcExp, 0.20, 2.0, 0.05,
            (v) => setState(() => _arcExp = v),
            subStyle,
          ),
          Text(
            'xR=${_arcXRight.round()} xL=${_arcXLeft.round()} yH=${_arcYHorizon.round()} yP=${_arcYPeak.round()}',
            style: GoogleFonts.outfit(
              color: const Color(0x61C8DCFF),
              fontSize: 10,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _PresetChip(
                label: 'Reset defaults',
                onTap: () {
                  setState(() {
                    _arcXRight = ArcConfig.defaults.xRight;
                    _arcXLeft = ArcConfig.defaults.xLeft;
                    _arcYHorizon = ArcConfig.defaults.yHorizon;
                    _arcYPeak = ArcConfig.defaults.yPeak;
                    _arcExp = ArcConfig.defaults.arcExp;
                  });
                },
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _onArcPanStart(DragStartDetails details, double width, double height) {
    final x = details.localPosition.dx / width * 100;
    final y = details.localPosition.dy / height * 130;

    // Check which handle is closest
    final riseD = _dist(x, y, _arcXRight, _arcYHorizon);
    final setD = _dist(x, y, _arcXLeft, _arcYHorizon);
    final peakX = (_arcXRight + _arcXLeft) / 2;
    final peakD = _dist(x, y, peakX, _arcYPeak);

    const threshold = 12.0;
    if (riseD < threshold && riseD <= setD && riseD <= peakD) {
      _dragging = 'rise';
    } else if (setD < threshold && setD <= peakD) {
      _dragging = 'set';
    } else if (peakD < threshold) {
      _dragging = 'peak';
    }
  }

  void _onArcPanUpdate(DragUpdateDetails details, double width, double height) {
    if (_dragging == null) return;
    final x = details.localPosition.dx / width * 100;
    final y = details.localPosition.dy / height * 130;

    setState(() {
      if (_dragging == 'rise') {
        _arcXRight = x.clamp(55, 100).roundToDouble();
        _arcYHorizon = y.clamp(80, 145).roundToDouble();
      } else if (_dragging == 'set') {
        _arcXLeft = x.clamp(0, 45).roundToDouble();
        _arcYHorizon = y.clamp(80, 145).roundToDouble();
      } else if (_dragging == 'peak') {
        _arcYPeak = y.clamp(5, 90).roundToDouble();
      }
    });
  }

  double _dist(double x1, double y1, double x2, double y2) {
    return sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2));
  }
}

// ── Arc editor CustomPainter ──

class _ArcEditorPainter extends CustomPainter {
  final double xRight, xLeft, yHorizon, yPeak, arcExp;

  _ArcEditorPainter({
    required this.xRight,
    required this.xLeft,
    required this.yHorizon,
    required this.yPeak,
    required this.arcExp,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Coordinate mapping: viewBox is 0-100 x, 0-130 y
    double sx(double vx) => vx / 100 * w;
    double sy(double vy) => vy / 130 * h;

    // Visible screen area (light blue tint)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, sy(100)),
      Paint()..color = const Color(0x0F78B8F5),
    );

    // Below-screen area (dark)
    canvas.drawRect(
      Rect.fromLTWH(0, sy(100), w, sy(30)),
      Paint()..color = const Color(0x4D000000),
    );

    // Dashed horizon line at y=100
    final horizonPaint = Paint()
      ..color = const Color(0x40FFFFFF)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    double dx = 0;
    while (dx < w) {
      canvas.drawLine(
        Offset(dx, sy(100)),
        Offset((dx + dashWidth).clamp(0, w), sy(100)),
        horizonPaint,
      );
      dx += dashWidth + dashSpace;
    }

    // "screen edge" label
    final labelPainter = TextPainter(
      text: TextSpan(
        text: 'screen edge',
        style: TextStyle(
          color: const Color(0x47FFFFFF),
          fontSize: h * 0.028,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(canvas, Offset(sx(1), sy(96)));

    // Arc curve as polyline
    final arcPath = Path();
    const steps = 40;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = xRight - (xRight - xLeft) * t;
      final y =
          yHorizon - (yHorizon - yPeak) * pow(sin(pi * t), arcExp);
      final px = sx(x);
      final py = sy(y);
      if (i == 0) {
        arcPath.moveTo(px, py);
      } else {
        arcPath.lineTo(px, py);
      }
    }
    canvas.drawPath(
      arcPath,
      Paint()
        ..color = const Color(0xBFFFC850)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Handle radius
    final handleR = w * 0.028;
    final handleStroke = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    // Rise handle (orange)
    canvas.drawCircle(
      Offset(sx(xRight), sy(yHorizon)),
      handleR,
      Paint()..color = const Color(0xE6FFA028),
    );
    canvas.drawCircle(
      Offset(sx(xRight), sy(yHorizon)),
      handleR,
      handleStroke,
    );
    // Rise label
    final riseLbl = TextPainter(
      text: TextSpan(
        text: 'Rise',
        style: TextStyle(
          color: const Color(0xD9FFD264),
          fontSize: h * 0.028,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    riseLbl.paint(
      canvas,
      Offset(sx(xRight) - riseLbl.width - handleR - 2, sy(yHorizon) - handleR - riseLbl.height),
    );

    // Set handle (dark orange)
    canvas.drawCircle(
      Offset(sx(xLeft), sy(yHorizon)),
      handleR,
      Paint()..color = const Color(0xE6FF7828),
    );
    canvas.drawCircle(
      Offset(sx(xLeft), sy(yHorizon)),
      handleR,
      handleStroke,
    );
    // Set label
    final setLbl = TextPainter(
      text: TextSpan(
        text: 'Set',
        style: TextStyle(
          color: const Color(0xD9FFB450),
          fontSize: h * 0.028,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    setLbl.paint(
      canvas,
      Offset(sx(xLeft) + handleR + 2, sy(yHorizon) - handleR - setLbl.height),
    );

    // Peak handle (yellow)
    final peakX = (xRight + xLeft) / 2;
    canvas.drawCircle(
      Offset(sx(peakX), sy(yPeak)),
      handleR,
      Paint()..color = const Color(0xE6FFF064),
    );
    canvas.drawCircle(
      Offset(sx(peakX), sy(yPeak)),
      handleR,
      handleStroke,
    );
    // Peak label
    final peakLbl = TextPainter(
      text: TextSpan(
        text: 'Peak',
        style: TextStyle(
          color: const Color(0xD9FFF596),
          fontSize: h * 0.028,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    peakLbl.paint(
      canvas,
      Offset(sx(peakX) + handleR + 2, sy(yPeak) - peakLbl.height - 2),
    );
  }

  @override
  bool shouldRepaint(_ArcEditorPainter old) =>
      old.xRight != xRight ||
      old.xLeft != xLeft ||
      old.yHorizon != yHorizon ||
      old.yPeak != yPeak ||
      old.arcExp != arcExp;
}

// ── Reusable glass button ──

class _GlassButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  final bool highlight;

  const _GlassButton({
    required this.onTap,
    required this.child,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: highlight
              ? const Color(0x3878B8F5)
              : const Color(0x14FFFFFF),
          border: Border.all(
            color: highlight
                ? const Color(0x6678B8F5)
                : const Color(0x1FFFFFFF),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );
  }
}

// ── Preset chip ──

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0x12FFFFFF),
          border: Border.all(color: const Color(0x1AFFFFFF)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: const Color(0xFFc8daf4),
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
