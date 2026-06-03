import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte_carlo_simulator/widgets/scrub_field.dart';

Widget _harness({
  required double initial,
  required ScrubKind kind,
  required void Function(double) onChanged,
  double? min,
  double? max,
  String? suffix,
}) {
  double current = initial;
  return MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => ScrubField(
          label: 'Value',
          value: current,
          kind: kind,
          minValue: min,
          maxValue: max,
          suffixText: suffix,
          onChanged: (v) {
            current = v;
            onChanged(v);
            setState(() {});
          },
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('typing into the field emits parsed value', (tester) async {
    final emitted = <double>[];
    await tester.pumpWidget(_harness(
      initial: 10,
      kind: ScrubKind.integer,
      onChanged: emitted.add,
    ));

    await tester.enterText(find.byType(TextField), '42');
    await tester.pump();
    expect(emitted.last, 42.0);
  });

  testWidgets('invalid input is not emitted', (tester) async {
    final emitted = <double>[];
    await tester.pumpWidget(_harness(
      initial: 10,
      kind: ScrubKind.integer,
      onChanged: emitted.add,
    ));

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    expect(emitted, isEmpty);
  });

  testWidgets('dragging the handle right increases an integer value', (tester) async {
    final emitted = <double>[];
    await tester.pumpWidget(_harness(
      initial: 10,
      kind: ScrubKind.integer,
      onChanged: emitted.add,
    ));

    final handle = find.byKey(const ValueKey('scrub-handle'));
    expect(handle, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(15, 0));
    await gesture.up();
    await tester.pump();

    expect(emitted.last, 25.0);
  });

  testWidgets('dragging left below minValue clamps', (tester) async {
    final emitted = <double>[];
    await tester.pumpWidget(_harness(
      initial: 5,
      kind: ScrubKind.integer,
      min: 0,
      onChanged: emitted.add,
    ));

    final handle = find.byKey(const ValueKey('scrub-handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(-20, 0));
    await gesture.up();
    await tester.pump();

    expect(emitted.last, 0.0);
  });

  testWidgets('money kind scales step by current value', (tester) async {
    final emitted = <double>[];
    await tester.pumpWidget(_harness(
      initial: 10000,
      kind: ScrubKind.money,
      onChanged: emitted.add,
    ));

    final handle = find.byKey(const ValueKey('scrub-handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(10, 0));
    await gesture.up();
    await tester.pump();

    // 1% of 10_000 per pixel * 10 px = +1_000.
    expect(emitted.last, closeTo(11000.0, 0.1));
  });

  testWidgets('percent kind moves 0.1 per pixel', (tester) async {
    final emitted = <double>[];
    await tester.pumpWidget(_harness(
      initial: 7.0,
      kind: ScrubKind.percent,
      onChanged: emitted.add,
    ));

    final handle = find.byKey(const ValueKey('scrub-handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    await tester.pump();

    expect(emitted.last, closeTo(9.0, 1e-9));
  });
}
