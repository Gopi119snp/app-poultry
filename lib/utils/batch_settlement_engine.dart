import 'dart:convert';
import 'package:flutter/material.dart';

// =============================================================================
// 🎛️ 1. COMPANY TENANT SETTLEMENT CONFIGURATION MODEL
// =============================================================================
// Har company apne admin panel se in toggles aur ranges ko set karegi.
// =============================================================================
enum PriceType { fixed, variableAtArrival }

enum MedicineTreatment { includeInProdCost, deductFromEarning }

enum FcrStatus { good, normal, bad }

// ✅ TOGGLE SYSTEM: Rate rupya mein kaatna/dena hai ya base rate ke percentage par
enum IncentiveType { rupeesPerKg, percentageOfBaseRate }

class CompanySettlementConfig {
  // 1. Chicks Price Configurations
  PriceType chickPriceType;
  double globalFixedChickPrice; // Agar fixed company hai

  // 2. Feed Price Configurations
  PriceType feedPriceType;
  double globalFixedFeedPricePerKg; // Agar per KG feed cost fixed hai

  // 3. Medicine Cost Configurations
  MedicineTreatment
  medicineTreatment; // Cost/KG mein jodein ya earning se ghatayein

  // 4. FCR Multi-Range Boxes (Company apne hisab se range set karegi)
  double fcrGoodMin;
  double fcrGoodMax;
  double fcrNormalMin;
  double fcrNormalMax;
  double fcrBadMin;
  double fcrBadMax;

  // ✅ FCR INCENTIVE PARAMETERS: FCR optimization values rate inputs
  IncentiveType fcrIncentiveType; // rupeesPerKg ya percentageOfBaseRate
  double
  fcrBonusRatePerPoint; // 0.01 FCR deviation par milne wala reward (Rupya ya %)
  double
  fcrPenaltyRatePerPoint; // 0.01 FCR kharab hone par katne wali penalty (Rupya ya %)

  // 5. Converted FCR Feature Toggle
  bool useConvertedFcr;

  // 💸 Extra Core Settings (Standard parameters needed for base formulas)
  double standardBaseRearingRate; // e.g. ₹7.50 per KG base kisaan rate
  double tdsPercentage; // e.g. 1% ya 2% TDS

  CompanySettlementConfig({
    required this.chickPriceType,
    this.globalFixedChickPrice = 0.0,
    required this.feedPriceType,
    this.globalFixedFeedPricePerKg = 0.0,
    required this.medicineTreatment,
    required this.fcrGoodMin,
    required this.fcrGoodMax,
    required this.fcrNormalMin,
    required this.fcrNormalMax,
    required this.fcrBadMin,
    required this.fcrBadMax,
    required this.fcrIncentiveType,
    required this.fcrBonusRatePerPoint,
    required this.fcrPenaltyRatePerPoint,
    required this.useConvertedFcr,
    this.standardBaseRearingRate = 7.50,
    this.tdsPercentage = 1.0,
  });
}

// =============================================================================
// 🧮 2. BATCH SETTLEMENT COMPUTATION CORE ENGINE
// =============================================================================
// Yeh class batch band hote waqt company ke custom rules ke mutabik math chalayegi.
// =============================================================================
class BatchSettlementResult {
  double totalBiomassSoldKg;
  double actualFcr;
  double finalEvaluatedFcr; // Can be actual or converted based on toggle
  String fcrClassification; // GOOD, NORMAL, or BAD
  double
  baseRearingRateApplied; // Target rate after adding bonus or subtracting penalty (Ern RC/kg)
  double basicGrowingCharge; // Weight * Base Rate (Basic GC Amt)
  double fcrBonusOrPenaltyEarned; // Total bonus/penalty amount earned or lost
  double totalMedicineCost;
  double chickCostApplied;
  double totalProductionCost;
  double productionCostPerKg;
  double finalEarningBeforeTax;
  double tdsDeduction;
  double netPayoutToFarmer;

  BatchSettlementResult({
    required this.totalBiomassSoldKg,
    required this.actualFcr,
    required this.finalEvaluatedFcr,
    required this.fcrClassification,
    required this.baseRearingRateApplied,
    required this.basicGrowingCharge,
    required this.fcrBonusOrPenaltyEarned,
    required this.totalMedicineCost,
    required this.chickCostApplied,
    required this.totalProductionCost,
    required this.productionCostPerKg,
    required this.finalEarningBeforeTax,
    required this.tdsDeduction,
    required this.netPayoutToFarmer,
  });
}

class BatchSettlementEngine {
  static BatchSettlementResult processBatch({
    required CompanySettlementConfig config,
    required Map<String, dynamic> batchData,
    required List<dynamic> dailyEntries,
  }) {
    // ── STEP 1: PRE-CALCULATE BASE DATA FROM DAILY LOG DETAILS ────────────────
    int totalChicksHoused = batchData['chicksCount'] ?? 0;
    int totalChicksSold = 0;
    double totalWeightSoldKg = 0.0;
    double totalFeedConsumedKg = 0.0;
    double calculatedMedicineCostSum = 0.0;
    double latestRecordedAvgWeight = 0.0;

    for (var entry in dailyEntries) {
      String type = entry['type'].toString().toLowerCase();

      if (type == 'sale') {
        totalChicksSold += int.tryParse(entry['chicksSold'].toString()) ?? 0;
        totalWeightSoldKg +=
            double.tryParse(entry['totalWeightSold'].toString()) ?? 0.0;
      } else if (type == 'cost') {
        int feedBagsArrived = int.tryParse(entry['feed'].toString()) ?? 0;
        totalFeedConsumedKg +=
            (feedBagsArrived * 50.0); // 1 Bag = 50KG Standard

        double wt = double.tryParse(entry['weight'].toString()) ?? 0.0;
        if (wt > 0.0) latestRecordedAvgWeight = wt;
      } else if (type == 'medicine') {
        double medPrice = double.tryParse(entry['price'].toString()) ?? 0.0;
        calculatedMedicineCostSum += medPrice;
      }
    }

    if (latestRecordedAvgWeight == 0.0 && totalChicksSold > 0) {
      latestRecordedAvgWeight = totalWeightSoldKg / totalChicksSold;
    }

    // ── STEP 2: CHICK COST RULE RESOLUTION ───────────────────────────────────
    double finalChickUnitRate = 0.0;
    if (config.chickPriceType == PriceType.fixed) {
      finalChickUnitRate = config.globalFixedChickPrice;
    } else {
      finalChickUnitRate =
          double.tryParse(batchData['chicksRate'].toString()) ?? 40.0;
    }
    double totalChickCostAllotted = totalChicksHoused * finalChickUnitRate;

    // ── STEP 3: FEED COST RULE RESOLUTION ────────────────────────────────────
    double totalFeedCostAllotted = 0.0;
    if (config.feedPriceType == PriceType.fixed) {
      totalFeedCostAllotted =
          totalFeedConsumedKg * config.globalFixedFeedPricePerKg;
    } else {
      totalFeedCostAllotted = totalFeedConsumedKg * 35.0;
    }

    // ── STEP 4: FCR & CONVERTED FCR EVALUATION ENGINE ───────────────────────
    double baseActualFcr = totalWeightSoldKg > 0
        ? (totalFeedConsumedKg / totalWeightSoldKg)
        : 0.0;
    double finalEvaluatedFcr = baseActualFcr;

    if (config.useConvertedFcr && totalWeightSoldKg > 0) {
      finalEvaluatedFcr =
          baseActualFcr - ((latestRecordedAvgWeight - 2.0) * 0.25);
    }

    // FCR Box lookups classification allocation
    String evaluatedFcrGrade = 'NORMAL';
    if (finalEvaluatedFcr >= config.fcrGoodMin &&
        finalEvaluatedFcr <= config.fcrGoodMax) {
      evaluatedFcrGrade = 'GOOD ✅';
    } else if (finalEvaluatedFcr >= config.fcrNormalMin &&
        finalEvaluatedFcr <= config.fcrNormalMax) {
      evaluatedFcrGrade = 'NORMAL 📊';
    } else if (finalEvaluatedFcr >= config.fcrBadMin &&
        finalEvaluatedFcr <= config.fcrBadMax) {
      evaluatedFcrGrade = 'BAD 🚨';
    }

    // ── STEP 4B: ADVANCED FCR BONUS / PENALTY MATH MATRIX ────────────────────
    double calculatedPerKgModifier = 0.0;
    double totalFcrIncentiveMoneyValue = 0.0;

    // A. AGAR FCR NORMAL SE KAM (BADIYA) HAI -> BONUS APPLIED
    if (finalEvaluatedFcr < config.fcrNormalMin) {
      double pointsBetter = (config.fcrNormalMin - finalEvaluatedFcr) * 100;

      if (config.fcrIncentiveType == IncentiveType.rupeesPerKg) {
        calculatedPerKgModifier = pointsBetter * config.fcrBonusRatePerPoint;
      } else {
        double singlePointValue =
            (config.fcrBonusRatePerPoint / 100) *
            config.standardBaseRearingRate;
        calculatedPerKgModifier = pointsBetter * singlePointValue;
      }
      totalFcrIncentiveMoneyValue = totalWeightSoldKg * calculatedPerKgModifier;
    }
    // B. AGAR FCR NORMAL SE ZYAADA (KHARAB) HAI -> PENALTY APPLIED
    else if (finalEvaluatedFcr > config.fcrNormalMax) {
      double pointsWorse = (finalEvaluatedFcr - config.fcrNormalMax) * 100;

      if (config.fcrIncentiveType == IncentiveType.rupeesPerKg) {
        calculatedPerKgModifier =
            -(pointsWorse * config.fcrPenaltyRatePerPoint);
      } else {
        double singlePointValue =
            (config.fcrPenaltyRatePerPoint / 100) *
            config.standardBaseRearingRate;
        calculatedPerKgModifier = -(pointsWorse * singlePointValue);
      }
      totalFcrIncentiveMoneyValue = totalWeightSoldKg * calculatedPerKgModifier;
    }

    // Compute final dynamic rearing rate (Ern RC/kg) after modifications matrix
    double dynamicFinalRearingRatePerKg =
        config.standardBaseRearingRate + calculatedPerKgModifier;

    // ── STEP 5: PRODUCTION COSTING & MEDICINE TREATMENT RULE ────────────────
    double totalProductionCostSum =
        totalChickCostAllotted + totalFeedCostAllotted;

    if (config.medicineTreatment == MedicineTreatment.includeInProdCost) {
      totalProductionCostSum += calculatedMedicineCostSum;
    }

    double productionCostPerKgMetric = totalWeightSoldKg > 0
        ? (totalProductionCostSum / totalWeightSoldKg)
        : 0.0;

    // ── STEP 6: FARMER EARNINGS GENERATION PIPELINE ──────────────────────────
    double basicFarmerEarnings =
        totalWeightSoldKg * config.standardBaseRearingRate;
    double rawEarningsGross = basicFarmerEarnings + totalFcrIncentiveMoneyValue;

    if (config.medicineTreatment == MedicineTreatment.deductFromEarning) {
      rawEarningsGross = rawEarningsGross - calculatedMedicineCostSum;
    }

    if (rawEarningsGross < 0) rawEarningsGross = 0.0;

    double calculatedTds = (rawEarningsGross * config.tdsPercentage) / 100.0;
    double netPayoutCleared = rawEarningsGross - calculatedTds;

    return BatchSettlementResult(
      totalBiomassSoldKg: totalWeightSoldKg,
      actualFcr: baseActualFcr,
      finalEvaluatedFcr: finalEvaluatedFcr,
      fcrClassification: evaluatedFcrGrade,
      baseRearingRateApplied: dynamicFinalRearingRatePerKg,
      basicGrowingCharge: basicFarmerEarnings,
      fcrBonusOrPenaltyEarned: totalFcrIncentiveMoneyValue,
      totalMedicineCost: calculatedMedicineCostSum,
      chickCostApplied: totalChickCostAllotted,
      totalProductionCost: totalProductionCostSum,
      productionCostPerKg: productionCostPerKgMetric,
      finalEarningBeforeTax: rawEarningsGross,
      tdsDeduction: calculatedTds,
      netPayoutToFarmer: netPayoutCleared,
    );
  }
}
