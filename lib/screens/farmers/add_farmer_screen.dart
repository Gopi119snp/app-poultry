import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'add_farmer_screen_step2.dart';

class AddFarmerScreen extends StatefulWidget {
  const AddFarmerScreen({super.key});

  @override
  State<AddFarmerScreen> createState() => _AddFarmerScreenState();
}

class _AddFarmerScreenState extends State<AddFarmerScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);

  // Controllers
  final _nameController = TextEditingController();
  final _dobController = TextEditingController();
  final _phoneController = TextEditingController();
  final _relationNameController = TextEditingController();
  final _pinController = TextEditingController();
  final _streetController = TextEditingController();
  final _panchayatController = TextEditingController();
  final _postOfficeController = TextEditingController();
  final _policeStationController = TextEditingController();
  final _districtController = TextEditingController();
  final _stateController = TextEditingController();

  String? _selectedRelation;
  String? _selectedState;
  bool _isLoadingPin = false;

  final List<String> _relations = ['Father', 'Mother', 'Wife', 'Husband'];

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

  @override
  void initState() {
    super.initState();
    _pinController.addListener(_onPinChanged);
    _dobController.addListener(_onDobChanged);
  }

  void _onPinChanged() {
    if (_pinController.text.trim().length == 6 && !_isLoadingPin) {
      _fetchAddressFromPin(_pinController.text.trim());
    }
  }

  // DOB auto format — user digits daalega, automatic / lagega
  void _onDobChanged() {
    String value = _dobController.text;
    // Sirf digits nikalo
    String digits = value.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.length > 8) digits = digits.substring(0, 8);

    String formatted = '';
    for (int i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) formatted += '/';
      formatted += digits[i];
    }

    if (formatted != _dobController.text) {
      _dobController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  @override
  void dispose() {
    _pinController.removeListener(_onPinChanged);
    _dobController.removeListener(_onDobChanged);
    _nameController.dispose();
    _dobController.dispose();
    _phoneController.dispose();
    _relationNameController.dispose();
    _pinController.dispose();
    _streetController.dispose();
    _panchayatController.dispose();
    _postOfficeController.dispose();
    _policeStationController.dispose();
    _districtController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  Future<void> _fetchAddressFromPin(String pin) async {
    if (!mounted) return;
    setState(() => _isLoadingPin = true);
    try {
      final response = await http.get(
        Uri.parse('https://api.postalpincode.in/pincode/$pin'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data[0]['Status'] == 'Success') {
          final details = data[0]['PostOffice'][0];
          if (mounted) {
            setState(() {
              _districtController.text = details['District'];
              // Post Office autofill band — user khud dalega
              _stateController.text = details['State'];
              if (_states.contains(details['State'])) {
                _selectedState = details['State'];
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('PIN fetch error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPin = false);
    }
  }

  void _showError(String msg) {
    Get.snackbar(
      'Error',
      msg,
      backgroundColor: Colors.red.shade600,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(15),
    );
  }

  // FIXED: Is function ko async banakar native pop mapping ke liye handle kiya hai
  void _goToStep2() async {
    if (_nameController.text.trim().length < 3) {
      _showError('Farmer ka naam kam se kam 3 characters ka hona chahiye');
      return;
    }
    // DOB validate — DD/MM/YYYY format check
    final dob = _dobController.text;
    if (dob.length != 10) {
      _showError('Date of Birth poori daalo — DD/MM/YYYY');
      return;
    }
    if (_selectedRelation == null) {
      _showError('Relation type chuniye');
      return;
    }
    if (_relationNameController.text.trim().length < 3) {
      _showError('Relation ka naam kam se kam 3 characters');
      return;
    }
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(_phoneController.text.trim())) {
      _showError('Sahi phone number daalo — 10 digit');
      return;
    }
    if (_pinController.text.length != 6) {
      _showError('PIN code 6 digit ka hona chahiye');
      return;
    }
    if (_streetController.text.trim().length < 3) {
      _showError('Street/Mohalla daalo');
      return;
    }
    if (_panchayatController.text.trim().isEmpty) {
      _showError('Panchayat daalo');
      return;
    }
    if (_districtController.text.isEmpty) {
      _showError('Sahi PIN code daalo taaki District auto-fill ho');
      return;
    }

    final step1Data = {
      'name': _nameController.text.trim(),
      'dob': _dobController.text,
      'relation': _selectedRelation,
      'relationName': _relationNameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'pin': _pinController.text.trim(),
      'street': _streetController.text.trim(),
      'panchayat': _panchayatController.text.trim(),
      'postOffice': _postOfficeController.text.trim(),
      'policeStation': _policeStationController.text.trim(),
      'district': _districtController.text,
      'state': _stateController.text,
    };

    // FIXED: Native push kiya taaki context route clean rahe aur result await ho sake
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddFarmerScreenStep2(step1Data: step1Data),
      ),
    );

    // Agar Step 2 se success result (true) aata hai, toh Step 1 khud ko natively close karke Farmers tab par wapas bhej dega
    if (result == true) {
      if (!mounted) return;
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        title: const Text(
          'Farmer Add Karo',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProgress(),
              const SizedBox(height: 24),

              // ── PERSONAL INFO ────────────────======
              _sectionLabel('👤 PERSONAL INFORMATION'),
              const SizedBox(height: 14),

              _buildInput(
                controller: _nameController,
                label: 'Farmer ka Poora Naam *',
                hint: 'e.g. Ramesh Kumar',
                icon: Icons.person_rounded,
              ),

              // DOB — auto format
              _buildLabel('Date of Birth *'),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  controller: _dobController,
                  keyboardType: TextInputType.number,
                  maxLength: 10,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'DDMMYYYY likhte jaao',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      Icons.calendar_today_rounded,
                      color: Colors.grey.shade400,
                      size: 20,
                    ),
                    helperText: 'Sirf numbers daalo — / automatic aayega',
                    helperStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 11,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    counterText: '',
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

              // Relation Type
              _buildLabel('Relation Type *'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedRelation,
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    Icons.people_rounded,
                    color: Colors.grey.shade400,
                    size: 20,
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
                    borderSide: const BorderSide(
                      color: primaryGreen,
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                ),
                hint: Text(
                  'Chuniye',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                ),
                items: _relations
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(r, style: const TextStyle(fontSize: 13)),
                      ),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedRelation = val),
              ),
              const SizedBox(height: 16),

              _buildInput(
                controller: _relationNameController,
                label: 'Relation ka Naam *',
                hint: 'e.g. Suresh Kumar',
                icon: Icons.person_outline_rounded,
              ),

              _buildInput(
                controller: _phoneController,
                label: 'Phone Number *',
                hint: '10 digit mobile number',
                icon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                maxLength: 10,
              ),

              const SizedBox(height: 8),

              // ── LOCATION ───────────────────────────
              _sectionLabel('📍 LOCATION INFORMATION'),
              const SizedBox(height: 14),

              _buildInput(
                controller: _pinController,
                label: 'PIN Code *',
                hint: 'e.g. 800001',
                icon: Icons.pin_drop_rounded,
                keyboardType: TextInputType.number,
                maxLength: 6,
                suffix: _isLoadingPin
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),

              _buildInput(
                controller: _districtController,
                label: 'District (Auto-fill)',
                hint: 'PIN code daalte hi aayega',
                icon: Icons.location_city_rounded,
                enabled: false,
              ),

              // State Dropdown
              _buildLabel('State *'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedState,
                isExpanded: true,
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    Icons.map_rounded,
                    color: Colors.grey.shade400,
                    size: 20,
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
                    borderSide: const BorderSide(
                      color: primaryGreen,
                      width: 1.5,
                    ),
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
                onChanged: (val) {
                  setState(() {
                    _selectedState = val;
                    _stateController.text = val ?? '';
                  });
                },
              ),
              const SizedBox(height: 16),

              _buildInput(
                controller: _streetController,
                label: 'Street / Mohalla *',
                hint: 'e.g. Gandhi Nagar',
                icon: Icons.signpost_rounded,
              ),

              _buildInput(
                controller: _panchayatController,
                label: 'Panchayat *',
                hint: 'e.g. Rampur Panchayat',
                icon: Icons.account_balance_rounded,
              ),

              _buildInput(
                controller: _postOfficeController,
                label: 'Post Office',
                hint: 'e.g. Ballia Bazar',
                icon: Icons.local_post_office_rounded,
                enabled: true,
              ),

              _buildInput(
                controller: _policeStationController,
                label: 'Police Station',
                hint: 'e.g. Kotwali',
                icon: Icons.local_police_rounded,
              ),

              const SizedBox(height: 8),

              // Action trigger button layout element placement
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _goToStep2,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Aage Badhein — Step 2 →',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ── HELPER WIDGETS ─────────────────────────

  Widget _buildProgress() {
    return Row(
      children: [
        _progressStep('Personal &\nLocation', 1, true),
        Expanded(child: Container(height: 3, color: Colors.grey.shade200)),
        _progressStep('Documents &\nBank', 2, false),
      ],
    );
  }

  Widget _progressStep(String label, int step, bool isActive) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isActive ? primaryGreen : Colors.grey.shade200,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$step',
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            color: isActive ? primaryGreen : Colors.grey,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: primaryGreen.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primaryGreen.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: primaryGreen,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.black54,
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    bool enabled = true,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel(label),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
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
                borderSide: const BorderSide(color: primaryGreen, width: 1.5),
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
}
