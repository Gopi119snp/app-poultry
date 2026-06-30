import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:convert';
import '../../services/company_store.dart';

class BatchCreateScreen extends StatefulWidget {
  final Map<String, dynamic> farmer;

  const BatchCreateScreen({super.key, required this.farmer});

  @override
  State<BatchCreateScreen> createState() => _BatchCreateScreenState();
}

class _BatchCreateScreenState extends State<BatchCreateScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);

  final _chicksCountController = TextEditingController();
  final _chicksRateController = TextEditingController();
  final _supplierController = TextEditingController();
  final _dateController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Aaj ki date auto set
    final now = DateTime.now();
    _dateController.text =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  @override
  void dispose() {
    _chicksCountController.dispose();
    _chicksRateController.dispose();
    _supplierController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  // Batch ID auto-generate
  // Format: pehle 3 letters uppercase + 001 + LOT + number
  // Example: Deepak Kumar → DEE001-LOT-001
  String _generateBatchId(String farmerName, int lotNumber) {
    String prefix = farmerName.trim().length >= 3
        ? farmerName.trim().substring(0, 3).toUpperCase()
        : farmerName.trim().toUpperCase().padRight(3, 'X');
    String lotNum = lotNumber.toString().padLeft(3, '0');
    return '${prefix}001-LOT-$lotNum';
  }

  void _showError(String msg) {
    Get.snackbar(
      'Error',
      msg,
      backgroundColor: Colors.red.shade600,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(15),
      icon: const Icon(Icons.error_rounded, color: Colors.white),
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
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
      setState(() {
        _dateController.text =
            '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
    }
  }

  Future<void> _createBatch() async {
    // Validations
    if (_chicksCountController.text.trim().isEmpty) {
      _showError('Chicks count daalo');
      return;
    }
    final chicksCount = int.tryParse(_chicksCountController.text.trim());
    if (chicksCount == null || chicksCount <= 0) {
      _showError('Sahi chicks count daalo');
      return;
    }
    if (_chicksRateController.text.trim().isEmpty) {
      _showError('Chicks rate daalo');
      return;
    }
    final chicksRate = double.tryParse(_chicksRateController.text.trim());
    if (chicksRate == null || chicksRate <= 0) {
      _showError('Sahi chicks rate daalo');
      return;
    }
    if (_dateController.text.isEmpty) {
      _showError('Date daalo');
      return;
    }

    setState(() => _isLoading = true);

    List<Map<String, dynamic>> farmersList =
        await CompanyStore.instance.getJsonList('companyFarmers');

    if (farmersList.isEmpty) {
      _showError('Farmers data nahi mila');
      setState(() => _isLoading = false);
      return;
    }

    // Farmer dhundho
    int farmerIndex = farmersList.indexWhere(
      (f) => f['id'] == widget.farmer['id'],
    );

    if (farmerIndex == -1) {
      _showError('Farmer nahi mila');
      setState(() => _isLoading = false);
      return;
    }

    // Active batch check — sirf 1 active batch allowed
    List<dynamic> existingBatches = farmersList[farmerIndex]['batches'] ?? [];

    bool hasActiveBatch = existingBatches.any(
      (b) =>
          b['status'].toString().toUpperCase() == 'ACTIVE' ||
          b['status'].toString().toUpperCase() == 'LIFTING READY' ||
          b['status'].toString().toUpperCase() == 'PARTIAL LIFTED',
    );

    if (hasActiveBatch) {
      _showError(
        'Is farmer ki ek active batch pehle se hai!\nPehle current batch close karo.',
      );
      setState(() => _isLoading = false);
      return;
    }

    // Batch ID generate
    int lotNumber = existingBatches.length + 1;
    String batchId = _generateBatchId(
      widget.farmer['name'] ?? 'FAR',
      lotNumber,
    );

    // Naya batch data
    final newBatch = {
      'id': batchId,
      'batchId': batchId,
      'lotNumber': lotNumber,
      'chicksCount': chicksCount,
      'chicksRate': chicksRate,
      'totalChicksCost': (chicksCount * chicksRate).toStringAsFixed(2),
      'supplier': _supplierController.text.trim(),
      'startDate': _dateController.text,
      'status': 'ACTIVE',
      'createdOn': DateTime.now().toIso8601String(),
      'dailyEntries': [],
    };

    // Farmer ke batches mein add karo
    if (farmersList[farmerIndex]['batches'] == null) {
      farmersList[farmerIndex]['batches'] = [];
    }
    farmersList[farmerIndex]['batches'].add(newBatch);

    // Save karo
    await CompanyStore.instance.saveJsonList('companyFarmers', farmersList);

    setState(() => _isLoading = false);

    if (!mounted) return;

    Get.snackbar(
      '✅ Batch Created!',
      'Batch ID: $batchId — Successfully create ho gaya!',
      backgroundColor: primaryGreen,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
      margin: const EdgeInsets.all(15),
    );

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    // Natively pop with success status to trigger auto-forwarding on parent screen
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        title: const Text(
          'Naya Batch Shuru Karo',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Farmer Info Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: primaryGreen.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primaryGreen.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: primaryGreen.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          (widget.farmer['name'] as String? ?? 'F')[0]
                              .toUpperCase(),
                          style: const TextStyle(
                            color: primaryGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.farmer['name'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            '📍 ${widget.farmer['district'] ?? ''}, ${widget.farmer['state'] ?? ''}',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Batch number preview
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: primaryGreen,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'LOT-${((widget.farmer['batches'] as List?)?.length ?? 0) + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Section — Chicks Info
              _sectionLabel('🐣 CHICKS INFORMATION'),
              const SizedBox(height: 14),

              _buildInput(
                controller: _chicksCountController,
                label: 'Chicks Count *',
                hint: 'e.g. 1000',
                icon: Icons.numbers_rounded,
                keyboardType: TextInputType.number,
              ),

              _buildInput(
                controller: _chicksRateController,
                label: 'Chicks Rate (₹ per chick) *',
                hint: 'e.g. 42',
                icon: Icons.currency_rupee_rounded,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),

              // Total Cost auto-calculate
              if (_chicksCountController.text.isNotEmpty &&
                  _chicksRateController.text.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calculate_rounded,
                        color: Colors.orange,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Total Chicks Cost: ₹${((int.tryParse(_chicksCountController.text) ?? 0) * (double.tryParse(_chicksRateController.text) ?? 0)).toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

              _buildInput(
                controller: _supplierController,
                label: 'Supplier / Company Name (Optional)',
                hint: 'e.g. Suguna Poultry',
                icon: Icons.business_rounded,
              ),

              const SizedBox(height: 8),

              // Section — Date
              _sectionLabel('📅 PLACEMENT DATE'),
              const SizedBox(height: 14),

              // Date picker
              _buildLabel('Chicks Place Date *'),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _selectDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        color: Colors.grey.shade400,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _dateController.text,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_drop_down_rounded,
                        color: Colors.grey.shade400,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Info box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ℹ️ Important Rules:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '• Ek farmer ke liye ek hi active batch ho sakti hai\n• Batch ID automatically generate hogi\n• Batch close hone ke baad hi naya batch shuru hoga\n• 23+ din hone par lifting ready status ho jaayega',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue.shade700,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Create Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _createBatch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          '🐣 Batch Shuru Karo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: primaryGreen.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primaryGreen.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: primaryGreen,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.black54,
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel(label),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: primaryGreen, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
