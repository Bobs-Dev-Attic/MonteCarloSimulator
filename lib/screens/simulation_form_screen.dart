import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/simulation_config.dart';
import '../state/providers.dart';
import '../widgets/scrub_field.dart';
import 'results_screen.dart';

/// Form for configuring and launching a GBM or retirement simulation.
///
/// When [initialTickers] are supplied (e.g. from a customer's investments
/// database), the form opens on the GBM tab and derives the expected return and
/// volatility from those tickers' price history via `estimatePortfolio`.
class SimulationFormScreen extends ConsumerStatefulWidget {
  const SimulationFormScreen({
    super.key,
    this.initialTickers,
    this.initialWeights,
  });

  final List<String>? initialTickers;
  final List<double>? initialWeights;

  @override
  ConsumerState<SimulationFormScreen> createState() =>
      _SimulationFormScreenState();
}

class _SimulationFormScreenState extends ConsumerState<SimulationFormScreen> {
  String _model = 'gbm';
  bool _busy = false;
  bool _compareGarch = false;
  String? _error;

  // Set when μ/σ were derived from a tickers basket (provenance banner).
  bool _estimating = false;
  String? _estimateLabel;

  @override
  void initState() {
    super.initState();
    if (widget.initialTickers != null && widget.initialTickers!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _estimateFromTickers();
      });
    }
  }

  Future<void> _estimateFromTickers() async {
    final tickers = widget.initialTickers;
    if (tickers == null || tickers.isEmpty) return;
    setState(() {
      _estimating = true;
      _error = null;
    });
    try {
      final est = await ref.read(portfolioServiceProvider).estimate(
            tickers: tickers,
            weights: widget.initialWeights,
          );
      if (!mounted) return;
      setState(() {
        _mu = est.mu * 100; // fraction -> percent for the form fields
        _sigma = est.sigma * 100;
        final window = est.startDate != null && est.endDate != null
            ? ' · ${est.startDate}→${est.endDate}'
            : '';
        _estimateLabel = 'From history: ${est.tickers.join(', ')}$window';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _estimateLabel = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text("Couldn't fetch market data; enter expected return / volatility manually"),
        ),
      );
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

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
            if (_estimating || _estimateLabel != null) ...[
              const SizedBox(height: 12),
              _EstimateBanner(
                estimating: _estimating,
                label: _estimateLabel,
              ),
            ],
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

/// Small banner shown when the GBM inputs were derived from a tickers basket,
/// so the advisor can see the expected return / volatility are data-driven (and
/// still edit them).
class _EstimateBanner extends StatelessWidget {
  const _EstimateBanner({required this.estimating, required this.label});

  final bool estimating;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (estimating)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(Icons.insights, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              estimating
                  ? 'Estimating expected return & volatility from price history…'
                  : (label ?? ''),
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
