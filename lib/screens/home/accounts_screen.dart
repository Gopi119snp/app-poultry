import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:convert';
import '../../services/company_store.dart';
import 'purchase_expense_screen.dart'
    show
        formatHistoryDateTime,
        ensureFeedStockMigrated,
        kFeedTypeIds,
        kFeedTypeNames,
        kFeedTypeEmoji;
import 'sales_screen.dart'
    show
        ChicksPrivateSaleDetailScreen,
        FeedSaleDetailScreen,
        MedicineSaleDetailScreen;

// ═══════════════════════════════════════════════════════════════════════════
// 💼 ACCOUNTS SCREEN
// ═══════════════════════════════════════════════════════════════════════════

const Color _accGreen = Color(0xFF1B5E20);

String _cleanFarmerLabel(String raw) {
  if (raw.contains(' - ')) {
    return raw.split(' - ').first.trim();
  }
  return raw;
}

// ── Dynamic Date Filter Data Model ──────────────────────────────────────────
class AppDateFilter {
  final String label;
  final DateTime? start;
  final DateTime? end;
  final bool isAllTime;

  AppDateFilter({
    required this.label,
    this.start,
    this.end,
    this.isAllTime = false,
  });
}

// Global Filter Helper function
bool isDateInFilter(String? dateStr, AppDateFilter filter) {
  if (filter.isAllTime) return true;

  DateTime d = (dateStr != null && dateStr.isNotEmpty)
      ? (DateTime.tryParse(dateStr) ?? DateTime(2000))
      : DateTime(2000);

  if (filter.start != null && filter.end != null) {
    return d.isAfter(filter.start!.subtract(const Duration(seconds: 1))) &&
        d.isBefore(filter.end!.add(const Duration(days: 1)));
  }
  return false;
}

// ── Data models (internal use) ──────────────────────────────────────────────
class _DueItem {
  final String category;
  final String buyerName;
  final String mobile;
  final double totalAmount;
  final double paid;
  final double due;
  final DateTime? date;
  final String emoji;
  final Color color;
  final VoidCallback onTap;

  _DueItem({
    required this.category,
    required this.buyerName,
    required this.mobile,
    required this.totalAmount,
    required this.paid,
    required this.due,
    required this.date,
    required this.emoji,
    required this.color,
    required this.onTap,
  });
}

class _LedgerItem {
  final String category;
  final String title;
  final String subtitle;
  final double amount;
  final DateTime? date;
  final String emoji;
  final Color color;
  final String addedBy;

  _LedgerItem({
    required this.category,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.date,
    required this.emoji,
    required this.color,
    this.addedBy = '',
  });
}

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  List<_DueItem> _dues = [];
  List<_LedgerItem> _expenses = [];
  List<_LedgerItem> _purchases = [];

  List<Map<String, dynamic>> _rawChicksPurchases = [];
  List<Map<String, dynamic>> _rawFeedStock = [];
  List<Map<String, dynamic>> _rawMedicineStock = [];

  // ── FILTER STATE ──
  late AppDateFilter _selectedFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    final now = DateTime.now();
    _selectedFilter = AppDateFilter(
      label: 'Current Month',
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
    );

    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Filtered getters
  List<_DueItem> get _filteredDues => _dues
      .where((d) => isDateInFilter(d.date?.toIso8601String(), _selectedFilter))
      .toList();

  List<_LedgerItem> get _filteredExpenses => _expenses
      .where((e) => isDateInFilter(e.date?.toIso8601String(), _selectedFilter))
      .toList();

  List<_LedgerItem> get _filteredPurchases => _purchases
      .where((p) => isDateInFilter(p.date?.toIso8601String(), _selectedFilter))
      .toList();

  double get _totalDue => _filteredDues.fold(0.0, (s, d) => s + d.due);
  double get _totalExpense =>
      _filteredExpenses.fold(0.0, (s, e) => s + e.amount);
  double get _totalPurchase =>
      _filteredPurchases.fold(0.0, (s, p) => s + p.amount);

  DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);

    final List<_DueItem> dues = [];
    final List<_LedgerItem> expenses = [];
    final List<_LedgerItem> purchases = [];

    // 🐣 CHICKS
    final String? chicksJson = await CompanyStore.instance.getString(
      'chicksPurchaseHistory',
    );
    if (chicksJson != null) {
      try {
        final List<dynamic> rawChicks = json.decode(chicksJson);
        _rawChicksPurchases = rawChicks
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        for (final purchase in _rawChicksPurchases) {
          final String lotName = purchase['company']?.toString() ?? 'Lot';
          final double effRate =
              (purchase['effectiveRate'] as num?)?.toDouble() ??
              (purchase['rate'] as num?)?.toDouble() ??
              0.0;
          final double totalAmt =
              (purchase['totalAmount'] as num?)?.toDouble() ?? 0.0;

          purchases.add(
            _LedgerItem(
              category: 'Chicks',
              title: '🐣 $lotName',
              subtitle:
                  '${(purchase['quantity'] as num?)?.toStringAsFixed(0) ?? '0'} chicks',
              amount: totalAmt,
              date: _parseDate(purchase['date']?.toString()),
              emoji: '🐣',
              color: Colors.orange.shade800,
              addedBy: purchase['addedByName']?.toString() ?? '',
            ),
          );

          final List<dynamic> allocs =
              (purchase['allocations'] as List<dynamic>?) ?? [];
          for (final rawAlloc in allocs) {
            final Map<String, dynamic> alloc = Map<String, dynamic>.from(
              rawAlloc,
            );
            if (alloc['type'] != 'Private') continue;

            final double qty = (alloc['qty'] as num?)?.toDouble() ?? 0.0;
            final double rate = (alloc['rate'] as num?)?.toDouble() ?? 0.0;
            final double paid = (alloc['paid'] as num?)?.toDouble() ?? 0.0;
            final double total = qty * rate;
            final double due = (total - paid).clamp(0.0, double.infinity);
            if (due <= 0.01) continue;

            dues.add(
              _DueItem(
                category: 'Chicks',
                buyerName: alloc['name']?.toString() ?? '-',
                mobile: alloc['mobile']?.toString() ?? '',
                totalAmount: total,
                paid: paid,
                due: due,
                date: _parseDate(alloc['allocatedOn']?.toString()),
                emoji: '🐣',
                color: Colors.orange.shade800,
                onTap: () {
                  Get.to(
                    () => ChicksPrivateSaleDetailScreen(
                      alloc: alloc,
                      lotName: lotName,
                      purchaseEffectiveRate: effRate,
                    ),
                  );
                },
              ),
            );
          }
        }
      } catch (_) {}
    }

    // 🌾 FEED
    final String? feedSalesJson = await CompanyStore.instance.getString(
      'feedSalesHistory',
    );
    if (feedSalesJson != null) {
      try {
        final List<dynamic> rawSales = json.decode(feedSalesJson);
        for (final raw in rawSales) {
          final Map<String, dynamic> sale = Map<String, dynamic>.from(raw);
          final double due = (sale['dueAmount'] as num?)?.toDouble() ?? 0.0;
          if (due <= 0.01) continue;

          dues.add(
            _DueItem(
              category: 'Feed',
              buyerName: sale['buyerName']?.toString() ?? '-',
              mobile: sale['mobile']?.toString() ?? '',
              totalAmount: (sale['totalSaleAmount'] as num?)?.toDouble() ?? 0.0,
              paid: (sale['paidAmount'] as num?)?.toDouble() ?? 0.0,
              due: due,
              date: _parseDate(sale['date']?.toString()),
              emoji: '🌾',
              color: Colors.blue.shade700,
              onTap: () {
                Get.to(() => FeedSaleDetailScreen(sale: sale));
              },
            ),
          );
        }
      } catch (_) {}
    }

    try {
      _rawFeedStock = await ensureFeedStockMigrated();
      for (final feedType in _rawFeedStock) {
        final String id = feedType['id']?.toString() ?? '';
        final String name =
            feedType['name']?.toString() ?? kFeedTypeNames[id] ?? id;
        final String emoji = kFeedTypeEmoji[id] ?? '🌾';
        final List<dynamic> hist =
            (feedType['purchaseHistory'] as List<dynamic>?) ?? [];
        for (final rawH in hist) {
          final Map<String, dynamic> h = Map<String, dynamic>.from(rawH);
          final double bags = (h['bags'] as num?)?.toDouble() ?? 0.0;
          final double perBag = (h['perBagPrice'] as num?)?.toDouble() ?? 0.0;
          purchases.add(
            _LedgerItem(
              category: 'Feed',
              title: '$emoji $name — ${h['company'] ?? '-'}',
              subtitle:
                  '${bags.toStringAsFixed(0)} bag @ ₹${perBag.toStringAsFixed(2)}',
              amount: bags * perBag,
              date: _parseDate(h['date']?.toString()),
              emoji: emoji,
              color: Colors.blue.shade700,
              addedBy: h['addedByName']?.toString() ?? '',
            ),
          );
        }
      }
    } catch (_) {}

    // 💊 MEDICINE
    final String? medSalesJson = await CompanyStore.instance.getString(
      'medicineSalesHistory',
    );
    if (medSalesJson != null) {
      try {
        final List<dynamic> rawSales = json.decode(medSalesJson);
        for (final raw in rawSales) {
          final Map<String, dynamic> sale = Map<String, dynamic>.from(raw);
          final double due = (sale['dueAmount'] as num?)?.toDouble() ?? 0.0;
          if (due <= 0.01) continue;

          dues.add(
            _DueItem(
              category: 'Medicine',
              buyerName: sale['buyerName']?.toString() ?? '-',
              mobile: sale['mobile']?.toString() ?? '',
              totalAmount: (sale['totalSaleAmount'] as num?)?.toDouble() ?? 0.0,
              paid: (sale['paidAmount'] as num?)?.toDouble() ?? 0.0,
              due: due,
              date: _parseDate(sale['date']?.toString()),
              emoji: '💊',
              color: Colors.teal.shade700,
              onTap: () {
                Get.to(() => MedicineSaleDetailScreen(sale: sale));
              },
            ),
          );
        }
      } catch (_) {}
    }

    final String? medStockJson = await CompanyStore.instance.getString(
      'medicineStockList',
    );
    if (medStockJson != null) {
      try {
        final List<dynamic> rawMeds = json.decode(medStockJson);
        _rawMedicineStock = rawMeds
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        for (final med in _rawMedicineStock) {
          final String name = med['name']?.toString() ?? '-';
          final String unit = med['unit']?.toString() ?? '';
          final List<dynamic> hist =
              (med['purchaseHistory'] as List<dynamic>?) ?? [];
          for (final rawH in hist) {
            final Map<String, dynamic> h = Map<String, dynamic>.from(rawH);
            final double actualPrice =
                (h['actualPrice'] as num?)?.toDouble() ?? 0.0;
            final double qty = (h['qty'] as num?)?.toDouble() ?? 0.0;
            purchases.add(
              _LedgerItem(
                category: 'Medicine',
                title: '💊 $name',
                subtitle: '${qty.toStringAsFixed(2)} ${h['unit'] ?? unit}',
                amount: actualPrice,
                date: _parseDate(h['date']?.toString()),
                emoji: '💊',
                color: Colors.teal.shade700,
                addedBy: h['addedByName']?.toString() ?? '',
              ),
            );
          }
        }
      } catch (_) {}
    }

    // 👷 LABOUR + 📋 OTHER
    final String? labourJson = await CompanyStore.instance.getString(
      'labourExpenseHistory',
    );
    if (labourJson != null) {
      try {
        final List<dynamic> rawList = json.decode(labourJson);
        for (final raw in rawList) {
          final Map<String, dynamic> e = Map<String, dynamic>.from(raw);
          expenses.add(
            _LedgerItem(
              category: 'Labour',
              title: '👷 ${e['workerName'] ?? '-'}',
              subtitle: '${e['labourType'] ?? ''} • ${e['unitMode'] ?? ''}',
              amount: (e['totalAmount'] as num?)?.toDouble() ?? 0.0,
              date: _parseDate(e['date']?.toString()),
              emoji: '👷',
              color: Colors.orange.shade800,
              addedBy: e['addedByName']?.toString() ?? '',
            ),
          );
        }
      } catch (_) {}
    }

    final String? otherJson = await CompanyStore.instance.getString(
      'otherExpenseHistory',
    );
    if (otherJson != null) {
      try {
        final List<dynamic> rawList = json.decode(otherJson);
        for (final raw in rawList) {
          final Map<String, dynamic> e = Map<String, dynamic>.from(raw);
          expenses.add(
            _LedgerItem(
              category: 'Other',
              title: '📋 ${e['expenseType'] ?? '-'}',
              subtitle: (e['note']?.toString().isNotEmpty ?? false)
                  ? e['note'].toString()
                  : 'Koi note nahi',
              amount: (e['amount'] as num?)?.toDouble() ?? 0.0,
              date: _parseDate(e['date']?.toString()),
              emoji: '📋',
              color: Colors.purple.shade700,
              addedBy: e['addedByName']?.toString() ?? '',
            ),
          );
        }
      } catch (_) {}
    }

    // Sort
    dues.sort((a, b) => b.due.compareTo(a.due));
    expenses.sort(
      (a, b) => (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)),
    );
    purchases.sort(
      (a, b) => (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)),
    );

    if (mounted) {
      setState(() {
        _dues = dues;
        _expenses = expenses;
        _purchases = purchases;
        _isLoading = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🌟 NEW DYNAMIC FILTER SYSTEM: Sirf wahi dikhega jiska data exist karta hai
  // ═══════════════════════════════════════════════════════════════════════════

  /// Ye function app ka poora data scan karke sirf un mahino ki list nikalta
  /// hai jinka record tumne app me add kiya hai.
  List<DateTime> _getAvailableMonthsWithData() {
    Set<String> uniqueMonths = {};
    List<DateTime> result = [];

    void addDate(DateTime? d) {
      if (d != null) {
        // Year-Month ke format me unique key banate hain taaki ek mahina do baar na aaye
        String key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        if (!uniqueMonths.contains(key)) {
          uniqueMonths.add(key);
          result.add(DateTime(d.year, d.month, 1));
        }
      }
    }

    // Saare data se dates nikalna
    for (final d in _dues) addDate(d.date);
    for (final e in _expenses) addDate(e.date);
    for (final p in _purchases) addDate(p.date);

    // ✅ Current Month HAMESHA list me rahega (chahe entry zero hi kyun na ho)
    addDate(DateTime.now());

    // Naye mahine sabse upar dikhane ke liye sort (Descending)
    result.sort((a, b) => b.compareTo(a));
    return result;
  }

  void _showFilterBottomSheet() {
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
                  color: _accGreen,
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
                  setState(
                    () => _selectedFilter = AppDateFilter(
                      label: 'All Time',
                      isAllTime: true,
                    ),
                  );
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.calendar_today_rounded,
                  color: _accGreen,
                ),
                title: const Text(
                  'Current Month',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  final now = DateTime.now();
                  setState(
                    () => _selectedFilter = AppDateFilter(
                      label: 'Current Month',
                      start: DateTime(now.year, now.month, 1),
                      end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
                    ),
                  );
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.calendar_month_rounded,
                  color: _accGreen,
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
                leading: const Icon(Icons.date_range_rounded, color: _accGreen),
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
    // 🛠️ Yahan ab Hardcoded "24 Months" ki jagah hamara Naya Dynamic List aayega
    final List<DateTime> months = _getAvailableMonthsWithData();
    final List<String> monthNames = [
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
                      setState(() {
                        _selectedFilter = AppDateFilter(
                          label: label,
                          start: m,
                          end: DateTime(m.year, m.month + 1, 0, 23, 59, 59),
                        );
                      });
                      Navigator.pop(ctx);
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
    DateTime? minDate;

    void checkMin(DateTime? d) {
      if (d != null) {
        if (minDate == null || d.isBefore(minDate!)) {
          minDate = d;
        }
      }
    }

    // Check oldest date in all records
    for (final d in _dues) checkMin(d.date);
    for (final e in _expenses) checkMin(e.date);
    for (final p in _purchases) checkMin(p.date);

    // Agar app me bilkul data hi nahi hai, to default is mahine se shuru karo
    DateTime firstAllowedDate =
        minDate ?? DateTime(DateTime.now().year, DateTime.now().month, 1);

    // UI clean dikhane ke liye oldest record wale mahine ki 1 tareekh par lock kar do
    firstAllowedDate = DateTime(
      firstAllowedDate.year,
      firstAllowedDate.month,
      1,
    );

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate:
          firstAllowedDate, // ✅ FIX: Ab calendar galti se bhi isse pichhe nahi jayega
      lastDate: DateTime.now(), // Aaj tak ki date allow karo
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _accGreen,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        String startStr =
            '${picked.start.day}/${picked.start.month}/${picked.start.year}';
        String endStr =
            '${picked.end.day}/${picked.end.month}/${picked.end.year}';
        _selectedFilter = AppDateFilter(
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
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _accGreen,
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
            Text('💼', style: TextStyle(fontSize: 20)),
            SizedBox(width: 8),
            Text(
              'Accounts',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          // Filter Button in AppBar
          InkWell(
            onTap: _showFilterBottomSheet,
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
                    constraints: const BoxConstraints(maxWidth: 100),
                    child: Text(
                      _selectedFilter.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.white),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12.5,
          ),
          tabs: const [
            Tab(text: '📊 Overview'),
            Tab(text: '⏳ Udhaar'),
            Tab(text: '💸 Kharcha'),
            Tab(text: '🛒 Kharida'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _accGreen))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildDuesTab(),
                _buildLedgerTab(_filteredExpenses, 'Koi expense record nahi.'),
                _KharidaTabView(
                  selectedFilter: _selectedFilter,
                  chicksPurchases: _rawChicksPurchases,
                  feedStock: _rawFeedStock,
                  medicineStock: _rawMedicineStock,
                  onRefresh: _loadAll,
                ),
              ],
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 📊 OVERVIEW TAB
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildOverviewTab() {
    final double net = _totalDue - _totalExpense;

    Map<String, double> byCategory(List<_LedgerItem> items) {
      final Map<String, double> map = {};
      for (final i in items) {
        map[i.category] = (map[i.category] ?? 0.0) + i.amount;
      }
      return map;
    }

    final expByCat = byCategory(_filteredExpenses);
    final purByCat = byCategory(_filteredPurchases);

    Map<String, double> dueByCat = {};
    for (final d in _filteredDues) {
      dueByCat[d.category] = (dueByCat[d.category] ?? 0.0) + d.due;
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      color: _accGreen,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F3D12),
                  Color(0xFF1B5E20),
                  Color(0xFF2E7D32),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _accGreen.withOpacity(0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Company Ka Pura Hisaab',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _ovKpi('⏳ Udhaar Aana', _totalDue, Colors.orange.shade200),
                    const SizedBox(width: 8),
                    _ovKpi('💸 Kharcha', _totalExpense, Colors.red.shade200),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _ovKpi('🛒 Kharida', _totalPurchase, Colors.blue.shade100),
                    const SizedBox(width: 8),
                    _ovKpi(
                      net >= 0
                          ? '📈 Net (Udhaar−Kharcha)'
                          : '📉 Net (Udhaar−Kharcha)',
                      net,
                      net >= 0
                          ? Colors.greenAccent.shade100
                          : Colors.red.shade200,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            '⏳ Udhaar — Category Wise',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (dueByCat.isEmpty)
            _emptyCatCard('Koi udhaar pending nahi 🎉')
          else
            ...dueByCat.entries.map(
              (e) => _catRow(
                _emojiFor(e.key),
                e.key,
                e.value,
                Colors.orange.shade700,
              ),
            ),

          const SizedBox(height: 20),
          const Text(
            '💸 Kharcha — Category Wise',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (expByCat.isEmpty)
            _emptyCatCard('Koi expense record nahi.')
          else
            ...expByCat.entries.map(
              (e) => _catRow(
                _emojiFor(e.key),
                e.key,
                e.value,
                Colors.red.shade700,
              ),
            ),

          const SizedBox(height: 20),
          const Text(
            '🛒 Kharida — Category Wise',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (purByCat.isEmpty)
            _emptyCatCard('Koi purchase record nahi.')
          else
            ...purByCat.entries.map(
              (e) => _catRow(
                _emojiFor(e.key),
                e.key,
                e.value,
                Colors.blue.shade700,
              ),
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _emojiFor(String category) {
    switch (category) {
      case 'Chicks':
        return '🐣';
      case 'Feed':
        return '🌾';
      case 'Medicine':
        return '💊';
      case 'Labour':
        return '👷';
      case 'Other':
        return '📋';
      default:
        return '📦';
    }
  }

  Widget _ovKpi(String label, double value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
            const SizedBox(height: 4),
            Text(
              '₹${value.toStringAsFixed(0)}',
              style: TextStyle(
                color: valueColor,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catRow(String emoji, String label, double amount, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCatCard(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        msg,
        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ⏳ UDHAAR (DUES) TAB
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildDuesTab() {
    final filteredDues = _filteredDues;
    if (filteredDues.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadAll,
        color: _accGreen,
        child: ListView(
          children: [
            SizedBox(
              height: 400,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('🎉', style: TextStyle(fontSize: 52)),
                    const SizedBox(height: 12),
                    Text(
                      'Koi Udhaar Pending Nahi!',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      color: _accGreen,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filteredDues.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Udhaar (${filteredDues.length} buyers)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.orange.shade900,
                    ),
                  ),
                  Text(
                    '₹${_totalDue.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ],
              ),
            );
          }
          final d = filteredDues[index - 1];
          return _dueCard(d);
        },
      ),
    );
  }

  Widget _dueCard(_DueItem d) {
    return GestureDetector(
      onTap: d.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: d.color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: d.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(d.emoji, style: const TextStyle(fontSize: 20)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _cleanFarmerLabel(d.buyerName),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: d.color.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          d.category,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: d.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bill: ₹${d.totalAmount.toStringAsFixed(0)}  •  Paid: ₹${d.paid.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                  if (d.date != null)
                    Text(
                      formatHistoryDateTime(d.date!.toIso8601String()),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black45,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${d.due.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 💸 GENERIC LEDGER TAB
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildLedgerTab(List<_LedgerItem> items, String emptyMsg) {
    final double total = items.fold(0.0, (s, i) => s + i.amount);

    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadAll,
        color: _accGreen,
        child: ListView(
          children: [
            SizedBox(
              height: 400,
              child: Center(
                child: Text(
                  emptyMsg,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      color: _accGreen,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _accGreen.withOpacity(0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _accGreen.withOpacity(0.25)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total (${items.length} entries)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: _accGreen,
                    ),
                  ),
                  Text(
                    '₹${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: _accGreen,
                    ),
                  ),
                ],
              ),
            );
          }
          final e = items[index - 1];
          return _ledgerCard(e);
        },
      ),
    );
  }

  Widget _ledgerCard(_LedgerItem e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: e.color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: e.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(e.emoji, style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  e.subtitle,
                  style: const TextStyle(fontSize: 11.5, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (e.addedBy.isNotEmpty)
                      Expanded(
                        child: Text(
                          '👤 ${e.addedBy}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black45,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (e.date != null)
                      Text(
                        formatHistoryDateTime(e.date!.toIso8601String()),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black45,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '₹${e.amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: e.color,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🛒 KHARIDA TAB
// ═══════════════════════════════════════════════════════════════════════════

class _KharidaTabView extends StatelessWidget {
  final AppDateFilter selectedFilter;
  final List<Map<String, dynamic>> chicksPurchases;
  final List<Map<String, dynamic>> feedStock;
  final List<Map<String, dynamic>> medicineStock;
  final Future<void> Function() onRefresh;

  const _KharidaTabView({
    required this.selectedFilter,
    required this.chicksPurchases,
    required this.feedStock,
    required this.medicineStock,
    required this.onRefresh,
  });

  List<Map<String, dynamic>> get _chicksInPeriod {
    return chicksPurchases
        .where((p) => isDateInFilter(p['date']?.toString(), selectedFilter))
        .toList();
  }

  Map<String, double> get _feedTotalsInPeriod {
    double bags = 0, amount = 0;
    int count = 0;
    for (final feedType in feedStock) {
      final hist = (feedType['purchaseHistory'] as List?) ?? [];
      for (final rawH in hist) {
        final h = Map<String, dynamic>.from(rawH);
        if (!isDateInFilter(h['date']?.toString(), selectedFilter)) continue;
        final double b = (h['bags'] as num?)?.toDouble() ?? 0.0;
        final double perBag = (h['perBagPrice'] as num?)?.toDouble() ?? 0.0;
        bags += b;
        amount += b * perBag;
        count++;
      }
    }
    return {'bags': bags, 'amount': amount, 'count': count.toDouble()};
  }

  Map<String, double> get _medicineTotalsInPeriod {
    double amount = 0;
    int count = 0;
    for (final med in medicineStock) {
      final hist = (med['purchaseHistory'] as List?) ?? [];
      for (final rawH in hist) {
        final h = Map<String, dynamic>.from(rawH);
        if (!isDateInFilter(h['date']?.toString(), selectedFilter)) continue;
        amount += (h['actualPrice'] as num?)?.toDouble() ?? 0.0;
        count++;
      }
    }
    return {'amount': amount, 'count': count.toDouble()};
  }

  @override
  Widget build(BuildContext context) {
    final chicksList = _chicksInPeriod;
    final double chicksQty = chicksList.fold(
      0.0,
      (s, p) => s + ((p['quantity'] as num?)?.toDouble() ?? 0.0),
    );
    final double chicksAmt = chicksList.fold(
      0.0,
      (s, p) => s + ((p['totalAmount'] as num?)?.toDouble() ?? 0.0),
    );

    final feedTotals = _feedTotalsInPeriod;
    final medTotals = _medicineTotalsInPeriod;

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: _accGreen,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _accGreen.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _accGreen.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.filter_alt_rounded, color: _accGreen),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Filter: ${selectedFilter.label}',
                    style: const TextStyle(
                      color: _accGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          _kharidaSectionCard(
            emoji: '🐣',
            title: 'Chicks',
            subtitle:
                '${chicksList.length} purchase${chicksList.length == 1 ? '' : 's'} • ${chicksQty.toStringAsFixed(0)} pcs',
            amount: chicksAmt,
            color: Colors.orange.shade800,
            onTap: () {
              Get.to(
                () => ChicksMonthlyPurchaseListScreen(
                  selectedFilter: selectedFilter,
                  purchases: chicksList,
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          _kharidaSectionCard(
            emoji: '🌾',
            title: 'Feed',
            subtitle:
                '${feedTotals['count']!.toStringAsFixed(0)} purchases • ${feedTotals['bags']!.toStringAsFixed(0)} bag',
            amount: feedTotals['amount']!,
            color: Colors.blue.shade700,
            onTap: () {
              Get.to(
                () => FeedTypesOverviewScreen(
                  selectedFilter: selectedFilter,
                  feedStock: feedStock,
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          _kharidaSectionCard(
            emoji: '💊',
            title: 'Medicine',
            subtitle: '${medTotals['count']!.toStringAsFixed(0)} purchases',
            amount: medTotals['amount']!,
            color: Colors.teal.shade700,
            onTap: () {
              Get.to(
                () => MedicineOverviewScreen(
                  selectedFilter: selectedFilter,
                  medicineStock: medicineStock,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _kharidaSectionCard({
    required String emoji,
    required String title,
    required String subtitle,
    required double amount,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.25)),
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
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 3),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${amount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                  size: 20,
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
// 🐣 CHICKS MONTHLY PURCHASE LIST
// ═══════════════════════════════════════════════════════════════════════════
class ChicksMonthlyPurchaseListScreen extends StatelessWidget {
  final AppDateFilter selectedFilter;
  final List<Map<String, dynamic>> purchases;

  const ChicksMonthlyPurchaseListScreen({
    super.key,
    required this.selectedFilter,
    required this.purchases,
  });

  @override
  Widget build(BuildContext context) {
    final double totalQty = purchases.fold(
      0.0,
      (s, p) => s + ((p['quantity'] as num?)?.toDouble() ?? 0.0),
    );
    final double totalAmt = purchases.fold(
      0.0,
      (s, p) => s + ((p['totalAmount'] as num?)?.toDouble() ?? 0.0),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.orange.shade800,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          '🐣 Chicks — ${selectedFilter.label}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: purchases.isEmpty
          ? Center(
              child: Text(
                'Is period mein koi chicks purchase nahi hui.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: purchases.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${purchases.length} Lots • ${totalQty.toStringAsFixed(0)} pcs',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                            color: Colors.orange.shade900,
                          ),
                        ),
                        Text(
                          '₹${totalAmt.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final p = purchases[index - 1];
                final double qty = (p['quantity'] as num?)?.toDouble() ?? 0.0;
                final double amt =
                    (p['totalAmount'] as num?)?.toDouble() ?? 0.0;
                return GestureDetector(
                  onTap: () {
                    Get.to(
                      () => ChicksLotAllocationBreakdownScreen(purchase: p),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p['company']?.toString() ?? 'Lot',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Breed: ${p['breed'] ?? '-'} • ${qty.toStringAsFixed(0)} pcs',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.black54,
                                ),
                              ),
                              Text(
                                formatHistoryDateTime(p['date']?.toString()),
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.black45,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹${amt.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.orange.shade900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: Colors.grey.shade400,
                            ),
                          ],
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
// 🐣 CHICKS LOT ALLOCATION BREAKDOWN
// ═══════════════════════════════════════════════════════════════════════════
class ChicksLotAllocationBreakdownScreen extends StatelessWidget {
  final Map<String, dynamic> purchase;
  const ChicksLotAllocationBreakdownScreen({super.key, required this.purchase});

  @override
  Widget build(BuildContext context) {
    final String lotName = purchase['company']?.toString() ?? 'Lot';
    final double totalQty = (purchase['quantity'] as num?)?.toDouble() ?? 0.0;
    final double totalAmt =
        (purchase['totalAmount'] as num?)?.toDouble() ?? 0.0;

    final List<dynamic> allocationsRaw =
        (purchase['allocations'] as List<dynamic>?) ?? [];
    final List<Map<String, dynamic>> allocations = allocationsRaw
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final companyAllocs = allocations
        .where((a) => a['type'] == 'Company')
        .toList();
    final privateAllocs = allocations
        .where((a) => a['type'] == 'Private')
        .toList();

    double companyQty = 0, companyAmt = 0;
    for (final a in companyAllocs) {
      final q = (a['qty'] as num?)?.toDouble() ?? 0.0;
      final r = (a['rate'] as num?)?.toDouble() ?? 0.0;
      companyQty += q;
      companyAmt += q * r;
    }

    double privateQty = 0, privateAmt = 0;
    for (final a in privateAllocs) {
      final q = (a['qty'] as num?)?.toDouble() ?? 0.0;
      final r = (a['rate'] as num?)?.toDouble() ?? 0.0;
      privateQty += q;
      privateAmt += q * r;
    }

    final double pendingQty = (totalQty - companyQty - privateQty).clamp(
      0.0,
      double.infinity,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.orange.shade800,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          '📦 $lotName',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade800,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Kharida: ${totalQty.toStringAsFixed(0)} pcs',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${totalAmt.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _breakdownSummaryCard(
            emoji: '🏢',
            title: 'Company Farmers Ko Gaya',
            qty: companyQty,
            amount: companyAmt,
            color: Colors.blue.shade700,
          ),
          const SizedBox(height: 12),

          _breakdownSummaryCard(
            emoji: '🛒',
            title: 'Private Mein Becha',
            qty: privateQty,
            amount: privateAmt,
            color: Colors.green.shade700,
          ),

          if (pendingQty > 0.01) ...[
            const SizedBox(height: 12),
            _breakdownSummaryCard(
              emoji: '⏳',
              title: 'Abhi Bhi Pending (Allocate Nahi Hua)',
              qty: pendingQty,
              amount: 0,
              color: Colors.grey.shade600,
              showAmount: false,
            ),
          ],

          const SizedBox(height: 24),

          if (companyAllocs.isNotEmpty) ...[
            const Text(
              '🏢 Farmer-Wise List',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ...companyAllocs.map(
              (a) => _allocListTile(
                name: a['name']?.toString() ?? '-',
                qty: (a['qty'] as num?)?.toDouble() ?? 0.0,
                rate: (a['rate'] as num?)?.toDouble() ?? 0.0,
                color: Colors.blue.shade700,
              ),
            ),
            const SizedBox(height: 20),
          ],

          if (privateAllocs.isNotEmpty) ...[
            const Text(
              '🛒 Private Buyer-Wise List',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ...privateAllocs.map(
              (a) => _allocListTile(
                name: a['name']?.toString() ?? '-',
                qty: (a['qty'] as num?)?.toDouble() ?? 0.0,
                rate: (a['rate'] as num?)?.toDouble() ?? 0.0,
                color: Colors.green.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _breakdownSummaryCard({
    required String emoji,
    required String title,
    required double qty,
    required double amount,
    required Color color,
    bool showAmount = true,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${qty.toStringAsFixed(0)} pcs',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          if (showAmount)
            Text(
              '₹${amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
        ],
      ),
    );
  }

  Widget _allocListTile({
    required String name,
    required double qty,
    required double rate,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _cleanFarmerLabel(name),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${qty.toStringAsFixed(0)} pcs',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            '₹${(qty * rate).toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🌾 FEED TYPES OVERVIEW
// ═══════════════════════════════════════════════════════════════════════════
class FeedTypesOverviewScreen extends StatelessWidget {
  final AppDateFilter selectedFilter;
  final List<Map<String, dynamic>> feedStock;

  const FeedTypesOverviewScreen({
    super.key,
    required this.selectedFilter,
    required this.feedStock,
  });

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
          '🌾 Feed — ${selectedFilter.label}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: kFeedTypeIds.map((id) {
          final Map<String, dynamic> typeData = feedStock.firstWhere(
            (s) => s['id'] == id,
            orElse: () => <String, dynamic>{},
          );
          final String name = kFeedTypeNames[id] ?? id;
          final String emoji = kFeedTypeEmoji[id] ?? '🌾';

          final List<dynamic> hist =
              (typeData['purchaseHistory'] as List?) ?? [];
          double bags = 0, amount = 0;
          int count = 0;
          for (final rawH in hist) {
            final h = Map<String, dynamic>.from(rawH);
            if (!isDateInFilter(h['date']?.toString(), selectedFilter))
              continue;
            final double b = (h['bags'] as num?)?.toDouble() ?? 0.0;
            final double perBag = (h['perBagPrice'] as num?)?.toDouble() ?? 0.0;
            bags += b;
            amount += b * perBag;
            count++;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: () {
                Get.to(
                  () => FeedTypeMonthlyDetailScreen(
                    selectedFilter: selectedFilter,
                    feedTypeData: typeData,
                    typeId: id,
                    typeName: name,
                    emoji: emoji,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.shade200),
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
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$count purchases • ${bags.toStringAsFixed(0)} bag',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${amount.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey.shade400,
                          size: 20,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🌾 FEED TYPE MONTHLY DETAIL
// ═══════════════════════════════════════════════════════════════════════════
class FeedTypeMonthlyDetailScreen extends StatelessWidget {
  final AppDateFilter selectedFilter;
  final Map<String, dynamic> feedTypeData;
  final String typeId;
  final String typeName;
  final String emoji;

  const FeedTypeMonthlyDetailScreen({
    super.key,
    required this.selectedFilter,
    required this.feedTypeData,
    required this.typeId,
    required this.typeName,
    required this.emoji,
  });

  @override
  Widget build(BuildContext context) {
    // ── Purchase History ──
    final List<dynamic> histRaw =
        (feedTypeData['purchaseHistory'] as List?) ?? [];
    final List<Map<String, dynamic>> purchases = histRaw
        .map((e) => Map<String, dynamic>.from(e))
        .where((h) => isDateInFilter(h['date']?.toString(), selectedFilter))
        .toList();

    double totalBags = 0, totalAmount = 0;
    for (final h in purchases) {
      final double b = (h['bags'] as num?)?.toDouble() ?? 0.0;
      final double perBag = (h['perBagPrice'] as num?)?.toDouble() ?? 0.0;
      totalBags += b;
      totalAmount += b * perBag;
    }

    // ── Company Farmer allocations ──
    final List<dynamic> allocRaw = (feedTypeData['allocations'] as List?) ?? [];
    final List<Map<String, dynamic>> allocs = allocRaw
        .map((e) => Map<String, dynamic>.from(e))
        .where(
          (a) => isDateInFilter(a['allocatedOn']?.toString(), selectedFilter),
        )
        .toList();

    double allocQty = 0, allocAmt = 0;
    for (final a in allocs) {
      final double q = (a['qty'] as num?)?.toDouble() ?? 0.0;
      final double r = (a['rate'] as num?)?.toDouble() ?? 0.0;
      allocQty += q;
      allocAmt += q * r;
    }

    // ── Private Sales ──
    final List<dynamic> saleRaw = (feedTypeData['privateSales'] as List?) ?? [];
    final List<Map<String, dynamic>> sales = saleRaw
        .map((e) => Map<String, dynamic>.from(e))
        .where((s) => isDateInFilter(s['date']?.toString(), selectedFilter))
        .toList();

    double saleQty = 0, saleAmt = 0;
    for (final s in sales) {
      final double q = (s['qty'] as num?)?.toDouble() ?? 0.0;
      final double r = (s['rate'] as num?)?.toDouble() ?? 0.0;
      saleQty += q;
      saleAmt += q * r;
    }

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
          '$emoji $typeName — ${selectedFilter.label}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade700,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Kharida (${purchases.length} purchase${purchases.length == 1 ? '' : 's'})',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '${totalBags.toStringAsFixed(0)} Bag  •  ₹${totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _feedBreakdownCard(
            emoji: '🏢',
            title: 'Company Farmers Ko Diya',
            qty: allocQty,
            amount: allocAmt,
            color: Colors.blue.shade700,
          ),
          const SizedBox(height: 12),
          _feedBreakdownCard(
            emoji: '🛒',
            title: 'Private Mein Becha',
            qty: saleQty,
            amount: saleAmt,
            color: Colors.green.shade700,
          ),
          const SizedBox(height: 24),

          const Text(
            '📜 Purchase History',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (purchases.isEmpty)
            _emptyMsg('Is period mein koi purchase nahi hui.')
          else
            ...purchases.map((h) {
              final double b = (h['bags'] as num?)?.toDouble() ?? 0.0;
              final double perBag =
                  (h['perBagPrice'] as num?)?.toDouble() ?? 0.0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            h['company']?.toString() ?? '-',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '${b.toStringAsFixed(0)} bag @ ₹${perBag.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Colors.black54,
                            ),
                          ),
                          Text(
                            formatHistoryDateTime(h['date']?.toString()),
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₹${(b * perBag).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 20),

          if (allocs.isNotEmpty) ...[
            const Text(
              '🏢 Farmer-Wise List',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ...allocs.map(
              (a) => _feedAllocTile(
                name: a['farmerName']?.toString() ?? '-',
                qty: (a['qty'] as num?)?.toDouble() ?? 0.0,
                rate: (a['rate'] as num?)?.toDouble() ?? 0.0,
                color: Colors.blue.shade700,
              ),
            ),
            const SizedBox(height: 20),
          ],

          if (sales.isNotEmpty) ...[
            const Text(
              '🛒 Private Buyer-Wise List',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ...sales.map(
              (s) => _feedAllocTile(
                name: s['buyerName']?.toString() ?? '-',
                qty: (s['qty'] as num?)?.toDouble() ?? 0.0,
                rate: (s['rate'] as num?)?.toDouble() ?? 0.0,
                color: Colors.green.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _feedBreakdownCard({
    required String emoji,
    required String title,
    required double qty,
    required double amount,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${qty.toStringAsFixed(0)} Bag',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _feedAllocTile({
    required String name,
    required double qty,
    required double rate,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _cleanFarmerLabel(name),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${qty.toStringAsFixed(0)} bag',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            '₹${(qty * rate).toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyMsg(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        msg,
        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 💊 MEDICINE OVERVIEW SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class MedicineOverviewScreen extends StatelessWidget {
  final AppDateFilter selectedFilter;
  final List<Map<String, dynamic>> medicineStock;

  const MedicineOverviewScreen({
    super.key,
    required this.selectedFilter,
    required this.medicineStock,
  });

  @override
  Widget build(BuildContext context) {
    final List<Map<String, Object>> filtered = [];
    for (final med in medicineStock) {
      final List<dynamic> hist = (med['purchaseHistory'] as List?) ?? [];
      double qtyBase = 0, amount = 0;
      int count = 0;
      for (final rawH in hist) {
        final h = Map<String, dynamic>.from(rawH);
        if (!isDateInFilter(h['date']?.toString(), selectedFilter)) continue;
        final double qBase =
            (h['qtyInBaseUnit'] as num?)?.toDouble() ??
            (h['qty'] as num?)?.toDouble() ??
            0.0;
        final double price = (h['actualPrice'] as num?)?.toDouble() ?? 0.0;
        qtyBase += qBase;
        amount += price;
        count++;
      }
      if (count == 0) continue;
      filtered.add({
        'med': med,
        'qtyBase': qtyBase,
        'amount': amount,
        'count': count,
      });
    }
    filtered.sort(
      (a, b) => (b['amount'] as double).compareTo(a['amount'] as double),
    );

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
          '💊 Medicine — ${selectedFilter.label}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: filtered.isEmpty
          ? Center(
              child: Text(
                'Is period mein koi medicine purchase nahi hui.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final row = filtered[index];
                final Map<String, dynamic> med =
                    row['med'] as Map<String, dynamic>;
                final double qtyBase = row['qtyBase'] as double;
                final double amount = row['amount'] as double;
                final int count = row['count'] as int;
                final String name = med['name']?.toString() ?? '-';
                final String baseUnit = med['unit']?.toString() ?? '';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: GestureDetector(
                    onTap: () {
                      Get.to(
                        () => MedicineMonthlyDetailScreen(
                          selectedFilter: selectedFilter,
                          medicineData: med,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.teal.shade200),
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
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Center(
                              child: Text('💊', style: TextStyle(fontSize: 24)),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '$count purchase${count == 1 ? '' : 's'} • ${qtyBase.toStringAsFixed(2)} $baseUnit',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₹${amount.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal.shade700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.grey.shade400,
                                size: 20,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 💊 MEDICINE MONTHLY DETAIL SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class MedicineMonthlyDetailScreen extends StatefulWidget {
  final AppDateFilter selectedFilter;
  final Map<String, dynamic> medicineData;

  const MedicineMonthlyDetailScreen({
    super.key,
    required this.selectedFilter,
    required this.medicineData,
  });

  @override
  State<MedicineMonthlyDetailScreen> createState() =>
      _MedicineMonthlyDetailScreenState();
}

class _MedicineMonthlyDetailScreenState
    extends State<MedicineMonthlyDetailScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _privateSales = [];

  @override
  void initState() {
    super.initState();
    _loadPrivateSales();
  }

  Future<void> _loadPrivateSales() async {
    final String mId = widget.medicineData['id']?.toString() ?? '';
    final String? salesJson = await CompanyStore.instance.getString(
      'medicineSalesHistory',
    );

    List<Map<String, dynamic>> salesList = [];
    if (salesJson != null) {
      try {
        final List<dynamic> rawSales = json.decode(salesJson);
        for (final sale in rawSales) {
          if (!isDateInFilter(sale['date']?.toString(), widget.selectedFilter))
            continue;

          final List<dynamic> items = sale['items'] as List<dynamic>? ?? [];
          for (final item in items) {
            if (item['medicineId']?.toString() == mId) {
              salesList.add({
                'buyerName': sale['buyerName'] ?? '-',
                'date': sale['date'],
                'qtyInBaseUnit':
                    (item['qtyInBaseUnit'] as num?)?.toDouble() ??
                    (item['qty'] as num?)?.toDouble() ??
                    0.0,
                'totalSale': (item['totalSale'] as num?)?.toDouble() ?? 0.0,
              });
            }
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _privateSales = salesList;
        _isLoading = false;
      });
    }
  }

  double _allocRatePerBase(Map<String, dynamic> alloc) {
    final double? ratePerBase = (alloc['ratePerBase'] as num?)?.toDouble();
    if (ratePerBase != null && ratePerBase > 0) return ratePerBase;
    return (alloc['rate'] as num?)?.toDouble() ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.teal)),
      );
    }

    final String name = widget.medicineData['name']?.toString() ?? '-';
    final String baseUnit = widget.medicineData['unit']?.toString() ?? '';

    // ── Purchase History ──
    final List<dynamic> histRaw =
        (widget.medicineData['purchaseHistory'] as List?) ?? [];
    final List<Map<String, dynamic>> purchases = histRaw
        .map((e) => Map<String, dynamic>.from(e))
        .where(
          (h) => isDateInFilter(h['date']?.toString(), widget.selectedFilter),
        )
        .toList();

    double totalPurchasedBase = 0, totalAmount = 0;
    for (final h in purchases) {
      totalPurchasedBase +=
          (h['qtyInBaseUnit'] as num?)?.toDouble() ??
          (h['qty'] as num?)?.toDouble() ??
          0.0;
      totalAmount += (h['actualPrice'] as num?)?.toDouble() ?? 0.0;
    }

    // ── Company Farmer allocations ──
    final List<dynamic> allocRaw =
        (widget.medicineData['allocations'] as List?) ?? [];
    final List<Map<String, dynamic>> allocs = allocRaw
        .map((e) => Map<String, dynamic>.from(e))
        .where(
          (a) => isDateInFilter(
            a['allocatedOn']?.toString(),
            widget.selectedFilter,
          ),
        )
        .toList();

    double allocQtyBase = 0, allocAmt = 0;
    for (final a in allocs) {
      final double qBase =
          (a['qtyInBaseUnit'] as num?)?.toDouble() ??
          (a['qty'] as num?)?.toDouble() ??
          0.0;
      final double rBase = _allocRatePerBase(a);
      allocQtyBase += qBase;
      allocAmt += qBase * rBase;
    }

    // ── Private Sales ──
    double saleQtyBase = 0, saleAmt = 0;
    for (final s in _privateSales) {
      saleQtyBase += (s['qtyInBaseUnit'] as num?)?.toDouble() ?? 0.0;
      saleAmt += (s['totalSale'] as num?)?.toDouble() ?? 0.0;
    }

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
          '💊 $name — ${widget.selectedFilter.label}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.teal.shade700,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Kharida (${purchases.length} purchase${purchases.length == 1 ? '' : 's'})',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '${totalPurchasedBase.toStringAsFixed(2)} $baseUnit  •  ₹${totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _medBreakdownCard(
            emoji: '🏢',
            title: 'Company Farmers Ko Diya',
            qty: allocQtyBase,
            unit: baseUnit,
            amount: allocAmt,
            color: Colors.teal.shade700,
          ),
          const SizedBox(height: 12),
          _medBreakdownCard(
            emoji: '🛒',
            title: 'Private Mein Becha',
            qty: saleQtyBase,
            unit: baseUnit,
            amount: saleAmt,
            color: Colors.green.shade700,
          ),
          const SizedBox(height: 24),

          const Text(
            '📜 Purchase History',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (purchases.isEmpty)
            _emptyMsg('Is period mein koi purchase nahi hui.')
          else
            ...purchases.map((h) {
              final double qb =
                  (h['qtyInBaseUnit'] as num?)?.toDouble() ??
                  (h['qty'] as num?)?.toDouble() ??
                  0.0;
              final double actPrice =
                  (h['actualPrice'] as num?)?.toDouble() ?? 0.0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.teal.shade100),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${qb.toStringAsFixed(2)} $baseUnit',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            formatHistoryDateTime(h['date']?.toString()),
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₹${actPrice.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade800,
                      ),
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 20),

          if (allocs.isNotEmpty) ...[
            const Text(
              '🏢 Farmer-Wise List',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ...allocs.map(
              (a) => _medAllocTile(
                name: a['farmerName']?.toString() ?? '-',
                qty:
                    (a['qtyInBaseUnit'] as num?)?.toDouble() ??
                    (a['qty'] as num?)?.toDouble() ??
                    0.0,
                unit: baseUnit,
                amount:
                    ((a['qtyInBaseUnit'] as num?)?.toDouble() ??
                        (a['qty'] as num?)?.toDouble() ??
                        0.0) *
                    _allocRatePerBase(a),
                color: Colors.teal.shade700,
              ),
            ),
            const SizedBox(height: 20),
          ],

          if (_privateSales.isNotEmpty) ...[
            const Text(
              '🛒 Private Buyer-Wise List',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ..._privateSales.map(
              (s) => _medAllocTile(
                name: s['buyerName']?.toString() ?? '-',
                qty: (s['qtyInBaseUnit'] as num?)?.toDouble() ?? 0.0,
                unit: baseUnit,
                amount: (s['totalSale'] as num?)?.toDouble() ?? 0.0,
                color: Colors.green.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _medBreakdownCard({
    required String emoji,
    required String title,
    required double qty,
    required String unit,
    required double amount,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${qty.toStringAsFixed(2)} $unit',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _medAllocTile({
    required String name,
    required double qty,
    required String unit,
    required double amount,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _cleanFarmerLabel(name),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${qty.toStringAsFixed(2)} $unit',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            '₹${amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyMsg(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        msg,
        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }
}
