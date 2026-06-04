import 'package:flutter_test/flutter_test.dart';
import 'package:monte_carlo_simulator/services/portfolio_service.dart';
import 'package:monte_carlo_simulator/services/quote_service.dart';

void main() {
  group('QuoteService.parse', () {
    test('maps quotes, missing, and stale flag', () {
      final result = QuoteService.parse({
        'quotes': {
          'AAPL': {'price': 150.5, 'as_of': '2026-06-03'},
          'MSFT': {'price': 300.0, 'as_of': '2026-06-03'},
        },
        'missing': ['ZZZZ'],
        'stale': true,
      });
      expect(result.quotes.length, 2);
      expect(result.quotes['AAPL']!.price, 150.5);
      expect(result.quotes['AAPL']!.asOf, '2026-06-03');
      expect(result.quotes['MSFT']!.price, 300.0);
      expect(result.missing, ['ZZZZ']);
      expect(result.stale, isTrue);
    });

    test('defaults stale to false and tolerates absent fields', () {
      final result = QuoteService.parse({
        'quotes': {
          'AAPL': {'price': 10, 'as_of': '2026-06-01'},
        },
      });
      expect(result.stale, isFalse);
      expect(result.missing, isEmpty);
      expect(result.quotes['AAPL']!.price, 10.0); // int coerced to double
    });

    test('empty response yields empty result', () {
      final result = QuoteService.parse(const {});
      expect(result.quotes, isEmpty);
      expect(result.missing, isEmpty);
      expect(result.stale, isFalse);
    });
  });

  group('PortfolioEstimate.fromJson', () {
    test('parses mu/sigma, tickers, weights, and date range', () {
      final est = PortfolioEstimate.fromJson({
        'mu': 0.082,
        'sigma': 0.171,
        'tickers': ['AAPL', 'MSFT'],
        'weights': [0.6, 0.4],
        'start_date': '2021-06-01',
        'end_date': '2026-06-01',
      });
      expect(est.mu, 0.082);
      expect(est.sigma, 0.171);
      expect(est.tickers, ['AAPL', 'MSFT']);
      expect(est.weights, [0.6, 0.4]);
      expect(est.startDate, '2021-06-01');
      expect(est.endDate, '2026-06-01');
    });

    test('tolerates missing optional dates', () {
      final est = PortfolioEstimate.fromJson({
        'mu': 0.05,
        'sigma': 0.12,
        'tickers': ['SPY'],
        'weights': [1.0],
      });
      expect(est.startDate, isNull);
      expect(est.endDate, isNull);
      expect(est.weights, [1.0]);
    });
  });
}
