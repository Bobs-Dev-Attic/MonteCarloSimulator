import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte_carlo_simulator/models/investment.dart';

void main() {
  group('Investment.fromDoc', () {
    late FakeFirebaseFirestore db;

    setUp(() {
      db = FakeFirebaseFirestore();
    });

    test('parses a full document', () async {
      final ref = db
          .collection('households')
          .doc('h1')
          .collection('investments')
          .doc('i1');
      await ref.set({
        'ticker': 'AAPL',
        'quantity': 12.5,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 6, 1)),
        'createdBy': 'advisor-uid',
      });
      final inv = Investment.fromDoc(await ref.get(), 'h1');

      expect(inv.id, 'i1');
      expect(inv.householdId, 'h1');
      expect(inv.ticker, 'AAPL');
      expect(inv.quantity, 12.5);
      expect(inv.createdBy, 'advisor-uid');
    });

    test('upper-cases a lower-case stored ticker', () async {
      final ref = db
          .collection('households')
          .doc('h1')
          .collection('investments')
          .doc('i1');
      await ref.set({
        'ticker': 'msft',
        'quantity': 3,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 6, 1)),
        'createdBy': 'a',
      });
      final inv = Investment.fromDoc(await ref.get(), 'h1');
      expect(inv.ticker, 'MSFT');
    });

    test('defaults quantity to 0 when missing', () async {
      final ref = db
          .collection('households')
          .doc('h1')
          .collection('investments')
          .doc('i1');
      await ref.set({
        'ticker': 'TSLA',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 6, 1)),
        'createdBy': 'a',
      });
      final inv = Investment.fromDoc(await ref.get(), 'h1');
      expect(inv.quantity, 0.0);
    });
  });

  group('Investment.marketValue', () {
    Investment make(double qty) => Investment(
          id: 'i',
          householdId: 'h',
          ticker: 'AAPL',
          quantity: qty,
          createdAt: DateTime.utc(2026, 6, 1),
          createdBy: 'a',
        );

    test('multiplies quantity by price', () {
      expect(make(10).marketValue(25.0), 250.0);
    });

    test('is null when no price', () {
      expect(make(10).marketValue(null), isNull);
    });
  });

  group('InvestmentDraft.toUpdatePayload', () {
    test('trims and upper-cases the ticker', () {
      final p = InvestmentDraft(ticker: '  aapl ', quantity: 5).toUpdatePayload();
      expect(p['ticker'], 'AAPL');
      expect(p['quantity'], 5);
      expect(p.containsKey('createdAt'), isFalse);
      expect(p.containsKey('createdBy'), isFalse);
    });
  });

  group('Investment.toCreatePayload', () {
    test('adds serverTimestamp sentinel and createdBy', () {
      final payload = Investment.toCreatePayload(
        advisorUid: 'advisor-uid',
        draft: InvestmentDraft(ticker: 'AAPL', quantity: 2),
      );
      expect(payload['ticker'], 'AAPL');
      expect(payload['quantity'], 2);
      expect(payload['createdBy'], 'advisor-uid');
      expect(payload['createdAt'], isA<FieldValue>());
    });
  });
}
