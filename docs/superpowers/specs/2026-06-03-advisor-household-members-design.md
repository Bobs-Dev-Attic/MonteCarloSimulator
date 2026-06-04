# Advisor → Household members CRUD

## Purpose

Sub-project 2 of the advisor pivot. Add a `members` subcollection under
each household and the advisor-facing UI to create, list, edit, and
delete members. After this sub-project an advisor can populate a
household with the people whose finances it represents — names,
relationships, ages, retirement targets, income — using data shapes
the simulator will later consume.

## Non-goals

- Portfolios CRUD or any category-specific schema (sub-project 3).
- Wiring `SimulationConfig` to a member or portfolio (sub-project 4).
- Member avatars, photos, or document attachments.
- Per-member soft delete, audit trail, or history.
- A team-invitation flow that would let members log in themselves.
- Cascade cleanup of members on household delete. See Risks.

## Information architecture

`HouseholdDetailScreen` is no longer a stub. It becomes a two-tab
shell that will host members today and portfolios in sub-project 3.

```
┌──────────────────────────────────────────────────────────┐
│  ←  The Smith Family                                     │  AppBar
├──────────────────────────────────────────────────────────┤
│ [ Members ]  [ Portfolios ]                              │  TabBar
├──────────────────────────────────────────────────────────┤
│  👤  John Smith                                          │
│      primary · age 47                          [✎] [🗑] │
│  👤  Mary Smith                                          │
│      spouse · age 45                           [✎] [🗑] │
│  👤  Olivia Smith                                        │
│      child · age 12                            [✎] [🗑] │
│                                                      (+) │
└──────────────────────────────────────────────────────────┘
```

The `Portfolios` tab body is intentionally a stub
(`"Portfolios coming soon"`) so sub-project 3 only adds a tab body
without re-laying-out the screen.

## Data model — Firestore

```
households/{hid}/members/{mid}
  name            : string                   // required, trimmed, non-empty
  relation        : string                   // required, enum value (see below)
  dateOfBirth     : timestamp | null         // optional; authoritative if present
  currentAge      : int | null               // optional fallback if DOB unknown
  retirementAge   : int | null               // optional
  lifeExpectancy  : int | null               // optional
  annualIncome    : number | null            // optional, USD
  createdAt       : timestamp                // serverTimestamp()
  createdBy       : string                   // advisor uid
```

`relation` is stored as a lowercase string drawn from a fixed Dart
enum:

```dart
enum MemberRelation { primary, spouse, child, parent, dependent, other }
```

`other` is the escape hatch for relationships that don't fit the list.
Free-text is not stored alongside the enum in this sub-project; if
`other` shows up often we can add a `relationNote: string` field
later without a migration.

### Why both `dateOfBirth` and `currentAge`

DOB is authoritative — it never goes stale and yields a precise
display age. But not every member has a known DOB (older relatives,
estates, hypothetical heirs in planning scenarios). `currentAge` is
the fallback so a member is still usable when DOB is unknown.

Display always prefers DOB-derived age when DOB is present. The
stored `currentAge` is treated as a snapshot and may go stale; the
form pre-fills the field with the stored number, not the derived age.

### Firestore rules

No rules changes. Sub-project 1 already authorized
`households/{hid}/members/{mid}` reads and writes via a `get()`
lookup on the parent's `advisorIds`. That rule covers this
sub-project as-is.

### Firestore indexes

No new index. Members are queried with a single
`households/{hid}/members` collection read (no `where` filter, no
`orderBy`); ordering is applied client-side using
`MemberRelation.index` with `name` as the tiebreaker.

## Dart layer

### `lib/models/member.dart` (new)

```dart
enum MemberRelation { primary, spouse, child, parent, dependent, other }

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

  /// DOB-derived age when DOB is set, otherwise the stored
  /// snapshot, otherwise null.
  int? get effectiveAge;

  factory Member.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String householdId,
  );

  /// Write payload for a brand-new member. Uses
  /// [FieldValue.serverTimestamp] for `createdAt` and pins
  /// `createdBy` to the creating advisor.
  static Map<String, Object?> toCreatePayload({
    required String advisorUid,
    required MemberDraft draft,
  });
}

/// Plain value class held by the form. Decouples form state from
/// the persisted [Member] (which carries id, createdAt, createdBy).
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

  /// Write payload for an update. Does NOT touch `createdAt` or
  /// `createdBy`.
  Map<String, Object?> toUpdatePayload();
}
```

`relation` round-trips via `name` (e.g. `'primary'`). Unknown strings
on read decode to `MemberRelation.other`.

### `lib/services/member_service.dart` (new)

```dart
class MemberService {
  MemberService({FirebaseFirestore? db});

  Stream<List<Member>> watchMembers(String householdId);
  Future<String> createMember({
    required String householdId,
    required String advisorUid,
    required MemberDraft draft,
  });
  Future<void> updateMember({
    required String householdId,
    required String memberId,
    required MemberDraft draft,
  });
  Future<void> deleteMember({
    required String householdId,
    required String memberId,
  });
}
```

`watchMembers` issues
`_db.collection('households').doc(hid).collection('members').snapshots()`
and sorts client-side by `(relation.index, name.toLowerCase())`. No
`orderBy` on the server.

### `lib/state/providers.dart` (modified)

```dart
final memberServiceProvider = Provider((ref) => MemberService());

final membersProvider =
    StreamProvider.autoDispose.family<List<Member>, String>(
  (ref, hid) => ref.watch(memberServiceProvider).watchMembers(hid),
);
```

The existing `householdServiceProvider`, `householdsProvider`, and
`currentAdvisorUidProvider` are unchanged.

## UI

### `lib/screens/household_detail_screen.dart` (replaces the stub)

A `DefaultTabController` with two tabs:

- AppBar: `title: Text(household.name)`, default back button.
- TabBar: `[Tab('Members'), Tab('Portfolios')]`.
- Body: `TabBarView([_MembersTab(household), _PortfoliosTab()])`.

`_MembersTab` (private widget in same file):
- `Consumer` watching `membersProvider(household.id)`.
- Loading: centered `CircularProgressIndicator`.
- Error: red text, centered, message `error.toString()`.
- Empty: centered `"No members yet. Tap + to add the primary."`
- Populated: `ListView.builder` of `_MemberTile`s. Tiles already come
  pre-sorted from the service. Bottom inset padding so the FAB
  doesn't cover the last row.
- `FloatingActionButton.extended` "Add member" → push
  `MemberFormScreen(householdId: household.id)`.

`_MemberTile`:
- Leading: relation-appropriate icon (`Icons.person` for primary,
  `Icons.favorite_outline` for spouse, `Icons.child_care` for child,
  `Icons.elderly` for parent, `Icons.group` for dependent/other).
- Title: `member.name`.
- Subtitle: `'{relation label} · age {effectiveAge ?? '—'}'`.
- Trailing: a `Row(mainAxisSize: min, [editBtn, deleteBtn])`.
- Tapping the row OR the edit icon pushes
  `MemberFormScreen(householdId, existing: member)`.
- Delete icon shows an `AlertDialog` confirm; on confirm calls
  `deleteMember`.

`_PortfoliosTab`:
- `Center(Padding(EdgeInsets.all(24), Text('Portfolios coming soon')))`.
- Stub. Sub-project 3 replaces the body.

### `lib/screens/member_form_screen.dart` (new)

```dart
class MemberFormScreen extends ConsumerStatefulWidget {
  const MemberFormScreen({
    super.key,
    required this.householdId,
    this.existing,
  });
  final String householdId;
  final Member? existing;
}
```

Layout: single-screen scrolling `Column` of inputs (web-sized; no
`Wrap` columns this sub-project — the field count is small enough).

Fields, in order, with keys for tests:
1. `TextFormField` — name. Required, trimmed, non-empty.
   Key `'name-field'`.
2. `DropdownButtonFormField<MemberRelation>` — relation. Required.
   Default on create: `MemberRelation.primary` when the household has
   no members yet (read from `membersProvider(hid).value`), otherwise
   `MemberRelation.child`. Key `'relation-field'`.
3. `_DatePickerField` — DOB. Optional. Tapping opens
   `showDatePicker(firstDate: 1900-01-01, lastDate: today)`. Clear
   button when set. Key `'dob-field'`.
4. `ScrubField(kind: integer, minValue: 0, maxValue: 120)` — current
   age. Optional. Key `'age-field'`.
5. `ScrubField(kind: years, minValue: 0, maxValue: 100)` — retirement
   age. Optional. Key `'retirement-field'`.
6. `ScrubField(kind: years, minValue: 0, maxValue: 120)` — life
   expectancy. Optional. Key `'lifeexp-field'`.
7. `ScrubField(kind: money, minValue: 0)` — annual income. Optional.
   Key `'income-field'`.

Save button (key `'save-member'`): validates, builds a `MemberDraft`,
calls `createMember` or `updateMember` depending on `existing`, then
`Navigator.pop()`. Errors render as red text under the save button.

On edit, the AppBar has a trailing delete icon (key `'delete-member'`)
that shows the confirm dialog and on confirm calls `deleteMember`
then `Navigator.pop()`.

AppBar title: `'New member'` when `existing == null`, else
`'Edit member'`.

`ScrubField` already exists from the results-redesign sub-project; we
re-use it. Optional numeric fields use `ScrubField` initialized to
zero with a separate "use this value" approach: form treats an empty
or unedited field as null, a touched field as the typed/scrubbed
value. Detail in implementation plan.

### Relation labels and ordering

Centralized in a small `relation_labels.dart` helper:

```dart
String relationLabel(MemberRelation r);   // e.g. 'spouse'
IconData relationIcon(MemberRelation r);
```

List ordering: `(a.relation.index, a.name.toLowerCase())`.

## Testing

### Unit (Dart, `test/`)

`member_test.dart`:
- `Member.fromDoc` parses all field types — string `name`, string
  `relation` decoded to enum, `Timestamp` `dateOfBirth` decoded to
  `DateTime`, nullable optional numerics preserved as null when
  missing.
- Unknown `relation` string decodes to `MemberRelation.other`.
- `Member.toCreatePayload` emits `advisorIds`-style sentinel: the
  returned map's `createdAt` is a `FieldValue` instance and
  `createdBy` is the supplied uid.
- `MemberDraft.toUpdatePayload` does not include `createdAt` or
  `createdBy`.
- `effectiveAge` returns DOB-derived age when DOB set (within ±1 of
  expected for the test date), falls back to `currentAge` when DOB
  null, and returns null when both are null.

`member_service_test.dart` (uses `fake_cloud_firestore`):
- `createMember` writes under
  `households/{hid}/members/{auto}` with name, relation,
  optional fields, and the supplied advisor uid.
- `updateMember` patches an existing doc without altering
  `createdAt` or `createdBy`.
- `deleteMember` removes the doc.
- `watchMembers` returns members sorted by `(relation.index, name)`:
  seed three members with relations `child`, `primary`, `spouse` and
  names that would sort differently alphabetically; assert the
  emitted order is `primary, spouse, child`.
- `watchMembers` scopes to the supplied household only: seed members
  under two households, query one, expect the other's members
  absent.

### Widget (Dart, `test/widgets/`)

`household_detail_screen_test.dart`:
- Two tabs render with the labels `Members` and `Portfolios`.
- Members tab empty state shows the no-members copy when the stream
  emits `[]`.
- Populated list shows tiles in the sorted order from the service.
- Tapping the FAB pushes `MemberFormScreen` with the right
  `householdId` and no `existing`.
- Tapping a member tile (or its edit icon) pushes `MemberFormScreen`
  with `existing` set to that member.
- The delete trailing icon prompts a confirm dialog; only on confirm
  does `deleteMember` get called.

`member_form_screen_test.dart`:
- Empty-name submit shows validation error; service is not called.
- Create path: fill name + relation, save, expect `createMember`
  invoked with the typed values and screen popped.
- Edit path: render with `existing`, fields pre-fill, change name,
  save, expect `updateMember` invoked and screen popped.
- Edit path AppBar delete: prompts confirm, on confirm calls
  `deleteMember` and pops.

### Manual smoke

- Open a household → Members tab shows empty state → add a primary
  → tile shows correctly sorted.
- Add a spouse and two children → ordering is primary, spouse,
  child (oldest by name first since we tiebreak ascending).
- Edit a member, change name and DOB → tile updates.
- Delete a member with confirm → tile disappears.
- Portfolios tab shows the stub.

## Risks and open questions

- **Member orphan on household delete.** `deleteHousehold` from
  sub-project 1 deletes only the parent doc; members written under
  it leak. Firestore has no atomic recursive delete from the client,
  and a partial client-side loop is failure-prone. Accept the leak
  this sub-project — the parent is gone so rules block access — and
  add a Cloud Function trigger in a follow-up.
- **DOB and `currentAge` can diverge over time.** Form pre-fills
  `currentAge` with the stored value as written, not the derived
  age. Display always prefers DOB-derived age. Acceptable; a future
  hardening pass can null out `currentAge` whenever DOB is present
  on save.
- **Relation ordering is enum-index-driven.** Renaming or reordering
  `MemberRelation` changes display order. If the enum stabilizes we
  can switch to an explicit `_relationRank(MemberRelation)` helper
  to decouple. Acceptable now; reordering the enum is a deliberate
  act and we'd catch the test fixtures.
- **Optional numeric ScrubField + null semantics.** `ScrubField` was
  designed for required numerics. The form must treat
  "field never touched" as null on save vs "field touched and set to
  0" as 0. The implementation plan will document how (likely a
  small `_NullableScrub` wrapper holding a `bool _touched` and a
  `double` value).
- **`Member` carries `householdId` even though it's redundant with
  the doc path.** Convenient for tile rendering and callbacks; the
  field is set from the path at `fromDoc` time, never written.
