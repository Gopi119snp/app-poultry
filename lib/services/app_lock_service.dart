import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_service.dart';
import '../screens/auth/app_lock_setup_screen.dart';

/// ============================================================================
/// AppLockService — Device-level App Lock (Face/Fingerprint ya PIN)
/// ============================================================================
///
/// Ye login/register session se ALAG hai — ye ek extra local security layer
/// hai jo HAR user (Owner, Manager, Company Farmer, Personal Farmer) ke
/// liye lagu hoti hai:
///   - App pehli baar khulti hai (cold start, already logged-in)
///   - App minimize karke wapas khola jaye (resume)
///
/// PIN aur biometric preference sirf isi DEVICE par store hoti hai
/// (SharedPreferences), Firebase/server ko iska pata nahi hota — isliye
/// zero cost hai, koi network call nahi lagti.
class AppLockService {
  AppLockService._();
  static final AppLockService instance = AppLockService._();

  static const _kPinHash = 'app_lock_pin_hash';
  static const _kBiometricEnabled = 'app_lock_biometric_enabled';
  static const _kSetupDone = 'app_lock_setup_done';

  final LocalAuthentication _localAuth = LocalAuthentication();

  /// Jab true ho, poore app ke upar lock-screen overlay dikhta hai
  /// (main.dart mein wire kiya hua).
  final ValueNotifier<bool> isLocked = ValueNotifier<bool>(false);

  bool _wasBackgrounded = false;

  // ── PIN hashing (SHA-256, koi plaintext store nahi hota) ────────────────
  String _hashPin(String pin) => sha256.convert(utf8.encode(pin)).toString();

  // ── Setup status ─────────────────────────────────────────────────────────
  Future<bool> isSetupDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSetupDone) ?? false;
  }

  /// PIN set karta hai (4 digit) aur setup ko "done" mark karta hai.
  Future<void> setupPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPinHash, _hashPin(pin));
    await prefs.setBool(_kSetupDone, true);
  }

  Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final storedHash = prefs.getString(_kPinHash);
    if (storedHash == null) return false;
    return storedHash == _hashPin(pin);
  }

  // ── Biometric preference ────────────────────────────────────────────────
  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiometricEnabled, enabled);
  }

  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBiometricEnabled) ?? false;
  }

  /// Kya is device mein Face/Fingerprint hardware available hai?
  Future<bool> isBiometricAvailable() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported && canCheck;
    } catch (e) {
      debugPrint('[AppLockService] biometric check failed: $e');
      return false;
    }
  }

  /// Face/Fingerprint prompt dikhata hai. `true` = unlock success.
  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'App unlock karne ke liye verify karein',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (e) {
      debugPrint('[AppLockService] biometric auth failed: $e');
      return false;
    }
  }

  // ── App lifecycle wiring (main.dart se call hota hai) ───────────────────

  /// App background/minimize mein gaya.
  void onAppPaused() {
    _wasBackgrounded = true;
  }

  /// App resume hua (minimize se wapas aaya). Agar user logged-in hai aur
  /// PIN setup done hai, to lock-screen dikhado.
  Future<void> onAppResumed() async {
    if (!_wasBackgrounded) return;
    _wasBackgrounded = false;

    final loggedIn = await SessionService.isLoggedIn;
    if (!loggedIn) return;

    final setupDone = await isSetupDone();
    if (!setupDone) return; // Setup abhi hua hi nahi (edge case)

    isLocked.value = true;
  }

  /// Cold-start ke turant baad (SplashScreen se) explicitly lock karne ke
  /// liye — taaki app khulte hi lock-screen dikhe agar setup already ho
  /// chuka hai.
  Future<void> lockIfNeeded() async {
    final setupDone = await isSetupDone();
    if (setupDone) {
      isLocked.value = true;
    }
  }

  void unlock() {
    isLocked.value = false;
  }

  /// Login/Register success ke baad ye call karo — agar PIN setup nahi
  /// hua hai to mandatory Setup Screen dikhayega, warna seedha
  /// [nextScreen] par le jayega.
  Future<void> routeAfterAuth(Widget nextScreen) async {
    final setupDone = await isSetupDone();
    if (setupDone) {
      Get.offAll(() => nextScreen);
    } else {
      Get.offAll(() => AppLockSetupScreen(nextScreen: nextScreen));
    }
  }
}
