import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
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
