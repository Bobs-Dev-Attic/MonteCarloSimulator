import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/simulation_config.dart';
import '../models/simulation_result.dart';

/// Distribution of terminal outcomes with better scaling and contextual colors.
class TerminalHistogram extends StatelessWidget {
  const TerminalHistogram({
    super.key,
    required this.histogram,
    required this.config,
  });

  final Histogram histogram;
  final SimulationConfig config;

  static final NumberFormat _money =
      NumberFormat.compactCurrency(symbol: '\$', decimalDigits: 0);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final counts = histogram.counts;
    final edges = histogram.edges;
    final maxCount =
        counts.isEmpty ? 1 : counts.reduce((a, b) => a > b ? a : b);
    final breakEven = config.model == 'gbm'
        ? (config.inputs['beginning_value'] as num).toDouble()
        : 0.0;
    final xInterval = counts.length <= 8 ? 1.0 : (counts.length / 5).ceilToDouble();
    final yInterval = math.max(1, (maxCount / 4).ceil()).toDouble();
    final barWidth = counts.length > 32 ? 6.0 : 10.0;

    return AspectRatio(
      aspectRatio: 1.55,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceBetween,
          maxY: maxCount.toDouble() * 1.12,
          minY: 0,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yInterval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: scheme.outlineVariant.withOpacity(0.28),
              strokeWidth: 1,
            ),
          ),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              tooltipPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              tooltipMargin: 10,
              tooltipBorderRadius: BorderRadius.circular(14),
              tooltipBorder: BorderSide(
                color: scheme.outlineVariant.withOpacity(0.35),
              ),
              getTooltipColor: (_) => scheme.surface.withOpacity(0.96),
              getTooltipItem: (group, _, rod, __) {
                final lo = edges[group.x];
                final hi = edges[group.x + 1];
                final pct = counts.isEmpty
                    ? 0.0
                    : rod.toY / counts.fold<int>(0, (sum, n) => sum + n) * 100;
                return BarTooltipItem(
                  '${_money.format(lo)} to ${_money.format(hi)}\n'
                  '${rod.toY.toInt()} paths • ${pct.toStringAsFixed(1)}%',
                  textTheme.bodySmall!.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: yInterval,
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: xInterval,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= counts.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _money.format(edges[i]),
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              left: BorderSide(color: scheme.outlineVariant.withOpacity(0.35)),
              bottom: BorderSide(color: scheme.outlineVariant.withOpacity(0.35)),
            ),
          ),
          barGroups: [
            for (int i = 0; i < counts.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: counts[i].toDouble(),
                    width: barWidth,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: _binMidpoint(edges, i) < breakEven
                          ? [
                              scheme.error.withOpacity(0.72),
                              scheme.error,
                            ]
                          : [
                              scheme.tertiary.withOpacity(0.72),
                              scheme.primary,
                            ],
                    ),
                  ),
                ],
              ),
          ],
        ),
        duration: const Duration(milliseconds: 450),
      ),
    );
  }

  double _binMidpoint(List<double> edges, int i) => (edges[i] + edges[i + 1]) / 2;
}
