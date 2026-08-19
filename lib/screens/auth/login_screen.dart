import 'package:flutter/material.dart';
import 'dart:async';
import 'package:get/get.dart';
import '../home/home_screen.dart';
import '../dashboards/farmer_dashboard.dart';
import '../../services/auth_service.dart';
import '../../services/company_store.dart';
import '../../services/otp_service.dart';
import '../../services/app_lock_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);

  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _farmerPhoneController = TextEditingController();
  final _farmerPinController = TextEditingController();
  final _farmerPinConfirmController = TextEditingController();
  final _farmerDobController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmNewPasswordController = TextEditingController();
  final _forgotPhoneController = TextEditingController();
  final _forgotOtpController = TextEditingController();
  final _forgotNewPassController = TextEditingController();
  final _forgotConfirmPassController = TextEditingController();

  bool _showPassword = false;
  bool _isLoading = false;
  int _forgotResendCooldown = 0;
  Timer? _forgotResendTimer;
  void Function(void Function())? _forgotDialogSetState;

  // OTP Login state (Company Farmer)
  bool _farmerPhoneChecked = false;
  bool _farmerHasPin = false;
  bool _farmerForgotPin = false;
  String? _farmerCompanyId;
  bool _otpVerified = false;
  bool _showNewPassFields = false;

  // Forgot Password state
  bool _forgotOtpSent = false;
  bool _forgotOtpVerified = false;
  bool _showForgotNewPass = false;
  bool _showForgotNewPassword = false;
  bool _showForgotConfirmPassword = false;
  String? _forgotResolvedEmail;
  String? _forgotResetToken;

  // Current tab: 0 = Password Login, 1 = OTP Login (Company Farmer)
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _farmerDobController.addListener(_formatDob);
  }

  void _formatDob() {
    String digits = _farmerDobController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 8) digits = digits.substring(0, 8);
    String formatted = '';
    for (int i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) formatted += '/';
      formatted += digits[i];
    }
    if (formatted != _farmerDobController.text) {
      _farmerDobController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  @override
  void dispose() {
    _farmerDobController.removeListener(_formatDob);
    _forgotResendTimer?.cancel();
    _phoneController.dispose();
    _passwordController.dispose();
    _farmerPhoneController.dispose();
    _farmerPinController.dispose();
    _farmerPinConfirmController.dispose();
    _farmerDobController.dispose();
    _newPasswordController.dispose();
    _confirmNewPasswordController.dispose();
    _forgotPhoneController.dispose();
    _forgotOtpController.dispose();
    _forgotNewPassController.dispose();
    _forgotConfirmPassController.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------
  // PASSWORD LOGIN — Owner / Manager / Personal Farmer
  // ----------------------------------------------------------------
  Future<void> _login() async {
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;

    if (phone.isEmpty || password.isEmpty) {
      _showError('Phone aur password dono daalo');
      return;
    }
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
      _showError('Sahi phone number daalo — 10 digit');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await AuthService.instance.loginWithPhonePassword(
        phone: phone,
        password: password,
      );

      setState(() => _isLoading = false);

      if (!result.success) {
        _showError(result.errorMessage ?? 'Login fail');
        return;
      }

      Get.snackbar(
        '✅ Welcome!',
        'Namaste, ${result.displayName}! 👋',
        backgroundColor: primaryGreen,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      await Future.delayed(const Duration(milliseconds: 800));

      await AppLockService.instance.routeAfterAuth(
        HomeScreen(
          ownerName: result.displayName ?? result.ownerName ?? '',
          companyName: result.companyName ?? '',
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Server Error: ${e.toString()}');
    }
  }

  // ----------------------------------------------------------------
  // COMPANY FARMER LOGIN — Number Match + PIN (zero-cost, no OTP/SMS)
  // ----------------------------------------------------------------
  Future<void> _checkFarmerPhone() async {
    final phone = _farmerPhoneController.text.trim();
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
      _showError('Sahi phone number daalo — 10 digit');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final check = await AuthService.instance.checkCompanyFarmerPhone(phone);
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (!check.exists) {
        _showError('Yeh number register nahi hai. Owner se contact karo.');
        return;
      }

      setState(() {
        _farmerPhoneChecked = true;
        _farmerHasPin = check.hasPin;
        _farmerCompanyId = check.companyId;
        _farmerForgotPin = false;
        _farmerDobController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Error checking farmer: ${e.toString()}');
    }
  }

  // Updated _submitFarmerPin with DOB validation and passing dob for new PIN setup
  Future<void> _submitFarmerPin() async {
    final pin = _farmerPinController.text.trim();
    if (pin.length != 4) {
      _showError('4 digit PIN daalo');
      return;
    }

    if (!_farmerHasPin) {
      final confirm = _farmerPinConfirmController.text.trim();
      if (pin != confirm) {
        _showError('PIN match nahi kar raha');
        return;
      }
      final dob = _farmerDobController.text.trim();
      if (dob.isEmpty) {
        _showError('Apni Date of Birth daalo (jo Office Manager ko di thi)');
        return;
      }
    }

    if (_farmerCompanyId == null) {
      _showError('Kuch galat ho gaya — dobara try karo');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = _farmerHasPin
          ? await AuthService.instance.loginCompanyFarmerWithPin(
              companyId: _farmerCompanyId!,
              phone: _farmerPhoneController.text.trim(),
              pin: pin,
            )
          : await AuthService.instance.setupCompanyFarmerPin(
              companyId: _farmerCompanyId!,
              phone: _farmerPhoneController.text.trim(),
              dob: _farmerDobController.text.trim(),
              pin: pin,
            );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (!result.success) {
        _showError(result.errorMessage ?? 'Login fail');
        return;
      }

      Get.snackbar(
        '✅ Welcome!',
        'Namaste, ${result.displayName}! 👋',
        backgroundColor: primaryGreen,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      await Future.delayed(const Duration(milliseconds: 800));
      await AppLockService.instance.routeAfterAuth(
        FarmerDashboard(
          ownerName: result.displayName ?? '',
          companyName: result.companyName ?? '',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Kuch galat ho gaya: ${e.toString()}');
    }
  }

  /// ✅ Self-service PIN reset — FARMER khud karta hai, DOB confirm
  /// karke (jo Office Manager ko onboarding ke time di thi). Koi
  /// Office Manager/Owner involvement nahi chahiye.
  Future<void> _submitFarmerPinReset() async {
    final dob = _farmerDobController.text.trim();
    final pin = _farmerPinController.text.trim();
    final confirm = _farmerPinConfirmController.text.trim();

    if (dob.isEmpty) {
      _showError('Apni Date of Birth daalo (jo Office Manager ko di thi)');
      return;
    }
    if (pin.length != 4) {
      _showError('4 digit naya PIN daalo');
      return;
    }
    if (pin != confirm) {
      _showError('PIN match nahi kar raha');
      return;
    }
    if (_farmerCompanyId == null) {
      _showError('Kuch galat ho gaya — dobara try karo');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await AuthService.instance.resetFarmerPinWithDob(
        companyId: _farmerCompanyId!,
        phone: _farmerPhoneController.text.trim(),
        dob: dob,
        newPin: pin,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (!result.success) {
        _showError(result.errorMessage ?? 'Reset fail ho gaya');
        return;
      }

      Get.snackbar(
        '✅ PIN Reset Ho Gaya!',
        'Naye PIN se login ho gaya',
        backgroundColor: primaryGreen,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      await Future.delayed(const Duration(milliseconds: 800));
      await AppLockService.instance.routeAfterAuth(
        FarmerDashboard(
          ownerName: result.displayName ?? '',
          companyName: result.companyName ?? '',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Kuch galat ho gaya: ${e.toString()}');
    }
  }

  // ----------------------------------------------------------------
  // FORGOT PASSWORD — Owner / Personal Farmer only (REAL OTP + Cloud Function)
  // ----------------------------------------------------------------
  Future<void> _sendForgotOtp() async {
    final phone = _forgotPhoneController.text.trim();
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
      _showError('Sahi phone number daalo');
      return;
    }

    try {
      final lookup = await CompanyStore.instance.lookupPhone(phone);
      final role = lookup?['role'] as String?;

      if (role != 'Owner' && role != 'Personal Farmer') {
        _showError(
          'Yeh number Owner ya Personal Farmer ka nahi hai.\nManager ka password Owner ke paas hota hai — unse puchein.',
        );
        return;
      }

      // Owner/Personal Farmer ka authEmail chahiye — usi par OTP jayega.
      final authEmail = lookup?['authEmail'] as String?;
      if (authEmail == null || authEmail.isEmpty) {
        _showError('Is account ka email record nahi mila.');
        return;
      }
      _forgotResolvedEmail = authEmail;

      if (!mounted) return;
      setState(() => _isLoading = true);

      final error = await OtpService.instance.sendEmailOtp(authEmail);

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (error != null) {
        _showError(error);
        return;
      }

      setState(() => _forgotOtpSent = true);
      _startForgotResendCooldown();
      Get.snackbar(
        'OTP Bheja Gaya!',
        'Aapke registered email par OTP bheja gaya',
        backgroundColor: primaryGreen,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Error sending OTP: ${e.toString()}');
    }
  }

  // ✅ Resend OTP — 30-second cooldown.
  void _startForgotResendCooldown() {
    _forgotResendTimer?.cancel();
    setState(() => _forgotResendCooldown = 30);
    _forgotDialogSetState?.call(() {});
    _forgotResendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_forgotResendCooldown <= 1) {
        timer.cancel();
        setState(() => _forgotResendCooldown = 0);
      } else {
        setState(() => _forgotResendCooldown--);
      }
      _forgotDialogSetState?.call(() {});
    });
  }

  Future<void> _resendForgotOtp() async {
    if (_forgotResendCooldown > 0 || _forgotResolvedEmail == null) return;
    final error = await OtpService.instance.sendEmailOtp(_forgotResolvedEmail!);
    if (!mounted) return;
    if (error != null) {
      _showError('Resend fail: $error');
      return;
    }
    _startForgotResendCooldown();
    Get.snackbar(
      'Naya OTP Bheja Gaya!',
      'Email check karo',
      backgroundColor: primaryGreen,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(15),
    );
  }

  Future<void> _verifyForgotOtp() async {
    if (_forgotOtpController.text.length != 6) {
      _showError('6 digit OTP daalo');
      return;
    }
    if (_forgotResolvedEmail == null) {
      _showError('Session expire ho gaya — dobara try karo');
      return;
    }

    final resetToken = await OtpService.instance.verifyEmailOtpForReset(
      _forgotResolvedEmail!,
      _forgotOtpController.text.trim(),
    );

    if (resetToken == null) {
      _showError('OTP galat ya expire ho gaya');
      return;
    }

    _forgotResetToken = resetToken;

    if (!mounted) return;
    setState(() {
      _forgotOtpVerified = true;
      _showForgotNewPass = true;
    });
    Get.snackbar(
      '✅ Verified!',
      'Ab naya password set karo',
      backgroundColor: primaryGreen,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(15),
    );
  }

  Future<void> _setNewPassword() async {
    if (_forgotNewPassController.text.length < 6) {
      _showError('Password kam se kam 6 characters ka hona chahiye');
      return;
    }
    if (_forgotNewPassController.text != _forgotConfirmPassController.text) {
      _showError('Password match nahi kar raha');
      return;
    }
    if (_forgotResolvedEmail == null || _forgotResetToken == null) {
      _showError('Session expire ho gaya — dobara OTP verify karo');
      return;
    }

    try {
      // Server-side Cloud Function — email OTP se mile resetToken ke saath
      final error = await OtpService.instance.resetPasswordAfterOtp(
        email: _forgotResolvedEmail!,
        resetToken: _forgotResetToken!,
        newPassword: _forgotNewPassController.text,
      );

      if (error != null) {
        _showError(error);
        return;
      }

      Get.snackbar(
        '✅ Password Updated!',
        'Naya password set ho gaya. Ab login karo.',
        backgroundColor: primaryGreen,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );

      // Reset forgot password state
      setState(() {
        _forgotOtpSent = false;
        _forgotOtpVerified = false;
        _showForgotNewPass = false;
        _forgotResolvedEmail = null;
        _forgotResetToken = null;
        _forgotPhoneController.clear();
        _forgotOtpController.clear();
        _forgotNewPassController.clear();
        _forgotConfirmPassController.clear();
      });

      Navigator.pop(context); // Dialog band karo
    } catch (e) {
      _showError('Error resetting password: ${e.toString()}');
    }
  }

  void _showForgotPasswordDialog() {
    // State reset
    setState(() {
      _forgotOtpSent = false;
      _forgotOtpVerified = false;
      _showForgotNewPass = false;
      _forgotResolvedEmail = null;
      _forgotResetToken = null;
      _forgotPhoneController.clear();
      _forgotOtpController.clear();
      _forgotNewPassController.clear();
      _forgotConfirmPassController.clear();
      _forgotResendCooldown = 0;
    });
    _forgotResendTimer?.cancel();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // ✅ Resend-cooldown timer isi setDialogState se dialog ko
          // live-refresh kar sake, isliye har build par latest reference
          // save kar lete hain.
          _forgotDialogSetState = setDialogState;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              '🔑 Forgot Password',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info note
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text(
                      '⚠️ Sirf Owner aur Personal Farmer apna password reset kar sakte hain.\n\nManager ka password Owner ke paas hota hai.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade800,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Phone field
                  if (!_forgotOtpSent) ...[
                    const Text(
                      'Registered Phone Number',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _forgotPhoneController,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: '10 digit mobile number',
                        prefixIcon: const Icon(Icons.phone_rounded),
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: primaryGreen,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],

                  // OTP field
                  if (_forgotOtpSent && !_forgotOtpVerified) ...[
                    Text(
                      _forgotResolvedEmail != null
                          ? '$_forgotResolvedEmail par OTP bheja gaya'
                          : 'Aapke registered email par OTP bheja gaya',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '6 Digit OTP',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _forgotOtpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: 'Email se aaya hua code',
                        prefixIcon: const Icon(Icons.lock_clock_rounded),
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: primaryGreen,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _forgotResendCooldown > 0
                            ? null
                            : () {
                                _resendForgotOtp().then((_) {
                                  _forgotDialogSetState?.call(() {});
                                });
                              },
                        child: Text(
                          _forgotResendCooldown > 0
                              ? 'Resend OTP (${_forgotResendCooldown}s)'
                              : 'Resend OTP',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _forgotResendCooldown > 0
                                ? Colors.grey
                                : primaryGreen,
                          ),
                        ),
                      ),
                    ),
                  ],

                  // New Password fields
                  if (_showForgotNewPass) ...[
                    const Text(
                      'Naya Password',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    StatefulBuilder(
                      builder: (context, setPassState) => Column(
                        children: [
                          TextField(
                            controller: _forgotNewPassController,
                            obscureText: !_showForgotNewPassword,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              hintText: 'Naya password',
                              prefixIcon: const Icon(Icons.lock_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showForgotNewPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey,
                                ),
                                onPressed: () => setPassState(
                                  () => _showForgotNewPassword =
                                      !_showForgotNewPassword,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: primaryGreen,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _forgotConfirmPassController,
                            obscureText: !_showForgotConfirmPassword,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              hintText: 'Confirm password',
                              prefixIcon: const Icon(Icons.lock_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showForgotConfirmPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey,
                                ),
                                onPressed: () => setPassState(
                                  () => _showForgotConfirmPassword =
                                      !_showForgotConfirmPassword,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: primaryGreen,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _forgotOtpSent = false;
                    _forgotOtpVerified = false;
                    _showForgotNewPass = false;
                  });
                  Navigator.pop(context);
                },
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  if (!_forgotOtpSent) {
                    _sendForgotOtp().then((_) {
                      setDialogState(() {});
                    });
                  } else if (!_forgotOtpVerified) {
                    _verifyForgotOtp().then((_) {
                      setDialogState(() {});
                    });
                  } else {
                    _setNewPassword();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  !_forgotOtpSent
                      ? 'OTP Bhejo'
                      : !_forgotOtpVerified
                      ? 'Verify Karo'
                      : 'Password Save Karo',
                ),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      // Dialog band ho gaya — resend timer aur stale reference clean karo
      _forgotResendTimer?.cancel();
      _forgotDialogSetState = null;
    });
  }

  void _showError(String msg) {
    Get.snackbar(
      'Error',
      msg,
      backgroundColor: Colors.red.shade600,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
      margin: const EdgeInsets.all(15),
      icon: const Icon(Icons.error_rounded, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Top Green Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 40,
                  horizontal: 24,
                ),
                decoration: const BoxDecoration(
                  color: primaryGreen,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white30, width: 1.5),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.track_changes_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Tracko',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Apne account mein login karo',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 20),

                    // Tab Switcher
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          _tabButton(label: '🔒 Password Login', index: 0),
                          _tabButton(
                            label: '📱 Company Farmer',
                            index: 1,
                          ), // Changed here
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _currentTab == 0
                    ? _buildPasswordLogin()
                    : _buildOtpLogin(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabButton({required String label, required int index}) {
    final isActive = _currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isActive ? primaryGreen : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // PASSWORD LOGIN UI
  // ----------------------------------------------------------------
  Widget _buildPasswordLogin() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: primaryGreen.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: primaryGreen.withOpacity(0.2)),
          ),
          child: const Text(
            '👑 Owner  •  👔 Office Manager  •  🌾 Field Manager  •  🧑‍🌾 Personal Farmer',
            style: TextStyle(
              fontSize: 11,
              color: primaryGreen,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 20),

        // Phone
        const Text(
          'Phone Number',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          textInputAction: TextInputAction.next,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: '10 digit mobile number',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            prefixIcon: const Icon(Icons.phone_rounded, color: primaryGreen),
            filled: true,
            fillColor: Colors.white,
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: primaryGreen, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Password
        const Text(
          'Password',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _passwordController,
          obscureText: !_showPassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _login(),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: 'Apna password daalo',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            prefixIcon: const Icon(Icons.lock_rounded, color: primaryGreen),
            suffixIcon: IconButton(
              icon: Icon(
                _showPassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: primaryGreen, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
          ),
        ),

        // Forgot Password
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _showForgotPasswordDialog,
            child: const Text(
              'Forgot Password?',
              style: TextStyle(
                color: primaryGreen,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Login Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _login,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              elevation: 3,
              shadowColor: primaryGreen.withOpacity(0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text(
                    'Login Karo →',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
        ),

        const SizedBox(height: 20),

        // Register link
        Center(
          child: GestureDetector(
            onTap: () => Get.back(),
            child: RichText(
              text: TextSpan(
                text: 'Naya account banana hai? ',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
                children: [
                  TextSpan(
                    text: 'Register Karo',
                    style: TextStyle(
                      color: primaryGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ----------------------------------------------------------------
  // LOGIN UI — Company Farmer (Number + PIN)
  // ----------------------------------------------------------------
  Widget _buildOtpLogin() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: const Text(
            '🐔 Sirf Company Farmer ke liye\nOwner ne aapka number register kiya hoga tabhi login hoga',
            style: TextStyle(
              fontSize: 11,
              color: Colors.deepOrange,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 20),

        // Phone
        const Text(
          'Aapka Phone Number',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _farmerPhoneController,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                enabled: !_farmerPhoneChecked,
                textInputAction: TextInputAction.done,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: '10 digit mobile number',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(
                    Icons.phone_rounded,
                    color: primaryGreen,
                  ),
                  filled: true,
                  fillColor: _farmerPhoneChecked
                      ? Colors.grey.shade100
                      : Colors.white,
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: primaryGreen,
                      width: 1.5,
                    ),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: (_farmerPhoneChecked || _isLoading)
                  ? null
                  : _checkFarmerPhone,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: (_isLoading && !_farmerPhoneChecked)
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      _farmerPhoneChecked ? '✓ Verified' : 'Check Number',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),

        // PIN field
        if (_farmerPhoneChecked && !_farmerForgotPin) ...[
          const SizedBox(height: 20),
          Text(
            _farmerHasPin ? 'Apna 4-digit PIN daalo' : 'Naya 4-digit PIN banao',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _farmerPinController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: '4 digit PIN',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              prefixIcon: const Icon(
                Icons.lock_outline_rounded,
                color: primaryGreen,
              ),
              filled: true,
              fillColor: Colors.white,
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: primaryGreen, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
            ),
          ),

          if (!_farmerHasPin) ...[
            const SizedBox(height: 14),
            const Text(
              'PIN Confirm Karo',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _farmerPinConfirmController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Wahi PIN dobara daalo',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                prefixIcon: const Icon(
                  Icons.lock_outline_rounded,
                  color: primaryGreen,
                ),
                filled: true,
                fillColor: Colors.white,
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: primaryGreen, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
              ),
            ),

            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Text(
                'Security ke liye apni Date of Birth confirm karo (wahi jo Office Manager ko onboarding ke time di thi).',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.blue.shade900,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Date of Birth',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _farmerDobController,
              keyboardType: TextInputType.datetime,
              maxLength: 10, // Added
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'DD/MM/YYYY',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                prefixIcon: const Icon(
                  Icons.cake_outlined,
                  color: primaryGreen,
                ),
                filled: true,
                fillColor: Colors.white,
                counterText: '', // Added
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: primaryGreen, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submitFarmerPin,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      _farmerHasPin ? 'Login Karo' : 'PIN Set Karo & Login',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),

          // "PIN bhool gaye?" — sirf returning farmer (already PIN set)
          // ko dikhega, naye farmer ko nahi (uska to PIN hi ban raha hai)
          if (_farmerHasPin) ...[
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _farmerForgotPin = true;
                    _farmerPinController.clear();
                    _farmerPinConfirmController.clear();
                  });
                },
                child: const Text(
                  'PIN bhool gaye?',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ],

        // ── Forgot PIN — SELF-SERVICE reset (farmer khud karta hai) ──────
        // DOB confirm karke naya PIN set hota hai, Office Manager ki
        // zaroorat nahi.
        if (_farmerPhoneChecked && _farmerForgotPin) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Text(
              'Apni Date of Birth daalo (wahi jo Office Manager ko onboarding ke time di thi) — match hone par naya PIN set kar sakte ho.',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.blue.shade900,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Date of Birth',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _farmerDobController,
            keyboardType: TextInputType.datetime,
            maxLength: 10, // Added
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'DD/MM/YYYY',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              prefixIcon: const Icon(Icons.cake_outlined, color: primaryGreen),
              filled: true,
              fillColor: Colors.white,
              counterText: '', // Added
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: primaryGreen, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Naya 4-digit PIN',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _farmerPinController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: '4 digit PIN',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              prefixIcon: const Icon(
                Icons.lock_outline_rounded,
                color: primaryGreen,
              ),
              filled: true,
              fillColor: Colors.white,
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: primaryGreen, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'PIN Confirm Karo',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _farmerPinConfirmController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'Wahi naya PIN dobara daalo',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              prefixIcon: const Icon(
                Icons.lock_outline_rounded,
                color: primaryGreen,
              ),
              filled: true,
              fillColor: Colors.white,
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: primaryGreen, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submitFarmerPinReset,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'PIN Reset Karo & Login',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () {
                setState(() {
                  _farmerForgotPin = false;
                  _farmerPinController.clear();
                  _farmerPinConfirmController.clear();
                  _farmerDobController.clear();
                });
              },
              child: const Text(
                '← Wapas jao',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          ),
        ],

        const SizedBox(height: 40),
      ],
    );
  }
}
