import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte_carlo_simulator/models/household.dart';

void main() {
  group('Household', () {
    test('fromDoc parses a written document', () async {
      final db = FakeFirebaseFirestore();
      final ref = db.collection('households').doc('h1');
      await ref.set({
        'name': 'The Smiths',
        'advisorIds': ['advisor-1'],
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 4, 12)),
        'createdBy': 'advisor-1',
      });
      final snap = await ref.get();

      final h = Household.fromDoc(snap);

      expect(h.id, 'h1');
      expect(h.name, 'The Smiths');
      expect(h.advisorIds, ['advisor-1']);
      expect(h.createdAt, DateTime.utc(2026, 4, 12));
      expect(h.createdBy, 'advisor-1');
    });

    test('fromDoc tolerates a null createdAt (serverTimestamp pending)', () async {
      final db = FakeFirebaseFirestore();
      final ref = db.collection('households').doc('h2');
      await ref.set({
        'name': 'Pending',
        'advisorIds': ['a'],
        'createdAt': null,
        'createdBy': 'a',
      });
      final snap = await ref.get();

      final h = Household.fromDoc(snap);
      expect(h.createdAt, isA<DateTime>());
    });

    test('toFirestore emits expected fields with serverTimestamp', () {
      final write = Household.toCreatePayload(
        name: 'Acme Trust',
        advisorUid: 'advisor-9',
      );

      expect(write['name'], 'Acme Trust');
      expect(write['advisorIds'], ['advisor-9']);
      expect(write['createdBy'], 'advisor-9');
      expect(write['createdAt'], isA<FieldValue>());
    });
  });
}
