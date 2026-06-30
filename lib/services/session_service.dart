import 'package:shared_preferences/shared_preferences.dart';

/// Sirf device session — cloud data CompanyStore se aata hai.
class SessionService {
  SessionService._();

  static const _kLoggedIn = 'isLoggedIn';
  static const _kCompanyId = 'companyId';
  static const _kCurrentRole = 'currentRole';
  static const _kCurrentName = 'currentName';
  static const _kOwnerName = 'ownerName';
  static const _kCompanyName = 'companyName';
  static const _kPhone = 'phone';
  static const _kIndustry = 'industry';
  static const _kAuthEmail = 'authEmail';

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  static Future<bool> get isLoggedIn async {
    final p = await _prefs;
    return p.getBool(_kLoggedIn) ?? false;
  }

  static Future<String?> get companyId async {
    final p = await _prefs;
    return p.getString(_kCompanyId);
  }

  static Future<String?> get currentRole async {
    final p = await _prefs;
    return p.getString(_kCurrentRole);
  }

  static Future<String?> get currentName async {
    final p = await _prefs;
    return p.getString(_kCurrentName);
  }

  static Future<String?> get ownerName async {
    final p = await _prefs;
    return p.getString(_kOwnerName);
  }

  static Future<String?> get companyName async {
    final p = await _prefs;
    return p.getString(_kCompanyName);
  }

  static Future<String?> get phone async {
    final p = await _prefs;
    return p.getString(_kPhone);
  }

  static Future<String?> get industry async {
    final p = await _prefs;
    return p.getString(_kIndustry);
  }

  static Future<String?> get authEmail async {
    final p = await _prefs;
    return p.getString(_kAuthEmail);
  }

  static Future<void> saveLoginSession({
    required String companyId,
    required String role,
    required String displayName,
    required String ownerName,
    required String companyName,
    required String phone,
    required String industry,
    String? authEmail,
  }) async {
    final p = await _prefs;
    await p.setBool(_kLoggedIn, true);
    await p.setString(_kCompanyId, companyId);
    await p.setString(_kCurrentRole, role);
    await p.setString(_kCurrentName, displayName);
    await p.setString(_kOwnerName, ownerName);
    await p.setString(_kCompanyName, companyName);
    await p.setString(_kPhone, phone);
    await p.setString(_kIndustry, industry);
    if (authEmail != null) {
      await p.setString(_kAuthEmail, authEmail);
    }
  }

  static Future<void> logout() async {
    final p = await _prefs;
    await p.setBool(_kLoggedIn, false);
    await p.remove(_kCurrentRole);
    await p.remove(_kCurrentName);
    await p.remove(_kAuthEmail);
  }

  static Future<void> clearAll() async {
    final p = await _prefs;
    await p.clear();
  }
}
