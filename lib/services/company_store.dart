import 'dart:async'; // ✅ FIX — naya import, StreamController ke liye
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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
  // ✅ FIX — real-time change notification stream. Jab bhi cloud se naya
  // data aaye (kisi bhi device se), ye event fire karega taaki saari open
  // screens turant apna data refresh kar sakein.
  final StreamController<void> _changeController =
      StreamController<void>.broadcast();
  Stream<void> get onDataChanged => _changeController.stream;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _dataSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

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

    // ✅ MISSING KEYS ADDED HERE
    'chicksPurchaseHistory',
    'globalActivityLogs', // Recent Activity
    'medicinePurchaseHistory',
    'chickSalesHistory', // Sales Data
    'feedSalesHistory',
    'medicineSalesHistory',
    'chickenLiftingSaleHistory',
    'salesHistory', // Common sales key
    // ========================
    'rule1SettlementConfig',
    'rule2SettlementConfig',
    'feedConsumptionRuleConfig',
    'weightGrowthRuleConfig',
    'runningCostConfig',
    'performanceAlertConfig',
    'personalFarmers',
    'password', // legacy owner password — Firebase Auth primary hai
    'ownerSignature', // Owner ka signature — base64 encoded image string
    'customRoles', // Owner ke banaye custom role names (Office/Field Manager se alag)
    'rolePermissions', // Har role ke module-wise View/Add/Edit/Delete permissions
    'personPermissions', // Har individual staff member (name+phone) ka custom permission override
    'farmerAllocationMode', // ✅ NEW — single ya multiple allocation mode
    'staffPerformanceBenchmarkConfig', // ✅ NEW — Staff Performance ke Good/Average/Poor numbers
    'subscriptionStatus', // 'trial' | 'active' | 'expired'
    'trialExpiry', // ISO8601 string — company banne ke 7 din baad
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

  // ✅ FIX — pehle yahan is method ka ek purana duplicate version bhi tha
  // (bina _startRealtimeListeners call ke). Wo duplicate hata diya gaya hai,
  // ab sirf ye ek hi (updated) version hai jo realtime listener bhi start karta hai.
  Future<void> activateCompany(String companyId) async {
    _activeCompanyId = companyId;
    _hydrated = false;
    await hydrateFromCloud(companyId);
    _startRealtimeListeners(companyId); // ✅ FIX
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
      _startRealtimeListeners(companyId); // ✅ FIX — pehli baar hydrate
      // hote hi bhi listener start ho jaye
      debugPrint('[CompanyStore] Hydrated company $companyId from Firestore.');
    } catch (e, st) {
      debugPrint('[CompanyStore] hydrate failed: $e\n$st');
      _hydrated = true; // local cache use karo
    }
  }

  // ✅ FIX — naya method: Firestore ka real-time listener. Jab bhi is
  // company ka data/main document kahi se bhi update hota hai, Firestore
  // khud turant is listener ko naya snapshot bhej deta hai.
  void _startRealtimeListeners(String companyId) {
    if (!FirebaseBootstrap.isReady) return;

    _dataSub?.cancel();
    _profileSub?.cancel();

    _dataSub = _dataRef(companyId).snapshots().listen(
      (snap) async {
        if (!snap.exists) return;
        final data = snap.data() ?? {};
        final prefs = await SharedPreferences.getInstance();
        await _writeDataDocToPrefs(prefs, data);
        _changeController.add(null);
      },
      onError: (e) {
        debugPrint('[CompanyStore] realtime data listener error: $e');
      },
    );

    _profileSub = _companyRef(companyId).snapshots().listen(
      (snap) async {
        if (!snap.exists) return;
        final profile = snap.data() ?? {};
        final prefs = await SharedPreferences.getInstance();
        await _writeProfileToPrefs(prefs, profile);
        _changeController.add(null);
      },
      onError: (e) {
        debugPrint('[CompanyStore] realtime profile listener error: $e');
      },
    );
  }

  // ✅ FIX — logout/company-switch ke waqt listener band karo
  void stopRealtimeListeners() {
    _dataSub?.cancel();
    _profileSub?.cancel();
    _dataSub = null;
    _profileSub = null;
    _hydrated = false;
    _activeCompanyId = null;
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

  /// ✅ Per-company farmer phone index — collection-group query ke liye.
  /// Global registerPhoneLookup() ki tarah overwrite nahi karta, kyunki
  /// har company apna alag doc rakhti hai: companies/{companyId}/farmerPhoneIndex/{phone}
  Future<void> registerFarmerPhoneIndex({
    required String companyId,
    required String phone,
    required String farmerId,
    required String farmerName,
    required String companyName,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    final normalized = _normalizePhone(phone);
    if (normalized.isEmpty) return;

    await _companyRef(
      companyId,
    ).collection('farmerPhoneIndex').doc(normalized).set({
      'farmerId': farmerId,
      'farmerName': farmerName,
      'companyId': companyId,
      'companyName': companyName,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> registerStaffMembership({
    required String companyId,
    required String staffUid,
    required String phone,
    required String role,
    required String displayName,
  }) async {
    await _db
        .collection('companies')
        .doc(companyId)
        .collection('staff')
        .doc(staffUid)
        .set({
          'phone': phone,
          'role': role,
          'displayName': displayName,
          'createdAt': FieldValue.serverTimestamp(),
        });
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
      return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
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
    // ✅ NEW — har naye company ke liye 7-din ka free trial shuru
    'subscriptionStatus': 'trial',
    'trialExpiry': DateTime.now()
        .add(const Duration(days: 7))
        .toIso8601String(),
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

// ✅ FIX — Reusable mixin: koi bhi State class jo real-time cloud sync
// chahti hai, wo baar-baar StreamSubscription boilerplate likhne ke bajaye
// sirf ye mixin use kare aur "onCloudDataChanged()" override kare.
mixin CloudSyncMixin<T extends StatefulWidget> on State<T> {
  StreamSubscription<void>? _cloudSyncSub;

  void onCloudDataChanged();

  void startCloudSync() {
    _cloudSyncSub = CompanyStore.instance.onDataChanged.listen((_) {
      if (mounted) onCloudDataChanged();
    });
  }

  void stopCloudSync() {
    _cloudSyncSub?.cancel();
  }
}
