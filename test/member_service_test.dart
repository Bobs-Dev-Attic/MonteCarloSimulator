import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte_carlo_simulator/models/member.dart';
import 'package:monte_carlo_simulator/services/member_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MemberService svc;

  setUp(() {
    db = FakeFirebaseFirestore();
    svc = MemberService(db: db);
  });

  test('createMember writes under households/{hid}/members', () async {
    final id = await svc.createMember(
      householdId: 'h1',
      advisorUid: 'advisor-uid',
      draft: MemberDraft(
        name: 'John',
        relation: MemberRelation.primary,
        currentAge: 47,
      ),
    );
    final snap = await db
        .collection('households')
        .doc('h1')
        .collection('members')
        .doc(id)
        .get();
    expect(snap.exists, isTrue);
    expect(snap.data()!['name'], 'John');
    expect(snap.data()!['relation'], 'primary');
    expect(snap.data()!['currentAge'], 47);
    expect(snap.data()!['createdBy'], 'advisor-uid');
  });

  test('updateMember patches without altering createdBy/createdAt', () async {
    final ref = db
        .collection('households')
        .doc('h1')
        .collection('members')
        .doc('m1');
    await ref.set({
      'name': 'Old',
      'relation': 'primary',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      'createdBy': 'original-advisor',
    });
    await svc.updateMember(
      householdId: 'h1',
      memberId: 'm1',
      draft: MemberDraft(name: 'New', relation: MemberRelation.spouse),
    );
    final after = await ref.get();
    expect(after.data()!['name'], 'New');
    expect(after.data()!['relation'], 'spouse');
    expect(after.data()!['createdBy'], 'original-advisor');
    expect(
      (after.data()!['createdAt'] as Timestamp)
          .toDate()
          .isAtSameMomentAs(DateTime.utc(2026, 1, 1)),
      isTrue,
    );
  });

  test('deleteMember removes the doc', () async {
    final ref = db
        .collection('households')
        .doc('h1')
        .collection('members')
        .doc('m1');
    await ref.set({'name': 'X', 'relation': 'primary'});
    await svc.deleteMember(householdId: 'h1', memberId: 'm1');
    expect((await ref.get()).exists, isFalse);
  });

  test('watchMembers emits sorted by (relation.index, name)', () async {
    final col =
        db.collection('households').doc('h1').collection('members');
    await col.doc('m1').set({'name': 'Zoe', 'relation': 'child'});
    await col.doc('m2').set({'name': 'Alice', 'relation': 'primary'});
    await col.doc('m3').set({'name': 'Bob', 'relation': 'spouse'});
    await col.doc('m4').set({'name': 'Charlie', 'relation': 'child'});
    await col.doc('m5').set({'name': 'anna', 'relation': 'child'}); // lowercase for case-insensitivity check
    final list = await svc.watchMembers('h1').first;
    expect(
      list.map((m) => m.name).toList(),
      ['Alice', 'Bob', 'anna', 'Charlie', 'Zoe'],
    );
  });

  test('watchMembers scopes to the household', () async {
    await db
        .collection('households')
        .doc('h1')
        .collection('members')
        .doc('m1')
        .set({'name': 'A', 'relation': 'primary'});
    await db
        .collection('households')
        .doc('h2')
        .collection('members')
        .doc('m1')
        .set({'name': 'B', 'relation': 'primary'});
    final list = await svc.watchMembers('h1').first;
    expect(list.length, 1);
    expect(list.first.name, 'A');
  });
}
