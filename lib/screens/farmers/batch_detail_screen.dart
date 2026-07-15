import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_file/open_file.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import '../../../utils/pdf_download.dart' as pdf_web;
import '../../../services/company_store.dart';
import '../../../utils/feed_consumption_rule_engine.dart';
import '../../../utils/fraud_risk_engine.dart';
import '../../../utils/performance_alert_engine.dart';
import 'daily_update_list_screen.dart';

// =============================================================================
// BATCH DETAIL & DAILY DATA ENTRY SCREEN
// =============================================================================

class BatchDetailScreen extends StatefulWidget {
  final String farmerId;
  final Map<String, dynamic> batchData;
  final String userRole;

  const BatchDetailScreen({
    super.key,
    required this.farmerId,
    required this.batchData,
    required this.userRole,
  });

  @override
  State<BatchDetailScreen> createState() => _BatchDetailScreenState();
}

class _ThemeColors {
  static const Color primaryGreen = Color(0xFF1B5E20);
}

class _BatchDetailScreenState extends State<BatchDetailScreen> {
  // ── Local notifications — "Download complete, tap to view" ke liye ─────
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;
  static const Color primaryGreen = Color(0xFF1B5E20);

  final _weightController = TextEditingController();
  final _mortalityController = TextEditingController();
  final _dateController = TextEditingController();

  // ── ✅ NEW: Feed ab 3 type mein — Starter / Grower / Finisher ───────────
  final _feedStarterBagsController = TextEditingController();
  final _feedStarterKgPerBagController = TextEditingController(text: '50.0');
  final _feedGrowerBagsController = TextEditingController();
  final _feedGrowerKgPerBagController = TextEditingController(text: '50.0');
  final _feedFinisherBagsController = TextEditingController();
  final _feedFinisherKgPerBagController = TextEditingController(text: '50.0');

  final _buyerNameController = TextEditingController();
  final _soldChicksController = TextEditingController();
  final _totalWeightSoldController = TextEditingController();
  final _pricePerKgController = TextEditingController();

  final _medicineNameController = TextEditingController();
  final _medicineQuantityController = TextEditingController();
  final _medicinePriceController = TextEditingController();
  String _selectedMedicineUnit = 'ml';

  final _remainingFeedController = TextEditingController();
  // ── ✅ NEW: Return Feed Controller ──────────────────────────────────────
  final _returnFeedKgController = TextEditingController();

  // ── ✅ NEW: Camera-verify state ──────────────────────────────────────────
  final ImagePicker _picker = ImagePicker();
  Uint8List? _mortalityPhotoBytes;
  Uint8List? _weightPhotoBytes;
  Uint8List? _remainingFeedPhotoBytes;
  bool _mortalityPhotoMismatch = false;
  bool _weightPhotoMismatch = false;
  String? _mortalityMismatchReason;
  String? _weightMismatchReason;
  bool _verifyingPhoto = false;

  final List<String> _medicineUnitsList = [
    'ml',
    'L',
    'packet',
    'vial',
    'kg',
    'g',
    'box',
  ];

  List<dynamic> _dailyEntries = [];
  bool _isLoading = false;
  bool _weightReminderShown = false;
  Map<String, dynamic> _liveBatchData = {};

  int _minLiftingDays = 23;
  int _maxLiftingDays = 60;
  DateTime _selectedDate = DateTime.now();

  // ── Farmer Info ──────────────────────────────────────────────────────────
  String _farmerName = '';
  String _farmerPhone = '';
  String _farmerBankName = '';
  String _farmerAccountNo = '';
  String _farmerAccountHolder = '';
  String _farmerIfsc = '';
  String _farmerAddress = '';
  String _companyName = '';

  Uint8List? _farmerAvatarBytes;
  Uint8List? _farmerSignatureBytes;
  Uint8List? _ownerSignatureBytes;

  // ── Settlement Rule State ─────────────────────────────────────────────────
  int? _appliedRuleId;

  // ── Feed Consumption Rule ────────────────────────────────────────────────
  FeedConsumptionRuleConfig _feedRuleConfig = FeedConsumptionRuleConfig(
    ruleType: FeedRuleType.standardAgeChart,
  );

  // ── Performance Alert Rule ──────────────────────────────────────────────
  PerformanceAlertConfig _performanceConfig = PerformanceAlertConfig();

  // Rule 1 — Big Size params
  double _r1BigFeedRate = 42.0;
  double _r1BigChicksRate = 40.0;
  double _r1BigAdminCost = 1.50;
  double _r1BigKgPerBag = 50.0;
  double _r1BigTargetCost = 85.0;
  double _r1BigBaseComm = 8.0;
  double _r1BigSavingsShare = 50.0;
  double _r1BigExceededShare = 50.0;
  double _r1BigRateBonusThresh = 110.0;
  double _r1BigRateBonusShare = 10.0;
  bool _r1BigMedicineInProd = true;

  // Rule 1 — Small Size params
  double _r1SmFeedRate = 42.0;
  double _r1SmChicksRate = 40.0;
  double _r1SmAdminCost = 1.50;
  double _r1SmKgPerBag = 50.0;
  double _r1SmTargetCost = 90.0;
  double _r1SmBaseComm = 10.0;
  double _r1SmSavingsShare = 50.0;
  double _r1SmExceededShare = 50.0;
  double _r1SmRateBonusThresh = 120.0;
  double _r1SmRateBonusShare = 10.0;
  bool _r1SmMedicineInProd = true;

  // Rule 2 — FCR Matrix params
  double _r2BaseRate = 7.50;
  double _r2GoodMin = 1.40;
  double _r2GoodMax = 1.54;
  double _r2NormMin = 1.55;
  double _r2NormMax = 1.65;
  double _r2Bonus = 0.10;
  double _r2Penalty = 0.15;
  bool _r2IsRupeeMode = true;
  bool _r2IsMedIncludeProd = true;
  bool _r2UseConvFcr = true;

  @override
  void initState() {
    super.initState();
    _dailyEntries = widget.batchData['dailyEntries'] ?? [];
    _liveBatchData = Map<String, dynamic>.from(widget.batchData);
    _dateController.text = _formatDate(DateTime.now());
    _loadFreshBatchData();
    _initDownloadNotifications();
  }

  // ── Download notification setup ─────────────────────────────────────────
  Future<void> _initDownloadNotifications() async {
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) async {
          final path = response.payload;
          if (path != null && path.isNotEmpty) {
            try {
              await OpenFile.open(path);
            } catch (_) {}
          }
        },
      );
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      _notificationsReady = true;
    } catch (_) {
      _notificationsReady = false;
    }
  }

  Future<void> _showDownloadNotification({
    required String fileName,
    required String filePath,
  }) async {
    if (!_notificationsReady) return;
    try {
      const androidDetails = AndroidNotificationDetails(
        'pdf_downloads_channel',
        'PDF Downloads',
        channelDescription:
            'Batch settlement rasid PDF download complete notifications',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
      const notifDetails = NotificationDetails(android: androidDetails);
      await _notificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        fileName,
        'Download complete. Tap to view.',
        notifDetails,
        payload: filePath,
      );
    } catch (_) {}
  }

  String _formatDate(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
  }

  // ── 🏦 Bank Name Formatter ────────────────────────────────────────────
  static const Map<String, String> _bankFullNames = {
    'sbi': 'SBI (State Bank of India)',
    'hdfc': 'HDFC (Housing Development Finance Corporation) Bank',
    'icici':
        'ICICI (Industrial Credit and Investment Corporation of India) Bank',
    'pnb': 'PNB (Punjab National Bank)',
    'bob': 'BOB (Bank of Baroda)',
    'boi': 'BOI (Bank of India)',
    'canara': 'Canara Bank',
    'union': 'Union Bank of India',
    'ubi': 'UBI (Union Bank of India)',
    'axis': 'Axis Bank',
    'kotak': 'Kotak Mahindra Bank',
    'idbi': 'IDBI (Industrial Development Bank of India)',
    'indian': 'Indian Bank',
    'iob': 'IOB (Indian Overseas Bank)',
    'central': 'Central Bank of India',
    'uco': 'UCO (United Commercial Bank)',
    'yes': 'YES Bank',
    'idfc': 'IDFC FIRST Bank',
    'rbl': 'RBL (Ratnakar) Bank',
    'federal': 'Federal Bank',
    'karnataka': 'Karnataka Bank',
    'maharashtra': 'BOM (Bank of Maharashtra)',
    'bom': 'BOM (Bank of Maharashtra)',
    'psb': 'PSB (Punjab & Sind Bank)',
    'dcb': 'DCB (Development Credit Bank)',
    'south indian': 'South Indian Bank',
    'j&k': 'J&K (Jammu & Kashmir) Bank',
    'jk': 'J&K (Jammu & Kashmir) Bank',
    'au small finance': 'AU Small Finance Bank',
    'equitas': 'Equitas Small Finance Bank',
    'ujjivan': 'Ujjivan Small Finance Bank',
    'paytm': 'Paytm Payments Bank',
    'hsbc': 'HSBC (Hongkong and Shanghai Banking Corporation)',
    'citi': 'Citibank',
    'standard chartered': 'Standard Chartered Bank',
    'deutsche': 'Deutsche Bank',
  };

  String _formatBankName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '--';

    final key = trimmed.toLowerCase();
    if (_bankFullNames.containsKey(key)) {
      return _bankFullNames[key]!;
    }

    final looksLikeAcronym = !trimmed.contains(' ') && trimmed.length <= 6;
    if (looksLikeAcronym) {
      return trimmed.toUpperCase();
    }

    return trimmed
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  // ── 🧾 PDF-safe text cleaner ─────────────────────────────────────────────
  static final RegExp _emojiPattern = RegExp(
    r'[\u{1F1E6}-\u{1FFFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}\u{2934}\u{2935}]',
    unicode: true,
  );

  String _pdfSafe(String raw) {
    return raw
        .replaceAll(_emojiPattern, '')
        .replaceAll('₹', 'Rs.')
        .replaceAll('−', '-')
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  // ── 🚨 Fraud Risk Indicator Card ───────────────────────────────────────
  Widget _buildFraudRiskCard(FraudRiskAssessment a) {
    Color bgColor;
    Color borderColor;
    Color textColor;
    String headline;
    IconData icon;

    switch (a.riskLevel) {
      case 'high':
        bgColor = Colors.red.shade50;
        borderColor = Colors.red.shade300;
        textColor = Colors.red.shade900;
        headline = '🚨 High Risk — Dono checks flag ho rahe hain';
        icon = Icons.report_problem_rounded;
        break;
      case 'watch':
        bgColor = Colors.amber.shade50;
        borderColor = Colors.amber.shade400;
        textColor = Colors.orange.shade900;
        headline = '⚠️ Watch — Ek check flag ho raha hai';
        icon = Icons.warning_amber_rounded;
        break;
      default:
        bgColor = const Color(0xFFE8F5E9);
        borderColor = primaryGreen.withOpacity(0.4);
        textColor = primaryGreen;
        headline = '✅ Sab Normal — Koi risk signal nahi';
        icon = Icons.verified_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: textColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headline,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _fraudCheckRow(
            label: 'Feed-per-Bird',
            detail:
                'Actual ${a.feedPerBird.actualConsumedKg.toStringAsFixed(1)} kg / '
                'Expected ${a.feedPerBird.expectedConsumedKg.toStringAsFixed(1)} kg '
                '(${a.feedPerBird.ratioPercent.toStringAsFixed(1)}%)',
            isFlagged: a.feedPerBird.isFlagged,
          ),
          const SizedBox(height: 6),
          _fraudCheckRow(
            label: 'Purchase Reconciliation',
            detail:
                'Expected Stock ${a.purchaseReconciliation.expectedRemainingKg.toStringAsFixed(1)} kg '
                'vs Actual ${a.purchaseReconciliation.actualRemainingKg.toStringAsFixed(1)} kg '
                '(Gap ${a.purchaseReconciliation.gapPercent.toStringAsFixed(1)}%)',
            isFlagged: a.purchaseReconciliation.isFlagged,
          ),
        ],
      ),
    );
  }

  Widget _fraudCheckRow({
    required String label,
    required String detail,
    required bool isFlagged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isFlagged ? Icons.cancel_rounded : Icons.check_circle_rounded,
          size: 15,
          color: isFlagged ? Colors.red.shade700 : Colors.green.shade700,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 11.5, color: Colors.black87),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: detail),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _weightController.dispose();
    _mortalityController.dispose();
    _feedStarterBagsController.dispose();
    _feedStarterKgPerBagController.dispose();
    _feedGrowerBagsController.dispose();
    _feedGrowerKgPerBagController.dispose();
    _feedFinisherBagsController.dispose();
    _feedFinisherKgPerBagController.dispose();
    _dateController.dispose();
    _buyerNameController.dispose();
    _soldChicksController.dispose();
    _totalWeightSoldController.dispose();
    _pricePerKgController.dispose();
    _medicineNameController.dispose();
    _medicineQuantityController.dispose();
    _medicinePriceController.dispose();
    _remainingFeedController.dispose();
    _returnFeedKgController.dispose();
    super.dispose();
  }

  Future<void> _loadFreshBatchData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _minLiftingDays = prefs.getInt('minLiftingDays') ?? 23;
      _maxLiftingDays = prefs.getInt('maxLiftingDays') ?? 60;
    });

    final savedRuleId = prefs.getInt('appliedCompanyRuleId');
    final String? rule1Json = prefs.getString('rule1SettlementConfig');
    final String? rule2Json = prefs.getString('rule2SettlementConfig');
    final String? feedRuleJson = prefs.getString('feedConsumptionRuleConfig');
    final String? perfAlertJson = prefs.getString('performanceAlertConfig');

    setState(() {
      _appliedRuleId = savedRuleId;

      if (feedRuleJson != null && feedRuleJson.isNotEmpty) {
        try {
          _feedRuleConfig = FeedConsumptionRuleConfig.fromJson(
            json.decode(feedRuleJson),
          );
        } catch (_) {}
      }

      if (perfAlertJson != null && perfAlertJson.isNotEmpty) {
        try {
          _performanceConfig = PerformanceAlertConfig.fromJson(
            json.decode(perfAlertJson),
          );
        } catch (_) {}
      }

      if (rule1Json != null) {
        final Map<String, dynamic> r1 = json.decode(rule1Json);
        _r1BigFeedRate = (r1['bigFeedRate'] ?? 42.0).toDouble();
        _r1BigChicksRate = (r1['bigChicksRate'] ?? 40.0).toDouble();
        _r1BigAdminCost = (r1['bigAdminCost'] ?? 1.50).toDouble();
        _r1BigKgPerBag = (r1['bigKgPerBag'] ?? 50.0).toDouble();
        _r1BigTargetCost = (r1['bigTargetCost'] ?? 85.0).toDouble();
        _r1BigBaseComm = (r1['bigBaseComm'] ?? 8.0).toDouble();
        _r1BigSavingsShare = (r1['bigSavingsShare'] ?? 50.0).toDouble();
        _r1BigExceededShare = (r1['bigExceededShare'] ?? 50.0).toDouble();
        _r1BigRateBonusThresh = (r1['bigRateBonusThresh'] ?? 110.0).toDouble();
        _r1BigRateBonusShare = (r1['bigRateBonusShare'] ?? 10.0).toDouble();
        _r1BigMedicineInProd = r1['bigMedicineInProd'] ?? true;

        _r1SmFeedRate = (r1['smFeedRate'] ?? 42.0).toDouble();
        _r1SmChicksRate = (r1['smChicksRate'] ?? 40.0).toDouble();
        _r1SmAdminCost = (r1['smAdminCost'] ?? 1.50).toDouble();
        _r1SmKgPerBag = (r1['smKgPerBag'] ?? 50.0).toDouble();
        _r1SmTargetCost = (r1['smTargetCost'] ?? 90.0).toDouble();
        _r1SmBaseComm = (r1['smBaseComm'] ?? 10.0).toDouble();
        _r1SmSavingsShare = (r1['smSavingsShare'] ?? 50.0).toDouble();
        _r1SmExceededShare = (r1['smExceededShare'] ?? 50.0).toDouble();
        _r1SmRateBonusThresh = (r1['smRateBonusThresh'] ?? 120.0).toDouble();
        _r1SmRateBonusShare = (r1['smRateBonusShare'] ?? 10.0).toDouble();
        _r1SmMedicineInProd = r1['smMedicineInProd'] ?? true;
      }

      if (rule2Json != null) {
        final Map<String, dynamic> r2 = json.decode(rule2Json);
        _r2BaseRate = (r2['baseRate'] ?? 7.50).toDouble();
        _r2GoodMin = (r2['goodMin'] ?? 1.40).toDouble();
        _r2GoodMax = (r2['goodMax'] ?? 1.54).toDouble();
        _r2NormMin = (r2['normMin'] ?? 1.55).toDouble();
        _r2NormMax = (r2['normMax'] ?? 1.65).toDouble();
        _r2Bonus = (r2['bonus'] ?? 0.10).toDouble();
        _r2Penalty = (r2['penalty'] ?? 0.15).toDouble();
        _r2IsRupeeMode = r2['isRupeeMode'] ?? true;
        _r2IsMedIncludeProd = r2['isMedIncludeProd'] ?? true;
        _r2UseConvFcr = r2['useConvFcr'] ?? true;
      }
    });

    final String? farmersJson = prefs.getString('companyFarmers');
    if (farmersJson != null) {
      List<dynamic> farmersList = json.decode(farmersJson);
      final currentFarmer = farmersList
          .cast<Map<String, dynamic>>()
          .where((f) => f['id'] == widget.farmerId)
          .firstOrNull;

      if (currentFarmer != null) {
        setState(() {
          _farmerName = currentFarmer['name'] ?? '';
          _farmerPhone = currentFarmer['phone'] ?? '';
          final rawBankName = (currentFarmer['bankName'] ?? '').toString();
          _farmerBankName = _formatBankName(rawBankName);
          final rawAccountHolder = (currentFarmer['accountHolder'] ?? '')
              .toString()
              .trim();
          _farmerAccountHolder = rawAccountHolder.isNotEmpty
              ? rawAccountHolder
              : _farmerName;
          _farmerAccountNo = '';
          for (final key in [
            'accountNumber',
            'accountNo',
            'bankAccountNo',
            'bankAccountNumber',
            'accNo',
            'account_no',
            'account_number',
          ]) {
            final val = currentFarmer[key];
            if (val != null && val.toString().trim().isNotEmpty) {
              _farmerAccountNo = val.toString().trim();
              break;
            }
          }
          _farmerIfsc = '';
          for (final key in ['ifsc', 'ifscCode', 'IFSC', 'ifsc_code']) {
            final val = currentFarmer[key];
            if (val != null && val.toString().trim().isNotEmpty) {
              _farmerIfsc = val.toString().trim();
              break;
            }
          }
          _farmerAddress = currentFarmer['address'] ?? '';
        });

        _companyName = '';
        for (final key in [
          'companyName',
          'businessName',
          'firmName',
          'orgName',
          'companyDisplayName',
        ]) {
          final v = prefs.getString(key);
          if (v != null && v.trim().isNotEmpty) {
            _companyName = v.trim();
            break;
          }
        }
        if (_companyName.isEmpty) {
          try {
            final cs = await CompanyStore.instance.getString('companyName');
            if (cs != null && cs.trim().isNotEmpty) {
              _companyName = cs.trim();
            }
          } catch (_) {}
        }

        // ── Farmer photo ──────────────────────────────────────────────────
        final photoPathVal = currentFarmer['photoPath']?.toString();
        if (photoPathVal != null && photoPathVal.isNotEmpty) {
          try {
            final photoFile = File(photoPathVal);
            if (await photoFile.exists()) {
              final bytes = await photoFile.readAsBytes();
              setState(() => _farmerAvatarBytes = bytes);
            }
          } catch (_) {
            _farmerAvatarBytes = null;
          }
        }
        if (_farmerAvatarBytes == null) {
          for (final key in [
            'profileImageBase64',
            'imageBase64',
            'avatarBase64',
            'photo',
            'image',
          ]) {
            final val = currentFarmer[key];
            if (val != null && val.toString().isNotEmpty) {
              try {
                setState(
                  () => _farmerAvatarBytes = base64Decode(val.toString()),
                );
              } catch (_) {}
              break;
            }
          }
        }

        // ── Farmer signature ─────────────────────────────────────────────
        _farmerSignatureBytes = null;
        final sigPathVal = currentFarmer['signaturePath']?.toString();
        if (sigPathVal != null && sigPathVal.isNotEmpty) {
          try {
            final sigFile = File(sigPathVal);
            if (await sigFile.exists()) {
              final bytes = await sigFile.readAsBytes();
              setState(() => _farmerSignatureBytes = bytes);
            }
          } catch (_) {
            _farmerSignatureBytes = null;
          }
        }

        // ── Owner signature ──────────────────────────────────────────────
        _ownerSignatureBytes = null;
        try {
          final ownerSigBase64 = await CompanyStore.instance.getString(
            'ownerSignature',
          );
          if (ownerSigBase64 != null && ownerSigBase64.isNotEmpty) {
            setState(() => _ownerSignatureBytes = base64Decode(ownerSigBase64));
          }
        } catch (_) {
          _ownerSignatureBytes = null;
        }

        if (currentFarmer['batches'] != null) {
          List<dynamic> batches = currentFarmer['batches'];
          final currentBatch = batches
              .cast<Map<String, dynamic>>()
              .where((b) => b['id'] == widget.batchData['id'])
              .firstOrNull;

          if (currentBatch != null) {
            if (!mounted) return;
            setState(() {
              _liveBatchData = Map<String, dynamic>.from(currentBatch);
              _dailyEntries = currentBatch['dailyEntries'] ?? [];
            });
            int daysOld = _calculateChicksDaysOld(
              _liveBatchData['startDate'] ?? '',
            );
            _checkWeightUpdateReminder(daysOld);
          }
        }
      }
    }
  }

  String _formatStartDateForDisplay(dynamic raw) {
    if (raw == null) return '-';
    final String s = raw.toString().trim();
    if (s.isEmpty) return '-';
    if (RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$').hasMatch(s)) return s;
    try {
      final d = DateTime.parse(s);
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return s;
    }
  }

  int _calculateChicksDaysOld(String startDateStr) {
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
      DateTime isoDate = DateTime.parse(startDateStr);
      int totalDays = DateTime.now().difference(isoDate).inDays;
      return totalDays < 0 ? 0 : totalDays;
    } catch (e) {
      debugPrint('Date parsing: $e');
    }
    return 0;
  }

  void _checkWeightUpdateReminder(int daysOld) {
    if (_weightReminderShown) return;
    String status = (_liveBatchData['status'] ?? '').toString().toUpperCase();
    if (status == 'COMPLETED' || status == 'CLOSED') return;
    DateTime lastWeightUpdatedDate = DateTime.now();
    bool foundAnyWeightLog = false;

    for (var entry in _dailyEntries.reversed) {
      if (entry['type'].toString().toLowerCase() == 'sale' ||
          entry['type'].toString().toLowerCase() == 'medicine')
        continue;
      double wt = double.tryParse(entry['weight'].toString()) ?? 0.0;
      if (wt > 0.0) {
        try {
          List<String> parts = entry['date'].toString().split('/');
          if (parts.length == 3) {
            lastWeightUpdatedDate = DateTime(
              int.parse(parts[2]),
              int.parse(parts[1]),
              int.parse(parts[0]),
            );
            foundAnyWeightLog = true;
            break;
          }
        } catch (_) {}
      }
    }

    if (!foundAnyWeightLog) {
      try {
        List<String> parts = _liveBatchData['startDate'].toString().split('/');
        if (parts.length == 3) {
          lastWeightUpdatedDate = DateTime(
            int.parse(parts[2]),
            int.parse(parts[1]),
            int.parse(parts[0]),
          );
        }
      } catch (_) {}
    }

    int daysSinceLastUpdate = DateTime.now()
        .difference(lastWeightUpdatedDate)
        .inDays;
    if (daysSinceLastUpdate >= 7) {
      _weightReminderShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 28,
                ),
                SizedBox(width: 8),
                Text(
                  'Weight Update Required ⚠️',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Text(
              'Average Weight update kiye huye $daysSinceLastUpdate din ho chuke hain. '
              'Kripya dhyan dein aur aaj ka Average Weight jald se jald darj karein!',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    color: primaryGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      });
    }
  }

  int _getAppStandardTargetWeight(int daysOld) {
    if (daysOld <= 0) return 40;
    if (daysOld <= 7) return 40 + (daysOld * 20);
    if (daysOld <= 14) return 180 + ((daysOld - 7) * 38);
    if (daysOld <= 21) return 446 + ((daysOld - 14) * 64);
    if (daysOld <= 28) return 894 + ((daysOld - 21) * 85);
    return 1489 + ((daysOld - 28) * 90);
  }

  Future<void> _pickDate(
    BuildContext context,
    StateSetter setDialogState,
  ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(
          context,
        ).copyWith(colorScheme: const ColorScheme.light(primary: primaryGreen)),
        child: child!,
      ),
    );
    if (picked != null) {
      setDialogState(() {
        _selectedDate = picked;
        _dateController.text = _formatDate(picked);
      });
    }
  }

  // ===========================================================================
  // PDF GENERATOR — Improved Design with Farmer Photo + Colored Sections
  // ===========================================================================

  Future<Uint8List> _generateSettlementPdf({
    required String ruleLabel,
    required String sizeLabel,
    required int initialChicks,
    required int totalMortality,
    required int totalChicksSold,
    required double totalWeightSoldKg,
    required double totalSaleMoney,
    required double avgSaleRate,
    required double latestAvgWeight,
    required int totalFeedBags,
    required double totalFeedKg,
    required double totalChickCost,
    required double totalFeedCost,
    required double totalAdminCost,
    required double totalMedicineCost,
    required bool medInProdCost,
    required double totalProdCost,
    required double actualCostPerKg,
    required double targetCostPerKg,
    required double costDiff,
    required double baseCommPerKg,
    required double costAdjPerKg,
    required String costAdjLabel,
    required bool rateBonusApplied,
    required double rateBonusPerKg,
    required double rateBonThresh,
    required double finalCommPerKg,
    required double grossEarning,
    required double netPayout,
    bool isRule2 = false,
  }) async {
    final pdf = pw.Document();

    // ── PDF Color Palette ───────────────────────────────────────────────────
    const PdfColor kGreen = PdfColor.fromInt(0xFF1B5E20);
    const PdfColor kGreenMid = PdfColor.fromInt(0xFF2E7D32);
    const PdfColor kGreenDark = PdfColor.fromInt(0xFF0F3D12);
    const PdfColor kGreenLight = PdfColor.fromInt(0xFFE8F5E9);
    const PdfColor kRedLight = PdfColor.fromInt(0xFFFFEBEE);
    const PdfColor kBlueLight = PdfColor.fromInt(0xFFE3F2FD);
    const PdfColor kIndigoLight = PdfColor.fromInt(0xFFE8EAF6);
    const PdfColor kOrangeLight = PdfColor.fromInt(0xFFFFF3E0);
    const PdfColor kGrey = PdfColor.fromInt(0xFF757575);
    const PdfColor kDark = PdfColor.fromInt(0xFF212121);
    const PdfColor kRed = PdfColor.fromInt(0xFFC62828);
    const PdfColor kRedDark = PdfColor.fromInt(0xFF8E0000);
    const PdfColor kBlue = PdfColor.fromInt(0xFF1565C0);
    const PdfColor kBlueDark = PdfColor.fromInt(0xFF0D47A1);
    const PdfColor kIndigo = PdfColor.fromInt(0xFF283593);
    const PdfColor kIndigoDark = PdfColor.fromInt(0xFF1A237E);
    const PdfColor kOrange = PdfColor.fromInt(0xFFE65100);
    const PdfColor kGold = PdfColor.fromInt(0xFFFFC107);
    const PdfColor kWhite = PdfColors.white;
    const PdfColor kDivider = PdfColor.fromInt(0xFFE0E0E0);

    // ── TextStyle helper ─────────────────────────────────────────────────────
    pw.TextStyle ts({
      double size = 10,
      bool bold = false,
      PdfColor color = kDark,
    }) => pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color,
    );

    // ── Layered "elevation" shadow ────────────────────────────────────────
    List<pw.BoxShadow> cardShadow({double opacity = 0.14}) => [
      pw.BoxShadow(
        color: PdfColor(0, 0, 0, opacity * 0.6),
        offset: const PdfPoint(0, 1),
        blurRadius: 2,
      ),
      pw.BoxShadow(
        color: PdfColor(0, 0, 0, opacity),
        offset: const PdfPoint(0, 5),
        blurRadius: 11,
      ),
    ];

    // ── Round icon-badge ────────────────────────────────────────────────────
    pw.Widget pdfIconBadge(String letter, PdfColor accent, PdfColor accent2) =>
        pw.Container(
          width: 24,
          height: 24,
          padding: const pw.EdgeInsets.all(2),
          decoration: pw.BoxDecoration(
            shape: pw.BoxShape.circle,
            gradient: pw.LinearGradient(
              begin: pw.Alignment.topLeft,
              end: pw.Alignment.bottomRight,
              colors: [PdfColors.white, PdfColor.fromInt(0xFFEDEDED)],
            ),
            boxShadow: [
              pw.BoxShadow(
                color: const PdfColor(0, 0, 0, 0.3),
                offset: const PdfPoint(0, 1.5),
                blurRadius: 2,
              ),
            ],
          ),
          child: pw.Container(
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              color: PdfColors.white,
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(
              letter,
              style: ts(size: 10.5, bold: true, color: accent),
            ),
          ),
        );

    // ── Small dashboard stat-chip ──────────────────────────────────────────
    pw.Widget statChip(String value, String label, PdfColor c1, PdfColor c2) =>
        pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 3),
            padding: const pw.EdgeInsets.symmetric(vertical: 9),
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                begin: pw.Alignment.topLeft,
                end: pw.Alignment.bottomRight,
                colors: [c1, c2],
              ),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              boxShadow: cardShadow(opacity: 0.2),
            ),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  value,
                  style: ts(size: 13, bold: true, color: PdfColors.white),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  label,
                  style: ts(size: 6.8, color: const PdfColor(1, 1, 1, 0.88)),
                ),
              ],
            ),
          ),
        );

    // ── Header row inside green banner ─────────────────────────────────────
    pw.Widget pdfHeaderRow(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Flexible(
            child: pw.Text(
              label,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: ts(size: 9, color: const PdfColor(1, 1, 1, 0.85)),
            ),
          ),
          pw.SizedBox(width: 4),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text(
                '.' * 60,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                style: ts(size: 8, color: const PdfColor(1, 1, 1, 0.3)),
              ),
            ),
          ),
          pw.SizedBox(width: 4),
          pw.Flexible(
            child: pw.Text(
              value,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              textAlign: pw.TextAlign.right,
              style: ts(size: 9, bold: true, color: kWhite),
            ),
          ),
        ],
      ),
    );

    // ── Key-value data row ──────────────────────────────────────────────────
    pw.Widget pdfDataRow(
      String label,
      String value, {
      bool bold = false,
      PdfColor valueColor = kDark,
      bool divider = false,
      bool highlight = false,
    }) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (divider) pw.Divider(color: kDivider, thickness: 0.5),
          pw.Container(
            color: highlight ? kGreenLight : null,
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Flexible(
                  child: pw.Text(
                    label,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: ts(size: 8.5, color: kGrey),
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2.5),
                    child: pw.Text(
                      '.' * 90,
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                      style: ts(size: 7.5, color: kDivider),
                    ),
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Flexible(
                  child: pw.Text(
                    value,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    textAlign: pw.TextAlign.right,
                    style: ts(
                      size: bold ? 9.5 : 8.5,
                      bold: bold,
                      color: valueColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // ── Section card ────────────────────────────────────────────────────────
    pw.Widget pdfSection(
      String title,
      String badgeLetter,
      PdfColor titleColor,
      PdfColor titleColorDark,
      PdfColor bgColor,
      List<pw.Widget> rows,
    ) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        decoration: pw.BoxDecoration(
          color: bgColor,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
          border: pw.Border.all(
            color: PdfColor(
              titleColor.red,
              titleColor.green,
              titleColor.blue,
              0.35,
            ),
            width: 0.7,
          ),
          boxShadow: cardShadow(),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 7,
              ),
              decoration: pw.BoxDecoration(
                gradient: pw.LinearGradient(
                  begin: pw.Alignment.centerLeft,
                  end: pw.Alignment.centerRight,
                  colors: [titleColorDark, titleColor],
                ),
                borderRadius: const pw.BorderRadius.only(
                  topLeft: pw.Radius.circular(10),
                  topRight: pw.Radius.circular(10),
                ),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pdfIconBadge(badgeLetter, titleColor, titleColorDark),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Text(
                      title,
                      style: ts(size: 10, bold: true, color: kWhite),
                    ),
                  ),
                ],
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: rows,
              ),
            ),
          ],
        ),
      );
    }

    String batchId = _liveBatchData['batchId'] ?? _liveBatchData['id'] ?? '-';
    String startDate = _formatStartDateForDisplay(_liveBatchData['startDate']);
    String endDate = _formatDate(DateTime.now());
    int totalDays = _calculateChicksDaysOld(_liveBatchData['startDate'] ?? '');
    double mortalityPct = initialChicks > 0
        ? (totalMortality / initialChicks) * 100
        : 0.0;

    final String watermarkText = _companyName.isNotEmpty
        ? _companyName.toUpperCase()
        : 'TRACKO';

    // ── Page theme with background watermark ─────────────────────────────
    final pw.PageTheme pageTheme = pw.PageTheme(
      pageFormat: const PdfPageFormat(595.28, 1500),
      margin: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      buildForeground: (pw.Context context) {
        pw.Widget singleWatermark() => pw.Watermark.text(
          watermarkText,
          angle: 0.5,
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.normal,
            color: PdfColor.fromInt(0xFFE8E8E8),
          ),
        );

        pw.Widget gridSlot({
          required double top,
          required double bottom,
          required double left,
          required double right,
        }) => pw.Positioned(
          top: top,
          bottom: bottom,
          left: left,
          right: right,
          child: singleWatermark(),
        );

        return pw.FullPage(
          ignoreMargins: true,
          child: pw.Stack(
            children: [
              gridSlot(top: 150, bottom: 1300, left: 40, right: 335),
              gridSlot(top: 150, bottom: 1300, left: 335, right: 40),
              gridSlot(top: 650, bottom: 800, left: 40, right: 335),
              gridSlot(top: 650, bottom: 800, left: 335, right: 40),
              gridSlot(top: 1150, bottom: 300, left: 40, right: 335),
              gridSlot(top: 1150, bottom: 300, left: 335, right: 40),
            ],
          ),
        );
      },
    );

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        build: (ctx) => [
          // ── FARMER PROFILE CARD ───────────────────────────────────────────
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: kWhite,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              border: pw.Border.all(color: kDivider, width: 0.8),
              boxShadow: cardShadow(),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 60,
                  height: 60,
                  padding: const pw.EdgeInsets.all(3),
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    gradient: pw.LinearGradient(
                      begin: pw.Alignment.topLeft,
                      end: pw.Alignment.bottomRight,
                      colors: [kGold, PdfColor.fromInt(0xFFB8860B)],
                    ),
                    boxShadow: cardShadow(opacity: 0.25),
                  ),
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(2),
                    decoration: pw.BoxDecoration(
                      shape: pw.BoxShape.circle,
                      color: kWhite,
                    ),
                    child: pw.Container(
                      width: 50,
                      height: 50,
                      decoration: pw.BoxDecoration(
                        shape: pw.BoxShape.circle,
                        color: kGreenLight,
                        border: pw.Border.all(color: kGreenMid, width: 1.5),
                      ),
                      child: _farmerAvatarBytes != null
                          ? pw.ClipOval(
                              child: pw.Image(
                                pw.MemoryImage(_farmerAvatarBytes!),
                                width: 50,
                                height: 50,
                                fit: pw.BoxFit.cover,
                              ),
                            )
                          : pw.Center(
                              child: pw.Text(
                                _farmerName.isNotEmpty
                                    ? _farmerName[0].toUpperCase()
                                    : 'F',
                                style: ts(size: 22, bold: true, color: kGreen),
                              ),
                            ),
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        _farmerName.isNotEmpty ? _farmerName : 'Farmer',
                        style: ts(size: 14, bold: true, color: kDark),
                      ),
                      if (_farmerPhone.isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Ph: $_farmerPhone',
                          style: ts(size: 9, color: kGrey),
                        ),
                      ],
                      if (_farmerAddress.isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Addr: $_farmerAddress',
                          style: ts(size: 9, color: kGrey),
                        ),
                      ],
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: pw.BoxDecoration(
                    gradient: pw.LinearGradient(
                      begin: pw.Alignment.topLeft,
                      end: pw.Alignment.bottomRight,
                      colors: [kGreenMid, kGreenDark],
                    ),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(6),
                    ),
                    boxShadow: cardShadow(opacity: 0.2),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        watermarkText,
                        style: ts(size: 9, bold: true, color: kWhite),
                      ),
                      pw.Text(
                        'via Tracko App',
                        style: ts(
                          size: 7,
                          color: const PdfColor(1, 1, 1, 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── STAT DASHBOARD CHIPS ───────────────────────────────────────────
          pw.Row(
            children: [
              statChip('$totalDays Din', 'TOTAL DAYS', kBlueDark, kBlue),
              statChip(
                '${mortalityPct.toStringAsFixed(1)}%',
                'MORTALITY',
                kRedDark,
                kRed,
              ),
              statChip(
                'Rs.${finalCommPerKg.toStringAsFixed(2)}',
                'FINAL COMM/KG',
                kGreenDark,
                kGreenMid,
              ),
            ],
          ),
          pw.SizedBox(height: 12),

          // ── GREEN MAIN HEADER ─────────────────────────────────────────────
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(bottom: 12),
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                begin: pw.Alignment.topLeft,
                end: pw.Alignment.bottomRight,
                colors: [kGreenDark, kGreenMid],
              ),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              boxShadow: cardShadow(opacity: 0.22),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Batch Settlement Rasid',
                      style: ts(size: 16, bold: true, color: kWhite),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: pw.BoxDecoration(
                        gradient: pw.LinearGradient(
                          colors: [kGold, const PdfColor.fromInt(0xFFB8860B)],
                        ),
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(20),
                        ),
                        boxShadow: [
                          pw.BoxShadow(
                            color: const PdfColor(0, 0, 0, 0.3),
                            offset: const PdfPoint(0, 1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                      child: pw.Text(
                        sizeLabel.toUpperCase(),
                        style: ts(size: 7.5, bold: true, color: kGreenDark),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  _pdfSafe(ruleLabel),
                  style: ts(size: 9, color: const PdfColor(1, 1, 1, 0.85)),
                ),
                pw.SizedBox(height: 10),
                pw.Divider(
                  color: const PdfColor(1, 1, 1, 0.25),
                  thickness: 0.5,
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pdfHeaderRow('Batch ID', batchId),
                          pw.SizedBox(height: 3),
                          pdfHeaderRow('Start Date', startDate),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 16),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pdfHeaderRow('End Date', endDate),
                          pw.SizedBox(height: 3),
                          pdfHeaderRow('Total Days', '$totalDays Din'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── BATCH SUMMARY ─────────────────────────────────────────────────
          pdfSection('Batch Summary', 'B', kBlue, kBlueDark, kBlueLight, [
            pdfDataRow('Initial Chicks Housed', '$initialChicks pcs'),
            pdfDataRow(
              'Total Mortality',
              '$totalMortality pcs (${mortalityPct.toStringAsFixed(2)}%)',
            ),
            pdfDataRow('Total Chicks Sold', '$totalChicksSold pcs'),
            pdfDataRow(
              'Total Weight Sold',
              '${totalWeightSoldKg.toStringAsFixed(2)} KG',
            ),
            pdfDataRow(
              'Avg Sale Rate',
              'Rs.${avgSaleRate.toStringAsFixed(2)}/KG',
            ),
            pdfDataRow(
              'Total Sale Proceeds',
              'Rs.${totalSaleMoney.toStringAsFixed(2)}',
              bold: true,
              valueColor: kGreen,
              divider: true,
              highlight: true,
            ),
            pdfDataRow(
              'Avg Bird Weight (Last)',
              '${latestAvgWeight.toStringAsFixed(2)} KG',
            ),
            pdfDataRow('Size Category', sizeLabel),
            pdfDataRow(
              'Total Feed Used',
              '$totalFeedBags Bags (${totalFeedKg.toStringAsFixed(1)} KG)',
            ),
          ]),

          // ── BANK DETAILS ──────────────────────────────────────────────────
          pdfSection(
            'Farmer Bank Details',
            '\$',
            kIndigo,
            kIndigoDark,
            kIndigoLight,
            [
              pdfDataRow(
                'Account Holder',
                _farmerAccountHolder.isNotEmpty ? _farmerAccountHolder : '--',
              ),
              pdfDataRow(
                'Bank Name',
                _farmerBankName.isNotEmpty ? _farmerBankName : '--',
              ),
              pdfDataRow(
                'Account No.',
                _farmerAccountNo.isNotEmpty ? _farmerAccountNo : '--',
              ),
              pdfDataRow(
                'IFSC Code',
                _farmerIfsc.isNotEmpty ? _farmerIfsc : '--',
              ),
            ],
          ),

          if (!isRule2) ...[
            // ── PRODUCTION COST ───────────────────────────────────────────
            pdfSection(
              'Production Cost Breakdown',
              'P',
              kRed,
              kRedDark,
              kRedLight,
              [
                pdfDataRow(
                  'Chick Cost',
                  'Rs.${totalChickCost.toStringAsFixed(2)}',
                ),
                pdfDataRow(
                  'Feed Cost',
                  'Rs.${totalFeedCost.toStringAsFixed(2)}',
                ),
                pdfDataRow(
                  'Admin/Labour Charge',
                  'Rs.${totalAdminCost.toStringAsFixed(2)}',
                ),
                pdfDataRow(
                  'Medicine Cost',
                  'Rs.${totalMedicineCost.toStringAsFixed(2)}'
                      ' (${medInProdCost ? "Included in Prod" : "Excluded"})',
                ),
                pdfDataRow(
                  'Total Production Cost',
                  'Rs.${totalProdCost.toStringAsFixed(2)}',
                  bold: true,
                  valueColor: kRed,
                  divider: true,
                ),
                pdfDataRow(
                  'Actual Cost/KG',
                  'Rs.${actualCostPerKg.toStringAsFixed(2)}/KG',
                  bold: true,
                ),
                pdfDataRow(
                  'Target Cost/KG',
                  'Rs.${targetCostPerKg.toStringAsFixed(2)}/KG',
                ),
                pdfDataRow(
                  costDiff >= 0 ? 'Cost Saving/KG' : 'Cost Exceeded/KG',
                  '${costDiff >= 0 ? "+" : ""}Rs.${costDiff.toStringAsFixed(2)}/KG',
                  valueColor: costDiff >= 0 ? kGreen : kRed,
                  bold: true,
                ),
              ],
            ),

            // ── COMMISSION ────────────────────────────────────────────────
            pdfSection(
              'Farmer Commission Calculation',
              'C',
              kGreen,
              kGreenDark,
              kGreenLight,
              [
                pdfDataRow(
                  'Base Commission',
                  'Rs.${baseCommPerKg.toStringAsFixed(2)}/KG',
                ),
                pdfDataRow(
                  costAdjPerKg >= 0 ? 'Cost Saving Bonus' : 'Exceeded Penalty',
                  '${costAdjPerKg >= 0 ? "+" : ""}Rs.${costAdjPerKg.toStringAsFixed(2)}/KG',
                  valueColor: costAdjPerKg >= 0 ? kGreen : kRed,
                ),
                pdfDataRow('Calculation Note', _pdfSafe(costAdjLabel)),
                pdfDataRow(
                  'Rate Bonus',
                  rateBonusApplied
                      ? '+Rs.${rateBonusPerKg.toStringAsFixed(2)}/KG'
                      : 'Rs.0.00 (Not Applicable)',
                  valueColor: rateBonusApplied ? kGreen : kGrey,
                ),
                pdfDataRow(
                  'Final Commission/KG',
                  'Rs.${finalCommPerKg.toStringAsFixed(2)}/KG',
                  bold: true,
                  valueColor: kGreen,
                  divider: true,
                  highlight: true,
                ),
              ],
            ),

            // ── NET PAYOUT ───────────────────────────────────────────────────
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10, top: 2),
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                gradient: pw.LinearGradient(
                  begin: pw.Alignment.topLeft,
                  end: pw.Alignment.bottomRight,
                  colors: [kGreenDark, kGreenMid, kGreenDark],
                  stops: const [0.0, 0.55, 1.0],
                ),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                border: pw.Border.all(
                  color: const PdfColor(1, 1, 1, 0.12),
                  width: 1,
                ),
                boxShadow: cardShadow(opacity: 0.32),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Row(
                        children: [
                          pdfIconBadge('N', kGreenMid, kGreenDark),
                          pw.SizedBox(width: 8),
                          pw.Text(
                            'NET FARMER PAYOUT',
                            style: ts(size: 11, bold: true, color: kWhite),
                          ),
                        ],
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: pw.BoxDecoration(
                          gradient: pw.LinearGradient(
                            colors: [kGold, const PdfColor.fromInt(0xFFB8860B)],
                          ),
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(20),
                          ),
                          boxShadow: [
                            pw.BoxShadow(
                              color: const PdfColor(0, 0, 0, 0.3),
                              offset: const PdfPoint(0, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                        child: pw.Text(
                          'SETTLED',
                          style: ts(size: 7.5, bold: true, color: kGreenDark),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 12),
                  pw.Container(
                    padding: const pw.EdgeInsets.only(bottom: 8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          color: PdfColor(1, 1, 1, 0.25),
                          width: 0.6,
                        ),
                      ),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(
                          child: pw.Text(
                            'Gross Earning (Wt x Comm)',
                            style: ts(
                              size: 8.5,
                              color: const PdfColor(1, 1, 1, 0.85),
                            ),
                          ),
                        ),
                        pw.Text(
                          '${totalWeightSoldKg.toStringAsFixed(2)} KG'
                          ' x Rs.${finalCommPerKg.toStringAsFixed(2)}'
                          ' = Rs.${grossEarning.toStringAsFixed(2)}',
                          textAlign: pw.TextAlign.right,
                          style: ts(size: 8.5, bold: true, color: kWhite),
                        ),
                      ],
                    ),
                  ),
                  if (!medInProdCost) ...[
                    pw.SizedBox(height: 6),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Medicine Deduction',
                          style: ts(
                            size: 8.5,
                            color: const PdfColor(1, 1, 1, 0.85),
                          ),
                        ),
                        pw.Text(
                          '-Rs.${totalMedicineCost.toStringAsFixed(2)}',
                          style: ts(size: 8.5, bold: true, color: kGold),
                        ),
                      ],
                    ),
                  ],
                  pw.SizedBox(height: 12),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Net Payout to Farmer',
                        style: ts(
                          size: 9.5,
                          color: const PdfColor(1, 1, 1, 0.9),
                        ),
                      ),
                      pw.Text(
                        'Rs.${netPayout.toStringAsFixed(2)}',
                        style: ts(
                          size: 24,
                          bold: true,
                          color: netPayout > 0 ? kGold : PdfColors.red100,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            // ── RULE 2 NOTICE ─────────────────────────────────────────────
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: kOrangeLight,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                border: pw.Border.all(
                  color: const PdfColor(0.9, 0.4, 0.0, 0.4),
                  width: 0.7,
                ),
                boxShadow: cardShadow(),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Rule 2 - FCR Matrix Notice',
                    style: ts(size: 11, bold: true, color: kOrange),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Rule 2 ke liye settlement amount FCR calculation ke baad '
                    'manually decide hota hai. Live FCR aur weight data se '
                    'accurate commission determine karein.',
                    style: ts(size: 9, color: kDark),
                  ),
                ],
              ),
            ),
          ],

          // ── SIGNATURES ───────────────────────────────────────────────────
          pw.SizedBox(height: 24),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    _ownerSignatureBytes != null
                        ? pw.Container(
                            height: 34,
                            alignment: pw.Alignment.bottomCenter,
                            child: pw.Image(
                              pw.MemoryImage(_ownerSignatureBytes!),
                              height: 32,
                              fit: pw.BoxFit.contain,
                            ),
                          )
                        : pw.SizedBox(height: 34),
                    pw.Container(width: 150, height: 0.8, color: kDark),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      'Company Owner Signature',
                      style: ts(size: 8, bold: true, color: kDark),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Text(watermarkText, style: ts(size: 7.5, color: kGrey)),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    _farmerSignatureBytes != null
                        ? pw.Container(
                            height: 34,
                            alignment: pw.Alignment.bottomCenter,
                            child: pw.Image(
                              pw.MemoryImage(_farmerSignatureBytes!),
                              height: 32,
                              fit: pw.BoxFit.contain,
                            ),
                          )
                        : pw.SizedBox(height: 34),
                    pw.Container(width: 150, height: 0.8, color: kDark),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      'Farmer Signature',
                      style: ts(size: 8, bold: true, color: kDark),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Text(
                      _farmerName.isNotEmpty ? _farmerName : 'Farmer',
                      style: ts(size: 7.5, color: kGrey),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── FOOTER ────────────────────────────────────────────────────────
          pw.SizedBox(height: 4),
          pw.Divider(color: kDivider, thickness: 0.7),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Row(
                children: [
                  pw.Container(
                    width: 6,
                    height: 6,
                    decoration: pw.BoxDecoration(
                      color: kGreenMid,
                      shape: pw.BoxShape.circle,
                    ),
                  ),
                  pw.SizedBox(width: 5),
                  pw.Text(
                    'Generated by Tracko App',
                    style: ts(size: 8, bold: true, color: kGrey),
                  ),
                ],
              ),
              pw.Text(
                _formatDate(DateTime.now()),
                style: ts(size: 8, color: kGrey),
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ===========================================================================
  // BATCH END CONFIRMATION
  // ===========================================================================

  void _showBatchEndConfirmation({
    required int liveChicks,
    required double latestAvgWeight,
    required int totalFeedBags,
    required double totalFeedKg,
    required int totalMortality,
    required int totalChicksSold,
    required double totalWeightSoldKg,
    required double totalSaleMoney,
    required double totalMedicineExpense,
  }) {
    if (liveChicks > 0) {
      Get.snackbar(
        'Batch End Nahi Ho Sakta ⚠️',
        'Abhi $liveChicks chicks live hain. Pehle unki sale entry karo!',
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.flag_rounded, color: Colors.red, size: 26),
            SizedBox(width: 8),
            Text(
              'Batch Khatam Karo?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Saari ${widget.batchData['chicksCount'] ?? 0} chicks ki sale ho chuki hai.\n'
          'Ab settlement rasid generate karke batch permanently close karein?',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _generateAndShowSettlementRasid(
                totalFeedBags: totalFeedBags,
                totalFeedKg: totalFeedKg,
                totalMortality: totalMortality,
                totalChicksSold: totalChicksSold,
                totalWeightSoldKg: totalWeightSoldKg,
                totalSaleMoney: totalSaleMoney,
                totalMedicineExpense: totalMedicineExpense,
                latestAvgWeight: latestAvgWeight,
              );
            },
            child: const Text(
              'Haan, Batch Band Karo',
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

  void _generateAndShowSettlementRasid({
    required int totalFeedBags,
    required double totalFeedKg,
    required int totalMortality,
    required int totalChicksSold,
    required double totalWeightSoldKg,
    required double totalSaleMoney,
    required double totalMedicineExpense,
    required double latestAvgWeight,
  }) {
    int initialChicks = _liveBatchData['chicksCount'] ?? 0;

    if (_appliedRuleId == null) {
      _showNoRuleAlert();
      return;
    }

    if (_appliedRuleId == 1) {
      bool isBigSize = latestAvgWeight > 1.2;
      _showRule1SettlementRasid(
        isBigSize: isBigSize,
        initialChicks: initialChicks,
        totalFeedBags: totalFeedBags,
        totalFeedKg: totalFeedKg,
        totalMortality: totalMortality,
        totalChicksSold: totalChicksSold,
        totalWeightSoldKg: totalWeightSoldKg,
        totalSaleMoney: totalSaleMoney,
        totalMedicineExpense: totalMedicineExpense,
        latestAvgWeight: latestAvgWeight,
      );
    } else if (_appliedRuleId == 2) {
      _showRule2SettlementRasid(
        initialChicks: initialChicks,
        totalFeedBags: totalFeedBags,
        totalFeedKg: totalFeedKg,
        totalMortality: totalMortality,
        totalChicksSold: totalChicksSold,
        totalWeightSoldKg: totalWeightSoldKg,
        totalSaleMoney: totalSaleMoney,
        totalMedicineExpense: totalMedicineExpense,
        latestAvgWeight: latestAvgWeight,
      );
    }
  }

  void _showNoRuleAlert() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Colors.orange, size: 26),
            SizedBox(width: 8),
            Text(
              'Rule Apply Nahi Hua',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'Settlement ke liye pehle Home Screen → FAB → Batch Settlement '
          'mein jaake koi ek Rule select aur apply karein!',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── RULE 1 ────────────────────────────────────────────────────────────────
  void _showRule1SettlementRasid({
    required bool isBigSize,
    required int initialChicks,
    required int totalFeedBags,
    required double totalFeedKg,
    required int totalMortality,
    required int totalChicksSold,
    required double totalWeightSoldKg,
    required double totalSaleMoney,
    required double totalMedicineExpense,
    required double latestAvgWeight,
  }) {
    double feedRate = isBigSize ? _r1BigFeedRate : _r1SmFeedRate;
    double chicksRate = isBigSize ? _r1BigChicksRate : _r1SmChicksRate;
    double adminCost = isBigSize ? _r1BigAdminCost : _r1SmAdminCost;
    double kgPerBag = isBigSize ? _r1BigKgPerBag : _r1SmKgPerBag;
    double targetCost = isBigSize ? _r1BigTargetCost : _r1SmTargetCost;
    double baseComm = isBigSize ? _r1BigBaseComm : _r1SmBaseComm;
    double savingsShare = isBigSize ? _r1BigSavingsShare : _r1SmSavingsShare;
    double exceededShare = isBigSize ? _r1BigExceededShare : _r1SmExceededShare;
    double rateBonThresh = isBigSize
        ? _r1BigRateBonusThresh
        : _r1SmRateBonusThresh;
    double rateBonShare = isBigSize
        ? _r1BigRateBonusShare
        : _r1SmRateBonusShare;
    bool medInProd = isBigSize ? _r1BigMedicineInProd : _r1SmMedicineInProd;

    double totalChickCost = initialChicks * chicksRate;
    double totalFeedKgCal = totalFeedBags * kgPerBag;
    double totalFeedCost = totalFeedKgCal * feedRate;
    double totalAdminCost = totalWeightSoldKg * adminCost;

    double totalProdCost = totalChickCost + totalFeedCost + totalAdminCost;
    if (medInProd) totalProdCost += totalMedicineExpense;

    double actualCostPerKg = totalWeightSoldKg > 0
        ? totalProdCost / totalWeightSoldKg
        : 0.0;
    double costDiff = targetCost - actualCostPerKg;

    double costAdjustment = 0.0;
    String costAdjLabel = '';
    if (costDiff > 0) {
      costAdjustment = costDiff * (savingsShare / 100);
      costAdjLabel =
          '✅ Saving Bonus (+₹${costAdjustment.toStringAsFixed(2)}/KG)';
    } else if (costDiff < 0) {
      costAdjustment = costDiff * (exceededShare / 100);
      costAdjLabel =
          '❌ Penalty Deduction (−₹${costAdjustment.abs().toStringAsFixed(2)}/KG)';
    } else {
      costAdjLabel = '✅ Target Exactly Met (₹0 adj)';
    }

    double avgSaleRate = totalWeightSoldKg > 0
        ? totalSaleMoney / totalWeightSoldKg
        : 0.0;

    bool rateBonusApplied =
        (actualCostPerKg <= targetCost) && (avgSaleRate >= rateBonThresh);
    double rateBonusPerKg = 0.0;
    if (rateBonusApplied) {
      rateBonusPerKg = (avgSaleRate - rateBonThresh) * (rateBonShare / 100);
    }

    double finalComm = baseComm + costAdjustment + rateBonusPerKg;
    if (finalComm < 0) finalComm = 0.0;

    double grossEarning = totalWeightSoldKg * finalComm;
    double netPayout = grossEarning < 0 ? 0.0 : grossEarning;
    if (!medInProd) netPayout -= totalMedicineExpense;
    if (netPayout < 0) netPayout = 0.0;

    _showSettlementReceiptDialog(
      ruleLabel: isBigSize
          ? 'Rule 1 — Auto Size (🐔 Big Size > 1.2 KG)'
          : 'Rule 1 — Auto Size (🐣 Small Size ≤ 1.2 KG)',
      sizeLabel: isBigSize ? 'Big Size Poultry' : 'Small Size Poultry',
      initialChicks: initialChicks,
      totalMortality: totalMortality,
      totalChicksSold: totalChicksSold,
      totalWeightSoldKg: totalWeightSoldKg,
      totalSaleMoney: totalSaleMoney,
      avgSaleRate: avgSaleRate,
      latestAvgWeight: latestAvgWeight,
      totalFeedBags: totalFeedBags,
      totalFeedKg: totalFeedKg,
      totalChickCost: totalChickCost,
      totalFeedCost: totalFeedCost,
      totalAdminCost: totalAdminCost,
      totalMedicineCost: totalMedicineExpense,
      medInProdCost: medInProd,
      totalProdCost: totalProdCost,
      actualCostPerKg: actualCostPerKg,
      targetCostPerKg: targetCost,
      costDiff: costDiff,
      baseCommPerKg: baseComm,
      costAdjPerKg: costAdjustment,
      costAdjLabel: costAdjLabel,
      rateBonusApplied: rateBonusApplied,
      rateBonusPerKg: rateBonusPerKg,
      rateBonThresh: rateBonThresh,
      finalCommPerKg: finalComm,
      grossEarning: grossEarning,
      netPayout: netPayout,
    );
  }

  // ── RULE 2 ────────────────────────────────────────────────────────────────
  void _showRule2SettlementRasid({
    required int initialChicks,
    required int totalFeedBags,
    required double totalFeedKg,
    required int totalMortality,
    required int totalChicksSold,
    required double totalWeightSoldKg,
    required double totalSaleMoney,
    required double totalMedicineExpense,
    required double latestAvgWeight,
  }) {
    double avgSaleRate = totalWeightSoldKg > 0
        ? totalSaleMoney / totalWeightSoldKg
        : 0.0;

    _showSettlementReceiptDialog(
      ruleLabel: 'Rule 2 — FCR Matrix',
      sizeLabel: 'FCR Based Settlement',
      initialChicks: initialChicks,
      totalMortality: totalMortality,
      totalChicksSold: totalChicksSold,
      totalWeightSoldKg: totalWeightSoldKg,
      totalSaleMoney: totalSaleMoney,
      avgSaleRate: avgSaleRate,
      latestAvgWeight: latestAvgWeight,
      totalFeedBags: totalFeedBags,
      totalFeedKg: totalFeedKg,
      totalChickCost: 0,
      totalFeedCost: 0,
      totalAdminCost: 0,
      totalMedicineCost: totalMedicineExpense,
      medInProdCost: true,
      totalProdCost: 0,
      actualCostPerKg: 0,
      targetCostPerKg: 0,
      costDiff: 0,
      baseCommPerKg: 0,
      costAdjPerKg: 0,
      costAdjLabel: 'FCR Matrix — Manual calculation required',
      rateBonusApplied: false,
      rateBonusPerKg: 0,
      rateBonThresh: 0,
      finalCommPerKg: 0,
      grossEarning: 0,
      netPayout: 0,
      isRule2: true,
    );
  }

  // ===========================================================================
  // SETTLEMENT RECEIPT DIALOG — Full Screen
  // ===========================================================================

  void _showSettlementReceiptDialog({
    required String ruleLabel,
    required String sizeLabel,
    required int initialChicks,
    required int totalMortality,
    required int totalChicksSold,
    required double totalWeightSoldKg,
    required double totalSaleMoney,
    required double avgSaleRate,
    required double latestAvgWeight,
    required int totalFeedBags,
    required double totalFeedKg,
    required double totalChickCost,
    required double totalFeedCost,
    required double totalAdminCost,
    required double totalMedicineCost,
    required bool medInProdCost,
    required double totalProdCost,
    required double actualCostPerKg,
    required double targetCostPerKg,
    required double costDiff,
    required double baseCommPerKg,
    required double costAdjPerKg,
    required String costAdjLabel,
    required bool rateBonusApplied,
    required double rateBonusPerKg,
    required double rateBonThresh,
    required double finalCommPerKg,
    required double grossEarning,
    required double netPayout,
    bool isRule2 = false,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: const Color(0xFFF9FBF9),
          appBar: AppBar(
            backgroundColor: primaryGreen,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(ctx),
            ),
            title: const Text(
              'Settlement Rasid 🧾',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _markBatchAsCompleted();
                },
                icon: const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                label: const Text(
                  'Close Batch',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── FARMER PROFILE CARD ───────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: primaryGreen.withOpacity(0.13),
                        backgroundImage: _farmerAvatarBytes != null
                            ? MemoryImage(_farmerAvatarBytes!)
                            : null,
                        child: _farmerAvatarBytes == null
                            ? Text(
                                _farmerName.isNotEmpty
                                    ? _farmerName[0].toUpperCase()
                                    : 'F',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: primaryGreen,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _farmerName.isNotEmpty ? _farmerName : 'Farmer',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            if (_farmerPhone.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.phone_rounded,
                                    size: 13,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _farmerPhone,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (_farmerAddress.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    size: 13,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _farmerAddress,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.black45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── MAIN GREEN HEADER ─────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: primaryGreen,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('🧾', style: TextStyle(fontSize: 24)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Batch Settlement Rasid',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  ruleLabel,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 6),
                      _receiptHeaderRow(
                        '🆔 Batch ID',
                        _liveBatchData['batchId'] ??
                            _liveBatchData['id'] ??
                            '-',
                      ),
                      _receiptHeaderRow(
                        '📅 Start Date',
                        _formatStartDateForDisplay(_liveBatchData['startDate']),
                      ),
                      _receiptHeaderRow(
                        '📅 End Date',
                        _formatDate(DateTime.now()),
                      ),
                      _receiptHeaderRow(
                        '📦 Total Days',
                        '${_calculateChicksDaysOld(_liveBatchData['startDate'] ?? '')} Din',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── BATCH SUMMARY ─────────────────────────────────────────
                _rasidSection(
                  title: '🐥 Batch Summary',
                  color: Colors.blue.shade700,
                  bgColor: Colors.blue.shade50,
                  rows: [
                    _rasidRow('Initial Chicks Housed', '$initialChicks pcs'),
                    _rasidRow(
                      'Total Mortality',
                      '$totalMortality pcs'
                          ' (${initialChicks > 0 ? ((totalMortality / initialChicks) * 100).toStringAsFixed(2) : 0}%)',
                    ),
                    _rasidRow('Total Chicks Sold', '$totalChicksSold pcs'),
                    _rasidRow(
                      'Total Weight Sold',
                      '${totalWeightSoldKg.toStringAsFixed(2)} KG',
                    ),
                    _rasidRow(
                      'Avg Sale Rate',
                      '₹${avgSaleRate.toStringAsFixed(2)}/KG',
                    ),
                    _rasidRow(
                      'Total Sale Proceeds',
                      '₹${totalSaleMoney.toStringAsFixed(2)}',
                    ),
                    _rasidRow(
                      'Avg Bird Weight (Last)',
                      '${latestAvgWeight.toStringAsFixed(2)} KG',
                    ),
                    _rasidRow('Size Category', sizeLabel),
                    _rasidRow(
                      'Total Feed Used',
                      '$totalFeedBags Bags (${totalFeedKg.toStringAsFixed(1)} KG)',
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // ── BANK DETAILS ──────────────────────────────────────────
                _rasidSection(
                  title: '🏦 Farmer Bank Details',
                  color: Colors.indigo.shade700,
                  bgColor: Colors.indigo.shade50,
                  rows: [
                    _rasidRow(
                      'Account Holder',
                      _farmerAccountHolder.isNotEmpty
                          ? _farmerAccountHolder
                          : '—',
                    ),
                    _rasidRow(
                      'Bank Name',
                      _farmerBankName.isNotEmpty ? _farmerBankName : '—',
                    ),
                    _rasidRow(
                      'Account No.',
                      _farmerAccountNo.isNotEmpty ? _farmerAccountNo : '—',
                    ),
                    _rasidRow(
                      'IFSC Code',
                      _farmerIfsc.isNotEmpty ? _farmerIfsc : '—',
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                if (!isRule2) ...[
                  // ── PRODUCTION COST ───────────────────────────────────
                  _rasidSection(
                    title: '🏭 Production Cost Breakdown',
                    color: Colors.red.shade700,
                    bgColor: Colors.red.shade50,
                    rows: [
                      _rasidRow(
                        'Chick Cost',
                        '₹${totalChickCost.toStringAsFixed(2)}',
                      ),
                      _rasidRow(
                        'Feed Cost',
                        '₹${totalFeedCost.toStringAsFixed(2)}',
                      ),
                      _rasidRow(
                        'Admin/Labour Charge',
                        '₹${totalAdminCost.toStringAsFixed(2)}',
                      ),
                      _rasidRow(
                        'Medicine Cost',
                        '₹${totalMedicineCost.toStringAsFixed(2)}'
                            ' (${medInProdCost ? "✅ Prod Cost Mein" : "❌ Exclude"})',
                      ),
                      _rasidDividerRow(),
                      _rasidRow(
                        'Total Production Cost',
                        '₹${totalProdCost.toStringAsFixed(2)}',
                        isBold: true,
                      ),
                      _rasidRow(
                        'Actual Cost/KG',
                        '₹${actualCostPerKg.toStringAsFixed(2)}/KG',
                        isBold: true,
                      ),
                      _rasidRow(
                        'Target Cost/KG',
                        '₹${targetCostPerKg.toStringAsFixed(2)}/KG',
                      ),
                      _rasidRow(
                        costDiff >= 0
                            ? '✅ Cost Saving/KG'
                            : '❌ Cost Exceeded/KG',
                        '${costDiff >= 0 ? "+" : ""}₹${costDiff.toStringAsFixed(2)}/KG',
                        valueColor: costDiff >= 0
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ── COMMISSION ────────────────────────────────────────
                  _rasidSection(
                    title: '💰 Farmer Commission Calculation',
                    color: Colors.green.shade700,
                    bgColor: Colors.green.shade50,
                    rows: [
                      _rasidRow(
                        'Base Commission',
                        '₹${baseCommPerKg.toStringAsFixed(2)}/KG',
                      ),
                      _rasidRow(
                        costAdjPerKg >= 0
                            ? '✅ Cost Saving Bonus'
                            : '❌ Exceeded Penalty',
                        '${costAdjPerKg >= 0 ? "+" : ""}₹${costAdjPerKg.toStringAsFixed(2)}/KG',
                        valueColor: costAdjPerKg >= 0
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                      _rasidRow(
                        '💡 Calculation',
                        costAdjLabel,
                        smallText: true,
                      ),
                      const SizedBox(height: 4),
                      _rasidRow(
                        'Rate Bonus',
                        rateBonusApplied
                            ? '+₹${rateBonusPerKg.toStringAsFixed(2)}/KG ✅'
                            : '₹0.00 (Not Applicable)',
                        valueColor: rateBonusApplied
                            ? Colors.green.shade700
                            : Colors.grey,
                      ),
                      if (rateBonusApplied)
                        _rasidRow(
                          '  (Sale ₹${avgSaleRate.toStringAsFixed(2)} − Thresh ₹${rateBonThresh.toStringAsFixed(2)}) × %',
                          '',
                          smallText: true,
                        ),
                      _rasidDividerRow(),
                      _rasidRow(
                        'Final Commission/KG',
                        '₹${finalCommPerKg.toStringAsFixed(2)}/KG',
                        isBold: true,
                        valueColor: primaryGreen,
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ── NET PAYOUT ────────────────────────────────────────
                  _rasidSection(
                    title: '🏦 Net Farmer Payout',
                    color: primaryGreen,
                    bgColor: const Color(0xFFE8F5E9),
                    rows: [
                      _rasidRow(
                        'Gross Earning (Wt × Comm)',
                        '${totalWeightSoldKg.toStringAsFixed(2)} × ₹${finalCommPerKg.toStringAsFixed(2)} = ₹${grossEarning.toStringAsFixed(2)}',
                        smallText: true,
                      ),
                      if (!medInProdCost)
                        _rasidRow(
                          '− Medicine Deduction',
                          '−₹${totalMedicineCost.toStringAsFixed(2)}',
                          valueColor: Colors.red.shade700,
                        ),
                      _rasidDividerRow(),
                      _rasidRow(
                        '💵 Net Payout to Farmer',
                        '₹${netPayout.toStringAsFixed(2)}',
                        isBold: true,
                        valueColor: primaryGreen,
                        isLarge: true,
                      ),
                    ],
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '⚠️ Rule 2 — FCR Matrix Notice',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.deepOrange,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Rule 2 (FCR Matrix) ke liye settlement amount FCR '
                          'calculation ke baad manually decide hota hai. '
                          'Upar ki batch summary dekhke owner apna hisab lagayein.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // ── SHARE + DOWNLOAD BUTTONS ──────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _shareSettlementAsPdf(
                          ruleLabel: ruleLabel,
                          sizeLabel: sizeLabel,
                          initialChicks: initialChicks,
                          totalMortality: totalMortality,
                          totalChicksSold: totalChicksSold,
                          totalWeightSoldKg: totalWeightSoldKg,
                          totalSaleMoney: totalSaleMoney,
                          avgSaleRate: avgSaleRate,
                          latestAvgWeight: latestAvgWeight,
                          totalFeedBags: totalFeedBags,
                          totalFeedKg: totalFeedKg,
                          totalChickCost: totalChickCost,
                          totalFeedCost: totalFeedCost,
                          totalAdminCost: totalAdminCost,
                          totalMedicineCost: totalMedicineCost,
                          medInProdCost: medInProdCost,
                          totalProdCost: totalProdCost,
                          actualCostPerKg: actualCostPerKg,
                          targetCostPerKg: targetCostPerKg,
                          costDiff: costDiff,
                          baseCommPerKg: baseCommPerKg,
                          costAdjPerKg: costAdjPerKg,
                          costAdjLabel: costAdjLabel,
                          rateBonusApplied: rateBonusApplied,
                          rateBonusPerKg: rateBonusPerKg,
                          rateBonThresh: rateBonThresh,
                          finalCommPerKg: finalCommPerKg,
                          grossEarning: grossEarning,
                          netPayout: netPayout,
                          isRule2: isRule2,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(
                          Icons.share_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        label: const Text(
                          'Share PDF',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _downloadSettlementAsPdf(
                          ruleLabel: ruleLabel,
                          sizeLabel: sizeLabel,
                          initialChicks: initialChicks,
                          totalMortality: totalMortality,
                          totalChicksSold: totalChicksSold,
                          totalWeightSoldKg: totalWeightSoldKg,
                          totalSaleMoney: totalSaleMoney,
                          avgSaleRate: avgSaleRate,
                          latestAvgWeight: latestAvgWeight,
                          totalFeedBags: totalFeedBags,
                          totalFeedKg: totalFeedKg,
                          totalChickCost: totalChickCost,
                          totalFeedCost: totalFeedCost,
                          totalAdminCost: totalAdminCost,
                          totalMedicineCost: totalMedicineCost,
                          medInProdCost: medInProdCost,
                          totalProdCost: totalProdCost,
                          actualCostPerKg: actualCostPerKg,
                          targetCostPerKg: targetCostPerKg,
                          costDiff: costDiff,
                          baseCommPerKg: baseCommPerKg,
                          costAdjPerKg: costAdjPerKg,
                          costAdjLabel: costAdjLabel,
                          rateBonusApplied: rateBonusApplied,
                          rateBonusPerKg: rateBonusPerKg,
                          rateBonThresh: rateBonThresh,
                          finalCommPerKg: finalCommPerKg,
                          grossEarning: grossEarning,
                          netPayout: netPayout,
                          isRule2: isRule2,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(
                          Icons.download_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        label: const Text(
                          'Download PDF',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ── CLOSE BATCH BUTTON ────────────────────────────────────
                if (_liveBatchData['status']?.toString().toUpperCase() !=
                    'COMPLETED')
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _markBatchAsCompleted();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      label: const Text(
                        'Rasid Confirm — Batch Permanently Close Karo',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),

                if (_liveBatchData['status']?.toString().toUpperCase() !=
                    'COMPLETED')
                  const SizedBox(height: 8),

                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: primaryGreen),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: primaryGreen,
                      size: 18,
                    ),
                    label: const Text(
                      'Wapas Jao (Batch Abhi Band Mat Karo)',
                      style: TextStyle(
                        color: primaryGreen,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SHARE AS PDF
  // ===========================================================================

  Future<bool> _confirmSignaturesOrProceed() async {
    final missingFarmer = _farmerSignatureBytes == null;
    final missingOwner = _ownerSignatureBytes == null;
    if (!missingFarmer && !missingOwner) return true;

    if (!mounted) return true;

    final String message = missingFarmer && missingOwner
        ? 'Farmer aur Company Owner — dono ka signature abhi tak profile mein load nahi hua hai.'
        : missingFarmer
        ? 'Farmer ka signature abhi tak profile mein load nahi hua hai.'
        : 'Company Owner ka signature abhi tak profile mein load nahi hua hai.';

    final bool? proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Signature Missing'),
          ],
        ),
        content: Text(
          '$message\n\nPehle profile se signature load kar lo, taaki rasid mein '
          'digital signature dikhe. Agar abhi continue karoge to iske bajaye '
          'khaali jagah milegi jaha hand se sign kiya ja sakta hai.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
            ),
            child: const Text(
              'Continue Anyway',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    return proceed ?? false;
  }

  Future<void> _shareSettlementAsPdf({
    required String ruleLabel,
    required String sizeLabel,
    required int initialChicks,
    required int totalMortality,
    required int totalChicksSold,
    required double totalWeightSoldKg,
    required double totalSaleMoney,
    required double avgSaleRate,
    required double latestAvgWeight,
    required int totalFeedBags,
    required double totalFeedKg,
    required double totalChickCost,
    required double totalFeedCost,
    required double totalAdminCost,
    required double totalMedicineCost,
    required bool medInProdCost,
    required double totalProdCost,
    required double actualCostPerKg,
    required double targetCostPerKg,
    required double costDiff,
    required double baseCommPerKg,
    required double costAdjPerKg,
    required String costAdjLabel,
    required bool rateBonusApplied,
    required double rateBonusPerKg,
    required double rateBonThresh,
    required double finalCommPerKg,
    required double grossEarning,
    required double netPayout,
    bool isRule2 = false,
    bool skipSignatureCheck = false,
  }) async {
    if (!skipSignatureCheck && !await _confirmSignaturesOrProceed()) {
      return;
    }

    if (kIsWeb) {
      await _downloadSettlementAsPdf(
        ruleLabel: ruleLabel,
        sizeLabel: sizeLabel,
        initialChicks: initialChicks,
        totalMortality: totalMortality,
        totalChicksSold: totalChicksSold,
        totalWeightSoldKg: totalWeightSoldKg,
        totalSaleMoney: totalSaleMoney,
        avgSaleRate: avgSaleRate,
        latestAvgWeight: latestAvgWeight,
        totalFeedBags: totalFeedBags,
        totalFeedKg: totalFeedKg,
        totalChickCost: totalChickCost,
        totalFeedCost: totalFeedCost,
        totalAdminCost: totalAdminCost,
        totalMedicineCost: totalMedicineCost,
        medInProdCost: medInProdCost,
        totalProdCost: totalProdCost,
        actualCostPerKg: actualCostPerKg,
        targetCostPerKg: targetCostPerKg,
        costDiff: costDiff,
        baseCommPerKg: baseCommPerKg,
        costAdjPerKg: costAdjPerKg,
        costAdjLabel: costAdjLabel,
        rateBonusApplied: rateBonusApplied,
        rateBonusPerKg: rateBonusPerKg,
        rateBonThresh: rateBonThresh,
        finalCommPerKg: finalCommPerKg,
        grossEarning: grossEarning,
        netPayout: netPayout,
        isRule2: isRule2,
        skipSignatureCheck: true,
      );
      return;
    }
    try {
      Get.snackbar(
        '📤 PDF Taiyaar Ho Raha Hai...',
        'Thoda wait karo',
        backgroundColor: Colors.blue.shade700,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
        duration: const Duration(seconds: 3),
        icon: const Icon(Icons.hourglass_top_rounded, color: Colors.white),
      );

      final bytes = await _generateSettlementPdf(
        ruleLabel: ruleLabel,
        sizeLabel: sizeLabel,
        initialChicks: initialChicks,
        totalMortality: totalMortality,
        totalChicksSold: totalChicksSold,
        totalWeightSoldKg: totalWeightSoldKg,
        totalSaleMoney: totalSaleMoney,
        avgSaleRate: avgSaleRate,
        latestAvgWeight: latestAvgWeight,
        totalFeedBags: totalFeedBags,
        totalFeedKg: totalFeedKg,
        totalChickCost: totalChickCost,
        totalFeedCost: totalFeedCost,
        totalAdminCost: totalAdminCost,
        totalMedicineCost: totalMedicineCost,
        medInProdCost: medInProdCost,
        totalProdCost: totalProdCost,
        actualCostPerKg: actualCostPerKg,
        targetCostPerKg: targetCostPerKg,
        costDiff: costDiff,
        baseCommPerKg: baseCommPerKg,
        costAdjPerKg: costAdjPerKg,
        costAdjLabel: costAdjLabel,
        rateBonusApplied: rateBonusApplied,
        rateBonusPerKg: rateBonusPerKg,
        rateBonThresh: rateBonThresh,
        finalCommPerKg: finalCommPerKg,
        grossEarning: grossEarning,
        netPayout: netPayout,
        isRule2: isRule2,
      );

      final batchId =
          _liveBatchData['batchId'] ?? _liveBatchData['id'] ?? 'batch';

      if (!kIsWeb) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/Settlement_$batchId.pdf');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles([
          XFile(file.path, mimeType: 'application/pdf'),
        ], subject: 'Settlement Rasid — $batchId — Tracko App');
      } else {
        final fileName = 'Settlement_$batchId.pdf';
        await pdf_web.downloadPdfOnWeb(bytes, fileName);
        if (!mounted) return;
        Get.snackbar(
          '✅ PDF Downloaded!',
          '$fileName browser ke Downloads mein save ho gaya!',
          backgroundColor: Colors.green.shade700,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(15),
          duration: const Duration(seconds: 5),
          icon: const Icon(
            Icons.check_circle_rounded,
            color: Colors.white,
            size: 26,
          ),
        );
      }
    } catch (e) {
      Get.snackbar(
        '❌ Error',
        'PDF share failed: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
    }
  }

  // ===========================================================================
  // DOWNLOAD AS PDF — Direct Downloads Folder + Progress Snackbars
  // ===========================================================================

  Future<void> _downloadSettlementAsPdf({
    required String ruleLabel,
    required String sizeLabel,
    required int initialChicks,
    required int totalMortality,
    required int totalChicksSold,
    required double totalWeightSoldKg,
    required double totalSaleMoney,
    required double avgSaleRate,
    required double latestAvgWeight,
    required int totalFeedBags,
    required double totalFeedKg,
    required double totalChickCost,
    required double totalFeedCost,
    required double totalAdminCost,
    required double totalMedicineCost,
    required bool medInProdCost,
    required double totalProdCost,
    required double actualCostPerKg,
    required double targetCostPerKg,
    required double costDiff,
    required double baseCommPerKg,
    required double costAdjPerKg,
    required String costAdjLabel,
    required bool rateBonusApplied,
    required double rateBonusPerKg,
    required double rateBonThresh,
    required double finalCommPerKg,
    required double grossEarning,
    required double netPayout,
    bool isRule2 = false,
    bool skipSignatureCheck = false,
  }) async {
    if (!skipSignatureCheck && !await _confirmSignaturesOrProceed()) {
      return;
    }

    Get.snackbar(
      '📥 PDF Download Ho Raha Hai...',
      'Kripya wait karein — PDF ban rahi hai',
      backgroundColor: Colors.teal.shade700,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(15),
      duration: const Duration(seconds: 60),
      isDismissible: false,
      icon: const Icon(Icons.hourglass_bottom_rounded, color: Colors.white),
    );

    try {
      final bytes = await _generateSettlementPdf(
        ruleLabel: ruleLabel,
        sizeLabel: sizeLabel,
        initialChicks: initialChicks,
        totalMortality: totalMortality,
        totalChicksSold: totalChicksSold,
        totalWeightSoldKg: totalWeightSoldKg,
        totalSaleMoney: totalSaleMoney,
        avgSaleRate: avgSaleRate,
        latestAvgWeight: latestAvgWeight,
        totalFeedBags: totalFeedBags,
        totalFeedKg: totalFeedKg,
        totalChickCost: totalChickCost,
        totalFeedCost: totalFeedCost,
        totalAdminCost: totalAdminCost,
        totalMedicineCost: totalMedicineCost,
        medInProdCost: medInProdCost,
        totalProdCost: totalProdCost,
        actualCostPerKg: actualCostPerKg,
        targetCostPerKg: targetCostPerKg,
        costDiff: costDiff,
        baseCommPerKg: baseCommPerKg,
        costAdjPerKg: costAdjPerKg,
        costAdjLabel: costAdjLabel,
        rateBonusApplied: rateBonusApplied,
        rateBonusPerKg: rateBonusPerKg,
        rateBonThresh: rateBonThresh,
        finalCommPerKg: finalCommPerKg,
        grossEarning: grossEarning,
        netPayout: netPayout,
        isRule2: isRule2,
      );

      final batchId =
          _liveBatchData['batchId'] ?? _liveBatchData['id'] ?? 'batch';
      final fileName = 'Settlement_$batchId.pdf';

      Get.closeAllSnackbars();
      await Future.delayed(const Duration(milliseconds: 300));

      if (kIsWeb) {
        await pdf_web.downloadPdfOnWeb(bytes, fileName);
        if (!mounted) return;
        Get.snackbar(
          '✅ PDF Downloaded!',
          '$fileName browser ke Downloads mein save ho gaya!',
          backgroundColor: Colors.green.shade700,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(15),
          duration: const Duration(seconds: 5),
          icon: const Icon(
            Icons.check_circle_rounded,
            color: Colors.white,
            size: 26,
          ),
        );
      } else {
        Directory downloadsDir;
        try {
          downloadsDir = Directory('/storage/emulated/0/Download');
          if (!await downloadsDir.exists()) {
            final ext = await getExternalStorageDirectory();
            downloadsDir = ext ?? await getApplicationDocumentsDirectory();
          }
        } catch (_) {
          downloadsDir = await getApplicationDocumentsDirectory();
        }

        File file = File('${downloadsDir.path}/$fileName');
        bool savedToPublicDownloads = true;
        try {
          await file.writeAsBytes(bytes);
        } catch (_) {
          savedToPublicDownloads = false;
          final appDir =
              await getExternalStorageDirectory() ??
              await getApplicationDocumentsDirectory();
          final rasidFolder = Directory('${appDir.path}/Tracko_Rasid');
          if (!await rasidFolder.exists()) {
            await rasidFolder.create(recursive: true);
          }
          file = File('${rasidFolder.path}/$fileName');
          await file.writeAsBytes(bytes);
        }

        await _showDownloadNotification(
          fileName: fileName,
          filePath: file.path,
        );

        if (!mounted) return;
        Get.snackbar(
          '✅ PDF Downloaded!',
          savedToPublicDownloads
              ? 'Saved: Downloads/$fileName\nTap OPEN to view'
              : 'Saved: App Storage/Tracko_Rasid/$fileName\nTap OPEN to view',
          backgroundColor: Colors.green.shade700,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(15),
          duration: const Duration(seconds: 7),
          icon: const Icon(
            Icons.check_circle_rounded,
            color: Colors.white,
            size: 26,
          ),
          mainButton: TextButton(
            onPressed: () async {
              Get.closeAllSnackbars();
              try {
                await OpenFile.open(file.path);
              } catch (_) {
                await Share.shareXFiles([
                  XFile(file.path, mimeType: 'application/pdf'),
                ], subject: 'Settlement Rasid — $batchId');
              }
            },
            child: const Text(
              'OPEN',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      Get.closeAllSnackbars();
      await Future.delayed(const Duration(milliseconds: 200));
      Get.snackbar(
        '❌ Download Failed',
        'Error: $e',
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
    }
  }

  // ===========================================================================
  // MARK BATCH COMPLETED
  // ===========================================================================

  Future<void> _markBatchAsCompleted() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? farmersJson = prefs.getString('companyFarmers');
      if (farmersJson != null) {
        List<dynamic> farmersList = json.decode(farmersJson);
        for (var farmer in farmersList) {
          if (farmer['id'] == widget.farmerId) {
            for (var batch in (farmer['batches'] ?? [])) {
              if (batch['id'] == _liveBatchData['id']) {
                batch['status'] = 'COMPLETED';
                batch['completedOn'] = DateTime.now().toIso8601String();
                break;
              }
            }
            break;
          }
        }
        await CompanyStore.instance.setString(
          'companyFarmers',
          json.encode(farmersList),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    if (!mounted) return;
    Get.snackbar(
      'Batch Closed ✅',
      'Batch successfully close ho gaya. Settlement complete!',
      backgroundColor: primaryGreen,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(15),
    );
    await _loadFreshBatchData();
  }

  // ===========================================================================
  // RASID HELPER WIDGETS
  // ===========================================================================

  Widget _receiptHeaderRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rasidSection({
    required String title,
    required Color color,
    required Color bgColor,
    required List<Widget> rows,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rows,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rasidRow(
    String label,
    String value, {
    bool isBold = false,
    bool isLarge = false,
    bool smallText = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: TextStyle(
                fontSize: smallText ? 10 : 12,
                color: Colors.black54,
                fontStyle: smallText ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 4,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: isLarge ? 15 : (smallText ? 10 : 12),
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: valueColor ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rasidDividerRow() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Divider(height: 1, thickness: 1, color: Colors.black12),
    );
  }

  // ===========================================================================
  // DIALOGS
  // ===========================================================================

  void _showDailyEntryDialog() {
    final existingEntries = List<dynamic>.from(_dailyEntries);
    _mortalityPhotoBytes = null;
    _weightPhotoBytes = null;
    _remainingFeedPhotoBytes = null;
    _mortalityPhotoMismatch = false;
    _weightPhotoMismatch = false;
    _mortalityMismatchReason = null;
    _weightMismatchReason = null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Row(
              children: [
                const Icon(Icons.note_add_rounded, color: primaryGreen),
                const SizedBox(width: 8),
                Text(
                  'Flock Record (${widget.userRole})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => _pickDate(context, setDialogState),
                    child: AbsorbPointer(
                      child: TextField(
                        controller: _dateController,
                        decoration: const InputDecoration(
                          labelText: 'Tareekh (Date) *',
                          prefixIcon: Icon(Icons.date_range_rounded),
                          suffixIcon: Icon(Icons.calendar_today, size: 18),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ═══════════════════════════════════════════════════════
                  // 🏢 SECTION 1 — FEED (Owner / Office Manager hi bhar sakte)
                  // ═══════════════════════════════════════════════════════
                  if (widget.userRole == 'Owner' ||
                      widget.userRole == 'Office Manager') ...[
                    const Text(
                      '🏢 Feed Section (Owner / Office Manager)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _feedTypeInputBlock(
                      label: 'Starter Feed',
                      bagsCtrl: _feedStarterBagsController,
                      kgPerBagCtrl: _feedStarterKgPerBagController,
                      setDialogState: setDialogState,
                    ),
                    const SizedBox(height: 12),
                    _feedTypeInputBlock(
                      label: 'Grower Feed',
                      bagsCtrl: _feedGrowerBagsController,
                      kgPerBagCtrl: _feedGrowerKgPerBagController,
                      setDialogState: setDialogState,
                    ),
                    const SizedBox(height: 12),
                    _feedTypeInputBlock(
                      label: 'Finisher Feed',
                      bagsCtrl: _feedFinisherBagsController,
                      kgPerBagCtrl: _feedFinisherKgPerBagController,
                      setDialogState: setDialogState,
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                  ],

                  // ═══════════════════════════════════════════════════════
                  // 🌾 SECTION 2 — WEIGHT / MORTALITY / REMAINING FEED
                  // ═══════════════════════════════════════════════════════
                  if (widget.userRole == 'Owner' ||
                      widget.userRole == 'Field Manager') ...[
                    const Text(
                      '🌾 Field Manager Entries',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: primaryGreen,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),

                    TextField(
                      controller: _weightController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Average Weight (KG) *',
                        hintText: 'Sirf KG mein daalein, e.g. 1.8 ya 2.4',
                        prefixIcon: const Icon(Icons.monitor_weight_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _photoVerifyRow(
                      label: 'Taraju (Scale) Photo — optional',
                      photoBytes: _weightPhotoBytes,
                      mismatch: _weightPhotoMismatch,
                      mismatchReason: _weightMismatchReason,
                      onCapture: () =>
                          _captureAndVerifyWeightPhoto(setDialogState),
                      onRemove: () => setDialogState(() {
                        _weightPhotoBytes = null;
                        _weightPhotoMismatch = false;
                        _weightMismatchReason = null;
                      }),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _mortalityController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Mortality (Murgi Death Count) *',
                        hintText: 'e.g. 2',
                        prefixIcon: const Icon(Icons.analytics_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _photoVerifyRow(
                      label: 'Mortality Photo — optional',
                      photoBytes: _mortalityPhotoBytes,
                      mismatch: _mortalityPhotoMismatch,
                      mismatchReason: _mortalityMismatchReason,
                      onCapture: () =>
                          _captureAndVerifyMortalityPhoto(setDialogState),
                      onRemove: () => setDialogState(() {
                        _mortalityPhotoBytes = null;
                        _mortalityPhotoMismatch = false;
                        _mortalityMismatchReason = null;
                      }),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _remainingFeedController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Actual Remaining Feed (Bags) *',
                        hintText: 'Farm par abhi kitne bags bache hain',
                        prefixIcon: const Icon(Icons.inventory_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _photoVerifyRow(
                      label: 'Farm Feed Stock Photo — optional',
                      photoBytes: _remainingFeedPhotoBytes,
                      mismatch: false,
                      mismatchReason: null,
                      onCapture: () =>
                          _captureRemainingFeedPhoto(setDialogState),
                      onRemove: () => setDialogState(() {
                        _remainingFeedPhotoBytes = null;
                      }),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _weightController.clear();
                  _mortalityController.clear();
                  _feedStarterBagsController.clear();
                  _feedGrowerBagsController.clear();
                  _feedFinisherBagsController.clear();
                  _remainingFeedController.clear();
                  _mortalityPhotoBytes = null;
                  _weightPhotoBytes = null;
                  _remainingFeedPhotoBytes = null;
                  Navigator.pop(context);
                },
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: _verifyingPhoto
                    ? null
                    : () => _saveDailyLogEntryToStorage(
                        context,
                        existingEntries,
                        setDialogState,
                      ),
                style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
                child: const Text(
                  'Save Entry',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── ✅ NEW: Return Feed Dialog ────────────────────────────────────────
  void _showReturnFeedDialog({required VoidCallback onDone}) {
    _returnFeedKgController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.assignment_return_rounded, color: Colors.teal),
            SizedBox(width: 8),
            Text(
              'Return Feed 📦',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Agar farmer ke farm se koi feed WAAPAS aaya hai (unused), '
              'to uska total KG yahan darj karo. Ye Total Feed Consumption '
              'se minus hoke Settlement Rasid mein use hoga.',
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.black54,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _returnFeedKgController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Return Feed (KG)',
                hintText: 'e.g. 45.5',
                prefixIcon: const Icon(Icons.inventory_2_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDone(); // skip — seedha batch end confirmation pe jao
            },
            child: const Text('Skip', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
            ),
            onPressed: () async {
              final kg =
                  double.tryParse(_returnFeedKgController.text.trim()) ?? 0.0;
              Navigator.pop(ctx);
              if (kg > 0) {
                await _saveReturnFeedEntryToStorage(kg);
              }
              onDone();
            },
            child: const Text(
              'Save & Continue',
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

  Future<void> _saveReturnFeedEntryToStorage(double kg) async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? farmersJson = prefs.getString('companyFarmers');
      if (farmersJson != null) {
        List<dynamic> farmersList = json.decode(farmersJson);
        final Map<String, dynamic> returnEntry = {
          'type': 'returnFeed',
          'date': _formatDate(DateTime.now()),
          'returnFeedKg': kg,
          'enteredBy': widget.userRole,
          'timestamp': DateTime.now().toIso8601String(),
        };
        for (var farmerItem in farmersList) {
          if (farmerItem['id'] == widget.farmerId) {
            for (var batchItem in (farmerItem['batches'] ?? [])) {
              if (batchItem['id'] == _liveBatchData['id']) {
                batchItem['dailyEntries'] ??= [];
                batchItem['dailyEntries'].add(returnEntry);
                break;
              }
            }
            break;
          }
        }
        await CompanyStore.instance.setString(
          'companyFarmers',
          json.encode(farmersList),
        );
        await _loadFreshBatchData();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    if (!mounted) return;
    Get.snackbar(
      'Return Feed Saved ✅',
      '${kg.toStringAsFixed(1)} KG return feed record ho gaya.',
      backgroundColor: Colors.teal.shade700,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(15),
    );
  }

  Widget _feedTypeInputBlock({
    required String label,
    required TextEditingController bagsCtrl,
    required TextEditingController kgPerBagCtrl,
    required StateSetter setDialogState,
  }) {
    final bags = double.tryParse(bagsCtrl.text.trim()) ?? 0.0;
    final kgPerBag = double.tryParse(kgPerBagCtrl.text.trim()) ?? 0.0;
    final totalKg = bags * kgPerBag;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: bagsCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Bags',
                    hintText: '0',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: kgPerBagCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Per Bag (KG)',
                    hintText: '50.0',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Total: ${totalKg.toStringAsFixed(1)} KG',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primaryGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoVerifyRow({
    required String label,
    required Uint8List? photoBytes,
    required bool mismatch,
    required String? mismatchReason,
    required VoidCallback onCapture,
    required VoidCallback onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
            if (photoBytes != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.red),
                onPressed: onRemove,
                tooltip: 'Photo hatao',
              ),
            IconButton(
              icon: Icon(
                photoBytes == null
                    ? Icons.camera_alt_outlined
                    : Icons.camera_alt,
                color: primaryGreen,
              ),
              onPressed: _verifyingPhoto ? null : onCapture,
              tooltip: 'Camera se photo lo',
            ),
          ],
        ),
        if (_verifyingPhoto)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text(
                  'Photo verify ho rahi hai...',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
        if (photoBytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              photoBytes,
              height: 90,
              width: 90,
              fit: BoxFit.cover,
            ),
          ),
        if (mismatch && mismatchReason != null)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              '⚠️ $mismatchReason',
              style: TextStyle(fontSize: 11, color: Colors.red.shade700),
            ),
          ),
      ],
    );
  }

  Future<void> _captureAndVerifyMortalityPhoto(
    StateSetter setDialogState,
  ) async {
    if (kIsWeb) {
      Get.snackbar(
        'Not Supported',
        'Camera-verify web par available nahi hai.',
        backgroundColor: Colors.orange.shade700,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final XFile? shot = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );
    if (shot == null) return;

    setDialogState(() => _verifyingPhoto = true);
    ObjectDetector? detector;
    try {
      final bytes = await shot.readAsBytes();
      final enteredMortality =
          int.tryParse(_mortalityController.text.trim()) ?? 0;

      detector = ObjectDetector(
        options: ObjectDetectorOptions(
          mode: DetectionMode.single,
          classifyObjects: false,
          multipleObjects: true,
        ),
      );
      final inputImage = InputImage.fromFilePath(shot.path);
      final detected = await detector.processImage(inputImage);
      final detectedCount = detected.length;

      bool mismatch = detectedCount != enteredMortality;
      String? reason;
      if (mismatch) {
        reason =
            'Photo mein ~$detectedCount object(s) detect hue, lekin '
            'entered mortality $enteredMortality hai. Kripya dobara check karein.';
      }

      setDialogState(() {
        _mortalityPhotoBytes = bytes;
        _mortalityPhotoMismatch = mismatch;
        _mortalityMismatchReason = reason;
        _verifyingPhoto = false;
      });

      if (mismatch && mounted) {
        _showMismatchWarningDialog(
          title: 'Mortality Mismatch ⚠️',
          message: reason!,
        );
      }
    } catch (e) {
      setDialogState(() {
        _mortalityPhotoBytes = null;
        _mortalityPhotoMismatch = false;
        _mortalityMismatchReason = null;
        _verifyingPhoto = false;
      });
      Get.snackbar(
        'Verify Failed',
        'Photo verify nahi ho payi: $e',
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      await detector?.close();
    }
  }

  Future<void> _captureAndVerifyWeightPhoto(StateSetter setDialogState) async {
    if (kIsWeb) {
      Get.snackbar(
        'Not Supported',
        'Camera-verify web par available nahi hai.',
        backgroundColor: Colors.orange.shade700,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final XFile? shot = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );
    if (shot == null) return;

    setDialogState(() => _verifyingPhoto = true);
    TextRecognizer? recognizer;
    try {
      final bytes = await shot.readAsBytes();
      final enteredWeight =
          double.tryParse(_weightController.text.trim()) ?? 0.0;

      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFilePath(shot.path);
      final recognizedText = await recognizer.processImage(inputImage);
      final scaleReading = _extractLikelyWeightFromText(
        recognizedText.text,
        enteredWeight,
      );

      bool mismatch = false;
      String? reason;
      if (scaleReading == null) {
        mismatch = true;
        reason =
            'Scale ka reading photo mein clear nahi mila. Entered weight: '
            '${enteredWeight.toStringAsFixed(2)} KG — kripya dobara photo lein.';
      } else {
        final tolerance = (enteredWeight * 0.10).clamp(0.15, 5.0);
        if ((scaleReading - enteredWeight).abs() > tolerance) {
          mismatch = true;
          reason =
              'Scale photo mein ~${scaleReading.toStringAsFixed(2)} KG dikha, '
              'lekin entered weight ${enteredWeight.toStringAsFixed(2)} KG hai.';
        }
      }

      setDialogState(() {
        _weightPhotoBytes = bytes;
        _weightPhotoMismatch = mismatch;
        _weightMismatchReason = reason;
        _verifyingPhoto = false;
      });

      if (mismatch && mounted) {
        _showMismatchWarningDialog(
          title: 'Weight Mismatch ⚠️',
          message: reason!,
        );
      }
    } catch (e) {
      setDialogState(() {
        _weightPhotoBytes = null;
        _weightPhotoMismatch = false;
        _weightMismatchReason = null;
        _verifyingPhoto = false;
      });
      Get.snackbar(
        'Verify Failed',
        'Photo verify nahi ho payi: $e',
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      await recognizer?.close();
    }
  }

  Future<void> _captureRemainingFeedPhoto(StateSetter setDialogState) async {
    if (kIsWeb) {
      Get.snackbar(
        'Not Supported',
        'Camera web par available nahi hai.',
        backgroundColor: Colors.orange.shade700,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final XFile? shot = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );
    if (shot == null) return;
    final bytes = await shot.readAsBytes();
    setDialogState(() => _remainingFeedPhotoBytes = bytes);
  }

  void _showMismatchWarningDialog({
    required String title,
    required String message,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15))),
          ],
        ),
        content: Text(
          '$message\n\nAap fir bhi ye entry save kar sakte hain, lekin ye '
          'din Daily Update List mein LAL (red) dikhega aur reason neeche '
          'likha hoga taaki office isko dekh sake.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Samajh Gaya',
              style: TextStyle(
                color: primaryGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double? _extractLikelyWeightFromText(String text, double enteredWeight) {
    final matches = RegExp(r'\d+\.?\d*').allMatches(text);
    double? best;
    double bestDiff = double.infinity;
    for (final m in matches) {
      final val = double.tryParse(m.group(0) ?? '');
      if (val == null || val <= 0) continue;
      final diff = enteredWeight > 0 ? (val - enteredWeight).abs() : 0.0;
      if (diff < bestDiff) {
        bestDiff = diff;
        best = val;
      }
    }
    return best;
  }

  void _showSalesEntryDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          double soldChicks =
              double.tryParse(_soldChicksController.text.trim()) ?? 0;
          double totalWeight =
              double.tryParse(_totalWeightSoldController.text.trim()) ?? 0;
          double pricePerKg =
              double.tryParse(_pricePerKgController.text.trim()) ?? 0;
          double calculatedAvgWeight = soldChicks > 0
              ? (totalWeight / soldChicks)
              : 0.0;
          double calculatedTotalMoney = totalWeight * pricePerKg;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Row(
              children: [
                Icon(Icons.monetization_on_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Nayi Sales Entry 💰',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _buyerNameController,
                    decoration: InputDecoration(
                      labelText: 'Kharidne Wale ka Name *',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _soldChicksController,
                    keyboardType: TextInputType.number,
                    onChanged: (val) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Total Chicks Sold Count *',
                      prefixIcon: const Icon(Icons.tag),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _totalWeightSoldController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (val) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Total Weight Sold (KG) *',
                      prefixIcon: const Icon(Icons.scale_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pricePerKgController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (val) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Price Per KG (₹) *',
                      prefixIcon: const Icon(Icons.currency_rupee),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Chicks Avg Wt (Autofill):',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                            Text(
                              '${calculatedAvgWeight.toStringAsFixed(3)} kg',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total Money (Autofill):',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                            Text(
                              '₹${calculatedTotalMoney.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _buyerNameController.clear();
                  _soldChicksController.clear();
                  _totalWeightSoldController.clear();
                  _pricePerKgController.clear();
                  Navigator.pop(context);
                },
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: () => _saveSalesEntryToStorage(
                  context,
                  calculatedAvgWeight,
                  calculatedTotalMoney,
                ),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text(
                  'Save Sale',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showMedicineEntryDialog() {
    List<Map<String, dynamic>> stockMedicines = [];
    Map<String, dynamic>? matchedStockMed;
    bool isStockLinked = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Row(
              children: [
                Icon(Icons.medical_services_rounded, color: Colors.purple),
                SizedBox(width: 8),
                Text(
                  'Nayi Medicine Entry 💊',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _medicineNameController,
                    onChanged: (val) async {
                      final prefs = await SharedPreferences.getInstance();
                      final String? medJson = prefs.getString(
                        'medicineStockList',
                      );
                      if (medJson != null) {
                        stockMedicines = List<Map<String, dynamic>>.from(
                          json.decode(medJson),
                        );
                      }
                      String input = val.trim().toLowerCase();
                      Map<String, dynamic>? found;
                      if (input.isNotEmpty) {
                        try {
                          found = stockMedicines.firstWhere(
                            (m) =>
                                (m['nickName'] ?? '')
                                        .toString()
                                        .toLowerCase() ==
                                    input ||
                                (m['name'] ?? '').toString().toLowerCase() ==
                                    input,
                          );
                        } catch (_) {
                          found = null;
                        }
                      }
                      setDialogState(() {
                        matchedStockMed = found;
                        isStockLinked = found != null;
                        if (found != null) {
                          double remaining = (found['remainingQuantity'] as num)
                              .toDouble();
                          double total = (found['totalQuantity'] as num)
                              .toDouble();
                          double price = (found['totalPrice'] as num)
                              .toDouble();
                          double pricePerUnit = total > 0 ? price / total : 0.0;
                          _medicineQuantityController.text = remaining
                              .toStringAsFixed(2);
                          _medicinePriceController.text =
                              (remaining * pricePerUnit).toStringAsFixed(2);
                          _selectedMedicineUnit = found['unit'] ?? 'ml';
                        }
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Nick Name / Medicine Naam *',
                      hintText: 'Nick name type karo (e.g. "Enro")',
                      prefixIcon: const Icon(Icons.medication_rounded),
                      suffixIcon: isStockLinked
                          ? const Icon(Icons.link_rounded, color: Colors.teal)
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  if (isStockLinked && matchedStockMed != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Colors.teal,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '✅ Stock Linked: ${matchedStockMed!['name']}\n'
                              'Bacha Hua: ${(matchedStockMed!['remainingQuantity'] as num).toStringAsFixed(2)} ${matchedStockMed!['unit']}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.teal.shade800,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (!isStockLinked) ...[
                    const SizedBox(height: 6),
                    Text(
                      '💡 Tip: Nick name se match hone par stock se auto-fill hoga',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _medicineQuantityController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) {
                            if (isStockLinked && matchedStockMed != null) {
                              double qty =
                                  double.tryParse(
                                    _medicineQuantityController.text.trim(),
                                  ) ??
                                  0.0;
                              double total =
                                  (matchedStockMed!['totalQuantity'] as num)
                                      .toDouble();
                              double price =
                                  (matchedStockMed!['totalPrice'] as num)
                                      .toDouble();
                              double pricePerUnit = total > 0
                                  ? price / total
                                  : 0.0;
                              setDialogState(() {
                                _medicinePriceController.text =
                                    (qty * pricePerUnit).toStringAsFixed(2);
                              });
                            }
                          },
                          decoration: InputDecoration(
                            labelText: 'Quantity *',
                            prefixIcon: const Icon(
                              Icons.production_quantity_limits,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: _selectedMedicineUnit,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                          ),
                          items: _medicineUnitsList
                              .map(
                                (String unit) => DropdownMenuItem<String>(
                                  value: unit,
                                  child: Text(
                                    unit,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => _selectedMedicineUnit = val);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _medicinePriceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    readOnly: isStockLinked,
                    decoration: InputDecoration(
                      labelText: isStockLinked
                          ? 'Auto-Calculated Price (₹)'
                          : 'Kharid Price (₹) *',
                      prefixIcon: const Icon(Icons.currency_rupee),
                      filled: isStockLinked,
                      fillColor: isStockLinked ? Colors.grey.shade100 : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  if (isStockLinked && matchedStockMed != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Text(
                        '⚠️ Save karne par stock se ye quantity automatically kat jayegi',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _medicineNameController.clear();
                  _medicineQuantityController.clear();
                  _medicinePriceController.clear();
                  Navigator.pop(context);
                },
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: () => _saveMedicineEntryToStorage(
                  context,
                  stockMedicine: matchedStockMed,
                ),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                child: const Text(
                  'Save Med',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ===========================================================================
  // SAVE METHODS
  // ===========================================================================

  Future<void> _saveDailyLogEntryToStorage(
    BuildContext dialogContext,
    List<dynamic> existingEntries,
    StateSetter setDialogState,
  ) async {
    if (_isLoading) return;

    String weightInput = _weightController.text.trim();
    String mortalityInput = _mortalityController.text.trim();
    String starterBagsInput = _feedStarterBagsController.text.trim();
    String growerBagsInput = _feedGrowerBagsController.text.trim();
    String finisherBagsInput = _feedFinisherBagsController.text.trim();
    double starterKgPerBag =
        double.tryParse(_feedStarterKgPerBagController.text.trim()) ?? 50.0;
    double growerKgPerBag =
        double.tryParse(_feedGrowerKgPerBagController.text.trim()) ?? 50.0;
    double finisherKgPerBag =
        double.tryParse(_feedFinisherKgPerBagController.text.trim()) ?? 50.0;
    String dateInput = _dateController.text.trim();
    String remainingFeedInput = _remainingFeedController.text.trim();

    bool anyFeedEntered =
        starterBagsInput.isNotEmpty ||
        growerBagsInput.isNotEmpty ||
        finisherBagsInput.isNotEmpty;

    if (weightInput.isEmpty &&
        mortalityInput.isEmpty &&
        !anyFeedEntered &&
        remainingFeedInput.isEmpty) {
      Get.snackbar(
        'Validation Error ⚠️',
        'Kripya kam se kam ek entry bharein!',
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      return;
    }

    double? weightVal = double.tryParse(weightInput);
    int? mortalityVal = int.tryParse(mortalityInput);
    int starterBags = int.tryParse(starterBagsInput) ?? 0;
    int growerBags = int.tryParse(growerBagsInput) ?? 0;
    int finisherBags = int.tryParse(finisherBagsInput) ?? 0;
    int feedVal = starterBags + growerBags + finisherBags;
    int? remainingVal = int.tryParse(remainingFeedInput);

    if ((weightVal != null && weightVal < 0) ||
        (mortalityVal != null && mortalityVal < 0) ||
        (remainingVal != null && remainingVal < 0)) {
      Get.snackbar(
        'Invalid Value ⚠️',
        'Weight, Mortality aur Remaining Feed negative nahi ho sakti!',
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      return;
    }

    if (feedVal < 0) {
      int currentTotalFeed = 0;
      for (var e in _dailyEntries) {
        if (e['type'].toString().toLowerCase() == 'cost') {
          currentTotalFeed += int.tryParse(e['feed'].toString()) ?? 0;
        }
      }
      if ((currentTotalFeed + feedVal) < 0) {
        Get.snackbar(
          'Invalid Correction ⚠️',
          'Total Feed Bags $currentTotalFeed hain. Itna minus nahi kar sakte!',
          backgroundColor: Colors.red.shade600,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(15),
        );
        return;
      }
    }

    if (mortalityVal != null && mortalityVal > 0) {
      int initialChicks = _liveBatchData['chicksCount'] ?? 0;
      int totalMortalitySoFar = 0;
      int totalChicksSoldSoFar = 0;
      for (var e in _dailyEntries) {
        if (e['type'].toString().toLowerCase() == 'cost') {
          totalMortalitySoFar += int.tryParse(e['mortality'].toString()) ?? 0;
        } else if (e['type'].toString().toLowerCase() == 'sale') {
          totalChicksSoldSoFar += int.tryParse(e['chicksSold'].toString()) ?? 0;
        }
      }
      int currentLiveChicks =
          initialChicks - totalMortalitySoFar - totalChicksSoldSoFar;
      if (mortalityVal > currentLiveChicks) {
        Get.snackbar(
          'Invalid Mortality ⚠️',
          'Mortality ($mortalityVal) live chicks ($currentLiveChicks) se jyada nahi ho sakti!',
          backgroundColor: Colors.red.shade600,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(15),
        );
        return;
      }
    }

    int sameDateCostCount = existingEntries
        .where(
          (e) =>
              e['type'].toString().toLowerCase() == 'cost' &&
              e['date'].toString() == dateInput,
        )
        .length;
    if (sameDateCostCount >= 3) {
      Get.snackbar(
        'Limit Reached ⚠️',
        '$dateInput ko 3 cost entries pehle se save hain. Max 3 allowed!',
        backgroundColor: Colors.orange.shade700,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      return;
    }

    double starterKg = starterBags * starterKgPerBag;
    double growerKg = growerBags * growerKgPerBag;
    double finisherKg = finisherBags * finisherKgPerBag;
    double totalFeedKg = starterKg + growerKg + finisherKg;

    final bool hasMismatch = _mortalityPhotoMismatch || _weightPhotoMismatch;
    final List<String> mismatchReasons = [
      if (_mortalityPhotoMismatch && _mortalityMismatchReason != null)
        _mortalityMismatchReason!,
      if (_weightPhotoMismatch && _weightMismatchReason != null)
        _weightMismatchReason!,
    ];

    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? farmersJson = prefs.getString('companyFarmers');
      if (farmersJson != null) {
        List<dynamic> farmersList = json.decode(farmersJson);
        final Map<String, dynamic> logEntry = {
          'type': 'cost',
          'date': dateInput,
          'weight': weightInput.isEmpty ? '0' : weightInput,
          'mortality': mortalityInput.isEmpty ? '0' : mortalityInput,
          'feed': feedVal.toString(),
          'feedStarterBags': starterBags,
          'feedGrowerBags': growerBags,
          'feedFinisherBags': finisherBags,
          'feedStarterKgPerBag': starterKgPerBag,
          'feedGrowerKgPerBag': growerKgPerBag,
          'feedFinisherKgPerBag': finisherKgPerBag,
          'feedTotalKg': totalFeedKg,
          'remainingFeed': remainingFeedInput.isEmpty
              ? '0'
              : remainingFeedInput,
          'enteredBy': widget.userRole,
          'timestamp': DateTime.now().toIso8601String(),
          if (_mortalityPhotoBytes != null)
            'mortalityPhotoBase64': base64Encode(_mortalityPhotoBytes!),
          if (_weightPhotoBytes != null)
            'weightPhotoBase64': base64Encode(_weightPhotoBytes!),
          if (_remainingFeedPhotoBytes != null)
            'remainingFeedPhotoBase64': base64Encode(_remainingFeedPhotoBytes!),
          'hasMismatch': hasMismatch,
          if (mismatchReasons.isNotEmpty)
            'mismatchReason': mismatchReasons.join(' | '),
        };
        for (var farmerItem in farmersList) {
          if (farmerItem['id'] == widget.farmerId) {
            for (var batchItem in (farmerItem['batches'] ?? [])) {
              if (batchItem['id'] == _liveBatchData['id']) {
                batchItem['dailyEntries'] ??= [];
                batchItem['dailyEntries'].add(logEntry);
                break;
              }
            }
            break;
          }
        }
        await CompanyStore.instance.setString(
          'companyFarmers',
          json.encode(farmersList),
        );
        _weightController.clear();
        _mortalityController.clear();
        _feedStarterBagsController.clear();
        _feedGrowerBagsController.clear();
        _feedFinisherBagsController.clear();
        _remainingFeedController.clear();
        _mortalityPhotoBytes = null;
        _weightPhotoBytes = null;
        _remainingFeedPhotoBytes = null;
        _mortalityPhotoMismatch = false;
        _weightPhotoMismatch = false;
        _mortalityMismatchReason = null;
        _weightMismatchReason = null;
        await _loadFreshBatchData();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    if (!mounted) return;
    Navigator.pop(dialogContext);
    Get.snackbar(
      'Saved ✅',
      'Rozana ka cost data save ho gaya!',
      backgroundColor: primaryGreen,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  Future<void> _saveSalesEntryToStorage(
    BuildContext dialogContext,
    double calculatedAvgWeight,
    double calculatedTotalMoney,
  ) async {
    if (_isLoading) return;

    String buyerName = _buyerNameController.text.trim();
    String soldChicksStr = _soldChicksController.text.trim();
    String totalWeight = _totalWeightSoldController.text.trim();
    String pricePerKg = _pricePerKgController.text.trim();

    if (buyerName.isEmpty ||
        soldChicksStr.isEmpty ||
        totalWeight.isEmpty ||
        pricePerKg.isEmpty) {
      Get.snackbar(
        'Error ⚠️',
        'Saari fields bharna compulsory hai',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    int soldChicksVal = int.tryParse(soldChicksStr) ?? 0;
    double totalWeightVal = double.tryParse(totalWeight) ?? 0.0;
    double priceVal = double.tryParse(pricePerKg) ?? 0.0;

    if (soldChicksVal <= 0 || totalWeightVal <= 0 || priceVal <= 0) {
      Get.snackbar(
        'Invalid Value ⚠️',
        'Sold chicks, weight aur price zero ya negative nahi ho sakti!',
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    int initialChicks = _liveBatchData['chicksCount'] ?? 0;
    int totalMortalitySoFar = 0;
    int totalChicksSoldSoFar = 0;
    for (var e in _dailyEntries) {
      if (e['type'].toString().toLowerCase() == 'cost') {
        totalMortalitySoFar += int.tryParse(e['mortality'].toString()) ?? 0;
      } else if (e['type'].toString().toLowerCase() == 'sale') {
        totalChicksSoldSoFar += int.tryParse(e['chicksSold'].toString()) ?? 0;
      }
    }
    int currentLiveChicks =
        initialChicks - totalMortalitySoFar - totalChicksSoldSoFar;

    if (soldChicksVal > currentLiveChicks) {
      Get.snackbar(
        'Invalid Sale ⚠️',
        'Sold chicks ($soldChicksVal) live chicks ($currentLiveChicks) se jyada nahi ho sakta!',
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? farmersJson = prefs.getString('companyFarmers');
      if (farmersJson != null) {
        List<dynamic> farmersList = json.decode(farmersJson);
        final Map<String, dynamic> saleEntry = {
          'type': 'sale',
          'date': _formatDate(DateTime.now()),
          'buyerName': buyerName,
          'chicksSold': soldChicksStr,
          'totalWeightSold': totalWeight,
          'pricePerKg': pricePerKg,
          'avgWeightSold': calculatedAvgWeight.toStringAsFixed(3),
          'totalMoney': calculatedTotalMoney.toStringAsFixed(2),
          'enteredBy': widget.userRole,
          'timestamp': DateTime.now().toIso8601String(),
        };
        for (var farmerItem in farmersList) {
          if (farmerItem['id'] == widget.farmerId) {
            for (var batchItem in (farmerItem['batches'] ?? [])) {
              if (batchItem['id'] == _liveBatchData['id']) {
                batchItem['dailyEntries'] ??= [];
                batchItem['dailyEntries'].add(saleEntry);
                break;
              }
            }
            break;
          }
        }
        await CompanyStore.instance.setString(
          'companyFarmers',
          json.encode(farmersList),
        );
        _buyerNameController.clear();
        _soldChicksController.clear();
        _totalWeightSoldController.clear();
        _pricePerKgController.clear();
        await _loadFreshBatchData();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    if (!mounted) return;
    Navigator.pop(dialogContext);
    Get.snackbar(
      'Sold Success 🎉',
      'Sales record permanently save ho gaya!',
      backgroundColor: Colors.orange,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  Future<void> _saveMedicineEntryToStorage(
    BuildContext dialogContext, {
    Map<String, dynamic>? stockMedicine,
  }) async {
    if (_isLoading) return;

    String medName = _medicineNameController.text.trim();
    String qty = _medicineQuantityController.text.trim();
    String price = _medicinePriceController.text.trim();

    if (medName.isEmpty || qty.isEmpty || price.isEmpty) {
      Get.snackbar(
        'Error ⚠️',
        'Saari fields bharna compulsory hai',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    double? qtyVal = double.tryParse(qty);
    double? priceVal = double.tryParse(price);

    if ((qtyVal != null && qtyVal <= 0) || (priceVal != null && priceVal < 0)) {
      Get.snackbar(
        'Invalid Value ⚠️',
        'Quantity aur price valid honi chahiye!',
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    if (stockMedicine != null && qtyVal != null) {
      double remaining = (stockMedicine['remainingQuantity'] as num).toDouble();
      if (qtyVal > remaining + 0.0001) {
        Get.snackbar(
          'Stock Kam Hai ⚠️',
          'Sirf ${remaining.toStringAsFixed(2)} ${stockMedicine['unit']} bacha hai stock mein.',
          backgroundColor: Colors.red.shade600,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(15),
        );
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final String? medJson = prefs.getString('medicineStockList');
      if (medJson != null) {
        List<dynamic> stockList = json.decode(medJson);
        for (var item in stockList) {
          if (item['id'] == stockMedicine['id']) {
            item['remainingQuantity'] = remaining - qtyVal;
            break;
          }
        }
        await prefs.setString('medicineStockList', json.encode(stockList));
      }
    }

    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? farmersJson = prefs.getString('companyFarmers');
      if (farmersJson != null) {
        List<dynamic> farmersList = json.decode(farmersJson);
        final Map<String, dynamic> medicineEntry = {
          'type': 'medicine',
          'date': _formatDate(DateTime.now()),
          'medicineName': stockMedicine != null
              ? stockMedicine['name']
              : medName,
          'quantity': qty,
          'unit': _selectedMedicineUnit,
          'price': priceVal ?? 0.0,
          'stockLinked': stockMedicine != null,
          'enteredBy': widget.userRole,
          'timestamp': DateTime.now().toIso8601String(),
        };
        for (var farmerItem in farmersList) {
          if (farmerItem['id'] == widget.farmerId) {
            for (var batchItem in (farmerItem['batches'] ?? [])) {
              if (batchItem['id'] == _liveBatchData['id']) {
                batchItem['dailyEntries'] ??= [];
                batchItem['dailyEntries'].add(medicineEntry);
                break;
              }
            }
            break;
          }
        }
        await CompanyStore.instance.setString(
          'companyFarmers',
          json.encode(farmersList),
        );
        _medicineNameController.clear();
        _medicineQuantityController.clear();
        _medicinePriceController.clear();
        await _loadFreshBatchData();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    if (!mounted) return;
    Navigator.pop(dialogContext);
    Get.snackbar(
      stockMedicine != null ? 'Stock Updated ✅' : 'Saved ✅',
      stockMedicine != null
          ? '${stockMedicine['name']} — $qty ${stockMedicine['unit']} stock se kat gaya.'
          : 'Medicine distribution metrics updated successfully.',
      backgroundColor: Colors.purple,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  // ===========================================================================
  // QUICK ACTION CARD
  // ===========================================================================

  Widget _buildQuickActionCard({
    required String label,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: Colors.grey.shade200, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: accentColor, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // MAIN BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    int initialChicks = _liveBatchData['chicksCount'] ?? 0;
    int totalMortality = 0;
    int totalFeedBags = 0;
    double totalFeedKgSum = 0.0;
    int totalChicksSold = 0;
    double latestAvgWeight = 0.0;
    double totalWeightSoldKg = 0.0;
    double totalSaleMoney = 0.0;
    double totalMedicineExpense = 0.0;
    String actualRemainingBags = '0';
    bool hasRemainingFeedLogged = false;
    double totalReturnFeedKg = 0.0;

    for (var entry in _dailyEntries) {
      String currentType = entry['type'].toString().toLowerCase();
      if (currentType == 'sale') {
        int sold =
            int.tryParse(entry['chicksSold'].toString().trim()) ??
            double.tryParse(entry['chicksSold'].toString().trim())?.toInt() ??
            0;
        totalChicksSold += sold;
        totalWeightSoldKg +=
            double.tryParse(entry['totalWeightSold'].toString()) ?? 0.0;
        totalSaleMoney +=
            double.tryParse(entry['totalMoney'].toString()) ?? 0.0;
        double saleAvgWt =
            double.tryParse(entry['avgWeightSold'].toString()) ?? 0.0;
        if (saleAvgWt > 0.0 && latestAvgWeight == 0.0)
          latestAvgWeight = saleAvgWt;
      } else if (currentType == 'cost') {
        totalMortality += int.tryParse(entry['mortality'].toString()) ?? 0;
        int entryFeedBags = int.tryParse(entry['feed'].toString()) ?? 0;
        totalFeedBags += entryFeedBags;
        totalFeedKgSum += (entry['feedTotalKg'] is num)
            ? (entry['feedTotalKg'] as num).toDouble()
            : entryFeedBags * 50.0;
        double wt = double.tryParse(entry['weight'].toString()) ?? 0.0;
        if (wt > 0.0) latestAvgWeight = wt;
        if (entry['remainingFeed'] != null && entry['remainingFeed'] != '0') {
          actualRemainingBags = entry['remainingFeed'].toString();
          hasRemainingFeedLogged = true;
        }
      } else if (currentType == 'medicine') {
        totalMedicineExpense +=
            double.tryParse(entry['price'].toString()) ?? 0.0;
      } else if (currentType == 'returnfeed') {
        totalReturnFeedKg += (entry['returnFeedKg'] is num)
            ? (entry['returnFeedKg'] as num).toDouble()
            : double.tryParse(entry['returnFeedKg'].toString()) ?? 0.0;
      }
    }

    double netTotalFeedKgSum = totalFeedKgSum - totalReturnFeedKg;
    if (netTotalFeedKgSum < 0) netTotalFeedKgSum = 0.0;
    int netTotalFeedBags = (netTotalFeedKgSum / 50.0).round();

    int liveChicks = initialChicks - totalMortality - totalChicksSold;
    double mortalityPercent = initialChicks > 0
        ? (totalMortality / initialChicks) * 100
        : 0.0;
    int chicksAgeDays = _calculateChicksDaysOld(
      _liveBatchData['startDate'] ?? '',
    );
    int idealTargetWeight = _getAppStandardTargetWeight(chicksAgeDays);

    DateTime batchStartDate;
    try {
      final parts = (_liveBatchData['startDate'] ?? '').toString().split('/');
      batchStartDate = parts.length == 3
          ? DateTime(
              int.parse(parts[2]),
              int.parse(parts[1]),
              int.parse(parts[0]),
            )
          : DateTime.now();
    } catch (_) {
      batchStartDate = DateTime.now();
    }

    final int feedLoopDays = chicksAgeDays + 1;
    double totalExpectedConsumedKg = 0.0;
    for (int day = 1; day <= feedLoopDays; day++) {
      totalExpectedConsumedKg += FeedConsumptionEngine.calculateDayFeedKg(
        config: _feedRuleConfig,
        liveChicks: initialChicks,
        dayNumber: day,
        entryDate: batchStartDate.add(Duration(days: day - 1)),
      );
    }

    double engineEstimatedRemainingKg =
        netTotalFeedKgSum - totalExpectedConsumedKg;
    if (engineEstimatedRemainingKg < 0) engineEstimatedRemainingKg = 0.0;
    double engineEstimatedRemainingBags = engineEstimatedRemainingKg / 50.0;

    double expectedConsumedBags = totalExpectedConsumedKg / 50.0;
    double expectedRemainingBags = engineEstimatedRemainingBags;

    double actualRemainingBagsNum = double.tryParse(actualRemainingBags) ?? 0.0;

    double calculatedConsumedBags = netTotalFeedBags - actualRemainingBagsNum;
    if (!hasRemainingFeedLogged && actualRemainingBagsNum == 0.0) {
      calculatedConsumedBags = expectedConsumedBags > netTotalFeedBags
          ? netTotalFeedBags.toDouble()
          : expectedConsumedBags;
    }
    if (calculatedConsumedBags < 0) calculatedConsumedBags = 0;
    double actualFeedConsumedKg = calculatedConsumedBags * 50.0;
    double currentLiveWeightKg = liveChicks * latestAvgWeight;
    double totalBiomassProducedKg = totalWeightSoldKg + currentLiveWeightKg;
    double fcr = totalBiomassProducedKg > 0
        ? (actualFeedConsumedKg / totalBiomassProducedKg)
        : 0.0;

    final FraudRiskAssessment fraudAssessment = FraudRiskEngine.assess(
      feedDeliveredKg: netTotalFeedKgSum,
      expectedConsumedKg: totalExpectedConsumedKg,
      actualRemainingKg: actualRemainingBagsNum * 50.0,
      remainingFeedEverReported: hasRemainingFeedLogged,
    );

    String dynamicStatus = _liveBatchData['status'].toString().toUpperCase();
    if (dynamicStatus == 'CLOSED') dynamicStatus = 'COMPLETED';
    if (dynamicStatus == 'ACTIVE' &&
        chicksAgeDays >= _minLiftingDays &&
        chicksAgeDays <= _maxLiftingDays) {
      dynamicStatus = 'LIFTING READY';
    }

    bool showBatchEndBtn =
        dynamicStatus != 'COMPLETED' && liveChicks == 0 && totalChicksSold > 0;
    bool showSettlementRasidBtn = dynamicStatus == 'COMPLETED';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context, true),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Batch Tracking Details',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.shade800,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                '🆔 ${_liveBatchData['batchId'] ?? _liveBatchData['id'] ?? '-'}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (showBatchEndBtn)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () => _showReturnFeedDialog(
                  onDone: () => _showBatchEndConfirmation(
                    liveChicks: liveChicks,
                    latestAvgWeight: latestAvgWeight,
                    totalFeedBags: netTotalFeedBags,
                    totalFeedKg: netTotalFeedKgSum,
                    totalMortality: totalMortality,
                    totalChicksSold: totalChicksSold,
                    totalWeightSoldKg: totalWeightSoldKg,
                    totalSaleMoney: totalSaleMoney,
                    totalMedicineExpense: totalMedicineExpense,
                  ),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(
                  Icons.flag_rounded,
                  color: Colors.white,
                  size: 16,
                ),
                label: const Text(
                  'Batch End',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (dynamicStatus == 'COMPLETED')
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '✅ CLOSED',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      // ====== BODY: SINGLECHILDSCROLLVIEW WITH SLIDING WHITE CONTAINER ======
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // ── GREEN HEADER (unchanged) ──────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
              decoration: const BoxDecoration(
                color: primaryGreen,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatBlock('Chicks Quantity', '$initialChicks 🐥'),
                      _buildStatBlock('Live Chicks', '$liveChicks 🐥'),
                      _buildStatBlock('Days Old', '$chicksAgeDays Din 📅'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatBlock(
                        'Total Feed Bags',
                        totalReturnFeedKg > 0
                            ? 'Net: $netTotalFeedBags Bags 📦\n(${netTotalFeedKgSum.toStringAsFixed(1)} KG)\n'
                                  'Delivered: ${totalFeedKgSum.toStringAsFixed(1)} KG\n'
                                  'Returned: ${totalReturnFeedKg.toStringAsFixed(1)} KG'
                            : '$netTotalFeedBags Bags 📦\n(${netTotalFeedKgSum.toStringAsFixed(1)} KG)',
                      ),
                      _buildStatBlock(
                        'Mortality',
                        '$totalMortality (${mortalityPercent.toStringAsFixed(2)}%) 💀',
                        alert: PerformanceAlertEngine.evaluateMortality(
                          mortalityPercent,
                          _performanceConfig,
                          dayNumber: chicksAgeDays,
                        ),
                      ),
                      _buildStatBlock(
                        'Start Date',
                        _formatStartDateForDisplay(_liveBatchData['startDate']),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatBlock(
                        'Current Weight',
                        '${latestAvgWeight > 0 ? latestAvgWeight.toStringAsFixed(2) : "0.00"} kg ⚖️',
                      ),
                      _buildStatBlock(
                        'Target Weight',
                        '${(idealTargetWeight / 1000).toStringAsFixed(3)} kg 🎯',
                      ),
                      _buildStatBlock(
                        'Live FCR Index',
                        '${fcr > 0 ? fcr.toStringAsFixed(2) : "0.00"} 📊',
                        alert: fcr > 0
                            ? PerformanceAlertEngine.evaluateFcr(
                                fcr,
                                _performanceConfig,
                                dayNumber: chicksAgeDays,
                              )
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatBlock(
                        'Expected Consumed',
                        '${expectedConsumedBags.toStringAsFixed(1)} Bags 📉\n(${totalExpectedConsumedKg.toStringAsFixed(1)} KG)',
                      ),
                      _buildStatBlock(
                        'Expected Balance',
                        '${expectedRemainingBags.toStringAsFixed(1)} Bags 📊\n${(expectedRemainingBags * 50.0).toStringAsFixed(1)} KG',
                      ),
                      _buildStatBlock(
                        'Actual Farm Stock',
                        hasRemainingFeedLogged
                            ? '$actualRemainingBags Bags 🚜\n${(actualRemainingBagsNum * 50.0).toStringAsFixed(1)} KG'
                            : 'Not Reported Yet ⚠️',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'STATUS: $dynamicStatus',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── NEW: WHITE ROUNDED CONTAINER WITH SLIDING EFFECT ──────────
            Transform.translate(
              offset: const Offset(0, -18),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  children: [
                    // ── FRAUD RISK CARD ──────────────────────────────────
                    if (fraudAssessment.hasAnyData)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: _buildFraudRiskCard(fraudAssessment),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: Colors.grey.shade600,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Fraud Risk check tab shuru hoga jab kabhi "Actual Remaining Feed" '
                                  '(Flock Record mein) report hui ho.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // ── BATCH END BANNER ──────────────────────────────────
                    if (showBatchEndBtn)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: GestureDetector(
                          onTap: () => _showReturnFeedDialog(
                            onDone: () => _showBatchEndConfirmation(
                              liveChicks: liveChicks,
                              latestAvgWeight: latestAvgWeight,
                              totalFeedBags: netTotalFeedBags,
                              totalFeedKg: netTotalFeedKgSum,
                              totalMortality: totalMortality,
                              totalChicksSold: totalChicksSold,
                              totalWeightSoldKg: totalWeightSoldKg,
                              totalSaleMoney: totalSaleMoney,
                              totalMedicineExpense: totalMedicineExpense,
                            ),
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.red.shade300,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.flag_rounded,
                                    color: Colors.red,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '🎉 Saari Murgiyan Bik Gayi!',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Batch End karo aur Settlement Rasid generate karo',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.red,
                                  size: 22,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    if (showBatchEndBtn) const SizedBox(height: 12),

                    // ── SETTLEMENT RASID BUTTON ──────────────────────────
                    if (showSettlementRasidBtn)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: GestureDetector(
                          onTap: () => _generateAndShowSettlementRasid(
                            totalFeedBags: netTotalFeedBags,
                            totalFeedKg: netTotalFeedKgSum,
                            totalMortality: totalMortality,
                            totalChicksSold: totalChicksSold,
                            totalWeightSoldKg: totalWeightSoldKg,
                            totalSaleMoney: totalSaleMoney,
                            totalMedicineExpense: totalMedicineExpense,
                            latestAvgWeight: latestAvgWeight,
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: primaryGreen.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: primaryGreen,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: primaryGreen.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.receipt_long_rounded,
                                    color: primaryGreen,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '🧾 Settlement Rasid Dekho',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: primaryGreen,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Tap karo — PDF Download aur Share bhi kar sakte ho',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: primaryGreen,
                                  size: 22,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    if (showSettlementRasidBtn) const SizedBox(height: 12),

                    // ── QUICK ACTION BUTTONS ──────────────────────────────
                    if (dynamicStatus != 'COMPLETED')
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            _buildQuickActionCard(
                              label: '+ Flock Record',
                              icon: Icons.add_circle_outline_rounded,
                              accentColor: primaryGreen,
                              onTap: _showDailyEntryDialog,
                            ),
                            _buildQuickActionCard(
                              label: '+ Sale',
                              icon: Icons.monetization_on_outlined,
                              accentColor: Colors.orange,
                              onTap: _showSalesEntryDialog,
                            ),
                            _buildQuickActionCard(
                              label: 'Medicine',
                              icon: Icons.medical_services_outlined,
                              accentColor: Colors.purple,
                              onTap: _showMedicineEntryDialog,
                            ),
                          ],
                        ),
                      ),

                    if (dynamicStatus != 'COMPLETED')
                      const SizedBox(height: 16),

                    // ── DATA SHEETS HEADER ──────────────────────────────
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '📋 DATA SHEETS',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            color: Colors.black54,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),

                    // ── DAILY UPDATE LIST BUTTON ──────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryGreen,
                            side: BorderSide(
                              color: primaryGreen.withOpacity(0.6),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(
                            Icons.calendar_view_day_rounded,
                            size: 20,
                          ),
                          label: const Text(
                            'Daily Update List Dekho',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => DailyUpdateListScreen(
                                  batchData: _liveBatchData,
                                  dailyEntries: _dailyEntries,
                                  feedRuleConfig: _feedRuleConfig,
                                  farmerId: widget.farmerId,
                                  userRole: widget.userRole,
                                ),
                              ),
                            );
                            await _loadFreshBatchData();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── DATA LIST (shrink-wrapped, non-scrollable) ──────
                    _dailyEntries.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.analytics_rounded,
                                    size: 48,
                                    color: Colors.grey.shade300,
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Abhi is batch ka koi daily record nahi hai.\nUpar button se log entry shuru karein.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            itemCount: _dailyEntries.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, index) {
                              final logRow =
                                  _dailyEntries[_dailyEntries.length -
                                      1 -
                                      index];
                              String rowType = logRow['type']
                                  .toString()
                                  .toLowerCase();

                              if (rowType == 'sale') {
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: const BorderSide(
                                      color: Colors.orange,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Container(
                                    color: Colors.orange.withOpacity(0.02),
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Text(
                                              '💰 Sales Entry Successfully',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: Colors.orange,
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              '${logRow['date']}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const Divider(
                                          color: Colors.orange,
                                          height: 16,
                                        ),
                                        Text(
                                          '👤 Buyer Name: ${logRow['buyerName']}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '🐥 Sold: ${logRow['chicksSold']} pcs',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              '⚖️ Total Wt: ${logRow['totalWeightSold']} kg',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              '🏷️ Rate: ₹${logRow['pricePerKg']}/kg',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '🐔 Avg Weight: ${logRow['avgWeightSold']} kg',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.black54,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                            Text(
                                              'Total Cash Received: ₹${logRow['totalMoney']}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Align(
                                          alignment: Alignment.bottomRight,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: Colors.orange.shade200,
                                              ),
                                            ),
                                            child: Text(
                                              'By: ${logRow['enteredBy'] ?? 'Staff'}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.orange.shade900,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              if (rowType == 'medicine') {
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: const BorderSide(
                                      color: Colors.purple,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Container(
                                    color: Colors.purple.withOpacity(0.01),
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Text(
                                              '💊 Medicine Administered',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: Colors.purple,
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              '${logRow['date']}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const Divider(
                                          color: Colors.purple,
                                          height: 16,
                                        ),
                                        Text(
                                          '🧪 Item Name: ${logRow['medicineName']}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '📦 Vol/Qty: ${logRow['quantity']} ${logRow['unit']}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.black54,
                                              ),
                                            ),
                                            Text(
                                              'Exp Price: ₹${(double.tryParse(logRow['price'].toString()) ?? 0.0).toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.purple,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.bottomRight,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.purple.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'By: ${logRow['enteredBy'] ?? 'Staff'}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.purple.shade900,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              if (rowType == 'cost') {
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: BorderSide(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              '📅 Din ki Entry: ${logRow['date']}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: Colors.black87,
                                              ),
                                            ),
                                            const Spacer(),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'By: ${logRow['enteredBy'] ?? 'Staff'}',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.black54,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const Divider(
                                          color: Color(0xFFF5F5F5),
                                          height: 16,
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            _buildLogMetricRow(
                                              '⚖️ Avg Weight',
                                              '${logRow['weight']} kg',
                                            ),
                                            _buildLogMetricRow(
                                              '💀 Mortality',
                                              '${logRow['mortality']}',
                                            ),
                                            _buildLogMetricRow(
                                              (int.tryParse(
                                                            logRow['feed']
                                                                .toString(),
                                                          ) ??
                                                          0) <
                                                      0
                                                  ? '📦 Feed Correction ❌'
                                                  : '📦 Feed Bags Arrived',
                                              '${logRow['feed']} Bag'
                                              '${logRow['feedTotalKg'] is num ? ' (${(logRow['feedTotalKg'] as num).toStringAsFixed(1)} KG)' : ''}',
                                            ),
                                          ],
                                        ),
                                        if (logRow['remainingFeed'] != null &&
                                            logRow['remainingFeed'] != '0') ...[
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.inventory_2_outlined,
                                                size: 14,
                                                color: Colors.blueGrey,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Farm Stock Balance Checked: ${logRow['remainingFeed']} Bags bache hain',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blueGrey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                        if (logRow['hasMismatch'] == true) ...[
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.red.shade300,
                                              ),
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Icon(
                                                  Icons.error_outline,
                                                  size: 14,
                                                  color: Colors.red,
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    '⚠️ Photo Mismatch: '
                                                    '${logRow['mismatchReason'] ?? 'Entered value photo se match nahi hua'}',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      color:
                                                          Colors.red.shade800,
                                                      fontWeight:
                                                          FontWeight.w600,
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
                                );
                              }

                              if (rowType == 'returnfeed') {
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: const BorderSide(
                                      color: Colors.teal,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Container(
                                    color: Colors.teal.withOpacity(0.02),
                                    padding: const EdgeInsets.all(14),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.assignment_return_rounded,
                                          color: Colors.teal,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                '↩️ Return Feed',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  color: Colors.teal,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                '${logRow['returnFeedKg']} KG farm se waapas aaya',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          '${logRow['date']}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black54,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              return const SizedBox.shrink();
                            },
                          ),

                    const SizedBox(height: 24), // ✅ bottom padding
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBlock(
    String headerTitle,
    String metricValue, {
    AlertLevel? alert,
  }) {
    return Column(
      children: [
        Text(
          headerTitle,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          metricValue,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        if (alert != null) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: alert == AlertLevel.red
                  ? Colors.red.shade600
                  : alert == AlertLevel.yellow
                  ? Colors.amber.shade600
                  : Colors.green.shade600,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              alert == AlertLevel.red
                  ? '🔴 Kharab'
                  : alert == AlertLevel.yellow
                  ? '🟡 Badiya'
                  : '🟢 Normal',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLogMetricRow(String labelTitle, String metricDataValue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelTitle,
          style: const TextStyle(fontSize: 11, color: Colors.black45),
        ),
        const SizedBox(height: 2),
        Text(
          metricDataValue,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}
