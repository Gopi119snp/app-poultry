import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import '../profile/profile_screen.dart';
import '../farmers/farmers_screen.dart';
import '../welcome_screen.dart';
import '../../utils/batch_settlement_engine.dart';
import '../../utils/simple_settlement_engine.dart';
import '../../services/company_store.dart';
import '../../services/session_service.dart';
import '../../services/auth_service.dart';
import 'purchase_expense_screen.dart';
import 'sales_screen.dart';

class HomeScreen extends StatefulWidget {
  final String ownerName;
  final String companyName;

  const HomeScreen({
    super.key,
    this.ownerName = 'Rajesh',
    this.companyName = 'Singh Poultry Farms',
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;

  static const Color primaryGreen = Color(0xFF1B5E20);
  static const Color lightGreen = Color(0xFFE8F5E9);

  int _farmerCount = 0;
  int _activeBatchCount = 0;
  final List<Map<String, dynamic>> _liftingFarmers = [];

  int _minLiftingDays = 23;
  int _maxLiftingDays = 60;

  List<Map<String, dynamic>> _recentActivitiesList = [];
  Timer? _instantRefreshTimer;
  String _selectedActivityFilter = 'Default';

  // ── 🚜 SAAS SELECTION STATE TRACKING VARIABLES ─────────────────────────────
  int? _appliedCompanyRuleId;
  bool _isRule1Editing = true;
  bool _isRule2Editing = true;

  // ── 📦 STOCK MANAGEMENT STATE (FEED + MEDICINE) ────────────────────────────
  int _stockSubTab = 0; // 0 = Feed, 1 = Medicine
  Map<String, double> _feedStock = {
    'Starter': 0.0,
    'Grower': 0.0,
    'Finisher': 0.0,
  };
  List<Map<String, dynamic>> _medicineStock = [];

  // ── CHICK ANIMATION ───────────────────────────────────────────────────────
  late AnimationController _chickBounceController;
  late AnimationController _dustController;
  late Animation<double> _chickBounceAnim;
  late Animation<double> _dustOpacityAnim;
  late Animation<double> _dustScaleAnim;
  bool _showDust = false;

  @override
  void initState() {
    super.initState();
    _loadKpiData();
    _loadStockData();
    _loadAppliedRuleState();
    _instantRefreshTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) {
      _loadKpiData();
      _loadStockData();
    });

    _chickBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _chickBounceAnim = Tween<double>(begin: 0, end: -16).animate(
      CurvedAnimation(
        parent: _chickBounceController,
        curve: Curves.easeOut,
        reverseCurve: Curves.bounceIn,
      ),
    );

    _dustController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _dustOpacityAnim = Tween<double>(
      begin: 0.85,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _dustController, curve: Curves.easeOut));
    _dustScaleAnim = Tween<double>(
      begin: 0.2,
      end: 1.5,
    ).animate(CurvedAnimation(parent: _dustController, curve: Curves.easeOut));

    _chickBounceController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        setState(() => _showDust = true);
        _dustController.forward(from: 0).then((_) {
          if (mounted) setState(() => _showDust = false);
        });
        Future.delayed(const Duration(milliseconds: 110), () {
          if (mounted) _chickBounceController.forward();
        });
      }
      if (status == AnimationStatus.completed) {
        _chickBounceController.reverse();
      }
    });

    _chickBounceController.forward();
  }

  @override
  void dispose() {
    _instantRefreshTimer?.cancel();
    _chickBounceController.dispose();
    _dustController.dispose();
    super.dispose();
  }

  Future<void> _loadAppliedRuleState() async {
    if (!mounted) return;
    final savedRuleId = await CompanyStore.instance.getInt(
      'appliedCompanyRuleId',
    );
    if (savedRuleId != null) {
      setState(() {
        _appliedCompanyRuleId = savedRuleId;
        if (savedRuleId == 1) _isRule1Editing = false;
        if (savedRuleId == 2) _isRule2Editing = false;
      });
    }
  }

  // =============================================================================
  // 🔐 SESSION — Logged-in user ka role aur naam auto-detect
  // =============================================================================
  Future<String> _getSessionRole() async {
    return await SessionService.currentRole ?? 'Owner';
  }

  Future<String> _getSessionName() async {
    return await SessionService.currentName ?? widget.ownerName;
  }

  String _formatActivityRelativeTime(
    String? timestampStr,
    String fallbackDate,
  ) {
    if (timestampStr == null || timestampStr.isEmpty) return fallbackDate;
    try {
      DateTime logTime = DateTime.parse(timestampStr);
      DateTime now = DateTime.now();
      Duration diff = now.difference(logTime);
      if (diff.inMinutes < 1) return 'Abhi-Abhi';
      if (diff.inMinutes < 60) return '${diff.inMinutes} min pehle';
      if (diff.inHours < 24) return '${diff.inHours} ghante pehle';
      if (diff.inDays == 1) return 'Kal';
      return fallbackDate;
    } catch (_) {
      return fallbackDate;
    }
  }

  Future<void> _loadKpiData() async {
    if (!mounted) return;

    List<dynamic> officeMgrList = [];
    List<dynamic> fieldMgrList = [];
    try {
      officeMgrList = await CompanyStore.instance.getJsonList('officeManagers');
      fieldMgrList = await CompanyStore.instance.getJsonList('fieldManagers');
    } catch (_) {}

    final farmers = await CompanyStore.instance.getJsonList('companyFarmers');
    final minLifting =
        await CompanyStore.instance.getInt('minLiftingDays') ?? 23;
    final maxLifting =
        await CompanyStore.instance.getInt('maxLiftingDays') ?? 60;

    if (!mounted) return;

    setState(() {
      _minLiftingDays = minLifting;
      _maxLiftingDays = maxLifting;
      _liftingFarmers.clear();
      _recentActivitiesList.clear();

      if (farmers.isNotEmpty) {
        _farmerCount = farmers.length;

        int activeBatchesSum = 0;
        List<Map<String, dynamic>> tempActivitiesCompiled = [];

        for (var farmer in farmers) {
          String farmerName = farmer['name'] ?? 'Farmer';

          if (farmer['batches'] != null) {
            final List<dynamic> batchesList = farmer['batches'];
            for (var batch in batchesList) {
              String batchId = batch['batchId'] ?? batch['id'] ?? 'LOT';
              String batchStatus = batch['status'].toString().toUpperCase();

              if (batchStatus == 'ACTIVE' ||
                  batchStatus == 'LIFTING READY' ||
                  batchStatus == 'PARTIAL LIFTED') {
                activeBatchesSum++;

                int daysOld = 0;
                try {
                  String startDateStr = batch['startDate'] ?? '';
                  List<String> parts = startDateStr.split('/');
                  if (parts.length == 3) {
                    DateTime startDate = DateTime(
                      int.parse(parts[2]),
                      int.parse(parts[1]),
                      int.parse(parts[0]),
                    );
                    DateTime currentDate = DateTime.now();
                    daysOld = currentDate.difference(startDate).inDays;
                    if (daysOld < 0) daysOld = 0;
                  }
                } catch (e) {
                  debugPrint('Lifting dynamic calculation failure: $e');
                }

                if (daysOld >= _minLiftingDays && daysOld <= _maxLiftingDays) {
                  int initialChicks = batch['chicksCount'] ?? 0;
                  int totalMortality = 0;
                  int totalChicksSold = 0;
                  double latestWeight = 0.0;

                  if (batch['dailyEntries'] != null) {
                    for (var entry in batch['dailyEntries']) {
                      if (entry['type'] == 'sale') {
                        totalChicksSold +=
                            int.tryParse(entry['chicksSold'].toString()) ?? 0;
                      } else {
                        totalMortality +=
                            int.tryParse(entry['mortality'].toString()) ?? 0;
                        double wt =
                            double.tryParse(entry['weight'].toString()) ?? 0.0;
                        if (wt > 0.0) latestWeight = wt;
                      }
                    }
                  }

                  int liveChicksCount =
                      initialChicks - totalMortality - totalChicksSold;

                  _liftingFarmers.add({
                    'name': farmerName,
                    'days': daysOld,
                    'chicks': liveChicksCount,
                    'avgWeight': latestWeight > 0
                        ? latestWeight.toStringAsFixed(2)
                        : '0.00',
                    'orderDays': daysOld,
                    'rawBatch': batch,
                  });
                }
              }

              if (batch['createdOn'] != null) {
                tempActivitiesCompiled.add({
                  'emoji': '🐣',
                  'roleGroup': 'Office Manager',
                  'title': 'Naya Batch: $farmerName ($batchId)',
                  'subtitle':
                      'By Owner | Quantity: ${batch['chicksCount']} chicks darj huye',
                  'timeString': _formatActivityRelativeTime(
                    batch['createdOn'],
                    batch['startDate'] ?? '',
                  ),
                  'timestampRaw':
                      DateTime.tryParse(batch['createdOn'] ?? '') ??
                      DateTime(2026, 1, 1),
                });
              }

              if (batch['dailyEntries'] != null) {
                for (var entry in batch['dailyEntries']) {
                  String rawTimestamp =
                      entry['timestamp'] ?? DateTime.now().toIso8601String();
                  DateTime parsedTime =
                      DateTime.tryParse(rawTimestamp) ?? DateTime(2026, 1, 1);
                  String rawRole = entry['enteredBy'] ?? 'Staff';
                  String entryUiDate = entry['date'] ?? '';

                  String compiledAttributionName = 'By Owner';
                  if (rawRole == 'Office Manager') {
                    if (officeMgrList.length > 1) {
                      var foundMatch = officeMgrList.firstWhere(
                        (m) => m['role'] == 'Office Manager',
                        orElse: () => null,
                      );
                      compiledAttributionName = foundMatch != null
                          ? 'By ${foundMatch['name']} (Office)'
                          : 'By Office Manager';
                    } else if (officeMgrList.length == 1) {
                      compiledAttributionName =
                          'By ${officeMgrList[0]['name']} (Office)';
                    } else {
                      compiledAttributionName = 'By Office Manager';
                    }
                  } else if (rawRole == 'Field Manager') {
                    if (fieldMgrList.length > 1) {
                      var foundMatch = fieldMgrList.firstWhere(
                        (m) => m['role'] == 'Field Manager',
                        orElse: () => null,
                      );
                      compiledAttributionName = foundMatch != null
                          ? 'By ${foundMatch['name']} (Field)'
                          : 'By Field Manager';
                    } else if (fieldMgrList.length == 1) {
                      compiledAttributionName =
                          'By ${fieldMgrList[0]['name']} (Field)';
                    } else {
                      compiledAttributionName = 'By Field Manager';
                    }
                  } else {
                    compiledAttributionName = 'By ${widget.ownerName} (Owner)';
                  }

                  if (entry['type'] == 'sale') {
                    tempActivitiesCompiled.add({
                      'emoji': '💰',
                      'roleGroup': 'Office Manager',
                      'title': 'Murgi Sale: $farmerName ($batchId)',
                      'subtitle':
                          '$compiledAttributionName | ${entry['chicksSold']} pcs uthe | Cash: ₹${entry['totalMoney']}',
                      'timeString': _formatActivityRelativeTime(
                        rawTimestamp,
                        entryUiDate,
                      ),
                      'timestampRaw': parsedTime,
                    });
                  } else {
                    int mort = int.tryParse(entry['mortality'].toString()) ?? 0;
                    int feed = int.tryParse(entry['feed'].toString()) ?? 0;
                    double wt =
                        double.tryParse(entry['weight'].toString()) ?? 0.0;

                    String compiledSubText = '$compiledAttributionName | ';
                    if (mort > 0) compiledSubText += '💀 Death: $mort ';
                    if (feed > 0) compiledSubText += '📦 Feed: $feed Bag ';
                    if (wt > 0)
                      compiledSubText +=
                          '⚖️ Wt: ${wt > 20 ? (wt / 1000).toStringAsFixed(2) : wt}kg ';

                    String logicGroup = (wt > 0 || mort > 0)
                        ? 'Field Manager'
                        : 'Office Manager';

                    tempActivitiesCompiled.add({
                      'emoji': '📝',
                      'roleGroup': logicGroup,
                      'title': 'Cost Entry: $farmerName ($batchId)',
                      'subtitle': compiledSubText,
                      'timeString': _formatActivityRelativeTime(
                        rawTimestamp,
                        entryUiDate,
                      ),
                      'timestampRaw': parsedTime,
                    });
                  }
                }
              }
            }
          }
        }

        tempActivitiesCompiled.sort(
          (a, b) => b['timestampRaw'].compareTo(a['timestampRaw']),
        );

        if (_selectedActivityFilter == 'Field Manager') {
          _recentActivitiesList = tempActivitiesCompiled
              .where((act) => act['roleGroup'] == 'Field Manager')
              .take(5)
              .toList();
        } else if (_selectedActivityFilter == 'Office Manager') {
          _recentActivitiesList = tempActivitiesCompiled
              .where((act) => act['roleGroup'] == 'Office Manager')
              .take(5)
              .toList();
        } else {
          _recentActivitiesList = tempActivitiesCompiled.take(5).toList();
        }

        _activeBatchCount = activeBatchesSum;
      } else {
        _farmerCount = 0;
        _activeBatchCount = 0;
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📦 STOCK DATA — LOAD / SAVE / ADD / USE (FEED + MEDICINE)
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _loadStockData() async {
    if (!mounted) return;

    final loadedFeed = await CompanyStore.instance.getFeedStockMap();
    final loadedMedicine = await CompanyStore.instance.getJsonList(
      'medicineStockList',
    );

    if (!mounted) return;
    setState(() {
      _feedStock = loadedFeed;
      _medicineStock = loadedMedicine;
    });
  }

  Future<void> _saveFeedStock() async {
    await CompanyStore.instance.saveFeedStockMap(_feedStock);
  }

  Future<void> _saveMedicineStock() async {
    await CompanyStore.instance.saveJsonList(
      'medicineStockList',
      _medicineStock,
    );
  }

  String _generateStockId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        Random().nextInt(9999).toString();
  }

  double? _convertQty(double value, String fromUnit, String toUnit) {
    if (fromUnit == toUnit) return value;
    if (fromUnit == 'ml' && toUnit == 'liter') return value / 1000.0;
    if (fromUnit == 'liter' && toUnit == 'ml') return value * 1000.0;
    return null;
  }

  List<String> _compatibleUnitsFor(String baseUnit) {
    if (baseUnit == 'ml' || baseUnit == 'liter') return ['ml', 'liter'];
    return [baseUnit];
  }

  Future<void> _addFeedStock(String type, double qty) async {
    setState(() {
      _feedStock[type] = (_feedStock[type] ?? 0.0) + qty;
    });
    await _saveFeedStock();
  }

  Future<bool> _useFeedStock(String type, double qty) async {
    double available = _feedStock[type] ?? 0.0;
    if (qty <= 0 || qty > available + 0.0001) return false;
    setState(() {
      _feedStock[type] = available - qty;
    });
    await _saveFeedStock();
    return true;
  }

  Future<void> _addMedicineStock({
    required String name,
    required double quantity,
    required String unit,
    required double actualPrice,
    required double farmerPrice,
    String nickName = '',
    String addedByRole = 'Owner',
    String addedByName = '',
  }) async {
    final newEntry = {
      'id': _generateStockId(),
      'name': name,
      'nickName': nickName,
      'unit': unit,
      'totalQuantity': quantity,
      'actualPrice': actualPrice,
      'farmerPrice': farmerPrice,
      'totalPrice': actualPrice,
      'remainingQuantity': quantity,
      'addedByRole': addedByRole,
      'addedByName': addedByName.isEmpty ? widget.ownerName : addedByName,
      'createdOn': DateTime.now().toIso8601String(),
    };
    setState(() {
      _medicineStock.insert(0, newEntry);
    });
    await _saveMedicineStock();
  }

  Future<Map<String, dynamic>> _useMedicineStock({
    required String medicineId,
    required double qty,
    required String inputUnit,
  }) async {
    final index = _medicineStock.indexWhere((m) => m['id'] == medicineId);
    if (index == -1) {
      return {'success': false, 'message': 'Medicine record nahi mila.'};
    }

    final med = _medicineStock[index];
    final String baseUnit = med['unit'];
    double totalQuantity = (med['totalQuantity'] as num).toDouble();
    double totalPrice = (med['totalPrice'] as num).toDouble();
    double remainingQuantity = (med['remainingQuantity'] as num).toDouble();

    double? qtyInBase = _convertQty(qty, inputUnit, baseUnit);
    if (qtyInBase == null) {
      return {
        'success': false,
        'message': 'Unit conversion possible nahi hai.',
      };
    }

    if (qtyInBase <= 0) {
      return {'success': false, 'message': 'Sahi quantity daalein.'};
    }

    if (qtyInBase > remainingQuantity + 0.0001) {
      return {
        'success': false,
        'message':
            'Itna stock available nahi hai. Sirf ${remainingQuantity.toStringAsFixed(2)} $baseUnit bacha hai.',
      };
    }

    double pricePerUnit = totalQuantity > 0 ? totalPrice / totalQuantity : 0.0;
    double deductedCost = qtyInBase * pricePerUnit;
    double newRemaining = remainingQuantity - qtyInBase;

    setState(() {
      _medicineStock[index]['remainingQuantity'] = newRemaining;
    });
    await _saveMedicineStock();

    return {
      'success': true,
      'cost': deductedCost,
      'remaining': newRemaining,
      'baseUnit': baseUnit,
    };
  }

  Future<void> _deleteMedicineStock(String medicineId) async {
    setState(() {
      _medicineStock.removeWhere((m) => m['id'] == medicineId);
    });
    await _saveMedicineStock();
  }

  Future<void> _devMasterResetAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text(
              'Master Reset Data?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'Isse registration details, managers, farmers aur batch entries ka saara data phone se udh jayega. Kya aap sure hain?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Haan, Delete Karo',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AuthService.instance.signOut();
      await SessionService.clearAll();
      Get.offAll(() => const WelcomeScreen());
      Get.snackbar(
        'App Reset Successfully',
        'Saara testing data khali ho gaya hai.',
        backgroundColor: Colors.black87,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
    }
  }

  void _showLiftingSettingsDialog() {
    final minController = TextEditingController(text: '$_minLiftingDays');
    final maxController = TextEditingController(text: '$_maxLiftingDays');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.settings_suggest_rounded, color: primaryGreen),
            SizedBox(width: 8),
            Text(
              'App Settings ⚙️',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: minController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Minimum Din (Kam se kam 20) *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: maxController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Maximum Din (Zyada se zyada 60) *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
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
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
            onPressed: () async {
              int? minD = int.tryParse(minController.text.trim());
              int? maxD = int.tryParse(maxController.text.trim());

              if (minD == null ||
                  maxD == null ||
                  minD < 20 ||
                  maxD > 60 ||
                  minD > maxD) {
                Get.snackbar(
                  'Invalid Range',
                  'Sahi range daalein! Min 20 se kam nahi, Max 60 se zyada nahi.',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                  snackPosition: SnackPosition.BOTTOM,
                  margin: const EdgeInsets.all(15),
                );
                return;
              }

              await CompanyStore.instance.setInt('minLiftingDays', minD);
              await CompanyStore.instance.setInt('maxLiftingDays', maxD);

              if (!mounted) return;
              Navigator.pop(context);
              await _loadKpiData();

              Get.snackbar(
                'Settings Saved',
                'Lifting criteria set: $minD - $maxD days.',
                backgroundColor: primaryGreen,
                colorText: Colors.white,
                snackPosition: SnackPosition.BOTTOM,
                margin: const EdgeInsets.all(15),
              );
            },
            child: const Text(
              'Save Settings',
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

  // =============================================================================
  // 🐣 CHICKS PURCHASE FORM
  // =============================================================================
  Future<void> _showChicksPurchaseForm() async {
    final companyCtrl = TextEditingController();
    final breedCtrl = TextEditingController();
    final billedQtyCtrl = TextEditingController();
    final freeQtyCtrl = TextEditingController();
    String freeType = 'Number';
    final rateCtrl = TextEditingController();
    final transportCtrl = TextEditingController();

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog.fullscreen(
        child: StatefulBuilder(
          builder: (context, setModalState) {
            double billedQty =
                double.tryParse(billedQtyCtrl.text.trim()) ?? 0.0;
            double freeInput = double.tryParse(freeQtyCtrl.text.trim()) ?? 0.0;
            double freeQty = freeType == 'Percentage'
                ? (billedQty * freeInput / 100)
                : freeInput;
            double totalChicks = billedQty + freeQty;
            double rate = double.tryParse(rateCtrl.text.trim()) ?? 0.0;
            double transportCost =
                double.tryParse(transportCtrl.text.trim()) ?? 0.0;
            double chicksCost = billedQty * rate;
            double grandTotal = chicksCost + transportCost;
            double effectiveRate = totalChicks > 0
                ? (grandTotal / totalChicks)
                : 0.0;

            return Scaffold(
              backgroundColor: const Color(0xFFF9FBF9),
              appBar: AppBar(
                backgroundColor: Colors.orange.shade800,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Row(
                  children: [
                    Text('🐣', style: TextStyle(fontSize: 20)),
                    SizedBox(width: 8),
                    Text(
                      'Chicks Purchase (Stock In)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: companyCtrl,
                      decoration: InputDecoration(
                        labelText: 'Hatchery/Company Ka Naam *',
                        hintText: 'e.g. Suguna, Venkys',
                        prefixIcon: const Icon(Icons.business_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: breedCtrl,
                      decoration: InputDecoration(
                        labelText: 'Breed / Nasal (Optional)',
                        hintText: 'e.g. Vencobb 400, Ross 308',
                        prefixIcon: const Icon(Icons.pets_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Chicks Quantity & Rate',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: billedQtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setModalState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Billed Chicks *',
                              hintText: 'e.g. 15000',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: rateCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setModalState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Rate/Chick (₹) *',
                              hintText: 'e.g. 35',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Free Chicks (Mortality Cover)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              Row(
                                children: [
                                  ChoiceChip(
                                    label: const Text('%'),
                                    selected: freeType == 'Percentage',
                                    onSelected: (val) => setModalState(
                                      () => freeType = 'Percentage',
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: const Text('Num'),
                                    selected: freeType == 'Number',
                                    onSelected: (val) => setModalState(
                                      () => freeType = 'Number',
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: freeQtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setModalState(() {}),
                            decoration: InputDecoration(
                              labelText: freeType == 'Percentage'
                                  ? 'Free Percentage (%)'
                                  : 'Free Chicks Number',
                              hintText: freeType == 'Percentage'
                                  ? 'e.g. 2'
                                  : 'e.g. 300',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          if (freeQty > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              '💡 Calculated Free Chicks: ${freeQty.toStringAsFixed(0)} pcs',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange.shade800,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: transportCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Gaadi Bhada / Transport (₹)',
                        hintText: 'e.g. 2500',
                        prefixIcon: const Icon(Icons.local_shipping_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade800,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '📊 Purchase Summary',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total Chicks (Billed + Free)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '${totalChicks.toStringAsFixed(0)} pcs',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Actual Rate/Chick (Bhada milakar)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '₹${effectiveRate.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Divider(color: Colors.white24, height: 1),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '💰 Grand Total',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '₹${grandTotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
              bottomNavigationBar: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                color: Colors.white,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      String company = companyCtrl.text.trim();
                      if (company.isEmpty || billedQty <= 0 || rate <= 0) {
                        Get.snackbar(
                          'Sahi Value Daalein ⚠️',
                          'Company ka naam, Billed Quantity aur Rate bharna zaroori hai.',
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                          snackPosition: SnackPosition.BOTTOM,
                          margin: const EdgeInsets.all(15),
                        );
                        return;
                      }

                      final addedByRole = await _getSessionRole();
                      final addedByName = await _getSessionName();

                      String? historyJson = await CompanyStore.instance
                          .getString('chicksPurchaseHistory');
                      List<dynamic> history = historyJson != null
                          ? json.decode(historyJson)
                          : [];

                      history.insert(0, {
                        'company': company,
                        'breed': breedCtrl.text.trim(),
                        'quantity': totalChicks,
                        'billedQty': billedQty,
                        'freeQty': freeQty,
                        'rate': rate,
                        'transportCost': transportCost,
                        'totalAmount': grandTotal,
                        'effectiveRate': effectiveRate,
                        'addedByRole': addedByRole,
                        'addedByName': addedByName,
                        'date': DateTime.now().toIso8601String(),
                      });

                      await CompanyStore.instance.setString(
                        'chicksPurchaseHistory',
                        json.encode(history),
                      );

                      if (!mounted) return;
                      Navigator.pop(context);
                      Get.snackbar(
                        'Chicks Stock Added ✅',
                        'Total $totalChicks chicks company stock mein add ho gaye.',
                        backgroundColor: Colors.orange.shade800,
                        colorText: Colors.white,
                        snackPosition: SnackPosition.BOTTOM,
                        margin: const EdgeInsets.all(15),
                      );
                    },
                    child: const Text(
                      'Save & Add to Stock',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // =============================================================================
  // 🌾 FEED PURCHASE FORM
  // =============================================================================
  Future<void> _showFeedPurchaseForm() async {
    final feedCompanyCtrl = TextEditingController();
    final starterBagsCtrl = TextEditingController();
    final starterPerBagCtrl = TextEditingController();
    final growerBagsCtrl = TextEditingController();
    final growerPerBagCtrl = TextEditingController();
    final finisherBagsCtrl = TextEditingController();
    final finisherPerBagCtrl = TextEditingController();

    double calcTotal(TextEditingController bags, TextEditingController perBag) {
      double b = double.tryParse(bags.text.trim()) ?? 0.0;
      double p = double.tryParse(perBag.text.trim()) ?? 0.0;
      return b * p;
    }

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog.fullscreen(
        child: StatefulBuilder(
          builder: (context, setModalState) {
            double starterTotal = calcTotal(starterBagsCtrl, starterPerBagCtrl);
            double growerTotal = calcTotal(growerBagsCtrl, growerPerBagCtrl);
            double finisherTotal = calcTotal(
              finisherBagsCtrl,
              finisherPerBagCtrl,
            );
            double grandTotal = starterTotal + growerTotal + finisherTotal;

            return Scaffold(
              backgroundColor: const Color(0xFFF9FBF9),
              appBar: AppBar(
                backgroundColor: primaryGreen,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.grass_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Feed Purchase',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: feedCompanyCtrl,
                      decoration: InputDecoration(
                        labelText: 'Company Ka Naam *',
                        hintText: 'e.g. Godrej Agrovet',
                        prefixIcon: const Icon(Icons.business_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _feedTypeSection(
                      emoji: '🐣',
                      label: 'Starter Feed',
                      color: Colors.blue,
                      bagsCtrl: starterBagsCtrl,
                      perBagCtrl: starterPerBagCtrl,
                      sectionTotal: starterTotal,
                      onChanged: () => setModalState(() {}),
                    ),
                    const SizedBox(height: 16),
                    _feedTypeSection(
                      emoji: '🐥',
                      label: 'Grower Feed',
                      color: Colors.purple,
                      bagsCtrl: growerBagsCtrl,
                      perBagCtrl: growerPerBagCtrl,
                      sectionTotal: growerTotal,
                      onChanged: () => setModalState(() {}),
                    ),
                    const SizedBox(height: 16),
                    _feedTypeSection(
                      emoji: '🐔',
                      label: 'Finisher Feed',
                      color: Colors.deepOrange,
                      bagsCtrl: finisherBagsCtrl,
                      perBagCtrl: finisherPerBagCtrl,
                      sectionTotal: finisherTotal,
                      onChanged: () => setModalState(() {}),
                    ),
                    const SizedBox(height: 20),
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
                          const Text(
                            '📊 Total Cost Summary',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _totalRow(
                            '🐣 Starter',
                            '₹${starterTotal.toStringAsFixed(2)}',
                          ),
                          const SizedBox(height: 4),
                          _totalRow(
                            '🐥 Grower',
                            '₹${growerTotal.toStringAsFixed(2)}',
                          ),
                          const SizedBox(height: 4),
                          _totalRow(
                            '🐔 Finisher',
                            '₹${finisherTotal.toStringAsFixed(2)}',
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(color: Colors.white24, height: 1),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '💰 Grand Total',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '₹${grandTotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
              bottomNavigationBar: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                color: Colors.white,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      String company = feedCompanyCtrl.text.trim();
                      if (company.isEmpty) {
                        Get.snackbar(
                          'Company Naam Chahiye ⚠️',
                          'Company ka naam bharna zaroori hai.',
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                          snackPosition: SnackPosition.BOTTOM,
                          margin: const EdgeInsets.all(15),
                        );
                        return;
                      }

                      double sBags =
                          double.tryParse(starterBagsCtrl.text.trim()) ?? 0;
                      double gBags =
                          double.tryParse(growerBagsCtrl.text.trim()) ?? 0;
                      double fBags =
                          double.tryParse(finisherBagsCtrl.text.trim()) ?? 0;

                      if (sBags <= 0 && gBags <= 0 && fBags <= 0) {
                        Get.snackbar(
                          'Bags Chahiye ⚠️',
                          'Kam se kam ek feed type ke bags bharo.',
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                          snackPosition: SnackPosition.BOTTOM,
                          margin: const EdgeInsets.all(15),
                        );
                        return;
                      }

                      final addedByRole = await _getSessionRole();
                      final addedByName = await _getSessionName();

                      if (sBags > 0) await _addFeedStock('Starter', sBags);
                      if (gBags > 0) await _addFeedStock('Grower', gBags);
                      if (fBags > 0) await _addFeedStock('Finisher', fBags);

                      String? historyJson = await CompanyStore.instance
                          .getString('feedPurchaseHistory');
                      List<dynamic> history = historyJson != null
                          ? json.decode(historyJson)
                          : [];

                      double sPerBag =
                          double.tryParse(starterPerBagCtrl.text.trim()) ?? 0;
                      double gPerBag =
                          double.tryParse(growerPerBagCtrl.text.trim()) ?? 0;
                      double fPerBag =
                          double.tryParse(finisherPerBagCtrl.text.trim()) ?? 0;

                      history.insert(0, {
                        'company': company,
                        'starter': {
                          'bags': sBags,
                          'perBagPrice': sPerBag,
                          'total': sBags * sPerBag,
                        },
                        'grower': {
                          'bags': gBags,
                          'perBagPrice': gPerBag,
                          'total': gBags * gPerBag,
                        },
                        'finisher': {
                          'bags': fBags,
                          'perBagPrice': fPerBag,
                          'total': fBags * fPerBag,
                        },
                        'grandTotal': grandTotal,
                        'addedByRole': addedByRole,
                        'addedByName': addedByName,
                        'date': DateTime.now().toIso8601String(),
                      });
                      await CompanyStore.instance.setString(
                        'feedPurchaseHistory',
                        json.encode(history),
                      );

                      if (!mounted) return;
                      Navigator.pop(context);
                      Get.snackbar(
                        'Feed Purchase Saved ✅',
                        'Teeno feed types stock mein add ho gaye | Total: ₹${grandTotal.toStringAsFixed(2)}',
                        backgroundColor: primaryGreen,
                        colorText: Colors.white,
                        snackPosition: SnackPosition.BOTTOM,
                        margin: const EdgeInsets.all(15),
                      );
                    },
                    child: const Text(
                      'Save Karo',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // =============================================================================
  // 💊 MEDICINE PURCHASE FORM
  // =============================================================================
  Future<void> _showMedicinePurchaseForm() async {
    final medNameCtrl = TextEditingController();
    final medNickNameCtrl = TextEditingController();
    final medQtyCtrl = TextEditingController();
    final medActualPriceCtrl = TextEditingController();
    final medFarmerPriceCtrl = TextEditingController();
    String selectedMedUnit = 'ml';

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog.fullscreen(
        child: StatefulBuilder(
          builder: (context, setModalState) {
            return Scaffold(
              backgroundColor: const Color(0xFFF9FBF9),
              appBar: AppBar(
                backgroundColor: Colors.teal,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Row(
                  children: [
                    Icon(
                      Icons.medication_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Medicine Purchase',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: medNameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Medicine Ka Naam *',
                        prefixIcon: const Icon(
                          Icons.medication_rounded,
                          color: Colors.teal,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: medNickNameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Nick Name (Optional)',
                        helperText:
                            'e.g. "Enro" — Batch entry mein shortcut ke liye',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: medQtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Total Quantity *',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Unit Chuno *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['ml', 'liter', 'packet', 'dabba'].map((unit) {
                        bool isSel = selectedMedUnit == unit;
                        return GestureDetector(
                          onTap: () =>
                              setModalState(() => selectedMedUnit = unit),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: isSel ? Colors.teal : Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSel ? Colors.teal : Colors.black12,
                              ),
                            ),
                            child: Text(
                              unit,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isSel
                                    ? Colors.white
                                    : Colors.teal.shade800,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.currency_rupee,
                            color: Colors.teal,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Price Details',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.teal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: medActualPriceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Actual Price (₹) *',
                        helperText: 'Company ne jis rate pe kharida',
                        prefixIcon: const Icon(
                          Icons.store_rounded,
                          color: Colors.blue,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Colors.blue,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: medFarmerPriceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Farmer Price (₹) *',
                        helperText: 'Jo rate farmer ko charge hoga',
                        prefixIcon: const Icon(
                          Icons.person_rounded,
                          color: Colors.orange,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Colors.orange,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
              bottomNavigationBar: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                color: Colors.white,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      String name = medNameCtrl.text.trim();
                      double? qty = double.tryParse(medQtyCtrl.text.trim());
                      double? actualPrice = double.tryParse(
                        medActualPriceCtrl.text.trim(),
                      );
                      double? farmerPrice = double.tryParse(
                        medFarmerPriceCtrl.text.trim(),
                      );

                      if (name.isEmpty ||
                          qty == null ||
                          qty <= 0 ||
                          actualPrice == null ||
                          actualPrice < 0 ||
                          farmerPrice == null ||
                          farmerPrice < 0) {
                        Get.snackbar(
                          'Invalid Input ⚠️',
                          'Sabhi fields sahi se bharein.',
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                          snackPosition: SnackPosition.BOTTOM,
                          margin: const EdgeInsets.all(15),
                        );
                        return;
                      }

                      final addedByRole = await _getSessionRole();
                      final addedByName = await _getSessionName();

                      await _addMedicineStock(
                        name: name,
                        quantity: qty,
                        unit: selectedMedUnit,
                        actualPrice: actualPrice,
                        farmerPrice: farmerPrice,
                        nickName: medNickNameCtrl.text.trim(),
                        addedByRole: addedByRole,
                        addedByName: addedByName,
                      );

                      if (!mounted) return;
                      Navigator.pop(context);
                      Get.snackbar(
                        'Medicine Purchase Saved ✅',
                        '$name ($qty $selectedMedUnit) stock mein add ho gaya.',
                        backgroundColor: Colors.teal,
                        colorText: Colors.white,
                        snackPosition: SnackPosition.BOTTOM,
                        margin: const EdgeInsets.all(15),
                      );
                    },
                    child: const Text(
                      'Save Karo',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // =============================================================================
  // 👷 LABOUR EXPENSE FORM
  // =============================================================================
  Future<void> _showLabourExpenseForm() async {
    final workerNameCtrl = TextEditingController();
    final quantityCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    final monthlySalaryCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String selectedLabourType = 'General Labour';
    String hisaabMode = 'din';

    final List<String> labourTypeOptions = [
      'Loading/Unloading',
      'Shed Cleaning',
      'Shed Repair',
      'Vaccination Help',
      'General Labour',
      'Monthly',
      'Other',
    ];

    double calcTotal(TextEditingController qty, TextEditingController rate) {
      double q = double.tryParse(qty.text.trim()) ?? 0.0;
      double r = double.tryParse(rate.text.trim()) ?? 0.0;
      return q * r;
    }

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog.fullscreen(
        child: StatefulBuilder(
          builder: (context, setModalState) {
            double totalAmount = hisaabMode == 'monthly'
                ? (double.tryParse(monthlySalaryCtrl.text.trim()) ?? 0.0)
                : calcTotal(quantityCtrl, rateCtrl);

            return Scaffold(
              backgroundColor: const Color(0xFFF9FBF9),
              appBar: AppBar(
                backgroundColor: Colors.orange.shade800,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Row(
                  children: [
                    Icon(
                      Icons.engineering_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Labour Expense',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: workerNameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Worker Ka Naam *',
                        hintText: 'e.g. Ramesh Mistri',
                        prefixIcon: const Icon(Icons.person_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Kaam Ka Type *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: labourTypeOptions.map((type) {
                        bool isSel = selectedLabourType == type;
                        return GestureDetector(
                          onTap: () =>
                              setModalState(() => selectedLabourType = type),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? Colors.orange.shade800
                                  : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSel
                                    ? Colors.orange.shade800
                                    : Colors.black12,
                              ),
                            ),
                            child: Text(
                              type,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isSel
                                    ? Colors.white
                                    : Colors.orange.shade800,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Hisaab Kis Tarah Karein? *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ChoiceChip(
                          label: const Text('Din (Days)'),
                          selected: hisaabMode == 'din',
                          selectedColor: Colors.orange.shade800,
                          labelStyle: TextStyle(
                            color: hisaabMode == 'din'
                                ? Colors.white
                                : Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (val) =>
                              setModalState(() => hisaabMode = 'din'),
                        ),
                        ChoiceChip(
                          label: const Text('Ghanta (Hours)'),
                          selected: hisaabMode == 'ghanta',
                          selectedColor: Colors.orange.shade800,
                          labelStyle: TextStyle(
                            color: hisaabMode == 'ghanta'
                                ? Colors.white
                                : Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (val) =>
                              setModalState(() => hisaabMode = 'ghanta'),
                        ),
                        ChoiceChip(
                          label: const Text('Monthly (Fixed Salary)'),
                          selected: hisaabMode == 'monthly',
                          selectedColor: Colors.orange.shade800,
                          labelStyle: TextStyle(
                            color: hisaabMode == 'monthly'
                                ? Colors.white
                                : Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (val) =>
                              setModalState(() => hisaabMode = 'monthly'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (hisaabMode != 'monthly')
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: quantityCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (_) => setModalState(() {}),
                              decoration: InputDecoration(
                                labelText: hisaabMode == 'din'
                                    ? 'Kitne Din *'
                                    : 'Kitne Ghante *',
                                hintText: hisaabMode == 'din'
                                    ? 'e.g. 2'
                                    : 'e.g. 6',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: rateCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (_) => setModalState(() {}),
                              decoration: InputDecoration(
                                labelText: hisaabMode == 'din'
                                    ? 'Rate/Din (₹) *'
                                    : 'Rate/Ghanta (₹) *',
                                hintText: 'e.g. 400',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      TextField(
                        controller: monthlySalaryCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setModalState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Maheene Ki Salary (₹) *',
                          hintText: 'e.g. 8000',
                          helperText:
                              'Ye worker ko mahine mein itna fixed milta hai',
                          prefixIcon: const Icon(Icons.calendar_month_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade800,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '💰 Total Amount',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '₹${totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Note (Optional)',
                        hintText: 'e.g. Chicks unload karne ke liye',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
              bottomNavigationBar: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                color: Colors.white,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      String workerName = workerNameCtrl.text.trim();
                      double qty =
                          double.tryParse(quantityCtrl.text.trim()) ?? 0;
                      double rate = double.tryParse(rateCtrl.text.trim()) ?? 0;
                      double monthlySalary =
                          double.tryParse(monthlySalaryCtrl.text.trim()) ?? 0;

                      if (workerName.isEmpty) {
                        Get.snackbar(
                          'Worker Naam Chahiye ⚠️',
                          'Worker ka naam bharna zaroori hai.',
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                          snackPosition: SnackPosition.BOTTOM,
                          margin: const EdgeInsets.all(15),
                        );
                        return;
                      }

                      if (hisaabMode == 'monthly') {
                        if (monthlySalary <= 0) {
                          Get.snackbar(
                            'Sahi Salary Daalein ⚠️',
                            'Monthly salary zero ya negative nahi ho sakti.',
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                            snackPosition: SnackPosition.BOTTOM,
                            margin: const EdgeInsets.all(15),
                          );
                          return;
                        }
                      } else {
                        if (qty <= 0 || rate <= 0) {
                          Get.snackbar(
                            'Sahi Value Daalein ⚠️',
                            'Din/Ghanta aur Rate zero ya negative nahi ho sakte.',
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                            snackPosition: SnackPosition.BOTTOM,
                            margin: const EdgeInsets.all(15),
                          );
                          return;
                        }
                      }

                      final addedByRole = await _getSessionRole();
                      final addedByName = await _getSessionName();

                      String? historyJson = await CompanyStore.instance
                          .getString('labourExpenseHistory');
                      List<dynamic> history = historyJson != null
                          ? json.decode(historyJson)
                          : [];

                      double finalTotal = hisaabMode == 'monthly'
                          ? monthlySalary
                          : qty * rate;

                      history.insert(0, {
                        'workerName': workerName,
                        'labourType': selectedLabourType,
                        'unitMode': hisaabMode == 'din'
                            ? 'Din'
                            : hisaabMode == 'ghanta'
                            ? 'Ghanta'
                            : 'Monthly',
                        'quantity': hisaabMode == 'monthly' ? 1 : qty,
                        'rate': hisaabMode == 'monthly' ? monthlySalary : rate,
                        'totalAmount': finalTotal,
                        'note': noteCtrl.text.trim(),
                        'addedByRole': addedByRole,
                        'addedByName': addedByName,
                        'date': DateTime.now().toIso8601String(),
                      });

                      await CompanyStore.instance.setString(
                        'labourExpenseHistory',
                        json.encode(history),
                      );

                      if (!mounted) return;
                      Navigator.pop(context);
                      Get.snackbar(
                        'Labour Expense Saved ✅',
                        '$workerName ko ₹${finalTotal.toStringAsFixed(2)} ka kharcha darj ho gaya.',
                        backgroundColor: Colors.orange.shade800,
                        colorText: Colors.white,
                        snackPosition: SnackPosition.BOTTOM,
                        margin: const EdgeInsets.all(15),
                      );
                    },
                    child: const Text(
                      'Save Karo',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // =============================================================================
  // 📋 OTHER EXPENSE FORM
  // =============================================================================
  Future<void> _showOtherExpenseForm() async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String selectedExpenseType = 'General/Other';

    final List<String> expenseTypeOptions = [
      'Transport/Fuel',
      'Electricity Bill',
      'Shed Rent',
      'Equipment/Repair',
      'Litter/Bedding',
      'Water Supply',
      'Stationery/Office',
      'Bank/Loan Interest',
      'General/Other',
    ];

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog.fullscreen(
        child: StatefulBuilder(
          builder: (context, setModalState) {
            double amountVal = double.tryParse(amountCtrl.text.trim()) ?? 0.0;

            return Scaffold(
              backgroundColor: const Color(0xFFF9FBF9),
              appBar: AppBar(
                backgroundColor: Colors.purple.shade700,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Row(
                  children: [
                    Icon(
                      Icons.receipt_long_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Other Expense',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Expense Ka Type *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: expenseTypeOptions.map((type) {
                        bool isSel = selectedExpenseType == type;
                        return GestureDetector(
                          onTap: () =>
                              setModalState(() => selectedExpenseType = type),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? Colors.purple.shade700
                                  : Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSel
                                    ? Colors.purple.shade700
                                    : Colors.black12,
                              ),
                            ),
                            child: Text(
                              type,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isSel
                                    ? Colors.white
                                    : Colors.purple.shade800,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Amount (₹) *',
                        hintText: 'e.g. 1500',
                        prefixIcon: const Icon(Icons.currency_rupee),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Note (Optional)',
                        hintText: 'e.g. Generator repair karaya',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade700,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '💰 Total Amount',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '₹${amountVal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
              bottomNavigationBar: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                color: Colors.white,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade700,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      double amount =
                          double.tryParse(amountCtrl.text.trim()) ?? 0;

                      if (amount <= 0) {
                        Get.snackbar(
                          'Sahi Amount Daalein ⚠️',
                          'Amount zero ya negative nahi ho sakta.',
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                          snackPosition: SnackPosition.BOTTOM,
                          margin: const EdgeInsets.all(15),
                        );
                        return;
                      }

                      final addedByRole = await _getSessionRole();
                      final addedByName = await _getSessionName();

                      String? historyJson = await CompanyStore.instance
                          .getString('otherExpenseHistory');
                      List<dynamic> history = historyJson != null
                          ? json.decode(historyJson)
                          : [];

                      history.insert(0, {
                        'expenseType': selectedExpenseType,
                        'amount': amount,
                        'note': noteCtrl.text.trim(),
                        'addedByRole': addedByRole,
                        'addedByName': addedByName,
                        'date': DateTime.now().toIso8601String(),
                      });

                      await CompanyStore.instance.setString(
                        'otherExpenseHistory',
                        json.encode(history),
                      );

                      if (!mounted) return;
                      Navigator.pop(context);
                      Get.snackbar(
                        'Expense Saved ✅',
                        '$selectedExpenseType — ₹${amount.toStringAsFixed(2)} darj ho gaya.',
                        backgroundColor: Colors.purple.shade700,
                        colorText: Colors.white,
                        snackPosition: SnackPosition.BOTTOM,
                        margin: const EdgeInsets.all(15),
                      );
                    },
                    child: const Text(
                      'Save Karo',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // =============================================================================
  // _showAddFeedStockDialog() — Stock screen ka "+ Add Stock" button
  // =============================================================================
  void _showAddFeedStockDialog() {
    final feedCompanyCtrl = TextEditingController();
    final starterBagsCtrl = TextEditingController();
    final starterPerBagCtrl = TextEditingController();
    final growerBagsCtrl = TextEditingController();
    final growerPerBagCtrl = TextEditingController();
    final finisherBagsCtrl = TextEditingController();
    final finisherPerBagCtrl = TextEditingController();

    double calcTotal(TextEditingController bags, TextEditingController perBag) {
      double b = double.tryParse(bags.text.trim()) ?? 0.0;
      double p = double.tryParse(perBag.text.trim()) ?? 0.0;
      return b * p;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog.fullscreen(
        child: StatefulBuilder(
          builder: (context, setModalState) {
            double starterTotal = calcTotal(starterBagsCtrl, starterPerBagCtrl);
            double growerTotal = calcTotal(growerBagsCtrl, growerPerBagCtrl);
            double finisherTotal = calcTotal(
              finisherBagsCtrl,
              finisherPerBagCtrl,
            );
            double grandTotal = starterTotal + growerTotal + finisherTotal;

            return Scaffold(
              backgroundColor: const Color(0xFFF9FBF9),
              appBar: AppBar(
                backgroundColor: primaryGreen,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.add_box_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Feed Stock Add Karo',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: feedCompanyCtrl,
                      decoration: InputDecoration(
                        labelText: 'Company Ka Naam *',
                        hintText: 'e.g. Godrej Agrovet',
                        prefixIcon: const Icon(Icons.business_rounded),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _feedTypeSection(
                      emoji: '🐣',
                      label: 'Starter Feed',
                      color: Colors.blue,
                      bagsCtrl: starterBagsCtrl,
                      perBagCtrl: starterPerBagCtrl,
                      sectionTotal: starterTotal,
                      onChanged: () => setModalState(() {}),
                    ),
                    const SizedBox(height: 16),
                    _feedTypeSection(
                      emoji: '🐥',
                      label: 'Grower Feed',
                      color: Colors.purple,
                      bagsCtrl: growerBagsCtrl,
                      perBagCtrl: growerPerBagCtrl,
                      sectionTotal: growerTotal,
                      onChanged: () => setModalState(() {}),
                    ),
                    const SizedBox(height: 16),
                    _feedTypeSection(
                      emoji: '🐔',
                      label: 'Finisher Feed',
                      color: Colors.deepOrange,
                      bagsCtrl: finisherBagsCtrl,
                      perBagCtrl: finisherPerBagCtrl,
                      sectionTotal: finisherTotal,
                      onChanged: () => setModalState(() {}),
                    ),
                    const SizedBox(height: 20),
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
                          const Text(
                            '📊 Total Cost Summary',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _totalRow(
                            '🐣 Starter',
                            '₹${starterTotal.toStringAsFixed(2)}',
                          ),
                          const SizedBox(height: 4),
                          _totalRow(
                            '🐥 Grower',
                            '₹${growerTotal.toStringAsFixed(2)}',
                          ),
                          const SizedBox(height: 4),
                          _totalRow(
                            '🐔 Finisher',
                            '₹${finisherTotal.toStringAsFixed(2)}',
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(color: Colors.white24, height: 1),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '💰 Grand Total',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '₹${grandTotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
              bottomNavigationBar: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                color: Colors.white,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      String company = feedCompanyCtrl.text.trim();
                      if (company.isEmpty) {
                        Get.snackbar(
                          'Company Naam Chahiye ⚠️',
                          'Company ka naam bharna zaroori hai.',
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                          snackPosition: SnackPosition.BOTTOM,
                          margin: const EdgeInsets.all(15),
                        );
                        return;
                      }

                      double sBags =
                          double.tryParse(starterBagsCtrl.text.trim()) ?? 0;
                      double gBags =
                          double.tryParse(growerBagsCtrl.text.trim()) ?? 0;
                      double fBags =
                          double.tryParse(finisherBagsCtrl.text.trim()) ?? 0;

                      if (sBags <= 0 && gBags <= 0 && fBags <= 0) {
                        Get.snackbar(
                          'Bags Chahiye ⚠️',
                          'Kam se kam ek feed type ke bags bharo.',
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                          snackPosition: SnackPosition.BOTTOM,
                          margin: const EdgeInsets.all(15),
                        );
                        return;
                      }

                      if (sBags > 0) await _addFeedStock('Starter', sBags);
                      if (gBags > 0) await _addFeedStock('Grower', gBags);
                      if (fBags > 0) await _addFeedStock('Finisher', fBags);

                      String? historyJson = await CompanyStore.instance
                          .getString('feedPurchaseHistory');
                      List<dynamic> history = historyJson != null
                          ? json.decode(historyJson)
                          : [];

                      double sPerBag =
                          double.tryParse(starterPerBagCtrl.text.trim()) ?? 0;
                      double gPerBag =
                          double.tryParse(growerPerBagCtrl.text.trim()) ?? 0;
                      double fPerBag =
                          double.tryParse(finisherPerBagCtrl.text.trim()) ?? 0;

                      history.insert(0, {
                        'company': company,
                        'starter': {
                          'bags': sBags,
                          'perBagPrice': sPerBag,
                          'total': sBags * sPerBag,
                        },
                        'grower': {
                          'bags': gBags,
                          'perBagPrice': gPerBag,
                          'total': gBags * gPerBag,
                        },
                        'finisher': {
                          'bags': fBags,
                          'perBagPrice': fPerBag,
                          'total': fBags * fPerBag,
                        },
                        'grandTotal': grandTotal,
                        'date': DateTime.now().toIso8601String(),
                      });
                      await CompanyStore.instance.setString(
                        'feedPurchaseHistory',
                        json.encode(history),
                      );

                      if (!mounted) return;
                      Navigator.pop(context);
                      Get.snackbar(
                        'Stock Added ✅',
                        '$company se feed stock update ho gaya | Total: ₹${grandTotal.toStringAsFixed(2)}',
                        backgroundColor: primaryGreen,
                        colorText: Colors.white,
                        snackPosition: SnackPosition.BOTTOM,
                        margin: const EdgeInsets.all(15),
                      );
                    },
                    child: const Text(
                      'Add Karo',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Feed Type Section Widget ─────────────────────────────────────────────────
  Widget _feedTypeSection({
    required String emoji,
    required String label,
    required MaterialColor color,
    required TextEditingController bagsCtrl,
    required TextEditingController perBagCtrl,
    required double sectionTotal,
    required VoidCallback onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color.shade800,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: sectionTotal > 0
                      ? color.shade100
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '₹${sectionTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: sectionTotal > 0 ? color.shade900 : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: bagsCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => onChanged(),
                  decoration: InputDecoration(
                    labelText: 'Total Bags *',
                    hintText: 'e.g. 10',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: color.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: color.shade200),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: perBagCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => onChanged(),
                  decoration: InputDecoration(
                    labelText: 'Per Bag Price (₹) *',
                    hintText: 'e.g. 1200',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: color.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: color.shade200),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Total Row Helper ─────────────────────────────────────────────────────────
  Widget _totalRow(String label, String value) {
    return Row(
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
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📦 STOCK DIALOGS — USE FEED, ADD/USE/DELETE MEDICINE
  // ═══════════════════════════════════════════════════════════════════════════

  void _showUseFeedStockDialog(String type) {
    final qtyCtrl = TextEditingController();
    double available = _feedStock[type] ?? 0.0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(
              Icons.remove_circle_outline_rounded,
              color: Colors.orange,
            ),
            const SizedBox(width: 8),
            Text(
              '$type Stock Use Karo',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available Stock: ${available.toStringAsFixed(2)} Bag',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Kitne Bag Use Karna Hai *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () async {
              double? qty = double.tryParse(qtyCtrl.text.trim());
              if (qty == null || qty <= 0) {
                Get.snackbar(
                  'Invalid Quantity',
                  'Sahi bag quantity daalein.',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                  snackPosition: SnackPosition.BOTTOM,
                  margin: const EdgeInsets.all(15),
                );
                return;
              }
              bool success = await _useFeedStock(type, qty);
              if (!mounted) return;
              if (!success) {
                Get.snackbar(
                  'Stock Kam Hai',
                  'Itna stock available nahi hai.',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                  snackPosition: SnackPosition.BOTTOM,
                  margin: const EdgeInsets.all(15),
                );
                return;
              }
              Navigator.pop(context);
              Get.snackbar(
                'Stock Use Hua ✅',
                '$type se $qty bag ghata diya gaya.',
                backgroundColor: primaryGreen,
                colorText: Colors.white,
                snackPosition: SnackPosition.BOTTOM,
                margin: const EdgeInsets.all(15),
              );
            },
            child: const Text(
              'Confirm Karo',
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

  void _showAddMedicineDialog() {
    final nameCtrl = TextEditingController();
    final nickNameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final actualPriceCtrl = TextEditingController();
    final farmerPriceCtrl = TextEditingController();
    String selectedUnit = 'ml';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.medication_rounded, color: Colors.teal),
              SizedBox(width: 8),
              Text(
                'Medicine Stock Add Karo',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Medicine Ka Naam *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nickNameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Nick Name (Optional)',
                    helperText: 'e.g. "Enro" for Enrofloxacin',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Total Quantity *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Unit Chuno *',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['ml', 'liter', 'packet', 'dabba'].map((unit) {
                    bool isSel = selectedUnit == unit;
                    return GestureDetector(
                      onTap: () => setModalState(() => selectedUnit = unit),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: isSel ? Colors.teal : Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSel ? Colors.teal : Colors.black12,
                          ),
                        ),
                        child: Text(
                          unit,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSel ? Colors.white : Colors.teal.shade800,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: actualPriceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Actual Price (₹) *',
                    helperText: 'Company ne jis rate pe kharida',
                    prefixIcon: const Icon(
                      Icons.store_rounded,
                      color: Colors.blue,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: farmerPriceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Farmer Price (₹) *',
                    helperText: 'Jo rate farmer ko charge hoga',
                    prefixIcon: const Icon(
                      Icons.person_rounded,
                      color: Colors.orange,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              onPressed: () async {
                String name = nameCtrl.text.trim();
                double? qty = double.tryParse(qtyCtrl.text.trim());
                double? actualPrice = double.tryParse(
                  actualPriceCtrl.text.trim(),
                );
                double? farmerPrice = double.tryParse(
                  farmerPriceCtrl.text.trim(),
                );

                if (name.isEmpty ||
                    qty == null ||
                    qty <= 0 ||
                    actualPrice == null ||
                    actualPrice < 0 ||
                    farmerPrice == null ||
                    farmerPrice < 0) {
                  Get.snackbar(
                    'Invalid Input',
                    'Sabhi fields sahi se bharein.',
                    backgroundColor: Colors.red,
                    colorText: Colors.white,
                    snackPosition: SnackPosition.BOTTOM,
                    margin: const EdgeInsets.all(15),
                  );
                  return;
                }

                await _addMedicineStock(
                  name: name,
                  quantity: qty,
                  unit: selectedUnit,
                  actualPrice: actualPrice,
                  farmerPrice: farmerPrice,
                  nickName: nickNameCtrl.text.trim(),
                );

                if (!mounted) return;
                Navigator.pop(context);
                Get.snackbar(
                  'Medicine Added ✅',
                  '$name ($qty $selectedUnit) stock mein add ho gaya.',
                  backgroundColor: Colors.teal,
                  colorText: Colors.white,
                  snackPosition: SnackPosition.BOTTOM,
                  margin: const EdgeInsets.all(15),
                );
              },
              child: const Text(
                'Add Karo',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUseMedicineDialog(Map<String, dynamic> medicine) {
    final qtyCtrl = TextEditingController();
    final String baseUnit = medicine['unit'];
    String selectedUnit = baseUnit;
    double remaining = (medicine['remainingQuantity'] as num).toDouble();
    double totalQuantity = (medicine['totalQuantity'] as num).toDouble();
    double totalPrice = (medicine['totalPrice'] as num).toDouble();
    double pricePerUnit = totalQuantity > 0 ? totalPrice / totalQuantity : 0.0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          double enteredQty = double.tryParse(qtyCtrl.text.trim()) ?? 0.0;
          double? qtyInBase = _convertQty(enteredQty, selectedUnit, baseUnit);
          double previewCost = (qtyInBase != null)
              ? qtyInBase * pricePerUnit
              : 0.0;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                const Icon(Icons.medication_liquid_rounded, color: Colors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${medicine['name']} Use Karo',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Available: ${remaining.toStringAsFixed(2)} $baseUnit  |  Rate: ₹${pricePerUnit.toStringAsFixed(2)}/$baseUnit',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.teal.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setModalState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Quantity *',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (_compatibleUnitsFor(baseUnit).length > 1)
                      Expanded(
                        flex: 1,
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedUnit,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: _compatibleUnitsFor(baseUnit)
                              .map(
                                (u) =>
                                    DropdownMenuItem(value: u, child: Text(u)),
                              )
                              .toList(),
                          onChanged: (val) => setModalState(
                            () => selectedUnit = val ?? baseUnit,
                          ),
                        ),
                      )
                    else
                      Expanded(
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            baseUnit,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Text(
                    'Iska Cost Hoga: ₹${previewCost.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                onPressed: () async {
                  double? qty = double.tryParse(qtyCtrl.text.trim());
                  if (qty == null || qty <= 0) {
                    Get.snackbar(
                      'Invalid Quantity',
                      'Sahi quantity daalein.',
                      backgroundColor: Colors.red,
                      colorText: Colors.white,
                      snackPosition: SnackPosition.BOTTOM,
                      margin: const EdgeInsets.all(15),
                    );
                    return;
                  }

                  final result = await _useMedicineStock(
                    medicineId: medicine['id'],
                    qty: qty,
                    inputUnit: selectedUnit,
                  );

                  if (!mounted) return;

                  if (result['success'] != true) {
                    Get.snackbar(
                      'Stock Error',
                      result['message'] ?? 'Kuch galat ho gaya.',
                      backgroundColor: Colors.red,
                      colorText: Colors.white,
                      snackPosition: SnackPosition.BOTTOM,
                      margin: const EdgeInsets.all(15),
                    );
                    return;
                  }

                  Navigator.pop(context);
                  Get.snackbar(
                    'Stock Use Hua ✅',
                    '$qty $selectedUnit nikala gaya | Cost: ₹${(result['cost'] as double).toStringAsFixed(2)}',
                    backgroundColor: primaryGreen,
                    colorText: Colors.white,
                    snackPosition: SnackPosition.BOTTOM,
                    margin: const EdgeInsets.all(15),
                  );
                },
                child: const Text(
                  'Nikaalo',
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

  void _showDeleteMedicineConfirm(Map<String, dynamic> medicine) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text(
              'Entry Delete Karein?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          '${medicine['name']} ki ye stock entry permanently delete ho jayegi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _deleteMedicineStock(medicine['id']);
              if (!mounted) return;
              Navigator.pop(context);
              Get.snackbar(
                'Entry Deleted',
                '${medicine['name']} hata diya gaya.',
                backgroundColor: Colors.black87,
                colorText: Colors.white,
                snackPosition: SnackPosition.BOTTOM,
                margin: const EdgeInsets.all(15),
              );
            },
            child: const Text(
              'Delete Karo',
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

  void _showRuleConflictWarning(BuildContext context, int activeId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 26),
            SizedBox(width: 8),
            Text(
              'Rule Locked Alert!',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Aapne already Rule $activeId select kiya hua hai. Kripya use unselect/edit karne ke baad hi aap dusra rule apply kar sakte hain.',
          style: const TextStyle(
            fontSize: 14,
            height: 1.4,
            color: Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'OK Clear',
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

  // ═══════════════════════════════════════════════════════════════════════════
  // 🧮 SETTLEMENT WIZARD
  // ═══════════════════════════════════════════════════════════════════════════
  void _showLiveSettlementWizard() {
    final r1BigFeedRateCtrl = TextEditingController(text: '42.00');
    final r1BigChicksRateCtrl = TextEditingController(text: '40.00');
    final r1BigAdminCostCtrl = TextEditingController(text: '1.50');
    final r1BigKgPerBagCtrl = TextEditingController(text: '50.0');
    final r1BigTargetCostCtrl = TextEditingController(text: '85.00');
    final r1BigBaseCommCtrl = TextEditingController(text: '8.00');
    final r1BigSavingsShareCtrl = TextEditingController(text: '50');
    final r1BigExceededShareCtrl = TextEditingController(text: '50');
    final r1BigRateBonusThreshCtrl = TextEditingController(text: '110.00');
    final r1BigRateBonusShareCtrl = TextEditingController(text: '10');
    bool r1BigMedicineInProdCost = true;

    final r1SmFeedRateCtrl = TextEditingController(text: '42.00');
    final r1SmChicksRateCtrl = TextEditingController(text: '40.00');
    final r1SmAdminCostCtrl = TextEditingController(text: '1.50');
    final r1SmKgPerBagCtrl = TextEditingController(text: '50.0');
    final r1SmTargetCostCtrl = TextEditingController(text: '90.00');
    final r1SmBaseCommCtrl = TextEditingController(text: '10.00');
    final r1SmSavingsShareCtrl = TextEditingController(text: '50');
    final r1SmExceededShareCtrl = TextEditingController(text: '50');
    final r1SmRateBonusThreshCtrl = TextEditingController(text: '120.00');
    final r1SmRateBonusShareCtrl = TextEditingController(text: '10');
    bool r1SmMedicineInProdCost = true;

    final r2BaseRateCtrl = TextEditingController(text: '7.50');
    final r2GoodMinCtrl = TextEditingController(text: '1.40');
    final r2GoodMaxCtrl = TextEditingController(text: '1.54');
    final r2NormMinCtrl = TextEditingController(text: '1.55');
    final r2NormMaxCtrl = TextEditingController(text: '1.65');
    final r2BonusCtrl = TextEditingController(text: '0.10');
    final r2PenaltyCtrl = TextEditingController(text: '0.15');
    bool r2IsRupeeIncentiveMode = true;
    bool r2IsMedicineIncludeProd = true;
    bool r2UseConvertedFcr = true;

    int selectedRuleTab = (_appliedCompanyRuleId != null)
        ? _appliedCompanyRuleId!
        : 1;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog.fullscreen(
        child: StatefulBuilder(
          builder: (context, setModalState) => Scaffold(
            backgroundColor: const Color(0xFFF9FBF9),
            appBar: AppBar(
              backgroundColor: primaryGreen,
              elevation: 0,
              title: const Text(
                'SaaS Settlement Panel Engine',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: Column(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 12,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildRuleTabHeader(
                          1,
                          'Rule 1 (Auto Size)',
                          selectedRuleTab,
                          (tab) => setModalState(() => selectedRuleTab = tab),
                        ),
                        const SizedBox(width: 8),
                        _buildRuleTabHeader(
                          2,
                          'Rule 2 (FCR Matrix)',
                          selectedRuleTab,
                          (tab) => setModalState(() => selectedRuleTab = tab),
                        ),
                        const SizedBox(width: 8),
                        _buildRuleTabHeader(
                          3,
                          'Rule 3 (Future)',
                          selectedRuleTab,
                          null,
                          isLocked: true,
                        ),
                        const SizedBox(width: 8),
                        _buildRuleTabHeader(
                          4,
                          'Rule 4 (Future)',
                          selectedRuleTab,
                          null,
                          isLocked: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1, color: Colors.black12),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: selectedRuleTab == 1
                        ? _buildRule1AutoSizeForm(
                            bigFeedRate: r1BigFeedRateCtrl,
                            bigChicksRate: r1BigChicksRateCtrl,
                            bigAdminCost: r1BigAdminCostCtrl,
                            bigKgPerBag: r1BigKgPerBagCtrl,
                            bigTargetCost: r1BigTargetCostCtrl,
                            bigBaseComm: r1BigBaseCommCtrl,
                            bigSavingsShare: r1BigSavingsShareCtrl,
                            bigExceededShare: r1BigExceededShareCtrl,
                            bigRateBonusThresh: r1BigRateBonusThreshCtrl,
                            bigRateBonusShare: r1BigRateBonusShareCtrl,
                            bigMedicineInProdCost: r1BigMedicineInProdCost,
                            onBigMedicineToggle: (val) => setModalState(
                              () => r1BigMedicineInProdCost = val,
                            ),
                            smFeedRate: r1SmFeedRateCtrl,
                            smChicksRate: r1SmChicksRateCtrl,
                            smAdminCost: r1SmAdminCostCtrl,
                            smKgPerBag: r1SmKgPerBagCtrl,
                            smTargetCost: r1SmTargetCostCtrl,
                            smBaseComm: r1SmBaseCommCtrl,
                            smSavingsShare: r1SmSavingsShareCtrl,
                            smExceededShare: r1SmExceededShareCtrl,
                            smRateBonusThresh: r1SmRateBonusThreshCtrl,
                            smRateBonusShare: r1SmRateBonusShareCtrl,
                            smMedicineInProdCost: r1SmMedicineInProdCost,
                            onSmMedicineToggle: (val) => setModalState(
                              () => r1SmMedicineInProdCost = val,
                            ),
                            isEditable:
                                _isRule1Editing &&
                                (_appliedCompanyRuleId == null ||
                                    _appliedCompanyRuleId == 1),
                            showEditButton: _appliedCompanyRuleId == 1,
                            onToggleEdit: () {
                              setState(() {
                                _isRule1Editing = true;
                                _appliedCompanyRuleId = null;
                              });
                              setModalState(() {});
                            },
                          )
                        : _buildRule2FormFields(
                            baseRate: r2BaseRateCtrl,
                            goodMin: r2GoodMinCtrl,
                            goodMax: r2GoodMaxCtrl,
                            normMin: r2NormMinCtrl,
                            normMax: r2NormMaxCtrl,
                            bonus: r2BonusCtrl,
                            penalty: r2PenaltyCtrl,
                            isRupeeMode: r2IsRupeeIncentiveMode,
                            isMedInclude: r2IsMedicineIncludeProd,
                            useConvFcr: r2UseConvertedFcr,
                            onToggleIncentive: (val) => setModalState(
                              () => r2IsRupeeIncentiveMode = val,
                            ),
                            onToggleMed: (val) => setModalState(
                              () => r2IsMedicineIncludeProd = val,
                            ),
                            onToggleConvFcr: (val) =>
                                setModalState(() => r2UseConvertedFcr = val),
                            isEditable:
                                _isRule2Editing &&
                                (_appliedCompanyRuleId == null ||
                                    _appliedCompanyRuleId == 2),
                            showEditButton: _appliedCompanyRuleId == 2,
                            onToggleEdit: () {
                              setState(() {
                                _isRule2Editing = true;
                                _appliedCompanyRuleId = null;
                              });
                              setModalState(() {});
                            },
                          ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (_appliedCompanyRuleId == selectedRuleTab)
                        ? Colors.orange
                        : primaryGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    if (_appliedCompanyRuleId != null &&
                        _appliedCompanyRuleId != selectedRuleTab) {
                      Navigator.pop(context);
                      _showRuleConflictWarning(context, _appliedCompanyRuleId!);
                      return;
                    }

                    if (selectedRuleTab == 1) {
                      final rule1Config = {
                        'bigFeedRate':
                            double.tryParse(r1BigFeedRateCtrl.text.trim()) ??
                            42.0,
                        'bigChicksRate':
                            double.tryParse(r1BigChicksRateCtrl.text.trim()) ??
                            40.0,
                        'bigAdminCost':
                            double.tryParse(r1BigAdminCostCtrl.text.trim()) ??
                            1.50,
                        'bigKgPerBag':
                            double.tryParse(r1BigKgPerBagCtrl.text.trim()) ??
                            50.0,
                        'bigTargetCost':
                            double.tryParse(r1BigTargetCostCtrl.text.trim()) ??
                            85.0,
                        'bigBaseComm':
                            double.tryParse(r1BigBaseCommCtrl.text.trim()) ??
                            8.0,
                        'bigSavingsShare':
                            double.tryParse(
                              r1BigSavingsShareCtrl.text.trim(),
                            ) ??
                            50.0,
                        'bigExceededShare':
                            double.tryParse(
                              r1BigExceededShareCtrl.text.trim(),
                            ) ??
                            50.0,
                        'bigRateBonusThresh':
                            double.tryParse(
                              r1BigRateBonusThreshCtrl.text.trim(),
                            ) ??
                            110.0,
                        'bigRateBonusShare':
                            double.tryParse(
                              r1BigRateBonusShareCtrl.text.trim(),
                            ) ??
                            10.0,
                        'bigMedicineInProd': r1BigMedicineInProdCost,
                        'smFeedRate':
                            double.tryParse(r1SmFeedRateCtrl.text.trim()) ??
                            42.0,
                        'smChicksRate':
                            double.tryParse(r1SmChicksRateCtrl.text.trim()) ??
                            40.0,
                        'smAdminCost':
                            double.tryParse(r1SmAdminCostCtrl.text.trim()) ??
                            1.50,
                        'smKgPerBag':
                            double.tryParse(r1SmKgPerBagCtrl.text.trim()) ??
                            50.0,
                        'smTargetCost':
                            double.tryParse(r1SmTargetCostCtrl.text.trim()) ??
                            90.0,
                        'smBaseComm':
                            double.tryParse(r1SmBaseCommCtrl.text.trim()) ??
                            10.0,
                        'smSavingsShare':
                            double.tryParse(r1SmSavingsShareCtrl.text.trim()) ??
                            50.0,
                        'smExceededShare':
                            double.tryParse(
                              r1SmExceededShareCtrl.text.trim(),
                            ) ??
                            50.0,
                        'smRateBonusThresh':
                            double.tryParse(
                              r1SmRateBonusThreshCtrl.text.trim(),
                            ) ??
                            120.0,
                        'smRateBonusShare':
                            double.tryParse(
                              r1SmRateBonusShareCtrl.text.trim(),
                            ) ??
                            10.0,
                        'smMedicineInProd': r1SmMedicineInProdCost,
                      };

                      await CompanyStore.instance.setString(
                        'rule1SettlementConfig',
                        json.encode(rule1Config),
                      );
                      await CompanyStore.instance.setInt(
                        'appliedCompanyRuleId',
                        1,
                      );

                      setState(() {
                        _appliedCompanyRuleId = 1;
                        _isRule1Editing = false;
                      });
                      setModalState(() {});
                      if (!mounted) return;
                      Navigator.pop(context);
                      Get.snackbar(
                        'Rule 1 (Auto Size) Applied ✅',
                        '> 1.2 KG = Big Size rates, ≤ 1.2 KG = Small Size rates — automatic apply hoga.',
                        backgroundColor: primaryGreen,
                        colorText: Colors.white,
                        snackPosition: SnackPosition.BOTTOM,
                        margin: const EdgeInsets.all(15),
                      );
                    } else if (selectedRuleTab == 2) {
                      final rule2Config = {
                        'baseRate':
                            double.tryParse(r2BaseRateCtrl.text.trim()) ?? 7.50,
                        'goodMin':
                            double.tryParse(r2GoodMinCtrl.text.trim()) ?? 1.40,
                        'goodMax':
                            double.tryParse(r2GoodMaxCtrl.text.trim()) ?? 1.54,
                        'normMin':
                            double.tryParse(r2NormMinCtrl.text.trim()) ?? 1.55,
                        'normMax':
                            double.tryParse(r2NormMaxCtrl.text.trim()) ?? 1.65,
                        'bonus':
                            double.tryParse(r2BonusCtrl.text.trim()) ?? 0.10,
                        'penalty':
                            double.tryParse(r2PenaltyCtrl.text.trim()) ?? 0.15,
                        'isRupeeMode': r2IsRupeeIncentiveMode,
                        'isMedIncludeProd': r2IsMedicineIncludeProd,
                        'useConvFcr': r2UseConvertedFcr,
                      };

                      await CompanyStore.instance.setString(
                        'rule2SettlementConfig',
                        json.encode(rule2Config),
                      );
                      await CompanyStore.instance.setInt(
                        'appliedCompanyRuleId',
                        2,
                      );

                      setState(() {
                        _appliedCompanyRuleId = 2;
                        _isRule2Editing = false;
                      });
                      setModalState(() {});
                      if (!mounted) return;
                      Navigator.pop(context);
                      Get.snackbar(
                        'Rule 2 Globally Applied Locked ⚡',
                        'FCR range criteria successfully lock ho chuki hai.',
                        backgroundColor: primaryGreen,
                        colorText: Colors.white,
                        snackPosition: SnackPosition.BOTTOM,
                        margin: const EdgeInsets.all(15),
                      );
                    }
                  },
                  child: Text(
                    _appliedCompanyRuleId == selectedRuleTab
                        ? 'Rule Active & Saved'
                        : 'Process Selected Rule Engine',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRuleTabHeader(
    int id,
    String title,
    int currentSelected,
    ValueChanged<int>? onSelect, {
    bool isLocked = false,
  }) {
    bool isCurrent = currentSelected == id;
    return GestureDetector(
      onTap: isLocked ? null : () => onSelect?.call(id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isCurrent
              ? primaryGreen
              : (isLocked ? Colors.grey.shade100 : Colors.green.shade50),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isCurrent ? primaryGreen : Colors.black12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLocked)
              const Icon(Icons.lock_outline, size: 14, color: Colors.grey),
            if (isLocked) const SizedBox(width: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isCurrent
                    ? Colors.white
                    : (isLocked ? Colors.grey : primaryGreen),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRule1AutoSizeForm({
    required TextEditingController bigFeedRate,
    required TextEditingController bigChicksRate,
    required TextEditingController bigAdminCost,
    required TextEditingController bigKgPerBag,
    required TextEditingController bigTargetCost,
    required TextEditingController bigBaseComm,
    required TextEditingController bigSavingsShare,
    required TextEditingController bigExceededShare,
    required TextEditingController bigRateBonusThresh,
    required TextEditingController bigRateBonusShare,
    required bool bigMedicineInProdCost,
    required ValueChanged<bool> onBigMedicineToggle,
    required TextEditingController smFeedRate,
    required TextEditingController smChicksRate,
    required TextEditingController smAdminCost,
    required TextEditingController smKgPerBag,
    required TextEditingController smTargetCost,
    required TextEditingController smBaseComm,
    required TextEditingController smSavingsShare,
    required TextEditingController smExceededShare,
    required TextEditingController smRateBonusThresh,
    required TextEditingController smRateBonusShare,
    required bool smMedicineInProdCost,
    required ValueChanged<bool> onSmMedicineToggle,
    required bool isEditable,
    required bool showEditButton,
    required VoidCallback onToggleEdit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primaryGreen.withOpacity(0.4)),
          ),
          child: const Row(
            children: [
              Text('⚙️', style: TextStyle(fontSize: 20)),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Auto Size Detection Active',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: primaryGreen,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '🐔 Avg Weight > 1.2 KG → Big Size rates apply\n🐣 Avg Weight ≤ 1.2 KG → Small Size rates apply',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade300),
          ),
          child: const Row(
            children: [
              Text('🐔', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Big Size Poultry — Avg Weight > 1.2 KG',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          '1. Input Cost Configuration (Big Size)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: primaryGreen,
          ),
        ),
        const SizedBox(height: 10),
        _r1Field(bigFeedRate, 'Feed Rate (₹/KG) *', isEditable),
        const SizedBox(height: 10),
        _r1Field(bigChicksRate, 'Chicks Rate (₹/Piece) *', isEditable),
        const SizedBox(height: 10),
        _r1Field(bigAdminCost, 'Admin/Extra Charge (₹/KG) *', isEditable),
        const SizedBox(height: 10),
        _r1Field(bigKgPerBag, 'KG Per Feed Bag *', isEditable),
        const SizedBox(height: 16),
        _r1MedicineToggle(
          label: 'Medicine Cost (Big Size)',
          value: bigMedicineInProdCost,
          enabled: isEditable,
          onChanged: onBigMedicineToggle,
        ),
        const SizedBox(height: 20),
        const Text(
          '2. Production Target & Base Commission (Big Size)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: primaryGreen,
          ),
        ),
        const SizedBox(height: 10),
        _r1Field(
          bigTargetCost,
          'Target Production Cost (₹/KG) *',
          isEditable,
          helper: 'Is cost se neeche lana hai farmer ko',
        ),
        const SizedBox(height: 10),
        _r1Field(bigBaseComm, 'Base Farmer Commission (₹/KG) *', isEditable),
        const SizedBox(height: 20),
        const Text(
          '3. Cost Savings Bonus Rule (Big Size)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: primaryGreen,
          ),
        ),
        const SizedBox(height: 6),
        _r1InfoBox(
          Colors.green,
          'Jab actual production cost, target se NEECHE aaye:\nFarmer ko (saving ₹/KG) ka X% bonus milega commission mein JODKE.\ne.g. Target=₹85, Actual=₹83 → Saving=₹2/KG, 50% share → +₹1/KG bonus',
        ),
        const SizedBox(height: 10),
        _r1Field(
          bigSavingsShare,
          'Saving Share % (Farmer ko kitna %) *',
          isEditable,
          helper: 'e.g. 50 = saving ka 50% farmer ko milega',
        ),
        const SizedBox(height: 20),
        const Text(
          '4. Cost Exceeded Penalty Rule (Big Size)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: primaryGreen,
          ),
        ),
        const SizedBox(height: 6),
        _r1InfoBox(
          Colors.red,
          'Jab actual production cost, target se UPAR jaye:\nFarmer ke base commission mein se (exceeded ₹/KG) ka X% KATEGA.\ne.g. Target=₹85, Actual=₹87 → Extra=₹2/KG, 50% penalty → -₹1/KG deduction',
        ),
        const SizedBox(height: 10),
        _r1Field(
          bigExceededShare,
          'Exceeded Penalty % (Kitna % katega) *',
          isEditable,
          helper: 'e.g. 50 = exceeded amount ka 50% commission se katega',
        ),
        const SizedBox(height: 20),
        const Text(
          '5. Rate Bonus Rule (Big Size)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: primaryGreen,
          ),
        ),
        const SizedBox(height: 6),
        _r1InfoBox(
          Colors.blue,
          'Rate bonus milega SIRF TAB jab DONO conditions sath poori hon:\n✅ Actual production cost ≤ Target production cost\n✅ Avg sale rate ≥ Rate Bonus Threshold\n\nBonus = (Avg Sale Rate − Threshold) × X%\ne.g. Threshold=₹110, Avg Sale=₹115 → Excess=₹5, 10% → +₹0.50/KG bonus',
        ),
        const SizedBox(height: 10),
        _r1Field(
          bigRateBonusThresh,
          'Rate Bonus Threshold (₹/KG Sale Rate) *',
          isEditable,
          helper: 'Chicken is rate ya upar bikna chahiye tab bonus milega',
        ),
        const SizedBox(height: 10),
        _r1Field(
          bigRateBonusShare,
          'Rate Bonus Share (%) *',
          isEditable,
          helper:
              'e.g. 10 = threshold se jo kitna upar bika uska 10% bonus milega',
        ),
        const SizedBox(height: 30),
        const Divider(thickness: 2, color: Color(0xFFDDDDDD)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.purple.shade300),
          ),
          child: const Row(
            children: [
              Text('🐣', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Small Size Poultry — Avg Weight ≤ 1.2 KG',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          '1. Input Cost Configuration (Small Size)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: primaryGreen,
          ),
        ),
        const SizedBox(height: 10),
        _r1Field(smFeedRate, 'Feed Rate (₹/KG) *', isEditable),
        const SizedBox(height: 10),
        _r1Field(smChicksRate, 'Chicks Rate (₹/Piece) *', isEditable),
        const SizedBox(height: 10),
        _r1Field(smAdminCost, 'Admin/Extra Charge (₹/KG) *', isEditable),
        const SizedBox(height: 10),
        _r1Field(smKgPerBag, 'KG Per Feed Bag *', isEditable),
        const SizedBox(height: 16),
        _r1MedicineToggle(
          label: 'Medicine Cost (Small Size)',
          value: smMedicineInProdCost,
          enabled: isEditable,
          onChanged: onSmMedicineToggle,
        ),
        const SizedBox(height: 20),
        const Text(
          '2. Production Target & Base Commission (Small Size)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: primaryGreen,
          ),
        ),
        const SizedBox(height: 10),
        _r1Field(
          smTargetCost,
          'Target Production Cost (₹/KG) *',
          isEditable,
          helper: 'Is cost se neeche lana hai farmer ko',
        ),
        const SizedBox(height: 10),
        _r1Field(smBaseComm, 'Base Farmer Commission (₹/KG) *', isEditable),
        const SizedBox(height: 20),
        const Text(
          '3. Cost Savings Bonus Rule (Small Size)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: primaryGreen,
          ),
        ),
        const SizedBox(height: 6),
        _r1InfoBox(
          Colors.green,
          'Jab actual production cost, target se NEECHE aaye:\nFarmer ko (saving ₹/KG) ka X% bonus milega commission mein JODKE.\ne.g. Target=₹90, Actual=₹88 → Saving=₹2/KG, 50% share → +₹1/KG bonus',
        ),
        const SizedBox(height: 10),
        _r1Field(
          smSavingsShare,
          'Saving Share % (Farmer ko kitna %) *',
          isEditable,
          helper: 'e.g. 50 = saving ka 50% farmer ko milega',
        ),
        const SizedBox(height: 20),
        const Text(
          '4. Cost Exceeded Penalty Rule (Small Size)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: primaryGreen,
          ),
        ),
        const SizedBox(height: 6),
        _r1InfoBox(
          Colors.red,
          'Jab actual production cost, target se UPAR jaye:\nFarmer ke base commission mein se (exceeded ₹/KG) ka X% KATEGA.\ne.g. Target=₹90, Actual=₹92 → Extra=₹2/KG, 50% penalty → -₹1/KG deduction',
        ),
        const SizedBox(height: 10),
        _r1Field(
          smExceededShare,
          'Exceeded Penalty % (Kitna % katega) *',
          isEditable,
          helper: 'e.g. 50 = exceeded amount ka 50% commission se katega',
        ),
        const SizedBox(height: 20),
        const Text(
          '5. Rate Bonus Rule (Small Size)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: primaryGreen,
          ),
        ),
        const SizedBox(height: 6),
        _r1InfoBox(
          Colors.blue,
          'Rate bonus milega SIRF TAB jab DONO conditions sath poori hon:\n✅ Actual production cost ≤ Target production cost\n✅ Avg sale rate ≥ Rate Bonus Threshold\n\nBonus = (Avg Sale Rate − Threshold) × X%\ne.g. Threshold=₹120, Avg Sale=₹125 → Excess=₹5, 10% → +₹0.50/KG bonus',
        ),
        const SizedBox(height: 10),
        _r1Field(
          smRateBonusThresh,
          'Rate Bonus Threshold (₹/KG Sale Rate) *',
          isEditable,
          helper: 'Chicken is rate ya upar bikna chahiye tab bonus milega',
        ),
        const SizedBox(height: 10),
        _r1Field(
          smRateBonusShare,
          'Rate Bonus Share (%) *',
          isEditable,
          helper:
              'e.g. 10 = threshold se jo kitna upar bika uska 10% bonus milega',
        ),
        if (showEditButton) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.orange.shade900,
                backgroundColor: Colors.orange.shade100.withOpacity(0.5),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text(
                'Edit Rule 1 Parameters',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
              onPressed: onToggleEdit,
            ),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _r1Field(
    TextEditingController ctrl,
    String label,
    bool enabled, {
    String? helper,
  }) {
    return TextField(
      controller: ctrl,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _r1InfoBox(MaterialColor color, String text) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade200),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color.shade800, height: 1.5),
      ),
    );
  }

  Widget _r1MedicineToggle({
    required String label,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: value ? Colors.teal.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value ? Colors.teal.shade300 : Colors.grey.shade300,
        ),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        activeColor: Colors.teal,
        title: Text(
          '$label — Production Cost Mein Include Karo?',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          value
              ? '✅ ON: Medicine cost target production cost mein JODKE count hoga'
              : '❌ OFF: Medicine cost bina target production cost calculate hoga (sirf Feed + Chicks)',
          style: TextStyle(
            fontSize: 10,
            color: value ? Colors.teal.shade700 : Colors.grey.shade600,
            height: 1.4,
          ),
        ),
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }

  Widget _buildRule2FormFields({
    required TextEditingController baseRate,
    required TextEditingController goodMin,
    required TextEditingController goodMax,
    required TextEditingController normMin,
    required TextEditingController normMax,
    required TextEditingController bonus,
    required TextEditingController penalty,
    required bool isRupeeMode,
    required bool isMedInclude,
    required bool useConvFcr,
    required ValueChanged<bool> onToggleIncentive,
    required ValueChanged<bool> onToggleMed,
    required ValueChanged<bool> onToggleConvFcr,
    required bool isEditable,
    required bool showEditButton,
    required VoidCallback onToggleEdit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '1. Base Rate Setup',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: primaryGreen,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: baseRate,
          enabled: isEditable,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Standard Base Rearing Rate (₹/KG)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          '2. FCR Multi-Range Boxes Setting',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: primaryGreen,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: goodMin,
                enabled: isEditable,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Good FCR Min',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: goodMax,
                enabled: isEditable,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Good FCR Max',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: normMin,
                enabled: isEditable,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Normal FCR Min',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: normMax,
                enabled: isEditable,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Normal FCR Max',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          '3. Modifier Calculation Unit',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: primaryGreen,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const Center(child: Text('Absolute Rupee (₹)')),
                selected: isRupeeMode,
                onSelected: isEditable
                    ? (val) => onToggleIncentive(true)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ChoiceChip(
                label: const Center(child: Text('Percentage (%)')),
                selected: !isRupeeMode,
                onSelected: isEditable
                    ? (val) => onToggleIncentive(false)
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: bonus,
                enabled: isEditable,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Bonus Rate Per 0.01',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: penalty,
                enabled: isEditable,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Penalty Rate Per 0.01',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        if (showEditButton) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.orange.shade900,
                backgroundColor: Colors.orange.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text(
                'Edit Rule 2 Parameters',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
              onPressed: onToggleEdit,
            ),
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          '4. System Adjustments',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: primaryGreen,
          ),
        ),
        SwitchListTile(
          title: const Text(
            'Use Converted FCR Protocol',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          value: useConvFcr,
          contentPadding: EdgeInsets.zero,
          activeColor: primaryGreen,
          onChanged: isEditable ? onToggleConvFcr : null,
        ),
        SwitchListTile(
          title: const Text(
            'Include Medicine in Prod Cost',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          value: isMedInclude,
          contentPadding: EdgeInsets.zero,
          activeColor: primaryGreen,
          onChanged: isEditable ? onToggleMed : null,
        ),
      ],
    );
  }

  void _showSimpleVoucherModal(SimpleSettlementResult bill) {}
  void _showAdvancedVoucherModal(BatchSettlementResult bill) {}

  // ── PREMIUM BOTTOM SHEET ──────────────────────────────────────────────────
  void _showCreativeShortcutsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: primaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.flash_on_rounded,
                      color: primaryGreen,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quick Tools',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        'Shortcut actions for fast work',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Divider(height: 1, color: Color(0xFFF0F0F0)),
              const SizedBox(height: 20),
              _premiumSheetTile(
                icon: Icons.receipt_long_rounded,
                iconBg: const Color(0xFFE3F2FD),
                iconColor: Colors.blue.shade700,
                title: 'Batch Settlement',
                subtitle: 'Farmer ka final profit & recovery calculate karo',
                badgeText: 'Live Engine ⚡',
                badgeColor: const Color(0xFFE3F2FD),
                badgeTextColor: Colors.blue.shade800,
                onTap: () {
                  Navigator.pop(context);
                  _showLiveSettlementWizard();
                },
              ),
              const SizedBox(height: 12),
              _premiumSheetTile(
                icon: Icons.tune_rounded,
                iconBg: const Color(0xFFE8F5E9),
                iconColor: primaryGreen,
                title: 'App Settings',
                subtitle: 'Lifting ke liye min-max din ki range configure karo',
                badgeText: '$_minLiftingDays-$_maxLiftingDays Din',
                badgeColor: Colors.green.shade50,
                badgeTextColor: primaryGreen,
                onTap: () {
                  Navigator.pop(context);
                  _showLiftingSettingsDialog();
                },
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F8F8),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: Colors.grey,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Active Batches: $_activeBatchCount  |  Lifting Ready: ${_liftingFarmers.length}  |  Total Farmers: $_farmerCount',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _premiumSheetTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String badgeText,
    required Color badgeColor,
    required Color badgeTextColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF0F0F0), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: badgeTextColor,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey.shade400,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ── ANIMATED CHICK FAB ────────────────────────────────────────────────────
  Widget _buildChickFab() {
    return GestureDetector(
      onTap: _showCreativeShortcutsMenu,
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (_showDust)
              Positioned(
                bottom: 0,
                child: AnimatedBuilder(
                  animation: _dustController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _dustOpacityAnim.value,
                      child: Transform.scale(
                        scale: _dustScaleAnim.value,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(5, (i) {
                            double angle = (i - 2) * 28.0;
                            return Transform.rotate(
                              angle: angle * pi / 180,
                              child: Container(
                                width: 5,
                                height: 5,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    );
                  },
                ),
              ),
            AnimatedBuilder(
              animation: _chickBounceController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, _chickBounceAnim.value),
                  child: child,
                );
              },
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: primaryGreen.withOpacity(0.5),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                    BoxShadow(
                      color: Colors.white.withOpacity(0.12),
                      blurRadius: 4,
                      offset: const Offset(-2, -2),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text('🐥', style: TextStyle(fontSize: 28)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvoked: (didPop) {
        if (!didPop) setState(() => _currentIndex = 0);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: primaryGreen,
          elevation: 0,
          title: Row(
            children: [
              const Text('🐔', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              const Text(
                'Tracko',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(
                Icons.delete_forever_rounded,
                color: Colors.redAccent,
                size: 26,
              ),
              onPressed: _devMasterResetAllData,
            ),
            IconButton(
              icon: const Icon(Icons.search, color: Colors.white, size: 26),
              onPressed: () {},
            ),
            IconButton(
              icon: Stack(
                children: [
                  const Icon(
                    Icons.notifications_outlined,
                    color: Colors.white,
                    size: 26,
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(
                Icons.account_circle_outlined,
                color: Colors.white,
                size: 26,
              ),
              onPressed: () => Get.to(() => const ProfileScreen()),
            ),
          ],
        ),
        body: _currentIndex == 0
            ? _buildDashboard()
            : _currentIndex == 1
            ? FarmersScreen(onFarmerAdded: _loadKpiData)
            : _currentIndex == 2
            ? _buildStockScreen()
            : _currentIndex == 4
            ? _buildLiftingScreen()
            : _buildComingSoon(_getTabName(_currentIndex)),
        floatingActionButton: _currentIndex == 0 ? _buildChickFab() : null,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: primaryGreen,
          unselectedItemColor: Colors.grey,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Farmers'),
            BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2),
              label: 'Stock',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart),
              label: 'Reports',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.upgrade_rounded),
              label: 'Lifting',
            ),
          ],
        ),
      ),
    );
  }

  String _getTabName(int index) {
    switch (index) {
      case 1:
        return 'Farmers';
      case 2:
        return 'Stock';
      case 3:
        return 'Reports';
      default:
        return '';
    }
  }

  Widget _buildDashboard() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: primaryGreen,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Namaste, ${widget.ownerName}! 👋',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.companyName,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _kpiCard('🧑‍🌾', 'Farmers', '$_farmerCount', Colors.white),
                    const SizedBox(width: 12),
                    _kpiCard(
                      '🐔',
                      'Active Batches',
                      '$_activeBatchCount',
                      Colors.white,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _kpiCard('💰', 'Income', '₹0', Colors.white),
                    const SizedBox(width: 12),
                    _kpiCard(
                      '🚜',
                      'Lifting Ready',
                      '${_liftingFarmers.length}',
                      Colors.white,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _quickAction(
                      Icons.add_shopping_cart,
                      'Purchase\nExpense',
                      primaryGreen,
                      onTap: () {
                        Get.to(
                          () => PurchaseExpenseScreen(
                            onChicksTap: _showChicksPurchaseForm,
                            onFeedTap: _showFeedPurchaseForm,
                            onMedicineTap: _showMedicinePurchaseForm,
                            onLabourTap: _showLabourExpenseForm,
                            onOtherTap: _showOtherExpenseForm,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 10),
                    _quickAction(
                      Icons.point_of_sale,
                      '+ Sale',
                      Colors.orange,
                      onTap: () {
                        Get.to(
                          () => SalesScreen(
                            onChicksSaleTap: () async {},
                            onFeedSaleTap: () async {},
                            onMedicineSaleTap: () async {},
                            onChickenSaleTap: () async {},
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 10),
                    _quickAction(Icons.bar_chart, 'Reports', Colors.blue),
                    const SizedBox(width: 10),
                    _quickAction(
                      Icons.account_balance_wallet,
                      'Accounts',
                      Colors.purple,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Recent Activity',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (String criteria) {
                        setState(() => _selectedActivityFilter = criteria);
                        _loadKpiData();
                      },
                      icon: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: primaryGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: primaryGreen.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _selectedActivityFilter == 'Default'
                                  ? 'View All'
                                  : _selectedActivityFilter,
                              style: const TextStyle(
                                color: primaryGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_drop_down_rounded,
                              color: primaryGreen,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                      itemBuilder: (BuildContext context) =>
                          <PopupMenuEntry<String>>[
                            const PopupMenuItem<String>(
                              value: 'Default',
                              child: Text('Default (All Feeds)'),
                            ),
                            const PopupMenuItem<String>(
                              value: 'Field Manager',
                              child: Text('Field Manager Logs'),
                            ),
                            const PopupMenuItem<String>(
                              value: 'Office Manager',
                              child: Text('Office Manager Logs'),
                            ),
                          ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _recentActivitiesList.isEmpty
                    ? Container(
                        padding: const EdgeInsets.all(20),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'Is select kiye gaye filter ke liye abhi koi activity nahi hai.\nBatch entries karte hi yahan automatic dikhega!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      )
                    : Column(
                        children: _recentActivitiesList.map((act) {
                          return _activityItem(
                            act['emoji'] ?? '📝',
                            act['title'] ?? 'Activity Update',
                            act['subtitle'] ?? '',
                            act['timeString'] ?? 'Recent',
                          );
                        }).toList(),
                      ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildLiftingScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: primaryGreen,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '🚜 Lifting Ready',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.settings_suggest_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: _showLiftingSettingsDialog,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Range Set: $_minLiftingDays se $_maxLiftingDays Din | Total Ready: ${_liftingFarmers.length}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _liftingFarmers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('✅', style: TextStyle(fontSize: 60)),
                      const SizedBox(height: 16),
                      const Text(
                        'Abhi koi lifting pending nahi!',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Aapki set ki gayi range ($_minLiftingDays - $_maxLiftingDays din) ke andar\nkoi bhi farmer ka lot match nahi hua.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _liftingFarmers.length,
                  itemBuilder: (context, index) =>
                      _liftingFarmerCard(_liftingFarmers[index]),
                ),
        ),
      ],
    );
  }

  Widget _liftingFarmerCard(Map<String, dynamic> farmer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🧑‍🌾', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    farmer['name'],
                    style: const TextStyle(
                      fontSize: 16,
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
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Text(
                    '${farmer['days']} din',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _statChip('🐥', 'Chicks', '${farmer['chicks']}'),
                const SizedBox(width: 10),
                _statChip('⚖️', 'Avg Weight', '${farmer['avgWeight']} kg'),
                const SizedBox(width: 10),
                _statChip('📅', 'Din', '${farmer['days']}'),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Get.snackbar(
                    'Lifting Confirm',
                    '${farmer['name']} ka lifting process shuru ho gaya',
                    backgroundColor: primaryGreen,
                    colorText: Colors.white,
                    snackPosition: SnackPosition.BOTTOM,
                    margin: const EdgeInsets.all(15),
                  );
                },
                icon: const Icon(Icons.upgrade_rounded, size: 18),
                label: const Text(
                  'Lifting Confirm Karo',
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
          ],
        ),
      ),
    );
  }

  Widget _statChip(String emoji, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiCard(String emoji, String label, String value, Color textColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white30),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(color: textColor.withOpacity(0.8), fontSize: 11),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAction(
    IconData icon,
    String label,
    Color color, {
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap ?? () {},
        child: Container(
          height: 80,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activityItem(
    String emoji,
    String title,
    String subtitle,
    String time,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4),
        ],
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(time, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📦 STOCK SCREEN UI
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildStockScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: const BoxDecoration(
            color: primaryGreen,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Text('📦', style: TextStyle(fontSize: 22)),
                  SizedBox(width: 8),
                  Text(
                    'Stock Management',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _stockTabButton('🌾 Feed', 0)),
                  const SizedBox(width: 10),
                  Expanded(child: _stockTabButton('💊 Medicine', 1)),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _stockSubTab == 0
              ? _buildFeedStockTab()
              : _buildMedicineStockTab(),
        ),
      ],
    );
  }

  Widget _stockTabButton(String label, int tabIndex) {
    bool isSel = _stockSubTab == tabIndex;
    return GestureDetector(
      onTap: () => setState(() => _stockSubTab = tabIndex),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSel ? Colors.white : Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isSel ? primaryGreen : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildFeedStockTab() {
    final types = ['Starter', 'Grower', 'Finisher'];
    final emojis = {'Starter': '🐣', 'Grower': '🐥', 'Finisher': '🐔'};
    final Map<String, MaterialColor> colors = {
      'Starter': Colors.blue,
      'Grower': Colors.purple,
      'Finisher': Colors.deepOrange,
    };

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Feed Bags Inventory',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showAddFeedStockDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.add, size: 16, color: Colors.white),
                label: const Text(
                  'Add Stock',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: types.length,
              itemBuilder: (context, index) {
                String type = types[index];
                double qty = _feedStock[type] ?? 0.0;
                bool isWhole = qty == qty.roundToDouble();
                MaterialColor c = colors[type] ?? Colors.green;
                bool isOut = qty <= 0;
                bool isLow = qty > 0 && qty < 10;

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: c.shade100, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: c.withOpacity(0.10),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [c.shade300, c.shade700],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: c.withOpacity(0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  emojis[type] ?? '🌾',
                                  style: const TextStyle(fontSize: 26),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        type,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (isOut)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade50,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: const Text(
                                            'KHATAM',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: Colors.red,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )
                                      else if (isLow)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.shade50,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            'KAM STOCK',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: Colors.orange.shade800,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        qty.toStringAsFixed(isWhole ? 0 : 2),
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: c.shade700,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Bag Available',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                          fontWeight: FontWeight.w600,
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
                      Divider(height: 1, color: c.shade50),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: qty > 0
                                ? () => _showUseFeedStockDialog(type)
                                : null,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: c.shade800,
                              disabledForegroundColor: Colors.grey.shade400,
                              side: BorderSide(
                                color: qty > 0
                                    ? c.shade200
                                    : Colors.grey.shade200,
                                width: 1.4,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(
                              Icons.remove_circle_outline_rounded,
                              size: 18,
                            ),
                            label: const Text(
                              'Stock Use Karo',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicineStockTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Medicine Inventory',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showAddMedicineDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.add, size: 16, color: Colors.white),
                label: const Text(
                  'Add Medicine',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _medicineStock.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('💊', style: TextStyle(fontSize: 50)),
                        const SizedBox(height: 12),
                        Text(
                          'Abhi koi medicine stock nahi hai',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _medicineStock.length,
                    itemBuilder: (context, index) =>
                        _medicineStockCard(_medicineStock[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _medicineStockCard(Map<String, dynamic> medicine) {
    double totalQuantity = (medicine['totalQuantity'] as num).toDouble();
    double totalPrice = (medicine['totalPrice'] as num).toDouble();
    double remainingQuantity = (medicine['remainingQuantity'] as num)
        .toDouble();
    double actualPrice =
        (medicine['actualPrice'] as num? ?? medicine['totalPrice'] as num)
            .toDouble();
    double farmerPrice = (medicine['farmerPrice'] as num? ?? 0.0).toDouble();
    String unit = medicine['unit'];
    double pricePerUnit = totalQuantity > 0 ? totalPrice / totalQuantity : 0.0;
    double remainingValue = remainingQuantity * pricePerUnit;
    bool isOut = remainingQuantity <= 0.0001;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOut ? Colors.red.shade200 : Colors.teal.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💊', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medicine['name'],
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    if ((medicine['nickName'] ?? '').toString().isNotEmpty)
                      Text(
                        '🏷️ "${medicine['nickName']}"',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.teal.shade600,
                        ),
                      ),
                  ],
                ),
              ),
              if (isOut)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'KHATAM',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.grey,
                  size: 20,
                ),
                onPressed: () => _showDeleteMedicineConfirm(medicine),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _stockMiniStat(
                  'Bacha Hua',
                  '${remainingQuantity.toStringAsFixed(2)} $unit',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _stockMiniStat(
                  'Bachi Value',
                  '₹${remainingValue.toStringAsFixed(2)}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _stockMiniStat(
                  'Actual Rate',
                  '₹${(totalQuantity > 0 ? actualPrice / totalQuantity : 0).toStringAsFixed(2)}/$unit',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_rounded,
                        size: 14,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Farmer Rate: ₹${(totalQuantity > 0 ? farmerPrice / totalQuantity : 0).toStringAsFixed(2)}/$unit',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isOut ? null : () => _showUseMedicineDialog(medicine),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(
                Icons.medication_liquid_rounded,
                size: 16,
                color: Colors.white,
              ),
              label: const Text(
                'Medicine Nikaalo',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stockMiniStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildComingSoon(String name) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🚧', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 16),
          Text(
            name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('Jald aayega!', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
