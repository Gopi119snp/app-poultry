// lib/screens/dashboards/field_manager_dashboard.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../main.dart';
import '../../services/session_service.dart';
import '../../services/company_store.dart';
import '../welcome_screen.dart';

class FieldManagerDashboard extends StatefulWidget {
  final String ownerName;
  final String companyName;
  const FieldManagerDashboard({
    Key? key,
    required this.ownerName,
    required this.companyName,
  }) : super(key: key);

  @override
  State<FieldManagerDashboard> createState() => _FieldManagerDashboardState();
}

class _FieldManagerDashboardState extends State<FieldManagerDashboard> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _FMHomeTab(
            ownerName: widget.ownerName,
            companyName: widget.companyName,
          ),
          _FMFarmersTab(),
          _FMActivitiesTab(),
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
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_rounded),
            label: 'Farmers',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_rounded),
            label: 'Activities',
          ),
        ],
      ),
    );
  }
}

// ── Tab 1: Home ──────────────────────────────────────────────
class _FMHomeTab extends StatefulWidget {
  final String ownerName;
  final String companyName;
  const _FMHomeTab({required this.ownerName, required this.companyName});
  @override
  State<_FMHomeTab> createState() => _FMHomeTabState();
}

class _FMHomeTabState extends State<_FMHomeTab> {
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
    final activeFarmers = _farmers
        .where((f) => f['status'] == 'active')
        .toList();

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: AppColors.poultryColor,
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
              'Field Manager',
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
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.poultryColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.poultryColor.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.agriculture_rounded,
                          color: AppColors.poultryColor,
                          size: 22,
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
                                  color: AppColors.poultryColor,
                                ),
                              ),
                              const Text(
                                'Field Manager Access',
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
                      _FMStatCard(
                        icon: Icons.people_rounded,
                        label: 'Total Farmers',
                        value: '${_farmers.length}',
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 12),
                      _FMStatCard(
                        icon: Icons.check_circle_rounded,
                        label: 'Active Farmers',
                        value: '${activeFarmers.length}',
                        color: AppColors.poultryColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Field Activities',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FMActionTile(
                    icon: Icons.monitor_weight_rounded,
                    label: 'Weight Entry',
                    sub: 'Farmers ka weight darj karein',
                    color: Colors.blue.shade700,
                    onTap: () {},
                  ),
                  _FMActionTile(
                    icon: Icons.remove_circle_rounded,
                    label: 'Mortality Entry',
                    sub: 'Bird mortality record karein',
                    color: Colors.red.shade700,
                    onTap: () {},
                  ),
                  _FMActionTile(
                    icon: Icons.local_shipping_rounded,
                    label: 'Lifting Record',
                    sub: 'Bird lifting data darj karein',
                    color: Colors.orange.shade700,
                    onTap: () {},
                  ),
                  _FMActionTile(
                    icon: Icons.people_rounded,
                    label: 'Farmers List',
                    sub: 'Apne assigned farmers dekhein',
                    color: AppColors.poultryColor,
                    onTap: () {},
                  ),
                ],
              ),
            ),
    );
  }
}

// ── Tab 2: Farmers ───────────────────────────────────────────
class _FMFarmersTab extends StatefulWidget {
  @override
  State<_FMFarmersTab> createState() => _FMFarmersTabState();
}

class _FMFarmersTabState extends State<_FMFarmersTab> {
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
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: AppColors.poultryColor,
        title: const Text(
          'My Farmers',
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
                  Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'Koi farmer assign nahi hai',
                    style: TextStyle(color: Colors.grey, fontSize: 15),
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
                  final isActive = f['status'] == 'active';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isActive
                            ? AppColors.poultryColor
                            : Colors.grey,
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

// ── Tab 3: Activities ────────────────────────────────────────
class _FMActivitiesTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: AppColors.poultryColor,
        title: const Text(
          'Field Activities',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Aaj ki Activities',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          _ActivityCard(
            icon: Icons.monitor_weight_rounded,
            title: 'Weight Entry',
            description: 'Farmers ke batch ka daily weight record karein',
            color: Colors.blue.shade700,
            onTap: () {},
          ),
          _ActivityCard(
            icon: Icons.remove_circle_outline_rounded,
            title: 'Mortality Entry',
            description: 'Mrityu ki sankhya darj karein',
            color: Colors.red.shade700,
            onTap: () {},
          ),
          _ActivityCard(
            icon: Icons.local_shipping_rounded,
            title: 'Lifting Record',
            description: 'Bird lifting aur sale data',
            color: Colors.orange.shade700,
            onTap: () {},
          ),
          _ActivityCard(
            icon: Icons.feed_rounded,
            title: 'Feed Distribution',
            description: 'Feed vitaran record karein',
            color: Colors.teal,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

// ── Shared Widgets ────────────────────────────────────────────
class _FMStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _FMStatCard({
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
                fontSize: 22,
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

class _FMActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final VoidCallback onTap;
  const _FMActionTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;
  const _ActivityCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
