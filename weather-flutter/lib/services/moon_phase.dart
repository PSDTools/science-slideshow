/// Lunar phase via Julian Day Number.
/// Returns 0 = new moon, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter.
/// The returned value is a continuous 0-1 fraction.
double getMoonPhase() {
  final d = DateTime.now();
  final a = ((14 - (d.month)) / 12).floor();
  final y = d.year + 4800 - a;
  final m = d.month + 12 * a - 3;
  final jd = d.day +
      ((153 * m + 2) / 5).floor() +
      365 * y +
      (y / 4).floor() -
      (y / 100).floor() +
      (y / 400).floor() -
      32045 +
      (d.hour - 12) / 24.0 +
      d.minute / 1440.0;

  // Reference new moon: Jan 6, 2000 18:14 UTC -> JD 2451550.1
  const synodicMonth = 29.53058867;
  final age = (((jd - 2451550.1) % synodicMonth) + synodicMonth) % synodicMonth;
  return age / synodicMonth;
}
