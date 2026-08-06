import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../home/home_screen.dart';
import '../../services/auth_service.dart';
import '../../services/company_store.dart';
import '../../services/otp_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);

  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpPhoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmNewPasswordController = TextEditingController();
  final _forgotPhoneController = TextEditingController();
  final _forgotOtpController = TextEditingController();
  final _forgotNewPassController = TextEditingController();
  final _forgotConfirmPassController = TextEditingController();

  bool _showPassword = false;
  bool _isLoading = false;

  // OTP Login state (Company Farmer)
  bool _otpSent = false;
  bool _otpVerified = false;
  bool _showNewPassFields = false;

  // Forgot Password state
  bool _forgotOtpSent = false;
  bool _forgotOtpVerified = false;
  bool _showForgotNewPass = false;
  bool _showForgotNewPassword = false;
  bool _showForgotConfirmPassword = false;

  // Current tab: 0 = Password Login, 1 = OTP Login (Company Farmer)
  int _currentTab = 0;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _otpPhoneController.dispose();
    _otpController.dispose();
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
      Get.offAll(
        () => HomeScreen(
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
  // OTP LOGIN — Company Farmer (REAL Firebase Phone Auth)
  // ----------------------------------------------------------------
  Future<void> _sendFarmerOtp() async {
    final phone = _otpPhoneController.text.trim();
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
      _showError('Sahi phone number daalo — 10 digit');
      return;
    }

    try {
      final companyFarmers = await CompanyStore.instance.getJsonList(
        'companyFarmers',
      );
      final farmerExists = companyFarmers.any((f) => f['phone'] == phone);

      if (!farmerExists) {
        _showError('Yeh number register nahi hai. Owner se contact karo.');
        return;
      }

      setState(() => _isLoading = true);
      await OtpService.instance.sendOtp(
        phone: phone,
        onCodeSent: () {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _otpSent = true;
          });
          Get.snackbar(
            'OTP Bheja Gaya!',
            '$phone pe OTP bheja gaya',
            backgroundColor: primaryGreen,
            colorText: Colors.white,
            snackPosition: SnackPosition.BOTTOM,
            margin: const EdgeInsets.all(15),
          );
        },
        onError: (msg) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          _showError(msg);
        },
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error checking farmer: ${e.toString()}');
    }
  }

  Future<void> _verifyFarmerOtp() async {
    if (_otpController.text.length != 6) {
      _showError('6 digit OTP daalo');
      return;
    }

    setState(() => _isLoading = true);

    final otpOk = await OtpService.instance.verifyOtp(
      _otpController.text.trim(),
    );

    if (!otpOk) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('OTP galat hai');
      return;
    }

    try {
      // Session signed-in HI rakho (sign out mat karo) — isse farmer ka
      // real Firebase UID mil jayega jo linkAuthUser use karega.
      final result = await AuthService.instance.loginCompanyFarmer(
        phone: _otpPhoneController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (!result.success) {
        await OtpService.instance.signOutOtpSession();
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
      Get.offAll(
        () => HomeScreen(
          ownerName: result.displayName ?? '',
          companyName: result.companyName ?? '',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('OTP verification error: ${e.toString()}');
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

      await OtpService.instance.sendOtp(
        phone: phone,
        onCodeSent: () {
          if (!mounted) return;
          setState(() => _forgotOtpSent = true);
          Get.snackbar(
            'OTP Bheja Gaya!',
            '$phone pe OTP bheja gaya',
            backgroundColor: primaryGreen,
            colorText: Colors.white,
            snackPosition: SnackPosition.BOTTOM,
            margin: const EdgeInsets.all(15),
          );
        },
        onError: (msg) => _showError(msg),
      );
    } catch (e) {
      _showError('Error sending OTP: ${e.toString()}');
    }
  }

  Future<void> _verifyForgotOtp() async {
    if (_forgotOtpController.text.length != 6) {
      _showError('6 digit OTP daalo');
      return;
    }

    final ok = await OtpService.instance.verifyOtp(
      _forgotOtpController.text.trim(),
    );

    if (!ok) {
      _showError('OTP galat hai');
      return;
    }

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

    try {
      // Server-side Cloud Function — verified phone-auth session se hi kaam karti hai
      final error = await OtpService.instance.resetPasswordAfterOtp(
        _forgotNewPassController.text,
      );
      // Temporary phone-auth session ab band karo
      await OtpService.instance.signOutOtpSession();

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
      _forgotPhoneController.clear();
      _forgotOtpController.clear();
      _forgotNewPassController.clear();
      _forgotConfirmPassController.clear();
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                    '${_forgotPhoneController.text} pe OTP bheja gaya',
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
                      hintText: 'e.g. 123456',
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
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
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
        ),
      ),
    );
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
                          _tabButton(label: '📱 OTP Login', index: 1),
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
  // OTP LOGIN UI — Company Farmer
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
                controller: _otpPhoneController,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                enabled: !_otpSent,
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
                  fillColor: _otpSent ? Colors.grey.shade100 : Colors.white,
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
              onPressed: (_otpSent || _isLoading) ? null : _sendFarmerOtp,
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
              child: (_isLoading && !_otpSent)
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      _otpSent ? '✓ Sent' : 'OTP Bhejo',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),

        // OTP field
        if (_otpSent) ...[
          const SizedBox(height: 20),
          const Text(
            '6 Digit OTP',
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
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'SMS se aaya hua code',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.lock_clock_rounded,
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
                      borderSide: const BorderSide(
                        color: primaryGreen,
                        width: 1.5,
                      ),
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
                onPressed: _isLoading ? null : _verifyFarmerOtp,
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
                child: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Verify',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 40),
      ],
    );
  }
}
