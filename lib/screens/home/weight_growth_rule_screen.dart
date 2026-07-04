import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../services/company_store.dart';
import '../../utils/weight_growth_rule_engine.dart';

// =============================================================================
// ⚖️ WEIGHT GROWTH RULE SCREEN
// -----------------------------------------------------------------------------
// Company yahan decide karti hai "Automatic Body Weight" kaise calculate ho:
//   1) Standard (App Default) — piecewise growth formula (jo Target Weight
//      mein bhi use hoti hai)
//   2) Custom Chart — company apna Day → Gram table de sakti hai
// =============================================================================
class WeightGrowthRuleScreen extends StatefulWidget {
  const WeightGrowthRuleScreen({super.key});

  @override
  State<WeightGrowthRuleScreen> createState() =>
      _WeightGrowthRuleScreenState();
}

class _WeightGrowthRuleScreenState extends State<WeightGrowthRuleScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);

  bool _loading = true;
  bool _saving = false;
  bool _showSavedBanner = false;

  WeightRuleType _ruleType = WeightRuleType.standardFormula;
  final Map<int, double> _customChart = {};

  @override
  void initState() {
    super.initState();
    _loadExistingConfig();
  }

  Future<void> _loadExistingConfig() async {
    final raw = await CompanyStore.instance.getString('weightGrowthRuleConfig');
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final config = WeightGrowthRuleConfig.fromJson(decoded);
        setState(() {
          _ruleType = config.ruleType;
          _customChart
            ..clear()
            ..addAll(config.customBodyWeightGramPerDay ?? {});
          // Storage mein pehle se valid rule mila — matlab yeh CURRENTLY
          // active/saved rule hai. Isliye banner turant dikhao, chahe abhi
          // Save button dabaya ho ya screen dobara khol ke aaye ho.
          _showSavedBanner = true;
        });
      } catch (_) {
        // corrupt data mile toh default hi rahega, banner nahi dikhega
      }
    }
    setState(() => _loading = false);
  }

  Future<void> _saveConfig() async {
    if (_ruleType == WeightRuleType.customChart && _customChart.isEmpty) {
      Get.snackbar(
        'Chart Khaali Hai',
        'Custom mode chuna hai toh kam se kam ek din ka weight add karein',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      return;
    }

    setState(() => _saving = true);

    final config = WeightGrowthRuleConfig(
      ruleType: _ruleType,
      customBodyWeightGramPerDay:
          _customChart.isEmpty ? null : Map<int, double>.from(_customChart),
    );

    final encoded = jsonEncode(config.toJson());
    await CompanyStore.instance.setString('weightGrowthRuleConfig', encoded);
    final verifyRaw = await CompanyStore.instance.getString(
      'weightGrowthRuleConfig',
    );
    final bool ok = verifyRaw == encoded;

    if (!mounted) return;
    setState(() {
      _saving = false;
      _showSavedBanner = ok;
    });

    Get.snackbar(
      ok ? 'Rule Saved ✅' : 'Save Fail Hua ⚠️',
      ok
          ? 'Weight Growth Rule update ho gaya.'
          : 'Kuch gadbad hui, dobara try karein.',
      backgroundColor: ok ? primaryGreen : Colors.red,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(15),
      duration: const Duration(seconds: 3),
    );
  }

  void _showAddDayDialog() {
    final dayCtrl = TextEditingController();
    final weightCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Din ka Weight Add Karo',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: dayCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Din Number (e.g. 7)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: weightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Body Weight (gram, e.g. 182)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
            onPressed: () {
              final day = int.tryParse(dayCtrl.text.trim());
              final wt = double.tryParse(weightCtrl.text.trim());
              if (day == null || day <= 0 || wt == null || wt <= 0) {
                Get.snackbar(
                  'Invalid Input',
                  'Sahi Din number aur weight daalein',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                  snackPosition: SnackPosition.BOTTOM,
                  margin: const EdgeInsets.all(15),
                );
                return;
              }
              setState(() {
                _customChart[day] = wt;
                _showSavedBanner = false;
              });
              Navigator.pop(context);
            },
            child: const Text('Add Karo',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedDays = _customChart.keys.toList()..sort();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Weight Growth Rule',
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: primaryGreen.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: primaryGreen, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _ruleType == WeightRuleType.standardFormula
                                ? 'Abhi ACTIVE hai: Standard (App Default) — yeh rule save ho '
                                  'chuka hai aur "Automatic Body Weight" isi se calculate ho raha hai.'
                                : 'Abhi ACTIVE hai: Custom Chart (${_customChart.length} din diye '
                                  'gaye) — yeh rule save ho chuka hai.',
                            style: const TextStyle(
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: Colors.orange, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Abhi kuch bhi SAVE nahi hua hai — neeche se rule chunke '
                            '"Rule Save Karo" dabao.',
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
                  'Yeh "Automatic Body Weight" aur usse judi Automatic FCR '
                  'calculation ke liye use hoga — Daily Update List mein.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey),
                ),
                const SizedBox(height: 18),
                _ruleTypeCard(
                  type: WeightRuleType.standardFormula,
                  title: 'Standard (App Default)',
                  subtitle: 'Wahi growth formula jo abhi "Target Weight" mein use hoti hai',
                  icon: Icons.auto_graph_rounded,
                ),
                const SizedBox(height: 12),
                _ruleTypeCard(
                  type: WeightRuleType.customChart,
                  title: 'Custom Chart',
                  subtitle: 'Apna khud ka Day → Gram table dijiye (register jaisa)',
                  icon: Icons.edit_note_rounded,
                ),
                if (_ruleType == WeightRuleType.customChart) ...[
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Custom Weight Chart',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      TextButton.icon(
                        onPressed: _showAddDayDialog,
                        icon: const Icon(Icons.add_circle_rounded, size: 18),
                        label: const Text('Din Add Karo'),
                        style: TextButton.styleFrom(foregroundColor: primaryGreen),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (sortedDays.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Koi din add nahi hua — kam se kam kuch din ka weight '
                        'daalein (jitne zyada din, utna accurate curve banega).',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  else
                    ...sortedDays.map((d) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade100),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('Din $d',
                                    style: const TextStyle(
                                        fontSize: 11.5, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text('${_customChart[d]} gram',
                                      style: const TextStyle(fontSize: 13))),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: Colors.redAccent, size: 20),
                                onPressed: () => setState(() {
                                  _customChart.remove(d);
                                  _showSavedBanner = false;
                                }),
                              ),
                            ],
                          ),
                        )),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _saveConfig,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_rounded, color: Colors.white),
                    label: Text(
                      _saving ? 'Saving...' : 'Rule Save Karo',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _ruleTypeCard({
    required WeightRuleType type,
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
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: selected ? primaryGreen : Colors.black87)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                ],
              ),
            ),
            Radio<WeightRuleType>(
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
