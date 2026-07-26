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
                  children: _buildNodes(
                    PermissionService.tree,
                    _roleDefaults[role]!,
                    (id, action, val) =>
                        _toggleRoleDefault(role, id, action, val),
                    (id, val) => _setAllRoleDefaultForModule(role, id, val),
                  ),
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
                padding: const EdgeInsets.only(right: 10, top: 6),
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
  /// Leaf → detailed permission card. Group → nested ExpansionTile.
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
            padding: EdgeInsets.only(
              left: depth * 10.0,
              right: 4,
              bottom: 10,
              top: 2,
            ),
            child: _permissionModuleCard(
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

        if (node.hasPermission) {
          childWidgets.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 2),
              child: _permissionModuleCard(
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
                highlight: true,
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
            padding: EdgeInsets.only(left: depth * 10.0, bottom: 8, top: 2),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  leading: Text(
                    node.emoji,
                    style: const TextStyle(fontSize: 17),
                  ),
                  title: Text(
                    node.label,
                    style: TextStyle(
                      fontSize: depth == 0 ? 13.5 : 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
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

  /// ⭐ Design 1 — detailed card: emoji+label header, phir har action apni
  /// row me label + ON/OFF pill ke saath.
  Widget _permissionModuleCard({
    required PermissionNode node,
    required Map<String, bool> perms,
    required VoidCallback onAllOn,
    required VoidCallback onAllOff,
    required void Function(String action, bool value) onToggle,
    bool highlight = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: highlight ? Colors.blue.shade50 : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? Colors.blue.shade200 : Colors.black12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: emoji + label + All ON/OFF ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                Text(node.emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onAllOn,
                  child: const Text('All ON', style: TextStyle(fontSize: 10)),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onAllOff,
                  child: const Text('All OFF', style: TextStyle(fontSize: 10)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.black12),
          // ── Action rows ──
          ...PermissionService.actions.map((action) {
            final val = perms[action] ?? false;
            final isLast = action == PermissionService.actions.last;
            return Column(
              children: [
                _actionRow(
                  icon: _actionIcon(action),
                  label: _actionLabel(action),
                  value: val,
                  onTap: () => onToggle(action, !val),
                ),
                if (!isLast) const Divider(height: 1, color: Color(0xFFF0F0F0)),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String label,
    required bool value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12.5, color: Colors.black87),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: value ? primaryGreen : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                value ? 'ON' : 'OFF',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: value ? Colors.white : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'view':
        return Icons.visibility_rounded;
      case 'add':
        return Icons.add_circle_outline_rounded;
      case 'edit':
        return Icons.edit_rounded;
      case 'delete':
        return Icons.delete_outline_rounded;
      default:
        return Icons.help_outline_rounded;
    }
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
