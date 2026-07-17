import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';
import 'package:poultrypro/services/company_store.dart';
import 'package:poultrypro/services/session_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 🔗 SHARED HELPERS — Farmer ka batch dhoondhna / naya batch ID banana
// (Chicks/Feed/Medicine teeno allocation flows yahi use karte hain, taaki
// batch-creation ka pattern farmer_profile_screen.dart jaisa hi rahe.)
// ═══════════════════════════════════════════════════════════════════════════

const List<String> kRunningBatchStatuses = [
  'ACTIVE',
  'LIFTING READY',
  'PARTIAL LIFTED',
];

/// Farmer ke batches mein se abhi "running" (not completed) batch dhoondo.
/// Null aata hai agar koi running batch nahi hai (ya batches hi nahi hain).
Map<String, dynamic>? findRunningBatch(Map<String, dynamic> farmer) {
  final batches = (farmer['batches'] as List?) ?? [];
  for (var b in batches) {
    final status = (b['status'] ?? '').toString().toUpperCase();
    if (kRunningBatchStatuses.contains(status)) {
      return Map<String, dynamic>.from(b as Map);
    }
  }
  return null;
}

/// Farmer ke COMPLETED (ended) batches ki list — purane/back-batch select
/// karne ke liye (Feed/Medicine allocation mein use hota hai).
List<Map<String, dynamic>> findCompletedBatches(Map<String, dynamic> farmer) {
  final batches = (farmer['batches'] as List?) ?? [];
  return batches
      .where((b) => (b['status'] ?? '').toString().toUpperCase() == 'COMPLETED')
      .map((b) => Map<String, dynamic>.from(b as Map))
      .toList();
}

/// farmer_profile_screen.dart jaisa hi Batch ID format:
/// "<3-letter-prefix>001-LOT-<lotNumber padded>"
String generateBatchId(Map<String, dynamic> farmer) {
  final batches = (farmer['batches'] as List?) ?? [];
  int lotNumber = batches.length + 1;
  String farmerName = farmer['name']?.toString() ?? 'FAR';
  String prefix = farmerName.trim().length >= 3
      ? farmerName.trim().substring(0, 3).toUpperCase()
      : farmerName.trim().toUpperCase().padRight(3, 'X');
  return '${prefix}001-LOT-${lotNumber.toString().padLeft(3, '0')}';
}

/// ✅ NEW: Purchase entries mein date ISO format ("2026-07-08T13:40...")
/// mein save hoti hai, lekin batch ka "startDate" hamesha "dd/MM/yyyy"
/// format mein hona chahiye (farmer_profile_screen.dart jaisa) — warna
/// Batch Tracking Details screen mein overflow/galat calculation hoti hai.
String formatDateForBatch(String? rawDate) {
  if (rawDate == null || rawDate.trim().isEmpty) {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  }
  try {
    final d = DateTime.parse(rawDate);
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  } catch (_) {
    // Already "dd/MM/yyyy" jaisa kisi aur format mein ho, waisa hi rehne do
    return rawDate;
  }
}

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

  // SharedPreferences se load karne ke liye (SAFE VERSION)
  factory ChicksPurchase.fromMap(Map<String, dynamic> map) {
    // Ye helper function numbers aur strings dono ko safely double mein convert karega
    double parseDouble(dynamic val) {
      if (val == null) return 0.0;
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? 0.0;
      return 0.0;
    }

    // Ye helper function allocations ko safely parse karega
    List<Map<String, dynamic>> parseAllocations(dynamic allocData) {
      if (allocData is List) {
        return allocData.map((e) {
          if (e is Map) return Map<String, dynamic>.from(e);
          return <String, dynamic>{};
        }).toList();
      }
      return [];
    }

    return ChicksPurchase(
      company: map['company']?.toString() ?? '',
      breed: map['breed']?.toString() ?? '',
      totalQty: parseDouble(map['quantity']),
      rate: parseDouble(map['rate']),
      effectiveRate: parseDouble(map['effectiveRate']),
      totalAmount: parseDouble(map['totalAmount']),
      date: map['date']?.toString() ?? '',
      addedByName: map['addedByName']?.toString() ?? '',
      addedByRole: map['addedByRole']?.toString() ?? '',
      allocations: parseAllocations(map['allocations']),
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

                            // ✅ NEW: Batch ID badge — sirf Company allocation
                            // jo kisi batch se linked hai
                            if (allocType == 'Company' &&
                                (thisAlloc['batchId']?.toString().isNotEmpty ??
                                    false)) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.purple.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.purple.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.badge_rounded,
                                      size: 16,
                                      color: Colors.purple.shade700,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Batch ID: ${thisAlloc['batchId']}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Colors.purple.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],

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
    // ✅ NEW: display-string → farmerId map, taaki batch auto-link/create ke
    // liye asli farmer record dhoondh sakein (sirf naam se match risky hai).
    final Map<String, String> farmerDisplayToId = {};
    for (int fi = 0; fi < rawFarmers.length; fi++) {
      farmerDisplayToId[farmerOptions[fi]] =
          rawFarmers[fi]['id']?.toString() ?? '';
    }

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
        'farmerId': null,
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
                                          alloc['farmerId'] = null;
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
                                                        alloc['farmerId'] =
                                                            farmerDisplayToId[option];
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
                              // ✅ NEW: BATCH LINK/CREATE PRE-FLIGHT CHECK
                              // Company allocation ke liye farmer ka batch
                              // dhoondo/validate karo SAVE se pehle — taaki
                              // partial save na ho agar koi block fail ho.
                              // ══════════════════════════════════════
                              List<dynamic> freshFarmersForBatchCheck =
                                  await CompanyStore.instance.getJsonList(
                                    'companyFarmers',
                                  );
                              for (int i = 0; i < allocations.length; i++) {
                                var a = allocations[i];
                                double compQty =
                                    double.tryParse(
                                      (a['companyQtyCtrl']
                                              as TextEditingController)
                                          .text,
                                    ) ??
                                    0.0;
                                if (compQty <= 0) continue;

                                String? farmerId = a['farmerId']?.toString();
                                if (farmerId == null || farmerId.isEmpty) {
                                  Get.snackbar(
                                    'Farmer Select Karein ⚠️',
                                    'Block #${i + 1}: Kripya dropdown list se hi farmer select karein (batch link karne ke liye zaroori hai).',
                                    backgroundColor: Colors.red,
                                    colorText: Colors.white,
                                  );
                                  return;
                                }

                                Map<String, dynamic>? farmerMap;
                                for (var f in freshFarmersForBatchCheck) {
                                  if (f['id']?.toString() == farmerId) {
                                    farmerMap = Map<String, dynamic>.from(f);
                                    break;
                                  }
                                }
                                if (farmerMap == null) {
                                  Get.snackbar(
                                    'Error ⚠️',
                                    'Block #${i + 1}: Farmer record nahi mila.',
                                    backgroundColor: Colors.red,
                                    colorText: Colors.white,
                                  );
                                  return;
                                }

                                final runningBatch = findRunningBatch(
                                  farmerMap,
                                );
                                if (runningBatch != null) {
                                  double runningChicks =
                                      (runningBatch['chicksCount'] as num?)
                                          ?.toDouble() ??
                                      0.0;
                                  if (runningChicks != compQty) {
                                    Get.snackbar(
                                      'Batch Mismatch ⚠️',
                                      'Block #${i + 1}: ${farmerMap['name']} ka running batch (${runningBatch['batchId']}) mein $runningChicks chicks hain, lekin aap $compQty allocate kar rahe hain. Dono same hone chahiye — allocate nahi ho sakta.',
                                      backgroundColor: Colors.red,
                                      colorText: Colors.white,
                                      duration: const Duration(seconds: 5),
                                    );
                                    return;
                                  }
                                  // ✅ Match ho gaya — isi running batch se link hoga
                                  a['_batchAction'] = 'link';
                                  a['_batchId'] = runningBatch['batchId'];
                                } else {
                                  // Koi running batch nahi — naya batch banega
                                  a['_batchAction'] = 'create';
                                  a['_batchId'] = null;
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

                              // ✅ NEW: Company farmers list bhi load karo —
                              // isi mein batch link/create hoga.
                              List<Map<String, dynamic>> farmersForBatchWrite =
                                  await CompanyStore.instance.getJsonList(
                                    'companyFarmers',
                                  );
                              bool farmersListChanged = false;

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

                                      // ✅ NEW: Batch link/create — pre-flight
                                      // check mein already decide ho chuka hai.
                                      String? linkedBatchId = a['_batchId'];
                                      if (a['_batchAction'] == 'create') {
                                        final String? farmerId = a['farmerId']
                                            ?.toString();
                                        for (var f in farmersForBatchWrite) {
                                          if (f['id']?.toString() == farmerId) {
                                            if (f['batches'] == null) {
                                              f['batches'] = [];
                                            }
                                            final String newBatchId =
                                                generateBatchId(
                                                  Map<String, dynamic>.from(f),
                                                );
                                            final double compRate =
                                                double.tryParse(
                                                  (a['companyRateCtrl']
                                                          as TextEditingController)
                                                      .text,
                                                ) ??
                                                0.0;
                                            f['batches'].add({
                                              'id': newBatchId,
                                              'batchId': newBatchId,
                                              'lotNumber':
                                                  f['batches'].length + 1,
                                              'chicksCount': compQty.toInt(),
                                              'chicksRate': compRate,
                                              'totalChicksCost':
                                                  (compQty * compRate)
                                                      .toStringAsFixed(2),
                                              'startDate': formatDateForBatch(
                                                purchaseEntry['date']
                                                    ?.toString(),
                                              ),
                                              'status': 'ACTIVE',
                                              'dailyEntries': [],
                                            });
                                            linkedBatchId = newBatchId;
                                            farmersListChanged = true;
                                            break;
                                          }
                                        }
                                      }

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
                                        'farmerId': a['farmerId'],
                                        'batchId':
                                            linkedBatchId, // ✅ NEW: batch number allocation ke saath save
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

                              // ✅ NEW: agar naya batch bana ho to farmers list
                              // bhi persist karo.
                              if (farmersListChanged) {
                                await CompanyStore.instance.saveJsonList(
                                  'companyFarmers',
                                  farmersForBatchWrite,
                                );
                              }

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

  // SAFE LOAD — ek corrupt entry se puri list crash nahi hogi
  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final String? jsonStr = await CompanyStore.instance.getString(
      'chicksPurchaseHistory',
    );
    if (jsonStr != null) {
      try {
        final List<dynamic> raw = json.decode(jsonStr);
        List<ChicksPurchase> loadedEntries = [];

        for (var e in raw) {
          if (e is Map) {
            try {
              loadedEntries.add(
                ChicksPurchase.fromMap(Map<String, dynamic>.from(e)),
              );
            } catch (err) {
              debugPrint(
                'Chicks parse error: $err',
              ); // Kisi ek error pe puri list crash nahi hogi
            }
          }
        }
        _entries = loadedEntries;
      } catch (_) {}
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // ✅ NEW: Ek lot ko date se dobara fresh load karo (edit/delete ke baad
  // sub-list screen refresh karne ke liye).
  Future<ChicksPurchase?> _refetchByDate(String date) async {
    await _loadHistory();
    try {
      return _entries.firstWhere((e) => e.date == date);
    } catch (_) {
      return null;
    }
  }

  // ✅ NEW: Farmer Allocation / Private Buyer summary row (Feed/Medicine
  // jaisa hi look) — tap karke filtered sub-list khulti hai.
  Widget _allocSummaryNavRow({
    required IconData icon,
    required String label,
    required MaterialColor color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.shade100),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color.shade900,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color.shade400),
          ],
        ),
      ),
    );
  }

  // ✅ NEW: Us lot ke sirf ek type (Company/Private) ke allocations ki
  // filtered sub-list screen khulo — tap karke wahi purana edit/delete
  // detail dialog khulta hai.
  void _openFilteredAllocationList(ChicksPurchase purchase, String filterType) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (routeContext) => _ChicksAllocSubListScreen(
          initialPurchase: purchase,
          filterType: filterType,
          onShowAllocation: widget.onShowAllocation,
          refetch: () => _refetchByDate(purchase.date),
        ),
      ),
    );
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

                            // ── ✅ NEW: Ab inline mixed list nahi — 2 alag
                            // buttons (Farmer Allocation / Private Buyer),
                            // Feed/Medicine jaisa hi pattern. Tap karne par
                            // us lot ke sirf usi type ke allocations ki list
                            // khulti hai, aur wahan se tap karke same
                            // edit/delete detail dialog khulta hai.
                            if (purchase.allocations.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  10,
                                  14,
                                  0,
                                ),
                                child: Column(
                                  children: [
                                    _allocSummaryNavRow(
                                      icon: Icons.people_alt_rounded,
                                      label:
                                          'Farmer Allocation (${purchase.allocations.where((a) => a['type'] == 'Company').length})',
                                      color: Colors.blue,
                                      onTap: () => _openFilteredAllocationList(
                                        purchase,
                                        'Company',
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _allocSummaryNavRow(
                                      icon: Icons.storefront_rounded,
                                      label:
                                          'Private Buyer (${purchase.allocations.where((a) => a['type'] == 'Private').length})',
                                      color: Colors.green,
                                      onTap: () => _openFilteredAllocationList(
                                        purchase,
                                        'Private',
                                      ),
                                    ),
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
// 🧾 CHICKS ALLOCATION SUB-LIST — Ek lot ke sirf ek type (Farmer/Private)
// ke allocations ki filtered list. Tap karke wahi purana edit/delete detail
// dialog khulta hai (widget.onShowAllocation), koi naya dialog nahi likha.
// ═══════════════════════════════════════════════════════════════════════════
class _ChicksAllocSubListScreen extends StatefulWidget {
  final ChicksPurchase initialPurchase;
  final String filterType; // 'Company' ya 'Private'
  final void Function(
    BuildContext context,
    Map<String, dynamic> entry,
    VoidCallback onSaved, {
    bool isInformationMode,
    int entryIndex,
  })
  onShowAllocation;
  final Future<ChicksPurchase?> Function() refetch;

  const _ChicksAllocSubListScreen({
    required this.initialPurchase,
    required this.filterType,
    required this.onShowAllocation,
    required this.refetch,
  });

  @override
  State<_ChicksAllocSubListScreen> createState() =>
      _ChicksAllocSubListScreenState();
}

class _ChicksAllocSubListScreenState extends State<_ChicksAllocSubListScreen> {
  late ChicksPurchase _purchase;

  @override
  void initState() {
    super.initState();
    _purchase = widget.initialPurchase;
  }

  Future<void> _reload() async {
    final fresh = await widget.refetch();
    if (fresh != null && mounted) {
      setState(() => _purchase = fresh);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isFarmer = widget.filterType == 'Company';
    final List<MapEntry<int, Map<String, dynamic>>> filtered = [];
    for (int i = 0; i < _purchase.allocations.length; i++) {
      if (_purchase.allocations[i]['type'] == widget.filterType) {
        filtered.add(MapEntry(i, _purchase.allocations[i]));
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.orange.shade800,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isFarmer ? '🧑 Farmer Allocations' : '🛒 Private Buyers',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
      body: filtered.isEmpty
          ? const Center(child: Text('Koi record nahi.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              itemBuilder: (context, idx) {
                final allocIndex = filtered[idx].key;
                final alloc = filtered[idx].value;
                double pending = 0.0;
                if (!isFarmer) {
                  double qty = (alloc['qty'] as num?)?.toDouble() ?? 0.0;
                  double rate = (alloc['rate'] as num?)?.toDouble() ?? 0.0;
                  double paid = (alloc['paid'] as num?)?.toDouble() ?? 0.0;
                  pending = (qty * rate) - paid;
                }
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    widget.onShowAllocation(
                      context,
                      _purchase.toMap(),
                      _reload,
                      isInformationMode: true,
                      entryIndex: allocIndex,
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isFarmer
                          ? Colors.blue.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isFarmer
                            ? Colors.blue.shade200
                            : Colors.green.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    isFarmer ? '🧑 ' : '🛒 ',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${alloc['name']}',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${(alloc['qty'] as num).toStringAsFixed(0)} Chicks',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (!isFarmer) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: pending > 0
                                          ? Colors.red.shade100
                                          : Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      pending > 0
                                          ? 'Due: ₹${pending.toStringAsFixed(0)}'
                                          : 'Paid',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: pending > 0
                                            ? Colors.red.shade900
                                            : Colors.green.shade900,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: Colors.grey.shade500,
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (alloc['batchId']?.toString().isNotEmpty ?? false)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '🏷️ Batch: ${alloc['batchId']}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade700,
                              ),
                            ),
                          ),
                        if ((alloc['allocatedByName']?.toString() ?? '')
                            .isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '👤 ${alloc['allocatedByRole'] != null && (alloc['allocatedByRole'] as String).isNotEmpty ? "${alloc['allocatedByRole']}: " : ""}${alloc['allocatedByName']}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        if (alloc['allocatedOn'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '🕒 ${formatHistoryDateTime(alloc['allocatedOn']?.toString())}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🌾 FEED STOCK SYSTEM — Medicine jaisa hi pattern: 3 FIXED running-stock
// entities (Starter/Grower/Finisher). Har purchase isi mein add hota hai,
// aur Farmer Allocation bhi isi se hoti hai (per-type Purchase History +
// Farmer Allocations, jaisa Medicine mein hai).
//
// NOTE: Purani "Private Sales" (feedSalesHistory, lot-name se match) feature
// yahan carry-forward nahi ki — Gopi ke spec mein sirf 2 sections maange the
// (Purchase History + Farmer Allocations), Private Buyers nahi. Agar wo bhi
// chahiye ho to sales_screen.dart dekhna padega (uploaded nahi hai abhi).
// ═══════════════════════════════════════════════════════════════════════════

const List<String> kFeedTypeIds = ['starter', 'grower', 'finisher'];
const Map<String, String> kFeedTypeNames = {
  'starter': 'Starter Feed',
  'grower': 'Grower Feed',
  'finisher': 'Finisher Feed',
};
const Map<String, String> kFeedTypeEmoji = {
  'starter': '🐣',
  'grower': '🐥',
  'finisher': '🐔',
};

/// Ek baar purane 'feedPurchaseHistory' lots ko naye 3-entity system mein
/// migrate karta hai (Gopi ke confirm kiye anusaar) — allocations bhi split
/// karke migrate hoti hain (ek purani allocation jisme S+G+F teeno ho, wo
/// teeno type ki apni-apni list mein chali jaati hai). Dobara migration nahi
/// chalta agar ek baar ho chuka ho.
Future<List<Map<String, dynamic>>> ensureFeedStockMigrated() async {
  List<Map<String, dynamic>> stock = await CompanyStore.instance.getJsonList(
    'feedStockList',
  );

  for (final id in kFeedTypeIds) {
    if (!stock.any((s) => s['id'] == id)) {
      stock.add({
        'id': id,
        'name': kFeedTypeNames[id],
        'unit': 'bag',
        'totalBags': 0.0,
        'weightedAvgCost': 0.0,
        'purchaseHistory': [],
        'allocations': [],
        'privateSales': [],
      });
    }
  }

  final bool migrationDone = stock.any((s) => s['migratedFromOldLots'] == true);
  if (!migrationDone) {
    List<Map<String, dynamic>> oldLots = await CompanyStore.instance
        .getJsonList('feedPurchaseHistory');
    for (final lot in oldLots) {
      final String company = lot['company']?.toString() ?? '';
      final String date =
          lot['date']?.toString() ?? DateTime.now().toIso8601String();
      final String addedByName = lot['addedByName']?.toString() ?? '';
      final String addedByRole = lot['addedByRole']?.toString() ?? '';

      for (final id in kFeedTypeIds) {
        final typeData = lot[id] as Map?;
        final double bags = (typeData?['bags'] as num?)?.toDouble() ?? 0.0;
        final double perBagPrice =
            (typeData?['perBagPrice'] as num?)?.toDouble() ?? 0.0;
        if (bags <= 0) continue;

        final entry = stock.firstWhere((s) => s['id'] == id);
        final double oldTotal = (entry['totalBags'] as num?)?.toDouble() ?? 0.0;
        final double oldAvg =
            (entry['weightedAvgCost'] as num?)?.toDouble() ?? 0.0;
        final double newTotal = oldTotal + bags;
        final double newAvg = newTotal > 0
            ? ((oldTotal * oldAvg) + (bags * perBagPrice)) / newTotal
            : perBagPrice;
        entry['totalBags'] = newTotal;
        entry['weightedAvgCost'] = newAvg;
        final hist = (entry['purchaseHistory'] as List?) ?? [];
        hist.add({
          'id': '${DateTime.now().microsecondsSinceEpoch}_$id',
          'company': company,
          'bags': bags,
          'perBagPrice': perBagPrice,
          'date': date,
          'addedByName': addedByName,
          'addedByRole': addedByRole,
          'migrated': true,
        });
        entry['purchaseHistory'] = hist;
      }

      final List<dynamic> oldAllocs = lot['allocations'] ?? [];
      for (final a in oldAllocs) {
        for (final id in kFeedTypeIds) {
          final double qty = (a['${id}Qty'] as num?)?.toDouble() ?? 0.0;
          if (qty <= 0) continue;
          final entry = stock.firstWhere((s) => s['id'] == id);
          final allocs = (entry['allocations'] as List?) ?? [];
          allocs.add({
            'id': '${a['id'] ?? DateTime.now().microsecondsSinceEpoch}_$id',
            'farmerName': a['farmerName'],
            'farmerId': a['farmerId'],
            'batchId': a['batchId'],
            'qty': qty,
            'rate': a['${id}Rate'] ?? 0.0,
            'allocatedOn': a['allocatedOn'],
            'allocatedByName': a['allocatedByName'],
            'allocatedByRole': a['allocatedByRole'],
            'migrated': true,
          });
          entry['allocations'] = allocs;
        }
      }
    }
    for (final s in stock) {
      s['migratedFromOldLots'] = true;
    }
  }

  await CompanyStore.instance.saveJsonList('feedStockList', stock);
  return stock;
}

double computeFeedRemaining(Map<String, dynamic> feedType) {
  final double total = (feedType['totalBags'] as num?)?.toDouble() ?? 0.0;
  double allocated = 0.0;
  for (final a in ((feedType['allocations'] as List?) ?? [])) {
    allocated += (a['qty'] as num?)?.toDouble() ?? 0.0;
  }
  double sold = 0.0;
  for (final s in ((feedType['privateSales'] as List?) ?? [])) {
    sold += (s['qty'] as num?)?.toDouble() ?? 0.0;
  }
  return (total - allocated - sold).clamp(0.0, double.infinity);
}

/// ✅ NEW: Private (non-farmer) feed sale record karo — sales_screen.dart
/// se call hota hai. Medicine ke private-buyer pattern jaisa, bas ab feed
/// bhi persistent per-type stock (feedStockList) se link hai, lot se nahi.
Future<void> recordFeedPrivateSale({
  required String feedTypeId,
  required String buyerName,
  required String mobile,
  required double qty,
  required double rate,
  required double paidAmount,
  String addedByName = '',
  String addedByRole = '',
}) async {
  List<Map<String, dynamic>> stock = await ensureFeedStockMigrated();
  final idx = stock.indexWhere((s) => s['id'] == feedTypeId);
  if (idx == -1) return;
  final sales = (stock[idx]['privateSales'] as List?) ?? [];
  sales.add({
    'id': DateTime.now().millisecondsSinceEpoch.toString(),
    'buyerName': buyerName,
    'mobile': mobile,
    'qty': qty,
    'rate': rate,
    'paidAmount': paidAmount,
    'date': DateTime.now().toIso8601String(),
    'addedByName': addedByName,
    'addedByRole': addedByRole,
  });
  stock[idx]['privateSales'] = sales;
  await CompanyStore.instance.saveJsonList('feedStockList', stock);
}

/// Feed purchase add karo — Medicine ke `addOrUpdateMedicinePurchase` jaisa
/// hi weighted-average pattern, bas unit hamesha "bag" fixed hai.
Future<void> addOrUpdateFeedPurchase({
  required String feedTypeId,
  required double bags,
  required double perBagPrice,
  required String company,
  String addedByName = '',
  String addedByRole = '',
}) async {
  List<Map<String, dynamic>> stock = await ensureFeedStockMigrated();
  final idx = stock.indexWhere((s) => s['id'] == feedTypeId);
  if (idx == -1) return;
  final entry = stock[idx];
  final double oldTotal = (entry['totalBags'] as num?)?.toDouble() ?? 0.0;
  final double oldAvg = (entry['weightedAvgCost'] as num?)?.toDouble() ?? 0.0;
  final double newTotal = oldTotal + bags;
  final double newAvg = newTotal > 0
      ? ((oldTotal * oldAvg) + (bags * perBagPrice)) / newTotal
      : perBagPrice;
  entry['totalBags'] = newTotal;
  entry['weightedAvgCost'] = newAvg;
  final hist = (entry['purchaseHistory'] as List?) ?? [];
  hist.add({
    'id': DateTime.now().millisecondsSinceEpoch.toString(),
    'company': company,
    'bags': bags,
    'perBagPrice': perBagPrice,
    'date': DateTime.now().toIso8601String(),
    'addedByName': addedByName,
    'addedByRole': addedByRole,
  });
  entry['purchaseHistory'] = hist;
  stock[idx] = entry;
  await CompanyStore.instance.saveJsonList('feedStockList', stock);
}

// ═══════════════════════════════════════════════════════════════════════════
// 🌾 FEED HISTORY SCREEN — Medicine jaisa 3 running-stock cards
// ═══════════════════════════════════════════════════════════════════════════
class FeedHistoryScreen extends StatefulWidget {
  final Future<void> Function() onFeedTap;
  const FeedHistoryScreen({super.key, required this.onFeedTap});

  @override
  State<FeedHistoryScreen> createState() => _FeedHistoryScreenState();
}

class _FeedHistoryScreenState extends State<FeedHistoryScreen> {
  List<Map<String, dynamic>> _feedStock = [];
  bool _isLoading = true;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final stock = await ensureFeedStockMigrated();
    stock.sort(
      (a, b) => kFeedTypeIds
          .indexOf(a['id'])
          .compareTo(kFeedTypeIds.indexOf(b['id'])),
    );
    if (mounted) {
      setState(() {
        _feedStock = stock;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Get.back(result: _changed);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: Colors.blue.shade700,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
            ),
            onPressed: () => Get.back(result: _changed),
          ),
          title: const Row(
            children: [
              Text('🌾', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text('Feed Purchase'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await widget.onFeedTap();
                        _changed = true;
                        _load();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                      ),
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text(
                        'Naya Feed Purchase',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final result = await _showFeedAllocateToFarmerDialog(
                          context,
                          _feedStock,
                        );
                        if (result == true) {
                          _changed = true;
                          _load();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                      ),
                      icon: const Icon(
                        Icons.person_add_alt_1_rounded,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Allocate to Farmer',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._feedStock.map(
                    (f) => _FeedRunningStockCard(
                      feedType: f,
                      onChanged: () {
                        _changed = true;
                        _load();
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Running stock card (Medicine's _MedicineRunningLotCard jaisa) ──
class _FeedRunningStockCard extends StatelessWidget {
  final Map<String, dynamic> feedType;
  final VoidCallback onChanged;
  const _FeedRunningStockCard({
    required this.feedType,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final String id = feedType['id']?.toString() ?? '';
    final String name =
        feedType['name']?.toString() ?? kFeedTypeNames[id] ?? id;
    final String emoji = kFeedTypeEmoji[id] ?? '🌾';
    final double total = (feedType['totalBags'] as num?)?.toDouble() ?? 0.0;
    final double remaining = computeFeedRemaining(feedType);
    final double avgCost =
        (feedType['weightedAvgCost'] as num?)?.toDouble() ?? 0.0;
    final int purchaseCount =
        ((feedType['purchaseHistory'] as List?) ?? []).length;
    final int allocCount = ((feedType['allocations'] as List?) ?? []).length;
    final int privateSaleCount =
        ((feedType['privateSales'] as List?) ?? []).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              children: [
                Text(emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Total Kharida: ${total.toStringAsFixed(0)} bag',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      Text(
                        'Bacha: ${remaining.toStringAsFixed(0)} bag',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: remaining > 0
                              ? Colors.green.shade700
                              : Colors.grey,
                        ),
                      ),
                      if (avgCost > 0)
                        Text(
                          'Avg Cost: ₹${avgCost.toStringAsFixed(2)} / bag',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black45,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _navRow(
                  icon: Icons.history_rounded,
                  label: 'Purchase History ($purchaseCount baar kharida)',
                  onTap: () async {
                    await Get.to(
                      () => FeedPurchaseHistoryScreen(feedTypeId: id),
                    );
                    onChanged();
                  },
                ),
                const SizedBox(height: 8),
                _navRow(
                  icon: Icons.people_alt_rounded,
                  label: 'Farmer Allocations ($allocCount)',
                  onTap: () async {
                    await Get.to(
                      () => FeedFarmerAllocationsListScreen(feedTypeId: id),
                    );
                    onChanged();
                  },
                ),
                const SizedBox(height: 8),
                _navRow(
                  icon: Icons.storefront_rounded,
                  label: 'Private Buyers ($privateSaleCount)',
                  onTap: () async {
                    await Get.to(
                      () => FeedPrivateBuyersListScreen(feedTypeId: id),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.blue.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade900,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.blue.shade400),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🌾 ALLOCATE TO FARMER — single farmer, teeno type ek session mein optional
// ═══════════════════════════════════════════════════════════════════════════
Future<bool?> _showFeedAllocateToFarmerDialog(
  BuildContext context,
  List<Map<String, dynamic>> feedStock,
) async {
  double availFor(String id) {
    final entry = feedStock.firstWhere((s) => s['id'] == id, orElse: () => {});
    if (entry.isEmpty) return 0.0;
    return computeFeedRemaining(entry);
  }

  double avgCostFor(String id) {
    final entry = feedStock.firstWhere((s) => s['id'] == id, orElse: () => {});
    return (entry['weightedAvgCost'] as num?)?.toDouble() ?? 0.0;
  }

  final double availS = availFor('starter');
  final double availG = availFor('grower');
  final double availF = availFor('finisher');

  double defaultBillingPerBag = 42.0 * 50.0;
  double feedKgPerBagCfg = 50.0;
  try {
    final prefs = await SharedPreferences.getInstance();
    final String? r1Json = prefs.getString('rule1SettlementConfig');
    if (r1Json != null) {
      final Map<String, dynamic> r1 = json.decode(r1Json);
      final double bigFeedRate = (r1['bigFeedRate'] ?? 42.0).toDouble();
      final double bigKgPerBag = (r1['bigKgPerBag'] ?? 50.0).toDouble();
      defaultBillingPerBag = bigFeedRate * bigKgPerBag;
      feedKgPerBagCfg = bigKgPerBag;
    }
  } catch (_) {}

  List<dynamic> rawFarmers = await CompanyStore.instance.getJsonList(
    'companyFarmers',
  );
  List<String> farmerOptions = rawFarmers.map((f) {
    String name = f['name']?.toString() ?? 'Unknown';
    String mobile = f['phone']?.toString() ?? 'No Mobile';
    String location = f['district']?.toString() ?? 'No Location';
    return "$name - $mobile - $location";
  }).toList();
  final Map<String, String> farmerDisplayToId = {};
  for (int fi = 0; fi < rawFarmers.length; fi++) {
    farmerDisplayToId[farmerOptions[fi]] =
        rawFarmers[fi]['id']?.toString() ?? '';
  }

  final farmerSearchCtrl = TextEditingController();
  String? selectedFarmer;
  String? selectedFarmerId;
  bool dropdownVisible = false;

  final starterQtyCtrl = TextEditingController();
  final starterRateCtrl = TextEditingController(
    text: defaultBillingPerBag.toStringAsFixed(2),
  );
  final growerQtyCtrl = TextEditingController();
  final growerRateCtrl = TextEditingController(
    text: defaultBillingPerBag.toStringAsFixed(2),
  );
  final finisherQtyCtrl = TextEditingController();
  final finisherRateCtrl = TextEditingController(
    text: defaultBillingPerBag.toStringAsFixed(2),
  );

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog.fullscreen(
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return Scaffold(
            backgroundColor: const Color(0xFFF9FBF9),
            appBar: AppBar(
              backgroundColor: Colors.orange.shade800,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context, false),
              ),
              title: const Text(
                'Feed Allocate Karo',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            body: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.orange.shade800,
                  width: double.infinity,
                  child: Text(
                    'Bacha: S ${availS.toStringAsFixed(0)} | G ${availG.toStringAsFixed(0)} | F ${availF.toStringAsFixed(0)} Bag',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: farmerSearchCtrl,
                          decoration: InputDecoration(
                            labelText:
                                'Apna Farmer Search Karein (Naam, Mobile ya Jagah) *',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: selectedFarmer != null
                                ? const Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.green,
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            helperText: selectedFarmer != null
                                ? '✅ Selected: $selectedFarmer'
                                : 'Type karein aur neeche se select karein',
                            helperMaxLines: 2,
                          ),
                          onChanged: (_) => setModalState(() {
                            dropdownVisible = true;
                            selectedFarmer = null;
                            selectedFarmerId = null;
                          }),
                        ),
                        if (dropdownVisible &&
                            farmerSearchCtrl.text.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 160),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.orange.shade200),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Builder(
                              builder: (ctx) {
                                final query = farmerSearchCtrl.text
                                    .toLowerCase();
                                final filtered = farmerOptions
                                    .where(
                                      (f) => f.toLowerCase().contains(query),
                                    )
                                    .toList();
                                if (filtered.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text(
                                      'Koi farmer nahi mila',
                                      style: TextStyle(color: Colors.grey),
                                    ),
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
                                        selectedFarmerId =
                                            farmerDisplayToId[option];
                                        farmerSearchCtrl.text = option;
                                        dropdownVisible = false;
                                      }),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        child: Text(
                                          option,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        _feedAllocInput(
                          'Starter',
                          starterQtyCtrl,
                          starterRateCtrl,
                          availS,
                          avgCostFor('starter'),
                          setModalState,
                        ),
                        _feedAllocInput(
                          'Grower',
                          growerQtyCtrl,
                          growerRateCtrl,
                          availG,
                          avgCostFor('grower'),
                          setModalState,
                        ),
                        _feedAllocInput(
                          'Finisher',
                          finisherQtyCtrl,
                          finisherRateCtrl,
                          availF,
                          avgCostFor('finisher'),
                          setModalState,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  color: Colors.white,
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final String farmerName =
                            (selectedFarmer ?? farmerSearchCtrl.text).trim();
                        double sQty =
                            double.tryParse(starterQtyCtrl.text) ?? 0.0;
                        double gQty =
                            double.tryParse(growerQtyCtrl.text) ?? 0.0;
                        double fQty =
                            double.tryParse(finisherQtyCtrl.text) ?? 0.0;

                        if (farmerName.isEmpty) {
                          Get.snackbar(
                            'Error',
                            'Farmer select karein.',
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                          return;
                        }
                        if (sQty <= 0 && gQty <= 0 && fQty <= 0) {
                          Get.snackbar(
                            'Error',
                            'Kam se kam ek type ki quantity bharein.',
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                          return;
                        }
                        if (sQty > availS) {
                          Get.snackbar(
                            'Error',
                            'Starter: sirf ${availS.toStringAsFixed(0)} bag available hai',
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                          return;
                        }
                        if (gQty > availG) {
                          Get.snackbar(
                            'Error',
                            'Grower: sirf ${availG.toStringAsFixed(0)} bag available hai',
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                          return;
                        }
                        if (fQty > availF) {
                          Get.snackbar(
                            'Error',
                            'Finisher: sirf ${availF.toStringAsFixed(0)} bag available hai',
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                          return;
                        }
                        if (selectedFarmerId == null ||
                            selectedFarmerId!.isEmpty) {
                          Get.snackbar(
                            'Farmer Select Karein ⚠️',
                            'Kripya dropdown list se hi farmer select karein.',
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                          return;
                        }

                        List<Map<String, dynamic>> farmersForBatch =
                            await CompanyStore.instance.getJsonList(
                              'companyFarmers',
                            );
                        Map<String, dynamic>? farmerMap;
                        int farmerIdxInList = -1;
                        for (int fi = 0; fi < farmersForBatch.length; fi++) {
                          if (farmersForBatch[fi]['id']?.toString() ==
                              selectedFarmerId) {
                            farmerMap = Map<String, dynamic>.from(
                              farmersForBatch[fi],
                            );
                            farmerIdxInList = fi;
                            break;
                          }
                        }
                        if (farmerMap == null) {
                          Get.snackbar(
                            'Error',
                            'Farmer record nahi mila.',
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                          return;
                        }

                        String? linkedBatchId;
                        final runningBatch = findRunningBatch(farmerMap);
                        if (runningBatch != null) {
                          linkedBatchId = runningBatch['batchId']?.toString();
                        } else {
                          final completedBatches = findCompletedBatches(
                            farmerMap,
                          );
                          final String? choice = await showDialog<String>(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              title: const Text('Batch Nahi Mila ⚠️'),
                              content: Text(
                                '$farmerName ka koi RUNNING batch nahi hai.\n\n'
                                'Kya ye feed kisi NAYE batch ke liye hai (jo abhi banega), '
                                'ya kisi PURANE (completed) batch ke liye hai?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                                if (completedBatches.isNotEmpty)
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, 'old'),
                                    child: const Text('Purane Batch Ka'),
                                  ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, 'new'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade800,
                                  ),
                                  child: const Text(
                                    'Naya Batch',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          );

                          if (choice == null || choice == 'cancel') return;

                          if (choice == 'old') {
                            final Map<String, dynamic>?
                            picked = await showDialog<Map<String, dynamic>>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Batch Chuniye'),
                                content: SizedBox(
                                  width: double.maxFinite,
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: completedBatches.length,
                                    itemBuilder: (c, bi) {
                                      final b = completedBatches[bi];
                                      return ListTile(
                                        title: Text(
                                          b['batchId']?.toString() ?? '-',
                                        ),
                                        subtitle: Text(
                                          '${b['chicksCount']} chicks | ${b['startDate'] ?? ''}',
                                        ),
                                        onTap: () => Navigator.pop(ctx, b),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                            if (picked == null) return;
                            linkedBatchId = picked['batchId']?.toString();
                          }
                        }

                        final String allocatedByRole =
                            await SessionService.currentRole ?? 'Owner';
                        final String allocatedByName =
                            await SessionService.currentName ?? '';
                        final String groupId = DateTime.now()
                            .millisecondsSinceEpoch
                            .toString();
                        final String allocDate = DateTime.now()
                            .toIso8601String();

                        if (linkedBatchId != null && farmerIdxInList >= 0) {
                          final target = farmersForBatch[farmerIdxInList];
                          for (var b in (target['batches'] ?? [])) {
                            if (b['batchId']?.toString() == linkedBatchId) {
                              final now = DateTime.now();
                              final dateStr =
                                  '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
                              final int totalBags = (sQty + gQty + fQty)
                                  .toInt();
                              b['dailyEntries'] ??= [];
                              b['dailyEntries'].add({
                                'type': 'cost',
                                'date': dateStr,
                                'weight': '0',
                                'mortality': '0',
                                'feed': totalBags.toString(),
                                'feedStarterBags': sQty.toInt(),
                                'feedGrowerBags': gQty.toInt(),
                                'feedFinisherBags': fQty.toInt(),
                                'feedTotalKg':
                                    (sQty + gQty + fQty) * feedKgPerBagCfg,
                                'remainingFeed': '0',
                                'enteredBy': allocatedByRole,
                                'timestamp': now.toIso8601String(),
                                'source': 'feedAllocation',
                              });
                              break;
                            }
                          }
                          await CompanyStore.instance.saveJsonList(
                            'companyFarmers',
                            farmersForBatch,
                          );
                        }

                        List<Map<String, dynamic>> stock =
                            await ensureFeedStockMigrated();
                        final Map<String, double> qtyByType = {
                          'starter': sQty,
                          'grower': gQty,
                          'finisher': fQty,
                        };
                        final Map<String, TextEditingController> rateByType = {
                          'starter': starterRateCtrl,
                          'grower': growerRateCtrl,
                          'finisher': finisherRateCtrl,
                        };
                        for (final id in kFeedTypeIds) {
                          final qty = qtyByType[id] ?? 0.0;
                          if (qty <= 0) continue;
                          final idx = stock.indexWhere((s) => s['id'] == id);
                          if (idx == -1) continue;
                          final allocs =
                              (stock[idx]['allocations'] as List?) ?? [];
                          allocs.add({
                            'id': '$groupId-$id',
                            'groupId': groupId,
                            'farmerName': farmerName,
                            'farmerId': selectedFarmerId,
                            'batchId': linkedBatchId,
                            'qty': qty,
                            'rate':
                                double.tryParse(rateByType[id]!.text) ?? 0.0,
                            // ✅ NEW: Is waqt ka actual purchase avg cost
                            // snapshot karke save karo — taaki baad mein
                            // naye feed purchase se is batch ka calculated
                            // income retroactively na badle (report screen
                            // isi field ko cost basis maanega).
                            'costAtAllocation':
                                (stock[idx]['weightedAvgCost'] as num?)
                                    ?.toDouble() ??
                                0.0,
                            'allocatedOn': allocDate,
                            'allocatedByName': allocatedByName,
                            'allocatedByRole': allocatedByRole,
                          });
                          stock[idx]['allocations'] = allocs;
                        }
                        await CompanyStore.instance.saveJsonList(
                          'feedStockList',
                          stock,
                        );

                        if (!context.mounted) return;
                        Navigator.pop(context, true);
                        Get.snackbar(
                          'Saved ✅',
                          'Feed allocate ho gaya!',
                          backgroundColor: Colors.green,
                          colorText: Colors.white,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade800,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Save Allocation',
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
}

// ✅ SAFE VERSION — Error-Free _feedAllocInput
Widget _feedAllocInput(
  String title,
  TextEditingController qtyCtrl,
  TextEditingController rateCtrl,
  double avail,
  double purchaseRatePerBag,
  StateSetter setModalState,
) {
  double qty = double.tryParse(qtyCtrl.text) ?? 0.0;
  double billingRate = double.tryParse(rateCtrl.text) ?? 0.0;
  bool isOver = qty > avail;
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
      border: Border.all(
        color: isOver ? Colors.red.shade300 : Colors.grey.shade300,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '🌾 $title',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.blue.shade900,
              ),
            ),
            Text(
              'Bacha: ${avail.toStringAsFixed(0)} Bag',
              style: TextStyle(
                fontSize: 11,
                color: isOver ? Colors.red.shade700 : Colors.green.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setModalState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Billing Rate (₹/Bag)',
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        // Profit / Loss mini widget (only if hasCalc)
        if (hasCalc) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: profit >= 0 ? Colors.blue.shade50 : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: profit >= 0
                    ? Colors.blue.shade200
                    : Colors.orange.shade200,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Cost: ₹${totalCost.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                Text(
                  'Bill: ₹${totalBilling.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                Text(
                  profit >= 0
                      ? '📈 +₹${profit.toStringAsFixed(0)}'
                      : '📉 -₹${profit.abs().toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: profit >= 0
                        ? Colors.blue.shade800
                        : Colors.orange.shade800,
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
// 📜 FEED PURCHASE HISTORY SCREEN (per type)
// ═══════════════════════════════════════════════════════════════════════════
class FeedPurchaseHistoryScreen extends StatefulWidget {
  final String feedTypeId;
  const FeedPurchaseHistoryScreen({super.key, required this.feedTypeId});

  @override
  State<FeedPurchaseHistoryScreen> createState() =>
      _FeedPurchaseHistoryScreenState();
}

class _FeedPurchaseHistoryScreenState extends State<FeedPurchaseHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  String _name = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final stock = await ensureFeedStockMigrated();
    final entry = stock.firstWhere(
      (s) => s['id'] == widget.feedTypeId,
      orElse: () => {},
    );
    final hist = List<Map<String, dynamic>>.from(
      ((entry['purchaseHistory'] as List?) ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    hist.sort(
      (a, b) =>
          (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()),
    );
    if (mounted) {
      setState(() {
        _history = hist;
        _name =
            entry['name']?.toString() ??
            kFeedTypeNames[widget.feedTypeId] ??
            '';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          '📜 $_name — Purchase History',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
          ? const Center(child: Text('Koi purchase record nahi.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _history.length,
              itemBuilder: (context, i) {
                final h = _history[i];
                final double bags = (h['bags'] as num?)?.toDouble() ?? 0.0;
                final double perBag =
                    (h['perBagPrice'] as num?)?.toDouble() ?? 0.0;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            h['company']?.toString() ?? '-',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '₹${(bags * perBag).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${bags.toStringAsFixed(0)} bag @ ₹${perBag.toStringAsFixed(2)}/bag',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      if ((h['addedByName']?.toString() ?? '').isNotEmpty)
                        Text(
                          '👤 ${h['addedByRole'] ?? ''}: ${h['addedByName']}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      if ((h['date']?.toString() ?? '').isNotEmpty)
                        Text(
                          '🕒 ${formatHistoryDateTime(h['date'].toString())}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black45,
                          ),
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
// 🧑 FEED FARMER ALLOCATIONS LIST SCREEN (per type)
// ═══════════════════════════════════════════════════════════════════════════
class FeedFarmerAllocationsListScreen extends StatefulWidget {
  final String feedTypeId;
  const FeedFarmerAllocationsListScreen({super.key, required this.feedTypeId});

  @override
  State<FeedFarmerAllocationsListScreen> createState() =>
      _FeedFarmerAllocationsListScreenState();
}

class _FeedFarmerAllocationsListScreenState
    extends State<FeedFarmerAllocationsListScreen> {
  List<Map<String, dynamic>> _allocs = [];
  String _name = '';
  bool _isLoading = true;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final stock = await ensureFeedStockMigrated();
    final entry = stock.firstWhere(
      (s) => s['id'] == widget.feedTypeId,
      orElse: () => {},
    );
    final allocs = List<Map<String, dynamic>>.from(
      ((entry['allocations'] as List?) ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    allocs.sort(
      (a, b) => (b['allocatedOn'] ?? '').toString().compareTo(
        (a['allocatedOn'] ?? '').toString(),
      ),
    );
    if (mounted) {
      setState(() {
        _allocs = allocs;
        _name =
            entry['name']?.toString() ??
            kFeedTypeNames[widget.feedTypeId] ??
            '';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Get.back(result: _changed);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: Colors.blue.shade700,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
            ),
            onPressed: () => Get.back(result: _changed),
          ),
          title: Text(
            '🧑 $_name — Farmer Allocations',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _allocs.isEmpty
            ? const Center(child: Text('Koi allocation nahi.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _allocs.length,
                itemBuilder: (context, i) {
                  final a = _allocs[i];
                  final String date = formatHistoryDateTime(
                    a['allocatedOn']?.toString(),
                  );
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      final result = await Get.to(
                        () => FeedAllocationDetailScreen(
                          feedTypeId: widget.feedTypeId,
                          allocIndex: i,
                        ),
                      );
                      if (result == true) {
                        _changed = true;
                        _load();
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '🧑 ${a['farmerName'] ?? '-'}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (a['batchId']?.toString().isNotEmpty ??
                                    false)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      '🏷️ Batch: ${a['batchId']}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purple.shade700,
                                      ),
                                    ),
                                  ),
                                if (date.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(
                                      date,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            '${((a['qty'] as num?) ?? 0).toStringAsFixed(0)} bag',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Colors.grey.shade500,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🛒 FEED PRIVATE BUYERS LIST SCREEN (per type) — Read-only, koi edit/delete
// nahi (jaisa Gopi ne maanga: "purchase mein bas wahan data dekhe").
// ═══════════════════════════════════════════════════════════════════════════
class FeedPrivateBuyersListScreen extends StatefulWidget {
  final String feedTypeId;
  const FeedPrivateBuyersListScreen({super.key, required this.feedTypeId});

  @override
  State<FeedPrivateBuyersListScreen> createState() =>
      _FeedPrivateBuyersListScreenState();
}

class _FeedPrivateBuyersListScreenState
    extends State<FeedPrivateBuyersListScreen> {
  List<Map<String, dynamic>> _sales = [];
  String _name = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final stock = await ensureFeedStockMigrated();
    final entry = stock.firstWhere(
      (s) => s['id'] == widget.feedTypeId,
      orElse: () => {},
    );
    final sales = List<Map<String, dynamic>>.from(
      ((entry['privateSales'] as List?) ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    sales.sort(
      (a, b) =>
          (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()),
    );
    if (mounted) {
      setState(() {
        _sales = sales;
        _name =
            entry['name']?.toString() ??
            kFeedTypeNames[widget.feedTypeId] ??
            '';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          '🛒 $_name — Private Buyers',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sales.isEmpty
          ? const Center(child: Text('Koi private buyer nahi.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _sales.length,
              itemBuilder: (context, i) {
                final s = _sales[i];
                final double qty = (s['qty'] as num?)?.toDouble() ?? 0.0;
                final double rate = (s['rate'] as num?)?.toDouble() ?? 0.0;
                final double paid =
                    (s['paidAmount'] as num?)?.toDouble() ?? 0.0;
                final double total = qty * rate;
                final double due = (total - paid).clamp(0.0, double.infinity);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '🛒 ${s['buyerName'] ?? '-'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '₹${total.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${qty.toStringAsFixed(0)} bag @ ₹${rate.toStringAsFixed(2)}/bag',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      if ((s['mobile']?.toString() ?? '').isNotEmpty)
                        Text(
                          '📞 ${s['mobile']}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: due > 0
                                ? Colors.red.shade50
                                : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            due > 0
                                ? 'Due: ₹${due.toStringAsFixed(0)}'
                                : '✅ Paid',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: due > 0
                                  ? Colors.red.shade800
                                  : Colors.green.shade800,
                            ),
                          ),
                        ),
                      ),
                      if ((s['addedByName']?.toString() ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '👤 ${s['addedByRole'] ?? ''}: ${s['addedByName']}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      if ((s['date']?.toString() ?? '').isNotEmpty)
                        Text(
                          '🕒 ${formatHistoryDateTime(s['date'].toString())}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black45,
                          ),
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
// ✏️ FEED ALLOCATION DETAIL SCREEN (per type, single farmer record) — Edit/Delete
// ═══════════════════════════════════════════════════════════════════════════
class FeedAllocationDetailScreen extends StatefulWidget {
  final String feedTypeId;
  final int allocIndex;
  const FeedAllocationDetailScreen({
    super.key,
    required this.feedTypeId,
    required this.allocIndex,
  });

  @override
  State<FeedAllocationDetailScreen> createState() =>
      _FeedAllocationDetailScreenState();
}

class _FeedAllocationDetailScreenState
    extends State<FeedAllocationDetailScreen> {
  Map<String, dynamic>? _feedType;
  Map<String, dynamic>? _alloc;
  bool _isEditMode = false;
  bool _isLoading = true;

  final _nameCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final stock = await ensureFeedStockMigrated();
    final entry = stock.firstWhere(
      (s) => s['id'] == widget.feedTypeId,
      orElse: () => {},
    );
    final allocs = (entry['allocations'] as List?) ?? [];
    if (widget.allocIndex < allocs.length) {
      final alloc = Map<String, dynamic>.from(allocs[widget.allocIndex] as Map);
      _nameCtrl.text = alloc['farmerName']?.toString() ?? '';
      _qtyCtrl.text = ((alloc['qty'] as num?) ?? 0).toString();
      _rateCtrl.text = ((alloc['rate'] as num?) ?? 0).toString();
      if (mounted) {
        setState(() {
          _feedType = entry;
          _alloc = alloc;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double _availForEdit() {
    if (_feedType == null || _alloc == null) return 0.0;
    final double remaining = computeFeedRemaining(_feedType!);
    final double currentQty = (_alloc!['qty'] as num?)?.toDouble() ?? 0.0;
    return remaining + currentQty;
  }

  Future<void> _save() async {
    final double qty = double.tryParse(_qtyCtrl.text) ?? 0.0;
    if (qty <= 0) {
      Get.snackbar(
        'Error',
        'Sahi quantity daalein',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    if (qty > _availForEdit()) {
      Get.snackbar(
        'Error',
        'Sirf ${_availForEdit().toStringAsFixed(0)} bag available hai',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    List<Map<String, dynamic>> stock = await CompanyStore.instance.getJsonList(
      'feedStockList',
    );
    final idx = stock.indexWhere((s) => s['id'] == widget.feedTypeId);
    if (idx == -1) return;
    final allocs = (stock[idx]['allocations'] as List?) ?? [];
    if (widget.allocIndex < allocs.length) {
      allocs[widget.allocIndex]['farmerName'] = _nameCtrl.text.trim();
      allocs[widget.allocIndex]['qty'] = qty;
      allocs[widget.allocIndex]['rate'] =
          double.tryParse(_rateCtrl.text) ?? 0.0;
    }
    stock[idx]['allocations'] = allocs;
    await CompanyStore.instance.saveJsonList('feedStockList', stock);
    if (!mounted) return;
    Get.back(result: true);
    Get.snackbar(
      'Updated ✅',
      'Allocation update ho gayi',
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Karein?'),
        content: const Text(
          'Ye allocation delete karna chahte hain? Ye undo nahi hoga.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Yes, Delete',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    List<Map<String, dynamic>> stock = await CompanyStore.instance.getJsonList(
      'feedStockList',
    );
    final idx = stock.indexWhere((s) => s['id'] == widget.feedTypeId);
    if (idx == -1) return;
    final allocs = (stock[idx]['allocations'] as List?) ?? [];
    if (widget.allocIndex < allocs.length) {
      allocs.removeAt(widget.allocIndex);
    }
    stock[idx]['allocations'] = allocs;
    await CompanyStore.instance.saveJsonList('feedStockList', stock);
    if (!mounted) return;
    Get.back(result: true);
    Get.snackbar(
      'Deleted ✅',
      'Allocation delete ho gayi',
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_alloc == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Get.back(),
          ),
        ),
        body: const Center(child: Text('Allocation nahi mila.')),
      );
    }

    final double qty = double.tryParse(_qtyCtrl.text) ?? 0.0;
    final double rate = double.tryParse(_rateCtrl.text) ?? 0.0;
    final double avgCost =
        (_feedType!['weightedAvgCost'] as num?)?.toDouble() ?? 0.0;
    final double cost = qty * avgCost;
    final double billing = qty * rate;
    final double profit = billing - cost;
    final String feedName =
        _feedType!['name']?.toString() ??
        kFeedTypeNames[widget.feedTypeId] ??
        '';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          _isEditMode ? 'Edit Allocation' : 'Farmer Allocation',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isEditMode ? Icons.close_rounded : Icons.edit_rounded,
              color: Colors.white,
            ),
            onPressed: () => setState(() => _isEditMode = !_isEditMode),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '🌾 $feedName',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
            ),
            if (_alloc!['batchId']?.toString().isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Text(
                  '🏷️ Batch: ${_alloc!['batchId']}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple.shade800,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              enabled: _isEditMode,
              decoration: InputDecoration(
                labelText: 'Farmer Ka Naam',
                prefixIcon: const Icon(Icons.person_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    enabled: _isEditMode,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Quantity (Bag)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _rateCtrl,
                    enabled: _isEditMode,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Billing Rate (₹/Bag)',
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
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Purchase Cost'),
                      Text(
                        '₹${cost.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Billing/Sale Value'),
                      Text(
                        '₹${billing.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '📈 Margin / Profit',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '₹${profit.toStringAsFixed(2)}',
                        style: TextStyle(
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
            if (_alloc!['allocatedByName'] != null &&
                (_alloc!['allocatedByName'] as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '👤 ${_alloc!['allocatedByRole'] ?? ''}: ${_alloc!['allocatedByName']}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            if (_alloc!['allocatedOn'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '🕒 ${formatHistoryDateTime(_alloc!['allocatedOn']?.toString())}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            if (_isEditMode) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PurchaseExpenseScreen.primaryGreen,
                  ),
                  child: const Text(
                    'Save Changes',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
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
const Map<String, double> _unitToMl = {'ml': 1.0, 'liter': 1000.0};
const Map<String, double> _unitToGram = {'gram': 1.0, 'kg': 1000.0};

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
const List<String> kMedicineUnits = [
  'ml',
  'liter',
  'gram',
  'kg',
  'packet',
  'dabba',
];

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
    return pricePerBase * _unitToMl[t]! / _unitToMl[b]!;
  if (_unitToGram.containsKey(b) && _unitToGram.containsKey(t))
    return pricePerBase * _unitToGram[t]! / _unitToGram[b]!;
  return null;
}

/// Rs/target → Rs/base  e.g. Rs2/ml → Rs2000/liter
double? priceToBase(double pricePerTarget, String target, String base) =>
    pricePerUnit(pricePerTarget, target, base);

// ═══════════════════════════════════════════════════════════════════════════
// 💊 SHARED MEDICINE PURCHASE LOGIC
// Ye 2 functions hi "Naya Medicine Add Karo" aur "Add Stock" dono jagah se
// use hote hain — taaki dono jagah SAME rule follow ho (koi mismatch na ho).
// ═══════════════════════════════════════════════════════════════════════════

/// Ek medicine ka abhi "bacha hua" (remaining) base qty nikalta hai:
/// total purchase − farmer allocations − private sales
Future<double> computeMedicineRemainingBaseQty(Map<String, dynamic> med) async {
  final String mId = med['id']?.toString() ?? '';
  final double totalBase = (med['totalBaseQty'] as num?)?.toDouble() ?? 0.0;

  double allocBase = 0;
  for (final a in (med['allocations'] as List<dynamic>? ?? [])) {
    allocBase +=
        (a['qtyInBaseUnit'] as num?)?.toDouble() ??
        (a['qty'] as num?)?.toDouble() ??
        0.0;
  }

  double soldBase = 0;
  final String? salesJson = await CompanyStore.instance.getString(
    'medicineSalesHistory',
  );
  if (salesJson != null) {
    try {
      final List<dynamic> rawSales = json.decode(salesJson);
      for (final sale in rawSales) {
        final List<dynamic> items = sale['items'] as List<dynamic>? ?? [];
        for (final item in items) {
          if (item['medicineId']?.toString() != mId) continue;
          soldBase +=
              (item['qtyInBaseUnit'] as num?)?.toDouble() ??
              (item['qty'] as num?)?.toDouble() ??
              0.0;
        }
      }
    } catch (_) {}
  }

  return (totalBase - allocBase - soldBase).clamp(0.0, double.infinity);
}

/// Medicine purchase add karo (naya lot ho ya purane mein aur stock jode).
///
/// RULE (Gopi ke confirm kiye hue anusaar):
/// - Agar ye medicine PEHLI BAAR add ho rahi hai → seedha naya record banega
///   (avg cost / farmer rate = isi purchase ke values, kyunki bacha hua = 0).
/// - Agar SAME NAAM ki medicine PEHLE SE hai → purane "BACHE HUE" stock ka
///   cost/rate aur is naye purchase ka cost/rate — dono ko unki quantity ke
///   weight se AVERAGE kiya jayega (na ki ab tak total kharide hue ke hisaab se).
Future<void> addOrUpdateMedicinePurchase({
  required String name,
  required double qty,
  required String unit,
  required double actualPrice,
  required double farmerPrice,
  String nickName = '',
  String addedByName = '',
  String addedByRole = '',
}) async {
  final String? stockJson = await CompanyStore.instance.getString(
    'medicineStockList',
  );
  List<dynamic> all = [];
  if (stockJson != null) {
    try {
      all = json.decode(stockJson);
    } catch (_) {}
  }

  final int idx = all.indexWhere(
    (m) =>
        m['name']?.toString().toLowerCase().trim() == name.toLowerCase().trim(),
  );

  final String newHistId = DateTime.now().millisecondsSinceEpoch.toString();

  if (idx == -1) {
    // ── PEHLI BAAR — naya medicine lot banao ──
    final double qtyBase = qty; // base unit = jo unit select kiya
    final double perBaseActual = qtyBase > 0 ? actualPrice / qtyBase : 0;
    final double perBaseFarmer = qtyBase > 0 ? farmerPrice / qtyBase : 0;

    final Map<String, dynamic> newMed = {
      'id': newHistId,
      'name': name,
      'nickName': nickName,
      'unit': unit,
      'totalBaseQty': qtyBase,
      'weightedAvgCost': perBaseActual,
      'currentFarmerRate': perBaseFarmer,
      'addedByName': addedByName,
      'addedByRole': addedByRole,
      'createdOn': DateTime.now().toIso8601String(),
      'allocations': [],
      'purchaseHistory': [
        {
          'id': newHistId,
          'qty': qty,
          'unit': unit,
          'qtyInBaseUnit': qtyBase,
          'actualPrice': actualPrice,
          'farmerPrice': farmerPrice,
          'perBaseActualCost': perBaseActual,
          'perBaseFarmerRate': perBaseFarmer,
          'date': DateTime.now().toIso8601String(),
          'addedByName': addedByName,
          'addedByRole': addedByRole,
        },
      ],
    };
    all.insert(0, newMed);
  } else {
    // ── SAME medicine pehle se hai — bache hue stock ke saath average karo ──
    final Map<String, dynamic> med = Map<String, dynamic>.from(all[idx] as Map);
    final String baseUnit = med['unit']?.toString() ?? unit;

    final double remainingBase = await computeMedicineRemainingBaseQty(med);
    final double oldAvgCost =
        (med['weightedAvgCost'] as num?)?.toDouble() ?? 0.0;
    final double oldFarmerRate =
        (med['currentFarmerRate'] as num?)?.toDouble() ?? 0.0;
    final double oldTotalBase =
        (med['totalBaseQty'] as num?)?.toDouble() ?? 0.0;

    final double qtyBase = convertToBase(qty, unit, baseUnit) ?? qty;
    final double perBaseActual = qtyBase > 0 ? actualPrice / qtyBase : 0;
    final double perBaseFarmer = qtyBase > 0 ? farmerPrice / qtyBase : 0;

    final double newRemainingTotal = remainingBase + qtyBase;
    final double newAvgCost = newRemainingTotal > 0
        ? ((remainingBase * oldAvgCost) + (qtyBase * perBaseActual)) /
              newRemainingTotal
        : perBaseActual;
    final double newFarmerRate = newRemainingTotal > 0
        ? ((remainingBase * oldFarmerRate) + (qtyBase * perBaseFarmer)) /
              newRemainingTotal
        : perBaseFarmer;

    med['totalBaseQty'] = oldTotalBase + qtyBase; // record ke liye cumulative
    med['weightedAvgCost'] = newAvgCost; // bache hue ke hisaab se average
    med['currentFarmerRate'] = newFarmerRate; // bache hue ke hisaab se average

    final List<dynamic> hist = med['purchaseHistory'] as List<dynamic>? ?? [];
    hist.add({
      'id': newHistId,
      'qty': qty,
      'unit': unit,
      'qtyInBaseUnit': qtyBase,
      'actualPrice': actualPrice,
      'farmerPrice': farmerPrice,
      'perBaseActualCost': perBaseActual,
      'perBaseFarmerRate': perBaseFarmer,
      'date': DateTime.now().toIso8601String(),
      'addedByName': addedByName,
      'addedByRole': addedByRole,
    });
    med['purchaseHistory'] = hist;

    all[idx] = med;
  }

  await CompanyStore.instance.setString('medicineStockList', json.encode(all));
}

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
  Map<String, double> _soldBaseQty = {};
  Map<String, double> _availBaseQty = {}; // mId → available base qty
  // mId → list of {buyerName, qty, unit, saleId, mobile, date}
  Map<String, List<Map<String, dynamic>>> _privateSalesByMed = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // 1. Medicine stock
    final String? stockJson = await CompanyStore.instance.getString(
      'medicineStockList',
    );
    List<Map<String, dynamic>> meds = [];
    if (stockJson != null) {
      try {
        final List<dynamic> raw = json.decode(stockJson);
        meds = raw.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }

    // 2. Private sales — sold qty per medicine + buyer-wise breakdown
    final String? salesJson = await CompanyStore.instance.getString(
      'medicineSalesHistory',
    );
    Map<String, double> soldMap = {};
    Map<String, List<Map<String, dynamic>>> privateSalesMap = {};
    if (salesJson != null) {
      try {
        final List<dynamic> rawSales = json.decode(salesJson);
        for (final sale in rawSales) {
          final List<dynamic> items = sale['items'] as List<dynamic>? ?? [];
          for (final item in items) {
            final String mId = item['medicineId']?.toString() ?? '';
            if (mId.isEmpty) continue;
            final double qBase =
                (item['qtyInBaseUnit'] as num?)?.toDouble() ??
                (item['qty'] as num?)?.toDouble() ??
                0.0;
            soldMap[mId] = (soldMap[mId] ?? 0.0) + qBase;

            (privateSalesMap[mId] ??= []).add({
              'saleId': sale['id']?.toString() ?? '',
              'buyerName': sale['buyerName']?.toString() ?? '-',
              'mobile': sale['mobile']?.toString() ?? '',
              'qty': (item['qty'] as num?)?.toDouble() ?? 0.0,
              'unit':
                  item['saleUnit']?.toString() ??
                  item['unit']?.toString() ??
                  '',
              'date': sale['date']?.toString() ?? '',
            });
          }
        }
      } catch (_) {}
    }

    // 3. Available = total − allocated − sold
    Map<String, double> availMap = {};
    for (final med in meds) {
      final String mId = med['id']?.toString() ?? '';
      if (mId.isEmpty) continue;
      final double total = (med['totalBaseQty'] as num?)?.toDouble() ?? 0.0;
      double allocBase = 0;
      for (final a in (med['allocations'] as List<dynamic>? ?? [])) {
        allocBase +=
            (a['qtyInBaseUnit'] as num?)?.toDouble() ??
            (a['qty'] as num?)?.toDouble() ??
            0.0;
      }
      availMap[mId] = (total - allocBase - (soldMap[mId] ?? 0.0)).clamp(
        0.0,
        double.infinity,
      );
    }

    if (mounted) {
      setState(() {
        _medicines = meds;
        _soldBaseQty = soldMap;
        _availBaseQty = availMap;
        _privateSalesByMed = privateSalesMap;
        _isLoading = false;
      });
    }
  }

  /// Farmer allocations ka total base qty
  double _allocatedBaseQty(Map<String, dynamic> med) {
    final allocs = List<Map<String, dynamic>>.from(
      (med['allocations'] as List<dynamic>?)?.map(
            (e) => Map<String, dynamic>.from(e as Map),
          ) ??
          [],
    );
    double total = 0;
    for (final a in allocs) {
      total +=
          (a['qtyInBaseUnit'] as num?)?.toDouble() ??
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
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: const Row(
          children: [
            Text('💊', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text(
              'Medicine Purchase',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await widget.onMedicineTap();
                  _loadData();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                ),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text(
                  'Naya Medicine Add Karo',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          // ── Allocate to Farmer button ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _medicines.isEmpty
                    ? null
                    : () async {
                        await Get.to(
                          () => AllocateMedicineToFarmerScreen(
                            medicines: _medicines,
                            availBaseQty: _availBaseQty,
                          ),
                        );
                        _loadData();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
                icon: const Icon(Icons.person_add_rounded, color: Colors.white),
                label: const Text(
                  'Allocate to Farmer',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                        const Text('💊', style: TextStyle(fontSize: 52)),
                        const SizedBox(height: 12),
                        Text(
                          'Koi medicine record nahi.',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _medicines.length,
                    itemBuilder: (ctx, index) {
                      final med = _medicines[index];
                      final String mId = med['id']?.toString() ?? '';
                      return _MedicineRunningLotCard(
                        med: med,
                        soldBaseQty: _soldBaseQty[mId] ?? 0.0,
                        allocatedBaseQty: _allocatedBaseQty(med),
                        privateSales: _privateSalesByMed[mId] ?? const [],
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
  final List<Map<String, dynamic>> privateSales;
  final VoidCallback onRefresh;

  const _MedicineRunningLotCard({
    required this.med,
    required this.soldBaseQty,
    required this.allocatedBaseQty,
    this.privateSales = const [],
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
    final double leftBaseQty = (totalBaseQty - allocatedBaseQty - soldBaseQty)
        .clamp(0.0, double.infinity);
    final bool anyLeft = leftBaseQty > 0;

    final List<Map<String, dynamic>> purchaseHistory =
        List<Map<String, dynamic>>.from(
          (med['purchaseHistory'] as List<dynamic>?)?.map(
                (e) => Map<String, dynamic>.from(e as Map),
              ) ??
              [],
        );
    final List<Map<String, dynamic>> allocs = List<Map<String, dynamic>>.from(
      (med['allocations'] as List<dynamic>?)?.map(
            (e) => Map<String, dynamic>.from(e as Map),
          ) ??
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
                          Text(
                            '💊 $name',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.teal.shade900,
                            ),
                          ),
                          if (nickName.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade100,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                '"$nickName"',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.teal.shade800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total Kharida: ${totalBaseQty.toStringAsFixed(2)} $unit',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      Text(
                        'Bacha: ${leftBaseQty.toStringAsFixed(2)} $unit',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: anyLeft ? Colors.green.shade700 : Colors.grey,
                        ),
                      ),
                      if (weightedAvgCost > 0)
                        Text(
                          'Avg Cost: ₹${weightedAvgCost.toStringAsFixed(2)} / $unit',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      if (currentFarmerRate > 0)
                        Text(
                          'Farmer Rate: ₹${currentFarmerRate.toStringAsFixed(2)} / $unit',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.teal.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                // Add + Delete lot buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Add more stock
                    GestureDetector(
                      onTap: () async {
                        await _showAddMoreStockDialog(context, med);
                        onRefresh();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade700,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Add',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
                              'Kya aap "$name" ka poora lot delete karna '
                              'chahte hain?\n\n'
                              '⚠️ Isse is medicine ki saari purchase '
                              'history aur allocations bhi delete ho '
                              'jayenge. Yeh permanent hai.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
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
                        all.removeWhere((m) => m['id']?.toString() == mId);
                        await CompanyStore.instance.setString(
                          'medicineStockList',
                          json.encode(all),
                        );
                        Get.snackbar(
                          'Deleted 🗑️',
                          '"$name" lot delete ho gaya',
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                        onRefresh();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Icon(
                          Icons.delete_rounded,
                          color: Colors.red.shade700,
                          size: 16,
                        ),
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
              onTap: () => Get.to(
                () => MedicinePurchaseHistoryScreen(
                  medicineId: mId,
                  medicineName: name,
                  unit: unit,
                ),
              ),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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
                        Icon(
                          Icons.history_rounded,
                          size: 15,
                          color: Colors.teal.shade700,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Purchase History (${purchaseHistory.length} baar kharida)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.teal.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: Colors.teal.shade700,
                    ),
                  ],
                ),
              ),
            ),

          // ── FARMER ALLOCATIONS BUTTON ──
          if (allocs.isNotEmpty)
            InkWell(
              onTap: () async {
                final result = await Get.to(
                  () => MedicineFarmerAllocationsListScreen(
                    medicineId: mId,
                    medicineName: name,
                    unit: unit,
                  ),
                );
                if (result == true) onRefresh();
              },
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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
                        Icon(
                          Icons.people_alt_rounded,
                          size: 15,
                          color: Colors.teal.shade700,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Farmer Allocations (${allocs.length})',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.teal.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: Colors.teal.shade700,
                    ),
                  ],
                ),
              ),
            ),

          // ── PRIVATE BUYERS BUTTON (medicine sold directly, not via farmer) ──
          if (privateSales.isNotEmpty)
            InkWell(
              onTap: () => Get.to(
                () => MedicinePrivateBuyersListScreen(
                  medicineId: mId,
                  medicineName: name,
                  unit: unit,
                ),
              ),
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.shopping_cart_rounded,
                          size: 15,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Private Buyers (${privateSales.length})',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: Colors.blue.shade700,
                    ),
                  ],
                ),
              ),
            ),

          // ── Stock status indicator (no per-lot allocate button) ──
          if (!anyLeft)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  '✅ Fully Used / Sold',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 14),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🧑 FARMER ALLOCATIONS — LIST SCREEN (medicine ke saare farmer allocation)
// Tap on any farmer -> MedicineAllocationDetailScreen (edit/delete already hai)
// ═══════════════════════════════════════════════════════════════════════════
class MedicineFarmerAllocationsListScreen extends StatefulWidget {
  final String medicineId;
  final String medicineName;
  final String unit;

  const MedicineFarmerAllocationsListScreen({
    super.key,
    required this.medicineId,
    required this.medicineName,
    required this.unit,
  });

  @override
  State<MedicineFarmerAllocationsListScreen> createState() =>
      _MedicineFarmerAllocationsListScreenState();
}

class _MedicineFarmerAllocationsListScreenState
    extends State<MedicineFarmerAllocationsListScreen> {
  List<Map<String, dynamic>> _allocs = [];
  bool _isLoading = true;
  bool _changed = false; // detail screen se koi edit/delete hua ho to

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final String? stockJson = await CompanyStore.instance.getString(
      'medicineStockList',
    );
    List<Map<String, dynamic>> allocs = [];
    if (stockJson != null) {
      try {
        final List<dynamic> all = json.decode(stockJson);
        for (final m in all) {
          if (m['id']?.toString() == widget.medicineId) {
            final List<dynamic> raw = m['allocations'] as List<dynamic>? ?? [];
            allocs = raw
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            break;
          }
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _allocs = allocs;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _changed);
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: Colors.teal.shade700,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, _changed),
          ),
          title: Text(
            '🧑 ${widget.medicineName} — Farmer Allocations',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _allocs.isEmpty
            ? const Center(child: Text('Koi farmer allocation nahi.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _allocs.length,
                itemBuilder: (ctx, i) {
                  final a = _allocs[i];
                  final double aBaseQty =
                      (a['qtyInBaseUnit'] as num?)?.toDouble() ??
                      (a['qty'] as num?)?.toDouble() ??
                      0.0;
                  final String aDisplayUnit =
                      a['unit']?.toString() ?? widget.unit;
                  final double aDisplayQty =
                      convertFromBase(aBaseQty, widget.unit, aDisplayUnit) ??
                      aBaseQty;
                  final String date = formatHistoryDateTime(
                    a['date']?.toString(),
                  );
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      final result = await Get.to(
                        () => MedicineAllocationDetailScreen(
                          medicineId: widget.medicineId,
                          allocIndex: i,
                        ),
                      );
                      if (result == true) {
                        _changed = true;
                        _load();
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.teal.shade100),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '🧑 ${a['farmerName'] ?? '-'}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                // ✅ NEW: Batch ID
                                if (a['batchId']?.toString().isNotEmpty ??
                                    false)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      '🏷️ Batch: ${a['batchId']}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purple.shade700,
                                      ),
                                    ),
                                  ),
                                if (date.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(
                                      date,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            '${aDisplayQty.toStringAsFixed(2)} $aDisplayUnit',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Colors.grey.shade500,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🛒 PRIVATE BUYERS — LIST SCREEN (medicine ke saare private sale buyers)
// Tap on any buyer -> MedicinePrivateSaleDetailScreen (read-only, no edit/delete
// — wo Sales section mein already available hai)
// ═══════════════════════════════════════════════════════════════════════════
class MedicinePrivateBuyersListScreen extends StatefulWidget {
  final String medicineId;
  final String medicineName;
  final String unit;

  const MedicinePrivateBuyersListScreen({
    super.key,
    required this.medicineId,
    required this.medicineName,
    required this.unit,
  });

  @override
  State<MedicinePrivateBuyersListScreen> createState() =>
      _MedicinePrivateBuyersListScreenState();
}

class _MedicinePrivateBuyersListScreenState
    extends State<MedicinePrivateBuyersListScreen> {
  List<Map<String, dynamic>> _rows =
      []; // {saleId, buyerName, mobile, date, qty, unit, rate}
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final String? salesJson = await CompanyStore.instance.getString(
      'medicineSalesHistory',
    );
    List<Map<String, dynamic>> rows = [];
    if (salesJson != null) {
      try {
        final List<dynamic> rawSales = json.decode(salesJson);
        for (final sale in rawSales) {
          final List<dynamic> items = sale['items'] as List<dynamic>? ?? [];
          for (final item in items) {
            if (item['medicineId']?.toString() != widget.medicineId) continue;
            rows.add({
              'saleId': sale['id']?.toString() ?? '',
              'buyerName': sale['buyerName']?.toString() ?? '-',
              'mobile': sale['mobile']?.toString() ?? '',
              'date': sale['date']?.toString() ?? '',
              'qty': (item['qty'] as num?)?.toDouble() ?? 0.0,
              'unit':
                  item['saleUnit']?.toString() ??
                  item['unit']?.toString() ??
                  widget.unit,
            });
          }
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _rows = rows;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.teal.shade700,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          '🛒 ${widget.medicineName} — Private Buyers',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
          ? const Center(child: Text('Koi private buyer nahi.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _rows.length,
              itemBuilder: (ctx, i) {
                final r = _rows[i];
                final double qty = (r['qty'] as num?)?.toDouble() ?? 0.0;
                final String unit = r['unit']?.toString() ?? widget.unit;
                final String date = formatHistoryDateTime(
                  r['date']?.toString(),
                );
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Get.to(
                    () => MedicinePrivateSaleDetailScreen(
                      saleId: r['saleId']?.toString() ?? '',
                      medicineId: widget.medicineId,
                    ),
                  ),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🛒 ${r['buyerName'] ?? '-'}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (date.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    date,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          '${qty.toStringAsFixed(2)} $unit',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: Colors.grey.shade500,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🛒 PRIVATE SALE — DETAIL SCREEN (READ-ONLY — koi edit/delete nahi)
// Edit/Delete Sales section (Medicine Sales History) mein already available hai
// ═══════════════════════════════════════════════════════════════════════════
class MedicinePrivateSaleDetailScreen extends StatefulWidget {
  final String saleId;
  final String medicineId;

  const MedicinePrivateSaleDetailScreen({
    super.key,
    required this.saleId,
    required this.medicineId,
  });

  @override
  State<MedicinePrivateSaleDetailScreen> createState() =>
      _MedicinePrivateSaleDetailScreenState();
}

class _MedicinePrivateSaleDetailScreenState
    extends State<MedicinePrivateSaleDetailScreen> {
  Map<String, dynamic>? _sale;
  Map<String, dynamic>? _item;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final String? salesJson = await CompanyStore.instance.getString(
      'medicineSalesHistory',
    );
    Map<String, dynamic>? foundSale;
    Map<String, dynamic>? foundItem;
    if (salesJson != null) {
      try {
        final List<dynamic> rawSales = json.decode(salesJson);
        for (final sale in rawSales) {
          if (sale['id']?.toString() != widget.saleId) continue;
          foundSale = Map<String, dynamic>.from(sale);
          final List<dynamic> items = sale['items'] as List<dynamic>? ?? [];
          for (final item in items) {
            if (item['medicineId']?.toString() == widget.medicineId) {
              foundItem = Map<String, dynamic>.from(item);
              break;
            }
          }
          break;
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _sale = foundSale;
        _item = foundItem;
        _isLoading = false;
      });
    }
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final sale = _sale;
    final item = _item;

    final String buyer = sale?['buyerName']?.toString() ?? '-';
    final String mobile = sale?['mobile']?.toString() ?? '';
    final String date = formatHistoryDateTime(sale?['date']?.toString());
    final String medicineName = item?['medicineName']?.toString() ?? '-';
    final String nickName = item?['nickName']?.toString() ?? '';
    final double qty = (item?['qty'] as num?)?.toDouble() ?? 0.0;
    final String saleUnit = item?['saleUnit']?.toString() ?? '';
    final double saleRate = (item?['saleRate'] as num?)?.toDouble() ?? 0.0;
    final double totalSale = (item?['totalSale'] as num?)?.toDouble() ?? 0.0;
    final double totalCost = (item?['totalCost'] as num?)?.toDouble() ?? 0.0;
    final double profit = totalSale - totalCost;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: const Text(
          '🛒 Private Sale Detail',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (sale == null || item == null)
          ? const Center(child: Text('Sale record nahi mila.'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🛒 $buyer',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(height: 22),
                    if (mobile.isNotEmpty) _row('📞 Mobile', mobile),
                    _row('🕒 Date', date),
                    _row(
                      '💊 Medicine',
                      nickName.isNotEmpty
                          ? '$medicineName ("$nickName")'
                          : medicineName,
                    ),
                    _row('📦 Quantity', '${qty.toStringAsFixed(2)} $saleUnit'),
                    _row(
                      '💰 Rate',
                      '₹${saleRate.toStringAsFixed(2)} / $saleUnit',
                    ),
                    _row('🧾 Total Sale', '₹${totalSale.toStringAsFixed(2)}'),
                    _row('📊 Profit/Loss', '₹${profit.toStringAsFixed(2)}'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'ℹ️ Is sale ko edit ya delete karne ke liye Sales → Medicine Sales section mein jaayein.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
                    decimal: true,
                  ),
                  onChanged: (_) => setDlg(() {}),
                  decoration: InputDecoration(
                    labelText: 'Quantity *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Unit select
                Text(
                  'Unit Chuno:',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
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
                        fontSize: 11,
                        color: Colors.teal.shade700,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),

                // Actual price
                TextField(
                  controller: actualPriceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Actual Price (₹) *',
                    helperText: 'Company ne jis rate pe kharida',
                    prefixIcon: const Icon(Icons.store_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Farmer price
                TextField(
                  controller: farmerPriceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Farmer Price (₹) *',
                    helperText: 'Jo rate farmer ko charge hoga',
                    prefixIcon: const Icon(Icons.person_rounded),
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
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final double qty2 = double.tryParse(qtyCtrl.text) ?? 0.0;
                final double actualPrice =
                    double.tryParse(actualPriceCtrl.text) ?? 0.0;
                final double farmerPrice =
                    double.tryParse(farmerPriceCtrl.text) ?? 0.0;

                if (qty2 <= 0) {
                  Get.snackbar(
                    'Error',
                    'Quantity dalein',
                    backgroundColor: Colors.red,
                    colorText: Colors.white,
                  );
                  return;
                }
                if (actualPrice <= 0) {
                  Get.snackbar(
                    'Error',
                    'Actual price dalein',
                    backgroundColor: Colors.red,
                    colorText: Colors.white,
                  );
                  return;
                }

                if (farmerPrice <= 0) {
                  Get.snackbar(
                    'Error',
                    'Farmer price dalein',
                    backgroundColor: Colors.red,
                    colorText: Colors.white,
                  );
                  return;
                }

                final String addedByName =
                    await SessionService.currentName ?? '';
                final String addedByRole =
                    await SessionService.currentRole ?? '';

                // Shared function — bache hue stock ke saath cost/rate
                // ko weighted-average karega (name se match karke)
                await addOrUpdateMedicinePurchase(
                  name: name,
                  qty: qty2,
                  unit: selectedUnit,
                  actualPrice: actualPrice,
                  farmerPrice: farmerPrice,
                  addedByName: addedByName,
                  addedByRole: addedByRole,
                );

                Navigator.pop(ctx);
                Get.snackbar(
                  'Added ✅',
                  '${qty2.toStringAsFixed(2)} $selectedUnit add ho gaya!',
                  backgroundColor: Colors.green,
                  colorText: Colors.white,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
              ),
              child: const Text(
                'Add Stock',
                style: TextStyle(color: Colors.white),
              ),
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
              title: const Text(
                '💊 Medicine Purchase',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
                        borderRadius: BorderRadius.circular(10),
                      ),
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
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Qty
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setDlg(() {}),
                    decoration: InputDecoration(
                      labelText: 'Total Quantity *',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Unit select
                  const Text(
                    'Unit Chuno *',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
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
                        Icon(
                          Icons.currency_rupee,
                          color: Colors.teal.shade700,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Price Details',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.teal.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Actual price
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
                  const SizedBox(height: 12),

                  // Farmer price
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
                          Get.snackbar(
                            'Error',
                            'Medicine ka naam dalein',
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                          return;
                        }
                        if (qty2 <= 0) {
                          Get.snackbar(
                            'Error',
                            'Quantity dalein',
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                          return;
                        }
                        if (actualPrice <= 0) {
                          Get.snackbar(
                            'Error',
                            'Actual price dalein',
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                          return;
                        }
                        if (farmerPrice <= 0) {
                          Get.snackbar(
                            'Error',
                            'Farmer price dalein',
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                          return;
                        }

                        final String addedByName =
                            await SessionService.currentName ?? '';
                        final String addedByRole =
                            await SessionService.currentRole ?? '';

                        // Naya ho ya same naam ki medicine pehle se ho —
                        // dono cases isi shared function se handle honge
                        // (agar pehle se hai, to bache hue stock ke saath
                        // average ho jayega; naya hai to seedha save hoga).
                        await addOrUpdateMedicinePurchase(
                          name: name,
                          qty: qty2,
                          unit: selectedUnit,
                          actualPrice: actualPrice,
                          farmerPrice: farmerPrice,
                          nickName: nickCtrl.text.trim(),
                          addedByName: addedByName,
                          addedByRole: addedByRole,
                        );

                        Navigator.pop(ctx);
                        Get.snackbar(
                          'Saved ✅',
                          '$name add ho gaya!',
                          backgroundColor: Colors.green,
                          colorText: Colors.white,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Save Karo',
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
    final String? stockJson = await CompanyStore.instance.getString(
      'medicineStockList',
    );
    if (stockJson != null) {
      try {
        final List<dynamic> all = json.decode(stockJson);
        for (final m in all) {
          if (m['id']?.toString() == widget.medicineId) {
            final List<dynamic> hist =
                m['purchaseHistory'] as List<dynamic>? ?? [];
            _history = hist.map((e) => Map<String, dynamic>.from(e)).toList();
            break;
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // ── Recalculate stock totals from remaining history ──
  Future<void> _recalcAndSave(
    List<dynamic> hist,
    List<dynamic> all,
    int medIdx,
  ) async {
    double newTotalBase = 0, newTotalCost = 0;
    double lastFPB = 0;
    for (final h in hist) {
      final double hBase = (h['qtyInBaseUnit'] as num?)?.toDouble() ?? 0;
      final double hAct = (h['actualPrice'] as num?)?.toDouble() ?? 0;
      final double hFPB = (h['perBaseFarmerRate'] as num?)?.toDouble() ?? 0;
      final double hCPB = hBase > 0 ? hAct / hBase : 0;
      newTotalBase += hBase;
      newTotalCost += hBase * hCPB;
      lastFPB = hFPB;
    }
    all[medIdx]['totalBaseQty'] = newTotalBase;
    all[medIdx]['weightedAvgCost'] = newTotalBase > 0
        ? newTotalCost / newTotalBase
        : 0.0;
    if (lastFPB > 0) all[medIdx]['currentFarmerRate'] = lastFPB;
    await CompanyStore.instance.setString(
      'medicineStockList',
      json.encode(all),
    );
  }

  Future<void> _deleteEntry(int index) async {
    final h = _history[index];
    final String hUnit = h['unit']?.toString() ?? widget.unit;
    final double qty = (h['qty'] as num?)?.toDouble() ?? 0;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Karein?'),
        content: Text(
          'Kya aap "${qty.toStringAsFixed(2)} $hUnit" wali purchase '
          'entry delete karna chahte hain?\n\n'
          '⚠️ Stock quantity bhi update hogi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final String? sj = await CompanyStore.instance.getString(
      'medicineStockList',
    );
    if (sj == null) return;
    List<dynamic> all = json.decode(sj);
    for (int i = 0; i < all.length; i++) {
      if (all[i]['id']?.toString() == widget.medicineId) {
        List<dynamic> hist = all[i]['purchaseHistory'] ?? [];
        if (index >= 0 && index < hist.length) hist.removeAt(index);
        all[i]['purchaseHistory'] = hist;
        await _recalcAndSave(hist, all, i);
        break;
      }
    }
    Get.snackbar(
      'Deleted 🗑️',
      'Entry delete ho gaya',
      backgroundColor: Colors.red,
      colorText: Colors.white,
    );
    _load();
  }

  Future<void> _editEntry(int index) async {
    final h = _history[index];
    final String entryUnit = h['unit']?.toString() ?? widget.unit;
    final qtyCtrl = TextEditingController(
      text: (h['qty'] as num?)?.toStringAsFixed(2) ?? '',
    );
    final aCtrl = TextEditingController(
      text: (h['actualPrice'] as num?)?.toStringAsFixed(2) ?? '',
    );
    final fCtrl = TextEditingController(
      text: (h['farmerPrice'] as num?)?.toStringAsFixed(2) ?? '',
    );

    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('✏️ Edit Purchase Entry'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Unit: $entryUnit',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Quantity ($entryUnit)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: aCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Actual Price (₹ total)',
                  helperText: 'Company ne jis rate pe kharida',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: fCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Farmer Price (₹ total)',
                  helperText: 'Jo rate farmer ko charge hoga',
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
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
            ),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (saved != true) return;

    final double qty2 = double.tryParse(qtyCtrl.text) ?? 0;
    final double act = double.tryParse(aCtrl.text) ?? 0;
    final double frm = double.tryParse(fCtrl.text) ?? 0;
    if (qty2 <= 0 || act <= 0) {
      Get.snackbar(
        'Error',
        'Quantity aur actual price zaroori hai',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    final double qBase = convertToBase(qty2, entryUnit, widget.unit) ?? qty2;
    final double cPB = qBase > 0 ? act / qBase : 0;
    final double fPB = qBase > 0 ? frm / qBase : 0;

    final String? sj = await CompanyStore.instance.getString(
      'medicineStockList',
    );
    if (sj == null) return;
    List<dynamic> all = json.decode(sj);
    for (int i = 0; i < all.length; i++) {
      if (all[i]['id']?.toString() == widget.medicineId) {
        List<dynamic> hist = all[i]['purchaseHistory'] ?? [];
        if (index >= 0 && index < hist.length) {
          hist[index] = {
            ...Map<String, dynamic>.from(hist[index]),
            'qty': qty2,
            'qtyInBaseUnit': qBase,
            'actualPrice': act,
            'farmerPrice': frm,
            'perBaseActualCost': cPB,
            'perBaseFarmerRate': fPB,
            'editedOn': DateTime.now().toIso8601String(),
          };
        }
        all[i]['purchaseHistory'] = hist;
        await _recalcAndSave(hist, all, i);
        break;
      }
    }
    Get.snackbar(
      'Updated ✅',
      'Entry update ho gaya',
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
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
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          '💊 ${widget.medicineName} — History',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
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
                final double qty = (h['qty'] as num?)?.toDouble() ?? 0;
                final String hUnit = h['unit']?.toString() ?? widget.unit;
                final double qb =
                    (h['qtyInBaseUnit'] as num?)?.toDouble() ?? qty;
                final double act = (h['actualPrice'] as num?)?.toDouble() ?? 0;
                final double frm = (h['farmerPrice'] as num?)?.toDouble() ?? 0;
                final double cPB =
                    (h['perBaseActualCost'] as num?)?.toDouble() ?? 0;
                final String date = formatHistoryDateTime(
                  h['date']?.toString(),
                );
                final String by = h['addedByName']?.toString() ?? '';
                final String byR = h['addedByRole']?.toString() ?? '';

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
                      // Header: qty + price + Edit + Delete
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${qty.toStringAsFixed(2)} $hUnit',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.teal.shade900,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                '₹${act.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.teal.shade900,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Edit
                              InkWell(
                                onTap: () => _editEntry(i),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.blue.shade200,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.edit_rounded,
                                    size: 14,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Delete
                              InkWell(
                                onTap: () => _deleteEntry(i),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.red.shade200,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.delete_rounded,
                                    size: 14,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (hUnit != widget.unit)
                        Text(
                          '(= ${qb.toStringAsFixed(3)} ${widget.unit})',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        'Actual: ₹${act.toStringAsFixed(2)}  •  Farmer: ₹${frm.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      if (cPB > 0)
                        Text(
                          'Per unit cost: ₹${cPB.toStringAsFixed(2)} / ${widget.unit}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.teal.shade700,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (by.isNotEmpty)
                            Text(
                              '👤 ${byR.isNotEmpty ? "$byR: " : ""}$by',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black45,
                              ),
                            ),
                          Text(
                            '🕒 $date',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black45,
                            ),
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
  final double totalBaseQty = (med['totalBaseQty'] as num?)?.toDouble() ?? 0.0;
  final double weightedAvgCost =
      (med['weightedAvgCost'] as num?)?.toDouble() ?? 0.0;
  final double currentFarmerRate =
      (med['currentFarmerRate'] as num?)?.toDouble() ?? 0.0;

  // Already allocated
  final List<Map<String, dynamic>> allocs = List<Map<String, dynamic>>.from(
    (med['allocations'] as List<dynamic>?)?.map(
          (e) => Map<String, dynamic>.from(e as Map),
        ) ??
        [],
  );
  double allocatedBase = 0;
  for (final a in allocs) {
    allocatedBase +=
        (a['qtyInBaseUnit'] as num?)?.toDouble() ??
        (a['qty'] as num?)?.toDouble() ??
        0.0;
  }

  // Private sales bhi minus karo
  double soldBase = 0;
  final String? salesJson = await CompanyStore.instance.getString(
    'medicineSalesHistory',
  );
  if (salesJson != null) {
    try {
      final List<dynamic> rawSales = json.decode(salesJson);
      for (final sale in rawSales) {
        final List<dynamic> items = sale['items'] as List<dynamic>? ?? [];
        for (final item in items) {
          if (item['medicineId']?.toString() == mId) {
            soldBase +=
                (item['qtyInBaseUnit'] as num?)?.toDouble() ??
                (item['qty'] as num?)?.toDouble() ??
                0.0;
          }
        }
      }
    } catch (_) {}
  }

  double availBase = (totalBaseQty - allocatedBase - soldBase).clamp(
    0.0,
    double.infinity,
  );

  // Company farmers
  List<dynamic> rawFarmers = await CompanyStore.instance.getJsonList(
    'companyFarmers',
  );
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
  final rateCtrl = TextEditingController(
    text: currentFarmerRate > 0 ? currentFarmerRate.toStringAsFixed(2) : '',
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
          final double saleRate = double.tryParse(rateCtrl.text) ?? 0.0;
          final bool isOver = qtyBase > availBase;
          final double availInSelected =
              convertFromBase(availBase, baseUnit, selectedUnit) ?? availBase;
          final double totalCost = qtyBase * weightedAvgCost;
          final double totalBill = qtyBase * saleRate;
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
                  fontSize: 15,
                ),
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
                          fontSize: 14,
                        ),
                      ),
                      if (weightedAvgCost > 0)
                        Text(
                          'Avg Cost: ₹${weightedAvgCost.toStringAsFixed(2)} / $baseUnit',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
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
                            labelText: 'Apna Farmer Search Karein *',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: selectedFarmer != null
                                ? const Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.green,
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
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
                            constraints: const BoxConstraints(maxHeight: 150),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.teal.shade200),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Builder(
                              builder: (cx) {
                                final q = farmerSearchCtrl.text.toLowerCase();
                                final filtered = farmerOptions
                                    .where((f) => f.toLowerCase().contains(q))
                                    .toList();
                                if (filtered.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text(
                                      'Koi farmer nahi mila',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  );
                                }
                                return ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: filtered.length,
                                  itemBuilder: (cx2, fi) {
                                    return InkWell(
                                      onTap: () => setDlg(() {
                                        selectedFarmer = filtered[fi];
                                        farmerSearchCtrl.text = filtered[fi];
                                        dropdownVisible = false;
                                      }),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        child: Text(
                                          filtered[fi],
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),

                        // Unit select for allocation
                        const Text(
                          'Unit Chuno:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                                      if (v) {
                                        setDlg(() {
                                          selectedUnit = u;
                                          // Rate update — convert per base to per selected
                                          if (currentFarmerRate > 0) {
                                            final double perSelected =
                                                convertFromBase(
                                                  currentFarmerRate,
                                                  baseUnit,
                                                  u,
                                                ) ??
                                                currentFarmerRate;
                                            rateCtrl.text = perSelected
                                                .toStringAsFixed(2);
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
                            color: isOver ? Colors.red.shade50 : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isOver
                                  ? Colors.red.shade300
                                  : Colors.grey.shade300,
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
                                    '💊 ${med['name']}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.teal.shade900,
                                    ),
                                  ),
                                  Text(
                                    'Max: ${availInSelected.toStringAsFixed(2)} $selectedUnit',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isOver
                                          ? Colors.red.shade700
                                          : Colors.green.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              if (weightedAvgCost > 0)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 3,
                                    bottom: 3,
                                  ),
                                  child: Text(
                                    'Auto Cost: ₹${weightedAvgCost.toStringAsFixed(2)} / $baseUnit',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: qtyCtrl,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
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
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      onChanged: (_) => setDlg(() {}),
                                      decoration: InputDecoration(
                                        labelText: 'Rate (₹/$selectedUnit)',
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
                                      color: Colors.teal.shade700,
                                    ),
                                  ),
                                ),
                              if (hasCalc) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: profit >= 0
                                        ? Colors.teal.shade50
                                        : Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: profit >= 0
                                          ? Colors.teal.shade200
                                          : Colors.orange.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Cost: ₹${totalCost.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      Text(
                                        'Bill: ₹${totalBill.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.black54,
                                        ),
                                      ),
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
                        final String farmerName =
                            (selectedFarmer ?? farmerSearchCtrl.text).trim();
                        final double qty2 =
                            double.tryParse(qtyCtrl.text) ?? 0.0;
                        final double qtyBase2 =
                            convertToBase(qty2, selectedUnit, baseUnit) ?? qty2;
                        final double rate =
                            double.tryParse(rateCtrl.text) ?? 0.0;

                        if (farmerName.isEmpty) {
                          Get.snackbar(
                            'Error',
                            'Farmer select karein.',
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
                          return;
                        }
                        if (qty2 <= 0) {
                          Get.snackbar(
                            'Error',
                            'Quantity dalein.',
                            backgroundColor: Colors.red,
                            colorText: Colors.white,
                          );
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
                        final String? stockJson = await CompanyStore.instance
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
                              'id': DateTime.now().millisecondsSinceEpoch
                                  .toString(),
                              'farmerName': farmerName,
                              'qty': qty2,
                              'unit': selectedUnit,
                              'qtyInBaseUnit': qtyBase2,
                              'rate': rate,
                              // ✅ NEW: cost snapshot (historical, non-changing)
                              'costAtAllocation':
                                  (all[i]['weightedAvgCost'] as num?)
                                      ?.toDouble() ??
                                  0.0,
                              'allocatedOn': DateTime.now().toIso8601String(),
                              'allocatedByName': allocByName,
                              'allocatedByRole': allocByRole,
                            });
                            all[i]['allocations'] = allocList;
                            break;
                          }
                        }
                        await CompanyStore.instance.setString(
                          'medicineStockList',
                          json.encode(all),
                        );

                        Navigator.pop(ctx);
                        Get.snackbar(
                          'Saved ✅',
                          '${qty2.toStringAsFixed(2)} $selectedUnit allocate ho gaya!',
                          backgroundColor: Colors.green,
                          colorText: Colors.white,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Save Allocation',
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
    final String? stockJson = await CompanyStore.instance.getString(
      'medicineStockList',
    );
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
      (found['allocations'] as List<dynamic>?)?.map(
            (e) => Map<String, dynamic>.from(e as Map),
          ) ??
          [],
    );
    final alloc = (widget.allocIndex >= 0 && widget.allocIndex < allocs.length)
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
    final double totalBase = (_med!['totalBaseQty'] as num?)?.toDouble() ?? 0.0;
    final allocs = List<Map<String, dynamic>>.from(
      (_med!['allocations'] as List<dynamic>?)?.map(
            (e) => Map<String, dynamic>.from(e as Map),
          ) ??
          [],
    );
    double allocElsewhere = 0;
    for (int i = 0; i < allocs.length; i++) {
      if (i == widget.allocIndex) continue;
      allocElsewhere +=
          (allocs[i]['qtyInBaseUnit'] as num?)?.toDouble() ??
          (allocs[i]['qty'] as num?)?.toDouble() ??
          0.0;
    }
    final double availBase = totalBase - allocElsewhere;
    return convertFromBase(availBase, baseUnit, _selectedUnit) ?? availBase;
  }

  Future<void> _save() async {
    final String baseUnit = _med!['unit']?.toString() ?? 'ml';
    final double qty = double.tryParse(_qtyCtrl.text) ?? 0.0;
    final double qtyBase = convertToBase(qty, _selectedUnit, baseUnit) ?? qty;
    final double avail = _availForEdit();

    if (qty > avail) {
      Get.snackbar(
        'Error',
        'Sirf ${avail.toStringAsFixed(2)} $baseUnit available hai.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    final String? stockJson = await CompanyStore.instance.getString(
      'medicineStockList',
    );
    List<dynamic> all = [];
    if (stockJson != null) {
      try {
        all = json.decode(stockJson);
      } catch (_) {}
    }
    for (int i = 0; i < all.length; i++) {
      if (all[i]['id']?.toString() == widget.medicineId) {
        List<dynamic> allocList = all[i]['allocations'] ?? [];
        if (widget.allocIndex >= 0 && widget.allocIndex < allocList.length) {
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
      'medicineStockList',
      json.encode(all),
    );
    Get.back(result: true);
    Get.snackbar(
      'Updated ✅',
      'Allocation update ho gaya',
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  Future<void> _delete() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Karein?'),
        content: const Text(
          'Kya aap is allocation ko delete karna chahte hain?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final String? stockJson = await CompanyStore.instance.getString(
      'medicineStockList',
    );
    List<dynamic> all = [];
    if (stockJson != null) {
      try {
        all = json.decode(stockJson);
      } catch (_) {}
    }
    for (int i = 0; i < all.length; i++) {
      if (all[i]['id']?.toString() == widget.medicineId) {
        List<dynamic> allocList = all[i]['allocations'] ?? [];
        if (widget.allocIndex >= 0 && widget.allocIndex < allocList.length) {
          allocList.removeAt(widget.allocIndex);
        }
        all[i]['allocations'] = allocList;
        break;
      }
    }
    await CompanyStore.instance.setString(
      'medicineStockList',
      json.encode(all),
    );
    Get.back(result: true);
    Get.snackbar(
      'Deleted 🗑️',
      'Allocation delete ho gaya',
      backgroundColor: Colors.red,
      colorText: Colors.white,
    );
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
    final double qtyBase = convertToBase(qty, _selectedUnit, baseUnit) ?? qty;
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
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          _isEditMode ? 'Edit Allocation' : 'Farmer Allocation',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isEditMode ? Icons.close_rounded : Icons.edit_rounded,
              color: Colors.white,
            ),
            onPressed: () => setState(() => _isEditMode = !_isEditMode),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.teal.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '💊 $name',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade900,
                ),
              ),
            ),
            // ✅ NEW: Batch ID badge — jis farmer-batch mein ye medicine gaya
            if (_alloc?['batchId']?.toString().isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Text(
                  '🏷️ Batch: ${_alloc!['batchId']}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple.shade800,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              enabled: _isEditMode,
              decoration: InputDecoration(
                labelText: 'Farmer Ka Naam',
                prefixIcon: const Icon(Icons.person_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Unit select (edit mode only)
            if (_isEditMode) ...[
              const Text(
                'Unit:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
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
                          ? (_selectedUnit == u ? Colors.white : Colors.black87)
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
                  color: isOver ? Colors.red.shade300 : Colors.grey.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '💊 $name',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.teal.shade900,
                        ),
                      ),
                      if (_isEditMode)
                        Text(
                          'Max: ${_availForEdit().toStringAsFixed(2)} $_selectedUnit',
                          style: TextStyle(
                            fontSize: 11,
                            color: isOver
                                ? Colors.red.shade700
                                : Colors.green.shade700,
                            fontWeight: FontWeight.bold,
                          ),
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
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _qtyCtrl,
                          enabled: _isEditMode,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
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
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
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
                      child: Text(
                        '= ${qtyBase.toStringAsFixed(3)} $baseUnit',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.teal.shade700,
                        ),
                      ),
                    ),
                  if (hasCalc) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: profit >= 0
                            ? Colors.teal.shade50
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: profit >= 0
                              ? Colors.teal.shade200
                              : Colors.orange.shade200,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Cost: ₹${totalCost.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                          Text(
                            'Bill: ₹${totalBilling.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
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
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            if (_alloc?['allocatedOn'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '🕒 ${formatHistoryDateTime(_alloc!['allocatedOn']?.toString())}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
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
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 👨‍🌾 CENTRAL ALLOCATE MEDICINE TO FARMER SCREEN
// Ek farmer ko ek baar mein multiple medicines allocate karo
// ═══════════════════════════════════════════════════════════════════════════
class AllocateMedicineToFarmerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> medicines;
  final Map<String, double> availBaseQty; // mId → available base qty

  const AllocateMedicineToFarmerScreen({
    super.key,
    required this.medicines,
    required this.availBaseQty,
  });

  @override
  State<AllocateMedicineToFarmerScreen> createState() =>
      _AllocateMedicineToFarmerScreenState();
}

class _AllocateMedicineToFarmerScreenState
    extends State<AllocateMedicineToFarmerScreen> {
  // Farmer search
  final _farmerSearchCtrl = TextEditingController();
  String? _selectedFarmer;
  String? _selectedFarmerId; // ✅ NEW: batch link/create ke liye
  Map<String, String> _farmerDisplayToId = {}; // ✅ NEW
  bool _dropdownVisible = false;
  List<String> _farmerOptions = [];

  // Medicine search — poore lots ki list yahin available rehti hai,
  // lekin form sirf usi medicine ka dikhta hai jise search karke choose kiya ho
  // [{med, saleUnit, qtyCtrl}]
  List<Map<String, dynamic>> _medicineRows = [];
  final _medicineSearchCtrl = TextEditingController();
  bool _medicineDropdownVisible = false;
  // Indices (in _medicineRows) jo user ne search karke select kiye hain —
  // ek se zyada medicine bhi ek hi farmer ko diya ja sakta hai, isliye List hai
  List<int> _selectedIndices = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
    // ✅ FIX: Pehle yahan _farmerSearchCtrl.addListener() tha jo controller
    // ki HAR .text change par fire hota tha — including jab dropdown se
    // farmer select karne par hum khud `_farmerSearchCtrl.text = option;`
    // set karte the! Isse listener turant _selectedFarmer/_selectedFarmerId
    // ko wapas null kar deta tha (race condition), aur Save button hamesha
    // "Farmer Select Karein" bolta rehta tha chahe farmer select kiya ho.
    // Ab TextField ke `onChanged` (neeche) mein hi reset hota hai — wo sirf
    // real typing par fire hota hai, programmatic assignment par nahi.
    _medicineSearchCtrl.addListener(
      () => setState(() {
        _medicineDropdownVisible = _medicineSearchCtrl.text.isNotEmpty;
      }),
    );
  }

  Future<void> _init() async {
    // Load farmers
    List<dynamic> rawFarmers = await CompanyStore.instance.getJsonList(
      'companyFarmers',
    );
    final farmers = rawFarmers.map((f) {
      return '${f['name'] ?? 'Unknown'} - ${f['phone'] ?? ''} - ${f['district'] ?? ''}';
    }).toList();
    // ✅ NEW: display-string → farmerId map
    final Map<String, String> displayToId = {};
    for (int fi = 0; fi < rawFarmers.length; fi++) {
      displayToId[farmers[fi]] = rawFarmers[fi]['id']?.toString() ?? '';
    }

    // Build medicine rows — only those with available qty > 0
    final rows = <Map<String, dynamic>>[];
    for (final med in widget.medicines) {
      final String mId = med['id']?.toString() ?? '';
      final double avail = widget.availBaseQty[mId] ?? 0.0;
      if (avail <= 0) continue;
      final String bu = med['unit']?.toString() ?? 'unit';
      rows.add({
        'med': med,
        'mId': mId,
        'saleUnit': bu, // default = base unit
        'qtyCtrl': TextEditingController(),
      });
    }

    if (mounted) {
      setState(() {
        _farmerOptions = farmers;
        _farmerDisplayToId = displayToId;
        _medicineRows = rows;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _farmerSearchCtrl.dispose();
    _medicineSearchCtrl.dispose();
    for (final row in _medicineRows) {
      (row['qtyCtrl'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  // Total bill preview — sirf selected (search se chuni gayi) medicines ka
  double _totalBill() {
    double total = 0;
    for (final idx in _selectedIndices) {
      final row = _medicineRows[idx];
      final med = row['med'] as Map<String, dynamic>;
      final String bu = med['unit']?.toString() ?? '';
      final String su = row['saleUnit']?.toString() ?? bu;
      final double qty =
          double.tryParse((row['qtyCtrl'] as TextEditingController).text) ?? 0;
      final double qb = convertToBase(qty, su, bu) ?? qty;
      final double fRatePB =
          (med['currentFarmerRate'] as num?)?.toDouble() ?? 0;
      total += qb * fRatePB;
    }
    return total;
  }

  Future<void> _save() async {
    final String farmerName = (_selectedFarmer ?? _farmerSearchCtrl.text)
        .trim();
    if (farmerName.isEmpty) {
      Get.snackbar(
        'Error',
        'Farmer select karein',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    // Check at least one medicine search karke select ki gayi hai
    if (_selectedIndices.isEmpty) {
      Get.snackbar(
        'Error',
        'Kam se kam ek medicine search karke select karein',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    // Check at least one qty entered (selected medicines mein se)
    final hasAny = _selectedIndices.any((idx) {
      final row = _medicineRows[idx];
      final double qty =
          double.tryParse((row['qtyCtrl'] as TextEditingController).text) ?? 0;
      return qty > 0;
    });
    if (!hasAny) {
      Get.snackbar(
        'Error',
        'Kam se kam ek medicine ki qty dalein',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    // Validate each selected row
    for (final idx in _selectedIndices) {
      final row = _medicineRows[idx];
      final med = row['med'] as Map<String, dynamic>;
      final String mId = row['mId']?.toString() ?? '';
      final String bu = med['unit']?.toString() ?? '';
      final String su = row['saleUnit']?.toString() ?? bu;
      final double qty =
          double.tryParse((row['qtyCtrl'] as TextEditingController).text) ?? 0;
      if (qty <= 0) continue; // skip empty rows
      final double qb = convertToBase(qty, su, bu) ?? qty;
      final double avail = widget.availBaseQty[mId] ?? 0;
      if (qb > avail) {
        final double av = convertFromBase(avail, bu, su) ?? avail;
        Get.snackbar(
          'Error',
          '${med['name']}: sirf ${av.toStringAsFixed(2)} $su available hai',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }
    }

    // ✅ NEW: farmerId zaroori hai batch link karne ke liye
    if (_selectedFarmerId == null || _selectedFarmerId!.isEmpty) {
      Get.snackbar(
        'Farmer Select Karein ⚠️',
        'Kripya dropdown list se hi farmer select karein.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    // ✅ NEW: Farmer ka batch dhoondo (running ya back/completed)
    List<Map<String, dynamic>> farmersForBatch = await CompanyStore.instance
        .getJsonList('companyFarmers');
    Map<String, dynamic>? farmerMap;
    int farmerIdxInList = -1;
    for (int fi = 0; fi < farmersForBatch.length; fi++) {
      if (farmersForBatch[fi]['id']?.toString() == _selectedFarmerId) {
        farmerMap = Map<String, dynamic>.from(farmersForBatch[fi]);
        farmerIdxInList = fi;
        break;
      }
    }
    if (farmerMap == null) {
      Get.snackbar(
        'Error',
        'Farmer record nahi mila.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    String? linkedBatchId;
    final runningBatch = findRunningBatch(farmerMap);
    if (runningBatch != null) {
      linkedBatchId = runningBatch['batchId']?.toString();
    } else {
      final completedBatches = findCompletedBatches(farmerMap);
      final String? choice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text('Batch Nahi Mila ⚠️'),
          content: Text(
            '$farmerName ka koi RUNNING batch nahi hai.\n\n'
            'Kya ye medicine kisi NAYE batch ke liye hai (jo abhi banega), '
            'ya kisi PURANE (completed) batch ke liye hai?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            if (completedBatches.isNotEmpty)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'old'),
                child: const Text('Purane Batch Ka'),
              ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'new'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
              ),
              child: const Text(
                'Naya Batch',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );

      if (choice == null || choice == 'cancel') return;

      if (choice == 'old') {
        final Map<String, dynamic>?
        picked = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Batch Chuniye'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: completedBatches.length,
                itemBuilder: (c, bi) {
                  final b = completedBatches[bi];
                  return ListTile(
                    title: Text(b['batchId']?.toString() ?? '-'),
                    subtitle: Text(
                      '${b['chicksCount']} chicks | ${b['startDate'] ?? ''}',
                    ),
                    onTap: () => Navigator.pop(ctx, b),
                  );
                },
              ),
            ),
          ),
        );
        if (picked == null) return;
        linkedBatchId = picked['batchId']?.toString();
      }
      // choice == 'new' → linkedBatchId null hi rahega (purana behavior)
    }

    final String byName = await SessionService.currentName ?? '';
    final String byRole = await SessionService.currentRole ?? '';
    final String allocId = DateTime.now().millisecondsSinceEpoch.toString();
    final String allocDate = DateTime.now().toIso8601String();

    // Load stock
    final String? sj = await CompanyStore.instance.getString(
      'medicineStockList',
    );
    List<dynamic> all = sj != null ? json.decode(sj) : [];

    // Add allocation entry to each selected medicine that has qty > 0
    for (final idx in _selectedIndices) {
      final row = _medicineRows[idx];
      final med = row['med'] as Map<String, dynamic>;
      final String mId = row['mId']?.toString() ?? '';
      final String bu = med['unit']?.toString() ?? '';
      final String su = row['saleUnit']?.toString() ?? bu;
      final double qty =
          double.tryParse((row['qtyCtrl'] as TextEditingController).text) ?? 0;
      if (qty <= 0) continue;
      final double qb = convertToBase(qty, su, bu) ?? qty;
      final double fRatePB =
          (med['currentFarmerRate'] as num?)?.toDouble() ?? 0;
      final double fRateSu = pricePerUnit(fRatePB, bu, su) ?? fRatePB;

      for (int i = 0; i < all.length; i++) {
        if (all[i]['id']?.toString() == mId) {
          List<dynamic> allocs = all[i]['allocations'] ?? [];
          allocs.add({
            'id': '$allocId-$mId',
            'groupId': allocId, // same group = same allocation session
            'farmerName': farmerName,
            'farmerId': _selectedFarmerId, // ✅ NEW
            'batchId': linkedBatchId, // ✅ NEW: is batch ko gaya
            'qty': qty,
            'unit': su,
            'qtyInBaseUnit': qb,
            'rate': fRateSu,
            'ratePerBase': fRatePB,
            // ✅ NEW: Is waqt ka actual purchase avg cost (per base unit)
            // snapshot karke save karo — taaki baad mein naye medicine
            // purchase se is batch ka calculated income retroactively na
            // badle (report screen isi field ko cost basis maanega).
            'costAtAllocation':
                (all[i]['weightedAvgCost'] as num?)?.toDouble() ?? 0.0,
            'allocatedOn': allocDate,
            'allocatedByName': byName,
            'allocatedByRole': byRole,
          });
          all[i]['allocations'] = allocs;
          break;
        }
      }

      // ✅ NEW: Agar batch mila (running ya back), to us batch ki
      // dailyEntries mein seedha medicine-entry add karo — taaki
      // Batch Tracking Details/Data Sheet mein wahi se dikhe.
      if (linkedBatchId != null && farmerIdxInList >= 0) {
        final target = farmersForBatch[farmerIdxInList];
        for (var b in (target['batches'] ?? [])) {
          if (b['batchId']?.toString() == linkedBatchId) {
            final now = DateTime.now();
            final dateStr =
                '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
            b['dailyEntries'] ??= [];
            b['dailyEntries'].add({
              'type': 'medicine',
              'date': dateStr,
              'medicineName': med['name'] ?? '',
              'quantity': qty,
              'unit': su,
              'price': qb * fRatePB,
              'stockLinked': true,
              'enteredBy': byRole,
              'timestamp': now.toIso8601String(),
              'source': 'medicineAllocation',
            });
            break;
          }
        }
      }
    }

    if (linkedBatchId != null) {
      await CompanyStore.instance.saveJsonList(
        'companyFarmers',
        farmersForBatch,
      );
    }

    await CompanyStore.instance.setString(
      'medicineStockList',
      json.encode(all),
    );
    Get.back(result: true);
    Get.snackbar(
      'Allocated ✅',
      '$farmerName ko medicines allocate ho gayi',
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final double bill = _totalBill();
    final bool hasAvail = _medicineRows.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.orange.shade700,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: const Row(
          children: [
            Text('👨‍🌾', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text(
              'Allocate to Farmer',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Farmer search ──
                  const Text(
                    '👨‍🌾 Farmer Select Karein',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _farmerSearchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Naam, Mobile ya Jagah se search karein...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _selectedFarmer != null
                          ? const Icon(
                              Icons.check_circle_rounded,
                              color: Colors.green,
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.orange.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.orange.shade600,
                          width: 2,
                        ),
                      ),
                      helperText: _selectedFarmer != null
                          ? '✅ $_selectedFarmer'
                          : null,
                      helperMaxLines: 2,
                    ),
                    onChanged: (_) => setState(() {
                      _dropdownVisible = _farmerSearchCtrl.text.isNotEmpty;
                      _selectedFarmer = null;
                      _selectedFarmerId = null;
                    }),
                  ),

                  // Dropdown
                  if (_dropdownVisible &&
                      _farmerSearchCtrl.text.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 160),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.07),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Builder(
                        builder: (cx) {
                          final q = _farmerSearchCtrl.text.toLowerCase();
                          final filtered = _farmerOptions
                              .where((f) => f.toLowerCase().contains(q))
                              .toList();
                          if (filtered.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'Koi farmer nahi mila',
                                style: TextStyle(color: Colors.grey),
                              ),
                            );
                          }
                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            itemBuilder: (cx2, fi) => InkWell(
                              onTap: () => setState(() {
                                _selectedFarmer = filtered[fi];
                                _selectedFarmerId =
                                    _farmerDisplayToId[filtered[fi]];
                                _farmerSearchCtrl.text = filtered[fi];
                                _dropdownVisible = false;
                              }),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Text(
                                  filtered[fi],
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ── Medicine search + selected rows ──
                  if (!hasAvail)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Center(
                        child: Text(
                          '⚠️ Koi medicine available nahi hai.\nPehle purchase karein.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.orange.shade800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  else ...[
                    const Text(
                      '💊 Medicine Select Karein',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _medicineSearchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Naam ya nickname se search karein...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.orange.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.orange.shade600,
                            width: 2,
                          ),
                        ),
                      ),
                    ),

                    // Search dropdown — sirf abhi tak select na ki gayi medicines
                    if (_medicineDropdownVisible &&
                        _medicineSearchCtrl.text.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.07),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Builder(
                          builder: (cx) {
                            final q = _medicineSearchCtrl.text.toLowerCase();
                            final List<int> filtered = [];
                            for (int i = 0; i < _medicineRows.length; i++) {
                              if (_selectedIndices.contains(i)) continue;
                              final med =
                                  _medicineRows[i]['med']
                                      as Map<String, dynamic>;
                              final String name =
                                  (med['name']?.toString() ?? '').toLowerCase();
                              final String nick =
                                  (med['nickName']?.toString() ?? '')
                                      .toLowerCase();
                              if (name.contains(q) || nick.contains(q)) {
                                filtered.add(i);
                              }
                            }
                            if (filtered.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text(
                                  'Koi medicine nahi mili',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              );
                            }
                            return ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              itemBuilder: (cx2, fi) {
                                final idx = filtered[fi];
                                final med =
                                    _medicineRows[idx]['med']
                                        as Map<String, dynamic>;
                                final String name =
                                    med['name']?.toString() ?? '-';
                                final String nick =
                                    med['nickName']?.toString() ?? '';
                                return InkWell(
                                  onTap: () => setState(() {
                                    _selectedIndices.add(idx);
                                    _medicineSearchCtrl.clear();
                                    _medicineDropdownVisible = false;
                                  }),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        const Text(
                                          '💊',
                                          style: TextStyle(fontSize: 14),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              if (nick.isNotEmpty)
                                                Text(
                                                  '"$nick"',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // ── Selected medicines ke fill-forms ──
                    if (_selectedIndices.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Upar search karke medicine choose karein — usi ka fill karne ka form yahan aayega.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      )
                    else
                      ..._selectedIndices
                          .map((idx) => _medicineRow(idx))
                          .toList(),
                  ],

                  const SizedBox(height: 16),

                  // ── Bill preview ──
                  if (bill > 0)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Farmer Bill:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '₹${bill.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Save button ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            color: Colors.white,
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: hasAvail ? _save : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Save Allocation',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _medicineRow(int index) {
    final row = _medicineRows[index];
    final med = row['med'] as Map<String, dynamic>;
    final String mId = row['mId']?.toString() ?? '';
    final String bu = med['unit']?.toString() ?? 'unit';
    final String su = row['saleUnit']?.toString() ?? bu;
    final String name = med['name']?.toString() ?? '-';
    final String nick = med['nickName']?.toString() ?? '';
    final double fRatePB = (med['currentFarmerRate'] as num?)?.toDouble() ?? 0;
    final double avgCostPB = (med['weightedAvgCost'] as num?)?.toDouble() ?? 0;
    final double availBase = widget.availBaseQty[mId] ?? 0;
    final double availSu = convertFromBase(availBase, bu, su) ?? availBase;

    final qCtrl = row['qtyCtrl'] as TextEditingController;
    final double qty = double.tryParse(qCtrl.text) ?? 0;
    final double qb = convertToBase(qty, su, bu) ?? qty;
    final bool isOver = qb > availBase && availBase >= 0;

    // Rate in sale unit (CORRECT price conversion)
    final double fRateSu = pricePerUnit(fRatePB, bu, su) ?? fRatePB;
    final double costSu = pricePerUnit(avgCostPB, bu, su) ?? avgCostPB;
    final double itemBill = qb * fRatePB;
    final double itemCost = qb * avgCostPB;
    final double itemProf = itemBill - itemCost;
    final bool hasCalc = qty > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: qty > 0 ? Colors.white : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOver
              ? Colors.red.shade300
              : qty > 0
              ? Colors.orange.shade300
              : Colors.grey.shade300,
          width: qty > 0 ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: qty > 0 ? Colors.orange.shade50 : Colors.grey.shade100,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Text('💊', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: qty > 0
                              ? Colors.orange.shade900
                              : Colors.grey.shade600,
                        ),
                      ),
                      if (nick.isNotEmpty)
                        Text(
                          '"$nick"',
                          style: TextStyle(
                            fontSize: 11,
                            color: qty > 0
                                ? Colors.orange.shade700
                                : Colors.grey.shade500,
                          ),
                        ),
                    ],
                  ),
                ),
                // Available badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Text(
                    '${availSu.toStringAsFixed(2)} $su left',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
                // Remove — galti se select ho gayi ho to hata sakein
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Colors.grey.shade500,
                  ),
                  tooltip: 'Hatayein',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    qCtrl.clear();
                    _selectedIndices.remove(index);
                  }),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Unit chips
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: kMedicineUnits.map((u) {
                    final bool enabled = canConvert(u, bu);
                    return ChoiceChip(
                      label: Text(u, style: const TextStyle(fontSize: 11)),
                      selected: su == u,
                      onSelected: enabled
                          ? (v) {
                              if (!v) return;
                              setState(() {
                                _medicineRows[index]['saleUnit'] = u;
                                // Reset qty on unit change to avoid confusion
                                qCtrl.clear();
                              });
                            }
                          : null,
                      selectedColor: Colors.orange.shade700,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 0,
                      ),
                      labelStyle: TextStyle(
                        color: !enabled
                            ? Colors.grey.shade400
                            : su == u
                            ? Colors.white
                            : Colors.black87,
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 10),

                // Qty + farmer rate info
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qCtrl,
                        onChanged: (_) => setState(() {}),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Qty ($su)',
                          isDense: true,
                          errorText: isOver
                              ? 'Max ${availSu.toStringAsFixed(2)}'
                              : null,
                          helperText: fRateSu > 0
                              ? 'Rate: ₹${fRateSu.toStringAsFixed(2)} / $su'
                              : null,
                          helperStyle: const TextStyle(
                            fontSize: 10,
                            color: Colors.black45,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    // Cost per unit info
                    if (costSu > 0) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cost / $su',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                '₹${costSu.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                // Conversion display
                if (su != bu && qty > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '= ${qb.toStringAsFixed(3)} $bu',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),

                // Mini P&L
                if (hasCalc) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: itemProf >= 0
                          ? Colors.teal.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: itemProf >= 0
                            ? Colors.teal.shade200
                            : Colors.orange.shade200,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Cost: ₹${itemCost.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                        Text(
                          'Bill: ₹${itemBill.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                        Text(
                          itemProf >= 0
                              ? '📈 +₹${itemProf.toStringAsFixed(0)}'
                              : '📉 -₹${itemProf.abs().toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: itemProf >= 0
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
    );
  }
}
