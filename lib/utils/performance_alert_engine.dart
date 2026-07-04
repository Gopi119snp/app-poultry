// =============================================================================
// 🚦 PERFORMANCE ALERT ENGINE (FCR + Mortality)
// -----------------------------------------------------------------------------
// Company khud decide karti hai FCR aur Mortality% ke liye "kitne se kitna
// tak Red (kharab), Green (normal), Yellow (normal se badiya)" hoga.
//
// FCR: kam FCR = accha, isliye:
//   FCR > redAboveThreshold        → 🔴 Red (kharab)
//   FCR < yellowBelowThreshold     → 🟡 Yellow (normal se badiya)
//   beech mein                     → 🟢 Green (normal)
//
// Mortality %: kam mortality = accha, isliye:
//   Mortality% > redAboveThreshold      → 🔴 Red (kharab)
//   Mortality% < yellowBelowThreshold   → 🟡 Yellow (normal se badiya)
//   beech mein                          → 🟢 Green (normal)
// =============================================================================

enum AlertLevel { red, green, yellow }

class PerformanceAlertConfig {
  // FCR thresholds
  double fcrRedAboveThreshold; // ispar/upar → Red
  double fcrYellowBelowThreshold; // iske neeche → Yellow

  // Mortality % thresholds
  double mortalityRedAboveThreshold; // ispar/upar → Red
  double mortalityYellowBelowThreshold; // iske neeche → Yellow

  PerformanceAlertConfig({
    this.fcrRedAboveThreshold = 1.8,
    this.fcrYellowBelowThreshold = 1.5,
    this.mortalityRedAboveThreshold = 5.0,
    this.mortalityYellowBelowThreshold = 2.0,
  });

  factory PerformanceAlertConfig.fromJson(Map<String, dynamic> json) {
    return PerformanceAlertConfig(
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
    'fcrRedAboveThreshold': fcrRedAboveThreshold,
    'fcrYellowBelowThreshold': fcrYellowBelowThreshold,
    'mortalityRedAboveThreshold': mortalityRedAboveThreshold,
    'mortalityYellowBelowThreshold': mortalityYellowBelowThreshold,
  };
}

class PerformanceAlertEngine {
  static AlertLevel evaluateFcr(double fcr, PerformanceAlertConfig config) {
    if (fcr <= 0) return AlertLevel.green; // data hi nahi, neutral rakho
    if (fcr > config.fcrRedAboveThreshold) return AlertLevel.red;
    if (fcr < config.fcrYellowBelowThreshold) return AlertLevel.yellow;
    return AlertLevel.green;
  }

  static AlertLevel evaluateMortality(
    double mortalityPercent,
    PerformanceAlertConfig config,
  ) {
    if (mortalityPercent > config.mortalityRedAboveThreshold) {
      return AlertLevel.red;
    }
    if (mortalityPercent < config.mortalityYellowBelowThreshold) {
      return AlertLevel.yellow;
    }
    return AlertLevel.green;
  }
}
