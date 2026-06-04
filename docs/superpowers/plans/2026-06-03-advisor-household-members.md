# Advisor Household Members Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a members subcollection under each household with full create / list / edit / delete from the advisor UI, replacing today's stub `HouseholdDetailScreen` with a two-tab shell (Members | Portfolios-stub).

**Architecture:** New `Member` model + `MemberDraft` form-state class + `MemberService` (CRUD + watch via `fake_cloud_firestore`-testable Firestore wrapper). Riverpod `membersProvider.family` keyed by household id. UI: `HouseholdDetailScreen` becomes `DefaultTabController(length: 2)`; the Members tab hosts list/empty-state/FAB; new `MemberFormScreen` handles both create and edit. A small `NullableScrubField` wraps the existing `ScrubField` to support optional numeric fields.

**Tech Stack:** Flutter, Riverpod 3.x, cloud_firestore, fake_cloud_firestore (test), the existing `ScrubField` widget from the results-redesign sub-project.

**Spec:** [docs/superpowers/specs/2026-06-03-advisor-household-members-design.md](../specs/2026-06-03-advisor-household-members-design.md)

---

## File structure

**New files:**
- `lib/models/member.dart` — `MemberRelation` enum, `Member` class, `MemberDraft` value class.
- `lib/services/member_service.dart` — `MemberService` with `watchMembers`, `createMember`, `updateMember`, `deleteMember`.
- `lib/widgets/relation_labels.dart` — `relationLabel(MemberRelation)` + `relationIcon(MemberRelation)`.
- `lib/widgets/nullable_scrub_field.dart` — `NullableScrubField` wrapping `ScrubField` for optional numerics.
- `lib/screens/member_form_screen.dart` — Create/edit form.
- `test/member_test.dart`, `test/member_service_test.dart`, `test/widgets/household_detail_screen_test.dart`, `test/widgets/member_form_screen_test.dart`.

**Modified:**
- `lib/state/providers.dart` — add `memberServiceProvider` + `membersProvider.family`.
- `lib/screens/household_detail_screen.dart` — replace stub body with two-tab layout.

**Untouched:** household model/service/providers, `ScrubField`, home screen, simulator path.

---

### Task 1: Member model and MemberDraft

**Files:**
- Create: `lib/models/member.dart`
- Test: `test/member_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/member_test.dart`:

```dart
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
      expect(m.dateOfBirth, DateTime.utc(1978, 4, 12));
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
      // born 1978-04-12; "now" is approximately 2026-06-03 in test env.
      final m = make(dob: DateTime.utc(1978, 4, 12));
      expect(m.effectiveAge, anyOf(47, 48));
    });

    test('falls back to currentAge when DOB null', () {
      expect(make(age: 30).effectiveAge, 30);
    });

    test('returns null when both null', () {
      expect(make().effectiveAge, isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/member_test.dart`
Expected: FAIL — `Member` not defined.

- [ ] **Step 3: Implement the model**

Create `lib/models/member.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum MemberRelation { primary, spouse, child, parent, dependent, other }

MemberRelation _relationFromString(String? s) {
  for (final r in MemberRelation.values) {
    if (r.name == s) return r;
  }
  return MemberRelation.other;
}

class MemberDraft {
  MemberDraft({
    required this.name,
    required this.relation,
    this.dateOfBirth,
    this.currentAge,
    this.retirementAge,
    this.lifeExpectancy,
    this.annualIncome,
  });

  final String name;
  final MemberRelation relation;
  final DateTime? dateOfBirth;
  final int? currentAge;
  final int? retirementAge;
  final int? lifeExpectancy;
  final double? annualIncome;

  Map<String, Object?> toUpdatePayload() {
    return {
      'name': name.trim(),
      'relation': relation.name,
      'dateOfBirth':
          dateOfBirth == null ? null : Timestamp.fromDate(dateOfBirth!),
      'currentAge': currentAge,
      'retirementAge': retirementAge,
      'lifeExpectancy': lifeExpectancy,
      'annualIncome': annualIncome,
    };
  }
}

class Member {
  Member({
    required this.id,
    required this.householdId,
    required this.name,
    required this.relation,
    this.dateOfBirth,
    this.currentAge,
    this.retirementAge,
    this.lifeExpectancy,
    this.annualIncome,
    required this.createdAt,
    required this.createdBy,
  });

  final String id;
  final String householdId;
  final String name;
  final MemberRelation relation;
  final DateTime? dateOfBirth;
  final int? currentAge;
  final int? retirementAge;
  final int? lifeExpectancy;
  final double? annualIncome;
  final DateTime createdAt;
  final String createdBy;

  int? get effectiveAge {
    final dob = dateOfBirth;
    if (dob != null) {
      final now = DateTime.now();
      var age = now.year - dob.year;
      final hadBirthdayThisYear = (now.month > dob.month) ||
          (now.month == dob.month && now.day >= dob.day);
      if (!hadBirthdayThisYear) age -= 1;
      return age;
    }
    return currentAge;
  }

  factory Member.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String householdId,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Member(
      id: doc.id,
      householdId: householdId,
      name: (data['name'] as String?) ?? '',
      relation: _relationFromString(data['relation'] as String?),
      dateOfBirth: (data['dateOfBirth'] as Timestamp?)?.toDate(),
      currentAge: (data['currentAge'] as num?)?.toInt(),
      retirementAge: (data['retirementAge'] as num?)?.toInt(),
      lifeExpectancy: (data['lifeExpectancy'] as num?)?.toInt(),
      annualIncome: (data['annualIncome'] as num?)?.toDouble(),
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: (data['createdBy'] as String?) ?? '',
    );
  }

  static Map<String, Object?> toCreatePayload({
    required String advisorUid,
    required MemberDraft draft,
  }) {
    final base = draft.toUpdatePayload();
    return {
      ...base,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': advisorUid,
    };
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/member_test.dart`
Expected: PASS, all groups green.

- [ ] **Step 5: Commit**

```bash
git add lib/models/member.dart test/member_test.dart
git commit -m "feat: add Member model and MemberDraft"
```

---

### Task 2: MemberService

**Files:**
- Create: `lib/services/member_service.dart`
- Test: `test/member_service_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/member_service_test.dart`:

```dart
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
      (after.data()!['createdAt'] as Timestamp).toDate(),
      DateTime.utc(2026, 1, 1),
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
    final list = await svc.watchMembers('h1').first;
    expect(list.map((m) => m.name).toList(), ['Alice', 'Bob', 'Zoe']);
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/member_service_test.dart`
Expected: FAIL — `MemberService` not defined.

- [ ] **Step 3: Implement the service**

Create `lib/services/member_service.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/member.dart';

class MemberService {
  MemberService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _members(String hid) =>
      _db.collection('households').doc(hid).collection('members');

  Stream<List<Member>> watchMembers(String householdId) {
    return _members(householdId).snapshots().map((snap) {
      final list = snap.docs
          .map((d) => Member.fromDoc(d, householdId))
          .toList()
        ..sort((a, b) {
          final byRel = a.relation.index.compareTo(b.relation.index);
          if (byRel != 0) return byRel;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      return list;
    });
  }

  Future<String> createMember({
    required String householdId,
    required String advisorUid,
    required MemberDraft draft,
  }) async {
    final ref = await _members(householdId).add(
      Member.toCreatePayload(advisorUid: advisorUid, draft: draft),
    );
    return ref.id;
  }

  Future<void> updateMember({
    required String householdId,
    required String memberId,
    required MemberDraft draft,
  }) {
    return _members(householdId)
        .doc(memberId)
        .update(draft.toUpdatePayload());
  }

  Future<void> deleteMember({
    required String householdId,
    required String memberId,
  }) {
    return _members(householdId).doc(memberId).delete();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/member_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/member_service.dart test/member_service_test.dart
git commit -m "feat: add MemberService with CRUD + watch"
```

---

### Task 3: Riverpod providers

**Files:**
- Modify: `lib/state/providers.dart`

- [ ] **Step 1: Add the providers**

In `lib/state/providers.dart`, add the import:

```dart
import '../services/member_service.dart';
```

And after the existing `currentAdvisorUidProvider`, append:

```dart
final memberServiceProvider =
    Provider<MemberService>((ref) => MemberService());

/// Live, sorted list of members under a household. Keyed by household id.
final membersProvider = StreamProvider.autoDispose
    .family<List<Member>, String>(
  (ref, hid) => ref.watch(memberServiceProvider).watchMembers(hid),
);
```

Add the missing import at the top:

```dart
import '../models/member.dart';
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/state/providers.dart`
Expected: no errors (pre-existing infos OK).

- [ ] **Step 3: Commit**

```bash
git add lib/state/providers.dart
git commit -m "feat: add memberServiceProvider and membersProvider family"
```

---

### Task 4: relation_labels helper

**Files:**
- Create: `lib/widgets/relation_labels.dart`

- [ ] **Step 1: Implement**

Create `lib/widgets/relation_labels.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/member.dart';

String relationLabel(MemberRelation r) {
  switch (r) {
    case MemberRelation.primary:
      return 'primary';
    case MemberRelation.spouse:
      return 'spouse';
    case MemberRelation.child:
      return 'child';
    case MemberRelation.parent:
      return 'parent';
    case MemberRelation.dependent:
      return 'dependent';
    case MemberRelation.other:
      return 'other';
  }
}

IconData relationIcon(MemberRelation r) {
  switch (r) {
    case MemberRelation.primary:
      return Icons.person;
    case MemberRelation.spouse:
      return Icons.favorite_outline;
    case MemberRelation.child:
      return Icons.child_care;
    case MemberRelation.parent:
      return Icons.elderly;
    case MemberRelation.dependent:
    case MemberRelation.other:
      return Icons.group;
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/relation_labels.dart
git commit -m "feat: add relation label and icon helpers"
```

---

### Task 5: NullableScrubField wrapper

**Files:**
- Create: `lib/widgets/nullable_scrub_field.dart`

- [ ] **Step 1: Implement**

A small `StatefulWidget` that wraps `ScrubField` and tracks whether
the user has touched the field. Untouched → `onChanged(null)` on save
intent; touched → emit the current numeric value. The widget exposes
its current value through `onChanged` so the parent form owns the
state.

Create `lib/widgets/nullable_scrub_field.dart`:

```dart
import 'package:flutter/material.dart';

import 'scrub_field.dart';

/// Wraps [ScrubField] so callers can model an "unset" state distinctly
/// from a typed-or-scrubbed zero. The user opts the field into a value
/// by tapping a "Set" affordance; once set, the field behaves like a
/// normal [ScrubField]. Tapping "Clear" returns to the unset state.
class NullableScrubField extends StatefulWidget {
  const NullableScrubField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.kind,
    this.suffixText,
    this.minValue,
    this.maxValue,
    this.initialIfSet = 0,
  });

  final String label;
  final double? value;
  final ValueChanged<double?> onChanged;
  final ScrubKind kind;
  final String? suffixText;
  final double? minValue;
  final double? maxValue;

  /// Default numeric value used the first time the user opts in.
  final double initialIfSet;

  @override
  State<NullableScrubField> createState() => _NullableScrubFieldState();
}

class _NullableScrubFieldState extends State<NullableScrubField> {
  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    if (v == null) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: Row(
          children: [
            const Expanded(child: Text('—')),
            TextButton(
              key: ValueKey('${widget.label}-set'),
              onPressed: () => widget.onChanged(widget.initialIfSet),
              child: const Text('Set'),
            ),
          ],
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: ScrubField(
            label: widget.label,
            value: v,
            onChanged: widget.onChanged,
            kind: widget.kind,
            suffixText: widget.suffixText,
            minValue: widget.minValue,
            maxValue: widget.maxValue,
          ),
        ),
        IconButton(
          key: ValueKey('${widget.label}-clear'),
          tooltip: 'Clear',
          icon: const Icon(Icons.close),
          onPressed: () => widget.onChanged(null),
        ),
      ],
    );
  }
}
```

Note: there is no separate test file for this widget; its behavior is
exercised through `member_form_screen_test.dart` in Task 7.

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/nullable_scrub_field.dart
git commit -m "feat: add NullableScrubField for optional numeric inputs"
```

---

### Task 6: MemberFormScreen

**Files:**
- Create: `lib/screens/member_form_screen.dart`
- Test: `test/widgets/member_form_screen_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/widgets/member_form_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:monte_carlo_simulator/models/member.dart';
import 'package:monte_carlo_simulator/screens/member_form_screen.dart';
import 'package:monte_carlo_simulator/services/member_service.dart';
import 'package:monte_carlo_simulator/state/providers.dart';

class _FakeService extends Mock implements MemberService {}

class _DraftMatcher extends Matcher {
  _DraftMatcher(this.name, this.relation);
  final String name;
  final MemberRelation relation;
  @override
  Description describe(Description d) =>
      d.add('MemberDraft(name=$name, relation=$relation)');
  @override
  bool matches(Object? item, Map matchState) =>
      item is MemberDraft && item.name == name && item.relation == relation;
}

void main() {
  late _FakeService svc;

  setUpAll(() {
    registerFallbackValue(
      MemberDraft(name: '_', relation: MemberRelation.other),
    );
  });

  setUp(() {
    svc = _FakeService();
  });

  Widget _host({Member? existing}) {
    return ProviderScope(
      overrides: [
        memberServiceProvider.overrideWithValue(svc),
        currentAdvisorUidProvider.overrideWithValue('advisor-uid'),
      ],
      child: MaterialApp(
        home: MemberFormScreen(
          householdId: 'h1',
          existing: existing,
        ),
      ),
    );
  }

  testWidgets('empty name shows validation error and does not call service',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.byKey(const ValueKey('save-member')));
    await tester.pump();
    expect(find.text('Name is required'), findsOneWidget);
    verifyNever(() => svc.createMember(
          householdId: any(named: 'householdId'),
          advisorUid: any(named: 'advisorUid'),
          draft: any(named: 'draft'),
        ));
  });

  testWidgets('create calls createMember and pops', (tester) async {
    when(() => svc.createMember(
          householdId: any(named: 'householdId'),
          advisorUid: any(named: 'advisorUid'),
          draft: any(named: 'draft'),
        )).thenAnswer((_) async => 'new-id');

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) {
        return ProviderScope(
          overrides: [
            memberServiceProvider.overrideWithValue(svc),
            currentAdvisorUidProvider.overrideWithValue('advisor-uid'),
          ],
          child: Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) => const MemberFormScreen(householdId: 'h1'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('name-field')),
      'Jane',
    );
    await tester.tap(find.byKey(const ValueKey('save-member')));
    await tester.pumpAndSettle();

    verify(() => svc.createMember(
          householdId: 'h1',
          advisorUid: 'advisor-uid',
          draft: _DraftMatcher('Jane', MemberRelation.primary),
        )).called(1);
    expect(find.byType(MemberFormScreen), findsNothing);
  });

  testWidgets('edit pre-fills and calls updateMember', (tester) async {
    when(() => svc.updateMember(
          householdId: any(named: 'householdId'),
          memberId: any(named: 'memberId'),
          draft: any(named: 'draft'),
        )).thenAnswer((_) async {});

    final existing = Member(
      id: 'm1',
      householdId: 'h1',
      name: 'Old',
      relation: MemberRelation.spouse,
      createdAt: DateTime.utc(2026, 1, 1),
      createdBy: 'a',
    );

    await tester.pumpWidget(_host(existing: existing));
    expect(find.text('Old'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('name-field')),
      'New',
    );
    await tester.tap(find.byKey(const ValueKey('save-member')));
    await tester.pumpAndSettle();

    verify(() => svc.updateMember(
          householdId: 'h1',
          memberId: 'm1',
          draft: _DraftMatcher('New', MemberRelation.spouse),
        )).called(1);
  });

  testWidgets('edit AppBar delete prompts confirm and calls deleteMember',
      (tester) async {
    when(() => svc.deleteMember(
          householdId: any(named: 'householdId'),
          memberId: any(named: 'memberId'),
        )).thenAnswer((_) async {});

    final existing = Member(
      id: 'm1',
      householdId: 'h1',
      name: 'Old',
      relation: MemberRelation.spouse,
      createdAt: DateTime.utc(2026, 1, 1),
      createdBy: 'a',
    );

    await tester.pumpWidget(_host(existing: existing));
    await tester.tap(find.byKey(const ValueKey('delete-member')));
    await tester.pumpAndSettle();

    expect(find.text('Delete this member?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    verify(() => svc.deleteMember(householdId: 'h1', memberId: 'm1'))
        .called(1);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/member_form_screen_test.dart`
Expected: FAIL — `MemberFormScreen` not defined.

- [ ] **Step 3: Implement the form screen**

Create `lib/screens/member_form_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/member.dart';
import '../state/providers.dart';
import '../widgets/nullable_scrub_field.dart';
import '../widgets/relation_labels.dart';
import '../widgets/scrub_field.dart';

class MemberFormScreen extends ConsumerStatefulWidget {
  const MemberFormScreen({
    super.key,
    required this.householdId,
    this.existing,
  });

  final String householdId;
  final Member? existing;

  @override
  ConsumerState<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends ConsumerState<MemberFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late MemberRelation _relation;
  DateTime? _dob;
  double? _currentAge;
  double? _retirementAge;
  double? _lifeExpectancy;
  double? _annualIncome;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _relation = e?.relation ?? MemberRelation.primary;
    _dob = e?.dateOfBirth;
    _currentAge = e?.currentAge?.toDouble();
    _retirementAge = e?.retirementAge?.toDouble();
    _lifeExpectancy = e?.lifeExpectancy?.toDouble();
    _annualIncome = e?.annualIncome;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1900, 1, 1),
      lastDate: now,
      initialDate: _dob ?? DateTime(now.year - 30, now.month, now.day),
    );
    if (picked != null) {
      setState(() => _dob = picked);
    }
  }

  MemberDraft _buildDraft() {
    return MemberDraft(
      name: _nameController.text.trim(),
      relation: _relation,
      dateOfBirth: _dob,
      currentAge: _currentAge?.round(),
      retirementAge: _retirementAge?.round(),
      lifeExpectancy: _lifeExpectancy?.round(),
      annualIncome: _annualIncome,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final svc = ref.read(memberServiceProvider);
      if (_isEdit) {
        await svc.updateMember(
          householdId: widget.householdId,
          memberId: widget.existing!.id,
          draft: _buildDraft(),
        );
      } else {
        final advisor = ref.read(currentAdvisorUidProvider);
        if (advisor == null) {
          throw StateError('Not signed in');
        }
        await svc.createMember(
          householdId: widget.householdId,
          advisorUid: advisor,
          draft: _buildDraft(),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this member?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(memberServiceProvider).deleteMember(
            householdId: widget.householdId,
            memberId: widget.existing!.id,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit member' : 'New member'),
        actions: [
          if (_isEdit)
            IconButton(
              key: const ValueKey('delete-member'),
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _confirmDelete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('name-field'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<MemberRelation>(
                key: const ValueKey('relation-field'),
                initialValue: _relation,
                decoration: const InputDecoration(
                  labelText: 'Relation',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final r in MemberRelation.values)
                    DropdownMenuItem(value: r, child: Text(relationLabel(r))),
                ],
                onChanged: (r) {
                  if (r != null) setState(() => _relation = r);
                },
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date of birth',
                  border: OutlineInputBorder(),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _dob == null
                            ? '—'
                            : '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('dob-field'),
                      onPressed: _pickDob,
                      child: Text(_dob == null ? 'Set' : 'Change'),
                    ),
                    if (_dob != null)
                      IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _dob = null),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              NullableScrubField(
                key: const ValueKey('age-field'),
                label: 'Current age',
                value: _currentAge,
                kind: ScrubKind.integer,
                minValue: 0,
                maxValue: 120,
                initialIfSet: 40,
                onChanged: (v) => setState(() => _currentAge = v),
              ),
              const SizedBox(height: 12),
              NullableScrubField(
                key: const ValueKey('retirement-field'),
                label: 'Retirement age',
                value: _retirementAge,
                kind: ScrubKind.years,
                minValue: 0,
                maxValue: 100,
                initialIfSet: 65,
                onChanged: (v) => setState(() => _retirementAge = v),
              ),
              const SizedBox(height: 12),
              NullableScrubField(
                key: const ValueKey('lifeexp-field'),
                label: 'Life expectancy',
                value: _lifeExpectancy,
                kind: ScrubKind.years,
                minValue: 0,
                maxValue: 120,
                initialIfSet: 90,
                onChanged: (v) => setState(() => _lifeExpectancy = v),
              ),
              const SizedBox(height: 12),
              NullableScrubField(
                key: const ValueKey('income-field'),
                label: 'Annual income',
                value: _annualIncome,
                kind: ScrubKind.money,
                minValue: 0,
                suffixText: 'USD',
                initialIfSet: 100000,
                onChanged: (v) => setState(() => _annualIncome = v),
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const ValueKey('save-member'),
                onPressed: _saving ? null : _save,
                child: Text(_isEdit ? 'Save changes' : 'Add member'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/member_form_screen_test.dart`
Expected: PASS. If `mocktail` is not yet a dev dependency, add it: `flutter pub add --dev mocktail` and rerun.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/member_form_screen.dart test/widgets/member_form_screen_test.dart pubspec.yaml pubspec.lock
git commit -m "feat: add MemberFormScreen (create + edit + delete)"
```

---

### Task 7: HouseholdDetailScreen with tabs and members list

**Files:**
- Modify: `lib/screens/household_detail_screen.dart`
- Test: `test/widgets/household_detail_screen_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/widgets/household_detail_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:monte_carlo_simulator/models/household.dart';
import 'package:monte_carlo_simulator/models/member.dart';
import 'package:monte_carlo_simulator/screens/household_detail_screen.dart';
import 'package:monte_carlo_simulator/screens/member_form_screen.dart';
import 'package:monte_carlo_simulator/services/member_service.dart';
import 'package:monte_carlo_simulator/state/providers.dart';

class _FakeService extends Mock implements MemberService {}

Household _hh() => Household(
      id: 'h1',
      name: 'Smith Family',
      advisorIds: const ['advisor-uid'],
      createdAt: DateTime.utc(2026, 6, 1),
      createdBy: 'advisor-uid',
    );

Member _m(String id, String name, MemberRelation r) => Member(
      id: id,
      householdId: 'h1',
      name: name,
      relation: r,
      createdAt: DateTime.utc(2026, 6, 1),
      createdBy: 'advisor-uid',
    );

void main() {
  late _FakeService svc;

  setUp(() {
    svc = _FakeService();
  });

  Widget _host(Stream<List<Member>> stream) {
    when(() => svc.watchMembers(any())).thenAnswer((_) => stream);
    return ProviderScope(
      overrides: [
        memberServiceProvider.overrideWithValue(svc),
        currentAdvisorUidProvider.overrideWithValue('advisor-uid'),
      ],
      child: MaterialApp(
        home: HouseholdDetailScreen(household: _hh()),
      ),
    );
  }

  testWidgets('renders two tabs', (tester) async {
    await tester.pumpWidget(_host(Stream.value(const [])));
    await tester.pumpAndSettle();
    expect(find.text('Members'), findsOneWidget);
    expect(find.text('Portfolios'), findsOneWidget);
  });

  testWidgets('empty state shown when no members', (tester) async {
    await tester.pumpWidget(_host(Stream.value(const [])));
    await tester.pumpAndSettle();
    expect(find.textContaining('No members yet'), findsOneWidget);
  });

  testWidgets('populated list shows tiles', (tester) async {
    await tester.pumpWidget(_host(Stream.value([
      _m('m1', 'John', MemberRelation.primary),
      _m('m2', 'Mary', MemberRelation.spouse),
    ])));
    await tester.pumpAndSettle();
    expect(find.text('John'), findsOneWidget);
    expect(find.text('Mary'), findsOneWidget);
  });

  testWidgets('FAB pushes MemberFormScreen', (tester) async {
    await tester.pumpWidget(_host(Stream.value(const [])));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byType(MemberFormScreen), findsOneWidget);
  });

  testWidgets('delete prompts confirm and only calls service on confirm',
      (tester) async {
    when(() => svc.deleteMember(
          householdId: any(named: 'householdId'),
          memberId: any(named: 'memberId'),
        )).thenAnswer((_) async {});

    await tester.pumpWidget(_host(Stream.value([
      _m('m1', 'John', MemberRelation.primary),
    ])));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    expect(find.text('Delete this member?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    verifyNever(() => svc.deleteMember(
        householdId: any(named: 'householdId'),
        memberId: any(named: 'memberId')));

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    verify(() => svc.deleteMember(householdId: 'h1', memberId: 'm1'))
        .called(1);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/household_detail_screen_test.dart`
Expected: FAIL — current screen is the stub with no tabs or list.

- [ ] **Step 3: Replace the screen**

Overwrite `lib/screens/household_detail_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/household.dart';
import '../models/member.dart';
import '../state/providers.dart';
import '../widgets/relation_labels.dart';
import 'member_form_screen.dart';

class HouseholdDetailScreen extends ConsumerWidget {
  const HouseholdDetailScreen({super.key, required this.household});

  final Household household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(household.name),
          bottom: const TabBar(
            tabs: [Tab(text: 'Members'), Tab(text: 'Portfolios')],
          ),
        ),
        body: TabBarView(
          children: [
            _MembersTab(household: household),
            const _PortfoliosTab(),
          ],
        ),
      ),
    );
  }
}

class _MembersTab extends ConsumerWidget {
  const _MembersTab({required this.household});
  final Household household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(membersProvider(household.id));
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              e.toString(),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
        data: (members) {
          if (members.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No members yet. Tap + to add the primary.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: members.length,
            itemBuilder: (_, i) =>
                _MemberTile(household: household, member: members[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add member'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MemberFormScreen(householdId: household.id),
          ),
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.household, required this.member});
  final Household household;
  final Member member;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this member?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(memberServiceProvider).deleteMember(
            householdId: household.id,
            memberId: member.id,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final age = member.effectiveAge;
    return Consumer(builder: (context, ref, _) {
      return ListTile(
        leading: Icon(relationIcon(member.relation)),
        title: Text(member.name),
        subtitle: Text(
          '${relationLabel(member.relation)} · age ${age ?? '—'}',
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MemberFormScreen(
              householdId: household.id,
              existing: member,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MemberFormScreen(
                    householdId: household.id,
                    existing: member,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
        ),
      );
    });
  }
}

class _PortfoliosTab extends StatelessWidget {
  const _PortfoliosTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Portfolios coming soon',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/household_detail_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Run all Dart tests**

Run: `flutter test`
Expected: All new tests pass. Pre-existing failing `test/widget_test.dart` (broken before this branch) still fails — leave it.

- [ ] **Step 6: Run analyze**

Run: `flutter analyze`
Expected: No new errors. Pre-existing `withOpacity` deprecation infos remain.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/household_detail_screen.dart test/widgets/household_detail_screen_test.dart
git commit -m "feat: HouseholdDetailScreen with Members tab and CRUD"
```

---

### Task 8: Manual smoke verification

**Files:** none modified.

- [ ] **Step 1: Run the app**

Run: `flutter run -d chrome`
Sign in.

- [ ] **Step 2: Exercise the flows**

For at least one household:

- Open it → land on Members tab → see empty state copy.
- Tap **Add member** → form opens with default relation `primary` →
  enter name "John" → save → tile appears.
- Add a spouse "Mary" → add two children "Olivia" and "Aaron".
- Verify ordering: primary, spouse, child (Aaron before Olivia
  alphabetically).
- Tap a member tile → form pre-fills → change DOB via date picker →
  save → subtitle age updates.
- Tap delete icon on a member → confirm → tile disappears.
- Open a different household → its members list is independent.
- Switch to **Portfolios** tab → see "Portfolios coming soon".
- Sign out and back in → households + members persist.

- [ ] **Step 3: Report any defects**

If anything regressed or doesn't match the spec, file follow-up tasks
rather than amending this plan in-flight.

- [ ] **Step 4: Commit the smoke confirmation (no code changes)**

No commit needed. Mark the task complete in TodoWrite and proceed to
finishing the branch.

---

## Completion checklist

- [ ] All 8 tasks complete with passing tests
- [ ] `flutter test` green except the pre-existing broken
      `test/widget_test.dart` scaffold stub
- [ ] `flutter analyze` shows no new errors
- [ ] Manual smoke passes
- [ ] No rules changes needed (sub-project 1 already authorized
      `households/{hid}/members/*`)
- [ ] No new Firestore index needed (client-side sort)
