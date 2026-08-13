import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// ============================================================================
/// OtpService — Real Firebase Phone Auth (SMS OTP) wrapper
/// ============================================================================
///
/// Ye service 3 jagah use hoti hai:
///   1. Registration (Owner / Personal Farmer) — sirf phone ownership verify karni
///      hai, isliye verifyOtp() ke turant baad signOutOtpSession() call karo.
///   2. Company Farmer OTP Login — verifyOtp() ke baad session signed-in HI
///      rehne do (sign out mat karo), taaki farmer ka real Firebase UID mil
///      jaye aur AuthService use link kar sake.
///   3. Forgot Password (Owner / Personal Farmer) — verifyOtp() ke baad isi
///      verified session se resetPasswordAfterOtp() call karo, phir
///      signOutOtpSession() karo.
///
/// Firebase khud is verified session ke ID token mein `phone_number` claim
/// daalta hai — Cloud Function (resetPasswordAfterOtp) usi claim ko trust
/// karti hai, kisi bhi client-bheje phone number ko nahi.
class OtpService {
  OtpService._();

  static final OtpService instance = OtpService._();

  FirebaseAuth get _auth => FirebaseAuth.instance;

  String? _verificationId;
  int? _resendToken;

  /// 10-digit Indian number ko E.164 format ("+91XXXXXXXXXX") mein badalta hai.
  String _toE164(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final last10 = digits.length >= 10
        ? digits.substring(digits.length - 10)
        : digits;
    return '+91$last10';
  }

  /// STEP 1 — Phone par OTP bhejo.
  ///
  /// [onCodeSent]     → SMS successfully bhej diya gaya, ab UI mein OTP field dikhao.
  /// [onError]        → koi bhi failure (galat number, quota khatam, network).
  /// [onAutoVerified] → sirf Android par kabhi-kabhi call hota hai jab OS khud
  ///                    hi SMS padh ke verify kar deta hai (user ko OTP type
  ///                    karne ki zaroorat nahi padti). Optional hai — na diya
  ///                    to bhi kaam chalega, user manually OTP daal dega.
  Future<void> sendOtp({
    required String phone,
    required VoidCallback onCodeSent,
    required void Function(String message) onError,
    VoidCallback? onAutoVerified,
  }) async {
    final e164 = _toE164(phone);

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: e164,
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            await _auth.signInWithCredential(credential);
            onAutoVerified?.call();
          } catch (e) {
            onError(_friendlyError(e));
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint(
            '[OtpService] verificationFailed → code: ${e.code}, message: ${e.message}',
          );
          onError(_friendlyError(e));
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          onCodeSent();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // Timeout ho gaya, lekin agar user abhi bhi OTP type karke submit
          // karega to ye verificationId use hoga — isliye store rakhna zaroori hai.
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      debugPrint('[OtpService] sendOtp catch → $e');
      onError(_friendlyError(e));
    }
  }

  /// STEP 2 — User ne jo 6-digit code type kiya, wo verify karo.
  /// Success par user temporarily Firebase Auth mein phone-verified sign-in
  /// ho jata hai. Return `true` = OTP sahi tha, `false` = galat tha.
  Future<bool> verifyOtp(String smsCode) async {
    if (_verificationId == null) {
      debugPrint(
        '[OtpService] verifyOtp: koi verificationId nahi hai — pehle sendOtp() call karo',
      );
      return false;
    }
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode.trim(),
      );
      await _auth.signInWithCredential(credential);
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('[OtpService] verifyOtp failed: ${e.code}');
      return false;
    }
  }

  /// Verified phone-auth session se sign out — jab kaam ho chuka ho
  /// (registration complete ho gayi, ya password reset complete ho gaya).
  /// Isse app ka "asli" login session (email/password wala) disturb nahi hota,
  /// kyunki ye sirf temporary verification session tha.
  Future<void> signOutOtpSession() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // ignore — already signed out ho sakta hai
    }
    _verificationId = null;
    _resendToken = null;
  }

  /// Forgot Password — EMAIL OTP based (ab mobile OTP/phone-auth session
  /// ki zaroorat nahi). [resetToken] wahi hai jo verifyEmailOtpForReset()
  /// se mila tha — isse pehle wo call karna ZAROORI hai.
  ///
  /// Return: `null` = success, warna error message (Hinglish, user ko dikhane layak).
  Future<String?> resetPasswordAfterOtp({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'resetPasswordAfterOtp',
      );
      final result = await callable.call(<String, dynamic>{
        'email': email.trim().toLowerCase(),
        'resetToken': resetToken,
        'newPassword': newPassword,
      });
      final data = result.data;
      if (data is Map && data['success'] == true) return null;
      return 'Password reset fail ho gaya';
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? 'Password reset error (${e.code})';
    } catch (e) {
      return 'Password reset error: $e';
    }
  }

  /// Forgot Password ka Email OTP verify karta hai — normal verifyEmailOtp()
  /// jaisa hi hai, bas success par ek `resetToken` bhi milta hai jo
  /// resetPasswordAfterOtp() mein use hoga. Return `null` = OTP galat/expire,
  /// warna resetToken string.
  Future<String?> verifyEmailOtpForReset(String email, String code) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'verifyEmailOtpForReset',
      );
      final result = await callable.call(<String, dynamic>{
        'email': email.trim().toLowerCase(),
        'code': code.trim(),
      });
      final data = result.data;
      if (data is Map && data['success'] == true) {
        return data['resetToken'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('[OtpService] verifyEmailOtpForReset failed: $e');
      return null;
    }
  }

  /// Email OTP bhejta hai — Cloud Function (`sendEmailOtp`) ke through,
  /// jo Gmail SMTP se real email bhejti hai. Company registration ke
  /// email-verification step ke liye use hota hai.
  ///
  /// Return: `null` = success, warna error message.
  Future<String?> sendEmailOtp(String email) async {
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty) return 'Email address daalo';
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('sendEmailOtp');
      final result = await callable.call(<String, dynamic>{'email': trimmed});
      final data = result.data;
      if (data is Map && data['success'] == true) return null;
      return 'Email OTP bhejne mein fail ho gaya';
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? 'Email OTP error (${e.code})';
    } catch (e) {
      return 'Email OTP error: $e';
    }
  }

  /// Email OTP verify karta hai — Cloud Function (`verifyEmailOtp`) se.
  /// Return `true` = code sahi tha, `false` = galat/expire ho gaya.
  Future<bool> verifyEmailOtp(String email, String code) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'verifyEmailOtp',
      );
      final result = await callable.call(<String, dynamic>{
        'email': email.trim().toLowerCase(),
        'code': code.trim(),
      });
      final data = result.data;
      return data is Map && data['success'] == true;
    } catch (e) {
      debugPrint('[OtpService] verifyEmailOtp failed: $e');
      return false;
    }
  }

  String _friendlyError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-phone-number':
          return 'Phone number format galat hai';
        case 'too-many-requests':
          return 'Bahut zyada koshish ho gayi — thodi der baad try karo';
        case 'quota-exceeded':
          return 'SMS quota khatam ho gaya — Firebase Console check karo';
        case 'invalid-verification-code':
          return 'OTP galat hai';
        case 'session-expired':
          return 'OTP expire ho gaya — dobara bhejo';
        case 'operation-not-allowed':
          return 'Phone sign-in Firebase Console mein enable nahi hai';
        default:
          return e.message ?? 'OTP error (${e.code})';
      }
    }
    return e.toString();
  }
}
