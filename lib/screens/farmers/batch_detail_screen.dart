import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../utils/pdf_download.dart' as pdf_web;
import '../../../utils/feed_consumption_rule_engine.dart';
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
  static const Color primaryGreen = Color(0xFF1B5E20);

  final _weightController = TextEditingController();
  final _mortalityController = TextEditingController();
  final _feedController = TextEditingController();
  final _dateController = TextEditingController();

  final _buyerNameController = TextEditingController();
  final _soldChicksController = TextEditingController();
  final _totalWeightSoldController = TextEditingController();
  final _pricePerKgController = TextEditingController();

  final _medicineNameController = TextEditingController();
  final _medicineQuantityController = TextEditingController();
  final _medicinePriceController = TextEditingController();
  String _selectedMedicineUnit = 'ml';

  final _remainingFeedController = TextEditingController();

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
  String _farmerIfsc = '';
  String _farmerAddress = '';

  // ── FIX 1: Farmer avatar bytes for PDF photo ─────────────────────────────
  Uint8List? _farmerAvatarBytes;

  // ── Settlement Rule State ─────────────────────────────────────────────────
  int? _appliedRuleId;

  // ── Feed Consumption Rule (company-configurable) ────────────────────────
  // Default = standardAgeChart taaki jab tak company khud koi rule set na
  // kare, purana wala fixed gram/day chart hi chalta rahe (backward-compatible).
  FeedConsumptionRuleConfig _feedRuleConfig = FeedConsumptionRuleConfig(
    ruleType: FeedRuleType.standardAgeChart,
  );

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
  }

  String _formatDate(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
  }

  @override
  void dispose() {
    _weightController.dispose();
    _mortalityController.dispose();
    _feedController.dispose();
    _dateController.dispose();
    _buyerNameController.dispose();
    _soldChicksController.dispose();
    _totalWeightSoldController.dispose();
    _pricePerKgController.dispose();
    _medicineNameController.dispose();
    _medicineQuantityController.dispose();
    _medicinePriceController.dispose();
    _remainingFeedController.dispose();
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

    setState(() {
      _appliedRuleId = savedRuleId;

      if (feedRuleJson != null && feedRuleJson.isNotEmpty) {
        try {
          _feedRuleConfig = FeedConsumptionRuleConfig.fromJson(
            json.decode(feedRuleJson),
          );
        } catch (_) {
          // corrupt data mile toh purana default (standardAgeChart) hi rahega
        }
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
        // ── Farmer info load karo ─────────────────────────────────────
        setState(() {
          _farmerName = currentFarmer['name'] ?? '';
          _farmerPhone = currentFarmer['phone'] ?? '';
          _farmerBankName = currentFarmer['bankName'] ?? '';
          _farmerAccountNo = currentFarmer['accountNo'] ?? '';
          _farmerIfsc = currentFarmer['ifsc'] ?? '';
          _farmerAddress = currentFarmer['address'] ?? '';
        });

        // ── FIX 1: Farmer profile photo load karo (multiple keys support) ──
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
              setState(() => _farmerAvatarBytes = base64Decode(val.toString()));
            } catch (_) {}
            break;
          }
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
  // FIX 1+2: PDF GENERATOR — Improved Design with Farmer Photo + Colored Sections
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

    // NotoEmoji font — http se load karo (koi asset file nahi chahiye)
    // Ye font Google ke CDN se directly download hota hai at runtime.
    pw.Font? emojiFont;
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://github.com/google/fonts/raw/main/ofl/notoemoji/NotoEmoji%5Bwght%5D.ttf',
            ),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        emojiFont = pw.Font.ttf(response.bodyBytes.buffer.asByteData());
      }
    } catch (_) {
      emojiFont = null;
    }

    // ── PDF Color Palette ───────────────────────────────────────────────────
    const PdfColor kGreen = PdfColor.fromInt(0xFF1B5E20);
    const PdfColor kGreenMid = PdfColor.fromInt(0xFF2E7D32);
    const PdfColor kGreenLight = PdfColor.fromInt(0xFFE8F5E9);
    const PdfColor kRedLight = PdfColor.fromInt(0xFFFFEBEE);
    const PdfColor kBlueLight = PdfColor.fromInt(0xFFE3F2FD);
    const PdfColor kIndigoLight = PdfColor.fromInt(0xFFE8EAF6);
    const PdfColor kOrangeLight = PdfColor.fromInt(0xFFFFF3E0);
    const PdfColor kGrey = PdfColor.fromInt(0xFF757575);
    const PdfColor kDark = PdfColor.fromInt(0xFF212121);
    const PdfColor kRed = PdfColor.fromInt(0xFFC62828);
    const PdfColor kBlue = PdfColor.fromInt(0xFF1565C0);
    const PdfColor kIndigo = PdfColor.fromInt(0xFF283593);
    const PdfColor kOrange = PdfColor.fromInt(0xFFE65100);
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

    // tsEmoji — emoji support with NotoEmoji font fallback
    pw.TextStyle tsEmoji({
      double size = 10,
      bool bold = false,
      PdfColor color = kDark,
    }) => pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color,
      fontFallback: emojiFont != null ? [emojiFont!] : [],
    );

    // ── Header row inside green banner ──────────────────────────────────────
    pw.Widget pdfHeaderRow(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 4,
            child: pw.Text(
              label,
              style: ts(size: 9, color: const PdfColor(1, 1, 1, 0.85)),
            ),
          ),
          pw.Expanded(
            flex: 6,
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: ts(size: 9, bold: true, color: kWhite),
            ),
          ),
        ],
      ),
    );

    // ── Key-value data row — flex 6:4 prevents right-side clipping ──────────
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
            color: highlight
                ? const PdfColor(0.106, 0.369, 0.125, 0.08)
                : const PdfColor(0, 0, 0, 0),
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // flex 5:5 — equal space for label and value, no clipping
                pw.Expanded(
                  flex: 5,
                  child: pw.Text(label, style: ts(size: 8.5, color: kGrey)),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  flex: 5,
                  child: pw.Text(
                    value,
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

    // ── Section card ─────────────────────────────────────────────────────────
    // NOTE: Emojis removed from section titles — pdf package renders them as
    // boxes without a special emoji font. Clean text looks professional.
    pw.Widget pdfSection(
      String title,
      PdfColor titleColor,
      PdfColor bgColor,
      List<pw.Widget> rows,
    ) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8),
        decoration: pw.BoxDecoration(
          color: bgColor,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          border: pw.Border.all(
            color: PdfColor(
              titleColor.red,
              titleColor.green,
              titleColor.blue,
              0.35,
            ),
            width: 0.7,
          ),
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
                color: titleColor,
                borderRadius: const pw.BorderRadius.only(
                  topLeft: pw.Radius.circular(8),
                  topRight: pw.Radius.circular(8),
                ),
              ),
              child: pw.Text(
                title,
                style: tsEmoji(size: 10, bold: true, color: kWhite),
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
    String startDate = _liveBatchData['startDate'] ?? '-';
    String endDate = _formatDate(DateTime.now());
    int totalDays = _calculateChicksDaysOld(_liveBatchData['startDate'] ?? '');
    double mortalityPct = initialChicks > 0
        ? (totalMortality / initialChicks) * 100
        : 0.0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        build: (ctx) => [
          // ── FARMER PROFILE CARD ───────────────────────────────────────────
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: kWhite,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              border: pw.Border.all(color: kDivider, width: 0.8),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Avatar — real photo OR initials
                pw.Container(
                  width: 54,
                  height: 54,
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    color: const PdfColor(0.106, 0.369, 0.125, 0.15),
                    border: pw.Border.all(
                      color: const PdfColor(0.106, 0.369, 0.125, 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: _farmerAvatarBytes != null
                      ? pw.ClipOval(
                          child: pw.Image(
                            pw.MemoryImage(_farmerAvatarBytes!),
                            width: 54,
                            height: 54,
                            fit: pw.BoxFit.cover,
                          ),
                        )
                      : pw.Center(
                          child: pw.Text(
                            _farmerName.isNotEmpty
                                ? _farmerName[0].toUpperCase()
                                : 'F',
                            style: ts(size: 24, bold: true, color: kGreen),
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
                // Tracko badge
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: pw.BoxDecoration(
                    color: kGreen,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(6),
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        'TRACKO',
                        style: ts(size: 9, bold: true, color: kWhite),
                      ),
                      pw.Text(
                        'Poultry App',
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

          // ── GREEN MAIN HEADER ─────────────────────────────────────────────
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(bottom: 12),
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: kGreenMid,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Batch Settlement Rasid',
                  style: ts(size: 16, bold: true, color: kWhite),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  ruleLabel,
                  style: tsEmoji(size: 9, color: const PdfColor(1, 1, 1, 0.85)),
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
          pdfSection('🐥  Batch Summary', kBlue, kBlueLight, [
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
            pdfDataRow('Total Feed Used', '$totalFeedBags Bags'),
          ]),

          // ── BANK DETAILS ──────────────────────────────────────────────────
          pdfSection('🏦  Farmer Bank Details', kIndigo, kIndigoLight, [
            pdfDataRow(
              'Account Holder',
              _farmerName.isNotEmpty ? _farmerName : '--',
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
          ]),

          if (!isRule2) ...[
            // ── PRODUCTION COST ───────────────────────────────────────────
            pdfSection('🏭  Production Cost Breakdown', kRed, kRedLight, [
              pdfDataRow(
                'Chick Cost',
                'Rs.${totalChickCost.toStringAsFixed(2)}',
              ),
              pdfDataRow('Feed Cost', 'Rs.${totalFeedCost.toStringAsFixed(2)}'),
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
            ]),

            // ── COMMISSION ────────────────────────────────────────────────
            pdfSection('💰  Farmer Commission Calculation', kGreen, kGreenLight, [
              pdfDataRow(
                'Base Commission',
                'Rs.${baseCommPerKg.toStringAsFixed(2)}/KG',
              ),
              pdfDataRow(
                costAdjPerKg >= 0 ? 'Cost Saving Bonus' : 'Exceeded Penalty',
                '${costAdjPerKg >= 0 ? "+" : ""}Rs.${costAdjPerKg.toStringAsFixed(2)}/KG',
                valueColor: costAdjPerKg >= 0 ? kGreen : kRed,
              ),
              pdfDataRow('Calculation Note', costAdjLabel),
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
            ]),

            // ── NET PAYOUT ────────────────────────────────────────────────
            pdfSection('💵  Net Farmer Payout', kGreen, kGreenLight, [
              pdfDataRow(
                'Gross Earning (Wt x Comm)',
                '${totalWeightSoldKg.toStringAsFixed(2)} KG'
                    ' x Rs.${finalCommPerKg.toStringAsFixed(2)}'
                    ' = Rs.${grossEarning.toStringAsFixed(2)}',
              ),
              if (!medInProdCost)
                pdfDataRow(
                  'Medicine Deduction',
                  '-Rs.${totalMedicineCost.toStringAsFixed(2)}',
                  valueColor: kRed,
                ),
              pdfDataRow(
                'NET PAYOUT TO FARMER',
                'Rs.${netPayout.toStringAsFixed(2)}',
                bold: true,
                valueColor: netPayout > 0 ? kGreen : kRed,
                divider: true,
                highlight: true,
              ),
            ]),
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

          // ── FOOTER ────────────────────────────────────────────────────────
          pw.SizedBox(height: 4),
          pw.Divider(color: kDivider, thickness: 0.5),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated by Tracko App',
                style: ts(size: 8, color: kGrey),
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
    double totalFeedKg = totalFeedBags * kgPerBag;
    double totalFeedCost = totalFeedKg * feedRate;
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
                        _liveBatchData['startDate'] ?? '-',
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
                    _rasidRow('Total Feed Used', '$totalFeedBags Bags'),
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
                      _farmerName.isNotEmpty ? _farmerName : '—',
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
    // Web pe share nahi hota — download karo
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
        // ── Mobile: temp file + share ────────────────────────────────────
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/Settlement_$batchId.pdf');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles([
          XFile(file.path, mimeType: 'application/pdf'),
        ], subject: 'Settlement Rasid — $batchId — Tracko App');
      } else {
        // ── Web: browser download via utility ───────────────────────────
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
  // FIX 2+3: DOWNLOAD AS PDF — Direct Downloads Folder + Progress Snackbars
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
        // ── WEB: Browser download via utility ────────────────────────────
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
        // ── ANDROID: Direct Downloads folder ─────────────────────────────
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

        final file = File('${downloadsDir.path}/$fileName');
        await file.writeAsBytes(bytes);

        if (!mounted) return;
        Get.snackbar(
          '✅ PDF Downloaded!',
          'Saved: Downloads/$fileName\nTap OPEN to view',
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
              await Share.shareXFiles([
                XFile(file.path, mimeType: 'application/pdf'),
              ], subject: 'Settlement Rasid — $batchId');
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
        await prefs.setString('companyFarmers', json.encode(farmersList));
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
                  'Cost Entry (${widget.userRole})',
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
                  const SizedBox(height: 14),
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
                    const SizedBox(height: 6),
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
                    const SizedBox(height: 14),
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
                    const SizedBox(height: 14),
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
                    const SizedBox(height: 16),
                  ],
                  if (widget.userRole == 'Owner' ||
                      widget.userRole == 'Office Manager') ...[
                    const Text(
                      '🏢 Office Manager Entries',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _feedController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Feed Bags (Arrived / Correction) *',
                        hintText: 'Add: 5  |  Correction/Minus: -2',
                        prefixIcon: const Icon(Icons.shopping_bag_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
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
                  _weightController.clear();
                  _mortalityController.clear();
                  _feedController.clear();
                  _remainingFeedController.clear();
                  Navigator.pop(context);
                },
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: () =>
                    _saveDailyLogEntryToStorage(context, existingEntries),
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
  ) async {
    if (_isLoading) return;

    String weightInput = _weightController.text.trim();
    String mortalityInput = _mortalityController.text.trim();
    String feedInput = _feedController.text.trim();
    String dateInput = _dateController.text.trim();
    String remainingFeedInput = _remainingFeedController.text.trim();

    if (weightInput.isEmpty &&
        mortalityInput.isEmpty &&
        feedInput.isEmpty &&
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
    int? feedVal = int.tryParse(feedInput);
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

    if (feedVal != null && feedVal < 0) {
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
          'feed': feedInput.isEmpty ? '0' : feedInput,
          'remainingFeed': remainingFeedInput.isEmpty
              ? '0'
              : remainingFeedInput,
          'enteredBy': widget.userRole,
          'timestamp': DateTime.now().toIso8601String(),
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
        await prefs.setString('companyFarmers', json.encode(farmersList));
        _weightController.clear();
        _mortalityController.clear();
        _feedController.clear();
        _remainingFeedController.clear();
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
        await prefs.setString('companyFarmers', json.encode(farmersList));
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
        await prefs.setString('companyFarmers', json.encode(farmersList));
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
    int totalChicksSold = 0;
    double latestAvgWeight = 0.0;
    double totalWeightSoldKg = 0.0;
    double totalSaleMoney = 0.0;
    double totalMedicineExpense = 0.0;
    String actualRemainingBags = '0';
    bool hasRemainingFeedLogged = false;

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
        totalFeedBags += int.tryParse(entry['feed'].toString()) ?? 0;
        double wt = double.tryParse(entry['weight'].toString()) ?? 0.0;
        if (wt > 0.0) latestAvgWeight = wt;
        if (entry['remainingFeed'] != null && entry['remainingFeed'] != '0') {
          actualRemainingBags = entry['remainingFeed'].toString();
          hasRemainingFeedLogged = true;
        }
      } else if (currentType == 'medicine') {
        totalMedicineExpense +=
            double.tryParse(entry['price'].toString()) ?? 0.0;
      }
    }

    int liveChicks = initialChicks - totalMortality - totalChicksSold;
    double mortalityPercent = initialChicks > 0
        ? (totalMortality / initialChicks) * 100
        : 0.0;
    int chicksAgeDays = _calculateChicksDaysOld(
      _liveBatchData['startDate'] ?? '',
    );
    int idealTargetWeight = _getAppStandardTargetWeight(chicksAgeDays);

    // ── Expected Consumed — company ke configured Feed Consumption Rule
    // (_feedRuleConfig) ke hisaab se calculate hota hai. Standard Age Chart
    // mode mein purana fixed gram/day table use hota hai; Linear Multiplier
    // mode mein Live×Multiplier×Day÷1000 formula (season-aware) use hota hai.
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

    double totalExpectedConsumedKg = 0.0;
    for (int day = 1; day <= chicksAgeDays; day++) {
      totalExpectedConsumedKg += FeedConsumptionEngine.calculateDayFeedKg(
        config: _feedRuleConfig,
        liveChicks: initialChicks,
        dayNumber: day,
        entryDate: batchStartDate.add(Duration(days: day - 1)),
      );
    }

    double expectedConsumedBags = totalExpectedConsumedKg / 50.0;
    double expectedRemainingBags = totalFeedBags - expectedConsumedBags;
    if (expectedRemainingBags < 0) expectedRemainingBags = 0;

    double actualRemainingBagsNum = double.tryParse(actualRemainingBags) ?? 0.0;
    double calculatedConsumedBags = totalFeedBags - actualRemainingBagsNum;
    if (!hasRemainingFeedLogged && actualRemainingBagsNum == 0.0) {
      calculatedConsumedBags = expectedConsumedBags > totalFeedBags
          ? totalFeedBags.toDouble()
          : expectedConsumedBags;
    }
    if (calculatedConsumedBags < 0) calculatedConsumedBags = 0;

    double actualFeedConsumedKg = calculatedConsumedBags * 50.0;
    double currentLiveWeightKg = liveChicks * latestAvgWeight;
    double totalBiomassProducedKg = totalWeightSoldKg + currentLiveWeightKg;
    double fcr = totalBiomassProducedKg > 0
        ? (actualFeedConsumedKg / totalBiomassProducedKg)
        : 0.0;

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
                onPressed: () => _showBatchEndConfirmation(
                  liveChicks: liveChicks,
                  latestAvgWeight: latestAvgWeight,
                  totalFeedBags: totalFeedBags,
                  totalMortality: totalMortality,
                  totalChicksSold: totalChicksSold,
                  totalWeightSoldKg: totalWeightSoldKg,
                  totalSaleMoney: totalSaleMoney,
                  totalMedicineExpense: totalMedicineExpense,
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
      body: Column(
        children: [
          // ── TOP LIVE STATS HEADER ───────────────────────────────────
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
                      '$totalFeedBags Bags 📦',
                    ),
                    _buildStatBlock(
                      'Mortality',
                      '$totalMortality (${mortalityPercent.toStringAsFixed(2)}%) 💀',
                    ),
                    _buildStatBlock(
                      'Start Date',
                      _liveBatchData['startDate'] ?? '-',
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
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatBlock(
                      'Expected Consumed',
                      '${expectedConsumedBags.toStringAsFixed(1)} Bags 📉',
                    ),
                    _buildStatBlock(
                      'Expected Balance',
                      '${expectedRemainingBags.toStringAsFixed(1)} Bags 📊',
                    ),
                    _buildStatBlock(
                      'Actual Farm Stock',
                      '$actualRemainingBags Bags 🚜',
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

          const SizedBox(height: 16),

          // ── BATCH END BANNER ──────────────────────────────────────────
          if (showBatchEndBtn)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: GestureDetector(
                onTap: () => _showBatchEndConfirmation(
                  liveChicks: liveChicks,
                  latestAvgWeight: latestAvgWeight,
                  totalFeedBags: totalFeedBags,
                  totalMortality: totalMortality,
                  totalChicksSold: totalChicksSold,
                  totalWeightSoldKg: totalWeightSoldKg,
                  totalSaleMoney: totalSaleMoney,
                  totalMedicineExpense: totalMedicineExpense,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.red.shade300, width: 1.5),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
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

          // ── SETTLEMENT RASID BUTTON ───────────────────────────────────
          if (showSettlementRasidBtn)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: GestureDetector(
                onTap: () => _generateAndShowSettlementRasid(
                  totalFeedBags: totalFeedBags,
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
                    border: Border.all(color: primaryGreen, width: 1.5),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
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

          // ── QUICK ACTION BUTTONS ──────────────────────────────────────
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

          if (dynamicStatus != 'COMPLETED') const SizedBox(height: 16),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryGreen,
                  side: BorderSide(color: primaryGreen.withOpacity(0.6)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.calendar_view_day_rounded, size: 20),
                label: const Text(
                  'Daily Update List Dekho',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DailyUpdateListScreen(
                        batchData: _liveBatchData,
                        dailyEntries: _dailyEntries,
                        feedRuleConfig: _feedRuleConfig,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── DATA LIST ─────────────────────────────────────────────────
          Expanded(
            child: _dailyEntries.isEmpty
                ? Center(
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
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    itemCount: _dailyEntries.length,
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (context, index) {
                      final logRow =
                          _dailyEntries[_dailyEntries.length - 1 - index];
                      String rowType = logRow['type'].toString().toLowerCase();

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
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                const Divider(color: Colors.orange, height: 16),
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
                                      borderRadius: BorderRadius.circular(6),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                const Divider(color: Colors.purple, height: 16),
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
                                      borderRadius: BorderRadius.circular(6),
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

                      // ── COST ENTRY CARD ─────────────────────────────
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(6),
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
                                    (int.tryParse(logRow['feed'].toString()) ??
                                                0) <
                                            0
                                        ? '📦 Feed Correction ❌'
                                        : '📦 Feed Bags Arrived',
                                    '${logRow['feed']} Bag',
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
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBlock(String headerTitle, String metricValue) {
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
