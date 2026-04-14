import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/alert_service.dart';

/// Fixed top banner for NWS weather alerts with severity-based coloring.
class AlertBar extends StatelessWidget {
  final WeatherAlert? alert;

  const AlertBar({super.key, this.alert});

  Color _severityColor(AlertSeverity sev) {
    return switch (sev) {
      AlertSeverity.extreme => const Color(0xDBC31212), // rgba(195,18,18,0.86)
      AlertSeverity.severe => const Color(0xD1CD3708),  // rgba(205,55,8,0.82)
      AlertSeverity.moderate => const Color(0xCCC87D08), // rgba(200,125,8,0.80)
      AlertSeverity.minor => const Color(0xBD166EC8),   // rgba(22,110,200,0.74)
      AlertSeverity.unknown => const Color(0xCCD26E0A), // default orange
    };
  }

  @override
  Widget build(BuildContext context) {
    if (alert == null) return const SizedBox.shrink();

    final vw = MediaQuery.of(context).size.width;
    // font-size: clamp(11px, 1.5vw, 15px)
    final fontSize = (vw * 0.015).clamp(11.0, 15.0);
    // padding horizontal: clamp(16px, 3vw, 48px)
    final hPad = (vw * 0.03).clamp(16.0, 48.0);

    final a = alert!;
    final extra = a.totalCount > 1 ? ' (+${a.totalCount - 1} more)' : '';

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 10, horizontal: hPad),
            decoration: BoxDecoration(
              color: _severityColor(a.severity),
              border: const Border(
                bottom: BorderSide(color: Color(0x2EFFFFFF), width: 1),
              ),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '\u26a0 ${a.event}',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600,
                      fontSize: fontSize,
                      color: Colors.white,
                      letterSpacing: fontSize * 0.06,
                      shadows: [
                        const Shadow(color: Color(0x73000000), blurRadius: 5),
                      ],
                    ),
                  ),
                  TextSpan(
                    text: '  ${a.headline}$extra',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w400,
                      fontSize: fontSize,
                      color: Colors.white,
                      letterSpacing: fontSize * 0.06,
                      shadows: [
                        const Shadow(color: Color(0x73000000), blurRadius: 5),
                      ],
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
