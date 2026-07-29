import 'dart:convert';
import '../../services/company_store.dart';
import '../home/purchase_expense_screen.dart' show ensureFeedStockMigrated;
import 'accounts_screen.dart' show AppDateFilter;

// ═══════════════════════════════════════════════════════════════════════════
// 💰 INCOME ENGINE — Shared calculation source-of-truth
//
// Ye file `farmer_report_screen.dart` ke True-Total-Profit formula ka EK
// COMPANY-WIDE (sab farmers, sab batches) version hai — sirf date-filtered
// bhi. Isko FarmerReportScreen ke formula se HAMESHA match hona chahiye:
//
//   True Total Profit = Total Sale
//                        − Chicks/Feed/Medicine ka ASAL company cost
//                        − Operational Expense share
//                        − Farmer ko asal mein diya gaya Payout
//
// Isi True Total Profit ko 4 category mein tod ke dikhaya jaata hai:
//   Chicks Income + Feed Income + Medicine Income + Admin/Operational Effect
// (Admin/Operational Effect = admin charge, cost-saving/penalty, rate bonus
//  waghera ka combined asar — jo "batch ke total profit" mein se Chicks/
//  Feed/Medicine ka margin nikalne ke baad bacha hua hissa hai). In chaaro
// ko jodne se HAMESHA True Total Profit hi milega, ek rupya bhi idhar-udhar
// nahi hoga.
//
// ✅ DATE-FILTERING ASSUMPTION (important, Gopi ko pata hona chahiye):
// Chicks/Feed/Medicine ka company-cost aur farmer-payout batch ke DAILY
// ENTRIES se nahi, balki purchase/allocation RECORDS se aata hai (jo sirf
// batchId se link hote hain, kisi ek sale-date se nahi). Isliye jab "is
// mahine kitna kamaya" nikalna ho, batch ka TOTAL profit us batch ke
// sale-dates par **kg-sold ke hisaab se proportionally baant** diya jaata
// hai. Example: batch ka total profit ₹10,000 hai, aur is batch ki 100kg
// sale hui — 60kg is month, 40kg pichle month — to is month ₹6,000 count
// hoga. Ye ek fair approximation hai, exact "us din ka feed cost" nahi,
// lekin sabhi mahino ka jod hamesha batch ke TRUE total ke barabar rahega
// (koi double-count ya missing amount nahi hoga).
// ═══════════════════════════════════════════════════════════════════════════

/// Chicks/Feed/Medicine/Admin-Operational — 4 category ka breakdown.
/// `total` in chaaron ka jod hai — hamesha True Total Profit ke barabar.
class CategoryBreakdown {
  final double chicks;
  final double feed;
  final double medicine;
  final double adminOperational;

  const CategoryBreakdown({
    this.chicks = 0,
    this.feed = 0,
    this.medicine = 0,
    this.adminOperational = 0,
  });

  double get total => chicks + feed + medicine + adminOperational;

  CategoryBreakdown operator +(CategoryBreakdown o) => CategoryBreakdown(
    chicks: chicks + o.chicks,
    feed: feed + o.feed,
    medicine: medicine + o.medicine,
    adminOperational: adminOperational + o.adminOperational,
  );

  static const zero = CategoryBreakdown();
}

// ── Internal: ek category ka billed (farmer se liya) vs cost (company ne
// khud khareeda) — dono se income (profit margin) nikalta hai. ──────────────
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

DateTime? _parseSaleDateDdMmYyyy(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final parts = s.trim().split('/');
  if (parts.length != 3) return null;
  try {
    final int day = int.parse(parts[0]);
    final int month = int.parse(parts[1]);
    final int year = int.parse(parts[2]);
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    final DateTime dt = DateTime(year, month, day);
    if (dt.year != year || dt.month != month || dt.day != day) return null;
    return dt;
  } catch (_) {
    return null;
  }
}

DateTime? _parseAnyEntryDate(Map<String, dynamic> e) {
  final String? raw = e['date']?.toString();
  final DateTime? dmy = _parseSaleDateDdMmYyyy(raw);
  if (dmy != null) return dmy;
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw.trim());
}

DateTime? _parseFlexibleDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final DateTime? dmy = _parseSaleDateDdMmYyyy(raw);
  if (dmy != null) return dmy;
  return DateTime.tryParse(raw.trim());
}

String _monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

String _previousMonthKey(DateTime d) {
  final prev = DateTime(d.year, d.month - 1, 1);
  return _monthKey(prev);
}

bool _inFilter(DateTime? d, AppDateFilter filter) {
  if (filter.isAllTime) return true;
  if (d == null) return false;
  if (filter.start == null || filter.end == null) return false;
  return d.isAfter(filter.start!.subtract(const Duration(seconds: 1))) &&
      d.isBefore(filter.end!.add(const Duration(days: 1)));
}

// ── Settlement config (Rule 1 — Big/Small) ──────────────────────────────────
class _SettlementConfig {
  final double adminCost;
  final double targetCost;
  final double baseComm;
  final double savingsShare;
  final double exceededShare;
  final double rateBonusThresh;
  final double rateBonusShare;
  final bool medicineInProd;

  const _SettlementConfig({
    required this.adminCost,
    required this.targetCost,
    required this.baseComm,
    required this.savingsShare,
    required this.exceededShare,
    required this.rateBonusThresh,
    required this.rateBonusShare,
    required this.medicineInProd,
  });
}

/// ═══════════════════════════════════════════════════════════════════════
/// 🧑‍🌾 COMPANY ↔ FARMER — company-wide, date-filtered
/// ═══════════════════════════════════════════════════════════════════════
Future<CategoryBreakdown> computeCompanyFarmerIncome(
  AppDateFilter filter,
) async {
  // Rule 1 settings (Big/Small) — same defaults jaise farmer_report_screen
  double r1BigAdminCost = 1.50, r1SmAdminCost = 1.50;
  double r1BigTargetCost = 85.0, r1SmTargetCost = 90.0;
  double r1BigBaseComm = 8.0, r1SmBaseComm = 10.0;
  double r1BigSavingsShare = 50.0, r1SmSavingsShare = 50.0;
  double r1BigExceededShare = 50.0, r1SmExceededShare = 50.0;
  double r1BigRateBonusThresh = 110.0, r1SmRateBonusThresh = 120.0;
  double r1BigRateBonusShare = 10.0, r1SmRateBonusShare = 10.0;
  bool r1BigMedicineInProd = true, r1SmMedicineInProd = true;

  final String? rule1Json = await CompanyStore.instance.getString(
    'rule1SettlementConfig',
  );
  if (rule1Json != null && rule1Json.isNotEmpty) {
    try {
      final Map<String, dynamic> r1 = json.decode(rule1Json);
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

  _SettlementConfig resolveCfg(Map<String, dynamic> batch, bool isBigSize) {
    final dynamic rawSnap = batch['settlementSnapshot'];
    if (rawSnap is Map) {
      try {
        final Map<String, dynamic> snap = Map<String, dynamic>.from(rawSnap);
        final String prefix = isBigSize ? 'big' : 'sm';
        double snapDouble(String key, double fallback) =>
            (snap['$prefix$key'] as num?)?.toDouble() ?? fallback;
        return _SettlementConfig(
          adminCost: snapDouble(
            'AdminCost',
            isBigSize ? r1BigAdminCost : r1SmAdminCost,
          ),
          targetCost: snapDouble(
            'TargetCost',
            isBigSize ? r1BigTargetCost : r1SmTargetCost,
          ),
          baseComm: snapDouble(
            'BaseComm',
            isBigSize ? r1BigBaseComm : r1SmBaseComm,
          ),
          savingsShare: snapDouble(
            'SavingsShare',
            isBigSize ? r1BigSavingsShare : r1SmSavingsShare,
          ),
          exceededShare: snapDouble(
            'ExceededShare',
            isBigSize ? r1BigExceededShare : r1SmExceededShare,
          ),
          rateBonusThresh: snapDouble(
            'RateBonusThresh',
            isBigSize ? r1BigRateBonusThresh : r1SmRateBonusThresh,
          ),
          rateBonusShare: snapDouble(
            'RateBonusShare',
            isBigSize ? r1BigRateBonusShare : r1SmRateBonusShare,
          ),
          medicineInProd:
              (snap['${prefix}MedicineInProd'] as bool?) ??
              (isBigSize ? r1BigMedicineInProd : r1SmMedicineInProd),
        );
      } catch (_) {}
    }
    return _SettlementConfig(
      adminCost: isBigSize ? r1BigAdminCost : r1SmAdminCost,
      targetCost: isBigSize ? r1BigTargetCost : r1SmTargetCost,
      baseComm: isBigSize ? r1BigBaseComm : r1SmBaseComm,
      savingsShare: isBigSize ? r1BigSavingsShare : r1SmSavingsShare,
      exceededShare: isBigSize ? r1BigExceededShare : r1SmExceededShare,
      rateBonusThresh: isBigSize ? r1BigRateBonusThresh : r1SmRateBonusThresh,
      rateBonusShare: isBigSize ? r1BigRateBonusShare : r1SmRateBonusShare,
      medicineInProd: isBigSize ? r1BigMedicineInProd : r1SmMedicineInProd,
    );
  }

  final farmersList = await CompanyStore.instance.getJsonList('companyFarmers');

  List<Map<String, dynamic>> feedStock = [];
  try {
    feedStock = List<Map<String, dynamic>>.from(
      await ensureFeedStockMigrated(),
    );
  } catch (_) {}

  List<Map<String, dynamic>> medStock = [];
  final String? medJson = await CompanyStore.instance.getString(
    'medicineStockList',
  );
  if (medJson != null) {
    try {
      medStock = (json.decode(medJson) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {}
  }

  List<Map<String, dynamic>> chicksHistory = [];
  final String? chicksJson = await CompanyStore.instance.getString(
    'chicksPurchaseHistory',
  );
  if (chicksJson != null) {
    try {
      chicksHistory = (json.decode(chicksJson) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {}
  }

  _CatAmount sumChicksForBatch(String batchId, double fallbackBilled) {
    if (batchId.isEmpty) return _CatAmount(fallbackBilled, 0);
    double billed = 0, cost = 0;
    bool found = false;
    for (final purchase in chicksHistory) {
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

  _CatAmount sumFeedForBatch(String batchId) {
    if (batchId.isEmpty) return const _CatAmount(0, 0);
    double billed = 0, cost = 0;
    for (final feedType in feedStock) {
      final currentAvgCost =
          (feedType['weightedAvgCost'] as num?)?.toDouble() ?? 0;
      final allocs = _dedupeAllocs((feedType['allocations'] as List?) ?? []);
      for (final a in allocs) {
        if (a['batchId']?.toString() == batchId) {
          final qty = (a['qty'] as num?)?.toDouble() ?? 0;
          final rate = (a['rate'] as num?)?.toDouble() ?? 0;
          final costPerUnit = a['costAtAllocation'] != null
              ? (a['costAtAllocation'] as num).toDouble()
              : currentAvgCost;
          billed += qty * rate;
          cost += qty * costPerUnit;
        }
      }
    }
    return _CatAmount(billed, cost);
  }

  _CatAmount sumMedicineForBatch(String batchId) {
    if (batchId.isEmpty) return const _CatAmount(0, 0);
    double billed = 0, cost = 0;
    for (final med in medStock) {
      final currentAvgCostPerBase =
          (med['weightedAvgCost'] as num?)?.toDouble() ?? 0;
      final allocs = _dedupeAllocs((med['allocations'] as List?) ?? []);
      for (final a in allocs) {
        if (a['batchId']?.toString() == batchId) {
          final qty = (a['qty'] as num?)?.toDouble() ?? 0;
          final rate = (a['rate'] as num?)?.toDouble() ?? 0;
          final qtyBase = a['qtyInBaseUnit'] != null
              ? (a['qtyInBaseUnit'] as num).toDouble()
              : qty;
          final costPerBase = a['costAtAllocation'] != null
              ? (a['costAtAllocation'] as num).toDouble()
              : currentAvgCostPerBase;
          billed += qty * rate;
          cost += qtyBase * costPerBase;
        }
      }
    }
    return _CatAmount(billed, cost);
  }

  // Company-wide monthly Operational Expense + KG Sold — pichle-mahine ka
  // per-KG rate nikalne ke liye (jaisa Operational Expense report karta hai)
  final Map<String, double> monthlyOpExpense = {};
  final Map<String, double> monthlyKgSold = {};

  final String? otherJson = await CompanyStore.instance.getString(
    'otherExpenseHistory',
  );
  if (otherJson != null) {
    try {
      for (final rawE in (json.decode(otherJson) as List)) {
        final e = Map<String, dynamic>.from(rawE);
        final d = _parseAnyEntryDate(e);
        if (d == null) continue;
        final amt = (e['amount'] as num?)?.toDouble() ?? 0.0;
        monthlyOpExpense[_monthKey(d)] =
            (monthlyOpExpense[_monthKey(d)] ?? 0) + amt;
      }
    } catch (_) {}
  }

  final String? labourJson = await CompanyStore.instance.getString(
    'labourExpenseHistory',
  );
  if (labourJson != null) {
    try {
      for (final rawE in (json.decode(labourJson) as List)) {
        final e = Map<String, dynamic>.from(rawE);
        final d = _parseAnyEntryDate(e);
        if (d == null) continue;
        final amt = (e['totalAmount'] as num?)?.toDouble() ?? 0.0;
        monthlyOpExpense[_monthKey(d)] =
            (monthlyOpExpense[_monthKey(d)] ?? 0) + amt;
      }
    } catch (_) {}
  }

  for (final rawF in farmersList) {
    final f = Map<String, dynamic>.from(rawF);
    for (final rawB in ((f['batches'] as List?) ?? [])) {
      final b = Map<String, dynamic>.from(rawB);
      for (final rawE in ((b['dailyEntries'] as List?) ?? [])) {
        final e = Map<String, dynamic>.from(rawE);
        if ((e['type'] ?? '').toString().toLowerCase() != 'sale') continue;
        final d = _parseSaleDateDdMmYyyy(e['date']?.toString());
        if (d == null) continue;
        final kg =
            double.tryParse(e['totalWeightSold']?.toString() ?? '') ?? 0.0;
        if (kg <= 0) continue;
        monthlyKgSold[_monthKey(d)] = (monthlyKgSold[_monthKey(d)] ?? 0) + kg;
      }
    }
  }

  double? prevMonthPerKgRate(DateTime saleDate) {
    final prevKey = _previousMonthKey(saleDate);
    final expense = monthlyOpExpense[prevKey];
    final kg = monthlyKgSold[prevKey];
    if (expense == null || kg == null || kg <= 0) return null;
    return expense / kg;
  }

  // ── Har batch ka True Total Profit + category-split nikalo, phir
  // period ke andar aane wale sale-dates ke kg-share se prorate karo ──
  CategoryBreakdown result = CategoryBreakdown.zero;

  for (final rawF in farmersList) {
    final f = Map<String, dynamic>.from(rawF);
    for (final rawB in ((f['batches'] as List?) ?? [])) {
      final batch = Map<String, dynamic>.from(rawB);
      final batchId = (batch['batchId'] ?? batch['id'] ?? '').toString();
      final entries = (batch['dailyEntries'] as List?) ?? [];

      double totalWeightSoldKg = 0;
      double totalSaleMoney = 0;
      double latestAvgWeight = 0;
      double operationalExpenseShare = 0;
      final List<Map<String, dynamic>> saleEntries = [];

      for (final rawE in entries) {
        final e = Map<String, dynamic>.from(rawE as Map);
        final type = e['type'].toString().toLowerCase();
        if (type == 'sale') {
          final saleKg = double.tryParse(e['totalWeightSold'].toString()) ?? 0;
          final saleMoney = double.tryParse(e['totalMoney'].toString()) ?? 0;
          totalWeightSoldKg += saleKg;
          totalSaleMoney += saleMoney;
          final saleWt = double.tryParse(e['avgWeightSold'].toString()) ?? 0;
          if (saleWt > 0) latestAvgWeight = saleWt;
          final saleDate = _parseSaleDateDdMmYyyy(e['date']?.toString());
          double entryOpExp = 0;
          if (saleKg > 0 && saleDate != null) {
            final rate = prevMonthPerKgRate(saleDate);
            if (rate != null) entryOpExp = saleKg * rate;
          }
          operationalExpenseShare += entryOpExp;
          saleEntries.add({'date': saleDate, 'kg': saleKg});
        } else if (type == 'cost') {
          final wt = double.tryParse(e['weight'].toString()) ?? 0;
          if (wt > 0) latestAvgWeight = wt;
        }
      }

      if (totalWeightSoldKg <= 0)
        continue; // koi sale hi nahi hui is batch mein

      final isBigSize = latestAvgWeight > 1.2;
      final cfg = resolveCfg(batch, isBigSize);
      final adminCost = cfg.adminCost;
      final medInProd = cfg.medicineInProd;

      final chickBilledFallback =
          double.tryParse(batch['totalChicksCost']?.toString() ?? '') ??
          (((batch['chicksCount'] ?? 0) as num).toDouble() *
              ((batch['chicksRate'] as num?)?.toDouble() ?? 40.0));

      final chicksAmt = sumChicksForBatch(batchId, chickBilledFallback);
      final feedAmt = sumFeedForBatch(batchId);
      final medAmt = sumMedicineForBatch(batchId);

      final adminIncome = totalWeightSoldKg * adminCost;
      double totalProdCost = chicksAmt.billed + feedAmt.billed + adminIncome;
      if (medInProd) totalProdCost += medAmt.billed;

      final actualCostPerKg = totalProdCost / totalWeightSoldKg;
      final costDiff = cfg.targetCost - actualCostPerKg;
      double costAdj = 0;
      if (costDiff > 0) {
        costAdj = costDiff * (cfg.savingsShare / 100);
      } else if (costDiff < 0) {
        costAdj = costDiff * (cfg.exceededShare / 100);
      }
      final avgSaleRate = totalSaleMoney / totalWeightSoldKg;
      final rateBonApplied =
          (actualCostPerKg <= cfg.targetCost) &&
          (avgSaleRate >= cfg.rateBonusThresh);
      final rateBonus = rateBonApplied
          ? (avgSaleRate - cfg.rateBonusThresh) * (cfg.rateBonusShare / 100)
          : 0.0;

      double finalComm = cfg.baseComm + costAdj + rateBonus;
      if (finalComm < 0) finalComm = 0;
      double farmerPayout = totalWeightSoldKg * finalComm;
      if (!medInProd) farmerPayout -= medAmt.billed;
      if (farmerPayout < 0) farmerPayout = 0;

      // ── Batch ka TOTAL True Profit + 4-category split ──
      final double silentTotal =
          chicksAmt.income + feedAmt.income + medAmt.income;
      final double trueTotal =
          totalSaleMoney -
          chicksAmt.cost -
          feedAmt.cost -
          medAmt.cost -
          operationalExpenseShare -
          farmerPayout;
      final double adminOpTotal = trueTotal - silentTotal;

      // ── Ab is batch ka total 4 numbers ko sale-dates par kg-share se
      // baanto, aur sirf period ke andar wale hisse count karo ──
      for (final se in saleEntries) {
        final kg = se['kg'] as double;
        if (kg <= 0) continue;
        final DateTime? d = se['date'] as DateTime?;
        if (!_inFilter(d, filter)) continue;
        final double share = kg / totalWeightSoldKg;
        result =
            result +
            CategoryBreakdown(
              chicks: chicksAmt.income * share,
              feed: feedAmt.income * share,
              medicine: medAmt.income * share,
              adminOperational: adminOpTotal * share,
            );
      }
    }
  }

  return result;
}

/// ═══════════════════════════════════════════════════════════════════════
/// 🛒 PRIVATE SALES — Chicks/Feed/Medicine, seedha Sales screen ke data se
/// ═══════════════════════════════════════════════════════════════════════
Future<CategoryBreakdown> computePrivateSalesIncome(
  AppDateFilter filter,
) async {
  double chicksProfit = 0, feedProfit = 0, medicineProfit = 0;

  // 🐣 Chicks Private Sale — chicksPurchaseHistory ke andar 'Private' allocs
  final String? chicksJson = await CompanyStore.instance.getString(
    'chicksPurchaseHistory',
  );
  if (chicksJson != null) {
    try {
      final List<dynamic> purchases = json.decode(chicksJson);
      for (final rawP in purchases) {
        final purchase = Map<String, dynamic>.from(rawP);
        final double purchaseRate =
            (purchase['effectiveRate'] as num?)?.toDouble() ??
            (purchase['rate'] as num?)?.toDouble() ??
            0.0;
        final allocs = _dedupeAllocs((purchase['allocations'] as List?) ?? []);
        for (final rawA in allocs) {
          final alloc = Map<String, dynamic>.from(rawA);
          if (alloc['type'] != 'Private') continue;
          final d = _parseFlexibleDate(alloc['allocatedOn']?.toString());
          if (!_inFilter(d, filter)) continue;
          final qty = (alloc['qty'] as num?)?.toDouble() ?? 0.0;
          final rate = (alloc['rate'] as num?)?.toDouble() ?? 0.0;
          chicksProfit += (qty * rate) - (qty * purchaseRate);
        }
      }
    } catch (_) {}
  }

  // 🌾 Feed Sale — profitAmount already stored per sale
  final String? feedSalesJson = await CompanyStore.instance.getString(
    'feedSalesHistory',
  );
  if (feedSalesJson != null) {
    try {
      for (final rawS in (json.decode(feedSalesJson) as List)) {
        final sale = Map<String, dynamic>.from(rawS);
        final d = _parseFlexibleDate(sale['date']?.toString());
        if (!_inFilter(d, filter)) continue;
        feedProfit += (sale['profitAmount'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {}
  }

  // 💊 Medicine Sale — profitAmount already stored per sale
  final String? medSalesJson = await CompanyStore.instance.getString(
    'medicineSalesHistory',
  );
  if (medSalesJson != null) {
    try {
      for (final rawS in (json.decode(medSalesJson) as List)) {
        final sale = Map<String, dynamic>.from(rawS);
        final d = _parseFlexibleDate(sale['date']?.toString());
        if (!_inFilter(d, filter)) continue;
        medicineProfit += (sale['profitAmount'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {}
  }

  return CategoryBreakdown(
    chicks: chicksProfit,
    feed: feedProfit,
    medicine: medicineProfit,
    adminOperational: 0,
  );
}
