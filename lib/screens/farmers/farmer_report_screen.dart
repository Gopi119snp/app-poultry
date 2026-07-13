import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math' as math;
import '../../services/company_store.dart';

// =============================================================================
// FARMER REPORT SCREEN — ✅ RESTRUCTURED:
// Main screen ab sirf "abhi jo batch khatam hua" (sabse recent COMPLETED
// batch) ka poora income breakdown dikhata hai, + ek button "Sabhi Reports
// Dekho" jo alag screen (AllBatchesReportScreen) kholta hai jisme abhi tak
// ke SAARE batches ki list + total summary hoti hai (jo pehle isi screen
// mein sab ek saath dikhta tha).
// =============================================================================

const Color primaryGreen = Color(0xFF1B5E20);

/// Ek category (Chicks/Feed/Medicine) ka billed (farmer se liya) vs cost
/// (company ne khud khareeda) — dono se income (profit margin) nikalta hai.
class _CatAmount {
  final double billed;
  final double cost;
  const _CatAmount(this.billed, this.cost);
  double get income => billed - cost;
}

// ── Shared Formatters ───────────────────────────────────────────────────────
String fmt(double v) {
  final double abs = v.abs();
  if (abs >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
  if (abs >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  return v.toStringAsFixed(0);
}

String fmtShort(double v) => fmt(v);

class FarmerReportScreen extends StatefulWidget {
  final Map<String, dynamic> farmer;
  const FarmerReportScreen({super.key, required this.farmer});

  @override
  State<FarmerReportScreen> createState() => _FarmerReportScreenState();
}

class _FarmerReportScreenState extends State<FarmerReportScreen>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> _batches = [];
  bool _isLoading = true;

  // ✅ Asal (actual) purchase/allocation data — company ka INCOME nikalne
  // ke liye zaroori hai (billed amount − actual purchase cost).
  List<Map<String, dynamic>> _feedStock = [];
  List<Map<String, dynamic>> _medicineStock = [];
  List<Map<String, dynamic>> _chicksPurchaseHistory = [];

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
      } catch (_) {}
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

    // ✅ Feed stock (per-type allocations, batchId-linked) load karo
    List<Map<String, dynamic>> feedStock = [];
    try {
      feedStock = await CompanyStore.instance.getJsonList('feedStockList');
    } catch (_) {}

    // ✅ Medicine stock (per-medicine allocations, batchId-linked) load karo
    List<Map<String, dynamic>> medStock = [];
    final String? medJson = await CompanyStore.instance.getString(
      'medicineStockList',
    );
    if (medJson != null) {
      try {
        final List<dynamic> raw = json.decode(medJson);
        medStock = raw.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
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
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _batches = allBatches;
        _feedStock = feedStock;
        _medicineStock = medStock;
        _chicksPurchaseHistory = chicksHistory;
        _isLoading = false;
      });
    }
  }

  // ── ✅ Chicks: Company ne jitne mein khareeda, farmer se jitna liya —
  // dono is batch ke liye chicksPurchaseHistory ki allocations se nikalte
  // hain (batchId match karke). Agar koi linked purchase record na mile
  // (purani/manual batch), toh billed amount hi dikhado (cost 0 maan lo,
  // kyunki asal purchase rate pata nahi).
  _CatAmount _sumChicksForBatch(String batchId, double fallbackBilled) {
    if (batchId.isEmpty) return _CatAmount(fallbackBilled, 0);
    double billed = 0, cost = 0;
    bool found = false;
    for (final purchase in _chicksPurchaseHistory) {
      final double purchaseRate =
          (purchase['effectiveRate'] as num?)?.toDouble() ??
          (purchase['rate'] as num?)?.toDouble() ??
          0;
      final List<dynamic> allocs = (purchase['allocations'] as List?) ?? [];
      for (final a in allocs) {
        if (a['type'] == 'Company' && a['batchId']?.toString() == batchId) {
          final double qty = (a['qty'] as num?)?.toDouble() ?? 0;
          final double rate = (a['rate'] as num?)?.toDouble() ?? 0;
          billed += qty * rate;
          cost += qty * purchaseRate;
          found = true;
        }
      }
    }
    if (!found) return _CatAmount(fallbackBilled, 0);
    return _CatAmount(billed, cost);
  }

  // ── ✅ Feed: Company ne jis rate pe khareeda (allocation ke waqt ka
  // snapshot 'costAtAllocation', ya purani entries ke liye current avg)
  // us batch ki allocations ke against, farmer se jitna liya — dono
  // nikalte hain batchId match karke.
  _CatAmount _sumFeedForBatch(String batchId) {
    if (batchId.isEmpty) return const _CatAmount(0, 0);
    double billed = 0, cost = 0;
    for (final feedType in _feedStock) {
      final double currentAvgCost =
          (feedType['weightedAvgCost'] as num?)?.toDouble() ?? 0;
      final List<dynamic> allocs = (feedType['allocations'] as List?) ?? [];
      for (final a in allocs) {
        if (a['batchId']?.toString() == batchId) {
          final double qty = (a['qty'] as num?)?.toDouble() ?? 0;
          final double rate = (a['rate'] as num?)?.toDouble() ?? 0;
          final double costPerUnit =
              (a['costAtAllocation'] as num?)?.toDouble() ?? currentAvgCost;
          billed += qty * rate;
          cost += qty * costPerUnit;
        }
      }
    }
    return _CatAmount(billed, cost);
  }

  // ── ✅ Medicine: Company ne jis rate pe khareeda (allocation ke waqt
  // ka snapshot 'costAtAllocation', ya purani entries ke liye current
  // avg, base unit mein), us batch ki allocations ke against, farmer se
  // jitna liya — dono nikalte hain batchId match karke.
  _CatAmount _sumMedicineForBatch(String batchId) {
    if (batchId.isEmpty) return const _CatAmount(0, 0);
    double billed = 0, cost = 0;
    for (final med in _medicineStock) {
      final double currentAvgCostPerBase =
          (med['weightedAvgCost'] as num?)?.toDouble() ?? 0;
      final List<dynamic> allocs = (med['allocations'] as List?) ?? [];
      for (final a in allocs) {
        if (a['batchId']?.toString() == batchId) {
          final double qty = (a['qty'] as num?)?.toDouble() ?? 0; // sale unit
          final double rate =
              (a['rate'] as num?)?.toDouble() ?? 0; // per sale unit
          final double qtyBase =
              (a['qtyInBaseUnit'] as num?)?.toDouble() ?? qty;
          final double costPerBase =
              (a['costAtAllocation'] as num?)?.toDouble() ??
              currentAvgCostPerBase;
          billed += qty * rate;
          cost += qtyBase * costPerBase;
        }
      }
    }
    return _CatAmount(billed, cost);
  }

  // ── Per-Lot Earning Calculate ─────────────────────────────────────────────
  _LotEarning _calculateLotEarning(Map<String, dynamic> batch) {
    final List<dynamic> entries = batch['dailyEntries'] ?? [];
    final int initialChicks = batch['chicksCount'] ?? 0;
    final String batchId = (batch['batchId'] ?? batch['id'] ?? '').toString();

    double totalWeightSoldKg = 0;
    double totalSaleMoney = 0;
    double latestAvgWeight = 0;

    for (var e in entries) {
      final String type = e['type'].toString().toLowerCase();
      if (type == 'sale') {
        totalWeightSoldKg +=
            double.tryParse(e['totalWeightSold'].toString()) ?? 0;
        totalSaleMoney += double.tryParse(e['totalMoney'].toString()) ?? 0;
        final double saleWt =
            double.tryParse(e['avgWeightSold'].toString()) ?? 0;
        if (saleWt > 0 && latestAvgWeight == 0) latestAvgWeight = saleWt;
      } else if (type == 'cost') {
        final double wt = double.tryParse(e['weight'].toString()) ?? 0;
        if (wt > 0) latestAvgWeight = wt;
      }
    }

    final bool isBigSize = latestAvgWeight > 1.2;

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
    if (!medInProd) farmerPayout -= medicineCostBilled;
    if (farmerPayout < 0) farmerPayout = 0;

    // ✅ Batch End hone ke baad Company ko kitna bacha = Sale − Farmer Payout
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
    );
  }

  /// ✅ Sabhi batches ke earnings, batches list ke order mein (lotNumber
  /// ascending — jaisa batch create hote waqt append hota hai).
  List<_LotEarning> get _allEarnings =>
      _batches.map(_calculateLotEarning).toList();

  /// ✅ NEW: "Abhi jo batch khatam hua" — sabse RECENT COMPLETED batch.
  /// Batches list mein append-order hi chronological order hai (naya
  /// batch hamesha list ke end mein judta hai), isliye COMPLETED batches
  /// mein se LAST wala hi sabse recent completed batch hai.
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

          // ✅ NEW: Sabhi Reports dekhne ka button — alag screen khulti hai
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
// ✅ NEW: ALL BATCHES REPORT SCREEN — "Sabhi Reports Dekho" button se yahan
// aate hain. Yahan abhi tak ke SAARE batches (active + completed) ki list,
// N-lot filter, aur total summary card hoti hai — jo pehle main Report tab
// mein sab ek saath dikhta tha, wo ab yahan hai.
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

  List<_LotEarning> get _filtered {
    if (_lastNBatches == 0 || _lastNBatches >= widget.earnings.length) {
      return widget.earnings;
    }
    return widget.earnings.take(_lastNBatches).toList();
  }

  @override
  Widget build(BuildContext context) {
    final earnings = _filtered;

    final double totalSale = earnings.fold(0, (s, e) => s + e.totalSaleMoney);
    final double totalFarmerPayout = earnings.fold(
      0,
      (s, e) => s + e.farmerPayout,
    );
    final double totalCompanyEarning = earnings.fold(
      0,
      (s, e) => s + e.companyEarning,
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
          _buildTopHeader(totalSale, totalCompanyEarning),
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
                          totalCompanyEarning: totalCompanyEarning,
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

  Widget _buildTopHeader(double totalSale, double totalCompanyEarning) {
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
                '${totalCompanyEarning >= 0 ? "+" : ""}₹${fmt(totalCompanyEarning)}',
                totalCompanyEarning >= 0
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
// ✅ SHARED WIDGETS — Dono screens (highlight card + all-reports list) yahi
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
                      '${e.avgWeight > 0 ? " • Avg ${e.avgWeight.toStringAsFixed(2)} kg" : ""}',
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
        ],
      ],
    ),
  );
}

// ── Bar Graph ─────────────────────────────────────────────────────────────
Widget buildBarGraph(_LotEarning e) {
  final bars = [
    _BarData('Chicks\nIncome', e.chicksIncome, Colors.orange.shade600),
    _BarData('Feed\nIncome', e.feedIncome, Colors.blue.shade600),
    _BarData('Medicine\nIncome', e.medicineIncome, Colors.purple.shade600),
    _BarData('Admin\nIncome', e.adminIncome, Colors.teal.shade600),
    _BarData(
      'Batch End\nBacha',
      e.companyEarning,
      e.companyEarning >= 0 ? primaryGreen : Colors.red.shade600,
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
  final double totalCompanyIncome =
      e.chicksIncome + e.feedIncome + e.medicineIncome + e.adminIncome;

  return Column(
    children: [
      breakRow(
        '🐥',
        Colors.orange.shade600,
        'Chicks Se Company Income',
        e.chicksIncome,
        hint: 'Farmer se liya − Company ne khareeda',
        isIncome: true,
      ),
      const SizedBox(height: 8),
      breakRow(
        '🌾',
        Colors.blue.shade600,
        'Feed Se Company Income',
        e.feedIncome,
        hint: 'Farmer se liya − Company ne khareeda',
        isIncome: true,
      ),
      const SizedBox(height: 8),
      breakRow(
        '💊',
        Colors.purple.shade600,
        'Medicine Se Company Income',
        e.medicineIncome,
        hint: 'Farmer se liya − Company ne khareeda',
        isIncome: true,
      ),
      const SizedBox(height: 8),
      breakRow(
        '🛡️',
        Colors.teal.shade600,
        'Admin Income',
        e.adminIncome,
        hint:
            '${e.totalWeightSoldKg.toStringAsFixed(1)} kg × company admin rate',
        isIncome: true,
      ),
      const SizedBox(height: 12),
      Divider(color: Colors.grey.shade200, height: 1),
      const SizedBox(height: 10),

      simpleRow(
        'Batch Ke Dauraan Total Income',
        '₹${fmt(totalCompanyIncome)}',
        Colors.black54,
        primaryGreen,
      ),

      const SizedBox(height: 12),
      Divider(color: Colors.grey.shade200, height: 1),
      const SizedBox(height: 10),

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
      const SizedBox(height: 12),

      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: e.companyEarning >= 0
              ? primaryGreen.withOpacity(0.07)
              : Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: e.companyEarning >= 0
                ? primaryGreen.withOpacity(0.3)
                : Colors.red.shade200,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.companyEarning >= 0
                      ? '📈 Batch End — Company Ko Bacha'
                      : '📉 Batch End — Company Ko Nuksaan',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: e.companyEarning >= 0
                        ? primaryGreen
                        : Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Farmer Ko Payout Dene Ke Baad (Sale − Payout)',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
            Text(
              '${e.companyEarning >= 0 ? "+" : ""}₹${fmt(e.companyEarning)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: e.companyEarning >= 0
                    ? primaryGreen
                    : Colors.red.shade700,
              ),
            ),
          ],
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
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: TextStyle(fontSize: 12, color: labelColor)),
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
  required double totalCompanyEarning,
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
  final double totalBatchIncome =
      totalChicksIncome + totalFeedIncome + totalMedIncome + totalAdmin;
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

        totalRow('Chicks Se Income', totalChicksIncome, isGood: true),
        totalRow('Feed Se Income', totalFeedIncome, isGood: true),
        totalRow('Medicine Se Income', totalMedIncome, isGood: true),
        totalRow('Admin Income', totalAdmin, isGood: true),

        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Divider(color: Colors.grey.shade200, height: 1),
        ),
        totalRow(
          'Batch Ke Dauraan Total Income',
          totalBatchIncome,
          isGood: true,
          isBold: true,
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

        // ✅ NEW: Batch-wise pie chart — kis batch se kitna income aaya,
        // tap karke dekho
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

        // Hero box — halka green-tinted box, per-lot card jaisa hi look
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: totalCompanyEarning >= 0
                ? primaryGreen.withOpacity(0.07)
                : Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: totalCompanyEarning >= 0
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
                      totalCompanyEarning >= 0
                          ? '📈 Batch End — Company Ka Total Bacha'
                          : '📉 Batch End — Company Ka Total Nuksaan',
                      style: TextStyle(
                        color: totalCompanyEarning >= 0
                            ? primaryGreen
                            : Colors.red.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$nLabel lots ka combined result (Sale − Payout)',
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
                '${totalCompanyEarning >= 0 ? "+" : ""}₹${fmt(totalCompanyEarning)}',
                style: TextStyle(
                  color: totalCompanyEarning >= 0
                      ? primaryGreen
                      : Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
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
                miniStat('Per Lot Avg', '₹${fmt(totalCompanyEarning / n)}'),
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
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isBold ? Colors.black87 : Colors.black54,
            fontSize: 12,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          '$prefix₹${fmt(value)}',
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
      widget.earnings.where((e) => e.companyEarning != 0).toList();

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

    final double total = valid.fold(0.0, (s, e) => s + e.companyEarning.abs());
    if (total <= 0) return;

    double cumulative = 0;
    for (int i = 0; i < valid.length; i++) {
      final double sweep =
          (valid[i].companyEarning.abs() / total) * 2 * math.pi;
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
                      values: valid.map((e) => e.companyEarning.abs()).toList(),
                      colors: colors,
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
                            '${valid[_selectedIndex!].companyEarning >= 0 ? "+" : ""}₹${fmt(valid[_selectedIndex!].companyEarning)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: valid[_selectedIndex!].companyEarning >= 0
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
                  border: isSelected
                      ? Border.all(color: Colors.green.shade300)
                      : Border.all(color: Colors.grey.shade200),
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
                      valid[i].batchId,
                      style: const TextStyle(
                        color: Colors.black87,
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
  final int? selectedIndex;

  _PieChartPainter({
    required this.values,
    required this.colors,
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

      final Paint borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
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
        oldDelegate.colors != colors;
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
  });
}

class _BarData {
  final String label;
  final double value;
  final Color color;
  const _BarData(this.label, this.value, this.color);
}
