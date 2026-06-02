import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/simulation_result.dart';

/// Bar chart of the terminal-value distribution (typically log-normal shaped).
class TerminalHistogram extends StatelessWidget {
  const TerminalHistogram({super.key, required this.histogram});

  final Histogram histogram;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    final counts = histogram.counts;
    final edges = histogram.edges;
    final maxCount =
        counts.isEmpty ? 1 : counts.reduce((a, b) => a > b ? a : b);
    final fmt = NumberFormat.compact();

    return AspectRatio(
      aspectRatio: 1.6,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceBetween,
          maxY: maxCount.toDouble() * 1.05,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, __) {
                final lo = edges[group.x];
                final hi = edges[group.x + 1];
                return BarTooltipItem(
                  '${fmt.format(lo)}–${fmt.format(hi)}\n${rod.toY.toInt()} paths',
                  const TextStyle(color: Colors.white, fontSize: 11),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: (counts.length / 5).ceilToDouble(),
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= edges.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(fmt.format(edges[i]),
                        style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (int i = 0; i < counts.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: counts[i].toDouble(),
                  color: color,
                  width: 4,
                  borderRadius: BorderRadius.zero,
                ),
              ]),
          ],
        ),
      ),
    );
  }
}
