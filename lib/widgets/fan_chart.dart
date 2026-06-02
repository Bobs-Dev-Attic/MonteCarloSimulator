import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/simulation_result.dart';

/// "Fan chart" of percentile bands over time: a shaded p5–p95 region, a lighter
/// p25–p75 region, and a solid median line.
class FanChart extends StatelessWidget {
  const FanChart({super.key, required this.bands});

  final PercentileBands bands;

  List<FlSpot> _spots(List<double> ys) => [
        for (int i = 0; i < bands.steps.length; i++)
          FlSpot(bands.steps[i], ys[i]),
      ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final maxY = bands.p95.isEmpty ? 1.0 : bands.p95.reduce((a, b) => a > b ? a : b);

    LineChartBarData band(List<double> ys, {required List<double> below}) {
      return LineChartBarData(
        spots: _spots(ys),
        isCurved: false,
        color: Colors.transparent,
        barWidth: 0,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: primary.withOpacity(0.12),
          applyCutOffY: true,
          cutOffY: 0,
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 1.6,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY * 1.05,
          lineTouchData: const LineTouchData(enabled: true),
          titlesData: const FlTitlesData(
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
            bottomTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 24)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            // p95 shaded down to baseline, then p5 masks it -> p5..p95 band.
            band(bands.p95, below: bands.p5),
            LineChartBarData(
              spots: _spots(bands.p5),
              color: Colors.transparent,
              barWidth: 0,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: Colors.white),
            ),
            // Median line.
            LineChartBarData(
              spots: _spots(bands.p50),
              isCurved: false,
              color: primary,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}
