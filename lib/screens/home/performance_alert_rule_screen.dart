import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../services/company_store.dart';
import '../../utils/performance_alert_engine.dart';

// =============================================================================
// 🚦 PERFORMANCE ALERT RULE SCREEN — v2 (Flat / Daily / Weekly)
// -----------------------------------------------------------------------------
// Company yahan FCR aur Mortality% ke Red/Green/Yellow thresholds set karti
// hai. Ab 3 modes hain:
//   FLAT   — poore batch ke liye ek hi threshold
//   DAILY  — har specific din ka apna threshold (baaki din default se chalte hain)
//   WEEKLY — har hafte ka apna threshold (baaki hafte default se chalte hain)
// =============================================================================
class PerformanceAlertRuleScreen extends StatefulWidget {
  const PerformanceAlertRuleScreen({super.key});

  @override
  State<PerformanceAlertRuleScreen> createState() =>
      _PerformanceAlertRuleScreenState();
}

class _PerformanceAlertRuleScreenState
    extends State<PerformanceAlertRuleScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);

  bool _loading = true;
  bool _saving = false;
  bool _showSavedBanner = false;

  AlertGranularity _granularity = AlertGranularity.flat;

  final _fcrRedCtrl = TextEditingController(text: '1.8');
  final _fcrYellowCtrl = TextEditingController(text: '1.5');
  final _mortRedCtrl = TextEditingController(text: '5.0');
  final _mortYellowCtrl = TextEditingController(text: '2.0');

  List<ThresholdOverride> _overrides = [];

  @override
  void initState() {
    super.initState();
    _loadExistingConfig();
  }

  @override
  void dispose() {
    _fcrRedCtrl.dispose();
    _fcrYellowCtrl.dispose();
    _mortRedCtrl.dispose();
    _mortYellowCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExistingConfig() async {
    final raw = await CompanyStore.instance.getString('performanceAlertConfig');
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final config = PerformanceAlertConfig.fromJson(decoded);
        setState(() {
          _granularity = config.granularity;
          _fcrRedCtrl.text = config.fcrRedAboveThreshold.toString();
          _fcrYellowCtrl.text = config.fcrYellowBelowThreshold.toString();
          _mortRedCtrl.text = config.mortalityRedAboveThreshold.toString();
          _mortYellowCtrl.text = config.mortalityYellowBelowThreshold.toString();
          _overrides = config.overrides;
          _showSavedBanner = true;
        });
      } catch (_) {}
    }
    setState(() => _loading = false);
  }

  Future<void> _saveConfig() async {
    final fcrRed = double.tryParse(_fcrRedCtrl.text.trim());
    final fcrYellow = double.tryParse(_fcrYellowCtrl.text.trim());
    final mortRed = double.tryParse(_mortRedCtrl.text.trim());
    final mortYellow = double.tryParse(_mortYellowCtrl.text.trim());

    if (fcrRed == null || fcrYellow == null || mortRed == null || mortYellow == null) {
      Get.snackbar(
        'Invalid Input',
        'Sahi numbers daalein',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      return;
    }

    if (fcrYellow >= fcrRed) {
      Get.snackbar(
        'Invalid Range',
        'FCR Yellow threshold, Red threshold se KAM hona chahiye',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      return;
    }

    if (mortYellow >= mortRed) {
      Get.snackbar(
        'Invalid Range',
        'Mortality Yellow threshold, Red threshold se KAM hona chahiye',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      return;
    }

    if (_granularity != AlertGranularity.flat && _overrides.isEmpty) {
      Get.snackbar(
        'Koi Override Nahi Hai',
        _granularity == AlertGranularity.daily
            ? 'Kam se kam ek Din ka threshold add karein, ya Flat mode chunein'
            : 'Kam se kam ek Hafte ka threshold add karein, ya Flat mode chunein',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(15),
      );
      return;
    }

    setState(() => _saving = true);

    final config = PerformanceAlertConfig(
      granularity: _granularity,
      fcrRedAboveThreshold: fcrRed,
      fcrYellowBelowThreshold: fcrYellow,
      mortalityRedAboveThreshold: mortRed,
      mortalityYellowBelowThreshold: mortYellow,
      overrides: _overrides,
    );

    final encoded = jsonEncode(config.toJson());
    await CompanyStore.instance.setString('performanceAlertConfig', encoded);
    final verifyRaw = await CompanyStore.instance.getString('performanceAlertConfig');
    final bool ok = verifyRaw == encoded;

    if (!mounted) return;
    setState(() {
      _saving = false;
      _showSavedBanner = ok;
    });

    Get.snackbar(
      ok ? 'Rule Saved ✅' : 'Save Fail Hua ⚠️',
      ok
          ? 'Performance Alert Rule update ho gaya.'
          : 'Kuch gadbad hui, dobara try karein.',
      backgroundColor: ok ? primaryGreen : Colors.red,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(15),
      duration: const Duration(seconds: 3),
    );
  }

  void _showAddOverrideDialog() {
    final periodCtrl = TextEditingController();
    final fcrRedCtrl = TextEditingController();
    final fcrYellowCtrl = TextEditingController();
    final mortRedCtrl = TextEditingController();
    final mortYellowCtrl = TextEditingController();
    final bool isDaily = _granularity == AlertGranularity.daily;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isDaily ? 'Din ka Threshold Add Karo' : 'Hafte ka Threshold Add Karo',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: periodCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: isDaily ? 'Din Number (e.g. 7)' : 'Hafta Number (e.g. 2)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: fcrRedCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '🔴 FCR Red — ispar/upar',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: fcrYellowCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '🟡 FCR Yellow — iske neeche',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: mortRedCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '🔴 Mortality% Red — ispar/upar',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: mortYellowCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '🟡 Mortality% Yellow — iske neeche',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
              final period = int.tryParse(periodCtrl.text.trim());
              final fr = double.tryParse(fcrRedCtrl.text.trim());
              final fy = double.tryParse(fcrYellowCtrl.text.trim());
              final mr = double.tryParse(mortRedCtrl.text.trim());
              final my = double.tryParse(mortYellowCtrl.text.trim());

              if (period == null || period <= 0 || fr == null || fy == null ||
                  mr == null || my == null) {
                Get.snackbar(
                  'Invalid Input',
                  'Sahi values daalein',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                  snackPosition: SnackPosition.BOTTOM,
                  margin: const EdgeInsets.all(15),
                );
                return;
              }
              if (fy >= fr || my >= mr) {
                Get.snackbar(
                  'Invalid Range',
                  'Yellow threshold, Red se KAM hona chahiye',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                  snackPosition: SnackPosition.BOTTOM,
                  margin: const EdgeInsets.all(15),
                );
                return;
              }

              setState(() {
                _overrides.removeWhere((o) => o.periodKey == period);
                _overrides.add(ThresholdOverride(
                  periodKey: period,
                  fcrRedAboveThreshold: fr,
                  fcrYellowBelowThreshold: fy,
                  mortalityRedAboveThreshold: mr,
                  mortalityYellowBelowThreshold: my,
                ));
                _overrides.sort((a, b) => a.periodKey.compareTo(b.periodKey));
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

  Widget _thresholdField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() => _showSavedBanner = false),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _granularityCard({
    required AlertGranularity value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final bool selected = _granularity == value;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() {
        _granularity = value;
        _showSavedBanner = false;
      }),
      child: Container(
        padding: const EdgeInsets.all(14),
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
            Icon(icon, color: selected ? primaryGreen : Colors.grey, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: selected ? primaryGreen : Colors.black87)),
                  Text(subtitle, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
                ],
              ),
            ),
            Radio<AlertGranularity>(
              value: value,
              groupValue: _granularity,
              activeColor: primaryGreen,
              onChanged: (v) => setState(() {
                _granularity = v!;
                _showSavedBanner = false;
              }),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isFlat = _granularity == AlertGranularity.flat;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Performance Alert Rule',
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
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: primaryGreen, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Yeh rule SAVE ho chuka hai — Batch Detail aur Daily '
                            'Update List dono jagah isi se badge dikhega.',
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
                            'Abhi kuch bhi SAVE nahi hua hai — default values use ho rahe hain.',
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

                // ── Granularity Selection ────────────────────────────────
                const Text(
                  'Threshold Kis Tarah Set Karna Hai?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                const Text(
                  'FCR/Mortality naturally batch ke saath badhte hain — isliye '
                  'chahe toh Din-wise ya Hafta-wise alag threshold set kar sakte ho.',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                _granularityCard(
                  value: AlertGranularity.flat,
                  title: 'Flat — Poore Batch ke liye Ek Hi',
                  subtitle: 'Simple, ek threshold hamesha use hoga',
                  icon: Icons.horizontal_rule_rounded,
                ),
                const SizedBox(height: 10),
                _granularityCard(
                  value: AlertGranularity.daily,
                  title: 'Daily-Wise',
                  subtitle: 'Har specific din ka apna threshold',
                  icon: Icons.calendar_view_day_rounded,
                ),
                const SizedBox(height: 10),
                _granularityCard(
                  value: AlertGranularity.weekly,
                  title: 'Weekly-Wise',
                  subtitle: 'Har hafte (7 din) ka apna threshold',
                  icon: Icons.view_week_rounded,
                ),

                const SizedBox(height: 20),

                // ── FCR Section (Default/Flat values) ────────────────────
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
                      Text(
                        isFlat ? '🎯 FCR Thresholds' : '🎯 FCR Thresholds (Default/Fallback)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isFlat
                            ? 'Kam FCR accha hota hai (kam feed mein zyada weight)'
                            : 'Jis din/hafte ka specific override na ho, wahan yeh values use hongi',
                        style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      _thresholdField(
                        controller: _fcrRedCtrl,
                        label: '🔴 Red — ispar/upar (kharab)',
                        hint: 'e.g. 1.8',
                      ),
                      const SizedBox(height: 12),
                      _thresholdField(
                        controller: _fcrYellowCtrl,
                        label: '🟡 Yellow — iske neeche (normal se badiya)',
                        hint: 'e.g. 1.5',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '🟢 Green (normal) = in dono ke beech mein',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Mortality Section (Default/Flat values) ──────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isFlat
                            ? '💀 Mortality % Thresholds'
                            : '💀 Mortality % Thresholds (Default/Fallback)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Kam Mortality% accha hota hai',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      _thresholdField(
                        controller: _mortRedCtrl,
                        label: '🔴 Red — ispar/upar % (kharab)',
                        hint: 'e.g. 5.0',
                      ),
                      const SizedBox(height: 12),
                      _thresholdField(
                        controller: _mortYellowCtrl,
                        label: '🟡 Yellow — iske neeche % (normal se badiya)',
                        hint: 'e.g. 2.0',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '🟢 Green (normal) = in dono % ke beech mein',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),

                // ── Overrides List (Daily/Weekly mode only) ──────────────
                if (!isFlat) ...[
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _granularity == AlertGranularity.daily
                            ? 'Din-Wise Overrides'
                            : 'Hafta-Wise Overrides',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      TextButton.icon(
                        onPressed: _showAddOverrideDialog,
                        icon: const Icon(Icons.add_circle_rounded, size: 18),
                        label: Text(
                          _granularity == AlertGranularity.daily
                              ? 'Din Add Karo'
                              : 'Hafta Add Karo',
                        ),
                        style: TextButton.styleFrom(foregroundColor: primaryGreen),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_overrides.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _granularity == AlertGranularity.daily
                            ? 'Koi din add nahi hua — sabhi din Default values se chalenge.'
                            : 'Koi hafta add nahi hua — sabhi hafte Default values se chalenge.',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  else
                    ..._overrides.map((o) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade100),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _granularity == AlertGranularity.daily
                                      ? 'Din ${o.periodKey}'
                                      : 'Week ${o.periodKey}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'FCR: 🔴>${o.fcrRedAboveThreshold} 🟡<${o.fcrYellowBelowThreshold}  •  '
                                  'Mort: 🔴>${o.mortalityRedAboveThreshold}% 🟡<${o.mortalityYellowBelowThreshold}%',
                                  style: const TextStyle(fontSize: 10.5, color: Colors.black87),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: Colors.redAccent, size: 20),
                                onPressed: () => setState(() {
                                  _overrides.remove(o);
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
}
