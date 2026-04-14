import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centered large temperature display with degree symbol and "feels like" sub-text.
class TemperatureHero extends StatelessWidget {
  final int? temperature;
  final int? heatIndex;
  final int? windChill;
  final Color tempColor;
  final Color glowColor;
  final Color subColor;

  const TemperatureHero({
    super.key,
    this.temperature,
    this.heatIndex,
    this.windChill,
    required this.tempColor,
    required this.glowColor,
    required this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    final vw = MediaQuery.of(context).size.width;

    // font-size temp: clamp(130px, 32vw, 290px)
    final tempSize = (vw * 0.32).clamp(130.0, 290.0);
    // font-size degree: clamp(40px, 8vw, 80px)
    final degSize = (vw * 0.08).clamp(40.0, 80.0);
    // glow radii: clamp(30px,6vw,80px) and clamp(80px,16vw,200px)
    final glowSmall = (vw * 0.06).clamp(30.0, 80.0);
    final glowLarge = (vw * 0.16).clamp(80.0, 200.0);
    // degree top padding: clamp(16px, 3vw, 38px)
    final degPadTop = (vw * 0.03).clamp(16.0, 38.0);
    // feels like font size: clamp(11px, 1.8vw, 17px)
    final feelsSize = (vw * 0.018).clamp(11.0, 17.0);

    final tempText = temperature != null ? '$temperature' : '--';

    // Build feels-like string
    String feelsText = '';
    if (temperature != null) {
      if (heatIndex != null && temperature! > 75) {
        feelsText = 'feels like $heatIndex\u00b0\u2003heat index';
      } else if (windChill != null && temperature! < 50) {
        feelsText = 'feels like $windChill\u00b0\u2003wind chill';
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Temperature + degree symbol row
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tempText,
              style: GoogleFonts.bigShoulders(
                fontWeight: FontWeight.w900,
                fontSize: tempSize,
                color: tempColor,
                height: 0.88,
                letterSpacing: tempSize * -0.02,
                shadows: [
                  Shadow(
                    color: glowColor,
                    blurRadius: glowSmall,
                  ),
                  Shadow(
                    color: glowColor,
                    blurRadius: glowLarge,
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: degPadTop, left: 4),
              child: Opacity(
                opacity: 0.5,
                child: Text(
                  '\u00b0',
                  style: GoogleFonts.bigShoulders(
                    fontWeight: FontWeight.w900,
                    fontSize: degSize,
                    color: tempColor,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
        // Feels like sub-text
        SizedBox(height: (MediaQuery.of(context).size.height * 0.012).clamp(8.0, 16.0)),
        SizedBox(
          height: feelsSize * 1.4,
          child: Text(
            feelsText.isEmpty ? '\u00a0' : feelsText,
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w300,
              fontSize: feelsSize,
              color: subColor,
              letterSpacing: feelsSize * 0.12,
            ),
          ),
        ),
      ],
    );
  }
}
