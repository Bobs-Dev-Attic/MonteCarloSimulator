import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('Shift held during drag scales by 10x', (tester) async {
    final emitted = <double>[];
    await tester.pumpWidget(_harness(
      initial: 0,
      kind: ScrubKind.integer,
      onChanged: emitted.add,
    ));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final handle = find.byKey(const ValueKey('scrub-handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(3, 0));
    await gesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(emitted.last, 30.0); // 3 px * (1 * 10)
  });

  testWidgets('Alt held during drag scales by 0.1x', (tester) async {
    final emitted = <double>[];
    await tester.pumpWidget(_harness(
      initial: 0,
      kind: ScrubKind.percent,
      onChanged: emitted.add,
    ));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final handle = find.byKey(const ValueKey('scrub-handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(10, 0));
    await gesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();

    expect(emitted.last, closeTo(0.1, 1e-9)); // 10 px * 0.1 * 0.1
  });
}
