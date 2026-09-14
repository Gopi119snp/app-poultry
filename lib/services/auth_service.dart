import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'company_store.dart';
import 'firebase_bootstrap.dart';
import 'session_service.dart';

class AuthResult {
  final bool success;
  final String? errorMessage;
  final String? companyId;
  final String? role;
  final String? displayName;
  final String? ownerName;
  final String? companyName;

  const AuthResult({
    required this.success,
    this.errorMessage,
    this.companyId,
    this.role,
    this.displayName,
    this.ownerName,
    this.companyName,
  });

  factory AuthResult.fail(String message) =>
      AuthResult(success: false, errorMessage: message);

  factory AuthResult.ok({
    required String companyId,
    required String role,
    required String displayName,
    required String ownerName,
    required String companyName,
  }) => AuthResult(
    success: true,
    companyId: companyId,
    role: role,
    displayName: displayName,
    ownerName: ownerName,
    companyName: companyName,
  );
}

/// Company Farmer login ke "number check" step ka result — batata hai
/// number valid hai ya nahi, aur uska PIN pehle se set hai ya nahi
/// (set hai = returning farmer, PIN daalo | nahi hai = naya, PIN set karo).
class FarmerPhoneCheckResult {
  final bool exists;
  final bool hasPin;
  final String? companyId;
  final String? farmerName;

  const FarmerPhoneCheckResult({
    required this.exists,
    required this.hasPin,
    this.companyId,
    this.farmerName,
  });
}

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  FirebaseAuth get _auth => FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  /// Company owner registration — Firebase Auth + Firestore company doc.
  Future<AuthResult> registerCompany({
    required String email,
    required String password,
    required String ownerName,
    required String companyName,
    required String phone,
    required String industry,
    Map<String, dynamic>? extraProfile,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      return _registerCompanyLocalOnly(
        email: email,
        password: password,
        ownerName: ownerName,
        companyName: companyName,
        phone: phone,
        industry: industry,
      );
    }

    // 🛑 NAYA — phone-uniqueness check. Pehle ye check kahin nahi tha,
    // isliye same phone number se baar-baar naya company account ban
    // jaata tha (jisse login ke time phone_lookup ambiguous ho jaata aur
    // permission errors aate). Ab Firebase Auth account banane se PEHLE
    // hi verify karte hain ki ye number kisi aur account (Owner/Manager/
    // Farmer) se already linked to nahi hai.
    final normalizedPhone = _normalizePhone(phone);
    final existingLookup = await CompanyStore.instance.lookupPhone(
      normalizedPhone,
    );
    if (existingLookup != null) {
      final existingRole = existingLookup['role'] as String? ?? 'account';
      return AuthResult.fail(
        'Yeh phone number pehle se register hai ($existingRole ke roop mein). '
        'Isi number se dobara naya account nahi ban sakta. Agar ye number '
        'aapka hi hai, to "Forgot Password" se apne purane account mein '
        'login karo.',
      );
    }

    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      final uid = cred.user!.uid;

      // ✅ FIX — Agar account banne ke baad (upar wali line) koi bhi
      // step fail ho jaye (internet cut, app crash, Firestore error
      // waghera), to Firebase Auth account yahin turant DELETE (rollback)
      // kar dete hain. Warna wo email hamesha ke liye "already
      // registered" bol ke stuck ho jata, bina kisi usable account ke —
      // na login ho sakta, na dobara register ho sakta.
      try {
        final profile = {
          'ownerName': ownerName,
          'companyName': companyName,
          'phone': phone,
          'email': email.trim().toLowerCase(),
          'authEmail': email.trim().toLowerCase(),
          'industry': industry,
          'accountType': 'company',
          if (extraProfile != null) ...extraProfile,
        };

        await CompanyStore.instance.createCompanyInCloud(
          companyId: uid,
          profile: profile,
        );

        await CompanyStore.instance.linkAuthUser(
          authUid: uid,
          companyId: uid,
          role: 'Owner',
          phone: phone,
          displayName: ownerName,
        );

        await CompanyStore.instance.registerPhoneLookup(
          phone: phone,
          companyId: uid,
          role: 'Owner',
          authEmail: email.trim().toLowerCase(),
          displayName: ownerName,
        );

        await SessionService.saveLoginSession(
          companyId: uid,
          role: 'Owner',
          displayName: ownerName,
          ownerName: ownerName,
          companyName: companyName,
          phone: phone,
          industry: industry,
          authEmail: email.trim().toLowerCase(),
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('password', password);
      } catch (innerError) {
        debugPrint(
          '[registerCompany] Post-auth step failed, rolling back Auth user: $innerError',
        );
        try {
          await cred.user!.delete();
        } catch (deleteError) {
          debugPrint(
            '[registerCompany] Rollback delete also failed: $deleteError',
          );
        }
        return AuthResult.fail(
          'Registration beech mein fail ho gaya (network/data issue). '
          'Koi account create nahi hua — dobara try karo.',
        );
      }

      return AuthResult.ok(
        companyId: uid,
        role: 'Owner',
        displayName: ownerName,
        ownerName: ownerName,
        companyName: companyName,
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult.fail(_authErrorMessage(e));
    } catch (e) {
      return AuthResult.fail('Registration fail: $e');
    }
  }

  /// Personal Farmer registration — akela farmer apna khud ka farm chalata
  /// hai, koi doosra staff nahi hota. Company jaisa hi Firestore schema
  /// reuse hota hai — bas `companyId` khud farmer ka apna `uid` hota hai
  /// (single-farmer "company"), isliye baaki saara app (farmers_screen,
  /// batch screens, waghera) bina kisi change ke iske saath kaam karta hai.
  ///
  /// [email] optional hai — personal register screen mein email field
  /// optional hai. Agar nahi diya to phone-based synthetic email banta hai
  /// (jaise staff members ke liye already ban raha hai), taaki
  /// Firebase Auth ke liye email+password ki zaroorat poori ho jaye.
  Future<AuthResult> registerPersonalFarmer({
    required String farmerName,
    required String phone,
    required String password,
    required String industry,
    String? email,
    Map<String, dynamic>? extraProfile,
  }) async {
    final normalized = _normalizePhone(phone);
    final authEmail = (email != null && email.trim().isNotEmpty)
        ? email.trim().toLowerCase()
        : 'personal.$normalized@poultrypro.app';

    if (!FirebaseBootstrap.isReady) {
      return _registerCompanyLocalOnly(
        email: authEmail,
        password: password,
        ownerName: farmerName,
        companyName: farmerName,
        phone: normalized,
        industry: industry,
      );
    }

    // 🛑 NAYA — phone-uniqueness check (registerCompany() jaisa hi wajah).
    // Auth account banane se PEHLE verify karte hain ki ye number kisi aur
    // account (Owner/Manager/Farmer) se already linked to nahi hai.
    final existingLookup = await CompanyStore.instance.lookupPhone(normalized);
    if (existingLookup != null) {
      final existingRole = existingLookup['role'] as String? ?? 'account';
      return AuthResult.fail(
        'Yeh phone number pehle se register hai ($existingRole ke roop mein). '
        'Isi number se dobara naya account nahi ban sakta. Agar ye number '
        'aapka hi hai, to "Forgot Password" se apne purane account mein '
        'login karo.',
      );
    }

    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: authEmail,
        password: password,
      );

      final uid = cred.user!.uid;

      // ✅ FIX — registerCompany() jaisa hi rollback: agar account banne
      // ke baad koi step fail ho, to Auth user turant delete kar dete
      // hain, taaki email hamesha ke liye stuck na ho jaye.
      try {
        final profile = {
          'ownerName': farmerName,
          'companyName': farmerName,
          'phone': normalized,
          'email': authEmail,
          'authEmail': authEmail,
          'industry': industry,
          'accountType': 'personal',
          if (extraProfile != null) ...extraProfile,
        };

        await CompanyStore.instance.createCompanyInCloud(
          companyId: uid,
          profile: profile,
        );

        await CompanyStore.instance.linkAuthUser(
          authUid: uid,
          companyId: uid,
          role: 'Personal Farmer',
          phone: normalized,
          displayName: farmerName,
        );

        await CompanyStore.instance.registerPhoneLookup(
          phone: normalized,
          companyId: uid,
          role: 'Personal Farmer',
          authEmail: authEmail,
          displayName: farmerName,
        );

        await SessionService.saveLoginSession(
          companyId: uid,
          role: 'Personal Farmer',
          displayName: farmerName,
          ownerName: farmerName,
          companyName: farmerName,
          phone: normalized,
          industry: industry,
          authEmail: authEmail,
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('password', password);
      } catch (innerError) {
        debugPrint(
          '[registerPersonalFarmer] Post-auth step failed, rolling back Auth user: $innerError',
        );
        try {
          await cred.user!.delete();
        } catch (deleteError) {
          debugPrint(
            '[registerPersonalFarmer] Rollback delete also failed: $deleteError',
          );
        }
        return AuthResult.fail(
          'Registration beech mein fail ho gaya (network/data issue). '
          'Koi account create nahi hua — dobara try karo.',
        );
      }

      return AuthResult.ok(
        companyId: uid,
        role: 'Personal Farmer',
        displayName: farmerName,
        ownerName: farmerName,
        companyName: farmerName,
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult.fail(_authErrorMessage(e));
    } catch (e) {
      return AuthResult.fail('Registration fail: $e');
    }
  }

  /// Phone + password login — Owner, Manager, Personal Farmer.
  Future<AuthResult> loginWithPhonePassword({
    required String phone,
    required String password,
  }) async {
    final normalized = _normalizePhone(phone);

    if (FirebaseBootstrap.isReady) {
      try {
        final lookup = await CompanyStore.instance.lookupPhone(normalized);

        if (lookup != null) {
          final companyId = lookup['companyId'] as String;
          final role = lookup['role'] as String? ?? 'Owner';
          final authEmail = lookup['authEmail'] as String?;

          if (authEmail != null && authEmail.isNotEmpty) {
            await _auth.signInWithEmailAndPassword(
              email: authEmail,
              password: password,
            );

            await CompanyStore.instance.activateCompany(companyId);
            final profile = await _loadCompanyProfile(companyId);

            if (role == 'Office Manager' || role == 'Field Manager') {
              final valid = await _verifyManagerPassword(
                companyId: companyId,
                phone: normalized,
                password: password,
                role: role,
              );
              if (!valid) {
                await _auth.signOut();
                return AuthResult.fail('Phone ya password galat hai');
              }
            }

            final displayName =
                lookup['displayName'] as String? ??
                profile['ownerName'] as String? ??
                '';

            await _finalizeSession(
              companyId: companyId,
              role: role,
              displayName: displayName,
              profile: profile,
              phoneOverride: normalized, // ✅ ADD
            );

            return AuthResult.ok(
              companyId: companyId,
              role: role,
              displayName: displayName,
              ownerName: profile['ownerName'] as String? ?? displayName,
              companyName: profile['companyName'] as String? ?? '',
            );
          }
        }

        final localEmail = await SessionService.authEmail;
        if (localEmail != null) {
          await _auth.signInWithEmailAndPassword(
            email: localEmail,
            password: password,
          );
          final companyId = _auth.currentUser!.uid;
          await CompanyStore.instance.activateCompany(companyId);
          final profile = await _loadCompanyProfile(companyId);
          await _finalizeSession(
            companyId: companyId,
            role: 'Owner',
            displayName: profile['ownerName'] as String? ?? '',
            profile: profile,
            phoneOverride: normalized, // ✅ ADD
          );
          return AuthResult.ok(
            companyId: companyId,
            role: 'Owner',
            displayName: profile['ownerName'] as String? ?? '',
            ownerName: profile['ownerName'] as String? ?? '',
            companyName: profile['companyName'] as String? ?? '',
          );
        }
      } on FirebaseAuthException catch (e) {
        if (e.code != 'user-not-found' && e.code != 'wrong-password') {
          return AuthResult.fail(_authErrorMessage(e));
        }
      }
    }

    return _loginLocalOnly(phone: normalized, password: password);
  }

  /// Company farmer OTP login (registered check + session).
  Future<AuthResult> loginCompanyFarmer({required String phone}) async {
    final normalized = _normalizePhone(phone);

    if (FirebaseBootstrap.isReady) {
      final lookup = await CompanyStore.instance.lookupPhone(normalized);
      String? companyId = lookup?['companyId'] as String?;

      companyId ??= await _findCompanyIdForFarmerPhone(normalized);

      if (companyId != null) {
        await CompanyStore.instance.activateCompany(companyId);
        final farmers = await CompanyStore.instance.getJsonList(
          'companyFarmers',
        );
        final farmer = farmers.where((f) => f['phone'] == normalized).toList();

        if (farmer.isEmpty) {
          return AuthResult.fail(
            'Yeh number register nahi hai. Owner se contact karo.',
          );
        }

        final profile = await _loadCompanyProfile(companyId);
        await _finalizeSession(
          companyId: companyId,
          role: 'Company Farmer',
          displayName: farmer.first['name'] as String? ?? '',
          profile: profile,
          phoneOverride: normalized, // ✅ ADD
        );

        return AuthResult.ok(
          companyId: companyId,
          role: 'Company Farmer',
          displayName: farmer.first['name'] as String? ?? '',
          ownerName: profile['ownerName'] as String? ?? '',
          companyName: profile['companyName'] as String? ?? '',
        );
      }
    }

    final farmers = await CompanyStore.instance.getJsonList('companyFarmers');
    final farmer = farmers.where((f) => f['phone'] == normalized).toList();
    if (farmer.isEmpty) {
      return AuthResult.fail(
        'Yeh number register nahi hai. Owner se contact karo.',
      );
    }

    final companyName = await SessionService.companyName ?? '';
    final ownerName = await SessionService.ownerName ?? '';
    final companyId = await SessionService.companyId ?? 'local';
    await SessionService.saveLoginSession(
      companyId: companyId,
      role: 'Company Farmer',
      displayName: farmer.first['name'] as String? ?? '',
      ownerName: ownerName,
      companyName: companyName,
      phone: normalized,
      industry: await SessionService.industry ?? 'poultry',
    );

    return AuthResult.ok(
      companyId: companyId,
      role: 'Company Farmer',
      displayName: farmer.first['name'] as String? ?? '',
      ownerName: ownerName,
      companyName: companyName,
    );
  }

  // ==========================================================================
  // COMPANY FARMER LOGIN — NUMBER MATCH + PIN (Cloud Functions ke through,
  // Admin SDK bypass rules) + Custom Auth Token (taaki farmer bhi properly
  // Firebase Auth mein "signed in" ho jaye, aur dashboard ki normal
  // Firestore reads bhi Security Rules pass kar sakein).
  // ==========================================================================

  /// Step 1 — Number check karta hai: kya ye Company Farmer record mein
  /// hai, aur kya uska PIN pehle se set hai (returning farmer) ya nahi
  /// (naya/pehli-baar login — PIN set karwana hoga).
  Future<FarmerPhoneCheckResult> checkCompanyFarmerPhone(String phone) async {
    final normalized = _normalizePhone(phone);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'checkCompanyFarmerPin',
      );
      final result = await callable.call<Map<String, dynamic>>({
        'phone': normalized,
      });
      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['exists'] != true) {
        return FarmerPhoneCheckResult(exists: false, hasPin: false);
      }

      return FarmerPhoneCheckResult(
        exists: true,
        hasPin: data['hasPin'] == true,
        companyId: data['companyId'] as String?,
        farmerName: data['farmerName'] as String? ?? '',
      );
    } catch (e) {
      debugPrint('[checkCompanyFarmerPhone] failed: $e');
      return FarmerPhoneCheckResult(exists: false, hasPin: false);
    }
  }

  /// Step 2a — Pehli baar login: farmer apna 4-digit PIN set karta hai —
  /// lekin pehle apni Date of Birth confirm karta hai (jo Office Manager
  /// ne onboarding KYC mein li thi). PIN set karne aur DOB verify karne
  /// ka kaam ab `setupCompanyFarmerPin` Cloud Function (Admin SDK) karta
  /// hai, taaki Firestore Security Rules kabhi block na karein. Success
  /// hone par mila hua Custom Auth Token use karke farmer ko properly
  /// Firebase Auth mein sign-in karte hain.
  Future<AuthResult> setupCompanyFarmerPin({
    required String companyId,
    required String phone,
    required String dob,
    required String pin,
  }) async {
    try {
      final normalized = _normalizePhone(phone);
      final callable = FirebaseFunctions.instance.httpsCallable(
        'setupCompanyFarmerPin',
      );
      final result = await callable.call<Map<String, dynamic>>({
        'phone': normalized,
        'dob': dob,
        'pin': pin,
      });
      final data = Map<String, dynamic>.from(result.data as Map);

      await _auth.signInWithCustomToken(data['customToken'] as String);

      final resolvedCompanyId = data['companyId'] as String;
      await CompanyStore.instance.activateCompany(resolvedCompanyId);

      final farmerName = data['farmerName'] as String? ?? '';
      final profile = {
        'ownerName': data['ownerName'] ?? '',
        'companyName': data['companyName'] ?? '',
      };

      await _finalizeSession(
        companyId: resolvedCompanyId,
        role: 'Company Farmer',
        displayName: farmerName,
        profile: profile,
        phoneOverride: normalized,
      );

      return AuthResult.ok(
        companyId: resolvedCompanyId,
        role: 'Company Farmer',
        displayName: farmerName,
        ownerName: profile['ownerName'] as String? ?? '',
        companyName: profile['companyName'] as String? ?? '',
      );
    } on FirebaseFunctionsException catch (e) {
      return AuthResult.fail(e.message ?? 'PIN set nahi ho paaya.');
    } catch (e) {
      debugPrint('[setupCompanyFarmerPin] failed: $e');
      return AuthResult.fail('PIN set nahi ho paaya: ${e.toString()}');
    }
  }

  /// Step 2b — Returning farmer: number + PIN se login. PIN check karne
  /// ka kaam ab `loginCompanyFarmerWithPin` Cloud Function (Admin SDK)
  /// karta hai. Success hone par mila hua Custom Auth Token use karke
  /// farmer ko properly Firebase Auth mein sign-in karte hain.
  Future<AuthResult> loginCompanyFarmerWithPin({
    required String companyId,
    required String phone,
    required String pin,
  }) async {
    try {
      final normalized = _normalizePhone(phone);
      final callable = FirebaseFunctions.instance.httpsCallable(
        'loginCompanyFarmerWithPin',
      );
      final result = await callable.call<Map<String, dynamic>>({
        'phone': normalized,
        'pin': pin,
      });
      final data = Map<String, dynamic>.from(result.data as Map);

      await _auth.signInWithCustomToken(data['customToken'] as String);

      final resolvedCompanyId = data['companyId'] as String;
      await CompanyStore.instance.activateCompany(resolvedCompanyId);

      final farmerName = data['farmerName'] as String? ?? '';
      final profile = {
        'ownerName': data['ownerName'] ?? '',
        'companyName': data['companyName'] ?? '',
      };

      await _finalizeSession(
        companyId: resolvedCompanyId,
        role: 'Company Farmer',
        displayName: farmerName,
        profile: profile,
        phoneOverride: normalized,
      );

      return AuthResult.ok(
        companyId: resolvedCompanyId,
        role: 'Company Farmer',
        displayName: farmerName,
        ownerName: profile['ownerName'] as String? ?? '',
        companyName: profile['companyName'] as String? ?? '',
      );
    } on FirebaseFunctionsException catch (e) {
      return AuthResult.fail(e.message ?? 'Login nahi ho paaya.');
    } catch (e) {
      debugPrint('[loginCompanyFarmerWithPin] failed: $e');
      return AuthResult.fail('Login nahi ho paaya: ${e.toString()}');
    }
  }

  /// ✅ PRIMARY reset path — SELF-SERVICE, farmer khud karta hai, Office
  /// Manager/Owner ki zaroorat nahi. Farmer apni **Date of Birth**
  /// confirm karta hai (jo onboarding ke time Office Manager ne KYC mein
  /// li thi) — match hone par naya PIN set ho jata hai aur farmer seedha
  /// login bhi ho jata hai. Ab ye kaam `resetCompanyFarmerPinWithDob`
  /// Cloud Function (Admin SDK) karta hai, taaki Firestore Security Rules
  /// kabhi block na karein.
  Future<AuthResult> resetFarmerPinWithDob({
    required String companyId,
    required String phone,
    required String dob,
    required String newPin,
  }) async {
    try {
      final normalized = _normalizePhone(phone);
      final callable = FirebaseFunctions.instance.httpsCallable(
        'resetCompanyFarmerPinWithDob',
      );
      final result = await callable.call<Map<String, dynamic>>({
        'phone': normalized,
        'dob': dob,
        'newPin': newPin,
      });
      final data = Map<String, dynamic>.from(result.data as Map);

      await _auth.signInWithCustomToken(data['customToken'] as String);

      final resolvedCompanyId = data['companyId'] as String;
      await CompanyStore.instance.activateCompany(resolvedCompanyId);

      final farmerName = data['farmerName'] as String? ?? '';
      final profile = {
        'ownerName': data['ownerName'] ?? '',
        'companyName': data['companyName'] ?? '',
      };

      await _finalizeSession(
        companyId: resolvedCompanyId,
        role: 'Company Farmer',
        displayName: farmerName,
        profile: profile,
        phoneOverride: normalized,
      );

      return AuthResult.ok(
        companyId: resolvedCompanyId,
        role: 'Company Farmer',
        displayName: farmerName,
        ownerName: profile['ownerName'] as String? ?? '',
        companyName: profile['companyName'] as String? ?? '',
      );
    } on FirebaseFunctionsException catch (e) {
      return AuthResult.fail(e.message ?? 'PIN reset nahi ho paaya.');
    } catch (e) {
      debugPrint('[resetFarmerPinWithDob] failed: $e');
      return AuthResult.fail('PIN reset nahi ho paaya: ${e.toString()}');
    }
  }

  /// FALLBACK ONLY — agar farmer apni DOB bhi bhool jaye ya galat KYC
  /// data record ho gaya ho, tab Office Manager/Owner (farmer_profile
  /// screen mein "Reset Farmer PIN" button se) ye emergency-override use
  /// kar sakte hain — bas PIN clear karega, farmer agli baar phir DOB se
  /// khud naya PIN bana lega. Ye call hamesha Owner/Manager ke already
  /// signed-in session se hota hai, isliye seedha Firestore read/write
  /// yahan sahi hai (Security Rules pass ho jaati hain).
  Future<void> resetCompanyFarmerPin({
    required String companyId,
    required String phone,
  }) async {
    final normalized = _normalizePhone(phone);
    await CompanyStore.instance.activateCompany(companyId);
    final farmers = await CompanyStore.instance.getJsonList('companyFarmers');
    final idx = farmers.indexWhere((f) => f['phone'] == normalized);
    if (idx == -1) return;
    farmers[idx].remove('loginPinHash');
    await CompanyStore.instance.saveJsonList('companyFarmers', farmers);
  }

  /// Manager add karte waqt Firebase account (alag phone par login).
  Future<void> createStaffAuthAccount({
    required String phone,
    required String password,
    required String name,
    required String role,
  }) async {
    if (!FirebaseBootstrap.isReady) return;

    final companyId = await SessionService.companyId;
    if (companyId == null) return;

    final email = CompanyStore.syntheticEmail(
      companyId: companyId,
      phone: phone,
    );

    try {
      final secondary = await _getSecondaryAuth();
      final cred = await secondary.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final staffUid = cred.user!.uid;
      await secondary.signOut();

      await CompanyStore.instance.registerPhoneLookup(
        phone: phone,
        companyId: companyId,
        role: role,
        authEmail: email,
        displayName: name,
      );

      await CompanyStore.instance.registerStaffMembership(
        companyId: companyId,
        staffUid: staffUid,
        phone: phone,
        role: role,
        displayName: name,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        await CompanyStore.instance.registerPhoneLookup(
          phone: phone,
          companyId: companyId,
          role: role,
          authEmail: email,
          displayName: name,
        );
      } else {
        debugPrint('[AuthService] staff account create failed: ${e.code}');
      }
    }
  }

  // ⬇️ YEH HAI UPDATED signOut FUNCTION ⬇️
  Future<void> signOut() async {
    // 1. Firebase se logout
    if (FirebaseBootstrap.isReady) {
      await _auth.signOut();
    }

    // 2. Session Service se logout
    await SessionService.logout();

    // 3. YEH HAI MASTER STROKE (Auto Clear Data)
    // Jaise hi user logout karega, app ki saari local memory khud saaf ho jayegi
    final prefs = await SharedPreferences.getInstance();
    await prefs
        .clear(); // Is line se user ko kabhi phone ki setting me nahi jana padega

    // 4. Memory se purani company ka connection hata do
    CompanyStore.instance.stopRealtimeListeners();
  }
  // ⬆️ UPDATED SIGN OUT ENDS ⬆️

  Future<void> _finalizeSession({
    required String companyId,
    required String role,
    required String displayName,
    required Map<String, dynamic> profile,
    String? phoneOverride, // ✅ NEW
  }) async {
    final uid = _auth.currentUser?.uid;
    final effectivePhone = phoneOverride ?? (profile['phone'] as String? ?? '');

    if (uid != null && FirebaseBootstrap.isReady) {
      await CompanyStore.instance.linkAuthUser(
        authUid: uid,
        companyId: companyId,
        role: role,
        phone: effectivePhone, // ✅ badla
        displayName: displayName,
      );
    }

    await SessionService.saveLoginSession(
      companyId: companyId,
      role: role,
      displayName: displayName,
      ownerName: profile['ownerName'] as String? ?? displayName,
      companyName: profile['companyName'] as String? ?? '',
      phone: effectivePhone, // ✅ badla
      industry: profile['industry'] as String? ?? 'poultry',
      authEmail: profile['authEmail'] as String?,
    );
  }

  Future<Map<String, dynamic>> _loadCompanyProfile(String companyId) async {
    if (!FirebaseBootstrap.isReady) {
      return {
        'ownerName': await SessionService.ownerName ?? '',
        'companyName': await SessionService.companyName ?? '',
        'phone': await SessionService.phone ?? '',
        'industry': await SessionService.industry ?? 'poultry',
      };
    }
    final snap = await FirebaseFirestore.instance
        .collection('companies')
        .doc(companyId)
        .get();
    return snap.data() ?? {};
  }

  Future<bool> _verifyManagerPassword({
    required String companyId,
    required String phone,
    required String password,
    required String role,
  }) async {
    final key = role == 'Office Manager' ? 'officeManagers' : 'fieldManagers';
    final list = await CompanyStore.instance.getJsonList(key);
    for (final m in list) {
      if (m['phone'] == phone && m['password'] == password) return true;
    }
    return false;
  }

  // 🛑 FIX — pehle ye bhi global `lookupPhone()` (phone_lookup collection)
  // call karta tha — lekin farmers jaan-boojh kar us collection mein kabhi
  // likhe hi nahi jate (taaki unka number kisi Owner/Manager ka phone_lookup
  // overwrite na kar sake). Isliye ye function farmer ke liye hamesha null
  // return karta tha, chahe farmer sahi se add kiya gaya ho — Company
  // Farmer login kabhi kaam hi nahi kar raha tha. Ab `lookupFarmerCompany()`
  // call karta hai, jo saari companies ke `farmerPhoneIndex` mein secure
  // collection-group search karta hai (Cloud Function ke through).
  Future<String?> _findCompanyIdForFarmerPhone(String phone) async {
    final lookup = await CompanyStore.instance.lookupFarmerCompany(phone);
    return lookup?['companyId'] as String?;
  }

  Future<AuthResult> _registerCompanyLocalOnly({
    required String email,
    required String password,
    required String ownerName,
    required String companyName,
    required String phone,
    required String industry,
  }) async {
    const localId = 'local_company';
    await SessionService.saveLoginSession(
      companyId: localId,
      role: 'Owner',
      displayName: ownerName,
      ownerName: ownerName,
      companyName: companyName,
      phone: phone,
      industry: industry,
      authEmail: email,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('password', password);
    await prefs.setString('email', email);
    await CompanyStore.instance.activateCompany(localId);
    return AuthResult.ok(
      companyId: localId,
      role: 'Owner',
      displayName: ownerName,
      ownerName: ownerName,
      companyName: companyName,
    );
  }

  Future<AuthResult> _loginLocalOnly({
    required String phone,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final ownerPhone = prefs.getString('phone') ?? '';
    final ownerPassword = prefs.getString('password') ?? '';
    final ownerName = prefs.getString('ownerName') ?? '';
    final companyName = prefs.getString('companyName') ?? '';

    if (phone == ownerPhone && password == ownerPassword) {
      final cid = prefs.getString('companyId') ?? 'local_company';
      await SessionService.saveLoginSession(
        companyId: cid,
        role: 'Owner',
        displayName: ownerName,
        ownerName: ownerName,
        companyName: companyName,
        phone: phone,
        industry: prefs.getString('industry') ?? 'poultry',
      );
      await CompanyStore.instance.activateCompany(cid);
      return AuthResult.ok(
        companyId: cid,
        role: 'Owner',
        displayName: ownerName,
        ownerName: ownerName,
        companyName: companyName,
      );
    }

    for (final key in ['officeManagers', 'fieldManagers']) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      final list = List<Map<String, dynamic>>.from(json.decode(raw) as List);
      for (final m in list) {
        if (m['phone'] == phone && m['password'] == password) {
          final role = key == 'officeManagers'
              ? 'Office Manager'
              : 'Field Manager';
          final cid = prefs.getString('companyId') ?? 'local_company';
          await SessionService.saveLoginSession(
            companyId: cid,
            role: role,
            displayName: m['name'] as String? ?? '',
            ownerName: ownerName,
            companyName: companyName,
            phone: phone,
            industry: prefs.getString('industry') ?? 'poultry',
          );
          await CompanyStore.instance.activateCompany(cid);
          return AuthResult.ok(
            companyId: cid,
            role: role,
            displayName: m['name'] as String? ?? '',
            ownerName: ownerName,
            companyName: companyName,
          );
        }
      }
    }

    return AuthResult.fail('Phone ya password galat hai');
  }

  Future<FirebaseAuth> _getSecondaryAuth() async {
    try {
      final existing = Firebase.app('Secondary');
      return FirebaseAuth.instanceFor(app: existing);
    } catch (_) {
      final app = await Firebase.initializeApp(
        name: 'Secondary',
        options: Firebase.app().options,
      );
      return FirebaseAuth.instanceFor(app: app);
    }
  }

  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Yeh email pehle se register hai';
      case 'weak-password':
        return 'Password bahut weak hai — kam se kam 6 characters';
      case 'invalid-email':
        return 'Email format galat hai';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Phone ya password galat hai';
      case 'network-request-failed':
        return 'Internet connection check karo';
      default:
        return e.message ?? 'Authentication error (${e.code})';
    }
  }

  static String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) return digits.substring(digits.length - 10);
    return digits;
  }
}
