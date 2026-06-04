import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte_carlo_simulator/models/household.dart';
import 'package:monte_carlo_simulator/screens/household_detail_screen.dart';
import 'package:monte_carlo_simulator/screens/saved_portfolio_form_screen.dart';
import 'package:monte_carlo_simulator/services/investment_service.dart';
import 'package:monte_carlo_simulator/services/member_service.dart';
import 'package:monte_carlo_simulator/services/saved_portfolio_service.dart';
import 'package:monte_carlo_simulator/state/providers.dart';

Household _hh() => Household(
      id: 'h1',
      name: 'Smith Family',
      advisorIds: const ['advisor-uid'],
      createdAt: DateTime.utc(2026, 6, 1),
      createdBy: 'advisor-uid',
    );

void main() {
  Future<FakeFirebaseFirestore> _seed(
      List<Map<String, dynamic>> portfolios) async {
    final db = FakeFirebaseFirestore();
    final col = db.collection('households').doc('h1').collection('portfolios');
    var i = 0;
    for (final p in portfolios) {
      await col.doc('p${i++}').set(p);
    }
    return db;
  }

  Widget _host(FakeFirebaseFirestore db) {
    return ProviderScope(
      overrides: [
        // The Members/Investments tabs may build during tab transitions, so
        // back their services with the same fake Firestore (both empty).
        memberServiceProvider.overrideWithValue(MemberService(db: db)),
        investmentServiceProvider.overrideWithValue(InvestmentService(db: db)),
        savedPortfolioServiceProvider
            .overrideWithValue(SavedPortfolioService(db: db)),
        currentAdvisorUidProvider.overrideWithValue('advisor-uid'),
      ],
      child: MaterialApp(home: HouseholdDetailScreen(household: _hh())),
    );
  }

  Future<void> _openPortfoliosTab(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portfolios'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists saved portfolios with holding summaries', (tester) async {
    final db = await _seed([
      {
        'name': '60/40 Growth',
        'period': '5y',
        'holdings': [
          {'ticker': 'VTI', 'weight': 60},
          {'ticker': 'BND', 'weight': 40},
        ],
      },
      {
        'name': 'All Equity',
        'period': '10y',
        'holdings': [
          {'ticker': 'VOO', 'weight': 100},
        ],
      },
    ]);

    await tester.pumpWidget(_host(db));
    await _openPortfoliosTab(tester);

    expect(find.text('60/40 Growth'), findsOneWidget);
    expect(find.text('All Equity'), findsOneWidget);
    expect(find.textContaining('2 holdings · VTI, BND'), findsOneWidget);
    expect(find.textContaining('1 holding · VOO'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Simulate'), findsNWidgets(2));
  });

  testWidgets('empty state invites modeling a basket', (tester) async {
    final db = await _seed(const []);
    await tester.pumpWidget(_host(db));
    await _openPortfoliosTab(tester);
    expect(find.textContaining('No portfolios yet'), findsOneWidget);
  });

  testWidgets('Add-portfolio FAB opens the form', (tester) async {
    final db = await _seed(const []);
    await tester.pumpWidget(_host(db));
    await _openPortfoliosTab(tester);

    await tester.tap(find.text('Add portfolio'));
    await tester.pumpAndSettle();
    expect(find.byType(SavedPortfolioFormScreen), findsOneWidget);
  });
}
