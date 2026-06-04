import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte_carlo_simulator/services/household_service.dart';

void main() {
  group('HouseholdService', () {
    test('createHousehold writes a doc with the caller in advisorIds', () async {
      final db = FakeFirebaseFirestore();
      final service = HouseholdService(db: db);

      final id = await service.createHousehold(
        advisorUid: 'advisor-1',
        name: '  The Smiths  ',
      );

      final snap = await db.collection('households').doc(id).get();
      final data = snap.data()!;
      expect(data['name'], 'The Smiths');
      expect(data['advisorIds'], ['advisor-1']);
      expect(data['createdBy'], 'advisor-1');
    });

    test('watchHouseholds returns only households containing the uid', () async {
      final db = FakeFirebaseFirestore();
      final service = HouseholdService(db: db);

      await service.createHousehold(advisorUid: 'a1', name: 'H1');
      await service.createHousehold(advisorUid: 'a2', name: 'H2');
      await service.createHousehold(advisorUid: 'a1', name: 'H3');

      final list = await service.watchHouseholds('a1').first;
      expect(list.map((h) => h.name).toSet(), {'H1', 'H3'});
    });

    test('deleteHousehold removes the document', () async {
      final db = FakeFirebaseFirestore();
      final service = HouseholdService(db: db);

      final id =
          await service.createHousehold(advisorUid: 'a1', name: 'Gone');
      await service.deleteHousehold(id);
      final snap = await db.collection('households').doc(id).get();
      expect(snap.exists, isFalse);
    });
  });
}
