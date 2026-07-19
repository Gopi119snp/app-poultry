import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'dart:math' as math;
import '../../services/company_store.dart';
import '../home/purchase_expense_screen.dart' show ensureFeedStockMigrated;

// =============================================================================
// FARMER REPORT SCREEN — Main screen ab sirf "abhi jo batch khatam hua" (sabse
// recent COMPLETED batch) ka poora income breakdown dikhata hai, + ek button
// "Sabhi Reports Dekho" jo alag screen (AllBatchesReportScreen) kholta hai
// jisme abhi tak ke SAARE batches ki list + total summary hoti hai.
//
// ✅ NEW: Har lot card ke neeche ek "Detail Information Dekho" button hai —
// isse BatchDetailInformationScreen khulti hai jisme Chicks/Feed/Medicine
// har ek ka alag line/area chart (Company Rate vs Farmer Rate, cumulative
// quantity ke against) aur profit/loss dikhta hai.
//
// ────────────────────────────────────────────────────────────────────────────
// 🔧 BUG-FIX PASS NOTES (isi file ke andar):
// Fixed (safe, unambiguous):
//   - "Last N" filter tha reversed (oldest N utha raha tha, ab latest N).
//   - Chicks allocation 'type' match ab case-insensitive hai.
//   - Sale-date parser ab strict hai (invalid dates jaise 32/01 reject karta
//     hai, silently normalize nahi hone deta).
//   - Daily entries ab date ke hisaab se sort karke process hote hain (isse
//     "latest weight" wala bug + entry-order-dependent classification bug
//     dono fix hote hain).
//   - "latestAvgWeight" ab sach mein sabse latest weight leta hai (pehle
//     accidentally sabse PEHLI valid weight le raha tha).
//   - Missing/estimated cost data (chicks/feed/medicine) ab silently 0/wrong
//     nahi maana jaata — flag hoke UI mein "estimated" ke roop mein dikhta
//     hai (jaisa pehle se Operational Expense missing case mein hota tha).
//   - Silent `catch (_) {}` blocks ab kam se kam debugPrint karte hain aur
//     user-facing warning banner mein bhi surface hote hain.
//   - Duplicate allocation records (agar unka apna unique id ho) ab dedupe
//     ho jaate hain.
//   - feedStockList ab migration-safe loader (ensureFeedStockMigrated) se
//     load hota hai, jaisa detail screen already karti thi.
//   - _allEarnings ab per-load ek hi baar calculate hokar cache hota hai.
//   - Unused TickerProviderStateMixin hata diya.
//   - Pie chart ab loss-wale batches ko red border se visually alag dikhata
//     hai (magnitude hamesha positive slice ke roop mein dikhegi, lekin ab
//     sign clearly dikhta hai).
//
// Business-rule-dependent (JAAN-BOOJH KAR unchanged chhoda hai — neeche
// TODO(confirm) comments dekho, aur chat mein sawal poochha hai):
//   - Operational expense lagged-allocation methodology
//   - Big/Small boundary (> 1.2 vs >= 1.2)
//   - No-weight-data => Small Size default
//   - Negative farmer payout ko 0 clamp karna
//   - Medicine deduction jab !medInProd
//   - Admin income ko "income" treat karna
//   - Active (incomplete) batches ko total summary mein include karna
//   - "Abhi jo batch khatam hua" list-order se nikalna (completedDate field
//     nahi mila, isliye abhi bhi `.last` use ho raha hai)
//   - Settlement Rule config ka snapshot-at-close-time na hona (batch close
//     hone ke baad bhi current rules se recalculate hota hai)
// ────────────────────────────────────────────────────────────────────────────

const Color primaryGreen = Color(0xFF1B5E20);

/// Ek category (Chicks/Feed/Medicine) ka billed (farmer se liya) vs cost
/// (company ne khud khareeda) — dono se income (profit margin) nikalta hai.
class _CatAmount {
  final double billed;
  final double cost;

  /// true = cost ek real linked purchase/allocation record se nahi aayi,
  /// balki fallback/estimate hai (purani/incomplete data ki wajah se).
  /// Report mein ye number isliye "estimated" flag ke saath dikhta hai,
  /// silently precise fact ki tarah nahi.
  final bool costEstimated;
  const _CatAmount(this.billed, this.cost, {this.costEstimated = false});
  double get income => billed - cost;
}

/// Allocation records mein agar apna unique id ho (allocationId/id), to
/// accidental duplicate-saved allocations ko dedupe karta hai. Agar id field
/// hi nahi hai, behavior bilkul pehle jaisa hi rehta hai (no-op).
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

// ── Shared Formatters ───────────────────────────────────────────────────────
String fmt(double v) {
  final double abs = v.abs();
  if (abs >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
  if (abs >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  return v.toStringAsFixed(0);
}

String fmtShort(double v) => fmt(v);

// ── ✅ Operational Expense helpers ──────────────────────────────────────────

/// Strict dd/MM/yyyy parser. Dart ka DateTime constructor kuch out-of-range
/// values (jaise din=32) ko silently agle mahine mein "roll" kar deta hai —
/// isliye reconstruct karke wapas compare karte hain; mismatch = invalid date.
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
    if (dt.year != year || dt.month != month || dt.day != day) {
      return null; // Dart ne normalize kar diya — matlab original invalid tha
    }
    return dt;
  } catch (_) {
    return null;
  }
}

/// Kisi bhi daily-entry map se date nikalne ki koshish karta hai — pehle
/// dd/MM/yyyy (jaisa sale entries mein hota hai), phir ISO-style tryParse
/// (jaisa cost/other entries mein ho sakta hai). Dono fail ho to null.
DateTime? _parseAnyEntryDate(Map<String, dynamic> e) {
  final String? raw = e['date']?.toString();
  final DateTime? dmy = _parseSaleDateDdMmYyyy(raw);
  if (dmy != null) return dmy;
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw.trim());
}

String _monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

String _previousMonthKey(DateTime d) {
  final prev = DateTime(d.year, d.month - 1, 1);
  return _monthKey(prev);
}

class FarmerReportScreen extends StatefulWidget {
  final Map<String, dynamic> farmer;
  const FarmerReportScreen({super.key, required this.farmer});

  @override
  State<FarmerReportScreen> createState() => _FarmerReportScreenState();
}

class _FarmerReportScreenState extends State<FarmerReportScreen> {
  List<Map<String, dynamic>> _batches = [];
  bool _isLoading = true;

  // ✅ Asal (actual) purchase/allocation data — company ka INCOME nikalne
  // ke liye zaroori hai (billed amount − actual purchase cost).
  List<Map<String, dynamic>> _feedStock = [];
  List<Map<String, dynamic>> _medicineStock = [];
  List<Map<String, dynamic>> _chicksPurchaseHistory = [];

  // ✅ Company-wide monthly totals — Operational Expense rate ke liye
  Map<String, double> _monthlyOpExpense = {};
  Map<String, double> _monthlyKgSold = {};

  // ✅ NEW: Data-quality warnings — silent catch se aane wali cheezein ab
  // yahan surface hoti hain (poori tarah chhupti nahi).
  List<String> _dataWarnings = [];

  // ✅ NEW: _allEarnings ab har _loadData() ke baad ek hi baar calculate
  // hokar cache ho jaata hai (pehle har getter-access par pura recalculation
  // hota tha — batches/allocations bade hone par slow ho sakta tha).
  List<_LotEarning>? _cachedEarnings;

  // Rule 1 — Big Size
  double _r1BigFeedRate = 42.0;
  double _r1BigChicksRate = 40.0;
  double _r1BigAdminCost = 1.50;
  double _r1BigKgPerBag = 50.0;
  double _r1BigTargetCost = 85.0;
  double _r1BigBaseComm = 8.0;
  double _r1BigSavingsShare = 50.0;
  double _r1BigExceededShare = 50.0;
  double _r1BigRateBonusThresh = 110.0;
  double _r1BigRateBonusShare = 10.0;
  bool _r1BigMedicineInProd = true;

  // Rule 1 — Small Size
  double _r1SmFeedRate = 42.0;
  double _r1SmChicksRate = 40.0;
  double _r1SmAdminCost = 1.50;
  double _r1SmKgPerBag = 50.0;
  double _r1SmTargetCost = 90.0;
  double _r1SmBaseComm = 10.0;
  double _r1SmSavingsShare = 50.0;
  double _r1SmExceededShare = 50.0;
  double _r1SmRateBonusThresh = 120.0;
  double _r1SmRateBonusShare = 10.0;
  bool _r1SmMedicineInProd = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final List<String> dataWarnings = [];

    final String? rule1Json = await CompanyStore.instance.getString(
      'rule1SettlementConfig',
    );

    if (rule1Json != null && rule1Json.isNotEmpty) {
      try {
        final Map<String, dynamic> r1 = json.decode(rule1Json);
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
      } catch (e) {
        debugPrint(
          'FarmerReportScreen: rule1SettlementConfig parse failed: $e',
        );
        dataWarnings.add(
          'Settlement rule config load nahi ho saka — default values use ho rahe hain.',
        );
      }
    }

    final farmersList = await CompanyStore.instance.getJsonList(
      'companyFarmers',
    );
    Map<String, dynamic>? freshFarmer;
    for (var f in farmersList) {
      if (f['id'] == widget.farmer['id']) {
        freshFarmer = Map<String, dynamic>.from(f);
        break;
      }
    }

    List<Map<String, dynamic>> allBatches = [];
    if (freshFarmer != null && freshFarmer['batches'] != null) {
      for (var b in (freshFarmer['batches'] as List)) {
        allBatches.add(Map<String, dynamic>.from(b));
      }
    }

    // ✅ Feed stock (per-type allocations, batchId-linked) — migration-safe
    // loader use karo (pehle yahan raw getJsonList tha jo purani entries ke
    // liye migration skip kar deta tha, jabki detail screen migration-safe
    // loader use karti thi — dono jagah consistent hona chahiye).
    List<Map<String, dynamic>> feedStock = [];
    try {
      feedStock = List<Map<String, dynamic>>.from(
        await ensureFeedStockMigrated(),
      );
    } catch (e) {
      debugPrint('FarmerReportScreen: feed stock load/migration failed: $e');
      dataWarnings.add(
        'Feed stock data load nahi ho saka — Feed income is report mein 0 dikhega.',
      );
    }

    // ✅ Medicine stock (per-medicine allocations, batchId-linked) load karo
    List<Map<String, dynamic>> medStock = [];
    final String? medJson = await CompanyStore.instance.getString(
      'medicineStockList',
    );
    if (medJson != null) {
      try {
        final List<dynamic> raw = json.decode(medJson);
        medStock = raw.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {
        debugPrint('FarmerReportScreen: medicineStockList parse failed: $e');
        dataWarnings.add(
          'Medicine stock data corrupt/load nahi ho saka — Medicine income is report mein 0 dikhega.',
        );
      }
    }

    // ✅ Chicks purchase history (batchId-linked allocations) load karo —
    // isi se company ka chicks purchase-rate pata chalta hai.
    List<Map<String, dynamic>> chicksHistory = [];
    final String? chicksJson = await CompanyStore.instance.getString(
      'chicksPurchaseHistory',
    );
    if (chicksJson != null) {
      try {
        final List<dynamic> raw = json.decode(chicksJson);
        chicksHistory = raw.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {
        debugPrint(
          'FarmerReportScreen: chicksPurchaseHistory parse failed: $e',
        );
        dataWarnings.add(
          'Chicks purchase history load nahi ho saka — Chicks income estimate ho sakta hai.',
        );
      }
    }

    // ✅ Company-wide monthly Operational Expense + KG Sold nikalo —
    // taaki har mahine ka "per-KG operational cost" pata chal sake. Ye
    // COMPANY-WIDE hai (sirf is farmer ka nahi), isliye poori farmersList
    // use karte hain.
    final Map<String, double> monthlyOpExpense = {};
    final Map<String, double> monthlyKgSold = {};

    // Other Expense — us mahine mein pura amount jud jaega
    final String? otherJson = await CompanyStore.instance.getString(
      'otherExpenseHistory',
    );
    if (otherJson != null) {
      try {
        final List<dynamic> raw = json.decode(otherJson);
        for (final rawE in raw) {
          final e = Map<String, dynamic>.from(rawE);
          final d = DateTime.tryParse(e['date']?.toString() ?? '');
          if (d == null) continue;
          final amt = (e['amount'] as num?)?.toDouble() ?? 0.0;
          final key = _monthKey(d);
          monthlyOpExpense[key] = (monthlyOpExpense[key] ?? 0) + amt;
        }
      } catch (e) {
        debugPrint('FarmerReportScreen: otherExpenseHistory parse failed: $e');
        dataWarnings.add('Other Expense history load nahi ho saka.');
      }
    }

    // Labour Expense — Din/Ghanta/Monthly sab us entry ke apne mahine mein
    // pura amount jud jaega (monthly salary uske record hone wale mahine
    // ki hi maani jaati hai).
    final String? labourJson = await CompanyStore.instance.getString(
      'labourExpenseHistory',
    );
    if (labourJson != null) {
      try {
        final List<dynamic> raw = json.decode(labourJson);
        for (final rawE in raw) {
          final e = Map<String, dynamic>.from(rawE);
          final d = DateTime.tryParse(e['date']?.toString() ?? '');
          if (d == null) continue;
          final amt = (e['totalAmount'] as num?)?.toDouble() ?? 0.0;
          final key = _monthKey(d);
          monthlyOpExpense[key] = (monthlyOpExpense[key] ?? 0) + amt;
        }
      } catch (e) {
        debugPrint('FarmerReportScreen: labourExpenseHistory parse failed: $e');
        dataWarnings.add('Labour Expense history load nahi ho saka.');
      }
    }

    // Company-wide Total KG Sold — SAARE farmers ke SAARE batches ki sale
    // entries se, unke sale-date ke mahine ke hisaab se.
    // TODO(confirm): Other/Labour expense dates DateTime.tryParse (ISO-style)
    // se parse ho rahe hain jabki sale dates dd/MM/yyyy se — agar in dono
    // history ke 'date' fields bhi asal mein dd/MM/yyyy string hain (na ki
    // ISO), to ye silently records skip kar sakta hai. Confirm karo ki
    // otherExpenseHistory/labourExpenseHistory mein date kis format mein
    // save hoti hai.
    for (final rawF in farmersList) {
      final f = Map<String, dynamic>.from(rawF);
      final batches = (f['batches'] as List?) ?? [];
      for (final rawB in batches) {
        final b = Map<String, dynamic>.from(rawB);
        final entries = (b['dailyEntries'] as List?) ?? [];
        for (final rawE in entries) {
          final e = Map<String, dynamic>.from(rawE);
          if ((e['type'] ?? '').toString().toLowerCase() != 'sale') continue;
          final d = _parseSaleDateDdMmYyyy(e['date']?.toString());
          if (d == null) continue;
          final kg =
              double.tryParse(e['totalWeightSold']?.toString() ?? '') ?? 0.0;
          if (kg <= 0) continue;
          final key = _monthKey(d);
          monthlyKgSold[key] = (monthlyKgSold[key] ?? 0) + kg;
        }
      }
    }

    if (mounted) {
      setState(() {
        _batches = allBatches;
        _feedStock = feedStock;
        _medicineStock = medStock;
        _chicksPurchaseHistory = chicksHistory;
        _monthlyOpExpense = monthlyOpExpense;
        _monthlyKgSold = monthlyKgSold;
        _dataWarnings = dataWarnings;
        _cachedEarnings = null; // ✅ naya data aaya, cache invalidate karo
        _isLoading = false;
      });
    }
  }

  // ✅ Ek sale-date ke liye "pichle mahine ka per-KG operational rate"
  // nikalta hai. Agar pichle mahine ka data hi nahi hai, null return hota
  // hai (calculation se exclude hoga, silently 0 nahi maana jaata).
  double? _prevMonthPerKgRate(DateTime saleDate) {
    final prevKey = _previousMonthKey(saleDate);
    final expense = _monthlyOpExpense[prevKey];
    final kg = _monthlyKgSold[prevKey];
    if (expense == null || kg == null || kg <= 0) return null;
    return expense / kg;
  }

  // ── ✅ Chicks: Company ne jitne mein khareeda, farmer se jitna liya —
  // dono is batch ke liye chicksPurchaseHistory ki allocations se nikalte
  // hain (batchId match karke). Agar koi linked purchase record na mile
  // (purani/manual batch), toh billed amount hi dikhado, aur cost-estimate
  // flag laga do (cost=0 ko hidden fact ki tarah nahi, "estimated" ki
  // tarah treat karo).
  _CatAmount _sumChicksForBatch(String batchId, double fallbackBilled) {
    if (batchId.isEmpty) {
      return _CatAmount(fallbackBilled, 0, costEstimated: true);
    }
    double billed = 0, cost = 0;
    bool found = false;
    for (final purchase in _chicksPurchaseHistory) {
      final double purchaseRate =
          (purchase['effectiveRate'] as num?)?.toDouble() ??
          (purchase['rate'] as num?)?.toDouble() ??
          0;
      final List<dynamic> allocs = _dedupeAllocs(
        (purchase['allocations'] as List?) ?? [],
      );
      for (final a in allocs) {
        final String allocType = (a['type']?.toString() ?? '').toLowerCase();
        if (allocType == 'company' && a['batchId']?.toString() == batchId) {
          final double qty = (a['qty'] as num?)?.toDouble() ?? 0;
          final double rate = (a['rate'] as num?)?.toDouble() ?? 0;
          billed += qty * rate;
          cost += qty * purchaseRate;
          found = true;
        }
      }
    }
    if (!found) return _CatAmount(fallbackBilled, 0, costEstimated: true);
    return _CatAmount(billed, cost);
  }

  // ── ✅ Feed: Company ne jis rate pe khareeda (allocation ke waqt ka
  // snapshot 'costAtAllocation', ya purani entries ke liye current avg —
  // is case mein estimated flag lagta hai) us batch ki allocations ke
  // against, farmer se jitna liya — dono nikalte hain batchId match karke.
  _CatAmount _sumFeedForBatch(String batchId) {
    if (batchId.isEmpty) return const _CatAmount(0, 0);
    double billed = 0, cost = 0;
    bool estimated = false;
    for (final feedType in _feedStock) {
      final double currentAvgCost =
          (feedType['weightedAvgCost'] as num?)?.toDouble() ?? 0;
      final List<dynamic> allocs = _dedupeAllocs(
        (feedType['allocations'] as List?) ?? [],
      );
      for (final a in allocs) {
        if (a['batchId']?.toString() == batchId) {
          final double qty = (a['qty'] as num?)?.toDouble() ?? 0;
          final double rate = (a['rate'] as num?)?.toDouble() ?? 0;
          final bool hasSnapshot = a['costAtAllocation'] != null;
          final double costPerUnit = hasSnapshot
              ? (a['costAtAllocation'] as num).toDouble()
              : currentAvgCost;
          if (!hasSnapshot) estimated = true;
          billed += qty * rate;
          cost += qty * costPerUnit;
        }
      }
    }
    return _CatAmount(billed, cost, costEstimated: estimated);
  }

  // ── ✅ Medicine: Company ne jis rate pe khareeda (allocation ke waqt
  // ka snapshot 'costAtAllocation', ya purani entries ke liye current
  // avg, base unit mein — estimated flag lagta hai), us batch ki
  // allocations ke against, farmer se jitna liya — dono nikalte hain
  // batchId match karke. Agar qtyInBaseUnit missing hai (unit-conversion
  // ambiguous), wo bhi estimated maana jaata hai.
  _CatAmount _sumMedicineForBatch(String batchId) {
    if (batchId.isEmpty) return const _CatAmount(0, 0);
    double billed = 0, cost = 0;
    bool estimated = false;
    for (final med in _medicineStock) {
      final double currentAvgCostPerBase =
          (med['weightedAvgCost'] as num?)?.toDouble() ?? 0;
      final List<dynamic> allocs = _dedupeAllocs(
        (med['allocations'] as List?) ?? [],
      );
      for (final a in allocs) {
        if (a['batchId']?.toString() == batchId) {
          final double qty = (a['qty'] as num?)?.toDouble() ?? 0; // sale unit
          final double rate =
              (a['rate'] as num?)?.toDouble() ?? 0; // per sale unit
          final bool hasBaseQty = a['qtyInBaseUnit'] != null;
          final double qtyBase = hasBaseQty
              ? (a['qtyInBaseUnit'] as num).toDouble()
              : qty;
          final bool hasSnapshot = a['costAtAllocation'] != null;
          final double costPerBase = hasSnapshot
              ? (a['costAtAllocation'] as num).toDouble()
              : currentAvgCostPerBase;
          if (!hasBaseQty || !hasSnapshot) estimated = true;
          billed += qty * rate;
          cost += qtyBase * costPerBase;
        }
      }
    }
    return _CatAmount(billed, cost, costEstimated: estimated);
  }

  // ── Per-Lot Earning Calculate ─────────────────────────────────────────────
  _LotEarning _calculateLotEarning(Map<String, dynamic> batch) {
    final List<dynamic> rawEntries = batch['dailyEntries'] ?? [];
    final int initialChicks = batch['chicksCount'] ?? 0;
    final String batchId = (batch['batchId'] ?? batch['id'] ?? '').toString();

    // ✅ Entries ko date ke hisaab se sort karo (stable — original order
    // tiebreaker ke roop mein rehta hai jab date na mile). Isse:
    //   (a) "latest weight" sahi latest ban jaata hai
    //   (b) Big/Small classification save-order par depend nahi karti
    final List<MapEntry<int, Map<String, dynamic>>> indexed =
        List<MapEntry<int, Map<String, dynamic>>>.generate(
          rawEntries.length,
          (i) => MapEntry(i, Map<String, dynamic>.from(rawEntries[i])),
        );
    indexed.sort((a, b) {
      final DateTime? da = _parseAnyEntryDate(a.value);
      final DateTime? db = _parseAnyEntryDate(b.value);
      if (da != null && db != null) {
        final int cmp = da.compareTo(db);
        if (cmp != 0) return cmp;
      } else if (da != null && db == null) {
        return -1;
      } else if (da == null && db != null) {
        return 1;
      }
      return a.key.compareTo(b.key);
    });
    final List<Map<String, dynamic>> entries = indexed
        .map((e) => e.value)
        .toList();

    double totalWeightSoldKg = 0;
    double totalSaleMoney = 0;
    double latestAvgWeight = 0;
    // ✅ Har sale-event ka apna operational expense share (pichle mahine ke
    // per-KG rate se) accumulate karo
    double operationalExpenseShare = 0;
    bool opExpenseDataMissing = false;

    for (var e in entries) {
      final String type = e['type'].toString().toLowerCase();
      if (type == 'sale') {
        final double saleKg =
            double.tryParse(e['totalWeightSold'].toString()) ?? 0;
        totalWeightSoldKg += saleKg;
        totalSaleMoney += double.tryParse(e['totalMoney'].toString()) ?? 0;
        final double saleWt =
            double.tryParse(e['avgWeightSold'].toString()) ?? 0;
        // ✅ FIX: pehle sirf "agar abhi tak 0 hai" tab set hota tha (yaani
        // effectively FIRST valid weight), ab entries chronological order
        // mein hain isliye hamesha overwrite karke sach mein LATEST weight
        // milta hai.
        if (saleWt > 0) latestAvgWeight = saleWt;

        // ✅ Is sale ki date se pichle mahine ka per-KG rate lagao
        final DateTime? saleDate = _parseSaleDateDdMmYyyy(
          e['date']?.toString(),
        );
        if (saleKg > 0) {
          if (saleDate != null) {
            final double? rate = _prevMonthPerKgRate(saleDate);
            if (rate != null) {
              operationalExpenseShare += saleKg * rate;
            } else {
              opExpenseDataMissing = true; // pichle mahine ka data nahi mila
            }
          } else {
            opExpenseDataMissing = true;
          }
        }
      } else if (type == 'cost') {
        final double wt = double.tryParse(e['weight'].toString()) ?? 0;
        if (wt > 0) latestAvgWeight = wt;
      }
    }

    // TODO(confirm): boundary case — exactly 1.20 kg abhi "Small" maana
    // jaata hai (`> 1.2`). Agar business rule "Big Size >= 1.2 kg" hai, to
    // ye `>=` hona chahiye. Confirm karke fix karunga.
    final bool isBigSize = latestAvgWeight > 1.2;
    // ✅ NEW: koi bhi valid weight (sale ya cost) nahi mila — isliye upar
    // wala isBigSize=false sirf DEFAULT hai, asal weight data nahi hai.
    // TODO(confirm): abhi is case mein bhi Small Size settlement apply ho
    // raha hai (jaisa pehle tha) — flag UI mein dikhta hai taaki chhupa na
    // rahe, lekin calculation-behavior badla nahi hai jab tak confirm na ho.
    final bool weightDataMissing = latestAvgWeight <= 0;

    // FALLBACK — sirf tab use hota hai jab batch mein chicksRate save
    // nahi hui purani entries ke liye.
    final double chicksRateFallback = isBigSize
        ? _r1BigChicksRate
        : _r1SmChicksRate;
    final double adminCost = isBigSize ? _r1BigAdminCost : _r1SmAdminCost;
    final bool medInProd = isBigSize
        ? _r1BigMedicineInProd
        : _r1SmMedicineInProd;
    final double targetCost = isBigSize ? _r1BigTargetCost : _r1SmTargetCost;
    final double baseComm = isBigSize ? _r1BigBaseComm : _r1SmBaseComm;
    final double savingsShare = isBigSize
        ? _r1BigSavingsShare
        : _r1SmSavingsShare;
    final double exceededShare = isBigSize
        ? _r1BigExceededShare
        : _r1SmExceededShare;
    final double rateBonThresh = isBigSize
        ? _r1BigRateBonusThresh
        : _r1SmRateBonusThresh;
    final double rateBonShare = isBigSize
        ? _r1BigRateBonusShare
        : _r1SmRateBonusShare;

    // Batch ka apna stored billed amount (chicks) — settlement formula ke
    // "production cost" calculation ke liye zaroori hai (unchanged logic).
    final double chickBilledFallback =
        double.tryParse(batch['totalChicksCost']?.toString() ?? '') ??
        (initialChicks *
            ((batch['chicksRate'] as num?)?.toDouble() ?? chicksRateFallback));

    // ✅ Teeno category ka billed (farmer se liya) vs cost (company ne
    // khud khareeda) — inhi se company ka ASAL INCOME nikalta hai.
    final _CatAmount chicksAmt = _sumChicksForBatch(
      batchId,
      chickBilledFallback,
    );
    final _CatAmount feedAmt = _sumFeedForBatch(batchId);
    final _CatAmount medAmt = _sumMedicineForBatch(batchId);

    final double chickCostBilled = chicksAmt.billed;
    final double feedCostBilled = feedAmt.billed;
    final double medicineCostBilled = medAmt.billed;
    final double adminIncome = totalWeightSoldKg * adminCost;

    // Production cost (farmer ka hisaab — settlement formula, JAISA THA
    // WAISA HI unchanged, kyunki ye farmer ki commission formula hai)
    double totalProdCost = chickCostBilled + feedCostBilled + adminIncome;
    if (medInProd) totalProdCost += medicineCostBilled;

    final double actualCostPerKg = totalWeightSoldKg > 0
        ? totalProdCost / totalWeightSoldKg
        : 0;
    final double costDiff = targetCost - actualCostPerKg;

    double costAdj = 0;
    if (costDiff > 0) {
      costAdj = costDiff * (savingsShare / 100);
    } else if (costDiff < 0) {
      costAdj = costDiff * (exceededShare / 100);
    }

    final double avgSaleRate = totalWeightSoldKg > 0
        ? totalSaleMoney / totalWeightSoldKg
        : 0;
    final bool rateBonApplied =
        (actualCostPerKg <= targetCost) && (avgSaleRate >= rateBonThresh);
    final double rateBonus = rateBonApplied
        ? (avgSaleRate - rateBonThresh) * (rateBonShare / 100)
        : 0;

    double finalComm = baseComm + costAdj + rateBonus;
    if (finalComm < 0) finalComm = 0;

    double farmerPayout = totalWeightSoldKg * finalComm;
    // TODO(confirm): !medInProd case mein medicine ka farmer-billed amount
    // yahan deduct ho raha hai — verify karo ki ye settlement contract ke
    // hisaab se sahi hai, ya isse double-deduction ho sakta hai agar
    // medicine farmer se alag se bhi recover ho raha ho.
    if (!medInProd) farmerPayout -= medicineCostBilled;
    // TODO(confirm): negative payout ko 0 clamp kiya ja raha hai — agar
    // farmer ka theoretically company ko kuch "owe" karna intended hai
    // (receivable), to ye information yahan discard ho rahi hai.
    if (farmerPayout < 0) farmerPayout = 0;

    // Sale − Farmer Payout (reference figure only). Ye "profit" NAHI hai —
    // asal chicks/feed/medicine kharch/operational expense ismein subtract
    // nahi hua. TRUE profit ke liye `trueTotalProfit` getter dekho (jo real
    // cash flows se banta hai), `dekhaKeProfit` aur `silentIncomeTotal` ke
    // saath.
    final double companyEarning = totalSaleMoney - farmerPayout;

    return _LotEarning(
      batchId: batch['batchId'] ?? batch['id'] ?? '-',
      startDate: batch['startDate'] ?? '-',
      status: batch['status']?.toString().toUpperCase() ?? 'ACTIVE',
      initialChicks: initialChicks,
      totalWeightSoldKg: totalWeightSoldKg,
      totalSaleMoney: totalSaleMoney,
      chicksIncome: chicksAmt.income,
      feedIncome: feedAmt.income,
      medicineIncome: medAmt.income,
      adminIncome: adminIncome,
      medInProd: medInProd,
      farmerPayout: farmerPayout,
      companyEarning: companyEarning,
      isBigSize: isBigSize,
      avgWeight: latestAvgWeight,
      operationalExpenseShare: operationalExpenseShare,
      opExpenseDataMissing: opExpenseDataMissing,
      chicksCostEstimated: chicksAmt.costEstimated,
      feedCostEstimated: feedAmt.costEstimated,
      medicineCostEstimated: medAmt.costEstimated,
      weightDataMissing: weightDataMissing,
      chicksCompanyCost: chicksAmt.cost,
      feedCompanyCost: feedAmt.cost,
      medicineCompanyCost: medAmt.cost,
    );
  }

  /// ✅ Sabhi batches ke earnings, batches list ke order mein, ab cached
  /// (ek hi baar calculate hota hai jab tak naya data load na ho).
  List<_LotEarning> get _allEarnings {
    _cachedEarnings ??= _batches.map(_calculateLotEarning).toList();
    return _cachedEarnings!;
  }

  /// "Abhi jo batch khatam hua" — sabse RECENT COMPLETED batch.
  /// TODO(confirm): Batches list mein append-order ko hi chronological order
  /// maana ja raha hai. Agar kabhi sync/import/manual-edit se order badal
  /// sakta hai, to iske bajaay batch ki asal completedDate/closedDate field
  /// se sort karna zyada reliable hoga — batao agar aisi koi field data mein
  /// available hai.
  _LotEarning? get _mostRecentCompleted {
    final completed = _allEarnings
        .where((e) => e.status == 'COMPLETED' || e.status == 'CLOSED')
        .toList();
    if (completed.isEmpty) return null;
    return completed.last;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${widget.farmer['name'] ?? 'Farmer'} — Report',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryGreen))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_batches.isEmpty) {
      return _buildEmptyState(
        title: 'Koi Batch Data Nahi',
        message: 'Batch create karne ke baad yahan data aayega.',
      );
    }

    final recent = _mostRecentCompleted;
    final earnings = _allEarnings;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ NEW: Data-quality warning banner — silent catches ab yahan
          // dikhte hain, poori tarah chhupte nahi.
          if (_dataWarnings.isNotEmpty) _buildDataWarningBanner(),

          if (recent != null) ...[
            Row(
              children: const [
                Icon(
                  Icons.event_available_rounded,
                  color: primaryGreen,
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  'Abhi Jo Batch Khatam Hua',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            buildLotCard(recent),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.hourglass_empty_rounded,
                    color: Colors.orange.shade300,
                    size: 36,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Abhi Tak Koi Batch Complete Nahi Hua',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Batch khatam hone ke baad yahan uska poora income breakdown dikhega.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // ✅ Sabhi Reports dekhne ka button — alag screen khulti hai
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AllBatchesReportScreen(
                      farmerName: widget.farmer['name']?.toString() ?? 'Farmer',
                      earnings: earnings,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.bar_chart_rounded, size: 20),
              label: Text(
                'Sabhi Reports Dekho (${earnings.length} Lots)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataWarningBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange.shade800,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Data Load Warning',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ..._dataWarnings.map(
            (w) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $w',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({required String title, required String message}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart_rounded,
              size: 60,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ALL BATCHES REPORT SCREEN — "Sabhi Reports Dekho" button se yahan
// aate hain. Yahan abhi tak ke SAARE batches (active + completed) ki list,
// N-lot filter, aur total summary card hoti hai.
//
// TODO(confirm): Active/incomplete batches abhi bhi total summary mein
// include ho rahe hain (settlement/final-payout incomplete ho sakta hai
// unke liye). Agar "Total Net Profit" ko sirf REALIZED/COMPLETED batches
// tak限 karna hai to batao, filter add kar dunga.
// ═══════════════════════════════════════════════════════════════════════════
class AllBatchesReportScreen extends StatefulWidget {
  final String farmerName;
  final List<_LotEarning> earnings;

  const AllBatchesReportScreen({
    super.key,
    required this.farmerName,
    required this.earnings,
  });

  @override
  State<AllBatchesReportScreen> createState() => _AllBatchesReportScreenState();
}

class _AllBatchesReportScreenState extends State<AllBatchesReportScreen> {
  int _lastNBatches = 0; // 0 = Sabhi

  // ✅ FIX: pehle `.take(n)` use ho raha tha jo list ke SHURU ke n (yaani
  // sabse PURANE n batches) utha raha tha. "Last N" ka matlab hona chahiye
  // list ke ANT ke n batches (sabse RECENT n) — ab sublist se end se utha
  // rahe hain.
  List<_LotEarning> get _filtered {
    final all = widget.earnings;
    if (_lastNBatches == 0 || _lastNBatches >= all.length) {
      return all;
    }
    return all.sublist(all.length - _lastNBatches);
  }

  @override
  Widget build(BuildContext context) {
    final earnings = _filtered;

    final double totalSale = earnings.fold(0, (s, e) => s + e.totalSaleMoney);
    final double totalFarmerPayout = earnings.fold(
      0,
      (s, e) => s + e.farmerPayout,
    );
    final double totalBatchProfit = earnings.fold(
      0,
      (s, e) => s + e.trueTotalProfit,
    );
    final double totalAdmin = earnings.fold(0, (s, e) => s + e.adminIncome);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${widget.farmerName} — Sabhi Reports',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
      body: Column(
        children: [
          _buildTopHeader(totalSale, totalBatchProfit),
          Expanded(
            child: widget.earnings.isEmpty
                ? Center(
                    child: Text(
                      'Koi Batch Data Nahi',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: earnings.length + 1,
                    itemBuilder: (context, index) {
                      if (index == earnings.length) {
                        return buildTotalSummaryCard(
                          earnings: earnings,
                          totalSale: totalSale,
                          totalFarmerPayout: totalFarmerPayout,
                          totalBatchProfit: totalBatchProfit,
                          totalAdmin: totalAdmin,
                          lastNBatches: _lastNBatches,
                        );
                      }
                      return buildLotCard(earnings[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopHeader(double totalSale, double totalBatchProfit) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      decoration: const BoxDecoration(
        color: primaryGreen,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              kpiChip(
                'Total Lots',
                '${_filtered.length}',
                Colors.white.withOpacity(0.15),
                emoji: '📦',
              ),
              const SizedBox(width: 8),
              kpiChip(
                'Total Sale',
                '₹${fmt(totalSale)}',
                Colors.white.withOpacity(0.15),
                emoji: '🪙',
              ),
              const SizedBox(width: 8),
              kpiChip(
                'Batch End Bacha',
                '${totalBatchProfit >= 0 ? "+" : ""}₹${fmt(totalBatchProfit)}',
                totalBatchProfit >= 0
                    ? Colors.green.shade700.withOpacity(0.6)
                    : Colors.red.shade700.withOpacity(0.6),
                emoji: '📈',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total income kitne lots ka dekhna hai?',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _nChip(0, 'Sab'),
                      _nChip(2, 'Last 2'),
                      _nChip(3, 'Last 3'),
                      _nChip(5, 'Last 5'),
                      _nChip(10, 'Last 10'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nChip(int n, String label) {
    final bool selected = _lastNBatches == n;
    return GestureDetector(
      onTap: () => setState(() => _lastNBatches = n),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.white : Colors.white38,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? primaryGreen : Colors.white,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS — Dono screens (highlight card + all-reports list) yahi
// functions use karte hain, taaki look-and-feel same rahe.
// ═══════════════════════════════════════════════════════════════════════════

Widget kpiChip(String label, String value, Color bg, {String? emoji}) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          if (emoji != null) ...[
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 15)),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 9),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

// ── Lot Card ──────────────────────────────────────────────────────────────
Widget buildLotCard(_LotEarning e) {
  final bool isCompleted = e.status == 'COMPLETED' || e.status == 'CLOSED';
  final bool hasData = e.totalSaleMoney > 0;

  final Color headerBg = isCompleted
      ? Colors.green.shade50
      : Colors.orange.shade50;
  final Color badgeColor = isCompleted
      ? Colors.green.shade700
      : Colors.orange.shade700;
  final Color iconBg = isCompleted
      ? Colors.green.shade100
      : Colors.orange.shade100;

  return Container(
    margin: const EdgeInsets.only(bottom: 20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isCompleted ? Colors.green.shade200 : Colors.orange.shade200,
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Lot Header ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: headerBg,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  isCompleted ? '🔒' : '🐣',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.batchId,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '${e.initialChicks} birds • ${e.startDate}'
                      '${e.avgWeight > 0 ? " • Avg ${e.avgWeight.toStringAsFixed(2)} kg" : " • ⚠️ Weight data missing"}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isCompleted ? 'COMPLETED' : e.status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── No Data State ─────────────────────────────────────────────
        if (!hasData)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.hourglass_empty_rounded,
                    color: Colors.grey.shade300,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Abhi koi sale nahi hui\nData aane par yahan dikhega',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ),
          )
        else ...[
          // ── Bar Graph ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: buildBarGraph(e),
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // ── Breakdown Table ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: buildBreakdownTable(e),
          ),

          // Detail Information button — Chicks/Feed/Medicine ka alag-alag
          // line/area chart (Company Rate vs Farmer Rate) dikhane wali
          // screen kholta hai.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Builder(
              builder: (context) => SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            BatchDetailInformationScreen(batchId: e.batchId),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.query_stats_rounded,
                    size: 18,
                    color: primaryGreen,
                  ),
                  label: const Text(
                    'Detail Information Dekho',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: primaryGreen,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: primaryGreen),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

// ── Bar Graph ─────────────────────────────────────────────────────────────
Widget buildBarGraph(_LotEarning e) {
  final bars = [
    _BarData('Chicks\nIncome (Silent)', e.chicksIncome, Colors.orange.shade600),
    _BarData('Feed\nIncome (Silent)', e.feedIncome, Colors.blue.shade600),
    _BarData(
      'Medicine\nIncome (Silent)',
      e.medicineIncome,
      Colors.purple.shade600,
    ),
    _BarData(
      'Dekha Ke\nProfit/Loss',
      e.dekhaKeProfit,
      e.dekhaKeProfit >= 0 ? Colors.teal.shade600 : Colors.red.shade600,
    ),
    _BarData(
      'Total Batch\nProfit/Loss',
      e.trueTotalProfit,
      e.trueTotalProfit >= 0 ? primaryGreen : Colors.red.shade600,
    ),
  ];

  final double maxVal = bars.map((b) => b.value.abs()).reduce(math.max);
  if (maxVal <= 0) return const SizedBox.shrink();

  const double maxBarH = 100.0;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'COMPANY INCOME BREAKDOWN',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.black45,
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 140,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: bars.map((bar) {
            final double barH = (bar.value.abs() / maxVal) * maxBarH;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      fmtShort(bar.value),
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        color: bar.value < 0
                            ? Colors.red.shade700
                            : Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Container(
                      height: barH.clamp(4.0, maxBarH),
                      decoration: BoxDecoration(
                        color: bar.color,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bar.label,
                      style: const TextStyle(
                        fontSize: 8,
                        color: Colors.black54,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        runSpacing: 4,
        children: bars
            .map(
              (b) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: b.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    b.label.replaceAll('\n', ' '),
                    style: const TextStyle(fontSize: 9, color: Colors.black54),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    ],
  );
}

// ── Breakdown Table ───────────────────────────────────────────────────────
Widget buildBreakdownTable(_LotEarning e) {
  return Column(
    children: [
      // ── SILENT INCOME — Chicks/Feed/Medicine margin (Farmer se liya −
      // Company ne khareeda). Ye hamesha milta hai, batch achha ho ya
      // kharab.
      Text(
        'SILENT INCOME (Chicks/Feed/Medicine Margin)',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.black45,
          letterSpacing: 0.3,
        ),
      ),
      const SizedBox(height: 10),
      breakRow(
        '🐥',
        Colors.orange.shade600,
        e.chicksIncome >= 0
            ? 'Chicks Se Company Income'
            : 'Chicks Se Company Loss',
        e.chicksIncome,
        hint:
            'Farmer se liya − Company ne khareeda'
            '${e.chicksCostEstimated ? " ⚠️ estimated (purchase record incomplete)" : ""}',
        isIncome: true,
      ),
      const SizedBox(height: 8),
      breakRow(
        '🌾',
        Colors.blue.shade600,
        e.feedIncome >= 0 ? 'Feed Se Company Income' : 'Feed Se Company Loss',
        e.feedIncome,
        hint:
            'Farmer se liya − Company ne khareeda'
            '${e.feedCostEstimated ? " ⚠️ estimated (historical cost snapshot missing)" : ""}',
        isIncome: true,
      ),
      const SizedBox(height: 8),
      breakRow(
        '💊',
        Colors.purple.shade600,
        e.medicineIncome >= 0
            ? 'Medicine Se Company Income'
            : 'Medicine Se Company Loss',
        e.medicineIncome,
        hint:
            'Farmer se liya − Company ne khareeda'
            '${e.medicineCostEstimated ? " ⚠️ estimated (historical cost/unit data incomplete)" : ""}',
        isIncome: true,
      ),
      const SizedBox(height: 10),
      simpleRow(
        'Silent Income Total',
        '${e.silentIncomeTotal >= 0 ? "+" : "-"}₹${fmt(e.silentIncomeTotal.abs())}',
        Colors.black54,
        e.silentIncomeTotal >= 0 ? Colors.teal.shade700 : Colors.red.shade600,
      ),

      const SizedBox(height: 14),
      Divider(color: Colors.grey.shade200, height: 1),
      const SizedBox(height: 12),

      // ── DEKHA KE PROFIT/LOSS — production-cost-vs-target penalty/bonus,
      // medicine deduction, admin-charge ka indirect asar, operational
      // expense — ye sab is EK number mein reconcile ho jaate hain. Isko
      // TRUE Total mein se Silent Income nikaal ke banaya gaya hai, isliye
      // Silent + Dekha Ke kabhi bhi double-count nahi hoga.
      Text(
        'DEKHA KE (Production Cost, Payout, Op. Expense Ka Asar)',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.black45,
          letterSpacing: 0.3,
        ),
      ),
      const SizedBox(height: 10),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: e.dekhaKeProfit >= 0
              ? Colors.teal.shade50
              : Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: e.dekhaKeProfit >= 0
                ? Colors.teal.shade100
                : Colors.red.shade200,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.dekhaKeProfit >= 0 ? 'Dekha Ke Profit' : 'Dekha Ke Loss',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: e.dekhaKeProfit >= 0
                          ? Colors.teal.shade800
                          : Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Cost-Exceeded Penalty/Bonus + Medicine Deduction + Admin Charge ka asar + Operational Expense',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            Text(
              '${e.dekhaKeProfit >= 0 ? "+" : "-"}₹${fmt(e.dekhaKeProfit.abs())}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: e.dekhaKeProfit >= 0
                    ? Colors.teal.shade700
                    : Colors.red.shade600,
              ),
            ),
          ],
        ),
      ),
      if (e.opExpenseDataMissing)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '⚠️ Kuch sale entries ke liye pichle mahine ka expense data nahi mila — un par Operational Expense minus nahi hua.',
            style: TextStyle(fontSize: 10, color: Colors.orange.shade800),
          ),
        ),
      if (e.weightDataMissing)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '⚠️ Is batch ke liye koi valid weight entry nahi mili — Big/Small classification default (Small) le liya gaya hai.',
            style: TextStyle(fontSize: 10, color: Colors.orange.shade800),
          ),
        ),

      const SizedBox(height: 14),
      Divider(color: Colors.grey.shade200, height: 1),
      const SizedBox(height: 12),

      // ── Reference numbers (informational only — inko dobara add nahi
      // karna, ye sirf context ke liye hain, Total Batch Profit mein
      // already reflect ho chuke hain).
      simpleRow(
        'Total Sale Proceeds',
        '₹${fmt(e.totalSaleMoney)}',
        Colors.black54,
        Colors.black87,
      ),
      const SizedBox(height: 6),
      simpleRow(
        'Farmer Ko Diya (Payout)',
        '- ₹${fmt(e.farmerPayout)}',
        Colors.black54,
        Colors.red.shade600,
      ),
      const SizedBox(height: 6),
      simpleRow(
        'Admin Charge (reference — payout mein already asar dikha chuka)',
        '₹${fmt(e.adminIncome)}',
        Colors.black54,
        Colors.black45,
      ),
      const SizedBox(height: 6),
      simpleRow(
        'Operational Expense (Labour+Other)',
        '- ₹${fmt(e.operationalExpenseShare)}',
        Colors.black54,
        Colors.red.shade600,
      ),

      const SizedBox(height: 14),
      Divider(color: Colors.grey.shade200, height: 1),
      const SizedBox(height: 12),

      // ── TOTAL BATCH PROFIT/LOSS — hamesha Silent + Dekha Ke ke barabar
      // hoga (guaranteed by construction), aur sirf REAL cash flows se
      // bana hai — ye single "sach" number hai.
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: e.trueTotalProfit >= 0
              ? primaryGreen.withOpacity(0.07)
              : Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: e.trueTotalProfit >= 0
                ? primaryGreen.withOpacity(0.3)
                : Colors.red.shade200,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.trueTotalProfit >= 0
                        ? '📈 Total Batch Profit'
                        : '📉 Total Batch Loss',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: e.trueTotalProfit >= 0
                          ? primaryGreen
                          : Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Silent Income + Dekha Ke (Sale se sabhi asal kharche minus)',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${e.trueTotalProfit >= 0 ? "+" : "-"}₹${fmt(e.trueTotalProfit.abs())}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: e.trueTotalProfit >= 0
                    ? primaryGreen
                    : Colors.red.shade700,
              ),
            ),
          ],
        ),
      ),
      if (e.costDataEstimated)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '⚠️ Isme Chicks/Feed/Medicine ka kuch cost estimated hai (upar dekho), isliye Total Batch Profit bhi estimate hai, exact nahi.',
            style: TextStyle(fontSize: 10, color: Colors.orange.shade800),
          ),
        ),
    ],
  );
}

Widget breakRow(
  String emoji,
  Color color,
  String label,
  double value, {
  String? hint,
  bool isIncome = false,
}) {
  return Row(
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 17)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
            if (hint != null)
              Text(
                hint,
                style: const TextStyle(fontSize: 10, color: Colors.black45),
              ),
          ],
        ),
      ),
      Text(
        '${value >= 0 ? "+" : "-"}₹${fmt(value.abs())}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: value >= 0 ? Colors.teal.shade700 : Colors.red.shade600,
        ),
      ),
    ],
  );
}

Widget simpleRow(String label, String value, Color labelColor, Color valColor) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Expanded(
        child: Text(label, style: TextStyle(fontSize: 12, color: labelColor)),
      ),
      const SizedBox(width: 8),
      Text(
        value,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: valColor,
        ),
      ),
    ],
  );
}

// ── Total Summary Card ────────────────────────────────────────────────────
Widget buildTotalSummaryCard({
  required List<_LotEarning> earnings,
  required double totalSale,
  required double totalFarmerPayout,
  required double totalBatchProfit,
  required double totalAdmin,
  required int lastNBatches,
}) {
  if (earnings.isEmpty) return const SizedBox.shrink();

  final double totalChicksIncome = earnings.fold(
    0,
    (s, e) => s + e.chicksIncome,
  );
  final double totalFeedIncome = earnings.fold(0, (s, e) => s + e.feedIncome);
  final double totalMedIncome = earnings.fold(
    0,
    (s, e) => s + e.medicineIncome,
  );
  final double totalOpExpense = earnings.fold(
    0.0,
    (s, e) => s + e.operationalExpenseShare,
  );
  final bool anyOpExpenseMissing = earnings.any((e) => e.opExpenseDataMissing);
  final bool anyCostDataEstimated = earnings.any((e) => e.costDataEstimated);

  // ✅ Silent Income Total (Chicks+Feed+Medicine margin) — sabhi lots ka.
  final double totalSilentIncome = earnings.fold(
    0.0,
    (s, e) => s + e.silentIncomeTotal,
  );
  // ✅ Dekha Ke aggregate — True Total − Silent Income (remainder, isliye
  // kabhi double-count nahi hota).
  final double totalDekhaKe = earnings.fold(0.0, (s, e) => s + e.dekhaKeProfit);
  final int n = earnings.length;
  final String nLabel = lastNBatches == 0 ? 'Sabhi $n' : 'Last $n';

  return Container(
    margin: const EdgeInsets.only(top: 4, bottom: 8),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.green.shade200, width: 1.2),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: primaryGreen,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text('📊', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Income Summary — $nLabel Lots',
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        totalRow('Chicks Se Income (Silent)', totalChicksIncome, isGood: true),
        totalRow('Feed Se Income (Silent)', totalFeedIncome, isGood: true),
        totalRow('Medicine Se Income (Silent)', totalMedIncome, isGood: true),
        // ✅ Reference-only row — Admin Charge ka asar already Farmer
        // Payout (isliye Dekha Ke) ke andar hai, isliye ye row total mein
        // dobara add NAHI hota, sirf context ke liye hai.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Admin Charge (₹${fmt(totalAdmin)}) vs Op. Expense (₹${fmt(totalOpExpense)}) — reference',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 10.5),
                ),
              ),
            ],
          ),
        ),
        if (anyOpExpenseMissing)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              '⚠️ Kuch batches mein pichle mahine ka expense data missing tha.',
              style: TextStyle(fontSize: 10, color: Colors.orange.shade800),
            ),
          ),
        if (anyCostDataEstimated)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              '⚠️ Kuch batches mein Chicks/Feed/Medicine ka company-cost estimated hai (exact nahi).',
              style: TextStyle(fontSize: 10, color: Colors.orange.shade800),
            ),
          ),

        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Divider(color: Colors.grey.shade200, height: 1),
        ),

        // ✅ Silent Income Total — sabhi lots ka
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Silent Income Total',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${totalSilentIncome >= 0 ? "+" : "-"}₹${fmt(totalSilentIncome.abs())}',
              style: TextStyle(
                color: totalSilentIncome >= 0
                    ? Colors.teal.shade700
                    : Colors.red.shade700,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // ✅ Dekha Ke aggregate — True Total mein se Silent Income nikaal
        // ke (remainder), isliye Silent+Dekha Ke hamesha True Total ke
        // barabar hoga.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              totalDekhaKe >= 0
                  ? 'Dekha Ke Profit (Total)'
                  : 'Dekha Ke Loss (Total)',
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${totalDekhaKe >= 0 ? "+" : "-"}₹${fmt(totalDekhaKe.abs())}',
              style: TextStyle(
                color: totalDekhaKe >= 0
                    ? Colors.teal.shade700
                    : Colors.red.shade700,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),

        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(color: Colors.grey.shade200, height: 1),
        ),

        const Text(
          'BATCH-WISE INCOME SHARE',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.black45,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Slice size = magnitude (chhota/bada). Loss wale batches ka border LAAL hota hai.',
          style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
        ),

        // Batch-wise pie chart — kis batch se kitna income aaya, tap karke
        // dekho
        _BatchIncomePieChart(earnings: earnings),

        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(color: Colors.grey.shade200, height: 1),
        ),

        totalRow('Total Sale Proceeds', totalSale),
        totalRow(
          'Farmer Ko Diya (Total Payout)',
          totalFarmerPayout,
          isNegative: true,
        ),
        const SizedBox(height: 12),

        // Hero box — Total Batch Profit/Loss, sabhi lots ka combined,
        // guaranteed = Silent Income Total + Dekha Ke (upar dikhaya gaya)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: totalBatchProfit >= 0
                ? primaryGreen.withOpacity(0.07)
                : Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: totalBatchProfit >= 0
                  ? primaryGreen.withOpacity(0.3)
                  : Colors.red.shade200,
              width: 1.2,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      totalBatchProfit >= 0
                          ? '📈 Total Batch Profit'
                          : '📉 Total Batch Loss',
                      style: TextStyle(
                        color: totalBatchProfit >= 0
                            ? primaryGreen
                            : Colors.red.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$nLabel lots ka combined result (Silent Income + Dekha Ke)',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${totalBatchProfit >= 0 ? "+" : "-"}₹${fmt(totalBatchProfit.abs())}',
                style: TextStyle(
                  color: totalBatchProfit >= 0
                      ? primaryGreen
                      : Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),
        ),
        if (anyCostDataEstimated)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '⚠️ Kuch batches ka company-cost estimated hai, isliye Total Batch Profit bhi estimate hai.',
              style: TextStyle(fontSize: 10, color: Colors.orange.shade800),
            ),
          ),

        if (n > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                miniStat('Per Lot Avg', '₹${fmt(totalBatchProfit / n)}'),
                Container(width: 1, height: 28, color: Colors.grey.shade300),
                miniStat('Total Lots', '$n lots'),
                Container(width: 1, height: 28, color: Colors.grey.shade300),
                miniStat('Total Sale', '₹${fmt(totalSale)}'),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

Widget totalRow(
  String label,
  double value, {
  bool isGood = false,
  bool isNegative = false,
  bool isBold = false,
}) {
  Color valColor = Colors.black87;
  String prefix = '';
  if (isGood) {
    valColor = Colors.teal.shade700;
    prefix = '+';
  } else if (isNegative) {
    valColor = Colors.red.shade600;
    prefix = '- ';
  }
  // ✅ FIX: value.abs() use karo taaki agar kabhi already-negative value pass
  // ho jaaye to "- ₹-5K" jaisa double-sign na bane.
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: isBold ? Colors.black87 : Colors.black54,
              fontSize: 12,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$prefix₹${fmt(value.abs())}',
          style: TextStyle(
            color: valColor,
            fontSize: isBold ? 13 : 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

Widget miniStat(String label, String value) {
  return Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: Colors.black45, fontSize: 9)),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// 🥧 BATCH-WISE INCOME PIE CHART — Har batch ka "Batch End Bacha" contribution
// ek slice ke roop mein. Tap karo toh wo slice bada ho jata hai aur batch ID
// + us batch se aaya total rupya niche label mein dikhta hai.
// ✅ NEW: Loss-wale batches (companyEarning < 0) ka slice border ab RED hota
// hai (pehle sabka white border tha aur sirf center-label mein sign dikhta
// tha jab tap karo — is se pie ek nazar mein "sab profit jaisa" lag sakta
// tha).
// ═══════════════════════════════════════════════════════════════════════════
class _BatchIncomePieChart extends StatefulWidget {
  final List<_LotEarning> earnings;
  const _BatchIncomePieChart({required this.earnings});

  @override
  State<_BatchIncomePieChart> createState() => _BatchIncomePieChartState();
}

class _BatchIncomePieChartState extends State<_BatchIncomePieChart> {
  int? _selectedIndex;

  static const List<Color> _sliceColors = [
    Color(0xFFFFB74D), // orange
    Color(0xFF4FC3F7), // blue
    Color(0xFFBA68C8), // purple
    Color(0xFF4DB6AC), // teal
    Color(0xFFF06292), // pink
    Color(0xFFFFD54F), // amber
    Color(0xFF81C784), // green
    Color(0xFF7986CB), // indigo
  ];

  static const double _chartSize = 200;

  List<_LotEarning> get _valid =>
      widget.earnings.where((e) => e.trueTotalProfit != 0).toList();

  void _handleTap(Offset localPosition) {
    final valid = _valid;
    if (valid.isEmpty) return;

    final Offset center = const Offset(_chartSize / 2, _chartSize / 2);
    final Offset vector = localPosition - center;
    final double distance = vector.distance;
    final double outerRadius = _chartSize / 2;
    final double innerRadius = outerRadius * 0.5;

    // Donut ke bahar ya bilkul beech ke khaali hole mein tap kiya toh deselect
    if (distance > outerRadius + 14 || distance < innerRadius - 6) {
      setState(() => _selectedIndex = null);
      return;
    }

    double angle = math.atan2(vector.dy, vector.dx); // -pi..pi, 0 = 3 o'clock
    // Painter -pi/2 (12 o'clock) se start karta hai, isliye angle ko wahi se
    // measure karo taaki tap aur drawing match kare.
    double adjusted = angle + math.pi / 2;
    if (adjusted < 0) adjusted += 2 * math.pi;
    if (adjusted >= 2 * math.pi) adjusted -= 2 * math.pi;

    final double total = valid.fold(0.0, (s, e) => s + e.trueTotalProfit.abs());
    if (total <= 0) return;

    double cumulative = 0;
    for (int i = 0; i < valid.length; i++) {
      final double sweep =
          (valid[i].trueTotalProfit.abs() / total) * 2 * math.pi;
      if (adjusted >= cumulative && adjusted < cumulative + sweep) {
        setState(() {
          _selectedIndex = _selectedIndex == i ? null : i;
        });
        return;
      }
      cumulative += sweep;
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = _valid;
    if (valid.isEmpty) return const SizedBox.shrink();

    final List<Color> colors = List.generate(
      valid.length,
      (i) => _sliceColors[i % _sliceColors.length],
    );
    final List<bool> isNegative = valid
        .map((e) => e.trueTotalProfit < 0)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Center(
          child: GestureDetector(
            onTapUp: (details) => _handleTap(details.localPosition),
            child: SizedBox(
              width: _chartSize,
              height: _chartSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(_chartSize, _chartSize),
                    painter: _PieChartPainter(
                      values: valid
                          .map((e) => e.trueTotalProfit.abs())
                          .toList(),
                      colors: colors,
                      isNegative: isNegative,
                      selectedIndex: _selectedIndex,
                    ),
                  ),
                  // Beech mein selected batch ka info, warna kuch nahi
                  if (_selectedIndex != null)
                    Container(
                      width: _chartSize * 0.42,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            valid[_selectedIndex!].batchId,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${valid[_selectedIndex!].trueTotalProfit >= 0 ? "+" : ""}₹${fmt(valid[_selectedIndex!].trueTotalProfit)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: valid[_selectedIndex!].trueTotalProfit >= 0
                                  ? primaryGreen
                                  : Colors.red.shade600,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // ── Legend — tap karke bhi select ho sakta hai ──
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: List.generate(valid.length, (i) {
            final bool isSelected = _selectedIndex == i;
            final bool neg = isNegative[i];
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() {
                _selectedIndex = _selectedIndex == i ? null : i;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.green.shade50
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: neg
                      ? Border.all(color: Colors.red.shade300, width: 1.2)
                      : (isSelected
                            ? Border.all(color: Colors.green.shade300)
                            : Border.all(color: Colors.grey.shade200)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: colors[i],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${neg ? "− " : ""}${valid[i].batchId}',
                      style: TextStyle(
                        color: neg ? Colors.red.shade700 : Colors.black87,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final List<bool> isNegative;
  final int? selectedIndex;

  _PieChartPainter({
    required this.values,
    required this.colors,
    required this.isNegative,
    required this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double total = values.fold(0.0, (s, v) => s + v);
    if (total <= 0) return;

    final Offset center = Offset(size.width / 2, size.height / 2);
    final double baseRadius = size.width / 2 - 6;
    double startAngle = -math.pi / 2;

    for (int i = 0; i < values.length; i++) {
      final double sweep = (values[i] / total) * 2 * math.pi;
      final bool isSelected = selectedIndex == i;
      final double radius = isSelected ? baseRadius + 10 : baseRadius;

      // Selected slice thoda "explode" hoke bahar nikalta hai
      Offset sliceCenter = center;
      if (isSelected) {
        final double midAngle = startAngle + sweep / 2;
        sliceCenter =
            center + Offset(math.cos(midAngle), math.sin(midAngle)) * 8;
      }

      final Paint fillPaint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.fill;
      final Rect rect = Rect.fromCircle(center: sliceCenter, radius: radius);
      canvas.drawArc(rect, startAngle, sweep, true, fillPaint);

      // ✅ Loss-wale slices ka border red hota hai — profit/loss ek nazar
      // mein pehchana ja sake, sirf color-magnitude se confuse na ho.
      final bool neg = i < isNegative.length && isNegative[i];
      final Paint borderPaint = Paint()
        ..color = neg ? Colors.red.shade400 : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = neg ? 3.2 : 2.5;
      canvas.drawArc(rect, startAngle, sweep, true, borderPaint);

      startAngle += sweep;
    }

    // Donut hole — white card ke background jaisa
    final Paint holePaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, baseRadius * 0.5, holePaint);
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.values != values ||
        oldDelegate.colors != colors ||
        oldDelegate.isNegative != isNegative;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BATCH DETAIL INFORMATION SCREEN — "Detail Information Dekho" button se
// yahan aate hain. Isme Chicks/Feed/Medicine har ek ka alag line/area chart
// hota hai: X-axis = cumulative quantity (0 se total tak), Y-axis = rate (₹).
// Blue line = Company Purchase/Cost Rate, Orange line = Farmer Rate. Jahan
// farmer line company line se upar hoti hai wahan hara (profit) shading,
// jahan neeche hoti hai wahan laal (loss) shading. Har category ke neeche
// uska profit/loss aur sabse neeche total profit/loss.
// ═══════════════════════════════════════════════════════════════════════════

/// Ek allocation "segment" — kisi batch ko di gayi ek chicks/feed/medicine
/// allocation ka qty, company rate (cost) aur farmer rate (billed).
class _AllocSegment {
  final double qty;
  final double companyRate;
  final double farmerRate;
  const _AllocSegment(this.qty, this.companyRate, this.farmerRate);
  double get profit => (farmerRate - companyRate) * qty;
}

class BatchDetailInformationScreen extends StatefulWidget {
  final String batchId;
  const BatchDetailInformationScreen({super.key, required this.batchId});

  @override
  State<BatchDetailInformationScreen> createState() =>
      _BatchDetailInformationScreenState();
}

class _BatchDetailInformationScreenState
    extends State<BatchDetailInformationScreen> {
  bool _isLoading = true;
  List<_AllocSegment> _chicksSegs = [];
  Map<String, List<_AllocSegment>> _feedSegsByType = {};
  Map<String, List<_AllocSegment>> _medSegsByName = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // ── Chicks ────────────────────────────────────────────────────────────
    List<_AllocSegment> chicksSegs = [];
    final String? chicksJson = await CompanyStore.instance.getString(
      'chicksPurchaseHistory',
    );
    if (chicksJson != null) {
      try {
        final List<dynamic> raw = json.decode(chicksJson);
        List<Map<String, dynamic>> matches = [];
        for (final purchase in raw) {
          final double purchaseRate =
              (purchase['effectiveRate'] as num?)?.toDouble() ??
              (purchase['rate'] as num?)?.toDouble() ??
              0;
          final List<dynamic> allocs = _dedupeAllocs(
            (purchase['allocations'] as List?) ?? [],
          );
          for (final a in allocs) {
            final String allocType = (a['type']?.toString() ?? '')
                .toLowerCase();
            if (allocType == 'company' &&
                a['batchId']?.toString() == widget.batchId) {
              matches.add({
                'qty': (a['qty'] as num?)?.toDouble() ?? 0.0,
                'rate': (a['rate'] as num?)?.toDouble() ?? 0.0,
                'purchaseRate': purchaseRate,
                'allocatedOn': a['allocatedOn']?.toString() ?? '',
              });
            }
          }
        }
        matches.sort(
          (a, b) => (a['allocatedOn'] as String).compareTo(
            b['allocatedOn'] as String,
          ),
        );
        for (final m in matches) {
          if ((m['qty'] as double) <= 0) continue;
          chicksSegs.add(
            _AllocSegment(
              m['qty'] as double,
              m['purchaseRate'] as double,
              m['rate'] as double,
            ),
          );
        }
      } catch (e) {
        debugPrint(
          'BatchDetailInformationScreen: chicks history parse failed: $e',
        );
      }
    }

    // ── Feed (per type) ──────────────────────────────────────────────────
    Map<String, List<_AllocSegment>> feedSegs = {};
    try {
      final feedStock = await ensureFeedStockMigrated();
      for (final feedType in feedStock) {
        final String name =
            feedType['name']?.toString() ?? feedType['id']?.toString() ?? '';
        final double currentAvgCost =
            (feedType['weightedAvgCost'] as num?)?.toDouble() ?? 0.0;
        final List<dynamic> allocs = _dedupeAllocs(
          (feedType['allocations'] as List?) ?? [],
        );
        List<Map<String, dynamic>> matches = [];
        for (final a in allocs) {
          if (a['batchId']?.toString() == widget.batchId) {
            matches.add({
              'qty': (a['qty'] as num?)?.toDouble() ?? 0.0,
              'rate': (a['rate'] as num?)?.toDouble() ?? 0.0,
              'costAtAllocation':
                  (a['costAtAllocation'] as num?)?.toDouble() ?? currentAvgCost,
              'allocatedOn': a['allocatedOn']?.toString() ?? '',
            });
          }
        }
        if (matches.isEmpty) continue;
        matches.sort(
          (a, b) => (a['allocatedOn'] as String).compareTo(
            b['allocatedOn'] as String,
          ),
        );
        feedSegs[name] = matches
            .where((m) => (m['qty'] as double) > 0)
            .map(
              (m) => _AllocSegment(
                m['qty'] as double,
                m['costAtAllocation'] as double,
                m['rate'] as double,
              ),
            )
            .toList();
        if (feedSegs[name]!.isEmpty) feedSegs.remove(name);
      }
    } catch (e) {
      debugPrint('BatchDetailInformationScreen: feed stock load failed: $e');
    }

    // ── Medicine (per medicine) ──────────────────────────────────────────
    Map<String, List<_AllocSegment>> medSegs = {};
    final String? medJson = await CompanyStore.instance.getString(
      'medicineStockList',
    );
    if (medJson != null) {
      try {
        final List<dynamic> rawMeds = json.decode(medJson);
        for (final med in rawMeds) {
          final String name = med['name']?.toString() ?? '-';
          final double currentAvgCostPerBase =
              (med['weightedAvgCost'] as num?)?.toDouble() ?? 0.0;
          final List<dynamic> allocs = _dedupeAllocs(
            (med['allocations'] as List?) ?? [],
          );
          List<Map<String, dynamic>> matches = [];
          for (final a in allocs) {
            if (a['batchId']?.toString() == widget.batchId) {
              final double qty = (a['qty'] as num?)?.toDouble() ?? 0.0;
              final double rate = (a['rate'] as num?)?.toDouble() ?? 0.0;
              final double qtyBase =
                  (a['qtyInBaseUnit'] as num?)?.toDouble() ?? qty;
              final double costPerBase =
                  (a['costAtAllocation'] as num?)?.toDouble() ??
                  currentAvgCostPerBase;
              // Cost ko "per sale unit" mein convert karo taaki farmer rate
              // (jo sale unit mein hai) ke saath seedha compare ho sake.
              final double costPerSaleUnit = qty > 0
                  ? (qtyBase * costPerBase) / qty
                  : costPerBase;
              matches.add({
                'qty': qty,
                'rate': rate,
                'costPerUnit': costPerSaleUnit,
                'allocatedOn': a['allocatedOn']?.toString() ?? '',
              });
            }
          }
          if (matches.isEmpty) continue;
          matches.sort(
            (a, b) => (a['allocatedOn'] as String).compareTo(
              b['allocatedOn'] as String,
            ),
          );
          final segs = matches
              .where((m) => (m['qty'] as double) > 0)
              .map(
                (m) => _AllocSegment(
                  m['qty'] as double,
                  m['costPerUnit'] as double,
                  m['rate'] as double,
                ),
              )
              .toList();
          if (segs.isNotEmpty) medSegs[name] = segs;
        }
      } catch (e) {
        debugPrint(
          'BatchDetailInformationScreen: medicine stock parse failed: $e',
        );
      }
    }

    if (mounted) {
      setState(() {
        _chicksSegs = chicksSegs;
        _feedSegsByType = feedSegs;
        _medSegsByName = medSegs;
        _isLoading = false;
      });
    }
  }

  double get _totalProfit {
    double t = 0;
    for (final s in _chicksSegs) {
      t += s.profit;
    }
    for (final list in _feedSegsByType.values) {
      for (final s in list) {
        t += s.profit;
      }
    }
    for (final list in _medSegsByName.values) {
      for (final s in list) {
        t += s.profit;
      }
    }
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final bool hasAnyData =
        _chicksSegs.isNotEmpty ||
        _feedSegsByType.isNotEmpty ||
        _medSegsByName.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${widget.batchId} — Detail Info',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryGreen))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!hasAnyData)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.hourglass_empty_rounded,
                            color: Colors.orange.shade300,
                            size: 32,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Is batch ke liye koi allocation data nahi mila.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_chicksSegs.isNotEmpty) ...[
                    _sectionTitle('🐥 Chicks'),
                    const SizedBox(height: 10),
                    _categoryCard('Chicks', _chicksSegs, unit: 'pcs'),
                    const SizedBox(height: 20),
                  ],

                  if (_feedSegsByType.isNotEmpty) ...[
                    _sectionTitle('🌾 Feed'),
                    const SizedBox(height: 10),
                    ..._feedSegsByType.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _categoryCard(
                          entry.key,
                          entry.value,
                          unit: 'bag',
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],

                  if (_medSegsByName.isNotEmpty) ...[
                    _sectionTitle('💊 Medicine'),
                    const SizedBox(height: 10),
                    ..._medSegsByName.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _categoryCard(
                          entry.key,
                          entry.value,
                          unit: 'unit',
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],

                  if (hasAnyData) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _totalProfit >= 0
                            ? primaryGreen.withOpacity(0.08)
                            : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _totalProfit >= 0
                              ? primaryGreen.withOpacity(0.3)
                              : Colors.red.shade200,
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _totalProfit >= 0
                                ? '📈 Total Profit'
                                : '📉 Total Loss',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: _totalProfit >= 0
                                  ? primaryGreen
                                  : Colors.red.shade700,
                            ),
                          ),
                          Text(
                            '${_totalProfit >= 0 ? "+" : "-"}₹${fmt(_totalProfit.abs())}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: _totalProfit >= 0
                                  ? primaryGreen
                                  : Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String t) => Text(
    t,
    style: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.bold,
      color: Colors.black87,
    ),
  );

  Widget _categoryCard(
    String title,
    List<_AllocSegment> segs, {
    required String unit,
  }) {
    final double totalQty = segs.fold(0.0, (s, e) => s + e.qty);
    final double totalProfit = segs.fold(0.0, (s, e) => s + e.profit);
    final double avgCompanyRate = totalQty > 0
        ? segs.fold(0.0, (s, e) => s + e.qty * e.companyRate) / totalQty
        : 0;
    final double avgFarmerRate = totalQty > 0
        ? segs.fold(0.0, (s, e) => s + e.qty * e.farmerRate) / totalQty
        : 0;
    final double maxRate = math.max(avgCompanyRate, avgFarmerRate) <= 0
        ? 1
        : math.max(avgCompanyRate, avgFarmerRate);
    final bool isProfit = totalProfit >= 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${totalQty == totalQty.roundToDouble() ? totalQty.toStringAsFixed(0) : totalQty.toStringAsFixed(2)} $unit',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Rate Stat Boxes ──
          Row(
            children: [
              Expanded(
                child: _rateStatBox(
                  'Company Rate',
                  avgCompanyRate,
                  unit,
                  Colors.blue.shade600,
                  Colors.blue.shade50,
                  Icons.storefront_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _rateStatBox(
                  'Farmer Rate',
                  avgFarmerRate,
                  unit,
                  Colors.orange.shade700,
                  Colors.orange.shade50,
                  Icons.person_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── Comparison Bars ──
          _rateBarRow('Company', avgCompanyRate, Colors.blue.shade600, maxRate),
          const SizedBox(height: 10),
          _rateBarRow('Farmer', avgFarmerRate, Colors.orange.shade600, maxRate),
          const SizedBox(height: 18),

          // ── Profit / Loss Hero Box ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isProfit
                  ? primaryGreen.withOpacity(0.08)
                  : Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isProfit
                    ? primaryGreen.withOpacity(0.3)
                    : Colors.red.shade200,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      isProfit ? '📈' : '📉',
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isProfit ? 'Profit' : 'Loss',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isProfit ? primaryGreen : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${isProfit ? "+" : "-"}₹${fmt(totalProfit.abs())}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: isProfit ? primaryGreen : Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),

          // ── Multiple allocations breakdown (only if >1) ──
          if (segs.length > 1) ...[
            const SizedBox(height: 14),
            Text(
              '${segs.length} ALLOCATIONS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade500,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            ...segs.asMap().entries.map((entry) {
              final int i = entry.key;
              final _AllocSegment s = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text(
                      '#${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${s.qty == s.qty.roundToDouble() ? s.qty.toStringAsFixed(0) : s.qty.toStringAsFixed(2)} $unit @ ₹${s.companyRate.toStringAsFixed(0)} → ₹${s.farmerRate.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Text(
                      '${s.profit >= 0 ? "+" : "-"}₹${fmt(s.profit.abs())}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: s.profit >= 0
                            ? Colors.teal.shade700
                            : Colors.red.shade600,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _rateStatBox(
    String label,
    double rate,
    String unit,
    Color color,
    Color bgColor,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '₹${rate.toStringAsFixed(rate == rate.roundToDouble() ? 0 : 2)}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            '/ $unit',
            style: TextStyle(fontSize: 10, color: color.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  Widget _rateBarRow(String label, double rate, Color color, double maxRate) {
    final double frac = maxRate > 0 ? (rate / maxRate).clamp(0.0, 1.0) : 0.0;
    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Container(height: 14, color: Colors.grey.shade100),
                FractionallySizedBox(
                  widthFactor: frac,
                  child: Container(height: 14, color: color),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 62,
          child: Text(
            '₹${rate.toStringAsFixed(rate == rate.roundToDouble() ? 0 : 1)}',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Data Models ───────────────────────────────────────────────────────────────
class _LotEarning {
  final String batchId;
  final String startDate;
  final String status;
  final int initialChicks;
  final double totalWeightSoldKg;
  final double totalSaleMoney;
  final double chicksIncome;
  final double feedIncome;
  final double medicineIncome;
  final double adminIncome;
  final bool medInProd;
  final double farmerPayout;
  final double companyEarning;
  final bool isBigSize;
  final double avgWeight;
  // Operational Expense (Labour+Other, pichle mahine ke per-KG rate se)
  final double operationalExpenseShare;
  final bool
  opExpenseDataMissing; // true = kisi sale ke pichle mahine ka data nahi mila

  // ✅ NEW: Data-quality flags — jab company-cost ek real linked purchase
  // record se nahi, balki fallback/estimate se aayi hai.
  final bool chicksCostEstimated;
  final bool feedCostEstimated;
  final bool medicineCostEstimated;
  // ✅ NEW: true = koi bhi valid weight entry nahi mili is batch mein.
  final bool weightDataMissing;

  // ✅ NEW: Company ne ASAL MEIN kitna kharch kiya (billed nahi, cost) —
  // isi se "Total Cash Profit" (neeche) calculate hota hai.
  final double chicksCompanyCost;
  final double feedCompanyCost;
  final double medicineCompanyCost;

  const _LotEarning({
    required this.batchId,
    required this.startDate,
    required this.status,
    required this.initialChicks,
    required this.totalWeightSoldKg,
    required this.totalSaleMoney,
    required this.chicksIncome,
    required this.feedIncome,
    required this.medicineIncome,
    required this.adminIncome,
    required this.medInProd,
    required this.farmerPayout,
    required this.companyEarning,
    required this.isBigSize,
    required this.avgWeight,
    required this.operationalExpenseShare,
    required this.opExpenseDataMissing,
    this.chicksCostEstimated = false,
    this.feedCostEstimated = false,
    this.medicineCostEstimated = false,
    this.weightDataMissing = false,
    this.chicksCompanyCost = 0,
    this.feedCompanyCost = 0,
    this.medicineCompanyCost = 0,
  });

  bool get costDataEstimated =>
      chicksCostEstimated || feedCostEstimated || medicineCostEstimated;

  // ══════════════════════════════════════════════════════════════════════
  // ✅ FINAL PROFIT MODEL — "Silent" + "Dekha Ke" ko is tarah banaya gaya
  // hai ki inka jodna KABHI double-count nahi hota, chahe payout 0 pe
  // clamp ho jaaye, medicine production-cost mein ho ya na ho, kuch bhi ho.
  //
  // Tarika: pehle TRUE total profit sirf REAL cash flows se nikala jaata
  // hai (sale − asal purchase costs − real operational expense − farmer ko
  // asal mein diya gaya payout). Phir "Dekha Ke" ko is TRUE total mein se
  // "Silent Income" ghata ke (remainder ki tarah) nikala jaata hai — is
  // liye Silent + Dekha Ke hamesha True Total ke barabar hi hoga, kyunki
  // Dekha Ke ki definition hi "jo bacha" hai, alag se independently
  // calculate karke jodा nahi gaya.
  // ══════════════════════════════════════════════════════════════════════

  /// Silent Income — Chicks/Feed/Medicine ka margin (Farmer se liya −
  /// Company ne khareeda). Har category alag bhi dikhti hai (chicksIncome
  /// waghera), ye unka jod hai.
  double get silentIncomeTotal => chicksIncome + feedIncome + medicineIncome;

  /// TRUE Total Profit — sirf REAL cash flows se, koi "billed" figure
  /// isme nahi hai:
  ///   Total Sale − (Chicks+Feed+Medicine ka ASAL company kharcha)
  ///              − Operational Expense (Labour+Other, real kharcha)
  ///              − Farmer Ko Asal Mein Diya Gaya Payout
  ///
  /// Admin Charge yahan JAAN-BOOJH KAR nahi hai — uska poora asar already
  /// `farmerPayout` ke andar hai (Admin Charge → Production Cost badhata
  /// hai → cost-exceeded penalty lagti hai → commission/payout kam ho
  /// jaata hai). Dobara jodne se double-count ho jaayega.
  double get trueTotalProfit =>
      totalSaleMoney -
      chicksCompanyCost -
      feedCompanyCost -
      medicineCompanyCost -
      operationalExpenseShare -
      farmerPayout;

  /// Dekha Ke Profit/Loss — True Total mein se Silent Income nikaal ke jo
  /// bacha (production-cost-penalty effect, medicine-deduction effect,
  /// admin-charge ka indirect asar — sab isi ek number mein capture ho
  /// jaate hain, bina dobara gine).
  double get dekhaKeProfit => trueTotalProfit - silentIncomeTotal;
}

class _BarData {
  final String label;
  final double value;
  final Color color;
  const _BarData(this.label, this.value, this.color);
}
