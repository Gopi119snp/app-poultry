import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';
import 'package:poultrypro/services/company_store.dart';
import 'package:poultrypro/services/session_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 📦 STEP 1: ChicksPurchase DATA MODEL
// ═══════════════════════════════════════════════════════════════════════════
class ChicksPurchase {
  final String company;
  final String breed;
  final double totalQty;
  final double rate;
  final double effectiveRate;
  final double totalAmount;
  final String date;
  final String addedByName;
  final String addedByRole;
  List<Map<String, dynamic>> allocations;

  ChicksPurchase({
    required this.company,
    required this.breed,
    required this.totalQty,
    required this.rate,
    required this.effectiveRate,
    required this.totalAmount,
    required this.date,
    required this.addedByName,
    this.addedByRole = '',
    this.allocations = const [],
  });

  // Ye getter dynamically remaining qty calculate karta hai
  double get remainingQty {
    double allocated = allocations.fold(
      0.0,
      (sum, item) => sum + ((item['qty'] as num?)?.toDouble() ?? 0.0),
    );
    return totalQty - allocated;
  }

  // SharedPreferences se load karne ke liye
  factory ChicksPurchase.fromMap(Map<String, dynamic> map) {
    return ChicksPurchase(
      company: map['company']?.toString() ?? '',
      breed: map['breed']?.toString() ?? '',
      totalQty: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      rate: (map['rate'] as num?)?.toDouble() ?? 0.0,
      effectiveRate: (map['effectiveRate'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (map['totalAmount'] as num?)?.toDouble() ?? 0.0,
      date: map['date']?.toString() ?? '',
      addedByName: map['addedByName']?.toString() ?? '',
      addedByRole: map['addedByRole']?.toString() ?? '',
      allocations: List<Map<String, dynamic>>.from(
        (map['allocations'] as List<dynamic>?)?.map(
              (e) => Map<String, dynamic>.from(e as Map),
            ) ??
            [],
      ),
    );
  }

  // SharedPreferences mein save karne ke liye
  Map<String, dynamic> toMap() {
    return {
      'company': company,
      'breed': breed,
      'quantity': totalQty,
      'rate': rate,
      'effectiveRate': effectiveRate,
      'totalAmount': totalAmount,
      'date': date,
      'addedByName': addedByName,
      'addedByRole': addedByRole,
      'allocations': allocations,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🛒 PURCHASE EXPENSE SCREEN — FULL CODE WITH MULTIPLE ALLOCATIONS
// ═══════════════════════════════════════════════════════════════════════════
class PurchaseExpenseScreen extends StatelessWidget {
  final Future<void> Function() onChicksTap;
  final Future<void> Function() onFeedTap;
  final Future<void> Function() onMedicineTap;
  final Future<void> Function() onLabourTap;
  final Future<void> Function() onOtherTap;

  const PurchaseExpenseScreen({
    super.key,
    required this.onChicksTap,
    required this.onFeedTap,
    required this.onMedicineTap,
    required this.onLabourTap,
    required this.onOtherTap,
  });

  static const Color primaryGreen = Color(0xFF1B5E20);

  // =============================================================================
  // 🔀 MULTIPLE CHICKS ALLOCATION FORM — ADD MODE (New Allocations)
  // =============================================================================
  void _showAllocationDialog(
    BuildContext context,
    Map<String, dynamic> purchaseEntry,
    VoidCallback onAllocationSaved, {
    bool isInformationMode = false, // true = Existing allocation info/edit karo
    int entryIndex = -1, // Konsi allocation edit karni hai
  }) async {
    // 1. Purchase details nikalna
    String company = purchaseEntry['company']?.toString() ?? 'Hatchery';
    double totalQty = (purchaseEntry['quantity'] as num?)?.toDouble() ?? 0.0;
    double purchaseRate =
        (purchaseEntry['effectiveRate'] as num?)?.toDouble() ??
        (purchaseEntry['rate'] as num?)?.toDouble() ??
        0.0;

    // Pehle se saved allocations load karo (agar koi hain toh)
    List<Map<String, dynamic>> savedAllocations =
        List<Map<String, dynamic>>.from(
          (purchaseEntry['allocations'] as List<dynamic>?)?.map(
                (e) => Map<String, dynamic>.from(e as Map),
              ) ??
              [],
        );

    // ─────────────────────────────────────────────────────────────
    // INFORMATION / EDIT MODE — Existing ek allocation ko dekhna/edit karna
    // ─────────────────────────────────────────────────────────────
    if (isInformationMode &&
        entryIndex >= 0 &&
        entryIndex < savedAllocations.length) {
      final Map<String, dynamic> thisAlloc = savedAllocations[entryIndex];

      // Smart availableQty: edit ke waqt is entry ki qty wapas add kar do
      double alreadyAllocatedTotal = savedAllocations.fold(
        0.0,
        (sum, item) => sum + ((item['qty'] as num?)?.toDouble() ?? 0.0),
      );
      double thisEntryQty = (thisAlloc['qty'] as num?)?.toDouble() ?? 0.0;
      double availableQtyForEdit =
          (totalQty - alreadyAllocatedTotal) + thisEntryQty;

      final nameCtrl = TextEditingController(
        text: thisAlloc['name']?.toString() ?? '',
      );
      final mobileCtrl = TextEditingController(
        text: thisAlloc['mobile']?.toString() ?? '',
      );
      final qtyCtrl = TextEditingController(
        text: thisEntryQty.toStringAsFixed(0),
      );
      final rateCtrl = TextEditingController(
        text: ((thisAlloc['rate'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(
          2,
        ),
      );
      final paidCtrl = TextEditingController(
        text: ((thisAlloc['paid'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(
          2,
        ),
      );

      bool isEditMode = false; // Pehle sirf info dikhegi

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog.fullscreen(
          child: StatefulBuilder(
            builder: (context, setModalState) {
              double newQty = double.tryParse(qtyCtrl.text) ?? 0.0;
              double newRate = double.tryParse(rateCtrl.text) ?? 0.0;
              double newPaid = double.tryParse(paidCtrl.text) ?? 0.0;
              double salesVal = newQty * newRate;
              double costVal = newQty * purchaseRate;
              double profit = salesVal - costVal;
              double due = (salesVal - newPaid).clamp(0.0, double.infinity);
              bool isOverQty = newQty > availableQtyForEdit;
              String allocType = thisAlloc['type']?.toString() ?? 'Company';

              return Scaffold(
                backgroundColor: const Color(0xFFF9FBF9),
                appBar: AppBar(
                  backgroundColor: Colors.orange.shade900,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isEditMode ? 'Edit Allocation' : 'Allocation Details',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    // Edit mode nahi hai toh edit button dikhao
                    if (!isEditMode)
                      IconButton(
                        icon: const Icon(
                          Icons.edit_rounded,
                          color: Colors.white,
                        ),
                        tooltip: 'Edit this allocation',
                        onPressed: () => setModalState(() => isEditMode = true),
                      ),
                  ],
                ),
                body: Column(
                  children: [
                    // ── TOP: Available Stock Box ──
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isOverQty
                            ? Colors.red.shade900
                            : Colors.orange.shade800,
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 5,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Text('📦', style: TextStyle(fontSize: 30)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Lot: $company',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Total: ${totalQty.toStringAsFixed(0)} | Allocation #${entryIndex + 1}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  isEditMode
                                      ? 'Edit ke liye Max Qty: ${availableQtyForEdit.toStringAsFixed(0)}'
                                      : 'Yahan ki Qty: ${thisEntryQty.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  'Purchase Rate: ₹${purchaseRate.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── FIELDS ──
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Type Badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: allocType == 'Company'
                                    ? Colors.blue.shade50
                                    : Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: allocType == 'Company'
                                      ? Colors.blue.shade200
                                      : Colors.green.shade200,
                                ),
                              ),
                              child: Text(
                                allocType == 'Company'
                                    ? '🧑 Apna Farmer (Company)'
                                    : '🛒 Private Buyer',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: allocType == 'Company'
                                      ? Colors.blue.shade800
                                      : Colors.green.shade800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Name Field
                            TextField(
                              controller: nameCtrl,
                              enabled: isEditMode,
                              decoration: InputDecoration(
                                labelText: allocType == 'Company'
                                    ? 'Farmer Ka Naam'
                                    : 'Buyer Ka Naam',
                                prefixIcon: const Icon(Icons.person_rounded),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Mobile (only Private)
                            if (allocType == 'Private') ...[
                              TextField(
                                controller: mobileCtrl,
                                enabled: isEditMode,
                                keyboardType: TextInputType.phone,
                                maxLength: 10,
                                decoration: InputDecoration(
                                  labelText: 'Mobile Number',
                                  prefixText: '+91 ',
                                  prefixIcon: const Icon(
                                    Icons.phone_android_rounded,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  counterText: '',
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],

                            // Qty & Rate Row
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: qtyCtrl,
                                    enabled: isEditMode,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    onChanged: (_) => setModalState(() {}),
                                    decoration: InputDecoration(
                                      labelText: 'Quantity',
                                      errorText: isEditMode && isOverQty
                                          ? 'Max ${availableQtyForEdit.toStringAsFixed(0)}'
                                          : null,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: rateCtrl,
                                    enabled: isEditMode,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    onChanged: (_) => setModalState(() {}),
                                    decoration: InputDecoration(
                                      labelText: allocType == 'Company'
                                          ? 'Billing Rate (₹)'
                                          : 'Sale Rate (₹)',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // Payment (only Private)
                            if (allocType == 'Private') ...[
                              const SizedBox(height: 14),
                              const Divider(),
                              const SizedBox(height: 8),
                              TextField(
                                controller: paidCtrl,
                                enabled: isEditMode,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (_) => setModalState(() {}),
                                decoration: InputDecoration(
                                  labelText: 'Kitna Cash / Advance Mila? (₹)',
                                  prefixIcon: const Icon(
                                    Icons.payments_rounded,
                                    color: Colors.green,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(height: 20),

                            // Due Box (only Private)
                            if (allocType == 'Private' && salesVal > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: due > 0
                                      ? Colors.red.shade50
                                      : Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: due > 0
                                        ? Colors.red.shade200
                                        : Colors.green.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      due > 0
                                          ? Icons.cancel
                                          : Icons.check_circle,
                                      color: due > 0
                                          ? Colors.red
                                          : Colors.green,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        due > 0
                                            ? 'Udhaar Bacha: ₹${due.toStringAsFixed(2)}'
                                            : 'Pura Payment Clear Hai!',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: due > 0
                                              ? Colors.red.shade800
                                              : Colors.green.shade800,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            const SizedBox(height: 20),

                            // Profit/Loss Box
                            if (salesVal > 0)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: profit >= 0
                                      ? Colors.blue.shade50
                                      : Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: profit >= 0
                                        ? Colors.blue.shade200
                                        : Colors.orange.shade200,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Purchase Cost (₹$purchaseRate × ${newQty.toStringAsFixed(0)})',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.black54,
                                          ),
                                        ),
                                        Text(
                                          '₹${costVal.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Billing/Sale Value (₹$newRate × ${newQty.toStringAsFixed(0)})',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.black54,
                                          ),
                                        ),
                                        Text(
                                          '₹${salesVal.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 6.0,
                                      ),
                                      child: Divider(
                                        height: 1,
                                        color: Colors.black12,
                                      ),
                                    ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          profit >= 0
                                              ? '📈 Margin / Profit'
                                              : '📉 Loss',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: profit >= 0
                                                ? Colors.blue.shade800
                                                : Colors.orange.shade800,
                                          ),
                                        ),
                                        Text(
                                          '₹${profit.abs().toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: profit >= 0
                                                ? Colors.blue.shade800
                                                : Colors.orange.shade800,
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
                    ),

                    // ── SAVE BUTTON (Only in Edit Mode) ──
                    if (isEditMode)
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                        color: Colors.white,
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              double newQtyVal =
                                  double.tryParse(qtyCtrl.text) ?? 0.0;
                              double newRateVal =
                                  double.tryParse(rateCtrl.text) ?? 0.0;

                              // Validation
                              if (newQtyVal <= 0 || newRateVal <= 0) {
                                Get.snackbar(
                                  'Galti ⚠️',
                                  'Quantity aur Rate sahi bharo.',
                                  backgroundColor: Colors.red,
                                  colorText: Colors.white,
                                );
                                return;
                              }
                              if (newQtyVal > availableQtyForEdit) {
                                Get.snackbar(
                                  'Galti ⚠️',
                                  'Limit se zyada stock nahi de sakte! Max: ${availableQtyForEdit.toStringAsFixed(0)}',
                                  backgroundColor: Colors.red,
                                  colorText: Colors.white,
                                );
                                return;
                              }
                              if (allocType == 'Private' &&
                                  mobileCtrl.text.trim().length != 10) {
                                Get.snackbar(
                                  'Galti ⚠️',
                                  '10-digit Mobile Number zaruri hai.',
                                  backgroundColor: Colors.red,
                                  colorText: Colors.white,
                                );
                                return;
                              }

                              // Update logic
                              savedAllocations[entryIndex] = {
                                ...savedAllocations[entryIndex],
                                'name': nameCtrl.text.trim(),
                                'mobile': mobileCtrl.text.trim(),
                                'qty': newQtyVal,
                                'rate': newRateVal,
                                'paid': double.tryParse(paidCtrl.text) ?? 0.0,
                                'editedOn': DateTime.now().toIso8601String(),
                              };

                              // CompanyStore mein save karo (company-prefixed key)
                              final String? jsonStr = await CompanyStore
                                  .instance
                                  .getString('chicksPurchaseHistory');
                              List<dynamic> allEntries = [];
                              if (jsonStr != null) {
                                try {
                                  allEntries = json.decode(jsonStr);
                                } catch (_) {}
                              }

                              for (int i = 0; i < allEntries.length; i++) {
                                if (allEntries[i]['date'] ==
                                    purchaseEntry['date']) {
                                  allEntries[i]['allocations'] =
                                      savedAllocations;
                                  break;
                                }
                              }

                              await CompanyStore.instance.setString(
                                'chicksPurchaseHistory',
                                json.encode(allEntries),
                              );

                              Navigator.pop(context);
                              Get.snackbar(
                                'Saved ✅',
                                'Allocation #${entryIndex + 1} update ho gaya!',
                                backgroundColor: Colors.green,
                                colorText: Colors.white,
                              );
                              onAllocationSaved();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'Save Changes',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
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
      );
      return; // Information/Edit mode complete — ADD mode nahi chalana
    }

    // ─────────────────────────────────────────────────────────────
    // ADD MODE — New allocations add karna (existing logic unchanged)
    // ─────────────────────────────────────────────────────────────

    // Already allocated qty
    double alreadyAllocated = savedAllocations.fold(
      0.0,
      (sum, item) => sum + ((item['qty'] as num?)?.toDouble() ?? 0.0),
    );
    double availableQty = totalQty - alreadyAllocated;

    // 2. Company Farmers load karo
    List<dynamic> rawFarmers = await CompanyStore.instance.getJsonList(
      'companyFarmers',
    );
    // Null-safe map — koi bhi field missing ho toh crash nahi hoga
    List<String> farmerOptions = rawFarmers.map((f) {
      String name = f['name']?.toString() ?? 'Unknown';
      String mobile =
          f['phone']?.toString() ??
          'No Mobile'; // farmer_profile mein phone save hota hai
      String location =
          f['district']?.toString() ??
          'No Location'; // farmer_profile mein district save hota hai
      return "$name - $mobile - $location";
    }).toList();

    // 3. Settlement billing rate
    double settlementBillingRate = 40.00;

    // 4. Naye allocation blocks ki list (is session ke liye)
    List<Map<String, dynamic>> allocations = [];

    Map<String, dynamic> createAllocationBlock(String type) {
      return {
        'id':
            DateTime.now().millisecondsSinceEpoch.toString() +
            Random().nextInt(1000).toString(),
        'type': type, // Currently active type
        // ── Company data (hamesha preserve hota hai) ──
        'farmerInfo': null,
        'farmerSearchCtrl': TextEditingController(),
        'companyQtyCtrl': TextEditingController(),
        'companyRateCtrl': TextEditingController(
          text: settlementBillingRate.toStringAsFixed(2),
        ),
        'dropdownVisible': false,

        // ── Private data (hamesha preserve hota hai) ──
        'buyerNameCtrl': TextEditingController(),
        'buyerMobileCtrl': TextEditingController(),
        'privateQtyCtrl': TextEditingController(),
        'privateRateCtrl': TextEditingController(),
        'paidCtrl': TextEditingController(),

        // ── Flags: kya dono fill hain? ──
        'companyFilled': false,
        'privateFilled': false,
      };
    }

    allocations.add(createAllocationBlock('Company'));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog.fullscreen(
        child: StatefulBuilder(
          builder: (context, setModalState) {
            double totalAllocated = 0.0;
            for (var a in allocations) {
              totalAllocated +=
                  (double.tryParse(
                        (a['companyQtyCtrl'] as TextEditingController).text,
                      ) ??
                      0.0) +
                  (double.tryParse(
                        (a['privateQtyCtrl'] as TextEditingController).text,
                      ) ??
                      0.0);
            }
            double remainingStock = availableQty - totalAllocated;
            bool isOverAllocating = remainingStock < 0;

            return Scaffold(
              backgroundColor: const Color(0xFFF9FBF9),
              appBar: AppBar(
                backgroundColor: Colors.orange.shade900,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.call_split_rounded, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Multi-Allocate Chicks',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              body: Column(
                children: [
                  // ── TOP: STOCK INFO BOX ──
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isOverAllocating
                          ? Colors.red.shade900
                          : Colors.orange.shade800,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 5,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Text('📦', style: TextStyle(fontSize: 30)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Lot: $company',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Pehle Allocated: ${alreadyAllocated.toStringAsFixed(0)} / ${totalQty.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                'Bacha Hua Stock: ${remainingStock.toStringAsFixed(0)} / ${availableQty.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                'Company Purchase Rate: ₹${purchaseRate.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── MIDDLE: DYNAMIC ALLOCATION BLOCKS ──
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: allocations.length,
                      itemBuilder: (context, index) {
                        var alloc = allocations[index];
                        String type = alloc['type'];

                        double companyQty =
                            double.tryParse(
                              (alloc['companyQtyCtrl'] as TextEditingController)
                                  .text,
                            ) ??
                            0.0;
                        double privateQty =
                            double.tryParse(
                              (alloc['privateQtyCtrl'] as TextEditingController)
                                  .text,
                            ) ??
                            0.0;
                        double qty = type == 'Company'
                            ? companyQty
                            : privateQty;
                        double rate = type == 'Company'
                            ? (double.tryParse(
                                    (alloc['companyRateCtrl']
                                            as TextEditingController)
                                        .text,
                                  ) ??
                                  0.0)
                            : (double.tryParse(
                                    (alloc['privateRateCtrl']
                                            as TextEditingController)
                                        .text,
                                  ) ??
                                  0.0);
                        double paid =
                            double.tryParse(alloc['paidCtrl'].text) ?? 0.0;

                        double salesVal = qty * rate;
                        double costVal = qty * purchaseRate;
                        double profit = salesVal - costVal;
                        double due = salesVal - paid;
                        if (due < 0) due = 0.0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.orange.shade200,
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ─ Header ─
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(14),
                                    topRight: Radius.circular(14),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Allocation #${index + 1}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade900,
                                      ),
                                    ),
                                    if (allocations.length > 1)
                                      InkWell(
                                        onTap: () {
                                          setModalState(
                                            () => allocations.removeAt(index),
                                          );
                                        },
                                        child: const Icon(
                                          Icons.cancel_rounded,
                                          color: Colors.red,
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ─ Type Selector ─
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ChoiceChip(
                                            label: const Center(
                                              child: Text('🧑 Apna Farmer'),
                                            ),
                                            selected: type == 'Company',
                                            selectedColor:
                                                Colors.orange.shade800,
                                            labelStyle: TextStyle(
                                              color: type == 'Company'
                                                  ? Colors.white
                                                  : Colors.black87,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            onSelected: (_) {
                                              setModalState(() {
                                                alloc['type'] = 'Company';
                                              });
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: ChoiceChip(
                                            label: const Center(
                                              child: Text('🛒 Private Buyer'),
                                            ),
                                            selected: type == 'Private',
                                            selectedColor:
                                                Colors.orange.shade800,
                                            labelStyle: TextStyle(
                                              color: type == 'Private'
                                                  ? Colors.white
                                                  : Colors.black87,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            onSelected: (_) {
                                              setModalState(() {
                                                alloc['type'] = 'Private';
                                              });
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),

                                    // ─ Identity Fields ─
                                    if (type == 'Company') ...[
                                      // Stable farmer search — rebuild pe reset nahi hoga
                                      TextField(
                                        key: ValueKey(
                                          '${alloc["id"]}_farmerSearch',
                                        ),
                                        controller: alloc['farmerSearchCtrl'],
                                        decoration: InputDecoration(
                                          labelText:
                                              'Search Farmer (Naam, Mobile ya Jagah) *',
                                          prefixIcon: const Icon(
                                            Icons.search_rounded,
                                          ),
                                          suffixIcon:
                                              alloc['farmerInfo'] != null
                                              ? const Icon(
                                                  Icons.check_circle_rounded,
                                                  color: Colors.green,
                                                )
                                              : null,
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          helperText:
                                              alloc['farmerInfo'] != null
                                              ? '✅ Selected: ${alloc["farmerInfo"]}'
                                              : 'Type karein aur neeche se select karein',
                                          helperMaxLines: 2,
                                        ),
                                        onChanged: (_) => setModalState(() {
                                          alloc['dropdownVisible'] = true;
                                          alloc['farmerInfo'] =
                                              null; // typing kiya toh selection reset
                                        }),
                                      ),
                                      // Filtered dropdown — sirf tab dikhe jab dropdownVisible=true
                                      if (alloc['dropdownVisible'] == true &&
                                          (alloc['farmerSearchCtrl']
                                                  as TextEditingController)
                                              .text
                                              .isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Container(
                                          constraints: const BoxConstraints(
                                            maxHeight: 160,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            border: Border.all(
                                              color: Colors.orange.shade200,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.08,
                                                ),
                                                blurRadius: 6,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: Builder(
                                            builder: (ctx) {
                                              final query =
                                                  (alloc['farmerSearchCtrl']
                                                          as TextEditingController)
                                                      .text
                                                      .toLowerCase();
                                              final filtered = farmerOptions
                                                  .where(
                                                    (f) => f
                                                        .toLowerCase()
                                                        .contains(query),
                                                  )
                                                  .toList();
                                              if (filtered.isEmpty) {
                                                return const Padding(
                                                  padding: EdgeInsets.all(12),
                                                  child: Text(
                                                    'Koi farmer nahi mila',
                                                    style: TextStyle(
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                );
                                              }
                                              return ListView.builder(
                                                shrinkWrap: true,
                                                itemCount: filtered.length,
                                                itemBuilder: (ctx2, fi) {
                                                  final option = filtered[fi];
                                                  return InkWell(
                                                    onTap: () {
                                                      setModalState(() {
                                                        alloc['farmerInfo'] =
                                                            option;
                                                        (alloc['farmerSearchCtrl']
                                                                    as TextEditingController)
                                                                .text =
                                                            option;
                                                        alloc['dropdownVisible'] =
                                                            false; // ← select ke baad hide karo
                                                      });
                                                    },
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 14,
                                                            vertical: 10,
                                                          ),
                                                      child: Text(
                                                        option,
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ] else ...[
                                      TextField(
                                        key: ValueKey(
                                          '${alloc["id"]}_buyerName',
                                        ),
                                        controller: alloc['buyerNameCtrl'],
                                        decoration: InputDecoration(
                                          labelText: 'Private Buyer Ka Naam *',
                                          prefixIcon: const Icon(
                                            Icons.storefront_rounded,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        key: ValueKey(
                                          '${alloc["id"]}_buyerMobile',
                                        ),
                                        controller: alloc['buyerMobileCtrl'],
                                        keyboardType: TextInputType.phone,
                                        maxLength: 10,
                                        decoration: InputDecoration(
                                          labelText: 'Buyer Ka Mobile Number *',
                                          prefixText: '+91 ',
                                          prefixIcon: const Icon(
                                            Icons.phone_android_rounded,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          counterText: "",
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 16),

                                    // ─ Quantity & Rate ─
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            key: ValueKey(
                                              '${alloc["id"]}_${type}_qty',
                                            ),
                                            controller: type == 'Company'
                                                ? alloc['companyQtyCtrl']
                                                      as TextEditingController
                                                : alloc['privateQtyCtrl']
                                                      as TextEditingController,
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            onChanged: (_) =>
                                                setModalState(() {}),
                                            decoration: InputDecoration(
                                              labelText: 'Quantity *',
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: TextField(
                                            key: ValueKey(
                                              '${alloc["id"]}_${type}_rate',
                                            ),
                                            controller: type == 'Company'
                                                ? alloc['companyRateCtrl']
                                                      as TextEditingController
                                                : alloc['privateRateCtrl']
                                                      as TextEditingController,
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            onChanged: (_) =>
                                                setModalState(() {}),
                                            decoration: InputDecoration(
                                              labelText: type == 'Company'
                                                  ? 'Billing Rate (₹)'
                                                  : 'Sale Rate (₹)',
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    // ─ Payment (Only Private) ─
                                    if (type == 'Private') ...[
                                      const SizedBox(height: 16),
                                      const Divider(),
                                      const SizedBox(height: 8),
                                      TextField(
                                        key: ValueKey('${alloc["id"]}_paid'),
                                        controller: alloc['paidCtrl'],
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        onChanged: (_) => setModalState(() {}),
                                        decoration: InputDecoration(
                                          labelText:
                                              'Kitna Cash / Advance Mila? (₹)',
                                          prefixIcon: const Icon(
                                            Icons.payments_rounded,
                                            color: Colors.green,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      if (salesVal > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: due > 0
                                                ? Colors.red.shade50
                                                : Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: due > 0
                                                  ? Colors.red.shade200
                                                  : Colors.green.shade200,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                due > 0
                                                    ? Icons.cancel
                                                    : Icons.check_circle,
                                                color: due > 0
                                                    ? Colors.red
                                                    : Colors.green,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  due > 0
                                                      ? 'Udhaar Bacha: ₹${due.toStringAsFixed(2)}'
                                                      : 'Pura Payment Clear Hai!',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: due > 0
                                                        ? Colors.red.shade800
                                                        : Colors.green.shade800,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],

                                    const SizedBox(height: 20),

                                    // ─ Profit / Loss ─
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: profit >= 0
                                            ? Colors.blue.shade50
                                            : Colors.orange.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: profit >= 0
                                              ? Colors.blue.shade200
                                              : Colors.orange.shade200,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Purchase Cost (₹$purchaseRate × ${qty.toStringAsFixed(0)})',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                              Text(
                                                '₹${costVal.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Billing/Sale Value (₹$rate × ${qty.toStringAsFixed(0)})',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                              Text(
                                                '₹${salesVal.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const Padding(
                                            padding: EdgeInsets.symmetric(
                                              vertical: 6.0,
                                            ),
                                            child: Divider(
                                              height: 1,
                                              color: Colors.black12,
                                            ),
                                          ),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                profit >= 0
                                                    ? '📈 Margin / Profit'
                                                    : '📉 Loss',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: profit >= 0
                                                      ? Colors.blue.shade800
                                                      : Colors.orange.shade800,
                                                ),
                                              ),
                                              Text(
                                                '₹${profit.abs().toStringAsFixed(2)}',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                  color: profit >= 0
                                                      ? Colors.blue.shade800
                                                      : Colors.orange.shade800,
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
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // ── BOTTOM BUTTONS ──
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    color: Colors.white,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: isOverAllocating
                                ? null
                                : () {
                                    setModalState(() {
                                      allocations.add(
                                        createAllocationBlock('Company'),
                                      );
                                    });
                                  },
                            icon: const Icon(Icons.add_circle_outline_rounded),
                            label: const Text(
                              'Ek Aur Farmer/Buyer Jodein',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange.shade900,
                              side: BorderSide(
                                color: Colors.orange.shade400,
                                width: 2,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              if (isOverAllocating) {
                                Get.snackbar(
                                  'Galti ⚠️',
                                  'Aapne available stock se zyada allocate kar diya hai.',
                                  backgroundColor: Colors.red,
                                  colorText: Colors.white,
                                );
                                return;
                              }

                              // Validation — har block mein jo bhi filled hai check karo
                              for (int i = 0; i < allocations.length; i++) {
                                var a = allocations[i];
                                double compQty =
                                    double.tryParse(
                                      (a['companyQtyCtrl']
                                              as TextEditingController)
                                          .text,
                                    ) ??
                                    0.0;
                                double privQty =
                                    double.tryParse(
                                      (a['privateQtyCtrl']
                                              as TextEditingController)
                                          .text,
                                    ) ??
                                    0.0;

                                // Koi bhi fill nahi hua
                                if (compQty <= 0 && privQty <= 0) {
                                  Get.snackbar(
                                    'Error',
                                    'Block #${i + 1} mein koi quantity nahi bhari.',
                                    backgroundColor: Colors.red,
                                    colorText: Colors.white,
                                  );
                                  return;
                                }

                                // Company data validate karo agar qty bhari hai
                                if (compQty > 0) {
                                  double compRate =
                                      double.tryParse(
                                        (a['companyRateCtrl']
                                                as TextEditingController)
                                            .text,
                                      ) ??
                                      0.0;
                                  if (compRate <= 0) {
                                    Get.snackbar(
                                      'Error',
                                      'Block #${i + 1} Company: Billing Rate bhari nahi.',
                                      backgroundColor: Colors.red,
                                      colorText: Colors.white,
                                    );
                                    return;
                                  }
                                  final String farmerText =
                                      (a['farmerInfo']
                                              ?.toString()
                                              .trim()
                                              .isNotEmpty ==
                                          true)
                                      ? a['farmerInfo'].toString().trim()
                                      : (a['farmerSearchCtrl']
                                                as TextEditingController)
                                            .text
                                            .trim();
                                  if (farmerText.isEmpty) {
                                    Get.snackbar(
                                      'Error',
                                      'Block #${i + 1} Company: Farmer select karein.',
                                      backgroundColor: Colors.red,
                                      colorText: Colors.white,
                                    );
                                    return;
                                  }
                                }

                                // Private data validate karo agar qty bhari hai
                                if (privQty > 0) {
                                  if ((a['buyerNameCtrl']
                                          as TextEditingController)
                                      .text
                                      .trim()
                                      .isEmpty) {
                                    Get.snackbar(
                                      'Error',
                                      'Block #${i + 1} Private: Buyer ka naam likhein.',
                                      backgroundColor: Colors.red,
                                      colorText: Colors.white,
                                    );
                                    return;
                                  }
                                  if ((a['buyerMobileCtrl']
                                              as TextEditingController)
                                          .text
                                          .trim()
                                          .length !=
                                      10) {
                                    Get.snackbar(
                                      'Error',
                                      'Block #${i + 1} Private: 10-digit Mobile Number zaruri hai.',
                                      backgroundColor: Colors.red,
                                      colorText: Colors.white,
                                    );
                                    return;
                                  }
                                }
                              }

                              // ══════════════════════════════════════
                              // STEP 2: SAVE LOGIC — CompanyStore mein update (company-prefixed)
                              // ══════════════════════════════════════
                              // Current user ka naam aur role read karo
                              final String allocatedByRole =
                                  await SessionService.currentRole ?? 'Owner';
                              final String allocatedByName =
                                  await SessionService.currentName ?? '';
                              final String? jsonStr = await CompanyStore
                                  .instance
                                  .getString('chicksPurchaseHistory');
                              List<dynamic> allEntries = [];
                              if (jsonStr != null) {
                                try {
                                  allEntries = json.decode(jsonStr);
                                } catch (_) {}
                              }

                              // Match karo purchaseEntry ko list mein se (date se)
                              for (int i = 0; i < allEntries.length; i++) {
                                if (allEntries[i]['date'] ==
                                    purchaseEntry['date']) {
                                  List<Map<String, dynamic>> existingAllocs =
                                      List<Map<String, dynamic>>.from(
                                        (allEntries[i]['allocations']
                                                    as List<dynamic>?)
                                                ?.map(
                                                  (e) =>
                                                      Map<String, dynamic>.from(
                                                        e as Map,
                                                      ),
                                                ) ??
                                            [],
                                      );

                                  // Naye allocations add karo — ek block se 2 ban sakte hain
                                  for (var a in allocations) {
                                    double compQty =
                                        double.tryParse(
                                          (a['companyQtyCtrl']
                                                  as TextEditingController)
                                              .text,
                                        ) ??
                                        0.0;
                                    double privQty =
                                        double.tryParse(
                                          (a['privateQtyCtrl']
                                                  as TextEditingController)
                                              .text,
                                        ) ??
                                        0.0;

                                    // Company allocation save karo agar qty bhari hai
                                    if (compQty > 0) {
                                      final String farmerName =
                                          (a['farmerInfo']
                                                  ?.toString()
                                                  .trim()
                                                  .isNotEmpty ==
                                              true)
                                          ? a['farmerInfo'].toString().trim()
                                          : (a['farmerSearchCtrl']
                                                    as TextEditingController)
                                                .text
                                                .trim();
                                      existingAllocs.add({
                                        'name': farmerName.isNotEmpty
                                            ? farmerName
                                            : 'Unknown Farmer',
                                        'mobile': '',
                                        'qty': compQty,
                                        'rate':
                                            double.tryParse(
                                              (a['companyRateCtrl']
                                                      as TextEditingController)
                                                  .text,
                                            ) ??
                                            0.0,
                                        'paid': 0.0,
                                        'type': 'Company',
                                        'allocatedOn': DateTime.now()
                                            .toIso8601String(),
                                        'allocatedByName': allocatedByName,
                                        'allocatedByRole': allocatedByRole,
                                      });
                                    }

                                    // Private allocation save karo agar qty bhari hai
                                    if (privQty > 0) {
                                      existingAllocs.add({
                                        'name':
                                            (a['buyerNameCtrl']
                                                    as TextEditingController)
                                                .text
                                                .trim(),
                                        'mobile':
                                            (a['buyerMobileCtrl']
                                                    as TextEditingController)
                                                .text
                                                .trim(),
                                        'qty': privQty,
                                        'rate':
                                            double.tryParse(
                                              (a['privateRateCtrl']
                                                      as TextEditingController)
                                                  .text,
                                            ) ??
                                            0.0,
                                        'paid':
                                            double.tryParse(
                                              (a['paidCtrl']
                                                      as TextEditingController)
                                                  .text,
                                            ) ??
                                            0.0,
                                        'type': 'Private',
                                        'allocatedOn': DateTime.now()
                                            .toIso8601String(),
                                        'allocatedByName': allocatedByName,
                                        'allocatedByRole': allocatedByRole,
                                      });
                                    }
                                  }

                                  allEntries[i]['allocations'] = existingAllocs;
                                  break;
                                }
                              }

                              await CompanyStore.instance.setString(
                                'chicksPurchaseHistory',
                                json.encode(allEntries),
                              );

                              Navigator.pop(context);
                              Get.snackbar(
                                'Success ✅',
                                'Sabhi chicks successfully allocate ho gaye!',
                                backgroundColor: Colors.green,
                                colorText: Colors.white,
                              );

                              // Parent list refresh karo
                              onAllocationSaved();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'Save All Allocations',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: const Row(
          children: [
            Text('🛒', style: TextStyle(fontSize: 20)),
            SizedBox(width: 8),
            Text(
              'Purchase / Expense',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              decoration: const BoxDecoration(
                color: primaryGreen,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kya kharida ya kharcha kiya?',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Category select karein',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Categories',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Row 1 ──
                  Row(
                    children: [
                      Expanded(
                        child: _PurchaseCategoryCard(
                          emoji: '🐣',
                          label: 'Chicks',
                          subtitle: 'Day Old Chicks',
                          bgColor: Colors.yellow.shade50,
                          borderColor: Colors.yellow.shade300,
                          iconBg: Colors.yellow.shade200,
                          textColor: Colors.orange.shade900,
                          badgeText: 'Stock In',
                          onTap: () => Get.to(
                            () => ChicksHistoryScreen(
                              onChicksTap: onChicksTap,
                              onShowAllocation: _showAllocationDialog,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _PurchaseCategoryCard(
                          emoji: '🌾',
                          label: 'Feed',
                          subtitle: 'Starter, Grower, Finisher',
                          bgColor: Colors.blue.shade50,
                          borderColor: Colors.blue.shade200,
                          iconBg: Colors.blue.shade100,
                          textColor: Colors.blue.shade800,
                          badgeText: 'Stock Ready',
                          onTap: () => Get.to(
                            () => FeedHistoryScreen(onFeedTap: onFeedTap),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Row 2 ──
                  Row(
                    children: [
                      Expanded(
                        child: _PurchaseCategoryCard(
                          emoji: '💊',
                          label: 'Medicine',
                          subtitle: 'Dawai, Tika, Vitamin',
                          bgColor: Colors.teal.shade50,
                          borderColor: Colors.teal.shade200,
                          iconBg: Colors.teal.shade100,
                          textColor: Colors.teal.shade800,
                          badgeText: 'Farmer Rate',
                          onTap: () => Get.to(
                            () => MedicineHistoryScreen(
                              onMedicineTap: onMedicineTap,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _PurchaseCategoryCard(
                          emoji: '👷',
                          label: 'Labour',
                          subtitle: 'Majdoor, Kaam kharcha',
                          bgColor: Colors.orange.shade50,
                          borderColor: Colors.orange.shade200,
                          iconBg: Colors.orange.shade100,
                          textColor: Colors.orange.shade800,
                          badgeText: 'Company Expense',
                          onTap: () => Get.to(
                            () => CategoryHistoryScreen(
                              title: 'Labour Expense',
                              emoji: '👷',
                              themeColor: Colors.orange.shade800,
                              historyPrefsKey: 'labourExpenseHistory',
                              dateKey: 'date',
                              onAddTap: onLabourTap,
                              addButtonLabel: 'Naya Labour Expense',
                              emptyMessage: 'Koi record nahi.',
                              itemBuilder: (context, entry) => historyEntryCard(
                                title: entry['workerName'] ?? '-',
                                subtitle:
                                    '${entry['labourType']} | ${entry['unitMode']}',
                                amountLabel:
                                    '₹${(entry['totalAmount'] as num).toDouble().toStringAsFixed(2)}',
                                entry: entry,
                                dateKey: 'date',
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  // ── Row 3 ──
                  Row(
                    children: [
                      Expanded(
                        child: _PurchaseCategoryCard(
                          emoji: '📋',
                          label: 'Other Expense',
                          subtitle: 'Miscellaneous kharcha',
                          bgColor: Colors.purple.shade50,
                          borderColor: Colors.purple.shade200,
                          iconBg: Colors.purple.shade100,
                          textColor: Colors.purple.shade800,
                          badgeText: 'Company Expense',
                          onTap: () => Get.to(
                            () => CategoryHistoryScreen(
                              title: 'Other Expense',
                              emoji: '📋',
                              themeColor: Colors.purple.shade700,
                              historyPrefsKey: 'otherExpenseHistory',
                              dateKey: 'date',
                              onAddTap: onOtherTap,
                              addButtonLabel: 'Naya Expense Add Karo',
                              emptyMessage: 'Koi record nahi.',
                              itemBuilder: (context, entry) => historyEntryCard(
                                title: entry['expenseType'] ?? '-',
                                subtitle: entry['note'] ?? 'Koi note nahi',
                                amountLabel:
                                    '₹${(entry['amount'] as num).toDouble().toStringAsFixed(2)}',
                                entry: entry,
                                dateKey: 'date',
                                color: Colors.purple.shade700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🐣 STEP 3: CHICKS HISTORY SCREEN — Allocation list + Remaining qty dikhata hai
// ═══════════════════════════════════════════════════════════════════════════
class ChicksHistoryScreen extends StatefulWidget {
  final Future<void> Function() onChicksTap;
  final void Function(
    BuildContext context,
    Map<String, dynamic> entry,
    VoidCallback onSaved, {
    bool isInformationMode,
    int entryIndex,
  })
  onShowAllocation;

  const ChicksHistoryScreen({
    super.key,
    required this.onChicksTap,
    required this.onShowAllocation,
  });

  @override
  State<ChicksHistoryScreen> createState() => _ChicksHistoryScreenState();
}

class _ChicksHistoryScreenState extends State<ChicksHistoryScreen> {
  List<ChicksPurchase> _entries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final String? jsonStr = await CompanyStore.instance.getString(
      'chicksPurchaseHistory',
    );
    if (jsonStr != null) {
      try {
        final List<dynamic> raw = json.decode(jsonStr);
        _entries = raw
            .map((e) => ChicksPurchase.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.orange.shade800,
        title: const Row(
          children: [
            Text('🐣', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text('Chicks Purchase'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Add Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await widget.onChicksTap();
                  _loadHistory();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                ),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text(
                  'Naya Chicks Purchase Add Karo',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),

          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                ? const Center(child: Text('Koi record nahi.'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _entries.length,
                    itemBuilder: (context, index) {
                      final purchase = _entries[index];
                      final double remaining = purchase.remainingQty;
                      final bool fullyAllocated = remaining <= 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.orange.shade200,
                            width: 1.2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Purchase Header ──
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(14),
                                  topRight: Radius.circular(14),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          purchase.company,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.orange.shade900,
                                          ),
                                        ),
                                        Text(
                                          'Breed: ${purchase.breed} | Total: ${purchase.totalQty.toStringAsFixed(0)} Chicks',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black54,
                                          ),
                                        ),
                                        if (purchase.addedByName.isNotEmpty)
                                          Text(
                                            '👤 ${purchase.addedByRole.isNotEmpty ? "${purchase.addedByRole}: " : ""}${purchase.addedByName}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        Text(
                                          '🕒 ${formatHistoryDateTime(purchase.date)}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.black45,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '₹${purchase.totalAmount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Colors.orange.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // ── STEP 3: Allocation List (Loop) — TAP to view/edit ──
                            if (purchase.allocations.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  10,
                                  14,
                                  0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Allocations:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    ...purchase.allocations.asMap().entries.map((
                                      entry,
                                    ) {
                                      final allocIndex = entry.key;
                                      final alloc = entry.value;
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () {
                                          // Tap karo — Information Mode khulega
                                          widget.onShowAllocation(
                                            context,
                                            purchase.toMap(),
                                            _loadHistory,
                                            isInformationMode: true,
                                            entryIndex: allocIndex,
                                          );
                                        },
                                        child: Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 6,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: alloc['type'] == 'Company'
                                                ? Colors.blue.shade50
                                                : Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: alloc['type'] == 'Company'
                                                  ? Colors.blue.shade200
                                                  : Colors.green.shade200,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  // FIX 1: Expanded wrap — long names overflow nahi honge
                                                  Expanded(
                                                    child: Row(
                                                      children: [
                                                        Text(
                                                          alloc['type'] ==
                                                                  'Company'
                                                              ? '🧑 '
                                                              : '🛒 ',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 14,
                                                              ),
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            '${alloc['name']} (${alloc['type']})',
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  // FIX 2: Right side — qty + pending badge (Private) + chevron
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        '${(alloc['qty'] as num).toStringAsFixed(0)} Chicks',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      if (alloc['type'] ==
                                                          'Private') ...[
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        Builder(
                                                          builder: (context) {
                                                            double qty =
                                                                (alloc['qty']
                                                                        as num)
                                                                    .toDouble();
                                                            double rate =
                                                                (alloc['rate']
                                                                        as num?)
                                                                    ?.toDouble() ??
                                                                0.0;
                                                            double paid =
                                                                (alloc['paid']
                                                                        as num?)
                                                                    ?.toDouble() ??
                                                                0.0;
                                                            double pending =
                                                                (qty * rate) -
                                                                paid;
                                                            return Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        6,
                                                                    vertical: 2,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    pending > 0
                                                                    ? Colors
                                                                          .red
                                                                          .shade100
                                                                    : Colors
                                                                          .green
                                                                          .shade100,
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      4,
                                                                    ),
                                                              ),
                                                              child: Text(
                                                                pending > 0
                                                                    ? 'Due: ₹${pending.toStringAsFixed(0)}'
                                                                    : 'Paid',
                                                                style: TextStyle(
                                                                  fontSize: 10,
                                                                  color:
                                                                      pending >
                                                                          0
                                                                      ? Colors
                                                                            .red
                                                                            .shade900
                                                                      : Colors
                                                                            .green
                                                                            .shade900,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ],
                                                      const SizedBox(width: 6),
                                                      Icon(
                                                        Icons
                                                            .chevron_right_rounded,
                                                        size: 16,
                                                        color: Colors
                                                            .grey
                                                            .shade500,
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              // Date + Allocator row
                                              if (alloc['allocatedOn'] !=
                                                      null ||
                                                  alloc['allocatedByName'] !=
                                                      null)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 4,
                                                      ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      if (alloc['allocatedByName'] !=
                                                              null &&
                                                          (alloc['allocatedByName']
                                                                  as String)
                                                              .isNotEmpty)
                                                        Text(
                                                          '👤 ${alloc['allocatedByRole'] != null && (alloc['allocatedByRole'] as String).isNotEmpty ? "${alloc['allocatedByRole']}: " : ""}${alloc['allocatedByName']}',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Colors
                                                                .grey
                                                                .shade600,
                                                          ),
                                                        ),
                                                      if (alloc['allocatedOn'] !=
                                                          null)
                                                        Text(
                                                          '🕒 ${formatHistoryDateTime(alloc['allocatedOn']?.toString())}',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Colors
                                                                .grey
                                                                .shade500,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),

                            // ── STEP 3: Pending Allocation (remainingQty) ──
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: fullyAllocated
                                      ? Colors.green.shade50
                                      : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: fullyAllocated
                                        ? Colors.green.shade300
                                        : Colors.red.shade300,
                                  ),
                                ),
                                child: Text(
                                  fullyAllocated
                                      ? '✅ Sabhi Chicks Allocate Ho Gaye!'
                                      : '⏳ Pending Allocation: ${remaining.toStringAsFixed(0)} Chicks',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: fullyAllocated
                                        ? Colors.green.shade800
                                        : Colors.red.shade800,
                                  ),
                                ),
                              ),
                            ),

                            // ── Allocate Button (remaining > 0 ho toh enable) ──
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  // STEP 3 CONDITION: remainingQty > 0 ho toh enable
                                  onPressed: fullyAllocated
                                      ? null
                                      : () {
                                          widget.onShowAllocation(
                                            context,
                                            purchase.toMap(),
                                            _loadHistory,
                                          );
                                        },
                                  icon: const Icon(
                                    Icons.call_split_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    fullyAllocated
                                        ? 'Fully Allocated'
                                        : 'Allocate Chicks',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: fullyAllocated
                                        ? Colors.grey.shade400
                                        : Colors.orange.shade900,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
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
}

// ═══════════════════════════════════════════════════════════════════════════
// 🌾 FEED HISTORY SCREEN — Lot list + Apna Farmer Allocation
// ═══════════════════════════════════════════════════════════════════════════
class FeedHistoryScreen extends StatefulWidget {
  final Future<void> Function() onFeedTap;
  const FeedHistoryScreen({super.key, required this.onFeedTap});

  @override
  State<FeedHistoryScreen> createState() => _FeedHistoryScreenState();
}

class _FeedHistoryScreenState extends State<FeedHistoryScreen> {
  List<Map<String, dynamic>> _entries = [];
  // lotName -> {S, G, F} sold bags via private sales
  Map<String, Map<String, double>> _soldPerLot = {};
  // lotName -> list of private sale entries
  Map<String, List<Map<String, dynamic>>> _privateSalesPerLot = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);

    // 1. Purchase lots load karo
    final String? jsonStr =
        await CompanyStore.instance.getString('feedPurchaseHistory');
    List<Map<String, dynamic>> loaded = [];
    if (jsonStr != null) {
      try {
        final List<dynamic> raw = json.decode(jsonStr);
        loaded = raw.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }

    // 2. Feed private sales load karo (sales_screen se)
    final String? salesJson =
        await CompanyStore.instance.getString('feedSalesHistory');
    Map<String, Map<String, double>> soldPerLot = {};
    Map<String, List<Map<String, dynamic>>> privateSalesPerLot = {};
    if (salesJson != null) {
      try {
        final List<dynamic> rawSales = json.decode(salesJson);
        for (final sale in rawSales) {
          final String lotName = sale['lotName']?.toString() ?? '';
          if (lotName.isEmpty) continue;
          soldPerLot[lotName] ??= {'S': 0.0, 'G': 0.0, 'F': 0.0};
          soldPerLot[lotName]!['S'] = soldPerLot[lotName]!['S']! +
              ((sale['starter']?['qty'] as num?)?.toDouble() ?? 0.0);
          soldPerLot[lotName]!['G'] = soldPerLot[lotName]!['G']! +
              ((sale['grower']?['qty'] as num?)?.toDouble() ?? 0.0);
          soldPerLot[lotName]!['F'] = soldPerLot[lotName]!['F']! +
              ((sale['finisher']?['qty'] as num?)?.toDouble() ?? 0.0);
          privateSalesPerLot[lotName] ??= [];
          privateSalesPerLot[lotName]!
              .add(Map<String, dynamic>.from(sale as Map));
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _entries = loaded;
        _soldPerLot = soldPerLot;
        _privateSalesPerLot = privateSalesPerLot;
        _isLoading = false;
      });
    }
  }

  // Farmers ko allocate ho chuki qty (dispatch)
  Map<String, double> _allocatedSoFar(Map<String, dynamic> entry) {
    final allocs = List<Map<String, dynamic>>.from(
      (entry['allocations'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map)) ??
          [],
    );
    double s = 0, g = 0, f = 0;
    for (final a in allocs) {
      s += (a['starterQty'] as num?)?.toDouble() ?? 0.0;
      g += (a['growerQty'] as num?)?.toDouble() ?? 0.0;
      f += (a['finisherQty'] as num?)?.toDouble() ?? 0.0;
    }
    return {'S': s, 'G': g, 'F': f};
  }

  void _openAllocationForm(Map<String, dynamic> entry) {
    _showFeedAllocationDialog(context, entry, _loadHistory);
  }

  void _openAllocationDetail(Map<String, dynamic> entry, int allocIndex) async {
    final result = await Get.to(
      () => FeedAllocationDetailScreen(lotEntry: entry, allocIndex: allocIndex),
    );
    if (result == true) _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        title: const Row(
          children: [
            Text('🌾', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text('Feed Purchase'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await widget.onFeedTap();
                  _loadHistory();
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('Naya Feed Purchase',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? const Center(child: Text('Koi record nahi.'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _entries.length,
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          final String company = entry['company']?.toString() ?? '-';
                          final String addedByName = entry['addedByName']?.toString() ?? '';
                          final String addedByRole = entry['addedByRole']?.toString() ?? '';
                          final String lotDate = entry['date']?.toString() ?? '';

                          final double sBags = (entry['starter']?['bags'] as num?)?.toDouble() ?? 0.0;
                          final double gBags = (entry['grower']?['bags'] as num?)?.toDouble() ?? 0.0;
                          final double fBags = (entry['finisher']?['bags'] as num?)?.toDouble() ?? 0.0;
                          final double grandTotal = (entry['grandTotal'] as num?)?.toDouble() ?? 0.0;

                          final allocs = List<Map<String, dynamic>>.from(
                            (entry['allocations'] as List<dynamic>?)
                                    ?.map((e) => Map<String, dynamic>.from(e as Map)) ??
                                [],
                          );

                          // Allocated to farmers
                          final allocatedSoFar = _allocatedSoFar(entry);
                          // Sold via private sales
                          final soldSoFar = _soldPerLot[company] ?? {'S': 0.0, 'G': 0.0, 'F': 0.0};
                          final List<Map<String, dynamic>> privateSales =
                              _privateSalesPerLot[company] ?? [];

                          // Remaining = purchased - farmer allocated - private sold
                          final double sLeft = sBags - (allocatedSoFar['S'] ?? 0) - (soldSoFar['S'] ?? 0);
                          final double gLeft = gBags - (allocatedSoFar['G'] ?? 0) - (soldSoFar['G'] ?? 0);
                          final double fLeft = fBags - (allocatedSoFar['F'] ?? 0) - (soldSoFar['F'] ?? 0);
                          final bool anyLeft = sLeft > 0 || gLeft > 0 || fLeft > 0;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.blue.shade200, width: 1.2),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Lot Header ──
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(14),
                                      topRight: Radius.circular(14),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(company,
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color: Colors.blue.shade900)),
                                            Text(
                                              'S: ${sBags.toStringAsFixed(0)} | G: ${gBags.toStringAsFixed(0)} | F: ${fBags.toStringAsFixed(0)} Bag',
                                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                                            ),
                                            Text(
                                              'Bacha: S ${sLeft.clamp(0, double.infinity).toStringAsFixed(0)} | G ${gLeft.clamp(0, double.infinity).toStringAsFixed(0)} | F ${fLeft.clamp(0, double.infinity).toStringAsFixed(0)} Bag',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: anyLeft ? Colors.green.shade700 : Colors.grey),
                                            ),
                                            if (addedByName.isNotEmpty)
                                              Text(
                                                '👤 ${addedByRole.isNotEmpty ? "$addedByRole: " : ""}$addedByName',
                                                style: const TextStyle(fontSize: 11, color: Colors.black54),
                                              ),
                                            if (lotDate.isNotEmpty)
                                              Text(
                                                '🕒 ${formatHistoryDateTime(lotDate)}',
                                                style: const TextStyle(fontSize: 11, color: Colors.black45),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Text('₹${grandTotal.toStringAsFixed(2)}',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: Colors.blue.shade900)),
                                    ],
                                  ),
                                ),

                                // ── Farmer Allocation List ──
                                if (allocs.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('🧑 Farmer Allocations:',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey.shade700)),
                                        const SizedBox(height: 6),
                                        ...allocs.asMap().entries.map((e) {
                                          final i = e.key;
                                          final a = e.value;
                                          final parts = [
                                            if (((a['starterQty'] as num?) ?? 0) > 0)
                                              'S: ${(a['starterQty'] as num).toStringAsFixed(0)}',
                                            if (((a['growerQty'] as num?) ?? 0) > 0)
                                              'G: ${(a['growerQty'] as num).toStringAsFixed(0)}',
                                            if (((a['finisherQty'] as num?) ?? 0) > 0)
                                              'F: ${(a['finisherQty'] as num).toStringAsFixed(0)}',
                                          ].join(' | ');
                                          return InkWell(
                                            borderRadius: BorderRadius.circular(8),
                                            onTap: () => _openAllocationDetail(entry, i),
                                            child: Container(
                                              margin: const EdgeInsets.only(bottom: 6),
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 12, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.blue.shade200),
                                              ),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      '🧑 ${a['farmerName'] ?? '-'}',
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                          fontSize: 12, fontWeight: FontWeight.w600),
                                                    ),
                                                  ),
                                                  Text(parts.isEmpty ? '-' : parts,
                                                      style: const TextStyle(
                                                          fontSize: 11, fontWeight: FontWeight.bold)),
                                                  const SizedBox(width: 6),
                                                  Icon(Icons.chevron_right_rounded,
                                                      size: 16, color: Colors.grey.shade500),
                                                ],
                                              ),
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),

                                // ── Private Sales Section (read-only, from sales_screen) ──
                                if (privateSales.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('🛒 Private Sales:',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey.shade700)),
                                        const SizedBox(height: 6),
                                        ...privateSales.map((sale) {
                                          final parts = [
                                            if (((sale['starter']?['qty'] as num?) ?? 0) > 0)
                                              'S: ${(sale['starter']!['qty'] as num).toStringAsFixed(0)}',
                                            if (((sale['grower']?['qty'] as num?) ?? 0) > 0)
                                              'G: ${(sale['grower']!['qty'] as num).toStringAsFixed(0)}',
                                            if (((sale['finisher']?['qty'] as num?) ?? 0) > 0)
                                              'F: ${(sale['finisher']!['qty'] as num).toStringAsFixed(0)}',
                                          ].join(' | ');
                                          return Container(
                                            margin: const EdgeInsets.only(bottom: 6),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade50,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.green.shade200),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '🛒 ${sale['buyerName'] ?? '-'}',
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontSize: 12, fontWeight: FontWeight.w600),
                                                  ),
                                                ),
                                                Text(parts.isEmpty ? '-' : parts,
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.green.shade800)),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),

                                // ── Allocate Button ──
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: anyLeft ? () => _openAllocationForm(entry) : null,
                                      icon: const Icon(Icons.call_split_rounded, size: 18),
                                      label: Text(
                                        anyLeft ? 'Allocate Feed' : 'Fully Allocated',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            anyLeft ? Colors.blue.shade700 : Colors.grey.shade400,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10)),
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
}

// ═══════════════════════════════════════════════════════════════════════════
// 🌾 FEED ALLOCATION DIALOG (ADD MODE) — Sirf Apna Farmer (Company), S/G/F qty
// ═══════════════════════════════════════════════════════════════════════════
Future<void> _showFeedAllocationDialog(
  BuildContext context,
  Map<String, dynamic> lotEntry,
  VoidCallback onSaved,
) async {
  final String company = lotEntry['company']?.toString() ?? 'Lot';

  // ── Purchase lots ki info ──
  double sBags = (lotEntry['starter']?['bags'] as num?)?.toDouble() ?? 0.0;
  double gBags = (lotEntry['grower']?['bags'] as num?)?.toDouble() ?? 0.0;
  double fBags = (lotEntry['finisher']?['bags'] as num?)?.toDouble() ?? 0.0;
  // Company ka purchase rate (per bag) — readonly info
  double sPurchaseRate = (lotEntry['starter']?['perBagPrice'] as num?)?.toDouble() ?? 0.0;
  double gPurchaseRate = (lotEntry['grower']?['perBagPrice'] as num?)?.toDouble() ?? 0.0;
  double fPurchaseRate = (lotEntry['finisher']?['perBagPrice'] as num?)?.toDouble() ?? 0.0;

  // ── Farmer allocations already ho chuki ──
  List<Map<String, dynamic>> savedAllocations = List<Map<String, dynamic>>.from(
    (lotEntry['allocations'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map)) ??
        [],
  );
  double allocS = 0, allocG = 0, allocF = 0;
  for (final a in savedAllocations) {
    allocS += (a['starterQty'] as num?)?.toDouble() ?? 0.0;
    allocG += (a['growerQty'] as num?)?.toDouble() ?? 0.0;
    allocF += (a['finisherQty'] as num?)?.toDouble() ?? 0.0;
  }

  // ── Private sales bhi minus karo ──
  double soldS = 0, soldG = 0, soldF = 0;
  final String? salesJson = await CompanyStore.instance.getString('feedSalesHistory');
  if (salesJson != null) {
    try {
      final List<dynamic> rawSales = json.decode(salesJson);
      for (final sale in rawSales) {
        if (sale['lotName']?.toString() == company) {
          soldS += (sale['starter']?['qty'] as num?)?.toDouble() ?? 0.0;
          soldG += (sale['grower']?['qty'] as num?)?.toDouble() ?? 0.0;
          soldF += (sale['finisher']?['qty'] as num?)?.toDouble() ?? 0.0;
        }
      }
    } catch (_) {}
  }

  double availS = (sBags - allocS - soldS).clamp(0.0, double.infinity);
  double availG = (gBags - allocG - soldG).clamp(0.0, double.infinity);
  double availF = (fBags - allocF - soldF).clamp(0.0, double.infinity);

  // ── Settlement config se farmer billing rate load karo ──
  // rule1SettlementConfig mein bigFeedRate (₹/kg) × bigKgPerBag = ₹/bag
  double bigBillingPerBag = 42.0 * 50.0; // default fallback
  double smBillingPerBag = 42.0 * 50.0;
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? r1Json = prefs.getString('rule1SettlementConfig');
    if (r1Json != null) {
      final Map<String, dynamic> r1 = json.decode(r1Json);
      final double bigFeedRate = (r1['bigFeedRate'] ?? 42.0).toDouble();
      final double bigKgPerBag = (r1['bigKgPerBag'] ?? 50.0).toDouble();
      final double smFeedRate = (r1['smFeedRate'] ?? 42.0).toDouble();
      final double smKgPerBag = (r1['smKgPerBag'] ?? 50.0).toDouble();
      bigBillingPerBag = bigFeedRate * bigKgPerBag;
      smBillingPerBag = smFeedRate * smKgPerBag;
    }
  } catch (_) {}
  // Default: Big Size rate use karo (most common)
  double defaultBillingPerBag = bigBillingPerBag;

  // ── Company farmers load karo ──
  List<dynamic> rawFarmers = await CompanyStore.instance.getJsonList('companyFarmers');
  List<String> farmerOptions = rawFarmers.map((f) {
    String name = f['name']?.toString() ?? 'Unknown';
    String mobile = f['phone']?.toString() ?? 'No Mobile';
    String location = f['district']?.toString() ?? 'No Location';
    return "$name - $mobile - $location";
  }).toList();

  final farmerSearchCtrl = TextEditingController();
  String? selectedFarmer;
  bool dropdownVisible = false;

  final starterQtyCtrl = TextEditingController();
  final starterRateCtrl = TextEditingController(text: defaultBillingPerBag.toStringAsFixed(2));
  final growerQtyCtrl = TextEditingController();
  final growerRateCtrl = TextEditingController(text: defaultBillingPerBag.toStringAsFixed(2));
  final finisherQtyCtrl = TextEditingController();
  final finisherRateCtrl = TextEditingController(text: defaultBillingPerBag.toStringAsFixed(2));

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog.fullscreen(
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return Scaffold(
            backgroundColor: const Color(0xFFF9FBF9),
            appBar: AppBar(
              backgroundColor: Colors.blue.shade800,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text('Feed Allocate Karo',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            body: Column(
              children: [
                // ── TOP: Stock Box ──
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.blue.shade800,
                  width: double.infinity,
                  child: Row(
                    children: [
                      const Text('🌾', style: TextStyle(fontSize: 30)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Lot: $company',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                            const SizedBox(height: 4),
                            Text(
                              'Bacha: S ${availS.toStringAsFixed(0)} | G ${availG.toStringAsFixed(0)} | F ${availF.toStringAsFixed(0)} Bag',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── FIELDS ──
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Apna Farmer search
                        TextField(
                          controller: farmerSearchCtrl,
                          decoration: InputDecoration(
                            labelText: 'Apna Farmer Search Karein (Naam, Mobile ya Jagah) *',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: selectedFarmer != null
                                ? const Icon(Icons.check_circle_rounded, color: Colors.green)
                                : null,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            helperText: selectedFarmer != null
                                ? '✅ Selected: $selectedFarmer'
                                : 'Type karein aur neeche se select karein',
                            helperMaxLines: 2,
                          ),
                          onChanged: (_) => setModalState(() {
                            dropdownVisible = true;
                            selectedFarmer = null;
                          }),
                        ),
                        if (dropdownVisible && farmerSearchCtrl.text.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 160),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.blue.shade200),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 6,
                                    offset: const Offset(0, 3)),
                              ],
                            ),
                            child: Builder(builder: (ctx) {
                              final query = farmerSearchCtrl.text.toLowerCase();
                              final filtered = farmerOptions
                                  .where((f) => f.toLowerCase().contains(query))
                                  .toList();
                              if (filtered.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text('Koi farmer nahi mila',
                                      style: TextStyle(color: Colors.grey)),
                                );
                              }
                              return ListView.builder(
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                itemBuilder: (ctx2, fi) {
                                  final option = filtered[fi];
                                  return InkWell(
                                    onTap: () => setModalState(() {
                                      selectedFarmer = option;
                                      farmerSearchCtrl.text = option;
                                      dropdownVisible = false;
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                      child: Text(option, style: const TextStyle(fontSize: 13)),
                                    ),
                                  );
                                },
                              );
                            }),
                          ),
                        ],
                        const SizedBox(height: 20),

                        if (sBags > 0)
                          _feedAllocInput('Starter', starterQtyCtrl, starterRateCtrl,
                              availS, sPurchaseRate, setModalState),
                        if (gBags > 0)
                          _feedAllocInput('Grower', growerQtyCtrl, growerRateCtrl,
                              availG, gPurchaseRate, setModalState),
                        if (fBags > 0)
                          _feedAllocInput('Finisher', finisherQtyCtrl, finisherRateCtrl,
                              availF, fPurchaseRate, setModalState),
                      ],
                    ),
                  ),
                ),

                // ── SAVE BUTTON ──
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  color: Colors.white,
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final String farmerName = (selectedFarmer ?? farmerSearchCtrl.text).trim();
                        double sQty = double.tryParse(starterQtyCtrl.text) ?? 0.0;
                        double gQty = double.tryParse(growerQtyCtrl.text) ?? 0.0;
                        double fQty = double.tryParse(finisherQtyCtrl.text) ?? 0.0;

                        if (farmerName.isEmpty) {
                          Get.snackbar('Error', 'Farmer select karein.',
                              backgroundColor: Colors.red, colorText: Colors.white);
                          return;
                        }
                        if (sQty <= 0 && gQty <= 0 && fQty <= 0) {
                          Get.snackbar('Error', 'Kam se kam ek type ki quantity bharein.',
                              backgroundColor: Colors.red, colorText: Colors.white);
                          return;
                        }
                        if (sQty > availS) {
                          Get.snackbar('Error',
                              'Starter: sirf ${availS.toStringAsFixed(0)} bag available hai',
                              backgroundColor: Colors.red, colorText: Colors.white);
                          return;
                        }
                        if (gQty > availG) {
                          Get.snackbar('Error',
                              'Grower: sirf ${availG.toStringAsFixed(0)} bag available hai',
                              backgroundColor: Colors.red, colorText: Colors.white);
                          return;
                        }
                        if (fQty > availF) {
                          Get.snackbar('Error',
                              'Finisher: sirf ${availF.toStringAsFixed(0)} bag available hai',
                              backgroundColor: Colors.red, colorText: Colors.white);
                          return;
                        }

                        final String allocatedByRole =
                            await SessionService.currentRole ?? 'Owner';
                        final String allocatedByName =
                            await SessionService.currentName ?? '';

                        savedAllocations.add({
                          'id': DateTime.now().millisecondsSinceEpoch.toString(),
                          'farmerName': farmerName,
                          'starterQty': sQty,
                          'starterRate': double.tryParse(starterRateCtrl.text) ?? 0.0,
                          'growerQty': gQty,
                          'growerRate': double.tryParse(growerRateCtrl.text) ?? 0.0,
                          'finisherQty': fQty,
                          'finisherRate': double.tryParse(finisherRateCtrl.text) ?? 0.0,
                          'allocatedOn': DateTime.now().toIso8601String(),
                          'allocatedByName': allocatedByName,
                          'allocatedByRole': allocatedByRole,
                        });

                        final String? jsonStr =
                            await CompanyStore.instance.getString('feedPurchaseHistory');
                        List<dynamic> allEntries = [];
                        if (jsonStr != null) {
                          try {
                            allEntries = json.decode(jsonStr);
                          } catch (_) {}
                        }
                        for (int i = 0; i < allEntries.length; i++) {
                          if (allEntries[i]['date'] == lotEntry['date']) {
                            allEntries[i]['allocations'] = savedAllocations;
                            break;
                          }
                        }
                        await CompanyStore.instance
                            .setString('feedPurchaseHistory', json.encode(allEntries));

                        Navigator.pop(context);
                        Get.snackbar('Saved ✅', 'Feed allocate ho gaya!',
                            backgroundColor: Colors.green, colorText: Colors.white);
                        onSaved();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Save Allocation',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

Widget _feedAllocInput(
    String title,
    TextEditingController qtyCtrl,
    TextEditingController rateCtrl,
    double avail,
    double purchaseRatePerBag,
    StateSetter setModalState) {
  double qty = double.tryParse(qtyCtrl.text) ?? 0.0;
  double billingRate = double.tryParse(rateCtrl.text) ?? 0.0;
  bool isOver = qty > avail;

  // Profit / Loss calculation (per bag aur total)
  double totalCost = qty * purchaseRatePerBag;
  double totalBilling = qty * billingRate;
  double profit = totalBilling - totalCost;
  bool hasCalc = qty > 0 && billingRate > 0;

  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: isOver ? Colors.red.shade50 : Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: isOver ? Colors.red.shade300 : Colors.grey.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('🌾 $title',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue.shade900)),
            Text('Bacha: ${avail.toStringAsFixed(0)} Bag',
                style: TextStyle(
                    fontSize: 11,
                    color: isOver ? Colors.red.shade700 : Colors.green.shade700,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        // Purchase rate info (readonly)
        if (purchaseRatePerBag > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              'Auto Cost: ₹${purchaseRatePerBag.toStringAsFixed(2)} / Bag',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
        const SizedBox(height: 6),
        // Qty + Billing Rate
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setModalState(() {}),
                decoration: InputDecoration(
                  labelText: 'Qty (Bag)',
                  isDense: true,
                  errorText: isOver ? 'Max ${avail.toStringAsFixed(0)}' : null,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: rateCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setModalState(() {}),
                decoration: const InputDecoration(
                    labelText: 'Billing Rate (₹/Bag)', isDense: true),
              ),
            ),
          ],
        ),
        // Profit / Loss mini widget
        if (hasCalc) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: profit >= 0 ? Colors.blue.shade50 : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: profit >= 0 ? Colors.blue.shade200 : Colors.orange.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Cost: ₹${totalCost.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 11, color: Colors.black54)),
                Text('Bill: ₹${totalBilling.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 11, color: Colors.black54)),
                Text(
                  profit >= 0
                      ? '📈 +₹${profit.toStringAsFixed(0)}'
                      : '📉 -₹${profit.abs().toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: profit >= 0 ? Colors.blue.shade800 : Colors.orange.shade800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// 🌾 FEED ALLOCATION DETAIL SCREEN — Edit + Delete (with confirm popup)
// ═══════════════════════════════════════════════════════════════════════════
class FeedAllocationDetailScreen extends StatefulWidget {
  final Map<String, dynamic> lotEntry;
  final int allocIndex;
  const FeedAllocationDetailScreen({
    super.key,
    required this.lotEntry,
    required this.allocIndex,
  });

  @override
  State<FeedAllocationDetailScreen> createState() => _FeedAllocationDetailScreenState();
}

class _FeedAllocationDetailScreenState extends State<FeedAllocationDetailScreen> {
  bool _isEditMode = false;
  bool _isLoading = true;
  Map<String, dynamic>? _currentLotEntry;
  Map<String, dynamic>? _alloc;

  final _nameCtrl = TextEditingController();
  final _starterQtyCtrl = TextEditingController();
  final _starterRateCtrl = TextEditingController();
  final _growerQtyCtrl = TextEditingController();
  final _growerRateCtrl = TextEditingController();
  final _finisherQtyCtrl = TextEditingController();
  final _finisherRateCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAlloc();
  }

  Future<void> _loadAlloc() async {
    final String? jsonStr = await CompanyStore.instance.getString('feedPurchaseHistory');
    List<dynamic> allEntries = [];
    if (jsonStr != null) {
      try {
        allEntries = json.decode(jsonStr);
      } catch (_) {}
    }
    Map<String, dynamic>? freshEntry;
    for (final e in allEntries) {
      if (e['date'] == widget.lotEntry['date']) {
        freshEntry = Map<String, dynamic>.from(e);
        break;
      }
    }
    freshEntry ??= widget.lotEntry;
    final allocs = List<Map<String, dynamic>>.from(
      (freshEntry['allocations'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map)) ??
          [],
    );
    final alloc = (widget.allocIndex >= 0 && widget.allocIndex < allocs.length)
        ? allocs[widget.allocIndex]
        : <String, dynamic>{};

    _nameCtrl.text = alloc['farmerName']?.toString() ?? '';
    _starterQtyCtrl.text = ((alloc['starterQty'] as num?) ?? 0).toString();
    _starterRateCtrl.text = ((alloc['starterRate'] as num?) ?? 0).toString();
    _growerQtyCtrl.text = ((alloc['growerQty'] as num?) ?? 0).toString();
    _growerRateCtrl.text = ((alloc['growerRate'] as num?) ?? 0).toString();
    _finisherQtyCtrl.text = ((alloc['finisherQty'] as num?) ?? 0).toString();
    _finisherRateCtrl.text = ((alloc['finisherRate'] as num?) ?? 0).toString();

    if (mounted) {
      setState(() {
        _currentLotEntry = freshEntry;
        _alloc = alloc;
        _isLoading = false;
      });
    }
  }

  double _availFor(String type) {
    final entry = _currentLotEntry!;
    double purchased = (entry[type]?['bags'] as num?)?.toDouble() ?? 0.0;
    final allocs = List<Map<String, dynamic>>.from(
      (entry['allocations'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map)) ??
          [],
    );
    double allocatedElsewhere = 0;
    final String key =
        type == 'starter' ? 'starterQty' : (type == 'grower' ? 'growerQty' : 'finisherQty');
    for (int i = 0; i < allocs.length; i++) {
      if (i == widget.allocIndex) continue;
      allocatedElsewhere += (allocs[i][key] as num?)?.toDouble() ?? 0.0;
    }
    return purchased - allocatedElsewhere;
  }

  Future<void> _save() async {
    double sQty = double.tryParse(_starterQtyCtrl.text) ?? 0.0;
    double gQty = double.tryParse(_growerQtyCtrl.text) ?? 0.0;
    double fQty = double.tryParse(_finisherQtyCtrl.text) ?? 0.0;

    if (sQty > _availFor('starter')) {
      Get.snackbar('Error', 'Starter: sirf ${_availFor('starter').toStringAsFixed(0)} bag available hai',
          backgroundColor: Colors.red, colorText: Colors.white);
      return;
    }
    if (gQty > _availFor('grower')) {
      Get.snackbar('Error', 'Grower: sirf ${_availFor('grower').toStringAsFixed(0)} bag available hai',
          backgroundColor: Colors.red, colorText: Colors.white);
      return;
    }
    if (fQty > _availFor('finisher')) {
      Get.snackbar('Error', 'Finisher: sirf ${_availFor('finisher').toStringAsFixed(0)} bag available hai',
          backgroundColor: Colors.red, colorText: Colors.white);
      return;
    }

    final String? jsonStr = await CompanyStore.instance.getString('feedPurchaseHistory');
    List<dynamic> allEntries = [];
    if (jsonStr != null) {
      try {
        allEntries = json.decode(jsonStr);
      } catch (_) {}
    }
    for (int i = 0; i < allEntries.length; i++) {
      if (allEntries[i]['date'] == _currentLotEntry!['date']) {
        List<dynamic> allocs = allEntries[i]['allocations'] ?? [];
        if (widget.allocIndex >= 0 && widget.allocIndex < allocs.length) {
          allocs[widget.allocIndex] = {
            ...Map<String, dynamic>.from(allocs[widget.allocIndex]),
            'farmerName': _nameCtrl.text.trim(),
            'starterQty': sQty,
            'starterRate': double.tryParse(_starterRateCtrl.text) ?? 0.0,
            'growerQty': gQty,
            'growerRate': double.tryParse(_growerRateCtrl.text) ?? 0.0,
            'finisherQty': fQty,
            'finisherRate': double.tryParse(_finisherRateCtrl.text) ?? 0.0,
            'editedOn': DateTime.now().toIso8601String(),
          };
        }
        allEntries[i]['allocations'] = allocs;
        break;
      }
    }
    await CompanyStore.instance.setString('feedPurchaseHistory', json.encode(allEntries));
    Get.back(result: true);
    Get.snackbar('Updated ✅', 'Allocation update ho gaya', backgroundColor: Colors.green, colorText: Colors.white);
  }

  Future<void> _confirmDelete() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Karein?'),
        content: const Text(
            'Kya aap is farmer ki allocation info ko delete karna chahte hain? Yeh permanent hai.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final String? jsonStr = await CompanyStore.instance.getString('feedPurchaseHistory');
      List<dynamic> allEntries = [];
      if (jsonStr != null) {
        try {
          allEntries = json.decode(jsonStr);
        } catch (_) {}
      }
      for (int i = 0; i < allEntries.length; i++) {
        if (allEntries[i]['date'] == _currentLotEntry!['date']) {
          List<dynamic> allocs = allEntries[i]['allocations'] ?? [];
          if (widget.allocIndex >= 0 && widget.allocIndex < allocs.length) {
            allocs.removeAt(widget.allocIndex);
          }
          allEntries[i]['allocations'] = allocs;
          break;
        }
      }
      await CompanyStore.instance.setString('feedPurchaseHistory', json.encode(allEntries));
      Get.back(result: true);
      Get.snackbar('Deleted 🗑️', 'Farmer Allocation Delete Ho Gaya',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _starterQtyCtrl.dispose();
    _starterRateCtrl.dispose();
    _growerQtyCtrl.dispose();
    _growerRateCtrl.dispose();
    _finisherQtyCtrl.dispose();
    _finisherRateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final entry = _currentLotEntry!;
    final String company = entry['company']?.toString() ?? '-';
    final bool hasStarter = ((entry['starter']?['bags'] as num?) ?? 0) > 0;
    final bool hasGrower = ((entry['grower']?['bags'] as num?) ?? 0) > 0;
    final bool hasFinisher = ((entry['finisher']?['bags'] as num?) ?? 0) > 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        title: Text(_isEditMode ? 'Edit Allocation' : 'Farmer Allocation',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(
            icon: Icon(_isEditMode ? Icons.close_rounded : Icons.edit_rounded, color: Colors.white),
            tooltip: _isEditMode ? 'Cancel Edit' : 'Edit Allocation',
            onPressed: () => setState(() => _isEditMode = !_isEditMode),
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded, color: Colors.white),
            tooltip: 'Delete Allocation',
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(8)),
              child: Text('📦 Lot: $company',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              enabled: _isEditMode,
              decoration: InputDecoration(
                labelText: 'Farmer Ka Naam',
                prefixIcon: const Icon(Icons.person_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            if (hasStarter) _allocDetailRow('Starter', _starterQtyCtrl, _starterRateCtrl,
                _availFor('starter'),
                purchaseRatePerBag: (entry['starter']?['perBagPrice'] as num?)?.toDouble() ?? 0.0),
            if (hasGrower) _allocDetailRow('Grower', _growerQtyCtrl, _growerRateCtrl,
                _availFor('grower'),
                purchaseRatePerBag: (entry['grower']?['perBagPrice'] as num?)?.toDouble() ?? 0.0),
            if (hasFinisher) _allocDetailRow('Finisher', _finisherQtyCtrl, _finisherRateCtrl,
                _availFor('finisher'),
                purchaseRatePerBag: (entry['finisher']?['perBagPrice'] as num?)?.toDouble() ?? 0.0),
            const SizedBox(height: 12),
            if (_alloc?['allocatedByName'] != null &&
                (_alloc!['allocatedByName'] as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    '👤 ${_alloc!['allocatedByRole'] ?? ''}: ${_alloc!['allocatedByName']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ),
            if (_alloc?['allocatedOn'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('🕒 ${formatHistoryDateTime(_alloc!['allocatedOn']?.toString())}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ),
            if (_isEditMode) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700, padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Save Changes',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _allocDetailRow(
      String title,
      TextEditingController qtyCtrl,
      TextEditingController rateCtrl,
      double avail, {
      double purchaseRatePerBag = 0.0,
    }) {
    double qty = double.tryParse(qtyCtrl.text) ?? 0.0;
    double billingRate = double.tryParse(rateCtrl.text) ?? 0.0;
    bool isOver = _isEditMode && qty > avail;
    double totalCost = qty * purchaseRatePerBag;
    double totalBilling = qty * billingRate;
    double profit = totalBilling - totalCost;
    bool hasCalc = qty > 0 && billingRate > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isOver ? Colors.red.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isOver ? Colors.red.shade300 : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('🌾 $title',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue.shade900)),
              if (_isEditMode)
                Text('Max: ${avail.toStringAsFixed(0)} Bag',
                    style: TextStyle(
                        fontSize: 11,
                        color: isOver ? Colors.red.shade700 : Colors.green.shade700,
                        fontWeight: FontWeight.bold)),
            ],
          ),
          if (purchaseRatePerBag > 0)
            Padding(
              padding: const EdgeInsets.only(top: 3, bottom: 3),
              child: Text('Auto Cost: ₹${purchaseRatePerBag.toStringAsFixed(2)} / Bag',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: qtyCtrl,
                  enabled: _isEditMode,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      labelText: 'Qty (Bag)',
                      isDense: true,
                      errorText: isOver ? 'Max ${avail.toStringAsFixed(0)}' : null),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: rateCtrl,
                  enabled: _isEditMode,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: 'Billing Rate (₹/Bag)', isDense: true),
                ),
              ),
            ],
          ),
          if (hasCalc) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: profit >= 0 ? Colors.blue.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: profit >= 0 ? Colors.blue.shade200 : Colors.orange.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Cost: ₹${totalCost.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  Text('Bill: ₹${totalBilling.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  Text(
                    profit >= 0
                        ? '📈 +₹${profit.toStringAsFixed(0)}'
                        : '📉 -₹${profit.abs().toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: profit >= 0 ? Colors.blue.shade800 : Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 📋 CATEGORY HISTORY SCREEN (Feed, Medicine, Labour, Other ke liye)
// ═══════════════════════════════════════════════════════════════════════════
class CategoryHistoryScreen extends StatefulWidget {
  final String title;
  final String emoji;
  final Color themeColor;
  final String historyPrefsKey;
  final String dateKey;
  final Future<void> Function() onAddTap;
  final String addButtonLabel;
  final String emptyMessage;
  final Widget Function(BuildContext context, Map<String, dynamic> entry)
  itemBuilder;
  final List<Widget> Function(Map<String, dynamic> entry)? actionsBuilder;

  const CategoryHistoryScreen({
    super.key,
    required this.title,
    required this.emoji,
    required this.themeColor,
    required this.historyPrefsKey,
    required this.dateKey,
    required this.onAddTap,
    required this.addButtonLabel,
    required this.emptyMessage,
    required this.itemBuilder,
    this.actionsBuilder,
  });

  @override
  State<CategoryHistoryScreen> createState() => _CategoryHistoryScreenState();
}

class _CategoryHistoryScreenState extends State<CategoryHistoryScreen> {
  List<dynamic> _entries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final String? jsonStr = await CompanyStore.instance.getString(
      widget.historyPrefsKey,
    );
    if (jsonStr != null) {
      try {
        _entries = json.decode(jsonStr);
      } catch (_) {}
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: widget.themeColor,
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await widget.onAddTap();
                  _loadHistory();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.themeColor,
                ),
                icon: const Icon(Icons.add, color: Colors.white),
                label: Text(
                  widget.addButtonLabel,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _entries.length,
                    itemBuilder: (context, index) {
                      final entry = Map<String, dynamic>.from(_entries[index]);
                      return Column(
                        children: [
                          widget.itemBuilder(context, entry),
                          if (widget.actionsBuilder != null) ...[
                            Row(children: widget.actionsBuilder!(entry)),
                            const SizedBox(height: 10),
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🧾 HELPERS
// ═══════════════════════════════════════════════════════════════════════════
String formatHistoryDateTime(String? isoStr) {
  if (isoStr == null) return '-';
  try {
    DateTime dt = DateTime.parse(isoStr);
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}, ${dt.hour}:${dt.minute}';
  } catch (_) {
    return '-';
  }
}

Widget historyEntryCard({
  required String title,
  required String subtitle,
  required String amountLabel,
  required Map<String, dynamic> entry,
  required String dateKey,
  required Color color,
}) {
  String addedByLabel = (entry['addedByName'] ?? '').toString();
  String dateTimeLabel = formatHistoryDateTime(entry[dateKey]?.toString());

  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: color,
                ),
              ),
            ),
            Text(
              amountLabel,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 10),
        Divider(height: 1, color: color.withOpacity(0.12)),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '👤 $addedByLabel',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
            Text(
              '🕒 $dateTimeLabel',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ],
    ),
  );
}

class _PurchaseCategoryCard extends StatelessWidget {
  final String emoji, label, subtitle, badgeText;
  final Color bgColor, borderColor, iconBg, textColor;
  final VoidCallback onTap;

  const _PurchaseCategoryCard({
    required this.emoji,
    required this.label,
    required this.subtitle,
    required this.bgColor,
    required this.borderColor,
    required this.iconBg,
    required this.textColor,
    required this.badgeText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 26)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.7)),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 💊 UNIT CONVERSION HELPERS
// ═══════════════════════════════════════════════════════════════════════════

// Base unit groups — sirf liquid units convertible hain
const Map<String, double> _unitToMl = {
  'ml': 1.0,
  'liter': 1000.0,
};
const Map<String, double> _unitToGram = {
  'gram': 1.0,
  'kg': 1000.0,
};

/// kisi bhi qty ko base unit mein convert karo
/// Returns null if conversion not possible (different groups)
double? convertToBase(double qty, String fromUnit, String baseUnit) {
  final String f = fromUnit.toLowerCase().trim();
  final String b = baseUnit.toLowerCase().trim();
  if (f == b) return qty;

  // Liquid group
  if (_unitToMl.containsKey(f) && _unitToMl.containsKey(b)) {
    final double inMl = qty * _unitToMl[f]!;
    return inMl / _unitToMl[b]!;
  }
  // Weight group
  if (_unitToGram.containsKey(f) && _unitToGram.containsKey(b)) {
    final double inGram = qty * _unitToGram[f]!;
    return inGram / _unitToGram[b]!;
  }
  // packet / dabba — no conversion possible
  return null;
}

/// Base unit se display unit mein convert karo
double? convertFromBase(double qtyInBase, String baseUnit, String toUnit) {
  return convertToBase(qtyInBase, baseUnit, toUnit);
}

/// Available unit options list
const List<String> kMedicineUnits = ['ml', 'liter', 'gram', 'kg', 'packet', 'dabba'];

/// Units jo ek doosre mein convert ho sakti hain
bool canConvert(String unit1, String unit2) {
  final String u1 = unit1.toLowerCase().trim();
  final String u2 = unit2.toLowerCase().trim();
  if (u1 == u2) return true;
  if (_unitToMl.containsKey(u1) && _unitToMl.containsKey(u2)) return true;
  if (_unitToGram.containsKey(u1) && _unitToGram.containsKey(u2)) return true;
  return false;
}

/// Rs/base → Rs/target  e.g. Rs2000/liter → Rs2/ml  (DIVIDE)
double? pricePerUnit(double pricePerBase, String base, String target) {
  final b = base.toLowerCase().trim(), t = target.toLowerCase().trim();
  if (b == t) return pricePerBase;
  if (_unitToMl.containsKey(b) && _unitToMl.containsKey(t))
    return pricePerBase * _unitToMl[b]! / _unitToMl[t]!;
  if (_unitToGram.containsKey(b) && _unitToGram.containsKey(t))
    return pricePerBase * _unitToGram[b]! / _unitToGram[t]!;
  return null;
}

/// Rs/target → Rs/base  e.g. Rs2/ml → Rs2000/liter
double? priceToBase(double pricePerTarget, String target, String base) =>
    pricePerUnit(pricePerTarget, target, base);

// ═══════════════════════════════════════════════════════════════════════════
// 💊 MEDICINE HISTORY SCREEN — Running lot per medicine type
// ═══════════════════════════════════════════════════════════════════════════
class MedicineHistoryScreen extends StatefulWidget {
  final Future<void> Function() onMedicineTap;
  const MedicineHistoryScreen({super.key, required this.onMedicineTap});

  @override
  State<MedicineHistoryScreen> createState() => _MedicineHistoryScreenState();
}

class _MedicineHistoryScreenState extends State<MedicineHistoryScreen> {
  List<Map<String, dynamic>> _medicines = [];
  // medicineId -> totalSoldInBaseUnit from private sales (sales_screen)
  Map<String, double> _soldBaseQty = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // 1. Medicine stock load
    final String? stockJson =
        await CompanyStore.instance.getString('medicineStockList');
    List<Map<String, dynamic>> meds = [];
    if (stockJson != null) {
      try {
        final List<dynamic> raw = json.decode(stockJson);
        meds = raw.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }

    // 2. Private sales — sold qty in base unit per medicine
    final String? salesJson =
        await CompanyStore.instance.getString('medicineSalesHistory');
    Map<String, double> soldMap = {};
    if (salesJson != null) {
      try {
        final List<dynamic> rawSales = json.decode(salesJson);
        for (final sale in rawSales) {
          final List<dynamic> items = sale['items'] as List<dynamic>? ?? [];
          for (final item in items) {
            final String mId = item['medicineId']?.toString() ?? '';
            if (mId.isEmpty) continue;
            // item mein qtyInBaseUnit stored hai
            final double qBase =
                (item['qtyInBaseUnit'] as num?)?.toDouble() ??
                (item['qty'] as num?)?.toDouble() ??
                0.0;
            soldMap[mId] = (soldMap[mId] ?? 0.0) + qBase;
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _medicines = meds;
        _soldBaseQty = soldMap;
        _isLoading = false;
      });
    }
  }

  /// Farmer allocations ka total base qty
  double _allocatedBaseQty(Map<String, dynamic> med) {
    final allocs = List<Map<String, dynamic>>.from(
      (med['allocations'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map)) ??
          [],
    );
    double total = 0;
    for (final a in allocs) {
      total += (a['qtyInBaseUnit'] as num?)?.toDouble() ??
          (a['qty'] as num?)?.toDouble() ??
          0.0;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.teal.shade700,
        leading: IconButton(
          icon: const Icon(
              Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        title: const Row(
          children: [
            Text('💊', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text('Medicine Purchase',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await widget.onMedicineTap();
                  _loadData();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('Naya Medicine Add Karo',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _medicines.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('💊',
                                style: TextStyle(fontSize: 52)),
                            const SizedBox(height: 12),
                            Text('Koi medicine record nahi.',
                                style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 14)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _medicines.length,
                        itemBuilder: (ctx, index) {
                          final med = _medicines[index];
                          return _MedicineRunningLotCard(
                            med: med,
                            soldBaseQty:
                                _soldBaseQty[med['id']?.toString() ?? ''] ??
                                    0.0,
                            allocatedBaseQty: _allocatedBaseQty(med),
                            onRefresh: _loadData,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 💊 MEDICINE RUNNING LOT CARD
// ═══════════════════════════════════════════════════════════════════════════
class _MedicineRunningLotCard extends StatelessWidget {
  final Map<String, dynamic> med;
  final double soldBaseQty;
  final double allocatedBaseQty;
  final VoidCallback onRefresh;

  const _MedicineRunningLotCard({
    required this.med,
    required this.soldBaseQty,
    required this.allocatedBaseQty,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final String mId = med['id']?.toString() ?? '';
    final String name = med['name']?.toString() ?? '-';
    final String nickName = med['nickName']?.toString() ?? '';
    final String unit = med['unit']?.toString() ?? '';
    final double totalBaseQty =
        (med['totalBaseQty'] as num?)?.toDouble() ?? 0.0;
    final double weightedAvgCost =
        (med['weightedAvgCost'] as num?)?.toDouble() ?? 0.0;
    final double currentFarmerRate =
        (med['currentFarmerRate'] as num?)?.toDouble() ?? 0.0;
    final double leftBaseQty =
        (totalBaseQty - allocatedBaseQty - soldBaseQty)
            .clamp(0.0, double.infinity);
    final bool anyLeft = leftBaseQty > 0;

    final List<Map<String, dynamic>> purchaseHistory =
        List<Map<String, dynamic>>.from(
      (med['purchaseHistory'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map)) ??
          [],
    );
    final List<Map<String, dynamic>> allocs =
        List<Map<String, dynamic>>.from(
      (med['allocations'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map)) ??
          [],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.teal.shade200, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── HEADER ──
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('💊 $name',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.teal.shade900)),
                          if (nickName.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade100,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text('"$nickName"',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.teal.shade800)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total Kharida: ${totalBaseQty.toStringAsFixed(2)} $unit',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54),
                      ),
                      Text(
                        'Bacha: ${leftBaseQty.toStringAsFixed(2)} $unit',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: anyLeft
                                ? Colors.green.shade700
                                : Colors.grey),
                      ),
                      if (weightedAvgCost > 0)
                        Text(
                          'Avg Cost: ₹${weightedAvgCost.toStringAsFixed(2)} / $unit',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                      if (currentFarmerRate > 0)
                        Text(
                          'Farmer Rate: ₹${currentFarmerRate.toStringAsFixed(2)} / $unit',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.teal.shade700,
                              fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
                // Add more stock button + Delete lot button
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () async {
                        await _showAddMoreStockDialog(context, med);
                        onRefresh();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade700,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text('Add',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Delete entire lot
                    GestureDetector(
                      onTap: () async {
                        final bool? confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Pura Lot Delete Karein?'),
                            content: Text(
                              'Kya aap "$name" ka poora lot delete karna chahte hain?\n\n'
                              '⚠️ Isse is medicine ki saari purchase history, '
                              'farmer allocations sab delete ho jayenge.\n\n'
                              'Yeh permanent hai.',
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel')),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.red),
                                child: const Text('Yes, Delete Lot'),
                              ),
                            ],
                          ),
                        );
                        if (confirm != true) return;

                        final String? sj = await CompanyStore.instance
                            .getString('medicineStockList');
                        if (sj == null) return;
                        List<dynamic> all = json.decode(sj);
                        all.removeWhere(
                            (m) => m['id']?.toString() == mId);
                        await CompanyStore.instance.setString(
                            'medicineStockList', json.encode(all));
                        Get.snackbar('Deleted 🗑️',
                            '"$name" lot delete ho gaya',
                            backgroundColor: Colors.red,
                            colorText: Colors.white);
                        onRefresh();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Icon(Icons.delete_rounded,
                            color: Colors.red.shade700, size: 16),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── PURCHASE HISTORY BUTTON ──
          if (purchaseHistory.isNotEmpty)
            InkWell(
              onTap: () => Get.to(() => MedicinePurchaseHistoryScreen(
                    medicineId: mId,
                    medicineName: name,
                    unit: unit,
                  )),
              child: Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.history_rounded,
                            size: 15, color: Colors.teal.shade700),
                        const SizedBox(width: 6),
                        Text(
                          'Purchase History (${purchaseHistory.length} baar kharida)',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.teal.shade800,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 16, color: Colors.teal.shade700),
                  ],
                ),
              ),
            ),

          // ── FARMER ALLOCATIONS ──
          if (allocs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🧑 Farmer Allocations:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700)),
                  const SizedBox(height: 6),
                  ...allocs.asMap().entries.map((e) {
                    final i = e.key;
                    final a = e.value;
                    final double aBaseQty =
                        (a['qtyInBaseUnit'] as num?)?.toDouble() ??
                            (a['qty'] as num?)?.toDouble() ??
                            0.0;
                    final String aDisplayUnit =
                        a['unit']?.toString() ?? unit;
                    final double aDisplayQty =
                        convertFromBase(aBaseQty, unit, aDisplayUnit) ??
                            aBaseQty;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () async {
                        final result = await Get.to(
                          () => MedicineAllocationDetailScreen(
                            medicineId: mId,
                            allocIndex: i,
                          ),
                        );
                        if (result == true) onRefresh();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: Colors.teal.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '🧑 ${a['farmerName'] ?? '-'}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text(
                              '${aDisplayQty.toStringAsFixed(2)} $aDisplayUnit',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.chevron_right_rounded,
                                size: 16, color: Colors.grey.shade500),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),

          // ── ALLOCATE BUTTON ──
          Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: anyLeft
                    ? () async {
                        await _showMedicineAllocationDialog(
                            context, med, mId, unit);
                        onRefresh();
                      }
                    : null,
                icon: const Icon(Icons.call_split_rounded, size: 18),
                label: Text(
                  anyLeft
                      ? 'Allocate Medicine to Farmer'
                      : 'Fully Used / Sold',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      anyLeft ? Colors.teal.shade700 : Colors.grey.shade400,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 💊 ADD MORE STOCK DIALOG — Same medicine mein add karo (Running lot)
// ═══════════════════════════════════════════════════════════════════════════
Future<void> _showAddMoreStockDialog(
  BuildContext context,
  Map<String, dynamic> med,
) async {
  final String mId = med['id']?.toString() ?? '';
  final String name = med['name']?.toString() ?? '';
  final String baseUnit = med['unit']?.toString() ?? 'unit';

  final TextEditingController qtyCtrl = TextEditingController();
  String selectedUnit = baseUnit;
  final TextEditingController actualPriceCtrl = TextEditingController();
  final TextEditingController farmerPriceCtrl = TextEditingController();

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx2, setDlg) {
        final double qty = double.tryParse(qtyCtrl.text) ?? 0.0;
        final double qtyInBase =
            convertToBase(qty, selectedUnit, baseUnit) ?? qty;

        return AlertDialog(
          title: Text('💊 $name — Aur Stock Add Karo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Qty
                TextField(
                  controller: qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  onChanged: (_) => setDlg(() {}),
                  decoration: InputDecoration(
                    labelText: 'Quantity *',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),

                // Unit select
                Text('Unit Chuno:',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: kMedicineUnits.map((u) {
                    final bool enabled = canConvert(u, baseUnit);
                    return ChoiceChip(
                      label: Text(u),
                      selected: selectedUnit == u,
                      onSelected: enabled
                          ? (v) {
                              if (v) setDlg(() => selectedUnit = u);
                            }
                          : null,
                      selectedColor: Colors.teal.shade700,
                      labelStyle: TextStyle(
                        color: enabled
                            ? (selectedUnit == u
                                ? Colors.white
                                : Colors.black87)
                            : Colors.grey,
                      ),
                    );
                  }).toList(),
                ),

                // Conversion preview
                if (qty > 0 && selectedUnit != baseUnit)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '= ${qtyInBase.toStringAsFixed(3)} $baseUnit (base)',
                      style: TextStyle(
                          fontSize: 11, color: Colors.teal.shade700),
                    ),
                  ),
                const SizedBox(height: 12),

                // Actual price
                TextField(
                  controller: actualPriceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Actual Price (₹) *',
                    helperText: 'Company ne jis rate pe kharida',
                    prefixIcon: const Icon(Icons.store_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),

                // Farmer price
                TextField(
                  controller: farmerPriceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Farmer Price (₹) *',
                    helperText: 'Jo rate farmer ko charge hoga',
                    prefixIcon: const Icon(Icons.person_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final double qty2 =
                    double.tryParse(qtyCtrl.text) ?? 0.0;
                final double actualPrice =
                    double.tryParse(actualPriceCtrl.text) ?? 0.0;
                final double farmerPrice =
                    double.tryParse(farmerPriceCtrl.text) ?? 0.0;

                if (qty2 <= 0) {
                  Get.snackbar('Error', 'Quantity dalein',
                      backgroundColor: Colors.red,
                      colorText: Colors.white);
                  return;
                }
                if (actualPrice <= 0) {
                  Get.snackbar('Error', 'Actual price dalein',
                      backgroundColor: Colors.red,
                      colorText: Colors.white);
                  return;
                }

                final double qtyBase =
                    convertToBase(qty2, selectedUnit, baseUnit) ?? qty2;
                final double perBaseActual =
                    qtyBase > 0 ? actualPrice / qtyBase : 0;

                // Stock load
                final String? stockJson = await CompanyStore.instance
                    .getString('medicineStockList');
                List<dynamic> all = [];
                if (stockJson != null) {
                  try {
                    all = json.decode(stockJson);
                  } catch (_) {}
                }

                final String addedByName =
                    await SessionService.currentName ?? '';
                final String addedByRole =
                    await SessionService.currentRole ?? '';

                for (int i = 0; i < all.length; i++) {
                  if (all[i]['id']?.toString() == mId) {
                    final double oldBase =
                        (all[i]['totalBaseQty'] as num?)?.toDouble() ??
                            0.0;
                    final double oldAvgCost =
                        (all[i]['weightedAvgCost'] as num?)?.toDouble() ??
                            0.0;
                    final double newTotalBase = oldBase + qtyBase;

                    // Weighted average cost
                    final double newAvgCost = newTotalBase > 0
                        ? ((oldBase * oldAvgCost) +
                                (qtyBase * perBaseActual)) /
                            newTotalBase
                        : perBaseActual;

                    // Current farmer rate = per base unit farmer price (naya wala)
                    final double perBaseFarmer =
                        qtyBase > 0 ? farmerPrice / qtyBase : 0;

                    all[i]['totalBaseQty'] = newTotalBase;
                    all[i]['weightedAvgCost'] = newAvgCost;
                    all[i]['currentFarmerRate'] = perBaseFarmer;

                    // Purchase history mein add karo
                    List<dynamic> hist =
                        all[i]['purchaseHistory'] as List<dynamic>? ??
                            [];
                    hist.add({
                      'id': DateTime.now()
                          .millisecondsSinceEpoch
                          .toString(),
                      'qty': qty2,
                      'unit': selectedUnit,
                      'qtyInBaseUnit': qtyBase,
                      'actualPrice': actualPrice,
                      'farmerPrice': farmerPrice,
                      'perBaseActualCost': perBaseActual,
                      'perBaseFarmerRate': perBaseFarmer,
                      'date': DateTime.now().toIso8601String(),
                      'addedByName': addedByName,
                      'addedByRole': addedByRole,
                    });
                    all[i]['purchaseHistory'] = hist;
                    break;
                  }
                }

                await CompanyStore.instance.setString(
                    'medicineStockList', json.encode(all));

                Navigator.pop(ctx);
                Get.snackbar('Added ✅', '${qty2.toStringAsFixed(2)} $selectedUnit add ho gaya!',
                    backgroundColor: Colors.green,
                    colorText: Colors.white);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700),
              child: const Text('Add Stock',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// 💊 MEDICINE FIRST-TIME CREATION — onMedicineTap se call hoga
// home_screen se tap karne par pehli baar naya medicine type banao
// ═══════════════════════════════════════════════════════════════════════════
Future<void> showMedicineAddDialog(BuildContext context) async {
  final nameCtrl = TextEditingController();
  final nickCtrl = TextEditingController();
  final qtyCtrl = TextEditingController();
  final actualPriceCtrl = TextEditingController();
  final farmerPriceCtrl = TextEditingController();
  String selectedUnit = 'ml';

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx2, setDlg) {
        final double qty = double.tryParse(qtyCtrl.text) ?? 0.0;

        return Dialog.fullscreen(
          child: Scaffold(
            backgroundColor: const Color(0xFFF9FBF9),
            appBar: AppBar(
              backgroundColor: Colors.teal.shade700,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
              title: const Text('💊 Medicine Purchase',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Medicine Name
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Medicine Ka Naam *',
                      prefixIcon: const Icon(Icons.medical_services_rounded),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Nick Name
                  TextField(
                    controller: nickCtrl,
                    decoration: InputDecoration(
                      labelText: 'Nick Name (Optional)',
                      helperText:
                          'e.g. "Enro" — Batch entry mein shortcut ke liye',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Qty
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    onChanged: (_) => setDlg(() {}),
                    decoration: InputDecoration(
                      labelText: 'Total Quantity *',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Unit select
                  const Text('Unit Chuno *',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: kMedicineUnits.map((u) {
                      return ChoiceChip(
                        label: Text(u),
                        selected: selectedUnit == u,
                        onSelected: (v) {
                          if (v) setDlg(() => selectedUnit = u);
                        },
                        selectedColor: Colors.teal.shade700,
                        labelStyle: TextStyle(
                          color: selectedUnit == u
                              ? Colors.white
                              : Colors.black87,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // Price section header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.currency_rupee,
                            color: Colors.teal.shade700, size: 18),
                        const SizedBox(width: 8),
                        Text('Price Details',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.teal.shade800)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Actual price
                  TextField(
                    controller: actualPriceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Actual Price (₹) *',
                      helperText: 'Company ne jis rate pe kharida',
                      prefixIcon: const Icon(Icons.store_rounded,
                          color: Colors.blue),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Farmer price
                  TextField(
                    controller: farmerPriceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Farmer Price (₹) *',
                      helperText: 'Jo rate farmer ko charge hoga',
                      prefixIcon: const Icon(Icons.person_rounded,
                          color: Colors.orange),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () async {
                        final String name = nameCtrl.text.trim();
                        final double qty2 =
                            double.tryParse(qtyCtrl.text) ?? 0.0;
                        final double actualPrice =
                            double.tryParse(actualPriceCtrl.text) ?? 0.0;
                        final double farmerPrice =
                            double.tryParse(farmerPriceCtrl.text) ?? 0.0;

                        if (name.isEmpty) {
                          Get.snackbar('Error', 'Medicine ka naam dalein',
                              backgroundColor: Colors.red,
                              colorText: Colors.white);
                          return;
                        }
                        if (qty2 <= 0) {
                          Get.snackbar('Error', 'Quantity dalein',
                              backgroundColor: Colors.red,
                              colorText: Colors.white);
                          return;
                        }
                        if (actualPrice <= 0) {
                          Get.snackbar('Error', 'Actual price dalein',
                              backgroundColor: Colors.red,
                              colorText: Colors.white);
                          return;
                        }
                        if (farmerPrice <= 0) {
                          Get.snackbar('Error', 'Farmer price dalein',
                              backgroundColor: Colors.red,
                              colorText: Colors.white);
                          return;
                        }

                        // qty is already in selected unit = base unit on first creation
                        // base unit = selectedUnit
                        final double qtyBase = qty2; // first purchase = base qty
                        final double perBaseActual =
                            qtyBase > 0 ? actualPrice / qtyBase : 0;
                        final double perBaseFarmer =
                            qtyBase > 0 ? farmerPrice / qtyBase : 0;

                        final String addedByName =
                            await SessionService.currentName ?? '';
                        final String addedByRole =
                            await SessionService.currentRole ?? '';
                        final String newId = DateTime.now()
                            .millisecondsSinceEpoch
                            .toString();

                        final Map<String, dynamic> newMed = {
                          'id': newId,
                          'name': name,
                          'nickName': nickCtrl.text.trim(),
                          'unit': selectedUnit, // base unit
                          'totalBaseQty': qtyBase,
                          'weightedAvgCost': perBaseActual,
                          'currentFarmerRate': perBaseFarmer,
                          'addedByName': addedByName,
                          'addedByRole': addedByRole,
                          'createdOn': DateTime.now().toIso8601String(),
                          'allocations': [],
                          'purchaseHistory': [
                            {
                              'id': newId,
                              'qty': qty2,
                              'unit': selectedUnit,
                              'qtyInBaseUnit': qtyBase,
                              'actualPrice': actualPrice,
                              'farmerPrice': farmerPrice,
                              'perBaseActualCost': perBaseActual,
                              'perBaseFarmerRate': perBaseFarmer,
                              'date': DateTime.now().toIso8601String(),
                              'addedByName': addedByName,
                              'addedByRole': addedByRole,
                            }
                          ],
                        };

                        // Existing stock load karo
                        final String? stockJson = await CompanyStore.instance
                            .getString('medicineStockList');
                        List<dynamic> all = [];
                        if (stockJson != null) {
                          try {
                            all = json.decode(stockJson);
                          } catch (_) {}
                        }
                        // Same name ki medicine already hai?
                        final bool exists = all.any(
                          (m) =>
                              m['name']
                                  ?.toString()
                                  .toLowerCase()
                                  .trim() ==
                              name.toLowerCase().trim(),
                        );
                        if (exists) {
                          Get.snackbar('Already Exists',
                              '"$name" pehle se hai. Usi card mein "Add" button se stock add karo.',
                              backgroundColor: Colors.orange,
                              colorText: Colors.white);
                          return;
                        }

                        all.insert(0, newMed);
                        await CompanyStore.instance.setString(
                            'medicineStockList', json.encode(all));

                        Navigator.pop(ctx);
                        Get.snackbar('Saved ✅', '$name add ho gaya!',
                            backgroundColor: Colors.green,
                            colorText: Colors.white);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Save Karo',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// 💊 MEDICINE PURCHASE HISTORY SCREEN — Kab kab kharida
// ═══════════════════════════════════════════════════════════════════════════
class MedicinePurchaseHistoryScreen extends StatefulWidget {
  final String medicineId;
  final String medicineName;
  final String unit;

  const MedicinePurchaseHistoryScreen({
    super.key,
    required this.medicineId,
    required this.medicineName,
    required this.unit,
  });

  @override
  State<MedicinePurchaseHistoryScreen> createState() =>
      _MedicinePurchaseHistoryScreenState();
}

class _MedicinePurchaseHistoryScreenState
    extends State<MedicinePurchaseHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final String? stockJson =
        await CompanyStore.instance.getString('medicineStockList');
    if (stockJson != null) {
      try {
        final List<dynamic> all = json.decode(stockJson);
        for (final m in all) {
          if (m['id']?.toString() == widget.medicineId) {
            final List<dynamic> hist =
                m['purchaseHistory'] as List<dynamic>? ?? [];
            _history =
                hist.map((e) => Map<String, dynamic>.from(e)).toList();
            break;
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // ── Delete ek purchase entry ──
  Future<void> _deleteEntry(int index) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Karein?'),
        content: Text(
            'Kya aap "${_history[index]['qty']} ${_history[index]['unit'] ?? widget.unit}" '
            'wali purchase entry delete karna chahte hain?\n\n'
            '⚠️ Isse stock quantity bhi update hogi.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final String? stockJson =
        await CompanyStore.instance.getString('medicineStockList');
    if (stockJson == null) return;
    List<dynamic> all = json.decode(stockJson);

    for (int i = 0; i < all.length; i++) {
      if (all[i]['id']?.toString() == widget.medicineId) {
        List<dynamic> hist = all[i]['purchaseHistory'] ?? [];
        if (index < 0 || index >= hist.length) break;

        final double removedBase =
            (hist[index]['qtyInBaseUnit'] as num?)?.toDouble() ??
            (hist[index]['qty'] as num?)?.toDouble() ?? 0.0;
        final double removedActual =
            (hist[index]['actualPrice'] as num?)?.toDouble() ?? 0.0;
        hist.removeAt(index);
        all[i]['purchaseHistory'] = hist;

        // Recalculate totalBaseQty and weightedAvgCost from remaining entries
        double newTotalBase = 0;
        double newTotalCost = 0;
        for (final h in hist) {
          final double hBase = (h['qtyInBaseUnit'] as num?)?.toDouble() ??
              (h['qty'] as num?)?.toDouble() ?? 0.0;
          final double hActual = (h['actualPrice'] as num?)?.toDouble() ?? 0.0;
          final double hCostPB = hBase > 0 ? hActual / hBase : 0;
          newTotalBase += hBase;
          newTotalCost += hBase * hCostPB;
        }
        all[i]['totalBaseQty']    = newTotalBase;
        all[i]['weightedAvgCost'] = newTotalBase > 0
            ? newTotalCost / newTotalBase
            : 0.0;
        break;
      }
    }

    await CompanyStore.instance.setString('medicineStockList', json.encode(all));
    Get.snackbar('Deleted 🗑️', 'Purchase entry delete ho gaya',
        backgroundColor: Colors.red, colorText: Colors.white);
    _load();
  }

  // ── Edit ek purchase entry ──
  Future<void> _editEntry(int index) async {
    final h = _history[index];
    final qtyCtrl = TextEditingController(
        text: (h['qty'] as num?)?.toStringAsFixed(2) ?? '');
    final aCtrl = TextEditingController(
        text: (h['actualPrice'] as num?)?.toStringAsFixed(2) ?? '');
    final fCtrl = TextEditingController(
        text: (h['farmerPrice'] as num?)?.toStringAsFixed(2) ?? '');
    final String entryUnit = h['unit']?.toString() ?? widget.unit;

    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('✏️ Edit Purchase Entry'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Unit: $entryUnit',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Quantity ($entryUnit)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: aCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Actual Price (₹)',
                helperText: 'Company ne jis rate pe kharida (total)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: fCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Farmer Price (₹)',
                helperText: 'Jo rate farmer ko charge hoga (total)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700),
            child: const Text('Save',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (saved != true) return;

    final double qty2 = double.tryParse(qtyCtrl.text) ?? 0;
    final double act  = double.tryParse(aCtrl.text)   ?? 0;
    final double frm  = double.tryParse(fCtrl.text)   ?? 0;
    if (qty2 <= 0 || act <= 0) {
      Get.snackbar('Error', 'Quantity aur actual price zaroori hai',
          backgroundColor: Colors.red, colorText: Colors.white);
      return;
    }

    final double qBase =
        convertToBase(qty2, entryUnit, widget.unit) ?? qty2;
    final double cPB = qBase > 0 ? act / qBase : 0;
    final double fPB = qBase > 0 ? frm / qBase : 0;

    final String? stockJson =
        await CompanyStore.instance.getString('medicineStockList');
    if (stockJson == null) return;
    List<dynamic> all = json.decode(stockJson);

    for (int i = 0; i < all.length; i++) {
      if (all[i]['id']?.toString() == widget.medicineId) {
        List<dynamic> hist = all[i]['purchaseHistory'] ?? [];
        if (index >= 0 && index < hist.length) {
          hist[index] = {
            ...Map<String, dynamic>.from(hist[index]),
            'qty'           : qty2,
            'qtyInBaseUnit' : qBase,
            'actualPrice'   : act,
            'farmerPrice'   : frm,
            'perBaseActualCost': cPB,
            'perBaseFarmerRate': fPB,
            'editedOn'      : DateTime.now().toIso8601String(),
          };
        }
        all[i]['purchaseHistory'] = hist;

        // Recalculate totalBaseQty and weightedAvgCost
        double newTotalBase = 0, newTotalCost = 0;
        for (final hEntry in hist) {
          final double hBase = (hEntry['qtyInBaseUnit'] as num?)?.toDouble() ?? 0;
          final double hAct  = (hEntry['actualPrice']   as num?)?.toDouble() ?? 0;
          final double hCPB  = hBase > 0 ? hAct / hBase : 0;
          newTotalBase += hBase;
          newTotalCost += hBase * hCPB;
        }
        all[i]['totalBaseQty']    = newTotalBase;
        all[i]['weightedAvgCost'] = newTotalBase > 0
            ? newTotalCost / newTotalBase : 0.0;
        // Update farmer rate from latest entry
        if (hist.isNotEmpty) {
          final lastFPB = (hist.last['perBaseFarmerRate'] as num?)?.toDouble() ?? fPB;
          all[i]['currentFarmerRate'] = lastFPB;
        }
        break;
      }
    }

    await CompanyStore.instance.setString(
        'medicineStockList', json.encode(all));
    Get.snackbar('Updated ✅', 'Purchase entry update ho gaya',
        backgroundColor: Colors.green, colorText: Colors.white);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.teal.shade700,
        leading: IconButton(
          icon: const Icon(
              Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        title: Text(
          '💊 ${widget.medicineName} — History',
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const Center(child: Text('Koi purchase history nahi.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _history.length,
                  itemBuilder: (ctx, i) {
                    final h = _history[i];
                    final double qty =
                        (h['qty'] as num?)?.toDouble() ?? 0.0;
                    final String hUnit =
                        h['unit']?.toString() ?? widget.unit;
                    final double qtyBase =
                        (h['qtyInBaseUnit'] as num?)?.toDouble() ?? qty;
                    final double actualPrice =
                        (h['actualPrice'] as num?)?.toDouble() ?? 0.0;
                    final double farmerPrice =
                        (h['farmerPrice'] as num?)?.toDouble() ?? 0.0;
                    final double cPB =
                        (h['perBaseActualCost'] as num?)?.toDouble() ?? 0;
                    final String date =
                        formatHistoryDateTime(h['date']?.toString());
                    final String addedBy =
                        h['addedByName']?.toString() ?? '';
                    final String addedByRole =
                        h['addedByRole']?.toString() ?? '';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.teal.shade100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Header: qty + price + edit/delete ──
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${qty.toStringAsFixed(2)} $hUnit',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Colors.teal.shade900),
                              ),
                              Row(children: [
                                Text(
                                  '₹${actualPrice.toStringAsFixed(2)}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Colors.teal.shade900),
                                ),
                                const SizedBox(width: 8),
                                // Edit button
                                InkWell(
                                  onTap: () => _editEntry(i),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                            color: Colors.blue.shade200)),
                                    child: Icon(Icons.edit_rounded,
                                        size: 14,
                                        color: Colors.blue.shade700),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Delete button
                                InkWell(
                                  onTap: () => _deleteEntry(i),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                            color: Colors.red.shade200)),
                                    child: Icon(Icons.delete_rounded,
                                        size: 14,
                                        color: Colors.red.shade700),
                                  ),
                                ),
                              ]),
                            ],
                          ),
                          if (hUnit != widget.unit)
                            Text(
                              '(= ${qtyBase.toStringAsFixed(3)} ${widget.unit})',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            'Actual: ₹${actualPrice.toStringAsFixed(2)}  •  Farmer: ₹${farmerPrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54),
                          ),
                          if (cPB > 0)
                            Text(
                              'Per unit cost: ₹${cPB.toStringAsFixed(2)} / ${widget.unit}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.teal.shade700)),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              if (addedBy.isNotEmpty)
                                Text(
                                  '👤 ${addedByRole.isNotEmpty ? "$addedByRole: " : ""}$addedBy',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.black45),
                                ),
                              Text(
                                '🕒 $date',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.black45),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 💊 MEDICINE ALLOCATION DIALOG — Farmer ko medicine do
// ═══════════════════════════════════════════════════════════════════════════
Future<void> _showMedicineAllocationDialog(
  BuildContext context,
  Map<String, dynamic> med,
  String mId,
  String baseUnit,
) async {
  final double totalBaseQty =
      (med['totalBaseQty'] as num?)?.toDouble() ?? 0.0;
  final double weightedAvgCost =
      (med['weightedAvgCost'] as num?)?.toDouble() ?? 0.0;
  final double currentFarmerRate =
      (med['currentFarmerRate'] as num?)?.toDouble() ?? 0.0;

  // Already allocated
  final List<Map<String, dynamic>> allocs = List<Map<String, dynamic>>.from(
    (med['allocations'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map)) ??
        [],
  );
  double allocatedBase = 0;
  for (final a in allocs) {
    allocatedBase += (a['qtyInBaseUnit'] as num?)?.toDouble() ??
        (a['qty'] as num?)?.toDouble() ??
        0.0;
  }

  // Private sales bhi minus karo
  double soldBase = 0;
  final String? salesJson =
      await CompanyStore.instance.getString('medicineSalesHistory');
  if (salesJson != null) {
    try {
      final List<dynamic> rawSales = json.decode(salesJson);
      for (final sale in rawSales) {
        final List<dynamic> items = sale['items'] as List<dynamic>? ?? [];
        for (final item in items) {
          if (item['medicineId']?.toString() == mId) {
            soldBase += (item['qtyInBaseUnit'] as num?)?.toDouble() ??
                (item['qty'] as num?)?.toDouble() ??
                0.0;
          }
        }
      }
    } catch (_) {}
  }

  double availBase =
      (totalBaseQty - allocatedBase - soldBase).clamp(0.0, double.infinity);

  // Company farmers
  List<dynamic> rawFarmers =
      await CompanyStore.instance.getJsonList('companyFarmers');
  List<String> farmerOptions = rawFarmers.map((f) {
    String name = f['name']?.toString() ?? 'Unknown';
    String mobile = f['phone']?.toString() ?? 'No Mobile';
    String location = f['district']?.toString() ?? 'No Location';
    return "$name - $mobile - $location";
  }).toList();

  final farmerSearchCtrl = TextEditingController();
  String? selectedFarmer;
  bool dropdownVisible = false;
  String selectedUnit = baseUnit;
  final qtyCtrl = TextEditingController();
  // Rate pre-fill: currentFarmerRate is Rs/baseUnit → convert to Rs/selectedUnit
  // Initially selectedUnit == baseUnit so no conversion needed yet
  final rateCtrl = TextEditingController(
    text: currentFarmerRate > 0
        ? currentFarmerRate.toStringAsFixed(2)
        : '',
  );

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog.fullscreen(
      child: StatefulBuilder(
        builder: (ctx2, setDlg) {
          final double qty = double.tryParse(qtyCtrl.text) ?? 0.0;
          final double qtyBase =
              convertToBase(qty, selectedUnit, baseUnit) ?? qty;
          final double saleRate =
              double.tryParse(rateCtrl.text) ?? 0.0;
          // saleRate is Rs/selectedUnit → convert to Rs/baseUnit for calc
          final double saleRatePerBase =
              priceToBase(saleRate, selectedUnit, baseUnit) ?? saleRate;
          final bool isOver = qtyBase > availBase;
          final double availInSelected =
              convertFromBase(availBase, baseUnit, selectedUnit) ?? availBase;
          // Cost display in selectedUnit (CORRECT: divide)
          final double costInSelected =
              pricePerUnit(weightedAvgCost, baseUnit, selectedUnit) ?? weightedAvgCost;
          final double totalCost = qtyBase * weightedAvgCost;
          final double totalBill = qtyBase * saleRatePerBase;
          final double profit = totalBill - totalCost;
          final bool hasCalc = qty > 0 && saleRate > 0;

          return Scaffold(
            backgroundColor: const Color(0xFFF9FBF9),
            appBar: AppBar(
              backgroundColor: Colors.teal.shade700,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
              title: Text(
                '💊 ${med['name']} Allocate Karo',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
              ),
            ),
            body: Column(
              children: [
                // Top stock bar
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.teal.shade700,
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bacha: ${availBase.toStringAsFixed(3)} $baseUnit',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14),
                      ),
                      if (weightedAvgCost > 0)
                        Text(
                          'Avg Cost: ₹${weightedAvgCost.toStringAsFixed(2)} / $baseUnit',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11),
                        ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Farmer search
                        TextField(
                          controller: farmerSearchCtrl,
                          decoration: InputDecoration(
                            labelText:
                                'Apna Farmer Search Karein *',
                            prefixIcon:
                                const Icon(Icons.search_rounded),
                            suffixIcon: selectedFarmer != null
                                ? const Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.green)
                                : null,
                            border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(10)),
                            helperText: selectedFarmer != null
                                ? '✅ $selectedFarmer'
                                : null,
                            helperMaxLines: 2,
                          ),
                          onChanged: (_) => setDlg(() {
                            dropdownVisible = true;
                            selectedFarmer = null;
                          }),
                        ),
                        if (dropdownVisible &&
                            farmerSearchCtrl.text.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            constraints:
                                const BoxConstraints(maxHeight: 150),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                  color: Colors.teal.shade200),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Builder(builder: (cx) {
                              final q = farmerSearchCtrl.text
                                  .toLowerCase();
                              final filtered = farmerOptions
                                  .where((f) =>
                                      f.toLowerCase().contains(q))
                                  .toList();
                              if (filtered.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text('Koi farmer nahi mila',
                                      style: TextStyle(
                                          color: Colors.grey)),
                                );
                              }
                              return ListView.builder(
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                itemBuilder: (cx2, fi) {
                                  return InkWell(
                                    onTap: () => setDlg(() {
                                      selectedFarmer = filtered[fi];
                                      farmerSearchCtrl.text =
                                          filtered[fi];
                                      dropdownVisible = false;
                                    }),
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 10),
                                      child: Text(filtered[fi],
                                          style: const TextStyle(
                                              fontSize: 13)),
                                    ),
                                  );
                                },
                              );
                            }),
                          ),
                        ],
                        const SizedBox(height: 20),

                        // Unit select for allocation
                        const Text('Unit Chuno:',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: kMedicineUnits.map((u) {
                            final bool enabled =
                                canConvert(u, baseUnit);
                            return ChoiceChip(
                              label: Text(u),
                              selected: selectedUnit == u,
                              onSelected: enabled
                                  ? (v) {
                                      if (v) {
                                        setDlg(() {
                                          final String oldUnit = selectedUnit;
                                          selectedUnit = u;
                                          // Rate convert: Rs/oldUnit → Rs/base → Rs/newUnit
                                          final double curRate =
                                              double.tryParse(rateCtrl.text) ?? 0.0;
                                          if (curRate > 0) {
                                            final double rBase =
                                                priceToBase(curRate, oldUnit, baseUnit) ?? curRate;
                                            final double rNew =
                                                pricePerUnit(rBase, baseUnit, u) ?? rBase;
                                            rateCtrl.text = rNew.toStringAsFixed(2);
                                          } else if (currentFarmerRate > 0) {
                                            // Fallback: use farmer rate from purchase
                                            final double rNew =
                                                pricePerUnit(currentFarmerRate, baseUnit, u) ??
                                                    currentFarmerRate;
                                            rateCtrl.text = rNew.toStringAsFixed(2);
                                          }
                                        });
                                      }
                                    }
                                  : null,
                              selectedColor: Colors.teal.shade700,
                              labelStyle: TextStyle(
                                color: enabled
                                    ? (selectedUnit == u
                                        ? Colors.white
                                        : Colors.black87)
                                    : Colors.grey,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),

                        // Qty + Rate fields
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isOver
                                ? Colors.red.shade50
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: isOver
                                    ? Colors.red.shade300
                                    : Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('💊 ${med['name']}',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Colors.teal.shade900)),
                                  Text(
                                    'Max: ${availInSelected.toStringAsFixed(2)} $selectedUnit',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: isOver
                                            ? Colors.red.shade700
                                            : Colors.green.shade700,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              if (weightedAvgCost > 0)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      top: 3, bottom: 3),
                                  child: Text(
                                    'Cost: ₹${costInSelected.toStringAsFixed(2)} / $selectedUnit',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: qtyCtrl,
                                      keyboardType: const TextInputType
                                          .numberWithOptions(
                                          decimal: true),
                                      onChanged: (_) => setDlg(() {}),
                                      decoration: InputDecoration(
                                        labelText: 'Qty ($selectedUnit)',
                                        isDense: true,
                                        errorText: isOver
                                            ? 'Max ${availInSelected.toStringAsFixed(2)}'
                                            : null,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextField(
                                      controller: rateCtrl,
                                      keyboardType: const TextInputType
                                          .numberWithOptions(
                                          decimal: true),
                                      onChanged: (_) => setDlg(() {}),
                                      decoration: InputDecoration(
                                        labelText:
                                            'Rate (₹/$selectedUnit)',
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (selectedUnit != baseUnit && qty > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '= ${qtyBase.toStringAsFixed(3)} $baseUnit',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.teal.shade700),
                                  ),
                                ),
                              if (hasCalc) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: profit >= 0
                                        ? Colors.teal.shade50
                                        : Colors.orange.shade50,
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    border: Border.all(
                                        color: profit >= 0
                                            ? Colors.teal.shade200
                                            : Colors.orange.shade200),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                          'Cost: ₹${totalCost.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.black54)),
                                      Text(
                                          'Bill: ₹${totalBill.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.black54)),
                                      Text(
                                        profit >= 0
                                            ? '📈 +₹${profit.toStringAsFixed(0)}'
                                            : '📉 -₹${profit.abs().toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: profit >= 0
                                              ? Colors.teal.shade800
                                              : Colors.orange.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Save button
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  color: Colors.white,
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final String farmerName = (selectedFarmer ??
                                farmerSearchCtrl.text)
                            .trim();
                        final double qty2 =
                            double.tryParse(qtyCtrl.text) ?? 0.0;
                        final double qtyBase2 =
                            convertToBase(qty2, selectedUnit, baseUnit) ??
                                qty2;
                        final double rate =
                            double.tryParse(rateCtrl.text) ?? 0.0;

                        if (farmerName.isEmpty) {
                          Get.snackbar('Error', 'Farmer select karein.',
                              backgroundColor: Colors.red,
                              colorText: Colors.white);
                          return;
                        }
                        if (qty2 <= 0) {
                          Get.snackbar('Error', 'Quantity dalein.',
                              backgroundColor: Colors.red,
                              colorText: Colors.white);
                          return;
                        }
                        if (qtyBase2 > availBase) {
                          Get.snackbar(
                            'Error',
                            'Sirf ${availInSelected.toStringAsFixed(2)} $selectedUnit available hai.',
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                          return;
                        }

                        final String allocByRole =
                            await SessionService.currentRole ?? '';
                        final String allocByName =
                            await SessionService.currentName ?? '';

                        // Stock update
                        final String? stockJson = await CompanyStore
                            .instance
                            .getString('medicineStockList');
                        List<dynamic> all = [];
                        if (stockJson != null) {
                          try {
                            all = json.decode(stockJson);
                          } catch (_) {}
                        }
                        for (int i = 0; i < all.length; i++) {
                          if (all[i]['id']?.toString() == mId) {
                            List<dynamic> allocList =
                                all[i]['allocations'] ?? [];
                            allocList.add({
                              'id': DateTime.now()
                                  .millisecondsSinceEpoch
                                  .toString(),
                              'farmerName': farmerName,
                              'qty': qty2,
                              'unit': selectedUnit,
                              'qtyInBaseUnit': qtyBase2,
                              'rate': rate,
                              'allocatedOn':
                                  DateTime.now().toIso8601String(),
                              'allocatedByName': allocByName,
                              'allocatedByRole': allocByRole,
                            });
                            all[i]['allocations'] = allocList;
                            break;
                          }
                        }
                        await CompanyStore.instance.setString(
                            'medicineStockList', json.encode(all));

                        Navigator.pop(ctx);
                        Get.snackbar('Saved ✅',
                            '${qty2.toStringAsFixed(2)} $selectedUnit allocate ho gaya!',
                            backgroundColor: Colors.green,
                            colorText: Colors.white);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Save Allocation',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// 💊 MEDICINE ALLOCATION DETAIL SCREEN — View + Edit + Delete
// ═══════════════════════════════════════════════════════════════════════════
class MedicineAllocationDetailScreen extends StatefulWidget {
  final String medicineId;
  final int allocIndex;
  const MedicineAllocationDetailScreen({
    super.key,
    required this.medicineId,
    required this.allocIndex,
  });

  @override
  State<MedicineAllocationDetailScreen> createState() =>
      _MedicineAllocationDetailScreenState();
}

class _MedicineAllocationDetailScreenState
    extends State<MedicineAllocationDetailScreen> {
  bool _isEditMode = false;
  bool _isLoading = true;
  Map<String, dynamic>? _med;
  Map<String, dynamic>? _alloc;

  final _nameCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  String _selectedUnit = 'ml';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final String? stockJson =
        await CompanyStore.instance.getString('medicineStockList');
    Map<String, dynamic>? found;
    if (stockJson != null) {
      try {
        final List<dynamic> all = json.decode(stockJson);
        for (final m in all) {
          if (m['id']?.toString() == widget.medicineId) {
            found = Map<String, dynamic>.from(m);
            break;
          }
        }
      } catch (_) {}
    }
    if (found == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final allocs = List<Map<String, dynamic>>.from(
      (found['allocations'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map)) ??
          [],
    );
    final alloc = (widget.allocIndex >= 0 &&
            widget.allocIndex < allocs.length)
        ? allocs[widget.allocIndex]
        : <String, dynamic>{};

    _nameCtrl.text = alloc['farmerName']?.toString() ?? '';
    final String unit =
        alloc['unit']?.toString() ?? found['unit']?.toString() ?? 'ml';
    _selectedUnit = unit;
    _qtyCtrl.text = ((alloc['qty'] as num?) ?? 0).toString();
    _rateCtrl.text = ((alloc['rate'] as num?) ?? 0).toString();

    if (mounted) {
      setState(() {
        _med = found;
        _alloc = alloc;
        _isLoading = false;
      });
    }
  }

  double _availForEdit() {
    final String baseUnit = _med!['unit']?.toString() ?? 'ml';
    final double totalBase =
        (_med!['totalBaseQty'] as num?)?.toDouble() ?? 0.0;
    final allocs = List<Map<String, dynamic>>.from(
      (_med!['allocations'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map)) ??
          [],
    );
    double allocElsewhere = 0;
    for (int i = 0; i < allocs.length; i++) {
      if (i == widget.allocIndex) continue;
      allocElsewhere += (allocs[i]['qtyInBaseUnit'] as num?)?.toDouble() ??
          (allocs[i]['qty'] as num?)?.toDouble() ??
          0.0;
    }
    final double availBase = totalBase - allocElsewhere;
    return convertFromBase(availBase, baseUnit, _selectedUnit) ?? availBase;
  }

  Future<void> _save() async {
    final String baseUnit = _med!['unit']?.toString() ?? 'ml';
    final double qty = double.tryParse(_qtyCtrl.text) ?? 0.0;
    final double qtyBase =
        convertToBase(qty, _selectedUnit, baseUnit) ?? qty;
    final double avail = _availForEdit();

    if (qty > avail) {
      Get.snackbar('Error',
          'Sirf ${avail.toStringAsFixed(2)} $baseUnit available hai.',
          backgroundColor: Colors.red, colorText: Colors.white);
      return;
    }

    final String? stockJson =
        await CompanyStore.instance.getString('medicineStockList');
    List<dynamic> all = [];
    if (stockJson != null) {
      try {
        all = json.decode(stockJson);
      } catch (_) {}
    }
    for (int i = 0; i < all.length; i++) {
      if (all[i]['id']?.toString() == widget.medicineId) {
        List<dynamic> allocList = all[i]['allocations'] ?? [];
        if (widget.allocIndex >= 0 &&
            widget.allocIndex < allocList.length) {
          allocList[widget.allocIndex] = {
            ...Map<String, dynamic>.from(allocList[widget.allocIndex]),
            'farmerName': _nameCtrl.text.trim(),
            'qty': qty,
            'unit': _selectedUnit,
            'qtyInBaseUnit': qtyBase,
            'rate': double.tryParse(_rateCtrl.text) ?? 0.0,
            'editedOn': DateTime.now().toIso8601String(),
          };
        }
        all[i]['allocations'] = allocList;
        break;
      }
    }
    await CompanyStore.instance.setString(
        'medicineStockList', json.encode(all));
    Get.back(result: true);
    Get.snackbar('Updated ✅', 'Allocation update ho gaya',
        backgroundColor: Colors.green, colorText: Colors.white);
  }

  Future<void> _delete() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Karein?'),
        content: const Text(
            'Kya aap is allocation ko delete karna chahte hain?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final String? stockJson =
        await CompanyStore.instance.getString('medicineStockList');
    List<dynamic> all = [];
    if (stockJson != null) {
      try {
        all = json.decode(stockJson);
      } catch (_) {}
    }
    for (int i = 0; i < all.length; i++) {
      if (all[i]['id']?.toString() == widget.medicineId) {
        List<dynamic> allocList = all[i]['allocations'] ?? [];
        if (widget.allocIndex >= 0 &&
            widget.allocIndex < allocList.length) {
          allocList.removeAt(widget.allocIndex);
        }
        all[i]['allocations'] = allocList;
        break;
      }
    }
    await CompanyStore.instance.setString(
        'medicineStockList', json.encode(all));
    Get.back(result: true);
    Get.snackbar('Deleted 🗑️', 'Allocation delete ho gaya',
        backgroundColor: Colors.red, colorText: Colors.white);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    if (_med == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.teal.shade700),
        body: const Center(child: Text('Medicine nahi mila.')),
      );
    }

    final String name = _med!['name']?.toString() ?? '-';
    final String baseUnit = _med!['unit']?.toString() ?? 'ml';
    final double weightedAvgCost =
        (_med!['weightedAvgCost'] as num?)?.toDouble() ?? 0.0;
    final double qty = double.tryParse(_qtyCtrl.text) ?? 0.0;
    final double qtyBase =
        convertToBase(qty, _selectedUnit, baseUnit) ?? qty;
    final double rate = double.tryParse(_rateCtrl.text) ?? 0.0;
    final bool isOver = _isEditMode && qty > _availForEdit();
    final double totalCost = qtyBase * weightedAvgCost;
    final double totalBilling = qtyBase * rate;
    final double profit = totalBilling - totalCost;
    final bool hasCalc = qty > 0 && rate > 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.teal.shade700,
        leading: IconButton(
          icon: const Icon(
              Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        title: Text(
          _isEditMode ? 'Edit Allocation' : 'Farmer Allocation',
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: Icon(
                _isEditMode ? Icons.close_rounded : Icons.edit_rounded,
                color: Colors.white),
            onPressed: () =>
                setState(() => _isEditMode = !_isEditMode),
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded, color: Colors.white),
            onPressed: _delete,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.teal.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('💊 $name',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade900)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              enabled: _isEditMode,
              decoration: InputDecoration(
                labelText: 'Farmer Ka Naam',
                prefixIcon: const Icon(Icons.person_rounded),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),

            // Unit select (edit mode only)
            if (_isEditMode) ...[
              const Text('Unit:',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: kMedicineUnits.map((u) {
                  final bool enabled = canConvert(u, baseUnit);
                  return ChoiceChip(
                    label: Text(u),
                    selected: _selectedUnit == u,
                    onSelected: enabled
                        ? (v) {
                            if (v) setState(() => _selectedUnit = u);
                          }
                        : null,
                    selectedColor: Colors.teal.shade700,
                    labelStyle: TextStyle(
                      color: enabled
                          ? (_selectedUnit == u
                              ? Colors.white
                              : Colors.black87)
                          : Colors.grey,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isOver ? Colors.red.shade50 : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: isOver
                        ? Colors.red.shade300
                        : Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('💊 $name',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.teal.shade900)),
                      if (_isEditMode)
                        Text(
                          'Max: ${_availForEdit().toStringAsFixed(2)} $_selectedUnit',
                          style: TextStyle(
                              fontSize: 11,
                              color: isOver
                                  ? Colors.red.shade700
                                  : Colors.green.shade700,
                              fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                  if (weightedAvgCost > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 3, bottom: 3),
                      child: Text(
                          'Avg Cost: ₹${weightedAvgCost.toStringAsFixed(2)} / $baseUnit',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600)),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _qtyCtrl,
                          enabled: _isEditMode,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Qty ($_selectedUnit)',
                            isDense: true,
                            errorText: isOver
                                ? 'Max ${_availForEdit().toStringAsFixed(2)}'
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _rateCtrl,
                          enabled: _isEditMode,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Rate (₹/$_selectedUnit)',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedUnit != baseUnit && qty > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('= ${qtyBase.toStringAsFixed(3)} $baseUnit',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.teal.shade700)),
                    ),
                  if (hasCalc) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: profit >= 0
                            ? Colors.teal.shade50
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: profit >= 0
                                ? Colors.teal.shade200
                                : Colors.orange.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Cost: ₹${totalCost.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54)),
                          Text(
                              'Bill: ₹${totalBilling.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54)),
                          Text(
                            profit >= 0
                                ? '📈 +₹${profit.toStringAsFixed(0)}'
                                : '📉 -₹${profit.abs().toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: profit >= 0
                                  ? Colors.teal.shade800
                                  : Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            if (_alloc?['allocatedByName'] != null &&
                (_alloc!['allocatedByName'] as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    '👤 ${_alloc!['allocatedByRole'] ?? ''}: ${_alloc!['allocatedByName']}',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ),
            if (_alloc?['allocatedOn'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    '🕒 ${formatHistoryDateTime(_alloc!['allocatedOn']?.toString())}',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ),

            if (_isEditMode) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Save Changes',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
