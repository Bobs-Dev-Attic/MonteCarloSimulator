import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte_carlo_simulator/models/investment.dart';
import 'package:monte_carlo_simulator/services/investment_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late InvestmentService svc;

  setUp(() {
    db = FakeFirebaseFirestore();
    svc = InvestmentService(db: db);
  });

  test('createInvestment writes under households/{hid}/investments', () async {
    final id = await svc.createInvestment(
      householdId: 'h1',
      advisorUid: 'advisor-uid',
      draft: InvestmentDraft(ticker: 'aapl', quantity: 10),
    );
    final snap = await db
        .collection('households')
        .doc('h1')
        .collection('investments')
        .doc(id)
        .get();
    expect(snap.exists, isTrue);
    expect(snap.data()!['ticker'], 'AAPL'); // normalized on write
    expect(snap.data()!['quantity'], 10);
    expect(snap.data()!['createdBy'], 'advisor-uid');
  });

  test('updateInvestment patches without altering createdBy/createdAt',
      () async {
    final ref = db
        .collection('households')
        .doc('h1')
        .collection('investments')
        .doc('i1');
    await ref.set({
      'ticker': 'AAPL',
      'quantity': 5,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      'createdBy': 'original-advisor',
    });
    await svc.updateInvestment(
      householdId: 'h1',
      investmentId: 'i1',
      draft: InvestmentDraft(ticker: 'AAPL', quantity: 8),
    );
    final after = await ref.get();
    expect(after.data()!['quantity'], 8);
    expect(after.data()!['createdBy'], 'original-advisor');
    expect(
      (after.data()!['createdAt'] as Timestamp)
          .toDate()
          .isAtSameMomentAs(DateTime.utc(2026, 1, 1)),
      isTrue,
    );
  });

  test('deleteInvestment removes the doc', () async {
    final ref = db
        .collection('households')
        .doc('h1')
        .collection('investments')
        .doc('i1');
    await ref.set({'ticker': 'AAPL', 'quantity': 1});
    await svc.deleteInvestment(householdId: 'h1', investmentId: 'i1');
    expect((await ref.get()).exists, isFalse);
  });

  test('watchInvestments emits sorted by ticker (case-insensitive)', () async {
    final col =
        db.collection('households').doc('h1').collection('investments');
    await col.doc('i1').set({'ticker': 'MSFT', 'quantity': 1});
    await col.doc('i2').set({'ticker': 'aapl', 'quantity': 1});
    await col.doc('i3').set({'ticker': 'TSLA', 'quantity': 1});
    final list = await svc.watchInvestments('h1').first;
    expect(list.map((i) => i.ticker).toList(), ['AAPL', 'MSFT', 'TSLA']);
  });

  test('watchInvestments scopes to the household', () async {
    await db
        .collection('households')
        .doc('h1')
        .collection('investments')
        .doc('i1')
        .set({'ticker': 'AAPL', 'quantity': 1});
    await db
        .collection('households')
        .doc('h2')
        .collection('investments')
        .doc('i1')
        .set({'ticker': 'MSFT', 'quantity': 1});
    final list = await svc.watchInvestments('h1').first;
    expect(list.length, 1);
    expect(list.first.ticker, 'AAPL');
  });
}
