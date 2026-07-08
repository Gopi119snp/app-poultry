import 'dart:convert';
import 'package:flutter/material.dart';

// =============================================================================
// 🎛️ 1. CHHOTI COMPANY SETTLEMENT CONFIGURATION MODEL
// =============================================================================
enum SimpleMedicineTreatment { includeInProdCost, deductFromEarning }

class SimpleCompanyConfig {
  double standardRearingRatePerKg;
  double chickPricePerPiece;
  double targetProductionCostPerKg;
  double farmerSavingsSharePercentage;
  double farmerPenaltySharePercentage;
  double minRearingRateGuarantee;
  double kgPerBag;
  double feedRate;
  double adminCostPerKg;
  SimpleMedicineTreatment medicineTreatment;

  // ── ✅ NAYE RATE BONUS PARAMETERS ─────────────────────────────────────────
  // Rate bonus milega jab:
  // 1. Actual production cost <= targetProductionCostPerKg
  // 2. Avg sale rate >= rateBonusThreshold
  // Jitna rupya sale rate threshold se upar hoga, uska rateBonusSharePercentage% milega
  double rateBonusThreshold; // e.g. 110.00 ₹/KG
  double
  rateBonusSharePercentage; // e.g. 10 matlab 10% of (saleRate - threshold)

  SimpleCompanyConfig({
    required this.standardRearingRatePerKg,
    required this.chickPricePerPiece,
    required this.targetProductionCostPerKg,
    required this.farmerSavingsSharePercentage,
    required this.farmerPenaltySharePercentage,
    required this.minRearingRateGuarantee,
    required this.kgPerBag,
    required this.feedRate,
    required this.adminCostPerKg,
    required this.medicineTreatment,
    this.rateBonusThreshold = 110.0,
    this.rateBonusSharePercentage = 10.0,
  });
}

// =============================================================================
// 🧮 2. SIMPLE BATCH SETTLEMENT COMPUTATION ENGINE
// =============================================================================
class SimpleSettlementResult {
  double totalWeightSoldKg;
  double totalChickCost;
  double totalFeedCost;
  double totalAdminCost;
  double totalMedicineCost;
  double totalProductionCost;
  double actualProductionCostPerKg;
  double costDifferencePerKg;
  double efficiencyBonusOrPenaltyPerKg;
  double rateBonusPerKg; // ✅ NEW
  bool rateBonusApplied; // ✅ NEW
  double finalRearingRateApplied;
  double grossFarmerEarning;
  double netPayoutToFarmer;

  SimpleSettlementResult({
    required this.totalWeightSoldKg,
    required this.totalChickCost,
    required this.totalFeedCost,
    required this.totalAdminCost,
    required this.totalMedicineCost,
    required this.totalProductionCost,
    required this.actualProductionCostPerKg,
    required this.costDifferencePerKg,
    required this.efficiencyBonusOrPenaltyPerKg,
    required this.rateBonusPerKg,
    required this.rateBonusApplied,
    required this.finalRearingRateApplied,
    required this.grossFarmerEarning,
    required this.netPayoutToFarmer,
  });
}

class SimpleBatchSettlementEngine {
  static SimpleSettlementResult processSimpleBatch({
    required SimpleCompanyConfig config,
    required Map<String, dynamic> batchData,
    required List<dynamic> dailyEntries,
  }) {
    int totalChicksHoused = batchData['chicksCount'] ?? 0;
    double totalWeightSoldKg = 0.0;
    double totalSaleMoney = 0.0;
    double calculatedMedicineCostSum = 0.0;
    int totalFeedBagsCount = 0;

    double totalChickCostAllotted =
        totalChicksHoused * config.chickPricePerPiece;

    for (var entry in dailyEntries) {
      String type = entry['type'].toString().toLowerCase();
      if (type == 'sale') {
        totalWeightSoldKg +=
            double.tryParse(entry['totalWeightSold'].toString()) ?? 0.0;
        totalSaleMoney +=
            double.tryParse(entry['totalMoney'].toString()) ?? 0.0;
      } else if (type == 'feed_dispatch' || type == 'cost') {
        int bagsCount = int.tryParse(entry['feedBags'].toString()) ?? 0;
        if (bagsCount > 0) totalFeedBagsCount += bagsCount;
      } else if (type == 'medicine') {
        double medPrice = double.tryParse(entry['price'].toString()) ?? 0.0;
        calculatedMedicineCostSum += medPrice;
      }
    }

    // ✅ Bags -> KG -> cost, seedhe formula se (perBag "fix" allocation mode
    // hata diya gaya, ab hamesha bag ka actual kg-weight use hoga).
    double totalKgConsumed = totalFeedBagsCount * config.kgPerBag;
    double totalFeedCostAllotted = totalKgConsumed * config.feedRate;

    double totalAdminCostSum = totalWeightSoldKg * config.adminCostPerKg;
    double totalProductionCostSum =
        totalChickCostAllotted + totalFeedCostAllotted + totalAdminCostSum;

    if (config.medicineTreatment == SimpleMedicineTreatment.includeInProdCost) {
      totalProductionCostSum += calculatedMedicineCostSum;
    }

    double actualProdCostPerKgMetric = totalWeightSoldKg > 0
        ? (totalProductionCostSum / totalWeightSoldKg)
        : 0.0;

    double costDifferencePerKg =
        config.targetProductionCostPerKg - actualProdCostPerKgMetric;
    double efficiencyBonusOrPenaltyPerKg = 0.0;

    if (costDifferencePerKg > 0) {
      // Bachat: savings ka X% milega
      efficiencyBonusOrPenaltyPerKg =
          costDifferencePerKg * (config.farmerSavingsSharePercentage / 100);
    } else if (costDifferencePerKg < 0) {
      // ✅ EXCEEDED PENALTY: jo extra kharch kiya uska farmerPenaltySharePercentage% base rate se katega
      // costDifferencePerKg negative hai, isliye result bhi negative hoga (rate kam hoga)
      efficiencyBonusOrPenaltyPerKg =
          costDifferencePerKg * (config.farmerPenaltySharePercentage / 100);
    }

    // ── ✅ RATE BONUS LOGIC ────────────────────────────────────────────────
    // Condition 1: actual production cost <= target production cost
    // Condition 2: avg sale rate >= rateBonusThreshold
    // Bonus = (avgSaleRate - threshold) * rateBonusSharePercentage / 100
    double avgSaleRate = totalWeightSoldKg > 0
        ? totalSaleMoney / totalWeightSoldKg
        : 0.0;

    bool rateBonusApplied =
        (actualProdCostPerKgMetric <= config.targetProductionCostPerKg) &&
        (avgSaleRate >= config.rateBonusThreshold);

    double rateBonusPerKg = 0.0;
    if (rateBonusApplied) {
      double excessAboveThreshold = avgSaleRate - config.rateBonusThreshold;
      rateBonusPerKg =
          excessAboveThreshold * (config.rateBonusSharePercentage / 100);
    }

    // Final Applied Rate = base + efficiency adjustment + rate bonus
    double dynamicFinalRearingRatePerKg =
        config.standardRearingRatePerKg +
        efficiencyBonusOrPenaltyPerKg +
        rateBonusPerKg;

    // ✅ GUARANTEE FLOOR: minimum guarantee se niche nahi jayega
    if (dynamicFinalRearingRatePerKg < config.minRearingRateGuarantee) {
      dynamicFinalRearingRatePerKg = config.minRearingRateGuarantee;
    }

    double basicFarmerEarnings =
        totalWeightSoldKg * dynamicFinalRearingRatePerKg;
    double netPayoutCleared = basicFarmerEarnings;

    if (config.medicineTreatment == SimpleMedicineTreatment.deductFromEarning) {
      netPayoutCleared = netPayoutCleared - calculatedMedicineCostSum;
    }

    if (netPayoutCleared < 0) netPayoutCleared = 0.0;

    return SimpleSettlementResult(
      totalWeightSoldKg: totalWeightSoldKg,
      totalChickCost: totalChickCostAllotted,
      totalFeedCost: totalFeedCostAllotted,
      totalAdminCost: totalAdminCostSum,
      totalMedicineCost: calculatedMedicineCostSum,
      totalProductionCost: totalProductionCostSum,
      actualProductionCostPerKg: actualProdCostPerKgMetric,
      costDifferencePerKg: costDifferencePerKg,
      efficiencyBonusOrPenaltyPerKg: efficiencyBonusOrPenaltyPerKg,
      rateBonusPerKg: rateBonusPerKg,
      rateBonusApplied: rateBonusApplied,
      finalRearingRateApplied: dynamicFinalRearingRatePerKg,
      grossFarmerEarning: basicFarmerEarnings,
      netPayoutToFarmer: netPayoutCleared,
    );
  }
}

// =============================================================================
// 🐔 RULE 3 CONFIG: BIG SIZE POULTRY (1.2 KG SE BADA)
// =============================================================================
class BigSizePoultryConfig {
  double feedRatePerKg;
  double chickPricePerPiece;
  double adminChargePerKg;
  double targetProductionCost;
  double baseCommissionPerKg;

  // ✅ CORRECTED: Percentage-based bonus/penalty
  // Saving ya exceed hone par base commission mein ±X% adjustment hoga
  double costSavingSharePercentage; // e.g. 50 → saving ka 50% bonus
  double
  costExceededSharePercentage; // e.g. 50 → exceed ka 50% penalty deduction

  // ✅ CORRECTED: Progressive rate bonus
  // Condition 1: actual cost <= targetProductionCost
  // Condition 2: avgSaleRate >= rateBonusThreshold
  // Bonus = (avgSaleRate - threshold) * rateBonusSharePercentage / 100
  double rateBonusThreshold;
  double rateBonusSharePercentage; // % of amount above threshold

  double kgPerBag;

  // ✅ NEW: Medicine toggle
  // true  = medicine cost target production cost mein JODEGA (cost badhega)
  // false = medicine cost ko ignore karega production cost calculation mein
  bool includeMedicineInProdCost;

  BigSizePoultryConfig({
    this.feedRatePerKg = 42.00,
    this.chickPricePerPiece = 40.00,
    this.adminChargePerKg = 1.50,
    this.targetProductionCost = 85.00,
    this.baseCommissionPerKg = 8.00,
    this.costSavingSharePercentage = 50.0,
    this.costExceededSharePercentage = 50.0,
    this.rateBonusThreshold = 110.00,
    this.rateBonusSharePercentage = 10.0,
    this.kgPerBag = 50.0,
    this.includeMedicineInProdCost = true,
  });
}

// =============================================================================
// 🐣 RULE 4 CONFIG: SMALL SIZE POULTRY (1.2 KG TAK)
// =============================================================================
class SmallSizePoultryConfig {
  double feedRatePerKg;
  double chickPricePerPiece;
  double adminChargePerKg;
  double targetProductionCost;
  double baseCommissionPerKg;

  double costSavingSharePercentage;
  double costExceededSharePercentage;

  double rateBonusThreshold;
  double rateBonusSharePercentage;

  double kgPerBag;

  // ✅ NEW: Medicine toggle
  bool includeMedicineInProdCost;

  SmallSizePoultryConfig({
    this.feedRatePerKg = 42.00,
    this.chickPricePerPiece = 40.00,
    this.adminChargePerKg = 1.50,
    this.targetProductionCost = 90.00,
    this.baseCommissionPerKg = 10.00,
    this.costSavingSharePercentage = 50.0,
    this.costExceededSharePercentage = 50.0,
    this.rateBonusThreshold = 120.00,
    this.rateBonusSharePercentage = 10.0,
    this.kgPerBag = 50.0,
    this.includeMedicineInProdCost = true,
  });
}

// =============================================================================
// 📊 RESULT MODEL — BIG SIZE & SMALL SIZE DONO KE LIYE COMMON
// =============================================================================
class SizeBasedSettlementResult {
  final double totalWeightSoldKg;
  final double avgSaleRatePerKg;
  final double totalChickCost;
  final double totalFeedCost;
  final double totalAdminCost;
  final double totalMedicineCost;
  final double totalProductionCost;
  final double actualProductionCostPerKg;
  final double costDifferencePerKg; // + = saving, - = exceeded
  final double costAdjustmentPerKg; // Bonus ya penalty ₹/KG
  final double rateBonusPerKg; // Progressive rate bonus ₹/KG
  final bool rateBonusApplied;
  final double finalCommissionPerKg; // Base + adjustment + rateBonus
  final double grossFarmerEarning;
  final double netPayoutToFarmer;

  const SizeBasedSettlementResult({
    required this.totalWeightSoldKg,
    required this.avgSaleRatePerKg,
    required this.totalChickCost,
    required this.totalFeedCost,
    required this.totalAdminCost,
    required this.totalMedicineCost,
    required this.totalProductionCost,
    required this.actualProductionCostPerKg,
    required this.costDifferencePerKg,
    required this.costAdjustmentPerKg,
    required this.rateBonusPerKg,
    required this.rateBonusApplied,
    required this.finalCommissionPerKg,
    required this.grossFarmerEarning,
    required this.netPayoutToFarmer,
  });
}

// =============================================================================
// 🧮 RULE 3 ENGINE: BIG SIZE POULTRY SETTLEMENT CALCULATOR
// =============================================================================
class BigSizeSettlementEngine {
  static SizeBasedSettlementResult calculate({
    required BigSizePoultryConfig config,
    required Map<String, dynamic> batchData,
    required List<dynamic> dailyEntries,
  }) {
    int totalChicksHoused = batchData['chicksCount'] ?? 0;
    double totalWeightSoldKg = 0.0;
    double totalSaleMoney = 0.0;
    int totalFeedBags = 0;
    double totalMedicineCost = 0.0;

    for (var entry in dailyEntries) {
      String type = entry['type'].toString().toLowerCase();
      if (type == 'sale') {
        double wt = double.tryParse(entry['totalWeightSold'].toString()) ?? 0.0;
        double money = double.tryParse(entry['totalMoney'].toString()) ?? 0.0;
        totalWeightSoldKg += wt;
        totalSaleMoney += money;
      } else if (type == 'cost') {
        int bags = int.tryParse(entry['feed'].toString()) ?? 0;
        if (bags > 0) totalFeedBags += bags;
      } else if (type == 'medicine') {
        totalMedicineCost += double.tryParse(entry['price'].toString()) ?? 0.0;
      }
    }

    // --- COST CALCULATION ---
    double totalChickCost = totalChicksHoused * config.chickPricePerPiece;
    double totalFeedKg = totalFeedBags * config.kgPerBag;
    double totalFeedCost = totalFeedKg * config.feedRatePerKg;
    double totalAdminCost = totalWeightSoldKg * config.adminChargePerKg;

    // ✅ MEDICINE TOGGLE: owner ke choice ke hisaab se production cost mein jodega ya nahi
    double totalProductionCost =
        totalChickCost + totalFeedCost + totalAdminCost;
    if (config.includeMedicineInProdCost) {
      totalProductionCost += totalMedicineCost;
    }

    double actualCostPerKg = totalWeightSoldKg > 0
        ? totalProductionCost / totalWeightSoldKg
        : 0.0;

    // --- COST DIFF & COMMISSION ADJUSTMENT (PERCENTAGE BASED) ---
    // costDiff = targetCost - actualCost
    // + matlab saving hua, - matlab exceeded hua
    double costDiff = config.targetProductionCost - actualCostPerKg;

    double costAdjustment = 0.0;
    if (costDiff > 0) {
      // ✅ SAVING BONUS: saving ka costSavingSharePercentage% milega commission mein
      // e.g. target=85, actual=83, saving=2 ₹/kg, 50% share → +1 ₹/kg
      costAdjustment = costDiff * (config.costSavingSharePercentage / 100);
    } else if (costDiff < 0) {
      // ✅ EXCEEDED PENALTY: extra kharch ka costExceededSharePercentage% commission se katega
      // e.g. target=85, actual=87, exceeded=2 ₹/kg, 50% penalty → -1 ₹/kg
      // costDiff negative hai, isliye result bhi negative hoga (rate kam hoga)
      costAdjustment = costDiff * (config.costExceededSharePercentage / 100);
    }

    // --- RATE BONUS CHECK (PROGRESSIVE) ---
    // Condition 1: actual cost <= target cost
    // Condition 2: avgSaleRate >= rateBonusThreshold
    // Bonus = (avgSaleRate - threshold) * rateBonusSharePercentage / 100
    double avgSaleRate = totalWeightSoldKg > 0
        ? totalSaleMoney / totalWeightSoldKg
        : 0.0;

    bool rateBonusApplied =
        (actualCostPerKg <= config.targetProductionCost) &&
        (avgSaleRate >= config.rateBonusThreshold);

    double rateBonusPerKg = 0.0;
    if (rateBonusApplied) {
      double excessAboveThreshold = avgSaleRate - config.rateBonusThreshold;
      rateBonusPerKg =
          excessAboveThreshold * (config.rateBonusSharePercentage / 100);
    }

    // --- FINAL COMMISSION ---
    double finalCommission =
        config.baseCommissionPerKg + costAdjustment + rateBonusPerKg;

    if (finalCommission < 0) finalCommission = 0.0;

    double grossEarning = totalWeightSoldKg * finalCommission;
    double netPayout = grossEarning < 0 ? 0.0 : grossEarning;

    return SizeBasedSettlementResult(
      totalWeightSoldKg: totalWeightSoldKg,
      avgSaleRatePerKg: avgSaleRate,
      totalChickCost: totalChickCost,
      totalFeedCost: totalFeedCost,
      totalAdminCost: totalAdminCost,
      totalMedicineCost: totalMedicineCost,
      totalProductionCost: totalProductionCost,
      actualProductionCostPerKg: actualCostPerKg,
      costDifferencePerKg: costDiff,
      costAdjustmentPerKg: costAdjustment,
      rateBonusPerKg: rateBonusPerKg,
      rateBonusApplied: rateBonusApplied,
      finalCommissionPerKg: finalCommission,
      grossFarmerEarning: grossEarning,
      netPayoutToFarmer: netPayout,
    );
  }
}

// =============================================================================
// 🧮 RULE 4 ENGINE: SMALL SIZE POULTRY SETTLEMENT CALCULATOR
// =============================================================================
class SmallSizeSettlementEngine {
  static SizeBasedSettlementResult calculate({
    required SmallSizePoultryConfig config,
    required Map<String, dynamic> batchData,
    required List<dynamic> dailyEntries,
  }) {
    int totalChicksHoused = batchData['chicksCount'] ?? 0;
    double totalWeightSoldKg = 0.0;
    double totalSaleMoney = 0.0;
    int totalFeedBags = 0;
    double totalMedicineCost = 0.0;

    for (var entry in dailyEntries) {
      String type = entry['type'].toString().toLowerCase();
      if (type == 'sale') {
        double wt = double.tryParse(entry['totalWeightSold'].toString()) ?? 0.0;
        double money = double.tryParse(entry['totalMoney'].toString()) ?? 0.0;
        totalWeightSoldKg += wt;
        totalSaleMoney += money;
      } else if (type == 'cost') {
        int bags = int.tryParse(entry['feed'].toString()) ?? 0;
        if (bags > 0) totalFeedBags += bags;
      } else if (type == 'medicine') {
        totalMedicineCost += double.tryParse(entry['price'].toString()) ?? 0.0;
      }
    }

    // --- COST CALCULATION ---
    double totalChickCost = totalChicksHoused * config.chickPricePerPiece;
    double totalFeedKg = totalFeedBags * config.kgPerBag;
    double totalFeedCost = totalFeedKg * config.feedRatePerKg;
    double totalAdminCost = totalWeightSoldKg * config.adminChargePerKg;

    // ✅ MEDICINE TOGGLE
    double totalProductionCost =
        totalChickCost + totalFeedCost + totalAdminCost;
    if (config.includeMedicineInProdCost) {
      totalProductionCost += totalMedicineCost;
    }

    double actualCostPerKg = totalWeightSoldKg > 0
        ? totalProductionCost / totalWeightSoldKg
        : 0.0;

    // --- COST DIFF & COMMISSION ADJUSTMENT (PERCENTAGE BASED) ---
    double costDiff = config.targetProductionCost - actualCostPerKg;

    double costAdjustment = 0.0;
    if (costDiff > 0) {
      costAdjustment = costDiff * (config.costSavingSharePercentage / 100);
    } else if (costDiff < 0) {
      costAdjustment = costDiff * (config.costExceededSharePercentage / 100);
    }

    // --- RATE BONUS CHECK (PROGRESSIVE) ---
    double avgSaleRate = totalWeightSoldKg > 0
        ? totalSaleMoney / totalWeightSoldKg
        : 0.0;

    bool rateBonusApplied =
        (actualCostPerKg <= config.targetProductionCost) &&
        (avgSaleRate >= config.rateBonusThreshold);

    double rateBonusPerKg = 0.0;
    if (rateBonusApplied) {
      double excessAboveThreshold = avgSaleRate - config.rateBonusThreshold;
      rateBonusPerKg =
          excessAboveThreshold * (config.rateBonusSharePercentage / 100);
    }

    // --- FINAL COMMISSION ---
    double finalCommission =
        config.baseCommissionPerKg + costAdjustment + rateBonusPerKg;

    if (finalCommission < 0) finalCommission = 0.0;

    double grossEarning = totalWeightSoldKg * finalCommission;
    double netPayout = grossEarning < 0 ? 0.0 : grossEarning;

    return SizeBasedSettlementResult(
      totalWeightSoldKg: totalWeightSoldKg,
      avgSaleRatePerKg: avgSaleRate,
      totalChickCost: totalChickCost,
      totalFeedCost: totalFeedCost,
      totalAdminCost: totalAdminCost,
      totalMedicineCost: totalMedicineCost,
      totalProductionCost: totalProductionCost,
      actualProductionCostPerKg: actualCostPerKg,
      costDifferencePerKg: costDiff,
      costAdjustmentPerKg: costAdjustment,
      rateBonusPerKg: rateBonusPerKg,
      rateBonusApplied: rateBonusApplied,
      finalCommissionPerKg: finalCommission,
      grossFarmerEarning: grossEarning,
      netPayoutToFarmer: netPayout,
    );
  }
}
