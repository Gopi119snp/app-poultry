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
  // ✅ NEW — Guest Preview Mode flag
  static const _kGuestMode = 'isGuestMode';

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  static Future<bool> get isLoggedIn async {
    final p = await _prefs;
    return p.getBool(_kLoggedIn) ?? false;
  }

  // ✅ NEW — Guest mode mein hai ya nahi
  static Future<bool> get isGuestMode async {
    final p = await _prefs;
    return p.getBool(_kGuestMode) ?? false;
  }

  static Future<String?> get companyId async {
    final p = await _prefs;
    return p.getString(_kCompanyId);
  }

  static Future<String?> get currentRole async {
    final p = await _prefs;
    return p.getString(_kCurrentRole);
  }

  static Future<bool> get isOwner async {
    final role = await currentRole;
    if (role == null) return false;
    return role.trim().toLowerCase() == 'owner';
  }

  static Future<String?> get normalizedRole async {
    final role = await currentRole;
    if (role == null) return null;
    final trimmed = role.trim();
    return trimmed.isEmpty ? null : trimmed;
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

  // ✅ NEW — Guest Preview Mode shuru karne ke liye.
  // Purana kisi bhi user ka leftover local data pehle poora clear karta hai
  // (taaki galti se real business data guest ko na dikh jaye), fir guest
  // flag set karta hai. Demo data seed karna DemoDataService ka kaam hai —
  // isko caller (Welcome Screen) alag se call karega.
  static Future<void> enterGuestMode() async {
    final p = await _prefs;
    await p
        .clear(); // ✅ Purana leftover data (agar koi real login pehle hua ho) safaya
    await p.setBool(_kLoggedIn, false);
    await p.setBool(_kGuestMode, true);
    await p.setString(_kCurrentRole, 'Guest');
    await p.setString(_kCurrentName, 'Guest User');
    await p.setString(_kCompanyName, 'Demo Company');
    await p.setString(_kOwnerName, 'Guest User');
  }

  // ✅ NEW — Guest mode se bahar nikal ke Welcome screen pe jaana
  static Future<void> exitGuestMode() async {
    final p = await _prefs;
    await p.clear();
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
    await p.setBool(
      _kGuestMode,
      false,
    ); // ✅ NEW — real login hote hi guest flag hata do
    await p.setString(_kCompanyId, companyId);
    await p.setString(_kCurrentRole, role.trim());
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
    await p.setBool(_kGuestMode, false); // ✅ NEW
    await p.remove(_kCurrentRole);
    await p.remove(_kCurrentName);
    await p.remove(_kAuthEmail);
  }

  static Future<void> clearAll() async {
    final p = await _prefs;
    await p.clear();
  }
}
