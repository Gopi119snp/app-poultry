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

  FeedRuleType _ruleType = FeedRuleType.standardAgeChart;
  final TextEditingController _multiplierCtrl = TextEditingController(
    text: '4.5',
  );
  List<SeasonalMultiplier> _seasons = [];

  static const List<String> _monthNames = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

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
        });
      } catch (_) {
        // corrupt/missing data → defaults hi rahenge
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

    await CompanyStore.instance.setString(
      'feedConsumptionRuleConfig',
      jsonEncode(config.toJson()),
    );

    setState(() => _saving = false);
    if (!mounted) return;

    Get.snackbar(
      'Rule Saved ✅',
      'Feed consumption rule update ho gaya. Sabhi batches isi rule se calculate honge.',
      backgroundColor: primaryGreen,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(15),
    );
    Navigator.pop(context);
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
                              onPressed: () =>
                                  setState(() => _seasons.removeAt(i)),
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
      onTap: () => setState(() => _ruleType = type),
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
              onChanged: (v) => setState(() => _ruleType = v!),
            ),
          ],
        ),
      ),
    );
  }
}
