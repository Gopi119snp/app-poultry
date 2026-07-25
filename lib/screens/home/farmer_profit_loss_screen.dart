import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:get/get.dart';
import 'dart:convert';
import '../../services/company_store.dart';
import 'purchase_expense_screen.dart' show ensureFeedStockMigrated;

const Color _fplGreen = Color(0xFF1B5E20);

// ═══════════════════════════════════════════════════════════════════════════
// 🔧 SHARED HELPERS (farmer_report_screen.dart jaisa hi)
// ═══════════════════════════════════════════════════════════════════════════

DateTime? _parseDdMmYyyy(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final parts = s.trim().split('/');
  if (parts.length != 3) return null;
  try {
    final int day = int.parse(parts[0]);
    final int month = int.parse(parts[1]);
    final int year = int.parse(parts[2]);
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    final dt = DateTime(year, month, day);
    if (dt.year != year || dt.month != month || dt.day != day) return null;
    return dt;
  } catch (_) {
    return null;
  }
}

DateTime? _parseAnyDate(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  if (s.contains('/')) return _parseDdMmYyyy(s);
  try {
    return DateTime.parse(s);
  } catch (_) {
    return null;
  }
}

String _monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';
String _prevMonthKey(DateTime d) => _monthKey(DateTime(d.year, d.month - 1, 1));

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

class _CatAmount {
  final double billed;
  final double cost;
  const _CatAmount(this.billed, this.cost);
  double get income => billed - cost;
}

// ═══════════════════════════════════════════════════════════════════════════
// 📦 PER-BATCH RECORD — ab har batch ka apna record store hota hai (status
// ke saath), taaki totals ko "include active?" toggle ke hisaab se
// dynamically recompute kiya ja sake, bina wapas se load kiye.
// ═══════════════════════════════════════════════════════════════════════════
class _BatchProfitRecord {
  final String farmerId;
  final String farmerName;
  final String batchId;
  final bool isCompleted; // COMPLETED/CLOSED = true, warna active/other
  final double trueTotalProfit;
  final double silentIncome;
  final bool opExpenseDataMissing;
  final bool allocationDataMissing; // ✅ FIX #9 — naya
  final DateTime
  trendDate; // last sale date, ya batch start date agar sale hi nahi hui

  const _BatchProfitRecord({
    required this.farmerId,
    required this.farmerName,
    required this.batchId,
    required this.isCompleted,
    required this.trueTotalProfit,
    required this.silentIncome,
    required this.opExpenseDataMissing,
    required this.allocationDataMissing, // ✅ FIX #9 — naya
    required this.trendDate,
  });
}

class _FarmerAgg {
  final String farmerId;
  final String farmerName;
  double trueTotalProfit = 0.0;
  int batchCount = 0;
  bool opExpenseDataMissing = false;
  bool allocationDataMissing = false; // ✅ FIX #9 — naya

  _FarmerAgg({required this.farmerId, required this.farmerName});
}

// ═══════════════════════════════════════════════════════════════════════════
// 📊 FARMER PROFIT / LOSS SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class FarmerProfitLossScreen extends StatefulWidget {
  const FarmerProfitLossScreen({super.key});

  @override
  State<FarmerProfitLossScreen> createState() => _FarmerProfitLossScreenState();
}

class _FarmerProfitLossScreenState extends State<FarmerProfitLossScreen> {
  bool _isLoading = true;
  String _granularity = 'Weekly';

  // ✅ NEW: true = Active (abhi sale na hui) batches ka invest bhi minus
  // karke total profit dikhega. false = sirf COMPLETED batches ka clean
  // profit dikhega.
  bool _includeActiveBatches = true;

  // ✅ NEW: raw per-batch records — toggle change hone par yahi se
  // dynamically re-aggregate hota hai, wapas load nahi karna padta.
  List<_BatchProfitRecord> _allRecords = [];

  // Rule 1 config
  double _r1BigFeedRate = 42.0, _r1BigChicksRate = 40.0, _r1BigAdminCost = 1.50;
  double _r1BigKgPerBag = 50.0, _r1BigTargetCost = 85.0, _r1BigBaseComm = 8.0;
  double _r1BigSavingsShare = 50.0, _r1BigExceededShare = 50.0;
  double _r1BigRateBonusThresh = 110.0, _r1BigRateBonusShare = 10.0;
  bool _r1BigMedicineInProd = true;

  double _r1SmFeedRate = 42.0, _r1SmChicksRate = 40.0, _r1SmAdminCost = 1.50;
  double _r1SmKgPerBag = 50.0, _r1SmTargetCost = 90.0, _r1SmBaseComm = 10.0;
  double _r1SmSavingsShare = 50.0, _r1SmExceededShare = 50.0;
  double _r1SmRateBonusThresh = 120.0, _r1SmRateBonusShare = 10.0;
  bool _r1SmMedicineInProd = true;

  Map<String, double> _monthlyOpExpense = {};
  Map<String, double> _monthlyKgSold = {};

  List<Map<String, dynamic>> _feedStock = [];
  List<Map<String, dynamic>> _medicineStock = [];
  List<Map<String, dynamic>> _chicksPurchaseHistory = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  double? _prevMonthPerKgRate(DateTime saleDate) {
    final key = _prevMonthKey(saleDate);
    final exp = _monthlyOpExpense[key];
    final kg = _monthlyKgSold[key];
    if (exp == null || kg == null || kg <= 0) return null;
    return exp / kg;
  }

  // ✅ FIX #7 — weighted sale-average weight (batch_detail_screen.dart ke
  // _computeWeightedSaleAvgWeight jaisa hi), taaki Big/Small classification
  // kisi ek leftover cost-entry weight se skew na ho.
  double _computeWeightedSaleAvgWeight(
    List<dynamic> entries, {
    required double fallback,
  }) {
    double totalWeightedSum = 0.0;
    double totalChicks = 0.0;
    for (final entry in entries) {
      if (entry is! Map) continue;
      if (entry['type'].toString().toLowerCase() != 'sale') continue;
      final chicks =
          double.tryParse(entry['chicksSold']?.toString() ?? '') ?? 0.0;
      final avgWt =
          double.tryParse(entry['avgWeightSold']?.toString() ?? '') ?? 0.0;
      if (chicks > 0 && avgWt > 0) {
        totalWeightedSum += chicks * avgWt;
        totalChicks += chicks;
      }
    }
    if (totalChicks > 0) return totalWeightedSum / totalChicks;
    return fallback;
  }

  _CatAmount _sumChicksForBatch(String batchId, double fallbackBilled) {
    if (batchId.isEmpty) return _CatAmount(fallbackBilled, 0);
    double billed = 0, cost = 0;
    bool found = false;
    for (final purchase in _chicksPurchaseHistory) {
      final double purchaseRate =
          (purchase['effectiveRate'] as num?)?.toDouble() ??
          (purchase['rate'] as num?)?.toDouble() ??
          0;
      final allocs = _dedupeAllocs((purchase['allocations'] as List?) ?? []);
      for (final a in allocs) {
        final allocType = (a['type']?.toString() ?? '').toLowerCase();
        if (allocType == 'company' && a['batchId']?.toString() == batchId) {
          final qty = (a['qty'] as num?)?.toDouble() ?? 0;
          final rate = (a['rate'] as num?)?.toDouble() ?? 0;
          billed += qty * rate;
          cost += qty * purchaseRate;
          found = true;
        }
      }
    }
    if (!found) return _CatAmount(fallbackBilled, 0);
    return _CatAmount(billed, cost);
  }

  _CatAmount _sumFeedForBatch(String batchId) {
    if (batchId.isEmpty) return const _CatAmount(0, 0);
    double billed = 0, cost = 0;
    for (final feedType in _feedStock) {
      final currentAvgCost =
          (feedType['weightedAvgCost'] as num?)?.toDouble() ?? 0;
      final allocs = _dedupeAllocs((feedType['allocations'] as List?) ?? []);
      for (final a in allocs) {
        if (a['batchId']?.toString() == batchId) {
          final qty = (a['qty'] as num?)?.toDouble() ?? 0;
          final rate = (a['rate'] as num?)?.toDouble() ?? 0;
          final costPerUnit =
              (a['costAtAllocation'] as num?)?.toDouble() ?? currentAvgCost;
          billed += qty * rate;
          cost += qty * costPerUnit;
        }
      }
    }
    return _CatAmount(billed, cost);
  }

  _CatAmount _sumMedicineForBatch(String batchId) {
    if (batchId.isEmpty) return const _CatAmount(0, 0);
    double billed = 0, cost = 0;
    for (final med in _medicineStock) {
      final currentAvgCostPerBase =
          (med['weightedAvgCost'] as num?)?.toDouble() ?? 0;
      final allocs = _dedupeAllocs((med['allocations'] as List?) ?? []);
      for (final a in allocs) {
        if (a['batchId']?.toString() == batchId) {
          final qty = (a['qty'] as num?)?.toDouble() ?? 0;
          final rate = (a['rate'] as num?)?.toDouble() ?? 0;
          final qtyBase = (a['qtyInBaseUnit'] as num?)?.toDouble() ?? qty;
          final costPerBase =
              (a['costAtAllocation'] as num?)?.toDouble() ??
              currentAvgCostPerBase;
          billed += qty * rate;
          cost += qtyBase * costPerBase;
        }
      }
    }
    return _CatAmount(billed, cost);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // ── Rule 1 config ──
    final r1Json = await CompanyStore.instance.getString(
      'rule1SettlementConfig',
    );
    if (r1Json != null && r1Json.isNotEmpty) {
      try {
        final r1 = Map<String, dynamic>.from(json.decode(r1Json));
        _r1BigFeedRate = (r1['bigFeedRate'] ?? 42.0).toDouble();
        _r1BigChicksRate = (r1['bigChicksRate'] ?? 40.0).toDouble();
        _r1BigAdminCost = (r1['bigAdminCost'] ?? 1.50).toDouble();
        _r1BigKgPerBag = (r1['bigKgPerBag'] ?? 50.0).toDouble();
        _r1BigTargetCost = (r1['bigTargetCost'] ?? 85.0).toDouble();
        _r1BigBaseComm = (r1['bigBaseComm'] ?? 8.0).toDouble();
        _r1BigSavingsShare = (r1['bigSavingsShare'] ?? 50.0).toDouble();
        _r1BigExceededShare = (r1['bigExceededShare'] ?? 50.0).toDouble();
        _r1BigRateBonusThresh = (r1['bigRateBonusThresh'] ?? 110.0).toDouble();
        _r1BigRateBonusShare = (r1['bigRateBonusShare'] ?? 10.0).toDouble();
        _r1BigMedicineInProd = r1['bigMedicineInProd'] ?? true;
        _r1SmFeedRate = (r1['smFeedRate'] ?? 42.0).toDouble();
        _r1SmChicksRate = (r1['smChicksRate'] ?? 40.0).toDouble();
        _r1SmAdminCost = (r1['smAdminCost'] ?? 1.50).toDouble();
        _r1SmKgPerBag = (r1['smKgPerBag'] ?? 50.0).toDouble();
        _r1SmTargetCost = (r1['smTargetCost'] ?? 90.0).toDouble();
        _r1SmBaseComm = (r1['smBaseComm'] ?? 10.0).toDouble();
        _r1SmSavingsShare = (r1['smSavingsShare'] ?? 50.0).toDouble();
        _r1SmExceededShare = (r1['smExceededShare'] ?? 50.0).toDouble();
        _r1SmRateBonusThresh = (r1['smRateBonusThresh'] ?? 120.0).toDouble();
        _r1SmRateBonusShare = (r1['smRateBonusShare'] ?? 10.0).toDouble();
        _r1SmMedicineInProd = r1['smMedicineInProd'] ?? true;
      } catch (_) {}
    }

    // ── Feed/Medicine/Chicks reference data ──
    List<Map<String, dynamic>> feedStock = [];
    try {
      feedStock = List<Map<String, dynamic>>.from(
        await ensureFeedStockMigrated(),
      );
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

    _feedStock = feedStock;
    _medicineStock = medStock;
    _chicksPurchaseHistory = chicksHistory;

    // ── Company-wide monthly Operational Expense ──
    final Map<String, double> monthlyOpExpense = {};
    final otherJson = await CompanyStore.instance.getString(
      'otherExpenseHistory',
    );
    if (otherJson != null) {
      try {
        for (final rawE in json.decode(otherJson) as List) {
          final e = Map<String, dynamic>.from(rawE);
          final d = _parseAnyDate(e['date']);
          if (d == null) continue;
          final amt = (e['amount'] as num?)?.toDouble() ?? 0.0;
          final key = _monthKey(d);
          monthlyOpExpense[key] = (monthlyOpExpense[key] ?? 0) + amt;
        }
      } catch (_) {}
    }
    final labourJson = await CompanyStore.instance.getString(
      'labourExpenseHistory',
    );
    if (labourJson != null) {
      try {
        for (final rawE in json.decode(labourJson) as List) {
          final e = Map<String, dynamic>.from(rawE);
          final d = _parseAnyDate(e['date']);
          if (d == null) continue;
          final amt = (e['totalAmount'] as num?)?.toDouble() ?? 0.0;
          final key = _monthKey(d);
          monthlyOpExpense[key] = (monthlyOpExpense[key] ?? 0) + amt;
        }
      } catch (_) {}
    }

    // ── Farmers + company-wide monthly KG sold ──
    final farmers = await CompanyStore.instance.getJsonList('companyFarmers');
    final Map<String, double> monthlyKgSold = {};
    for (final rawF in farmers) {
      final f = Map<String, dynamic>.from(rawF);
      final batches = (f['batches'] as List?) ?? [];
      for (final rawB in batches) {
        final b = Map<String, dynamic>.from(rawB);
        final entries = (b['dailyEntries'] as List?) ?? [];
        for (final rawE in entries) {
          final e = Map<String, dynamic>.from(rawE);
          if ((e['type'] ?? '').toString().toLowerCase() != 'sale') continue;
          final d = _parseDdMmYyyy(e['date']?.toString());
          if (d == null) continue;
          final kg =
              double.tryParse(e['totalWeightSold']?.toString() ?? '') ?? 0.0;
          if (kg <= 0) continue;
          monthlyKgSold[_monthKey(d)] = (monthlyKgSold[_monthKey(d)] ?? 0) + kg;
        }
      }
    }

    _monthlyOpExpense = monthlyOpExpense;
    _monthlyKgSold = monthlyKgSold;

    // ── Har farmer ke har batch ke liye trueTotalProfit calculate karo,
    // status ke saath store karo (filtering baad mein UI mein hogi) ──
    final List<_BatchProfitRecord> records = [];

    for (final rawF in farmers) {
      final f = Map<String, dynamic>.from(rawF);
      final farmerId = f['id']?.toString() ?? '';
      final farmerName = f['name']?.toString() ?? '-';
      final batches = (f['batches'] as List?) ?? [];
      if (batches.isEmpty) continue;

      for (final rawB in batches) {
        final b = Map<String, dynamic>.from(rawB);
        final batchId = (b['batchId'] ?? b['id'] ?? '').toString();
        final initialChicks = (b['chicksCount'] as num?)?.toInt() ?? 0;
        final entriesRaw = (b['dailyEntries'] as List?) ?? [];
        final String status = (b['status']?.toString() ?? 'ACTIVE')
            .toUpperCase();
        final bool isCompleted = status == 'COMPLETED' || status == 'CLOSED';

        // Sort by date (jaisa farmer_report_screen.dart karta hai)
        final indexed = List<MapEntry<int, Map<String, dynamic>>>.generate(
          entriesRaw.length,
          (i) => MapEntry(i, Map<String, dynamic>.from(entriesRaw[i])),
        );
        indexed.sort((a, b2) {
          final da = _parseAnyDate(a.value['date']);
          final db = _parseAnyDate(b2.value['date']);
          if (da != null && db != null) return da.compareTo(db);
          if (da != null) return -1;
          if (db != null) return 1;
          return a.key.compareTo(b2.key);
        });
        final entries = indexed.map((e) => e.value).toList();

        double totalWeightSoldKg = 0, totalSaleMoney = 0, latestAvgWeight = 0;
        double operationalExpenseShare = 0;
        bool opExpenseDataMissing = false;
        DateTime? lastSaleDate;

        for (final e in entries) {
          final type = e['type'].toString().toLowerCase();
          if (type == 'sale') {
            final saleKg =
                double.tryParse(e['totalWeightSold'].toString()) ?? 0;
            totalWeightSoldKg += saleKg;
            totalSaleMoney += double.tryParse(e['totalMoney'].toString()) ?? 0;
            final saleWt = double.tryParse(e['avgWeightSold'].toString()) ?? 0;
            if (saleWt > 0) latestAvgWeight = saleWt;

            final saleDate = _parseDdMmYyyy(e['date']?.toString());
            if (saleDate != null) {
              lastSaleDate = saleDate;
              final rate = _prevMonthPerKgRate(saleDate);
              if (rate != null) {
                operationalExpenseShare += saleKg * rate;
              } else if (saleKg > 0) {
                opExpenseDataMissing = true;
              }
            }
          } else if (type == 'cost') {
            final wt = double.tryParse(e['weight'].toString()) ?? 0;
            if (wt > 0) latestAvgWeight = wt;
          }
        }

        // ✅ FIX #7 — weighted sale-average weight, last-entry weight nahi
        final double sizeClassificationWeight = _computeWeightedSaleAvgWeight(
          entries,
          fallback: latestAvgWeight,
        );
        final isBigSize = sizeClassificationWeight > 1.2;

        final chicksRateFallback = isBigSize
            ? _r1BigChicksRate
            : _r1SmChicksRate;

        final chickBilledFallback =
            double.tryParse(b['totalChicksCost']?.toString() ?? '') ??
            (initialChicks *
                ((b['chicksRate'] as num?)?.toDouble() ?? chicksRateFallback));

        final chicksAmt = _sumChicksForBatch(batchId, chickBilledFallback);
        final feedAmt = _sumFeedForBatch(batchId);
        final medAmt = _sumMedicineForBatch(batchId);

        final bool hasAnyInvestment =
            chicksAmt.cost > 0 ||
            feedAmt.cost > 0 ||
            medAmt.cost > 0 ||
            totalSaleMoney > 0;
        if (!hasAnyInvestment) continue;

        // ✅ FIX #9 — flag karo jab sale hui ho lekin feed allocation-cost
        // record hi nahi hai (matlab ye batch sirf Flock se track hui,
        // Purchase→Allocate kabhi use hi nahi hua) — warna feed cost
        // silently ₹0 dikhta hai aur profit overstate ho jata hai.
        final bool allocationDataMissing =
            totalWeightSoldKg > 0 && feedAmt.cost <= 0;

        double farmerPayout;

        // ✅ FIX #8 — COMPLETED batches ke liye ACTUAL frozen settlement
        // snapshot (jo farmer ko diya gaya) use karo, live Rule-1 config se
        // dobara recalculate mat karo. Warna company baad mein rates
        // change kare to purani settled batches ka "profit" bhi silently
        // badal jayega — jo actual paid amount se mismatch karega.
        final Map<String, dynamic>? finalSnapshot =
            b['finalSettlementSnapshot'] is Map
            ? Map<String, dynamic>.from(b['finalSettlementSnapshot'])
            : null;

        if (isCompleted && finalSnapshot != null) {
          final ruleSnap = finalSnapshot['ruleSnapshot'] is Map
              ? Map<String, dynamic>.from(finalSnapshot['ruleSnapshot'])
              : null;
          final int? snapshotRuleId = ruleSnap != null
              ? (ruleSnap['ruleId'] as num?)?.toInt()
              : null;

          if (snapshotRuleId == 2) {
            // Rule 2 (FCR Matrix) — payout manual approval se aata hai
            farmerPayout =
                (finalSnapshot['approvedPayout'] as num?)?.toDouble() ?? 0.0;
          } else {
            farmerPayout =
                (finalSnapshot['netPayout'] as num?)?.toDouble() ?? 0.0;
          }
        } else {
          // ACTIVE batch ya settlement abhi tak nahi bana — sirf is case
          // mein live/current Rule-1 config se ESTIMATE karo (kyunki koi
          // frozen number exist hi nahi karta).
          final adminCost = isBigSize ? _r1BigAdminCost : _r1SmAdminCost;
          final medInProd = isBigSize
              ? _r1BigMedicineInProd
              : _r1SmMedicineInProd;
          final targetCost = isBigSize ? _r1BigTargetCost : _r1SmTargetCost;
          final baseComm = isBigSize ? _r1BigBaseComm : _r1SmBaseComm;
          final savingsShare = isBigSize
              ? _r1BigSavingsShare
              : _r1SmSavingsShare;
          final exceededShare = isBigSize
              ? _r1BigExceededShare
              : _r1SmExceededShare;
          final rateBonThresh = isBigSize
              ? _r1BigRateBonusThresh
              : _r1SmRateBonusThresh;
          final rateBonShare = isBigSize
              ? _r1BigRateBonusShare
              : _r1SmRateBonusShare;

          final adminIncome = totalWeightSoldKg * adminCost;
          double totalProdCost =
              chicksAmt.billed + feedAmt.billed + adminIncome;
          if (medInProd) totalProdCost += medAmt.billed;

          final actualCostPerKg = totalWeightSoldKg > 0
              ? totalProdCost / totalWeightSoldKg
              : 0.0;
          final costDiff = targetCost - actualCostPerKg;

          double costAdj = 0;
          if (costDiff > 0) {
            costAdj = costDiff * (savingsShare / 100);
          } else if (costDiff < 0) {
            costAdj = costDiff * (exceededShare / 100);
          }

          final avgSaleRate = totalWeightSoldKg > 0
              ? totalSaleMoney / totalWeightSoldKg
              : 0.0;
          final rateBonApplied =
              (actualCostPerKg <= targetCost) && (avgSaleRate >= rateBonThresh);
          final rateBonus = rateBonApplied
              ? (avgSaleRate - rateBonThresh) * (rateBonShare / 100)
              : 0.0;

          double finalComm = baseComm + costAdj + rateBonus;
          if (finalComm < 0) finalComm = 0;

          farmerPayout = totalWeightSoldKg * finalComm;
          if (!medInProd) farmerPayout -= medAmt.billed;
          if (farmerPayout < 0) farmerPayout = 0;
        }

        // ✅ Same trueTotalProfit formula jaisa farmer_report_screen.dart mein hai
        final double trueTotalProfit =
            totalSaleMoney -
            chicksAmt.cost -
            feedAmt.cost -
            medAmt.cost -
            operationalExpenseShare -
            farmerPayout;

        final double silentIncome =
            chicksAmt.income + feedAmt.income + medAmt.income;

        final DateTime trendDate =
            lastSaleDate ??
            _parseDdMmYyyy(b['startDate']?.toString()) ??
            DateTime.now();

        records.add(
          _BatchProfitRecord(
            farmerId: farmerId,
            farmerName: farmerName,
            batchId: batchId,
            isCompleted: isCompleted,
            trueTotalProfit: trueTotalProfit,
            silentIncome: silentIncome,
            opExpenseDataMissing: opExpenseDataMissing,
            allocationDataMissing: allocationDataMissing, // ✅ FIX #9 — naya
            trendDate: trendDate,
          ),
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _allRecords = records;
      _isLoading = false;
    });
  }

  // ✅ NEW: toggle ke hisaab se filtered records
  List<_BatchProfitRecord> get _filteredRecords {
    if (_includeActiveBatches) return _allRecords;
    return _allRecords.where((r) => r.isCompleted).toList();
  }

  // ✅ NEW: filtered records se farmer-wise aggregate banao
  List<_FarmerAgg> get _farmerAggs {
    final Map<String, _FarmerAgg> map = {};
    for (final r in _filteredRecords) {
      final agg = map.putIfAbsent(
        r.farmerId,
        () => _FarmerAgg(farmerId: r.farmerId, farmerName: r.farmerName),
      );
      agg.trueTotalProfit += r.trueTotalProfit;
      agg.batchCount += 1;
      if (r.opExpenseDataMissing) agg.opExpenseDataMissing = true;
      if (r.allocationDataMissing)
        agg.allocationDataMissing = true; // ✅ FIX #9 — naya
    }
    return map.values.toList();
  }

  // ── Trend: filtered records ko Daily/Weekly/Monthly bucket mein group karo ──
  List<MapEntry<DateTime, double>> _bucketedTrend() {
    final records = _filteredRecords;
    if (records.isEmpty) return [];

    DateTime bucketKey(DateTime d) {
      if (_granularity == 'Daily') return DateTime(d.year, d.month, d.day);
      if (_granularity == 'Weekly') {
        final dd = DateTime(d.year, d.month, d.day);
        return dd.subtract(Duration(days: dd.weekday - 1));
      }
      return DateTime(d.year, d.month, 1);
    }

    final Map<DateTime, double> buckets = {};
    for (final r in records) {
      final key = bucketKey(r.trendDate);
      buckets[key] = (buckets[key] ?? 0) + r.trueTotalProfit;
    }
    final keys = buckets.keys.toList()..sort();
    return keys.map((k) => MapEntry(k, buckets[k]!)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final trend = _bucketedTrend();
    final farmerAggs = _farmerAggs;
    final double totalNet = farmerAggs.fold(
      0.0,
      (s, f) => s + f.trueTotalProfit,
    );
    final bool anyMissing = farmerAggs.any((f) => f.opExpenseDataMissing);
    final bool anyAllocMissing = // ✅ FIX #9 — naya
    farmerAggs.any(
      (f) => f.allocationDataMissing,
    );

    final top5 = List<_FarmerAgg>.from(farmerAggs)
      ..sort((a, b) => b.trueTotalProfit.compareTo(a.trueTotalProfit));
    final bottom5 = List<_FarmerAgg>.from(farmerAggs)
      ..sort((a, b) => a.trueTotalProfit.compareTo(b.trueTotalProfit));

    final int activeBatchCount = _allRecords
        .where((r) => !r.isCompleted)
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _fplGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: const Text(
          '🧑‍🌾 Farmer Profit / Loss',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _fplGreen))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: _fplGreen,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_allRecords.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(30),
                      alignment: Alignment.center,
                      child: Text(
                        'Koi batch ka data nahi mila.',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    )
                  else ...[
                    // ✅ NEW: Active/Completed toggle
                    if (activeBatchCount > 0)
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.tune_rounded,
                                  size: 16,
                                  color: Colors.grey.shade700,
                                ),
                                const SizedBox(width: 6),
                                const Expanded(
                                  child: Text(
                                    'Active batches ka invest bhi minus karke dekhna hai?',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$activeBatchCount active batch${activeBatchCount == 1 ? '' : 'es'} mein abhi paisa laga hai lekin sale nahi hui — unka investment abhi "loss" jaisa dikhega jab tak sale na ho.',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Colors.grey.shade500,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _toggleChip(
                                    label: 'Haan, Minus Karo',
                                    selected: _includeActiveBatches,
                                    onTap: () => setState(
                                      () => _includeActiveBatches = true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _toggleChip(
                                    label: 'Nahi, Sirf Completed',
                                    selected: !_includeActiveBatches,
                                    onTap: () => setState(
                                      () => _includeActiveBatches = false,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                    if (anyMissing)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _warningBanner(
                          '⚠️ Kuch Data Missing Hai',
                          'Kuch batches ke liye pichle mahine ka Operational Expense data nahi mila — un par expense minus nahi hua.',
                        ),
                      ),

                    if (anyAllocMissing) // ✅ FIX #9 — naya
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _warningBanner(
                          '⚠️ Feed/Medicine Allocation Data Missing',
                          'Kuch batches mein sale hui hai lekin unka Feed '
                              'Purchase → Allocate se track nahi hua tha '
                              '(sirf Flock se record hua hoga) — un batches '
                              'ka Feed cost is report mein ₹0 dikh sakta hai, '
                              'jo profit ko galat tarike se badha hua dikhata hai.',
                        ),
                      ),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: totalNet >= 0
                              ? [
                                  const Color(0xFF0F3D12),
                                  const Color(0xFF2E7D32),
                                ]
                              : [Colors.red.shade900, Colors.red.shade600],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            totalNet >= 0
                                ? '📈 Company Ka Total Profit'
                                : '📉 Company Ka Total Loss',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${totalNet >= 0 ? "+" : "-"}₹${totalNet.abs().toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${farmerAggs.length} farmers ka combined result'
                            '${_includeActiveBatches ? "" : " (sirf completed batches)"}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '📊 Net Profit/Loss Trend',
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
                            'Har batch ka profit uski last sale date par plot hota hai',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 12),
                          trend.isEmpty
                              ? Container(
                                  height: 180,
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Koi trend data nahi mila.',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              : SizedBox(
                                  height: 200,
                                  child: _buildTrendChart(trend),
                                ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    _rankingSection(
                      title: '🏆 Top 5 — Sabse Zyada Profit',
                      list: top5,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 14),
                    _rankingSection(
                      title: '⚠️ Bottom 5 — Sabse Kam Profit / Loss (Dhyan Do)',
                      list: bottom5,
                      color: Colors.red,
                    ),
                  ],
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _toggleChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _fplGreen : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _fplGreen : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _warningBanner(String title, String message) {
    return Container(
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
                  color: sel ? _fplGreen : Colors.grey.shade600,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  Widget _buildTrendChart(List<MapEntry<DateTime, double>> trend) {
    double maxAbs = 0;
    for (final t in trend) {
      if (t.value.abs() > maxAbs) maxAbs = t.value.abs();
    }
    if (maxAbs <= 0) maxAbs = 100;
    final step = (trend.length / 5).ceil().clamp(1, trend.length);

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
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, m) => Text(
                '₹${(v / 1000).toStringAsFixed(0)}K',
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
                if (idx < 0 || idx >= trend.length || idx % step != 0)
                  return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _fmtDate(trend[idx].key),
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
            getTooltipItem: (g, gi, r, ri) {
              final t = trend[g.x.toInt()];
              return BarTooltipItem(
                '${t.value >= 0 ? "+" : ""}₹${t.value.toStringAsFixed(0)}\n${_fmtDate(t.key)}',
                const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
        ),
        barGroups: List.generate(trend.length, (i) {
          final v = trend[i].value;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: v,
                color: v >= 0 ? Colors.green.shade500 : Colors.red.shade400,
                width: trend.length > 25 ? 3 : 8,
                borderRadius: BorderRadius.circular(2),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _rankingSection({
    required String title,
    required List<_FarmerAgg> list,
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
            final f = entry.value;
            final bool isLoss = f.trueTotalProfit < 0;
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
                          f.farmerName,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${f.batchCount} batch${f.batchCount == 1 ? '' : 'es'}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${f.trueTotalProfit >= 0 ? "+" : "-"}₹${f.trueTotalProfit.abs().toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isLoss
                          ? Colors.red.shade700
                          : Colors.green.shade800,
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
