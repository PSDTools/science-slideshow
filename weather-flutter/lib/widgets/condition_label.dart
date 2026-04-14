import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Small-caps condition label above temperature ("clear", "rain", "sunrise", etc.).
class ConditionLabel extends StatelessWidget {
  final String text;
  final Color accentColor;

  const ConditionLabel({
    super.key,
    required this.text,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final vw = MediaQuery.of(context).size.width;
    final vh = MediaQuery.of(context).size.height;

    // font-size: clamp(11px, 2.2vw, 20px)
    final fontSize = (vw * 0.022).clamp(11.0, 20.0);
    // margin-bottom: clamp(6px, 1.2vh, 16px)
    final marginBottom = (vh * 0.012).clamp(6.0, 16.0);

    return Padding(
      padding: EdgeInsets.only(bottom: marginBottom),
      child: SizedBox(
        height: fontSize * 1.3,
        child: Opacity(
          opacity: 0.88,
          child: Text(
            text.toUpperCase(),
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w300,
              fontSize: fontSize,
              color: accentColor,
              letterSpacing: fontSize * 0.45,
            ),
          ),
        ),
      ),
    );
  }
}
