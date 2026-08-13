// lib/screens/dashboards/farmer_dashboard.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../main.dart';
import '../../services/session_service.dart';
import '../../services/company_store.dart';
import '../welcome_screen.dart';
import '../farmers/batch_detail_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// FARMER DASHBOARD — Company Farmer ka home. Sirf VIEW + apna Settlement
// Rasid dekhna/download karna — koi bhi add/edit/delete access nahi hai
// (wo lock batch_detail_screen.dart mein already ho chuka hai).
//
// 3 tabs:
//   Home     → profile + current active batch ka summary + quick access
//   My Batch → current active batch — BatchDetailScreen (read-only) khulti hai
//   Earnings → sabhi COMPLETED batches ki list, tap karke Settlement Rasid
// ═══════════════════════════════════════════════════════════════════════════

class FarmerDashboard extends StatefulWidget {
  final String ownerName;
  final String companyName;
  const FarmerDashboard({
    Key? key,
    required this.ownerName,
    required this.companyName,
  }) : super(key: key);

  @override
  State<FarmerDashboard> createState() => _FarmerDashboardState();
}

class _FarmerDashboardState extends State<FarmerDashboard> with CloudSyncMixin {
  int _currentIndex = 0;
  Map<String, dynamic>? _myFarmerData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMyData();
    startCloudSync();
  }

  @override
  void dispose() {
    stopCloudSync();
    super.dispose();
  }

  @override
  void onCloudDataChanged() {
    _loadMyData();
  }

  Future<void> _loadMyData() async {
    final phone = await SessionService.phone;
    final farmers = await CompanyStore.instance.getJsonList('companyFarmers');

    Map<String, dynamic>? myData;
    for (final f in farmers) {
      if (f['phone'] == phone) {
        myData = f;
        break;
      }
    }

    if (mounted) {
      setState(() {
        _myFarmerData = myData;
        _loading = false;
      });
    }
  }

  void _goToTab(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _FarmerHomeTab(
            farmerData: _myFarmerData,
            companyName: widget.companyName,
            ownerName: widget.ownerName,
            onGoToMyBatch: () => _goToTab(1),
            onGoToEarnings: () => _goToTab(2),
          ),
          _FarmerBatchTab(farmerData: _myFarmerData),
          _FarmerEarningsTab(farmerData: _myFarmerData),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _goToTab,
        selectedItemColor: AppColors.poultryColor,
        unselectedItemColor: Colors.grey.shade500,
        backgroundColor: Colors.white,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.egg_rounded),
            label: 'My Batch',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Earnings',
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED HELPERS — batch data se active/completed batch nikalna, date parse
// karna waghera. (Ye batch_detail_screen.dart ki calculation formula se
// duplicate NAHI hai — sirf halki summary ke liye hai, poora accurate FCR/
// cost breakdown "My Batch" tab mein BatchDetailScreen khud dikhata hai.)
// ═══════════════════════════════════════════════════════════════════════════

Map<String, dynamic>? _findActiveBatch(Map<String, dynamic>? farmerData) {
  final batches = farmerData?['batches'];
  if (batches is! List) return null;
  for (final b in batches) {
    if (b is! Map) continue;
    final status = (b['status'] ?? '').toString().toUpperCase();
    if (status != 'COMPLETED' && status != 'CLOSED') {
      return Map<String, dynamic>.from(b);
    }
  }
  return null;
}

List<Map<String, dynamic>> _findCompletedBatches(
  Map<String, dynamic>? farmerData,
) {
  final batches = farmerData?['batches'];
  if (batches is! List) return [];
  final result = <Map<String, dynamic>>[];
  for (final b in batches) {
    if (b is! Map) continue;
    final status = (b['status'] ?? '').toString().toUpperCase();
    if (status == 'COMPLETED' || status == 'CLOSED') {
      result.add(Map<String, dynamic>.from(b));
    }
  }
  return result.reversed.toList(); // sabse naya sabse upar
}

int _calcDaysOld(String? startDateStr) {
  if (startDateStr == null || startDateStr.trim().isEmpty) return 0;
  try {
    final parts = startDateStr.split('/');
    if (parts.length == 3) {
      final startDate = DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );
      final days = DateTime.now().difference(startDate).inDays;
      return days < 0 ? 0 : days;
    }
    final iso = DateTime.parse(startDateStr);
    final days = DateTime.now().difference(iso).inDays;
    return days < 0 ? 0 : days;
  } catch (_) {
    return 0;
  }
}

/// Batch ke dailyEntries se halka summary nikalta hai — sirf Home tab ke
/// stat-cards ke liye (poora/accurate FCR "My Batch" mein hi hai).
class _BatchQuickStats {
  final int liveChicks;
  final int totalMortality;
  final double mortalityPercent;
  final double latestWeight;
  const _BatchQuickStats({
    required this.liveChicks,
    required this.totalMortality,
    required this.mortalityPercent,
    required this.latestWeight,
  });
}

_BatchQuickStats _computeQuickStats(Map<String, dynamic> batch) {
  final int initialChicks = (batch['chicksCount'] as num?)?.toInt() ?? 0;
  final entries = (batch['dailyEntries'] as List?) ?? [];
  int mortality = 0;
  int sold = 0;
  double latestWeight = 0;

  for (final raw in entries) {
    if (raw is! Map) continue;
    final type = (raw['type'] ?? '').toString().toLowerCase();
    if (type == 'cost') {
      mortality += int.tryParse((raw['mortality'] ?? '0').toString()) ?? 0;
      final wt = double.tryParse((raw['weight'] ?? '0').toString()) ?? 0;
      if (wt > 0)
        latestWeight = wt; // list order — approx, theek hai summary ke liye
    } else if (type == 'sale') {
      sold += int.tryParse((raw['chicksSold'] ?? '0').toString()) ?? 0;
    }
  }

  final live = initialChicks - mortality - sold;
  final pct = initialChicks > 0 ? (mortality / initialChicks) * 100 : 0.0;

  return _BatchQuickStats(
    liveChicks: live < 0 ? 0 : live,
    totalMortality: mortality,
    mortalityPercent: pct,
    latestWeight: latestWeight,
  );
}

/// Batch ke finalSettlementSnapshot se net payout nikalta hai (Rule 1 ka
/// 'netPayout', ya Rule 2 approve hone par 'approvedPayout') — Rule 2 jab
/// tak Owner approve na kare tab tak null rehta hai.
double _batchNetPayout(Map<String, dynamic> batch) {
  final snap = batch['finalSettlementSnapshot'];
  if (snap is! Map) return 0.0;
  final netPayout = (snap['netPayout'] as num?)?.toDouble();
  if (netPayout != null) return netPayout;
  final approved = (snap['approvedPayout'] as num?)?.toDouble();
  return approved ?? 0.0;
}

// ═══════════════════════════════════════════════════════════════════════════
// HOME TAB
// ═══════════════════════════════════════════════════════════════════════════

class _FarmerHomeTab extends StatelessWidget {
  final Map<String, dynamic>? farmerData;
  final String companyName;
  final String ownerName;
  final VoidCallback onGoToMyBatch;
  final VoidCallback onGoToEarnings;
  const _FarmerHomeTab({
    required this.farmerData,
    required this.companyName,
    required this.ownerName,
    required this.onGoToMyBatch,
    required this.onGoToEarnings,
  });

  @override
  Widget build(BuildContext context) {
    final name = farmerData?['name'] as String? ?? ownerName;
    final phone = farmerData?['phone'] as String? ?? '';
    final accountNumber = farmerData?['accountNumber'] as String? ?? '';

    final activeBatch = _findActiveBatch(farmerData);
    final completed = _findCompletedBatches(farmerData);
    final lastPayment = completed.isNotEmpty
        ? _batchNetPayout(completed.first)
        : 0.0;

    _BatchQuickStats? stats;
    int? daysOld;
    if (activeBatch != null) {
      stats = _computeQuickStats(activeBatch);
      daysOld = _calcDaysOld(activeBatch['startDate']?.toString());
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: AppColors.poultryColor,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              companyName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Text(
              'Company Farmer',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await SessionService.logout();
              Get.offAll(() => const WelcomeScreen());
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Profile card ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.poultryColor,
                  AppColors.poultryColor.withOpacity(0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'F',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
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
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        phone,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                      if (accountNumber.isNotEmpty)
                        Text(
                          'A/C: $accountNumber',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Feed Confirm — RESERVED placeholder (feature abhi nahi bana,
          // jaisa decide kiya tha — sirf jagah reserve hai) ─────────────
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.local_shipping_outlined,
                  color: Colors.blue.shade700,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Feed Receive Confirm',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Jald aayega — jab feed dispatch hoga to yahan confirm kar sakoge',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Text(
            'Mera Batch',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),

          if (activeBatch == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade100),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.hourglass_empty_rounded,
                    color: Colors.orange.shade300,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Abhi koi batch assign nahi hua hai. Office Manager se sampark karein.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Row(
              children: [
                _FarmerStatCard(
                  icon: Icons.egg_rounded,
                  label: 'Batch — $daysOld din',
                  value: (activeBatch['batchId'] ?? activeBatch['id'] ?? '-')
                      .toString(),
                  color: AppColors.poultryColor,
                ),
                const SizedBox(width: 12),
                _FarmerStatCard(
                  icon: Icons.pets_rounded,
                  label: 'Live Chicks',
                  value: '${stats!.liveChicks}',
                  color: Colors.blue.shade700,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _FarmerStatCard(
                  icon: Icons.warning_amber_rounded,
                  label: 'Mortality',
                  value:
                      '${stats.totalMortality} (${stats.mortalityPercent.toStringAsFixed(1)}%)',
                  color: Colors.red.shade700,
                ),
                const SizedBox(width: 12),
                _FarmerStatCard(
                  icon: Icons.monitor_weight_outlined,
                  label: 'Last Weight',
                  value: stats.latestWeight > 0
                      ? '${stats.latestWeight.toStringAsFixed(2)} kg'
                      : '—',
                  color: Colors.purple.shade700,
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),
          Row(
            children: [
              _FarmerStatCard(
                icon: Icons.currency_rupee_rounded,
                label: 'Last Payment',
                value: lastPayment > 0
                    ? '₹${lastPayment.toStringAsFixed(0)}'
                    : '—',
                color: Colors.orange.shade700,
              ),
              const SizedBox(width: 12),
              _FarmerStatCard(
                icon: Icons.receipt_rounded,
                label: 'Receipts',
                value: '${completed.length}',
                color: Colors.teal.shade700,
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Text(
            'Quick Access',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          _FarmerActionTile(
            icon: Icons.egg_rounded,
            label: 'Mera Batch Dekho',
            sub: 'Current batch ki poori jankari',
            onTap: onGoToMyBatch,
          ),
          _FarmerActionTile(
            icon: Icons.account_balance_wallet_rounded,
            label: 'Meri Earnings Dekho',
            sub: 'Purane settlement receipts',
            onTap: onGoToEarnings,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MY BATCH TAB — active batch ka summary card, tap/button se poori
// BatchDetailScreen (read-only) khulti hai.
// ═══════════════════════════════════════════════════════════════════════════

class _FarmerBatchTab extends StatelessWidget {
  final Map<String, dynamic>? farmerData;
  const _FarmerBatchTab({required this.farmerData});

  @override
  Widget build(BuildContext context) {
    final activeBatch = _findActiveBatch(farmerData);
    final farmerId = farmerData?['id']?.toString() ?? '';

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: AppColors.poultryColor,
        title: const Text(
          'Mera Batch',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        automaticallyImplyLeading: false,
      ),
      body: activeBatch == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.egg_rounded,
                      size: 72,
                      color: AppColors.poultryColor.withOpacity(0.3),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Abhi koi active batch nahi hai',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Office Manager batch assign karega, tab yahan dikhega.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildActiveBatchCard(context, activeBatch, farmerId),
                ],
              ),
            ),
    );
  }

  Widget _buildActiveBatchCard(
    BuildContext context,
    Map<String, dynamic> batch,
    String farmerId,
  ) {
    final stats = _computeQuickStats(batch);
    final daysOld = _calcDaysOld(batch['startDate']?.toString());
    final batchId = (batch['batchId'] ?? batch['id'] ?? '-').toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.poultryColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text('🐣', style: TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      batchId,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '$daysOld din se chal raha hai',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _miniStatBox('Live Chicks', '${stats.liveChicks}'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _miniStatBox(
                  'Mortality',
                  '${stats.mortalityPercent.toStringAsFixed(1)}%',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.visibility_rounded),
              label: const Text('Poora Batch Detail Dekho'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.poultryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BatchDetailScreen(
                      farmerId: farmerId,
                      batchData: batch,
                      userRole: 'Company Farmer',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStatBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EARNINGS TAB — sabhi COMPLETED batches ki list, tap karke Settlement
// Rasid (BatchDetailScreen ke andar) khulti hai.
// ═══════════════════════════════════════════════════════════════════════════

class _FarmerEarningsTab extends StatelessWidget {
  final Map<String, dynamic>? farmerData;
  const _FarmerEarningsTab({required this.farmerData});

  @override
  Widget build(BuildContext context) {
    final completed = _findCompletedBatches(farmerData);
    final farmerId = farmerData?['id']?.toString() ?? '';
    final totalEarnings = completed.fold<double>(
      0.0,
      (sum, b) => sum + _batchNetPayout(b),
    );

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: AppColors.poultryColor,
        title: const Text(
          'Meri Earnings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.poultryColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  'Total Earnings',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  '₹${totalEarnings.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${completed.length} settled batch${completed.length == 1 ? '' : 'es'}',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Payment History',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          if (completed.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 48,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Koi payment record nahi',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Jab bhi batch settle hoga, yahan dikhega',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            )
          else
            ...completed.map((batch) {
              final batchId = (batch['batchId'] ?? batch['id'] ?? '-')
                  .toString();
              final payout = _batchNetPayout(batch);
              final completedOn = (batch['completedOn'] ?? '').toString();
              String dateLabel = '';
              if (completedOn.isNotEmpty) {
                try {
                  final d = DateTime.parse(completedOn);
                  dateLabel =
                      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
                } catch (_) {}
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.poultryColor.withOpacity(0.12),
                    child: const Text('🧾'),
                  ),
                  title: Text(
                    batchId,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    dateLabel.isNotEmpty ? 'Settled: $dateLabel' : 'Settled',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(
                    payout > 0 ? '₹${payout.toStringAsFixed(0)}' : '—',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.poultryColor,
                    ),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BatchDetailScreen(
                          farmerId: farmerId,
                          batchData: batch,
                          userRole: 'Company Farmer',
                        ),
                      ),
                    );
                  },
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ── Shared Widgets ────────────────────────────────────────────
class _FarmerStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _FarmerStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _FarmerActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
  const _FarmerActionTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Icon(icon, color: AppColors.poultryColor),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      ),
    );
  }
}
