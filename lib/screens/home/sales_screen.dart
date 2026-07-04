import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'dart:convert';
import 'package:poultrypro/services/company_store.dart';
import 'package:poultrypro/services/session_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 💰 SALES SCREEN — 4 Categories: Chicks, Feed, Medicine, Chicken
// ═══════════════════════════════════════════════════════════════════════════
class SalesScreen extends StatelessWidget {
  final Future<void> Function() onChicksSaleTap;
  final Future<void> Function() onFeedSaleTap;
  final Future<void> Function() onMedicineSaleTap;
  final Future<void> Function() onChickenSaleTap;

  const SalesScreen({
    super.key,
    required this.onChicksSaleTap,
    required this.onFeedSaleTap,
    required this.onMedicineSaleTap,
    required this.onChickenSaleTap,
  });

  static const Color primaryGreen = Color(0xFF1B5E20);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: primaryGreen,
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
            Text('💰', style: TextStyle(fontSize: 20)),
            SizedBox(width: 8),
            Text(
              'Sales / Bikri',
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
                color: primaryGreen,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kya becha aaj?',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Category select karein',
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
                    'Categories',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _SalesCategoryCard(
                          emoji: '🐣',
                          label: 'Chicks',
                          subtitle: 'Bacha becha',
                          bgColor: Colors.yellow.shade50,
                          borderColor: Colors.yellow.shade300,
                          iconBg: Colors.yellow.shade200,
                          textColor: Colors.orange.shade900,
                          badgeText: 'Chick Sale',
                          onTap: () => Get.to(() => const ChicksSalesView()),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _SalesCategoryCard(
                          emoji: '🌾',
                          label: 'Feed',
                          subtitle: 'Feed becha',
                          bgColor: Colors.blue.shade50,
                          borderColor: Colors.blue.shade200,
                          iconBg: Colors.blue.shade100,
                          textColor: Colors.blue.shade800,
                          badgeText: 'Feed Sale',
                          onTap: () =>
                              Get.to(() => const FeedSalesHistoryScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _SalesCategoryCard(
                          emoji: '💊',
                          label: 'Medicine',
                          subtitle: 'Dawai, Tika becha',
                          bgColor: Colors.teal.shade50,
                          borderColor: Colors.teal.shade200,
                          iconBg: Colors.teal.shade100,
                          textColor: Colors.teal.shade800,
                          badgeText: 'Medicine Sale',
                          onTap: () =>
                              Get.to(() => const MedicineSalesHistoryScreen()),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _SalesCategoryCard(
                          emoji: '🍗',
                          label: 'Chicken',
                          subtitle: 'Market mein becha',
                          bgColor: Colors.red.shade50,
                          borderColor: Colors.red.shade200,
                          iconBg: Colors.red.shade100,
                          textColor: Colors.red.shade800,
                          badgeText: 'Market Sale',
                          onTap: () {},
                        ),
                      ),
                    ],
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

// ═══════════════════════════════════════════════════════════════════════════
// 🐣 CHICKS SALES VIEW — Same chicksPurchaseHistory data, read-only
// ═══════════════════════════════════════════════════════════════════════════
class ChicksSalesView extends StatefulWidget {
  const ChicksSalesView({super.key});

  @override
  State<ChicksSalesView> createState() => _ChicksSalesViewState();
}

class _ChicksSalesViewState extends State<ChicksSalesView> {
  List<Map<String, dynamic>> _purchaseEntries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final String? jsonStr = await CompanyStore.instance.getString(
      'chicksPurchaseHistory',
    );
    if (jsonStr != null) {
      try {
        final List<dynamic> raw = json.decode(jsonStr);
        _purchaseEntries = raw
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (_) {}
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
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
        title: const Row(
          children: [
            Text('🐣', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text(
              'Chicks Sales',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _purchaseEntries.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🐣', style: TextStyle(fontSize: 52)),
                  const SizedBox(height: 12),
                  Text(
                    'Koi chicks purchase record nahi.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _purchaseEntries.length,
              itemBuilder: (context, index) {
                return _ChicksSalesLotCard(entry: _purchaseEntries[index]);
              },
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 📦 CHICKS SALES LOT CARD
// ═══════════════════════════════════════════════════════════════════════════
class _ChicksSalesLotCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _ChicksSalesLotCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final String lotName = entry['company']?.toString() ?? 'Lot';
    final double totalQty = (entry['quantity'] as num?)?.toDouble() ?? 0.0;
    final double totalAmount =
        (entry['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final double purchaseRate = (entry['rate'] as num?)?.toDouble() ?? 0.0;
    final double effectiveRate =
        (entry['effectiveRate'] as num?)?.toDouble() ?? purchaseRate;
    final String date = entry['date']?.toString() ?? '';

    final List<dynamic> allocationsRaw =
        (entry['allocations'] as List<dynamic>?) ?? [];
    final List<Map<String, dynamic>> allAllocations = allocationsRaw
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final List<Map<String, dynamic>> privateAllocations = allAllocations
        .where((a) => a['type'] == 'Private')
        .toList();
    final List<Map<String, dynamic>> companyAllocations = allAllocations
        .where((a) => a['type'] == 'Company')
        .toList();

    final double companyTotal = companyAllocations.fold(
      0.0,
      (sum, a) => sum + ((a['qty'] as num?)?.toDouble() ?? 0.0),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── LOT HEADER ──
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
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
                        '📦 Lot: $lotName',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.orange.shade900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Total: ${totalQty.toStringAsFixed(0)} Chicks',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      if (date.isNotEmpty)
                        Text(
                          '🕒 ${_formatDT(date)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black45,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '₹${totalAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.orange.shade900,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 🛒 PRIVATE SALES ──
                if (privateAllocations.isNotEmpty) ...[
                  Row(
                    children: [
                      const Text('🛒 ', style: TextStyle(fontSize: 14)),
                      Text(
                        'Private Sale',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...privateAllocations.map((alloc) {
                    final double qty =
                        (alloc['qty'] as num?)?.toDouble() ?? 0.0;
                    final double rate =
                        (alloc['rate'] as num?)?.toDouble() ?? 0.0;
                    final double paid =
                        (alloc['paid'] as num?)?.toDouble() ?? 0.0;
                    final double total = qty * rate;
                    final double due = (total - paid).clamp(
                      0.0,
                      double.infinity,
                    );

                    return GestureDetector(
                      onTap: () => Get.to(
                        () => ChicksPrivateSaleDetailScreen(
                          alloc: alloc,
                          lotName: lotName,
                          purchaseEffectiveRate: effectiveRate,
                        ),
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    alloc['name']?.toString() ?? '-',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.green.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${qty.toStringAsFixed(0)} Chicks  •  ₹${rate.toStringAsFixed(2)}/chick',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Total: ₹${total.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: due > 0
                                        ? Colors.red.shade100
                                        : Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    due > 0
                                        ? 'Due: ₹${due.toStringAsFixed(0)}'
                                        : '✅ Paid',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: due > 0
                                          ? Colors.red.shade900
                                          : Colors.green.shade900,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
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
                  }),
                  const SizedBox(height: 10),
                ],

                if (privateAllocations.isEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      '🛒 Koi private sale nahi abhi tak',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // ── 🏢 COMPANY FARMERS — tap karo → farmer list ──
                if (companyTotal > 0)
                  GestureDetector(
                    onTap: () => Get.to(
                      () => CompanyFarmerAllocationListScreen(
                        lotName: lotName,
                        companyAllocations: companyAllocations,
                      ),
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Text('🏢 ', style: TextStyle(fontSize: 14)),
                              Text(
                                'Company Farmers: ',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                              Text(
                                '${companyTotal.toStringAsFixed(0)} Chicks',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                            ],
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Colors.blue.shade400,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🏢 COMPANY FARMER ALLOCATION LIST SCREEN
// Tap karne par — jis jis farmer ko diya gaya, unki list
// ═══════════════════════════════════════════════════════════════════════════
class CompanyFarmerAllocationListScreen extends StatelessWidget {
  final String lotName;
  final List<Map<String, dynamic>> companyAllocations;

  const CompanyFarmerAllocationListScreen({
    super.key,
    required this.lotName,
    required this.companyAllocations,
  });

  @override
  Widget build(BuildContext context) {
    final double grandTotal = companyAllocations.fold(
      0.0,
      (sum, a) => sum + ((a['qty'] as num?)?.toDouble() ?? 0.0),
    );

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
        title: Row(
          children: [
            const Text('🏢', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Company Farmers — $lotName',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Total banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            color: Colors.blue.shade700,
            child: Text(
              'Total Company Allocation: ${grandTotal.toStringAsFixed(0)} Chicks',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),

          Expanded(
            child: companyAllocations.isEmpty
                ? Center(
                    child: Text(
                      'Koi company farmer allocation nahi.',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: companyAllocations.length,
                    itemBuilder: (context, index) {
                      final alloc = companyAllocations[index];
                      final double qty =
                          (alloc['qty'] as num?)?.toDouble() ?? 0.0;
                      final String name = alloc['name']?.toString() ?? '-';
                      final String allocatedBy =
                          alloc['allocatedByName']?.toString() ?? '';
                      final String allocatedByRole =
                          alloc['allocatedByRole']?.toString() ?? '';
                      final String allocatedOn = _formatDT(
                        alloc['allocatedOn']?.toString(),
                      );

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade100),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Farmer avatar
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Center(
                                child: Text(
                                  '🧑',
                                  style: TextStyle(fontSize: 20),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.blue.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${qty.toStringAsFixed(0)} Chicks allocated',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  if (allocatedBy.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      '👤 ${allocatedByRole.isNotEmpty ? "$allocatedByRole: " : ""}$allocatedBy',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                  if (allocatedOn.isNotEmpty &&
                                      allocatedOn != '-') ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      '🕒 $allocatedOn',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // Qty badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Text(
                                '${qty.toStringAsFixed(0)}\nChicks',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 📋 CHICKS PRIVATE SALE DETAIL SCREEN — Read Only + Profit/Loss
// ═══════════════════════════════════════════════════════════════════════════
class ChicksPrivateSaleDetailScreen extends StatelessWidget {
  final Map<String, dynamic> alloc;
  final String lotName;
  final double purchaseEffectiveRate; // Purchase ka actual cost per chick

  const ChicksPrivateSaleDetailScreen({
    super.key,
    required this.alloc,
    required this.lotName,
    required this.purchaseEffectiveRate,
  });

  @override
  Widget build(BuildContext context) {
    final double qty = (alloc['qty'] as num?)?.toDouble() ?? 0.0;
    final double saleRate = (alloc['rate'] as num?)?.toDouble() ?? 0.0;
    final double paid = (alloc['paid'] as num?)?.toDouble() ?? 0.0;
    final double saleTotal = qty * saleRate;
    final double due = (saleTotal - paid).clamp(0.0, double.infinity);

    // ── Profit / Loss calculation ──
    final double costTotal = qty * purchaseEffectiveRate;
    final double profitLoss = saleTotal - costTotal;
    final bool isProfit = profitLoss >= 0;

    final String buyerName = alloc['name']?.toString() ?? '-';
    final String mobile = alloc['mobile']?.toString() ?? '-';
    final String addedByName = alloc['allocatedByName']?.toString() ?? '';
    final String addedByRole = alloc['allocatedByRole']?.toString() ?? '';
    final String dateTime = _formatDT(alloc['allocatedOn']?.toString());

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.green.shade700,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: const Row(
          children: [
            Text('🛒', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text(
              'Private Sale Detail',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Lot badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '📦 Lot: $lotName',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade900,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Main Detail Card ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.shade200),
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
                  // Buyer naam
                  Text(
                    buyerName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade900,
                    ),
                  ),
                  if (mobile.isNotEmpty && mobile != '-')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '📞 $mobile',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 16),

                  _detailRow('Quantity', '${qty.toStringAsFixed(0)} Chicks'),
                  _detailRow(
                    'Sale Rate',
                    '₹${saleRate.toStringAsFixed(2)} / chick',
                  ),
                  _detailRow(
                    'Purchase Rate',
                    '₹${purchaseEffectiveRate.toStringAsFixed(2)} / chick',
                  ),
                  _detailRow(
                    'Total Amount',
                    '₹${saleTotal.toStringAsFixed(2)}',
                  ),
                  _detailRow('Paid', '₹${paid.toStringAsFixed(2)}'),

                  const SizedBox(height: 12),

                  // Due
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: due > 0
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: due > 0
                            ? Colors.red.shade300
                            : Colors.green.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          due > 0 ? '⏳ Baki (Due)' : '✅ Fully Paid',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: due > 0
                                ? Colors.red.shade800
                                : Colors.green.shade800,
                          ),
                        ),
                        Text(
                          due > 0 ? '₹${due.toStringAsFixed(2)}' : '₹0.00',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: due > 0
                                ? Colors.red.shade800
                                : Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── PROFIT / LOSS ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isProfit
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isProfit
                            ? Colors.green.shade400
                            : Colors.red.shade400,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isProfit ? '📈 Profit' : '📉 Loss',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: isProfit
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                              ),
                            ),
                            Text(
                              '${isProfit ? '+' : '-'}₹${profitLoss.abs().toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: isProfit
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Sale: ₹${saleRate.toStringAsFixed(2)}/chick  −  Cost: ₹${purchaseEffectiveRate.toStringAsFixed(2)}/chick  =  ${isProfit ? '+' : '-'}₹${(saleRate - purchaseEffectiveRate).abs().toStringAsFixed(2)}/chick',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),

                  if (addedByName.isNotEmpty)
                    _detailRow(
                      '👤 Added By',
                      addedByRole.isNotEmpty
                          ? '$addedByRole: $addedByName'
                          : addedByName,
                    ),
                  _detailRow('🕒 Date & Time', dateTime),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Payment placeholder
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_clock_rounded,
                    color: Colors.grey.shade400,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Payment feature jald aayega',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🌾 FEED SALES HISTORY SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class FeedSalesHistoryScreen extends StatefulWidget {
  const FeedSalesHistoryScreen({super.key});

  @override
  State<FeedSalesHistoryScreen> createState() => _FeedSalesHistoryScreenState();
}

class _FeedSalesHistoryScreenState extends State<FeedSalesHistoryScreen> {
  List<Map<String, dynamic>> _feedSales = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    setState(() => _isLoading = true);
    final String? jsonStr = await CompanyStore.instance.getString(
      'feedSalesHistory',
    );
    if (jsonStr != null) {
      try {
        final List<dynamic> raw = json.decode(jsonStr);
        _feedSales = raw.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }
    if (mounted) setState(() => _isLoading = false);
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
        title: const Row(
          children: [
            Text('🌾', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text(
              'Feed Sales',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await Get.to(() => const AddPrivateFeedSaleScreen());
                  _loadSales();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade800,
                ),
                icon: const Icon(
                  Icons.add_shopping_cart_rounded,
                  color: Colors.white,
                ),
                label: const Text(
                  'Private Feed Sale',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _feedSales.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('🌾', style: TextStyle(fontSize: 52)),
                        const SizedBox(height: 12),
                        Text(
                          'Koi feed sale record nahi.',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _feedSales.length,
                    itemBuilder: (context, index) {
                      final sale = _feedSales[index];
                      return _FeedSaleCard(sale: sale, onRefresh: _loadSales);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FeedSaleCard extends StatelessWidget {
  final Map<String, dynamic> sale;
  final VoidCallback onRefresh;
  const _FeedSaleCard({required this.sale, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final double totalSale =
        (sale['totalSaleAmount'] as num?)?.toDouble() ?? 0.0;
    final double due = (sale['dueAmount'] as num?)?.toDouble() ?? 0.0;
    final double profit = (sale['profitAmount'] as num?)?.toDouble() ?? 0.0;
    final bool isProfit = profit >= 0;

    // S/G/F bags sold
    final double sQty = (sale['starter']?['qty'] as num?)?.toDouble() ?? 0.0;
    final double gQty = (sale['grower']?['qty'] as num?)?.toDouble() ?? 0.0;
    final double fQty = (sale['finisher']?['qty'] as num?)?.toDouble() ?? 0.0;
    final String sUnit = sale['starter']?['unit']?.toString() ?? 'Bag';
    final String gUnit = sale['grower']?['unit']?.toString() ?? 'Bag';
    final String fUnit = sale['finisher']?['unit']?.toString() ?? 'Bag';

    final String addedByName = sale['addedByName']?.toString() ?? '';
    final String addedByRole = sale['addedByRole']?.toString() ?? '';

    return GestureDetector(
      onTap: () async {
        final result = await Get.to(() => FeedSaleDetailScreen(sale: sale));
        if (result == true) onRefresh();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.blue.shade200, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Buyer + Amount ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '🛒 ${sale['buyerName'] ?? 'Unknown'}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        '₹${totalSale.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey.shade400,
                        size: 18,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // ── Lot ──
              Text(
                'Lot: ${sale['lotName'] ?? '-'}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),

              // ── S/G/F bags ──
              const SizedBox(height: 4),
              Text(
                'S: ${sQty.toStringAsFixed(0)} $sUnit  |  G: ${gQty.toStringAsFixed(0)} $gUnit  |  F: ${fQty.toStringAsFixed(0)} $fUnit',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),

              // ── Added By ──
              if (addedByName.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  '👤 ${addedByRole.isNotEmpty ? '$addedByRole: ' : ''}$addedByName',
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ],

              Text(
                '🕒 ${_formatDT(sale['date']?.toString())}',
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
              const SizedBox(height: 10),

              // ── Badges ──
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: due > 0
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: due > 0
                            ? Colors.red.shade200
                            : Colors.green.shade200,
                      ),
                    ),
                    child: Text(
                      due > 0 ? 'Due: ₹${due.toStringAsFixed(0)}' : '✅ Paid',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: due > 0
                            ? Colors.red.shade900
                            : Colors.green.shade900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isProfit
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isProfit
                            ? Colors.green.shade200
                            : Colors.red.shade200,
                      ),
                    ),
                    child: Text(
                      '${isProfit ? '📈' : '📉'} ₹${profit.abs().toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isProfit
                            ? Colors.green.shade900
                            : Colors.red.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 📝 ADD PRIVATE FEED SALE SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class AddPrivateFeedSaleScreen extends StatefulWidget {
  final Map<String, dynamic>? existingSale;
  const AddPrivateFeedSaleScreen({super.key, this.existingSale});

  @override
  State<AddPrivateFeedSaleScreen> createState() =>
      _AddPrivateFeedSaleScreenState(existingSale: existingSale);
}

class _AddPrivateFeedSaleScreenState extends State<AddPrivateFeedSaleScreen> {
  List<Map<String, dynamic>> _purchaseLots = [];
  Map<String, dynamic>? _selectedLot;
  // Available bags after deducting sales (per lot)
  Map<String, Map<String, double>> _availableBags = {}; // lotCompany -> {S,G,F}

  final _buyerNameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _paidCtrl = TextEditingController();

  final _starterQtyCtrl = TextEditingController();
  final _starterRateCtrl = TextEditingController();
  String _starterUnit = 'Bag';

  final _growerQtyCtrl = TextEditingController();
  final _growerRateCtrl = TextEditingController();
  String _growerUnit = 'Bag';

  final _finisherQtyCtrl = TextEditingController();
  final _finisherRateCtrl = TextEditingController();
  String _finisherUnit = 'Bag';

  // Edit mode support
  final bool _isEditMode;
  final Map<String, dynamic>? _existingSale;

  _AddPrivateFeedSaleScreenState({Map<String, dynamic>? existingSale})
    : _isEditMode = existingSale != null,
      _existingSale = existingSale;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // Load purchase lots
    final String? purchaseJson = await CompanyStore.instance.getString(
      'feedPurchaseHistory',
    );
    List<Map<String, dynamic>> lots = [];
    if (purchaseJson != null) {
      try {
        final List<dynamic> raw = json.decode(purchaseJson);
        lots = raw.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }

    // Load existing sales to calculate sold bags per lot
    final String? salesJson = await CompanyStore.instance.getString(
      'feedSalesHistory',
    );
    List<Map<String, dynamic>> sales = [];
    if (salesJson != null) {
      try {
        final List<dynamic> raw = json.decode(salesJson);
        sales = raw.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }

    // Calculate sold bags per lot (excluding current sale in edit mode)
    Map<String, Map<String, double>> soldPerLot = {};
    for (final sale in sales) {
      // Skip the sale being edited
      if (_isEditMode && sale['id'] == _existingSale!['id']) continue;
      final String lotName = sale['lotName']?.toString() ?? '';
      soldPerLot[lotName] ??= {'S': 0, 'G': 0, 'F': 0};
      soldPerLot[lotName]!['S'] =
          (soldPerLot[lotName]!['S'] ?? 0) +
          ((sale['starter']?['qty'] as num?)?.toDouble() ?? 0);
      soldPerLot[lotName]!['G'] =
          (soldPerLot[lotName]!['G'] ?? 0) +
          ((sale['grower']?['qty'] as num?)?.toDouble() ?? 0);
      soldPerLot[lotName]!['F'] =
          (soldPerLot[lotName]!['F'] ?? 0) +
          ((sale['finisher']?['qty'] as num?)?.toDouble() ?? 0);
    }

    // Calculate available = purchased - sold
    Map<String, Map<String, double>> available = {};
    for (final lot in lots) {
      final String lotName = lot['company']?.toString() ?? '';
      final double purchasedS =
          (lot['starter']?['bags'] as num?)?.toDouble() ?? 0;
      final double purchasedG =
          (lot['grower']?['bags'] as num?)?.toDouble() ?? 0;
      final double purchasedF =
          (lot['finisher']?['bags'] as num?)?.toDouble() ?? 0;
      final double soldS = soldPerLot[lotName]?['S'] ?? 0;
      final double soldG = soldPerLot[lotName]?['G'] ?? 0;
      final double soldF = soldPerLot[lotName]?['F'] ?? 0;
      available[lotName] = {
        'S': (purchasedS - soldS).clamp(0.0, double.infinity),
        'G': (purchasedG - soldG).clamp(0.0, double.infinity),
        'F': (purchasedF - soldF).clamp(0.0, double.infinity),
      };
    }

    setState(() {
      _purchaseLots = lots;
      _availableBags = available;

      // Edit mode: pre-fill fields
      if (_isEditMode && _existingSale != null) {
        _buyerNameCtrl.text = _existingSale!['buyerName']?.toString() ?? '';
        _mobileCtrl.text = _existingSale!['mobile']?.toString() ?? '';
        _paidCtrl.text =
            (_existingSale!['paidAmount'] as num?)?.toString() ?? '0';
        _starterQtyCtrl.text =
            (_existingSale!['starter']?['qty'] as num?)?.toString() ?? '0';
        _starterRateCtrl.text =
            (_existingSale!['starter']?['saleRate'] as num?)?.toString() ?? '0';
        _starterUnit = _existingSale!['starter']?['unit']?.toString() ?? 'Bag';
        _growerQtyCtrl.text =
            (_existingSale!['grower']?['qty'] as num?)?.toString() ?? '0';
        _growerRateCtrl.text =
            (_existingSale!['grower']?['saleRate'] as num?)?.toString() ?? '0';
        _growerUnit = _existingSale!['grower']?['unit']?.toString() ?? 'Bag';
        _finisherQtyCtrl.text =
            (_existingSale!['finisher']?['qty'] as num?)?.toString() ?? '0';
        _finisherRateCtrl.text =
            (_existingSale!['finisher']?['saleRate'] as num?)?.toString() ??
            '0';
        _finisherUnit =
            _existingSale!['finisher']?['unit']?.toString() ?? 'Bag';

        // Select the lot matching existing sale
        final String existingLotName =
            _existingSale!['lotName']?.toString() ?? '';
        try {
          _selectedLot = lots.firstWhere(
            (l) => (l['company']?.toString() ?? '') == existingLotName,
          );
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _buyerNameCtrl.dispose();
    _mobileCtrl.dispose();
    _paidCtrl.dispose();
    _starterQtyCtrl.dispose();
    _starterRateCtrl.dispose();
    _growerQtyCtrl.dispose();
    _growerRateCtrl.dispose();
    _finisherQtyCtrl.dispose();
    _finisherRateCtrl.dispose();
    super.dispose();
  }

  Map<String, double> _calculateFinancials() {
    if (_selectedLot == null)
      return {'totalSale': 0, 'totalCost': 0, 'profit': 0, 'due': 0};

    double bagWeight = (_selectedLot!['bagWeight'] as num?)?.toDouble() ?? 50.0;

    double getCost(
      TextEditingController qtyC,
      String unit,
      Map<String, dynamic>? lotData,
    ) {
      double qty = double.tryParse(qtyC.text) ?? 0.0;
      double pRatePerBag = (lotData?['perBagPrice'] as num?)?.toDouble() ?? 0.0;
      double pRate = unit == 'Kg' ? (pRatePerBag / bagWeight) : pRatePerBag;
      return qty * pRate;
    }

    double getSale(TextEditingController qtyC, TextEditingController rateC) {
      double qty = double.tryParse(qtyC.text) ?? 0.0;
      double sRate = double.tryParse(rateC.text) ?? 0.0;
      return qty * sRate;
    }

    double totalCost =
        getCost(_starterQtyCtrl, _starterUnit, _selectedLot?['starter']) +
        getCost(_growerQtyCtrl, _growerUnit, _selectedLot?['grower']) +
        getCost(_finisherQtyCtrl, _finisherUnit, _selectedLot?['finisher']);

    double totalSale =
        getSale(_starterQtyCtrl, _starterRateCtrl) +
        getSale(_growerQtyCtrl, _growerRateCtrl) +
        getSale(_finisherQtyCtrl, _finisherRateCtrl);

    double paid = double.tryParse(_paidCtrl.text) ?? 0.0;
    double due = (totalSale - paid).clamp(0.0, double.infinity);

    return {
      'totalSale': totalSale,
      'totalCost': totalCost,
      'profit': totalSale - totalCost,
      'due': due,
    };
  }

  void _saveSale() async {
    if (_buyerNameCtrl.text.isEmpty || _selectedLot == null) {
      Get.snackbar(
        'Error',
        'Buyer Name aur Lot select karna zaroori hai',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    final fin = _calculateFinancials();
    if ((fin['totalSale'] ?? 0) == 0) {
      Get.snackbar(
        'Error',
        'Kam se kam ek feed item ki quantity aur rate dalein',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    // ── Available bags validation ──
    final String lotName = _selectedLot!['company']?.toString() ?? '';
    final Map<String, double> avail =
        _availableBags[lotName] ?? {'S': 0, 'G': 0, 'F': 0};
    final double enteredS = double.tryParse(_starterQtyCtrl.text) ?? 0.0;
    final double enteredG = double.tryParse(_growerQtyCtrl.text) ?? 0.0;
    final double enteredF = double.tryParse(_finisherQtyCtrl.text) ?? 0.0;

    // Edit mode mein 0 always allow hai (pehle ki value hatane ke liye)
    // Sirf tab rokna hai jab entered > available aur entered > 0
    if (enteredS > 0 && enteredS > (avail['S'] ?? 0)) {
      Get.snackbar(
        'Error',
        'Starter: sirf ${avail['S']?.toStringAsFixed(0)} bag available hai',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    if (enteredG > 0 && enteredG > (avail['G'] ?? 0)) {
      Get.snackbar(
        'Error',
        'Grower: sirf ${avail['G']?.toStringAsFixed(0)} bag available hai',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    if (enteredF > 0 && enteredF > (avail['F'] ?? 0)) {
      Get.snackbar(
        'Error',
        'Finisher: sirf ${avail['F']?.toStringAsFixed(0)} bag available hai',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    // ── Session se added by ──
    final String addedByName = await SessionService.currentName ?? '';
    final String addedByRole = await SessionService.currentRole ?? '';

    final Map<String, dynamic> newSale = {
      'id': _isEditMode
          ? _existingSale!['id']
          : DateTime.now().millisecondsSinceEpoch.toString(),
      'date': _isEditMode
          ? _existingSale!['date']
          : DateTime.now().toIso8601String(),
      'editedAt': _isEditMode ? DateTime.now().toIso8601String() : null,
      'buyerName': _buyerNameCtrl.text.trim(),
      'mobile': _mobileCtrl.text.trim(),
      'lotName': _selectedLot!['company'] ?? 'Unknown Lot',
      'bagWeightApplied':
          (_selectedLot!['bagWeight'] as num?)?.toDouble() ?? 50.0,
      'addedByName': _isEditMode
          ? (_existingSale!['addedByName'] ?? addedByName)
          : addedByName,
      'addedByRole': _isEditMode
          ? (_existingSale!['addedByRole'] ?? addedByRole)
          : addedByRole,
      'editedByName': _isEditMode ? addedByName : null,
      'editedByRole': _isEditMode ? addedByRole : null,
      'starter': {
        'qty': enteredS,
        'unit': _starterUnit,
        'saleRate': double.tryParse(_starterRateCtrl.text) ?? 0.0,
      },
      'grower': {
        'qty': enteredG,
        'unit': _growerUnit,
        'saleRate': double.tryParse(_growerRateCtrl.text) ?? 0.0,
      },
      'finisher': {
        'qty': enteredF,
        'unit': _finisherUnit,
        'saleRate': double.tryParse(_finisherRateCtrl.text) ?? 0.0,
      },
      'totalSaleAmount': fin['totalSale'],
      'totalCostAmount': fin['totalCost'],
      'profitAmount': fin['profit'],
      'paidAmount': double.tryParse(_paidCtrl.text) ?? 0.0,
      'dueAmount': fin['due'],
    };

    final String? existingSales = await CompanyStore.instance.getString(
      'feedSalesHistory',
    );
    List<dynamic> salesList = existingSales != null
        ? json.decode(existingSales)
        : [];

    if (_isEditMode) {
      // Replace existing sale
      final int idx = salesList.indexWhere(
        (s) => s['id'] == _existingSale!['id'],
      );
      if (idx != -1) {
        salesList[idx] = newSale;
      } else {
        salesList.insert(0, newSale);
      }
    } else {
      salesList.insert(0, newSale);
    }

    await CompanyStore.instance.setString(
      'feedSalesHistory',
      json.encode(salesList),
    );

    Get.back(result: true);
    Get.snackbar(
      _isEditMode ? 'Updated ✅' : 'Success ✅',
      _isEditMode
          ? 'Feed Sale Update Ho Gaya'
          : 'Feed Sale Record Save Ho Gaya',
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fin = _calculateFinancials();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.blue.shade800,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          _isEditMode ? 'Feed Sale Edit Karo' : 'New Private Feed Sale',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── LOT SELECTION ──
            DropdownButtonFormField<Map<String, dynamic>>(
              decoration: InputDecoration(
                labelText: 'Purchase Lot Select Karein *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              items: _purchaseLots
                  .map(
                    (lot) => DropdownMenuItem(
                      value: lot,
                      child: Text(
                        '${lot['company']} (${lot['date']?.toString().split('T')[0] ?? ''})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) => setState(() => _selectedLot = val),
            ),
            const SizedBox(height: 16),

            // ── BUYER INFO ──
            TextField(
              controller: _buyerNameCtrl,
              decoration: InputDecoration(
                labelText: 'Buyer Name *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _mobileCtrl,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: InputDecoration(
                labelText: 'Mobile Number',
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── FEED SECTIONS ──
            if (_selectedLot != null) ...[
              _buildFeedInputSection(
                'Starter',
                'S',
                _starterQtyCtrl,
                _starterRateCtrl,
                _starterUnit,
                (val) => setState(() => _starterUnit = val!),
                _selectedLot?['starter'],
              ),
              _buildFeedInputSection(
                'Grower',
                'G',
                _growerQtyCtrl,
                _growerRateCtrl,
                _growerUnit,
                (val) => setState(() => _growerUnit = val!),
                _selectedLot?['grower'],
              ),
              _buildFeedInputSection(
                'Finisher',
                'F',
                _finisherQtyCtrl,
                _finisherRateCtrl,
                _finisherUnit,
                (val) => setState(() => _finisherUnit = val!),
                _selectedLot?['finisher'],
              ),
            ] else
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    'Rate Auto-fill karne ke liye Lot select karein',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),

            const Divider(thickness: 2),
            const SizedBox(height: 12),

            // ── PAYMENT ──
            TextField(
              controller: _paidCtrl,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Advance / Cash Mila (₹)',
                prefixIcon: const Icon(
                  Icons.currency_rupee,
                  color: Colors.green,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── LIVE CALCULATION DASHBOARD ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Sale Bill:'),
                      Text(
                        '₹${fin['totalSale']!.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Purchase Cost:'),
                      Text('₹${fin['totalCost']!.toStringAsFixed(2)}'),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        fin['profit']! >= 0 ? 'Profit 📈' : 'Loss 📉',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: fin['profit']! >= 0
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                      Text(
                        '₹${fin['profit']!.abs().toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: fin['profit']! >= 0
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Due (Udhaar) ⏳:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      Text(
                        '₹${fin['due']!.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saveSale,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade800,
                ),
                child: const Text(
                  'Save Feed Sale',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedInputSection(
    String title,
    String typeKey, // 'S', 'G', 'F'
    TextEditingController qtyCtrl,
    TextEditingController rateCtrl,
    String currentUnit,
    ValueChanged<String?> onUnitChanged,
    Map<String, dynamic>? lotData,
  ) {
    double pRatePerBag = (lotData?['perBagPrice'] as num?)?.toDouble() ?? 0.0;
    double bagW = (_selectedLot!['bagWeight'] as num?)?.toDouble() ?? 50.0;
    double pRate = currentUnit == 'Kg' ? (pRatePerBag / bagW) : pRatePerBag;

    // Available = purchased - already sold from this lot
    final String lotName = _selectedLot!['company']?.toString() ?? '';
    final double availBags = _availableBags[lotName]?[typeKey] ?? 0.0;
    final double purchasedBags = (lotData?['bags'] as num?)?.toDouble() ?? 0.0;
    final double soldBags = purchasedBags - availBags;

    double enteredQty = double.tryParse(qtyCtrl.text) ?? 0.0;
    bool isExceeded =
        currentUnit == 'Bag' && enteredQty > availBags && availBags >= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: purchasedBags == 0
            ? Colors.grey.shade100
            : isExceeded
            ? Colors.red.shade50
            : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: purchasedBags == 0
              ? Colors.grey.shade300
              : isExceeded
              ? Colors.red.shade300
              : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '🌾 $title',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: purchasedBags == 0
                      ? Colors.grey
                      : Colors.blue.shade900,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (purchasedBags > 0)
                    Text(
                      'Auto Cost: ₹${pRate.toStringAsFixed(2)} / $currentUnit',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  if (purchasedBags > 0) ...[
                    Text(
                      'Kharida: ${purchasedBags.toStringAsFixed(0)} Bag',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black45,
                      ),
                    ),
                    if (soldBags > 0)
                      Text(
                        'Becha: ${soldBags.toStringAsFixed(0)} Bag',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    Text(
                      'Bacha: ${availBags.toStringAsFixed(0)} Bag',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isExceeded
                            ? Colors.red.shade700
                            : Colors.green.shade700,
                      ),
                    ),
                  ] else
                    Text(
                      'Is lot mein nahi aaya',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (purchasedBags == 0 && !_isEditMode)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '⚠️ Is lot mein $title nahi hai — add nahi kar sakte',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else if (purchasedBags == 0 && _isEditMode)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ Is lot mein $title nahi tha — 0 karo aur save karo',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: qtyCtrl,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Qty (0 karo)',
                      isDense: true,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            if (isExceeded)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '⚠️ Sirf ${availBags.toStringAsFixed(0)} bag available hai!',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: qtyCtrl,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.number,
                    enabled: purchasedBags > 0,
                    decoration: InputDecoration(
                      labelText: 'Qty',
                      isDense: true,
                      errorText: isExceeded
                          ? 'Max ${availBags.toStringAsFixed(0)}'
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    value: currentUnit,
                    decoration: const InputDecoration(isDense: true),
                    items: ['Bag', 'Kg']
                        .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                        .toList(),
                    onChanged: onUnitChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: rateCtrl,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Sale Rate',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 📋 FEED SALE DETAIL SCREEN — Full info + Edit button
// ═══════════════════════════════════════════════════════════════════════════
class FeedSaleDetailScreen extends StatelessWidget {
  final Map<String, dynamic> sale;
  const FeedSaleDetailScreen({super.key, required this.sale});

  @override
  Widget build(BuildContext context) {
    final double totalSale =
        (sale['totalSaleAmount'] as num?)?.toDouble() ?? 0.0;
    final double totalCost =
        (sale['totalCostAmount'] as num?)?.toDouble() ?? 0.0;
    final double profit = (sale['profitAmount'] as num?)?.toDouble() ?? 0.0;
    final double paid = (sale['paidAmount'] as num?)?.toDouble() ?? 0.0;
    final double due = (sale['dueAmount'] as num?)?.toDouble() ?? 0.0;
    final bool isProfit = profit >= 0;

    final double sQty = (sale['starter']?['qty'] as num?)?.toDouble() ?? 0.0;
    final double gQty = (sale['grower']?['qty'] as num?)?.toDouble() ?? 0.0;
    final double fQty = (sale['finisher']?['qty'] as num?)?.toDouble() ?? 0.0;
    final String sUnit = sale['starter']?['unit']?.toString() ?? 'Bag';
    final String gUnit = sale['grower']?['unit']?.toString() ?? 'Bag';
    final String fUnit = sale['finisher']?['unit']?.toString() ?? 'Bag';
    final double sRate =
        (sale['starter']?['saleRate'] as num?)?.toDouble() ?? 0.0;
    final double gRate =
        (sale['grower']?['saleRate'] as num?)?.toDouble() ?? 0.0;
    final double fRate =
        (sale['finisher']?['saleRate'] as num?)?.toDouble() ?? 0.0;

    final String buyerName = sale['buyerName']?.toString() ?? '-';
    final String mobile = sale['mobile']?.toString() ?? '';
    final String lotName = sale['lotName']?.toString() ?? '-';
    final String addedByName = sale['addedByName']?.toString() ?? '';
    final String addedByRole = sale['addedByRole']?.toString() ?? '';
    final String dateTime = _formatDT(sale['date']?.toString());

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
        title: const Row(
          children: [
            Text('🌾', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text(
              'Feed Sale Detail',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: Colors.white),
            tooltip: 'Edit Sale',
            onPressed: () async {
              final result = await Get.to(
                () => AddPrivateFeedSaleScreen(existingSale: sale),
              );
              if (result == true) {
                Get.back(
                  result: true,
                ); // Detail screen bhi band karo refresh ke liye
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded, color: Colors.white),
            tooltip: 'Delete Sale',
            onPressed: () => _confirmDeleteSale(context, sale),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Lot badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '📦 Lot: $lotName',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
            ),
            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    buyerName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                  if (mobile.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '📞 $mobile',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),

                  const Text(
                    'Feed Breakdown',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (sQty > 0)
                    _feedRow(
                      '🐣 Starter',
                      '$sQty $sUnit',
                      '₹$sRate / $sUnit',
                      '₹${(sQty * sRate).toStringAsFixed(2)}',
                      Colors.blue,
                    ),
                  if (gQty > 0)
                    _feedRow(
                      '🐥 Grower',
                      '$gQty $gUnit',
                      '₹$gRate / $gUnit',
                      '₹${(gQty * gRate).toStringAsFixed(2)}',
                      Colors.purple,
                    ),
                  if (fQty > 0)
                    _feedRow(
                      '🐔 Finisher',
                      '$fQty $fUnit',
                      '₹$fRate / $fUnit',
                      '₹${(fQty * fRate).toStringAsFixed(2)}',
                      Colors.deepOrange,
                    ),

                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),

                  _detailRow(
                    'Total Sale Bill',
                    '₹${totalSale.toStringAsFixed(2)}',
                  ),
                  _detailRow(
                    'Total Purchase Cost',
                    '₹${totalCost.toStringAsFixed(2)}',
                  ),
                  _detailRow('Paid', '₹${paid.toStringAsFixed(2)}'),
                  const SizedBox(height: 12),

                  // Due
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: due > 0
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: due > 0
                            ? Colors.red.shade300
                            : Colors.green.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          due > 0 ? '⏳ Baki (Due)' : '✅ Fully Paid',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: due > 0
                                ? Colors.red.shade800
                                : Colors.green.shade800,
                          ),
                        ),
                        Text(
                          due > 0 ? '₹${due.toStringAsFixed(2)}' : '₹0.00',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: due > 0
                                ? Colors.red.shade800
                                : Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Profit/Loss
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isProfit
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isProfit
                            ? Colors.green.shade400
                            : Colors.red.shade400,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isProfit ? '📈 Profit' : '📉 Loss',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isProfit
                                ? Colors.green.shade800
                                : Colors.red.shade800,
                          ),
                        ),
                        Text(
                          '${isProfit ? '+' : '-'}₹${profit.abs().toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: isProfit
                                ? Colors.green.shade800
                                : Colors.red.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),

                  if (addedByName.isNotEmpty)
                    _detailRow(
                      '👤 Added By',
                      addedByRole.isNotEmpty
                          ? '$addedByRole: $addedByName'
                          : addedByName,
                    ),
                  _detailRow('🕒 Date & Time', dateTime),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Payment placeholder
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_clock_rounded,
                    color: Colors.grey.shade400,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Payment feature jald aayega',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feedRow(
    String label,
    String qty,
    String rate,
    String total,
    MaterialColor color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.shade100),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: color.shade800,
                    ),
                  ),
                  Text(
                    'Qty: $qty  •  Rate: $rate',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
            Text(
              total,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: color.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🗑️ DELETE CONFIRMATION — Feed Sale
// ═══════════════════════════════════════════════════════════════════════════
Future<void> _confirmDeleteSale(
  BuildContext context,
  Map<String, dynamic> sale,
) async {
  final bool? confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete Karein?'),
      content: const Text(
        'Kya aap is sale ki info ko delete karna chahte hain? Yeh permanent hai.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('No'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Yes, Delete'),
        ),
      ],
    ),
  );

  if (confirm == true) {
    final String? existingSales = await CompanyStore.instance.getString(
      'feedSalesHistory',
    );
    List<dynamic> salesList = existingSales != null
        ? json.decode(existingSales)
        : [];
    salesList.removeWhere((s) => s['id'] == sale['id']);
    await CompanyStore.instance.setString(
      'feedSalesHistory',
      json.encode(salesList),
    );

    Get.back(
      result: true,
    ); // Detail screen band karo aur history list refresh karo
    Get.snackbar(
      'Deleted 🗑️',
      'Feed Sale Record Delete Ho Gaya',
      backgroundColor: Colors.red,
      colorText: Colors.white,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🧾 HELPER
// ═══════════════════════════════════════════════════════════════════════════
String _formatDT(String? isoStr) {
  if (isoStr == null || isoStr.isEmpty) return '-';
  try {
    DateTime dt = DateTime.parse(isoStr);
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}, ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return isoStr;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🎴 SALES CATEGORY CARD
// ═══════════════════════════════════════════════════════════════════════════
class _SalesCategoryCard extends StatelessWidget {
  final String emoji, label, subtitle, badgeText;
  final Color bgColor, borderColor, iconBg, textColor;
  final VoidCallback onTap;

  const _SalesCategoryCard({
    required this.emoji,
    required this.label,
    required this.subtitle,
    required this.bgColor,
    required this.borderColor,
    required this.iconBg,
    required this.textColor,
    required this.badgeText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 26)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.7)),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: textColor,
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
// 💊 MEDICINE SALES — Unit & Price conversion helpers
//
// KEY RULE:
//   Qty  : 500 ml → 0.5 liter  (×factor)
//   Price: Rs2000/liter → Rs2/ml  (DIVIDE by factor, not multiply)
//
//   _qtyToBase   : qty  from → base
//   _qtyFromBase : qty  base → display
//   _pricePerUnit: Rs/base → Rs/target  (e.g. Rs2000/L → Rs2/ml)
//   _priceToBase : Rs/target → Rs/base  (e.g. Rs2/ml → Rs2000/L)
// ═══════════════════════════════════════════════════════════════════════════
const Map<String, double> _sMl   = {'ml': 1.0, 'liter': 1000.0};
const Map<String, double> _sGram = {'gram': 1.0, 'kg': 1000.0};
const List<String> kMedSaleUnits = ['ml','liter','gram','kg','packet','dabba'];

double? _qtyToBase(double qty, String from, String base) {
  final f = from.toLowerCase().trim(), b = base.toLowerCase().trim();
  if (f == b) return qty;
  if (_sMl.containsKey(f)   && _sMl.containsKey(b))
    return qty * _sMl[f]!   / _sMl[b]!;
  if (_sGram.containsKey(f) && _sGram.containsKey(b))
    return qty * _sGram[f]! / _sGram[b]!;
  return null;
}
double? _qtyFromBase(double qty, String base, String to) =>
    _qtyToBase(qty, base, to);

/// Rs per BASE unit -> Rs per TARGET unit
/// e.g. Rs2000/liter -> Rs2/ml  (multiply by target-factor / base-factor)
double? _pricePerUnit(double pricePerBase, String base, String target) {
  final b = base.toLowerCase().trim(), t = target.toLowerCase().trim();
  if (b == t) return pricePerBase;
  if (_sMl.containsKey(b)   && _sMl.containsKey(t))
    return pricePerBase * _sMl[t]!   / _sMl[b]!;
  if (_sGram.containsKey(b) && _sGram.containsKey(t))
    return pricePerBase * _sGram[t]! / _sGram[b]!;
  return null;
}
double? _priceToBase(double pricePerTarget, String target, String base) =>
    _pricePerUnit(pricePerTarget, target, base);

bool _sCanConv(String a, String b) {
  final u = a.toLowerCase().trim(), v = b.toLowerCase().trim();
  if (u == v) return true;
  if (_sMl.containsKey(u)   && _sMl.containsKey(v))   return true;
  if (_sGram.containsKey(u) && _sGram.containsKey(v)) return true;
  return false;
}

String _sFmt(String? iso) {
  if (iso == null) return '-';
  try {
    final dt = DateTime.parse(iso);
    return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year}, ${dt.hour}:${dt.minute.toString().padLeft(2,'0')}';
  } catch (_) { return '-'; }
}

// ═══════════════════════════════════════════════════════════════════════════
// 💊 MEDICINE SALES HISTORY SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class MedicineSalesHistoryScreen extends StatefulWidget {
  const MedicineSalesHistoryScreen({super.key});
  @override
  State<MedicineSalesHistoryScreen> createState() =>
      _MedicineSalesHistoryScreenState();
}

class _MedicineSalesHistoryScreenState
    extends State<MedicineSalesHistoryScreen> {
  List<Map<String, dynamic>> _sales = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final String? j =
        await CompanyStore.instance.getString('medicineSalesHistory');
    if (j != null) {
      try {
        _sales = (json.decode(j) as List)
            .map((e) => Map<String,dynamic>.from(e)).toList();
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.teal.shade700,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        title: const Row(children: [
          Text('💊', style: TextStyle(fontSize: 18)),
          SizedBox(width: 8),
          Text('Medicine Sales',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await Get.to(() => const AddPrivateMedicineSaleScreen());
                  _load();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700),
                icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white),
                label: const Text('Private Medicine Sale',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _sales.isEmpty
                    ? Center(child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('💊', style: TextStyle(fontSize: 52)),
                          const SizedBox(height: 12),
                          Text('Koi medicine sale nahi.',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                        ],
                      ))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _sales.length,
                        itemBuilder: (ctx, i) =>
                            _MedSaleCard(sale: _sales[i], onRefresh: _load),
                      ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 💊 MEDICINE SALE CARD
// ═══════════════════════════════════════════════════════════════════════════
class _MedSaleCard extends StatelessWidget {
  final Map<String, dynamic> sale;
  final VoidCallback onRefresh;
  const _MedSaleCard({required this.sale, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final double total  = (sale['totalSaleAmount'] as num?)?.toDouble() ?? 0;
    final double due    = (sale['dueAmount']        as num?)?.toDouble() ?? 0;
    final double profit = (sale['profitAmount']     as num?)?.toDouble() ?? 0;
    final List items    = sale['items'] as List? ?? [];
    final String summary = items.take(2).map((i) =>
        '${(i['qty'] as num?)?.toStringAsFixed(2) ?? '0'} '
        '${i['saleUnit'] ?? i['unit'] ?? ''} '
        '${i['medicineName'] ?? '-'}').join(', ')
        + (items.length > 2 ? ' +${items.length - 2} more' : '');

    return GestureDetector(
      onTap: () async {
        final r = await Get.to(() => MedicineSaleDetailScreen(sale: sale));
        if (r == true) onRefresh();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.teal.shade200, width: 1.2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text('🛒 ${sale['buyerName'] ?? '-'}',
                  style: TextStyle(fontWeight: FontWeight.bold,
                      fontSize: 16, color: Colors.teal.shade900))),
              Text('₹${total.toStringAsFixed(2)}',
                  style: TextStyle(fontWeight: FontWeight.bold,
                      fontSize: 16, color: Colors.teal.shade900)),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 18),
            ]),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(summary, style: TextStyle(fontSize: 12, color: Colors.teal.shade700),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            Text('🕒 ${_sFmt(sale['date']?.toString())}',
                style: const TextStyle(fontSize: 11, color: Colors.black45)),
            const SizedBox(height: 8),
            Row(children: [
              _badge(due > 0 ? 'Due: ₹${due.toStringAsFixed(0)}' : '✅ Paid',
                  due > 0 ? Colors.red : Colors.green),
              const SizedBox(width: 8),
              _badge('${profit >= 0 ? '📈' : '📉'} ₹${profit.abs().toStringAsFixed(0)}',
                  profit >= 0 ? Colors.green : Colors.red),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _badge(String t, MaterialColor c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: c.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.shade200)),
    child: Text(t, style: TextStyle(fontSize: 11,
        fontWeight: FontWeight.bold, color: c.shade900)),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// 📝 ADD PRIVATE MEDICINE SALE
// - Inline search field (clear nahi hota)
// - Item layout: Name header → Qty → Unit chips → Rate
// - Price conversion SAHI: Rs/liter→Rs/ml = DIVIDE (not multiply)
// ═══════════════════════════════════════════════════════════════════════════
class AddPrivateMedicineSaleScreen extends StatefulWidget {
  final Map<String, dynamic>? existingSale;
  const AddPrivateMedicineSaleScreen({super.key, this.existingSale});
  @override
  State<AddPrivateMedicineSaleScreen> createState() =>
      _AddPrivateMedicineSaleScreenState();
}

class _AddPrivateMedicineSaleScreenState
    extends State<AddPrivateMedicineSaleScreen> {

  List<Map<String, dynamic>> _stock = [];
  Map<String, double> _availBase = {}; // mId -> available base qty

  final _buyerCtrl  = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _paidCtrl   = TextEditingController();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _suggestions = [];

  // [{medicineId, medicineName, nickName, baseUnit, saleUnit,
  //   avgCostPerBase, qtyCtrl, rateCtrl}]
  List<Map<String, dynamic>> _items = [];

  bool _isEdit = false;

  @override
  void initState() {
    super.initState();
    _isEdit = widget.existingSale != null;
    _loadData();
    _searchCtrl.addListener(_onSearch);
  }

  // Search listener — suggestions update karo
  void _onSearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) { setState(() => _suggestions = []); return; }
    final addedIds = _items.map((i) => i['medicineId'].toString()).toSet();
    setState(() {
      _suggestions = _stock.where((med) {
        final mId  = med['id']?.toString() ?? '';
        final name = med['name']?.toString().toLowerCase() ?? '';
        final nick = med['nickName']?.toString().toLowerCase() ?? '';
        final avail = _availBase[mId] ?? 0.0;
        return !addedIds.contains(mId) && avail > 0
            && (name.contains(q) || nick.contains(q));
      }).toList();
    });
  }

  Future<void> _loadData() async {
    // Medicine stock
    final String? sj = await CompanyStore.instance.getString('medicineStockList');
    List<Map<String, dynamic>> stock = [];
    if (sj != null) {
      try { stock = (json.decode(sj) as List)
          .map((e) => Map<String,dynamic>.from(e)).toList(); }
      catch (_) {}
    }

    // Sold base qty per medicine (exclude current sale if editing)
    final String? salesJ =
        await CompanyStore.instance.getString('medicineSalesHistory');
    Map<String, double> soldBase = {};
    if (salesJ != null) {
      try {
        for (final sale in json.decode(salesJ) as List) {
          if (_isEdit && sale['id'] == widget.existingSale!['id']) continue;
          for (final item in (sale['items'] as List? ?? [])) {
            final mId = item['medicineId']?.toString() ?? '';
            if (mId.isEmpty) continue;
            soldBase[mId] = (soldBase[mId] ?? 0.0) +
                ((item['qtyInBaseUnit'] as num?)?.toDouble() ??
                 (item['qty']           as num?)?.toDouble() ?? 0.0);
          }
        }
      } catch (_) {}
    }

    // Available = total - allocated - sold
    final Map<String, double> avail = {};
    for (final med in stock) {
      final mId  = med['id']?.toString() ?? '';
      if (mId.isEmpty) continue;
      final double total = (med['totalBaseQty'] as num?)?.toDouble() ?? 0.0;
      double allocBase = 0;
      for (final a in (med['allocations'] as List? ?? [])) {
        allocBase += (a['qtyInBaseUnit'] as num?)?.toDouble() ??
                     (a['qty']           as num?)?.toDouble() ?? 0.0;
      }
      avail[mId] = (total - allocBase - (soldBase[mId] ?? 0.0))
          .clamp(0.0, double.infinity);
    }

    setState(() {
      _stock     = stock;
      _availBase = avail;

      // Edit mode prefill
      if (_isEdit && widget.existingSale != null) {
        final s = widget.existingSale!;
        _buyerCtrl.text  = s['buyerName']?.toString() ?? '';
        _mobileCtrl.text = s['mobile']?.toString()    ?? '';
        _paidCtrl.text   = (s['paidAmount'] as num?)?.toStringAsFixed(2) ?? '0';
        _items = (s['items'] as List? ?? []).map((item) {
          final bu = item['baseUnit']?.toString() ?? item['unit']?.toString() ?? '';
          final su = item['saleUnit']?.toString() ?? bu;
          return {
            'medicineId'    : item['medicineId']?.toString() ?? '',
            'medicineName'  : item['medicineName']?.toString() ?? '',
            'nickName'      : item['nickName']?.toString() ?? '',
            'baseUnit'      : bu,
            'saleUnit'      : su,
            'avgCostPerBase': (item['costRatePerBase'] as num?)?.toDouble() ?? 0.0,
            'qtyCtrl'       : TextEditingController(
                text: (item['qty'] as num?)?.toStringAsFixed(2) ?? ''),
            'rateCtrl'      : TextEditingController(
                text: (item['saleRate'] as num?)?.toStringAsFixed(2) ?? ''),
          };
        }).toList();
      }
    });
  }

  // Suggestion tap → item add, search field clear NAHI hota
  void _addItem(Map<String, dynamic> med) {
    final mId          = med['id']?.toString() ?? '';
    final String bu    = med['unit']?.toString() ?? 'unit';
    final double avgCPB= (med['weightedAvgCost']   as num?)?.toDouble() ?? 0.0;
    final double fRatePB=(med['currentFarmerRate'] as num?)?.toDouble() ?? 0.0;

    setState(() {
      _items.add({
        'medicineId'    : mId,
        'medicineName'  : med['name']?.toString() ?? '',
        'nickName'      : med['nickName']?.toString() ?? '',
        'baseUnit'      : bu,
        'saleUnit'      : bu, // default = base unit
        'avgCostPerBase': avgCPB,
        // Pre-fill rate = farmer rate per base unit
        'qtyCtrl'       : TextEditingController(),
        'rateCtrl'      : TextEditingController(
            text: fRatePB > 0 ? fRatePB.toStringAsFixed(2) : ''),
      });
      _onSearch(); // suggestions refresh (added item hatao)
      // search field CLEAR NAHI karo
    });
  }

  // Financials — sab base unit mein calculate karo
  Map<String, double> _calc() {
    double totalSale = 0, totalCost = 0;
    for (final item in _items) {
      final String bu  = item['baseUnit']?.toString() ?? '';
      final String su  = item['saleUnit']?.toString() ?? bu;
      final double qty  = double.tryParse(
          (item['qtyCtrl']  as TextEditingController).text) ?? 0;
      final double rate = double.tryParse(
          (item['rateCtrl'] as TextEditingController).text) ?? 0;
      // qty: su → base
      final double qb   = _qtyToBase(qty,  su, bu) ?? qty;
      // rate: Rs/su → Rs/base
      final double rPB  = _priceToBase(rate, su, bu) ?? rate;
      final double cPB  = (item['avgCostPerBase'] as num?)?.toDouble() ?? 0;
      totalSale += qb * rPB;
      totalCost += qb * cPB;
    }
    final double paid = double.tryParse(_paidCtrl.text) ?? 0;
    return {
      'sale'  : totalSale,
      'cost'  : totalCost,
      'profit': totalSale - totalCost,
      'due'   : (totalSale - paid).clamp(0.0, double.infinity),
    };
  }

  Future<void> _save() async {
    if (_buyerCtrl.text.trim().isEmpty) {
      Get.snackbar('Error', 'Buyer Name zaroori hai',
          backgroundColor: Colors.red, colorText: Colors.white); return;
    }
    if (_items.isEmpty) {
      Get.snackbar('Error', 'Kam se kam ek medicine add karein',
          backgroundColor: Colors.red, colorText: Colors.white); return;
    }

    for (final item in _items) {
      final String bu  = item['baseUnit']?.toString() ?? '';
      final String su  = item['saleUnit']?.toString() ?? bu;
      final double qty = double.tryParse(
          (item['qtyCtrl'] as TextEditingController).text) ?? 0;
      final double qb  = _qtyToBase(qty, su, bu) ?? qty;
      final double avail = _availBase[item['medicineId']?.toString() ?? ''] ?? 0;
      if (qty <= 0) {
        Get.snackbar('Error', '${item['medicineName']}: quantity dalein',
            backgroundColor: Colors.red, colorText: Colors.white); return;
      }
      if (qb > avail) {
        final double av = _qtyFromBase(avail, bu, su) ?? avail;
        Get.snackbar('Error',
            '${item['medicineName']}: sirf ${av.toStringAsFixed(2)} $su available',
            backgroundColor: Colors.red, colorText: Colors.white); return;
      }
    }

    final fin    = _calc();
    final byName = await SessionService.currentName ?? '';
    final byRole = await SessionService.currentRole ?? '';

    final itemsList = _items.map((item) {
      final String bu    = item['baseUnit']?.toString() ?? '';
      final String su    = item['saleUnit']?.toString() ?? bu;
      final double qty   = double.tryParse(
          (item['qtyCtrl']  as TextEditingController).text) ?? 0;
      final double rate  = double.tryParse(
          (item['rateCtrl'] as TextEditingController).text) ?? 0;
      final double qb    = _qtyToBase(qty,  su, bu) ?? qty;
      final double rPB   = _priceToBase(rate, su, bu) ?? rate;
      final double cPB   = (item['avgCostPerBase'] as num?)?.toDouble() ?? 0;
      return {
        'medicineId'     : item['medicineId'],
        'medicineName'   : item['medicineName'],
        'nickName'       : item['nickName'],
        'baseUnit'       : bu,
        'saleUnit'       : su,
        'qty'            : qty,
        'qtyInBaseUnit'  : qb,
        'saleRate'       : rate,        // Rs per saleUnit (display)
        'saleRatePerBase': rPB,         // Rs per baseUnit (calc)
        'costRatePerBase': cPB,         // Rs per baseUnit
        'totalSale'      : qb * rPB,
        'totalCost'      : qb * cPB,
      };
    }).toList();

    final newSale = {
      'id'          : _isEdit ? widget.existingSale!['id']
                               : DateTime.now().millisecondsSinceEpoch.toString(),
      'date'        : _isEdit ? widget.existingSale!['date']
                               : DateTime.now().toIso8601String(),
      'editedAt'    : _isEdit ? DateTime.now().toIso8601String() : null,
      'buyerName'   : _buyerCtrl.text.trim(),
      'mobile'      : _mobileCtrl.text.trim(),
      'addedByName' : _isEdit
          ? (widget.existingSale!['addedByName'] ?? byName) : byName,
      'addedByRole' : _isEdit
          ? (widget.existingSale!['addedByRole'] ?? byRole) : byRole,
      'editedByName': _isEdit ? byName : null,
      'editedByRole': _isEdit ? byRole : null,
      'items'            : itemsList,
      'totalSaleAmount'  : fin['sale'],
      'totalCostAmount'  : fin['cost'],
      'profitAmount'     : fin['profit'],
      'paidAmount'       : double.tryParse(_paidCtrl.text) ?? 0,
      'dueAmount'        : fin['due'],
    };

    final String? ej =
        await CompanyStore.instance.getString('medicineSalesHistory');
    List list = ej != null ? json.decode(ej) : [];
    if (_isEdit) {
      final idx = list.indexWhere((s) => s['id'] == widget.existingSale!['id']);
      if (idx != -1) list[idx] = newSale; else list.insert(0, newSale);
    } else {
      list.insert(0, newSale);
    }
    await CompanyStore.instance.setString('medicineSalesHistory', json.encode(list));
    Get.back(result: true);
    Get.snackbar(_isEdit ? 'Updated ✅' : 'Saved ✅',
        _isEdit ? 'Sale update ho gaya' : 'Sale save ho gaya',
        backgroundColor: Colors.green, colorText: Colors.white);
  }

  @override
  void dispose() {
    _buyerCtrl.dispose(); _mobileCtrl.dispose();
    _paidCtrl.dispose();  _searchCtrl.dispose();
    for (final i in _items) {
      (i['qtyCtrl']  as TextEditingController).dispose();
      (i['rateCtrl'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fin = _calc();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.teal.shade700,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        title: Text(
          _isEdit ? 'Medicine Sale Edit Karo' : 'New Private Medicine Sale',
          style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Buyer info ──
            TextField(
              controller: _buyerCtrl,
              decoration: InputDecoration(
                labelText: 'Buyer Name *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _mobileCtrl,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: InputDecoration(
                labelText: 'Mobile Number',
                counterText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 24),

            // ── Medicine Items header ──
            const Text('💊 Medicine Items',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            // ── Inline Search field (clear nahi hota) ──
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Medicine naam ya nickname search karein...',
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.teal),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _suggestions = []);
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.teal.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.teal.shade600, width: 2),
                ),
              ),
            ),

            // ── Suggestions dropdown ──
            if (_suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                constraints: const BoxConstraints(maxHeight: 240),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.shade200),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07),
                      blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.grey.shade100),
                  itemBuilder: (ctx, i) {
                    final med   = _suggestions[i];
                    final mId   = med['id']?.toString() ?? '';
                    final name  = med['name']?.toString() ?? '-';
                    final nick  = med['nickName']?.toString() ?? '';
                    final unit  = med['unit']?.toString() ?? '';
                    final avail = _availBase[mId] ?? 0.0;
                    return InkWell(
                      onTap: () => _addItem(med),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(children: [
                          Container(
                            width: 38, height: 38,
                            decoration: BoxDecoration(
                                color: Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(8)),
                            child: const Center(
                                child: Text('💊', style: TextStyle(fontSize: 18))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                                if (nick.isNotEmpty)
                                  Text('"$nick"', style: TextStyle(
                                      fontSize: 11, color: Colors.teal.shade600)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${avail.toStringAsFixed(2)} $unit',
                                  style: TextStyle(fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700)),
                              Text('available', style: TextStyle(
                                  fontSize: 10, color: Colors.grey.shade500)),
                            ],
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.add_circle_rounded,
                              color: Colors.teal.shade600, size: 22),
                        ]),
                      ),
                    );
                  },
                ),
              ),

            // No result message
            if (_searchCtrl.text.isNotEmpty && _suggestions.isEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded,
                      color: Colors.orange.shade700, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                      'Koi medicine nahi mili — purchase history check karein.',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800))),
                ]),
              ),

            const SizedBox(height: 16),

            // ── Added items list ──
            if (_items.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Center(child: Column(children: [
                  Icon(Icons.medication_outlined,
                      color: Colors.grey.shade400, size: 36),
                  const SizedBox(height: 8),
                  Text('Upar search karein aur medicine add karein',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                ])),
              )
            else
              ...List.generate(_items.length, (i) => _itemCard(i)),

            const Divider(thickness: 2, height: 32),

            // ── Payment ──
            TextField(
              controller: _paidCtrl,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Advance / Cash Mila (₹)',
                prefixIcon: const Icon(Icons.currency_rupee, color: Colors.green),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 20),

            // ── P&L Dashboard ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Column(children: [
                _dRow('Total Sale Bill:',
                    '₹${fin['sale']!.toStringAsFixed(2)}', bold: true, size: 16),
                _dRow('Total Purchase Cost:',
                    '₹${fin['cost']!.toStringAsFixed(2)}'),
                const Divider(),
                _dRow(fin['profit']! >= 0 ? 'Profit 📈' : 'Loss 📉',
                    '₹${fin['profit']!.abs().toStringAsFixed(2)}',
                    color: fin['profit']! >= 0 ? Colors.green : Colors.red,
                    bold: true),
                _dRow('Due (Udhaar) ⏳:',
                    '₹${fin['due']!.toStringAsFixed(2)}',
                    color: Colors.orange, bold: true),
              ]),
            ),
            const SizedBox(height: 28),

            // ── Save button ──
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Save Medicine Sale',
                    style: TextStyle(color: Colors.white,
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _dRow(String label, String value,
      {Color? color, bool bold = false, double size = 14}) {
    final st = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        color: color ?? Colors.black87, fontSize: size);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label, style: st), Text(value, style: st)]),
    );
  }

  // ── Item card: Name → Qty → Unit chips → Rate ──
  Widget _itemCard(int index) {
    final item = _items[index];
    final String bu   = item['baseUnit']?.toString() ?? '';
    final String su   = item['saleUnit']?.toString() ?? bu;
    final double cPB  = (item['avgCostPerBase'] as num?)?.toDouble() ?? 0;
    final String mId  = item['medicineId']?.toString() ?? '';
    final double aBase = _availBase[mId] ?? 0;
    // Available in sale unit
    final double aSu  = _qtyFromBase(aBase, bu, su) ?? aBase;
    final qCtrl = item['qtyCtrl']  as TextEditingController;
    final rCtrl = item['rateCtrl'] as TextEditingController;
    final double qty  = double.tryParse(qCtrl.text)  ?? 0;
    final double rate = double.tryParse(rCtrl.text) ?? 0;
    final double qb   = _qtyToBase(qty,  su, bu) ?? qty;
    final double rPB  = _priceToBase(rate, su, bu) ?? rate;
    // Cost in sale unit for display (CORRECT: divide)
    final double cSu  = _pricePerUnit(cPB, bu, su) ?? cPB;
    final bool isOver = qb > aBase && aBase >= 0;
    final double iCost = qb * cPB;
    final double iBill = qb * rPB;
    final double iProf = iBill - iCost;
    final bool hasCalc = qty > 0 && rate > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isOver ? Colors.red.shade300 : Colors.teal.shade200,
            width: 1.3),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
            blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── 1. Name header ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12), topRight: Radius.circular(12)),
          ),
          child: Row(children: [
            const Text('💊', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['medicineName']?.toString() ?? '-',
                    style: TextStyle(fontWeight: FontWeight.bold,
                        fontSize: 14, color: Colors.teal.shade900)),
                if ((item['nickName']?.toString() ?? '').isNotEmpty)
                  Text('"${item['nickName']}"',
                      style: TextStyle(fontSize: 11, color: Colors.teal.shade600)),
              ],
            )),
            // Remove button
            InkWell(
              onTap: () => setState(() {
                (item['qtyCtrl']  as TextEditingController).dispose();
                (item['rateCtrl'] as TextEditingController).dispose();
                _items.removeAt(index);
                _onSearch(); // suggestions refresh
              }),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: Colors.red.shade50, shape: BoxShape.circle,
                    border: Border.all(color: Colors.red.shade200)),
                child: Icon(Icons.close_rounded,
                    size: 16, color: Colors.red.shade700),
              ),
            ),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── 2. Quantity field ──
            TextField(
              controller: qCtrl,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Quantity ($su)',
                isDense: true,
                errorText: isOver ? 'Max ${aSu.toStringAsFixed(2)} $su' : null,
                helperText: 'Bacha: ${aSu.toStringAsFixed(2)} $su',
                helperStyle: TextStyle(
                    fontSize: 11,
                    color: isOver ? Colors.red.shade700 : Colors.green.shade700,
                    fontWeight: FontWeight.w600),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),

            const SizedBox(height: 12),

            // ── 3. Unit chips ──
            Text('Unit:', style: TextStyle(
                fontSize: 12, color: Colors.grey.shade700,
                fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6, runSpacing: 4,
              children: kMedSaleUnits.map((u) {
                final bool enabled = _sCanConv(u, bu);
                return ChoiceChip(
                  label: Text(u, style: const TextStyle(fontSize: 12)),
                  selected: su == u,
                  onSelected: enabled ? (v) {
                    if (!v) return;
                    setState(() {
                      final String oldSu = item['saleUnit']?.toString() ?? bu;
                      item['saleUnit'] = u;
                      // Rate convert: Rs/oldSu → Rs/base → Rs/newSu (PRICE conversion)
                      if (rate > 0) {
                        final double rBase = _priceToBase(rate, oldSu, bu) ?? rate;
                        final double rNew  = _pricePerUnit(rBase, bu, u) ?? rBase;
                        rCtrl.text = rNew.toStringAsFixed(2);
                      }
                    });
                  } : null,
                  selectedColor: Colors.teal.shade700,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  labelStyle: TextStyle(
                    color: !enabled ? Colors.grey.shade400
                        : su == u ? Colors.white : Colors.black87,
                  ),
                );
              }).toList(),
            ),

            if (su != bu && qty > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('= ${qb.toStringAsFixed(3)} $bu',
                    style: TextStyle(fontSize: 10, color: Colors.teal.shade700)),
              ),

            const SizedBox(height: 12),

            // ── 4. Sale Rate field ──
            TextField(
              controller: rCtrl,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Sale Rate (₹ / $su)',
                isDense: true,
                // Purchase cost in SAME unit — CORRECT (divide not multiply)
                helperText: cSu > 0
                    ? 'Purchase cost: ₹${cSu.toStringAsFixed(2)} / $su'
                    : null,
                helperStyle: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.currency_rupee,
                    size: 18, color: Colors.teal),
              ),
            ),

            // ── Mini P&L ──
            if (hasCalc) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: iProf >= 0 ? Colors.teal.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: iProf >= 0
                      ? Colors.teal.shade200 : Colors.orange.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Cost: ₹${iCost.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 11, color: Colors.black54)),
                    Text('Bill: ₹${iBill.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 11, color: Colors.black54)),
                    Text(
                      iProf >= 0
                          ? '📈 +₹${iProf.toStringAsFixed(0)}'
                          : '📉 -₹${iProf.abs().toStringAsFixed(0)}',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold,
                          color: iProf >= 0
                              ? Colors.teal.shade800 : Colors.orange.shade800),
                    ),
                  ],
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 📋 MEDICINE SALE DETAIL SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class MedicineSaleDetailScreen extends StatelessWidget {
  final Map<String, dynamic> sale;
  const MedicineSaleDetailScreen({super.key, required this.sale});

  @override
  Widget build(BuildContext context) {
    final double total  = (sale['totalSaleAmount'] as num?)?.toDouble() ?? 0;
    final double cost   = (sale['totalCostAmount'] as num?)?.toDouble() ?? 0;
    final double profit = (sale['profitAmount']    as num?)?.toDouble() ?? 0;
    final double paid   = (sale['paidAmount']      as num?)?.toDouble() ?? 0;
    final double due    = (sale['dueAmount']        as num?)?.toDouble() ?? 0;
    final List items    = sale['items'] as List? ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.teal.shade700,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        title: const Text('💊 Medicine Sale Detail',
            style: TextStyle(color: Colors.white,
                fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: Colors.white),
            onPressed: () async {
              final r = await Get.to(
                  () => AddPrivateMedicineSaleScreen(existingSale: sale));
              if (r == true) Get.back(result: true);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded, color: Colors.white),
            onPressed: () => _delMedSale(context, sale),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.teal.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sale['buyerName']?.toString() ?? '-',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                    color: Colors.teal.shade900)),
            if ((sale['mobile']?.toString() ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('📞 ${sale['mobile']}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 10),
            const Text('Medicine Breakdown',
                style: TextStyle(fontWeight: FontWeight.bold,
                    fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 10),

            ...items.map((item) {
              final String name  = item['medicineName']?.toString() ?? '-';
              final String nick  = item['nickName']?.toString() ?? '';
              final double qty   = (item['qty']  as num?)?.toDouble() ?? 0;
              final String su    = item['saleUnit']?.toString()
                  ?? item['unit']?.toString() ?? '';
              final String bu    = item['baseUnit']?.toString() ?? su;
              final double rate  = (item['saleRate'] as num?)?.toDouble() ?? 0;
              final double rPB   = (item['saleRatePerBase'] as num?)?.toDouble()
                  ?? _priceToBase(rate, su, bu) ?? rate;
              final double qb    = (item['qtyInBaseUnit'] as num?)?.toDouble()
                  ?? _qtyToBase(qty, su, bu) ?? qty;
              final double lineT = qb * rPB;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.teal.shade100),
                ),
                child: Row(children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('💊 $name', style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13,
                          color: Colors.teal.shade800)),
                      if (nick.isNotEmpty)
                        Text('"$nick"', style: TextStyle(
                            fontSize: 10, color: Colors.teal.shade600)),
                      Text(
                        '${qty.toStringAsFixed(2)} $su  •  ₹${rate.toStringAsFixed(2)} / $su',
                        style: const TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                      if (su != bu)
                        Text('(= ${qb.toStringAsFixed(3)} $bu)',
                            style: TextStyle(fontSize: 10,
                                color: Colors.grey.shade500)),
                    ],
                  )),
                  Text('₹${lineT.toStringAsFixed(2)}',
                      style: TextStyle(fontWeight: FontWeight.bold,
                          fontSize: 14, color: Colors.teal.shade800)),
                ]),
              );
            }),

            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),

            _iRow('Total Sale Bill',  '₹${total.toStringAsFixed(2)}'),
            _iRow('Purchase Cost',    '₹${cost.toStringAsFixed(2)}'),
            _iRow('Paid',             '₹${paid.toStringAsFixed(2)}'),
            const SizedBox(height: 12),

            _sBox(due > 0 ? '⏳ Baki (Due)' : '✅ Fully Paid',
                due > 0 ? '₹${due.toStringAsFixed(2)}' : '₹0.00',
                due > 0 ? Colors.red : Colors.green),
            const SizedBox(height: 10),
            _sBox(profit >= 0 ? '📈 Profit' : '📉 Loss',
                '${profit >= 0 ? '+' : '-'}₹${profit.abs().toStringAsFixed(2)}',
                profit >= 0 ? Colors.green : Colors.red, big: true),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            if ((sale['addedByName']?.toString() ?? '').isNotEmpty)
              _iRow('👤 Added By',
                  '${sale['addedByRole'] ?? ''}: ${sale['addedByName']}'),
            _iRow('🕒 Date', _sFmt(sale['date']?.toString())),
          ]),
        ),
      ),
    );
  }

  Widget _iRow(String l, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l, style: const TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(width: 16),
          Flexible(child: Text(v, textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
  );

  Widget _sBox(String l, String v, MaterialColor c, {bool big = false}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.shade300, width: 1.5)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l, style: TextStyle(fontWeight: FontWeight.bold,
                  fontSize: big ? 15 : 14, color: c.shade800)),
              Text(v, style: TextStyle(fontWeight: FontWeight.bold,
                  fontSize: big ? 18 : 16, color: c.shade800)),
            ]),
      );
}

// ── Delete ──
Future<void> _delMedSale(BuildContext context, Map<String,dynamic> sale) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete Karein?'),
      content: const Text('Is medicine sale ko delete karna chahte hain?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
        TextButton(onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Delete')),
      ],
    ),
  );
  if (ok != true) return;
  final String? j =
      await CompanyStore.instance.getString('medicineSalesHistory');
  List list = j != null ? json.decode(j) : [];
  list.removeWhere((s) => s['id'] == sale['id']);
  await CompanyStore.instance.setString('medicineSalesHistory', json.encode(list));
  Get.back(result: true);
  Get.snackbar('Deleted 🗑️', 'Sale delete ho gaya',
      backgroundColor: Colors.red, colorText: Colors.white);
}
