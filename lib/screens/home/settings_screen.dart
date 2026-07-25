import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../services/company_store.dart';
import '../../services/permission_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);

  bool _isLoading = true;
  late TextEditingController _minCtrl;
  late TextEditingController _maxCtrl;
  Map<String, Map<String, Map<String, bool>>> _matrix = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final minD = await CompanyStore.instance.getInt('minLiftingDays') ?? 23;
    final maxD = await CompanyStore.instance.getInt('maxLiftingDays') ?? 60;
    final matrix = await PermissionService.getFullMatrix();

    _minCtrl = TextEditingController(text: '$minD');
    _maxCtrl = TextEditingController(text: '$maxD');

    if (!mounted) return;
    setState(() {
      _matrix = matrix;
      _isLoading = false;
    });
  }

  Future<void> _saveLiftingRange() async {
    int? minD = int.tryParse(_minCtrl.text.trim());
    int? maxD = int.tryParse(_maxCtrl.text.trim());

    if (minD == null || maxD == null || minD < 20 || maxD > 60 || minD > maxD) {
      Get.snackbar(
        'Invalid Range',
        'Sahi range daalein! Min 20 se kam nahi, Max 60 se zyada nahi.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      return;
    }

    await CompanyStore.instance.setInt('minLiftingDays', minD);
    await CompanyStore.instance.setInt('maxLiftingDays', maxD);

    Get.snackbar(
      'Settings Saved ✅',
      'Lifting criteria set: $minD - $maxD days.',
      backgroundColor: primaryGreen,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(15),
    );
  }

  Future<void> _togglePermission(
    String role,
    String moduleId,
    String action,
    bool value,
  ) async {
    setState(() => _matrix[role]![moduleId]![action] = value);
    await PermissionService.saveFullMatrix(_matrix);
  }

  void _setAllForModule(String role, String moduleId, bool value) {
    setState(() {
      for (final a in PermissionService.actions) {
        _matrix[role]![moduleId]![a] = value;
      }
    });
    PermissionService.saveFullMatrix(_matrix);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        elevation: 0,
        title: const Text(
          'Settings ⚙️',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryGreen))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionCard(
                  title: '🚜 App Settings',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Lifting Ready Range',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _minCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Minimum Din',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _maxCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Maximum Din',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _saveLiftingRange,
                          child: const Text(
                            'Save Lifting Range',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '🔐 Role Permissions',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ..._matrix.keys.map((role) => _roleCard(role)),
                const SizedBox(height: 20),
              ],
            ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: primaryGreen,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _roleCard(String role) {
    final moduleMap = _matrix[role]!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Row(
            children: [
              const Icon(Icons.badge_rounded, color: primaryGreen, size: 20),
              const SizedBox(width: 8),
              Text(
                role,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          children: PermissionService.modules.map((module) {
            final perms = moduleMap[module.id]!;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(module.emoji, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          module.label,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () =>
                            _setAllForModule(role, module.id, true),
                        child: const Text(
                          'All ON',
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () =>
                            _setAllForModule(role, module.id, false),
                        child: const Text(
                          'All OFF',
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    children: PermissionService.actions.map((action) {
                      final val = perms[action] ?? false;
                      return FilterChip(
                        label: Text(
                          _actionLabel(action),
                          style: const TextStyle(fontSize: 11),
                        ),
                        selected: val,
                        selectedColor: primaryGreen.withOpacity(0.18),
                        checkmarkColor: primaryGreen,
                        onSelected: (v) =>
                            _togglePermission(role, module.id, action, v),
                      );
                    }).toList(),
                  ),
                  const Divider(height: 18),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'view':
        return 'View';
      case 'add':
        return 'Add';
      case 'edit':
        return 'Edit';
      case 'delete':
        return 'Delete';
      default:
        return action;
    }
  }
}
