import 'package:cloud_firestore/cloud_firestore.dart';

/// One line in a saved portfolio: a ticker and its target weight. Weights are
/// stored as entered (e.g. 60 / 40, or 0.6 / 0.4) and normalized when the
/// basket is estimated, so the advisor can think in whatever units they like.
class PortfolioHolding {
  const PortfolioHolding({required this.ticker, required this.weight});

  final String ticker;
  final double weight;

  Map<String, Object?> toMap() => {
        'ticker': ticker.trim().toUpperCase(),
        'weight': weight,
      };

  factory PortfolioHolding.fromMap(Map<String, dynamic> map) {
    return PortfolioHolding(
      ticker: ((map['ticker'] as String?) ?? '').toUpperCase(),
      weight: (map['weight'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Editable fields for creating/updating a saved portfolio.
class SavedPortfolioDraft {
  SavedPortfolioDraft({
    required this.name,
    required this.holdings,
    this.period = '5y',
  });

  final String name;
  final List<PortfolioHolding> holdings;
  final String period;

  Map<String, Object?> toUpdatePayload() {
    return {
      'name': name.trim(),
      'period': period,
      'holdings': [
        for (final h in holdings)
          if (h.ticker.trim().isNotEmpty) h.toMap(),
      ],
    };
  }
}

/// A named, reusable basket of tickers + target weights, saved under a
/// household at `households/{hid}/portfolios/{id}`. Distinct from the
/// investments database (actual shares held): a saved portfolio is a *model*
/// allocation an advisor can re-estimate and simulate on demand.
class SavedPortfolio {
  SavedPortfolio({
    required this.id,
    required this.householdId,
    required this.name,
    required this.holdings,
    required this.period,
    required this.createdAt,
    required this.createdBy,
  });

  final String id;
  final String householdId;
  final String name;
  final List<PortfolioHolding> holdings;
  final String period;
  final DateTime createdAt;
  final String createdBy;

  List<String> get tickers => [for (final h in holdings) h.ticker];
  List<double> get weights => [for (final h in holdings) h.weight];

  factory SavedPortfolio.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String householdId,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawHoldings = (data['holdings'] as List?) ?? const [];
    return SavedPortfolio(
      id: doc.id,
      householdId: householdId,
      name: (data['name'] as String?) ?? '',
      holdings: [
        for (final h in rawHoldings)
          PortfolioHolding.fromMap(Map<String, dynamic>.from(h as Map)),
      ],
      period: (data['period'] as String?) ?? '5y',
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: (data['createdBy'] as String?) ?? '',
    );
  }

  static Map<String, Object?> toCreatePayload({
    required String advisorUid,
    required SavedPortfolioDraft draft,
  }) {
    return {
      ...draft.toUpdatePayload(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': advisorUid,
    };
  }
}
