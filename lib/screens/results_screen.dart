import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/simulation_config.dart';
import '../models/simulation_result.dart';
import '../state/providers.dart';
import '../widgets/fan_chart.dart';
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

  static final NumberFormat _money =
      NumberFormat.compactCurrency(symbol: '\$', decimalDigits: 0);

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summary = _result.summary;
    final successRate = (summary.successRate * 100).toStringAsFixed(1);
    final lossRate = (summary.probLoss * 100).toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title ??
              (_isRetirement ? 'Retirement Results' : 'Portfolio Results'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroSummary(
            title: _isRetirement
                ? 'Retirement runway under uncertainty'
                : 'Portfolio range under uncertainty',
            subtitle: _isRetirement
                ? '$successRate% of paths finish with money left at the end of the plan.'
                : '$lossRate% of paths finish below the starting value.',
            pills: [
              _InfoPill(
                label: 'Median outcome',
                value: _money.format(summary.median),
              ),
              _InfoPill(
                label: _isRetirement ? 'Success rate' : '95% VaR',
                value: _isRetirement ? '$successRate%' : _money.format(summary.var95),
              ),
              _InfoPill(
                label: '5th to 95th',
                value:
                    '${_money.format(summary.p5)} to ${_money.format(summary.p95)}',
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_result.comparison == null)
            _resultSection(
              sectionLabel: null,
              result: _result,
              sharedYRange: null,
            )
          else ...[
            _resultSection(
              sectionLabel: 'Constant σ (GBM)',
              result: _result,
              sharedYRange: _sharedYRangeWithComparison(),
            ),
            const SizedBox(height: 28),
            _resultSection(
              sectionLabel: 'GARCH(1,1)',
              result: _result.comparison!,
              sharedYRange: _sharedYRangeWithComparison(),
            ),
          ],
          const SizedBox(height: 20),
          const _SectionTitle('Scenario controls'),
          Card(
            elevation: 0,
            color: scheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: scheme.outlineVariant.withOpacity(0.24)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Adjust the assumptions and rerun from this screen.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (_config.model == 'gbm') ..._buildGbmControls() else ..._buildRetirementControls(),
                  _ParameterSlider(
                    label: 'Number of simulations',
                    description: 'Higher values smooth the distribution but take longer to run.',
                    value: _draftNSims.toDouble(),
                    min: 1000,
                    max: 50000,
                    divisions: 49,
                    displayValue: _draftNSims.toString(),
                    onChanged: (value) {
                      setState(() {
                        _draftNSims = (value / 1000).round() * 1000;
                      });
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(color: scheme.error),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
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
                        label: const Text('Reset controls'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _rerunSimulation,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.auto_graph),
                          label: Text(_busy ? 'Rerunning…' : 'Rerun simulation'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_isRetirement) ...[
            const SizedBox(height: 20),
            Card(
              color: scheme.secondaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'There is a $successRate% chance of not running out of money over the full horizon.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultSection({
    required String? sectionLabel,
    required SimulationResult result,
    required (double, double)? sharedYRange,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sectionLabel != null) ...[
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
        ],
        _ChartCard(
          title: _isRetirement ? 'Balance fan chart' : 'Portfolio fan chart',
          subtitle:
              'Outer band shows the 5th to 95th percentile range. Inner band shows the 25th to 75th percentile range.',
          child: FanChart(
            bands: result.bands,
            config: _config,
            yRange: sharedYRange,
          ),
        ),
        const SizedBox(height: 20),
        _ChartCard(
          title: 'Final outcome distribution',
          subtitle: _isRetirement
              ? 'Bars show how often final balances land in each bucket. Warm bars are depleted outcomes.'
              : 'Bars show the distribution of terminal values. Warm bars finish below the starting balance.',
          child: TerminalHistogram(
            histogram: result.histogram,
            config: _config,
          ),
        ),
        const SizedBox(height: 20),
        const _SectionTitle('Summary'),
        SummaryStatsCard(
          summary: result.summary,
          isRetirement: _isRetirement,
        ),
      ],
    );
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

  List<Widget> _buildGbmControls() => [
        _ParameterSlider(
          label: 'Beginning value',
          description: 'Initial portfolio size at the start of the simulation.',
          value: _input('beginning_value'),
          min: 1000,
          max: 500000,
          divisions: 499,
          displayValue: _money.format(_input('beginning_value')),
          onChanged: (value) => _setInput('beginning_value', value),
        ),
        _ParameterSlider(
          label: 'Expected annual return',
          description: 'Average yearly drift assumption used by the GBM model.',
          value: _input('mu') * 100,
          min: -10,
          max: 20,
          divisions: 60,
          displayValue: '${(_input('mu') * 100).toStringAsFixed(1)}%',
          onChanged: (value) => _setInput('mu', value / 100),
        ),
        _ParameterSlider(
          label: 'Volatility',
          description: 'Annual standard deviation of returns.',
          value: _input('sigma') * 100,
          min: 1,
          max: 60,
          divisions: 59,
          displayValue: '${(_input('sigma') * 100).toStringAsFixed(1)}%',
          onChanged: (value) => _setInput('sigma', value / 100),
        ),
        _ParameterSlider(
          label: 'Time horizon',
          description: 'How long to project the portfolio forward.',
          value: _input('years'),
          min: 1,
          max: 40,
          divisions: 39,
          displayValue: '${_input('years').round()} years',
          onChanged: (value) => _setInput('years', value.roundToDouble()),
        ),
      ];

  List<Widget> _buildRetirementControls() => [
        _ParameterSlider(
          label: 'Starting balance',
          description: 'Current investable balance.',
          value: _input('starting_balance'),
          min: 0,
          max: 2000000,
          divisions: 400,
          displayValue: _money.format(_input('starting_balance')),
          onChanged: (value) => _setInput('starting_balance', value),
        ),
        _ParameterSlider(
          label: 'Annual contribution',
          description: 'Amount added each year before retirement.',
          value: _input('annual_contribution'),
          min: 0,
          max: 100000,
          divisions: 200,
          displayValue: _money.format(_input('annual_contribution')),
          onChanged: (value) => _setInput('annual_contribution', value),
        ),
        _ParameterSlider(
          label: 'Years until retirement',
          description: 'Accumulation phase length.',
          value: _input('years_to_retire'),
          min: 0,
          max: 45,
          divisions: 45,
          displayValue: '${_input('years_to_retire').round()} years',
          onChanged: (value) => _setInput('years_to_retire', value.roundToDouble()),
        ),
        _ParameterSlider(
          label: 'Years in retirement',
          description: 'Withdrawal phase length.',
          value: _input('retirement_years'),
          min: 5,
          max: 45,
          divisions: 40,
          displayValue: '${_input('retirement_years').round()} years',
          onChanged: (value) => _setInput('retirement_years', value.roundToDouble()),
        ),
        _ParameterSlider(
          label: 'Annual withdrawal',
          description: 'First-year withdrawal before inflation adjustments.',
          value: _input('annual_withdrawal'),
          min: 10000,
          max: 200000,
          divisions: 190,
          displayValue: _money.format(_input('annual_withdrawal')),
          onChanged: (value) => _setInput('annual_withdrawal', value),
        ),
        _ParameterSlider(
          label: 'Mean annual return',
          description: 'Expected average return during both phases.',
          value: _input('mean_return') * 100,
          min: -5,
          max: 15,
          divisions: 40,
          displayValue: '${(_input('mean_return') * 100).toStringAsFixed(1)}%',
          onChanged: (value) => _setInput('mean_return', value / 100),
        ),
        _ParameterSlider(
          label: 'Return volatility',
          description: 'Annual variability of returns.',
          value: _input('std_return') * 100,
          min: 1,
          max: 40,
          divisions: 39,
          displayValue: '${(_input('std_return') * 100).toStringAsFixed(1)}%',
          onChanged: (value) => _setInput('std_return', value / 100),
        ),
        _ParameterSlider(
          label: 'Inflation',
          description: 'Withdrawal growth rate after retirement begins.',
          value: _input('inflation') * 100,
          min: 0,
          max: 10,
          divisions: 40,
          displayValue: '${(_input('inflation') * 100).toStringAsFixed(1)}%',
          onChanged: (value) => _setInput('inflation', value / 100),
        ),
      ];
}

class _HeroSummary extends StatelessWidget {
  const _HeroSummary({
    required this.title,
    required this.subtitle,
    required this.pills,
  });

  final String title;
  final String subtitle;
  final List<_InfoPill> pills;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer,
            scheme.surfaceContainerHigh,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: pills,
            ),
          ],
        ),
      ),
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

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: scheme.outlineVariant.withOpacity(0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _ParameterSlider extends StatelessWidget {
  const _ParameterSlider({
    required this.label,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onChanged,
  });

  final String label;
  final String description;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Text(
                  displayValue,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
            ),
            Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: displayValue,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
