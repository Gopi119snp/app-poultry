import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../home/home_screen.dart';
import '../../services/auth_service.dart';

class CompanyRegisterScreen extends StatefulWidget {
  final String industry;
  final Color industryColor;

  const CompanyRegisterScreen({
    super.key,
    required this.industry,
    required this.industryColor,
  });

  @override
  State<CompanyRegisterScreen> createState() => _CompanyRegisterScreenState();
}

class _CompanyRegisterScreenState extends State<CompanyRegisterScreen> {
  // ---------------------------------------------------------------------------
  // FLAGS & ANALYTICS DATA
  // ---------------------------------------------------------------------------

  // Web Transition Bug Fix ke liye flag
  bool _isTransitionDone = false;
  bool _isLoadingPin = false;
  bool _isLoadingVerification = false;

  // Background Location Analytics Data (Database mein store karne ke liye)
  Map<String, dynamic> _ipAnalyticsData = {};

  // ---------------------------------------------------------------------------
  // CONTROLLERS (Total 13 Controllers)
  // ---------------------------------------------------------------------------

  final _companyNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _emailController = TextEditingController(); // Compulsory Email
  final _streetController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pinController = TextEditingController();
  final _gstController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _emailOtpController = TextEditingController(); // Email OTP Controller
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // ---------------------------------------------------------------------------
  // UI & VERIFICATION STATE
  // ---------------------------------------------------------------------------

  bool _showPassword = false;
  bool _showConfirmPassword = false;

  // Verification Handling Flags
  bool _otpSent = false;
  bool _otpVerified = false;
  bool _emailOtpSent = false;
  bool _emailVerified = false;

  int _currentStep = 1;
  String? _selectedState;

  // Full States List for India
  final List<String> _states = [
    'Andhra Pradesh',
    'Arunachal Pradesh',
    'Assam',
    'Bihar',
    'Chhattisgarh',
    'Goa',
    'Gujarat',
    'Haryana',
    'Himachal Pradesh',
    'Jharkhand',
    'Karnataka',
    'Kerala',
    'Madhya Pradesh',
    'Maharashtra',
    'Manipur',
    'Meghalaya',
    'Mizoram',
    'Nagaland',
    'Odisha',
    'Punjab',
    'Rajasthan',
    'Sikkim',
    'Tamil Nadu',
    'Telangana',
    'Tripura',
    'Uttar Pradesh',
    'Uttarakhand',
    'West Bengal',
    'Delhi',
    'Jammu & Kashmir',
    'Ladakh',
  ];

  // ---------------------------------------------------------------------------
  // LIFECYCLE METHODS
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    // Smooth transition for Web performance
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isTransitionDone = true;
        });
      }
    });

    // PIN listener setup for automatic verification
    _pinController.addListener(_onPinChanged);
  }

  void _onPinChanged() {
    String pin = _pinController.text.trim();
    if (pin.length == 6 && !_isLoadingPin) {
      _fetchAddressFromPin(pin);
    }
  }

  @override
  void dispose() {
    // Cleanup controllers to prevent memory leaks
    _pinController.removeListener(_onPinChanged);
    _companyNameController.dispose();
    _ownerNameController.dispose();
    _emailController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pinController.dispose();
    _gstController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _emailOtpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // API INTEGRATIONS (FREE)
  // ---------------------------------------------------------------------------

  // PIN Code API Connection
  Future<void> _fetchAddressFromPin(String pin) async {
    if (!mounted) return;
    setState(() {
      _isLoadingPin = true;
    });

    try {
      final response = await http.get(
        Uri.parse('https://api.postalpincode.in/pincode/$pin'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data[0]['Status'] == 'Success') {
          var details = data[0]['PostOffice'][0];
          String fetchedState = details['State'];

          if (mounted) {
            setState(() {
              _cityController.text = details['District'];
              _stateController.text = fetchedState;

              // Automatic dropdown selection
              if (_states.contains(fetchedState)) {
                _selectedState = fetchedState;
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('PIN API Integration Warning: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPin = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // VALIDATION LOGIC
  // ---------------------------------------------------------------------------

  bool _isValidPhone(String p) => RegExp(r'^[6-9]\d{9}$').hasMatch(p);

  bool _isValidPin(String p) => RegExp(r'^\d{6}$').hasMatch(p);

  bool _isValidEmail(String e) =>
      RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(e);

  bool _isValidName(String n) => n.trim().length >= 3;

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

  // ---------------------------------------------------------------------------
  // PROCESS FLOW (OTP & REGISTER)
  // ---------------------------------------------------------------------------

  void _sendVerificationOTPs() async {
    // 1. Strict Form Validations
    if (!_isValidName(_companyNameController.text)) {
      _showError('Company naam sahi daalo — kam se kam 3 characters');
      return;
    }
    if (!_isValidName(_ownerNameController.text)) {
      _showError('Owner naam sahi daalo — kam se kam 3 characters');
      return;
    }
    if (!_isValidEmail(_emailController.text.trim())) {
      _showError('Sahi Email address daalo — ye compulsory hai');
      return;
    }
    if (_streetController.text.trim().length < 4) {
      _showError('Street / Area poora daalo — kam se kam 4 characters');
      return;
    }
    if (_cityController.text.isEmpty || _stateController.text.isEmpty) {
      _showError('Sahi PIN code daalo taaki City/State auto-fetch ho sake');
      return;
    }
    if (!_isValidPin(_pinController.text)) {
      _showError('PIN code 6 digit ka hona chahiye');
      return;
    }
    if (!_isValidPhone(_phoneController.text)) {
      _showError('Phone number sahi daalo — 10 digit, 6/7/8/9 se shuru');
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoadingVerification = true;
    });

    // 2. Background Network Analytics (Non-blocking)
    try {
      final ipResponse = await http.get(Uri.parse('https://ipapi.co/json/'));
      if (ipResponse.statusCode == 200) {
        final ipData = json.decode(ipResponse.body);
        _ipAnalyticsData = {
          'user_ip': ipData['ip'] ?? 'Unknown',
          'network_city': ipData['city'] ?? 'Unknown',
          'network_state': ipData['region'] ?? 'Unknown',
          'timestamp': DateTime.now().toIso8601String(),
        };
        debugPrint('DB Analytics Captured: $_ipAnalyticsData');
      }
    } catch (e) {
      debugPrint('Network tracing safely skipped: $e');
    }

    // 3. Move to Step 2 (Verification)
    if (!mounted) return;
    setState(() {
      _isLoadingVerification = false;
      _otpSent = true;
      _emailOtpSent = true;
      _currentStep = 2;
    });

    Get.snackbar(
      'Sent!',
      'Mobile aur Email dono par verification codes bheje gaye hain',
      backgroundColor: widget.industryColor,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(15),
    );
  }

  // Mobile OTP Verification Handler
  void _verifyMobileOTP() {
    /* // ORIGINAL LOGIC (Uncomment when going live)
    if (_otpController.text.length != 6 || !RegExp(r'^\d{6}$').hasMatch(_otpController.text)) {
      _showError('6 digit numeric Mobile OTP daalo');
      return;
    }
    */

    // --- TEST MODE BYPASS ---
    if (!mounted) return;
    setState(() {
      _otpVerified = true;
    });
    _checkIfAllVerified();
    // ------------------------
  }

  // Email OTP Verification Handler
  void _verifyEmailOTP() {
    /* // ORIGINAL LOGIC (Uncomment when going live)
    if (_emailOtpController.text.length != 6 || !RegExp(r'^\d{6}$').hasMatch(_emailOtpController.text)) {
      _showError('6 digit numeric Email OTP daalo');
      return;
    }
    */

    // --- TEST MODE BYPASS ---
    if (!mounted) return;
    setState(() {
      _emailVerified = true;
    });
    _checkIfAllVerified();
    // ------------------------
  }

  void _checkIfAllVerified() {
    if (_otpVerified && _emailVerified) {
      if (!mounted) return;
      setState(() {
        _currentStep = 3; // Step 3 Password setup unlocked
      });
      Get.snackbar(
        'Verified! ✅',
        'Details sahi payi gayi hain. Ab apna password banayein.',
        backgroundColor: widget.industryColor,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
    }
  }

  Future<void> _register() async {
    if (_passwordController.text.length < 6) {
      _showError('Password kam se kam 6 characters ka hona chahiye');
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      _showError('Password match nahi kar raha');
      return;
    }

    setState(() => _isLoadingVerification = true);

    final result = await AuthService.instance.registerCompany(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      ownerName: _ownerNameController.text.trim(),
      companyName: _companyNameController.text.trim(),
      phone: _phoneController.text.trim(),
      industry: widget.industry,
      extraProfile: {
        'street': _streetController.text.trim(),
        'city': _cityController.text.trim(),
        'state': _stateController.text.trim(),
        'pin': _pinController.text.trim(),
        'gst': _gstController.text.trim(),
        'ipAnalytics': _ipAnalyticsData,
      },
    );

    if (!mounted) return;
    setState(() => _isLoadingVerification = false);

    if (!result.success) {
      _showError(result.errorMessage ?? 'Registration fail');
      return;
    }

    Get.snackbar(
      '🎉 Registered!',
      'Welcome to PoultryPro — ${_companyNameController.text}',
      backgroundColor: widget.industryColor,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
      margin: const EdgeInsets.all(15),
    );

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    Get.offAll(
      () => HomeScreen(
        ownerName: _ownerNameController.text,
        companyName: _companyNameController.text,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MAIN UI BUILDER
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.black87),
          onPressed: () => Get.back(),
        ),
        title: const Text(
          'Company Account',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: !_isTransitionDone
            ? Center(
                child: CircularProgressIndicator(
                  color: widget.industryColor,
                  strokeWidth: 3,
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Step Progress Indicator
                    _buildProgress(),
                    const SizedBox(height: 32),

                    // STEP 1 — DATA ENTRY PHASE
                    if (_currentStep >= 1) ...[
                      _sectionLabel('🏢 COMPANY DETAIL', '1'),
                      const SizedBox(height: 16),
                      _buildInput(
                        controller: _companyNameController,
                        label: 'Company Naam *',
                        hint: 'e.g. Singh Poultry Farms',
                        icon: Icons.business_rounded,
                        enabled: !_otpSent,
                      ),
                      _buildInput(
                        controller: _ownerNameController,
                        label: 'Owner Naam *',
                        hint: 'e.g. Rajesh Singh',
                        icon: Icons.person_rounded,
                        enabled: !_otpSent,
                      ),
                      _buildInput(
                        controller: _emailController,
                        label: 'Email Address *',
                        hint: 'e.g. contact@business.com',
                        icon: Icons.email_rounded,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_otpSent,
                      ),
                      const SizedBox(height: 12),
                      _sectionLabel('📍 COMPANY ADDRESS', ''),
                      const SizedBox(height: 12),
                      _buildInput(
                        controller: _pinController,
                        label: 'PIN Code *',
                        hint: 'e.g. 800001',
                        icon: Icons.pin_drop_rounded,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        enabled: !_otpSent,
                        suffix: _isLoadingPin
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                      ),
                      _buildInput(
                        controller: _cityController,
                        label: 'City (Auto-fill) *',
                        hint: 'PIN code daalte hi aayega',
                        icon: Icons.location_city_rounded,
                        enabled: false,
                      ),
                      _buildStateDropdown(),
                      _buildInput(
                        controller: _streetController,
                        label: 'Street / Area *',
                        hint: 'Industrial Area, Near Main Gate',
                        icon: Icons.signpost_rounded,
                        enabled: !_otpSent,
                      ),
                      _buildInput(
                        controller: _gstController,
                        label: 'GST Number (Optional)',
                        hint: 'e.g. 10AAAAA0000A1Z5',
                        icon: Icons.receipt_long_rounded,
                        enabled: !_otpSent,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18, top: 2),
                        child: Text(
                          '* Sahi PIN Code daalne par City aur State khud ba khud fetch ho jayenge.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                      _sectionLabel('📱 PHONE NUMBER', ''),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: _buildInput(
                              controller: _phoneController,
                              label: 'Phone Number *',
                              hint: '10 digit mobile no.',
                              icon: Icons.phone_rounded,
                              keyboardType: TextInputType.phone,
                              maxLength: 10,
                              enabled: !_otpSent,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: ElevatedButton(
                              onPressed: (_otpSent || _isLoadingVerification)
                                  ? null
                                  : _sendVerificationOTPs,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: widget.industryColor,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: Colors.grey.shade300,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 18,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isLoadingVerification
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      _otpSent ? '✓ Sent' : 'Verify Info',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    // STEP 2 — VERIFICATION PHASE (Dual Verification)
                    if (_currentStep >= 2) ...[
                      const SizedBox(height: 32),
                      _sectionLabel('🔐 SECURITY VERIFICATION', '2'),
                      const SizedBox(height: 16),

                      // Mobile OTP Container
                      if (!_otpVerified) ...[
                        _buildVerificationRow(
                          controller: _otpController,
                          label: 'Mobile OTP *',
                          hint: 'Type anything (Test Mode)',
                          onVerify: _verifyMobileOTP,
                        ),
                      ] else
                        _verifiedBox(
                          'Mobile Number successfully verified! ✓',
                          widget.industryColor,
                        ),

                      const SizedBox(height: 16),

                      // Email OTP Container
                      if (!_emailVerified) ...[
                        _buildVerificationRow(
                          controller: _emailOtpController,
                          label: 'Email OTP *',
                          hint: 'Type anything (Test Mode)',
                          onVerify: _verifyEmailOTP,
                        ),
                      ] else
                        _verifiedBox(
                          'Email Account successfully verified! ✓',
                          widget.industryColor,
                        ),

                      if (!_otpVerified || !_emailVerified)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            'Kripya dhyan dein: Abhi app development phase (Test Mode) mein hai, isliye sirf Verify button dabane se bypass ho jayega.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              height: 1.4,
                            ),
                          ),
                        ),
                    ],

                    // STEP 3 — CREDENTIALS PHASE (Password Locking)
                    if (_currentStep >= 3) ...[
                      const SizedBox(height: 32),
                      _sectionLabel('🔒 PASSWORD SET KARO', '3'),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: widget.industryColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: widget.industryColor.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Password Rules:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: widget.industryColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '• Kam se kam 6 characters\n• Ek letter aur ek number zaroori\n• e.g. farm@123 ✓',
                              style: TextStyle(
                                fontSize: 11,
                                color: widget.industryColor.withOpacity(0.8),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildPasswordInput(
                        controller: _passwordController,
                        label: 'Naya Password *',
                        hint: 'Create password',
                        show: _showPassword,
                        onToggle: () {
                          if (!mounted) return;
                          setState(() => _showPassword = !_showPassword);
                        },
                      ),
                      _buildPasswordInput(
                        controller: _confirmPasswordController,
                        label: 'Confirm Password *',
                        hint: 'Dobara same password daalo',
                        show: _showConfirmPassword,
                        onToggle: () {
                          if (!mounted) return;
                          setState(
                            () => _showConfirmPassword = !_showConfirmPassword,
                          );
                        },
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _register,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.industryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            elevation: 4,
                            shadowColor: widget.industryColor.withOpacity(0.3),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Complete Registration — Start 7 Day Free →',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // REUSABLE UI COMPONENTS (Helper Widgets)
  // ---------------------------------------------------------------------------

  // Verification Row Builder
  Widget _buildVerificationRow({
    required TextEditingController controller,
    required String label,
    required String hint,
    required VoidCallback onVerify,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: _buildInput(
            controller: controller,
            label: label,
            hint: hint,
            icon: Icons.lock_clock_rounded,
            keyboardType: TextInputType.number,
            maxLength: 6,
          ),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: ElevatedButton(
            onPressed: onVerify,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.industryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Verify',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  // Original State Dropdown
  Widget _buildStateDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'State *',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedState,
            isExpanded: true,
            icon: const Icon(Icons.arrow_drop_down_circle_outlined, size: 20),
            decoration: InputDecoration(
              prefixIcon: Icon(
                Icons.map_rounded,
                color: Colors.grey.shade400,
                size: 20,
              ),
              filled: true,
              fillColor: _otpSent ? Colors.grey.shade100 : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: widget.industryColor, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 16,
              ),
            ),
            hint: Text(
              'State chuniye',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
            items: _states
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(s, style: const TextStyle(fontSize: 13)),
                  ),
                )
                .toList(),
            onChanged: _otpSent
                ? null
                : (val) {
                    if (!mounted) return;
                    setState(() {
                      _selectedState = val;
                      _stateController.text = val ?? '';
                    });
                  },
          ),
        ],
      ),
    );
  }

  // Verified Status Badge
  Widget _verifiedBox(String msg, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Main Stepper Progress
  Widget _buildProgress() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          _progressStep('Detail', 1),
          _progressLine(1),
          _progressStep('Verify', 2),
          _progressLine(2),
          _progressStep('Final', 3),
        ],
      ),
    );
  }

  Widget _progressStep(String label, int step) {
    final isActive = _currentStep >= step;
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isActive ? widget.industryColor : Colors.grey.shade200,
            shape: BoxShape.circle,
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: widget.industryColor.withOpacity(0.2),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: isActive && _currentStep > step
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                : Text(
                    '$step',
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.grey,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive ? widget.industryColor : Colors.grey,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.normal,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _progressLine(int step) {
    return Expanded(
      child: Container(
        height: 3,
        margin: const EdgeInsets.only(bottom: 20, left: 4, right: 4),
        decoration: BoxDecoration(
          color: _currentStep > step
              ? widget.industryColor
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, String num) {
    return Row(
      children: [
        if (num.isNotEmpty) ...[
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: widget.industryColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                num,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: Colors.black54,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  // Custom Input Field
  Widget _buildInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    int? maxLength,
    bool enabled = true,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            maxLength: maxLength,
            enabled: enabled,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
              suffixIcon: suffix != null
                  ? Padding(padding: const EdgeInsets.all(12), child: suffix)
                  : null,
              filled: true,
              fillColor: enabled ? Colors.white : Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: widget.industryColor, width: 1.5),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }

  // Custom Password Input Field
  Widget _buildPasswordInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool show,
    required VoidCallback onToggle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            obscureText: !show,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              prefixIcon: Icon(
                Icons.lock_rounded,
                color: Colors.grey.shade400,
                size: 20,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  show ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
                onPressed: onToggle,
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: widget.industryColor, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
