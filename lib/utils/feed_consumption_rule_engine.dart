// =============================================================================
// 🌾 CONFIGURABLE FEED CONSUMPTION RULE ENGINE
// -----------------------------------------------------------------------------
// Maqsad: Har company apna "daily feed consumption ka formula" khud set kar
// sake — bina code chede. Do modes support karta hai:
//
//   1) LINEAR MULTIPLIER MODE
//      Formula: Live Chicks × Multiplier × Day Number ÷ 1000  (kg)
//      Multiplier fixed bhi ho sakta hai (e.g. 4.5) ya SEASON ke hisaab se
//      alag-alag (e.g. Garmi=5.0, Sardi=4.0, Monsoon=4.2)
//
//   2) STANDARD AGE-CHART MODE
//      Har din ka fixed gram/bird value ek lookup table se aata hai
//      (jaisa aapke register mein printed standard chart tha). Company
//      chahe toh apne khud ke gram/day numbers se is table ko override
//      kar sakti hai.
//
// Company Settings screen mein isko simple form se configure karwaya ja
// sakta hai — koi bhi naya company sign-up hote hi apna FeedConsumptionRuleConfig
// bana sake, aur wahi config Firestore mein company profile ke saath save ho.
// =============================================================================

// -----------------------------------------------------------------------------
// 1. RULE TYPE — company decide karti hai kaunsa mode use karna hai
// -----------------------------------------------------------------------------
enum FeedRuleType {
  linearMultiplier, // Live × Multiplier × Day ÷ 1000
  standardAgeChart, // fixed gram/day lookup table
}

// -----------------------------------------------------------------------------
// 2. SEASONAL MULTIPLIER — LINEAR MODE ke liye, mausam ke hisaab se
//    multiplier badalne ka option
// -----------------------------------------------------------------------------
class SeasonalMultiplier {
  String seasonName; // e.g. "Garmi", "Sardi", "Barsaat"
  int startMonth; // 1 = January ... 12 = December
  int endMonth; // agar startMonth > endMonth toh year-wrap maana jayega
  // (e.g. Sardi: startMonth=11, endMonth=2 → Nov,Dec,Jan,Feb)
  double multiplier;

  SeasonalMultiplier({
    required this.seasonName,
    required this.startMonth,
    required this.endMonth,
    required this.multiplier,
  });

  bool matchesMonth(int month) {
    if (startMonth <= endMonth) {
      return month >= startMonth && month <= endMonth;
    } else {
      // year-wrap case, e.g. Nov(11) se Feb(2) tak
      return month >= startMonth || month <= endMonth;
    }
  }

  factory SeasonalMultiplier.fromJson(Map<String, dynamic> json) {
    return SeasonalMultiplier(
      seasonName: json['seasonName'] ?? '',
      startMonth: json['startMonth'] ?? 1,
      endMonth: json['endMonth'] ?? 12,
      multiplier: (json['multiplier'] ?? 4.5).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'seasonName': seasonName,
    'startMonth': startMonth,
    'endMonth': endMonth,
    'multiplier': multiplier,
  };
}

// -----------------------------------------------------------------------------
// 3. FULL CONFIG — yahi ek object company ke Settings se banega/save hoga
// -----------------------------------------------------------------------------
class FeedConsumptionRuleConfig {
  FeedRuleType ruleType;

  // ── Linear Multiplier Mode settings ──────────────────────────────────────
  double defaultMultiplier; // e.g. 4.5 — jab koi seasonal override match na ho
  List<SeasonalMultiplier> seasonalOverrides; // company jitne season chahe add kare

  // ── Standard Age-Chart Mode settings ─────────────────────────────────────
  // Agar company apna khud ka gram/day table dena chahe (day → gram/bird),
  // toh yahan override kar sakti hai. Null/missing day ke liye default
  // chart (neeche) use hoga.
  Map<int, double>? customAgeChartGramPerDay;

  FeedConsumptionRuleConfig({
    this.ruleType = FeedRuleType.linearMultiplier,
    this.defaultMultiplier = 4.5,
    List<SeasonalMultiplier>? seasonalOverrides,
    this.customAgeChartGramPerDay,
  }) : seasonalOverrides = seasonalOverrides ?? [];

  factory FeedConsumptionRuleConfig.fromJson(Map<String, dynamic> json) {
    return FeedConsumptionRuleConfig(
      ruleType: (json['ruleType'] == 'standardAgeChart')
          ? FeedRuleType.standardAgeChart
          : FeedRuleType.linearMultiplier,
      defaultMultiplier: (json['defaultMultiplier'] ?? 4.5).toDouble(),
      seasonalOverrides: (json['seasonalOverrides'] as List<dynamic>? ?? [])
          .map((e) => SeasonalMultiplier.fromJson(e as Map<String, dynamic>))
          .toList(),
      customAgeChartGramPerDay: (json['customAgeChartGramPerDay'] as Map?)
          ?.map((k, v) => MapEntry(int.parse(k.toString()), (v as num).toDouble())),
    );
  }

  Map<String, dynamic> toJson() => {
    'ruleType': ruleType == FeedRuleType.standardAgeChart
        ? 'standardAgeChart'
        : 'linearMultiplier',
    'defaultMultiplier': defaultMultiplier,
    'seasonalOverrides': seasonalOverrides.map((e) => e.toJson()).toList(),
    'customAgeChartGramPerDay': customAgeChartGramPerDay
        ?.map((k, v) => MapEntry(k.toString(), v)),
  };
}

// -----------------------------------------------------------------------------
// 4. DEFAULT STANDARD AGE-CHART (aapke register wala printed table)
//    Company override na kare toh yahi fallback use hoga.
// -----------------------------------------------------------------------------
const Map<int, double> defaultStandardAgeChartGramPerDay = {
  1: 13, 2: 16, 3: 19, 4: 22, 5: 25, 6: 28, 7: 32,
  8: 36, 9: 41, 10: 46, 11: 51, 12: 57, 13: 63, 14: 69,
  15: 75, 16: 89, 17: 96, 18: 103, 19: 110, 20: 118, 21: 125,
  22: 132, 23: 139, 24: 146, 25: 153, 26: 160, 27: 166, 28: 172,
  29: 178, 30: 184, 31: 190, 32: 195, 33: 200, 34: 204, 35: 208,
  36: 212, 37: 215, 38: 218, 39: 220, 40: 222, 41: 224, 42: 225,
  43: 226, 44: 226,
  // 44 se aage flat 226 rahega (neeche ka getter isko handle karta hai)
};

// -----------------------------------------------------------------------------
// 5. ENGINE — actual calculation, jo config ke hisaab se sahi mode chalata hai
// -----------------------------------------------------------------------------
class FeedConsumptionEngine {
  /// Us specific din ka feed consumption (kg) nikalta hai.
  ///
  /// [liveChicks]  = us din tak ka live chick count (mortality ghata ke)
  /// [dayNumber]   = chick ki age (1, 2, 3...)
  /// [entryDate]   = us din ki actual calendar date (seasonal mode ke liye zaroori)
  static double calculateDayFeedKg({
    required FeedConsumptionRuleConfig config,
    required int liveChicks,
    required int dayNumber,
    required DateTime entryDate,
  }) {
    if (config.ruleType == FeedRuleType.linearMultiplier) {
      double multiplier = _resolveMultiplier(config, entryDate);
      return (liveChicks * multiplier * dayNumber) / 1000;
    } else {
      double gramPerBird = _resolveGramPerDay(config, dayNumber);
      return (liveChicks * gramPerBird) / 1000;
    }
  }

  /// Din 1 se [uptoDay] tak ka cumulative (kul) feed consumption (kg).
  /// Har din ka liveChicks alag ho sakta hai (mortality ki wajah se), isliye
  /// [liveChicksPerDay] ek Map<dayNumber, liveChicksUsDin> ke roop mein diya
  /// jaata hai, aur [entryDatePerDay] har din ki calendar date.
  static double calculateCumulativeFeedKg({
    required FeedConsumptionRuleConfig config,
    required Map<int, int> liveChicksPerDay,
    required Map<int, DateTime> entryDatePerDay,
    required int uptoDay,
  }) {
    double total = 0.0;
    for (int day = 1; day <= uptoDay; day++) {
      int live = liveChicksPerDay[day] ?? 0;
      DateTime date = entryDatePerDay[day] ?? DateTime.now();
      total += calculateDayFeedKg(
        config: config,
        liveChicks: live,
        dayNumber: day,
        entryDate: date,
      );
    }
    return total;
  }

  // ── Internal helpers ───────────────────────────────────────────────────

  static double _resolveMultiplier(
    FeedConsumptionRuleConfig config,
    DateTime entryDate,
  ) {
    for (var season in config.seasonalOverrides) {
      if (season.matchesMonth(entryDate.month)) {
        return season.multiplier;
      }
    }
    return config.defaultMultiplier;
  }

  static double _resolveGramPerDay(
    FeedConsumptionRuleConfig config,
    int dayNumber,
  ) {
    // Pehle company ka custom override check karo
    if (config.customAgeChartGramPerDay != null &&
        config.customAgeChartGramPerDay!.containsKey(dayNumber)) {
      return config.customAgeChartGramPerDay![dayNumber]!;
    }
    // Warna default chart se lo
    if (defaultStandardAgeChartGramPerDay.containsKey(dayNumber)) {
      return defaultStandardAgeChartGramPerDay[dayNumber]!;
    }
    // 44+ din ke liye flat value (chart ka last value)
    return defaultStandardAgeChartGramPerDay[44]!;
  }
}

// =============================================================================
// 📌 USAGE EXAMPLE (Company Settings se aayega, hardcode nahi karna)
// =============================================================================
//
// Company A — sirf fixed multiplier chahti hai:
//
//   final configA = FeedConsumptionRuleConfig(
//     ruleType: FeedRuleType.linearMultiplier,
//     defaultMultiplier: 4.5,
//   );
//
// Company B — season ke hisaab se multiplier badalna chahti hai:
//
//   final configB = FeedConsumptionRuleConfig(
//     ruleType: FeedRuleType.linearMultiplier,
//     defaultMultiplier: 4.5, // baaki mahino ke liye fallback
//     seasonalOverrides: [
//       SeasonalMultiplier(seasonName: 'Garmi', startMonth: 4, endMonth: 6, multiplier: 5.0),
//       SeasonalMultiplier(seasonName: 'Sardi', startMonth: 11, endMonth: 2, multiplier: 4.0),
//       SeasonalMultiplier(seasonName: 'Barsaat', startMonth: 7, endMonth: 9, multiplier: 4.2),
//     ],
//   );
//
// Company C — purana standard-chart wala tarika hi chahti hai (jaisa app pehle se karta hai):
//
//   final configC = FeedConsumptionRuleConfig(
//     ruleType: FeedRuleType.standardAgeChart,
//   );
//
// Calculation call (kisi bhi config ke saath same tarike se):
//
//   double din30Feed = FeedConsumptionEngine.calculateDayFeedKg(
//     config: configB,
//     liveChicks: 1750,
//     dayNumber: 30,
//     entryDate: DateTime(2026, 6, 14), // Garmi ka mahina → multiplier 5.0 use hoga
//   );
//
// =============================================================================
