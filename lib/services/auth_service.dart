import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  }) =>
      AuthResult(
        success: true,
        companyId: companyId,
        role: role,
        displayName: displayName,
        ownerName: ownerName,
        companyName: companyName,
      );
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

    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      final uid = cred.user!.uid;
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

            final displayName = lookup['displayName'] as String? ??
                profile['ownerName'] as String? ??
                '';

            await _finalizeSession(
              companyId: companyId,
              role: role,
              displayName: displayName,
              profile: profile,
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
        final farmers =
            await CompanyStore.instance.getJsonList('companyFarmers');
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
      await secondary.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await secondary.signOut();

      await CompanyStore.instance.registerPhoneLookup(
        phone: phone,
        companyId: companyId,
        role: role,
        authEmail: email,
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

  Future<void> signOut() async {
    if (FirebaseBootstrap.isReady) {
      await _auth.signOut();
    }
    await SessionService.logout();
  }

  Future<void> _finalizeSession({
    required String companyId,
    required String role,
    required String displayName,
    required Map<String, dynamic> profile,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid != null && FirebaseBootstrap.isReady) {
      await CompanyStore.instance.linkAuthUser(
        authUid: uid,
        companyId: companyId,
        role: role,
        phone: profile['phone'] as String? ?? '',
        displayName: displayName,
      );
    }

    await SessionService.saveLoginSession(
      companyId: companyId,
      role: role,
      displayName: displayName,
      ownerName: profile['ownerName'] as String? ?? displayName,
      companyName: profile['companyName'] as String? ?? '',
      phone: profile['phone'] as String? ?? '',
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

  Future<String?> _findCompanyIdForFarmerPhone(String phone) async {
    final lookup = await CompanyStore.instance.lookupPhone(phone);
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
      final list =
          List<Map<String, dynamic>>.from(json.decode(raw) as List);
      for (final m in list) {
        if (m['phone'] == phone && m['password'] == password) {
          final role =
              key == 'officeManagers' ? 'Office Manager' : 'Field Manager';
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
