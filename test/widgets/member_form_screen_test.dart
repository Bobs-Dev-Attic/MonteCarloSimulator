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

  Future<void> setTallViewport(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Widget host({Member? existing}) {
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
    await setTallViewport(tester);
    await tester.pumpWidget(host());
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
    await setTallViewport(tester);
    when(() => svc.createMember(
          householdId: any(named: 'householdId'),
          advisorUid: any(named: 'advisorUid'),
          draft: any(named: 'draft'),
        )).thenAnswer((_) async => 'new-id');

    await tester.pumpWidget(ProviderScope(
      overrides: [
        memberServiceProvider.overrideWithValue(svc),
        currentAdvisorUidProvider.overrideWithValue('advisor-uid'),
      ],
      child: MaterialApp(
        home: Builder(builder: (ctx) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) => const MemberFormScreen(householdId: 'h1'),
                ),
              ),
              child: const Text('open'),
            ),
          );
        }),
      ),
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
          draft: any(
            named: 'draft',
            that: _DraftMatcher('Jane', MemberRelation.primary),
          ),
        )).called(1);
    expect(find.byType(MemberFormScreen), findsNothing);
  });

  testWidgets('edit pre-fills and calls updateMember', (tester) async {
    await setTallViewport(tester);
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

    await tester.pumpWidget(host(existing: existing));
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
          draft: any(
            named: 'draft',
            that: _DraftMatcher('New', MemberRelation.spouse),
          ),
        )).called(1);
  });

  testWidgets('edit AppBar delete prompts confirm and calls deleteMember',
      (tester) async {
    await setTallViewport(tester);
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

    await tester.pumpWidget(host(existing: existing));
    await tester.tap(find.byKey(const ValueKey('delete-member')));
    await tester.pumpAndSettle();

    expect(find.text('Delete this member?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    verify(() => svc.deleteMember(householdId: 'h1', memberId: 'm1'))
        .called(1);
  });
}
