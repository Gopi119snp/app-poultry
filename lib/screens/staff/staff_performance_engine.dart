import 'dart:convert';
import '../../services/company_store.dart';
import '../home/purchase_expense_screen.dart' show ensureFeedStockMigrated;
import '../../utils/weight_growth_rule_engine.dart';
import 'staff_performance_benchmark_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 📊 STAFF PERFORMANCE ENGINE
// Staff Performance report ke saare screens (Staff List, Staff Detail,
// Farmer List, Farmer Detail) isi file se data lete hain — taaki formula
// har jagah SAME rahe (dobara alag-alag na likha jaaye).
//
// ✅ MANUAL vs AUTO RULE (Gopi ke confirm kiye anusaar):
//   - Mortality hamesha "actual/manual" hoti hai (jo bhi field mein report
//     hui), koi auto-estimate nahi hoti.
//   - Weight: agar us din (ya usse pehle ka latest) manual report hua hai,
//     to WAHI use hoga. Agar kabhi manual report hi nahi hui, to
//     WeightGrowthRuleConfig curve se AUTO-estimated weight fallback ke
//     roop mein use hoti hai (jaisa daily_update_list_screen.dart mein hai).
//   - FCR: upar wali hi weight (manual-priority/auto-fallback) se calculate
//     hoti hai, isliye FCR bhi automatically manual-priority follow karta
//     hai.
//   - Har daily point par `weightIsManual`/`fcrIsManual` flag bhi milta hai
//     taaki graph mein Owner ko pata chale kaunsa point असल report hai aur
//     kaunsa estimate.
// ═══════════════════════════════════════════════════════════════════════════

// ── Batch scope — Owner decide karta hai report kis data par based ho ──────
enum BatchScope { current, all, lastN }

// ── Date helpers (dusri files jaisa hi dd/MM/yyyy parser) ─────────────────
DateTime? parseDdMmYyyy(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final parts = s.trim().split('/');
  if (parts.length != 3) return null;
  try {
    final int day = int.parse(parts[0]);
    final int month = int.parse(parts[1]);
    final int year = int.parse(parts[2]);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final dt = DateTime(year, month, day);
    if (dt.year != year || dt.month != month || dt.day != day) return null;
    return dt;
  } catch (_) {
    return null;
  }
}

// ── Standard age → target weight (gram) curve — batch_performance_screen.dart
// aur batch_detail_screen.dart mein bhi yehi hardcoded curve use hoti hai,
// isliye "Weight Growth %" ka matlab dono jagah SAME rahega.
int standardTargetWeightGrams(int daysOld) {
  if (daysOld <= 0) return 40;
  if (daysOld <= 7) return 40 + (daysOld * 20);
  if (daysOld <= 14) return 180 + ((daysOld - 7) * 38);
  if (daysOld <= 21) return 446 + ((daysOld - 14) * 64);
  if (daysOld <= 28) return 894 + ((daysOld - 21) * 85);
  return 1489 + ((daysOld - 28) * 90);
}

// ═══════════════════════════════════════════════════════════════════════════
// 📅 DAILY METRIC POINT (ek batch ke ek din ka data — graph ke liye)
// ═══════════════════════════════════════════════════════════════════════════
class FarmerDailyPoint {
  final int day; // batch start se din number (0 = baseline/start, 1, 2, 3...)
  final DateTime date;
  final int mortalityToday;
  final int cumulativeMortality;
  final double mortalityPct; // cumulative % of initial chicks
  final double weightKg; // manual (agar hai) warna auto-estimate — BLUE line
  final bool weightIsManual;
  final double autoWeightKg; // hamesha pure standard-curve estimate — RED line
  final double fcr; // cumulative feed / cumulative biomass
  final bool fcrIsManual; // weight manual thi to FCR bhi "manual-based" hai
  final double weightGrowthPct; // weightKg vs standard target, us din ke

  const FarmerDailyPoint({
    required this.day,
    required this.date,
    required this.mortalityToday,
    required this.cumulativeMortality,
    required this.mortalityPct,
    required this.weightKg,
    required this.weightIsManual,
    required this.autoWeightKg,
    required this.fcr,
    required this.fcrIsManual,
    required this.weightGrowthPct,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// 🐔 FARMER-BATCH SUMMARY — ek farmer ke ek batch ka final result + daily
// points (graph ke liye)
// ═══════════════════════════════════════════════════════════════════════════
class FarmerBatchSummary {
  final String farmerId;
  final String farmerName;
  final String batchId;
  final String status;
  final DateTime startDate;
  final int daysOld;
  final int initialChicks;

  final double finalMortalityPct;
  final double finalFcr;
  final double finalWeightGrowthPct;
  final bool hasWeightData;
  final bool hasFeedData;

  final List<FarmerDailyPoint> dailyPoints;

  const FarmerBatchSummary({
    required this.farmerId,
    required this.farmerName,
    required this.batchId,
    required this.status,
    required this.startDate,
    required this.daysOld,
    required this.initialChicks,
    required this.finalMortalityPct,
    required this.finalFcr,
    required this.finalWeightGrowthPct,
    required this.hasWeightData,
    required this.hasFeedData,
    required this.dailyPoints,
  });

  PerformanceRating fcrRating(StaffPerformanceBenchmark b) =>
      b.rateFcr(finalFcr);
  PerformanceRating mortalityRating(StaffPerformanceBenchmark b) =>
      b.rateMortality(finalMortalityPct);
  PerformanceRating weightGrowthRating(StaffPerformanceBenchmark b) =>
      b.rateWeightGrowth(finalWeightGrowthPct);

  PerformanceRating overallRating(StaffPerformanceBenchmark b) =>
      StaffPerformanceBenchmark.combined(
        fcr: fcrRating(b),
        mortality: mortalityRating(b),
        weightGrowth: weightGrowthRating(b),
      );

  // ═══════════════════════════════════════════════════════════════════════
  // 📋 DATA RELIABILITY SCORE — kitne % din ka weight/FCR data ASAL MEIN
  // manually report hua (na ki sirf standard curve se estimate). Mortality
  // ismein nahi aati kyunki wo hamesha hi actual/reported hoti hai.
  //
  // Ye batata hai ki FCR/Weight Growth ki rating (Achha/Average/Kharab)
  // par kitna bharosa kiya jaaye — agar zyada tar din auto-estimate se
  // chale hain, to rating farmer ki asal performance nahi, sirf ek
  // andaza reflect karti hai.
  // ═══════════════════════════════════════════════════════════════════════
  double get manualReportReliability {
    final real = dailyPoints.where((p) => p.day > 0).toList();
    if (real.isEmpty) return 0.0;
    final manualCount = real.where((p) => p.weightIsManual).length;
    return (manualCount / real.length) * 100;
  }

  // Bahut kam din ka data ho (jaise batch abhi 1-2 din ka hi hai) to
  // reliability % khud hi meaningless ho jaata hai — UI isko dikha ke
  // "itna kam data hai" jaisa note de sakti hai.
  bool get hasEnoughDataForReliability =>
      dailyPoints.where((p) => p.day > 0).length >= 3;

  // ═══════════════════════════════════════════════════════════════════════
  // ⚠️ DECLINE TREND DETECTION — batch ke apne hi daily data se nikalta hai
  // (koi purani history save karne ki zaroorat nahi). Batch ke BEECH ke
  // performance ko ABHI (latest/final) ke performance se compare karta hai
  // — agar rating gir rahi hai (achha → average, average → kharab, ya
  // achha → kharab), to alert milta hai. Sirf "abhi kharab hai" pe alert
  // nahi deta — sirf tab jab GIRAWAT ho rahi ho.
  // ═══════════════════════════════════════════════════════════════════════
  PerformanceTrendAlert? trendAlert(StaffPerformanceBenchmark b) {
    final real = dailyPoints.where((p) => p.day > 0).toList();
    // Bahut kam din ka data hai — trend batana bharosemand nahi hoga
    if (real.length < 4) return null;

    final midIdx = (real.length / 2).floor().clamp(0, real.length - 1);
    final mid = real[midIdx];

    PerformanceRating rateAt(FarmerDailyPoint p) =>
        StaffPerformanceBenchmark.combined(
          fcr: b.rateFcr(p.fcr),
          mortality: b.rateMortality(p.mortalityPct),
          weightGrowth: b.rateWeightGrowth(p.weightGrowthPct),
        );

    int score(PerformanceRating r) => r == PerformanceRating.good
        ? 2
        : (r == PerformanceRating.average ? 1 : 0);

    final earlyRating = rateAt(mid);
    final finalRating = overallRating(b);
    final int diff = score(earlyRating) - score(finalRating);

    if (diff <= 0) return null; // stable hai ya sudhar raha hai — alert nahi

    final bool isNowPoor = finalRating == PerformanceRating.poor;
    return PerformanceTrendAlert(
      farmerName: farmerName,
      batchId: batchId,
      severity: isNowPoor ? TrendSeverity.danger : TrendSeverity.caution,
      earlyLabel: _ratingWord(earlyRating),
      currentLabel: _ratingWord(finalRating),
      message: isNowPoor
          ? '$farmerName ka batch pehle "${_ratingWord(earlyRating)}" tha, '
                'ab "${_ratingWord(finalRating)}" ho chuka hai — agar dhyan '
                'nahi diya gaya to ye farmer company ko LOSS de sakta hai.'
          : '$farmerName ka performance "${_ratingWord(earlyRating)}" se '
                '"${_ratingWord(finalRating)}" ki taraf girta ja raha hai — '
                'abhi dhyan do taaki aage aur na bigde.',
    );
  }

  String _ratingWord(PerformanceRating r) {
    switch (r) {
      case PerformanceRating.good:
        return 'Achha';
      case PerformanceRating.average:
        return 'Average';
      case PerformanceRating.poor:
        return 'Kharab';
    }
  }
}

enum TrendSeverity { caution, danger }

class PerformanceTrendAlert {
  final String farmerName;
  final String batchId;
  final TrendSeverity severity;
  final String earlyLabel;
  final String currentLabel;
  final String message;

  const PerformanceTrendAlert({
    required this.farmerName,
    required this.batchId,
    required this.severity,
    required this.earlyLabel,
    required this.currentLabel,
    required this.message,
  });
}

// ── Helper: farmer ke allocatedEmployees list se employee-name nikalna ────
List<Map<String, dynamic>> farmerAllocatedEmployees(
  Map<String, dynamic> farmer,
) {
  final raw = farmer['allocatedEmployees'];
  if (raw is! List) return [];
  return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

/// Ek employee (staff) ke under jitne farmers allocate hain, unki list.
List<Map<String, dynamic>> farmersUnderEmployee(
  List<Map<String, dynamic>> allFarmers,
  String employeeId,
) {
  return allFarmers.where((f) {
    return farmerAllocatedEmployees(
      f,
    ).any((e) => e['id']?.toString() == employeeId);
  }).toList();
}

/// Farmer ke batches mein se scope (current/all/lastN) ke hisaab se
/// filtered batches nikalta hai — sabse purane se naye order mein.
List<Map<String, dynamic>> _filterBatchesByScope(
  Map<String, dynamic> farmer,
  BatchScope scope,
  int lastN,
) {
  final batches = ((farmer['batches'] as List?) ?? [])
      .map((b) => Map<String, dynamic>.from(b as Map))
      .toList();
  if (batches.isEmpty) return [];

  if (scope == BatchScope.current) {
    const runningStatuses = {'ACTIVE', 'LIFTING READY', 'PARTIAL LIFTED'};
    final running = batches
        .where(
          (b) => runningStatuses.contains(
            (b['status'] ?? '').toString().toUpperCase(),
          ),
        )
        .toList();
    if (running.isNotEmpty) return [running.last];
    // Koi running batch nahi — sabse recent batch (chahe completed ho) dikha do
    return [batches.last];
  }

  if (scope == BatchScope.lastN) {
    if (lastN <= 0 || lastN >= batches.length) return batches;
    return batches.sublist(batches.length - lastN);
  }

  // BatchScope.all
  return batches;
}

// ═══════════════════════════════════════════════════════════════════════════
// 🧮 EK BATCH KA DAILY-POINTS + FINAL SUMMARY NIKALNA
// (batch_performance_screen.dart ke computation pattern se milta-julta,
// bas manual-priority weight fallback ke saath)
// ═══════════════════════════════════════════════════════════════════════════
FarmerBatchSummary? _computeBatchSummary(
  Map<String, dynamic> farmer,
  Map<String, dynamic> batch,
  WeightGrowthRuleConfig weightConfig,
) {
  final initialChicks = (batch['chicksCount'] as num?)?.toInt() ?? 0;
  if (initialChicks <= 0) return null;

  final startDate = parseDdMmYyyy(batch['startDate']?.toString());
  if (startDate == null) return null;

  String status = (batch['status'] ?? '').toString().toUpperCase().trim();
  const completedStatuses = {'COMPLETED', 'CLOSED', 'SETTLED', 'FINISHED'};
  if (completedStatuses.contains(status)) status = 'COMPLETED';

  final rawEntries = (batch['dailyEntries'] as List?) ?? [];
  final List<Map<String, dynamic>> entries = [];
  for (final rawE in rawEntries) {
    final e = Map<String, dynamic>.from(rawE as Map);
    e['_parsedDate'] = parseDdMmYyyy(e['date']?.toString());
    entries.add(e);
  }
  entries.sort((a, b) {
    final da = a['_parsedDate'] as DateTime?;
    final db = b['_parsedDate'] as DateTime?;
    if (da == null && db == null) return 0;
    if (da == null) return -1;
    if (db == null) return 1;
    return da.compareTo(db);
  });

  DateTime? lastEntryDate;
  int totalMortality = 0;
  final Map<int, int> mortalityByDay = {};
  final Map<int, double> manualWeightByDay = {}; // KG, us din report hua
  final Map<int, double> feedKgByDay = {}; // us din ka feed
  final Map<int, double> returnFeedByDay = {};

  for (final e in entries) {
    final type = (e['type'] ?? '').toString().toLowerCase();
    final d = e['_parsedDate'] as DateTime?;
    if (d != null && (lastEntryDate == null || d.isAfter(lastEntryDate!))) {
      lastEntryDate = d;
    }
    final dayNum = d != null ? d.difference(startDate).inDays + 1 : null;
    if (dayNum == null || dayNum < 1) continue;

    if (type == 'cost') {
      final mort = int.tryParse(e['mortality']?.toString() ?? '') ?? 0;
      if (mort != 0) mortalityByDay[dayNum] = (mortalityByDay[dayNum] ?? 0) + mort;
      totalMortality += mort;

      final wt = double.tryParse(e['weight']?.toString() ?? '') ?? 0.0;
      if (wt > 0) manualWeightByDay[dayNum] = wt; // manual report

      final feedKg = (e['feedTotalKg'] is num)
          ? (e['feedTotalKg'] as num).toDouble()
          : 0.0;
      if (feedKg != 0) {
        feedKgByDay[dayNum] = (feedKgByDay[dayNum] ?? 0) + feedKg;
      }
    } else if (type == 'returnfeed') {
      final rf = (e['returnFeedKg'] is num)
          ? (e['returnFeedKg'] as num).toDouble()
          : 0.0;
      if (rf != 0) returnFeedByDay[dayNum] = (returnFeedByDay[dayNum] ?? 0) + rf;
    } else if (type == 'sale') {
      // Sale ke baad bhi weight/mortality tracking calculation ke liye
      // koi extra kaam nahi — biomass 'live chicks' se hi handle ho jaata
      // hai neeche.
    }
  }

  final referenceDate = status == 'COMPLETED'
      ? (lastEntryDate ?? startDate)
      : DateTime.now();
  final daysOld = referenceDate.difference(startDate).inDays.clamp(0, 100000);

  final List<FarmerDailyPoint> dailyPoints = [];
  double cumFeedKg = 0.0;
  double cumReturnFeedKg = 0.0;
  int cumMortality = 0;
  double lastManualWeight = 0.0;
  bool everManualReported = false;

  // ✅ NEW — "Din 0" baseline point (batch start se ek din pehle): mortality
  // 0%, weight standard 40 gram (jitna chick farm par diya jaata hai). Isse
  // graph mein hamesha ek "shuruaat" ka point milta hai, taaki jis din se
  // mortality/weight change hua wo RISE saaf dikhe — sirf ek flat line na
  // lage.
  dailyPoints.add(
    FarmerDailyPoint(
      day: 0,
      date: startDate.subtract(const Duration(days: 1)),
      mortalityToday: 0,
      cumulativeMortality: 0,
      mortalityPct: 0.0,
      weightKg: 0.04,
      weightIsManual: false,
      autoWeightKg: 0.04,
      fcr: 0.0,
      fcrIsManual: false,
      weightGrowthPct: 100.0,
    ),
  );

  for (int day = 1; day <= daysOld + 1; day++) {
    cumMortality += mortalityByDay[day] ?? 0;
    cumFeedKg += feedKgByDay[day] ?? 0.0;
    cumReturnFeedKg += returnFeedByDay[day] ?? 0.0;

    final double? manualToday = manualWeightByDay[day];
    if (manualToday != null) {
      lastManualWeight = manualToday;
      everManualReported = true;
    }

    // ✅ MANUAL-PRIORITY RULE: agar kabhi manual report hui hai (aaj ya
    // pehle), to wahi latest manual weight use hogi. Warna curve se
    // AUTO-estimated weight fallback hogi.
    final bool useManual = everManualReported;
    final double autoWeightKgToday =
        WeightGrowthEngine.getBodyWeightGram(
          config: weightConfig,
          dayNumber: day,
        ) /
        1000.0;
    final double weightKg = useManual ? lastManualWeight : autoWeightKgToday;

    final int liveChicks = (initialChicks - cumMortality).clamp(
      0,
      initialChicks,
    );
    final double biomassKg = liveChicks * weightKg;
    final double netFeedKg = (cumFeedKg - cumReturnFeedKg).clamp(
      0.0,
      double.infinity,
    );
    final double fcr = biomassKg > 0 ? netFeedKg / biomassKg : 0.0;

    final double mortalityPct = initialChicks > 0
        ? (cumMortality / initialChicks) * 100
        : 0.0;
    final int targetG = standardTargetWeightGrams(day - 1);
    final double weightGrowthPct = targetG > 0
        ? ((weightKg * 1000) / targetG) * 100
        : 0.0;

    dailyPoints.add(
      FarmerDailyPoint(
        day: day,
        date: startDate.add(Duration(days: day - 1)),
        mortalityToday: mortalityByDay[day] ?? 0,
        cumulativeMortality: cumMortality,
        mortalityPct: mortalityPct,
        weightKg: weightKg,
        weightIsManual: useManual,
        autoWeightKg: autoWeightKgToday,
        fcr: fcr,
        fcrIsManual: useManual,
        weightGrowthPct: weightGrowthPct,
      ),
    );
  }

  if (dailyPoints.length <= 1) return null;
  final last = dailyPoints.last;

  return FarmerBatchSummary(
    farmerId: farmer['id']?.toString() ?? '',
    farmerName: farmer['name']?.toString() ?? '-',
    batchId: batch['batchId']?.toString() ?? batch['id']?.toString() ?? '-',
    status: status,
    startDate: startDate,
    daysOld: daysOld,
    initialChicks: initialChicks,
    finalMortalityPct: last.mortalityPct,
    finalFcr: last.fcr,
    finalWeightGrowthPct: last.weightGrowthPct,
    hasWeightData: everManualReported || dailyPoints.any((p) => p.weightKg > 0),
    hasFeedData: cumFeedKg > 0,
    dailyPoints: dailyPoints,
  );
}

/// ✅ MAIN ENTRY — kisi bhi farmers list ke liye (all ya kisi employee ke
/// under wale), scope ke hisaab se batch-summaries nikalta hai. Agar ek
/// farmer ke multiple batches scope mein aate hain (all/lastN), to sabse
/// zyada relevant/recent ek combined summary chahiye ho to caller khud
/// average nikal sakta hai — ye function raw per-batch summaries deta hai.
Future<List<FarmerBatchSummary>> computeFarmerBatchSummaries({
  required List<Map<String, dynamic>> farmers,
  BatchScope scope = BatchScope.current,
  int lastN = 1,
}) async {
  WeightGrowthRuleConfig weightConfig = WeightGrowthRuleConfig();
  try {
    final raw = await CompanyStore.instance.getString('weightGrowthRuleConfig');
    if (raw != null && raw.isNotEmpty) {
      weightConfig = WeightGrowthRuleConfig.fromJson(json.decode(raw));
    }
  } catch (_) {}

  final List<FarmerBatchSummary> results = [];
  for (final farmer in farmers) {
    final batches = _filterBatchesByScope(farmer, scope, lastN);
    for (final batch in batches) {
      final summary = _computeBatchSummary(farmer, batch, weightConfig);
      if (summary != null) results.add(summary);
    }
  }
  return results;
}

// ═══════════════════════════════════════════════════════════════════════════
// 💰 PROFIT/LOSS — farmer_profit_loss_screen.dart / income_engine.dart ka
// formula reuse (True Total Profit = Sale − Asal Cost − Op.Expense − Payout)
// ═══════════════════════════════════════════════════════════════════════════

class _CatAmount {
  final double billed;
  final double cost;
  const _CatAmount(this.billed, this.cost);
  double get income => billed - cost;
}

List<dynamic> _dedupeAllocs(List<dynamic> allocs) {
  final seen = <String>{};
  final result = <dynamic>[];
  for (final a in allocs) {
    final id = (a['allocationId'] ?? a['id'])?.toString();
    if (id != null && id.isNotEmpty) {
      if (seen.contains(id)) continue;
      seen.add(id);
    }
    result.add(a);
  }
  return result;
}

String _monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';
String _prevMonthKey(DateTime d) => _monthKey(DateTime(d.year, d.month - 1, 1));

class EmployeeFarmerProfit {
  final String farmerId;
  final String farmerName;
  final double trueTotalProfit;
  const EmployeeFarmerProfit({
    required this.farmerId,
    required this.farmerName,
    required this.trueTotalProfit,
  });
}

/// Employee ke under wale farmers ka batch-wise True Total Profit —
/// farmer_profit_loss_screen.dart ka EXACT SAME formula, bas is employee
/// ke farmers tak scoped aur diye gaye BatchScope tak limited.
// ═══════════════════════════════════════════════════════════════════════════
// 📊 COMPANY AVERAGE — poore company ke SAARE farmers (chahe kisi staff ko
// allocate ho ya na ho) ka average FCR/Mortality/Weight Growth. Isse har
// staff/farmer apne number ko "company ke against" compare kar sakte hain.
// ═══════════════════════════════════════════════════════════════════════════
class CompanyAverageMetrics {
  final double avgFcr;
  final double avgMortalityPct;
  final double avgWeightGrowthPct;
  final int sampleCount; // kitne farmer-batches se ye average bana

  const CompanyAverageMetrics({
    required this.avgFcr,
    required this.avgMortalityPct,
    required this.avgWeightGrowthPct,
    required this.sampleCount,
  });
}

Future<CompanyAverageMetrics> computeCompanyAverageMetrics({
  BatchScope scope = BatchScope.current,
  int lastN = 1,
}) async {
  final allFarmers = await CompanyStore.instance.getJsonList('companyFarmers');
  final summaries = await computeFarmerBatchSummaries(
    farmers: allFarmers,
    scope: scope,
    lastN: lastN,
  );

  if (summaries.isEmpty) {
    return const CompanyAverageMetrics(
      avgFcr: 0,
      avgMortalityPct: 0,
      avgWeightGrowthPct: 0,
      sampleCount: 0,
    );
  }

  final double avgFcr =
      summaries.fold(0.0, (s, e) => s + e.finalFcr) / summaries.length;
  final double avgMortality =
      summaries.fold(0.0, (s, e) => s + e.finalMortalityPct) /
      summaries.length;
  final double avgWeightGrowth =
      summaries.fold(0.0, (s, e) => s + e.finalWeightGrowthPct) /
      summaries.length;

  return CompanyAverageMetrics(
    avgFcr: avgFcr,
    avgMortalityPct: avgMortality,
    avgWeightGrowthPct: avgWeightGrowth,
    sampleCount: summaries.length,
  );
}


Future<List<EmployeeFarmerProfit>> computeEmployeeFarmersProfit({
  required List<Map<String, dynamic>> farmers,
  BatchScope scope = BatchScope.current,
  int lastN = 1,
}) async {
  double r1BigAdminCost = 1.50, r1SmAdminCost = 1.50;
  double r1BigTargetCost = 85.0, r1SmTargetCost = 90.0;
  double r1BigBaseComm = 8.0, r1SmBaseComm = 10.0;
  double r1BigSavingsShare = 50.0, r1SmSavingsShare = 50.0;
  double r1BigExceededShare = 50.0, r1SmExceededShare = 50.0;
  double r1BigRateBonusThresh = 110.0, r1SmRateBonusThresh = 120.0;
  double r1BigRateBonusShare = 10.0, r1SmRateBonusShare = 10.0;
  bool r1BigMedicineInProd = true, r1SmMedicineInProd = true;

  final r1Json = await CompanyStore.instance.getString('rule1SettlementConfig');
  if (r1Json != null && r1Json.isNotEmpty) {
    try {
      final r1 = Map<String, dynamic>.from(json.decode(r1Json));
      r1BigAdminCost = (r1['bigAdminCost'] ?? 1.50).toDouble();
      r1BigTargetCost = (r1['bigTargetCost'] ?? 85.0).toDouble();
      r1BigBaseComm = (r1['bigBaseComm'] ?? 8.0).toDouble();
      r1BigSavingsShare = (r1['bigSavingsShare'] ?? 50.0).toDouble();
      r1BigExceededShare = (r1['bigExceededShare'] ?? 50.0).toDouble();
      r1BigRateBonusThresh = (r1['bigRateBonusThresh'] ?? 110.0).toDouble();
      r1BigRateBonusShare = (r1['bigRateBonusShare'] ?? 10.0).toDouble();
      r1BigMedicineInProd = r1['bigMedicineInProd'] ?? true;
      r1SmAdminCost = (r1['smAdminCost'] ?? 1.50).toDouble();
      r1SmTargetCost = (r1['smTargetCost'] ?? 90.0).toDouble();
      r1SmBaseComm = (r1['smBaseComm'] ?? 10.0).toDouble();
      r1SmSavingsShare = (r1['smSavingsShare'] ?? 50.0).toDouble();
      r1SmExceededShare = (r1['smExceededShare'] ?? 50.0).toDouble();
      r1SmRateBonusThresh = (r1['smRateBonusThresh'] ?? 120.0).toDouble();
      r1SmRateBonusShare = (r1['smRateBonusShare'] ?? 10.0).toDouble();
      r1SmMedicineInProd = r1['smMedicineInProd'] ?? true;
    } catch (_) {}
  }

  List<Map<String, dynamic>> feedStock = [];
  try {
    feedStock = List<Map<String, dynamic>>.from(await ensureFeedStockMigrated());
  } catch (_) {}

  List<Map<String, dynamic>> medStock = [];
  final medJson = await CompanyStore.instance.getString('medicineStockList');
  if (medJson != null) {
    try {
      medStock = (json.decode(medJson) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {}
  }

  List<Map<String, dynamic>> chicksHistory = [];
  final chicksJson = await CompanyStore.instance.getString(
    'chicksPurchaseHistory',
  );
  if (chicksJson != null) {
    try {
      chicksHistory = (json.decode(chicksJson) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {}
  }

  _CatAmount sumChicks(String batchId, double fallbackBilled) {
    if (batchId.isEmpty) return _CatAmount(fallbackBilled, 0);
    double billed = 0, cost = 0;
    bool found = false;
    for (final purchase in chicksHistory) {
      final double rate =
          (purchase['effectiveRate'] as num?)?.toDouble() ??
          (purchase['rate'] as num?)?.toDouble() ??
          0;
      final allocs = _dedupeAllocs((purchase['allocations'] as List?) ?? []);
      for (final a in allocs) {
        if ((a['type']?.toString() ?? '').toLowerCase() == 'company' &&
            a['batchId']?.toString() == batchId) {
          final qty = (a['qty'] as num?)?.toDouble() ?? 0;
          final r = (a['rate'] as num?)?.toDouble() ?? 0;
          billed += qty * r;
          cost += qty * rate;
          found = true;
        }
      }
    }
    return found ? _CatAmount(billed, cost) : _CatAmount(fallbackBilled, 0);
  }

  _CatAmount sumFeed(String batchId) {
    if (batchId.isEmpty) return const _CatAmount(0, 0);
    double billed = 0, cost = 0;
    for (final feedType in feedStock) {
      final avg = (feedType['weightedAvgCost'] as num?)?.toDouble() ?? 0;
      final allocs = _dedupeAllocs((feedType['allocations'] as List?) ?? []);
      for (final a in allocs) {
        if (a['batchId']?.toString() == batchId) {
          final qty = (a['qty'] as num?)?.toDouble() ?? 0;
          final r = (a['rate'] as num?)?.toDouble() ?? 0;
          final costPerUnit = a['costAtAllocation'] != null
              ? (a['costAtAllocation'] as num).toDouble()
              : avg;
          billed += qty * r;
          cost += qty * costPerUnit;
        }
      }
    }
    return _CatAmount(billed, cost);
  }

  _CatAmount sumMed(String batchId) {
    if (batchId.isEmpty) return const _CatAmount(0, 0);
    double billed = 0, cost = 0;
    for (final med in medStock) {
      final avg = (med['weightedAvgCost'] as num?)?.toDouble() ?? 0;
      final allocs = _dedupeAllocs((med['allocations'] as List?) ?? []);
      for (final a in allocs) {
        if (a['batchId']?.toString() == batchId) {
          final qty = (a['qty'] as num?)?.toDouble() ?? 0;
          final r = (a['rate'] as num?)?.toDouble() ?? 0;
          final qtyBase = a['qtyInBaseUnit'] != null
              ? (a['qtyInBaseUnit'] as num).toDouble()
              : qty;
          final costPerBase = a['costAtAllocation'] != null
              ? (a['costAtAllocation'] as num).toDouble()
              : avg;
          billed += qty * r;
          cost += qtyBase * costPerBase;
        }
      }
    }
    return _CatAmount(billed, cost);
  }

  final Map<String, double> monthlyOpExpense = {};
  final otherJson = await CompanyStore.instance.getString(
    'otherExpenseHistory',
  );
  if (otherJson != null) {
    try {
      for (final rawE in (json.decode(otherJson) as List)) {
        final e = Map<String, dynamic>.from(rawE);
        final d = parseDdMmYyyy(e['date']?.toString()) ??
            DateTime.tryParse(e['date']?.toString() ?? '');
        if (d == null) continue;
        final amt = (e['amount'] as num?)?.toDouble() ?? 0.0;
        monthlyOpExpense[_monthKey(d)] = (monthlyOpExpense[_monthKey(d)] ?? 0) + amt;
      }
    } catch (_) {}
  }
  final labourJson = await CompanyStore.instance.getString(
    'labourExpenseHistory',
  );
  if (labourJson != null) {
    try {
      for (final rawE in (json.decode(labourJson) as List)) {
        final e = Map<String, dynamic>.from(rawE);
        final d = parseDdMmYyyy(e['date']?.toString()) ??
            DateTime.tryParse(e['date']?.toString() ?? '');
        if (d == null) continue;
        final amt = (e['totalAmount'] as num?)?.toDouble() ?? 0.0;
        monthlyOpExpense[_monthKey(d)] = (monthlyOpExpense[_monthKey(d)] ?? 0) + amt;
      }
    } catch (_) {}
  }

  final allFarmers = await CompanyStore.instance.getJsonList('companyFarmers');
  final Map<String, double> monthlyKgSold = {};
  for (final rawF in allFarmers) {
    final f = Map<String, dynamic>.from(rawF);
    for (final rawB in ((f['batches'] as List?) ?? [])) {
      final b = Map<String, dynamic>.from(rawB);
      for (final rawE in ((b['dailyEntries'] as List?) ?? [])) {
        final e = Map<String, dynamic>.from(rawE);
        if ((e['type'] ?? '').toString().toLowerCase() != 'sale') continue;
        final d = parseDdMmYyyy(e['date']?.toString());
        if (d == null) continue;
        final kg = double.tryParse(e['totalWeightSold']?.toString() ?? '') ?? 0.0;
        if (kg <= 0) continue;
        monthlyKgSold[_monthKey(d)] = (monthlyKgSold[_monthKey(d)] ?? 0) + kg;
      }
    }
  }

  double? prevMonthRate(DateTime saleDate) {
    final key = _prevMonthKey(saleDate);
    final exp = monthlyOpExpense[key];
    final kg = monthlyKgSold[key];
    if (exp == null || kg == null || kg <= 0) return null;
    return exp / kg;
  }

  final List<EmployeeFarmerProfit> results = [];

  for (final farmer in farmers) {
    final batches = _filterBatchesByScope(farmer, scope, lastN);
    double farmerTotal = 0.0;
    bool anyBatch = false;

    for (final batch in batches) {
      final batchId = (batch['batchId'] ?? batch['id'] ?? '').toString();
      final entries = (batch['dailyEntries'] as List?) ?? [];

      double totalWeightSoldKg = 0, totalSaleMoney = 0, latestAvgWeight = 0;
      double opExpShare = 0;
      for (final rawE in entries) {
        final e = Map<String, dynamic>.from(rawE as Map);
        final type = e['type'].toString().toLowerCase();
        if (type == 'sale') {
          final saleKg = double.tryParse(e['totalWeightSold'].toString()) ?? 0;
          totalWeightSoldKg += saleKg;
          totalSaleMoney += double.tryParse(e['totalMoney'].toString()) ?? 0;
          final wt = double.tryParse(e['avgWeightSold'].toString()) ?? 0;
          if (wt > 0) latestAvgWeight = wt;
          final saleDate = parseDdMmYyyy(e['date']?.toString());
          if (saleKg > 0 && saleDate != null) {
            final rate = prevMonthRate(saleDate);
            if (rate != null) opExpShare += saleKg * rate;
          }
        } else if (type == 'cost') {
          final wt = double.tryParse(e['weight'].toString()) ?? 0;
          if (wt > 0) latestAvgWeight = wt;
        }
      }

      if (totalWeightSoldKg <= 0) continue; // koi sale nahi — profit N/A
      anyBatch = true;

      final isBig = latestAvgWeight > 1.2;
      final adminCost = isBig ? r1BigAdminCost : r1SmAdminCost;
      final medInProd = isBig ? r1BigMedicineInProd : r1SmMedicineInProd;
      final targetCost = isBig ? r1BigTargetCost : r1SmTargetCost;
      final baseComm = isBig ? r1BigBaseComm : r1SmBaseComm;
      final savingsShare = isBig ? r1BigSavingsShare : r1SmSavingsShare;
      final exceededShare = isBig ? r1BigExceededShare : r1SmExceededShare;
      final rateBonThresh = isBig ? r1BigRateBonusThresh : r1SmRateBonusThresh;
      final rateBonShare = isBig ? r1BigRateBonusShare : r1SmRateBonusShare;

      final chickBilledFallback =
          double.tryParse(batch['totalChicksCost']?.toString() ?? '') ??
          (((batch['chicksCount'] ?? 0) as num).toDouble() *
              ((batch['chicksRate'] as num?)?.toDouble() ?? 40.0));

      final chicksAmt = sumChicks(batchId, chickBilledFallback);
      final feedAmt = sumFeed(batchId);
      final medAmt = sumMed(batchId);

      final adminIncome = totalWeightSoldKg * adminCost;
      double totalProdCost = chicksAmt.billed + feedAmt.billed + adminIncome;
      if (medInProd) totalProdCost += medAmt.billed;
      final actualCostPerKg = totalProdCost / totalWeightSoldKg;
      final costDiff = targetCost - actualCostPerKg;

      double costAdj = 0;
      if (costDiff > 0) {
        costAdj = costDiff * (savingsShare / 100);
      } else if (costDiff < 0) {
        costAdj = costDiff * (exceededShare / 100);
      }
      final avgSaleRate = totalSaleMoney / totalWeightSoldKg;
      final rateBonApplied =
          (actualCostPerKg <= targetCost) && (avgSaleRate >= rateBonThresh);
      final rateBonus = rateBonApplied
          ? (avgSaleRate - rateBonThresh) * (rateBonShare / 100)
          : 0.0;

      double finalComm = baseComm + costAdj + rateBonus;
      if (finalComm < 0) finalComm = 0;
      double farmerPayout = totalWeightSoldKg * finalComm;
      if (!medInProd) farmerPayout -= medAmt.billed;
      if (farmerPayout < 0) farmerPayout = 0;

      final trueTotal = totalSaleMoney -
          chicksAmt.cost -
          feedAmt.cost -
          medAmt.cost -
          opExpShare -
          farmerPayout;

      farmerTotal += trueTotal;
    }

    if (anyBatch) {
      results.add(
        EmployeeFarmerProfit(
          farmerId: farmer['id']?.toString() ?? '',
          farmerName: farmer['name']?.toString() ?? '-',
          trueTotalProfit: farmerTotal,
        ),
      );
    }
  }

  return results;
}
