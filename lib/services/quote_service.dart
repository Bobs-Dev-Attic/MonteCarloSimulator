import 'package:cloud_functions/cloud_functions.dart';

/// A single live price point for a ticker.
class Quote {
  const Quote({required this.price, required this.asOf});

  final double price;
  final String asOf; // ISO date the close is from, e.g. "2026-06-03"

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
        price: (json['price'] as num).toDouble(),
        asOf: (json['as_of'] as String?) ?? '',
      );
}

/// Result of a quote request: resolved [quotes] keyed by upper-case ticker,
/// any [missing] symbols Yahoo had no price for, and whether these prices were
/// served [stale] from cache after a live fetch failed.
class QuotesResult {
  const QuotesResult({
    required this.quotes,
    required this.missing,
    this.stale = false,
  });

  final Map<String, Quote> quotes;
  final List<String> missing;
  final bool stale;

  static const empty = QuotesResult(quotes: {}, missing: []);
}

/// Invokes the server-side `fetchQuotes` Cloud Function (yfinance) to value a
/// customer's holdings live.
class QuoteService {
  QuoteService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<QuotesResult> fetchQuotes(List<String> tickers) async {
    if (tickers.isEmpty) return QuotesResult.empty;
    final callable = _functions.httpsCallable(
      'fetchQuotes',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    final response =
        await callable.call<Map<String, dynamic>>({'tickers': tickers});
    final data = _deepCast(response.data) as Map<String, dynamic>;

    final rawQuotes =
        (data['quotes'] as Map?)?.cast<String, dynamic>() ?? const {};
    final quotes = <String, Quote>{
      for (final entry in rawQuotes.entries)
        entry.key: Quote.fromJson(
          (entry.value as Map).cast<String, dynamic>(),
        ),
    };
    final missing = ((data['missing'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
    return QuotesResult(
      quotes: quotes,
      missing: missing,
      stale: data['stale'] == true,
    );
  }

  static dynamic _deepCast(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _deepCast(v)));
    }
    if (value is List) {
      return value.map(_deepCast).toList();
    }
    return value;
  }
}
