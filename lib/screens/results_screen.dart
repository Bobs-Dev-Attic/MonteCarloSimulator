import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/simulation_config.dart';
import '../models/simulation_result.dart';
import '../state/providers.dart';
import '../widgets/fan_chart.dart';
import '../widgets/results_tabs.dart';
import '../widgets/scrub_field.dart';
import '../widgets/summary_stats_card.dart';
import '../widgets/terminal_histogram.dart';

/// Displays a simulation's aggregated results and supports quick scenario reruns.
class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({
    super.key,
    required this.result,
    required this.config,
    this.title,
  });

  final SimulationResult result;
  final SimulationConfig config;
  final String? title;

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  late SimulationResult _result;
  late SimulationConfig _config;
  late Map<String, double> _draftInputs;
  late int _draftNSims;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _result = widget.result;
    _config = widget.config;
    _resetDraftFromConfig();
  }

  void _resetDraftFromConfig() {
    _draftInputs = {
      for (final entry in _config.inputs.entries)
        entry.key: (entry.value as num).toDouble(),
    };
    _draftNSims = _config.nSims;
  }

  bool get _isRetirement => _config.model == 'retirement';

  double _input(String key) => _draftInputs[key] ?? 0;

  void _setInput(String key, double value) {
    setState(() {
      _draftInputs[key] = value;
    });
  }

  SimulationConfig _buildConfigFromDraft() {
    if (_config.model == 'gbm') {
      return SimulationConfig.gbm(
        beginningValue: _input('beginning_value'),
        mu: _input('mu'),
        sigma: _input('sigma'),
        years: _input('years'),
        nSims: _draftNSims,
        compareGarch: _config.compareGarch,
      );
    }
    return SimulationConfig.retirement(
      startingBalance: _input('starting_balance'),
      annualContribution: _input('annual_contribution'),
      yearsToRetire: _input('years_to_retire').round(),
      retirementYears: _input('retirement_years').round(),
      annualWithdrawal: _input('annual_withdrawal'),
      meanReturn: _input('mean_return'),
      stdReturn: _input('std_return'),
      inflation: _input('inflation'),
      nSims: _draftNSims,
    );
  }

  Future<void> _rerunSimulation() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final nextConfig = _buildConfigFromDraft();
    try {
      final nextResult = await ref.read(simulationServiceProvider).run(nextConfig);
      if (!mounted) return;
      setState(() {
        _config = nextConfig;
        _result = nextResult;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  (double, double)? _sharedYRangeWithComparison() {
    final comp = _result.comparison;
    if (comp == null) return null;
    double maxOf(List<double> xs) =>
        xs.fold<double>(0, (m, v) => v > m ? v : m);
    final hi = [
      maxOf(_result.bands.p95),
      maxOf(_result.bands.p75),
      maxOf(_result.bands.p50),
      maxOf(comp.bands.p95),
      maxOf(comp.bands.p75),
      maxOf(comp.bands.p50),
    ].reduce((a, b) => a > b ? a : b);
    return (0.0, hi * 1.08);
  }

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

  // ignore: use_setters_to_change_properties
  void _setNSims(int value) => setState(() => _draftNSims = value);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title ??
              (_isRetirement ? 'Retirement Results' : 'Portfolio Results'),
        ),
      ),
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
    );
  }
}

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
        onChanged: (v) => state._setNSims(v.round()),
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

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
