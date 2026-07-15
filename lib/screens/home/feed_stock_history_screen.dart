import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../services/company_store.dart';
import 'dart:convert';
import 'purchase_expense_screen.dart'
    show ensureFeedStockMigrated, kFeedTypeNames, formatHistoryDateTime;

// ═══════════════════════════════════════════════════════════════════════════
// 📅 DATE FILTER SHEET — "Data Kab Ka Dekhna Hai?" (Accounts screen jaisa)
// Sirf Stock tab ke liye — purchase_expense_screen.dart me koi chhed-chhaad nahi.
// ═══════════════════════════════════════════════════════════════════════════
Future<MapEntry<String, DateTimeRange?>?> showFeedDateFilterSheet(
  BuildContext context,
) {
  return showModalBottomSheet<MapEntry<String, DateTimeRange?>>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const Text(
                'Data Kab Ka Dekhna Hai?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 18),
              _feedDateFilterOption(
                ctx,
                icon: Icons.all_inclusive_rounded,
                title: 'Pura Data (All Time)',
                subtitle: 'Shuru se ab tak ka sab kuch',
                onTap: () => Navigator.pop(
                  ctx,
                  const MapEntry('Pura Data (All Time)', null),
                ),
              ),
              const SizedBox(height: 14),
              _feedDateFilterOption(
                ctx,
                icon: Icons.calendar_today_rounded,
                title: 'Current Month',
                subtitle: '',
                onTap: () {
                  final now = DateTime.now();
                  final start = DateTime(now.year, now.month, 1);
                  final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
                  Navigator.pop(
                    ctx,
                    MapEntry(
                      'Current Month',
                      DateTimeRange(start: start, end: end),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              _feedDateFilterOption(
                ctx,
                icon: Icons.calendar_view_month_rounded,
                title: 'Koi Ek Mahina Chune',
                subtitle: '',
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    helpText: 'Koi bhi date chunein us mahine ki',
                  );
                  if (picked == null) return;
                  final start = DateTime(picked.year, picked.month, 1);
                  final end = DateTime(
                    picked.year,
                    picked.month + 1,
                    0,
                    23,
                    59,
                    59,
                  );
                  Navigator.pop(
                    ctx,
                    MapEntry(
                      '${picked.month}/${picked.year}',
                      DateTimeRange(start: start, end: end),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              _feedDateFilterOption(
                ctx,
                icon: Icons.date_range_rounded,
                title: 'Custom Range',
                subtitle: 'Kisi bhi do dates ke beech ka',
                onTap: () async {
                  final picked = await showDateRangePicker(
                    context: ctx,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked == null) return;
                  Navigator.pop(
                    ctx,
                    MapEntry(
                      '${picked.start.day}/${picked.start.month} - ${picked.end.day}/${picked.end.month}',
                      DateTimeRange(
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
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _feedDateFilterOption(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFF1B5E20), size: 22),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

bool _feedDateInRange(String? rawDate, DateTimeRange? range) {
  if (range == null) return true; // "All Time" — sab dikhao
  if (rawDate == null || rawDate.isEmpty) return false;
  final d = DateTime.tryParse(rawDate);
  if (d == null) return false;
  return !d.isBefore(range.start) && !d.isAfter(range.end);
}

// ═══════════════════════════════════════════════════════════════════════════
// 🗂️ HUB SCREEN — Farmer Allocation / Private Buyers, date-filtered
// ═══════════════════════════════════════════════════════════════════════════
class FeedStockHistoryHubScreen extends StatefulWidget {
  final String feedTypeId;
  const FeedStockHistoryHubScreen({super.key, required this.feedTypeId});

  @override
  State<FeedStockHistoryHubScreen> createState() =>
      _FeedStockHistoryHubScreenState();
}

class _FeedStockHistoryHubScreenState extends State<FeedStockHistoryHubScreen> {
  DateTimeRange? _range;
  String _label = 'Pura Data (All Time)';
  String _feedName = '';

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  Future<void> _loadName() async {
    final stock = await ensureFeedStockMigrated();
    final entry = stock.firstWhere(
      (s) => s['id'] == widget.feedTypeId,
      orElse: () => {},
    );
    if (mounted) {
      setState(() {
        _feedName =
            entry['name']?.toString() ??
            kFeedTypeNames[widget.feedTypeId] ??
            '';
      });
    }
  }

  Future<void> _pickFilter() async {
    final result = await showFeedDateFilterSheet(context);
    if (result == null) return;
    setState(() {
      _label = result.key;
      _range = result.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          '$_feedName — History',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: _pickFilter,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.filter_alt_rounded,
                      size: 18,
                      color: Colors.blue.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      color: Colors.blue.shade700,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            InkWell(
              onTap: () => Get.to(
                () => FeedStockFarmerAllocationsScreen(
                  feedTypeId: widget.feedTypeId,
                  dateRange: _range,
                ),
              ),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.people_alt_rounded,
                      color: Colors.blue.shade700,
                      size: 26,
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Farmer Allocation',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.blue.shade400,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => Get.to(
                () => FeedStockPrivateBuyersScreen(
                  feedTypeId: widget.feedTypeId,
                  dateRange: _range,
                ),
              ),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.storefront_rounded,
                      color: Colors.blue.shade700,
                      size: 26,
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Private Buyers',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.blue.shade400,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🧑 FARMER ALLOCATION HISTORY (Stock tab ke liye, read-only, date-filtered)
// ═══════════════════════════════════════════════════════════════════════════
class FeedStockFarmerAllocationsScreen extends StatefulWidget {
  final String feedTypeId;
  final DateTimeRange? dateRange;
  const FeedStockFarmerAllocationsScreen({
    super.key,
    required this.feedTypeId,
    this.dateRange,
  });

  @override
  State<FeedStockFarmerAllocationsScreen> createState() =>
      _FeedStockFarmerAllocationsScreenState();
}

class _FeedStockFarmerAllocationsScreenState
    extends State<FeedStockFarmerAllocationsScreen> {
  List<Map<String, dynamic>> _allocs = [];
  String _name = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final stock = await ensureFeedStockMigrated();
    final entry = stock.firstWhere(
      (s) => s['id'] == widget.feedTypeId,
      orElse: () => {},
    );
    List<Map<String, dynamic>> allocs = List<Map<String, dynamic>>.from(
      ((entry['allocations'] as List?) ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    allocs = allocs
        .where(
          (a) =>
              _feedDateInRange(a['allocatedOn']?.toString(), widget.dateRange),
        )
        .toList();
    allocs.sort(
      (a, b) => (b['allocatedOn'] ?? '').toString().compareTo(
        (a['allocatedOn'] ?? '').toString(),
      ),
    );
    if (mounted) {
      setState(() {
        _allocs = allocs;
        _name =
            entry['name']?.toString() ??
            kFeedTypeNames[widget.feedTypeId] ??
            '';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          '🧑 $_name — Farmer Allocations',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _allocs.isEmpty
          ? const Center(child: Text('Koi allocation nahi.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _allocs.length,
              itemBuilder: (context, i) {
                final a = _allocs[i];
                final String date = formatHistoryDateTime(
                  a['allocatedOn']?.toString(),
                );
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🧑 ${a['farmerName'] ?? '-'}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (a['batchId']?.toString().isNotEmpty ?? false)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '🏷️ Batch: ${a['batchId']}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple.shade700,
                                  ),
                                ),
                              ),
                            if (date.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  date,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '${((a['qty'] as num?) ?? 0).toStringAsFixed(0)} bag',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🛒 PRIVATE BUYERS HISTORY (Stock tab ke liye, read-only, date-filtered)
// ═══════════════════════════════════════════════════════════════════════════
class FeedStockPrivateBuyersScreen extends StatefulWidget {
  final String feedTypeId;
  final DateTimeRange? dateRange;
  const FeedStockPrivateBuyersScreen({
    super.key,
    required this.feedTypeId,
    this.dateRange,
  });

  @override
  State<FeedStockPrivateBuyersScreen> createState() =>
      _FeedStockPrivateBuyersScreenState();
}

class _FeedStockPrivateBuyersScreenState
    extends State<FeedStockPrivateBuyersScreen> {
  List<Map<String, dynamic>> _sales = [];
  String _name = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final stock = await ensureFeedStockMigrated();
    final entry = stock.firstWhere(
      (s) => s['id'] == widget.feedTypeId,
      orElse: () => {},
    );
    List<Map<String, dynamic>> sales = List<Map<String, dynamic>>.from(
      ((entry['privateSales'] as List?) ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    sales = sales
        .where((s) => _feedDateInRange(s['date']?.toString(), widget.dateRange))
        .toList();
    sales.sort(
      (a, b) =>
          (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()),
    );
    if (mounted) {
      setState(() {
        _sales = sales;
        _name =
            entry['name']?.toString() ??
            kFeedTypeNames[widget.feedTypeId] ??
            '';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          '🛒 $_name — Private Buyers',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sales.isEmpty
          ? const Center(child: Text('Koi private buyer nahi.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _sales.length,
              itemBuilder: (context, i) {
                final s = _sales[i];
                final double qty = (s['qty'] as num?)?.toDouble() ?? 0.0;
                final double rate = (s['rate'] as num?)?.toDouble() ?? 0.0;
                final double paid =
                    (s['paidAmount'] as num?)?.toDouble() ?? 0.0;
                final double total = qty * rate;
                final double due = (total - paid).clamp(0.0, double.infinity);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '🛒 ${s['buyerName'] ?? '-'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '₹${total.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${qty.toStringAsFixed(0)} bag @ ₹${rate.toStringAsFixed(2)}/bag',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: due > 0
                                ? Colors.red.shade50
                                : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            due > 0
                                ? 'Due: ₹${due.toStringAsFixed(0)}'
                                : '✅ Paid',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: due > 0
                                  ? Colors.red.shade800
                                  : Colors.green.shade800,
                            ),
                          ),
                        ),
                      ),
                      if ((s['date']?.toString() ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '🕒 ${formatHistoryDateTime(s['date'].toString())}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black45,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 💊 MEDICINE STOCK HISTORY — Same pattern, Medicine ke liye (read-only)
// ═══════════════════════════════════════════════════════════════════════════
class MedicineStockHistoryHubScreen extends StatefulWidget {
  final String medicineId;
  final String medicineName;
  final String unit;
  const MedicineStockHistoryHubScreen({
    super.key,
    required this.medicineId,
    required this.medicineName,
    required this.unit,
  });

  @override
  State<MedicineStockHistoryHubScreen> createState() =>
      _MedicineStockHistoryHubScreenState();
}

class _MedicineStockHistoryHubScreenState
    extends State<MedicineStockHistoryHubScreen> {
  DateTimeRange? _range;
  String _label = 'Pura Data (All Time)';

  Future<void> _pickFilter() async {
    final result = await showFeedDateFilterSheet(context);
    if (result == null) return;
    setState(() {
      _label = result.key;
      _range = result.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.teal.shade700,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          '${widget.medicineName} — History',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: _pickFilter,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.teal.shade100),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.filter_alt_rounded,
                      size: 18,
                      color: Colors.teal.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      color: Colors.teal.shade700,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            InkWell(
              onTap: () => Get.to(
                () => MedicineStockFarmerAllocationsScreen(
                  medicineId: widget.medicineId,
                  medicineName: widget.medicineName,
                  unit: widget.unit,
                  dateRange: _range,
                ),
              ),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.teal.shade100),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.people_alt_rounded,
                      color: Colors.teal.shade700,
                      size: 26,
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Farmer Allocation',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.teal.shade400,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => Get.to(
                () => MedicineStockPrivateBuyersScreen(
                  medicineId: widget.medicineId,
                  medicineName: widget.medicineName,
                  dateRange: _range,
                ),
              ),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.teal.shade100),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.storefront_rounded,
                      color: Colors.teal.shade700,
                      size: 26,
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Private Buyers',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.teal.shade400,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Medicine Farmer Allocations (read-only, date-filtered) ──
class MedicineStockFarmerAllocationsScreen extends StatefulWidget {
  final String medicineId;
  final String medicineName;
  final String unit;
  final DateTimeRange? dateRange;
  const MedicineStockFarmerAllocationsScreen({
    super.key,
    required this.medicineId,
    required this.medicineName,
    required this.unit,
    this.dateRange,
  });

  @override
  State<MedicineStockFarmerAllocationsScreen> createState() =>
      _MedicineStockFarmerAllocationsScreenState();
}

class _MedicineStockFarmerAllocationsScreenState
    extends State<MedicineStockFarmerAllocationsScreen> {
  List<Map<String, dynamic>> _allocs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final String? stockJson = await CompanyStore.instance.getString(
      'medicineStockList',
    );
    List<Map<String, dynamic>> allocs = [];
    if (stockJson != null) {
      try {
        final List<dynamic> all = json.decode(stockJson);
        for (final m in all) {
          if (m['id']?.toString() == widget.medicineId) {
            final List<dynamic> raw = m['allocations'] as List<dynamic>? ?? [];
            allocs = raw
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            break;
          }
        }
      } catch (_) {}
    }
    allocs = allocs
        .where(
          (a) =>
              _feedDateInRange(a['allocatedOn']?.toString(), widget.dateRange),
        )
        .toList();
    allocs.sort(
      (a, b) => (b['allocatedOn'] ?? '').toString().compareTo(
        (a['allocatedOn'] ?? '').toString(),
      ),
    );
    if (mounted) {
      setState(() {
        _allocs = allocs;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.teal.shade700,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          '🧑 ${widget.medicineName} — Farmer Allocations',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _allocs.isEmpty
          ? const Center(child: Text('Koi allocation nahi.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _allocs.length,
              itemBuilder: (context, i) {
                final a = _allocs[i];
                final String date = formatHistoryDateTime(
                  a['date']?.toString(),
                );
                final String allocDate = formatHistoryDateTime(
                  a['allocatedOn']?.toString(),
                );
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.teal.shade100),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🧑 ${a['farmerName'] ?? '-'}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (a['batchId']?.toString().isNotEmpty ?? false)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '🏷️ Batch: ${a['batchId']}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple.shade700,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                allocDate.isNotEmpty ? allocDate : date,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${((a['qty'] as num?) ?? 0).toStringAsFixed(2)} ${a['unit'] ?? widget.unit}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ── Medicine Private Buyers (read-only, date-filtered) ──
class MedicineStockPrivateBuyersScreen extends StatefulWidget {
  final String medicineId;
  final String medicineName;
  final DateTimeRange? dateRange;
  const MedicineStockPrivateBuyersScreen({
    super.key,
    required this.medicineId,
    required this.medicineName,
    this.dateRange,
  });

  @override
  State<MedicineStockPrivateBuyersScreen> createState() =>
      _MedicineStockPrivateBuyersScreenState();
}

class _MedicineStockPrivateBuyersScreenState
    extends State<MedicineStockPrivateBuyersScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final String? salesJson = await CompanyStore.instance.getString(
      'medicineSalesHistory',
    );
    List<Map<String, dynamic>> rows = [];
    if (salesJson != null) {
      try {
        final List<dynamic> rawSales = json.decode(salesJson);
        for (final sale in rawSales) {
          final List<dynamic> items = sale['items'] as List<dynamic>? ?? [];
          for (final item in items) {
            if (item['medicineId']?.toString() != widget.medicineId) continue;
            rows.add({
              'buyerName': sale['buyerName']?.toString() ?? '-',
              'mobile': sale['mobile']?.toString() ?? '',
              'date': sale['date']?.toString() ?? '',
              'qty': (item['qty'] as num?)?.toDouble() ?? 0.0,
              'unit': item['saleUnit']?.toString() ?? '',
              'totalSale': (item['totalSale'] as num?)?.toDouble() ?? 0.0,
            });
          }
        }
      } catch (_) {}
    }
    rows = rows
        .where((r) => _feedDateInRange(r['date']?.toString(), widget.dateRange))
        .toList();
    rows.sort(
      (a, b) =>
          (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()),
    );
    if (mounted) {
      setState(() {
        _rows = rows;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.teal.shade700,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          '🛒 ${widget.medicineName} — Private Buyers',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
          ? const Center(child: Text('Koi private buyer nahi.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _rows.length,
              itemBuilder: (context, i) {
                final r = _rows[i];
                final double qty = (r['qty'] as num?)?.toDouble() ?? 0.0;
                final String unit = r['unit']?.toString() ?? '';
                final double total =
                    (r['totalSale'] as num?)?.toDouble() ?? 0.0;
                final String date = formatHistoryDateTime(
                  r['date']?.toString(),
                );
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🛒 ${r['buyerName'] ?? '-'}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (date.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  date,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${qty.toStringAsFixed(2)} $unit',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '₹${total.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
