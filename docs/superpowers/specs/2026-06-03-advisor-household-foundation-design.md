# Advisor → Household data foundation

## Purpose

Lay the data model, Firestore rules, services, and minimum
advisor-facing UI for the multi-household direction the project is
taking. After this sub-project, a signed-in advisor can create,
list, view (stub), and delete their own client households — with
Firestore rules that prevent another advisor from reading them. This
is sub-project 1 of a planned sequence; members, portfolios, and the
simulator-to-portfolio rewiring are deferred to later sub-projects.

## Non-goals

- Members CRUD (deferred to sub-project 2).
- Portfolios CRUD or category-specific schemas (sub-project 3+).
- Wiring `SimulationConfig` / `ResultsScreen` to a portfolio
  (sub-project 4).
- Migrating or surfacing existing `users/{uid}/simulations` records.
  They keep working through the existing simulator path and are not
  visible from the new home screen.
- Client-facing portal, team invitations, audit logs, soft-delete,
  advisor profile pages.

## Information architecture

Today's home screen is a list of saved simulations under
`users/{uid}/simulations/`. After this sub-project, the home screen
becomes a list of households the signed-in advisor owns. The existing
"Run new simulation" entry point moves to an AppBar action icon so the
old flow remains reachable while the new structure builds out around
it.

```
┌───────────────────────────────────────────────────────────┐
│  Monte Carlo Simulator      [⚗️ Run sim]  [⎋ Sign out]   │
├───────────────────────────────────────────────────────────┤
│  Households                                               │
│  ┌─────────────────────────────────────────────────────┐  │
│  │ The Smith Family               created Apr 12  [🗑]│  │
│  │ Acme Trust                     created Apr 03  [🗑]│  │
│  │ Jones Household                created Mar 28  [🗑]│  │
│  └─────────────────────────────────────────────────────┘  │
│                                                       (+) │
└───────────────────────────────────────────────────────────┘
```

Tapping a row opens `HouseholdDetailScreen`, which in this sub-project
is a stub: title (household name), AppBar back button, body text
"Members and portfolios coming soon — household ID: {hid}." That stub
proves the routing and read path work end-to-end without scope creep.

## Data model — Firestore

Top-level collection:

```
households/{hid}
  name          : string                    // human-friendly label
  advisorIds    : array<string>             // uid(s) of owning advisors
  createdAt     : timestamp                 // serverTimestamp()
  createdBy     : string                    // creator advisor uid

  /members/{mid}        // (deferred — no documents written here yet)
  /portfolios/{pid}     // (deferred — same)
```

`advisorIds` is an **array of advisor uids**. Single-element today;
the schema allows multi-advisor sharing in a future sub-project
without a data migration.

Top-level (not nested under `advisors/{uid}/...`) because the
ownership check uses `array-contains` on `advisorIds` — a single
collection-group query lets an advisor list all their households,
including ones they were later added to as a co-advisor.

### Member / portfolio schemas (reserved, not written this sub-project)

Documented here so the access rules can preemptively cover them.

```
members/{mid}
  // schema TBD in sub-project 2 — left empty for now

portfolios/{pid}
  category : "investment" | "insurance" | "tax" | ...
  // params: map<string, any> — schema TBD in sub-project 3
```

## Firestore rules

Replace today's `match /users/{uid}/simulations/{simId}` block with
the same block **plus** a new top-level `match /households` block. The
existing simulation rules are unchanged.

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Existing: per-user simulations (unchanged)
    match /users/{uid}/simulations/{simId} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }

    // New: advisor-owned households
    match /households/{hid} {
      allow create: if request.auth != null
                    && request.auth.uid in request.resource.data.advisorIds
                    && request.resource.data.advisorIds is list
                    && request.resource.data.advisorIds.size() >= 1;

      allow read, update, delete:
        if request.auth != null
        && request.auth.uid in resource.data.advisorIds;

      // Deny all access to subcollections until their UIs land. The
      // parent-membership check protects against drive-by reads.
      match /members/{mid} {
        allow read, write: if request.auth != null
                           && request.auth.uid in get(
                                /databases/$(database)/documents/households/$(hid)
                              ).data.advisorIds;
      }

      match /portfolios/{pid} {
        allow read, write: if request.auth != null
                           && request.auth.uid in get(
                                /databases/$(database)/documents/households/$(hid)
                              ).data.advisorIds;
      }
    }
  }
}
```

The `create` clause requires the caller to be in the new doc's
`advisorIds`. This blocks a malicious client from creating a household
that belongs to someone else. The `update` clause does not currently
restrict who can change `advisorIds`; that's fine for an advisor-only
app and will get tightened when a team-invitation flow shows up.

## Dart layer

### `lib/models/household.dart`

```dart
class Household {
  Household({
    required this.id,
    required this.name,
    required this.advisorIds,
    required this.createdAt,
    required this.createdBy,
  });

  final String id;
  final String name;
  final List<String> advisorIds;
  final DateTime createdAt;
  final String createdBy;

  factory Household.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc);
  Map<String, Object?> toFirestore();   // includes FieldValue.serverTimestamp()
}
```

The Firestore form is **not** the same as a transport JSON — it
uses `FieldValue.serverTimestamp()` for `createdAt`, so `toFirestore`
returns a write payload, not a serialization. No `fromJson` /
`toJson` pair is added; saved-state round-trips are not needed in
this sub-project.

### `lib/services/household_service.dart`

```dart
class HouseholdService {
  HouseholdService({FirebaseFirestore? db});

  Stream<List<Household>> watchHouseholds(String advisorUid);
  Future<String> createHousehold({required String advisorUid, required String name});
  Future<void> deleteHousehold(String hid);
}
```

- `watchHouseholds` issues `_db.collection('households')
  .where('advisorIds', arrayContains: advisorUid)
  .orderBy('createdAt', descending: true).snapshots()`.
- `createHousehold` writes a doc with `advisorIds: [advisorUid]`,
  `createdBy: advisorUid`, `createdAt: serverTimestamp()`.
- `deleteHousehold` deletes the document. Subcollection cleanup is
  not needed in this sub-project (no docs there yet); a later
  sub-project that introduces members/portfolios will handle cascade.

### `lib/state/providers.dart`

Two new providers alongside the existing ones:

```dart
final householdServiceProvider = Provider((ref) => HouseholdService());

final householdsProvider = StreamProvider.autoDispose<List<Household>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(householdServiceProvider).watchHouseholds(user.uid);
});
```

The existing `savedSimulationsProvider` is kept untouched.

## UI

### `lib/screens/home_screen.dart` (modified)

Replace the saved-simulations list with a households list, and move
the "Run new simulation" entry point from the body button into an
AppBar action.

- AppBar:
  - `title: const Text('Households')`
  - `actions: [ IconButton(Icons.science_outlined, → SimulationFormScreen), IconButton(Icons.logout, → signOut) ]`
- Body: a `Consumer` watching `householdsProvider`. Renders a
  `ListView` of `_HouseholdTile`s, or an empty state card with a
  message and a single FilledButton wired to the FAB.
- FAB: `+` icon → `CreateHouseholdScreen`.

The existing `_SavedSimulationsList` and `_SavedSimulationTile`
classes are deleted (the savedSimulationsProvider stays, just
unreferenced from the home screen).

### `lib/screens/household_detail_screen.dart` (new — stub)

```dart
class HouseholdDetailScreen extends StatelessWidget {
  const HouseholdDetailScreen({super.key, required this.household});
  final Household household;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(household.name)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Members and portfolios coming soon — household ID: ${household.id}',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
```

### `lib/screens/create_household_screen.dart` (new)

A single-field form: text input for `name` (required, trimmed,
non-empty). Submit button calls
`HouseholdService.createHousehold({advisorUid: user.uid, name: name})`,
then `Navigator.pop()`. Standard error display (red text under the
field) mirrors the existing form-screen error pattern.

## Testing

### Unit (Dart, `test/`)

- `household_test.dart`:
  - `Household.fromDoc` correctly parses a fixture map (including a
    `Timestamp` for `createdAt`).
  - `Household.toFirestore` emits a map whose `advisorIds` contains the
    creator, `createdBy` is the creator uid, `createdAt` is a
    `FieldValue.serverTimestamp()` sentinel (`is FieldValue`).

- `household_service_test.dart`:
  - Uses `fake_cloud_firestore` (already a dev dependency).
  - `createHousehold` writes to `households/{auto}` with the expected
    fields.
  - `watchHouseholds` returns only households containing the queried
    advisor in `advisorIds` (write three docs; query one uid; expect
    two).
  - `deleteHousehold` removes the document.

### Widget (Dart, `test/widgets/`)

- `home_screen_test.dart`:
  - Empty state renders the "no households yet" copy when the stream
    emits `[]`.
  - Tapping the FAB pushes `CreateHouseholdScreen`.
  - Trailing delete icon prompts a confirmation dialog and only
    triggers the service call on confirm.

- `create_household_screen_test.dart`:
  - Empty name submission shows the validation error and does not
    call the service.
  - Successful save pops the screen.

### Rules (deferred — explicitly out of scope this sub-project)

Firestore rules tests using the local emulator are valuable but add a
new test runner (Node/Jest or the Python rules-emulator harness). The
spec defers them to a follow-up; the rule logic above is short enough
to inspect visually. If you'd rather pull them in now, name it as a
small extra task and we add a `firestore.rules.test.js` plus the
`@firebase/rules-unit-testing` dev dependency.

## Risks and open questions

- **`FieldValue.serverTimestamp()` round-trips as `null`** in a freshly
  created document until the server write returns. `Household.fromDoc`
  must treat a null `createdAt` as `DateTime.now()` (matches the
  existing pattern in `SavedSimulation.fromDoc`).
- **No Firestore index on `households.where(advisorIds, arrayContains:
  uid).orderBy(createdAt, desc)`.** Firestore prompts the first time
  the query runs; add the suggested index to
  `firestore.indexes.json` as part of the deploy step. The spec
  flags this; the implementation plan will include the index
  configuration.
- **AppBar congestion.** Three icons (Run sim, sign-out, possibly more
  later) might crowd the bar. Acceptable for now; revisit when more
  primary actions arrive.
- **Empty state copy.** The current copy is conservative. A more
  inviting copy ("Add your first household to get started") is
  trivial to change; left as-is to keep this spec focused.
