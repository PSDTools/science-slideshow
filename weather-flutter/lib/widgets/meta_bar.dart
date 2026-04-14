import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/weather_data.dart';

/// Very bottom bar: station ID, neighborhood, elevation, last updated.
class MetaBar extends StatelessWidget {
  final WeatherData? data;
  final Color subColor;

  const MetaBar({
    super.key,
    this.data,
    required this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    final vw = MediaQuery.of(context).size.width;
    final vh = MediaQuery.of(context).size.height;

    // bottom: clamp(5px, 1vh, 10px)
    final bottom = (vh * 0.01).clamp(5.0, 10.0);
    // font-size: clamp(7px, 0.9vw, 9px)
    final fontSize = (vw * 0.009).clamp(7.0, 9.0);

    final imp = data?.imperial ?? const ImperialData();

    final station = data?.stationID ?? '--';
    final hood = data?.neighborhood ?? data?.country ?? '';
    final elev = imp.elev != null ? '${imp.elev!.round()}\u202fft' : '--';

    String updated = '--';
    if (data?.obsTimeLocal != null) {
      try {
        final dt = DateTime.parse(data!.obsTimeLocal!);
        final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
        final ap = dt.hour >= 12 ? 'PM' : 'AM';
        updated = 'updated $h:${dt.minute.toString().padLeft(2, '0')} $ap';
      } catch (_) {}
    }

    final style = GoogleFonts.outfit(
      fontWeight: FontWeight.w300,
      fontSize: fontSize,
      color: subColor,
      letterSpacing: fontSize * 0.2,
    );

    final items = <String>[station, hood, elev, updated]
        .where((s) => s.isNotEmpty)
        .toList();

    return Positioned(
      bottom: bottom,
      left: 0,
      right: 0,
      child: Opacity(
        opacity: 0.35,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('\u00b7', style: style),
              ),
              Text(items[i].toUpperCase(), style: style),
            ],
          ],
        ),
      ),
    );
  }
}
