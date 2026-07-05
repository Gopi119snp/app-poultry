// =============================================================================
// 🚦 PERFORMANCE ALERT ENGINE (FCR + Mortality) — v2 with Stage-Wise Thresholds
// -----------------------------------------------------------------------------
// Company ab teen tarike se thresholds set kar sakti hai:
//
//   1) FLAT     — poore batch ke liye EK hi threshold (purana/simple tarika)
//   2) DAILY    — har specific din ka apna alag threshold (Din 7 alag, Din
//                 20 alag...). Jis din ka override na diya ho, wahan FLAT
//                 (default) values fallback ke roop mein use hoti hain.
//   3) WEEKLY   — har hafte (Week 1 = Din 1-7, Week 2 = Din 8-14...) ka apna
//                 alag threshold. Jis hafte ka override na ho, FLAT fallback.
//
// Yeh bilkul Feed Consumption Rule ke "Seasonal Override" jaisa hi pattern
// hai — base/default value + optional specific overrides.
// =============================================================================

enum AlertLevel { red, green, yellow }

enum AlertGranularity { flat, daily, weekly }

/// Ek specific Din ya Hafte ke liye custom thresholds.
class ThresholdOverride {
  int periodKey; // Daily mode: din number (1,2,3...). Weekly mode: hafta number (1,2,3...)
  double fcrRedAboveThreshold;
  double fcrYellowBelowThreshold;
  double mortalityRedAboveThreshold;
  double mortalityYellowBelowThreshold;

  ThresholdOverride({
    required this.periodKey,
    required this.fcrRedAboveThreshold,
    required this.fcrYellowBelowThreshold,
    required this.mortalityRedAboveThreshold,
    required this.mortalityYellowBelowThreshold,
  });

  factory ThresholdOverride.fromJson(Map<String, dynamic> json) {
    return ThresholdOverride(
      periodKey: json['periodKey'] ?? 1,
      fcrRedAboveThreshold: (json['fcrRedAboveThreshold'] ?? 1.8).toDouble(),
      fcrYellowBelowThreshold:
          (json['fcrYellowBelowThreshold'] ?? 1.5).toDouble(),
      mortalityRedAboveThreshold:
          (json['mortalityRedAboveThreshold'] ?? 5.0).toDouble(),
      mortalityYellowBelowThreshold:
          (json['mortalityYellowBelowThreshold'] ?? 2.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'periodKey': periodKey,
    'fcrRedAboveThreshold': fcrRedAboveThreshold,
    'fcrYellowBelowThreshold': fcrYellowBelowThreshold,
    'mortalityRedAboveThreshold': mortalityRedAboveThreshold,
    'mortalityYellowBelowThreshold': mortalityYellowBelowThreshold,
  };
}

class PerformanceAlertConfig {
  AlertGranularity granularity;

  // ── FLAT / Default (fallback) thresholds ─────────────────────────────
  double fcrRedAboveThreshold;
  double fcrYellowBelowThreshold;
  double mortalityRedAboveThreshold;
  double mortalityYellowBelowThreshold;

  // ── DAILY ya WEEKLY overrides (jab granularity flat na ho tab use hote hain) ──
  List<ThresholdOverride> overrides;

  PerformanceAlertConfig({
    this.granularity = AlertGranularity.flat,
    this.fcrRedAboveThreshold = 1.8,
    this.fcrYellowBelowThreshold = 1.5,
    this.mortalityRedAboveThreshold = 5.0,
    this.mortalityYellowBelowThreshold = 2.0,
    List<ThresholdOverride>? overrides,
  }) : overrides = overrides ?? [];

  factory PerformanceAlertConfig.fromJson(Map<String, dynamic> json) {
    AlertGranularity g = AlertGranularity.flat;
    if (json['granularity'] == 'daily') g = AlertGranularity.daily;
    if (json['granularity'] == 'weekly') g = AlertGranularity.weekly;

    return PerformanceAlertConfig(
      granularity: g,
      fcrRedAboveThreshold: (json['fcrRedAboveThreshold'] ?? 1.8).toDouble(),
      fcrYellowBelowThreshold:
          (json['fcrYellowBelowThreshold'] ?? 1.5).toDouble(),
      mortalityRedAboveThreshold:
          (json['mortalityRedAboveThreshold'] ?? 5.0).toDouble(),
      mortalityYellowBelowThreshold:
          (json['mortalityYellowBelowThreshold'] ?? 2.0).toDouble(),
      overrides: (json['overrides'] as List<dynamic>? ?? [])
          .map((e) => ThresholdOverride.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'granularity': granularity == AlertGranularity.daily
        ? 'daily'
        : granularity == AlertGranularity.weekly
        ? 'weekly'
        : 'flat',
    'fcrRedAboveThreshold': fcrRedAboveThreshold,
    'fcrYellowBelowThreshold': fcrYellowBelowThreshold,
    'mortalityRedAboveThreshold': mortalityRedAboveThreshold,
    'mortalityYellowBelowThreshold': mortalityYellowBelowThreshold,
    'overrides': overrides.map((e) => e.toJson()).toList(),
  };

  /// Din number ko Week number mein convert karta hai (Din 1-7 = Week 1,
  /// Din 8-14 = Week 2, waghera).
  static int dayToWeek(int dayNumber) => ((dayNumber - 1) ~/ 7) + 1;

  /// Us din ke liye sahi thresholds resolve karta hai — Daily/Weekly
  /// override maujood hai toh wahi, warna FLAT/default fallback.
  ({
    double fcrRedAbove,
    double fcrYellowBelow,
    double mortalityRedAbove,
    double mortalityYellowBelow,
  })
  resolveForDay(int dayNumber) {
    if (granularity == AlertGranularity.daily) {
      final match = overrides.where((o) => o.periodKey == dayNumber);
      if (match.isNotEmpty) {
        final o = match.first;
        return (
          fcrRedAbove: o.fcrRedAboveThreshold,
          fcrYellowBelow: o.fcrYellowBelowThreshold,
          mortalityRedAbove: o.mortalityRedAboveThreshold,
          mortalityYellowBelow: o.mortalityYellowBelowThreshold,
        );
      }
    } else if (granularity == AlertGranularity.weekly) {
      final weekNum = dayToWeek(dayNumber);
      final match = overrides.where((o) => o.periodKey == weekNum);
      if (match.isNotEmpty) {
        final o = match.first;
        return (
          fcrRedAbove: o.fcrRedAboveThreshold,
          fcrYellowBelow: o.fcrYellowBelowThreshold,
          mortalityRedAbove: o.mortalityRedAboveThreshold,
          mortalityYellowBelow: o.mortalityYellowBelowThreshold,
        );
      }
    }
    // Flat mode, ya override na milne par: default/fallback thresholds
    return (
      fcrRedAbove: fcrRedAboveThreshold,
      fcrYellowBelow: fcrYellowBelowThreshold,
      mortalityRedAbove: mortalityRedAboveThreshold,
      mortalityYellowBelow: mortalityYellowBelowThreshold,
    );
  }
}

class PerformanceAlertEngine {
  /// [dayNumber] optional hai — na diya jaaye toh hamesha FLAT/default
  /// thresholds use hongi (backward-compatible, jaise pehle tha).
  static AlertLevel evaluateFcr(
    double fcr,
    PerformanceAlertConfig config, {
    int? dayNumber,
  }) {
    if (fcr <= 0) return AlertLevel.green; // data hi nahi, neutral rakho
    final t = dayNumber != null
        ? config.resolveForDay(dayNumber)
        : (
            fcrRedAbove: config.fcrRedAboveThreshold,
            fcrYellowBelow: config.fcrYellowBelowThreshold,
            mortalityRedAbove: config.mortalityRedAboveThreshold,
            mortalityYellowBelow: config.mortalityYellowBelowThreshold,
          );
    if (fcr > t.fcrRedAbove) return AlertLevel.red;
    if (fcr < t.fcrYellowBelow) return AlertLevel.yellow;
    return AlertLevel.green;
  }

  static AlertLevel evaluateMortality(
    double mortalityPercent,
    PerformanceAlertConfig config, {
    int? dayNumber,
  }) {
    final t = dayNumber != null
        ? config.resolveForDay(dayNumber)
        : (
            fcrRedAbove: config.fcrRedAboveThreshold,
            fcrYellowBelow: config.fcrYellowBelowThreshold,
            mortalityRedAbove: config.mortalityRedAboveThreshold,
            mortalityYellowBelow: config.mortalityYellowBelowThreshold,
          );
    if (mortalityPercent > t.mortalityRedAbove) return AlertLevel.red;
    if (mortalityPercent < t.mortalityYellowBelow) return AlertLevel.yellow;
    return AlertLevel.green;
  }
}
