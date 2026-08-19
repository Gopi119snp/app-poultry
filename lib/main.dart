import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/foundation.dart'; // ✅ For debugPrint

import 'screens/welcome_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/dashboards/farmer_dashboard.dart';
import 'screens/auth/app_lock_screen.dart';
import 'services/company_store.dart';
import 'services/firebase_bootstrap.dart';
import 'services/session_service.dart';
import 'services/app_lock_service.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✅ NAYA — anonymous auth ke liye

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBootstrap.init();
  await _ensureAnonymousAuth(); // ✅ NAYA — Firestore rules pass karne ke liye
  runApp(const TrackoApp());
}

/// ✅ Anonymous Firebase Auth session banata hai (agar already nahi hai),
/// taaki Firestore Security Rules ka `request.auth != null` check pass ho
/// jaye. Ye humara real login system (phone+PIN/password) replace nahi
/// karta — sirf Firestore access allow karne ke liye ek background session
/// hai. FirebaseBootstrap.isReady false (local mode) to skip karo.
Future<void> _ensureAnonymousAuth() async {
  if (!FirebaseBootstrap.isReady) return;
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (e) {
    debugPrint('[main] Anonymous auth failed: $e');
  }
}

class AppColors {
  static const defaultPrimary = Color(0xFF1A237E);
  static const poultryColor = Color(0xFF1B5E20);
  static const dairyColor = Color(0xFF0D47A1);
  static const textileColor = Color(0xFF4A148C);
}

class TrackoApp extends StatefulWidget {
  const TrackoApp({super.key});

  @override
  State<TrackoApp> createState() => _TrackoAppState();
}

/// ✅ App Lock ke liye WidgetsBindingObserver — app minimize (paused) aur
/// wapas khulne (resumed) par AppLockService ko batata hai, taaki zaroorat
/// padne par lock-screen automatically overlay ho jaye.
class _TrackoAppState extends State<TrackoApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      AppLockService.instance.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      AppLockService.instance.onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Tracko',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.defaultPrimary),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
      // ✅ App Lock Overlay — jab bhi AppLockService.isLocked true ho, ye
      // poori app ke upar ek full-screen lock-screen dikha deta hai. Isse
      // koi bhi screen (jahan bhi user ho) turant lock ho jaati hai.
      builder: (context, child) {
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            ValueListenableBuilder<bool>(
              valueListenable: AppLockService.instance.isLocked,
              builder: (context, locked, _) {
                if (!locked) return const SizedBox.shrink();
                return const AppLockScreen();
              },
            ),
          ],
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), _checkLoginStatus);
  }

  Future<void> _checkLoginStatus() async {
    final isLoggedIn = await SessionService.isLoggedIn;
    final ownerName = await SessionService.ownerName ?? '';
    final companyName = await SessionService.companyName ?? '';
    final companyId = await SessionService.companyId;
    final role = await SessionService.currentRole ?? 'owner'; // ← Role check

    if (isLoggedIn && companyId != null) {
      await CompanyStore.instance.activateCompany(companyId);
    }

    if (!mounted) return;

    if (isLoggedIn && ownerName.isNotEmpty) {
      // ✅ Already logged-in hai — cold start pe bhi App Lock lagegi
      // (agar setup ho chuka hai). Setup nahi hua ho (purana user, naya
      // update aaya hai) to lockIfNeeded() kuch nahi karega, seedha
      // dashboard khulega — agli baar login/register pe setup mandatory
      // ho jayega.
      await AppLockService.instance.lockIfNeeded();

      // ✅ FIX — Owner, Office Manager, Field Manager — sab ab HomeScreen
      // use karenge, jaha permission-based system se access control hota
      // hai. Sirf Company Farmer ka alag dashboard/login-flow hai, isliye
      // wahi separate rakha hai.
      switch (role.trim()) {
        case 'Company Farmer':
          Get.off(
            () =>
                FarmerDashboard(ownerName: ownerName, companyName: companyName),
          );
          break;
        default:
          Get.off(
            () => HomeScreen(ownerName: ownerName, companyName: companyName),
          );
      }
    } else {
      Get.off(() => const WelcomeScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.defaultPrimary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withOpacity(0.25),
                  width: 1.5,
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.track_changes_rounded,
                  size: 60,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Tracko',
              style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              FirebaseBootstrap.isReady
                  ? 'CLOUD SYNC ON'
                  : 'LOCAL MODE — Firebase configure karo',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white.withOpacity(0.85),
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 60),
            SizedBox(
              width: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  backgroundColor: Colors.white.withOpacity(0.15),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
