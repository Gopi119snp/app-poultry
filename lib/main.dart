import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'screens/welcome_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/dashboards/office_manager_dashboard.dart';
import 'screens/dashboards/field_manager_dashboard.dart';
import 'screens/dashboards/farmer_dashboard.dart';
import 'services/company_store.dart';
import 'services/firebase_bootstrap.dart';
import 'services/session_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBootstrap.init();
  runApp(const TrackoApp());
}

class AppColors {
  static const defaultPrimary = Color(0xFF1A237E);
  static const poultryColor = Color(0xFF1B5E20);
  static const dairyColor = Color(0xFF0D47A1);
  static const textileColor = Color(0xFF4A148C);
}

class TrackoApp extends StatelessWidget {
  const TrackoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'PoultryPro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.defaultPrimary),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
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
      switch (role) {
        case 'owner':
          Get.off(
            () => HomeScreen(ownerName: ownerName, companyName: companyName),
          );
          break;
        case 'officeManager':
          Get.off(
            () => OfficeManagerDashboard(
              ownerName: ownerName,
              companyName: companyName,
            ),
          );
          break;
        case 'fieldManager':
          Get.off(
            () => FieldManagerDashboard(
              ownerName: ownerName,
              companyName: companyName,
            ),
          );
          break;
        case 'farmer':
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
              'PoultryPro',
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
