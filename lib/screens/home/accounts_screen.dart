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
// 💼 ACCOUNTS SCREEN — Company ka poora paisa hisaab ek jagah:
// 1. Overview     — sab kuch ek nazar mein
// 2. Udhaar       — private buyers (Chicks/Feed/Medicine) jinka payment baki
// 3. Kharcha      — Labour + Other expense
// 4. Kharida      — Chicks + Feed + Medicine purchase cost (month-wise)
// ═══════════════════════════════════════════════════════════════════════════

const Color _accGreen = Color(0xFF1B5E20);

/// Farmer dropdown se select karte waqt "Naam - Mobile - Jagah" jaisa poora
/// string kabhi kabhi farmerName field mein save ho jaata hai (galti se).
/// Display ke liye sirf naam nikaal lo — purane aur naye dono data ke liye
/// safe hai.
String _cleanFarmerLabel(String raw) {
  if (raw.contains(' - ')) {
    return raw.split(' - ').first.trim();
  }
  return raw;
}

// ── Data models (internal use) ──────────────────────────────────────────────
class _DueItem {
  final String category; // Chicks / Feed / Medicine
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

  double get _totalDue => _dues.fold(0.0, (s, d) => s + d.due);
  double get _totalExpense => _expenses.fold(0.0, (s, e) => s + e.amount);
  double get _totalPurchase => _purchases.fold(0.0, (s, p) => s + p.amount);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);

    final List<_DueItem> dues = [];
    final List<_LedgerItem> expenses = [];
    final List<_LedgerItem> purchases = [];

    // ═══════════════════════════════════════════════════════════════════
    // 🐣 CHICKS — Private allocations ka due + Purchase cost
    // ═══════════════════════════════════════════════════════════════════
    final String? chicksJson = await CompanyStore.instance.getString(
      'chicksPurchaseHistory',
    );
    if (chicksJson != null) {
      try {
        final List<dynamic> rawChicks = json.decode(chicksJson);
        for (final raw in rawChicks) {
          final Map<String, dynamic> purchase = Map<String, dynamic>.from(raw);
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

    // ═══════════════════════════════════════════════════════════════════
    // 🌾 FEED — Private sales ka due (feedSalesHistory) + Purchase cost
    // (per-type feedStockList se, taaki Purchase History jaisa hi total ho)
    // ═══════════════════════════════════════════════════════════════════
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
      final List<Map<String, dynamic>> feedStock =
          await ensureFeedStockMigrated();
      for (final feedType in feedStock) {
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

    // ═══════════════════════════════════════════════════════════════════
    // 💊 MEDICINE — Private sales ka due (medicineSalesHistory) + Purchase
    // ═══════════════════════════════════════════════════════════════════
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
        for (final rawMed in rawMeds) {
          final Map<String, dynamic> med = Map<String, dynamic>.from(rawMed);
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

    // ═══════════════════════════════════════════════════════════════════
    // 👷 LABOUR + 📋 OTHER — Company expenses
    // ═══════════════════════════════════════════════════════════════════
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

    // ── Sort ──
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
                _buildLedgerTab(_expenses, 'Koi expense record nahi.'),
                const _KharidaTabView(),
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

    final expByCat = byCategory(_expenses);
    final purByCat = byCategory(_purchases);

    Map<String, double> dueByCat = {};
    for (final d in _dues) {
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
    if (_dues.isEmpty) {
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
        itemCount: _dues.length + 1,
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
                    'Total Udhaar (${_dues.length} buyers)',
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
          final d = _dues[index - 1];
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
  // 💸 GENERIC LEDGER TAB (Kharcha use karta hai)
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
// 🛒 KHARIDA TAB — Month-wise (ya Last-N-Months) Purchase Overview
// 3 sections: Chicks / Feed / Medicine. Chicks aur Feed poori tarah kaam
// karte hain (drill-down list + allocation split). Medicine abhi placeholder.
// ═══════════════════════════════════════════════════════════════════════════

class _PurchasePeriod {
  final bool isRange;
  final int year;
  final int month; // 1-12 (single mode)
  final int rangeMonths; // (range mode)

  const _PurchasePeriod.single(this.year, this.month)
    : isRange = false,
      rangeMonths = 1;

  const _PurchasePeriod.range(this.rangeMonths)
    : isRange = true,
      year = 0,
      month = 0;

  String label() {
    if (!isRange) return '${_monthName(month)} $year';
    return 'Last $rangeMonths Mahine';
  }
}

const List<String> _kMonthNames = [
  '',
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _monthName(int m) => _kMonthNames[m];

DateTimeRange _computePurchaseRange(_PurchasePeriod p) {
  final now = DateTime.now();
  if (!p.isRange) {
    final start = DateTime(p.year, p.month, 1);
    final end = DateTime(p.year, p.month + 1, 1);
    return DateTimeRange(start: start, end: end);
  }
  int totalMonthsBack = p.rangeMonths - 1;
  int startMonth = now.month - totalMonthsBack;
  int startYear = now.year;
  while (startMonth <= 0) {
    startMonth += 12;
    startYear -= 1;
  }
  final start = DateTime(startYear, startMonth, 1);
  final end = DateTime(now.year, now.month + 1, 1);
  return DateTimeRange(start: start, end: end);
}

bool _dateInRange(String? isoStr, DateTimeRange range) {
  if (isoStr == null || isoStr.isEmpty) return false;
  final dt = DateTime.tryParse(isoStr);
  if (dt == null) return false;
  return !dt.isBefore(range.start) && dt.isBefore(range.end);
}

class _KharidaTabView extends StatefulWidget {
  const _KharidaTabView();

  @override
  State<_KharidaTabView> createState() => _KharidaTabViewState();
}

class _KharidaTabViewState extends State<_KharidaTabView> {
  bool _isLoading = true;

  List<Map<String, dynamic>> _allChicksPurchases = [];
  List<Map<String, dynamic>> _feedStock = [];
  List<Map<String, dynamic>> _medicineStock = [];

  late _PurchasePeriod _period;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _period = _PurchasePeriod.single(now.year, now.month);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    List<Map<String, dynamic>> chicks = [];
    final String? chicksJson = await CompanyStore.instance.getString(
      'chicksPurchaseHistory',
    );
    if (chicksJson != null) {
      try {
        final List<dynamic> raw = json.decode(chicksJson);
        chicks = raw.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }

    List<Map<String, dynamic>> feedStock = [];
    try {
      feedStock = await ensureFeedStockMigrated();
    } catch (_) {}

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

    if (mounted) {
      setState(() {
        _allChicksPurchases = chicks;
        _feedStock = feedStock;
        _medicineStock = medStock;
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _chicksInPeriod {
    final range = _computePurchaseRange(_period);
    return _allChicksPurchases
        .where((p) => _dateInRange(p['date']?.toString(), range))
        .toList();
  }

  Map<String, double> get _feedTotalsInPeriod {
    final range = _computePurchaseRange(_period);
    double bags = 0, amount = 0;
    int count = 0;
    for (final feedType in _feedStock) {
      final hist = (feedType['purchaseHistory'] as List?) ?? [];
      for (final rawH in hist) {
        final h = Map<String, dynamic>.from(rawH);
        if (!_dateInRange(h['date']?.toString(), range)) continue;
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
    final range = _computePurchaseRange(_period);
    double amount = 0;
    int count = 0;
    for (final med in _medicineStock) {
      final hist = (med['purchaseHistory'] as List?) ?? [];
      for (final rawH in hist) {
        final h = Map<String, dynamic>.from(rawH);
        if (!_dateInRange(h['date']?.toString(), range)) continue;
        amount += (h['actualPrice'] as num?)?.toDouble() ?? 0.0;
        count++;
      }
    }
    return {'amount': amount, 'count': count.toDouble()};
  }

  void _openPeriodPicker() async {
    final now = DateTime.now();
    final List<_PurchasePeriod> monthOptions = List.generate(24, (i) {
      int m = now.month - i;
      int y = now.year;
      while (m <= 0) {
        m += 12;
        y -= 1;
      }
      return _PurchasePeriod.single(y, m);
    });

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.75,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    color: _accGreen,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Period Chuniye',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Last N Mahine (Max 2 Saal)',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [2, 3, 5, 6, 12, 24].map((n) {
                  return ActionChip(
                    label: Text('Last $n'),
                    backgroundColor: _accGreen.withOpacity(0.08),
                    labelStyle: const TextStyle(
                      color: _accGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    onPressed: () {
                      setState(() => _period = _PurchasePeriod.range(n));
                      Navigator.pop(ctx);
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Ek Mahina Chuniye',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: monthOptions.length,
                itemBuilder: (c, i) {
                  final opt = monthOptions[i];
                  final bool isSelected =
                      !_period.isRange &&
                      _period.year == opt.year &&
                      _period.month == opt.month;
                  return ListTile(
                    dense: true,
                    title: Text(
                      opt.label(),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected ? _accGreen : Colors.black87,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: _accGreen,
                            size: 20,
                          )
                        : null,
                    onTap: () {
                      setState(() => _period = opt);
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _accGreen));
    }

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
      onRefresh: _loadData,
      color: _accGreen,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GestureDetector(
            onTap: _openPeriodPicker,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _accGreen,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _accGreen.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _period.label(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_drop_down_rounded,
                    color: Colors.white,
                  ),
                ],
              ),
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
                  periodLabel: _period.label(),
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
                  periodLabel: _period.label(),
                  period: _period,
                  feedStock: _feedStock,
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
              Get.snackbar(
                'Jald Aayega 🚧',
                'Medicine ka detailed view abhi kaam ho raha hai.',
                backgroundColor: Colors.teal.shade700,
                colorText: Colors.white,
                snackPosition: SnackPosition.BOTTOM,
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
// 🐣 CHICKS MONTHLY PURCHASE LIST — Us period ke saare chicks lots
// ═══════════════════════════════════════════════════════════════════════════
class ChicksMonthlyPurchaseListScreen extends StatelessWidget {
  final String periodLabel;
  final List<Map<String, dynamic>> purchases;

  const ChicksMonthlyPurchaseListScreen({
    super.key,
    required this.periodLabel,
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
          '🐣 Chicks — $periodLabel',
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
// 🐣 CHICKS LOT ALLOCATION BREAKDOWN — Ek lot ka Company-Farmer vs
// Private-Sale split (total qty + total amount dono jagah)
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
// 🌾 FEED TYPES OVERVIEW — 3 alag section (Starter/Grower/Finisher), har ek
// ka us period mein kitna purchase hua wo dikhata hai
// ═══════════════════════════════════════════════════════════════════════════
class FeedTypesOverviewScreen extends StatelessWidget {
  final String periodLabel;
  final _PurchasePeriod period;
  final List<Map<String, dynamic>> feedStock;

  const FeedTypesOverviewScreen({
    super.key,
    required this.periodLabel,
    required this.period,
    required this.feedStock,
  });

  @override
  Widget build(BuildContext context) {
    final range = _computePurchaseRange(period);

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
          '🌾 Feed — $periodLabel',
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
            if (!_dateInRange(h['date']?.toString(), range)) continue;
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
                    periodLabel: periodLabel,
                    period: period,
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
// 🌾 FEED TYPE MONTHLY DETAIL — Us period mein: Purchase History list +
// Company Farmer allocation vs Private Sale ka split (qty + amount + list)
// ═══════════════════════════════════════════════════════════════════════════
class FeedTypeMonthlyDetailScreen extends StatelessWidget {
  final String periodLabel;
  final _PurchasePeriod period;
  final Map<String, dynamic> feedTypeData;
  final String typeId;
  final String typeName;
  final String emoji;

  const FeedTypeMonthlyDetailScreen({
    super.key,
    required this.periodLabel,
    required this.period,
    required this.feedTypeData,
    required this.typeId,
    required this.typeName,
    required this.emoji,
  });

  @override
  Widget build(BuildContext context) {
    final range = _computePurchaseRange(period);

    // ── Purchase History (period filtered) ──
    final List<dynamic> histRaw =
        (feedTypeData['purchaseHistory'] as List?) ?? [];
    final List<Map<String, dynamic>> purchases = histRaw
        .map((e) => Map<String, dynamic>.from(e))
        .where((h) => _dateInRange(h['date']?.toString(), range))
        .toList();
    double totalBags = 0, totalAmount = 0;
    for (final h in purchases) {
      final double b = (h['bags'] as num?)?.toDouble() ?? 0.0;
      final double perBag = (h['perBagPrice'] as num?)?.toDouble() ?? 0.0;
      totalBags += b;
      totalAmount += b * perBag;
    }

    // ── Company Farmer allocations (period filtered by allocatedOn) ──
    final List<dynamic> allocRaw = (feedTypeData['allocations'] as List?) ?? [];
    final List<Map<String, dynamic>> allocs = allocRaw
        .map((e) => Map<String, dynamic>.from(e))
        .where((a) => _dateInRange(a['allocatedOn']?.toString(), range))
        .toList();
    double allocQty = 0, allocAmt = 0;
    for (final a in allocs) {
      final double q = (a['qty'] as num?)?.toDouble() ?? 0.0;
      final double r = (a['rate'] as num?)?.toDouble() ?? 0.0;
      allocQty += q;
      allocAmt += q * r;
    }

    // ── Private Sales (period filtered by date) ──
    final List<dynamic> saleRaw = (feedTypeData['privateSales'] as List?) ?? [];
    final List<Map<String, dynamic>> sales = saleRaw
        .map((e) => Map<String, dynamic>.from(e))
        .where((s) => _dateInRange(s['date']?.toString(), range))
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
          '$emoji $typeName — $periodLabel',
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
          // ── Total purchased header ──
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

          // ── Allocation summary cards ──
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

          // ── Purchase entries list ──
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

          // ── Farmer-wise list ──
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

          // ── Buyer-wise list ──
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
