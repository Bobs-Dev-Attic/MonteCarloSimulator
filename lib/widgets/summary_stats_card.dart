import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/simulation_result.dart';

/// Grid of headline risk/return statistics from a simulation.
class SummaryStatsCard extends StatelessWidget {
  const SummaryStatsCard({
    super.key,
    required this.summary,
    required this.isRetirement,
  });

  final SummaryStats summary;
  final bool isRetirement;

  static final _money =
      NumberFormat.compactCurrency(symbol: '\$', decimalDigits: 0);
  String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      ('Median outcome', _money.format(summary.median)),
      ('Mean outcome', _money.format(summary.mean)),
      ('5th percentile', _money.format(summary.p5)),
      ('95th percentile', _money.format(summary.p95)),
      if (isRetirement)
        ('Success rate', _pct(summary.successRate))
      else
        ('Prob. of loss', _pct(summary.probLoss)),
      ('95% VaR', _money.format(summary.var95)),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (label, value) in items)
              SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: Theme.of(context).textTheme.bodySmall),
                    Text(value,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
