import 'package:flutter/material.dart';

import '../models/simulation_config.dart';
import '../models/simulation_result.dart';
import '../widgets/fan_chart.dart';
import '../widgets/summary_stats_card.dart';
import '../widgets/terminal_histogram.dart';

/// Displays a simulation's aggregated results: fan chart, terminal-value
/// histogram, and summary statistics.
class ResultsScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isRetirement = config.model == 'retirement';
    return Scaffold(
      appBar: AppBar(
        title: Text(title ??
            (isRetirement ? 'Retirement Results' : 'Portfolio Results')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle(isRetirement
              ? 'Balance over time (percentile bands)'
              : 'Projected value over time (percentile bands)'),
          FanChart(bands: result.bands),
          const SizedBox(height: 24),
          const _SectionTitle('Distribution of final outcomes'),
          TerminalHistogram(histogram: result.histogram),
          const SizedBox(height: 24),
          const _SectionTitle('Summary'),
          SummaryStatsCard(
            summary: result.summary,
            isRetirement: isRetirement,
          ),
          if (isRetirement) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'There is a ${(result.summary.successRate * 100).toStringAsFixed(1)}% '
                  'chance of not running out of money over the full horizon.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ],
        ],
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
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
