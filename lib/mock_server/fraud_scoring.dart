import 'package:fraud_shield/core/utils/money.dart';

/// The server-side fraud engine, simplified. It scores a payment against
/// the customer's usual behaviour and explains why it looks unusual.
class PaymentCandidate {
  const PaymentCandidate({
    required this.merchant,
    required this.category,
    required this.amountPaise,
    required this.city,
    required this.country,
    required this.instrumentLabel,
    required this.knownMerchant,
  });

  final String merchant;
  final String category;
  final int amountPaise;
  final String city;
  final String country;
  final String instrumentLabel;
  final bool knownMerchant;
}

class CustomerProfile {
  const CustomerProfile({
    required this.homeCity,
    required this.homeCountry,
    required this.averageSpendPaise,
  });

  final String homeCity;
  final String homeCountry;
  final int averageSpendPaise;
}

class RiskAssessment {
  const RiskAssessment({required this.score, required this.reasons});

  final int score;
  final List<String> reasons;

  /// 'HIGH', 'MEDIUM' or 'LOW' (LOW does not raise an alert).
  String get level =>
      score >= 70
          ? 'HIGH'
          : score >= 40
          ? 'MEDIUM'
          : 'LOW';

  bool get raisesAlert => score >= 40;

  String get summary =>
      reasons.isEmpty ? 'Unusual activity' : reasons.join(' ');
}

class FraudScorer {
  const FraudScorer._();

  static const highRiskCategories = {'crypto', 'gift cards', 'wallet top-up'};

  static RiskAssessment assess(PaymentCandidate p, CustomerProfile profile) {
    var score = 0;
    final reasons = <String>[];

    if (p.country != profile.homeCountry) {
      score += 45;
      reasons.add(
        'Unusual location: ${p.city}, ${p.country}. Your '
        '${p.instrumentLabel.toLowerCase()} is normally used in '
        '${profile.homeCity}.',
      );
    }

    final ratio =
        profile.averageSpendPaise == 0
            ? 0
            : p.amountPaise ~/ profile.averageSpendPaise;
    if (ratio >= 5) {
      score += 30;
      reasons.add(
        '${Money.compact(p.amountPaise)} is ${ratio}x your usual spend.',
      );
    }

    if (highRiskCategories.contains(p.category)) {
      score += 25;
      reasons.add('High-risk merchant type: ${p.category}.');
    }

    if (!p.knownMerchant) {
      score += 10;
      reasons.add('First payment to ${p.merchant}.');
    }

    return RiskAssessment(score: score.clamp(0, 100), reasons: reasons);
  }
}
