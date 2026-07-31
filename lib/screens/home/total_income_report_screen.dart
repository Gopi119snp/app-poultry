import 'dart:async'; // ✅ EDIT: StreamSubscription + Timer ke liye
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:poultrypro/services/company_store.dart'; // ✅ EDIT: CompanyStore ke liye
import 'accounts_screen.dart' show AppDateFilter;
import 'income_engine.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 💰 TOTAL INCOME REPORT — Company-Farmer vs Private Sales, date-filtered
// ═══════════════════════════════════════════════════════════════════════════
const Color _tiGreen = Color(0xFF1B5E20);
const Color _companyFarmerColor = Color(0xFF4FC3F7); // blue
const Color _privateSalesColor = Color(0xFFFFB74D); // orange

String _fmt(double v) {
  final abs = v.abs();
  final sign = v < 0 ? '-' : '';
  if (abs >= 100000) return '$sign₹${(abs / 100000).toStringAsFixed(2)}L';
  if (abs >= 1000) return '$sign₹${(abs / 1000).toStringAsFixed(1)}K';
  return '$sign₹${abs.toStringAsFixed(0)}';
}

class TotalIncomeReportScreen extends StatefulWidget {
  const TotalIncomeReportScreen({super.key});

  @override
  State<TotalIncomeReportScreen> createState() =>
      _TotalIncomeReportScreenState();
}

class _TotalIncomeReportScreenState extends State<TotalIncomeReportScreen> {
  bool _isLoading = true;
  late AppDateFilter _selectedFilter;

  CategoryBreakdown _companyFarmer = CategoryBreakdown.zero;
  CategoryBreakdown _privateSales = CategoryBreakdown.zero;

  // 0 = Company-Farmer, 1 = Private Sales, null = koi select nahi
  int? _selectedSide;

  // ✅ Real-time sync & polling variables
  StreamSubscription<void>? _dataSub;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedFilter = AppDateFilter(
      label: 'Current Month',
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
    );
    _loadData();

    // ✅ Real-time CompanyStore stream listener — data change hote hi
    // report turant refresh ho jayegi
    _dataSub = CompanyStore.instance.onDataChanged.listen((_) {
      if (!mounted) return;
      _loadData();
    });

    // ✅ 5-second fast verification timer
    // (stream miss ho jaaye toh bhi backup ke roop mein kaam karega)
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _loadData();
    });
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _pollTimer?.cancel(); // ✅ Clean up
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      computeCompanyFarmerIncome(_selectedFilter),
      computePrivateSalesIncome(_selectedFilter),
    ]);
    if (!mounted) return;
    setState(() {
      _companyFarmer = results[0];
      _privateSales = results[1];
      _isLoading = false;
      _selectedSide = null;
    });
  }

  // ── Period Picker (jaisa Accounts screen mein hai) ──────────────────────
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
                'Data Kab Ka Dekhna Hai?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(
                  Icons.all_inclusive_rounded,
                  color: _tiGreen,
                ),
                title: const Text(
                  'Pura Data (All Time)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Shuru se ab tak ka sab kuch',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(
                    () => _selectedFilter = AppDateFilter(
                      label: 'All Time',
                      isAllTime: true,
                    ),
                  );
                  _loadData();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.calendar_today_rounded,
                  color: _tiGreen,
                ),
                title: const Text(
                  'Current Month',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  final now = DateTime.now();
                  setState(
                    () => _selectedFilter = AppDateFilter(
                      label: 'Current Month',
                      start: DateTime(now.year, now.month, 1),
                      end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
                    ),
                  );
                  _loadData();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.calendar_month_rounded,
                  color: _tiGreen,
                ),
                title: const Text(
                  'Koi Ek Mahina Chune',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSingleMonthPicker();
                },
              ),
              ListTile(
                leading: const Icon(Icons.date_range_rounded, color: _tiGreen),
                title: const Text(
                  'Custom Range',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Kisi bhi do dates ke beech ka',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickCustomDateRange();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSingleMonthPicker() {
    final now = DateTime.now();
    final months = List.generate(
      24,
      (i) => DateTime(now.year, now.month - i, 1),
    );
    const monthNames = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Mahina Chuniye',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: months.length,
                itemBuilder: (c, i) {
                  final m = months[i];
                  final label = '${monthNames[m.month]} ${m.year}';
                  return ListTile(
                    title: Text(label, style: const TextStyle(fontSize: 14)),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: Colors.grey,
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(
                        () => _selectedFilter = AppDateFilter(
                          label: label,
                          start: m,
                          end: DateTime(m.year, m.month + 1, 0, 23, 59, 59),
                        ),
                      );
                      _loadData();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _tiGreen,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    final startStr =
        '${picked.start.day}/${picked.start.month}/${picked.start.year}';
    final endStr = '${picked.end.day}/${picked.end.month}/${picked.end.year}';
    setState(
      () => _selectedFilter = AppDateFilter(
        label: '$startStr - $endStr',
        start: picked.start,
        end: DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        ),
      ),
    );
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final double companyFarmerTotal = _companyFarmer.total;
    final double privateTotal = _privateSales.total;
    final double grandTotal = companyFarmerTotal + privateTotal;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _tiGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: const Text(
          '💰 Total Income',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _tiGreen))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Period selector chip ──
                    InkWell(
                      onTap: _showFilterSheet,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _tiGreen.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _tiGreen.withOpacity(0.25)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.event_note_rounded,
                              color: _tiGreen,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedFilter.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _tiGreen,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: _tiGreen,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Total Income hero card ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: grandTotal >= 0 ? _tiGreen : Colors.red.shade700,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            grandTotal >= 0
                                ? '📈 Total Income (${_selectedFilter.label})'
                                : '📉 Total Loss (${_selectedFilter.label})',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${grandTotal >= 0 ? "+" : "-"}${_fmt(grandTotal.abs())}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (companyFarmerTotal == 0 && privateTotal == 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            'Is period mein koi data nahi mila.',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ),
                      )
                    else ...[
                      const Text(
                        'Kis Se Kitna Kamaya',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Slice par tap karo detail dekhne ke liye',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade600,
                        ),
                      ),

                      _TwoSlicePie(
                        companyFarmerTotal: companyFarmerTotal,
                        privateTotal: privateTotal,
                        selectedIndex: _selectedSide,
                        onSelect: (i) => setState(
                          () => _selectedSide = _selectedSide == i ? null : i,
                        ),
                      ),

                      if (_selectedSide != null) ...[
                        const SizedBox(height: 20),
                        _CategoryBreakdownCard(
                          title: _selectedSide == 0
                              ? '🧑‍🌾 Company ↔ Farmer — Kis Bhag Se'
                              : '🛒 Private Sales — Kis Bhag Se',
                          breakdown: _selectedSide == 0
                              ? _companyFarmer
                              : _privateSales,
                          showAdminOperational: _selectedSide == 0,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Donut — 2 slice (Company-Farmer / Private Sales)
// ═══════════════════════════════════════════════════════════════════════════
class _TwoSlicePie extends StatelessWidget {
  final double companyFarmerTotal;
  final double privateTotal;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;

  const _TwoSlicePie({
    required this.companyFarmerTotal,
    required this.privateTotal,
    required this.selectedIndex,
    required this.onSelect,
  });

  static const double _chartSize = 210;

  void _handleTap(Offset localPosition) {
    final values = [companyFarmerTotal.abs(), privateTotal.abs()];
    final total = values.fold(0.0, (s, v) => s + v);
    if (total <= 0) return;

    const Offset center = Offset(_chartSize / 2, _chartSize / 2);
    final Offset vector = localPosition - center;
    final double distance = vector.distance;
    const double outerRadius = _chartSize / 2;
    const double innerRadius = outerRadius * 0.5;
    if (distance > outerRadius + 14 || distance < innerRadius - 6) return;

    double angle = math.atan2(vector.dy, vector.dx);
    double adjusted = angle + math.pi / 2;
    if (adjusted < 0) adjusted += 2 * math.pi;
    if (adjusted >= 2 * math.pi) adjusted -= 2 * math.pi;

    double cumulative = 0;
    for (int i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * 2 * math.pi;
      if (adjusted >= cumulative && adjusted < cumulative + sweep) {
        onSelect(i);
        return;
      }
      cumulative += sweep;
    }
  }

  @override
  Widget build(BuildContext context) {
    final values = [companyFarmerTotal.abs(), privateTotal.abs()];
    final isNegative = [companyFarmerTotal < 0, privateTotal < 0];
    const colors = [_companyFarmerColor, _privateSalesColor];
    final total = values.fold(0.0, (s, v) => s + v);

    if (total <= 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(child: Text('Koi data nahi')),
      );
    }

    return Column(
      children: [
        const SizedBox(height: 14),
        Center(
          child: GestureDetector(
            onTapUp: (d) => _handleTap(d.localPosition),
            child: SizedBox(
              width: _chartSize,
              height: _chartSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(_chartSize, _chartSize),
                    painter: _DonutPainter(
                      values: values,
                      colors: colors,
                      isNegative: isNegative,
                      selectedIndex: selectedIndex,
                    ),
                  ),
                  if (selectedIndex != null)
                    Container(
                      width: _chartSize * 0.5,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            selectedIndex == 0
                                ? 'Company-Farmer'
                                : 'Private Sales',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            () {
                              final v = selectedIndex == 0
                                  ? companyFarmerTotal
                                  : privateTotal;
                              return '${v >= 0 ? "+" : "-"}${_fmt(v.abs())}';
                            }(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color:
                                  (selectedIndex == 0
                                          ? companyFarmerTotal
                                          : privateTotal) >=
                                      0
                                  ? _tiGreen
                                  : Colors.red.shade600,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
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
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _legendChip(
              'Company-Farmer',
              colors[0],
              isNegative[0],
              selectedIndex == 0,
              () => onSelect(0),
            ),
            _legendChip(
              'Private Sales',
              colors[1],
              isNegative[1],
              selectedIndex == 1,
              () => onSelect(1),
            ),
          ],
        ),
      ],
    );
  }

  Widget _legendChip(
    String label,
    Color color,
    bool neg,
    bool selected,
    VoidCallback onTap,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.green.shade50 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: neg
              ? Border.all(color: Colors.red.shade300, width: 1.2)
              : (selected
                    ? Border.all(color: Colors.green.shade300)
                    : Border.all(color: Colors.grey.shade200)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              '${neg ? "− " : ""}$label',
              style: TextStyle(
                color: neg ? Colors.red.shade700 : Colors.black87,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final List<bool> isNegative;
  final int? selectedIndex;

  _DonutPainter({
    required this.values,
    required this.colors,
    required this.isNegative,
    required this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold(0.0, (s, v) => s + v);
    if (total <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2 - 6;
    double startAngle = -math.pi / 2;

    for (int i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * 2 * math.pi;
      final isSelected = selectedIndex == i;
      final radius = isSelected ? baseRadius + 10 : baseRadius;

      Offset sliceCenter = center;
      if (isSelected) {
        final midAngle = startAngle + sweep / 2;
        sliceCenter =
            center + Offset(math.cos(midAngle), math.sin(midAngle)) * 8;
      }

      final fillPaint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.fill;
      final rect = Rect.fromCircle(center: sliceCenter, radius: radius);
      canvas.drawArc(rect, startAngle, sweep, true, fillPaint);

      final neg = i < isNegative.length && isNegative[i];
      final borderPaint = Paint()
        ..color = neg ? Colors.red.shade400 : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = neg ? 3.2 : 2.5;
      canvas.drawArc(rect, startAngle, sweep, true, borderPaint);

      startAngle += sweep;
    }

    final holePaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, baseRadius * 0.5, holePaint);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.values != values ||
        oldDelegate.colors != colors ||
        oldDelegate.isNegative != isNegative;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Category breakdown card — Chicks / Feed / Medicine / (Admin-Operational)
// Card-based bars (koi custom painter graph nahi — Gopi pehle bata chuka hai
// ki graph-line style usse pasand nahi aayi thi).
// ═══════════════════════════════════════════════════════════════════════════
class _CategoryBreakdownCard extends StatelessWidget {
  final String title;
  final CategoryBreakdown breakdown;
  final bool showAdminOperational;

  const _CategoryBreakdownCard({
    required this.title,
    required this.breakdown,
    required this.showAdminOperational,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <_CatRow>[
      _CatRow('🐣 Chicks', breakdown.chicks, Colors.orange.shade700),
      _CatRow('🌾 Feed', breakdown.feed, Colors.blue.shade700),
      _CatRow('💊 Medicine', breakdown.medicine, Colors.teal.shade700),
      if (showAdminOperational)
        _CatRow(
          '🧮 Admin/Operational Asar',
          breakdown.adminOperational,
          Colors.purple.shade400,
        ),
    ];

    final maxAbs = rows.fold<double>(0, (s, r) => math.max(s, r.value.abs()));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
          ),
          const SizedBox(height: 4),
          Text(
            'In sabka jod = ${breakdown.total >= 0 ? "+" : "-"}${_fmt(breakdown.total.abs())} (${_selectedLabel(showAdminOperational)})',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          for (final r in rows) ...[
            _buildRow(r, maxAbs),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  String _selectedLabel(bool isCompanyFarmer) =>
      isCompanyFarmer ? 'True Total Profit' : 'Private Sales Profit';

  Widget _buildRow(_CatRow r, double maxAbs) {
    final neg = r.value < 0;
    final double fraction = maxAbs > 0 ? (r.value.abs() / maxAbs) : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              r.label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${neg ? "-" : "+"}${_fmt(r.value.abs())}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: neg ? Colors.red.shade600 : Colors.green.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction.clamp(0, 1),
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(
              neg ? Colors.red.shade400 : r.color,
            ),
          ),
        ),
      ],
    );
  }
}

class _CatRow {
  final String label;
  final double value;
  final Color color;
  _CatRow(this.label, this.value, this.color);
}
