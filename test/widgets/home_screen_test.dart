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
