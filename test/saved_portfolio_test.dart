import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte_carlo_simulator/models/saved_portfolio.dart';

void main() {
  group('PortfolioHolding', () {
    test('toMap upper-cases and trims ticker', () {
      final m = const PortfolioHolding(ticker: 'aapl', weight: 0.6).toMap();
      expect(m['ticker'], 'AAPL');
      expect(m['weight'], 0.6);
    });

    test('fromMap coerces weight to double and upper-cases', () {
      final h = PortfolioHolding.fromMap({'ticker': 'msft', 'weight': 2});
      expect(h.ticker, 'MSFT');
      expect(h.weight, 2.0);
    });
  });

  group('SavedPortfolio.fromDoc', () {
    late FakeFirebaseFirestore db;
    setUp(() => db = FakeFirebaseFirestore());

    test('parses name, period, and holdings', () async {
      final ref = db
          .collection('households')
          .doc('h1')
          .collection('portfolios')
          .doc('p1');
      await ref.set({
        'name': '60/40 Growth',
        'period': '10y',
        'holdings': [
          {'ticker': 'VTI', 'weight': 60},
          {'ticker': 'BND', 'weight': 40},
        ],
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 6, 1)),
        'createdBy': 'advisor-uid',
      });
      final p = SavedPortfolio.fromDoc(await ref.get(), 'h1');

      expect(p.id, 'p1');
      expect(p.householdId, 'h1');
      expect(p.name, '60/40 Growth');
      expect(p.period, '10y');
      expect(p.tickers, ['VTI', 'BND']);
      expect(p.weights, [60.0, 40.0]);
      expect(p.createdBy, 'advisor-uid');
    });

    test('defaults period to 5y and tolerates missing holdings', () async {
      final ref = db
          .collection('households')
          .doc('h1')
          .collection('portfolios')
          .doc('p1');
      await ref.set({
        'name': 'Empty',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 6, 1)),
        'createdBy': 'a',
      });
      final p = SavedPortfolio.fromDoc(await ref.get(), 'h1');
      expect(p.period, '5y');
      expect(p.holdings, isEmpty);
    });
  });

  group('SavedPortfolioDraft.toUpdatePayload', () {
    test('drops blank-ticker rows and normalizes case', () {
      final draft = SavedPortfolioDraft(
        name: '  Mix ',
        period: '2y',
        holdings: const [
          PortfolioHolding(ticker: 'aapl', weight: 1),
          PortfolioHolding(ticker: '   ', weight: 5), // blank -> dropped
          PortfolioHolding(ticker: 'msft', weight: 2),
        ],
      );
      final p = draft.toUpdatePayload();
      expect(p['name'], 'Mix');
      expect(p['period'], '2y');
      final holdings = p['holdings'] as List;
      expect(holdings.length, 2);
      expect((holdings[0] as Map)['ticker'], 'AAPL');
      expect((holdings[1] as Map)['ticker'], 'MSFT');
      expect(p.containsKey('createdAt'), isFalse);
    });
  });

  group('SavedPortfolio.toCreatePayload', () {
    test('adds serverTimestamp sentinel and createdBy', () {
      final payload = SavedPortfolio.toCreatePayload(
        advisorUid: 'advisor-uid',
        draft: SavedPortfolioDraft(
          name: 'P',
          holdings: const [PortfolioHolding(ticker: 'SPY', weight: 1)],
        ),
      );
      expect(payload['name'], 'P');
      expect(payload['createdBy'], 'advisor-uid');
      expect(payload['createdAt'], isA<FieldValue>());
      expect((payload['holdings'] as List).length, 1);
    });
  });
}
