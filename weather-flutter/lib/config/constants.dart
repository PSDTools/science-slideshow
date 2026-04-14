import 'dart:ui';

// ============================================================================
// Color constants extracted from the Svelte WeatherDisplay source.
// ============================================================================

/// Default CSS root colors (base .wx-root, before any theme is applied).
const Color kDefaultBg0 = Color(0xFF0f1a2a);
const Color kDefaultBg1 = Color(0xFF172338);
const Color kDefaultText = Color(0xFFddeeff);
const Color kDefaultSub = Color(0x73C8DCFF); // rgba(200, 220, 255, 0.45)
const Color kDefaultTempCol = Color(0xFFe8f4ff);
const Color kDefaultGlowCol = Color(0x4778BEFF); // rgba(120, 190, 255, 0.28)
const Color kDefaultAccent = Color(0xB38CC8FF); // rgba(140, 200, 255, 0.7)

/// Star color.
const Color kStarColor = Color(0xFFd8eaff);

/// Shooting star gradient: rgba(255,255,255,0.9) to transparent.
const Color kShootStarColor = Color(0xE6FFFFFF); // rgba(255, 255, 255, 0.9)

/// Firefly color.
const Color kFireflyColor = Color(0xBFA5DC46); // rgba(165, 220, 70, 0.75)

/// Snowflake color for canvas drawing.
const Color kSnowflakeColor = Color(0xFFD7EBFC); // rgba(215, 235, 252, ...)

/// Rain drop colors.
const Color kRainLightColor = Color(0xFF78AFE1); // rgba(120, 175, 225, ...)
const Color kRainHeavyColor = Color(0xFFA0C8F5); // rgba(160, 200, 245, ...)

/// Lightning bolt colors.
const Color kBoltStroke = Color(0xEBDCD2FF); // rgba(220, 210, 255, 0.92)
const Color kBoltThinStroke = Color(0x73FFFFFF); // rgba(255, 255, 255, 0.45)

/// Lightning flash overlay.
const Color kLightningFlash = Color(0xD9D2C8FF); // rgba(210, 200, 255, 0.85)

/// Humidity haze overlay base color.
const Color kHazeBaseColor = Color(0xFFC8DCF0); // rgba(200, 220, 240, ...)

/// Wind streak gradient middle color.
const Color kWindStreakColor = Color(0xBFC8E1FF); // rgba(200, 225, 255, 0.75)

/// Data strip separator color.
const Color kDatumSeparator = Color(0x1AFFFFFF); // rgba(255, 255, 255, 0.1)

/// Severity indicator colors.
const Color kSevLowColor = Color(0xFF82c4f8);
const Color kSevHighColor = Color(0xFFf8c060);
const Color kSevHighGlow = Color(0x8CF0961E); // rgba(240, 150, 30, 0.55)
const Color kSevExtremeColor = Color(0xFFf87070);
const Color kSevExtremeGlow = Color(0xA6F03C28); // rgba(240, 60, 40, 0.65)

/// Alert bar background colors by severity.
const Color kAlertDefault = Color(0xCCD26E0A); // rgba(210, 110, 10, 0.8)
const Color kAlertExtreme = Color(0xDBC31212); // rgba(195, 18, 18, 0.86)
const Color kAlertSevere = Color(0xD1CD3708); // rgba(205, 55, 8, 0.82)
const Color kAlertModerate = Color(0xCCC87D08); // rgba(200, 125, 8, 0.8)
const Color kAlertMinor = Color(0xBD166EC8); // rgba(22, 110, 200, 0.74)

/// Moon rendering colors.
const Color kMoonLitSurface = Color(0xF5E8F0FF); // rgba(232, 240, 255, 0.96)
const Color kMoonNewRing = Color(0x1F96AAC8); // rgba(150, 170, 200, 0.12)
const Color kMoonLimbDark = Color(0x47000014); // rgba(0, 0, 20, 0.28)
const Color kMoonInnerHalo = Color(0x47B4D2FF); // rgba(180, 210, 255, 0.28)
const Color kMoonInnerHaloEdge = Color(0x00B4D2FF); // rgba(180, 210, 255, 0)
const Color kMoonOuterGlowCenter = Color(0x24A0C3FF); // rgba(160, 195, 255, 0.14)
const Color kMoonOuterGlowMid = Color(0x0F8CB4FF); // rgba(140, 180, 255, 0.06)
const Color kMoonOuterGlowEdge = Color(0x008CB4FF); // rgba(140, 180, 255, 0)

/// Sun radial gradient colors.
const Color kSunCoreCenter = Color(0xFFFFF8C0);
const Color kSunCoreMid = Color(0xFFFFD840);
const Color kSunCoreEdge = Color(0x00FFB400); // rgba(255, 180, 0, 0)

/// Sun halo gradient.
const Color kSunHaloCenter = Color(0x38FFE650); // rgba(255, 230, 80, 0.22)
const Color kSunHaloMid = Color(0x14FFC828); // rgba(255, 200, 40, 0.08)
const Color kSunHaloEdge = Color(0x00000000);

/// Sun corona ray color (alternating opacities in conic gradient).
const Color kSunCoronaHigh = Color(0x38FFE150); // rgba(255, 225, 80, 0.22)
const Color kSunCoronaLow = Color(0x0AFFE150); // rgba(255, 225, 80, 0.04)

/// Mist colors per theme (RGB passed to buildMist in Svelte source).
const Map<String, (int, int, int)> kMistColors = {
  'rise': (235, 142, 68),
  'golden': (215, 132, 48),
  'sunset': (195, 60, 30),
};

/// Precip overlay darkening during precipitation.
const Color kPrecipOverlay = Color(0x73000000); // rgba(0, 0, 0, 0.45)

// ============================================================================
// Animation timing constants.
// ============================================================================

/// Clock update interval.
const Duration kClockInterval = Duration(seconds: 1);

/// Sky cross-fade transition duration.
const Duration kSkyCrossFadeDuration = Duration(seconds: 3);

/// Theme transition durations.
const Duration kThemeTransitionDuration = Duration(seconds: 1);
const Duration kAtmosTransitionDuration = Duration(seconds: 2);
const Duration kHazeTransitionDuration = Duration(seconds: 3);

/// Treeline transition timing.
const Duration kTreelineFadeOut = Duration(milliseconds: 350);
const Duration kTreelineFadeIn = Duration(milliseconds: 500);
const Duration kTreelinePrecipTransition = Duration(seconds: 2);

/// Celestial body fade transition.
const Duration kCelestialFadeDuration = Duration(seconds: 2);

/// Sun breathing animation.
const Duration kSunBreatheDuration = Duration(seconds: 4);

/// Corona ray spin duration.
const Duration kCoronaSpinDuration = Duration(seconds: 16);

/// Star pulse animation range.
const double kStarPulseMinDuration = 1.5; // seconds
const double kStarPulseMaxDuration = 6.5; // 1.5 + 5.0

/// Shooting star animation.
const Duration kShootStarDuration = Duration(milliseconds: 1400);
const double kShootStarMinDelay = 7.0; // seconds
const double kShootStarMaxDelay = 27.0; // 7.0 + 20.0
const double kShootStarInitialMinDelay = 4.0;
const double kShootStarInitialMaxDelay = 13.0; // 4.0 + 9.0

/// Lightning strike timing.
const double kLightningMinInterval = 3.5; // seconds
const double kLightningMaxInterval = 12.5; // 3.5 + 9.0
const double kLightningInitialMin = 0.8;
const double kLightningInitialMax = 3.0; // 0.8 + 2.2

/// Lightning flash durations.
const Duration kLightningFlashBright = Duration(milliseconds: 72);
const Duration kLightningFlashDim = Duration(milliseconds: 45);
const Duration kLightningSecondFlashDelay = Duration(milliseconds: 130);
const double kLightningSecondFlashChance = 0.6; // Math.random() > 0.4

/// Firefly animation ranges.
const double kFireflyDriftMinDuration = 3.5; // seconds
const double kFireflyDriftMaxDuration = 10.0; // 3.5 + 6.5
const double kFireflyPulseMinDuration = 2.2;
const double kFireflyPulseMaxDuration = 6.4; // 2.2 + 4.2
const double kFireflyDriftXRange = 130.0; // px, -65 to +65
const double kFireflyDriftYRange = 90.0; // px, -45 to +45

/// Mist animation duration range.
const double kMistMinDuration = 8.0; // seconds
const double kMistMaxDuration = 20.0; // 8.0 + 12.0
const double kMistDrift = 30.0; // px translateX

/// Snow time increment per frame.
const double kSnowTimeIncrement = 0.008;

/// Severity pulse animation duration.
const Duration kSevPulseDuration = Duration(seconds: 2);

/// Entrance animation timings.
const Duration kEntranceTempHeroDelay = Duration(milliseconds: 120);
const Duration kEntranceTempHeroDuration = Duration(milliseconds: 900);
const Duration kEntranceClockDelay = Duration(milliseconds: 320);
const Duration kEntranceClockDuration = Duration(milliseconds: 700);
const Duration kEntranceDataStripDelay = Duration(milliseconds: 550);
const Duration kEntranceDataStripDuration = Duration(milliseconds: 750);
const Duration kEntranceTreelineDelay = Duration(milliseconds: 200);
const Duration kEntranceTreelineDuration = Duration(milliseconds: 1000);
const Duration kEntranceConditionDelay = Duration(milliseconds: 180);
const Duration kEntranceConditionDuration = Duration(milliseconds: 600);

// ============================================================================
// Particle / element counts.
// ============================================================================

/// Number of stars in night sky.
const int kStarCount = 115;

/// Star size range.
const double kStarMinSize = 0.5; // px
const double kStarMaxSize = 2.9; // 0.5 + 2.4

/// Star opacity range.
const double kStarMinOpacity = 0.12;
const double kStarMaxOpacity = 1.0; // 0.12 + 0.88

/// Firefly count.
const int kFireflyCount = 22;

/// Mist layer count.
const int kMistLayerCount = 6;
const double kMistMinHeight = 55.0; // px
const double kMistMaxHeight = 140.0; // 55 + 85

/// Rain drop counts.
const int kRainLightCount = 150;
const int kRainHeavyCount = 320;

/// Rain angles (degrees).
const double kRainLightAngle = 7.0;
const double kRainHeavyAngle = 18.0;
const double kRainAngleVariance = 6.0; // +/- 3 from base

/// Rain drop dimensions (light rain).
const double kRainLightMinLen = 14.0;
const double kRainLightMaxLen = 26.0; // 14 + 12
const double kRainLightMinSpeed = 11.0;
const double kRainLightMaxSpeed = 19.0; // 11 + 8

/// Rain drop dimensions (heavy / storm rain).
const double kRainHeavyMinLen = 22.0;
const double kRainHeavyMaxLen = 42.0; // 22 + 20
const double kRainHeavyMinSpeed = 18.0;
const double kRainHeavyMaxSpeed = 32.0; // 18 + 14

/// Rain drop opacity range.
const double kRainMinOpacity = 0.18;
const double kRainMaxOpacity = 0.66; // 0.18 + 0.48

/// Rain stroke widths.
const double kRainLightStrokeWidth = 0.9;
const double kRainHeavyStrokeWidth = 1.4;

/// Snowflake count.
const int kSnowflakeCount = 200;

/// Snowflake size range.
const double kSnowMinRadius = 1.2;
const double kSnowMaxRadius = 5.7; // 1.2 + 4.5

/// Snowflake speed range.
const double kSnowMinSpeed = 0.4;
const double kSnowMaxSpeed = 1.5; // 0.4 + 1.1

/// Snowflake drift range.
const double kSnowDriftRange = 0.5; // -0.25 to +0.25
const double kSnowDriftSinAmplitude = 0.5;

/// Snowflake opacity range.
const double kSnowMinOpacity = 0.35;
const double kSnowMaxOpacity = 0.90; // 0.35 + 0.55

/// Wind streak thresholds and ranges.
const double kWindStreakMinSpeed = 5.0; // mph, no streaks below this
const double kWindStreakMaxCount = 22.0;
const double kWindStreakCountDivisor = 2.5;
const double kWindStreakMinLen = 60.0; // px
const double kWindStreakMaxExtraLen = 120.0; // random portion
const double kWindStreakSpeedExtraLen = 80.0; // speed-scaled portion
const double kWindStreakMinAngle = -8.0; // degrees
const double kWindStreakMaxAngle = -20.0; // degrees (more negative = steeper)
const double kWindStreakMinOpacity = 0.06;
const double kWindStreakMaxOpacity = 0.24; // 0.06 + 0.18 * speedFactor

/// Celestial body fade zone: 4% of the day (~35 min) near each horizon.
const double kCelestialFade = 0.04;

/// Moon timing offsets relative to sunrise/sunset.
const double kMoonriseOffsetFromSunset = 0.5; // hours after sunset
const double kMoonsetOffsetFromSunrise = 0.33; // hours before sunrise

/// Shooting star angle range.
const double kShootStarMinAngle = 20.0; // degrees from horizontal
const double kShootStarMaxAngle = 75.0;

/// Moon disc rendering sizes.
const double kMoonCanvasSize = 180.0; // px
const double kMoonDiscRadius = 34.0; // px in canvas

/// Sun core size range (CSS clamp values).
const double kSunCoreMinSize = 60.0; // px
const double kSunCoreMaxSize = 105.0; // px

/// Sun corona size range.
const double kSunCoronaMinSize = 110.0; // px
const double kSunCoronaMaxSize = 200.0; // px

/// Sun halo size range.
const double kSunHaloMinSize = 200.0; // px
const double kSunHaloMaxSize = 360.0; // px

/// UV-based sun scaling factors.
const double kUvSunCoreScale = 0.35; // scale(1 + uv * 0.35)
const double kUvSunHaloScale = 0.55; // scale(1 + uv * 0.55)
const double kUvSunHaloMinOpacity = 0.6;
const double kUvSunHaloOpacityScale = 0.4;

/// Humidity haze calculation.
const double kHazeHumidityThreshold = 40.0; // no haze below this
const double kHazeHumidityRange = 60.0; // humidity range for scaling
const double kHazeMaxAlpha = 0.2;
const double kHazeBlurScale = 3.0; // px per alpha unit

/// Wind tree sway calculation.
const double kWindSwayMinDuration = 2.0; // seconds
const double kWindSwayMaxDuration = 9.0; // seconds (at 0 wind)
const double kWindSwaySpeedDivisor = 35.0;
const double kWindSwayDurationRange = 7.0; // 9.0 - 2.0
const double kWindSwayMaxAmplitude = 8.0; // px
const double kWindSwayAmplitudeDivisor = 5.0;

/// Treeline rendering constants.
const double kTreelineHeightFraction = 0.44; // of screen height
const double kTreelineGroundY = 0.62; // fraction of treeline canvas
const double kTreelineCanvasOverflow = 40.0; // px on each side

/// Lightning SVG viewBox.
const double kLightningSvgWidth = 1000.0;
const double kLightningSvgHeight = 600.0;

/// Lightning bolt rendering.
const double kBoltStrokeWidth = 2.0;
const double kBoltThinStrokeWidth = 0.8;
const double kBoltGaussianBlurSigma = 3.0;

/// Lightning flash intensities.
const double kFlashBrightOpacity = 0.62;
const double kFlashDimOpacity = 0.26;
const Color kFlashTempColor = Color(0xFFF0ECFF);

/// Precip treeline dimming.
const double kPrecipTreelineBrightness = 0.45;

/// Background gradient angle (CSS: 165deg).
const double kBgGradientAngleDeg = 165.0;
