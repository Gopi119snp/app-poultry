import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../services/company_store.dart';
import '../../utils/performance_alert_engine.dart';

// =============================================================================
// 🚦 PERFORMANCE ALERT RULE SCREEN
// -----------------------------------------------------------------------------
// Company yahan FCR aur Mortality% ke Red/Green/Yellow thresholds set karti
// hai. Yeh Batch Detail Screen (green card) aur Daily Update List dono jagah
// use hota hai.
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

  final _fcrRedCtrl = TextEditingController(text: '1.8');
  final _fcrYellowCtrl = TextEditingController(text: '1.5');
  final _mortRedCtrl = TextEditingController(text: '5.0');
  final _mortYellowCtrl = TextEditingController(text: '2.0');

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
          _fcrRedCtrl.text = config.fcrRedAboveThreshold.toString();
          _fcrYellowCtrl.text = config.fcrYellowBelowThreshold.toString();
          _mortRedCtrl.text = config.mortalityRedAboveThreshold.toString();
          _mortYellowCtrl.text = config.mortalityYellowBelowThreshold.toString();
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

    setState(() => _saving = true);

    final config = PerformanceAlertConfig(
      fcrRedAboveThreshold: fcrRed,
      fcrYellowBelowThreshold: fcrYellow,
      mortalityRedAboveThreshold: mortRed,
      mortalityYellowBelowThreshold: mortYellow,
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

  @override
  Widget build(BuildContext context) {
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
                            'Abhi kuch bhi SAVE nahi hua hai — default values '
                            '(FCR 1.5-1.8, Mortality 2%-5%) use ho rahe hain.',
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

                // ── FCR Section ──────────────────────────────────────────
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
                        '🎯 FCR Thresholds',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Kam FCR accha hota hai (kam feed mein zyada weight)',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey),
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

                // ── Mortality Section ────────────────────────────────────
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
                      const Text(
                        '💀 Mortality % Thresholds',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
