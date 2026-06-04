import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:monte_carlo_simulator/models/household.dart';
import 'package:monte_carlo_simulator/screens/household_detail_screen.dart';
import 'package:monte_carlo_simulator/screens/investment_form_screen.dart';
import 'package:monte_carlo_simulator/screens/saved_portfolio_form_screen.dart';
import 'package:monte_carlo_simulator/services/investment_service.dart';
import 'package:monte_carlo_simulator/services/member_service.dart';
import 'package:monte_carlo_simulator/services/quote_service.dart';
import 'package:monte_carlo_simulator/state/providers.dart';

class _FakeQuoteService extends Mock implements QuoteService {}

Household _hh() => Household(
      id: 'h1',
      name: 'Smith Family',
      advisorIds: const ['advisor-uid'],
      createdAt: DateTime.utc(2026, 6, 1),
      createdBy: 'advisor-uid',
    );

void main() {
  setUpAll(() => registerFallbackValue(<String>[]));

  Future<FakeFirebaseFirestore> _seed(Map<String, num> holdings) async {
    final db = FakeFirebaseFirestore();
    final col = db.collection('households').doc('h1').collection('investments');
    var i = 0;
    for (final entry in holdings.entries) {
      await col.doc('i${i++}').set({
        'ticker': entry.key,
        'quantity': entry.value,
      });
    }
    return db;
  }

  Widget _host(FakeFirebaseFirestore db, QuoteService quotes) {
    return ProviderScope(
      overrides: [
        // The Members tab is index 0 and builds immediately, so it needs a
        // Firestore-backed service too (otherwise it hits the uninitialized
        // FirebaseFirestore.instance singleton).
        memberServiceProvider.overrideWithValue(MemberService(db: db)),
        investmentServiceProvider.overrideWithValue(InvestmentService(db: db)),
        quoteServiceProvider.overrideWithValue(quotes),
        currentAdvisorUidProvider.overrideWithValue('advisor-uid'),
      ],
      child: MaterialApp(home: HouseholdDetailScreen(household: _hh())),
    );
  }

  Future<void> _openInvestmentsTab(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.text('Investments'));
    await tester.pumpAndSettle();
  }

  testWidgets('values holdings live and totals the portfolio', (tester) async {
    final db = await _seed({'AAPL': 10, 'MSFT': 5, 'ZZZZ': 3});
    final quotes = _FakeQuoteService();
    when(() => quotes.fetchQuotes(any())).thenAnswer(
      (_) async => const QuotesResult(
        quotes: {
          'AAPL': Quote(price: 150, asOf: '2026-06-03'),
          'MSFT': Quote(price: 300, asOf: '2026-06-03'),
        },
        missing: ['ZZZZ'],
      ),
    );

    await tester.pumpWidget(_host(db, quotes));
    await _openInvestmentsTab(tester);

    // All three rows render.
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('MSFT'), findsOneWidget);
    expect(find.text('ZZZZ'), findsOneWidget);

    // 10*150 + 5*300 = 3000 total; each priced row is worth 1500.
    expect(find.text('\$3,000'), findsOneWidget);
    expect(find.text('\$1,500'), findsNWidgets(2));

    // The unpriced ticker is surfaced, not silently dropped.
    expect(find.textContaining('No price for: ZZZZ'), findsOneWidget);
    expect(find.text('No price'), findsOneWidget); // ZZZZ row value label
  });

  testWidgets('shows a delayed-prices note when quotes are stale',
      (tester) async {
    final db = await _seed({'AAPL': 2});
    final quotes = _FakeQuoteService();
    when(() => quotes.fetchQuotes(any())).thenAnswer(
      (_) async => const QuotesResult(
        quotes: {'AAPL': Quote(price: 100, asOf: '2026-06-01')},
        missing: [],
        stale: true,
      ),
    );

    await tester.pumpWidget(_host(db, quotes));
    await _openInvestmentsTab(tester);

    expect(find.textContaining('Prices may be delayed'), findsOneWidget);
    // 2 * 100 = 200 appears twice with a single holding: the row and the total.
    expect(find.text('\$200'), findsNWidgets(2));
  });

  testWidgets('empty state invites adding a holding', (tester) async {
    final db = await _seed(const {});
    final quotes = _FakeQuoteService();
    when(() => quotes.fetchQuotes(any()))
        .thenAnswer((_) async => QuotesResult.empty);

    await tester.pumpWidget(_host(db, quotes));
    await _openInvestmentsTab(tester);

    expect(find.textContaining('No holdings yet'), findsOneWidget);
  });

  testWidgets('Add-holding FAB opens the investment form', (tester) async {
    final db = await _seed({'AAPL': 1});
    final quotes = _FakeQuoteService();
    when(() => quotes.fetchQuotes(any())).thenAnswer(
      (_) async => const QuotesResult(
        quotes: {'AAPL': Quote(price: 100, asOf: '2026-06-01')},
        missing: [],
      ),
    );

    await tester.pumpWidget(_host(db, quotes));
    await _openInvestmentsTab(tester);

    await tester.tap(find.text('Add holding'));
    await tester.pumpAndSettle();
    expect(find.byType(InvestmentFormScreen), findsOneWidget);
  });

  testWidgets('Save as portfolio opens the form prefilled with holdings',
      (tester) async {
    final db = await _seed({'AAPL': 10, 'MSFT': 5});
    final quotes = _FakeQuoteService();
    when(() => quotes.fetchQuotes(any())).thenAnswer(
      (_) async => const QuotesResult(
        quotes: {
          'AAPL': Quote(price: 150, asOf: '2026-06-03'),
          'MSFT': Quote(price: 300, asOf: '2026-06-03'),
        },
        missing: [],
      ),
    );

    await tester.pumpWidget(_host(db, quotes));
    await _openInvestmentsTab(tester);

    await tester.tap(find.text('Save as portfolio'));
    await tester.pumpAndSettle();

    expect(find.byType(SavedPortfolioFormScreen), findsOneWidget);
    expect(find.text('New portfolio'), findsOneWidget); // app bar title
    // Tickers are carried into the prefilled rows.
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('MSFT'), findsOneWidget);
  });
}
