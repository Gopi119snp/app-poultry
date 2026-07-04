import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../services/company_store.dart';
import '../../utils/feed_consumption_rule_engine.dart';

// =============================================================================
// 🌾 FEED CONSUMPTION RULE SCREEN
// -----------------------------------------------------------------------------
// Company yahan decide karti hai daily feed consumption kaise calculate hoga:
//   1) Linear Multiplier  → Live Chicks × Multiplier × Day ÷ 1000
//      (season ke hisaab se multiplier alag-alag set kar sakte hain)
//   2) Standard Age Chart → purana fixed gram/day lookup table
//
// Save karte hi yeh config CompanyStore mein 'feedConsumptionRuleConfig' key
// ke naam se (JSON string) save hota hai — local + cloud (Firestore) dono
// jagah sync hota hai. batch_detail_screen.dart isi config ko load karke
// Expected Consumed / Expected Balance calculate karta hai.
// =============================================================================
class FeedConsumptionRuleScreen extends StatefulWidget {
  const FeedConsumptionRuleScreen({super.key});

  @override
  State<FeedConsumptionRuleScreen> createState() =>
      _FeedConsumptionRuleScreenState();
}

class _FeedConsumptionRuleScreenState
    extends State<FeedConsumptionRuleScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);

  bool _loading = true;
  bool _saving = false;
  bool _showSavedBanner = false;

  FeedRuleType _ruleType = FeedRuleType.standardAgeChart;
  final TextEditingController _multiplierCtrl = TextEditingController(
    text: '4.5',
  );
  List<SeasonalMultiplier> _seasons = [];

  static const List<String> _monthNames = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Konse mahine kisi bhi season se cover nahi hain — inhi mahino mein
  /// Default Multiplier use hoga. Agar list empty hai, matlab saare 12
  /// mahine kisi season se cover ho chuke hain aur default kabhi use
  /// nahi hoga.
  List<String> _uncoveredMonthNames() {
    final covered = <int>{};
    for (final s in _seasons) {
      for (int m = 1; m <= 12; m++) {
        if (s.matchesMonth(m)) covered.add(m);
      }
    }
    final uncovered = <String>[];
    for (int m = 1; m <= 12; m++) {
      if (!covered.contains(m)) uncovered.add(_monthNames[m]);
    }
    return uncovered;
  }

  @override
  void initState() {
    super.initState();
    _loadExistingConfig();
  }

  @override
  void dispose() {
    _multiplierCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExistingConfig() async {
    final raw = await CompanyStore.instance.getString(
      'feedConsumptionRuleConfig',
    );
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final config = FeedConsumptionRuleConfig.fromJson(decoded);
        setState(() {
          _ruleType = config.ruleType;
          _multiplierCtrl.text = config.defaultMultiplier.toString();
          _seasons = config.seasonalOverrides;
          // Storage mein pehle se valid rule mila — matlab yeh CURRENTLY
          // active/saved rule hai. Banner turant dikhao, screen chahe abhi
          // khuli ho ya pehle kabhi save kiya ho.
          _showSavedBanner = true;
        });
      } catch (_) {
        // corrupt/missing data → defaults hi rahenge, banner nahi dikhega
      }
    }
    setState(() => _loading = false);
  }

  Future<void> _saveConfig() async {
    double? multiplier = double.tryParse(_multiplierCtrl.text.trim());
    if (_ruleType == FeedRuleType.linearMultiplier &&
        (multiplier == null || multiplier <= 0)) {
      Get.snackbar(
        'Invalid Multiplier',
        'Sahi multiplier value daalein (e.g. 4.5)',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      return;
    }

    setState(() => _saving = true);

    final config = FeedConsumptionRuleConfig(
      ruleType: _ruleType,
      defaultMultiplier: multiplier ?? 4.5,
      seasonalOverrides: _seasons,
    );

    final encoded = jsonEncode(config.toJson());
    await CompanyStore.instance.setString('feedConsumptionRuleConfig', encoded);

    // ── Round-trip verify: turant wapas padh ke confirm karo ki
    // Firestore/local dono mein sahi save hua ─────────────────────────────
    final verifyRaw = await CompanyStore.instance.getString(
      'feedConsumptionRuleConfig',
    );
    final bool actuallySaved = verifyRaw == encoded;

    if (!mounted) return;
    setState(() {
      _saving = false;
      _showSavedBanner = actuallySaved;
    });

    if (actuallySaved) {
      Get.snackbar(
        'Rule Saved ✅',
        'Feed consumption rule update ho gaya. Sabhi batches isi rule se calculate honge.',
        backgroundColor: primaryGreen,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
        duration: const Duration(seconds: 3),
      );
      // Yahan se ab NAHI pop kar rahe — taaki "Saved" wala green banner
      // screen pe dikhta rahe aur confirm ho ki save hua hai. User khud
      // back arrow se bahar jaayega jab confirm ho jaaye.
    } else {
      Get.snackbar(
        'Save Fail Hua ⚠️',
        'Kuch gadbad hui, dobara try karein.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
    }
  }

  void _showAddSeasonDialog() {
    final nameCtrl = TextEditingController();
    final multCtrl = TextEditingController();
    int startMonth = 1;
    int endMonth = 3;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Season Add Karo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Season ka naam (e.g. Garmi)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: startMonth,
                        decoration: InputDecoration(
                          labelText: 'Start Month',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        items: List.generate(
                          12,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text(_monthNames[i + 1]),
                          ),
                        ),
                        onChanged: (v) =>
                            setModalState(() => startMonth = v ?? 1),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: endMonth,
                        decoration: InputDecoration(
                          labelText: 'End Month',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        items: List.generate(
                          12,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text(_monthNames[i + 1]),
                          ),
                        ),
                        onChanged: (v) =>
                            setModalState(() => endMonth = v ?? 3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: multCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Multiplier is season ke liye (e.g. 5.0)',
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
              style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
              onPressed: () {
                final name = nameCtrl.text.trim();
                final mult = double.tryParse(multCtrl.text.trim());
                if (name.isEmpty || mult == null || mult <= 0) {
                  Get.snackbar(
                    'Invalid Input',
                    'Season naam aur sahi multiplier value daalein',
                    backgroundColor: Colors.red,
                    colorText: Colors.white,
                    snackPosition: SnackPosition.BOTTOM,
                    margin: const EdgeInsets.all(15),
                  );
                  return;
                }
                setState(() {
                  _seasons.add(
                    SeasonalMultiplier(
                      seasonName: name,
                      startMonth: startMonth,
                      endMonth: endMonth,
                      multiplier: mult,
                    ),
                  );
                  _showSavedBanner = false;
                });
                Navigator.pop(context);
              },
              child: const Text(
                'Add Karo',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Feed Consumption Rule',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: primaryGreen))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_showSavedBanner) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: primaryGreen.withOpacity(0.4)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: primaryGreen, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Yeh rule cloud par SAVE ho chuka hai — sabhi '
                            'batches abhi isi ke hisaab se calculate ho rahe hain.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: primaryGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ] else if (!_loading) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            color: Colors.orange, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Abhi kuch bhi SAVE nahi hua hai — neeche se rule '
                            'set karke "Rule Save Karo" dabao.',
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
                ],
                const Text(
                  'Yeh rule aapki company ke SABHI batches ke "Expected '
                  'Consumed" aur "Expected Balance" calculation mein use hoga.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey),
                ),
                const SizedBox(height: 18),

                // ── Rule Type Selection ──────────────────────────────────
                _ruleTypeCard(
                  type: FeedRuleType.standardAgeChart,
                  title: 'Standard Age Chart',
                  subtitle:
                      'Fixed gram/day table (13, 16, 19...226g) — App ka default tareeka',
                  icon: Icons.table_chart_rounded,
                ),
                const SizedBox(height: 12),
                _ruleTypeCard(
                  type: FeedRuleType.linearMultiplier,
                  title: 'Linear Multiplier',
                  subtitle:
                      'Live Chicks × Multiplier × Day ÷ 1000 — season ke hisaab se adjust ho sakta hai',
                  icon: Icons.calculate_rounded,
                ),

                if (_ruleType == FeedRuleType.linearMultiplier) ...[
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.green.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Default Multiplier',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Jab koi season match na ho tab yeh value use hogi',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _multiplierCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) =>
                              setState(() => _showSavedBanner = false),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.tune_rounded, size: 20),
                            labelText: 'Multiplier (e.g. 4.5)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Seasonal Overrides',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      TextButton.icon(
                        onPressed: _showAddSeasonDialog,
                        icon: const Icon(Icons.add_circle_rounded, size: 18),
                        label: const Text('Season Add Karo'),
                        style: TextButton.styleFrom(foregroundColor: primaryGreen),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_seasons.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Koi season override nahi hai — sabhi mahino mein default '
                        'multiplier use hoga.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  else
                    ..._seasons.asMap().entries.map((entry) {
                      final i = entry.key;
                      final s = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade100),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.wb_sunny_rounded,
                                color: Colors.orange, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.seasonName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    '${_monthNames[s.startMonth]} - ${_monthNames[s.endMonth]}  •  Multiplier: ${s.multiplier}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: Colors.redAccent, size: 20),
                              onPressed: () => setState(() {
                                _seasons.removeAt(i);
                                _showSavedBanner = false;
                              }),
                            ),
                          ],
                        ),
                      );
                    }),

                  const SizedBox(height: 12),
                  Builder(builder: (context) {
                    final uncovered = _uncoveredMonthNames();
                    final bool allCovered = uncovered.isEmpty;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: allCovered
                            ? Colors.blue.shade50
                            : Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: allCovered
                              ? Colors.blue.shade100
                              : Colors.amber.shade200,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            allCovered
                                ? Icons.info_rounded
                                : Icons.warning_amber_rounded,
                            size: 18,
                            color: allCovered
                                ? Colors.blue.shade700
                                : Colors.amber.shade800,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              allCovered
                                  ? 'Saare 12 mahine seasons se covered hain — '
                                    'isliye Default Multiplier (${_multiplierCtrl.text}) '
                                    'kabhi use nahi hoga.'
                                  : 'Default Multiplier (${_multiplierCtrl.text}) '
                                    'in mahino mein use hoga: ${uncovered.join(", ")}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: allCovered
                                    ? Colors.blue.shade900
                                    : Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],

                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _saveConfig,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded, color: Colors.white),
                    label: Text(
                      _saving ? 'Saving...' : 'Rule Save Karo',
                      style: const TextStyle(
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

  Widget _ruleTypeCard({
    required FeedRuleType type,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final bool selected = _ruleType == type;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() {
        _ruleType = type;
        _showSavedBanner = false;
      }),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8F5E9) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? primaryGreen : Colors.grey.shade200,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? primaryGreen : Colors.grey, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: selected ? primaryGreen : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Radio<FeedRuleType>(
              value: type,
              groupValue: _ruleType,
              activeColor: primaryGreen,
              onChanged: (v) => setState(() {
                _ruleType = v!;
                _showSavedBanner = false;
              }),
            ),
          ],
        ),
      ),
    );
  }
}
