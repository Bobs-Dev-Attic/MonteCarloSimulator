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
}
