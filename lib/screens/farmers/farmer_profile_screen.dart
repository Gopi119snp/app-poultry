import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../services/company_store.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'batch_detail_screen.dart';
import 'batch_create_screen.dart';
import 'farmer_report_screen.dart';

class FarmerProfileScreen extends StatefulWidget {
  final Map<String, dynamic> farmer;
  const FarmerProfileScreen({super.key, required this.farmer});
  @override
  State<FarmerProfileScreen> createState() => _FarmerProfileScreenState();
}

class _FarmerProfileScreenState extends State<FarmerProfileScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);
  int _currentTab = 0;
  bool _hasActiveBatch = false;
  Map<String, dynamic>? _activeBatchData;
  Map<String, dynamic> _currentFarmer = {};
  final _chicksCountController = TextEditingController();
  final _startDateController = TextEditingController();
  bool _isLoading = false;

  // Personal edit controllers
  final _editNameController = TextEditingController();
  final _editDobController = TextEditingController();
  final _editRelationNameController = TextEditingController();
  final _editPhoneController = TextEditingController();
  final _editAadhaarController = TextEditingController();
  final _editPanController = TextEditingController();

  // Location edit controllers
  final _editPinController = TextEditingController();
  final _editStreetController = TextEditingController();
  final _editPanchayatController = TextEditingController();
  final _editPostOfficeController = TextEditingController();
  final _editPoliceStationController = TextEditingController();
  final _editDistrictController = TextEditingController();
  final _editStateController = TextEditingController();

  // Bank edit controllers
  final _editBankNameController = TextEditingController();
  final _editAccountHolderController = TextEditingController();
  final _editAccountNumberController = TextEditingController();
  final _editIfscController = TextEditingController();

  // Cheque duplicate tracking
  List<String> _uploadedChequeNumbers = [];

  @override
  void initState() {
    super.initState();
    _currentFarmer = Map<String, dynamic>.from(widget.farmer);
    _startDateController.text =
        "${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}";
    _checkActiveBatchStatus();
    _loadUploadedChequeNumbers();
  }

  @override
  void dispose() {
    _chicksCountController.dispose();
    _startDateController.dispose();
    _editNameController.dispose();
    _editDobController.dispose();
    _editRelationNameController.dispose();
    _editPhoneController.dispose();
    _editAadhaarController.dispose();
    _editPanController.dispose();
    _editPinController.dispose();
    _editStreetController.dispose();
    _editPanchayatController.dispose();
    _editPostOfficeController.dispose();
    _editPoliceStationController.dispose();
    _editDistrictController.dispose();
    _editStateController.dispose();
    _editBankNameController.dispose();
    _editAccountHolderController.dispose();
    _editAccountNumberController.dispose();
    _editIfscController.dispose();
    super.dispose();
  }

  Future<void> _loadUploadedChequeNumbers() async {
    final farmersList = await CompanyStore.instance.getJsonList(
      'companyFarmers',
    );
    for (var f in farmersList) {
      if (f['id'] == widget.farmer['id']) {
        List<dynamic> saved = f['uploadedChequeNumbers'] ?? [];
        if (!mounted) return;
        setState(() => _uploadedChequeNumbers = saved.cast<String>());
        break;
      }
    }
  }

  int _calculateDaysOld(String startDateStr) {
    try {
      List<String> parts = startDateStr.split('/');
      if (parts.length == 3) {
        DateTime startDate = DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
        int totalDays = DateTime.now().difference(startDate).inDays;
        return totalDays < 0 ? 0 : totalDays;
      }
    } catch (_) {}
    return 0;
  }

  Future<void> _checkActiveBatchStatus() async {
    final farmersList = await CompanyStore.instance.getJsonList(
      'companyFarmers',
    );
    int minLiftingDays =
        await CompanyStore.instance.getInt('minLiftingDays') ?? 23;
    int maxLiftingDays =
        await CompanyStore.instance.getInt('maxLiftingDays') ?? 60;

    Map<String, dynamic>? foundFarmer;
    for (var f in farmersList) {
      if (f['id'] == widget.farmer['id']) {
        foundFarmer = f;
        break;
      }
    }
    if (foundFarmer != null) {
      if (!mounted) return;
      setState(() => _currentFarmer = Map<String, dynamic>.from(foundFarmer!));
      if (_currentFarmer['batches'] != null) {
        final List<dynamic> batches = _currentFarmer['batches'];
        Map<String, dynamic>? activeBatch;
        for (var b in batches) {
          String bStatus = b['status'].toString().toUpperCase();
          if (bStatus == 'ACTIVE' ||
              bStatus == 'LIFTING READY' ||
              bStatus == 'PARTIAL LIFTED') {
            activeBatch = b as Map<String, dynamic>;
            break;
          }
        }
        if (activeBatch != null) {
          if (!mounted) return;
          int daysOld = _calculateDaysOld(activeBatch['startDate'] ?? '');
          if (activeBatch['status'].toString().toUpperCase() == 'ACTIVE' &&
              daysOld >= minLiftingDays &&
              daysOld <= maxLiftingDays) {
            activeBatch['status'] = 'LIFTING READY';
          }
          setState(() {
            _hasActiveBatch = true;
            _activeBatchData = Map<String, dynamic>.from(activeBatch!);
          });
          return;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _hasActiveBatch = false;
      _activeBatchData = null;
    });
  }

  // ── PHOTO & SIGNATURE PICK + SAVE ────────────────────────────────────────
  Future<void> _pickAndSaveProfilePhoto() async {
    if (_isLoading) return;
    try {
      final XFile? f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (f == null) return;
      setState(() => _isLoading = true);
      List<Map<String, dynamic>> list = await CompanyStore.instance.getJsonList(
        'companyFarmers',
      );
      for (var farmer in list) {
        if (farmer['id'] == widget.farmer['id']) {
          farmer['hasPhoto'] = true;
          farmer['photoPath'] = f.path;
          break;
        }
      }
      await CompanyStore.instance.saveJsonList('companyFarmers', list);
      await _checkActiveBatchStatus();
      Get.snackbar(
        'Photo Updated',
        'Profile photo successfully save ho gaya.',
        backgroundColor: primaryGreen,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint('Photo pick error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndSaveSignature() async {
    if (_isLoading) return;
    try {
      final XFile? f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (f == null) return;
      setState(() => _isLoading = true);
      List<Map<String, dynamic>> list = await CompanyStore.instance.getJsonList(
        'companyFarmers',
      );
      for (var farmer in list) {
        if (farmer['id'] == widget.farmer['id']) {
          farmer['hasSignature'] = true;
          farmer['signaturePath'] = f.path;
          break;
        }
      }
      await CompanyStore.instance.saveJsonList('companyFarmers', list);
      await _checkActiveBatchStatus();
      Get.snackbar(
        'Signature Updated',
        'Signature successfully save ho gaya.',
        backgroundColor: primaryGreen,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint('Signature pick error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── BATCH DIALOGS ─────────────────────────────────────────────────────────
  void _showCreateBatchDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Naya Batch Shuru Karo',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _chicksCountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Total Chicks Count *',
                prefixIcon: const Icon(Icons.egg_sharp, color: primaryGreen),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _startDateController,
              decoration: InputDecoration(
                labelText: 'Start Date *',
                prefixIcon: const Icon(
                  Icons.calendar_today_rounded,
                  color: primaryGreen,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: _startNewBatchDataSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Batch Start Karo',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditActiveBatchDialog() {
    if (_activeBatchData == null) return;
    _chicksCountController.text = _activeBatchData!['chicksCount'].toString();
    _startDateController.text = _activeBatchData!['startDate'] ?? '';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: primaryGreen, size: 24),
            SizedBox(width: 8),
            Text(
              'Active Batch Edit Karo',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _chicksCountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Chicks Quantity *',
                prefixIcon: const Icon(Icons.egg_sharp, color: primaryGreen),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _startDateController,
              decoration: InputDecoration(
                labelText: 'Start Date *',
                prefixIcon: const Icon(
                  Icons.calendar_today_rounded,
                  color: primaryGreen,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _chicksCountController.clear();
              Navigator.pop(context);
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: _updateBatchDataSave,
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
            child: const Text(
              'Save Changes',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateBatchDataSave() async {
    String chicksCount = _chicksCountController.text.trim();
    String startDate = _startDateController.text.trim();
    if (chicksCount.isEmpty || int.tryParse(chicksCount) == null) {
      Get.snackbar(
        'Error',
        'Sahi chicks sankhya daalo',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    var farmersList = await CompanyStore.instance.getJsonList('companyFarmers');
    for (var f in farmersList) {
      if (f['id'] == widget.farmer['id']) {
        for (var b in (f['batches'] ?? [])) {
          if (b['id'] == _activeBatchData!['id']) {
            b['chicksCount'] = int.parse(chicksCount);
            b['startDate'] = startDate;
            double rate = double.tryParse(b['chicksRate'].toString()) ?? 40.0;
            b['totalChicksCost'] = (int.parse(chicksCount) * rate)
                .toStringAsFixed(2);
            break;
          }
        }
        break;
      }
    }
    await CompanyStore.instance.saveJsonList('companyFarmers', farmersList);
    _chicksCountController.clear();
    if (!mounted) return;
    Navigator.pop(context);
    await _checkActiveBatchStatus();
    Get.snackbar(
      'Updated',
      'Batch changes saved.',
      backgroundColor: primaryGreen,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  Future<void> _startNewBatchDataSave() async {
    String chicksCount = _chicksCountController.text.trim();
    String startDate = _startDateController.text.trim();
    if (chicksCount.isEmpty || int.tryParse(chicksCount) == null) {
      Get.snackbar(
        'Error',
        'Sahi chicks sankhya daalo',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    var farmersList = await CompanyStore.instance.getJsonList('companyFarmers');
    for (var f in farmersList) {
      if (f['id'] == widget.farmer['id']) {
        if (f['batches'] == null) f['batches'] = [];
        int lotNumber = f['batches'].length + 1;
        String farmerName = f['name'] ?? 'FAR';
        String prefix = farmerName.trim().length >= 3
            ? farmerName.trim().substring(0, 3).toUpperCase()
            : farmerName.trim().toUpperCase().padRight(3, 'X');
        String formattedBatchId =
            '${prefix}001-LOT-${lotNumber.toString().padLeft(3, '0')}';
        f['batches'].add({
          'id': formattedBatchId,
          'batchId': formattedBatchId,
          'lotNumber': lotNumber,
          'chicksCount': int.parse(chicksCount),
          'chicksRate': 40.0,
          'totalChicksCost': (int.parse(chicksCount) * 40.0).toStringAsFixed(2),
          'startDate': startDate,
          'status': 'ACTIVE',
          'dailyEntries': [],
        });
        break;
      }
    }
    await CompanyStore.instance.saveJsonList('companyFarmers', farmersList);
    _chicksCountController.clear();
    if (!mounted) return;
    Navigator.pop(context);
    await _checkActiveBatchStatus();
    Get.snackbar(
      'Success',
      'Naya batch shuru ho gaya!',
      backgroundColor: primaryGreen,
      colorText: Colors.white,
    );
  }

  // ── PERSONAL + LOCATION EDIT DIALOG ──────────────────────────────────────
  void _showEditPersonalDialog() {
    _editNameController.text = _currentFarmer['name'] ?? '';
    _editDobController.text = _currentFarmer['dob'] ?? '';
    _editRelationNameController.text = _currentFarmer['relationName'] ?? '';
    _editPhoneController.text = _currentFarmer['phone'] ?? '';
    _editAadhaarController.text = _currentFarmer['aadhaar'] ?? '';
    _editPanController.text = _currentFarmer['pan'] ?? '';
    _editPinController.text = _currentFarmer['pin'] ?? '';
    _editStreetController.text = _currentFarmer['street'] ?? '';
    _editPanchayatController.text = _currentFarmer['panchayat'] ?? '';
    _editPostOfficeController.text = _currentFarmer['postOffice'] ?? '';
    _editPoliceStationController.text = _currentFarmer['policeStation'] ?? '';
    _editDistrictController.text = _currentFarmer['district'] ?? '';
    _editStateController.text = _currentFarmer['state'] ?? '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_rounded, color: primaryGreen),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Details Edit Karo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: const Text(
                  'Personal Information',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: primaryGreen,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              TextField(
                controller: _editNameController,
                decoration: const InputDecoration(
                  labelText: 'Poora Naam *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _editDobController,
                decoration: const InputDecoration(
                  labelText: 'Date of Birth',
                  prefixIcon: Icon(Icons.cake_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _editRelationNameController,
                decoration: const InputDecoration(
                  labelText: 'Guardian Name',
                  prefixIcon: Icon(Icons.people_outline),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _editPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number *',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _editAadhaarController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Aadhaar Number *',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _editPanController,
                decoration: const InputDecoration(
                  labelText: 'PAN Card',
                  prefixIcon: Icon(Icons.credit_card_outlined),
                ),
              ),
              const SizedBox(height: 18),
              const Divider(height: 1, color: Color(0xFFEEEEEE)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: const Text(
                  'Location Details',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              TextField(
                controller: _editPinController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'PIN Code',
                  prefixIcon: Icon(Icons.pin_drop_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _editStreetController,
                decoration: const InputDecoration(
                  labelText: 'Street / Mohalla',
                  prefixIcon: Icon(Icons.signpost_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _editPanchayatController,
                decoration: const InputDecoration(
                  labelText: 'Panchayat',
                  prefixIcon: Icon(Icons.account_balance_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _editPostOfficeController,
                decoration: const InputDecoration(
                  labelText: 'Post Office',
                  prefixIcon: Icon(Icons.local_post_office_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _editPoliceStationController,
                decoration: const InputDecoration(
                  labelText: 'Police Station',
                  prefixIcon: Icon(Icons.local_police_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _editDistrictController,
                decoration: const InputDecoration(
                  labelText: 'District',
                  prefixIcon: Icon(Icons.map_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _editStateController,
                decoration: const InputDecoration(
                  labelText: 'State',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: _saveEditedPersonalDetails,
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
            child: const Text(
              'Save Details',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveEditedPersonalDetails() async {
    String name = _editNameController.text.trim();
    String phone = _editPhoneController.text.trim();
    String aadhaar = _editAadhaarController.text.trim();
    if (name.isEmpty || phone.isEmpty || aadhaar.isEmpty) {
      Get.snackbar(
        'Error',
        'Naam, Phone aur Aadhaar compulsory hain!',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    try {
      setState(() => _isLoading = true);
      var farmersList = await CompanyStore.instance.getJsonList(
        'companyFarmers',
      );
      for (var f in farmersList) {
        if (f['id'] == widget.farmer['id']) {
          f['name'] = name;
          f['dob'] = _editDobController.text.trim();
          f['relationName'] = _editRelationNameController.text.trim();
          f['phone'] = phone;
          f['aadhaar'] = aadhaar;
          f['pan'] = _editPanController.text.trim().toUpperCase();
          f['pin'] = _editPinController.text.trim();
          f['street'] = _editStreetController.text.trim();
          f['panchayat'] = _editPanchayatController.text.trim();
          f['postOffice'] = _editPostOfficeController.text.trim();
          f['policeStation'] = _editPoliceStationController.text.trim();
          f['district'] = _editDistrictController.text.trim();
          f['state'] = _editStateController.text.trim();
          break;
        }
      }
      await CompanyStore.instance.saveJsonList('companyFarmers', farmersList);
      Navigator.pop(context);
      await _checkActiveBatchStatus();
      Get.snackbar(
        'Saved',
        'Details update ho gayi.',
        backgroundColor: primaryGreen,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint('Personal edit error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── BANK EDIT DIALOG ──────────────────────────────────────────────────────
  void _showEditBankDialog() {
    _editBankNameController.text = _currentFarmer['bankName'] ?? '';
    _editAccountHolderController.text = _currentFarmer['accountHolder'] ?? '';
    _editAccountNumberController.text = _currentFarmer['accountNumber'] ?? '';
    _editIfscController.text = _currentFarmer['ifsc'] ?? '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.account_balance_rounded, color: primaryGreen),
            SizedBox(width: 8),
            Text(
              'Bank Details Edit Karo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _editBankNameController,
                decoration: const InputDecoration(
                  labelText: 'Bank Ka Naam *',
                  prefixIcon: Icon(Icons.account_balance_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _editAccountHolderController,
                decoration: const InputDecoration(
                  labelText: 'Account Holder Name *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _editAccountNumberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Account Number *',
                  prefixIcon: Icon(Icons.numbers_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _editIfscController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'IFSC Code *',
                  prefixIcon: Icon(Icons.code_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: _saveEditedBankDetails,
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
            child: const Text(
              'Save Bank Details',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveEditedBankDetails() async {
    String bankName = _editBankNameController.text.trim();
    String accountHolder = _editAccountHolderController.text.trim();
    String accountNumber = _editAccountNumberController.text.trim();
    String ifsc = _editIfscController.text.trim().toUpperCase();
    if (bankName.isEmpty ||
        accountHolder.isEmpty ||
        accountNumber.isEmpty ||
        ifsc.isEmpty) {
      Get.snackbar(
        'Error',
        'Saari bank fields bharna zaroori hai!',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    try {
      setState(() => _isLoading = true);
      var farmersList = await CompanyStore.instance.getJsonList(
        'companyFarmers',
      );
      for (var f in farmersList) {
        if (f['id'] == widget.farmer['id']) {
          f['bankName'] = bankName;
          f['accountHolder'] = accountHolder;
          f['accountNumber'] = accountNumber;
          f['ifsc'] = ifsc;
          break;
        }
      }
      await CompanyStore.instance.saveJsonList('companyFarmers', farmersList);
      Navigator.pop(context);
      await _checkActiveBatchStatus();
      Get.snackbar(
        'Saved',
        'Bank details update ho gayi.',
        backgroundColor: primaryGreen,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint('Bank edit error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── OCR VALIDATION ENGINE ─────────────────────────────────────────────────
  Future<void> _processImageOcrValidations(
    String statusKey,
    String pathKey,
    String selectedFilePath,
  ) async {
    setState(() => _isLoading = true);
    bool validationPassed = false;
    String blockReason = "Kripya sahi aur saaf document upload karein.";

    try {
      final inputImage = InputImage.fromFilePath(selectedFilePath);
      final textRecognizer = GoogleMlKit.vision.textRecognizer();
      final RecognizedText recognizedText = await textRecognizer.processImage(
        inputImage,
      );
      String extractedText = recognizedText.text.toUpperCase().trim();
      await textRecognizer.close();
      debugPrint("=== OCR TEXT ===\n$extractedText");

      String farmerName = (_currentFarmer['name'] ?? '')
          .toString()
          .toUpperCase()
          .trim();
      if (farmerName.isEmpty) farmerName = "FARMER";

      // AADHAAR FRONT
      if (statusKey == 'hasAadhaarFront') {
        bool hasName =
            extractedText.contains("NAME") ||
            extractedText.contains("\u0928\u093e\u092e");
        bool hasDob =
            extractedText.contains("DOB") ||
            extractedText.contains("DATE OF BIRTH") ||
            extractedText.contains("\u091c\u0928\u094d\u092e");
        bool hasGender =
            extractedText.contains("MALE") ||
            extractedText.contains("FEMALE") ||
            extractedText.contains("GENDER") ||
            extractedText.contains("\u0932\u093f\u0902\u0917");
        bool hasGovt =
            extractedText.contains("GOVERNMENT OF INDIA") ||
            extractedText.contains("GOVT OF INDIA") ||
            extractedText.contains(
              "\u092d\u093e\u0930\u0924 \u0938\u0930\u0915\u093e\u0930",
            ) ||
            extractedText.contains("UNIQUE IDENTIFICATION");
        RegExp rx = RegExp(r'\d{4}\s?\d{4}\s?\d{4}');
        String num = rx.stringMatch(extractedText) ?? "";
        int kw = (hasName ? 1 : 0) + (hasDob ? 1 : 0) + (hasGender ? 1 : 0);
        if (kw >= 2 || hasGovt) {
          validationPassed = true;
          if (num.isNotEmpty)
            _currentFarmer['extractedAadhaarFrontNum'] = num.replaceAll(
              " ",
              "",
            );
        } else {
          blockReason =
              "Aadhaar Front side nahi lag rahi! 'NAME', 'DOB', 'GENDER' keywords nahi mile.";
        }
      }
      // AADHAAR BACK
      else if (statusKey == 'hasAadhaarBack') {
        bool hasAddr =
            extractedText.contains("ADDRESS") ||
            extractedText.contains("\u092a\u0924\u093e") ||
            extractedText.contains("ADDR");
        bool hasFather =
            extractedText.contains("FATHER") ||
            extractedText.contains("S/O") ||
            extractedText.contains("D/O") ||
            extractedText.contains("W/O") ||
            extractedText.contains("\u092a\u093f\u0924\u093e");
        bool hasPin =
            extractedText.contains("PIN") ||
            extractedText.contains("PINCODE") ||
            extractedText.contains("\u092a\u093f\u0928");
        RegExp rx = RegExp(r'\d{4}\s?\d{4}\s?\d{4}');
        String num = rx.stringMatch(extractedText) ?? "";
        int kw = (hasAddr ? 1 : 0) + (hasFather ? 1 : 0) + (hasPin ? 1 : 0);
        if (kw >= 1 || num.isNotEmpty) {
          if (num.isNotEmpty &&
              _currentFarmer['extractedAadhaarFrontNum'] != null) {
            String back = num.replaceAll(" ", "");
            String front = _currentFarmer['extractedAadhaarFrontNum']
                .toString();
            if (back != front) {
              blockReason =
                  "Fraud Alert! Aadhaar Front ($front) aur Back ($back) ka 12-digit number match nahi ho raha!";
            } else {
              validationPassed = true;
            }
          } else {
            validationPassed = kw >= 1;
            if (!validationPassed)
              blockReason =
                  "Aadhaar Back side nahi lag rahi! 'ADDRESS', 'FATHER', 'PIN' keywords nahi mile.";
          }
        } else {
          blockReason =
              "Aadhaar Back side nahi lag rahi! 'ADDRESS', 'FATHER', 'PIN' keywords nahi mile.";
        }
      }
      // PAN CARD
      else if (statusKey == 'hasPanPhoto') {
        bool hasPan =
            RegExp(r'[A-Z]{5}[0-9]{4}[A-Z]{1}').hasMatch(extractedText) ||
            extractedText.contains("INCOME TAX") ||
            extractedText.contains("PERMANENT ACCOUNT") ||
            extractedText.contains("GOVT. OF INDIA");
        List<String> parts = farmerName.split(' ');
        bool nameMatch = parts.any(
          (p) => p.length > 2 && extractedText.contains(p),
        );
        if (hasPan && nameMatch) {
          validationPassed = true;
        } else if (!hasPan) {
          blockReason =
              "Valid PAN Card nahi lag raha! PAN format (ABCDE1234F) ya 'INCOME TAX' keyword nahi mila.";
        } else {
          blockReason =
              "PAN Card par darj naam farmer ke naam ($farmerName) se match nahi ho raha!";
        }
      }
      // 4 BLANK CHEQUES
      else if (statusKey == 'hasChq1' ||
          statusKey == 'hasChq2' ||
          statusKey == 'hasChq3' ||
          statusKey == 'hasChq4') {
        bool isCheque =
            extractedText.contains("BANK") ||
            extractedText.contains("CHEQUE") ||
            extractedText.contains("PAY") ||
            extractedText.contains("IFS") ||
            extractedText.contains("A/C") ||
            extractedText.contains("ACCOUNT");
        if (!isCheque) {
          blockReason =
              "Valid bank cheque leaf nahi hai! 'BANK', 'PAY', 'IFS', 'A/C' keywords nahi mile.";
        } else {
          RegExp rx = RegExp(r'\b(\d{6})\b');
          String chequeNum = "";
          for (var m in rx.allMatches(extractedText)) {
            String c = m.group(1) ?? "";
            if (c != "000000" && c != "123456") {
              chequeNum = c;
              break;
            }
          }
          if (chequeNum.isEmpty) {
            blockReason =
                "Cheque mein 6-digit cheque number nahi mila! Saaf photo kheinchein.";
          } else if (_uploadedChequeNumbers.contains(chequeNum)) {
            blockReason =
                "Duplicate Cheque! Cheque number $chequeNum pehle hi upload ho chuka hai. Naya cheque use karein.";
          } else {
            validationPassed = true;
            _uploadedChequeNumbers.add(chequeNum);
            await _saveChequeNumberToPersistence(chequeNum);
          }
        }
      }
      // PC CHEQUE
      else if (statusKey == 'hasPcCheque') {
        bool isCheque =
            extractedText.contains("BANK") ||
            extractedText.contains("CHEQUE") ||
            extractedText.contains("PAY") ||
            extractedText.contains("IFS") ||
            extractedText.contains("A/C");
        if (!isCheque) {
          blockReason = "Valid bank cheque leaf nahi hai!";
        } else {
          bool hasAmount =
              extractedText.contains("1000") ||
              extractedText.contains("1,000") ||
              extractedText.contains("ONE THOUSAND") ||
              extractedText.contains("RS");
          String? sigPath = _currentFarmer['signaturePath']?.toString();
          bool hasSig =
              sigPath != null &&
              sigPath.isNotEmpty &&
              File(sigPath).existsSync();

          if (!hasSig) {
            setState(() => _isLoading = false);
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    SizedBox(width: 8),
                    Text(
                      'Signature Warning',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                content: const Text(
                  'Personal signature abhi tak upload nahi hua. Pehle Personal tab mein signature upload karein, ya cheque aise hi upload karein.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _commitDocumentDataToPersistence(
                        statusKey,
                        pathKey,
                        selectedFilePath,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                    child: const Text(
                      'Upload Anyway',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
            return;
          } else {
            if (hasAmount) {
              setState(() => _isLoading = false);
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: const Row(
                    children: [
                      Icon(Icons.verified_user_rounded, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        'PC Cheque Confirm Karo',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PC Cheque (Rs.1,000) verify karein:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      const Text('Amount Rs.1,000 detected'),
                      const SizedBox(height: 8),
                      const Text('Confirm karein:'),
                      const SizedBox(height: 6),
                      const Text(
                        '- Farmer ka signature cheque par daala gaya hai?',
                      ),
                      const Text(
                        '- Signature neeche daayein taraf (sahi jagah) par hai?',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Registered Signature:',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 6),
                      if (sigPath != null && File(sigPath).existsSync())
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(sigPath),
                            height: 80,
                            fit: BoxFit.contain,
                          ),
                        ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Reject',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _commitDocumentDataToPersistence(
                          statusKey,
                          pathKey,
                          selectedFilePath,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                      ),
                      child: const Text(
                        'Haan, Signature Sahi Hai',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
              return;
            } else {
              blockReason =
                  "PC Cheque mein Rs.1,000 amount nahi mila! Sahi cheque upload karein.";
            }
          }
        }
      }
      // JAMEEN KA RASID
      else if (statusKey == 'hasLandReceipt') {
        String curYear = DateTime.now().year.toString();
        String prevYear = (DateTime.now().year - 1).toString();
        bool hasYear =
            extractedText.contains(curYear) ||
            extractedText.contains("$prevYear-${curYear.substring(2)}");
        List<String> nameParts = farmerName.split(' ');
        bool hasName = nameParts.any(
          (p) => p.length > 2 && extractedText.contains(p),
        );

        if (hasYear && hasName) {
          validationPassed = true;
        } else {
          setState(() => _isLoading = false);
          String msg = (!hasYear && !hasName)
              ? "Rasiid par:\n- Farmer ka naam ($farmerName) match nahi\n- Current year ($curYear) ka rasiid bhi nahi\n\nDono conditions fail!"
              : !hasYear
              ? "Jameen ka rasid current year ($curYear) ka nahi hai!"
              : "Rasiid par farmer ka naam ($farmerName) match nahi ho raha!";
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => CustomOcrOverridePopup(
              errorMessage: msg,
              onUploadAnyway: () {
                Navigator.pop(ctx);
                _commitDocumentDataToPersistence(
                  statusKey,
                  pathKey,
                  selectedFilePath,
                );
              },
            ),
          );
          return;
        }
      }
      // Default
      else {
        validationPassed = true;
      }

      if (validationPassed) {
        await _commitDocumentDataToPersistence(
          statusKey,
          pathKey,
          selectedFilePath,
        );
      } else {
        Get.snackbar(
          'AI Blocked',
          blockReason,
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(15),
        );
      }
    } catch (e) {
      debugPrint('OCR error: $e');
      Get.snackbar(
        'AI Failure',
        'Document verify nahi ho paya. Saaf photo kheinchein.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveChequeNumberToPersistence(String chequeNum) async {
    var list = await CompanyStore.instance.getJsonList('companyFarmers');
    for (var f in list) {
      if (f['id'] == widget.farmer['id']) {
        List<dynamic> existing = f['uploadedChequeNumbers'] ?? [];
        if (!existing.contains(chequeNum)) existing.add(chequeNum);
        f['uploadedChequeNumbers'] = existing;
        break;
      }
    }
    await CompanyStore.instance.saveJsonList('companyFarmers', list);
  }

  Future<void> _commitDocumentDataToPersistence(
    String statusKey,
    String pathKey,
    String selectedFilePath,
  ) async {
    var list = await CompanyStore.instance.getJsonList('companyFarmers');
    for (var f in list) {
      if (f['id'] == widget.farmer['id']) {
        f[statusKey] = true;
        f[pathKey] = selectedFilePath;
        break;
      }
    }
    await CompanyStore.instance.saveJsonList('companyFarmers', list);
    await _checkActiveBatchStatus();
    Get.snackbar(
      'Success',
      'Document verified aur save ho gaya.',
      backgroundColor: primaryGreen,
      colorText: Colors.white,
    );
  }

  Future<void> _pickAndSaveDocumentPhoto(
    String statusKey,
    String pathKey,
  ) async {
    if (_isLoading) return;
    try {
      final XFile? f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 65,
      );
      if (f != null)
        await _processImageOcrValidations(statusKey, pathKey, f.path);
    } catch (e) {
      debugPrint('Image pick error: $e');
    }
  }

  void _openDocumentLightboxPreview(String localPath, String title) {
    if (localPath.isEmpty || !File(localPath).existsSync()) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.file(File(localPath), fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 40,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(true),
        ),
        title: Text(
          _currentFarmer['name'] ?? 'Farmer Profile',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildProfileHeader(),
              _buildTabBar(),
              Expanded(
                child: _currentTab == 0
                    ? _buildPersonalTab()
                    : _currentTab == 1
                    ? _buildBatchTab()
                    : _currentTab == 2
                    ? _buildDocumentTab()
                    : _currentTab == 3
                    ? _buildBankTab()
                    : _buildReportTab(),
              ),
            ],
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black12,
                child: const Center(
                  child: CircularProgressIndicator(color: primaryGreen),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── PROFILE HEADER — circle tap se photo dekho / change karo ─────────────
  Widget _buildProfileHeader() {
    String? photoPath = _currentFarmer['photoPath']?.toString();
    bool hasPhoto =
        photoPath != null &&
        photoPath.isNotEmpty &&
        File(photoPath).existsSync();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        color: primaryGreen,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          // CIRCLE — tap = lightbox, long press = change photo
          GestureDetector(
            onTap: () {
              if (hasPhoto) {
                _openDocumentLightboxPreview(photoPath!, 'Profile Photo');
              } else {
                _pickAndSaveProfilePhoto();
              }
            },
            onLongPress: _pickAndSaveProfilePhoto,
            child: Stack(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white54, width: 2),
                  ),
                  child: ClipOval(
                    child: hasPhoto
                        ? Image.file(
                            File(photoPath!),
                            fit: BoxFit.cover,
                            width: 68,
                            height: 68,
                          )
                        : Center(
                            child: Text(
                              (_currentFarmer['name'] as String? ?? 'F')[0]
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                  ),
                ),
                // Camera icon badge
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: primaryGreen, width: 1.5),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 12,
                      color: primaryGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentFarmer['name'] ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '  ${_currentFarmer['phone'] ?? ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '  ${_currentFarmer['district'] ?? ''}, ${_currentFarmer['state'] ?? ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white38),
                  ),
                  child: Text(
                    _currentFarmer['status'] == 'active'
                        ? 'Active Farmer'
                        : 'Inactive',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: Row(
        children: [
          _buildTabItem('Personal', 0),
          _buildTabItem('Batch', 1),
          _buildTabItem('Document', 2),
          _buildTabItem('Bank', 3),
          _buildTabItem('Report', 4),
        ],
      ),
    );
  }

  Widget _buildTabItem(String label, int index) {
    final isActive = _currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? primaryGreen : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? primaryGreen : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  // ── PERSONAL TAB ──────────────────────────────────────────────────────────
  Widget _buildPersonalTab() {
    String? photoPath = _currentFarmer['photoPath']?.toString();
    bool hasPhoto =
        photoPath != null &&
        photoPath.isNotEmpty &&
        File(photoPath).existsSync();
    String? sigPath = _currentFarmer['signaturePath']?.toString();
    bool hasSig =
        sigPath != null && sigPath.isNotEmpty && File(sigPath).existsSync();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Farmer Identity Baseline',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                  fontSize: 12,
                ),
              ),
              TextButton.icon(
                onPressed: _showEditPersonalDialog,
                icon: const Icon(
                  Icons.edit_rounded,
                  size: 14,
                  color: primaryGreen,
                ),
                label: const Text(
                  'Edit Details',
                  style: TextStyle(
                    color: primaryGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _infoCard(
            title: 'Personal Information',
            children: [
              _infoRow('Poora Naam', _currentFarmer['name'] ?? '-'),
              _infoRow('Date of Birth', _currentFarmer['dob'] ?? '-'),
              _infoRow(
                '${_currentFarmer['relation'] ?? 'Relation'} ka Naam',
                _currentFarmer['relationName'] ?? '-',
              ),
              _infoRow('Phone', _currentFarmer['phone'] ?? '-'),
              _infoRow(
                'Aadhaar',
                _formatAadhaar(_currentFarmer['aadhaar'] ?? ''),
              ),
              _infoRow(
                'PAN',
                _currentFarmer['pan']?.isNotEmpty == true
                    ? _currentFarmer['pan']
                    : 'N/A',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _infoCard(
            title: 'Location',
            children: [
              _infoRow('PIN Code', _currentFarmer['pin'] ?? '-'),
              _infoRow('Street/Mohalla', _currentFarmer['street'] ?? '-'),
              _infoRow('Panchayat', _currentFarmer['panchayat'] ?? '-'),
              _infoRow(
                'Post Office',
                _currentFarmer['postOffice']?.isNotEmpty == true
                    ? _currentFarmer['postOffice']
                    : 'N/A',
              ),
              _infoRow(
                'Police Station',
                _currentFarmer['policeStation']?.isNotEmpty == true
                    ? _currentFarmer['policeStation']
                    : 'N/A',
              ),
              _infoRow('District', _currentFarmer['district'] ?? '-'),
              _infoRow('State', _currentFarmer['state'] ?? '-'),
            ],
          ),
          const SizedBox(height: 16),

          // Registration Details — Photo + Signature inline edit
          _infoCard(
            title: 'Registration Details',
            children: [
              _infoRow('Farmer ID', _currentFarmer['id'] ?? '-'),
              _infoRow(
                'Registered On',
                _formatDate(_currentFarmer['registeredOn'] ?? ''),
              ),
              _infoRow(
                'Status',
                _currentFarmer['status'] == 'active' ? 'Active' : 'Inactive',
              ),

              // PHOTO ROW — tap to view, button to change
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade100, width: 1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 130,
                          child: Text(
                            'Photo',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            hasPhoto ? 'Uploaded' : 'Not uploaded',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: hasPhoto
                                  ? Colors.green.shade700
                                  : Colors.red.shade400,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (hasPhoto) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () => _openDocumentLightboxPreview(
                          photoPath!,
                          'Farmer Photo',
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(photoPath!),
                            height: 100,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _pickAndSaveProfilePhoto,
                        icon: const Icon(
                          Icons.add_a_photo_outlined,
                          size: 14,
                          color: primaryGreen,
                        ),
                        label: Text(
                          hasPhoto ? 'Change Photo' : 'Upload Photo',
                          style: const TextStyle(
                            fontSize: 12,
                            color: primaryGreen,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // SIGNATURE ROW — tap to view, button to change
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 130,
                          child: Text(
                            'Signature',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            hasSig ? 'Uploaded' : 'Not uploaded',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: hasSig
                                  ? Colors.green.shade700
                                  : Colors.red.shade400,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (hasSig) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () => _openDocumentLightboxPreview(
                          sigPath!,
                          'Farmer Signature',
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              File(sigPath!),
                              height: 80,
                              width: double.infinity,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _pickAndSaveSignature,
                        icon: const Icon(
                          Icons.draw_outlined,
                          size: 14,
                          color: primaryGreen,
                        ),
                        label: Text(
                          hasSig ? 'Change Signature' : 'Upload Signature',
                          style: const TextStyle(
                            fontSize: 12,
                            color: primaryGreen,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── BATCH TAB ─────────────────────────────────────────────────────────────
  Widget _buildBatchTab() {
    final batches =
        (_currentFarmer['batches'] as List?)?.cast<Map<String, dynamic>>() ??
        [];
    final closedBatches = batches.where((b) {
      String s = b['status'].toString().toUpperCase();
      return s == 'CLOSED' || s == 'COMPLETED';
    }).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Active Batch',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (_hasActiveBatch)
                      IconButton(
                        icon: const Icon(
                          Icons.edit_note_rounded,
                          color: primaryGreen,
                          size: 22,
                        ),
                        onPressed: _showEditActiveBatchDialog,
                      ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _hasActiveBatch
                            ? Colors.green.shade100
                            : Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _hasActiveBatch
                            ? _activeBatchData!['status']
                                  .toString()
                                  .toUpperCase()
                            : 'Koi batch nahi',
                        style: TextStyle(
                          color: _hasActiveBatch
                              ? Colors.green.shade800
                              : Colors.orange.shade800,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_hasActiveBatch && _activeBatchData != null) ...[
                  _batchInfoRow(
                    'Batch ID',
                    _activeBatchData!['batchId'] ?? '-',
                  ),
                  _batchInfoRow(
                    'Chicks Count',
                    '${_activeBatchData!['chicksCount']} birds',
                  ),
                  _batchInfoRow(
                    'Start Date',
                    _activeBatchData!['startDate'] ?? '-',
                  ),
                  _batchInfoRow(
                    'Chicks Cost',
                    'Rs.${_activeBatchData!['totalChicksCost'] ?? '0'}',
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await Get.to(
                          () => BatchDetailScreen(
                            farmerId: _currentFarmer['id'] ?? '',
                            batchData: _activeBatchData!,
                            userRole: 'Owner',
                          ),
                        );
                        // Hamesha refresh karo — chahe result kuch bhi ho
                        await _checkActiveBatchStatus();
                      },
                      icon: const Icon(Icons.bar_chart_rounded, size: 18),
                      label: const Text(
                        'Batch Detail Dekho',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Center(
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        const Text(
                          'Is farmer ki abhi koi active batch nahi hai',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Neeche button se naya batch shuru karo',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final result = await Get.to(
                              () => BatchCreateScreen(farmer: _currentFarmer),
                            );
                            if (result == true) {
                              await _checkActiveBatchStatus();
                              if (_hasActiveBatch && _activeBatchData != null) {
                                Get.to(
                                  () => BatchDetailScreen(
                                    farmerId: _currentFarmer['id'] ?? '',
                                    batchData: _activeBatchData!,
                                    userRole: 'Owner',
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(
                            Icons.add,
                            size: 18,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Naya Batch Shuru Karo',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
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
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Batch History (${closedBatches.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                if (closedBatches.isEmpty)
                  Center(
                    child: Text(
                      'Abhi koi closed batch nahi hai',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                    ),
                  )
                else
                  ...closedBatches.map((b) => _closedBatchCard(b)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _batchInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _closedBatchCard(Map<String, dynamic> batch) {
    return GestureDetector(
      onTap: () {
        Get.to(
          () => BatchDetailScreen(
            farmerId: _currentFarmer['id'] ?? '',
            batchData: batch,
            userRole: 'Owner',
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_rounded, color: Colors.grey, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batch['batchId'] ?? '-',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${batch['chicksCount']} birds — ${batch['startDate']}',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: const Text(
                    'COMPLETED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Settlement Rasid Button ──────────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Get.to(
                    () => BatchDetailScreen(
                      farmerId: _currentFarmer['id'] ?? '',
                      batchData: batch,
                      userRole: 'Owner',
                    ),
                  );
                },
                icon: const Icon(
                  Icons.receipt_long_rounded,
                  size: 16,
                  color: primaryGreen,
                ),
                label: const Text(
                  'Settlement Rasid Dekho',
                  style: TextStyle(
                    fontSize: 12,
                    color: primaryGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: primaryGreen),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── DOCUMENT TAB ──────────────────────────────────────────────────────────
  Widget _buildDocumentTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _infoCard(
            title: 'Onboarding Verification Checklist',
            children: [
              _buildDocumentItem(
                '1. Aadhaar Card (Front Side)',
                'hasAadhaarFront',
                'aadhaarFrontPath',
              ),
              _buildDocumentItem(
                '1b. Aadhaar Card (Back Side)',
                'hasAadhaarBack',
                'aadhaarBackPath',
              ),
              _buildDocumentItem('2. PAN Card', 'hasPanPhoto', 'panPhotoPath'),
              _buildDocumentItem(
                '3. Passport Size Photo',
                'hasPassportPhoto',
                'passportPhotoPath',
              ),
              _buildDocumentItem(
                '4a. Security Cheque Leaf 1',
                'hasChq1',
                'chq1Path',
              ),
              _buildDocumentItem(
                '4b. Security Cheque Leaf 2',
                'hasChq2',
                'chq2Path',
              ),
              _buildDocumentItem(
                '4c. Security Cheque Leaf 3',
                'hasChq3',
                'chq3Path',
              ),
              _buildDocumentItem(
                '4d. Security Cheque Leaf 4',
                'hasChq4',
                'chq4Path',
              ),
              _buildDocumentItem(
                '5. PC Cheque (Rs.1,000 + Sign)',
                'hasPcCheque',
                'pcChequePath',
              ),
              _buildDocumentItem(
                '6. Jameen Ka Rasid (Current Year)',
                'hasLandReceipt',
                'landReceiptPath',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentItem(String label, String statusKey, String pathKey) {
    bool isUploaded = _currentFarmer[statusKey] == true;
    String? imgPath = _currentFarmer[pathKey]?.toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade100, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isUploaded ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isUploaded
                        ? Colors.green.shade200
                        : Colors.red.shade200,
                  ),
                ),
                child: Text(
                  isUploaded ? 'Uploaded' : 'Pending',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isUploaded
                        ? Colors.green.shade800
                        : Colors.red.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              if (isUploaded && imgPath != null)
                _openDocumentLightboxPreview(imgPath, label);
              else
                _pickAndSaveDocumentPhoto(statusKey, pathKey);
            },
            child:
                imgPath != null &&
                    imgPath.isNotEmpty &&
                    File(imgPath).existsSync()
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(imgPath),
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () =>
                              _pickAndSaveDocumentPhoto(statusKey, pathKey),
                          icon: const Icon(
                            Icons.refresh_rounded,
                            size: 14,
                            color: primaryGreen,
                          ),
                          label: const Text(
                            'Change / Re-upload',
                            style: TextStyle(
                              fontSize: 11,
                              color: primaryGreen,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.add_a_photo_outlined,
                          size: 24,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tap karke Gallery se load karein',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ── BANK TAB ──────────────────────────────────────────────────────────────
  Widget _buildBankTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Bank Account Info',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                  fontSize: 12,
                ),
              ),
              TextButton.icon(
                onPressed: _showEditBankDialog,
                icon: const Icon(
                  Icons.edit_rounded,
                  size: 14,
                  color: primaryGreen,
                ),
                label: const Text(
                  'Edit Bank Details',
                  style: TextStyle(
                    color: primaryGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _infoCard(
            title: 'Bank Details',
            children: [
              _infoRow('Bank Naam', _currentFarmer['bankName'] ?? '-'),
              _infoRow(
                'Account Holder',
                _currentFarmer['accountHolder'] ?? '-',
              ),
              _infoRow(
                'Account Number',
                _maskAccountNumber(_currentFarmer['accountNumber'] ?? ''),
              ),
              _infoRow('IFSC Code', _currentFarmer['ifsc'] ?? '-'),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text(
                      'Farmer Ledger',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.black87,
                      ),
                    ),
                    Spacer(),
                    Text(
                      'Coming Soon',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryGreen.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: primaryGreen.withOpacity(0.2)),
                  ),
                  child: const Text(
                    'Batch complete hone ke baad farmer ka poora hisaab yahan dikhega:\n\n- Chicks + Feed + Medicine (Debit)\n- Sale + FCR Bonus (Credit)\n- Net Settlement (Final Payment)',
                    style: TextStyle(
                      fontSize: 12,
                      color: primaryGreen,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── REPORT TAB ────────────────────────────────────────────────────────────
  Widget _buildReportTab() {
    return FarmerReportScreen(farmer: _currentFarmer);
  }

  // ── HELPER WIDGETS ─────────────────────────────────────────────────────────
  Widget _infoCard({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Colors.black54,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  String _formatAadhaar(String a) {
    if (a.length != 12) return a;
    return '${a.substring(0, 4)} ${a.substring(4, 8)} ${a.substring(8, 12)}';
  }

  String _maskAccountNumber(String acc) {
    if (acc.length <= 4) return acc;
    return '${'X' * (acc.length - 4)}${acc.substring(acc.length - 4)}';
  }

  String _formatDate(String isoDate) {
    if (isoDate.isEmpty) return '-';
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }
}

// ── CUSTOM OCR OVERRIDE POPUP ─────────────────────────────────────────────
class CustomOcrOverridePopup extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onUploadAnyway;
  const CustomOcrOverridePopup({
    super.key,
    required this.errorMessage,
    required this.onUploadAnyway,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.report_problem_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text(
            'AI Document Alert',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Text(errorMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          ),
        ),
        ElevatedButton(
          onPressed: onUploadAnyway,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          child: const Text(
            'Upload Anyway',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
