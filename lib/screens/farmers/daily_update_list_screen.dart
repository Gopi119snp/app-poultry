import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../services/company_store.dart';
import '../../../utils/feed_consumption_rule_engine.dart';
import '../../../utils/weight_growth_rule_engine.dart';

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
// =============================================================================
class DailyUpdateListScreen extends StatefulWidget {
  final Map<String, dynamic> batchData;
  final List<dynamic> dailyEntries;
  final FeedConsumptionRuleConfig feedRuleConfig;

  const DailyUpdateListScreen({
    super.key,
    required this.batchData,
    required this.dailyEntries,
    required this.feedRuleConfig,
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
  });
}

class _DailyUpdateListScreenState extends State<DailyUpdateListScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);

  bool _loading = true;
  FeedConsumptionRuleConfig get _feedConfig => widget.feedRuleConfig;
  WeightGrowthRuleConfig _weightConfig = WeightGrowthRuleConfig();

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

  @override
  void initState() {
    super.initState();
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
    for (final e in widget.dailyEntries) {
      if (e['type'].toString().toLowerCase() != 'cost') continue;
      final d = _parseDdMmYyyy(e['date']);
      if (d == null) continue;
      costEntries.add({
        'date': d,
        'mortality': int.tryParse(e['mortality'].toString()) ?? 0,
        'feedBags': int.tryParse(e['feed'].toString()) ?? 0,
        'weightKg': double.tryParse(e['weight'].toString()) ?? 0.0,
      });
    }

    int cumulativeMortality = 0;
    double cumulativeFeedConsumedKg = 0.0;
    double cumulativeFeedDeliveredKg = 0.0;
    double? lastManualWeightKg;
    final List<_DayRow> rows = [];

    for (int day = 1; day <= chicksAgeDays; day++) {
      final DateTime date = startDate.add(Duration(days: day - 1));

      int mortalityToday = 0;
      int feedBagsDeliveredToday = 0;
      double? weightEnteredToday;

      for (final entry in costEntries) {
        if (_sameDay(entry['date'] as DateTime, date)) {
          mortalityToday += entry['mortality'] as int;
          feedBagsDeliveredToday += entry['feedBags'] as int;
          final w = entry['weightKg'] as double;
          if (w > 0) weightEnteredToday = w;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Daily Update List',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: Colors.white),
            tooltip: 'Cost Settings',
            onPressed: _showCostConfigSheet,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: primaryGreen))
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.blue.shade50,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Text(
                    _appliedRuleId == 1
                        ? '💰 Cost/Kg abhi "Rule 1 (Big/Small Auto Size)" ke saved rates se aa raha hai (weight ke hisaab se auto).'
                        : '💰 Cost/Kg abhi ⚙️ Fallback Settings se aa raha hai (Rule 2 mein cost fields nahi hain abhi).',
                    style: const TextStyle(fontSize: 11.5, color: Colors.black87),
                  ),
                ),
                Container(
                  width: double.infinity,
                  color: Colors.grey.shade100,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: const Text(
                    '👉 Table ko side mein scroll karke saare columns dekhein. '
                    'FCR/Weight dono Automatic (rule-based) aur Manual (entered) hain.',
                    style: TextStyle(fontSize: 11.5, color: Colors.black87),
                  ),
                ),
                Expanded(
                  child: _rows.isEmpty
                      ? const Center(child: Text('Koi din data nahi hai'))
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(
                                primaryGreen,
                              ),
                              headingTextStyle: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11.5,
                              ),
                              dataTextStyle: const TextStyle(fontSize: 11.5),
                              columnSpacing: 18,
                              columns: const [
                                DataColumn(label: Text('Date')),
                                DataColumn(label: Text('Din')),
                                DataColumn(label: Text('Live Chicks')),
                                DataColumn(label: Text('Mortality')),
                                DataColumn(label: Text('Total Mort.')),
                                DataColumn(label: Text('Mort. %')),
                                DataColumn(label: Text('Daily Feed (kg)')),
                                DataColumn(label: Text('Total Feed (kg)')),
                                DataColumn(label: Text('Feed Stock (kg)')),
                                DataColumn(label: Text('Wt Auto (kg)')),
                                DataColumn(label: Text('Wt Manual (kg)')),
                                DataColumn(label: Text('FCR Auto')),
                                DataColumn(label: Text('FCR Manual')),
                                DataColumn(label: Text('Cost/Kg (₹)')),
                              ],
                              rows: _rows
                                  .map(
                                    (r) => DataRow(
                                      cells: [
                                        DataCell(Text(_fmtDate(r.date))),
                                        DataCell(Text('${r.day}')),
                                        DataCell(Text('${r.liveChicks}')),
                                        DataCell(
                                          Text(
                                            '${r.mortalityToday}',
                                            style: TextStyle(
                                              color: r.mortalityToday > 0
                                                  ? Colors.red
                                                  : Colors.black87,
                                              fontWeight: r.mortalityToday > 0
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                        DataCell(Text('${r.totalMortality}')),
                                        DataCell(
                                          Text(
                                            '${r.mortalityPercent.toStringAsFixed(2)}%',
                                          ),
                                        ),
                                        DataCell(
                                          Text(r.dailyFeedKg.toStringAsFixed(2)),
                                        ),
                                        DataCell(
                                          Text(r.totalFeedKg.toStringAsFixed(2)),
                                        ),
                                        DataCell(
                                          Text(r.feedStockKg.toStringAsFixed(2)),
                                        ),
                                        DataCell(
                                          Text(r.autoWeightKg.toStringAsFixed(3)),
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
                                          Text(r.autoFcr.toStringAsFixed(3)),
                                        ),
                                        DataCell(
                                          Text(
                                            r.manualFcr != null
                                                ? r.manualFcr!.toStringAsFixed(3)
                                                : '—',
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            '₹${r.costPerKg.toStringAsFixed(2)}',
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
