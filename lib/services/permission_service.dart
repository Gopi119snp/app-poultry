import 'dart:convert';
import 'company_store.dart';
import 'session_service.dart';

/// Ek node — ya to LEAF hoga (jispe View/Add/Edit/Delete permission set
/// hoti hai) ya GROUP (sirf UI mein expand/collapse ke liye — khud koi
/// permission store nahi karta, sirf apne children ko organize karta hai).
class PermissionNode {
  final String id;
  final String label;
  final String emoji;
  final bool isLeaf;
  final bool
  hasPermission; // ⭐ Group hote hue bhi khud ka Overall permission rakhega
  final List<PermissionNode> children;

  const PermissionNode({
    required this.id,
    required this.label,
    this.emoji = '📁',
    this.isLeaf = true,
    this.hasPermission = false,
    this.children = const [],
  });
}

class PersonInfo {
  final String phone;
  final String name;
  final String role;
  const PersonInfo({
    required this.phone,
    required this.name,
    required this.role,
  });
}

class PermissionService {
  PermissionService._();

  static const List<String> actions = ['view', 'add', 'edit', 'delete'];

  /// ⭐ Poore app ka permission tree — Owner ke diagram ke hisaab se.
  static const List<PermissionNode> tree = [
    PermissionNode(
      id: 'farmer',
      label: 'Farmer',
      emoji: '🧑‍🌾',
      isLeaf: false,
      children: [
        PermissionNode(
          id: 'farmerProfileGroup',
          label: 'Farmer Profile / Document',
          emoji: '👤',
          isLeaf: false,
          children: [
            PermissionNode(
              id: 'farmerProfile',
              label: 'Profile / Document',
              emoji: '📇',
            ),
            PermissionNode(
              id: 'farmerBankDetail',
              label: 'Bank Detail',
              emoji: '🏦',
            ),
          ],
        ),
        PermissionNode(
          id: 'farmerReportGroup',
          label: 'Farmer Report',
          emoji: '📈',
          isLeaf: false,
          hasPermission: true,
          children: [
            PermissionNode(
              id: 'farmerDetailInfo',
              label: 'Detail Information Dekho',
              emoji: '🔍',
            ),
            PermissionNode(
              id: 'farmerAllReports',
              label: 'Sabhi Reports Dekho',
              emoji: '📑',
            ),
          ],
        ),
        PermissionNode(
          id: 'batchCreate',
          label: 'Farmer Batch (Making)',
          emoji: '🐣',
        ),
        PermissionNode(
          id: 'batchTracking',
          label: 'Farmer Batch Tracking Detail',
          emoji: '📋',
          isLeaf: false,
          children: [
            PermissionNode(
              id: 'stockRecord',
              label: 'Stock Record',
              emoji: '📦',
              isLeaf: false,
              children: [
                PermissionNode(
                  id: 'feedEntry',
                  label: 'Feed Entry',
                  emoji: '🌾',
                ),
                PermissionNode(
                  id: 'averageWeight',
                  label: 'Average Weight',
                  emoji: '⚖️',
                ),
                PermissionNode(
                  id: 'mortality',
                  label: 'Mortality',
                  emoji: '💀',
                ),
                PermissionNode(
                  id: 'remainingFeed',
                  label: 'Actual Remaining Feed',
                  emoji: '📊',
                ),
              ],
            ),
            PermissionNode(id: 'batchSales', label: 'Sales', emoji: '💰'),
            PermissionNode(id: 'batchMedicine', label: 'Medicine', emoji: '💊'),
            PermissionNode(
              id: 'dailyUpdateList',
              label: 'Daily Update List',
              emoji: '📝',
            ),
            PermissionNode(id: 'feedReturn', label: 'Return Feed', emoji: '↩️'),
            PermissionNode(id: 'batchEnd', label: 'Batch End', emoji: '🏁'),
          ],
        ),
      ],
    ),
    PermissionNode(
      id: 'stockManagement',
      label: 'Stock Management',
      emoji: '📦',
      isLeaf: false,
      hasPermission: true,
      children: [
        PermissionNode(
          id: 'feedStock',
          label: 'Feed Stock Overview',
          emoji: '🌾',
        ),
        PermissionNode(
          id: 'medicineStock',
          label: 'Medicine Stock Overview',
          emoji: '💉',
        ),
      ],
    ),
    PermissionNode(
      id: 'purchaseExpense',
      label: 'Purchase / Expense',
      emoji: '🛒',
      isLeaf: false,
      hasPermission: true,
      children: [
        PermissionNode(
          id: 'chicksPurchase',
          label: 'Chicks Purchase',
          emoji: '🐣',
          isLeaf: false,
          hasPermission: true,
          children: [
            PermissionNode(
              id: 'chicksPurchaseEntry',
              label: 'Purchase Entry',
              emoji: '🛒',
            ),
            PermissionNode(
              id: 'chicksAllocation',
              label: 'Allocation (Farmer ko dena)',
              emoji: '📤',
            ),
          ],
        ),
        PermissionNode(
          id: 'feedPurchase',
          label: 'Feed Purchase',
          emoji: '🌾',
          isLeaf: false,
          hasPermission: true,
          children: [
            PermissionNode(
              id: 'feedPurchaseEntry',
              label: 'Purchase Entry',
              emoji: '🛒',
            ),
            PermissionNode(
              id: 'feedAllocation',
              label: 'Allocation (Farmer ko dena)',
              emoji: '📤',
            ),
          ],
        ),
        PermissionNode(
          id: 'medicinePurchase',
          label: 'Medicine Purchase',
          emoji: '💊',
          isLeaf: false,
          hasPermission: true,
          children: [
            PermissionNode(
              id: 'medicinePurchaseEntry',
              label: 'Purchase Entry',
              emoji: '🛒',
            ),
            PermissionNode(
              id: 'medicineAllocation2',
              label: 'Allocation (Farmer ko dena)',
              emoji: '📤',
            ),
          ],
        ),
        PermissionNode(
          id: 'labourExpense',
          label: 'Labour / Manager Expense',
          emoji: '👷',
        ),
        PermissionNode(id: 'otherExpense', label: 'Other Expense', emoji: '📋'),
      ],
    ),
    PermissionNode(
      id: 'sales',
      label: 'Sales / Lifting',
      emoji: '💰',
      isLeaf: false,
      hasPermission: true,
      children: [
        PermissionNode(id: 'chicksSale', label: 'Chicks Sale', emoji: '🐣'),
        PermissionNode(id: 'feedSale', label: 'Feed Sale', emoji: '🌾'),
        PermissionNode(id: 'medicineSale', label: 'Medicine Sale', emoji: '💊'),
        PermissionNode(
          id: 'chickenLiftingSale',
          label: 'Chicken Sale (Lifting)',
          emoji: '🐔',
        ),
      ],
    ),
    PermissionNode(
      id: 'reports',
      label: 'Reports',
      emoji: '📊',
      isLeaf: false,
      hasPermission: true,
      children: [
        PermissionNode(
          id: 'opExpenseRecoveryReport',
          label: 'Operational Expense Recovery',
          emoji: '💹',
        ),
        PermissionNode(
          id: 'batchPerformanceReport',
          label: 'Batch Performance',
          emoji: '📈',
        ),
        PermissionNode(
          id: 'farmerProfitLossReport',
          label: 'Farmer Profit / Loss',
          emoji: '📉',
        ),
      ],
    ),
    PermissionNode(
      id: 'accounts',
      label: 'Accounts',
      emoji: '🧾',
      isLeaf: false,
      hasPermission: true,
      children: [
        PermissionNode(id: 'accountsOverview', label: 'Overview', emoji: '📊'),
        PermissionNode(id: 'accountsUdhaar', label: 'Udhaar', emoji: '⏳'),
        PermissionNode(id: 'accountsKharcha', label: 'Kharcha', emoji: '💸'),
        PermissionNode(id: 'accountsKharida', label: 'Kharida', emoji: '🛒'),
        PermissionNode(id: 'accountsSales', label: 'Sales', emoji: '🎁'),
      ],
    ),
    PermissionNode(id: 'settlement', label: 'Settlement Engine', emoji: '⚖️'),
    PermissionNode(
      id: 'lifting',
      label: 'Lifting',
      emoji: '🚜',
      isLeaf: false,
      hasPermission: true,
      children: [
        PermissionNode(
          id: 'liftingRangeSet',
          label: 'Range Set Karna',
          emoji: '⚙️',
        ),
        PermissionNode(
          id: 'liftingListView',
          label: 'Lifting List Dekhna',
          emoji: '📋',
        ),
      ],
    ),
    PermissionNode(
      id: 'feedConsumptionRule',
      label: 'Feed Consumption Rule',
      emoji: '🌿',
    ),
    PermissionNode(
      id: 'weightGrowthRule',
      label: 'Weight Growth Rule',
      emoji: '📈',
    ),
    PermissionNode(
      id: 'performanceAlertRule',
      label: 'Performance Alert Rule',
      emoji: '🚦',
    ),
    PermissionNode(
      id: 'settingsPermissions',
      label: 'Settings & Permissions',
      emoji: '🔐',
    ),
  ];

  /// Sirf leaf modules ki flat list — actual permission isi par store hoti hai.
  static List<PermissionNode> get leafModules {
    final List<PermissionNode> result = [];
    void walk(List<PermissionNode> nodes) {
      for (final n in nodes) {
        if (n.isLeaf) {
          result.add(n);
        } else {
          if (n.hasPermission)
            result.add(n); // ⭐ group ka khud ka permission bhi count ho
          walk(n.children);
        }
      }
    }

    walk(tree);
    return result;
  }

  static const List<String> builtInRoles = ['Office Manager', 'Field Manager'];

  // ── Roles ─────────────────────────────────────────────────────────────────

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

    final allPerms = await _loadRawRolePermissions();
    allPerms[roleName] = _emptyModuleMap();
    await _saveRolePermissions(allPerms);
  }

  static Map<String, Map<String, bool>> _emptyModuleMap() {
    final map = <String, Map<String, bool>>{};
    for (final m in leafModules) {
      map[m.id] = {for (final a in actions) a: false};
    }
    return map;
  }

  static Map<String, Map<String, bool>> _fillModuleMap(
    Map<String, dynamic> raw,
  ) {
    final map = <String, Map<String, bool>>{};
    for (final m in leafModules) {
      final modData = (raw[m.id] is Map)
          ? Map<String, dynamic>.from(raw[m.id])
          : <String, dynamic>{};
      map[m.id] = {for (final a in actions) a: (modData[a] == true)};
    }
    return map;
  }

  // ── Person discovery ─────────────────────────────────────────────────────

  static Future<List<PersonInfo>> getAllPersons() async {
    final officeMgrs = await CompanyStore.instance.getJsonList(
      'officeManagers',
    );
    final fieldMgrs = await CompanyStore.instance.getJsonList('fieldManagers');

    final List<PersonInfo> persons = [];
    for (final m in officeMgrs) {
      final phone = (m['phone'] ?? '').toString();
      if (phone.isEmpty) continue;
      persons.add(
        PersonInfo(
          phone: phone,
          name: (m['name'] ?? 'Office Manager').toString(),
          role: 'Office Manager',
        ),
      );
    }
    for (final m in fieldMgrs) {
      final phone = (m['phone'] ?? '').toString();
      if (phone.isEmpty) continue;
      persons.add(
        PersonInfo(
          phone: phone,
          name: (m['name'] ?? 'Field Manager').toString(),
          role: 'Field Manager',
        ),
      );
    }
    return persons;
  }

  // ── ROLE DEFAULT storage ──────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _loadRawRolePermissions() async {
    final raw = await CompanyStore.instance.getString('rolePermissions');
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(json.decode(raw));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveRolePermissions(Map<String, dynamic> data) async {
    await CompanyStore.instance.setString('rolePermissions', json.encode(data));
  }

  static Future<Map<String, Map<String, bool>>> getRoleDefaultMatrix(
    String role,
  ) async {
    final raw = await _loadRawRolePermissions();
    final roleData = (raw[role] is Map)
        ? Map<String, dynamic>.from(raw[role])
        : <String, dynamic>{};
    return _fillModuleMap(roleData);
  }

  static Future<void> saveRoleDefaultMatrix(
    String role,
    Map<String, Map<String, bool>> matrix,
  ) async {
    final raw = await _loadRawRolePermissions();
    raw[role] = matrix.map((k, v) => MapEntry(k, v));
    await _saveRolePermissions(raw);
  }

  // ── PERSON OVERRIDE storage ───────────────────────────────────────────────

  static Future<Map<String, dynamic>> _loadRawPersonPermissions() async {
    final raw = await CompanyStore.instance.getString('personPermissions');
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(json.decode(raw));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _savePersonPermissions(Map<String, dynamic> data) async {
    await CompanyStore.instance.setString(
      'personPermissions',
      json.encode(data),
    );
  }

  static Future<Map<String, Map<String, bool>>> getPersonMatrix(
    String phone,
    String role,
  ) async {
    final raw = await _loadRawPersonPermissions();
    if (raw[phone] is Map) {
      return _fillModuleMap(Map<String, dynamic>.from(raw[phone]));
    }
    return getRoleDefaultMatrix(role);
  }

  static Future<void> savePersonMatrix(
    String phone,
    Map<String, Map<String, bool>> matrix,
  ) async {
    final raw = await _loadRawPersonPermissions();
    raw[phone] = matrix.map((k, v) => MapEntry(k, v));
    await _savePersonPermissions(raw);
  }

  static Future<void> resetPersonToRoleDefault(String phone) async {
    final raw = await _loadRawPersonPermissions();
    raw.remove(phone);
    await _savePersonPermissions(raw);
  }

  // ── RUNTIME CHECK ──────────────────────────────────────────────────────────

  /// Priority: Person override > Role default > false. Owner ko hamesha sab.
  static Future<bool> can(String moduleId, String action) async {
    final role = await SessionService.currentRole;
    if (role == null || role == 'Owner') return true;

    final phone = await SessionService.phone;
    if (phone == null || phone.isEmpty) return false;

    final personRaw = await _loadRawPersonPermissions();
    if (personRaw[phone] is Map) {
      final modData = personRaw[phone][moduleId];
      if (modData is Map) return modData[action] == true;
      return false;
    }

    final roleRaw = await _loadRawRolePermissions();
    if (roleRaw[role] is Map) {
      final modData = roleRaw[role][moduleId];
      if (modData is Map) return modData[action] == true;
    }
    return false;
  }
}
