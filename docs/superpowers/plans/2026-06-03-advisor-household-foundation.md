# Advisor Household Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship sub-project 1 of the advisor-mode pivot: a top-level Firestore `households` collection with array-ownership, Firestore rules, Dart `Household` + `HouseholdService`, and a minimum home-screen UI that lets the signed-in advisor create / list / view (stub) / delete their own households.

**Architecture:** New `households/{hid}` top-level collection with an `advisorIds: array<string>` field driving access. Rules grant CRUD when the caller's uid is in `advisorIds`. Subcollections (`members/`, `portfolios/`) are reserved with parent-check rules but no UI yet. On the client: `Household` model, `HouseholdService` for CRUD/streaming, two Riverpod providers, and three screen changes (`HomeScreen` rewired, two new screens). Existing `users/{uid}/simulations` continues working untouched.

**Tech Stack:** Firestore + Firestore security rules; Flutter + Riverpod (already wired); `fake_cloud_firestore` (already a dev dep). No new dependencies.

---

## Task 1: Firestore rules + composite index

**Files:**
- Modify: `firestore.rules`
- Modify: `firestore.indexes.json`

- [ ] **Step 1: Update `firestore.rules`**

Replace the contents of `firestore.rules` with:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Existing: per-user simulations (unchanged behavior).
    match /users/{uid}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }

    // Advisor-owned households. The advisorIds array determines access.
    match /households/{hid} {
      allow create: if request.auth != null
                    && request.resource.data.advisorIds is list
                    && request.resource.data.advisorIds.size() >= 1
                    && request.auth.uid in request.resource.data.advisorIds;

      allow read, update, delete:
        if request.auth != null
        && request.auth.uid in resource.data.advisorIds;

      // Subcollections inherit access from the parent household.
      // No UI writes here yet in this sub-project, but the rule is
      // deny-by-default-safe.
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

- [ ] **Step 2: Update `firestore.indexes.json`**

Replace the contents of `firestore.indexes.json` with:

```json
{
  "indexes": [
    {
      "collectionGroup": "households",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "advisorIds", "arrayConfig": "CONTAINS" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
```

- [ ] **Step 3: Commit**

```bash
git add firestore.rules firestore.indexes.json
git commit -m "feat(firestore): rules + index for advisor-owned households"
```

The rules and index get deployed in Task 8, after the Dart code is in place.

---

## Task 2: `Household` model

**Files:**
- Create: `lib/models/household.dart`
- Test: `test/household_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/household_test.dart`:

```dart
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
```

- [ ] **Step 2: Run; expect import-error failure**

Run: `flutter test test/household_test.dart`
Expected: `Target of URI doesn't exist: 'package:monte_carlo_simulator/models/household.dart'`.

- [ ] **Step 3: Implement `Household`**

Create `lib/models/household.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// A client household owned by one or more advisors.
///
/// Stored at top-level `households/{id}` so an advisor can list every
/// household they belong to via a single `advisorIds arrayContains` query.
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

  factory Household.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Household(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      advisorIds: ((data['advisorIds'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      // serverTimestamp() is null until the server write returns; fall
      // back to "now" so the UI can still render the optimistic doc.
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: (data['createdBy'] as String?) ?? '',
    );
  }

  /// Write payload for a brand-new household. Uses
  /// [FieldValue.serverTimestamp] for `createdAt` so the timestamp is
  /// authoritative across clients.
  static Map<String, Object?> toCreatePayload({
    required String name,
    required String advisorUid,
  }) {
    return {
      'name': name,
      'advisorIds': [advisorUid],
      'createdBy': advisorUid,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
```

- [ ] **Step 4: Run; expect 3 passed**

Run: `flutter test test/household_test.dart`
Expected: `+3: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/models/household.dart test/household_test.dart
git commit -m "feat(models): Household + toCreatePayload"
```

---

## Task 3: `HouseholdService`

**Files:**
- Create: `lib/services/household_service.dart`
- Test: `test/household_service_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/household_service_test.dart`:

```dart
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
```

- [ ] **Step 2: Run; expect import-error failure**

Run: `flutter test test/household_service_test.dart`
Expected: `Target of URI doesn't exist: 'package:monte_carlo_simulator/services/household_service.dart'`.

- [ ] **Step 3: Implement `HouseholdService`**

Create `lib/services/household_service.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/household.dart';

/// CRUD + streaming for the top-level `households` collection.
class HouseholdService {
  HouseholdService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('households');

  /// Newest-first stream of households the advisor belongs to.
  Stream<List<Household>> watchHouseholds(String advisorUid) {
    return _col
        .where('advisorIds', arrayContains: advisorUid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Household.fromDoc).toList());
  }

  /// Creates a household with the caller as the sole advisor. Returns
  /// the generated document id.
  Future<String> createHousehold({
    required String advisorUid,
    required String name,
  }) async {
    final doc = await _col.add(
      Household.toCreatePayload(name: name.trim(), advisorUid: advisorUid),
    );
    return doc.id;
  }

  Future<void> deleteHousehold(String hid) => _col.doc(hid).delete();
}
```

- [ ] **Step 4: Run; expect 3 passed**

Run: `flutter test test/household_service_test.dart`
Expected: `+3: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/services/household_service.dart test/household_service_test.dart
git commit -m "feat(services): HouseholdService CRUD + stream"
```

---

## Task 4: Riverpod providers

**Files:**
- Modify: `lib/state/providers.dart`

- [ ] **Step 1: Append the two new providers**

In `lib/state/providers.dart`, add to the imports:

```dart
import '../models/household.dart';
import '../services/household_service.dart';
```

Then add at the bottom of the file:

```dart
final householdServiceProvider =
    Provider<HouseholdService>((ref) => HouseholdService());

/// Live list of households the signed-in advisor belongs to.
final householdsProvider =
    StreamProvider.autoDispose<List<Household>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(householdServiceProvider).watchHouseholds(user.uid);
});
```

- [ ] **Step 2: Verify analyze**

Run: `flutter analyze lib/state/providers.dart`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/state/providers.dart
git commit -m "feat(providers): householdServiceProvider + householdsProvider"
```

---

## Task 5: `CreateHouseholdScreen`

**Files:**
- Create: `lib/screens/create_household_screen.dart`
- Test: `test/widgets/create_household_screen_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/widgets/create_household_screen_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart' show MockUser;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte_carlo_simulator/screens/create_household_screen.dart';
import 'package:monte_carlo_simulator/services/household_service.dart';
import 'package:monte_carlo_simulator/state/providers.dart';

void main() {
  Widget _harness({
    required FakeFirebaseFirestore db,
    required String uid,
  }) {
    return ProviderScope(
      overrides: [
        householdServiceProvider.overrideWithValue(HouseholdService(db: db)),
        currentAdvisorUidProvider.overrideWithValue(uid),
      ],
      child: const MaterialApp(home: CreateHouseholdScreen()),
    );
  }

  testWidgets('empty name shows validation and does not write', (tester) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(_harness(db: db, uid: 'a1'));

    await tester.tap(find.byKey(const ValueKey('save-household')));
    await tester.pump();

    expect(find.text('Enter a household name'), findsOneWidget);
    final snap = await db.collection('households').get();
    expect(snap.docs, isEmpty);
  });

  testWidgets('valid name creates a doc and pops', (tester) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(_harness(db: db, uid: 'a1'));

    await tester.enterText(find.byKey(const ValueKey('name-field')), 'Acme');
    await tester.tap(find.byKey(const ValueKey('save-household')));
    await tester.pumpAndSettle();

    final snap = await db.collection('households').get();
    expect(snap.docs.length, 1);
    expect(snap.docs.first.data()['name'], 'Acme');
  });
}
```

(The test references `currentAdvisorUidProvider` — declared in Task 6.)

- [ ] **Step 2: Add the override-only provider to `lib/state/providers.dart`**

Append to `lib/state/providers.dart`:

```dart
/// Read-only access to the current advisor's uid for screens that
/// don't want to depend on the full auth provider chain. Override in
/// tests to inject a fixed uid.
final currentAdvisorUidProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).value?.uid;
});
```

- [ ] **Step 3: Run the test; expect import-error failure on the screen**

Run: `flutter test test/widgets/create_household_screen_test.dart`
Expected: `Target of URI doesn't exist: 'package:monte_carlo_simulator/screens/create_household_screen.dart'`.

- [ ] **Step 4: Implement `CreateHouseholdScreen`**

Create `lib/screens/create_household_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

class CreateHouseholdScreen extends ConsumerStatefulWidget {
  const CreateHouseholdScreen({super.key});

  @override
  ConsumerState<CreateHouseholdScreen> createState() =>
      _CreateHouseholdScreenState();
}

class _CreateHouseholdScreenState extends ConsumerState<CreateHouseholdScreen> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a household name');
      return;
    }
    final uid = ref.read(currentAdvisorUidProvider);
    if (uid == null) {
      setState(() => _error = 'You must be signed in');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(householdServiceProvider)
          .createHousehold(advisorUid: uid, name: name);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New household')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('name-field'),
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Household name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('save-household'),
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_busy ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run; expect 2 passed**

Run: `flutter test test/widgets/create_household_screen_test.dart`
Expected: `+2: All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/screens/create_household_screen.dart test/widgets/create_household_screen_test.dart lib/state/providers.dart
git commit -m "feat(screens): CreateHouseholdScreen"
```

---

## Task 6: `HouseholdDetailScreen` (stub)

**Files:**
- Create: `lib/screens/household_detail_screen.dart`

- [ ] **Step 1: Implement**

Create `lib/screens/household_detail_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/household.dart';

/// Stub placeholder shown when tapping a household row. Members and
/// portfolios CRUD land in a later sub-project; this screen exists so
/// the routing path is exercised end-to-end today.
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

- [ ] **Step 2: Verify analyze**

Run: `flutter analyze lib/screens/household_detail_screen.dart`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/household_detail_screen.dart
git commit -m "feat(screens): HouseholdDetailScreen stub"
```

---

## Task 7: Rewire `HomeScreen` to households

**Files:**
- Modify: `lib/screens/home_screen.dart`
- Create: `test/widgets/home_screen_test.dart`

- [ ] **Step 1: Replace `lib/screens/home_screen.dart` in full**

Replace the entire file contents with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/household.dart';
import '../state/providers.dart';
import 'create_household_screen.dart';
import 'household_detail_screen.dart';
import 'simulation_form_screen.dart';

/// Landing screen: lists the signed-in advisor's households and opens
/// the simulator form via an AppBar action.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final households = ref.watch(householdsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Households'),
        actions: [
          IconButton(
            tooltip: 'Run a simulation',
            icon: const Icon(Icons.science_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SimulationFormScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateHouseholdScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New household'),
      ),
      body: households.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          if (items.isEmpty) return const _EmptyState();
          return ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => _HouseholdTile(household: items[i]),
          );
        },
      ),
    );
  }
}

class _HouseholdTile extends ConsumerWidget {
  const _HouseholdTile({required this.household});
  final Household household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final created = DateFormat.yMMMd().format(household.createdAt);
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.home_outlined)),
      title: Text(household.name),
      subtitle: Text('created $created'),
      trailing: IconButton(
        tooltip: 'Delete household',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _confirmDelete(context, ref),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => HouseholdDetailScreen(household: household),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${household.name}"?'),
        content: const Text(
          'This removes the household record. Members and portfolios will be removed in a later release.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(householdServiceProvider).deleteHousehold(household.id);
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home_outlined, size: 64, color: scheme.primary),
            const SizedBox(height: 12),
            const Text(
              'No households yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap the + button to add your first household.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Write the failing widget tests**

Create `test/widgets/home_screen_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte_carlo_simulator/models/household.dart';
import 'package:monte_carlo_simulator/screens/home_screen.dart';
import 'package:monte_carlo_simulator/services/household_service.dart';
import 'package:monte_carlo_simulator/state/providers.dart';

void main() {
  Widget _harness({
    required FakeFirebaseFirestore db,
    required String uid,
  }) {
    final service = HouseholdService(db: db);
    return ProviderScope(
      overrides: [
        householdServiceProvider.overrideWithValue(service),
        currentAdvisorUidProvider.overrideWithValue(uid),
        householdsProvider.overrideWith(
          (ref) => service.watchHouseholds(uid),
        ),
      ],
      child: const MaterialApp(home: HomeScreen()),
    );
  }

  testWidgets('shows empty state when there are no households',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(_harness(db: db, uid: 'a1'));
    await tester.pumpAndSettle();

    expect(find.text('No households yet'), findsOneWidget);
  });

  testWidgets('renders a row per household with delete trailing icon',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await HouseholdService(db: db)
        .createHousehold(advisorUid: 'a1', name: 'Smith Family');
    await tester.pumpWidget(_harness(db: db, uid: 'a1'));
    await tester.pumpAndSettle();

    expect(find.text('Smith Family'), findsOneWidget);
    expect(find.byTooltip('Delete household'), findsOneWidget);
  });

  testWidgets('delete confirmation removes the doc on confirm',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final hid = await HouseholdService(db: db)
        .createHousehold(advisorUid: 'a1', name: 'Gone');
    await tester.pumpWidget(_harness(db: db, uid: 'a1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete household'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    final snap = await db.collection('households').doc(hid).get();
    expect(snap.exists, isFalse);
  });
}
```

- [ ] **Step 3: Run all home-screen tests; expect 3 passed**

Run: `flutter test test/widgets/home_screen_test.dart`
Expected: `+3: All tests passed!`

- [ ] **Step 4: Run the full suite to confirm nothing else broke**

Run: `flutter test`
Expected: all tests pass (models + scrub field + results tabs + household tests).

- [ ] **Step 5: Commit**

```bash
git add lib/screens/home_screen.dart test/widgets/home_screen_test.dart
git commit -m "feat(home): replace saved-sims list with households list"
```

---

## Task 8: Deploy rules + index + manual smoke test

**Files:** None modified beyond what Tasks 1–7 already committed.

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: all tests pass.

Run: `cd functions && venv\Scripts\python.exe -m pytest -v` (PowerShell)
Expected: 22 passed (no server-side changes; just confirming nothing accidental).

- [ ] **Step 2: Deploy Firestore rules + indexes**

Run: `firebase deploy --only firestore:rules,firestore:indexes`
Expected: `+ firestore: released rules firestore.rules to cloud.firestore` and either `+ firestore: deployed indexes successfully` or a progress message that the new household index is building. The index takes a minute or two to come online; the app will surface a `failed-precondition` error on the home screen until it does.

- [ ] **Step 3: Manual smoke — launch the app**

Run: `flutter run -d chrome --web-port=5000`
Sign in.

- [ ] **Step 4: Verify empty state**

The home screen now reads "Households" in the AppBar with two icon actions (`Icons.science_outlined`, `Icons.logout`) and a FAB labeled "New household". The body shows the empty state "No households yet".

- [ ] **Step 5: Create a household**

Tap the FAB → enter "The Smiths" → Save. The screen pops, and the new household appears in the list with "created {today}".

- [ ] **Step 6: Verify the simulator entry point still works**

Tap the science flask icon in the AppBar → the existing `SimulationFormScreen` opens. Cancel out.

- [ ] **Step 7: Verify Firestore write**

Open https://console.firebase.google.com/project/montecarlosimulator-bda/firestore/data/~2Fhouseholds → confirm a `households/{auto-id}` doc exists with `advisorIds: [your-uid]`, `createdBy: your-uid`, `createdAt: {timestamp}`, `name: "The Smiths"`.

- [ ] **Step 8: Verify isolation**

In a separate Chrome profile (or incognito after signing in with a different account if you have one), confirm the new account's home screen shows the empty state — your "The Smiths" household is invisible. This proves the `advisorIds arrayContains` rule.

- [ ] **Step 9: Verify delete**

Back in the original account: tap the trash icon → confirm "Delete" in the dialog → the row disappears, and the Firestore console no longer shows the document.

---

## Self-review notes (already applied)

- **Spec coverage:**
  - Data model → Tasks 1, 2.
  - Firestore rules → Task 1.
  - Composite index → Task 1.
  - `Household` model + `toCreatePayload` → Task 2.
  - `HouseholdService` → Task 3.
  - Riverpod providers (including `currentAdvisorUidProvider` used by screens) → Tasks 4 and 5 (step 2).
  - `CreateHouseholdScreen` → Task 5.
  - `HouseholdDetailScreen` stub → Task 6.
  - Home screen rewire (AppBar action, FAB, list, empty state) → Task 7.
  - Manual smoke verification (including isolation between advisors) → Task 8.

- **Placeholder scan:** No "TBD" / "implement later" / "add validation" steps. Every code step shows the actual code.

- **Type / name consistency:**
  - `Household({id, name, advisorIds, createdAt, createdBy})` — same fields across Tasks 2 and 7.
  - `Household.toCreatePayload({name, advisorUid})` — called from `HouseholdService.createHousehold` in Task 3 with `name: name.trim()`.
  - `HouseholdService({db})` constructor — used in Tasks 3, 5, 7 test harnesses.
  - `householdServiceProvider`, `householdsProvider`, `currentAdvisorUidProvider` — declared in Tasks 4 and 5 Step 2, used in Tasks 5 and 7.
  - Widget keys `name-field` and `save-household` used in Task 5 implementation and tests; `Delete household` tooltip used in Task 7 implementation and tests.
