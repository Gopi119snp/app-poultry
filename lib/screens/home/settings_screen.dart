import 'package:flutter/material.dart';
import '../../services/permission_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);

  bool _isLoading = true;
  List<String> _roles = [];
  Map<String, List<PersonInfo>> _personsByRole = {};
  Map<String, Map<String, Map<String, bool>>> _roleDefaults = {};
  Map<String, Map<String, Map<String, bool>>> _personMatrices = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final roles = await PermissionService.getAllRoles();
    final persons = await PermissionService.getAllPersons();

    final Map<String, List<PersonInfo>> grouped = {};
    for (final r in roles) {
      grouped[r] = persons.where((p) => p.role == r).toList();
    }

    final Map<String, Map<String, Map<String, bool>>> roleDefaults = {};
    for (final r in roles) {
      roleDefaults[r] = await PermissionService.getRoleDefaultMatrix(r);
    }

    final Map<String, Map<String, Map<String, bool>>> personMatrices = {};
    for (final p in persons) {
      personMatrices[p.phone] = await PermissionService.getPersonMatrix(
        p.phone,
        p.role,
      );
    }

    if (!mounted) return;
    setState(() {
      _roles = roles;
      _personsByRole = grouped;
      _roleDefaults = roleDefaults;
      _personMatrices = personMatrices;
      _isLoading = false;
    });
  }

  Future<void> _toggleRoleDefault(
    String role,
    String moduleId,
    String action,
    bool value,
  ) async {
    setState(() => _roleDefaults[role]![moduleId]![action] = value);
    await PermissionService.saveRoleDefaultMatrix(role, _roleDefaults[role]!);
  }

  void _setAllRoleDefaultForModule(String role, String moduleId, bool value) {
    setState(() {
      for (final a in PermissionService.actions) {
        _roleDefaults[role]![moduleId]![a] = value;
      }
    });
    PermissionService.saveRoleDefaultMatrix(role, _roleDefaults[role]!);
  }

  Future<void> _togglePerson(
    String phone,
    String moduleId,
    String action,
    bool value,
  ) async {
    setState(() => _personMatrices[phone]![moduleId]![action] = value);
    await PermissionService.savePersonMatrix(phone, _personMatrices[phone]!);
  }

  void _setAllPersonForModule(String phone, String moduleId, bool value) {
    setState(() {
      for (final a in PermissionService.actions) {
        _personMatrices[phone]![moduleId]![a] = value;
      }
    });
    PermissionService.savePersonMatrix(phone, _personMatrices[phone]!);
  }

  Future<void> _resetPersonToDefault(String phone, String role) async {
    await PermissionService.resetPersonToRoleDefault(phone);
    final fresh = await PermissionService.getRoleDefaultMatrix(role);
    setState(() => _personMatrices[phone] = fresh);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Role ke default permission par wapas aa gaya'),
      ),
    );
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
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '🔐 Role & Person Permissions',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Category ke naam pe tap karo to neeche ka khulega. Har item ke aage View/Add/Edit/Delete set karo.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 12),
                ..._roles.map((role) => _roleGroupCard(role)),
                const SizedBox(height: 20),
              ],
            ),
    );
  }

  Widget _roleGroupCard(String role) {
    final persons = _personsByRole[role] ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
          leading: const Icon(
            Icons.badge_rounded,
            color: primaryGreen,
            size: 22,
          ),
          title: Text(
            role,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          subtitle: Text(
            '${persons.length} member${persons.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          children: [
            // ── Role Default (template for new members) ──
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F7F3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primaryGreen.withOpacity(0.2)),
              ),
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                  leading: const Icon(
                    Icons.tune_rounded,
                    color: primaryGreen,
                    size: 18,
                  ),
                  title: const Text(
                    'Default (Naye members ko ye milega)',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  children: [
                    _permissionHeaderRow(),
                    ..._buildNodes(
                      PermissionService.tree,
                      _roleDefaults[role]!,
                      (id, action, val) =>
                          _toggleRoleDefault(role, id, action, val),
                      (id, val) => _setAllRoleDefaultForModule(role, id, val),
                    ),
                  ],
                ),
              ),
            ),
            // ── Individual persons ──
            if (persons.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  'Abhi is role ka koi member add nahi hua hai.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              )
            else
              ...persons.map((p) => _personCard(p)),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _personCard(PersonInfo person) {
    final matrix = _personMatrices[person.phone]!;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: primaryGreen.withOpacity(0.12),
            child: Text(
              person.name.isNotEmpty ? person.name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: primaryGreen,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          title: Text(
            person.name,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            person.phone,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: TextButton.icon(
                  onPressed: () =>
                      _resetPersonToDefault(person.phone, person.role),
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: const Text(
                    'Role Default Par Reset Karo',
                    style: TextStyle(fontSize: 10.5),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                  ),
                ),
              ),
            ),
            _permissionHeaderRow(),
            ..._buildNodes(
              PermissionService.tree,
              matrix,
              (id, action, val) => _togglePerson(person.phone, id, action, val),
              (id, val) => _setAllPersonForModule(person.phone, id, val),
            ),
          ],
        ),
      ),
    );
  }

  /// ⭐ Recursive builder — tree ke har node ko render karta hai.
  /// Leaf → View/Add/Edit/Delete row. Group → nested ExpansionTile.
  List<Widget> _buildNodes(
    List<PermissionNode> nodes,
    Map<String, Map<String, bool>> matrix,
    void Function(String moduleId, String action, bool value) onToggle,
    void Function(String moduleId, bool value) onSetAll, {
    int depth = 0,
  }) {
    final List<Widget> widgets = [];
    for (final node in nodes) {
      if (node.isLeaf) {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(left: depth * 14.0),
            child: _permissionModuleRow(
              node: node,
              perms:
                  matrix[node.id] ??
                  {for (final a in PermissionService.actions) a: false},
              onAllOn: () => onSetAll(node.id, true),
              onAllOff: () => onSetAll(node.id, false),
              onToggle: (action, val) => onToggle(node.id, action, val),
            ),
          ),
        );
      } else {
        final List<Widget> childWidgets = [];

        // ⭐ Group ka khud ka "Overall" permission row (agar hasPermission true hai)
        if (node.hasPermission) {
          childWidgets.add(
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _permissionModuleRow(
                node: PermissionNode(
                  id: node.id,
                  label: 'Overall Access (Sabhi)',
                  emoji: node.emoji,
                ),
                perms:
                    matrix[node.id] ??
                    {for (final a in PermissionService.actions) a: false},
                onAllOn: () => onSetAll(node.id, true),
                onAllOff: () => onSetAll(node.id, false),
                onToggle: (action, val) => onToggle(node.id, action, val),
              ),
            ),
          );
        }

        childWidgets.addAll(
          _buildNodes(
            node.children,
            matrix,
            onToggle,
            onSetAll,
            depth: depth + 1,
          ),
        );

        widgets.add(
          Padding(
            padding: EdgeInsets.only(left: depth * 10.0, bottom: 6, top: 2),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black12),
              ),
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 10),
                  leading: Text(
                    node.emoji,
                    style: const TextStyle(fontSize: 15),
                  ),
                  title: Text(
                    node.label,
                    style: TextStyle(
                      fontSize: depth == 0 ? 12.5 : 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.only(bottom: 6),
                  children: childWidgets,
                ),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  Widget _permissionHeaderRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          const Expanded(flex: 3, child: SizedBox()),
          ...['V', 'A', 'E', 'D'].map(
            (l) => Container(
              width: 30,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              alignment: Alignment.center,
              child: Text(
                l,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissionModuleRow({
    required PermissionNode node,
    required Map<String, bool> perms,
    required VoidCallback onAllOn,
    required VoidCallback onAllOff,
    required void Function(String action, bool value) onToggle,
  }) {
    final bool allOn = PermissionService.actions.every((a) => perms[a] == true);
    final bool allOff = PermissionService.actions.every(
      (a) => perms[a] != true,
    );

    return InkWell(
      onTap: () => allOn ? onAllOff() : onAllOn(),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: allOn
              ? primaryGreen.withOpacity(0.06)
              : (allOff ? Colors.transparent : Colors.orange.withOpacity(0.05)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text(node.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Expanded(
              flex: 3,
              child: Text(
                node.label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ...PermissionService.actions.map((action) {
              final val = perms[action] ?? false;
              return _miniActionToggle(
                letter: _actionLetter(action),
                active: val,
                onTap: () => onToggle(action, !val),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _miniActionToggle({
    required String letter,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? primaryGreen : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? primaryGreen : Colors.grey.shade300,
          ),
        ),
        child: Text(
          letter,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: active ? Colors.white : Colors.grey.shade500,
          ),
        ),
      ),
    );
  }

  String _actionLetter(String action) {
    switch (action) {
      case 'view':
        return 'V';
      case 'add':
        return 'A';
      case 'edit':
        return 'E';
      case 'delete':
        return 'D';
      default:
        return '?';
    }
  }
}
