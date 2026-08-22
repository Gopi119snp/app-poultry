import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../services/company_store.dart';
import '../../services/session_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 👥 STAFF LIST SCREEN — Office Managers + Field Managers, dono ek jagah.
// SIRF OWNER isko access kar sakta hai — role-check yahin gate karta hai.
// Yahan hi Owner "Allocation Mode" bhi set karta hai:
//   'single'   → ek farmer sirf ek hi employee ke under
//   'multiple' → ek farmer ek se zyada employees ke under bhi ja sakta hai
// ═══════════════════════════════════════════════════════════════════════════
class StaffListScreen extends StatefulWidget {
  const StaffListScreen({super.key});

  @override
  State<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends State<StaffListScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);

  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _farmers = [];
  String _allocationMode = 'single'; // 'single' | 'multiple'
  bool _isLoading = true;
  bool _isOwner = false;
  bool _roleChecked = false;

  @override
  void initState() {
    super.initState();
    _checkRoleAndLoad();
  }

  // ✅ Sirf Owner hi is screen ko dekh sakta hai
  Future<void> _checkRoleAndLoad() async {
    final role = await SessionService.currentRole ?? 'Owner';
    final bool owner = role.toLowerCase() == 'owner';
    if (mounted) {
      setState(() {
        _isOwner = owner;
        _roleChecked = true;
      });
    }
    if (owner) await _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final office = await CompanyStore.instance.getJsonList('officeManagers');
    final field = await CompanyStore.instance.getJsonList('fieldManagers');
    final farmers = await CompanyStore.instance.getJsonList('companyFarmers');
    final mode = await CompanyStore.instance.getString('farmerAllocationMode');

    final List<Map<String, dynamic>> combined = [
      ...office.map((m) => Map<String, dynamic>.from(m)),
      ...field.map((m) => Map<String, dynamic>.from(m)),
    ];

    if (mounted) {
      setState(() {
        _staff = combined;
        _farmers = farmers;
        _allocationMode = (mode == 'multiple') ? 'multiple' : 'single';
        _isLoading = false;
      });
    }
  }

  Future<void> _setAllocationMode(String mode) async {
    // ✅ NEW — 'multiple' mode par switch karne se pehle hi warning dikhao,
    // taaki Owner ko shuru mein hi pata ho ki isse tracking/reports mein
    // dikkat aa sakti hai. 'single' par wapas jaane par warning nahi.
    if (mode == 'multiple' && _allocationMode != 'multiple') {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Dhyan Dein ⚠️',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: const Text(
            'Multiple mode mein ek hi farmer ko ek se zyada employees ko '
            'diya ja sakega.\n\n'
            'Isse aage chalke ye pata karna mushkil ho sakta hai ki kis '
            'staff ne farmer ke record mein kya badlav kiya — Reports mein '
            'bhi confusion ho sakta hai.\n\n'
            'Ye bhi pata karna mushkil ho jayega ki kis staff ke under kaunsa '
            'farmer tha aur uska performance kaisa raha.\n\n'
            'Kya aap phir bhi Multiple mode chalu karna chahte hain?',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Haan, Chalu Karo'),
            ),
          ],
        ),
      );
      if (confirm != true)
        return; // Owner ne cancel kiya — mode change nahi hoga
    }

    setState(() => _allocationMode = mode);
    await CompanyStore.instance.setString('farmerAllocationMode', mode);
  }

  // Farmer ka allocatedEmployees list (naya data model — pehle allocatedEmployeeId
  // tha, ab list rakhte hain taaki multiple-employee mode bhi chal sake)
  List<Map<String, dynamic>> _employeesOf(Map<String, dynamic> farmer) {
    final raw = farmer['allocatedEmployees'];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  int _allocatedCount(String employeeId) {
    return _farmers.where((f) {
      return _employeesOf(f).any((e) => e['id']?.toString() == employeeId);
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    // Role check hone tak loader dikhao
    if (!_roleChecked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // ✅ Owner nahi hai → Access Denied
    if (!_isOwner) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: primaryGreen,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
            onPressed: () => Get.back(),
          ),
          title: const Text(
            'Farmer Allocation',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_rounded, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  'Ye section sirf Owner dekh sakta hai.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        title: const Text(
          '👥 Farmer Allocation',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _allocationModeCard(),
                Expanded(
                  child: _staff.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Abhi koi Office Manager ya Field Manager nahi hai.\n'
                              'Pehle Profile screen se staff add karein.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _staff.length,
                          itemBuilder: (context, index) {
                            final emp = _staff[index];
                            final String role = emp['role']?.toString() ?? '';
                            final Color roleColor = role == 'Office Manager'
                                ? Colors.blue.shade700
                                : Colors.orange.shade700;
                            final int count = _allocatedCount(
                              emp['id']?.toString() ?? '',
                            );

                            return GestureDetector(
                              onTap: () async {
                                final result = await Get.to(
                                  () => EmployeeDetailScreen(
                                    employee: emp,
                                    allocationMode: _allocationMode,
                                  ),
                                );
                                if (result == true) _load();
                              },
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
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        color: roleColor.withOpacity(0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          (emp['name']?.toString().isNotEmpty ==
                                                  true
                                              ? emp['name']
                                                    .toString()[0]
                                                    .toUpperCase()
                                              : '?'),
                                          style: TextStyle(
                                            color: roleColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            emp['name']?.toString() ?? '-',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: roleColor.withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              role,
                                              style: TextStyle(
                                                color: roleColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 10.5,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '🧑‍🌾 $count farmer allocated',
                                            style: TextStyle(
                                              color: Colors.grey.shade500,
                                              fontSize: 12,
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
                ),
              ],
            ),
    );
  }

  // ✅ NEW — Owner yahan se decide karta hai ki ek farmer sirf ek employee
  // ke under rahega, ya multiple employees ke under bhi ja sakta hai
  Widget _allocationModeCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
          const Text(
            '⚙️ Allocation Mode',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text('1 Farmer → 1 Employee')),
                  selected: _allocationMode == 'single',
                  selectedColor: primaryGreen,
                  labelStyle: TextStyle(
                    color: _allocationMode == 'single'
                        ? Colors.white
                        : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 11.5,
                  ),
                  onSelected: (_) => _setAllocationMode('single'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text('1 Farmer → Multiple')),
                  selected: _allocationMode == 'multiple',
                  selectedColor: primaryGreen,
                  labelStyle: TextStyle(
                    color: _allocationMode == 'multiple'
                        ? Colors.white
                        : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 11.5,
                  ),
                  onSelected: (_) => _setAllocationMode('multiple'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _allocationMode == 'single'
                ? 'Ek farmer sirf ek hi employee ke under rahega.'
                : 'Ek farmer ek se zyada employees ke under bhi ja sakta hai.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 👤 EMPLOYEE DETAIL SCREEN — Allocate button + allocated farmers list (Remove)
// ═══════════════════════════════════════════════════════════════════════════
class EmployeeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> employee;
  final String allocationMode; // 'single' | 'multiple'
  const EmployeeDetailScreen({
    super.key,
    required this.employee,
    required this.allocationMode,
  });

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);

  List<Map<String, dynamic>> _allocatedFarmers = [];
  bool _isLoading = true;
  bool _changed = false;

  String get _employeeId => widget.employee['id']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _employeesOf(Map<String, dynamic> farmer) {
    final raw = farmer['allocatedEmployees'];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final farmers = await CompanyStore.instance.getJsonList('companyFarmers');
    final allocated = farmers
        .where(
          (f) => _employeesOf(f).any((e) => e['id']?.toString() == _employeeId),
        )
        .map((f) => Map<String, dynamic>.from(f))
        .toList();
    if (mounted) {
      setState(() {
        _allocatedFarmers = allocated;
        _isLoading = false;
      });
    }
  }

  Future<void> _removeFarmer(Map<String, dynamic> farmer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Farmer Hatayein?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          '${farmer['name']} ko is employee ke under se hatana chahte hain?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final farmers = await CompanyStore.instance.getJsonList('companyFarmers');
    final String farmerId = farmer['id']?.toString() ?? '';
    for (var f in farmers) {
      if (f['id']?.toString() == farmerId) {
        final List<dynamic> current = (f['allocatedEmployees'] as List?) ?? [];
        current.removeWhere((e) => e['id']?.toString() == _employeeId);
        f['allocatedEmployees'] = current;
        break;
      }
    }
    await CompanyStore.instance.saveJsonList('companyFarmers', farmers);
    _changed = true;
    if (!mounted) return;
    Get.snackbar(
      'Removed ✅',
      '${farmer['name']} ko hata diya gaya',
      backgroundColor: primaryGreen,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final String name = widget.employee['name']?.toString() ?? '-';
    final String role = widget.employee['role']?.toString() ?? '';
    final String phone = widget.employee['phone']?.toString() ?? '';
    final Color roleColor = role == 'Office Manager'
        ? Colors.blue.shade700
        : Colors.orange.shade700;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Get.back(result: _changed);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: primaryGreen,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
            onPressed: () => Get.back(result: _changed),
          ),
          title: Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: roleColor.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: roleColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
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
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '📱 $phone',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: roleColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            role,
                            style: TextStyle(
                              color: roleColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Get.to(
                      () => AllocateFarmersScreen(
                        employee: widget.employee,
                        allocationMode: widget.allocationMode,
                      ),
                    );
                    if (result == true) {
                      _changed = true;
                      _load();
                    }
                  },
                  icon: const Icon(
                    Icons.person_add_alt_1_rounded,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Allocate Farmers',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Allocated Farmers (${_allocatedFarmers.length})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _allocatedFarmers.isEmpty
                  ? Center(
                      child: Text(
                        'Abhi koi farmer allocate nahi kiya gaya.',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _allocatedFarmers.length,
                      itemBuilder: (context, index) {
                        final farmer = _allocatedFarmers[index];
                        // Multiple mode mein ye farmer kis-kis employee ke
                        // under hai wo bhi dikha do, taaki Owner ko clarity ho
                        final otherEmployees = _employeesOf(farmer)
                            .where((e) => e['id']?.toString() != _employeeId)
                            .map((e) => e['name']?.toString() ?? '')
                            .where((n) => n.isNotEmpty)
                            .toList();

                        return Container(
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
                                    const SizedBox(height: 2),
                                    Text(
                                      '📱 ${farmer['phone'] ?? ''}',
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                    Text(
                                      '📍 ${farmer['district'] ?? ''}, ${farmer['state'] ?? ''}',
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                    if (otherEmployees.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          '👥 Bhi: ${otherEmployees.join(", ")}',
                                          style: TextStyle(
                                            color: Colors.blue.shade600,
                                            fontSize: 10.5,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _removeFarmer(farmer),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.remove_circle_outline_rounded,
                                    color: Colors.red.shade400,
                                    size: 20,
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
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ➕ ALLOCATE FARMERS SCREEN
// 'single' mode  → sirf un farmers ki list jo kisi ko bhi allocate nahi hain
// 'multiple' mode → sabhi farmers dikhte hain (jo is employee ko already
//                    allocate hain unko chhodkar), aur agar farmer kisi aur
//                    employee ke paas hai to wo naam badge mein dikhta hai
// ═══════════════════════════════════════════════════════════════════════════
class AllocateFarmersScreen extends StatefulWidget {
  final Map<String, dynamic> employee;
  final String allocationMode; // 'single' | 'multiple'
  const AllocateFarmersScreen({
    super.key,
    required this.employee,
    required this.allocationMode,
  });

  @override
  State<AllocateFarmersScreen> createState() => _AllocateFarmersScreenState();
}

class _AllocateFarmersScreenState extends State<AllocateFarmersScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);

  List<Map<String, dynamic>> _availableFarmers = [];
  final Set<String> _selectedIds = {};
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isLoading = true;

  String get _employeeId => widget.employee['id']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _employeesOf(Map<String, dynamic> farmer) {
    final raw = farmer['allocatedEmployees'];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final farmers = await CompanyStore.instance.getJsonList('companyFarmers');

    List<Map<String, dynamic>> available;
    if (widget.allocationMode == 'single') {
      // Sirf wahi farmers jo kisi ke bhi under nahi hain
      available = farmers
          .where((f) => _employeesOf(f).isEmpty)
          .map((f) => Map<String, dynamic>.from(f))
          .toList();
    } else {
      // Multiple mode — sabhi farmers, bas is employee ko already allocated
      // hue ko chhod do (dobara add na ho jaaye)
      available = farmers
          .where(
            (f) =>
                !_employeesOf(f).any((e) => e['id']?.toString() == _employeeId),
          )
          .map((f) => Map<String, dynamic>.from(f))
          .toList();
    }

    if (mounted) {
      setState(() {
        _availableFarmers = available;
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final String q = _searchCtrl.text.toLowerCase().trim();
    if (q.isEmpty) return _availableFarmers;
    return _availableFarmers.where((f) {
      final name = (f['name'] ?? '').toString().toLowerCase();
      final phone = (f['phone'] ?? '').toString().toLowerCase();
      final district = (f['district'] ?? '').toString().toLowerCase();
      return name.contains(q) || phone.contains(q) || district.contains(q);
    }).toList();
  }

  // ✅ NEW — Multiple mode mein jab Owner kisi already-allocated farmer ko
  // ek aur employee ko dena chahta hai, tab ye warning dikhti hai — kyunki
  // ek se zyada employees ek farmer ko manage karenge to Reports mein ye
  // pata karna mushkil ho jayega ki kis staff ne kya kiya/badla.
  Future<bool?> _confirmMultiAllocation({
    required String farmerName,
    required List<String> existingNames,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Dhyan Dein ⚠️',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          '"$farmerName" pehle se ${existingNames.join(", ")} ke paas hai.\n\n'
          'Agar aap ise is employee ko bhi de dete hain, to aage chalke ye '
          'pata karna mushkil ho sakta hai ki kis staff ne farmer ke record '
          'mein kya badlav kiya — Reports mein bhi confusion ho sakta hai.\n\n'
          'Ye bhi pata karna mushkil ho jayega ki kis staff ke under kaunsa '
          'farmer tha aur uska performance kaisa raha.\n\n'
          'Kya aap phir bhi allocate karna chahte hain?',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Haan, Allocate Karo'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_selectedIds.isEmpty) {
      Get.snackbar(
        'Error',
        'Kam se kam ek farmer select karein',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    final String empId = widget.employee['id']?.toString() ?? '';
    final String empName = widget.employee['name']?.toString() ?? '';
    final String empRole = widget.employee['role']?.toString() ?? '';

    final allFarmers = await CompanyStore.instance.getJsonList(
      'companyFarmers',
    );
    for (var f in allFarmers) {
      final String fid = f['id']?.toString() ?? '';
      if (!_selectedIds.contains(fid)) continue;

      final List<dynamic> current = (f['allocatedEmployees'] as List?) ?? [];

      if (widget.allocationMode == 'single') {
        // Single mode — poori list replace kar do (sirf ye ek employee)
        f['allocatedEmployees'] = [
          {'id': empId, 'name': empName, 'role': empRole},
        ];
      } else {
        // Multiple mode — existing list mein add karo (duplicate check ke saath)
        final bool alreadyThere = current.any(
          (e) => e['id']?.toString() == empId,
        );
        if (!alreadyThere) {
          current.add({'id': empId, 'name': empName, 'role': empRole});
        }
        f['allocatedEmployees'] = current;
      }
    }
    await CompanyStore.instance.saveJsonList('companyFarmers', allFarmers);
    if (!mounted) return;
    Get.back(result: true);
    Get.snackbar(
      'Saved ✅',
      '${_selectedIds.length} farmer allocate ho gaye',
      backgroundColor: primaryGreen,
      colorText: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        title: const Text(
          'Allocate Farmers',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Farmer Search Karein (Naam, Mobile, Jagah)...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
          ),
          if (_selectedIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_selectedIds.length} farmer select kiye',
                  style: TextStyle(
                    color: primaryGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.allocationMode == 'single'
                            ? 'Sabhi farmers kisi na kisi employee ko allocate ho chuke hain.'
                            : 'Koi farmer nahi mila.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final farmer = list[index];
                      final String fid = farmer['id']?.toString() ?? '';
                      final bool selected = _selectedIds.contains(fid);

                      // Multiple mode mein — ye farmer already kis-kis
                      // employee ke paas hai wo dikhado
                      final existingEmployees =
                          widget.allocationMode == 'multiple'
                          ? _employeesOf(farmer)
                                .map((e) => e['name']?.toString() ?? '')
                                .where((n) => n.isNotEmpty)
                                .toList()
                          : <String>[];

                      return GestureDetector(
                        onTap: () async {
                          // Deselect karna ho to seedha kar do, warning ki
                          // zaroorat nahi
                          if (selected) {
                            setState(() => _selectedIds.remove(fid));
                            return;
                          }
                          // ✅ NEW — agar ye farmer pehle se kisi aur
                          // employee ke paas hai (multiple mode), to select
                          // karne se pehle Owner ko warning dikhao
                          if (existingEmployees.isNotEmpty) {
                            final bool? proceed = await _confirmMultiAllocation(
                              farmerName: farmer['name']?.toString() ?? '-',
                              existingNames: existingEmployees,
                            );
                            if (proceed != true) return;
                          }
                          setState(() => _selectedIds.add(fid));
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: selected
                                ? primaryGreen.withOpacity(0.08)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? primaryGreen
                                  : Colors.grey.shade200,
                              width: selected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                color: selected
                                    ? primaryGreen
                                    : Colors.grey.shade400,
                              ),
                              const SizedBox(width: 12),
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
                                    const SizedBox(height: 2),
                                    Text(
                                      '📱 ${farmer['phone'] ?? ''}  •  📍 ${farmer['district'] ?? ''}',
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                    if (existingEmployees.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          '👥 Already: ${existingEmployees.join(", ")}',
                                          style: TextStyle(
                                            color: Colors.orange.shade700,
                                            fontSize: 10.5,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            color: Colors.white,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Save (${_selectedIds.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
