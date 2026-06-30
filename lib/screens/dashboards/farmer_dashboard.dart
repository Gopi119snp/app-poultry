// lib/screens/dashboards/farmer_dashboard.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../main.dart';
import '../../services/session_service.dart';
import '../../services/company_store.dart';
import '../welcome_screen.dart';

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

class _FarmerDashboardState extends State<FarmerDashboard> {
  int _currentIndex = 0;
  Map<String, dynamic>? _myFarmerData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
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
          ),
          _FarmerBatchTab(farmerData: _myFarmerData),
          _FarmerEarningsTab(farmerData: _myFarmerData),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
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

class _FarmerHomeTab extends StatelessWidget {
  final Map<String, dynamic>? farmerData;
  final String companyName;
  final String ownerName;
  const _FarmerHomeTab({
    required this.farmerData,
    required this.companyName,
    required this.ownerName,
  });

  @override
  Widget build(BuildContext context) {
    final name = farmerData?['name'] as String? ?? ownerName;
    final phone = farmerData?['phone'] as String? ?? '';
    final accountNumber = farmerData?['accountNumber'] as String? ?? '';

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
          const Text(
            'Mera Batch',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _FarmerStatCard(
                icon: Icons.egg_rounded,
                label: 'Active Batch',
                value: '—',
                color: AppColors.poultryColor,
              ),
              const SizedBox(width: 12),
              _FarmerStatCard(
                icon: Icons.trending_up_rounded,
                label: 'Current FCR',
                value: '—',
                color: Colors.blue.shade700,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _FarmerStatCard(
                icon: Icons.currency_rupee_rounded,
                label: 'Last Payment',
                value: '—',
                color: Colors.orange.shade700,
              ),
              const SizedBox(width: 12),
              _FarmerStatCard(
                icon: Icons.receipt_rounded,
                label: 'Receipts',
                value: '0',
                color: Colors.purple.shade700,
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
            sub: 'Current batch ki jankari',
            onTap: () {},
          ),
          _FarmerActionTile(
            icon: Icons.trending_up_rounded,
            label: 'FCR Report',
            sub: 'Feed Conversion Ratio dekhein',
            onTap: () {},
          ),
          _FarmerActionTile(
            icon: Icons.receipt_long_rounded,
            label: 'Settlement Receipt',
            sub: 'Apni payment receipt',
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _FarmerBatchTab extends StatelessWidget {
  final Map<String, dynamic>? farmerData;
  const _FarmerBatchTab({required this.farmerData});

  @override
  Widget build(BuildContext context) {
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
      body: Center(
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
              'Batch detail yahan aayega',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.egg_rounded),
              label: const Text('Batch Dekho'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.poultryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
              ),
              onPressed: () {
                // TODO: BatchDetailScreen navigate karo
                // Get.to(() => BatchDetailScreen(farmerData: farmerData, userRole: 'farmer'));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FarmerEarningsTab extends StatelessWidget {
  final Map<String, dynamic>? farmerData;
  const _FarmerEarningsTab({required this.farmerData});

  @override
  Widget build(BuildContext context) {
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
            child: const Column(
              children: [
                Text(
                  'Total Earnings',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                SizedBox(height: 8),
                Text(
                  '₹ —',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Abhi tak',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
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
                  'Jab bhi payment hogi, yahan dikhegi',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.receipt_long_rounded),
            label: const Text('Settlement Receipt Download'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.poultryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
            ),
            onPressed: () {
              /* TODO */
            },
          ),
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
                fontSize: 20,
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
