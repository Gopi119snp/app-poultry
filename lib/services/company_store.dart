import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_bootstrap.dart';
import 'session_service.dart';

/// Company ka saara operational data — local cache + Firestore sync.
///
/// Firestore layout:
///   companies/{companyId}/profile        → owner/company metadata
///   companies/{companyId}/data/main      → farmers, stock, settings, history
///   phone_lookup/{10digitPhone}          → fast login routing
///   users/{firebaseAuthUid}              → auth uid → companyId + role
class CompanyStore {
  CompanyStore._();

  static final CompanyStore instance = CompanyStore._();

  static const _dataDocPath = 'data/main';

  /// String keys jo Firestore data/main document mein sync hote hain.
  static const stringKeys = {
    'companyFarmers',
    'officeManagers',
    'fieldManagers',
    'feedStockMap',
    'medicineStockList',
    'feedPurchaseHistory',
    'labourExpenseHistory',
    'otherExpenseHistory',
    'rule1SettlementConfig',
    'rule2SettlementConfig',
    'feedConsumptionRuleConfig',
    'weightGrowthRuleConfig',
    'runningCostConfig',
    'performanceAlertConfig',
    'personalFarmers',
    'password', // legacy owner password — Firebase Auth primary hai
  };

  static const intKeys = {
    'minLiftingDays',
    'maxLiftingDays',
    'appliedCompanyRuleId',
  };

  bool _hydrated = false;
  String? _activeCompanyId;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _companies =>
      _db.collection('companies');

  CollectionReference<Map<String, dynamic>> get _phoneLookup =>
      _db.collection('phone_lookup');

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  DocumentReference<Map<String, dynamic>> _companyRef(String companyId) =>
      _companies.doc(companyId);

  DocumentReference<Map<String, dynamic>> _dataRef(String companyId) =>
      _companyRef(companyId).collection('data').doc('main');

  // ── PUBLIC API ────────────────────────────────────────────────────────────

  Future<void> activateCompany(String companyId) async {
    _activeCompanyId = companyId;
    _hydrated = false;
    await hydrateFromCloud(companyId);
  }

  Future<void> hydrateFromCloud(String companyId) async {
    _activeCompanyId = companyId;
    final prefs = await SharedPreferences.getInstance();

    if (!FirebaseBootstrap.isReady) {
      _hydrated = true;
      return;
    }

    try {
      final profileSnap = await _companyRef(companyId).get();
      if (profileSnap.exists) {
        final profile = profileSnap.data() ?? {};
        await _writeProfileToPrefs(prefs, profile);
      }

      final dataSnap = await _dataRef(companyId).get();
      if (dataSnap.exists) {
        final data = dataSnap.data() ?? {};
        await _writeDataDocToPrefs(prefs, data);
      }

      _hydrated = true;
      debugPrint('[CompanyStore] Hydrated company $companyId from Firestore.');
    } catch (e, st) {
      debugPrint('[CompanyStore] hydrate failed: $e\n$st');
      _hydrated = true; // local cache use karo
    }
  }

  /// Nayi company registration — empty data doc + profile.
  Future<void> createCompanyInCloud({
    required String companyId,
    required Map<String, dynamic> profile,
    Map<String, dynamic>? initialData,
  }) async {
    if (!FirebaseBootstrap.isReady) return;

    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();

    batch.set(_companyRef(companyId), {
      ...profile,
      'createdAt': now,
      'updatedAt': now,
    });

    batch.set(_dataRef(companyId), {
      ...(initialData ?? _defaultData()),
      'updatedAt': now,
    });

    final ownerPhone = _normalizePhone(profile['phone']?.toString() ?? '');
    if (ownerPhone.isNotEmpty) {
      batch.set(_phoneLookup.doc(ownerPhone), {
        'companyId': companyId,
        'role': 'Owner',
        'authEmail': profile['authEmail'],
        'updatedAt': now,
      });
    }

    await batch.commit();
    await activateCompany(companyId);
  }

  Future<void> registerPhoneLookup({
    required String phone,
    required String companyId,
    required String role,
    String? authEmail,
    String? displayName,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    final normalized = _normalizePhone(phone);
    if (normalized.isEmpty) return;

    await _phoneLookup.doc(normalized).set({
      'companyId': companyId,
      'role': role,
      if (authEmail != null) 'authEmail': authEmail,
      if (displayName != null) 'displayName': displayName,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> lookupPhone(String phone) async {
    if (!FirebaseBootstrap.isReady) return null;
    final normalized = _normalizePhone(phone);
    if (normalized.isEmpty) return null;
    final snap = await _phoneLookup.doc(normalized).get();
    return snap.data();
  }

  Future<void> linkAuthUser({
    required String authUid,
    required String companyId,
    required String role,
    required String phone,
    String? displayName,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    await _users.doc(authUid).set({
      'companyId': companyId,
      'role': role,
      'phone': _normalizePhone(phone),
      if (displayName != null) 'displayName': displayName,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateProfile(Map<String, dynamic> profile) async {
    final companyId = await SessionService.companyId;
    if (companyId == null) return;

    final prefs = await SharedPreferences.getInstance();
    await _writeProfileToPrefs(prefs, profile);

    if (!FirebaseBootstrap.isReady) return;
    await _companyRef(companyId).set({
      ...profile,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ── String getters/setters (SharedPreferences compatible) ───────────────────

  Future<String?> getString(String key) async {
    await _ensureHydrated();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> setString(String key, String value) async {
    await _ensureHydrated();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
    await _pushStringKeyToCloud(key, value);
  }

  Future<int?> getInt(String key) async {
    await _ensureHydrated();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key);
  }

  Future<void> setInt(String key, int value) async {
    await _ensureHydrated();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
    await _pushIntKeyToCloud(key, value);
  }

  /// Poora data document ek saath cloud par save (batch operations ke baad).
  Future<void> syncAllToCloud() async {
    final companyId = _activeCompanyId ?? await SessionService.companyId;
    if (companyId == null || !FirebaseBootstrap.isReady) return;

    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    for (final key in stringKeys) {
      final v = prefs.getString(key);
      if (v != null) payload[key] = v;
    }
    for (final key in intKeys) {
      final v = prefs.getInt(key);
      if (v != null) payload[key] = v;
    }

    await _dataRef(companyId).set(payload, SetOptions(merge: true));
  }

  Future<void> deleteCompanyFromCloud(String companyId) async {
    if (!FirebaseBootstrap.isReady) return;
    // Note: subcollections need recursive delete in production (Cloud Function).
    await _dataRef(companyId).delete();
    await _companyRef(companyId).delete();
  }

  // ── Helpers for JSON lists ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getJsonList(String key) async {
    final raw = await getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<Map<String, dynamic>>.from(json.decode(raw));
    } catch (_) {
      return [];
    }
  }

  Future<void> saveJsonList(String key, List<Map<String, dynamic>> list) async {
    await setString(key, json.encode(list));
  }

  Future<Map<String, double>> getFeedStockMap() async {
    final raw = await getString('feedStockMap');
    if (raw == null) {
      return {'Starter': 0.0, 'Grower': 0.0, 'Finisher': 0.0};
    }
    try {
      final decoded = Map<String, dynamic>.from(json.decode(raw));
      return decoded.map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      );
    } catch (_) {
      return {'Starter': 0.0, 'Grower': 0.0, 'Finisher': 0.0};
    }
  }

  Future<void> saveFeedStockMap(Map<String, double> map) async {
    await setString('feedStockMap', json.encode(map));
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Future<void> _ensureHydrated() async {
    if (_hydrated) return;
    final companyId = await SessionService.companyId;
    if (companyId != null) {
      await hydrateFromCloud(companyId);
    } else {
      _hydrated = true;
    }
  }

  Map<String, dynamic> _defaultData() => {
        'companyFarmers': '[]',
        'officeManagers': '[]',
        'fieldManagers': '[]',
        'feedStockMap': json.encode({
          'Starter': 0.0,
          'Grower': 0.0,
          'Finisher': 0.0,
        }),
        'medicineStockList': '[]',
        'feedPurchaseHistory': '[]',
        'labourExpenseHistory': '[]',
        'otherExpenseHistory': '[]',
        'minLiftingDays': 23,
        'maxLiftingDays': 60,
        'appliedCompanyRuleId': 1,
      };

  Future<void> _writeProfileToPrefs(
    SharedPreferences prefs,
    Map<String, dynamic> profile,
  ) async {
    for (final entry in profile.entries) {
      final k = entry.key;
      if (entry.value == null) continue;
      if (k == 'createdAt' || k == 'updatedAt') continue;
      if (entry.value is String) {
        await prefs.setString(k, entry.value as String);
      } else if (entry.value is int) {
        await prefs.setInt(k, entry.value as int);
      } else if (entry.value is bool) {
        await prefs.setBool(k, entry.value as bool);
      }
    }
  }

  Future<void> _writeDataDocToPrefs(
    SharedPreferences prefs,
    Map<String, dynamic> data,
  ) async {
    for (final key in stringKeys) {
      if (data.containsKey(key) && data[key] is String) {
        await prefs.setString(key, data[key] as String);
      }
    }
    for (final key in intKeys) {
      if (data.containsKey(key) && data[key] is int) {
        await prefs.setInt(key, data[key] as int);
      } else if (data.containsKey(key) && data[key] is num) {
        await prefs.setInt(key, (data[key] as num).toInt());
      }
    }
  }

  Future<void> _pushStringKeyToCloud(String key, String value) async {
    if (!stringKeys.contains(key)) return;
    final companyId = _activeCompanyId ?? await SessionService.companyId;
    if (companyId == null || !FirebaseBootstrap.isReady) return;

    await _dataRef(companyId).set({
      key: value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _pushIntKeyToCloud(String key, int value) async {
    if (!intKeys.contains(key)) return;
    final companyId = _activeCompanyId ?? await SessionService.companyId;
    if (companyId == null || !FirebaseBootstrap.isReady) return;

    await _dataRef(companyId).set({
      key: value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) return digits.substring(digits.length - 10);
    return digits;
  }

  /// Manager / farmer ke liye synthetic Firebase email.
  static String syntheticEmail({
    required String companyId,
    required String phone,
  }) {
    final p = _normalizePhone(phone);
    return '$companyId.$p@poultrypro.app'.toLowerCase();
  }
}
