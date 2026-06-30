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
                            () => CategoryHistoryScreen(
                              title: 'Feed Purchase',
                              emoji: '🌾',
                              themeColor: Colors.blue.shade700,
                              historyPrefsKey: 'feedPurchaseHistory',
                              dateKey: 'date',
                              onAddTap: onFeedTap,
                              addButtonLabel: 'Naya Feed Purchase',
                              emptyMessage: 'Koi record nahi.',
                              itemBuilder: (context, entry) => historyEntryCard(
                                title: entry['company'] ?? '-',
                                subtitle:
                                    'S: ${entry['starter']['bags']} | G: ${entry['grower']['bags']} | F: ${entry['finisher']['bags']}',
                                amountLabel:
                                    '₹${(entry['grandTotal'] as num).toDouble().toStringAsFixed(2)}',
                                entry: entry,
                                dateKey: 'date',
                                color: Colors.blue.shade700,
                              ),
                            ),
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
                            () => CategoryHistoryScreen(
                              title: 'Medicine Purchase',
                              emoji: '💊',
                              themeColor: Colors.teal.shade700,
                              historyPrefsKey: 'medicineStockList',
                              dateKey: 'createdOn',
                              onAddTap: onMedicineTap,
                              addButtonLabel: 'Naya Medicine Add Karo',
                              emptyMessage: 'Koi record nahi.',
                              itemBuilder: (context, entry) => historyEntryCard(
                                title: entry['name'] ?? '-',
                                subtitle:
                                    'Quantity: ${entry['totalQuantity']} ${entry['unit']}',
                                amountLabel:
                                    '₹${(entry['totalPrice'] as num).toDouble().toStringAsFixed(2)}',
                                entry: entry,
                                dateKey: 'createdOn',
                                color: Colors.teal.shade700,
                              ),
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
