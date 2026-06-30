import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class PersonalRegisterScreen extends StatefulWidget {
  final String industry;
  const PersonalRegisterScreen({super.key, required this.industry});

  @override
  State<PersonalRegisterScreen> createState() => _PersonalRegisterScreenState();
}

class _PersonalRegisterScreenState extends State<PersonalRegisterScreen> {
  // ---------------------------------------------------------------------------
  // FLAGS & ANALYTICS DATA
  // ---------------------------------------------------------------------------

  // Web Transition Bug Fix (Safely loading UI after animation)
  bool _isTransitionDone = false;
  bool _isLoadingPin = false;
  bool _isLoadingVerification = false;

  // Background Location Analytics (Analytics ke liye data collect hoga)
  Map<String, dynamic> _ipAnalyticsData = {};

  // ---------------------------------------------------------------------------
  // CONTROLLERS (Total 11 Controllers)
  // ---------------------------------------------------------------------------

  final _nameController = TextEditingController();
  final _emailController = TextEditingController(); // Optional Email
  final _streetController = TextEditingController();
  final _villageController = TextEditingController();
  final _districtController = TextEditingController();
  final _stateController = TextEditingController();
  final _pinController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // ---------------------------------------------------------------------------
  // UI & VERIFICATION STATE
  // ---------------------------------------------------------------------------

  bool _showPassword = false;
  bool _showConfirmPassword = false;

  // Verification Flags
  bool _otpSent = false;
  bool _otpVerified = false;

  int _currentStep = 1;
  String? _selectedState;

  // Full Indian States List
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

    // Page load delay for Web stability
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isTransitionDone = true;
        });
      }
    });

    // Automatic PIN code fetcher listener
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
    // Memory cleanup
    _pinController.removeListener(_onPinChanged);
    _nameController.dispose();
    _emailController.dispose();
    _streetController.dispose();
    _villageController.dispose();
    _districtController.dispose();
    _stateController.dispose();
    _pinController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // API INTEGRATIONS (FREE PIN AUTO-FILL)
  // ---------------------------------------------------------------------------

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
              _districtController.text = details['District'];
              _stateController.text = fetchedState;

              // Sync dropdown with API fetched state
              if (_states.contains(fetchedState)) {
                _selectedState = fetchedState;
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('PIN API Silence Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPin = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // VALIDATION HELPERS
  // ---------------------------------------------------------------------------

  bool _isValidPhone(String p) => RegExp(r'^[6-9]\d{9}$').hasMatch(p);

  bool _isValidPin(String p) => RegExp(r'^\d{6}$').hasMatch(p);

  bool _isValidEmail(String e) {
    if (e.isEmpty) return true; // Keep optional as requested
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(e);
  }

  bool _isValidName(String n) {
    return n.trim().length >= 3 && RegExp(r'^[a-zA-Z\s]+$').hasMatch(n.trim());
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

  // ---------------------------------------------------------------------------
  // CORE PROCESS FLOW (OTP & DATA LOGGING)
  // ---------------------------------------------------------------------------

  void _sendOTP() async {
    // 1. Mandatory Validations
    if (!_isValidName(_nameController.text)) {
      _showError('Naam sahi daalo — kam se kam 3 letters');
      return;
    }
    if (_streetController.text.trim().length < 4) {
      _showError('Street / Mohalla sahi se bhariye');
      return;
    }
    if (_villageController.text.trim().isEmpty) {
      _showError('Village / Town ka naam daalo');
      return;
    }
    if (_districtController.text.trim().isEmpty) {
      _showError('District ka naam daalo');
      return;
    }
    if (_selectedState == null) {
      _showError('State chuniye');
      return;
    }
    if (!_isValidPin(_pinController.text)) {
      _showError('PIN code 6 digit ka hona chahiye');
      return;
    }
    if (!_isValidEmail(_emailController.text)) {
      _showError('Email format galat hai');
      return;
    }
    if (!_isValidPhone(_phoneController.text)) {
      _showError('10 digit Mobile Number daalo');
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoadingVerification = true;
    });

    // 2. IP Analytics Capture (Silent background logging)
    try {
      final ipResponse = await http.get(Uri.parse('https://ipapi.co/json/'));
      if (ipResponse.statusCode == 200) {
        final ipData = json.decode(ipResponse.body);
        _ipAnalyticsData = {
          'ip': ipData['ip'] ?? 'Unknown',
          'city': ipData['city'] ?? 'Unknown',
          'region': ipData['region'] ?? 'Unknown',
          'device': 'Personal_Farmer_Flow',
        };
        print('Background Analytics Logged: $_ipAnalyticsData');
      }
    } catch (e) {
      print('Network Analytics bypassed: $e');
    }

    if (!mounted) return;
    setState(() {
      _isLoadingVerification = false;
      _otpSent = true;
      _currentStep = 2; // Move to verification
    });

    Get.snackbar(
      'OTP Sent!',
      'Verification code aapke number ${_phoneController.text} par bheja gaya hai',
      backgroundColor: const Color(0xFF1B5E20),
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(15),
    );
  }

  void _verifyOTP() {
    /* -------------------------------------------------------------------------
    // ORIGINAL VERIFICATION LOGIC (Uncomment for Production)
    if (_otpController.text.length != 6 || !RegExp(r'^\d{6}$').hasMatch(_otpController.text)) {
      _showError('6 digit numeric OTP daalo');
      return;
    }
    ------------------------------------------------------------------------- */

    // --- TEST MODE BYPASS (Bina OTP check kiye aage badhega) ---
    if (!mounted) return;
    setState(() {
      _otpVerified = true;
      _currentStep = 3; // Unlocking Password phase
    });

    Get.snackbar(
      'Verified! ✅',
      'Phone number verify ho gaya. Ab apna password set karein.',
      backgroundColor: const Color(0xFF1B5E20),
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(15),
    );
  }

  void _register() {
    if (_passwordController.text.length < 6) {
      _showError('Password kam se kam 6 characters ka hona chahiye');
      return;
    }
    if (!RegExp(r'^(?=.*[A-Za-z])(?=.*\d).+$')
        .hasMatch(_passwordController.text)) {
      _showError(
          'Password mein kam se kam ek letter aur ek number hona chahiye');
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      _showError('Confirm password match nahi kar raha');
      return;
    }

    // Prepare final dataset
    print('Registering Farmer Profile:');
    print('Name: ${_nameController.text}, Analytics: $_ipAnalyticsData');

    Get.snackbar(
      '🎉 Registered!',
      'Welcome to Tracko — ${_nameController.text}',
      backgroundColor: const Color(0xFF1B5E20),
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
      margin: const EdgeInsets.all(15),
    );

    // Future sequence to Home Dashboard
  }

  // ---------------------------------------------------------------------------
  // UI BUILDER (SCREENS)
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
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Personal Account',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: !_isTransitionDone
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF1B5E20),
                  strokeWidth: 3,
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Visual Progress Tracker
                    _buildProgress(),
                    const SizedBox(height: 32),

                    // STEP 1 — PERSONAL DATA INPUT
                    if (_currentStep >= 1) ...[
                      _sectionLabel('👤 AAPKI DETAIL', '1'),
                      const SizedBox(height: 16),
                      _buildInput(
                        controller: _nameController,
                        label: 'Poora Naam *',
                        hint: 'e.g. Rajesh Kumar',
                        icon: Icons.person_rounded,
                        enabled: !_otpSent,
                      ),
                      _buildInput(
                        controller: _emailController,
                        label: 'Email ID (Optional)',
                        hint: 'e.g. rajesh@gmail.com',
                        icon: Icons.email_rounded,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_otpSent,
                      ),
                      const SizedBox(height: 12),
                      _sectionLabel('📍 AAPKA ADDRESS', ''),
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
                                  color: Color(0xFF1B5E20),
                                ),
                              )
                            : null,
                      ),
                      _buildInput(
                        controller: _districtController,
                        label: 'District (Auto-fill) *',
                        hint: 'PIN dalte hi aayega',
                        icon: Icons.location_city_rounded,
                        enabled: false, // Locked for safety
                      ),
                      _buildStateDropdown(),
                      _buildInput(
                        controller: _streetController,
                        label: 'Street / Mohalla / Gali *',
                        hint: 'e.g. Gandhi Nagar, Gali No. 2',
                        icon: Icons.signpost_rounded,
                        enabled: !_otpSent,
                      ),
                      _buildInput(
                        controller: _villageController,
                        label: 'Village / Town *',
                        hint: 'e.g. Rampur',
                        icon: Icons.holiday_village_rounded,
                        enabled: !_otpSent,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18, top: 2),
                        child: Text(
                          '* Sahi PIN Code daalne par District aur State khud ba khud bhar jayenge.',
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
                                  : _sendOTP,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1B5E20),
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
                                      _otpSent ? '✓ Sent' : 'Verify No.',
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

                    // STEP 2 — MOBILE VERIFICATION PHASE (Test Mode)
                    if (_currentStep >= 2) ...[
                      const SizedBox(height: 32),
                      _sectionLabel('🔐 SECURITY VERIFICATION', '2'),
                      const SizedBox(height: 16),
                      if (!_otpVerified) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: _buildInput(
                                controller: _otpController,
                                label: '6 Digit OTP *',
                                hint: 'Test Mode: Type anything',
                                icon: Icons.lock_clock_rounded,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: ElevatedButton(
                                onPressed: _verifyOTP,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1B5E20),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 18,
                                  ),
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
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            'Note: Abhi test mode hai, Verify button dabate hi bypass ho jayega.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ] else
                        _verifiedBox(
                          'Mobile verified successfully! ✓',
                          const Color(0xFF1B5E20),
                        ),
                    ],

                    // STEP 3 — PASSWORD LOCKING PHASE
                    if (_currentStep >= 3) ...[
                      const SizedBox(height: 32),
                      _sectionLabel('🔒 PASSWORD SET KARO', '3'),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF1B5E20).withOpacity(0.2),
                          ),
                        ),
                        child: Text(
                          '• Kam se kam 6 characters\n• Ek letter + ek number zaroori\n• e.g. farmer@123 ✓',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green.shade800,
                            height: 1.5,
                          ),
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
                            backgroundColor: const Color(0xFF1B5E20),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            elevation: 4,
                            shadowColor:
                                const Color(0xFF1B5E20).withOpacity(0.3),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Farmer Account Banao — Start FREE →',
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
  // HELPER COMPONENTS
  // ---------------------------------------------------------------------------

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
                borderSide:
                    const BorderSide(color: Color(0xFF1B5E20), width: 1.5),
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
            color: isActive ? const Color(0xFF1B5E20) : Colors.grey.shade200,
            shape: BoxShape.circle,
            boxShadow: isActive
                ? [
                    BoxShadow(
                        color: const Color(0xFF1B5E20).withOpacity(0.2),
                        blurRadius: 8)
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
            color: isActive ? const Color(0xFF1B5E20) : Colors.grey,
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
              ? const Color(0xFF1B5E20)
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
              color: const Color(0xFF1B5E20),
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
                borderSide:
                    const BorderSide(color: Color(0xFF1B5E20), width: 1.5),
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
                borderSide:
                    const BorderSide(color: Color(0xFF1B5E20), width: 1.5),
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
