import 'package:cloud_functions/cloud_functions.dart';

/// GBM inputs derived from a basket of tickers' historical prices, returned by
/// the server-side `estimatePortfolio` Cloud Function.
class PortfolioEstimate {
  const PortfolioEstimate({
    required this.mu,
    required this.sigma,
    required this.tickers,
    required this.weights,
    this.startDate,
    this.endDate,
  });

  /// Annual drift (e.g. 0.08 for 8%) in the GBM simulator's convention.
  final double mu;

  /// Annual volatility (e.g. 0.15 for 15%).
  final double sigma;
  final List<String> tickers;
  final List<double> weights;
  final String? startDate;
  final String? endDate;

  factory PortfolioEstimate.fromJson(Map<String, dynamic> json) {
    return PortfolioEstimate(
      mu: (json['mu'] as num).toDouble(),
      sigma: (json['sigma'] as num).toDouble(),
      tickers: ((json['tickers'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      weights: ((json['weights'] as List?) ?? const [])
          .map((e) => (e as num).toDouble())
          .toList(),
      startDate: json['start_date'] as String?,
      endDate: json['end_date'] as String?,
    );
  }
}

/// Invokes `estimatePortfolio` to turn a customer's holdings into a single
/// (mu, sigma) the GBM simulation can run on — the bridge from the investments
/// database to the simulator.
class PortfolioService {
  PortfolioService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<PortfolioEstimate> estimate({
    required List<String> tickers,
    List<double>? weights,
    String period = '5y',
  }) async {
    final callable = _functions.httpsCallable(
      'estimatePortfolio',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    );
    final response = await callable.call<Map<String, dynamic>>({
      'tickers': tickers,
      if (weights != null) 'weights': weights,
      'period': period,
    });
    final data = _deepCast(response.data) as Map<String, dynamic>;
    return PortfolioEstimate.fromJson(data);
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
