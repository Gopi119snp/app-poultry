import 'dart:async';
import 'package:flutter/material.dart';
import '../services/permission_service.dart';
import '../services/company_store.dart';
import '../services/session_service.dart';

/// ⭐ Poore app ko is widget se wrap karo (main navigation/home screen ke
/// upar). Agar company ka trial/subscription expire ho chuka hai, to ye
/// ek neutral "Account access limited" screen dikhayega.
///
/// ⚠️ IMPORTANT — Google Play Store compliance:
/// Is screen mein JAAN-BUJH KAR koi bhi payment link, "Buy", "Subscribe",
/// pricing, ya clickable website button NAHI hai. Sirf plain informational
/// text hai ("apna account website/email se manage karo"). Ye is liye
/// zaroori hai taaki Tracko ek "consumption-only" app rahe (Google Play
/// Payments Policy ke mutabiq) — agar app ke andar koi bhi payment-leading
/// UI element aa gaya, to Play Store Billing mandatory ho jaata hai.
/// Agar isme kabhi change karna ho, pehle current Play Store policy zaroor
/// check kar lena.
class SubscriptionGate extends StatefulWidget {
  final Widget child;
  const SubscriptionGate({super.key, required this.child});

  @override
  State<SubscriptionGate> createState() => _SubscriptionGateState();
}

class _SubscriptionGateState extends State<SubscriptionGate> {
  bool? _active;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _check();
    _sub = CompanyStore.instance.onDataChanged.listen((_) => _check());
  }

  Future<void> _check() async {
    final result = await PermissionService.isAccountActive();
    if (!mounted) return;
    if (_active != result) {
      setState(() => _active = result);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_active == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_active == true) {
      return widget.child;
    }
    return const _AccountLockedScreen();
  }
}

class _AccountLockedScreen extends StatelessWidget {
  const _AccountLockedScreen();

  static const primaryGreen = Color(0xFF1B5E20);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: primaryGreen.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('🔒', style: TextStyle(fontSize: 36)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Account Access Limited',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                // ⚠️ Neutral, informational text only — no clickable
                // link, no "buy"/"subscribe" wording. See class doc above.
                const Text(
                  'Aapke account ki membership avdhi samapt ho gayi hai.\n\n'
                  'Account activation ki jankari aapke registered email par bheji gayi hai. '
                  'Kripya apna inbox check karein.',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Colors.grey,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await SessionService.logout();
                      // App ka WelcomeScreen route yahan use karo agar
                      // import cycle allow kare; warna is button ko hata
                      // ke sirf "logout se dobara login karo" text rakh do.
                    },
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Logout'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryGreen,
                      side: const BorderSide(color: primaryGreen),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
