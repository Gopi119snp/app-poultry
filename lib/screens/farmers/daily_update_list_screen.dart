import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/company_store.dart';
import '../../../utils/feed_consumption_rule_engine.dart';
import '../../../utils/weight_growth_rule_engine.dart';
import '../../../utils/fraud_risk_engine.dart';
import '../../../utils/performance_alert_engine.dart';

// =============================================================================
// 📅 DAILY UPDATE LIST SCREEN
// -----------------------------------------------------------------------------
// Batch Start Date se lekar aaj tak, har din ka poora breakdown ek table mein:
// Date, Day, Live Chicks, Mortality, Total Mortality, Mortality%,
// Daily Feed(kg), Total Feed(kg), Feed Stock(kg), Body Weight (Auto+Manual),
// FCR (Auto+Manual, cumulative), aur Cost/Kg (running estimate).
//
// Automatic Body Weight & Daily Feed dono company ke configured rules
// (FeedConsumptionRuleConfig / WeightGrowthRuleConfig) se aate hain.
// Manual Body Weight wahi hai jo Flock Record ('cost' type entry) mein
// us din ke liye actual mein daala gaya tha.
//
// Row par TAP karke us din ke liye seedha ek naya Flock Record ('cost' type)
// entry add ki ja sakti hai — bilkul "+Flock Record" button jaisa hi, bas
// date pehle se fix hoti hai. Yeh CompanyFarmers/SharedPreferences mein
// waisa hi save hota hai jaisa Batch Detail Screen karta hai, isliye dono
// jagah data hamesha sync rehta hai.
// =============================================================================
class DailyUpdateListScreen extends StatefulWidget {
  final Map<String, dynamic> batchData;
  final List<dynamic> dailyEntries;
  final FeedConsumptionRuleConfig feedRuleConfig;
  final String farmerId;
  final String userRole;

  const DailyUpdateListScreen({
    super.key,
    required this.batchData,
    required this.dailyEntries,
    required this.feedRuleConfig,
    required this.farmerId,
    required this.userRole,
  });

  @override
  State<DailyUpdateListScreen> createState() => _DailyUpdateListScreenState();
}

/// Ek din ki poori calculated row.
class _DayRow {
  final DateTime date;
  final int day;
  final int liveChicks;
  final int mortalityToday;
  final int totalMortality;
  final double mortalityPercent;
  final double dailyFeedKg;
  final double totalFeedKg;
  final double feedStockKg;
  final double autoWeightKg;
  final double? manualWeightKg;
  final double autoFcr;
  final double? manualFcr;
  final double costPerKg;
  final FraudRiskAssessment fraud;

  _DayRow({
    required this.date,
    required this.day,
    required this.liveChicks,
    required this.mortalityToday,
    required this.totalMortality,
    required this.mortalityPercent,
    required this.dailyFeedKg,
    required this.totalFeedKg,
    required this.feedStockKg,
    required this.autoWeightKg,
    required this.manualWeightKg,
    required this.autoFcr,
    required this.manualFcr,
    required this.costPerKg,
    required this.fraud,
  });
}

class _DailyUpdateListScreenState extends State<DailyUpdateListScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);
  static const Color accentGreen = Color(0xFF43A047);
  static const Color lightGreen = Color(0xFFE8F5E9);
  static const Color deepShadow = Color(0x33000000);

  bool _loading = true;
  double _tableScale = 1.0;
  FeedConsumptionRuleConfig get _feedConfig => widget.feedRuleConfig;
  WeightGrowthRuleConfig _weightConfig = WeightGrowthRuleConfig();
  PerformanceAlertConfig _performanceConfig = PerformanceAlertConfig();

  // ── Cost Rates for "Per Kg Rate" column ─────────────────────────────────
  // Priority: Rule 1 (Big/Small Auto Size) ka saved config > fallback
  // standalone settings (jab Rule 2 active ho ya koi rule set na ho, kyunki
  // Rule 2 mein abhi chick/feed/admin cost fields exist hi nahi karte).
  int? _appliedRuleId;
  Map<String, dynamic>? _rule1Config;

  // Fallback (Rule 2 / no-rule case) ke liye
  double _fallbackChickPrice = 45.0;
  double _fallbackFeedRate = 38.0;
  double _fallbackAdminCost = 2.0;
  double _fallbackKgPerBag = 50.0;

  List<_DayRow> _rows = [];
  late List<dynamic> _localDailyEntries;

  @override
  void initState() {
    super.initState();
    _localDailyEntries = List<dynamic>.from(widget.dailyEntries);
    _loadAndCompute();
  }

  Future<void> _loadAndCompute() async {
    // Weight Growth Rule load
    final weightRaw = await CompanyStore.instance.getString(
      'weightGrowthRuleConfig',
    );
    if (weightRaw != null && weightRaw.isNotEmpty) {
      try {
        _weightConfig = WeightGrowthRuleConfig.fromJson(jsonDecode(weightRaw));
      } catch (_) {}
    }

    // Performance Alert Rule load (FCR + Mortality Red/Green/Yellow)
    final perfAlertRaw = await CompanyStore.instance.getString(
      'performanceAlertConfig',
    );
    if (perfAlertRaw != null && perfAlertRaw.isNotEmpty) {
      try {
        _performanceConfig = PerformanceAlertConfig.fromJson(
          jsonDecode(perfAlertRaw),
        );
      } catch (_) {}
    }

    // Applied Settlement Rule load (Rule 1 = Big/Small Auto Size)
    _appliedRuleId = await CompanyStore.instance.getInt('appliedCompanyRuleId');
    if (_appliedRuleId == 1) {
      final rule1Raw = await CompanyStore.instance.getString(
        'rule1SettlementConfig',
      );
      if (rule1Raw != null && rule1Raw.isNotEmpty) {
        try {
          _rule1Config = jsonDecode(rule1Raw) as Map<String, dynamic>;
        } catch (_) {}
      }
    }

    // Fallback Running Cost Config load (Rule 2 / no-rule case ke liye)
    final costRaw = await CompanyStore.instance.getString('runningCostConfig');
    if (costRaw != null && costRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(costRaw) as Map<String, dynamic>;
        _fallbackChickPrice = (decoded['chickPricePerPiece'] ?? 45.0).toDouble();
        _fallbackFeedRate = (decoded['feedRatePerKg'] ?? 38.0).toDouble();
        _fallbackAdminCost = (decoded['adminCostPerKg'] ?? 2.0).toDouble();
        _fallbackKgPerBag = (decoded['kgPerBag'] ?? 50.0).toDouble();
      } catch (_) {}
    }

    _computeRows();
    setState(() => _loading = false);
  }

  /// Us din ke weight ke hisaab se sahi cost rates return karta hai —
  /// Rule 1 active hone par Big/Small auto-detect (>1.2kg = Big), warna
  /// fallback settings.
  ({double chickPrice, double feedRate, double adminCost, double kgPerBag})
  _resolveCostRates(double weightKgForSizeCheck) {
    if (_appliedRuleId == 1 && _rule1Config != null) {
      final bool isBigSize = weightKgForSizeCheck > 1.2;
      final c = _rule1Config!;
      if (isBigSize) {
        return (
          chickPrice: (c['bigChicksRate'] ?? 40.0).toDouble(),
          feedRate: (c['bigFeedRate'] ?? 42.0).toDouble(),
          adminCost: (c['bigAdminCost'] ?? 1.5).toDouble(),
          kgPerBag: (c['bigKgPerBag'] ?? 50.0).toDouble(),
        );
      } else {
        return (
          chickPrice: (c['smChicksRate'] ?? 40.0).toDouble(),
          feedRate: (c['smFeedRate'] ?? 42.0).toDouble(),
          adminCost: (c['smAdminCost'] ?? 1.5).toDouble(),
          kgPerBag: (c['smKgPerBag'] ?? 50.0).toDouble(),
        );
      }
    }
    // Rule 2 active hai ya koi rule set nahi — fallback settings use karo
    return (
      chickPrice: _fallbackChickPrice,
      feedRate: _fallbackFeedRate,
      adminCost: _fallbackAdminCost,
      kgPerBag: _fallbackKgPerBag,
    );
  }

  DateTime? _parseDdMmYyyy(dynamic raw) {
    try {
      final parts = raw.toString().split('/');
      if (parts.length != 3) return null;
      return DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );
    } catch (_) {
      return null;
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _computeRows() {
    final int initialChicks = widget.batchData['chicksCount'] ?? 0;
    final DateTime startDate =
        _parseDdMmYyyy(widget.batchData['startDate']) ?? DateTime.now();

    final DateTime today = DateTime.now();
    int chicksAgeDays = today.difference(startDate).inDays + 1;
    if (chicksAgeDays < 1) chicksAgeDays = 1;

    // Cost-type entries pehle se parse kar lo (date ke saath)
    final List<Map<String, dynamic>> costEntries = [];
    for (final e in _localDailyEntries) {
      if (e['type'].toString().toLowerCase() != 'cost') continue;
      final d = _parseDdMmYyyy(e['date']);
      if (d == null) continue;
      costEntries.add({
        'date': d,
        'mortality': int.tryParse(e['mortality'].toString()) ?? 0,
        'feedBags': int.tryParse(e['feed'].toString()) ?? 0,
        'weightKg': double.tryParse(e['weight'].toString()) ?? 0.0,
        'remainingFeedBags': int.tryParse(e['remainingFeed'].toString()) ?? 0,
      });
    }

    int cumulativeMortality = 0;
    double cumulativeFeedConsumedKg = 0.0;
    double cumulativeFeedDeliveredKg = 0.0;
    double? lastManualWeightKg;
    double lastActualRemainingFeedKg = 0.0;
    bool remainingFeedEverReported = false;
    final List<_DayRow> rows = [];

    for (int day = 1; day <= chicksAgeDays; day++) {
      final DateTime date = startDate.add(Duration(days: day - 1));

      int mortalityToday = 0;
      int feedBagsDeliveredToday = 0;
      double? weightEnteredToday;
      int? remainingFeedBagsToday;

      for (final entry in costEntries) {
        if (_sameDay(entry['date'] as DateTime, date)) {
          mortalityToday += entry['mortality'] as int;
          feedBagsDeliveredToday += entry['feedBags'] as int;
          final w = entry['weightKg'] as double;
          if (w > 0) weightEnteredToday = w;
          final rf = entry['remainingFeedBags'] as int;
          if (rf > 0) remainingFeedBagsToday = rf;
        }
      }

      cumulativeMortality += mortalityToday;
      final int liveChicks = (initialChicks - cumulativeMortality).clamp(
        0,
        initialChicks,
      );
      final double mortalityPercent = initialChicks > 0
          ? (cumulativeMortality / initialChicks) * 100
          : 0.0;

      // ── Daily Feed Consumption (kg) — automatic, rule-based ─────────────
      final double dailyFeedKg = FeedConsumptionEngine.calculateDayFeedKg(
        config: _feedConfig,
        liveChicks: liveChicks,
        dayNumber: day,
        entryDate: date,
      );
      cumulativeFeedConsumedKg += dailyFeedKg;

      // ── Body Weight — Automatic (rule-based) + Manual (agar entry hai) ──
      final double autoWeightKg =
          WeightGrowthEngine.getBodyWeightGram(
            config: _weightConfig,
            dayNumber: day,
          ) /
          1000.0;

      if (weightEnteredToday != null) {
        lastManualWeightKg = weightEnteredToday;
      }
      final double? manualWeightKg = lastManualWeightKg;

      // ── Cost Rates resolve karo (Rule 1 Big/Small auto-detect, warna
      // fallback) — size-check ke liye manual weight ko priority, warna auto ──
      final ratesToday = _resolveCostRates(manualWeightKg ?? autoWeightKg);

      if (remainingFeedBagsToday != null) {
        lastActualRemainingFeedKg = remainingFeedBagsToday * ratesToday.kgPerBag;
        remainingFeedEverReported = true;
      }

      // ── Feed Stock in Farm (kg) — deliveries (jitni baar bhi aayi) minus
      // ab tak consume hua feed ─────────────────────────────────────────
      cumulativeFeedDeliveredKg +=
          feedBagsDeliveredToday * ratesToday.kgPerBag;
      final double feedStockKg =
          (cumulativeFeedDeliveredKg - cumulativeFeedConsumedKg).clamp(
        0,
        double.infinity,
      );

      // ── FCR — Cumulative, dono Automatic aur Manual weight ke basis pe ──
      final double autoBiomassKg = liveChicks * autoWeightKg;
      final double autoFcr =
          autoBiomassKg > 0 ? cumulativeFeedConsumedKg / autoBiomassKg : 0.0;

      double? manualFcr;
      if (manualWeightKg != null && manualWeightKg > 0) {
        final double manualBiomassKg = liveChicks * manualWeightKg;
        manualFcr = manualBiomassKg > 0
            ? cumulativeFeedConsumedKg / manualBiomassKg
            : null;
      }

      // ── Per Kg Rate — ab tak ka production cost ÷ live biomass ─────────
      // (Running estimate — batch abhi active hai, koi sale nahi hui hai।
      // Rates seedha active Settlement Rule se aate hain — dekho _resolveCostRates)
      final double cumulativeChickCost = initialChicks * ratesToday.chickPrice;
      final double cumulativeFeedCost =
          cumulativeFeedConsumedKg * ratesToday.feedRate;
      final double cumulativeAdminCost = autoBiomassKg * ratesToday.adminCost;
      final double cumulativeProductionCost =
          cumulativeChickCost + cumulativeFeedCost + cumulativeAdminCost;
      final double costPerKg =
          autoBiomassKg > 0 ? cumulativeProductionCost / autoBiomassKg : 0.0;

      // ── 🚨 Fraud Risk Assessment (Feed-per-Bird + Purchase Reconciliation) ──
      final FraudRiskAssessment fraud = FraudRiskEngine.assess(
        feedDeliveredKg: cumulativeFeedDeliveredKg,
        expectedConsumedKg: cumulativeFeedConsumedKg,
        actualRemainingKg: lastActualRemainingFeedKg,
        remainingFeedEverReported: remainingFeedEverReported,
      );

      rows.add(
        _DayRow(
          date: date,
          day: day,
          liveChicks: liveChicks,
          mortalityToday: mortalityToday,
          totalMortality: cumulativeMortality,
          mortalityPercent: mortalityPercent,
          dailyFeedKg: dailyFeedKg,
          totalFeedKg: cumulativeFeedConsumedKg,
          feedStockKg: feedStockKg,
          autoWeightKg: autoWeightKg,
          manualWeightKg: manualWeightKg,
          autoFcr: autoFcr,
          manualFcr: manualFcr,
          costPerKg: costPerKg,
          fraud: fraud,
        ),
      );
    }

    _rows = rows;
  }

  void _showCostConfigSheet() {
    if (_appliedRuleId == 1) {
      Get.snackbar(
        'Rule 1 Active Hai',
        'Abhi Cost/Kg "Rule 1 (Big/Small Auto Size)" ke saved rates se aa '
        'raha hai. Yeh fallback settings sirf tab use hoti hain jab Rule 2 '
        'ho ya koi rule set na ho.',
        backgroundColor: Colors.blue.shade700,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
        duration: const Duration(seconds: 4),
      );
      return;
    }

    final chickCtrl = TextEditingController(
      text: _fallbackChickPrice.toString(),
    );
    final feedCtrl = TextEditingController(text: _fallbackFeedRate.toString());
    final adminCtrl = TextEditingController(text: _fallbackAdminCost.toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cost/Kg Calculation Settings',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Yeh numbers "Per Kg Rate" column ke liye use honge (running '
              'estimate — cost ÷ live biomass).',
              style: TextStyle(fontSize: 11.5, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: chickCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Chick Price / Piece (₹)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: feedCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Feed Rate / Kg (₹)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: adminCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Admin Cost / Kg (₹)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  final chick = double.tryParse(chickCtrl.text.trim()) ?? 45.0;
                  final feed = double.tryParse(feedCtrl.text.trim()) ?? 38.0;
                  final admin = double.tryParse(adminCtrl.text.trim()) ?? 2.0;

                  await CompanyStore.instance.setString(
                    'runningCostConfig',
                    jsonEncode({
                      'chickPricePerPiece': chick,
                      'feedRatePerKg': feed,
                      'adminCostPerKg': admin,
                    }),
                  );

                  setState(() {
                    _fallbackChickPrice = chick;
                    _fallbackFeedRate = feed;
                    _fallbackAdminCost = admin;
                    _computeRows();
                  });

                  if (!mounted) return;
                  Navigator.pop(context);
                  Get.snackbar(
                    'Saved ✅',
                    'Cost settings update ho gayi.',
                    backgroundColor: primaryGreen,
                    colorText: Colors.white,
                    snackPosition: SnackPosition.BOTTOM,
                    margin: const EdgeInsets.all(15),
                  );
                },
                child: const Text(
                  'Save Karo',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _alertText(String text, AlertLevel? level) {
    Color color;
    switch (level) {
      case AlertLevel.red:
        color = Colors.red.shade700;
        break;
      case AlertLevel.yellow:
        color = Colors.amber.shade700;
        break;
      case AlertLevel.green:
        color = Colors.green.shade700;
        break;
      default:
        color = Colors.black87;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (level != null) ...[
          Container(
            width: 8 * _tableScale,
            height: 8 * _tableScale,
            margin: EdgeInsets.only(right: 5 * _tableScale),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.6),
                  blurRadius: 4,
                  spreadRadius: 0.5,
                ),
              ],
            ),
          ),
        ],
        Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: level != null ? FontWeight.bold : FontWeight.normal,
            fontSize: 11.5 * _tableScale,
          ),
        ),
      ],
    );
  }

  Widget _riskBadge(FraudRiskAssessment fraud) {
    late List<Color> gradientColors;
    late Color glowColor;
    late String label;
    switch (fraud.riskLevel) {
      case 'high':
        gradientColors = [Colors.red.shade400, Colors.red.shade800];
        glowColor = Colors.red.shade700;
        label = '🚨 High';
        break;
      case 'watch':
        gradientColors = [Colors.orange.shade300, Colors.orange.shade800];
        glowColor = Colors.orange.shade700;
        label = '⚠️ Watch';
        break;
      case 'safe':
        gradientColors = [Colors.green.shade400, Colors.green.shade800];
        glowColor = Colors.green.shade700;
        label = '✅ OK';
        break;
      default:
        gradientColors = [Colors.grey.shade400, Colors.grey.shade600];
        glowColor = Colors.grey;
        label = '—';
    }
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: 9 * _tableScale, vertical: 5 * _tableScale),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(0.45),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.6),
            blurRadius: 1,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 10.5 * _tableScale,
          shadows: const [Shadow(color: Colors.black26, blurRadius: 2)],
        ),
      ),
    );
  }

  // ── Row Tap → Us din ke liye naya Flock Record ('cost') entry add karo ───
  // NOTE: Feed Bags (delivered) field yahan JAAN-BOOJH KAR nahi hai — woh
  // Office Manager "+Flock Record" (Cost Entry) se seedha batch_detail_screen
  // se bharte hain. Yeh dialog sirf Field-level entries (Mortality, Weight,
  // Remaining Feed) ke liye hai.
  void _showEditDayDialog(_DayRow row) {
    final mortalityCtrl = TextEditingController();
    final weightCtrl = TextEditingController();
    final remainingFeedCtrl = TextEditingController();
    final String dateStr = _fmtDate(row.date);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [accentGreen, primaryGreen],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryGreen.withOpacity(0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.edit_calendar_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Entry — $dateStr (Din ${row.day})',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Live Chicks (is din tak): ${row.liveChicks}',
                  style: const TextStyle(fontSize: 11.5, color: Colors.black87),
                ),
              ),
              TextField(
                controller: mortalityCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Mortality (is din ki nayi entry)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Avg Weight (kg)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: remainingFeedCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Remaining Feed Bags (optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Yeh ek NAYI entry add karega (Flock Record jaisa) — is din '
                'ke pehle se maujood data mein add hoga, overwrite nahi. Feed '
                'Bags delivery Office Manager "+Flock Record" se alag bharte hain.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 4,
              shadowColor: primaryGreen.withOpacity(0.6),
            ),
            onPressed: () => _saveDayEntry(
              dialogContext: context,
              dateStr: dateStr,
              weightInput: weightCtrl.text.trim(),
              mortalityInput: mortalityCtrl.text.trim(),
              feedInput: '',
              remainingFeedInput: remainingFeedCtrl.text.trim(),
            ),
            child: const Text(
              'Save Karo',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveDayEntry({
    required BuildContext dialogContext,
    required String dateStr,
    required String weightInput,
    required String mortalityInput,
    required String feedInput,
    required String remainingFeedInput,
  }) async {
    if (weightInput.isEmpty &&
        mortalityInput.isEmpty &&
        feedInput.isEmpty &&
        remainingFeedInput.isEmpty) {
      Get.snackbar(
        'Validation Error ⚠️',
        'Kripya kam se kam ek entry bharein!',
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      return;
    }

    final double? weightVal = double.tryParse(weightInput);
    final int? mortalityVal = int.tryParse(mortalityInput);
    final int? feedVal = int.tryParse(feedInput);
    final int? remainingVal = int.tryParse(remainingFeedInput);

    if ((weightVal != null && weightVal < 0) ||
        (mortalityVal != null && mortalityVal < 0) ||
        (remainingVal != null && remainingVal < 0)) {
      Get.snackbar(
        'Invalid Value ⚠️',
        'Weight, Mortality aur Remaining Feed negative nahi ho sakti!',
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      return;
    }

    int currentTotalFeed = 0;
    int totalMortalitySoFar = 0;
    int totalChicksSoldSoFar = 0;
    for (final e in _localDailyEntries) {
      final type = e['type'].toString().toLowerCase();
      if (type == 'cost') {
        currentTotalFeed += int.tryParse(e['feed'].toString()) ?? 0;
        totalMortalitySoFar += int.tryParse(e['mortality'].toString()) ?? 0;
      } else if (type == 'sale') {
        totalChicksSoldSoFar += int.tryParse(e['chicksSold'].toString()) ?? 0;
      }
    }

    if (feedVal != null && feedVal < 0 && (currentTotalFeed + feedVal) < 0) {
      Get.snackbar(
        'Invalid Correction ⚠️',
        'Total Feed Bags $currentTotalFeed hain. Itna minus nahi kar sakte!',
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      return;
    }

    if (mortalityVal != null && mortalityVal > 0) {
      final int initialChicks = widget.batchData['chicksCount'] ?? 0;
      final int currentLiveChicks =
          initialChicks - totalMortalitySoFar - totalChicksSoldSoFar;
      if (mortalityVal > currentLiveChicks) {
        Get.snackbar(
          'Invalid Mortality ⚠️',
          'Mortality ($mortalityVal) live chicks ($currentLiveChicks) se jyada nahi ho sakti!',
          backgroundColor: Colors.red.shade600,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(15),
        );
        return;
      }
    }

    final int sameDateCostCount = _localDailyEntries
        .where(
          (e) =>
              e['type'].toString().toLowerCase() == 'cost' &&
              e['date'].toString() == dateStr,
        )
        .length;
    if (sameDateCostCount >= 3) {
      Get.snackbar(
        'Limit Reached ⚠️',
        '$dateStr ko 3 cost entries pehle se save hain. Max 3 allowed!',
        backgroundColor: Colors.orange.shade700,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? farmersJson = prefs.getString('companyFarmers');
      if (farmersJson == null) return;

      List<dynamic> farmersList = jsonDecode(farmersJson);
      final Map<String, dynamic> logEntry = {
        'type': 'cost',
        'date': dateStr,
        'weight': weightInput.isEmpty ? '0' : weightInput,
        'mortality': mortalityInput.isEmpty ? '0' : mortalityInput,
        'feed': feedInput.isEmpty ? '0' : feedInput,
        'remainingFeed': remainingFeedInput.isEmpty ? '0' : remainingFeedInput,
        'enteredBy': widget.userRole,
        'timestamp': DateTime.now().toIso8601String(),
      };

      List<dynamic>? updatedDailyEntries;
      for (var farmerItem in farmersList) {
        if (farmerItem['id'] == widget.farmerId) {
          for (var batchItem in (farmerItem['batches'] ?? [])) {
            if (batchItem['id'] == widget.batchData['id']) {
              batchItem['dailyEntries'] ??= [];
              batchItem['dailyEntries'].add(logEntry);
              updatedDailyEntries = batchItem['dailyEntries'];
              break;
            }
          }
          break;
        }
      }

      if (updatedDailyEntries == null) {
        Get.snackbar(
          'Error ⚠️',
          'Batch nahi mila, entry save nahi ho payi.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(15),
        );
        return;
      }

      // ✅ FIX: CompanyStore.setString use kiya (raw prefs.setString nahi) —
      // isse yeh cloud (Firestore) pe bhi push hoga, warna app-restart pe
      // purana data wapas load ho ke isko overwrite kar deta.
      await CompanyStore.instance.setString(
        'companyFarmers',
        jsonEncode(farmersList),
      );

      setState(() {
        _localDailyEntries = List<dynamic>.from(updatedDailyEntries!);
        _computeRows();
      });

      if (!mounted) return;
      Navigator.pop(dialogContext);
      Get.snackbar(
        'Saved ✅',
        '$dateStr ki entry save ho gayi — table update ho gayi hai.',
        backgroundColor: primaryGreen,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
    } catch (e) {
      Get.snackbar(
        'Error ⚠️',
        'Save nahi ho paya: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF4EF),
      extendBodyBehindAppBar: false,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryGreen, accentGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: primaryGreen.withOpacity(0.45),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text(
              'Daily Update List',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
                shadows: [Shadow(color: Colors.black26, blurRadius: 4)],
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.settings_rounded,
                        color: Colors.white),
                    tooltip: 'Cost Settings',
                    onPressed: _showCostConfigSheet,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: primaryGreen))
          : Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFEFF4EF), Color(0xFFF9FBF9)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                children: [
                  // ── 💰 Cost info banner (floating glassy card) ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.shade100.withOpacity(0.9),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                          const BoxShadow(
                            color: Colors.white,
                            blurRadius: 1,
                            offset: Offset(-1, -1),
                          ),
                        ],
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blue.shade300,
                                  Colors.blue.shade600
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.shade200,
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text('💰', style: TextStyle(fontSize: 15)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _appliedRuleId == 1
                                  ? 'Cost/Kg abhi "Rule 1 (Big/Small Auto Size)" ke saved rates se aa raha hai (weight ke hisaab se auto).'
                                  : 'Cost/Kg abhi ⚙️ Fallback Settings se aa raha hai (Rule 2 mein cost fields nahi hain abhi).',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.blue.shade900,
                                  height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── 🔍 List Zoom — neumorphic pill control ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.zoom_in_rounded,
                                  size: 16, color: primaryGreen),
                              const SizedBox(width: 6),
                              const Text(
                                'List Zoom',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              _zoomButton(
                                icon: Icons.remove_rounded,
                                onTap: () => setState(() {
                                  _tableScale =
                                      (_tableScale - 0.1).clamp(0.5, 1.8);
                                }),
                              ),
                              Container(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 10),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [primaryGreen, accentGreen],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: primaryGreen.withOpacity(0.35),
                                      blurRadius: 6,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  '${(_tableScale * 100).round()}%',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              _zoomButton(
                                icon: Icons.add_rounded,
                                onTap: () => setState(() {
                                  _tableScale =
                                      (_tableScale + 0.1).clamp(0.5, 1.8);
                                }),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── 👉 Tip banner ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: lightGreen,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.green.shade100),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.shade100.withOpacity(0.8),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('👉', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Kisi bhi din ki ROW par TAP karke Mortality/Weight/Feed add karo. '
                              'Side mein scroll karke saare columns bhi dekh sakte ho.',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.green.shade900,
                                  height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── 📊 Table — floating elevated card ──
                  Expanded(
                    child: _rows.isEmpty
                        ? const Center(child: Text('Koi din data nahi hai'))
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.12),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SingleChildScrollView(
                                  child: DataTable(
                                    showCheckboxColumn: false,
                                    headingRowColor: WidgetStateProperty.all(
                                      primaryGreen,
                                    ),
                                    headingTextStyle: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11.5 * _tableScale,
                                      letterSpacing: 0.2,
                                    ),
                                    dataTextStyle: TextStyle(
                                      fontSize: 11.5 * _tableScale,
                                    ),
                                    columnSpacing: 18 * _tableScale,
                                    horizontalMargin: 12 * _tableScale,
                                    dataRowMinHeight: 42 * _tableScale,
                                    dataRowMaxHeight: 58 * _tableScale,
                                    columns: const [
                                      DataColumn(label: Text('Edit')),
                                      DataColumn(label: Text('Risk')),
                                      DataColumn(label: Text('Date')),
                                      DataColumn(label: Text('Din')),
                                      DataColumn(label: Text('Live Chicks')),
                                      DataColumn(label: Text('Mortality')),
                                      DataColumn(label: Text('Total Mort.')),
                                      DataColumn(label: Text('Mort. %')),
                                      DataColumn(
                                          label: Text('Daily Feed (kg)')),
                                      DataColumn(
                                          label: Text('Total Feed (kg)')),
                                      DataColumn(
                                          label: Text('Feed Stock (kg)')),
                                      DataColumn(label: Text('Wt Auto (kg)')),
                                      DataColumn(
                                          label: Text('Wt Manual (kg)')),
                                      DataColumn(label: Text('FCR Auto')),
                                      DataColumn(label: Text('FCR Manual')),
                                      DataColumn(label: Text('Cost/Kg (₹)')),
                                    ],
                                    rows: _rows
                                        .asMap()
                                        .entries
                                        .map(
                                          (entry) {
                                            final i = entry.key;
                                            final r = entry.value;
                                            final bool isHigh =
                                                r.fraud.riskLevel == 'high';
                                            final bool isEven = i % 2 == 0;
                                            return DataRow(
                                              color: WidgetStateProperty.all(
                                                isHigh
                                                    ? Colors.red.shade50
                                                    : (isEven
                                                        ? Colors.white
                                                        : lightGreen
                                                            .withOpacity(0.5)),
                                              ),
                                              onSelectChanged: (_) =>
                                                  _showEditDayDialog(r),
                                              cells: [
                                                DataCell(
                                                  _editButton(
                                                      () => _showEditDayDialog(
                                                          r)),
                                                ),
                                                DataCell(_riskBadge(r.fraud)),
                                                DataCell(
                                                    Text(_fmtDate(r.date))),
                                                DataCell(Text('${r.day}')),
                                                DataCell(
                                                    Text('${r.liveChicks}')),
                                                DataCell(
                                                  Text(
                                                    '${r.mortalityToday}',
                                                    style: TextStyle(
                                                      color: r.mortalityToday >
                                                              0
                                                          ? Colors.red
                                                          : Colors.black87,
                                                      fontWeight:
                                                          r.mortalityToday > 0
                                                              ? FontWeight.bold
                                                              : FontWeight
                                                                  .normal,
                                                    ),
                                                  ),
                                                ),
                                                DataCell(Text(
                                                    '${r.totalMortality}')),
                                                DataCell(
                                                  _alertText(
                                                    '${r.mortalityPercent.toStringAsFixed(2)}%',
                                                    PerformanceAlertEngine
                                                        .evaluateMortality(
                                                      r.mortalityPercent,
                                                      _performanceConfig,
                                                      dayNumber: r.day,
                                                    ),
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(r.dailyFeedKg
                                                      .toStringAsFixed(2)),
                                                ),
                                                DataCell(
                                                  Text(r.totalFeedKg
                                                      .toStringAsFixed(2)),
                                                ),
                                                DataCell(
                                                  Text(r.feedStockKg
                                                      .toStringAsFixed(2)),
                                                ),
                                                DataCell(
                                                  Text(r.autoWeightKg
                                                      .toStringAsFixed(3)),
                                                ),
                                                DataCell(
                                                  Text(
                                                    r.manualWeightKg != null
                                                        ? r.manualWeightKg!
                                                            .toStringAsFixed(3)
                                                        : '—',
                                                  ),
                                                ),
                                                DataCell(
                                                  _alertText(
                                                    r.autoFcr
                                                        .toStringAsFixed(3),
                                                    r.autoFcr > 0
                                                        ? PerformanceAlertEngine
                                                            .evaluateFcr(
                                                            r.autoFcr,
                                                            _performanceConfig,
                                                            dayNumber: r.day,
                                                          )
                                                        : null,
                                                  ),
                                                ),
                                                DataCell(
                                                  r.manualFcr != null
                                                      ? _alertText(
                                                          r.manualFcr!
                                                              .toStringAsFixed(
                                                                  3),
                                                          PerformanceAlertEngine
                                                              .evaluateFcr(
                                                            r.manualFcr!,
                                                            _performanceConfig,
                                                            dayNumber: r.day,
                                                          ),
                                                        )
                                                      : const Text('—'),
                                                ),
                                                DataCell(
                                                  Text(
                                                    '₹${r.costPerKg.toStringAsFixed(2)}',
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        )
                                        .toList(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  // ── Neumorphic circular zoom (−/+) button ──
  Widget _zoomButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Icon(icon, size: 16, color: primaryGreen),
      ),
    );
  }

  // ── Raised gradient circular Edit button (row action) ──
  Widget _editButton(VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(6 * _tableScale),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accentGreen, primaryGreen],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: primaryGreen.withOpacity(0.4),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.edit_note_rounded,
          color: Colors.white,
          size: 16 * _tableScale,
        ),
      ),
    );
  }
}
