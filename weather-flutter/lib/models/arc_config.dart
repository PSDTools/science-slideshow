/// Configuration for celestial body arc positioning.
///
/// Screen faces NORTH: east = right, west = left.
/// The sun/moon arc is a LOW arc: rises right, peaks center-low, sets left.
class ArcConfig {
  /// x% where body rises (right side = east)
  final double xRight;

  /// x% where body sets (left side = west)
  final double xLeft;

  /// vh at horizon — use >100 to start/end off-screen
  final double yHorizon;

  /// vh at the top of the arc (noon / midnight)
  final double yPeak;

  /// Exponent shaping the arc (0.3 = flat, 1.5 = pointy)
  final double arcExp;

  const ArcConfig({
    this.xRight = 92,
    this.xLeft = 8,
    this.yHorizon = 115,
    this.yPeak = 32,
    this.arcExp = 0.65,
  });

  /// Default arc configuration matching ARC_DEFAULTS from the Svelte source.
  static const ArcConfig defaults = ArcConfig(
    xRight: 92,
    xLeft: 8,
    yHorizon: 115,
    yPeak: 32,
    arcExp: 0.65,
  );
}
