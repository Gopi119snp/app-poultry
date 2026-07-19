import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:get/get.dart';
import 'dart:convert';
import '../../services/company_store.dart';
import '../../utils/feed_consumption_rule_engine.dart';

const Color _bpGreen = Color(0xFF1B5E20);

// ═══════════════════════════════════════════════════════════════════════════
// 📦 DATA MODEL
// ═══════════════════════════════════════════════════════════════════════════
class _BatchMetrics {
  final String farmerId;
  final String farmerName;
  final String batchId;
  final String status;
  final int daysOld;
  final int initialChicks;
  final int liveChicks;
  final int totalMortality;
  final double mortalityPct;
  final int totalChicksSold;
  final double totalWeightSoldKg;
  final double latestAvgWeightKg;
  final double fcr;
  final double weightGrowthPct;
  final double feedEfficiencyPct;
  final double totalFeedKg;
  final double totalExpectedFeedKg;
  final DateTime startDate;
  // 🔧 Naye fields — data-quality tracking ke liye, taaki "missing data"
  // batches galti se ranking/averages mein "best" ya "worst" ban ke na aa jaayein.
  final bool hasWeightData;
  final bool hasFeedData;
  final bool isFcrValid;
  final double totalBiomassKg;

  _BatchMetrics({
    required this.farmerId,
    required this.farmerName,
    required this.batchId,
    required this.status,
    required this.daysOld,
    required this.initialChicks,
    required this.liveChicks,
    required this.totalMortality,
    required this.mortalityPct,
    required this.totalChicksSold,
    required this.totalWeightSoldKg,
    required this.latestAvgWeightKg,
    required this.fcr,
    required this.weightGrowthPct,
    required this.feedEfficiencyPct,
    required this.totalFeedKg,
    required this.totalExpectedFeedKg,
    required this.startDate,
    required this.hasWeightData,
    required this.hasFeedData,
    required this.isFcrValid,
    required this.totalBiomassKg,
  });
}

// Ek batch ke computation ka poora result — final metrics + uske trend
// samples ek hi pass mein ek saath, taaki dono kabhi disagree na karein.
class _BatchComputation {
  final _BatchMetrics metrics;
  final List<Map<String, dynamic>> trendSamples;
  final bool isCompleted;
  _BatchComputation({
    required this.metrics,
    required this.trendSamples,
    required this.isCompleted,
  });
}

// ── Shared helpers (batch_detail_screen.dart jaisi hi formula) ─────────────
int _standardTargetWeightGrams(int daysOld) {
  if (daysOld <= 0) return 40;
  if (daysOld <= 7) return 40 + (daysOld * 20);
  if (daysOld <= 14) return 180 + ((daysOld - 7) * 38);
  if (daysOld <= 21) return 446 + ((daysOld - 14) * 64);
  if (daysOld <= 28) return 894 + ((daysOld - 21) * 85);
  return 1489 + ((daysOld - 28) * 90);
}

DateTime? _parseDdMmYyyy(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final parts = s.trim().split('/');
  if (parts.length != 3) return null;
  try {
    return DateTime(
      int.parse(parts[2]),
      int.parse(parts[1]),
      int.parse(parts[0]),
    );
  } catch (_) {
    return null;
  }
}

int _daysOldFrom(DateTime start, DateTime reference) {
  final d = reference.difference(start).inDays;
  return d < 0 ? 0 : d;
}

int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

// candidate date "current" se naya ya barabar hai kya (null-safe) — latest
// weight/entry track karne ke liye use hota hai.
bool _isNewerOrEqual(DateTime? candidate, DateTime? current) {
  if (current == null) return true;
  if (candidate == null) return true;
  return !candidate.isBefore(current);
}

// ═══════════════════════════════════════════════════════════════════════════
// 📊 BATCH PERFORMANCE SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class BatchPerformanceScreen extends StatefulWidget {
  const BatchPerformanceScreen({super.key});

  @override
  State<BatchPerformanceScreen> createState() => _BatchPerformanceScreenState();
}

class _BatchPerformanceScreenState extends State<BatchPerformanceScreen> {
  bool _isLoading = true;
  bool _hasLoadError = false; // 🔧 ab silent fail nahi hoga, banner dikhega
  bool _showActive = true; // true = Active section, false = Completed section
  String _granularity = 'Weekly';

  List<_BatchMetrics> _activeBatches = [];
  List<_BatchMetrics> _completedBatches = [];

  // Trend raw samples — {batchDay, actualG, targetG, mortalityCount, actualFeedKg, expectedFeedKg}
  List<Map<String, dynamic>> _activeTrendSamples = [];
  List<Map<String, dynamic>> _completedTrendSamples = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _hasLoadError = false;
    });

    FeedConsumptionRuleConfig feedConfig = FeedConsumptionRuleConfig(
      ruleType: FeedRuleType.standardAgeChart,
    );
    try {
      final feedRuleJson = await CompanyStore.instance.getString(
        'feedConsumptionRuleConfig',
      );
      if (feedRuleJson != null && feedRuleJson.isNotEmpty) {
        feedConfig = FeedConsumptionRuleConfig.fromJson(
          json.decode(feedRuleJson),
        );
      }
    } catch (_) {
      // Feed rule config corrupt ho to bhi default config se aage badh jaate hain —
      // ye non-critical hai isliye yahan silent fallback theek hai.
    }

    final List<_BatchMetrics> active = [];
    final List<_BatchMetrics> completed = [];
    final List<Map<String, dynamic>> activeTrend = [];
    final List<Map<String, dynamic>> completedTrend = [];
    bool loadError = false;

    try {
      final farmers = await CompanyStore.instance.getJsonList('companyFarmers');
      for (final rawF in farmers) {
        final farmer = Map<String, dynamic>.from(rawF as Map);
        final batches = (farmer['batches'] as List?) ?? [];
        for (final rawB in batches) {
          final batch = Map<String, dynamic>.from(rawB as Map);
          final computed = _computeBatchAndTrend(farmer, batch, feedConfig);
          if (computed == null) continue;

          if (computed.isCompleted) {
            completed.add(computed.metrics);
            completedTrend.addAll(computed.trendSamples);
          } else {
            active.add(computed.metrics);
            activeTrend.addAll(computed.trendSamples);
          }
        }
      }
    } catch (e, st) {
      // 🔧 Pehle yahan catch (_) {} tha — error chupchaap gum ho jaati thi
      // aur report incomplete/empty dikh jaati thi bina bataye. Ab user ko
      // banner dikhega aur console mein bhi log hoga.
      debugPrint('BatchPerformanceScreen._loadData error: $e\n$st');
      loadError = true;
    }

    if (!mounted) return;
    setState(() {
      _activeBatches = active;
      _completedBatches = completed;
      _activeTrendSamples = activeTrend;
      _completedTrendSamples = completedTrend;
      _isLoading = false;
      _hasLoadError = loadError;
    });
  }

  // ── Ek batch ke liye final metrics + trend samples ek saath compute karo ──
  _BatchComputation? _computeBatchAndTrend(
    Map<String, dynamic> farmer,
    Map<String, dynamic> batch,
    FeedConsumptionRuleConfig feedConfig,
  ) {
    final initialChicks = (batch['chicksCount'] as num?)?.toInt() ?? 0;
    if (initialChicks <= 0) return null;

    final startDate = _parseDdMmYyyy(batch['startDate']?.toString());
    if (startDate == null) return null;

    // 🔧 Status normalization ab COMPLETED/CLOSED ke alawa common synonyms
    // (SETTLED/FINISHED/DONE) ko bhi pehchanta hai, taaki wo galti se
    // Active list mein na reh jaayein.
    String status = (batch['status'] ?? '').toString().toUpperCase().trim();
    const completedStatuses = {
      'COMPLETED',
      'CLOSED',
      'SETTLED',
      'FINISHED',
      'FINISH',
      'DONE',
    };
    final isCompleted = completedStatuses.contains(status);
    if (isCompleted) status = 'COMPLETED';

    // 🔧 Entries ko date ke hisaab se sort karte hain — isse (a) "latest
    // weight" waqai latest hoti hai chahe entries kisi bhi order mein save
    // hui hon, aur (b) mortality/sale ka day-wise cumulative timeline sahi
    // banta hai.
    final rawEntries = (batch['dailyEntries'] as List?) ?? [];
    final List<Map<String, dynamic>> entries = [];
    for (final rawE in rawEntries) {
      final e = Map<String, dynamic>.from(rawE as Map);
      e['_parsedDate'] = _parseDdMmYyyy(e['date']?.toString());
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

    int totalMortality = 0;
    int totalChicksSold = 0;
    double totalWeightSoldKg = 0.0;
    double totalFeedKg = 0.0;
    double totalReturnFeedKg = 0.0;
    double latestAvgWeightKg = 0.0;
    DateTime? latestWeightDate;
    DateTime? lastEntryDate;

    // Day-indexed deltas — Expected Feed ke liye mortality/sale-adjusted
    // live-bird timeline banane ke kaam aayenge.
    final Map<int, int> mortalityByDay = {};
    final Map<int, int> soldByDay = {};
    final Map<int, double> returnFeedByDay = {};

    for (final e in entries) {
      final type = (e['type'] ?? '').toString().toLowerCase();
      final d = e['_parsedDate'] as DateTime?;
      if (d != null && (lastEntryDate == null || d.isAfter(lastEntryDate!))) {
        lastEntryDate = d;
      }
      final dayNum = d != null ? d.difference(startDate).inDays + 1 : null;

      if (type == 'sale') {
        final sold = int.tryParse(e['chicksSold']?.toString() ?? '') ?? 0;
        totalChicksSold += sold;
        totalWeightSoldKg +=
            double.tryParse(e['totalWeightSold']?.toString() ?? '') ?? 0.0;
        if (dayNum != null && dayNum >= 1 && sold != 0) {
          soldByDay[dayNum] = (soldByDay[dayNum] ?? 0) + sold;
        }

        final saleAvgWt =
            double.tryParse(e['avgWeightSold']?.toString() ?? '') ?? 0.0;
        // 🔧 Pehle sirf tab update hota tha jab latestAvgWeightKg == 0 tha,
        // isliye baad ki actual sale weight ignore ho jaati thi. Ab hamesha
        // sabse latest DATE waali weight entry use hoti hai.
        if (saleAvgWt > 0 && _isNewerOrEqual(d, latestWeightDate)) {
          latestAvgWeightKg = saleAvgWt;
          latestWeightDate = d;
        }
      } else if (type == 'cost') {
        final mort = int.tryParse(e['mortality']?.toString() ?? '') ?? 0;
        totalMortality += mort;
        if (dayNum != null && dayNum >= 1 && mort != 0) {
          mortalityByDay[dayNum] = (mortalityByDay[dayNum] ?? 0) + mort;
        }

        totalFeedKg += (e['feedTotalKg'] is num)
            ? (e['feedTotalKg'] as num).toDouble()
            : 0.0;

        final wt = double.tryParse(e['weight']?.toString() ?? '') ?? 0.0;
        if (wt > 0 && _isNewerOrEqual(d, latestWeightDate)) {
          latestAvgWeightKg = wt;
          latestWeightDate = d;
        }
      } else if (type == 'returnfeed') {
        final rf = (e['returnFeedKg'] is num)
            ? (e['returnFeedKg'] as num).toDouble()
            : 0.0;
        totalReturnFeedKg += rf;
        if (dayNum != null && dayNum >= 1 && rf != 0) {
          returnFeedByDay[dayNum] = (returnFeedByDay[dayNum] ?? 0) + rf;
        }
      }
    }

    final netFeedKgRaw = totalFeedKg - totalReturnFeedKg;
    final netFeedKg = netFeedKgRaw < 0 ? 0.0 : netFeedKgRaw;
    final hasFeedData = netFeedKg > 0;
    final hasWeightData = latestAvgWeightKg > 0;

    // 🔧 Completed batch ki age ab aaj tak nahi badhti rahegi — jis din
    // batch ki AAKHRI entry hui (best available "closing" proxy jab tak
    // dedicated closing-date field na ho) usi ko reference maan kar daysOld
    // nikalte hain. Active batches ke liye pehle jaisa DateTime.now() hi hai.
    final referenceDate = isCompleted
        ? (lastEntryDate ?? startDate)
        : DateTime.now();
    final daysOld = _daysOldFrom(startDate, referenceDate);

    // 🔧 liveChicks ab kabhi negative nahi ho sakta (duplicate/galat entries
    // se bhi 0 se neeche nahi jayega).
    final rawLiveChicks = initialChicks - totalMortality - totalChicksSold;
    final liveChicks = _clampInt(rawLiveChicks, 0, initialChicks);
    final mortalityPct = initialChicks > 0
        ? (totalMortality / initialChicks) * 100
        : 0.0;

    // 🔧 Har din ke liye mortality/sale-adjusted "live at day start" timeline —
    // ye Expected Feed (main total) aur trend chart, dono ke liye ek hi
    // source hai, taaki dono kabhi ek-dusre se disagree na karein.
    final loopDays = daysOld + 1;
    final Map<int, int> liveAtDayStart = {};
    int cumMort = 0;
    int cumSold = 0;
    for (int day = 1; day <= loopDays; day++) {
      liveAtDayStart[day] = _clampInt(
        initialChicks - cumMort - cumSold,
        0,
        initialChicks,
      );
      cumMort += mortalityByDay[day] ?? 0;
      cumSold += soldByDay[day] ?? 0;
    }

    double totalExpectedKg = 0.0;
    for (int day = 1; day <= loopDays; day++) {
      totalExpectedKg += FeedConsumptionEngine.calculateDayFeedKg(
        config: feedConfig,
        liveChicks: liveAtDayStart[day] ?? initialChicks,
        dayNumber: day,
        entryDate: startDate.add(Duration(days: day - 1)),
      );
    }

    final currentLiveWeightKg = liveChicks * latestAvgWeightKg;
    final totalBiomassKg = totalWeightSoldKg + currentLiveWeightKg;
    // ⚠️ Simplification (pehle jaisi hi): "actual consumed" = net feed
    // delivered (bags − return). Agar future mein actual-consumption
    // (wastage/spillage adjust kiya hua) data available ho, to FCR formula
    // ko us hisaab se aur behtar kiya ja sakta hai — abhi ye business
    // formula decision hai jo maine change nahi ki, sirf data accuracy
    // (negative live chicks, latest weight, sorted entries) fix ki hai.
    final actualFeedConsumedKg = netFeedKg;
    final fcr = totalBiomassKg > 0
        ? actualFeedConsumedKg / totalBiomassKg
        : 0.0;
    final isFcrValid = hasWeightData && hasFeedData && totalBiomassKg > 0;

    final targetWeightG = _standardTargetWeightGrams(daysOld);
    final actualWeightG = latestAvgWeightKg * 1000;
    final weightGrowthPct = targetWeightG > 0
        ? (actualWeightG / targetWeightG) * 100
        : 0.0;

    final feedEfficiencyPct = actualFeedConsumedKg > 0
        ? (totalExpectedKg / actualFeedConsumedKg) * 100
        : (totalExpectedKg > 0 ? 0.0 : 100.0);

    final metrics = _BatchMetrics(
      farmerId: farmer['id']?.toString() ?? '',
      farmerName: farmer['name']?.toString() ?? '-',
      batchId: batch['batchId']?.toString() ?? batch['id']?.toString() ?? '-',
      status: status,
      daysOld: daysOld,
      initialChicks: initialChicks,
      liveChicks: liveChicks,
      totalMortality: totalMortality,
      mortalityPct: mortalityPct,
      totalChicksSold: totalChicksSold,
      totalWeightSoldKg: totalWeightSoldKg,
      latestAvgWeightKg: latestAvgWeightKg,
      fcr: fcr,
      weightGrowthPct: weightGrowthPct,
      feedEfficiencyPct: feedEfficiencyPct,
      totalFeedKg: netFeedKg,
      totalExpectedFeedKg: totalExpectedKg,
      startDate: startDate,
      hasWeightData: hasWeightData,
      hasFeedData: hasFeedData,
      isFcrValid: isFcrValid,
      totalBiomassKg: totalBiomassKg,
    );

    final trendSamples = _buildTrendSamples(
      entries,
      startDate,
      feedConfig,
      liveAtDayStart,
      returnFeedByDay,
    );

    return _BatchComputation(
      metrics: metrics,
      trendSamples: trendSamples,
      isCompleted: isCompleted,
    );
  }

  // ── Day-wise trend samples (batch-age indexed, calendar date nahi) ──
  List<Map<String, dynamic>> _buildTrendSamples(
    List<Map<String, dynamic>> entries,
    DateTime startDate,
    FeedConsumptionRuleConfig feedConfig,
    Map<int, int> liveAtDayStart,
    Map<int, double> returnFeedByDay,
  ) {
    final List<Map<String, dynamic>> samples = [];

    for (final e in entries) {
      final type = (e['type'] ?? '').toString().toLowerCase();
      if (type != 'cost') continue;

      final d = e['_parsedDate'] as DateTime?;
      if (d == null) continue;
      final dayNum = d.difference(startDate).inDays + 1;
      if (dayNum < 1) continue;

      final wt = double.tryParse(e['weight']?.toString() ?? '') ?? 0.0;
      final mortality = int.tryParse(e['mortality']?.toString() ?? '') ?? 0;
      final feedKg = (e['feedTotalKg'] is num)
          ? (e['feedTotalKg'] as num).toDouble()
          : 0.0;
      // 🔧 Usi din ka return feed bhi netted-off — pehle sirf final metric
      // mein return feed subtract hota tha, chart mein nahi; ab dono
      // consistent hain.
      final returnKg = returnFeedByDay[dayNum] ?? 0.0;
      final netFeedKgForDayRaw = feedKg - returnKg;
      final netFeedKgForDay = netFeedKgForDayRaw < 0 ? 0.0 : netFeedKgForDayRaw;

      // 🔧 Expected feed ab is din ke actual live-bird count (mortality/sale
      // adjusted) se calculate hota hai, initialChicks fixed maan kar nahi.
      final liveForDay = liveAtDayStart[dayNum] ?? 0;
      final expectedFeedKg = FeedConsumptionEngine.calculateDayFeedKg(
        config: feedConfig,
        liveChicks: liveForDay,
        dayNumber: dayNum,
        entryDate: d,
      );

      samples.add({
        'batchDay': dayNum, // 🔧 calendar date ki jagah batch-age (day number)
        'actualG': wt > 0 ? wt * 1000 : null,
        'targetG': wt > 0
            ? _standardTargetWeightGrams(dayNum - 1).toDouble()
            : null,
        'mortalityCount': mortality,
        'actualFeedKg': netFeedKgForDay,
        'expectedFeedKg': expectedFeedKg,
      });
    }
    return samples;
  }

  // ── Trend samples ko Daily/Weekly/Monthly bucket mein group karo ──
  // 🔧 Ab calendar date ki jagah batch-age (day number since batch start) se
  // bucket hota hai. Isse alag-alag start-date waale batches ek "calendar
  // week" mein mix nahi hote — sabka Day 1, Day 8... hi ek dusre se compare
  // hota hai, jo company-wide trend ke liye zyada meaningful hai.
  List<Map<String, dynamic>> _bucketTrend(
    List<Map<String, dynamic>> samples,
    String granularity,
  ) {
    if (samples.isEmpty) return [];

    int bucketKey(int batchDay) {
      if (granularity == 'Daily') return batchDay;
      if (granularity == 'Weekly') return ((batchDay - 1) ~/ 7) * 7 + 1;
      return ((batchDay - 1) ~/ 30) * 30 + 1;
    }

    final Map<int, List<double>> actualGList = {};
    final Map<int, List<double>> targetGList = {};
    final Map<int, int> mortalitySum = {};
    final Map<int, double> actualFeedSum = {};
    final Map<int, double> expectedFeedSum = {};

    for (final s in samples) {
      final key = bucketKey(s['batchDay'] as int);
      if (s['actualG'] != null) {
        (actualGList[key] ??= []).add(s['actualG'] as double);
        (targetGList[key] ??= []).add(s['targetG'] as double);
      }
      mortalitySum[key] =
          (mortalitySum[key] ?? 0) + (s['mortalityCount'] as int);
      actualFeedSum[key] =
          (actualFeedSum[key] ?? 0) + (s['actualFeedKg'] as double);
      expectedFeedSum[key] =
          (expectedFeedSum[key] ?? 0) + (s['expectedFeedKg'] as double);
    }

    final keys = {
      ...actualGList.keys,
      ...mortalitySum.keys,
      ...actualFeedSum.keys,
    }.toList()..sort();

    return keys.map((k) {
      final actList = actualGList[k] ?? [];
      final tgtList = targetGList[k] ?? [];
      final avgActual = actList.isNotEmpty
          ? actList.reduce((a, b) => a + b) / actList.length
          : 0.0;
      final avgTarget = tgtList.isNotEmpty
          ? tgtList.reduce((a, b) => a + b) / tgtList.length
          : 0.0;
      final weightGrowthPct = avgTarget > 0
          ? (avgActual / avgTarget) * 100
          : 0.0;
      final actFeed = actualFeedSum[k] ?? 0.0;
      final expFeed = expectedFeedSum[k] ?? 0.0;
      final feedEffPct = actFeed > 0 ? (expFeed / actFeed) * 100 : 0.0;

      return {
        'bucketDay': k,
        'weightGrowthPct': weightGrowthPct,
        'mortalityCount': mortalitySum[k] ?? 0,
        'feedEfficiencyPct': feedEffPct,
        'actualFeedKg': actFeed,
        'expectedFeedKg': expFeed,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _showActive ? _activeBatches : _completedBatches;
    final trendSamples = _showActive
        ? _activeTrendSamples
        : _completedTrendSamples;
    final trendPoints = _bucketTrend(trendSamples, _granularity);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _bpGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: const Text(
          '🐔 Batch Performance',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _bpGreen))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: _bpGreen,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 🔧 Data load karte waqt error aaye to ab chup nahi rehta —
                  // banner + retry button dikhta hai.
                  if (_hasLoadError)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange.shade800,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Kuch data load karte waqt error aayi — report incomplete ho sakti hai.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _loadData,
                            child: const Text(
                              'Retry',
                              style: TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── Active/Completed Toggle ──
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _sectionToggleBtn(
                            '🟢 Active (${_activeBatches.length})',
                            true,
                          ),
                        ),
                        Expanded(
                          child: _sectionToggleBtn(
                            '✅ Completed (${_completedBatches.length})',
                            false,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (list.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(30),
                      alignment: Alignment.center,
                      child: Text(
                        _showActive
                            ? 'Koi active batch nahi hai.'
                            : 'Koi completed batch nahi hai.',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    )
                  else ...[
                    _buildAverages(list),
                    const SizedBox(height: 20),
                    _buildTrendChart(trendPoints),
                    const SizedBox(height: 20),
                    _buildRankingSection(
                      title: '🏆 Top 5 — Best FCR',
                      list: List.of(list)
                        ..removeWhere((m) => !m.isFcrValid)
                        ..sort((a, b) => a.fcr.compareTo(b.fcr)),
                      valueBuilder: (m) => 'FCR ${m.fcr.toStringAsFixed(2)}',
                      color: Colors.green,
                    ),
                    const SizedBox(height: 14),
                    _buildRankingSection(
                      title: '⚠️ Bottom 5 — Worst FCR (Dhyan Do)',
                      list: List.of(list)
                        ..removeWhere((m) => !m.isFcrValid)
                        ..sort((a, b) => b.fcr.compareTo(a.fcr)),
                      valueBuilder: (m) => 'FCR ${m.fcr.toStringAsFixed(2)}',
                      color: Colors.red,
                    ),
                    const SizedBox(height: 14),
                    _buildRankingSection(
                      title: '🏆 Top 5 — Lowest Mortality',
                      list: List.of(list)
                        ..sort(
                          (a, b) => a.mortalityPct.compareTo(b.mortalityPct),
                        ),
                      valueBuilder: (m) =>
                          '${m.mortalityPct.toStringAsFixed(1)}% (${m.totalMortality} pcs)',
                      color: Colors.green,
                    ),
                    const SizedBox(height: 14),
                    _buildRankingSection(
                      title: '⚠️ Bottom 5 — Highest Mortality (Dhyan Do)',
                      list: List.of(list)
                        ..sort(
                          (a, b) => b.mortalityPct.compareTo(a.mortalityPct),
                        ),
                      valueBuilder: (m) =>
                          '${m.mortalityPct.toStringAsFixed(1)}% (${m.totalMortality} pcs)',
                      color: Colors.red,
                    ),
                    const SizedBox(height: 14),
                    _buildRankingSection(
                      title: '🏆 Top 5 — Best Weight Growth',
                      list: List.of(list)
                        ..removeWhere((m) => !m.hasWeightData)
                        ..sort(
                          (a, b) =>
                              b.weightGrowthPct.compareTo(a.weightGrowthPct),
                        ),
                      valueBuilder: (m) =>
                          '${m.weightGrowthPct.toStringAsFixed(1)}% of target',
                      color: Colors.green,
                    ),
                    const SizedBox(height: 14),
                    _buildRankingSection(
                      title: '⚠️ Bottom 5 — Worst Weight Growth (Dhyan Do)',
                      list: List.of(list)
                        ..removeWhere((m) => !m.hasWeightData)
                        ..sort(
                          (a, b) =>
                              a.weightGrowthPct.compareTo(b.weightGrowthPct),
                        ),
                      valueBuilder: (m) =>
                          '${m.weightGrowthPct.toStringAsFixed(1)}% of target',
                      color: Colors.red,
                    ),
                    const SizedBox(height: 14),
                    _buildRankingSection(
                      title: '🏆 Top 5 — Best Feed Efficiency',
                      list: List.of(list)
                        ..removeWhere(
                          (m) =>
                              !m.hasFeedData ||
                              !m.hasWeightData ||
                              m.weightGrowthPct < 85,
                        )
                        ..sort(
                          (a, b) => b.feedEfficiencyPct.compareTo(
                            a.feedEfficiencyPct,
                          ),
                        ),
                      valueBuilder: (m) =>
                          '${m.feedEfficiencyPct.toStringAsFixed(1)}%',
                      color: Colors.green,
                    ),
                    const SizedBox(height: 14),
                    _buildRankingSection(
                      title: '⚠️ Bottom 5 — Worst Feed Efficiency (Dhyan Do)',
                      list: List.of(list)
                        ..removeWhere((m) => !m.hasFeedData)
                        ..sort(
                          (a, b) => a.feedEfficiencyPct.compareTo(
                            b.feedEfficiencyPct,
                          ),
                        ),
                      valueBuilder: (m) =>
                          '${m.feedEfficiencyPct.toStringAsFixed(1)}%',
                      color: Colors.red,
                    ),
                  ],
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _sectionToggleBtn(String label, bool isActiveSection) {
    final bool sel = _showActive == isActiveSection;
    return GestureDetector(
      onTap: () => setState(() => _showActive = isActiveSection),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: sel ? _bpGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: sel ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _buildAverages(List<_BatchMetrics> list) {
    // 🔧 Avg FCR ab "pooled" hai (total feed ÷ total biomass) — chhota
    // 100-chick batch aur bada 50,000-chick batch ab unke size ke hisaab se
    // hi average mein contribute karte hain, barabar nahi. Invalid/missing
    // FCR waale batches average se bahar rakhe gaye hain.
    final fcrEligible = list.where((m) => m.isFcrValid).toList();
    final totalFeedForFcr = fcrEligible.fold(0.0, (s, m) => s + m.totalFeedKg);
    final totalBiomassForFcr = fcrEligible.fold(
      0.0,
      (s, m) => s + m.totalBiomassKg,
    );
    final avgFcr = totalBiomassForFcr > 0
        ? totalFeedForFcr / totalBiomassForFcr
        : 0.0;

    final totalMortality = list.fold(0, (s, m) => s + m.totalMortality);
    final totalInitial = list.fold(0, (s, m) => s + m.initialChicks);
    final avgMortalityPct = totalInitial > 0
        ? (totalMortality / totalInitial) * 100
        : 0.0;

    // 🔧 Weight growth ab chick-count-weighted hai, aur sirf un batches se
    // jinke paas actual weight data hai — missing data ab average ko galat
    // tarike se neeche nahi khinchega.
    final weightEligible = list.where((m) => m.hasWeightData).toList();
    final weightWeightedSum = weightEligible.fold(
      0.0,
      (s, m) => s + (m.weightGrowthPct * m.initialChicks),
    );
    final weightChickSum = weightEligible.fold(
      0,
      (s, m) => s + m.initialChicks,
    );
    final avgWeightGrowth = weightChickSum > 0
        ? weightWeightedSum / weightChickSum
        : 0.0;

    // 🔧 Feed efficiency bhi pooled — total expected ÷ total actual feed.
    final feedEligible = list.where((m) => m.hasFeedData).toList();
    final totalExpectedForEff = feedEligible.fold(
      0.0,
      (s, m) => s + m.totalExpectedFeedKg,
    );
    final totalActualForEff = feedEligible.fold(
      0.0,
      (s, m) => s + m.totalFeedKg,
    );
    final avgFeedEff = totalActualForEff > 0
        ? (totalExpectedForEff / totalActualForEff) * 100
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _showActive
                ? '📊 Active Batches — Averages'
                : '📊 Completed Batches — Averages',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _avgCard(
                  'Avg FCR',
                  avgFcr.toStringAsFixed(2),
                  Colors.indigo,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _avgCard(
                  'Avg Mortality',
                  '${avgMortalityPct.toStringAsFixed(1)}%\n($totalMortality pcs)',
                  Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _avgCard(
                  'Avg Weight Growth',
                  '${avgWeightGrowth.toStringAsFixed(1)}%',
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _avgCard(
                  'Avg Feed Efficiency',
                  '${avgFeedEff.toStringAsFixed(1)}%',
                  Colors.teal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avgCard(String label, String value, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10.5, color: color.shade800)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color.shade900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChart(List<Map<String, dynamic>> points) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '📈 Company Trend — Weight Growth %',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              _granularityToggle(),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Batch ke start-se-din (age) ke hisaab se compare hota hai, calendar date se nahi — taaki alag-alag batches same "stage" par compare hon.',
            style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          points.isEmpty
              ? Container(
                  height: 160,
                  alignment: Alignment.center,
                  child: Text(
                    'Koi trend data nahi mila.',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                )
              : SizedBox(height: 180, child: _weightGrowthLineChart(points)),
          const SizedBox(height: 20),
          const Text(
            '💀 Mortality Count (per period)',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          points.isEmpty
              ? const SizedBox()
              : SizedBox(height: 140, child: _mortalityBarChart(points)),
          const SizedBox(height: 20),
          const Text(
            '🌾 Feed Efficiency % (Expected ÷ Actual × 100)',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          points.isEmpty
              ? const SizedBox()
              : SizedBox(height: 160, child: _feedEfficiencyLineChart(points)),
        ],
      ),
    );
  }

  Widget _granularityToggle() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['Daily', 'Weekly', 'Monthly'].map((g) {
          final bool sel = _granularity == g;
          return GestureDetector(
            onTap: () => setState(() => _granularity = g),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: sel ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                boxShadow: sel
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 4,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                g,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: sel ? _bpGreen : Colors.grey.shade600,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _fmtBucketLabel(int day) {
    if (_granularity == 'Daily') return 'D$day';
    if (_granularity == 'Weekly') return 'Wk ${((day - 1) ~/ 7) + 1}';
    return 'M${((day - 1) ~/ 30) + 1}';
  }

  Widget _weightGrowthLineChart(List<Map<String, dynamic>> points) {
    final spots = <FlSpot>[];
    double maxY = 100;
    for (int i = 0; i < points.length; i++) {
      final v = points[i]['weightGrowthPct'] as double;
      spots.add(FlSpot(i.toDouble(), v));
      if (v > maxY) maxY = v;
    }
    maxY = maxY * 1.2;
    final step = (points.length / 5).ceil().clamp(1, points.length);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: Colors.grey.shade200, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, m) => Text(
                '${v.toInt()}%',
                style: const TextStyle(fontSize: 9, color: Colors.black45),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: step.toDouble(),
              getTitlesWidget: (v, m) {
                final idx = v.toInt();
                if (idx < 0 || idx >= points.length || idx % step != 0)
                  return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _fmtBucketLabel(points[idx]['bucketDay'] as int),
                    style: const TextStyle(fontSize: 9, color: Colors.black45),
                  ),
                );
              },
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: 100,
              color: Colors.grey.shade400,
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ],
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              final idx = s.x.toInt();
              return LineTooltipItem(
                '${s.y.toStringAsFixed(1)}%\n${_fmtBucketLabel(points[idx]['bucketDay'] as int)}',
                const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.blue.shade600,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.blue.withOpacity(0.08),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mortalityBarChart(List<Map<String, dynamic>> points) {
    double maxY = 5;
    for (final p in points) {
      final v = (p['mortalityCount'] as int).toDouble();
      if (v > maxY) maxY = v;
    }
    maxY = maxY * 1.3;
    final step = (points.length / 5).ceil().clamp(1, points.length);

    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: step.toDouble(),
              getTitlesWidget: (v, m) {
                final idx = v.toInt();
                if (idx < 0 || idx >= points.length || idx % step != 0)
                  return const SizedBox.shrink();
                return Text(
                  _fmtBucketLabel(points[idx]['bucketDay'] as int),
                  style: const TextStyle(fontSize: 8.5, color: Colors.black45),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (g, gi, r, ri) {
              final p = points[g.x.toInt()];
              return BarTooltipItem(
                '${p['mortalityCount']} deaths\n${_fmtBucketLabel(p['bucketDay'] as int)}',
                const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
        ),
        barGroups: List.generate(points.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: (points[i]['mortalityCount'] as int).toDouble(),
                color: Colors.red.shade400,
                width: points.length > 25 ? 3 : 8,
                borderRadius: BorderRadius.circular(2),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _feedEfficiencyLineChart(List<Map<String, dynamic>> points) {
    final spots = <FlSpot>[];
    double maxY = 100;
    for (int i = 0; i < points.length; i++) {
      final v = points[i]['feedEfficiencyPct'] as double;
      spots.add(FlSpot(i.toDouble(), v));
      if (v > maxY) maxY = v;
    }
    maxY = maxY * 1.2;
    final step = (points.length / 5).ceil().clamp(1, points.length);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: Colors.grey.shade200, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, m) => Text(
                '${v.toInt()}%',
                style: const TextStyle(fontSize: 9, color: Colors.black45),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: step.toDouble(),
              getTitlesWidget: (v, m) {
                final idx = v.toInt();
                if (idx < 0 || idx >= points.length || idx % step != 0)
                  return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _fmtBucketLabel(points[idx]['bucketDay'] as int),
                    style: const TextStyle(fontSize: 9, color: Colors.black45),
                  ),
                );
              },
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: 100,
              color: Colors.grey.shade400,
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ],
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              final idx = s.x.toInt();
              return LineTooltipItem(
                '${s.y.toStringAsFixed(1)}%\n${_fmtBucketLabel(points[idx]['bucketDay'] as int)}',
                const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.teal.shade600,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.teal.withOpacity(0.08),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankingSection({
    required String title,
    required List<_BatchMetrics> list,
    required String Function(_BatchMetrics) valueBuilder,
    required MaterialColor color,
  }) {
    final top5 = list.take(5).toList();
    return Container(
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: color.shade900,
              ),
            ),
          ),
          ...top5.asMap().entries.map((entry) {
            final i = entry.key;
            final m = entry.value;
            return Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color.shade900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.farmerName,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Batch: ${m.batchId} • ${m.daysOld} din',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    valueBuilder(m),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: color.shade800,
                    ),
                  ),
                ],
              ),
            );
          }),
          if (top5.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                'Data nahi hai.',
                style: TextStyle(fontSize: 11, color: color.shade700),
              ),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
