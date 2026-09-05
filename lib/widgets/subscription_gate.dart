import 'dart:async';
import 'package:flutter/material.dart';
import '../services/permission_service.dart';
import '../services/company_store.dart';
import '../services/session_service.dart';

/// ⭐ Poore app ko is widget se wrap karo (main navigation/home screen ke
/// upar). Agar company ka trial/subscription expire ho chuka hai, to ye
/// ek neutral "Account access limited" screen dikhayega. Agar active hai
/// lekin jald expire hone wala hai, to ek chhota non-blocking warning
/// banner dikhata hai (neeche `_ExpiryWarningBanner` dekho).
///
/// ⚠️ IMPORTANT — Google Play Store compliance:
/// Is file mein kahin bhi JAAN-BUJH KAR koi bhi payment link, "Buy",
/// "Subscribe", pricing, ya clickable website button NAHI hai — na lock
/// screen mein, na warning banner mein. Sirf plain informational text hai
/// ("apna account website/email/Owner se manage karo"). Ye is liye
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
  int? _daysLeft;
  bool _warningDismissed = false;
  StreamSubscription<void>? _sub;
  Timer? _periodicTimer;

  static const int _warningThresholdDays = 3;

  @override
  void initState() {
    super.initState();
    _check();
    _sub = CompanyStore.instance.onDataChanged.listen((_) => _check());

    // ✅ NEW — trial/paid expiry client-side date/time se calculate hoti
    // hai, isliye Firestore data change na bhi ho (jaise app khula hi
    // rahe aur expiry time apne aap nikal jaye), tab bhi ye timer har
    // 5 minute mein dobara check kar lega — taaki account time pe lock ho.
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _check(),
    );
  }

  Future<void> _check() async {
    final result = await PermissionService.isAccountActive();
    final days = await PermissionService.daysUntilExpiry();
    if (!mounted) return;
    if (_active != result || _daysLeft != days) {
      setState(() {
        _active = result;
        _daysLeft = days;
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _periodicTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_active == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_active == false) {
      return const _AccountLockedScreen();
    }

    // ✅ NEW — expiry ke kareeb ho (default: 3 din ya kam bacha ho) to ek
    // chhota, non-blocking, purely informational banner child ke upar
    // overlay ho jaata hai. Child (HomeScreen/FarmerDashboard) bilkul
    // normally kaam karta rehta hai — sirf ek dismiss-able strip dikhti
    // hai upar. Koi payment link/button nahi — sirf status batata hai
    // (Play Store compliance, class doc dekho).
    final showWarning =
        !_warningDismissed &&
        _daysLeft != null &&
        _daysLeft! <= _warningThresholdDays;

    if (!showWarning) return widget.child;

    return Stack(
      children: [
        widget.child,
        _ExpiryWarningBanner(
          daysLeft: _daysLeft!,
          onDismiss: () => setState(() => _warningDismissed = true),
        ),
      ],
    );
  }
}

/// Chhota, dismiss-able, purely informational banner — screen ke upar
/// overlay hota hai, child ka layout disturb nahi karta.
class _ExpiryWarningBanner extends StatelessWidget {
  final int daysLeft;
  final VoidCallback onDismiss;

  const _ExpiryWarningBanner({required this.daysLeft, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final String whenText = daysLeft <= 0
        ? 'aaj'
        : daysLeft == 1
        ? 'kal'
        : '$daysLeft din mein';

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFBEEDA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE9C88F)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Text('⏳', style: TextStyle(fontSize: 15)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    // ⚠️ Purely informational — koi payment link/button
                    // nahi. Owner ko email/website ka plain-text mention,
                    // koi clickable element nahi (Play Store compliance,
                    // is file ke top wala doc comment dekho).
                    'Aapka account $whenText khatam ho raha hai. Access jaari '
                    'rakhne ke liye apne company Owner ya registered '
                    'email/website se sampark karein.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8A5A12),
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onDismiss,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8, top: 1),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: Color(0xFF8A5A12),
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
                //
                // 🛑 NAYA — role-aware text. Email sirf Owner/Personal
                // Farmer ko jaati hai (unhi ke paas registered email hota
                // hai), isliye Office/Field Manager aur Company Farmer ko
                // "email check karo" bolna galat/confusing tha — unke paas
                // koi email hoti hi nahi. Ab unhe "apne Owner se sampark
                // karo" wala accurate message dikhega.
                FutureBuilder<String?>(
                  future: SessionService.currentRole,
                  builder: (context, snapshot) {
                    final role = (snapshot.data ?? '').trim();
                    final isOwnerOrPersonalFarmer =
                        role == 'Owner' || role == 'Personal Farmer';

                    final message = isOwnerOrPersonalFarmer
                        ? 'Aapke account ki membership avdhi samapt ho gayi hai.\n\n'
                              'Account activation ki jankari aapke registered email par bheji gayi hai. '
                              'Kripya apna inbox check karein.'
                        : 'Is company ki membership avdhi samapt ho gayi hai.\n\n'
                              'Account dobara activate karne ke liye apne company Owner se sampark karein.';

                    return Text(
                      message,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Colors.grey,
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    );
                  },
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
