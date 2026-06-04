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

  Widget host(Stream<List<Member>> stream) {
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
    await tester.pumpWidget(host(Stream.value(const [])));
    await tester.pumpAndSettle();
    expect(find.text('Members'), findsOneWidget);
    expect(find.text('Portfolios'), findsOneWidget);
  });

  testWidgets('empty state shown when no members', (tester) async {
    await tester.pumpWidget(host(Stream.value(const [])));
    await tester.pumpAndSettle();
    expect(find.textContaining('No members yet'), findsOneWidget);
  });

  testWidgets('populated list shows tiles', (tester) async {
    await tester.pumpWidget(host(Stream.value([
      _m('m1', 'John', MemberRelation.primary),
      _m('m2', 'Mary', MemberRelation.spouse),
    ])));
    await tester.pumpAndSettle();
    expect(find.text('John'), findsOneWidget);
    expect(find.text('Mary'), findsOneWidget);
  });

  testWidgets('FAB pushes MemberFormScreen', (tester) async {
    await tester.pumpWidget(host(Stream.value(const [])));
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

    await tester.pumpWidget(host(Stream.value([
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

  testWidgets('delete error surfaces a SnackBar', (tester) async {
    when(() => svc.deleteMember(
          householdId: any(named: 'householdId'),
          memberId: any(named: 'memberId'),
        )).thenThrow(Exception('boom'));

    await tester.pumpWidget(host(Stream.value([
      _m('m1', 'John', MemberRelation.primary),
    ])));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.textContaining('boom'), findsOneWidget);
  });
}
