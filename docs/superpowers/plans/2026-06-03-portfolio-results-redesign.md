# Results Screen Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `results_screen.dart` and `simulation_form_screen.dart` so a normal desktop window shows results without scrolling: a top-aligned inputs panel + action row, a one-row hero strip, and a 3-tab `TabBar` that fills the rest of the viewport — with a new reusable `ScrubField` widget replacing every slider and plain number field.

**Architecture:** Two new widgets: `ScrubField` (text input with a drag handle on the right that adjusts the numeric value as the user drags horizontally) and `ResultsTabs` (a `DefaultTabController`-backed `TabBar` + `TabBarView` with three slots). Existing comparison-mode helpers (`_sharedYRangeWithComparison`) and chart widgets (`FanChart`, `TerminalHistogram`, `SummaryStatsCard`) are preserved unchanged; only their hosting layout changes.

**Tech Stack:** Flutter + Material 3, fl_chart (unchanged), Riverpod (unchanged), intl (unchanged). No new dependencies.

---

## Task 1: `ScrubField` widget — typing path

**Files:**
- Create: `lib/widgets/scrub_field.dart`
- Test: `test/widgets/scrub_field_test.dart`

- [ ] **Step 1: Write the failing test for the typing path**

Create `test/widgets/scrub_field_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the test; expect failure**

Run: `flutter test test/widgets/scrub_field_test.dart`
Expected: `Target of URI doesn't exist: 'package:monte_carlo_simulator/widgets/scrub_field.dart'`.

- [ ] **Step 3: Implement the typing path**

Create `lib/widgets/scrub_field.dart`:

```dart
import 'package:flutter/material.dart';

/// Family of value units a [ScrubField] can carry. Drives per-pixel
/// drag sensitivity and (later) display formatting.
enum ScrubKind { integer, years, percent, money }

/// A numeric text input with a drag handle on the right.
///
/// Typing edits the value as a normal [TextFormField]. Horizontally
/// dragging the trailing grip icon scrubs the numeric value at a
/// sensitivity that depends on [kind].
class ScrubField extends StatefulWidget {
  const ScrubField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.kind,
    this.suffixText,
    this.minValue,
    this.maxValue,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ScrubKind kind;
  final String? suffixText;
  final double? minValue;
  final double? maxValue;

  @override
  State<ScrubField> createState() => _ScrubFieldState();
}

class _ScrubFieldState extends State<ScrubField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
  }

  @override
  void didUpdateWidget(covariant ScrubField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) {
      final formatted = _format(widget.value);
      if (_controller.text != formatted) {
        _controller.text = formatted;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _format(double v) {
    switch (widget.kind) {
      case ScrubKind.integer:
      case ScrubKind.years:
        return v.round().toString();
      case ScrubKind.percent:
      case ScrubKind.money:
        return v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
    }
  }

  double _clamp(double v) {
    if (widget.minValue != null && v < widget.minValue!) return widget.minValue!;
    if (widget.maxValue != null && v > widget.maxValue!) return widget.maxValue!;
    return v;
  }

  void _onTextChanged(String text) {
    final parsed = double.tryParse(text);
    if (parsed == null) return;
    final clamped = _clamp(parsed);
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: _onTextChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.suffixText,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test; expect 2 passed**

Run: `flutter test test/widgets/scrub_field_test.dart`
Expected: `+2: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/scrub_field.dart test/widgets/scrub_field_test.dart
git commit -m "feat(widgets): ScrubField typing path"
```

---

## Task 2: `ScrubField` — drag handle (no modifiers)

**Files:**
- Modify: `lib/widgets/scrub_field.dart`
- Modify: `test/widgets/scrub_field_test.dart`

- [ ] **Step 1: Add failing drag tests**

Append to `test/widgets/scrub_field_test.dart` inside `void main()`:

```dart
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
      initial: 10_000,
      kind: ScrubKind.money,
      onChanged: emitted.add,
    ));

    final handle = find.byKey(const ValueKey('scrub-handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(10, 0));
    await gesture.up();
    await tester.pump();

    // 1% of 10_000 per pixel * 10 px = +1_000.
    expect(emitted.last, closeTo(11_000.0, 0.1));
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
```

- [ ] **Step 2: Run; expect 4 failures (no handle key, no drag wiring)**

Run: `flutter test test/widgets/scrub_field_test.dart`
Expected: 2 prior tests pass, 4 new fail with `findsOneWidget` mismatch on the handle key.

- [ ] **Step 3: Add the drag handle widget**

In `lib/widgets/scrub_field.dart`, replace the existing `build` method with:

```dart
  double _stepPerPixel() {
    switch (widget.kind) {
      case ScrubKind.integer:
      case ScrubKind.years:
        return 1.0;
      case ScrubKind.percent:
        return 0.1;
      case ScrubKind.money:
        final v = widget.value.abs();
        return v < 100 ? 1.0 : v * 0.01;
    }
  }

  double _accumDx = 0.0;
  double _startValue = 0.0;

  void _onDragStart(DragStartDetails _) {
    _accumDx = 0.0;
    _startValue = widget.value;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _accumDx += details.delta.dx;
    final next = _clamp(_startValue + _accumDx * _stepPerPixel());
    if (next == widget.value) return;
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _controller,
      onChanged: _onTextChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.suffixText,
        suffixIcon: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            key: const ValueKey('scrub-handle'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.drag_indicator,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
```

- [ ] **Step 4: Run tests; expect 6 passed**

Run: `flutter test test/widgets/scrub_field_test.dart`
Expected: `+6: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/scrub_field.dart test/widgets/scrub_field_test.dart
git commit -m "feat(widgets): ScrubField drag handle with per-kind sensitivity"
```

---

## Task 3: `ScrubField` — Shift/Alt modifiers

**Files:**
- Modify: `lib/widgets/scrub_field.dart`
- Modify: `test/widgets/scrub_field_test.dart`

- [ ] **Step 1: Add failing modifier tests**

Append to `test/widgets/scrub_field_test.dart` inside `void main()`:

```dart
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

  testWidgets('Alt held during drag scales by 0.1x (no-op for integer)', (tester) async {
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
```

Also add at the top of the file with the other imports:

```dart
import 'package:flutter/services.dart';
```

- [ ] **Step 2: Run; expect 2 failures**

Run: `flutter test test/widgets/scrub_field_test.dart`
Expected: 6 previous tests pass, 2 new fail with mismatched values.

- [ ] **Step 3: Apply modifier multipliers**

In `lib/widgets/scrub_field.dart`, add `import 'package:flutter/services.dart';` to the top. Replace `_onDragUpdate` with:

```dart
  void _onDragUpdate(DragUpdateDetails details) {
    _accumDx += details.delta.dx;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;
    double multiplier = 1.0;
    if (shift) multiplier *= 10.0;
    if (alt) {
      // Integer/years stay at minimum 1/px; finer than that has no effect.
      if (widget.kind == ScrubKind.percent || widget.kind == ScrubKind.money) {
        multiplier *= 0.1;
      }
    }
    final next = _clamp(_startValue + _accumDx * _stepPerPixel() * multiplier);
    if (next == widget.value) return;
    widget.onChanged(next);
  }
```

- [ ] **Step 4: Run tests; expect 8 passed**

Run: `flutter test test/widgets/scrub_field_test.dart`
Expected: `+8: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/scrub_field.dart test/widgets/scrub_field_test.dart
git commit -m "feat(widgets): ScrubField Shift/Alt modifier multipliers"
```

---

## Task 4: `ResultsTabs` widget

**Files:**
- Create: `lib/widgets/results_tabs.dart`
- Test: `test/widgets/results_tabs_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/widgets/results_tabs_test.dart`:

```dart
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
```

- [ ] **Step 2: Run; expect file-not-found**

Run: `flutter test test/widgets/results_tabs_test.dart`
Expected: import error on `results_tabs.dart`.

- [ ] **Step 3: Implement `ResultsTabs`**

Create `lib/widgets/results_tabs.dart`:

```dart
import 'package:flutter/material.dart';

/// Three-tab layout (Fan chart / Histogram / Summary) for the results
/// screen. Tab bodies are provided by the caller so the parent can
/// vary content based on comparison mode without this widget knowing.
class ResultsTabs extends StatelessWidget {
  const ResultsTabs({
    super.key,
    required this.fanTab,
    required this.histogramTab,
    required this.summaryTab,
  });

  final Widget fanTab;
  final Widget histogramTab;
  final Widget summaryTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Fan chart'),
              Tab(text: 'Histogram'),
              Tab(text: 'Summary'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [fanTab, histogramTab, summaryTab],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test; expect pass**

Run: `flutter test test/widgets/results_tabs_test.dart`
Expected: `+1: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/results_tabs.dart test/widgets/results_tabs_test.dart
git commit -m "feat(widgets): ResultsTabs"
```

---

## Task 5: Convert simulation form to ScrubField + Wrap layout

**Files:**
- Modify: `lib/screens/simulation_form_screen.dart`

- [ ] **Step 1: Replace the file contents**

Replace `lib/screens/simulation_form_screen.dart` in full with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/simulation_config.dart';
import '../state/providers.dart';
import '../widgets/scrub_field.dart';
import 'results_screen.dart';

/// Form for configuring and launching a GBM or retirement simulation.
class SimulationFormScreen extends ConsumerStatefulWidget {
  const SimulationFormScreen({super.key});

  @override
  ConsumerState<SimulationFormScreen> createState() =>
      _SimulationFormScreenState();
}

class _SimulationFormScreenState extends ConsumerState<SimulationFormScreen> {
  String _model = 'gbm';
  bool _busy = false;
  bool _compareGarch = false;
  String? _error;

  // GBM fields.
  double _beginningValue = 10000;
  double _mu = 7;
  double _sigma = 15;
  double _years = 10;

  // Retirement fields.
  double _startingBalance = 100000;
  double _annualContribution = 15000;
  double _yearsToRetire = 25;
  double _retirementYears = 30;
  double _annualWithdrawal = 60000;
  double _meanReturn = 6;
  double _stdReturn = 12;
  double _inflation = 2.5;

  double _nSims = 10000;

  SimulationConfig _buildConfig() {
    final nSims = _nSims.round();
    if (_model == 'gbm') {
      return SimulationConfig.gbm(
        beginningValue: _beginningValue,
        mu: _mu / 100,
        sigma: _sigma / 100,
        years: _years,
        nSims: nSims,
        compareGarch: _compareGarch,
      );
    }
    return SimulationConfig.retirement(
      startingBalance: _startingBalance,
      annualContribution: _annualContribution,
      yearsToRetire: _yearsToRetire.round(),
      retirementYears: _retirementYears.round(),
      annualWithdrawal: _annualWithdrawal,
      meanReturn: _meanReturn / 100,
      stdReturn: _stdReturn / 100,
      inflation: _inflation / 100,
      nSims: nSims,
    );
  }

  Future<void> _runSimulation() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final config = _buildConfig();
      final result = await ref.read(simulationServiceProvider).run(config);

      final user = ref.read(authStateProvider).value;
      if (user != null) {
        await ref.read(firestoreServiceProvider).saveSimulation(
              uid: user.uid,
              config: config,
              result: result,
            );
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultsScreen(result: result, config: config),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int _columnsFor(double width) {
    if (width >= 720) return 4;
    if (width >= 420) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Simulation')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'gbm', label: Text('Portfolio (GBM)')),
                ButtonSegment(value: 'retirement', label: Text('Retirement')),
              ],
              selected: {_model},
              onSelectionChanged: (s) => setState(() => _model = s.first),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, c) {
              final cols = _columnsFor(c.maxWidth);
              const gutter = 12.0;
              final fieldWidth = (c.maxWidth - gutter * (cols - 1)) / cols;
              final fields = _model == 'gbm' ? _gbmFields() : _retirementFields();
              return Wrap(
                spacing: gutter,
                runSpacing: gutter,
                children: [
                  for (final f in fields) SizedBox(width: fieldWidth, child: f),
                ],
              );
            }),
            const SizedBox(height: 16),
            if (_model == 'gbm')
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _compareGarch,
                onChanged: (v) => setState(() => _compareGarch = v),
                title: const Text('Compare with GARCH(1,1)'),
                subtitle: const Text(
                    'Adds a second simulation with time-varying volatility, same average σ.'),
              ),
            const SizedBox(height: 8),
            ScrubField(
              label: 'Number of simulations',
              value: _nSims,
              kind: ScrubKind.integer,
              minValue: 1000,
              maxValue: 50000,
              onChanged: (v) => setState(() => _nSims = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _runSimulation,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_busy ? 'Running…' : 'Run simulation'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _gbmFields() => [
        ScrubField(
          label: 'Beginning value',
          value: _beginningValue,
          kind: ScrubKind.money,
          suffixText: '\$',
          minValue: 1,
          onChanged: (v) => setState(() => _beginningValue = v),
        ),
        ScrubField(
          label: 'Expected return',
          value: _mu,
          kind: ScrubKind.percent,
          suffixText: '%',
          onChanged: (v) => setState(() => _mu = v),
        ),
        ScrubField(
          label: 'Volatility',
          value: _sigma,
          kind: ScrubKind.percent,
          suffixText: '%',
          minValue: 0,
          onChanged: (v) => setState(() => _sigma = v),
        ),
        ScrubField(
          label: 'Time horizon',
          value: _years,
          kind: ScrubKind.years,
          suffixText: 'years',
          minValue: 1,
          maxValue: 50,
          onChanged: (v) => setState(() => _years = v),
        ),
      ];

  List<Widget> _retirementFields() => [
        ScrubField(
          label: 'Starting balance',
          value: _startingBalance,
          kind: ScrubKind.money,
          suffixText: '\$',
          minValue: 0,
          onChanged: (v) => setState(() => _startingBalance = v),
        ),
        ScrubField(
          label: 'Annual contribution',
          value: _annualContribution,
          kind: ScrubKind.money,
          suffixText: '\$',
          minValue: 0,
          onChanged: (v) => setState(() => _annualContribution = v),
        ),
        ScrubField(
          label: 'Years until retirement',
          value: _yearsToRetire,
          kind: ScrubKind.years,
          suffixText: 'years',
          minValue: 0,
          maxValue: 50,
          onChanged: (v) => setState(() => _yearsToRetire = v),
        ),
        ScrubField(
          label: 'Years in retirement',
          value: _retirementYears,
          kind: ScrubKind.years,
          suffixText: 'years',
          minValue: 1,
          maxValue: 50,
          onChanged: (v) => setState(() => _retirementYears = v),
        ),
        ScrubField(
          label: 'Annual withdrawal',
          value: _annualWithdrawal,
          kind: ScrubKind.money,
          suffixText: '\$',
          minValue: 0,
          onChanged: (v) => setState(() => _annualWithdrawal = v),
        ),
        ScrubField(
          label: 'Mean return',
          value: _meanReturn,
          kind: ScrubKind.percent,
          suffixText: '%',
          onChanged: (v) => setState(() => _meanReturn = v),
        ),
        ScrubField(
          label: 'Return volatility',
          value: _stdReturn,
          kind: ScrubKind.percent,
          suffixText: '%',
          minValue: 0,
          onChanged: (v) => setState(() => _stdReturn = v),
        ),
        ScrubField(
          label: 'Inflation',
          value: _inflation,
          kind: ScrubKind.percent,
          suffixText: '%',
          minValue: 0,
          onChanged: (v) => setState(() => _inflation = v),
        ),
      ];
}
```

- [ ] **Step 2: Verify it compiles and existing tests still pass**

Run: `flutter analyze lib/screens/simulation_form_screen.dart`
Expected: no errors. (Pre-existing `withOpacity` infos elsewhere are fine.)

Run: `flutter test test/models_test.dart test/widgets/scrub_field_test.dart test/widgets/results_tabs_test.dart`
Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/simulation_form_screen.dart
git commit -m "feat(form): redesign with ScrubField inputs and responsive Wrap"
```

---

## Task 6: Restructure ResultsScreen into top-controls + tabs

**Files:**
- Modify: `lib/screens/results_screen.dart`

- [ ] **Step 1: Read the existing file**

Read `lib/screens/results_screen.dart` to see the current `_ResultsScreenState`, the `_HeroSummary` / `_InfoPill` / `_ChartCard` / `_SectionTitle` / `_ParameterSlider` private widgets, and the existing `_resultSection` + `_sharedYRangeWithComparison` helpers.

- [ ] **Step 2: Replace the build pipeline**

In `_ResultsScreenState`, replace the existing `_resultSection` method (it currently emits the chart card + histogram card + summary card together) with three split methods so each tab can host only its own widget:

```dart
  Widget _fanSection({
    required String? sectionLabel,
    required SimulationResult result,
    required (double, double)? sharedYRange,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sectionLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              sectionLabel,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
            ),
          ),
        Expanded(
          child: FanChart(
            bands: result.bands,
            config: _config,
            yRange: sharedYRange,
          ),
        ),
      ],
    );
  }

  Widget _histogramSection({
    required String? sectionLabel,
    required SimulationResult result,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sectionLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              sectionLabel,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
            ),
          ),
        Expanded(
          child: TerminalHistogram(
            histogram: result.histogram,
            config: _config,
          ),
        ),
      ],
    );
  }

  Widget _summarySection({
    required String? sectionLabel,
    required SimulationResult result,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sectionLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              sectionLabel,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
            ),
          ),
        SummaryStatsCard(
          summary: result.summary,
          isRetirement: _isRetirement,
        ),
      ],
    );
  }

  Widget _buildFanTab() {
    final comp = _result.comparison;
    if (comp == null) {
      return _fanSection(
        sectionLabel: null,
        result: _result,
        sharedYRange: null,
      );
    }
    final range = _sharedYRangeWithComparison();
    return Column(
      children: [
        Expanded(
          child: _fanSection(
            sectionLabel: 'Constant σ (GBM)',
            result: _result,
            sharedYRange: range,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _fanSection(
            sectionLabel: 'GARCH(1,1)',
            result: comp,
            sharedYRange: range,
          ),
        ),
      ],
    );
  }

  Widget _buildHistogramTab() {
    final comp = _result.comparison;
    if (comp == null) {
      return _histogramSection(sectionLabel: null, result: _result);
    }
    return Column(
      children: [
        Expanded(
          child: _histogramSection(
            sectionLabel: 'Constant σ (GBM)',
            result: _result,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _histogramSection(
            sectionLabel: 'GARCH(1,1)',
            result: comp,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryTab() {
    final comp = _result.comparison;
    if (comp == null) {
      return _summarySection(sectionLabel: null, result: _result);
    }
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 600) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _summarySection(
              sectionLabel: 'Constant σ (GBM)', result: _result)),
            const SizedBox(width: 16),
            Expanded(child: _summarySection(
              sectionLabel: 'GARCH(1,1)', result: comp)),
          ],
        );
      }
      return Column(
        children: [
          _summarySection(sectionLabel: 'Constant σ (GBM)', result: _result),
          const SizedBox(height: 12),
          _summarySection(sectionLabel: 'GARCH(1,1)', result: comp),
        ],
      );
    });
  }
```

Delete the old `_resultSection` method body in the same edit.

- [ ] **Step 3: Replace the `body:` of the Scaffold**

Replace the existing `body: ListView(...)` (which contains the hero, chart card, histogram card, summary card, scenario controls section, and retirement footer) with the new layout. The current `build` returns a `Scaffold` with `body: ListView(padding: ..., children: [_HeroSummary(...), ..., scenario card, retirement footer])`. Replace the entire `body:` value with:

```dart
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InputsPanel(state: this),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () {
                            setState(() {
                              _resetDraftFromConfig();
                              _error = null;
                            });
                          },
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reset'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _rerunSimulation,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_graph),
                    label: Text(_busy ? 'Rerunning…' : 'Rerun'),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              _HeroStrip(summary: _result.summary, isRetirement: _isRetirement),
              const SizedBox(height: 12),
              Expanded(
                child: ResultsTabs(
                  fanTab: _buildFanTab(),
                  histogramTab: _buildHistogramTab(),
                  summaryTab: _buildSummaryTab(),
                ),
              ),
            ],
          ),
        ),
      ),
```

- [ ] **Step 4: Add the new private `_InputsPanel` and `_HeroStrip` widgets**

At the bottom of the file (alongside the existing private widget classes like `_HeroSummary`, `_InfoPill`, `_ChartCard`, etc.), add:

```dart
class _InputsPanel extends StatelessWidget {
  const _InputsPanel({required this.state});
  final _ResultsScreenState state;

  int _columnsFor(double width) {
    if (width >= 720) return 4;
    if (width >= 420) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = _columnsFor(c.maxWidth);
      const gutter = 10.0;
      final fieldWidth = (c.maxWidth - gutter * (cols - 1)) / cols;
      final fields = state._config.model == 'gbm'
          ? state._gbmScrubFields()
          : state._retirementScrubFields();
      final nSimsField = ScrubField(
        label: 'Number of simulations',
        value: state._draftNSims.toDouble(),
        kind: ScrubKind.integer,
        minValue: 1000,
        maxValue: 50000,
        onChanged: (v) => state.setState(() {
          state._draftNSims = v.round();
        }),
      );
      return Wrap(
        spacing: gutter,
        runSpacing: gutter,
        children: [
          for (final f in fields) SizedBox(width: fieldWidth, child: f),
          SizedBox(width: fieldWidth, child: nSimsField),
        ],
      );
    });
  }
}

class _HeroStrip extends StatelessWidget {
  const _HeroStrip({required this.summary, required this.isRetirement});
  final SummaryStats summary;
  final bool isRetirement;

  static final _money =
      NumberFormat.compactCurrency(symbol: '\$', decimalDigits: 0);

  @override
  Widget build(BuildContext context) {
    final successRate = (summary.successRate * 100).toStringAsFixed(1);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _InfoPill(label: 'Median', value: _money.format(summary.median)),
        _InfoPill(
          label: isRetirement ? 'Success rate' : '95% VaR',
          value: isRetirement ? '$successRate%' : _money.format(summary.var95),
        ),
        _InfoPill(
          label: '5–95',
          value:
              '${_money.format(summary.p5)} → ${_money.format(summary.p95)}',
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Add `_gbmScrubFields` and `_retirementScrubFields` helpers to `_ResultsScreenState`**

These are draft-binding analogues of the form's `_gbmFields` / `_retirementFields`, edits flow through `_setInput`:

```dart
  List<Widget> _gbmScrubFields() => [
        ScrubField(
          label: 'Beginning value',
          value: _input('beginning_value'),
          kind: ScrubKind.money,
          suffixText: '\$',
          minValue: 1,
          onChanged: (v) => _setInput('beginning_value', v),
        ),
        ScrubField(
          label: 'Expected return',
          value: _input('mu') * 100,
          kind: ScrubKind.percent,
          suffixText: '%',
          onChanged: (v) => _setInput('mu', v / 100),
        ),
        ScrubField(
          label: 'Volatility',
          value: _input('sigma') * 100,
          kind: ScrubKind.percent,
          suffixText: '%',
          minValue: 0,
          onChanged: (v) => _setInput('sigma', v / 100),
        ),
        ScrubField(
          label: 'Time horizon',
          value: _input('years'),
          kind: ScrubKind.years,
          suffixText: 'years',
          minValue: 1,
          maxValue: 50,
          onChanged: (v) => _setInput('years', v),
        ),
      ];

  List<Widget> _retirementScrubFields() => [
        ScrubField(
          label: 'Starting balance',
          value: _input('starting_balance'),
          kind: ScrubKind.money,
          suffixText: '\$',
          minValue: 0,
          onChanged: (v) => _setInput('starting_balance', v),
        ),
        ScrubField(
          label: 'Annual contribution',
          value: _input('annual_contribution'),
          kind: ScrubKind.money,
          suffixText: '\$',
          minValue: 0,
          onChanged: (v) => _setInput('annual_contribution', v),
        ),
        ScrubField(
          label: 'Years until retirement',
          value: _input('years_to_retire'),
          kind: ScrubKind.years,
          suffixText: 'years',
          minValue: 0,
          maxValue: 50,
          onChanged: (v) => _setInput('years_to_retire', v),
        ),
        ScrubField(
          label: 'Years in retirement',
          value: _input('retirement_years'),
          kind: ScrubKind.years,
          suffixText: 'years',
          minValue: 1,
          maxValue: 50,
          onChanged: (v) => _setInput('retirement_years', v),
        ),
        ScrubField(
          label: 'Annual withdrawal',
          value: _input('annual_withdrawal'),
          kind: ScrubKind.money,
          suffixText: '\$',
          minValue: 0,
          onChanged: (v) => _setInput('annual_withdrawal', v),
        ),
        ScrubField(
          label: 'Mean return',
          value: _input('mean_return') * 100,
          kind: ScrubKind.percent,
          suffixText: '%',
          onChanged: (v) => _setInput('mean_return', v / 100),
        ),
        ScrubField(
          label: 'Return volatility',
          value: _input('std_return') * 100,
          kind: ScrubKind.percent,
          suffixText: '%',
          minValue: 0,
          onChanged: (v) => _setInput('std_return', v / 100),
        ),
        ScrubField(
          label: 'Inflation',
          value: _input('inflation') * 100,
          kind: ScrubKind.percent,
          suffixText: '%',
          minValue: 0,
          onChanged: (v) => _setInput('inflation', v / 100),
        ),
      ];
```

- [ ] **Step 6: Add imports**

At the top of the file, add (or confirm):

```dart
import '../widgets/results_tabs.dart';
import '../widgets/scrub_field.dart';
```

- [ ] **Step 7: Delete unused legacy widgets**

Remove the `_ParameterSlider` private widget class (no longer referenced). Remove the `_HeroSummary` widget class — replaced by `_HeroStrip` and `_InfoPill` is the only piece still in use. Remove the `_ChartCard` widget class — the new tabs render charts without an enclosing card. Remove the `_SectionTitle` widget class if no remaining caller references it (grep first; remove only if all callers are gone).

- [ ] **Step 8: Verify analyze + tests**

Run: `flutter analyze lib/screens/results_screen.dart`
Expected: no errors. Pre-existing `withOpacity` info messages are fine.

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add lib/screens/results_screen.dart
git commit -m "feat(results): top controls + 3-tab layout, no scroll"
```

---

## Task 7: Manual smoke verification

**Files:** None modified.

- [ ] **Step 1: Launch the app**

Run: `flutter run -d chrome --web-port=5000`
Sign in.

- [ ] **Step 2: Verify form screen**

- The GBM tab shows 4 input fields packed into a row (or two rows depending on window width).
- Each input has a drag handle (`Icons.drag_indicator`) on the right.
- Hovering the handle changes the cursor to horizontal resize.
- Dragging the handle changes the field value live; typing also works.
- The Compare with GARCH switch is visible only on the GBM tab.
- Submit a run; results screen opens.

- [ ] **Step 3: Verify results screen — no comparison**

- The Scaffold body fits without scrolling at a normal browser-window height (≥ 700 px tall).
- Top has inputs row, then Reset/Rerun, then three hero pills, then a `TabBar` with `Fan chart`, `Histogram`, `Summary`.
- Each tab renders the corresponding chart filling the available space.
- Editing any input via drag handle then clicking Rerun produces a new result on the same screen.

- [ ] **Step 4: Verify results screen — comparison on**

- Run a GBM with the GARCH toggle on.
- Fan chart tab shows two stacked fan charts sharing the y-axis.
- Histogram tab shows two stacked histograms.
- Summary tab shows two side-by-side summary cards on a wide window; resize narrower and confirm they stack.

- [ ] **Step 5: Verify Firestore save and "with GARCH" chip**

- Confirm a doc landed under `users/{uid}/simulations/`.
- On the home screen the new saved tile shows the "with GARCH" chip.

- [ ] **Step 6: Commit (if any incidental fixes)**

If you didn't have to touch anything during the smoke test, skip the commit.

---

## Self-review notes (already applied)

- **Spec coverage:**
  - Inputs panel + ScrubField → Tasks 1–3, 5, 6 Step 4–5.
  - Tabbed chart pages → Tasks 4, 6.
  - Comparison-mode preserved → Task 6 Step 2 fan/histogram/summary tabs.
  - Drag sensitivities and modifiers per spec → Tasks 2 & 3.
- **Placeholder scan:** No TBDs, no "implement later", no vague "add validation" steps.
- **Type/name consistency:** `ScrubField`, `ScrubKind` (`integer`, `years`, `percent`, `money`), `ResultsTabs(fanTab, histogramTab, summaryTab)`, `_fanSection`/`_histogramSection`/`_summarySection`/`_buildFanTab`/`_buildHistogramTab`/`_buildSummaryTab`, `_InputsPanel`, `_HeroStrip`. Used consistently across all tasks.
