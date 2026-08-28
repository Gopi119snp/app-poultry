import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/company_store.dart';
import '../../../utils/feed_consumption_rule_engine.dart';
import '../../../utils/weight_growth_rule_engine.dart';
import '../../../utils/fraud_risk_engine.dart';
import '../../../utils/performance_alert_engine.dart';
import '../../../services/activity_logger.dart'; // 🛑 NAYA IMPORT
import '../../../services/permission_service.dart'; // ✅ FIX — is screen mein row-edit ka koi permission check nahi tha
import '../../../widgets/permission_gate.dart'; // ✅ FIX — PermissionScreenGate ke liye

// =============================================================================
// 📅 DAILY UPDATE LIST SCREEN
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
  final bool isShortfall; // true if feedStockKg is negative
  // ✅ NEW — "Feed Stock (Manual)" column data. This is SEPARATE from
  // feedStockKg (auto) and never overwrites it. Only populated on the exact
  // day the farmer reported "Actual Remaining Feed"; other days show
  // "Not Reported Yet".
  final bool manualStockReportedToday;
  final double? manualStockReportedKg;
  final double? manualStockDiffKg; // reported - auto (+ve = surplus vs auto)
  final double? manualStockDiffPercent; // diff as % of the REPORTED value
  final double returnFeedKgToday;
  final double autoWeightKg;
  final double? manualWeightKg;
  final double autoFcr;
  final double? manualFcr;
  final double costPerKg;
  final FraudRiskAssessment fraud;
  final bool hasMismatch;
  final String? mismatchReason;

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
    required this.isShortfall,
    required this.manualStockReportedToday,
    this.manualStockReportedKg,
    this.manualStockDiffKg,
    this.manualStockDiffPercent,
    required this.returnFeedKgToday,
    required this.autoWeightKg,
    required this.manualWeightKg,
    required this.autoFcr,
    required this.manualFcr,
    required this.costPerKg,
    required this.fraud,
    this.hasMismatch = false,
    this.mismatchReason,
  });
}

// ✅ FIX: Added CloudSyncMixin
class _DailyUpdateListScreenState extends State<DailyUpdateListScreen>
    with CloudSyncMixin {
  static const Color primaryGreen = Color(0xFF1B5E20);
  static const Color accentGreen = Color(0xFF43A047);
  static const Color lightGreen = Color(0xFFE8F5E9);
  static const Color deepShadow = Color(0x33000000);

  bool _loading = true;
  double _tableScale = 1.0;
  FeedConsumptionRuleConfig get _feedConfig => widget.feedRuleConfig;
  WeightGrowthRuleConfig _weightConfig = WeightGrowthRuleConfig();
  PerformanceAlertConfig _performanceConfig = PerformanceAlertConfig();

  int? _appliedRuleId;
  Map<String, dynamic>? _rule1Config;

  // Fallback (Rule 2 / no-rule case)
  double _fallbackChickPrice = 45.0;
  double _fallbackFeedRate = 38.0;
  double _fallbackAdminCost = 2.0;
  double _fallbackKgPerBag = 50.0;

  // #22 / #23 fix: instead of silently faking a Day-1 row or silently
  // falling back to "today" for a bad start date, we track the state and
  // show an honest message in the same empty-state slot the UI already had.
  bool _batchNotStarted = false;
  bool _startDateInvalid = false;

  List<_DayRow> _rows = [];
  late List<dynamic> _localDailyEntries;

  // ── 🔐 PERMISSION FLAGS ─────────────────────────────────────────────────
  bool _canAddWeight = false;
  bool _canAddMortality = false;
  bool _canAddRemainingFeed = false;
  bool get _canEditAnyField =>
      _canAddWeight || _canAddMortality || _canAddRemainingFeed;

  @override
  void initState() {
    super.initState();
    _localDailyEntries = List<dynamic>.from(widget.dailyEntries);
    _loadAndCompute();
    _loadEditPermissionFlags();
    startCloudSync(); // ✅ FIX
  }

  Future<void> _loadEditPermissionFlags() async {
    final weight = await PermissionService.canNested('averageWeight', 'add');
    final mortality = await PermissionService.canNested('mortality', 'add');
    final remainingFeed = await PermissionService.canNested(
      'remainingFeed',
      'add',
    );
    if (!mounted) return;
    setState(() {
      _canAddWeight = weight;
      _canAddMortality = mortality;
      _canAddRemainingFeed = remainingFeed;
    });
  }

  @override
  void dispose() {
    stopCloudSync(); // ✅ FIX
    super.dispose();
  }

  @override
  Future<void> onCloudDataChanged() async {
    _loadEditPermissionFlags(); // ✅ FIX — real-time permission refresh
    try {
      final farmersJson = await CompanyStore.instance.getString(
        'companyFarmers',
      );
      if (farmersJson == null) return;
      final List<dynamic> farmersList = jsonDecode(farmersJson);
      for (final farmerItem in farmersList) {
        if (farmerItem is! Map) continue;
        if (farmerItem['id'] != widget.farmerId) continue;
        final batches = farmerItem['batches'];
        if (batches is! List) continue;
        for (final batchItem in batches) {
          if (batchItem is! Map) continue;
          if (batchItem['id'] != widget.batchData['id']) continue;
          final freshEntries = batchItem['dailyEntries'];
          if (freshEntries is List && mounted) {
            setState(() {
              _localDailyEntries = List<dynamic>.from(freshEntries);
            });
            _computeRows();
            if (mounted) setState(() {});
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('DailyUpdateList: cloud refresh failed: $e');
    }
  }

  Future<void> _loadAndCompute() async {
    final weightRaw = await CompanyStore.instance.getString(
      'weightGrowthRuleConfig',
    );
    if (weightRaw != null && weightRaw.isNotEmpty) {
      try {
        _weightConfig = WeightGrowthRuleConfig.fromJson(jsonDecode(weightRaw));
      } catch (e) {
        debugPrint('DailyUpdateList: weightGrowthRuleConfig parse failed: $e');
      }
    }

    final perfAlertRaw = await CompanyStore.instance.getString(
      'performanceAlertConfig',
    );
    if (perfAlertRaw != null && perfAlertRaw.isNotEmpty) {
      try {
        _performanceConfig = PerformanceAlertConfig.fromJson(
          jsonDecode(perfAlertRaw),
        );
      } catch (e) {
        debugPrint('DailyUpdateList: performanceAlertConfig parse failed: $e');
      }
    }

    _appliedRuleId = await CompanyStore.instance.getInt('appliedCompanyRuleId');
    if (_appliedRuleId == 1) {
      final rule1Raw = await CompanyStore.instance.getString(
        'rule1SettlementConfig',
      );
      if (rule1Raw != null && rule1Raw.isNotEmpty) {
        try {
          _rule1Config = jsonDecode(rule1Raw) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('DailyUpdateList: rule1SettlementConfig parse failed: $e');
        }
      }
    }

    final costRaw = await CompanyStore.instance.getString('runningCostConfig');
    if (costRaw != null && costRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(costRaw) as Map<String, dynamic>;
        _fallbackChickPrice = (decoded['chickPricePerPiece'] ?? 45.0)
            .toDouble();
        _fallbackFeedRate = (decoded['feedRatePerKg'] ?? 38.0).toDouble();
        _fallbackAdminCost = (decoded['adminCostPerKg'] ?? 2.0).toDouble();
        _fallbackKgPerBag = (decoded['kgPerBag'] ?? 50.0).toDouble();
      } catch (e) {
        debugPrint('DailyUpdateList: runningCostConfig parse failed: $e');
      }
    }

    _computeRows();

    if (!mounted) return;
    setState(() => _loading = false);
  }

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
    return (
      chickPrice: _fallbackChickPrice,
      feedRate: _fallbackFeedRate,
      adminCost: _fallbackAdminCost,
      kgPerBag: _fallbackKgPerBag,
    );
  }

  DateTime? _parseDdMmYyyy(dynamic raw) {
    if (raw == null) return null;
    final String s = raw.toString().trim();
    if (s.isEmpty) return null;
    try {
      final parts = s.split('/');
      if (parts.length == 3) {
        return DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
      }
    } catch (_) {}
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _computeRows() {
    final int initialChicks = widget.batchData['chicksCount'] ?? 0;
    final DateTime? parsedStart = _parseDdMmYyyy(widget.batchData['startDate']);
    _startDateInvalid = parsedStart == null;
    final DateTime startDate = parsedStart ?? DateTime.now();

    final DateTime today = DateTime.now();
    final int rawAgeDays = today.difference(startDate).inDays + 1;

    if (rawAgeDays < 1) {
      _batchNotStarted = true;
      _rows = [];
      return;
    }
    _batchNotStarted = false;
    final int chicksAgeDays = rawAgeDays;

    final List<Map<String, dynamic>> costEntries = [];
    for (final e in _localDailyEntries) {
      if (e['type'].toString().toLowerCase() != 'cost') continue;
      final d = _parseDdMmYyyy(e['date']);
      if (d == null) continue;
      final String remainingRaw = (e['remainingFeed'] ?? '').toString();
      costEntries.add({
        'date': d,
        'mortality': int.tryParse(e['mortality'].toString()) ?? 0,
        'feedBags': int.tryParse(e['feed'].toString()) ?? 0,
        'weightKg': double.tryParse(e['weight'].toString()) ?? 0.0,
        'remainingFeedBags': remainingRaw.isEmpty
            ? null
            : int.tryParse(remainingRaw),
        'hasMismatch': e['hasMismatch'] == true,
        'mismatchReason': e['mismatchReason']?.toString(),
        'timestamp': DateTime.tryParse(e['timestamp']?.toString() ?? '') ?? d,
      });
    }
    costEntries.sort(
      (a, b) =>
          (a['timestamp'] as DateTime).compareTo(b['timestamp'] as DateTime),
    );

    final List<Map<String, dynamic>> saleEntries = [];
    for (final e in _localDailyEntries) {
      if (e['type'].toString().toLowerCase() != 'sale') continue;
      final d = _parseDdMmYyyy(e['date']);
      if (d == null) continue;
      saleEntries.add({
        'date': d,
        'chicksSold': int.tryParse(e['chicksSold'].toString()) ?? 0,
      });
    }

    final List<Map<String, dynamic>> returnFeedEntries = [];
    for (final e in _localDailyEntries) {
      if (e['type'].toString().toLowerCase() != 'returnfeed') continue;
      final d = _parseDdMmYyyy(e['date']);
      if (d == null) continue;
      returnFeedEntries.add({
        'date': d,
        'kg': (e['returnFeedKg'] is num)
            ? (e['returnFeedKg'] as num).toDouble()
            : double.tryParse(e['returnFeedKg'].toString()) ?? 0.0,
      });
    }

    int cumulativeMortality = 0;
    int cumulativeSold = 0;
    double cumulativeFeedConsumedKg = 0.0;
    double cumulativeFeedConsumedKgForCost =
        0.0; // ✅ NAYA — sirf Cost/Kg ke liye

    double grossDeliveredKg = 0.0;
    double cumulativeReturnedKg = 0.0;

    double? lockedChickCost;
    double cumulativeFeedCostRs = 0.0;

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
      bool remainingFeedReportedToday = false;
      bool hasMismatchToday = false;
      final List<String> mismatchReasonsToday = [];

      double returnFeedKgToday = 0.0;
      for (final rf in returnFeedEntries) {
        if (_sameDay(rf['date'] as DateTime, date)) {
          returnFeedKgToday += rf['kg'] as double;
        }
      }

      int soldToday = 0;
      for (final s in saleEntries) {
        if (_sameDay(s['date'] as DateTime, date)) {
          soldToday += s['chicksSold'] as int;
        }
      }
      cumulativeSold += soldToday;

      for (final entry in costEntries) {
        if (_sameDay(entry['date'] as DateTime, date)) {
          mortalityToday += entry['mortality'] as int;
          feedBagsDeliveredToday += entry['feedBags'] as int;
          final w = entry['weightKg'] as double;
          if (w > 0) weightEnteredToday = w;
          final rf = entry['remainingFeedBags'] as int?;
          if (rf != null) {
            remainingFeedBagsToday = rf;
            remainingFeedReportedToday = true;
          }
          if (entry['hasMismatch'] == true) {
            hasMismatchToday = true;
            final reason = entry['mismatchReason'] as String?;
            if (reason != null && reason.isNotEmpty) {
              mismatchReasonsToday.add(reason);
            }
          }
        }
      }

      cumulativeMortality += mortalityToday;
      final int liveChicks =
          (initialChicks - cumulativeMortality - cumulativeSold).clamp(
            0,
            initialChicks,
          );
      final double mortalityPercent = initialChicks > 0
          ? (cumulativeMortality / initialChicks) * 100
          : 0.0;

      final double dailyFeedKg = FeedConsumptionEngine.calculateDayFeedKg(
        config: _feedConfig,
        liveChicks: liveChicks,
        dayNumber: day,
        entryDate: date,
      );
      cumulativeFeedConsumedKg += dailyFeedKg;
      cumulativeFeedConsumedKgForCost +=
          dailyFeedKg; // ✅ NAYA — pehle ye bhi pure-auto hi chalta hai

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

      final ratesToday = _resolveCostRates(manualWeightKg ?? autoWeightKg);

      lockedChickCost ??= initialChicks * ratesToday.chickPrice;

      final double deliveredTodayKg =
          feedBagsDeliveredToday * ratesToday.kgPerBag;
      grossDeliveredKg += deliveredTodayKg;
      cumulativeReturnedKg += returnFeedKgToday;

      cumulativeFeedCostRs += dailyFeedKg * ratesToday.feedRate;

      // ✅ FIX (Shortfall → 0): raw (unclamped) value sirf internal diff/fraud
      // check ke liye rakhi, taaki wo logic bilkul waisa hi rahe jaisa tha.
      final double rawFeedStockKg =
          grossDeliveredKg - cumulativeReturnedKg - cumulativeFeedConsumedKg;
      final double feedStockKg = rawFeedStockKg < 0 ? 0.0 : rawFeedStockKg;
      final bool isShortfall = rawFeedStockKg < 0;

      double? manualStockReportedKg;
      double? manualStockDiffKg;
      double? manualStockDiffPercent;
      if (remainingFeedReportedToday) {
        final double reportedStockKg =
            (remainingFeedBagsToday ?? 0) * ratesToday.kgPerBag;
        manualStockReportedKg = reportedStockKg;
        // ⚠️ Unchanged — diff hamesha RAW (auto-projected) value se compare
        // hoti hai, taaki fraud-detection ka behaviour bilkul same rahe.
        manualStockDiffKg = reportedStockKg - rawFeedStockKg;
        manualStockDiffPercent = reportedStockKg != 0
            ? (manualStockDiffKg / reportedStockKg) * 100
            : null;
        lastActualRemainingFeedKg = reportedStockKg;
        remainingFeedEverReported = true;

        // ✅ FIX (Cost/Kg reconciliation) — sirf COST-tracking cumulative ko
        // "asli sach" (delivered - returned - reported remaining) par anchor
        // karo. Total Feed / FCR Auto / Feed Stock columns isse touch NAHI
        // hote — wo hamesha pure auto-curve hi dikhate rahenge.
        final double impliedActualConsumedKg =
            grossDeliveredKg - cumulativeReturnedKg - reportedStockKg;
        if (impliedActualConsumedKg >= 0) {
          final double consumptionAdjustmentKg =
              impliedActualConsumedKg - cumulativeFeedConsumedKgForCost;
          cumulativeFeedConsumedKgForCost = impliedActualConsumedKg;
          cumulativeFeedCostRs += consumptionAdjustmentKg * ratesToday.feedRate;
        }
      }

      final double autoBiomassKg = liveChicks * autoWeightKg;
      final double autoFcr = autoBiomassKg > 0
          ? cumulativeFeedConsumedKg / autoBiomassKg
          : 0.0;

      double? manualFcr;
      if (manualWeightKg != null && manualWeightKg > 0) {
        final double manualBiomassKg = liveChicks * manualWeightKg;
        manualFcr = manualBiomassKg > 0
            ? cumulativeFeedConsumedKg / manualBiomassKg
            : null;
      }

      final double biomassForCost =
          (manualWeightKg != null && manualWeightKg > 0)
          ? liveChicks * manualWeightKg
          : autoBiomassKg;

      final double cumulativeAdminCost = biomassForCost * ratesToday.adminCost;
      final double cumulativeProductionCost =
          lockedChickCost + cumulativeFeedCostRs + cumulativeAdminCost;
      final double costPerKg = biomassForCost > 0
          ? cumulativeProductionCost / biomassForCost
          : 0.0;

      final FraudRiskAssessment fraud = FraudRiskEngine.assess(
        feedDeliveredKg: grossDeliveredKg - cumulativeReturnedKg,
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
          isShortfall: isShortfall,
          manualStockReportedToday: remainingFeedReportedToday,
          manualStockReportedKg: manualStockReportedKg,
          manualStockDiffKg: manualStockDiffKg,
          manualStockDiffPercent: manualStockDiffPercent,
          returnFeedKgToday: returnFeedKgToday,
          autoWeightKg: autoWeightKg,
          manualWeightKg: manualWeightKg,
          autoFcr: autoFcr,
          manualFcr: manualFcr,
          costPerKg: costPerKg,
          fraud: fraud,
          hasMismatch: hasMismatchToday,
          mismatchReason: mismatchReasonsToday.isNotEmpty
              ? mismatchReasonsToday.join(' | ')
              : null,
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
    final adminCtrl = TextEditingController(
      text: _fallbackAdminCost.toString(),
    );

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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Chick Price / Piece (₹)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: feedCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Feed Rate / Kg (₹)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: adminCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Admin Cost / Kg (₹)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
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
                      'kgPerBag': _fallbackKgPerBag,
                    }),
                  );

                  // 🛑 NAYA CODE: Activity Logger
                  ActivityLogger.log(
                    actionType: 'EDIT',
                    module: 'Settings',
                    message:
                        'Running Cost Settings update ki gayi: Chick ₹$chick, Feed ₹$feed/kg, Admin ₹$admin/kg.',
                  );
                  // 🛑 END NAYA CODE

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
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
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
                  color: color.withValues(alpha: 0.6),
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
        horizontal: 9 * _tableScale,
        vertical: 5 * _tableScale,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.45),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.6),
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
                    color: primaryGreen.withValues(alpha: 0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.edit_calendar_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Entry — $dateStr (Din ${row.day})',
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                ),
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
              if (_canAddMortality) ...[
                TextField(
                  controller: mortalityCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Mortality (is din ki nayi entry)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_canAddWeight) ...[
                TextField(
                  controller: weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Avg Weight (kg)',
                    // ✅ FIX — chhote chicks ke liye sahi tareeka batane
                    // wala hint add kiya, taaki "40 gram" ki jagah galti se
                    // "40" (matlab 40 KG) na daala jaaye.
                    hintText: 'e.g. 0.06 (60 gram) ya 1.8 (1.8 KG)',
                    helperText:
                        'Hamesha KG mein daalo — chhote chick ke liye chhoti decimal '
                        'value likho, jaise 0.04 ya 0.06',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_canAddRemainingFeed) ...[
                TextField(
                  controller: remainingFeedCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Remaining Feed Bags (optional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
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
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 4,
              shadowColor: primaryGreen.withValues(alpha: 0.6),
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
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    Get.snackbar(
      'Invalid Value ⚠️',
      message,
      backgroundColor: Colors.red.shade600,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(15),
      duration: const Duration(seconds: 6),
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

    if (weightInput.isNotEmpty && double.tryParse(weightInput) == null) {
      _showError('Weight ki value samajh nahi aayi. Sirf number likhein.');
      return;
    }
    if (mortalityInput.isNotEmpty && int.tryParse(mortalityInput) == null) {
      _showError('Mortality ki value samajh nahi aayi. Sirf number likhein.');
      return;
    }
    if (feedInput.isNotEmpty && int.tryParse(feedInput) == null) {
      _showError('Feed bags ki value samajh nahi aayi. Sirf number likhein.');
      return;
    }
    if (remainingFeedInput.isNotEmpty &&
        int.tryParse(remainingFeedInput) == null) {
      _showError(
        'Remaining feed ki value samajh nahi aayi. Sirf number likhein.',
      );
      return;
    }

    final double? weightVal = weightInput.isEmpty
        ? null
        : double.parse(weightInput);
    final int? mortalityVal = mortalityInput.isEmpty
        ? null
        : int.parse(mortalityInput);
    final int? feedVal = feedInput.isEmpty ? null : int.parse(feedInput);
    final int? remainingVal = remainingFeedInput.isEmpty
        ? null
        : int.parse(remainingFeedInput);

    if (weightVal != null && weightVal <= 0) {
      _showError('Weight 0 se bada hona chahiye.');
      return;
    }

    // ✅ FIX — Weight ek REALISTIC range mein honi chahiye (KG). Ye field
    // KG expect karta hai; agar koi galti se chick ka wazan grams mein
    // (jaise "40" ka matlab tha 40 gram / 0.04 KG) daal de, to system
    // chup-chaap use 40 KG maan leta tha. Isse Cost/Kg aur FCR Manual jaise
    // saare downstream calculations bilkul galat ho jaate the (biomass
    // itna bada ban jaata tha ki FCR round ho ke "0.000" tak dikhne lagta
    // tha, aur Cost/Kg artificially bahut kam dikhta tha). Ab koi bhi
    // biologically-impossible weight (8 KG se zyada) save hone se pehle
    // hi block ho jaati hai.
    if (weightVal != null && weightVal > 8.0) {
      _showError(
        'Aapne $weightVal KG daala hai — ye ek murgi ke liye possible '
        'nahi hai. Agar chick chhota hai (jaise 40 gram), to KG mein '
        'likhein: 0.04 — poora "40" likhne ka matlab 40 KG ho jaata hai, '
        'jo galat hai.',
      );
      return;
    }

    if ((mortalityVal != null && mortalityVal < 0) ||
        (remainingVal != null && remainingVal < 0)) {
      _showError('Mortality aur Remaining Feed negative nahi ho sakti!');
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

    final DateTime? selectedDate = _parseDdMmYyyy(dateStr);
    final int sameDateCostCount = _localDailyEntries.where((e) {
      if (e['type'].toString().toLowerCase() != 'cost') return false;
      final d = _parseDdMmYyyy(e['date']);
      return d != null && selectedDate != null && _sameDay(d, selectedDate);
    }).length;
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
        'weight': weightInput,
        'mortality': mortalityInput,
        'feed': feedInput,
        'remainingFeed': remainingFeedInput,
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

      await CompanyStore.instance.setString(
        'companyFarmers',
        jsonEncode(farmersList),
      );

      // 🛑 NAYA CODE: Activity Logger
      ActivityLogger.log(
        actionType: 'EDIT',
        module: 'Batch',
        message:
            'Batch ${widget.batchData['batchId']} ki $dateStr ki entry update ki gayi.',
      );
      // 🛑 END NAYA CODE

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
    return PermissionScreenGate(
      moduleId: 'dailyUpdateList',
      action: 'view',
      child: Scaffold(
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
                  color: primaryGreen.withValues(alpha: 0.45),
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
                      color: Colors.white.withValues(alpha: 0.15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.settings_rounded,
                        color: Colors.white,
                      ),
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
            ? const Center(
                child: CircularProgressIndicator(color: primaryGreen),
              )
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.shade100.withValues(
                                alpha: 0.9,
                              ),
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
                                    Colors.blue.shade600,
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
                                child: Text(
                                  '💰',
                                  style: TextStyle(fontSize: 15),
                                ),
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
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
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
                                Icon(
                                  Icons.zoom_in_rounded,
                                  size: 16,
                                  color: primaryGreen,
                                ),
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
                                    _tableScale = (_tableScale - 0.1).clamp(
                                      0.5,
                                      1.8,
                                    );
                                  }),
                                ),
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [primaryGreen, accentGreen],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: primaryGreen.withValues(
                                          alpha: 0.35,
                                        ),
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
                                    _tableScale = (_tableScale + 0.1).clamp(
                                      0.5,
                                      1.8,
                                    );
                                  }),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

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
                              color: Colors.green.shade100.withValues(
                                alpha: 0.8,
                              ),
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
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    Expanded(
                      child: _rows.isEmpty
                          ? Center(
                              child: Text(
                                _startDateInvalid
                                    ? 'Batch ki start date sahi format mein nahi hai — pehle use theek karein.'
                                    : _batchNotStarted
                                    ? 'Yeh batch abhi start nahi hua hai.'
                                    : 'Koi din data nahi hai',
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.12,
                                      ),
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
                                          label: Text('Daily Feed (kg)'),
                                        ),
                                        DataColumn(
                                          label: Text('Total Feed (kg)'),
                                        ),
                                        DataColumn(
                                          label: Text('Feed Stock (kg)'),
                                        ),
                                        DataColumn(
                                          label: Text('Feed Stock (Manual)'),
                                        ),
                                        DataColumn(label: Text('Wt Auto (kg)')),
                                        DataColumn(
                                          label: Text('Wt Manual (kg)'),
                                        ),
                                        DataColumn(label: Text('FCR Auto')),
                                        DataColumn(label: Text('FCR Manual')),
                                        DataColumn(label: Text('Cost/Kg (₹)')),
                                      ],
                                      rows: _rows.asMap().entries.map((entry) {
                                        final i = entry.key;
                                        final r = entry.value;
                                        final bool isHigh =
                                            r.fraud.riskLevel == 'high';
                                        final bool isEven = i % 2 == 0;
                                        final bool isEditable = _isEditableDate(
                                          r.date,
                                        );
                                        return DataRow(
                                          color: WidgetStateProperty.all(
                                            r.hasMismatch
                                                ? Colors.red.shade100
                                                : (isHigh
                                                      ? Colors.red.shade50
                                                      : (isEven
                                                            ? Colors.white
                                                            : lightGreen
                                                                  .withValues(
                                                                    alpha: 0.5,
                                                                  ))),
                                          ),
                                          onSelectChanged: !_canEditAnyField
                                              ? null
                                              : (isEditable
                                                    ? (_) =>
                                                          _showEditDayDialog(r)
                                                    : (_) {
                                                        Get.snackbar(
                                                          'Locked 🔒',
                                                          'Sirf Aaj + pichle 2 din tak hi entry edit ho sakti hai.',
                                                          backgroundColor:
                                                              Colors
                                                                  .grey
                                                                  .shade700,
                                                          colorText:
                                                              Colors.white,
                                                          snackPosition:
                                                              SnackPosition
                                                                  .BOTTOM,
                                                        );
                                                      }),
                                          cells: [
                                            DataCell(
                                              !_canEditAnyField
                                                  ? const SizedBox.shrink()
                                                  : (isEditable
                                                        ? _editButton(
                                                            () =>
                                                                _showEditDayDialog(
                                                                  r,
                                                                ),
                                                          )
                                                        : _lockedButton()),
                                            ),
                                            DataCell(_riskBadge(r.fraud)),
                                            DataCell(
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(_fmtDate(r.date)),
                                                  if (r.hasMismatch) ...[
                                                    const SizedBox(width: 4),
                                                    InkWell(
                                                      onTap: () {
                                                        showDialog(
                                                          context: context,
                                                          builder: (ctx) => AlertDialog(
                                                            title: const Text(
                                                              '⚠️ Photo Mismatch',
                                                            ),
                                                            content: Text(
                                                              r.mismatchReason ??
                                                                  'Entered value photo se match nahi hui thi.',
                                                            ),
                                                            actions: [
                                                              TextButton(
                                                                onPressed: () =>
                                                                    Navigator.pop(
                                                                      ctx,
                                                                    ),
                                                                child:
                                                                    const Text(
                                                                      'OK',
                                                                    ),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                      child: const Icon(
                                                        Icons
                                                            .warning_amber_rounded,
                                                        size: 15,
                                                        color: Colors.red,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            DataCell(Text('${r.day}')),
                                            DataCell(Text('${r.liveChicks}')),
                                            DataCell(
                                              Text(
                                                '${r.mortalityToday}',
                                                style: TextStyle(
                                                  color: r.mortalityToday > 0
                                                      ? Colors.red
                                                      : Colors.black87,
                                                  fontWeight:
                                                      r.mortalityToday > 0
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text('${r.totalMortality}'),
                                            ),
                                            DataCell(
                                              _alertText(
                                                '${r.mortalityPercent.toStringAsFixed(2)}%',
                                                PerformanceAlertEngine.evaluateMortality(
                                                  r.mortalityPercent,
                                                  _performanceConfig,
                                                  dayNumber: r.day,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                r.dailyFeedKg.toStringAsFixed(
                                                  2,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                r.totalFeedKg.toStringAsFixed(
                                                  2,
                                                ),
                                              ),
                                            ),
                                            // ─── Feed Stock (kg) ────────────────────────
                                            DataCell(
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    r.feedStockKg
                                                        .toStringAsFixed(2),
                                                    style: r.isShortfall
                                                        ? const TextStyle(
                                                            color: Colors.red,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          )
                                                        : null,
                                                  ),
                                                  if (r.isShortfall)
                                                    const Text(
                                                      'Feed Khatam',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.red,
                                                        fontStyle:
                                                            FontStyle.italic,
                                                      ),
                                                    ),
                                                  if (r.returnFeedKgToday > 0)
                                                    Text(
                                                      '↩️ Return: ${r.returnFeedKgToday.toStringAsFixed(1)} KG',
                                                      style: const TextStyle(
                                                        color: Colors.teal,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            // ─── Feed Stock (Manual) ────────────────────
                                            DataCell(
                                              r.manualStockReportedToday
                                                  ? Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          '${r.manualStockReportedKg!.toStringAsFixed(2)} KG',
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Colors
                                                                    .blueGrey,
                                                              ),
                                                        ),
                                                        Text(
                                                          '${r.manualStockDiffKg! >= 0 ? '+' : ''}'
                                                          '${r.manualStockDiffKg!.toStringAsFixed(2)} KG'
                                                          '${r.manualStockDiffPercent != null ? ' (${r.manualStockDiffPercent! >= 0 ? '+' : ''}${r.manualStockDiffPercent!.toStringAsFixed(1)}%)' : ''}',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color:
                                                                r.manualStockDiffKg! <
                                                                    0
                                                                ? Colors.red
                                                                : Colors
                                                                      .green
                                                                      .shade700,
                                                          ),
                                                        ),
                                                      ],
                                                    )
                                                  : const Text(
                                                      'Not Reported Yet',
                                                      style: TextStyle(
                                                        fontSize: 10.5,
                                                        color: Colors.grey,
                                                        fontStyle:
                                                            FontStyle.italic,
                                                      ),
                                                    ),
                                            ),
                                            DataCell(
                                              Text(
                                                r.autoWeightKg.toStringAsFixed(
                                                  3,
                                                ),
                                              ),
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
                                                r.autoFcr.toStringAsFixed(3),
                                                r.autoFcr > 0
                                                    ? PerformanceAlertEngine.evaluateFcr(
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
                                                          .toStringAsFixed(3),
                                                      PerformanceAlertEngine.evaluateFcr(
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
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
      ), // Scaffold
    ); // PermissionScreenGate
  }

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
              color: Colors.black.withValues(alpha: 0.15),
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

  bool _isEditableDate(DateTime d) {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final dateOnly = DateTime(d.year, d.month, d.day);
    final diffDays = todayOnly.difference(dateOnly).inDays;
    return diffDays >= 0 && diffDays <= 2;
  }

  Widget _lockedButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Get.snackbar(
          'Locked 🔒',
          'Sirf Aaj + pichle 2 din tak hi entry edit ho sakti hai.',
          backgroundColor: Colors.grey.shade700,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      },
      child: Container(
        padding: EdgeInsets.all(6 * _tableScale),
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.lock_outline_rounded,
          color: Colors.grey.shade600,
          size: 16 * _tableScale,
        ),
      ),
    );
  }

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
              color: primaryGreen.withValues(alpha: 0.4),
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
