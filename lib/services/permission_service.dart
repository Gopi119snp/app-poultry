import 'dart:convert';
import 'company_store.dart';
import 'session_service.dart';

class PermissionModule {
  final String id;
  final String label;
  final String emoji;
  const PermissionModule(this.id, this.label, this.emoji);
}

/// Poore app ka permission system yahi se control hota hai.
/// Jab bhi Profile se naya role add hoga, ye service khud-ba-khud
/// use handle kar lega — Settings screen ka code touch nahi karna padega.
class PermissionService {
  PermissionService._();

  static const List<String> actions = ['view', 'add', 'edit', 'delete'];

  static const List<PermissionModule> modules = [
    PermissionModule('batch', 'Batch Management', '🐔'),
    PermissionModule('farmers', 'Farmers', '🧑‍🌾'),
    PermissionModule('feedStock', 'Feed Inventory', '🌾'),
    PermissionModule('medicineStock', 'Medicine Inventory', '💊'),
    PermissionModule('purchaseExpense', 'Purchase / Expense', '🛒'),
    PermissionModule('sales', 'Sales', '💰'),
    PermissionModule('reports', 'Reports', '📊'),
    PermissionModule('accounts', 'Accounts', '🧾'),
    PermissionModule('settlement', 'Settlement Engine', '⚖️'),
  ];

  static const List<String> builtInRoles = ['Office Manager', 'Field Manager'];

  /// Saare roles — built-in + Profile se add kiye gaye custom roles.
  static Future<List<String>> getAllRoles() async {
    final customRaw = await CompanyStore.instance.getString('customRoles');
    List<String> custom = [];
    if (customRaw != null && customRaw.isNotEmpty) {
      try {
        custom = List<String>.from(json.decode(customRaw));
      } catch (_) {}
    }
    final all = <String>{...builtInRoles, ...custom};
    return all.toList();
  }

  /// ⭐ Profile screen se ye function call karna jab naya role add ho.
  /// Isse Settings screen automatically naya role dikhane lagega.
  static Future<void> registerCustomRole(String roleName) async {
    final roles = await getAllRoles();
    if (roles.contains(roleName)) return;

    final customRaw = await CompanyStore.instance.getString('customRoles');
    List<String> custom = [];
    if (customRaw != null && customRaw.isNotEmpty) {
      try {
        custom = List<String>.from(json.decode(customRaw));
      } catch (_) {}
    }
    custom.add(roleName);
    await CompanyStore.instance.setString('customRoles', json.encode(custom));

    final allPerms = await _loadRawPermissions();
    allPerms[roleName] = _emptyModuleMap();
    await _savePermissions(allPerms);
  }

  static Map<String, Map<String, bool>> _emptyModuleMap() {
    final map = <String, Map<String, bool>>{};
    for (final m in modules) {
      map[m.id] = {for (final a in actions) a: false};
    }
    return map;
  }

  static Future<Map<String, dynamic>> _loadRawPermissions() async {
    final raw = await CompanyStore.instance.getString('rolePermissions');
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(json.decode(raw));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _savePermissions(Map<String, dynamic> data) async {
    await CompanyStore.instance.setString('rolePermissions', json.encode(data));
  }

  /// Sabhi roles ka poora permission matrix — missing entries default-false.
  static Future<Map<String, Map<String, Map<String, bool>>>>
  getFullMatrix() async {
    final roles = await getAllRoles();
    final raw = await _loadRawPermissions();

    final Map<String, Map<String, Map<String, bool>>> result = {};

    for (final role in roles) {
      final roleData = (raw[role] is Map)
          ? Map<String, dynamic>.from(raw[role])
          : <String, dynamic>{};

      final Map<String, Map<String, bool>> moduleMap = {};
      for (final m in modules) {
        final modData = (roleData[m.id] is Map)
            ? Map<String, dynamic>.from(roleData[m.id])
            : <String, dynamic>{};

        moduleMap[m.id] = {for (final a in actions) a: (modData[a] == true)};
      }
      result[role] = moduleMap;
    }
    return result;
  }

  static Future<void> saveFullMatrix(
    Map<String, Map<String, Map<String, bool>>> matrix,
  ) async {
    final encoded = <String, dynamic>{};
    matrix.forEach((role, moduleMap) {
      encoded[role] = moduleMap.map((k, v) => MapEntry(k, v));
    });
    await _savePermissions(encoded);
  }

  /// Kisi bhi screen/button me ye check lagao:
  /// if (await PermissionService.can('sales', 'add')) { ShowButton }
  /// Owner ko hamesha sab permission hoti hai.
  static Future<bool> can(String moduleId, String action) async {
    final role = await SessionService.currentRole;
    if (role == null || role == 'Owner') return true;

    final raw = await _loadRawPermissions();
    final roleData = raw[role];
    if (roleData is! Map) return false;
    final modData = roleData[moduleId];
    if (modData is! Map) return false;
    return modData[action] == true;
  }
}
