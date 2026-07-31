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

  /// ✅ NEW — Is node ki asal screen mein kaunse actions (View/Add/Edit/
  /// Delete) ka feature hi maujood hai. Settings screen ab sirf yahi
  /// buttons dikhayega — jis feature ka option screen mein hai hi nahi,
  /// uska toggle Settings mein bhi nahi dikhega. Default = sabhi 4
  /// (purana behaviour, taaki jin nodes ke liye ye specify nahi kiya
  /// gaya wahan kuch na tute).
  final List<String> availableActions;

  const PermissionNode({
    required this.id,
    required this.label,
    this.emoji = '📁',
    this.isLeaf = true,
    this.hasPermission = false,
    this.children = const [],
    this.availableActions = const ['view', 'add', 'edit', 'delete'],
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
              // ✅ FIX — farmers_screen.dart mein sirf Add Farmer button
              // (add) hai, farmer_profile_screen.dart mein sirf Edit
              // (personal details/photo/signature) hai. Poore codebase
              // mein kahin bhi farmer profile DELETE ka koi button/feature
              // nahi hai — isliye delete hata diya.
              availableActions: const ['view', 'add', 'edit'],
            ),
            PermissionNode(
              id: 'farmerBankDetail',
              label: 'Bank Detail',
              emoji: '🏦',
              // ✅ FIX — Bank detail sirf farmer_profile_screen.dart ke
              // Bank tab mein view hoti hai aur Edit Bank Details button
              // se edit hoti hai. Bank ka koi standalone "Add" button ya
              // Delete feature nahi hai (bank farmer registration ke
              // waqt hi save hoti hai, jo 'farmerProfile' add ke andar
              // aata hai).
              availableActions: const ['view', 'edit'],
            ),
          ],
        ),
        PermissionNode(
          id: 'farmerReportGroup',
          label: 'Farmer Report',
          emoji: '📈',
          isLeaf: false,
          hasPermission: true,
          // ✅ FIX — farmer_profile_screen.dart mein Report tab sirf
          // FarmerReportScreen dikhata hai (read-only bar-graph/breakdown
          // dashboard) — koi add/edit/delete button nahi hai. Isliye
          // sirf 'view' toggle rakha, purchaseExpense/stockManagement
          // jaisa hi group-card pattern.
          availableActions: const ['view'],
          children: [
            PermissionNode(
              id: 'farmerDetailInfo',
              label: 'Detail Information Dekho',
              emoji: '🔍',
              // ✅ FIX — farmer_report_screen.dart mein ye sirf ek
              // navigation button hai jo BatchDetailInformationScreen
              // (read-only charts) kholta hai — koi add/edit/delete
              // feature nahi hai.
              availableActions: const ['view'],
            ),
            PermissionNode(
              id: 'farmerAllReports',
              label: 'Sabhi Reports Dekho',
              emoji: '📑',
              // ✅ FIX — ye bhi sirf navigation button hai jo
              // AllBatchesReportScreen (read-only list+summary) kholta
              // hai — koi add/edit/delete feature nahi hai.
              availableActions: const ['view'],
            ),
          ],
        ),
        PermissionNode(
          id: 'batchCreate',
          label: 'Farmer Batch (Making)',
          emoji: '🐣',
          // ✅ FIX — farmer_profile_screen.dart mein 'view' Batch tab
          // dikhata hai, 'add' se naya batch start hota hai, 'edit' se
          // active batch edit hoti hai. Batch DELETE ka koi button nahi
          // hai (batch khatam karna alag 'batchEnd' node se hota hai).
          availableActions: const ['view', 'add', 'edit'],
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
                  // ✅ FIX — batch_detail_screen.dart mein sirf
                  // PermissionService.can('feedEntry','add') check hota
                  // hai (Flock Record dialog ke Feed section ke liye).
                  // Koi alag 'view' iska nahi hai (dikhna 'batchCreate'
                  // tab-level view se control hota hai, entries ka
                  // history 'dailyUpdateList' se), aur edit/delete ka
                  // koi feature hi nahi hai (entries immutable hain).
                  availableActions: const ['add'],
                ),
                PermissionNode(
                  id: 'averageWeight',
                  label: 'Average Weight',
                  emoji: '⚖️',
                  availableActions: const [
                    'add',
                  ], // ✅ FIX — sirf add check hota hai
                ),
                PermissionNode(
                  id: 'mortality',
                  label: 'Mortality',
                  emoji: '💀',
                  availableActions: const [
                    'add',
                  ], // ✅ FIX — sirf add check hota hai
                ),
                PermissionNode(
                  id: 'remainingFeed',
                  label: 'Actual Remaining Feed',
                  emoji: '📊',
                  availableActions: const [
                    'add',
                  ], // ✅ FIX — sirf add check hota hai
                ),
              ],
            ),
            PermissionNode(
              id: 'batchSales',
              label: 'Sales',
              emoji: '💰',
              // ✅ FIX — sirf PermissionService.can('batchSales','add')
              // check hota hai ('+ Sale' quick-action button). Edit/delete
              // ka koi feature nahi hai.
              availableActions: const ['add'],
            ),
            PermissionNode(
              id: 'batchMedicine',
              label: 'Medicine',
              emoji: '💊',
              // ✅ FIX — sirf 'add' check hota hai ('Medicine' quick-action
              // button). Edit/delete ka koi feature nahi hai.
              availableActions: const ['add'],
            ),
            PermissionNode(
              id: 'dailyUpdateList',
              label: 'Daily Update List',
              emoji: '📝',
              // ✅ FIX — ye sirf ek read-only history screen hai, sirf
              // 'view' check hota hai. Add/edit/delete ka yahan koi button
              // nahi hai.
              availableActions: const ['view'],
            ),
            PermissionNode(
              id: 'feedReturn',
              label: 'Return Feed',
              emoji: '↩️',
              // ✅ FIX — sirf 'add' check hota hai (Batch End flow ke
              // andar Return Feed dialog). Edit/delete nahi hai.
              availableActions: const ['add'],
            ),
            PermissionNode(
              id: 'batchEnd',
              label: 'Batch End',
              emoji: '🏁',
              // ✅ FIX — sirf 'add' check hota hai (Batch End button).
              // Edit/delete ka concept hi nahi (batch ek baar end hone ke
              // baad COMPLETED ho jaata hai).
              availableActions: const ['add'],
            ),
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
      // ✅ FIX — "Stock Management" ka Overall card sirf Feed/Medicine
      // sub-tab ke beech switch karta hai, khud koi add/edit/delete nahi
      // karta (purchaseExpense/sales/reports/accounts jaisa hi pattern).
      availableActions: const ['view'],
      children: [
        PermissionNode(
          id: 'feedStock',
          label: 'Feed Stock Overview',
          emoji: '🌾',
          // ✅ FIX — home_screen.dart ka Feed Stock tab poora read-only
          // inventory dashboard hai (koi add/edit/delete button hai hi
          // nahi — history button 'feedAllocation' se alag gate hota hai).
          availableActions: const ['view'],
        ),
        PermissionNode(
          id: 'medicineStock',
          label: 'Medicine Stock Overview',
          emoji: '💉',
          // ✅ FIX — Sirf View + Delete ka feature hai (stock record delete
          // karna). Add/Edit ka koi button is screen mein nahi hai.
          availableActions: const ['view', 'delete'],
        ),
      ],
    ),
    PermissionNode(
      id: 'purchaseExpense',
      label: 'Purchase / Expense',
      emoji: '🛒',
      isLeaf: false,
      hasPermission: true,
      availableActions: const ['view'], // sirf category card hai
      children: [
        PermissionNode(
          id: 'chicksPurchase',
          label: 'Chicks Purchase',
          emoji: '🐣',
          isLeaf: false,
          hasPermission: true,
          availableActions: const ['view'], // sirf category card hai
          children: [
            PermissionNode(
              id: 'chicksPurchaseEntry',
              label: 'Purchase Entry',
              emoji: '🛒',
              availableActions: const ['view', 'add'], // edit/delete nahi hai
            ),
            PermissionNode(
              id: 'chicksAllocation',
              label: 'Allocation (Farmer ko dena)',
              emoji: '📤',
              availableActions: const [
                'view',
                'add',
                'edit',
              ], // delete ka feature nahi hai
            ),
          ],
        ),
        PermissionNode(
          id: 'feedPurchase',
          label: 'Feed Purchase',
          emoji: '🌾',
          isLeaf: false,
          hasPermission: true,
          availableActions: const ['view'], // sirf category card hai
          children: [
            PermissionNode(
              id: 'feedPurchaseEntry',
              label: 'Purchase Entry',
              emoji: '🛒',
              availableActions: const ['view', 'add'], // edit/delete nahi hai
            ),
            PermissionNode(
              id: 'feedAllocation',
              label: 'Allocation (Farmer ko dena)',
              emoji: '📤',
              // full CRUD hai — default 4 actions hi rehne do
            ),
          ],
        ),
        PermissionNode(
          id: 'medicinePurchase',
          label: 'Medicine Purchase',
          emoji: '💊',
          isLeaf: false,
          hasPermission: true,
          availableActions: const ['view'], // sirf category card hai
          children: [
            PermissionNode(
              id: 'medicinePurchaseEntry',
              label: 'Purchase Entry',
              emoji: '🛒',
              // full CRUD hai — default 4 actions hi rehne do
            ),
            PermissionNode(
              id: 'medicineAllocation2',
              label: 'Allocation (Farmer ko dena)',
              emoji: '📤',
              // full CRUD hai — default 4 actions hi rehne do
            ),
          ],
        ),
        PermissionNode(
          id: 'labourExpense',
          label: 'Labour / Manager Expense',
          emoji: '👷',
          availableActions: const ['view', 'add'], // edit/delete nahi hai
        ),
        PermissionNode(
          id: 'otherExpense',
          label: 'Other Expense',
          emoji: '📋',
          availableActions: const ['view', 'add'], // edit/delete nahi hai
        ),
      ],
    ),
    PermissionNode(
      id: 'sales',
      label: 'Sales / Lifting',
      emoji: '💰',
      isLeaf: false,
      hasPermission: true,
      // ✅ FIX — purchaseExpense parent jaisa hi pattern: "Sales / Lifting"
      // ka Overall card khud koi add/edit/delete kaam nahi karta, sirf
      // category navigate karta hai. Isliye Settings mein bhi sirf "View"
      // toggle dikhna chahiye — baaki 3 (Add/Edit/Delete) yahan kabhi
      // istemal hi nahi honge.
      availableActions: const ['view'],
      children: [
        PermissionNode(
          id: 'chicksSale',
          label: 'Chicks Sale',
          emoji: '🐣',
          // ✅ FIX — Ye sirf ChicksSalesView (read-only) khudata hai, jo
          // chicksPurchaseHistory se auto-derive hoti hai. Add/Edit/Delete
          // ka koi feature hi nahi hai screen mein, isliye Settings mein
          // bhi sirf "View" toggle dikhna chahiye (purchase category-card
          // wala hi pattern).
          availableActions: const ['view'],
        ),
        PermissionNode(id: 'feedSale', label: 'Feed Sale', emoji: '🌾'),
        PermissionNode(id: 'medicineSale', label: 'Medicine Sale', emoji: '💊'),
        PermissionNode(
          id: 'chickenLiftingSale',
          label: 'Chicken Sale (Lifting)',
          emoji: '🐔',
          // ✅ FIX — Abhi ye feature banaya hi nahi gaya (stub onTap hai
          // sales_screen.dart mein), isliye sirf "View" toggle rakha —
          // jaise hi ye screen actually banegi, yahan availableActions
          // hata ke default 4-action wapas kar dena.
          availableActions: const ['view'],
        ),
      ],
    ),
    PermissionNode(
      id: 'reports',
      label: 'Reports',
      emoji: '📊',
      isLeaf: false,
      hasPermission: true,
      // ✅ FIX — purchaseExpense/sales parent jaisa hi: "Reports" ka Overall
      // card khud sirf category navigate karta hai, koi add/edit/delete
      // nahi. Sirf "View" toggle dikhna chahiye Settings mein.
      availableActions: const ['view'],
      children: [
        PermissionNode(
          id: 'opExpenseRecoveryReport',
          label: 'Operational Expense Recovery',
          emoji: '💹',
          // ✅ FIX — Ye report poori tarah read-only hai (koi add/edit/
          // delete/export button reports_screen.dart mein hai hi nahi).
          availableActions: const ['view'],
        ),
        PermissionNode(
          id: 'batchPerformanceReport',
          label: 'Batch Performance',
          emoji: '📈',
          // ✅ FIX — Read-only report, sirf View.
          availableActions: const ['view'],
        ),
        PermissionNode(
          id: 'farmerProfitLossReport',
          label: 'Farmer Profit / Loss',
          emoji: '📉',
          // ✅ FIX — Read-only report, sirf View.
          availableActions: const ['view'],
        ),
        // ✅ NAYA ADD KIYA GAYA NODE (Farmer Profit / Loss ke theek neeche)
        PermissionNode(
          id: 'totalIncomeReport',
          label: 'Total Income',
          emoji: '💰',
          // ✅ FIX — Read-only report, sirf View.
          availableActions: const ['view'],
        ),
      ],
    ),
    PermissionNode(
      id: 'accounts',
      label: 'Accounts',
      emoji: '🧾',
      isLeaf: false,
      hasPermission: true,
      // ✅ FIX — reports jaisa hi: Accounts ka Overall card sirf category
      // navigate karta hai, koi add/edit/delete nahi.
      availableActions: const ['view'],
      children: [
        PermissionNode(
          id: 'accountsOverview',
          label: 'Overview',
          emoji: '📊',
          // ✅ FIX — Poora accounts_screen.dart read-only hai (koi edit/
          // delete button hai hi nahi), sirf View.
          availableActions: const ['view'],
        ),
        PermissionNode(
          id: 'accountsUdhaar',
          label: 'Udhaar',
          emoji: '⏳',
          availableActions: const ['view'],
        ),
        PermissionNode(
          id: 'accountsKharcha',
          label: 'Kharcha',
          emoji: '💸',
          availableActions: const ['view'],
        ),
        PermissionNode(
          id: 'accountsKharida',
          label: 'Kharida',
          emoji: '🛒',
          availableActions: const ['view'],
        ),
        PermissionNode(
          id: 'accountsSales',
          label: 'Sales',
          emoji: '🎁',
          availableActions: const ['view'],
        ),
      ],
    ),
    PermissionNode(
      id: 'settlement',
      label: 'Settlement Engine',
      emoji: '⚖️',
      // ✅ FIX — home_screen.dart ka "Batch Settlement" ek Rule 1/Rule 2
      // config wizard hai — sirf dekhna (view) aur parameters change karke
      // "Process Selected Rule Engine" se save karna (edit). Koi add ya
      // delete ka feature nahi hai (naya rule bana nahi sakte, delete bhi
      // nahi kar sakte — sirf Rule 1/Rule 2 predefined slots hain).
      availableActions: const ['view', 'edit'],
    ),
    PermissionNode(
      id: 'lifting',
      label: 'Lifting',
      emoji: '🚜',
      isLeaf: false,
      hasPermission: true,
      // ✅ FIX — "Lifting" tab ka Overall card khud koi add/edit/delete
      // nahi karta, sirf ander ke 2 features (range set + list) ko
      // organize karta hai. Sirf View toggle hona chahiye.
      availableActions: const ['view'],
      children: [
        PermissionNode(
          id: 'liftingRangeSet',
          label: 'Range Set Karna',
          emoji: '⚙️',
          // ✅ FIX — Ye sirf ek settings-action hai (Min/Max din set karna),
          // koi separate view-screen nahi hai is permission ke liye —
          // isliye sirf 'edit' rakha.
          availableActions: const ['edit'],
        ),
        PermissionNode(
          id: 'liftingListView',
          label: 'Lifting List Dekhna',
          emoji: '📋',
          // ✅ FIX — 'view' se Lifting-ready farmers ki list dikhti hai,
          // 'edit' se "Lifting Confirm Karo" button dikhta hai. Add/Delete
          // ka koi feature is list mein nahi hai.
          availableActions: const ['view', 'edit'],
        ),
      ],
    ),
    PermissionNode(
      id: 'feedConsumptionRule',
      label: 'Feed Consumption Rule',
      emoji: '🌿',
      // ✅ FIX — Ye ek single rule-config screen hai (view current rule +
      // edit karke save). Koi separate "Add new rule" ya "Delete rule"
      // feature hai hi nahi — season add/remove sirf edit ka hissa hai.
      availableActions: const ['view', 'edit'],
    ),
    PermissionNode(
      id: 'weightGrowthRule',
      label: 'Weight Growth Rule',
      emoji: '📈',
      // ✅ FIX — Same reasoning: sirf View + Edit, no Add/Delete at top level.
      availableActions: const ['view', 'edit'],
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

  // ✅ FIX: JSON encoding crash को रोकने के लिए safe conversion + notify
  static Future<void> saveRoleDefaultMatrix(
    String role,
    Map<String, Map<String, bool>> matrix,
  ) async {
    final raw = await _loadRawRolePermissions();
    // Fix: JSON encoding crash ko rokne ke liye ekdum basic Map mein convert kiya
    final safeMatrix = <String, dynamic>{};
    matrix.forEach((k, v) {
      safeMatrix[k] = Map<String, dynamic>.from(v);
    });
    raw[role] = safeMatrix;
    await _saveRolePermissions(raw);

    // ✅ FIX: Notify app that permissions have changed
    await CompanyStore.instance.setString(
      'lastPermissionUpdated',
      DateTime.now().toIso8601String(),
    );
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

  // ✅ FIX: Same JSON fix for Person overriding + notify
  static Future<void> savePersonMatrix(
    String phone,
    Map<String, Map<String, bool>> matrix,
  ) async {
    final raw = await _loadRawPersonPermissions();
    // Fix: Same JSON fix for Person overriding
    final safeMatrix = <String, dynamic>{};
    matrix.forEach((k, v) {
      safeMatrix[k] = Map<String, dynamic>.from(v);
    });
    raw[phone] = safeMatrix;
    await _savePersonPermissions(raw);

    // ✅ FIX: Notify app that permissions have changed
  }

  static Future<void> resetPersonToRoleDefault(String phone) async {
    final raw = await _loadRawPersonPermissions();
    raw.remove(phone);
    await _savePersonPermissions(raw);
  }

  // ── RUNTIME CHECK ──────────────────────────────────────────────────────────

  /// Cache for ancestor IDs (nodes that have hasPermission) for each moduleId.
  static Map<String, List<String>>? _ancestorCache;

  static void _buildAncestorCache() {
    if (_ancestorCache != null) return;
    _ancestorCache = {};
    void walk(List<PermissionNode> nodes, List<String> ancestors) {
      for (final node in nodes) {
        // ✅ FIX — cache save karo ancestors (self ke bina) — ancestors mein
        // append karne SE PEHLE. Isse node ka apna id uski khud ki ancestor
        // list mein doosri baar nahi aata (canNested mein redundant check
        // avoid ho jata hai).
        if (node.isLeaf || node.hasPermission) {
          _ancestorCache![node.id] = ancestors;
        }
        // Recurse ke liye — is node ka hasPermission ho to isse bhi
        // ancestors mein jod do (taaki iske CHILDREN ke liye ye ancestor
        // ban jaye).
        final currentAncestors = node.hasPermission
            ? [...ancestors, node.id]
            : ancestors;
        walk(node.children, currentAncestors);
      }
    }

    walk(tree, []);
  }

  /// Priority: Person override > Role default. Owner gets full access.
  ///
  /// ✅ FIX — Ab STRICT tree-based check hai: koi bhi child/sub-item ka
  /// permission ON hone se parent apne aap "ON" nahi maana jayega.
  /// Har moduleId (parent ho ya leaf) ka apna EXPLICIT toggle hi authoritative
  /// hai. Matlab agar Owner ne "Purchase / Expense" ka Overall Access OFF
  /// kiya hai, to Chicks/Feed/Medicine/Labour/Other mein se kisi ka bhi
  /// permission ON kyu na ho — Purchase card turant hide ho jayega,
  /// kyunki parent explicitly OFF hai. Isse har node independently control
  /// hota hai aur "main OFF to sab OFF" wala tree-hierarchy behaviour milta
  /// hai (parent OFF hone par uske andar navigate karne ka raasta bhi khud
  /// band ho jata hai, kyunki parent card hi nahi dikhega).
  static Future<bool> can(String moduleId, String action) async {
    if (await SessionService.isOwner) return true;

    final role = await SessionService.normalizedRole;
    if (role == null) return false;

    final phone = await SessionService.phone;
    if (phone == null || phone.isEmpty) return false;

    bool hasDirectPerm(Map<String, dynamic> map, String id) {
      if (map[id] is Map) {
        return map[id][action] == true;
      }
      return false;
    }

    final personRaw = await _loadRawPersonPermissions();
    final roleRaw = await _loadRawRolePermissions();

    Map<String, dynamic> activeMap = {};
    if (personRaw[phone] is Map) {
      activeMap = Map<String, dynamic>.from(personRaw[phone]);
    } else if (roleRaw[role] is Map) {
      activeMap = Map<String, dynamic>.from(roleRaw[role]);
    }

    // Sirf direct match — koi hierarchy OR-fallback nahi. Har module
    // (parent group ho ya leaf) ka apna explicit toggle hi final hai.
    return hasDirectPerm(activeMap, moduleId);
  }

  /// ⭐⭐ Screen/feature ke liye ASLI check — "Grandfather → Father → Child"
  /// wala poora tree upar tak check karta hai (existing `_ancestorCache` /
  /// `_buildAncestorCache` ko reuse karke — wo pehle se hi har node ke
  /// hasPermission-wale ancestors ki list bana kar rakhta hai).
  ///
  /// Agar chain mein KAHI BHI (grandparent ho ya immediate parent) ka
  /// 'view' access OFF hai, to niche ka sab kuch — screen ho, button ho —
  /// turant OFF maana jayega, bhale khud moduleId ka apna toggle ON hi
  /// kyu na ho.
  ///
  /// Example: Purchase/Expense (grandfather) → Chicks Purchase (father) →
  /// Purchase Entry (child). Agar Purchase/Expense ka Overall Access OFF
  /// kar diya, to Chicks Purchase screen aur uske andar ke Purchase Entry /
  /// Allocation buttons — sab turant access-denied ho jayenge.
  ///
  /// PermissionGate aur PermissionScreenGate dono is method ko use karte
  /// hain, isliye jahan bhi ye widgets lage hain wahan cascade apne aap
  /// kaam karega — har jagah alag se code likhne ki zaroorat nahi.
  static Future<bool> canNested(String moduleId, String action) async {
    if (await SessionService.isOwner) return true;

    _buildAncestorCache();
    final ancestors = _ancestorCache![moduleId] ?? const <String>[];
    for (final ancestorId in ancestors) {
      if (!(await can(ancestorId, 'view'))) {
        return false; // Koi bhi ancestor ka view OFF => sab OFF
      }
    }
    return can(moduleId, action);
  }
}
