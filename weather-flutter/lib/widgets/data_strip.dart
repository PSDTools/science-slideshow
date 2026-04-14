import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../logic/severity.dart';
import '../models/weather_data.dart';

/// Bottom horizontal row of weather data with severity color coding.
class DataStrip extends StatelessWidget {
  final WeatherData? data;
  final Color textColor;
  final Color subColor;

  const DataStrip({
    super.key,
    this.data,
    required this.textColor,
    required this.subColor,
  });

  static const _lowColor = Color(0xFF82c4f8);
  static const _highColor = Color(0xFFf8c060);
  static const _extremeColor = Color(0xFFf87070);

  Color _sevColor(Severity sev) {
    return switch (sev) {
      Severity.low => _lowColor,
      Severity.mid => textColor,
      Severity.high => _highColor,
      Severity.extreme => _extremeColor,
    };
  }

  List<Shadow>? _sevShadows(Severity sev) {
    if (sev == Severity.high) {
      return [Shadow(color: const Color(0x8CF09618), blurRadius: 14)];
    }
    if (sev == Severity.extreme) {
      return [Shadow(color: const Color(0xA6F03C28), blurRadius: 16)];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final vw = MediaQuery.of(context).size.width;
    final vh = MediaQuery.of(context).size.height;
    final imp = data?.imperial ?? const ImperialData();

    // bottom: clamp(22px, 5.5vh, 52px)
    final bottomPad = (vh * 0.055).clamp(22.0, 52.0);
    // value font: clamp(18px, 2.6vw, 28px)
    final valSize = (vw * 0.026).clamp(18.0, 28.0);
    // label font: clamp(8px, 1.1vw, 12px)
    final labelSize = (vw * 0.011).clamp(8.0, 12.0);
    // horizontal padding: clamp(12px, 2.2vw, 28px)
    final hPad = (vw * 0.022).clamp(12.0, 28.0);

    final items = <_DatumData>[
      _DatumData(
        label: 'Humidity',
        value: data?.humidity != null ? '${data!.humidity!.round()}' : '--',
        unit: '%',
        severity: data?.humidity != null ? humiditySeverity(data!.humidity!) : Severity.mid,
      ),
      _DatumData(
        label: 'Wind',
        value: imp.windSpeed != null ? '${imp.windSpeed!.round()}' : '--',
        unit: ' mph',
        suffix: data?.winddir != null ? ' ${windDirection(data!.winddir!)}' : '',
        severity: imp.windSpeed != null ? windSeverity(imp.windSpeed!) : Severity.mid,
      ),
      _DatumData(
        label: 'Gust',
        value: imp.windGust != null ? '${imp.windGust!.round()}' : '--',
        unit: ' mph',
        severity: imp.windGust != null ? windSeverity(imp.windGust!) : Severity.mid,
      ),
      _DatumData(
        label: 'Pressure',
        value: imp.pressure != null ? imp.pressure!.toStringAsFixed(2) : '--',
        unit: ' \u2033', // double-prime (inches)
        severity: Severity.mid,
      ),
      _DatumData(
        label: 'Dew Point',
        value: imp.dewpt != null ? '${imp.dewpt!.round()}' : '--',
        unit: '\u00b0',
        severity: Severity.mid,
      ),
      _DatumData(
        label: 'UV',
        value: data?.uv != null ? '${data!.uv!.round()}' : '--',
        unit: '',
        severity: data?.uv != null ? uvSeverity(data!.uv!) : Severity.mid,
      ),
      _DatumData(
        label: 'Precip',
        value: imp.precipRate != null ? imp.precipRate!.toStringAsFixed(2) : '--',
        unit: ' in/hr',
        severity: Severity.mid,
      ),
    ];

    return Positioned(
      bottom: bottomPad,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) _pipe(valSize, hPad),
            _buildDatum(items[i], valSize, labelSize, hPad),
          ],
        ],
      ),
    );
  }

  Widget _pipe(double valSize, double hPad) {
    return Container(
      width: 1,
      height: valSize * 1.4,
      margin: EdgeInsets.symmetric(horizontal: hPad * 0.1),
      color: Colors.white.withValues(alpha: 0.1),
    );
  }

  Widget _buildDatum(_DatumData d, double valSize, double labelSize, double hPad) {
    final color = _sevColor(d.severity);
    final shadows = _sevShadows(d.severity);
    final needsPulse = d.severity == Severity.extreme;

    Widget valWidget = RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: d.value,
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w400,
              fontSize: valSize,
              color: color,
              letterSpacing: valSize * 0.04,
              shadows: shadows,
            ),
          ),
          TextSpan(
            text: d.unit,
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w300,
              fontSize: valSize * 0.62,
              color: color.withValues(alpha: 0.55),
            ),
          ),
          if (d.suffix.isNotEmpty)
            TextSpan(
              text: d.suffix,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w400,
                fontSize: valSize * 0.7,
                color: color.withValues(alpha: 0.6),
              ),
            ),
        ],
      ),
    );

    if (needsPulse) {
      valWidget = _PulsingWidget(child: valWidget);
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 0.6,
            child: Text(
              d.label.toUpperCase(),
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w300,
                fontSize: labelSize,
                color: subColor,
                letterSpacing: labelSize * 0.28,
              ),
            ),
          ),
          const SizedBox(height: 4),
          valWidget,
        ],
      ),
    );
  }
}

class _DatumData {
  final String label;
  final String value;
  final String unit;
  final String suffix;
  final Severity severity;

  const _DatumData({
    required this.label,
    required this.value,
    required this.unit,
    this.suffix = '',
    required this.severity,
  });
}

/// Pulsing animation for extreme severity values (2s ease-in-out infinite).
class _PulsingWidget extends StatefulWidget {
  final Widget child;
  const _PulsingWidget({required this.child});

  @override
  State<_PulsingWidget> createState() => _PulsingWidgetState();
}

class _PulsingWidgetState extends State<_PulsingWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        // Opacity oscillates between 0.65 and 1.0
        final opacity = 0.65 + 0.35 * (1 - _ctrl.value);
        return Opacity(opacity: opacity, child: child);
      },
      child: widget.child,
    );
  }
}
