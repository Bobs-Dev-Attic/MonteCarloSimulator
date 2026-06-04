import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte_carlo_simulator/models/member.dart';

void main() {
  group('Member.fromDoc', () {
    late FakeFirebaseFirestore db;

    setUp(() {
      db = FakeFirebaseFirestore();
    });

    test('parses full document', () async {
      final ref = db.collection('households').doc('h1').collection('members').doc('m1');
      await ref.set({
        'name': 'John Smith',
        'relation': 'primary',
        'dateOfBirth': Timestamp.fromDate(DateTime.utc(1978, 4, 12)),
        'currentAge': 47,
        'retirementAge': 65,
        'lifeExpectancy': 90,
        'annualIncome': 175000.0,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 6, 1)),
        'createdBy': 'advisor-uid',
      });
      final snap = await ref.get();
      final m = Member.fromDoc(snap, 'h1');

      expect(m.id, 'm1');
      expect(m.householdId, 'h1');
      expect(m.name, 'John Smith');
      expect(m.relation, MemberRelation.primary);
      expect(
        m.dateOfBirth!.isAtSameMomentAs(DateTime.utc(1978, 4, 12)),
        isTrue,
      );
      expect(m.currentAge, 47);
      expect(m.retirementAge, 65);
      expect(m.lifeExpectancy, 90);
      expect(m.annualIncome, 175000.0);
      expect(m.createdBy, 'advisor-uid');
    });

    test('unknown relation decodes to other', () async {
      final ref = db.collection('households').doc('h1').collection('members').doc('m1');
      await ref.set({
        'name': 'Jane',
        'relation': 'godparent',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 6, 1)),
        'createdBy': 'a',
      });
      final m = Member.fromDoc(await ref.get(), 'h1');
      expect(m.relation, MemberRelation.other);
    });

    test('null optionals stay null', () async {
      final ref = db.collection('households').doc('h1').collection('members').doc('m1');
      await ref.set({
        'name': 'Jane',
        'relation': 'spouse',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 6, 1)),
        'createdBy': 'a',
      });
      final m = Member.fromDoc(await ref.get(), 'h1');
      expect(m.dateOfBirth, isNull);
      expect(m.currentAge, isNull);
      expect(m.retirementAge, isNull);
      expect(m.lifeExpectancy, isNull);
      expect(m.annualIncome, isNull);
    });
  });

  group('Member.toCreatePayload', () {
    test('includes serverTimestamp sentinel and createdBy', () {
      final payload = Member.toCreatePayload(
        advisorUid: 'advisor-uid',
        draft: MemberDraft(name: 'John', relation: MemberRelation.primary),
      );
      expect(payload['name'], 'John');
      expect(payload['relation'], 'primary');
      expect(payload['createdBy'], 'advisor-uid');
      expect(payload['createdAt'], isA<FieldValue>());
    });

    test('omits null optionals from payload values, but keys exist', () {
      final payload = Member.toCreatePayload(
        advisorUid: 'a',
        draft: MemberDraft(name: 'X', relation: MemberRelation.child),
      );
      expect(payload['dateOfBirth'], isNull);
      expect(payload['currentAge'], isNull);
      expect(payload['annualIncome'], isNull);
    });
  });

  group('MemberDraft.toUpdatePayload', () {
    test('does not include createdAt or createdBy', () {
      final p = MemberDraft(
        name: 'John',
        relation: MemberRelation.primary,
        currentAge: 47,
      ).toUpdatePayload();
      expect(p.containsKey('createdAt'), isFalse);
      expect(p.containsKey('createdBy'), isFalse);
      expect(p['name'], 'John');
      expect(p['relation'], 'primary');
      expect(p['currentAge'], 47);
    });
  });

  group('Member.effectiveAge', () {
    Member make({DateTime? dob, int? age}) => Member(
          id: 'm',
          householdId: 'h',
          name: 'X',
          relation: MemberRelation.other,
          dateOfBirth: dob,
          currentAge: age,
          createdAt: DateTime.utc(2026, 6, 1),
          createdBy: 'a',
        );

    test('returns DOB-derived age when DOB present', () {
      final dob = DateTime.utc(1978, 4, 12);
      final today = DateTime.now();
      final hadBirthday = today.month > dob.month ||
          (today.month == dob.month && today.day >= dob.day);
      final expected = today.year - dob.year - (hadBirthday ? 0 : 1);
      final m = make(dob: dob);
      expect(m.effectiveAge, expected);
    });

    test('falls back to currentAge when DOB null', () {
      expect(make(age: 30).effectiveAge, 30);
    });

    test('returns null when both null', () {
      expect(make().effectiveAge, isNull);
    });

    test('returns null for future date of birth', () {
      final future = DateTime.now().add(const Duration(days: 365 * 5));
      expect(make(dob: future).effectiveAge, isNull);
    });
  });
}
