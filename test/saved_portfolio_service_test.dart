import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte_carlo_simulator/models/saved_portfolio.dart';
import 'package:monte_carlo_simulator/services/saved_portfolio_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late SavedPortfolioService svc;

  setUp(() {
    db = FakeFirebaseFirestore();
    svc = SavedPortfolioService(db: db);
  });

  SavedPortfolioDraft draft(String name) => SavedPortfolioDraft(
        name: name,
        holdings: const [
          PortfolioHolding(ticker: 'VTI', weight: 60),
          PortfolioHolding(ticker: 'BND', weight: 40),
        ],
        period: '5y',
      );

  test('createPortfolio writes under households/{hid}/portfolios', () async {
    final id = await svc.createPortfolio(
      householdId: 'h1',
      advisorUid: 'advisor-uid',
      draft: draft('60/40'),
    );
    final snap = await db
        .collection('households')
        .doc('h1')
        .collection('portfolios')
        .doc(id)
        .get();
    expect(snap.exists, isTrue);
    expect(snap.data()!['name'], '60/40');
    expect((snap.data()!['holdings'] as List).length, 2);
    expect(snap.data()!['createdBy'], 'advisor-uid');
  });

  test('updatePortfolio patches without altering createdBy/createdAt',
      () async {
    final ref = db
        .collection('households')
        .doc('h1')
        .collection('portfolios')
        .doc('p1');
    await ref.set({
      'name': 'Old',
      'period': '5y',
      'holdings': const [],
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      'createdBy': 'original-advisor',
    });
    await svc.updatePortfolio(
      householdId: 'h1',
      portfolioId: 'p1',
      draft: draft('New'),
    );
    final after = await ref.get();
    expect(after.data()!['name'], 'New');
    expect(after.data()!['createdBy'], 'original-advisor');
    expect(
      (after.data()!['createdAt'] as Timestamp)
          .toDate()
          .isAtSameMomentAs(DateTime.utc(2026, 1, 1)),
      isTrue,
    );
  });

  test('deletePortfolio removes the doc', () async {
    final ref = db
        .collection('households')
        .doc('h1')
        .collection('portfolios')
        .doc('p1');
    await ref.set({'name': 'X', 'holdings': const []});
    await svc.deletePortfolio(householdId: 'h1', portfolioId: 'p1');
    expect((await ref.get()).exists, isFalse);
  });

  test('watchPortfolios emits sorted by name (case-insensitive)', () async {
    final col =
        db.collection('households').doc('h1').collection('portfolios');
    await col.doc('p1').set({'name': 'Zen', 'holdings': const []});
    await col.doc('p2').set({'name': 'aggressive', 'holdings': const []});
    await col.doc('p3').set({'name': 'Balanced', 'holdings': const []});
    final list = await svc.watchPortfolios('h1').first;
    expect(list.map((p) => p.name).toList(),
        ['aggressive', 'Balanced', 'Zen']);
  });

  test('watchPortfolios scopes to the household', () async {
    await db
        .collection('households')
        .doc('h1')
        .collection('portfolios')
        .doc('p1')
        .set({'name': 'A', 'holdings': const []});
    await db
        .collection('households')
        .doc('h2')
        .collection('portfolios')
        .doc('p1')
        .set({'name': 'B', 'holdings': const []});
    final list = await svc.watchPortfolios('h1').first;
    expect(list.length, 1);
    expect(list.first.name, 'A');
  });
}
