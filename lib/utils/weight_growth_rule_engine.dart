// =============================================================================
// ⚖️ CONFIGURABLE WEIGHT GROWTH RULE ENGINE
// -----------------------------------------------------------------------------
// Maqsad: "Automatic Body Weight" kaise calculate ho, isko bhi company apne
// hisaab se set kar sake — bilkul Feed Consumption Rule Engine jaisa pattern.
//
// Do modes:
//   1) STANDARD (App Default) — wahi formula jo app pehle se "Target Weight"
//      ke liye use karta hai (piecewise growth curve).
//   2) CUSTOM CHART — company apna khud ka Day → Gram table de sakti hai
//      (jaise register mein printed chart hota hai: Din1=57g, Din2=72g...).
//
// Isse "Daily Update List" mein har din ka Automatic Body Weight column
// isi engine se aayega, aur agar company custom chart deti hai to Target
// Weight bhi (chaho to) isi se sync kiya ja sakta hai.
// =============================================================================

enum WeightRuleType {
  standardFormula, // App ka existing piecewise growth formula
  customChart, // Company ka apna Day→Gram table
}

class WeightGrowthRuleConfig {
  WeightRuleType ruleType;

  // Company ka custom Day (int) → Body Weight in Gram (double) table.
  // Sirf customChart mode mein use hota hai.
  Map<int, double>? customBodyWeightGramPerDay;

  WeightGrowthRuleConfig({
    this.ruleType = WeightRuleType.standardFormula,
    this.customBodyWeightGramPerDay,
  });

  factory WeightGrowthRuleConfig.fromJson(Map<String, dynamic> json) {
    return WeightGrowthRuleConfig(
      ruleType: (json['ruleType'] == 'customChart')
          ? WeightRuleType.customChart
          : WeightRuleType.standardFormula,
      customBodyWeightGramPerDay: (json['customBodyWeightGramPerDay'] as Map?)
          ?.map((k, v) => MapEntry(int.parse(k.toString()), (v as num).toDouble())),
    );
  }

  Map<String, dynamic> toJson() => {
    'ruleType': ruleType == WeightRuleType.customChart
        ? 'customChart'
        : 'standardFormula',
    'customBodyWeightGramPerDay': customBodyWeightGramPerDay
        ?.map((k, v) => MapEntry(k.toString(), v)),
  };
}

class WeightGrowthEngine {
  /// App ka original "Target Weight" formula — jaisa batch_detail_screen.dart
  /// mein `_getAppStandardTargetWeight` mein hai. Yahan duplicate rakha hai
  /// taaki yeh engine standalone/reusable rahe.
  static int _standardFormulaGram(int daysOld) {
    if (daysOld <= 0) return 40;
    if (daysOld <= 7) return 40 + (daysOld * 20);
    if (daysOld <= 14) return 180 + ((daysOld - 7) * 38);
    if (daysOld <= 21) return 446 + ((daysOld - 14) * 64);
    if (daysOld <= 28) return 894 + ((daysOld - 21) * 85);
    return 1489 + ((daysOld - 28) * 90);
  }

  /// Us specific din ka Automatic Body Weight (gram) nikalta hai — config ke
  /// hisaab se Standard formula ya Company ka Custom chart use hota hai.
  static double getBodyWeightGram({
    required WeightGrowthRuleConfig config,
    required int dayNumber,
  }) {
    if (config.ruleType == WeightRuleType.customChart &&
        config.customBodyWeightGramPerDay != null &&
        config.customBodyWeightGramPerDay!.isNotEmpty) {
      final chart = config.customBodyWeightGramPerDay!;
      if (chart.containsKey(dayNumber)) {
        return chart[dayNumber]!;
      }
      // Agar exact din chart mein nahi hai (company ne sirf kuch din diye
      // hain), toh sabse nazdeeki pichla din use karo, aur agar chart ke
      // aage nikal gaye to last-din + last-din ka average daily gain se
      // aage extrapolate karo.
      final days = chart.keys.toList()..sort();
      if (dayNumber < days.first) return chart[days.first]!;
      if (dayNumber > days.last) {
        final lastDay = days.last;
        final secondLastDay = days.length > 1 ? days[days.length - 2] : lastDay;
        final dailyGain = (lastDay != secondLastDay)
            ? (chart[lastDay]! - chart[secondLastDay]!) / (lastDay - secondLastDay)
            : 0.0;
        return chart[lastDay]! + dailyGain * (dayNumber - lastDay);
      }
      // beech ka koi din missing ho toh nazdeeki chhote din ki value lo
      int nearest = days.first;
      for (final d in days) {
        if (d <= dayNumber) nearest = d;
      }
      return chart[nearest]!;
    }
    return _standardFormulaGram(dayNumber).toDouble();
  }
}
