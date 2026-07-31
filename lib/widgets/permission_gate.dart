import 'dart:async';
import 'package:flutter/material.dart';
import '../services/permission_service.dart';
import '../services/company_store.dart';

/// Kisi bhi button/section/screen-content ko is widget se wrap karo.
/// Agar current logged-in user (Owner/Office Manager/Field Manager) ko
/// us module + action ka permission NAHI hai, to child dikhega hi nahi —
/// uski jagah khud collapse ho jayegi (SizedBox.shrink).
///
/// ✅ FIX — ab ye StatefulWidget hai aur CompanyStore.onDataChanged sunta
/// hai. Matlab Owner jab bhi Settings se koi permission ON/OFF karta hai
/// (khud ke device se ya kisi doosre device se), ye widget turant khud
/// permission dobara check karke rebuild ho jayega — chahe manager us
/// screen ko pehle se khola hua ho aur wapas na aaya ho.
///
/// USAGE EXAMPLE:
/// PermissionGate(
///   moduleId: 'sales',
///   action: 'add',
///   child: ElevatedButton(...),
/// )
class PermissionGate extends StatefulWidget {
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
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  bool? _allowed;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _check();
    // ✅ FIX — real-time listener: permission change hote hi turant refresh.
    _sub = CompanyStore.instance.onDataChanged.listen((_) => _check());
  }

  @override
  void didUpdateWidget(covariant PermissionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moduleId != widget.moduleId ||
        oldWidget.action != widget.action) {
      _check();
    }
  }

  Future<void> _check() async {
    final result = await PermissionService.canNested(
      widget.moduleId,
      widget.action,
    );
    if (!mounted) return;
    if (_allowed != result) {
      setState(() => _allowed = result);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Data load hone tak kuch mat dikhao (flicker avoid karne ke liye)
    if (_allowed == null) {
      return const SizedBox.shrink();
    }
    if (_allowed == true) {
      return widget.child;
    }
    return widget.fallback ?? const SizedBox.shrink();
  }
}

/// ⭐ Poore SCREEN ko protect karne ke liye — agar permission nahi hai
/// to ek "Access Denied" message dikhayega, ya wapas bhej dega.
///
/// ✅ FIX — ye bhi ab live-reactive hai. Agar manager screen khole hue
/// hai aur usi waqt Owner permission OFF kar deta hai, to ye screen
/// turant "Access Nahi Hai" dikha dega — back jaake dobara aane ki
/// zaroorat nahi.
///
/// USAGE EXAMPLE (screen ke build() method ke start me):
/// return PermissionScreenGate(
///   moduleId: 'reports',
///   action: 'view',
///   child: Scaffold(...), // asli screen content
/// );
class PermissionScreenGate extends StatefulWidget {
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
  State<PermissionScreenGate> createState() => _PermissionScreenGateState();
}

class _PermissionScreenGateState extends State<PermissionScreenGate> {
  bool? _allowed;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _check();
    _sub = CompanyStore.instance.onDataChanged.listen((_) => _check());
  }

  Future<void> _check() async {
    final result = await PermissionService.canNested(
      widget.moduleId,
      widget.action,
    );
    if (!mounted) return;
    if (_allowed != result) {
      setState(() => _allowed = result);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_allowed == true) {
      return widget.child;
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
  }
}
