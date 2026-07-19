import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:get/get.dart';
import 'dart:convert';
import '../../services/company_store.dart';
import 'batch_performance_screen.dart';
import 'farmer_profit_loss_screen.dart';
import 'accounts_screen.dart' show AppDateFilter, isDateInFilter;

// ═══════════════════════════════════════════════════════════════════════════
// 📊 REPORTS SCREEN — Main hub
// ═══════════════════════════════════════════════════════════════════════════
const Color _repGreen = Color(0xFF1B5E20);

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _repGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: const Row(
          children: [
            Text('📊', style: TextStyle(fontSize: 20)),
            SizedBox(width: 8),
            Text(
              'Reports',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              decoration: const BoxDecoration(
                color: _repGreen,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Business Insights',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Report Select Karein',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Available Reports',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ReportCard(
                    emoji: '🧮',
                    title: 'Operational Expense Recovery',
                    subtitle:
                        'Admin charges collected vs company ka operational kharcha — per KG basis',
                    color: Colors.indigo,
                    onTap: () =>
                        Get.to(() => const OperationalExpenseReportScreen()),
                  ),
                  const SizedBox(height: 12),
                  _ReportCard(
                    emoji: '🐔',
                    title: 'Batch Performance',
                    subtitle:
                        'FCR, Mortality, Weight Growth aur Feed Efficiency — Top/Bottom 5 ke saath',
                    color: Colors.indigo,
                    onTap: () => Get.to(() => const BatchPerformanceScreen()),
                  ),
                  const SizedBox(height: 12),
                  _ReportCard(
                    emoji: '🧑‍🌾',
                    title: 'Farmer Profit / Loss',
                    subtitle:
                        'Har farmer ka Chicks+Feed+Medicine+Admin margin minus Operational Expense',
                    color: Colors.indigo,
                    onTap: () => Get.to(() => const FarmerProfitLossScreen()),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final MaterialColor color;
  final VoidCallback onTap;
  final bool comingSoon;

  const _ReportCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: comingSoon ? null : onTap,
      child: Opacity(
        opacity: comingSoon ? 0.55 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.shade50,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 26)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        if (comingSoon) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Jald',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              if (!comingSoon)
                Icon(Icons.chevron_right_rounded, color: color.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🧮 OPERATIONAL EXPENSE RECOVERY REPORT (FIXED)
// ═══════════════════════════════════════════════════════════════════════════

class _DailyPoint {
  final DateTime date;
  final double kgSold;
  final double adminCollected;
  final double opExpense;
  final int missingWeightCount; // ✅ NEW: data-quality flag
  final int approxRateCount; // ✅ NEW: old sales without snapshot

  _DailyPoint({
    required this.date,
    required this.kgSold,
    required this.adminCollected,
    required this.opExpense,
    this.missingWeightCount = 0,
    this.approxRateCount = 0,
  });

  double get net => adminCollected - opExpense;
}

class OperationalExpenseReportScreen extends StatefulWidget {
  const OperationalExpenseReportScreen({super.key});

  @override
  State<OperationalExpenseReportScreen> createState() =>
      _OperationalExpenseReportScreenState();
}

class _OperationalExpenseReportScreenState
    extends State<OperationalExpenseReportScreen> {
  bool _isLoading = true;

  int? _appliedRuleId;
  double _bigAdminCost = 0.0;
  double _smAdminCost = 0.0;

  // {date, kg, avgWt, ruleIdAtSale, sizeCategoryAtSale, adminRateAtSale (null=no snapshot/old data)}
  List<Map<String, dynamic>> _saleEvents = [];
  List<Map<String, dynamic>> _otherExpenses = [];
  List<Map<String, dynamic>> _labourExpenses = [];

  late AppDateFilter _selectedFilter;
  String _granularity = 'Daily';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedFilter = AppDateFilter(
      label: 'This Month',
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
    );
    _loadData();
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

  DateTime? _parseIso(dynamic s) {
    if (s == null) return null;
    try {
      return DateTime.parse(s.toString());
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final ruleId = await CompanyStore.instance.getInt('appliedCompanyRuleId');
    double bigAdminCost = 0.0;
    double smAdminCost = 0.0;
    if (ruleId == 1) {
      final r1Json = await CompanyStore.instance.getString(
        'rule1SettlementConfig',
      );
      if (r1Json != null) {
        try {
          final r1 = Map<String, dynamic>.from(json.decode(r1Json));
          bigAdminCost = (r1['bigAdminCost'] ?? 0.0).toDouble();
          smAdminCost = (r1['smAdminCost'] ?? 0.0).toDouble();
        } catch (_) {}
      }
    }

    final List<Map<String, dynamic>> saleEvents = [];
    try {
      final farmers = await CompanyStore.instance.getJsonList('companyFarmers');
      for (final farmer in farmers) {
        final batches = (farmer['batches'] as List?) ?? [];
        for (final batch in batches) {
          final entries = (batch['dailyEntries'] as List?) ?? [];
          for (final rawE in entries) {
            final e = Map<String, dynamic>.from(rawE as Map);
            if ((e['type'] ?? '').toString().toLowerCase() != 'sale') continue;
            final d = _parseDdMmYyyy(e['date']?.toString());
            if (d == null) continue;
            final kg =
                double.tryParse(e['totalWeightSold']?.toString() ?? '') ?? 0.0;
            if (kg <= 0) continue;
            final avgWt =
                double.tryParse(e['avgWeightSold']?.toString() ?? '') ?? 0.0;

            // ✅ FIX #1: snapshot fields agar sale ke time save hue the
            final int? ruleIdAtSale = e['appliedRuleIdAtSale'] is int
                ? e['appliedRuleIdAtSale']
                : int.tryParse(e['appliedRuleIdAtSale']?.toString() ?? '');
            final String sizeCategoryAtSale = (e['sizeCategoryAtSale'] ?? '')
                .toString();
            final double? adminRateAtSale = e['adminRateAtSale'] != null
                ? double.tryParse(e['adminRateAtSale'].toString())
                : null;
            final bool hasSnapshot = e.containsKey('appliedRuleIdAtSale');

            saleEvents.add({
              'date': d,
              'kg': kg,
              'avgWt': avgWt,
              'ruleIdAtSale': ruleIdAtSale,
              'sizeCategoryAtSale': sizeCategoryAtSale,
              'adminRateAtSale': adminRateAtSale,
              'hasSnapshot': hasSnapshot,
            });
          }
        }
      }
    } catch (_) {}

    List<Map<String, dynamic>> otherExp = [];
    final otherJson = await CompanyStore.instance.getString(
      'otherExpenseHistory',
    );
    if (otherJson != null) {
      try {
        otherExp = (json.decode(otherJson) as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (_) {}
    }

    List<Map<String, dynamic>> labourExp = [];
    final labourJson = await CompanyStore.instance.getString(
      'labourExpenseHistory',
    );
    if (labourJson != null) {
      try {
        labourExp = (json.decode(labourJson) as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _appliedRuleId = ruleId;
      _bigAdminCost = bigAdminCost;
      _smAdminCost = smAdminCost;
      _saleEvents = saleEvents;
      _otherExpenses = otherExp;
      _labourExpenses = labourExp;
      _isLoading = false;
    });
  }

  List<_DailyPoint> _computeDailyPoints() {
    DateTime start;
    DateTime end;

    if (_selectedFilter.isAllTime) {
      DateTime? minD;
      for (final s in _saleEvents) {
        final d = s['date'] as DateTime;
        if (minD == null || d.isBefore(minD)) minD = d;
      }
      for (final e in _otherExpenses) {
        final d = _parseIso(e['date']);
        if (d != null && (minD == null || d.isBefore(minD))) minD = d;
      }
      for (final e in _labourExpenses) {
        final d = _parseIso(e['date']);
        if (d != null && (minD == null || d.isBefore(minD))) minD = d;
      }
      start = minD ?? DateTime.now();
      end = DateTime.now();
    } else {
      start = _selectedFilter.start ?? DateTime.now();
      end = _selectedFilter.end ?? DateTime.now();
    }

    start = DateTime(start.year, start.month, start.day);
    final today = DateTime.now();
    DateTime effectiveEnd = DateTime(end.year, end.month, end.day);
    final todayOnly = DateTime(today.year, today.month, today.day);
    if (effectiveEnd.isAfter(todayOnly)) effectiveEnd = todayOnly;
    if (effectiveEnd.isBefore(start)) return [];

    final Map<DateTime, double> kgByDay = {};
    final Map<DateTime, double> adminByDay = {};
    final Map<DateTime, double> opExpByDay = {};
    final Map<DateTime, int> missingWtByDay = {};
    final Map<DateTime, int> approxByDay = {};

    for (final s in _saleEvents) {
      final d = s['date'] as DateTime;
      if (d.isBefore(start) || d.isAfter(effectiveEnd)) continue;
      final kg = s['kg'] as double;
      kgByDay[d] = (kgByDay[d] ?? 0) + kg;

      final avgWt = s['avgWt'] as double;
      final bool hasSnapshot = s['hasSnapshot'] as bool;

      // ✅ FIX #3: weight missing hone par silently "small" mat maano —
      // data-quality issue ke roop mein flag karo, calculation se exclude karo
      if (avgWt <= 0) {
        missingWtByDay[d] = (missingWtByDay[d] ?? 0) + 1;
        continue;
      }

      double? adminAmount;
      if (hasSnapshot) {
        // ✅ FIX #1: naye sale ka apna snapshot rate use karo — current
        // rule/rate se koi lena dena nahi, chahe wo kuch bhi ho jaye
        final ruleIdAtSale = s['ruleIdAtSale'] as int?;
        final rateAtSale = s['adminRateAtSale'] as double?;
        if (ruleIdAtSale == 1 && rateAtSale != null) {
          adminAmount = kg * rateAtSale;
        }
        // Rule 2/no-rule tha sale ke time → admin charge concept applicable nahi, 0 rahega
      } else {
        // Purana data (fix se pehle ka) — snapshot nahi hai, isliye current
        // rate se sirf APPROXIMATE calculate karo aur count mark karo taaki
        // UI warning de sake ki ye number exact nahi hai
        if (_appliedRuleId == 1) {
          final isBig = avgWt > 1.2;
          final rate = isBig ? _bigAdminCost : _smAdminCost;
          adminAmount = kg * rate;
          approxByDay[d] = (approxByDay[d] ?? 0) + 1;
        }
      }

      if (adminAmount != null) {
        adminByDay[d] = (adminByDay[d] ?? 0) + adminAmount;
      }
    }

    for (final e in _otherExpenses) {
      final d = _parseIso(e['date']);
      if (d == null) continue;
      final dd = DateTime(d.year, d.month, d.day);
      if (dd.isBefore(start) || dd.isAfter(effectiveEnd)) continue;
      final amt = (e['amount'] as num?)?.toDouble() ?? 0.0;
      opExpByDay[dd] = (opExpByDay[dd] ?? 0) + amt;
    }

    for (final e in _labourExpenses) {
      final d = _parseIso(e['date']);
      if (d == null) continue;
      final mode = (e['unitMode'] ?? '').toString();
      final amt = (e['totalAmount'] as num?)?.toDouble() ?? 0.0;

      if (mode != 'Monthly') {
        final dd = DateTime(d.year, d.month, d.day);
        if (dd.isBefore(start) || dd.isAfter(effectiveEnd)) continue;
        opExpByDay[dd] = (opExpByDay[dd] ?? 0) + amt;
      } else {
        final daysInMonth = DateTime(d.year, d.month + 1, 0).day;
        final dailyPortion = daysInMonth > 0 ? amt / daysInMonth : 0.0;
        final monthStart = DateTime(d.year, d.month, 1);
        final monthEnd = DateTime(d.year, d.month, daysInMonth);
        final overlapStart = monthStart.isAfter(start) ? monthStart : start;
        final overlapEnd = monthEnd.isBefore(effectiveEnd)
            ? monthEnd
            : effectiveEnd;
        if (overlapStart.isAfter(overlapEnd)) continue;
        for (
          var day = overlapStart;
          !day.isAfter(overlapEnd);
          day = day.add(const Duration(days: 1))
        ) {
          opExpByDay[day] = (opExpByDay[day] ?? 0) + dailyPortion;
        }
      }
    }

    final List<_DailyPoint> points = [];
    for (
      var day = start;
      !day.isAfter(effectiveEnd);
      day = day.add(const Duration(days: 1))
    ) {
      points.add(
        _DailyPoint(
          date: day,
          kgSold: kgByDay[day] ?? 0.0,
          adminCollected: adminByDay[day] ?? 0.0,
          opExpense: opExpByDay[day] ?? 0.0,
          missingWeightCount: missingWtByDay[day] ?? 0,
          approxRateCount: approxByDay[day] ?? 0,
        ),
      );
    }
    return points;
  }

  List<_DailyPoint> _groupPoints(List<_DailyPoint> daily, String granularity) {
    if (granularity == 'Daily' || daily.isEmpty) return daily;

    final Map<DateTime, _DailyPoint> buckets = {};
    for (final p in daily) {
      DateTime key;
      if (granularity == 'Weekly') {
        key = p.date.subtract(Duration(days: p.date.weekday - 1));
      } else {
        key = DateTime(p.date.year, p.date.month, 1);
      }
      final existing = buckets[key];
      if (existing == null) {
        buckets[key] = _DailyPoint(
          date: key,
          kgSold: p.kgSold,
          adminCollected: p.adminCollected,
          opExpense: p.opExpense,
          missingWeightCount: p.missingWeightCount,
          approxRateCount: p.approxRateCount,
        );
      } else {
        buckets[key] = _DailyPoint(
          date: key,
          kgSold: existing.kgSold + p.kgSold,
          adminCollected: existing.adminCollected + p.adminCollected,
          opExpense: existing.opExpense + p.opExpense,
          missingWeightCount:
              existing.missingWeightCount + p.missingWeightCount,
          approxRateCount: existing.approxRateCount + p.approxRateCount,
        );
      }
    }
    final keys = buckets.keys.toList()..sort();
    return keys.map((k) => buckets[k]!).toList();
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Period Chuniye',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(
                  Icons.calendar_today_rounded,
                  color: _repGreen,
                ),
                title: const Text(
                  'This Month',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  final now = DateTime.now();
                  setState(() {
                    _selectedFilter = AppDateFilter(
                      label: 'This Month',
                      start: DateTime(now.year, now.month, 1),
                      end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
                    );
                  });
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.calendar_month_rounded,
                  color: _repGreen,
                ),
                title: const Text(
                  'Pichla Mahina',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  final now = DateTime.now();
                  final lastMonth = DateTime(now.year, now.month - 1, 1);
                  setState(() {
                    _selectedFilter = AppDateFilter(
                      label: 'Pichla Mahina',
                      start: lastMonth,
                      end: DateTime(
                        lastMonth.year,
                        lastMonth.month + 1,
                        0,
                        23,
                        59,
                        59,
                      ),
                    );
                  });
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.all_inclusive_rounded,
                  color: _repGreen,
                ),
                title: const Text(
                  'Pura Data (All Time)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  setState(() {
                    _selectedFilter = AppDateFilter(
                      label: 'All Time',
                      isAllTime: true,
                    );
                    _granularity = 'Monthly';
                  });
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.date_range_rounded, color: _repGreen),
                title: const Text(
                  'Custom Range',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2023),
                    lastDate: DateTime.now(),
                    builder: (context, child) => Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: _repGreen,
                          onPrimary: Colors.white,
                          onSurface: Colors.black,
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    final s = picked.start;
                    final e = picked.end;
                    setState(() {
                      _selectedFilter = AppDateFilter(
                        label:
                            '${s.day}/${s.month}/${s.year} - ${e.day}/${e.month}/${e.year}',
                        start: s,
                        end: DateTime(e.year, e.month, e.day, 23, 59, 59),
                      );
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daily = _computeDailyPoints();
    final points = _groupPoints(daily, _granularity);

    double totalOpExpense = 0.0;
    double totalAdminCollected = 0.0;
    double totalKgSold = 0.0;
    int totalMissingWt = 0;
    int totalApprox = 0;
    for (final p in daily) {
      totalOpExpense += p.opExpense;
      totalAdminCollected += p.adminCollected;
      totalKgSold += p.kgSold;
      totalMissingWt += p.missingWeightCount;
      totalApprox += p.approxRateCount;
    }

    final double? perKgOpExpense = totalKgSold > 0
        ? totalOpExpense / totalKgSold
        : null;
    final bool ruleTracksAdmin = _appliedRuleId == 1;
    final double? recoveryPct = (totalOpExpense > 0 && totalAdminCollected > 0)
        ? (totalAdminCollected / totalOpExpense) * 100
        : null;

    _DailyPoint? bestDay;
    _DailyPoint? worstDay;
    for (final p in daily) {
      if (p.opExpense <= 0 && p.adminCollected <= 0) continue;
      if (bestDay == null || p.net > bestDay.net) bestDay = p;
      if (worstDay == null || p.net < worstDay.net) worstDay = p;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _repGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: const Text(
          '🧮 Operational Expense Recovery',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        actions: [
          InkWell(
            onTap: _showFilterSheet,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.filter_alt_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 90),
                    child: Text(
                      _selectedFilter.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _repGreen))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: _repGreen,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_appliedRuleId == null)
                    _warningBanner(
                      '⚠️ Koi Settlement Rule Apply Nahi Hua',
                      'Home → Batch Settlement mein jaake Rule 1 apply karein, tabhi Admin Charges (Accrued) track hoga.',
                    ),
                  if (_appliedRuleId == 2)
                    _warningBanner(
                      '⚠️ Rule 2 (FCR Matrix) Active Hai',
                      'Rule 2 mein "Admin Cost ₹/KG" field abhi track nahi hoti. Isliye us period ki Admin Charges calculate nahi hongi (jab Rule 2 active tha). Sirf Operational Expense dikhaya ja raha hai.',
                    ),
                  if (totalApprox > 0)
                    _warningBanner(
                      '⚠️ Kuch Purani Sales Approximate Hain',
                      '$totalApprox purani sale entries mein rate snapshot nahi tha (is fix se pehle ki hain), unke liye CURRENT rate se approximate calculate kiya gaya hai — exact nahi ho sakta.',
                    ),
                  if (totalMissingWt > 0)
                    _warningBanner(
                      '⚠️ Data Quality Issue',
                      '$totalMissingWt sale entries mein Avg Weight missing/invalid thi — unhe calculation se EXCLUDE kar diya gaya hai (Big/Small assume nahi kiya).',
                    ),
                  if (_appliedRuleId == null ||
                      _appliedRuleId == 2 ||
                      totalApprox > 0 ||
                      totalMissingWt > 0)
                    const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          '💸',
                          'Total Operational Expense',
                          '₹${totalOpExpense.toStringAsFixed(0)}',
                          Colors.red.shade700,
                          Colors.red.shade50,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statCard(
                          '🏢',
                          'Admin Charges Accrued',
                          ruleTracksAdmin || totalApprox > 0
                              ? '₹${totalAdminCollected.toStringAsFixed(0)}'
                              : 'N/A',
                          Colors.green.shade700,
                          Colors.green.shade50,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          '⚖️',
                          'Per KG Operational Cost',
                          perKgOpExpense != null
                              ? '₹${perKgOpExpense.toStringAsFixed(2)}'
                              : 'N/A',
                          Colors.blue.shade700,
                          Colors.blue.shade50,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statCard(
                          recoveryPct == null
                              ? '❓'
                              : (recoveryPct >= 100 ? '✅' : '🔴'),
                          'Overall Recovery %',
                          recoveryPct != null
                              ? '${recoveryPct.toStringAsFixed(1)}%'
                              : 'N/A',
                          recoveryPct == null
                              ? Colors.grey.shade700
                              : (recoveryPct >= 100
                                    ? Colors.green.shade700
                                    : Colors.red.shade700),
                          recoveryPct == null
                              ? Colors.grey.shade100
                              : (recoveryPct >= 100
                                    ? Colors.green.shade50
                                    : Colors.red.shade50),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Container(
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
                            const Expanded(
                              child: Wrap(
                                spacing: 14,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _LegendDot(
                                    color: Colors.red,
                                    label: 'Op. Expense',
                                  ),
                                  _LegendDot(
                                    color: Colors.green,
                                    label: 'Admin Accrued',
                                  ),
                                ],
                              ),
                            ),
                            _granularityToggle(),
                          ],
                        ),
                        const SizedBox(height: 16),
                        points.isEmpty
                            ? Container(
                                height: 200,
                                alignment: Alignment.center,
                                child: Text(
                                  'Is period ke liye koi data nahi mila.',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                  ),
                                ),
                              )
                            : SizedBox(
                                height: 220,
                                child: _buildLineChart(points),
                              ),
                        if (points.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const Text(
                            'Daily Net Surplus (Admin − Expense)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(height: 140, child: _buildBarChart(points)),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _bottomStat(
                            '📈',
                            'Best Net Surplus Day',
                            bestDay != null
                                ? '₹${bestDay.net.toStringAsFixed(0)}'
                                : '-',
                            bestDay != null ? _fmtDate(bestDay.date) : '',
                            Colors.green.shade700,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey.shade200,
                        ),
                        Expanded(
                          child: _bottomStat(
                            '📉',
                            'Worst Net Surplus Day',
                            worstDay != null
                                ? '₹${worstDay.net.toStringAsFixed(0)}'
                                : '-',
                            worstDay != null ? _fmtDate(worstDay.date) : '',
                            Colors.red.shade700,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey.shade200,
                        ),
                        Expanded(
                          child: _bottomStat(
                            '📊',
                            'Overall Recovery',
                            recoveryPct != null
                                ? '${recoveryPct.toStringAsFixed(1)}%'
                                : 'N/A',
                            'Total ÷ Total',
                            Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  Text(
                    'ℹ️ Total KG Chicken Sold (period mein): ${totalKgSold.toStringAsFixed(1)} KG',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  Widget _warningBanner(String title, String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.orange.shade900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.orange.shade800,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(
    String emoji,
    String label,
    String value,
    Color valueColor,
    Color bgColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: Colors.black54),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomStat(
    String emoji,
    String label,
    String value,
    String sub,
    Color color,
  ) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 9.5, color: Colors.black54),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        if (sub.isNotEmpty)
          Text(sub, style: const TextStyle(fontSize: 9, color: Colors.black45)),
      ],
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: sel ? _repGreen : Colors.grey.shade600,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLineChart(List<_DailyPoint> points) {
    final List<FlSpot> expenseSpots = [];
    final List<FlSpot> adminSpots = [];
    double maxY = 0;

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      expenseSpots.add(FlSpot(i.toDouble(), p.opExpense));
      adminSpots.add(FlSpot(i.toDouble(), p.adminCollected));
      if (p.opExpense > maxY) maxY = p.opExpense;
      if (p.adminCollected > maxY) maxY = p.adminCollected;
    }
    if (maxY <= 0) maxY = 100;
    maxY = maxY * 1.2;

    final int labelStep = (points.length / 5).ceil().clamp(1, points.length);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: Colors.grey.shade200, strokeWidth: 1),
        ),
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
              reservedSize: 44,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) => Text(
                '₹${(value / 1000).toStringAsFixed(0)}K',
                style: const TextStyle(fontSize: 9, color: Colors.black45),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: labelStep.toDouble(),
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= points.length)
                  return const SizedBox.shrink();
                if (idx % labelStep != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _fmtDate(points[idx].date),
                    style: const TextStyle(fontSize: 9, color: Colors.black45),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              final idx = s.x.toInt();
              if (idx < 0 || idx >= points.length) return null;
              final p = points[idx];
              final isExpense = s.barIndex == 0;
              return LineTooltipItem(
                '${isExpense ? "Expense" : "Admin"}: ₹${(isExpense ? p.opExpense : p.adminCollected).toStringAsFixed(0)}\n${_fmtDate(p.date)}',
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
            spots: expenseSpots,
            isCurved: true,
            color: Colors.red.shade400,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.red.withOpacity(0.08),
            ),
          ),
          LineChartBarData(
            spots: adminSpots,
            isCurved: true,
            color: Colors.green.shade600,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.green.withOpacity(0.10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(List<_DailyPoint> points) {
    double maxAbs = 0;
    for (final p in points) {
      final v = p.net.abs();
      if (v > maxAbs) maxAbs = v;
    }
    if (maxAbs <= 0) maxAbs = 100;
    final int labelStep = (points.length / 5).ceil().clamp(1, points.length);

    return BarChart(
      BarChartData(
        minY: -maxAbs * 1.15,
        maxY: maxAbs * 1.15,
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
              reservedSize: 22,
              interval: labelStep.toDouble(),
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= points.length)
                  return const SizedBox.shrink();
                if (idx % labelStep != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _fmtDate(points[idx].date),
                    style: const TextStyle(
                      fontSize: 8.5,
                      color: Colors.black45,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIdx, rod, rodIdx) {
              final p = points[group.x.toInt()];
              return BarTooltipItem(
                '${p.net >= 0 ? "+" : ""}₹${p.net.toStringAsFixed(0)}\n${_fmtDate(p.date)}',
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
          final net = points[i].net;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: net,
                color: net >= 0 ? Colors.green.shade500 : Colors.red.shade400,
                width: (points.length > 25) ? 3 : 8,
                borderRadius: BorderRadius.circular(2),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: Colors.black54),
        ),
      ],
    );
  }
}
