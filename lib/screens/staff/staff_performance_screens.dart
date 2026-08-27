import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:get/get.dart';
import '../../services/company_store.dart';
import 'staff_performance_engine.dart';
import 'staff_performance_benchmark_screen.dart';

const Color _spGreen = Color(0xFF1B5E20);

// ═══════════════════════════════════════════════════════════════════════════
// 🎚️ BATCH SCOPE SELECTOR — Owner yahi decide karta hai ki report kis data
// par based ho (Current batch / All batches / Last N batches)
// ═══════════════════════════════════════════════════════════════════════════
class _ScopeSelector extends StatefulWidget {
  final BatchScope scope;
  final int lastN;
  final ValueChanged<BatchScope> onScopeChanged;
  final ValueChanged<int> onLastNChanged;

  const _ScopeSelector({
    required this.scope,
    required this.lastN,
    required this.onScopeChanged,
    required this.onLastNChanged,
  });

  @override
  State<_ScopeSelector> createState() => _ScopeSelectorState();
}

class _ScopeSelectorState extends State<_ScopeSelector> {
  late final TextEditingController _nCtrl;

  @override
  void initState() {
    super.initState();
    _nCtrl = TextEditingController(text: widget.lastN.toString());
  }

  @override
  void dispose() {
    _nCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📅 Data Kis Par Based Ho?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('Current Batch', BatchScope.current),
              _chip('Sabhi Batches', BatchScope.all),
              _chip('Last N Batches', BatchScope.lastN),
            ],
          ),
          // ✅ FIX — fixed chips (1/2/3/5) hata ke Owner khud number type
          // kar sake, jitna bhi bada N chahiye ho
          if (widget.scope == BatchScope.lastN) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Text(
                  'Kitne Last Batches?',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 90,
                  height: 38,
                  child: TextField(
                    controller: _nCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      hintText: 'e.g. 7',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onSubmitted: (v) => _applyN(v),
                    onChanged: (v) => _applyN(v),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _applyN(String v) {
    final n = int.tryParse(v.trim());
    if (n != null && n > 0) {
      widget.onLastNChanged(n);
    }
  }

  Widget _chip(String label, BatchScope value) {
    final bool sel = widget.scope == value;
    return GestureDetector(
      onTap: () => widget.onScopeChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? _spGreen : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: sel ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🏆 STAFF RANKING MODEL — efficiency (profit ÷ total chicks handled) se
// rank hota hai, sirf absolute profit se NAHI. Isse chhote scale wala lekin
// zyada efficient staff bhi sahi tarike se upar aata hai.
// ═══════════════════════════════════════════════════════════════════════════
class _StaffRanking {
  final Map<String, dynamic> employee;
  final int farmerCount;
  final int goodCount;
  final int avgCount;
  final int poorCount;
  final int totalChicks;
  final double totalProfit;
  final double? profitPerChick; // null = chicks data hi nahi (rank nahi milegi)
  final List<PerformanceTrendAlert> trendAlerts; // ✅ NEW

  const _StaffRanking({
    required this.employee,
    required this.farmerCount,
    required this.goodCount,
    required this.avgCount,
    required this.poorCount,
    required this.totalChicks,
    required this.totalProfit,
    required this.profitPerChick,
    required this.trendAlerts,
  });
}

String _medalFor(int rank) {
  switch (rank) {
    case 1:
      return '🥇';
    case 2:
      return '🥈';
    case 3:
      return '🥉';
    default:
      return '#$rank';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 1️⃣ STAFF PERFORMANCE OVERVIEW — har staff ka apna alag graph +
// efficiency-based ranking (medal emoji ke saath)
// ═══════════════════════════════════════════════════════════════════════════
class StaffPerformanceOverviewScreen extends StatefulWidget {
  const StaffPerformanceOverviewScreen({super.key});

  @override
  State<StaffPerformanceOverviewScreen> createState() =>
      _StaffPerformanceOverviewScreenState();
}

class _StaffPerformanceOverviewScreenState
    extends State<StaffPerformanceOverviewScreen> {
  bool _isLoading = true;
  BatchScope _scope = BatchScope.current;
  int _lastN = 1;

  List<_StaffRanking> _rankings = [];
  final TextEditingController _searchCtrl = TextEditingController(); // ✅ NEW

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() {})); // ✅ NEW
  }

  @override
  void dispose() {
    _searchCtrl.dispose(); // ✅ NEW
    super.dispose();
  }

  // ✅ NEW — naam se search karo, lekin RANK (medal) original ranking se hi
  // aani chahiye, filter karne se rank badalni nahi chahiye
  List<MapEntry<int, _StaffRanking>> get _filteredRankings {
    final query = _searchCtrl.text.trim().toLowerCase();
    final indexed = _rankings
        .asMap()
        .entries
        .toList(); // 0-based index = rank-1
    if (query.isEmpty) return indexed;
    return indexed.where((e) {
      final name = (e.value.employee['name']?.toString() ?? '').toLowerCase();
      return name.contains(query);
    }).toList();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final office = await CompanyStore.instance.getJsonList('officeManagers');
    final field = await CompanyStore.instance.getJsonList('fieldManagers');
    final allFarmers = await CompanyStore.instance.getJsonList(
      'companyFarmers',
    );
    final benchmark = await loadStaffPerformanceBenchmark();

    final staffList = [...office, ...field];
    final List<_StaffRanking> rankings = [];

    for (final emp in staffList) {
      final empId = emp['id']?.toString() ?? '';
      final farmers = farmersUnderEmployee(allFarmers, empId);
      if (farmers.isEmpty) continue;

      final summaries = await computeFarmerBatchSummaries(
        farmers: farmers,
        scope: _scope,
        lastN: _lastN,
      );
      final profits = await computeEmployeeFarmersProfit(
        farmers: farmers,
        scope: _scope,
        lastN: _lastN,
      );

      int good = 0, avg = 0, poor = 0;
      int totalChicks = 0;
      final List<PerformanceTrendAlert> trendAlerts = []; // ✅ NEW
      for (final s in summaries) {
        totalChicks += s.initialChicks;
        switch (s.overallRating(benchmark)) {
          case PerformanceRating.good:
            good++;
            break;
          case PerformanceRating.average:
            avg++;
            break;
          case PerformanceRating.poor:
            poor++;
            break;
        }
        final alert = s.trendAlert(benchmark); // ✅ NEW
        if (alert != null) trendAlerts.add(alert);
      }
      final totalProfit = profits.fold(0.0, (s, p) => s + p.trueTotalProfit);
      final profitPerChick = totalChicks > 0 ? totalProfit / totalChicks : null;

      rankings.add(
        _StaffRanking(
          employee: emp,
          farmerCount: farmers.length,
          goodCount: good,
          avgCount: avg,
          poorCount: poor,
          totalChicks: totalChicks,
          totalProfit: totalProfit,
          profitPerChick: profitPerChick,
          trendAlerts: trendAlerts,
        ),
      );
    }

    // ✅ Efficiency (profit ÷ chicks) se sort — sirf absolute profit se nahi.
    // Jinke paas chicks-data hi nahi hai wo sabse neeche chale jaate hain.
    rankings.sort((a, b) {
      if (a.profitPerChick == null && b.profitPerChick == null) return 0;
      if (a.profitPerChick == null) return 1;
      if (b.profitPerChick == null) return -1;
      return b.profitPerChick!.compareTo(a.profitPerChick!);
    });

    if (!mounted) return;
    setState(() {
      _rankings = rankings;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _spGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: const Text(
          '👥 Staff Performance',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: Colors.white),
            tooltip: 'Benchmark Settings',
            onPressed: () =>
                Get.to(() => const StaffPerformanceBenchmarkScreen()),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _spGreen))
          : RefreshIndicator(
              onRefresh: _load,
              color: _spGreen,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _ScopeSelector(
                    scope: _scope,
                    lastN: _lastN,
                    onScopeChanged: (s) {
                      setState(() => _scope = s);
                      _load();
                    },
                    onLastNChanged: (n) {
                      setState(() => _lastN = n);
                      _load();
                    },
                  ),
                  if (_rankings.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          'Kisi bhi staff ke under allocated farmer ka data nahi mila.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ),
                    )
                  else ...[
                    // ✅ NEW — staff naam se search
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Staff naam se search karein...',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                  onPressed: () => _searchCtrl.clear(),
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        '🏆 Staff Ranking (Profit per Chick ke hisaab se)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Sirf total profit se nahi — kitne chicks manage kiye, unke hisaab se '
                        'profit ka % dekh ke rank hoti hai, taaki chhota lekin efficient staff '
                        'bhi sahi credit paaye.',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                    ),
                    if (_filteredRankings.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(
                            'Is naam ka koi staff nahi mila.',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ),
                      )
                    else
                      ..._filteredRankings.map(
                        (e) => _staffCard(context, e.value, e.key + 1),
                      ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _staffCard(BuildContext context, _StaffRanking r, int rank) {
    final emp = r.employee;
    final role = emp['role']?.toString() ?? '';
    final total = r.goodCount + r.avgCount + r.poorCount;

    return GestureDetector(
      onTap: () => Get.to(
        () => StaffPerformanceDetailScreen(
          employee: emp,
          scope: _scope,
          lastN: _lastN,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
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
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rank <= 3
                        ? Colors.amber.shade50
                        : Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _medalFor(rank),
                    style: TextStyle(
                      fontSize: rank <= 3 ? 20 : 13,
                      fontWeight: FontWeight.bold,
                      color: rank <= 3 ? null : Colors.grey.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        emp['name']?.toString() ?? '-',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                        ),
                      ),
                      Text(
                        '$role • ${r.farmerCount} farmers • ${r.totalChicks} chicks',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
              ],
            ),

            // ✅ NEW — Decline trend warning (jab koi farmer badiya se
            // kharab ki taraf gir raha ho, sirf "abhi kharab hai" nahi)
            if (r.trendAlerts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color:
                      r.trendAlerts.any(
                        (a) => a.severity == TrendSeverity.danger,
                      )
                      ? Colors.red.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        r.trendAlerts.any(
                          (a) => a.severity == TrendSeverity.danger,
                        )
                        ? Colors.red.shade200
                        : Colors.orange.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.trending_down_rounded,
                      size: 15,
                      color:
                          r.trendAlerts.any(
                            (a) => a.severity == TrendSeverity.danger,
                          )
                          ? Colors.red.shade700
                          : Colors.orange.shade800,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${r.trendAlerts.length} farmer ka performance girta ja raha hai — tap karke dekho',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color:
                              r.trendAlerts.any(
                                (a) => a.severity == TrendSeverity.danger,
                              )
                              ? Colors.red.shade800
                              : Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),

            // ── Good/Avg/Poor mini stacked-bar graph (isi staff ka apna) ──
            if (total > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 16,
                  child: Row(
                    children: [
                      if (r.goodCount > 0)
                        Expanded(
                          flex: r.goodCount,
                          child: Container(color: Colors.green.shade500),
                        ),
                      if (r.avgCount > 0)
                        Expanded(
                          flex: r.avgCount,
                          child: Container(color: Colors.amber.shade500),
                        ),
                      if (r.poorCount > 0)
                        Expanded(
                          flex: r.poorCount,
                          child: Container(color: Colors.red.shade400),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                children: [
                  Text(
                    '🟢 ${r.goodCount} Achha',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.green.shade700,
                    ),
                  ),
                  Text(
                    '🟡 ${r.avgCount} Average',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.amber.shade800,
                    ),
                  ),
                  Text(
                    '🔴 ${r.poorCount} Kharab',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ] else
              Text(
                'Is scope ke liye koi performance data nahi mila.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),

            const SizedBox(height: 14),
            Divider(color: Colors.grey.shade200, height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Company Profit/Loss',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      '${r.totalProfit >= 0 ? "+" : "-"}₹${r.totalProfit.abs().toStringAsFixed(0)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: r.totalProfit >= 0
                            ? _spGreen
                            : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Profit / Chick (Efficiency)',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      r.profitPerChick != null
                          ? '₹${r.profitPerChick!.toStringAsFixed(2)}'
                          : 'N/A',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: (r.profitPerChick ?? 0) >= 0
                            ? _spGreen
                            : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 2️⃣ STAFF LIST — jin staff ko farmers allocate hue hain unki list
// ═══════════════════════════════════════════════════════════════════════════
class StaffPerformanceListScreen extends StatefulWidget {
  final BatchScope scope;
  final int lastN;
  const StaffPerformanceListScreen({
    super.key,
    required this.scope,
    required this.lastN,
  });

  @override
  State<StaffPerformanceListScreen> createState() =>
      _StaffPerformanceListScreenState();
}

class _StaffPerformanceListScreenState
    extends State<StaffPerformanceListScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _farmers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final office = await CompanyStore.instance.getJsonList('officeManagers');
    final field = await CompanyStore.instance.getJsonList('fieldManagers');
    final farmers = await CompanyStore.instance.getJsonList('companyFarmers');

    final combined = [...office, ...field].where((emp) {
      return farmersUnderEmployee(
        farmers,
        emp['id']?.toString() ?? '',
      ).isNotEmpty;
    }).toList();

    if (!mounted) return;
    setState(() {
      _staff = combined;
      _farmers = farmers;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _spGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: const Text(
          'Staff Select Karein',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _spGreen))
          : _staff.isEmpty
          ? Center(
              child: Text(
                'Kisi bhi staff ke under farmer allocate nahi hain.',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _staff.length,
              itemBuilder: (context, index) {
                final emp = _staff[index];
                final role = emp['role']?.toString() ?? '';
                final roleColor = role == 'Office Manager'
                    ? Colors.blue.shade700
                    : Colors.orange.shade700;
                final count = farmersUnderEmployee(
                  _farmers,
                  emp['id']?.toString() ?? '',
                ).length;

                return GestureDetector(
                  onTap: () => Get.to(
                    () => StaffPerformanceDetailScreen(
                      employee: emp,
                      scope: widget.scope,
                      lastN: widget.lastN,
                    ),
                  ),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: roleColor.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              (emp['name']?.toString().isNotEmpty == true
                                  ? emp['name'].toString()[0].toUpperCase()
                                  : '?'),
                              style: TextStyle(
                                color: roleColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                emp['name']?.toString() ?? '-',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$role • $count farmers',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 3️⃣ STAFF DETAIL — combined farmer performance + company profit/loss
// ═══════════════════════════════════════════════════════════════════════════
class StaffPerformanceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> employee;
  final BatchScope scope;
  final int lastN;
  const StaffPerformanceDetailScreen({
    super.key,
    required this.employee,
    required this.scope,
    required this.lastN,
  });

  @override
  State<StaffPerformanceDetailScreen> createState() =>
      _StaffPerformanceDetailScreenState();
}

class _StaffPerformanceDetailScreenState
    extends State<StaffPerformanceDetailScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _farmers = [];
  List<FarmerBatchSummary> _summaries = [];
  List<EmployeeFarmerProfit> _profits = [];
  StaffPerformanceBenchmark _benchmark = const StaffPerformanceBenchmark();
  CompanyAverageMetrics _companyAvg = const CompanyAverageMetrics(
    avgFcr: 0,
    avgMortalityPct: 0,
    avgWeightGrowthPct: 0,
    sampleCount: 0,
  ); // ✅ NEW

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final allFarmers = await CompanyStore.instance.getJsonList(
      'companyFarmers',
    );
    final farmers = farmersUnderEmployee(
      allFarmers,
      widget.employee['id']?.toString() ?? '',
    );
    final summaries = await computeFarmerBatchSummaries(
      farmers: farmers,
      scope: widget.scope,
      lastN: widget.lastN,
    );
    final profits = await computeEmployeeFarmersProfit(
      farmers: farmers,
      scope: widget.scope,
      lastN: widget.lastN,
    );
    final benchmark = await loadStaffPerformanceBenchmark();
    final companyAvg = await computeCompanyAverageMetrics(
      scope: widget.scope,
      lastN: widget.lastN,
    ); // ✅ NEW

    if (!mounted) return;
    setState(() {
      _farmers = farmers;
      _summaries = summaries;
      _profits = profits;
      _benchmark = benchmark;
      _companyAvg = companyAvg; // ✅ NEW
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final good = _summaries
        .where((s) => s.overallRating(_benchmark) == PerformanceRating.good)
        .toList();
    final avg = _summaries
        .where((s) => s.overallRating(_benchmark) == PerformanceRating.average)
        .toList();
    final poor = _summaries
        .where((s) => s.overallRating(_benchmark) == PerformanceRating.poor)
        .toList();

    final double totalProfit = _profits.fold(
      0.0,
      (s, p) => s + p.trueTotalProfit,
    );

    // ✅ NEW — decline-trend alerts (danger pehle, phir caution)
    final List<PerformanceTrendAlert> trendAlerts =
        _summaries
            .map((s) => s.trendAlert(_benchmark))
            .whereType<PerformanceTrendAlert>()
            .toList()
          ..sort(
            (a, b) => a.severity == b.severity
                ? 0
                : (a.severity == TrendSeverity.danger ? -1 : 1),
          );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _spGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          widget.employee['name']?.toString() ?? 'Staff',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _spGreen))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ✅ NEW — "Dhyan Do" section, sirf jab koi farmer decline
                // ho raha ho (danger = laal, caution = orange)
                if (trendAlerts.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            trendAlerts.any(
                              (a) => a.severity == TrendSeverity.danger,
                            )
                            ? Colors.red.shade200
                            : Colors.orange.shade200,
                        width: 1.4,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '⚠️ Dhyan Do — Performance Girta Ja Raha Hai',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...trendAlerts.map((a) {
                          final bool danger =
                              a.severity == TrendSeverity.danger;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: danger
                                  ? Colors.red.shade50
                                  : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  danger
                                      ? Icons.error_rounded
                                      : Icons.trending_down_rounded,
                                  size: 16,
                                  color: danger
                                      ? Colors.red.shade700
                                      : Colors.orange.shade800,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    a.message,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      height: 1.4,
                                      color: danger
                                          ? Colors.red.shade900
                                          : Colors.orange.shade900,
                                      fontWeight: danger
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🐔 Farmer Performance',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _countCard(
                              '🟢 Achha',
                              good.length,
                              Colors.green,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _countCard(
                              '🟡 Average',
                              avg.length,
                              Colors.amber,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _countCard(
                              '🔴 Kharab',
                              poor.length,
                              Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (good.isNotEmpty)
                        _farmerNameList(
                          '🟢 Achha Performance',
                          good,
                          Colors.green,
                        ),
                      if (avg.isNotEmpty)
                        _farmerNameList(
                          '🟡 Average Performance',
                          avg,
                          Colors.amber,
                        ),
                      if (poor.isNotEmpty)
                        _farmerNameList(
                          '🔴 Kharab Performance',
                          poor,
                          Colors.red,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _companyAverageCard(),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '💰 Company Profit/Loss (is staff ke farmers se)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        totalProfit >= 0
                            ? '📈 Total Profit: ₹${totalProfit.toStringAsFixed(0)}'
                            : '📉 Total Loss: ₹${totalProfit.abs().toStringAsFixed(0)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: totalProfit >= 0
                              ? _spGreen
                              : Colors.red.shade700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_profits.isEmpty)
                        Text(
                          'Abhi is staff ke farmers ki koi sale/profit data nahi mila.',
                          style: TextStyle(color: Colors.grey.shade500),
                        )
                      else
                        SizedBox(
                          height: 160,
                          child: BarChart(
                            BarChartData(
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
                                    reservedSize: 40,
                                    getTitlesWidget: (v, m) {
                                      final idx = v.toInt();
                                      if (idx < 0 || idx >= _profits.length) {
                                        return const SizedBox.shrink();
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Transform.rotate(
                                          angle: -0.4,
                                          child: Text(
                                            _profits[idx].farmerName,
                                            style: const TextStyle(fontSize: 8),
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
                                    final p = _profits[g.x.toInt()];
                                    return BarTooltipItem(
                                      '${p.farmerName}\n₹${p.trueTotalProfit.toStringAsFixed(0)}',
                                      const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              barGroups: List.generate(_profits.length, (i) {
                                final v = _profits[i].trueTotalProfit;
                                return BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(
                                      toY: v,
                                      color: v >= 0
                                          ? Colors.green.shade500
                                          : Colors.red.shade400,
                                      width: 14,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ],
                                );
                              }),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Get.to(
                      () => FarmerListUnderStaffScreen(
                        employee: widget.employee,
                        scope: widget.scope,
                        lastN: widget.lastN,
                      ),
                    ),
                    icon: const Icon(
                      Icons.people_alt_rounded,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Har Farmer Ki Report Dekhein',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _spGreen,
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

  // ✅ NEW — Staff ka apna average vs Company-wide average, color-coded
  // (green = company average se behtar, red = kharab)
  Widget _companyAverageCard() {
    if (_summaries.isEmpty) return const SizedBox.shrink();

    final double staffFcr =
        _summaries.fold(0.0, (s, e) => s + e.finalFcr) / _summaries.length;
    final double staffMortality =
        _summaries.fold(0.0, (s, e) => s + e.finalMortalityPct) /
        _summaries.length;
    final double staffWeightGrowth =
        _summaries.fold(0.0, (s, e) => s + e.finalWeightGrowthPct) /
        _summaries.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📊 Is Staff Ka Average vs Company Average',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
          ),
          const SizedBox(height: 2),
          Text(
            'Company average ${_companyAvg.sampleCount} farmer-batches se bana hai',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 14),
          _compareRow(
            'FCR',
            staffFcr,
            _companyAvg.avgFcr,
            lowerIsBetter: true,
            fmt: (v) => v.toStringAsFixed(2),
          ),
          const SizedBox(height: 10),
          _compareRow(
            'Mortality %',
            staffMortality,
            _companyAvg.avgMortalityPct,
            lowerIsBetter: true,
            fmt: (v) => '${v.toStringAsFixed(1)}%',
          ),
          const SizedBox(height: 10),
          _compareRow(
            'Weight Growth %',
            staffWeightGrowth,
            _companyAvg.avgWeightGrowthPct,
            lowerIsBetter: false,
            fmt: (v) => '${v.toStringAsFixed(1)}%',
          ),
        ],
      ),
    );
  }

  Widget _compareRow(
    String label,
    double staffValue,
    double companyAvgValue, {
    required bool lowerIsBetter,
    required String Function(double) fmt,
  }) {
    final double diff = staffValue - companyAvgValue;
    // lowerIsBetter=true (FCR/Mortality): diff<0 matlab staff behtar hai
    // lowerIsBetter=false (Weight Growth): diff>0 matlab staff behtar hai
    final bool isBetter = lowerIsBetter ? diff < 0 : diff > 0;
    final bool isSame = diff.abs() < 0.005;
    final Color color = isSame
        ? Colors.grey.shade600
        : (isBetter ? Colors.green.shade700 : Colors.red.shade700);
    final String arrow = isSame ? '≈' : (isBetter ? '✅' : '⚠️');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Text(
                fmt(staffValue),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$arrow Company Avg: ${fmt(companyAvgValue)}',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _countCard(String label, int count, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color.shade800,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10.5, color: color.shade700)),
        ],
      ),
    );
  }

  Widget _farmerNameList(
    String title,
    List<FarmerBatchSummary> list,
    MaterialColor color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: color.shade800,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: list
                .map(
                  (s) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: color.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.shade200),
                    ),
                    child: Text(
                      s.farmerName,
                      style: TextStyle(
                        fontSize: 11,
                        color: color.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 4️⃣ FARMER LIST UNDER STAFF
// ═══════════════════════════════════════════════════════════════════════════
class FarmerListUnderStaffScreen extends StatefulWidget {
  final Map<String, dynamic> employee;
  final BatchScope scope;
  final int lastN;
  const FarmerListUnderStaffScreen({
    super.key,
    required this.employee,
    required this.scope,
    required this.lastN,
  });

  @override
  State<FarmerListUnderStaffScreen> createState() =>
      _FarmerListUnderStaffScreenState();
}

class _FarmerListUnderStaffScreenState
    extends State<FarmerListUnderStaffScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _farmers = [];
  Map<String, FarmerBatchSummary> _latestSummaryByFarmerId = {};
  StaffPerformanceBenchmark _benchmark = const StaffPerformanceBenchmark();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final allFarmers = await CompanyStore.instance.getJsonList(
      'companyFarmers',
    );
    final farmers = farmersUnderEmployee(
      allFarmers,
      widget.employee['id']?.toString() ?? '',
    );
    final summaries = await computeFarmerBatchSummaries(
      farmers: farmers,
      scope: widget.scope,
      lastN: widget.lastN,
    );
    final benchmark = await loadStaffPerformanceBenchmark();

    final Map<String, FarmerBatchSummary> latest = {};
    for (final s in summaries) {
      latest[s.farmerId] = s;
    }

    if (!mounted) return;
    setState(() {
      _farmers = farmers;
      _latestSummaryByFarmerId = latest;
      _benchmark = benchmark;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _spGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          '${widget.employee['name']} — Farmers',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _spGreen))
          : _farmers.isEmpty
          ? Center(
              child: Text(
                'Is staff ke under koi farmer allocate nahi hai.',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _farmers.length,
              itemBuilder: (context, index) {
                final farmer = _farmers[index];
                final summary =
                    _latestSummaryByFarmerId[farmer['id']?.toString()];
                final rating = summary?.overallRating(_benchmark);

                return GestureDetector(
                  onTap: () => Get.to(
                    () => FarmerPerformanceDetailScreen(
                      farmer: farmer,
                      scope: widget.scope,
                      lastN: widget.lastN,
                    ),
                  ),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                farmer['name']?.toString() ?? '-',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              if (summary != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'FCR ${summary.finalFcr.toStringAsFixed(2)} • '
                                  'Mortality ${summary.finalMortalityPct.toStringAsFixed(1)}% • '
                                  'Weight ${summary.finalWeightGrowthPct.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ] else
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Data nahi mila',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (rating != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: ratingColor(rating).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              ratingLabel(rating),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: ratingColor(rating),
                              ),
                            ),
                          ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 5️⃣ FARMER PERFORMANCE DETAIL — daily graphs: Mortality, FCR, Weight Growth
// ═══════════════════════════════════════════════════════════════════════════
class FarmerPerformanceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> farmer;
  final BatchScope scope;
  final int lastN;
  const FarmerPerformanceDetailScreen({
    super.key,
    required this.farmer,
    required this.scope,
    required this.lastN,
  });

  @override
  State<FarmerPerformanceDetailScreen> createState() =>
      _FarmerPerformanceDetailScreenState();
}

class _FarmerPerformanceDetailScreenState
    extends State<FarmerPerformanceDetailScreen> {
  bool _isLoading = true;
  List<FarmerBatchSummary> _summaries = [];
  StaffPerformanceBenchmark _benchmark = const StaffPerformanceBenchmark();
  CompanyAverageMetrics _companyAvg = const CompanyAverageMetrics(
    avgFcr: 0,
    avgMortalityPct: 0,
    avgWeightGrowthPct: 0,
    sampleCount: 0,
  ); // ✅ NEW

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final summaries = await computeFarmerBatchSummaries(
      farmers: [widget.farmer],
      scope: widget.scope,
      lastN: widget.lastN,
    );
    final benchmark = await loadStaffPerformanceBenchmark();
    final companyAvg = await computeCompanyAverageMetrics(
      scope: widget.scope,
      lastN: widget.lastN,
    ); // ✅ NEW
    if (!mounted) return;
    setState(() {
      _summaries = summaries;
      _benchmark = benchmark;
      _companyAvg = companyAvg; // ✅ NEW
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _spGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          widget.farmer['name']?.toString() ?? 'Farmer',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _spGreen))
          : _summaries.isEmpty
          ? Center(
              child: Text(
                'Is farmer ka koi batch data nahi mila.',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _summaries.length,
              itemBuilder: (context, i) => _batchCard(_summaries[i]),
            ),
    );
  }

  Widget _batchCard(FarmerBatchSummary s) {
    final rating = s.overallRating(_benchmark);
    final trendAlert = s.trendAlert(_benchmark); // ✅ NEW
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${s.batchId} • ${s.daysOld} din',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: ratingColor(rating).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  ratingLabel(rating),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: ratingColor(rating),
                  ),
                ),
              ),
            ],
          ),
          // ✅ NEW — is batch ka decline-trend alert, agar hai to
          if (trendAlert != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: trendAlert.severity == TrendSeverity.danger
                    ? Colors.red.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    trendAlert.severity == TrendSeverity.danger
                        ? Icons.error_rounded
                        : Icons.trending_down_rounded,
                    size: 16,
                    color: trendAlert.severity == TrendSeverity.danger
                        ? Colors.red.shade700
                        : Colors.orange.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      trendAlert.message,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: trendAlert.severity == TrendSeverity.danger
                            ? Colors.red.shade900
                            : Colors.orange.shade900,
                        fontWeight: trendAlert.severity == TrendSeverity.danger
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _metricStat(
                  'FCR',
                  s.finalFcr.toStringAsFixed(2),
                  s.fcrRating(_benchmark),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metricStat(
                  'Mortality',
                  '${s.finalMortalityPct.toStringAsFixed(1)}%',
                  s.mortalityRating(_benchmark),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metricStat(
                  'Weight Growth',
                  '${s.finalWeightGrowthPct.toStringAsFixed(0)}%',
                  s.weightGrowthRating(_benchmark),
                ),
              ),
            ],
          ),
          // ✅ NEW — Company average ke against chhota comparison
          if (_companyAvg.sampleCount > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                Text(
                  'Company Avg — FCR ${_companyAvg.avgFcr.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
                Text(
                  'Mortality ${_companyAvg.avgMortalityPct.toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
                Text(
                  'Weight Growth ${_companyAvg.avgWeightGrowthPct.toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          _DailyGraphCard(
            title: '💀 Mortality — Daily (Cumulative %)',
            points: s.dailyPoints,
            valueOf: (p) => p.mortalityPct,
            isManualOf: (p) => p.day > 0, // din 0 baseline hai, manual nahi
            color: Colors.red.shade500,
            axisFormatter: (v) => v.toStringAsFixed(1),
            tooltipFormatter: (v) => '${v.toStringAsFixed(2)}%',
          ),
          const SizedBox(height: 24),
          _DailyGraphCard(
            title: '🎯 FCR — Daily (Cumulative)',
            points: s.dailyPoints,
            valueOf: (p) => p.fcr,
            isManualOf: (p) => p.fcrIsManual,
            color: Colors.indigo.shade500,
            axisFormatter: (v) => v.toStringAsFixed(2),
            tooltipFormatter: (v) => v.toStringAsFixed(3),
          ),
          const SizedBox(height: 24),
          // ✅ FIX — ab % nahi, seedha Weight (gram) dikhta hai, 40g se
          // shuru hoke Din ke hisaab se badhta hua. BLUE = actual (manual
          // report ho to wahi, warna auto-estimate), RED = pure standard
          // growth curve — dono compare karne ke liye same graph mein.
          _DailyGraphCard(
            title: '⚖️ Weight — Daily (gram)',
            points: s.dailyPoints,
            valueOf: (p) => p.weightKg * 1000,
            isManualOf: (p) => p.weightIsManual && p.day > 0,
            color: Colors.blue.shade600,
            axisFormatter: (v) => '${v.toStringAsFixed(0)}g',
            tooltipFormatter: (v) => '${v.toStringAsFixed(1)}g',
            secondaryValueOf: (p) => p.autoWeightKg * 1000,
            secondaryColor: Colors.red.shade400,
            secondaryLabel: 'Standard Curve (Auto)',
          ),
        ],
      ),
    );
  }

  Widget _metricStat(String label, String value, PerformanceRating rating) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ratingColor(rating).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: ratingColor(rating)),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: ratingColor(rating),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 📈 DAILY GRAPH CARD — Zoom (pinch), Din-select-karke value dekho, aur
// optional dual-line (BLUE=actual, RED=auto/standard curve compare).
// Default state mein poora batch (chahe 40 din ho ya 100) screen ke andar
// hi fit ho jaata hai — koi scroll nahi karna padta. Pinch se zoom karke
// pan (andar-bahar move) kar sakte ho.
// ═══════════════════════════════════════════════════════════════════════════
class _DailyGraphCard extends StatefulWidget {
  final String title;
  final List<FarmerDailyPoint> points;
  final double Function(FarmerDailyPoint) valueOf;
  final bool Function(FarmerDailyPoint) isManualOf;
  final Color color;
  final String Function(double) axisFormatter;
  final String Function(double) tooltipFormatter;
  final double Function(FarmerDailyPoint)? secondaryValueOf;
  final Color? secondaryColor;
  final String? secondaryLabel;

  const _DailyGraphCard({
    required this.title,
    required this.points,
    required this.valueOf,
    required this.isManualOf,
    required this.color,
    required this.axisFormatter,
    required this.tooltipFormatter,
    this.secondaryValueOf,
    this.secondaryColor,
    this.secondaryLabel,
  });

  @override
  State<_DailyGraphCard> createState() => _DailyGraphCardState();
}

class _DailyGraphCardState extends State<_DailyGraphCard> {
  int? _selectedIndex;
  final TransformationController _transformCtrl = TransformationController();

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformCtrl.value = Matrix4.identity();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.isEmpty) return const SizedBox.shrink();

    final spots = <FlSpot>[];
    final secondarySpots = widget.secondaryValueOf != null ? <FlSpot>[] : null;
    double maxY = 0;
    for (int i = 0; i < points.length; i++) {
      final v = widget.valueOf(points[i]);
      spots.add(FlSpot(i.toDouble(), v));
      if (v > maxY) maxY = v;
      if (widget.secondaryValueOf != null) {
        final sv = widget.secondaryValueOf!(points[i]);
        secondarySpots!.add(FlSpot(i.toDouble(), sv));
        if (sv > maxY) maxY = sv;
      }
    }
    maxY = maxY <= 0 ? 10 : maxY * 1.25;
    // ✅ FIX — poore batch ke saare din screen ke andar dikhein (koi bhi
    // batch lambaai ho), isliye label-step count ke hisaab se adjust hota
    // hai, points count se width nahi badhti (scroll ki zaroorat nahi).
    final step = (points.length / 6).ceil().clamp(1, points.length);

    final selected = _selectedIndex != null && _selectedIndex! < points.length
        ? points[_selectedIndex!]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.zoom_out_map_rounded, size: 18),
              tooltip: 'Zoom Reset',
              visualDensity: VisualDensity.compact,
              onPressed: _resetZoom,
            ),
          ],
        ),
        const SizedBox(height: 2),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _legendDot(widget.color, 'Manual Report', filled: true),
            _legendDot(Colors.grey.shade400, 'Auto Estimate', filled: false),
            if (widget.secondaryLabel != null)
              _legendDot(
                widget.secondaryColor ?? Colors.red,
                widget.secondaryLabel!,
                filled: true,
                isDashed: true,
              ),
          ],
        ),
        const SizedBox(height: 6),
        // ✅ NEW — Din tap/select karo, uska exact value yahan dikhega
        if (selected != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: widget.color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Din ${selected.day} (${_fmtDate(selected.date)}): '
              '${widget.tooltipFormatter(widget.valueOf(selected))}'
              '${widget.isManualOf(selected) ? " • Manual" : " • Auto"}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: widget.color,
              ),
            ),
          ),
        SizedBox(
          height: 200,
          width: double.infinity,
          child: InteractiveViewer(
            transformationController: _transformCtrl,
            panEnabled: true,
            scaleEnabled: true,
            minScale: 1,
            maxScale: 6,
            child: LineChart(
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
                        widget.axisFormatter(v),
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      interval: step.toDouble(),
                      getTitlesWidget: (v, m) {
                        final idx = v.toInt();
                        if (idx < 0 ||
                            idx >= points.length ||
                            idx % step != 0) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          'D${points[idx].day}',
                          style: const TextStyle(
                            fontSize: 8.5,
                            color: Colors.black45,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touched) => touched.map((t) {
                      final idx = t.x.toInt();
                      if (idx < 0 || idx >= points.length) return null;
                      final manual = widget.isManualOf(points[idx]);
                      return LineTooltipItem(
                        '${widget.tooltipFormatter(t.y)}\nDin ${points[idx].day}'
                        '${manual ? " (Manual)" : " (Auto)"}',
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }).toList(),
                  ),
                  // ✅ NEW — tap karke Din select karo, upar wala info-box
                  // update ho jaayega (touch chhodne ke baad bhi rahega)
                  touchCallback: (event, response) {
                    if (response == null ||
                        response.lineBarSpots == null ||
                        response.lineBarSpots!.isEmpty) {
                      return;
                    }
                    if (event is FlTapUpEvent ||
                        event is FlPanEndEvent ||
                        event is FlLongPressEnd) {
                      final idx = response.lineBarSpots!.first.x.toInt();
                      setState(() => _selectedIndex = idx);
                    }
                  },
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: widget.color,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) {
                        final manual = widget.isManualOf(points[index]);
                        final isSelected = index == _selectedIndex;
                        return FlDotCirclePainter(
                          radius: isSelected ? 4.5 : 2.8,
                          color: manual ? widget.color : Colors.white,
                          strokeWidth: manual ? 0 : 1.5,
                          strokeColor: isSelected
                              ? Colors.black87
                              : (manual ? widget.color : Colors.grey.shade400),
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: widget.secondaryValueOf == null,
                      color: widget.color.withOpacity(0.08),
                    ),
                  ),
                  if (secondarySpots != null)
                    LineChartBarData(
                      spots: secondarySpots,
                      isCurved: true,
                      color: widget.secondaryColor ?? Colors.red,
                      barWidth: 2,
                      dashArray: [6, 4],
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _legendDot(
    Color color,
    String label, {
    required bool filled,
    bool isDashed = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isDashed)
          SizedBox(
            width: 14,
            height: 2,
            child: CustomPaint(painter: _DashPainter(color: color)),
          )
        else
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: filled ? color : Colors.white,
              shape: BoxShape.circle,
              border: filled ? null : Border.all(color: color, width: 1.5),
            ),
          ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 9.5, color: Colors.black54),
        ),
      ],
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

class _DashPainter extends CustomPainter {
  final Color color;
  const _DashPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const dashWidth = 4.0;
    const dashSpace = 3.0;
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, size.height / 2),
        Offset(startX + dashWidth, size.height / 2),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter oldDelegate) =>
      oldDelegate.color != color;
}
