import 'package:cloud_firestore/cloud_firestore.dart';

/// A single security a customer holds, stored under
/// `households/{hid}/investments/{id}`.
///
/// Deliberately minimal — just a [ticker] and a [quantity] of shares. The
/// security's price (and therefore market value) is *not* stored; it is fetched
/// live from Yahoo Finance via the `fetchQuotes` Cloud Function so valuations
/// are always current. See [marketValue].
class InvestmentDraft {
  InvestmentDraft({
    required this.ticker,
    required this.quantity,
  });

  final String ticker;
  final double quantity;

  /// Normalized write payload. Tickers are upper-cased and trimmed so a
  /// household never ends up with both `aapl` and `AAPL`.
  Map<String, Object?> toUpdatePayload() {
    return {
      'ticker': ticker.trim().toUpperCase(),
      'quantity': quantity,
    };
  }
}

class Investment {
  Investment({
    required this.id,
    required this.householdId,
    required this.ticker,
    required this.quantity,
    required this.createdAt,
    required this.createdBy,
  });

  final String id;
  final String householdId;
  final String ticker;
  final double quantity;
  final DateTime createdAt;
  final String createdBy;

  /// Market value at [price] per share, or null when no quote is available.
  double? marketValue(double? price) =>
      price == null ? null : price * quantity;

  factory Investment.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String householdId,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Investment(
      id: doc.id,
      householdId: householdId,
      ticker: ((data['ticker'] as String?) ?? '').toUpperCase(),
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0.0,
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: (data['createdBy'] as String?) ?? '',
    );
  }

  static Map<String, Object?> toCreatePayload({
    required String advisorUid,
    required InvestmentDraft draft,
  }) {
    final base = draft.toUpdatePayload();
    return {
      ...base,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': advisorUid,
    };
  }
}
