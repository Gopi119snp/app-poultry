// =============================================================================
// 🚨 FRAUD RISK ENGINE
// -----------------------------------------------------------------------------
// Do independent signals combine karke batata hai ki batch mein kuch gadbad
// (feed diversion ya chupi hui bikri) ho sakti hai ya nahi:
//
//   1) FEED-PER-BIRD CHECK
//      "Kitna feed ACTUALLY khatam hua" vs "Reported Live Chicks ke hisaab
//      se kitna khatam HONA CHAHIYE THA". Agar actual bahut kam hai, matlab
//      utne birds farm pe hain hi nahi jitne report ho rahe hain.
//
//   2) PURCHASE-SIDE RECONCILIATION
//      "Company ne kitna feed bheja" (pakka record, farmer badal nahi
//      sakta) minus "Expected Consumption" = kitna stock bacha hona
//      chahiye. Isko farmer ke "Actual Remaining Feed" se compare karo.
//      Gap bada hai toh kuch feed/chicks missing hai.
//
// Dono checks alag-alag data angles se aate hain, isliye ek saath lagane se
// farmer ke liye dono taraf jhooth bolna mushkil ho jaata hai.
// =============================================================================

class FeedPerBirdResult {
  final double actualConsumedKg;
  final double expectedConsumedKg;
  final double ratioPercent; // (actual ÷ expected) × 100
  final bool isFlagged;
  final bool hasData; // Actual Remaining Feed kabhi report hua ya nahi

  FeedPerBirdResult({
    required this.actualConsumedKg,
    required this.expectedConsumedKg,
    required this.ratioPercent,
    required this.isFlagged,
    required this.hasData,
  });
}

class PurchaseReconciliationResult {
  final double feedDeliveredKg;
  final double expectedConsumedKg;
  final double expectedRemainingKg;
  final double actualRemainingKg;
  final double gapKg; // expectedRemaining − actualRemaining (+ve = stock missing)
  final double gapPercent;
  final bool isFlagged;
  final bool hasData;

  PurchaseReconciliationResult({
    required this.feedDeliveredKg,
    required this.expectedConsumedKg,
    required this.expectedRemainingKg,
    required this.actualRemainingKg,
    required this.gapKg,
    required this.gapPercent,
    required this.isFlagged,
    required this.hasData,
  });
}

class FraudRiskAssessment {
  final FeedPerBirdResult feedPerBird;
  final PurchaseReconciliationResult purchaseReconciliation;

  FraudRiskAssessment({
    required this.feedPerBird,
    required this.purchaseReconciliation,
  });

  bool get hasAnyData => feedPerBird.hasData || purchaseReconciliation.hasData;
  bool get isHighRisk => feedPerBird.isFlagged && purchaseReconciliation.isFlagged;
  bool get isWatchRisk =>
      (feedPerBird.isFlagged || purchaseReconciliation.isFlagged) && !isHighRisk;
  bool get isSafe => hasAnyData && !feedPerBird.isFlagged && !purchaseReconciliation.isFlagged;

  /// 'high' = dono checks flag ho rahe hain (sabse serious)
  /// 'watch' = koi ek check flag ho raha hai (nazar rakho)
  /// 'safe' = kuch bhi flag nahi
  /// 'no_data' = Actual Remaining Feed kabhi report hi nahi hua, assess nahi ho sakta
  String get riskLevel {
    if (!hasAnyData) return 'no_data';
    if (isHighRisk) return 'high';
    if (isWatchRisk) return 'watch';
    return 'safe';
  }
}

class FraudRiskEngine {
  /// Agar Actual Consumed, Expected Consumed ke is % se KAM ho, toh flag.
  static const double feedPerBirdFlagThresholdPercent = 85.0;

  /// Agar Expected vs Actual Remaining Stock ka gap is % se ZYADA ho, toh flag.
  static const double stockGapFlagThresholdPercent = 15.0;

  static FeedPerBirdResult evaluateFeedPerBird({
    required double actualConsumedKg,
    required double expectedConsumedKg,
    required bool remainingFeedEverReported,
  }) {
    if (!remainingFeedEverReported || expectedConsumedKg <= 0) {
      return FeedPerBirdResult(
        actualConsumedKg: actualConsumedKg,
        expectedConsumedKg: expectedConsumedKg,
        ratioPercent: 0,
        isFlagged: false,
        hasData: false,
      );
    }
    final double ratio = (actualConsumedKg / expectedConsumedKg) * 100;
    return FeedPerBirdResult(
      actualConsumedKg: actualConsumedKg,
      expectedConsumedKg: expectedConsumedKg,
      ratioPercent: ratio,
      isFlagged: ratio < feedPerBirdFlagThresholdPercent,
      hasData: true,
    );
  }

  static PurchaseReconciliationResult evaluatePurchaseReconciliation({
    required double feedDeliveredKg,
    required double expectedConsumedKg,
    required double actualRemainingKg,
    required bool remainingFeedEverReported,
  }) {
    final double expectedRemaining = feedDeliveredKg - expectedConsumedKg;

    if (!remainingFeedEverReported) {
      return PurchaseReconciliationResult(
        feedDeliveredKg: feedDeliveredKg,
        expectedConsumedKg: expectedConsumedKg,
        expectedRemainingKg: expectedRemaining,
        actualRemainingKg: 0,
        gapKg: 0,
        gapPercent: 0,
        isFlagged: false,
        hasData: false,
      );
    }

    final double gap = expectedRemaining - actualRemainingKg;
    final double gapPercent = expectedRemaining.abs() > 0.001
        ? (gap.abs() / expectedRemaining.abs()) * 100
        : (gap.abs() > 0.001 ? 100.0 : 0.0);

    return PurchaseReconciliationResult(
      feedDeliveredKg: feedDeliveredKg,
      expectedConsumedKg: expectedConsumedKg,
      expectedRemainingKg: expectedRemaining,
      actualRemainingKg: actualRemainingKg,
      gapKg: gap,
      gapPercent: gapPercent,
      isFlagged: gapPercent > stockGapFlagThresholdPercent,
      hasData: true,
    );
  }

  static FraudRiskAssessment assess({
    required double feedDeliveredKg,
    required double expectedConsumedKg,
    required double actualRemainingKg,
    required bool remainingFeedEverReported,
  }) {
    final double actualConsumedKg = feedDeliveredKg - actualRemainingKg;
    final feedPerBird = evaluateFeedPerBird(
      actualConsumedKg: actualConsumedKg,
      expectedConsumedKg: expectedConsumedKg,
      remainingFeedEverReported: remainingFeedEverReported,
    );
    final purchaseRecon = evaluatePurchaseReconciliation(
      feedDeliveredKg: feedDeliveredKg,
      expectedConsumedKg: expectedConsumedKg,
      actualRemainingKg: actualRemainingKg,
      remainingFeedEverReported: remainingFeedEverReported,
    );
    return FraudRiskAssessment(
      feedPerBird: feedPerBird,
      purchaseReconciliation: purchaseRecon,
    );
  }
}
