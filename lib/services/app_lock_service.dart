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

  /// Last biometric attempt ka human-readable error — AppLockScreen ye
  /// dikha sakti hai taaki silent failure na ho.
  String? lastBiometricError;

  bool _wasBackgrounded = false;

  // ✅ CRITICAL FIX: Jab Android ka system biometric dialog khulta hai
  // (Face/Fingerprint prompt), wo Flutter app ko technically "pause"
  // karta hai aur result aane par "resume" karta hai — bilkul waise hi
  // jaise user ne app minimize kiya ho. Pehle iske wajah se
  // onAppResumed() dobara isLocked=true set kar deta tha, jisse
  // AppLockScreen dobara build hoti thi aur biometric prompt phir se
  // automatically trigger ho jaata tha — ek infinite loop. Ye flag
  // authentication ke dauraan pause/resume events ko ignore karta hai.
  bool _isAuthenticating = false;

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
      debugPrint(
        '[AppLockService] isDeviceSupported=$supported canCheckBiometrics=$canCheck',
      );
      return supported && canCheck;
    } catch (e, st) {
      debugPrint('[AppLockService] biometric availability check failed: $e');
      debugPrint('$st');
      return false;
    }
  }

  /// Device mein kaunse biometric types enrolled hain — debugging ke liye.
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      final types = await _localAuth.getAvailableBiometrics();
      debugPrint('[AppLockService] available biometrics: $types');
      return types;
    } catch (e) {
      debugPrint('[AppLockService] getAvailableBiometrics failed: $e');
      return [];
    }
  }

  /// Face/Fingerprint prompt dikhata hai. `true` = unlock success.
  ///
  /// ✅ FIX: `_isAuthenticating` flag set karte hain taaki system
  /// biometric dialog ki wajah se aane wale pause/resume lifecycle
  /// events ko app khud "user minimize kiya" na samjhe aur dobara
  /// lock/prompt loop mein na jaaye.
  Future<bool> authenticateWithBiometrics() async {
    lastBiometricError = null;
    _isAuthenticating = true;
    try {
      final result = await _localAuth.authenticate(
        localizedReason: 'App unlock karne ke liye verify karein',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      debugPrint('[AppLockService] authenticate() result = $result');
      if (!result) {
        lastBiometricError = 'Authentication cancel ya fail hua';
      }
      return result;
    } catch (e, st) {
      debugPrint('[AppLockService] biometric auth EXCEPTION: $e');
      debugPrint('$st');
      lastBiometricError = e.toString();
      return false;
    } finally {
      // System biometric dialog band hone ke turant baad bhi Android
      // ka resume event thodi der se fire ho sakta hai — isliye chhoti
      // delay ke baad hi flag clear karte hain, taaki wo late resume
      // event bhi safely ignore ho jaaye.
      Future.delayed(const Duration(milliseconds: 600), () {
        _isAuthenticating = false;
      });
    }
  }

  // ── App lifecycle wiring (main.dart se call hota hai) ───────────────────

  /// App background/minimize mein gaya.
  void onAppPaused() {
    if (_isAuthenticating) {
      // Biometric prompt ki wajah se aaya pause hai — ignore karo.
      debugPrint(
        '[AppLockService] onAppPaused ignored (biometric prompt active)',
      );
      return;
    }
    _wasBackgrounded = true;
  }

  /// App resume hua (minimize se wapas aaya). Agar user logged-in hai aur
  /// PIN setup done hai, to lock-screen dikhado.
  Future<void> onAppResumed() async {
    if (_isAuthenticating) {
      // Biometric prompt ki wajah se aaya resume hai — ignore karo,
      // warna yahi dobara isLocked=true set kar dega aur infinite
      // biometric-prompt loop ban jaayega.
      debugPrint(
        '[AppLockService] onAppResumed ignored (biometric prompt active)',
      );
      return;
    }
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
    debugPrint('[AppLockService] unlock() called — isLocked -> false');
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
