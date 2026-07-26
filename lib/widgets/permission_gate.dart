import 'package:flutter/material.dart';
import '../services/permission_service.dart';

/// Kisi bhi button/section/screen-content ko is widget se wrap karo.
/// Agar current logged-in user (Owner/Office Manager/Field Manager) ko
/// us module + action ka permission NAHI hai, to child dikhega hi nahi —
/// uski jagah khud collapse ho jayegi (SizedBox.shrink).
///
/// USAGE EXAMPLE:
/// PermissionGate(
///   moduleId: 'sales',
///   action: 'add',
///   child: ElevatedButton(...),
/// )
class PermissionGate extends StatelessWidget {
  final String moduleId;
  final String action; // 'view', 'add', 'edit', 'delete'
  final Widget child;

  /// Agar permission nahi hai to ye dikhega (default: kuch nahi, empty space)
  final Widget? fallback;

  const PermissionGate({
    super.key,
    required this.moduleId,
    required this.action,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: PermissionService.can(moduleId, action),
      builder: (context, snapshot) {
        // Data load hone tak kuch mat dikhao (flicker avoid karne ke liye)
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        if (snapshot.data == true) {
          return child;
        }
        return fallback ?? const SizedBox.shrink();
      },
    );
  }
}

/// ⭐ Poore SCREEN ko protect karne ke liye — agar permission nahi hai
/// to ek "Access Denied" message dikhayega, ya wapas bhej dega.
///
/// USAGE EXAMPLE (screen ke build() method ke start me):
/// return PermissionScreenGate(
///   moduleId: 'reports',
///   action: 'view',
///   child: Scaffold(...), // asli screen content
/// );
class PermissionScreenGate extends StatelessWidget {
  final String moduleId;
  final String action;
  final Widget child;

  const PermissionScreenGate({
    super.key,
    required this.moduleId,
    required this.action,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: PermissionService.can(moduleId, action),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == true) {
          return child;
        }
        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1B5E20),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🔒', style: TextStyle(fontSize: 60)),
                const SizedBox(height: 16),
                const Text(
                  'Access Nahi Hai',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Is feature ka access aapko Owner ne nahi diya hai.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
