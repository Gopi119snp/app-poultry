import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../services/company_store.dart';
import '../../services/session_service.dart';

class AddFarmerScreenStep2 extends StatefulWidget {
  final Map<String, dynamic> step1Data;

  const AddFarmerScreenStep2({super.key, required this.step1Data});

  @override
  State<AddFarmerScreenStep2> createState() => _AddFarmerScreenStep2State();
}

class _AddFarmerScreenStep2State extends State<AddFarmerScreenStep2> {
  static const Color primaryGreen = Color(0xFF1B5E20);

  final _aadhaarController = TextEditingController();
  final _panController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _accountHolderController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _confirmAccountController = TextEditingController();
  final _ifscController = TextEditingController();

  bool _isLoading = false;
  File? _farmerPhotoFile;
  File? _signaturePhotoFile;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _aadhaarController.addListener(_formatAadhaar);
  }

  void _formatAadhaar() {
    String digits = _aadhaarController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 12) digits = digits.substring(0, 12);
    String formatted = '';
    for (int i = 0; i < digits.length; i++) {
      if (i == 4 || i == 8) formatted += ' ';
      formatted += digits[i];
    }
    if (formatted != _aadhaarController.text) {
      _aadhaarController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  @override
  void dispose() {
    _aadhaarController.removeListener(_formatAadhaar);
    _aadhaarController.dispose();
    _panController.dispose();
    _bankNameController.dispose();
    _accountHolderController.dispose();
    _accountNumberController.dispose();
    _confirmAccountController.dispose();
    _ifscController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isFarmerPhoto) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );
      if (image != null) {
        setState(() {
          if (isFarmerPhoto) {
            _farmerPhotoFile = File(image.path);
          } else {
            _signaturePhotoFile = File(image.path);
          }
        });
      }
    } catch (e) {
      _showError('Photo select nahi ho saki. Dobara try karo.');
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
      icon: const Icon(Icons.error_rounded, color: Colors.white),
    );
  }

  Future<void> _submitFarmer() async {
    // Validations
    final aadhaar = _aadhaarController.text.replaceAll(' ', '').trim();
    if (aadhaar.length != 12 || !RegExp(r'^\d{12}$').hasMatch(aadhaar)) {
      _showError('Aadhaar number 12 digit ka hona chahiye');
      return;
    }

    final pan = _panController.text.trim().toUpperCase();
    if (pan.isNotEmpty &&
        !RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$').hasMatch(pan)) {
      _showError('PAN number sahi format mein daalo — e.g. ABCDE1234F');
      return;
    }

    if (_bankNameController.text.trim().isEmpty) {
      _showError('Bank ka naam daalo');
      return;
    }

    if (_accountHolderController.text.trim().length < 3) {
      _showError('Account holder ka naam daalo');
      return;
    }

    if (_accountNumberController.text.trim().length < 9) {
      _showError('Sahi account number daalo');
      return;
    }

    if (_accountNumberController.text.trim() !=
        _confirmAccountController.text.trim()) {
      _showError('Account number match nahi kar raha');
      return;
    }

    final ifsc = _ifscController.text.trim().toUpperCase();
    if (ifsc.length != 11 || !RegExp(r'^[A-Z]{4}[A-Z0-9]{7}$').hasMatch(ifsc)) {
      _showError('IFSC code 11 characters ka hona chahiye — e.g. UCBA0632884');
      return;
    }

    setState(() => _isLoading = true);

    List<Map<String, dynamic>> farmers =
        await CompanyStore.instance.getJsonList('companyFarmers');

    // ── DUPLICATE CHECK ────────────────────────
    final phone = widget.step1Data['phone'];

    final duplicatePhone = farmers.firstWhere(
      (f) => f['phone'] == phone,
      orElse: () => {},
    );
    if (duplicatePhone.isNotEmpty) {
      setState(() => _isLoading = false);
      _showError(
        'Yeh phone number pehle se registered hai — ${duplicatePhone['name']} ke naam se',
      );
      return;
    }

    final duplicateAadhaar = farmers.firstWhere(
      (f) => f['aadhaar'] == aadhaar,
      orElse: () => {},
    );
    if (duplicateAadhaar.isNotEmpty) {
      setState(() => _isLoading = false);
      _showError(
        'Yeh Aadhaar number pehle se registered hai — ${duplicateAadhaar['name']} ke naam se',
      );
      return;
    }

    final accountNumber = _accountNumberController.text.trim();
    final duplicateAccount = farmers.firstWhere(
      (f) => f['accountNumber'] == accountNumber,
      orElse: () => {},
    );
    if (duplicateAccount.isNotEmpty) {
      setState(() => _isLoading = false);
      _showError(
        'Yeh account number pehle se registered hai — ${duplicateAccount['name']} ke naam se',
      );
      return;
    }
    // ──────────────────────────────────────────

    final farmerData = {
      ...widget.step1Data,
      'aadhaar': aadhaar,
      'pan': pan,
      'bankName': _bankNameController.text.trim(),
      'accountHolder': _accountHolderController.text.trim(),
      'accountNumber': accountNumber,
      'ifsc': ifsc,
      'hasPhoto': _farmerPhotoFile != null,
      'hasSignature': _signaturePhotoFile != null,
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'registeredOn': DateTime.now().toIso8601String(),
      'status': 'active',
    };

    farmers.add(farmerData);
    await CompanyStore.instance.saveJsonList('companyFarmers', farmers);

    final companyId = await SessionService.companyId;
    if (companyId != null) {
      await CompanyStore.instance.registerPhoneLookup(
        phone: phone as String,
        companyId: companyId,
        role: 'Company Farmer',
        displayName: widget.step1Data['name'] as String? ?? '',
      );
    }

    setState(() => _isLoading = false);

    if (!mounted) return;

    Get.snackbar(
      '✅ Farmer Registered!',
      '${widget.step1Data['name']} ka profile ban gaya!',
      backgroundColor: primaryGreen,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.all(15),
    );

    // ── FIX: Direct Farmers list pe wapas (Using Native Navigator to bypass open GetX snackbars overlay context) ──────
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    // NATIVE POP: Yeh GetX ke open overlays se atke bina direct Step 2 ko pop kar ke Step 1 ko signal bhej dega
    Navigator.of(context).pop(true);
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
              const SizedBox(height: 16),
              _buildStep1Summary(),
              const SizedBox(height: 20),

              // ── DOCUMENTS ──────────────────────────
              _sectionLabel('🪪 DOCUMENTS'),
              const SizedBox(height: 14),

              _buildInput(
                controller: _aadhaarController,
                label: 'Aadhaar Number *',
                hint: '1234 5678 9012',
                icon: Icons.credit_card_rounded,
                keyboardType: TextInputType.number,
                maxLength: 14,
              ),

              _buildInput(
                controller: _panController,
                label: 'PAN Number (Optional)',
                hint: 'e.g. ABCDE1234F',
                icon: Icons.badge_rounded,
                maxLength: 10,
              ),

              _buildLabel('Farmer ki Photo'),
              const SizedBox(height: 8),
              _buildPhotoUpload(
                label: 'Photo Upload Karo',
                icon: Icons.add_a_photo_rounded,
                imageFile: _farmerPhotoFile,
                onTap: () => _pickImage(true),
              ),
              const SizedBox(height: 16),

              _buildLabel('Signature / Thumb Print Photo'),
              const SizedBox(height: 8),
              _buildPhotoUpload(
                label: 'Signature ya Thumb Upload Karo',
                icon: Icons.fingerprint_rounded,
                imageFile: _signaturePhotoFile,
                onTap: () => _pickImage(false),
              ),
              const SizedBox(height: 20),

              // ── BANK DETAILS ───────────────────────
              _sectionLabel('🏦 BANK DETAILS'),
              const SizedBox(height: 14),

              _buildInput(
                controller: _bankNameController,
                label: 'Bank ka Naam *',
                hint: 'e.g. State Bank of India',
                icon: Icons.account_balance_rounded,
              ),

              _buildInput(
                controller: _accountHolderController,
                label: 'Account Holder ka Naam *',
                hint: 'e.g. Ramesh Kumar',
                icon: Icons.person_rounded,
              ),

              _buildInput(
                controller: _accountNumberController,
                label: 'Account Number *',
                hint: 'Bank account number',
                icon: Icons.numbers_rounded,
                keyboardType: TextInputType.number,
                maxLength: 18,
              ),

              _buildInput(
                controller: _confirmAccountController,
                label: 'Account Number Confirm Karo *',
                hint: 'Dobara account number daalo',
                icon: Icons.numbers_rounded,
                keyboardType: TextInputType.number,
                maxLength: 18,
              ),

              _buildInput(
                controller: _ifscController,
                label: 'IFSC Code *',
                hint: 'e.g. SBIN0001234 ya UCBA0632884',
                icon: Icons.code_rounded,
                maxLength: 11,
              ),

              Padding(
                padding: const EdgeInsets.only(bottom: 16, top: 2),
                child: Text(
                  '* IFSC code cheque book ya passbook mein milega',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitFarmer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    elevation: 3,
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
                          '✅ Farmer Register Karo',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
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
        _progressStep('Personal &\nLocation', 1, false, true),
        Expanded(child: Container(height: 3, color: primaryGreen)),
        _progressStep('Documents &\nBank', 2, true, false),
      ],
    );
  }

  Widget _progressStep(String label, int step, bool isActive, bool isDone) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isActive || isDone ? primaryGreen : Colors.grey.shade200,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                : Text(
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
            color: isActive || isDone ? primaryGreen : Colors.grey,
            fontWeight: isActive || isDone
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildStep1Summary() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: primaryGreen.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryGreen.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: primaryGreen,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Step 1 Complete ✅',
                style: TextStyle(
                  color: primaryGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _summaryRow('👤 Naam', widget.step1Data['name'] ?? ''),
          _summaryRow('📱 Phone', widget.step1Data['phone'] ?? ''),
          _summaryRow('🎂 DOB', widget.step1Data['dob'] ?? ''),
          _summaryRow(
            '📍 Location',
            '${widget.step1Data['district'] ?? ''}, ${widget.step1Data['state'] ?? ''}',
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoUpload({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    File? imageFile,
  }) {
    final bool isUploaded = imageFile != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 120,
        decoration: BoxDecoration(
          color: isUploaded ? primaryGreen.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUploaded
                ? primaryGreen.withOpacity(0.4)
                : Colors.grey.shade200,
            width: isUploaded ? 1.5 : 1,
          ),
        ),
        child: imageFile != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.file(imageFile, fit: BoxFit.cover),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.grey.shade400, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Gallery se chuniye',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                  ),
                ],
              ),
      ),
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
