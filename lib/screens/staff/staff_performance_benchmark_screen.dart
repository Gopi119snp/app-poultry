import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../services/company_store.dart';
import '../../services/session_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 📏 STAFF PERFORMANCE BENCHMARK MODEL
// Owner in numbers ke through decide karta hai ki kisi farmer ka performance
// "Achha", "Average" ya "Kharab" hai — Staff Performance report isi ko
// use karke har farmer ko classify karega.
//
// Rule:
//   FCR            → jitna KAM utna Achha (good = <= goodMax, poor = > poorMin)
//   Mortality %    → jitna KAM utna Achha (good = <= goodMax, poor = > poorMin)
//   Weight Growth% → jitna ZYADA utna Achha (good = >= goodMin, poor = < poorMax)
// ═══════════════════════════════════════════════════════════════════════════
enum PerformanceRating { good, average, poor }

class StaffPerformanceBenchmark {
  final double fcrGoodMax; // isse kam/barabar = Achha
  final double fcrPoorMin; // isse zyada = Kharab
  final double mortalityGoodMax; // isse kam/barabar = Achha (%)
  final double mortalityPoorMin; // isse zyada = Kharab (%)
  final double weightGrowthGoodMin; // isse zyada/barabar = Achha (%)
  final double weightGrowthPoorMax; // isse kam = Kharab (%)

  const StaffPerformanceBenchmark({
    this.fcrGoodMax = 1.6,
    this.fcrPoorMin = 1.8,
    this.mortalityGoodMax = 4.0,
    this.mortalityPoorMin = 6.0,
    this.weightGrowthGoodMin = 95.0,
    this.weightGrowthPoorMax = 85.0,
  });

  factory StaffPerformanceBenchmark.fromJson(Map<String, dynamic> j) {
    return StaffPerformanceBenchmark(
      fcrGoodMax: (j['fcrGoodMax'] ?? 1.6).toDouble(),
      fcrPoorMin: (j['fcrPoorMin'] ?? 1.8).toDouble(),
      mortalityGoodMax: (j['mortalityGoodMax'] ?? 4.0).toDouble(),
      mortalityPoorMin: (j['mortalityPoorMin'] ?? 6.0).toDouble(),
      weightGrowthGoodMin: (j['weightGrowthGoodMin'] ?? 95.0).toDouble(),
      weightGrowthPoorMax: (j['weightGrowthPoorMax'] ?? 85.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'fcrGoodMax': fcrGoodMax,
    'fcrPoorMin': fcrPoorMin,
    'mortalityGoodMax': mortalityGoodMax,
    'mortalityPoorMin': mortalityPoorMin,
    'weightGrowthGoodMin': weightGrowthGoodMin,
    'weightGrowthPoorMax': weightGrowthPoorMax,
  };

  PerformanceRating rateFcr(double v) {
    if (v <= fcrGoodMax) return PerformanceRating.good;
    if (v > fcrPoorMin) return PerformanceRating.poor;
    return PerformanceRating.average;
  }

  PerformanceRating rateMortality(double v) {
    if (v <= mortalityGoodMax) return PerformanceRating.good;
    if (v > mortalityPoorMin) return PerformanceRating.poor;
    return PerformanceRating.average;
  }

  PerformanceRating rateWeightGrowth(double v) {
    if (v >= weightGrowthGoodMin) return PerformanceRating.good;
    if (v < weightGrowthPoorMax) return PerformanceRating.poor;
    return PerformanceRating.average;
  }

  /// Teeno metrics ka combined rating — average score se decide hota hai.
  /// (good=2, average=1, poor=0 — total 3 metrics ka average)
  static PerformanceRating combined({
    required PerformanceRating fcr,
    required PerformanceRating mortality,
    required PerformanceRating weightGrowth,
  }) {
    int score(PerformanceRating r) => r == PerformanceRating.good
        ? 2
        : (r == PerformanceRating.average ? 1 : 0);
    final avg = (score(fcr) + score(mortality) + score(weightGrowth)) / 3.0;
    if (avg >= 1.5) return PerformanceRating.good;
    if (avg >= 0.75) return PerformanceRating.average;
    return PerformanceRating.poor;
  }
}

Future<StaffPerformanceBenchmark> loadStaffPerformanceBenchmark() async {
  final raw = await CompanyStore.instance.getString(
    'staffPerformanceBenchmarkConfig',
  );
  if (raw == null || raw.isEmpty) return const StaffPerformanceBenchmark();
  try {
    return StaffPerformanceBenchmark.fromJson(json.decode(raw));
  } catch (_) {
    return const StaffPerformanceBenchmark();
  }
}

Color ratingColor(PerformanceRating r) {
  switch (r) {
    case PerformanceRating.good:
      return Colors.green.shade700;
    case PerformanceRating.average:
      return Colors.amber.shade700;
    case PerformanceRating.poor:
      return Colors.red.shade700;
  }
}

String ratingLabel(PerformanceRating r) {
  switch (r) {
    case PerformanceRating.good:
      return '🟢 Achha';
    case PerformanceRating.average:
      return '🟡 Average';
    case PerformanceRating.poor:
      return '🔴 Kharab';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ⚙️ BENCHMARK SETTINGS SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class StaffPerformanceBenchmarkScreen extends StatefulWidget {
  const StaffPerformanceBenchmarkScreen({super.key});

  @override
  State<StaffPerformanceBenchmarkScreen> createState() =>
      _StaffPerformanceBenchmarkScreenState();
}

class _StaffPerformanceBenchmarkScreenState
    extends State<StaffPerformanceBenchmarkScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);

  bool _loading = true;
  bool _saving = false;
  bool _canEdit = false;
  bool _showSavedBanner = false;

  final _fcrGoodCtrl = TextEditingController(text: '1.6');
  final _fcrPoorCtrl = TextEditingController(text: '1.8');
  final _mortGoodCtrl = TextEditingController(text: '4.0');
  final _mortPoorCtrl = TextEditingController(text: '6.0');
  final _wgGoodCtrl = TextEditingController(text: '95.0');
  final _wgPoorCtrl = TextEditingController(text: '85.0');

  StreamSubscription<void>? _dataSub;

  @override
  void initState() {
    super.initState();
    _load();
    _checkEditPermission();
    _dataSub = CompanyStore.instance.onDataChanged.listen((_) {
      if (!mounted) return;
      _load();
    });
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _fcrGoodCtrl.dispose();
    _fcrPoorCtrl.dispose();
    _mortGoodCtrl.dispose();
    _mortPoorCtrl.dispose();
    _wgGoodCtrl.dispose();
    _wgPoorCtrl.dispose();
    super.dispose();
  }

  // Sirf Owner hi edit kar sake — jaise Farmer Allocation feature mein hai
  Future<void> _checkEditPermission() async {
    final role = await SessionService.currentRole ?? 'Owner';
    if (!mounted) return;
    setState(() => _canEdit = role.toLowerCase() == 'owner');
  }

  Future<void> _load() async {
    final cfg = await loadStaffPerformanceBenchmark();
    if (!mounted) return;
    setState(() {
      _fcrGoodCtrl.text = cfg.fcrGoodMax.toString();
      _fcrPoorCtrl.text = cfg.fcrPoorMin.toString();
      _mortGoodCtrl.text = cfg.mortalityGoodMax.toString();
      _mortPoorCtrl.text = cfg.mortalityPoorMin.toString();
      _wgGoodCtrl.text = cfg.weightGrowthGoodMin.toString();
      _wgPoorCtrl.text = cfg.weightGrowthPoorMax.toString();
      _loading = false;
      _showSavedBanner = true;
    });
  }

  Future<void> _save() async {
    final fcrGood = double.tryParse(_fcrGoodCtrl.text.trim());
    final fcrPoor = double.tryParse(_fcrPoorCtrl.text.trim());
    final mortGood = double.tryParse(_mortGoodCtrl.text.trim());
    final mortPoor = double.tryParse(_mortPoorCtrl.text.trim());
    final wgGood = double.tryParse(_wgGoodCtrl.text.trim());
    final wgPoor = double.tryParse(_wgPoorCtrl.text.trim());

    if ([
      fcrGood,
      fcrPoor,
      mortGood,
      mortPoor,
      wgGood,
      wgPoor,
    ].any((v) => v == null)) {
      Get.snackbar(
        'Invalid Input',
        'Sahi numbers daalein',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    if (fcrGood! >= fcrPoor!) {
      Get.snackbar(
        'Invalid Range',
        'FCR: Achha wala number, Kharab wale se KAM hona chahiye',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    if (mortGood! >= mortPoor!) {
      Get.snackbar(
        'Invalid Range',
        'Mortality: Achha wala number, Kharab wale se KAM hona chahiye',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    if (wgGood! <= wgPoor!) {
      Get.snackbar(
        'Invalid Range',
        'Weight Growth: Achha wala number, Kharab wale se ZYADA hona chahiye',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    setState(() => _saving = true);
    final cfg = StaffPerformanceBenchmark(
      fcrGoodMax: fcrGood,
      fcrPoorMin: fcrPoor,
      mortalityGoodMax: mortGood,
      mortalityPoorMin: mortPoor,
      weightGrowthGoodMin: wgGood,
      weightGrowthPoorMax: wgPoor,
    );
    await CompanyStore.instance.setString(
      'staffPerformanceBenchmarkConfig',
      json.encode(cfg.toJson()),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _showSavedBanner = true;
    });
    Get.snackbar(
      'Saved ✅',
      'Benchmark update ho gaya.',
      backgroundColor: primaryGreen,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(15),
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
          'Performance Benchmark',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: primaryGreen))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!_canEdit)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Sirf Owner ye benchmark change kar sakta hai — aap sirf dekh sakte hain.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: primaryGreen.withOpacity(0.3)),
                  ),
                  child: const Text(
                    'Ye numbers Staff Performance report mein har farmer ko '
                    '"Achha / Average / Kharab" classify karne ke liye use '
                    'honge — aap apne farm ke hisaab se adjust kar sakte hain.',
                    style: TextStyle(
                      fontSize: 12,
                      color: primaryGreen,
                      height: 1.4,
                    ),
                  ),
                ),

                _benchmarkSection(
                  title: '🎯 FCR (Feed Conversion Ratio)',
                  subtitle: 'Kam FCR accha hota hai',
                  goodLabel: '🟢 Achha — isse KAM ya barabar',
                  poorLabel: '🔴 Kharab — isse ZYADA',
                  goodCtrl: _fcrGoodCtrl,
                  poorCtrl: _fcrPoorCtrl,
                ),
                const SizedBox(height: 16),
                _benchmarkSection(
                  title: '💀 Mortality %',
                  subtitle: 'Kam mortality accha hota hai',
                  goodLabel: '🟢 Achha — isse KAM ya barabar %',
                  poorLabel: '🔴 Kharab — isse ZYADA %',
                  goodCtrl: _mortGoodCtrl,
                  poorCtrl: _mortPoorCtrl,
                ),
                const SizedBox(height: 16),
                _benchmarkSection(
                  title: '⚖️ Weight Growth % (Target ka)',
                  subtitle: 'Zyada weight growth accha hota hai',
                  goodLabel: '🟢 Achha — isse ZYADA ya barabar %',
                  poorLabel: '🔴 Kharab — isse KAM %',
                  goodCtrl: _wgGoodCtrl,
                  poorCtrl: _wgPoorCtrl,
                  goodIsUpper: true,
                ),

                const SizedBox(height: 28),
                if (_canEdit)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
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
                        _saving ? 'Saving...' : 'Benchmark Save Karo',
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

  Widget _benchmarkSection({
    required String title,
    required String subtitle,
    required String goodLabel,
    required String poorLabel,
    required TextEditingController goodCtrl,
    required TextEditingController poorCtrl,
    bool goodIsUpper = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11.5, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: goodCtrl,
            enabled: _canEdit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() => _showSavedBanner = false),
            decoration: InputDecoration(
              labelText: goodLabel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: poorCtrl,
            enabled: _canEdit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() => _showSavedBanner = false),
            decoration: InputDecoration(
              labelText: poorLabel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '🟡 Average = in dono ke beech mein',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
