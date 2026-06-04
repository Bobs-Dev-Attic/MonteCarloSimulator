import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte_carlo_simulator/widgets/results_tabs.dart';

void main() {
  testWidgets('renders three tabs and switches body', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ResultsTabs(
          fanTab: const Center(child: Text('FAN_BODY')),
          histogramTab: const Center(child: Text('HISTO_BODY')),
          summaryTab: const Center(child: Text('SUMMARY_BODY')),
        ),
      ),
    ));

    expect(find.text('Fan chart'), findsOneWidget);
    expect(find.text('Histogram'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('FAN_BODY'), findsOneWidget);

    await tester.tap(find.text('Histogram'));
    await tester.pumpAndSettle();
    expect(find.text('HISTO_BODY'), findsOneWidget);

    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    expect(find.text('SUMMARY_BODY'), findsOneWidget);
  });
}
