// lib/screens/dashboards/office_manager_dashboard.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../main.dart';
import '../../services/session_service.dart';
import '../../services/company_store.dart';
import '../welcome_screen.dart';

class OfficeManagerDashboard extends StatefulWidget {
  final String ownerName;
  final String companyName;
  const OfficeManagerDashboard({
    Key? key,
    required this.ownerName,
    required this.companyName,
  }) : super(key: key);

  @override
  State<OfficeManagerDashboard> createState() => _OfficeManagerDashboardState();
}

class _OfficeManagerDashboardState extends State<OfficeManagerDashboard> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _OMHomeTab(
            ownerName: widget.ownerName,
            companyName: widget.companyName,
          ),
          _OMFarmersTab(),
          _OMStockTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        selectedItemColor: AppColors.defaultPrimary,
        unselectedItemColor: Colors.grey.shade500,
        backgroundColor: Colors.white,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_rounded),
            label: 'Farmers',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_rounded),
            label: 'Stock',
          ),
        ],
      ),
    );
  }
}

// ── Tab 1: Home ──────────────────────────────────────────────
class _OMHomeTab extends StatefulWidget {
  final String ownerName;
  final String companyName;
  const _OMHomeTab({required this.ownerName, required this.companyName});
  @override
  State<_OMHomeTab> createState() => _OMHomeTabState();
}

class _OMHomeTabState extends State<_OMHomeTab> {
  List<Map<String, dynamic>> _farmers = [];
  Map<String, double> _feedStock = {};
  List<Map<String, dynamic>> _medicines = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final store = CompanyStore.instance;
    final farmers = await store.getJsonList('companyFarmers');
    final feedStock = await store.getFeedStockMap();
    final medicines = await store.getJsonList('medicineStockList');
    if (mounted) {
      setState(() {
        _farmers = farmers;
        _feedStock = feedStock;
        _medicines = medicines;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final starter = (_feedStock['Starter'] ?? 0.0).toStringAsFixed(0);
    final grower = (_feedStock['Grower'] ?? 0.0).toStringAsFixed(0);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: AppColors.defaultPrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.companyName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Text(
              'Office Manager',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await SessionService.logout();
              Get.offAll(() => const WelcomeScreen());
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.defaultPrimary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.defaultPrimary.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.badge_rounded,
                          color: AppColors.defaultPrimary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.ownerName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.defaultPrimary,
                                ),
                              ),
                              const Text(
                                'Office Manager Access',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _StatCard(
                        icon: Icons.people_rounded,
                        label: 'Total Farmers',
                        value: '${_farmers.length}',
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        icon: Icons.inventory_2_rounded,
                        label: 'Starter Stock',
                        value: '$starter kg',
                        color: Colors.green.shade700,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _StatCard(
                        icon: Icons.grass_rounded,
                        label: 'Grower Stock',
                        value: '$grower kg',
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        icon: Icons.medication_rounded,
                        label: 'Medicine Items',
                        value: '${_medicines.length}',
                        color: Colors.red.shade700,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Quick Access',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _QuickTile(
                    icon: Icons.people_rounded,
                    label: 'Farmers List',
                    sub: 'Farmer details dekhein',
                    onTap: () {},
                  ),
                  _QuickTile(
                    icon: Icons.inventory_2_rounded,
                    label: 'Stock Entry',
                    sub: 'Feed / Medicine stock update',
                    onTap: () {},
                  ),
                  _QuickTile(
                    icon: Icons.shopping_cart_rounded,
                    label: 'Feed Purchase',
                    sub: 'Nayi feed kharid darj karein',
                    onTap: () {},
                  ),
                ],
              ),
            ),
    );
  }
}

// ── Tab 2: Farmers ───────────────────────────────────────────
class _OMFarmersTab extends StatefulWidget {
  @override
  State<_OMFarmersTab> createState() => _OMFarmersTabState();
}

class _OMFarmersTabState extends State<_OMFarmersTab> {
  List<Map<String, dynamic>> _farmers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final farmers = await CompanyStore.instance.getJsonList('companyFarmers');
    if (mounted)
      setState(() {
        _farmers = farmers;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.defaultPrimary,
        title: const Text(
          'Farmers',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _farmers.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 60, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'Koi farmer nahi mila',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _farmers.length,
                itemBuilder: (context, i) {
                  final f = _farmers[i];
                  final name = f['name'] as String? ?? '?';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.defaultPrimary,
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(f['phone'] as String? ?? ''),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () {
                        // TODO: FarmerProfileScreen navigate karo
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}

// ── Tab 3: Stock ─────────────────────────────────────────────
class _OMStockTab extends StatefulWidget {
  @override
  State<_OMStockTab> createState() => _OMStockTabState();
}

class _OMStockTabState extends State<_OMStockTab> {
  Map<String, double> _feedStock = {};
  List<Map<String, dynamic>> _medicines = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final feedStock = await CompanyStore.instance.getFeedStockMap();
    final medicines = await CompanyStore.instance.getJsonList(
      'medicineStockList',
    );
    if (mounted)
      setState(() {
        _feedStock = feedStock;
        _medicines = medicines;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.defaultPrimary,
        title: const Text(
          'Stock & Feed',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Feed Stock',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ..._feedStock.entries.map(
                            (e) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    e.key,
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                  Text(
                                    '${e.value.toStringAsFixed(1)} kg',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Medicine Stock',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_medicines.isEmpty)
                            const Text(
                              'Koi medicine stock nahi',
                              style: TextStyle(color: Colors.grey),
                            )
                          else
                            ..._medicines.map(
                              (m) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      m['name'] as String? ?? '',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      '${m['quantity'] ?? 0} units',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Feed Purchase Add Karo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.defaultPrimary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: () {
                      /* TODO */
                    },
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.medication_rounded),
                    label: const Text('Medicine Entry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: () {
                      /* TODO */
                    },
                  ),
                ],
              ),
            ),
    );
  }
}

// ── Shared Widgets ────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard({
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

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: AppColors.defaultPrimary),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      ),
    );
  }
}
