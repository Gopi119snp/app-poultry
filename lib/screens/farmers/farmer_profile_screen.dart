import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../services/company_store.dart';
import '../../services/activity_logger.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'batch_detail_screen.dart';
import 'batch_create_screen.dart';
import 'farmer_report_screen.dart';
import '../../services/permission_service.dart';
import '../../services/session_service.dart';

class FarmerProfileScreen extends StatefulWidget {
  final Map<String, dynamic> farmer;
  const FarmerProfileScreen({super.key, required this.farmer});
  @override
  State<FarmerProfileScreen> createState() => _FarmerProfileScreenState();
}

class _FarmerProfileScreenState extends State<FarmerProfileScreen>
    with CloudSyncMixin {
  // ✅ FIX: added with CloudSyncMixin
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
  // ✅ FIX: holds the OCR-detected cheque number until the document commit
  // actually succeeds — prevents "consuming" a number on a failed save.
  String? _pendingChequeNumberForCommit;
  String? _pendingChequeStatusKeyForCommit;

  // ── 🔐 PERMISSION FLAGS ─────────────────────────────────────────────────
  bool _permissionsLoaded = false;
  bool _canViewProfile = false;
  bool _canEditProfile = false;
  bool _canViewBank = false;
  bool _canEditBank = false;
  bool _canViewBatchTab = false;
  bool _canAddBatch = false;
  bool _canEditBatch = false;
  bool _canViewReportTab = false;

  @override
  void initState() {
    super.initState();
    _currentFarmer = Map<String, dynamic>.from(widget.farmer);
    _startDateController.text =
        "${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}";
    _checkActiveBatchStatus();
    _loadUploadedChequeNumbers();
    _loadPermissionFlags();
    startCloudSync(); // ✅ FIX
  }

  @override
  void onCloudDataChanged() {
    // ✅ FIX
    _checkActiveBatchStatus();
    // ✅ FIX — permission flags bhi real-time refresh honi chahiye, warna
    // agar Owner Settings se kisi tab/button ka access ON/OFF karta hai
    // jab manager ye screen pehle se khole hue hai, to change turant nahi
    // dikhta tha (screen band karke dobara kholne par hi update hota tha).
    _loadPermissionFlags();
  }

  Future<void> _loadPermissionFlags() async {
    final viewProfile = await PermissionService.can('farmerProfile', 'view');
    final editProfile = await PermissionService.can('farmerProfile', 'edit');
    final viewBank = await PermissionService.can('farmerBankDetail', 'view');
    final editBank = await PermissionService.can('farmerBankDetail', 'edit');
    final viewBatch = await PermissionService.can('batchCreate', 'view');
    final addBatch = await PermissionService.can('batchCreate', 'add');
    final editBatch = await PermissionService.can('batchCreate', 'edit');
    final viewReport = await PermissionService.can('farmerReportGroup', 'view');

    if (!mounted) return;
    setState(() {
      _canViewProfile = viewProfile;
      _canEditProfile = editProfile;
      _canViewBank = viewBank;
      _canEditBank = editBank;
      _canViewBatchTab = viewBatch;
      _canAddBatch = addBatch;
      _canEditBatch = editBatch;
      _canViewReportTab = viewReport;
      _permissionsLoaded = true;
    });
  }

  // ✅ FIX — is farmer_profile_screen mein har jagah BatchDetailScreen ko
  // call karte waqt userRole: 'Owner' hardcoded tha, chahe actual logged-in
  // session kuch bhi ho. Ab yeh asli session role (SessionService) se aata
  // hai, taaki BatchDetailScreen ke andar PermissionService.can() calls
  // (jo SessionService.currentRole dekhte hain) UI label se match karein
  // aur "By: Owner" dikhne ke bawajood buttons galti se na chupein.
  Future<String> _resolveUserRoleForNavigation() async {
    final role = await SessionService.normalizedRole;
    return role ?? 'Owner';
  }

  List<MapEntry<String, Widget Function()>> _buildVisibleTabs() {
    final List<MapEntry<String, Widget Function()>> tabs = [];
    if (_canViewProfile) tabs.add(MapEntry('Personal', _buildPersonalTab));
    if (_canViewBatchTab) tabs.add(MapEntry('Batch', _buildBatchTab));
    if (_canViewProfile) tabs.add(MapEntry('Document', _buildDocumentTab));
    if (_canViewBank) tabs.add(MapEntry('Bank', _buildBankTab));
    if (_canViewReportTab) tabs.add(MapEntry('Report', _buildReportTab));
    return tabs;
  }

  @override
  void dispose() {
    stopCloudSync(); // ✅ FIX — ye ek line add karo, baaki sab waisa hi rahega
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

  // ── ✅ FIX: Centralized field validators (loophole fixes for weak/absent validation) ──
  bool _isValidPhone(String phone) {
    return RegExp(r'^[6-9]\d{9}$').hasMatch(phone.trim());
  }

  bool _isValidAadhaar(String aadhaar) {
    final a = aadhaar.trim();
    if (!RegExp(r'^\d{12}$').hasMatch(a)) return false;
    // Block obviously fake repeated-digit numbers e.g. 000000000000, 111111111111
    if (RegExp(r'^(\d)\1{11}$').hasMatch(a)) return false;
    return true;
  }

  bool _isValidPan(String pan) {
    if (pan.trim().isEmpty) return true; // PAN optional field
    return RegExp(
      r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$',
    ).hasMatch(pan.trim().toUpperCase());
  }

  bool _isValidIfsc(String ifsc) {
    return RegExp(
      r'^[A-Z]{4}0[A-Z0-9]{6}$',
    ).hasMatch(ifsc.trim().toUpperCase());
  }

  bool _isValidAccountNumber(String acc) {
    final a = acc.trim();
    return RegExp(r'^\d{9,18}$').hasMatch(a);
  }

  bool _isValidPin(String pin) {
    if (pin.trim().isEmpty) return true; // PIN optional field
    return RegExp(r'^[1-9]\d{5}$').hasMatch(pin.trim());
  }

  bool _isValidDobText(String dob) {
    if (dob.trim().isEmpty) return true; // DOB optional field
    try {
      DateTime? parsed;
      final parts = dob.trim().split('/');
      if (parts.length == 3) {
        parsed = DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
        // reject if normalization changed the date (e.g. 31/02/2020 auto-rolls over)
        if (parsed.day != int.parse(parts[0]) ||
            parsed.month != int.parse(parts[1]) ||
            parsed.year != int.parse(parts[2])) {
          return false;
        }
      } else {
        parsed = DateTime.tryParse(dob.trim());
        if (parsed == null) return false;
      }
      final now = DateTime.now();
      if (parsed.isAfter(now)) return false; // future DOB not allowed
      final age = now.difference(parsed).inDays / 365.25;
      if (age > 120) return false; // impossible age
      return true;
    } catch (_) {
      return false;
    }
  }

  /// ✅ FIX: Strict start-date validator — rejects free text, invalid/rolled-over
  /// dates, and future dates. Returns parsed DateTime or null if invalid.
  DateTime? _parseStrictDdMmYyyy(String input) {
    final parts = input.trim().split('/');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    if (m < 1 ||
        m > 12 ||
        d < 1 ||
        d > 31 ||
        y < 2015 ||
        y > DateTime.now().year + 1) {
      return null;
    }
    final dt = DateTime(y, m, d);
    // Dart auto-normalizes invalid dates (e.g. 31/02) — detect and reject that.
    if (dt.day != d || dt.month != m || dt.year != y) return null;
    if (dt.isAfter(DateTime.now()))
      return null; // batch start date can't be in future
    return dt;
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
        // ✅ FIX: detect (not silently ignore) more than one open batch — data
        // corruption / race-condition signal. We still surface only the first
        // one in the UI (no UI change), but we no longer pretend it's normal.
        List<Map<String, dynamic>> openBatches = batches
            .where((b) {
              String s = b['status'].toString().toUpperCase();
              return s == 'ACTIVE' ||
                  s == 'LIFTING READY' ||
                  s == 'PARTIAL LIFTED';
            })
            .cast<Map<String, dynamic>>()
            .toList();
        if (openBatches.length > 1) {
          debugPrint(
            '⚠️ DATA INTEGRITY WARNING: Farmer ${_currentFarmer['id']} has '
            '${openBatches.length} simultaneously-open batches. Only the first '
            'will be treated as the active batch until this is corrected.',
          );
        }
        Map<String, dynamic>? activeBatch = openBatches.isNotEmpty
            ? openBatches.first
            : null;
        if (activeBatch != null) {
          if (!mounted) return;
          int daysOld = _calculateDaysOld(activeBatch['startDate'] ?? '');
          String currentStatus = activeBatch['status'].toString().toUpperCase();
          String? newStatus;
          if (currentStatus == 'ACTIVE' &&
              daysOld >= minLiftingDays &&
              daysOld <= maxLiftingDays) {
            newStatus = 'LIFTING READY';
          } else if ((currentStatus == 'ACTIVE' ||
                  currentStatus == 'LIFTING READY') &&
              daysOld > maxLiftingDays) {
            // ✅ FIX: batches that blow past maxLiftingDays no longer stay
            // ACTIVE/LIFTING READY forever — flagged so office can act on it.
            newStatus = 'OVERDUE';
          }
          if (newStatus != null && newStatus != activeBatch['status']) {
            activeBatch['status'] = newStatus;
            // ✅ FIX: persist the status change immediately instead of only
            // holding it in memory (previous code changed status in-memory
            // but never called saveJsonList, so storage stayed stale).
            for (var f in farmersList) {
              if (f['id'] == widget.farmer['id']) {
                for (var b in (f['batches'] ?? [])) {
                  if (b['id'] == activeBatch['id']) {
                    b['status'] = newStatus;
                    break;
                  }
                }
                break;
              }
            }
            await CompanyStore.instance.saveJsonList(
              'companyFarmers',
              farmersList,
            );
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
      if (f == null || !mounted) return; // ✅ FIX: mounted check after await
      setState(() => _isLoading = true);
      List<Map<String, dynamic>> list = await CompanyStore.instance.getJsonList(
        'companyFarmers',
      );
      bool found = false;
      for (var farmer in list) {
        if (farmer['id'] == widget.farmer['id']) {
          farmer['hasPhoto'] = true;
          farmer['photoPath'] = f.path;
          found = true;
          break;
        }
      }
      if (!found) {
        // ✅ FIX: don't show success if farmer record wasn't actually found
        if (!mounted) return;
        Get.snackbar(
          'Error',
          'Farmer record nahi mila. Photo save nahi hui.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }
      await CompanyStore.instance.saveJsonList('companyFarmers', list);

      // 🛑 NAYA CODE: Activity Logger
      ActivityLogger.log(
        actionType: 'UPDATE',
        module: 'Farmer',
        message:
            'Farmer "${_currentFarmer['name']}" ki profile photo update ki gayi.',
      );
      // 🛑 END NAYA CODE

      await _checkActiveBatchStatus();
      if (!mounted) return;
      Get.snackbar(
        'Photo Updated',
        'Profile photo successfully save ho gaya.',
        backgroundColor: primaryGreen,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint('Photo pick error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndSaveSignature() async {
    if (_isLoading) return;
    try {
      final XFile? f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (f == null || !mounted) return; // ✅ FIX: mounted check after await
      setState(() => _isLoading = true);
      List<Map<String, dynamic>> list = await CompanyStore.instance.getJsonList(
        'companyFarmers',
      );
      bool found = false;
      for (var farmer in list) {
        if (farmer['id'] == widget.farmer['id']) {
          farmer['hasSignature'] = true;
          farmer['signaturePath'] = f.path;
          found = true;
          break;
        }
      }
      if (!found) {
        if (!mounted) return;
        Get.snackbar(
          'Error',
          'Farmer record nahi mila. Signature save nahi hui.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }
      await CompanyStore.instance.saveJsonList('companyFarmers', list);

      // 🛑 NAYA CODE: Activity Logger
      ActivityLogger.log(
        actionType: 'UPDATE',
        module: 'Farmer',
        message:
            'Farmer "${_currentFarmer['name']}" ka signature update kiya gaya.',
      );
      // 🛑 END NAYA CODE

      await _checkActiveBatchStatus();
      if (!mounted) return;
      Get.snackbar(
        'Signature Updated',
        'Signature successfully save ho gaya.',
        backgroundColor: primaryGreen,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint('Signature pick error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
    int? parsedChicks = int.tryParse(chicksCount);
    // ✅ FIX: reject 0 / negative chicks count (old check only verified it parsed)
    if (chicksCount.isEmpty || parsedChicks == null || parsedChicks <= 0) {
      Get.snackbar(
        'Error',
        'Chicks sankhya 0 ya negative nahi ho sakti. Sahi sankhya daalo.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    // ✅ FIX: strict date validation — rejects free text/invalid/future dates
    // that used to silently become "day-0" in age calculations.
    final parsedDate = _parseStrictDdMmYyyy(startDate);
    if (parsedDate == null) {
      Get.snackbar(
        'Error',
        'Start Date sahi format (DD/MM/YYYY) mein aur valid honi chahiye. Future date allowed nahi hai.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    var farmersList = await CompanyStore.instance.getJsonList('companyFarmers');
    bool farmerFound = false;
    bool batchFound = false;
    bool blockedHasEntries = false;
    for (var f in farmersList) {
      if (f['id'] == widget.farmer['id']) {
        farmerFound = true;
        for (var b in (f['batches'] ?? [])) {
          if (b['id'] == _activeBatchData!['id']) {
            batchFound = true;
            // ✅ FIX: once daily entries (mortality/feed/sale/medicine) exist
            // against this batch, chicksCount/startDate can no longer be
            // silently edited — that used to corrupt historical accounting.
            final List<dynamic> entries = b['dailyEntries'] ?? [];
            final bool countChanged =
                b['chicksCount'].toString() != parsedChicks.toString();
            final bool dateChanged = (b['startDate'] ?? '') != startDate;
            if (entries.isNotEmpty && (countChanged || dateChanged)) {
              blockedHasEntries = true;
              break;
            }
            b['chicksCount'] = parsedChicks;
            b['startDate'] = startDate;
            double rate = double.tryParse(b['chicksRate'].toString()) ?? 40.0;
            b['totalChicksCost'] = (parsedChicks * rate).toStringAsFixed(2);
            break;
          }
        }
        break;
      }
    }

    if (!farmerFound || !batchFound) {
      Get.snackbar(
        'Error',
        'Farmer ya batch record nahi mila. Changes save nahi hui.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    if (blockedHasEntries) {
      Get.snackbar(
        'Edit Blocked',
        'Is batch mein already daily entries (mortality/feed/sale) darj ho chuki hain, '
            'isliye Chicks Count ya Start Date ab change nahi ki ja sakti — isse '
            'accounting galat ho jaati hai.',
        backgroundColor: Colors.orange.shade700,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
      return;
    }

    await CompanyStore.instance.saveJsonList('companyFarmers', farmersList);

    // 🛑 NAYA CODE: Activity Logger
    ActivityLogger.log(
      actionType: 'EDIT',
      module: 'Batch',
      message:
          'Farmer "${_currentFarmer['name']}" ka batch details update kiya gaya: $parsedChicks birds, Start: $startDate.',
    );
    // 🛑 END NAYA CODE

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
    int? parsedChicks = int.tryParse(chicksCount);
    // ✅ FIX: reject 0 / negative chicks count
    if (chicksCount.isEmpty || parsedChicks == null || parsedChicks <= 0) {
      Get.snackbar(
        'Error',
        'Chicks sankhya 0 ya negative nahi ho sakti. Sahi sankhya daalo.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    // ✅ FIX: strict date validation
    final parsedDate = _parseStrictDdMmYyyy(startDate);
    if (parsedDate == null) {
      Get.snackbar(
        'Error',
        'Start Date sahi format (DD/MM/YYYY) mein aur valid honi chahiye. Future date allowed nahi hai.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    var farmersList = await CompanyStore.instance.getJsonList('companyFarmers');
    bool farmerFound = false;
    bool blockedActiveExists = false;

    // ✅ FIX: configurable chicks rate instead of hard-coded 40.0 — falls back
    // to 40.0 only if admin hasn't configured a rate yet. Using SharedPreferences
    // directly here since it mirrors how minLiftingDays/maxLiftingDays are read
    // elsewhere in this codebase, and avoids assuming a CompanyStore.getDouble API.
    double configuredChicksRate = 40.0;
    try {
      final prefs = await SharedPreferences.getInstance();
      configuredChicksRate = prefs.getDouble('defaultChicksRate') ?? 40.0;
    } catch (_) {}

    for (var f in farmersList) {
      if (f['id'] == widget.farmer['id']) {
        farmerFound = true;
        if (f['batches'] == null) f['batches'] = [];

        // ✅ FIX: guard against a second active batch being created for the
        // same farmer (e.g. via double-tap / stale UI state) — this method
        // used to add a batch unconditionally with no such check.
        bool alreadyHasOpenBatch = (f['batches'] as List).any((b) {
          String s = b['status'].toString().toUpperCase();
          return s == 'ACTIVE' ||
              s == 'LIFTING READY' ||
              s == 'PARTIAL LIFTED' ||
              s == 'OVERDUE';
        });
        if (alreadyHasOpenBatch) {
          blockedActiveExists = true;
          break;
        }

        int lotNumber = f['batches'].length + 1;
        // ✅ FIX: batch ID prefix now derived from the farmer's permanent ID
        // (not the editable name), so renaming the farmer later no longer
        // makes old/new batch IDs inconsistent, and collisions between two
        // farmers with the same first-3-letters can no longer happen.
        String farmerIdPart = (f['id'] ?? 'FAR').toString();
        String idSeed = farmerIdPart.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
        String prefix = idSeed.length >= 3
            ? idSeed.substring(0, 3).toUpperCase()
            : idSeed.toUpperCase().padRight(3, 'X');
        String formattedBatchId =
            '${prefix}-LOT-${lotNumber.toString().padLeft(3, '0')}-${DateTime.now().millisecondsSinceEpoch % 100000}';
        f['batches'].add({
          'id': formattedBatchId,
          'batchId': formattedBatchId,
          'lotNumber': lotNumber,
          'chicksCount': parsedChicks,
          'chicksRate': configuredChicksRate,
          'totalChicksCost': (parsedChicks * configuredChicksRate)
              .toStringAsFixed(2),
          'startDate': startDate,
          'status': 'ACTIVE',
          'dailyEntries': [],
        });
        break;
      }
    }

    if (!farmerFound) {
      Get.snackbar(
        'Error',
        'Farmer record nahi mila. Batch create nahi hua.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    if (blockedActiveExists) {
      Get.snackbar(
        'Batch Already Active',
        'Is farmer ki ek batch already active hai. Ek farmer ki ek hi active batch ho sakti hai.',
        backgroundColor: Colors.orange.shade700,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
      return;
    }

    await CompanyStore.instance.saveJsonList('companyFarmers', farmersList);

    // 🛑 NAYA CODE: Activity Logger
    ActivityLogger.log(
      actionType: 'ADD',
      module: 'Batch',
      message:
          'Farmer "${_currentFarmer['name']}" ke liye naya batch shuru kiya gaya: $parsedChicks birds.',
    );
    // 🛑 END NAYA CODE

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
    String pan = _editPanController.text.trim().toUpperCase();
    String pin = _editPinController.text.trim();
    String dob = _editDobController.text.trim();

    if (name.isEmpty || phone.isEmpty || aadhaar.isEmpty) {
      Get.snackbar(
        'Error',
        'Naam, Phone aur Aadhaar compulsory hain!',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    // ✅ FIX: real field-format validation (previously only checked "not empty")
    if (!_isValidPhone(phone)) {
      Get.snackbar(
        'Error',
        'Phone number valid 10-digit Indian mobile number hona chahiye (6-9 se shuru).',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    if (!_isValidAadhaar(aadhaar)) {
      Get.snackbar(
        'Error',
        'Aadhaar number 12 digit ka valid number hona chahiye.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    if (!_isValidPan(pan)) {
      Get.snackbar(
        'Error',
        'PAN format sahi nahi hai. Sahi format: ABCDE1234F',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    if (!_isValidPin(pin)) {
      Get.snackbar(
        'Error',
        'PIN Code 6-digit valid number hona chahiye.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    if (!_isValidDobText(dob)) {
      Get.snackbar(
        'Error',
        'Date of Birth valid honi chahiye — future date ya impossible age allowed nahi hai.',
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
      bool farmerFound = false;
      for (var f in farmersList) {
        if (f['id'] == widget.farmer['id']) {
          farmerFound = true;

          // ✅ FIX: duplicate identity check across other farmers (phone/aadhaar/pan)
          for (var other in farmersList) {
            if (other['id'] == f['id']) continue;
            if ((other['phone'] ?? '').toString().trim() == phone) {
              throw 'DUPLICATE_PHONE';
            }
            if ((other['aadhaar'] ?? '').toString().trim() == aadhaar) {
              throw 'DUPLICATE_AADHAAR';
            }
            if (pan.isNotEmpty &&
                (other['pan'] ?? '').toString().trim().toUpperCase() == pan) {
              throw 'DUPLICATE_PAN';
            }
          }

          // ✅ FIX: if identity-critical fields (name/aadhaar/pan) change,
          // previously-verified KYC documents no longer match the new baseline
          // — reset their verification flags so office knows to re-verify.
          bool nameChanged = (f['name'] ?? '').toString().trim() != name;
          bool aadhaarChanged =
              (f['aadhaar'] ?? '').toString().trim() != aadhaar;
          bool panChanged =
              (f['pan'] ?? '').toString().trim().toUpperCase() != pan;

          if (nameChanged || aadhaarChanged) {
            f['hasAadhaarFront'] = false;
            f['hasAadhaarBack'] = false;
            f['extractedAadhaarFrontNum'] = null;
          }
          if (nameChanged || panChanged) {
            f['hasPanPhoto'] = false;
          }

          f['name'] = name;
          f['dob'] = dob;
          f['relationName'] = _editRelationNameController.text.trim();
          f['phone'] = phone;
          f['aadhaar'] = aadhaar;
          f['pan'] = pan;
          f['pin'] = pin;
          f['street'] = _editStreetController.text.trim();
          f['panchayat'] = _editPanchayatController.text.trim();
          f['postOffice'] = _editPostOfficeController.text.trim();
          f['policeStation'] = _editPoliceStationController.text.trim();
          f['district'] = _editDistrictController.text.trim();
          f['state'] = _editStateController.text.trim();

          if (nameChanged || aadhaarChanged || panChanged) {
            f['identityLastEditedOn'] = DateTime.now().toIso8601String();
          }
          break;
        }
      }

      if (!farmerFound) {
        Get.snackbar(
          'Error',
          'Farmer record nahi mila. Details save nahi hui.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      await CompanyStore.instance.saveJsonList('companyFarmers', farmersList);

      // 🛑 NAYA CODE: Activity Logger
      ActivityLogger.log(
        actionType: 'EDIT',
        module: 'Farmer',
        message: 'Farmer "$name" ki personal details update ki gayin.',
      );
      // 🛑 END NAYA CODE

      if (!mounted) return;
      Navigator.pop(context);
      await _checkActiveBatchStatus();
      Get.snackbar(
        'Saved',
        'Details update ho gayi.',
        backgroundColor: primaryGreen,
        colorText: Colors.white,
      );
    } catch (e) {
      String msg = 'Details save nahi ho payi.';
      if (e == 'DUPLICATE_PHONE') {
        msg =
            'Ye Phone number kisi aur farmer ke record mein already registered hai!';
      } else if (e == 'DUPLICATE_AADHAAR') {
        msg =
            'Ye Aadhaar number kisi aur farmer ke record mein already registered hai!';
      } else if (e == 'DUPLICATE_PAN') {
        msg =
            'Ye PAN number kisi aur farmer ke record mein already registered hai!';
      } else {
        debugPrint('Personal edit error: $e');
      }
      Get.snackbar(
        'Error',
        msg,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
    // ✅ FIX: real IFSC/account-number format validation (previously only "not empty")
    if (!_isValidIfsc(ifsc)) {
      Get.snackbar(
        'Error',
        'IFSC Code format sahi nahi hai. Sahi format: ABCD0123456',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    if (!_isValidAccountNumber(accountNumber)) {
      Get.snackbar(
        'Error',
        'Account Number 9-18 digit ka valid number hona chahiye.',
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
      bool farmerFound = false;
      for (var f in farmersList) {
        if (f['id'] == widget.farmer['id']) {
          farmerFound = true;

          bool accountChanged =
              (f['accountNumber'] ?? '').toString().trim() != accountNumber;
          bool ifscChanged =
              (f['ifsc'] ?? '').toString().trim().toUpperCase() != ifsc;

          // ✅ FIX: if bank account/IFSC changes, previously-verified security
          // cheques and PC cheque no longer correspond to the new account —
          // reset their verification flags instead of leaving them "Uploaded".
          if (accountChanged || ifscChanged) {
            f['hasChq1'] = false;
            f['hasChq2'] = false;
            f['hasChq3'] = false;
            f['hasChq4'] = false;
            f['hasPcCheque'] = false;
            f['bankLastEditedOn'] = DateTime.now().toIso8601String();
          }

          f['bankName'] = bankName;
          f['accountHolder'] = accountHolder;
          f['accountNumber'] = accountNumber;
          f['ifsc'] = ifsc;
          break;
        }
      }

      if (!farmerFound) {
        Get.snackbar(
          'Error',
          'Farmer record nahi mila. Bank details save nahi hui.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      await CompanyStore.instance.saveJsonList('companyFarmers', farmersList);

      // 🛑 NAYA CODE: Activity Logger
      ActivityLogger.log(
        actionType: 'EDIT',
        module: 'Farmer',
        message:
            'Farmer "${_currentFarmer['name']}" ki bank details update ki gayin: Bank "$bankName".',
      );
      // 🛑 END NAYA CODE

      if (!mounted) return;
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
      Get.snackbar(
        'Error',
        'Bank details save nahi ho payi.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );
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
        String num = rx.stringMatch(extractedText)?.replaceAll(" ", "") ?? "";
        int kw = (hasName ? 1 : 0) + (hasDob ? 1 : 0) + (hasGender ? 1 : 0);

        // ✅ FIX: previously `kw >= 2 || hasGovt` meant a single "GOVERNMENT OF
        // INDIA" phrase alone (found on many unrelated govt documents) was
        // enough to pass. Now BOTH a real Aadhaar-number pattern AND at least
        // one genuine ID keyword are required, and the 12-digit number must
        // actually be extractable and match the farmer's registered Aadhaar.
        String registeredAadhaar = (_currentFarmer['aadhaar'] ?? '')
            .toString()
            .trim();
        bool hasStrongKeywordSignal = kw >= 2 && hasGovt;
        if (num.isEmpty) {
          blockReason =
              "Aadhaar Front par 12-digit Aadhaar number clearly nahi mila. Saaf photo kheinchein.";
        } else if (!hasStrongKeywordSignal) {
          blockReason =
              "Aadhaar Front side nahi lag rahi! 'NAME', 'DOB', 'GENDER' aur Govt-of-India marker sab zaroori hain.";
        } else if (registeredAadhaar.isNotEmpty && num != registeredAadhaar) {
          blockReason =
              "Ye Aadhaar card is farmer ka registered Aadhaar number ($registeredAadhaar) se match nahi karta! "
              "Kisi aur vyakti ka Aadhaar upload kiya gaya lagta hai.";
        } else {
          validationPassed = true;
          _currentFarmer['extractedAadhaarFrontNum'] = num;
          // ✅ FIX: persist immediately so re-opening the screen doesn't lose
          // this value and silently bypass Aadhaar Back cross-matching.
          await _persistFarmerField('extractedAadhaarFrontNum', num);
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
        String num = rx.stringMatch(extractedText)?.replaceAll(" ", "") ?? "";
        int kw = (hasAddr ? 1 : 0) + (hasFather ? 1 : 0) + (hasPin ? 1 : 0);

        // ✅ FIX: previously ANY single keyword (even without the 12-digit
        // number) could pass Aadhaar Back — meaning almost any address proof
        // would be accepted. Now: (1) front must already be verified & its
        // number persisted, (2) back must yield the same 12-digit number, and
        // (3) at least one genuine back-side keyword must also be present.
        if (_currentFarmer['extractedAadhaarFrontNum'] == null ||
            _currentFarmer['extractedAadhaarFrontNum'].toString().isEmpty) {
          blockReason =
              "Pehle Aadhaar Front side verify/upload karein — uske baad hi Back verify ho sakti hai.";
        } else if (num.isEmpty) {
          blockReason =
              "Aadhaar Back par 12-digit Aadhaar number clearly nahi mila. Saaf photo kheinchein.";
        } else if (kw < 1) {
          blockReason =
              "Aadhaar Back side nahi lag rahi! 'ADDRESS', 'FATHER', 'PIN' keywords nahi mile.";
        } else {
          String front = _currentFarmer['extractedAadhaarFrontNum'].toString();
          if (num != front) {
            blockReason =
                "Fraud Alert! Aadhaar Front ($front) aur Back ($num) ka 12-digit number match nahi ho raha!";
          } else {
            validationPassed = true;
          }
        }
      }
      // PAN CARD
      else if (statusKey == 'hasPanPhoto') {
        RegExp panRx = RegExp(r'[A-Z]{5}[0-9]{4}[A-Z]{1}');
        String? ocrPan = panRx.stringMatch(extractedText);
        bool hasPan =
            ocrPan != null ||
            extractedText.contains("INCOME TAX") ||
            extractedText.contains("PERMANENT ACCOUNT") ||
            extractedText.contains("GOVT. OF INDIA");
        // ✅ FIX: previously ANY single 3+ char fragment of the name (e.g. just
        // a common surname like "KUMAR") was enough to "match". Now require
        // BOTH the first name-part AND the last name-part to individually
        // appear in the OCR text (much harder to false-positive on).
        List<String> parts = farmerName
            .split(' ')
            .where((p) => p.trim().isNotEmpty)
            .toList();
        bool nameMatch;
        if (parts.length >= 2) {
          nameMatch =
              extractedText.contains(parts.first) &&
              extractedText.contains(parts.last);
        } else if (parts.length == 1) {
          nameMatch =
              parts.first.length > 2 && extractedText.contains(parts.first);
        } else {
          nameMatch = false;
        }

        String registeredPan = (_currentFarmer['pan'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        if (!hasPan) {
          blockReason =
              "Valid PAN Card nahi lag raha! PAN format (ABCDE1234F) ya 'INCOME TAX' keyword nahi mila.";
        } else if (!nameMatch) {
          blockReason =
              "PAN Card par darj naam farmer ke poore naam ($farmerName) se match nahi ho raha!";
        } else if (registeredPan.isNotEmpty &&
            ocrPan != null &&
            ocrPan != registeredPan) {
          blockReason =
              "Ye PAN card is farmer ke registered PAN ($registeredPan) se match nahi karta!";
        } else {
          validationPassed = true;
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
          } else {
            // ✅ FIX: duplicate check is now COMPANY-WIDE (across all farmers),
            // not just this farmer's own uploaded list — a cheque re-used on
            // a different farmer profile is now also caught.
            bool isDuplicate = await _isChequeNumberDuplicateCompanyWide(
              chequeNum,
            );
            if (isDuplicate) {
              blockReason =
                  "Duplicate Cheque! Cheque number $chequeNum pehle hi kisi record mein upload ho chuka hai. Naya cheque use karein.";
            } else {
              validationPassed = true;
              // ✅ FIX: cheque number is no longer reserved here before the
              // document is actually committed — it's saved inside
              // _commitDocumentDataToPersistence only after a successful
              // save, so a failed commit can no longer "consume" a number
              // without ever storing the document.
              _pendingChequeNumberForCommit = chequeNum;
              _pendingChequeStatusKeyForCommit = statusKey;
            }
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
              // ✅ FIX: bare "RS" used to count as an amount match by itself
              // (e.g. any cheque with just "Rs." printed on it would pass).
              // Now require "RS" to be immediately followed by 1000/1,000.
              RegExp(r'RS\.?\s*1[,]?000\b').hasMatch(extractedText);
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

  /// ✅ FIX: generic single-field persistence helper with farmer-not-found
  /// detection (previously several save paths would silently do nothing and
  /// still show a success message when the farmer record couldn't be found).
  Future<bool> _persistFarmerField(String key, dynamic value) async {
    var list = await CompanyStore.instance.getJsonList('companyFarmers');
    bool found = false;
    for (var f in list) {
      if (f['id'] == widget.farmer['id']) {
        f[key] = value;
        found = true;
        break;
      }
    }
    if (found) {
      await CompanyStore.instance.saveJsonList('companyFarmers', list);
    } else {
      debugPrint(
        '⚠️ _persistFarmerField: farmer ${widget.farmer['id']} not found — "$key" not saved.',
      );
    }
    return found;
  }

  /// ✅ FIX: company-wide duplicate check — a cheque re-used across two
  /// different farmer profiles is now caught (previously each farmer only
  /// checked their own uploaded list, so a cheque leaf photo re-used on a
  /// second farmer's profile would sail through).
  Future<bool> _isChequeNumberDuplicateCompanyWide(String chequeNum) async {
    final list = await CompanyStore.instance.getJsonList('companyFarmers');
    for (var f in list) {
      List<dynamic> nums = f['uploadedChequeNumbers'] ?? [];
      if (nums.map((e) => e.toString()).contains(chequeNum)) return true;
    }
    return false;
  }

  /// ✅ FIX: called only from inside a successful _commitDocumentDataToPersistence
  /// (i.e. after the document itself is actually saved) — so a cheque number
  /// can never be "consumed" by a commit that ultimately failed. Also removes
  /// the old number for that specific slot before storing the new one, so
  /// replacing a cheque photo doesn't leave a stale duplicate entry behind.
  Future<void> _saveChequeNumberToPersistence(
    String chequeNum,
    String slotKey,
  ) async {
    var list = await CompanyStore.instance.getJsonList('companyFarmers');
    for (var f in list) {
      if (f['id'] == widget.farmer['id']) {
        List<dynamic> existing = f['uploadedChequeNumbers'] ?? [];
        // ✅ FIX: per-slot mapping so we know which number belonged to which
        // of the 4 cheque leaf slots — needed to clean up on replace.
        Map<String, dynamic> slotMap = Map<String, dynamic>.from(
          f['chequeSlotNumbers'] ?? {},
        );
        String? oldNumberForSlot = slotMap[slotKey]?.toString();
        if (oldNumberForSlot != null && oldNumberForSlot != chequeNum) {
          existing.remove(oldNumberForSlot);
        }
        if (!existing.contains(chequeNum)) existing.add(chequeNum);
        slotMap[slotKey] = chequeNum;
        f['uploadedChequeNumbers'] = existing;
        f['chequeSlotNumbers'] = slotMap;
        break;
      }
    }
    await CompanyStore.instance.saveJsonList('companyFarmers', list);
    if (mounted) {
      setState(() {
        _uploadedChequeNumbers = List<String>.from(
          (list.firstWhere(
                    (f) => f['id'] == widget.farmer['id'],
                    orElse: () => {},
                  )['uploadedChequeNumbers'] ??
                  [])
              .map((e) => e.toString()),
        );
      });
    }
  }

  Future<void> _commitDocumentDataToPersistence(
    String statusKey,
    String pathKey,
    String selectedFilePath,
  ) async {
    var list = await CompanyStore.instance.getJsonList('companyFarmers');
    bool found = false;
    for (var f in list) {
      if (f['id'] == widget.farmer['id']) {
        f[statusKey] = true;
        f[pathKey] = selectedFilePath;
        found = true;
        break;
      }
    }

    if (!found) {
      // ✅ FIX: previously this loop would just do nothing and the caller
      // would still show a "Success" snackbar even though nothing was saved.
      Get.snackbar(
        'Error',
        'Farmer record nahi mila. Document save nahi hua.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      // Clear any pending cheque number so it isn't accidentally consumed later.
      _pendingChequeNumberForCommit = null;
      _pendingChequeStatusKeyForCommit = null;
      return;
    }

    await CompanyStore.instance.saveJsonList('companyFarmers', list);

    // 🛑 NAYA CODE: Activity Logger
    ActivityLogger.log(
      actionType: 'UPDATE',
      module: 'Farmer',
      message:
          'Farmer "${_currentFarmer['name']}" ka document ($statusKey) verify aur upload kiya gaya.',
    );
    // 🛑 END NAYA CODE

    // ✅ FIX: cheque number is only written to the duplicate-tracking list
    // here — i.e. only after the document itself has been successfully
    // committed to storage — not earlier at OCR-pass time.
    if (_pendingChequeNumberForCommit != null &&
        _pendingChequeStatusKeyForCommit == statusKey) {
      await _saveChequeNumberToPersistence(
        _pendingChequeNumberForCommit!,
        statusKey,
      );
      _pendingChequeNumberForCommit = null;
      _pendingChequeStatusKeyForCommit = null;
    }

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
    if (!_permissionsLoaded) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(backgroundColor: primaryGreen, elevation: 0),
        body: const Center(
          child: CircularProgressIndicator(color: primaryGreen),
        ),
      );
    }

    final visibleTabs = _buildVisibleTabs();
    final safeIndex = visibleTabs.isEmpty
        ? 0
        : _currentTab.clamp(0, visibleTabs.length - 1);

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
              _buildTabBar(visibleTabs, safeIndex),
              Expanded(
                child: visibleTabs.isEmpty
                    ? Center(
                        child: Text(
                          'Is farmer ke liye koi permission nahi hai.',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    : visibleTabs[safeIndex].value(),
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

  Widget _buildTabBar(
    List<MapEntry<String, Widget Function()>> visibleTabs,
    int safeIndex,
  ) {
    return Container(
      color: Colors.white,
      child: Row(
        children: List.generate(visibleTabs.length, (i) {
          return _buildTabItem(visibleTabs[i].key, i, safeIndex);
        }),
      ),
    );
  }

  Widget _buildTabItem(String label, int index, int safeIndex) {
    final isActive = safeIndex == index;
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
              if (_canEditProfile)
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
              // ✅ FIX: ab yahan naya readable "farmerId" (jaise SIN-RAM-1234)
              // dikhega. Purane farmers jinke paas ye field nahi hai unke
              // liye safe fallback purane 'id' (timestamp) par chala jaata
              // hai, taaki koi crash ya khaali value na dikhe.
              _infoRow(
                'Farmer ID',
                (_currentFarmer['farmerId'] ?? _currentFarmer['id'] ?? '-')
                    .toString(),
              ),
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
                    if (_canEditProfile)
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
                    if (_canEditProfile)
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
                    if (_hasActiveBatch && _canEditBatch)
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
                        // ✅ FIX — hardcoded 'Owner' hata ke asli session
                        // role use kar rahe hain, taaki BatchDetailScreen
                        // ke andar permission checks UI role se match karein.
                        final role = await _resolveUserRoleForNavigation();
                        await Get.to(
                          () => BatchDetailScreen(
                            farmerId: _currentFarmer['id'] ?? '',
                            batchData: _activeBatchData!,
                            userRole: role,
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
                        if (_canAddBatch)
                          ElevatedButton.icon(
                            onPressed: () async {
                              final result = await Get.to(
                                () => BatchCreateScreen(farmer: _currentFarmer),
                              );
                              if (result == true) {
                                await _checkActiveBatchStatus();
                                if (_hasActiveBatch &&
                                    _activeBatchData != null) {
                                  // ✅ FIX — yahan bhi hardcoded 'Owner' ki
                                  // jagah asli session role use karo.
                                  final role =
                                      await _resolveUserRoleForNavigation();
                                  Get.to(
                                    () => BatchDetailScreen(
                                      farmerId: _currentFarmer['id'] ?? '',
                                      batchData: _activeBatchData!,
                                      userRole: role,
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
      onTap: () async {
        // ✅ FIX — hardcoded 'Owner' ki jagah asli session role.
        final role = await _resolveUserRoleForNavigation();
        Get.to(
          () => BatchDetailScreen(
            farmerId: _currentFarmer['id'] ?? '',
            batchData: batch,
            userRole: role,
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
                onPressed: () async {
                  // ✅ FIX — hardcoded 'Owner' ki jagah asli session role.
                  final role = await _resolveUserRoleForNavigation();
                  Get.to(
                    () => BatchDetailScreen(
                      farmerId: _currentFarmer['id'] ?? '',
                      batchData: batch,
                      userRole: role,
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
    String? imgPath = _currentFarmer[pathKey]?.toString();
    // ✅ FIX: previously "Uploaded" was shown purely from the boolean flag,
    // even if the underlying file had been deleted/moved. Now we also verify
    // the file still exists on disk.
    bool fileExists =
        imgPath != null && imgPath.isNotEmpty && File(imgPath).existsSync();
    bool isUploaded = _currentFarmer[statusKey] == true && fileExists;
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
              if (isUploaded && imgPath != null) {
                _openDocumentLightboxPreview(imgPath, label);
              } else if (_canEditProfile) {
                _pickAndSaveDocumentPhoto(statusKey, pathKey);
              } else {
                Get.snackbar(
                  'Access Nahi Hai',
                  'Document upload karne ka permission nahi diya gaya hai.',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                  snackPosition: SnackPosition.BOTTOM,
                  margin: const EdgeInsets.all(15),
                );
              }
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
                      if (_canEditProfile)
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
              if (_canEditBank)
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
