import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Top-right positioned clock with time and date.
/// Shifts down when an alert banner is visible.
class ClockWidget extends StatefulWidget {
  final Color textColor;
  final Color subColor;
  final bool hasAlert;

  const ClockWidget({
    super.key,
    required this.textColor,
    required this.subColor,
    this.hasAlert = false,
  });

  @override
  State<ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<ClockWidget> {
  late Timer _timer;
  String _timeStr = '';
  String _dateStr = '';

  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _tick() {
    final d = DateTime.now();
    var h = d.hour;
    final ap = h >= 12 ? 'pm' : 'am';
    h = h % 12;
    if (h == 0) h = 12;
    final time = '$h:${d.minute.toString().padLeft(2, '0')}\u202f$ap';
    final date = '${_days[d.weekday - 1]}  \u00b7  ${_months[d.month - 1]} ${d.day}';

    if (time != _timeStr || date != _dateStr) {
      setState(() {
        _timeStr = time;
        _dateStr = date;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vw = MediaQuery.of(context).size.width;
    final vh = MediaQuery.of(context).size.height;

    // top: clamp(16px, 3vh, 30px), shifts +52px when alert visible
    final baseTop = (vh * 0.03).clamp(16.0, 30.0);
    final top = widget.hasAlert ? baseTop + 52 : baseTop;
    // right: clamp(20px, 3.5vw, 40px)
    final right = (vw * 0.035).clamp(20.0, 40.0);
    // font-size clock: clamp(22px, 4vw, 38px)
    final clockSize = (vw * 0.04).clamp(22.0, 38.0);
    // font-size date: clamp(8px, 1.1vw, 11px)
    final dateSize = (vw * 0.011).clamp(8.0, 11.0);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      top: top,
      right: right,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 0.55,
            child: Text(
              _timeStr,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w200,
                fontSize: clockSize,
                color: widget.textColor,
                letterSpacing: clockSize * 0.05,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Opacity(
            opacity: 0.35,
            child: Text(
              _dateStr.toUpperCase(),
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w300,
                fontSize: dateSize,
                color: widget.subColor,
                letterSpacing: dateSize * 0.22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
