import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/simulation_config.dart';
import '../models/simulation_result.dart';

/// Fan chart with percentile bands, a median path, and contextual markers.
class FanChart extends StatelessWidget {
  const FanChart({
    super.key,
    required this.bands,
    required this.config,
    this.yRange,
  });

  final PercentileBands bands;
  final SimulationConfig config;

  /// Optional (minY, maxY) override. When set, both charts can share an axis
  /// for honest side-by-side visual comparison.
  final (double, double)? yRange;

  static final NumberFormat _money =
      NumberFormat.compactCurrency(symbol: '\$', decimalDigits: 0);

  List<FlSpot> _spots(List<double> ys) => [
        for (int i = 0; i < bands.steps.length; i++)
          FlSpot(bands.steps[i], ys[i]),
      ];

  double _yearAt(double step) {
    if (config.model == 'retirement') {
      return step;
    }
    final stepsPerYear = (config.inputs['steps_per_year'] as num?)?.toDouble() ?? 252;
    return step / stepsPerYear;
  }

  String _bottomLabel(double step) {
    final years = _yearAt(step);
    if (years == 0) return 'Now';
    final rounded = years.round();
    if ((years - rounded).abs() < 0.15) return '${rounded}y';
    return '${years.toStringAsFixed(1)}y';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final steps = bands.steps;
    final autoMaxY = [
      ...bands.p95,
      ...bands.p75,
      ...bands.p50,
    ].fold<double>(1, (max, value) => value > max ? value : max);
    final effectiveMinY = yRange?.$1 ?? 0;
    final effectiveMaxY = yRange?.$2 ?? autoMaxY * 1.08;
    final maxY = effectiveMaxY; // used for y-axis interval below
    final startValue = config.model == 'gbm'
        ? (config.inputs['beginning_value'] as num).toDouble()
        : (config.inputs['starting_balance'] as num).toDouble();
    final retirementStartX = config.model == 'retirement'
        ? (config.inputs['years_to_retire'] as num).toDouble()
        : null;
    final xInterval = steps.length <= 1
        ? 1.0
        : (steps.last - steps.first) / 4;
    final yInterval = maxY <= 5 ? 1.0 : maxY / 4;

    LineChartBarData boundary(List<double> ys, Color color, {double width = 1.25}) {
      return LineChartBarData(
        spots: _spots(ys),
        isCurved: true,
        curveSmoothness: 0.18,
        color: color,
        barWidth: width,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
      );
    }

    const p5Index = 0;
    const p25Index = 1;
    const p50Index = 2;
    const p75Index = 3;
    const p95Index = 4;

    return AspectRatio(
      aspectRatio: 1.55,
      child: LineChart(
        LineChartData(
          minX: steps.isEmpty ? 0 : steps.first,
          maxX: steps.isEmpty ? 1 : steps.last,
          minY: effectiveMinY,
          maxY: effectiveMaxY,
          clipData: const FlClipData.all(),
          backgroundColor: scheme.surface,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yInterval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: scheme.outlineVariant.withOpacity(0.28),
              strokeWidth: 1,
            ),
          ),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchSpotThreshold: 24,
            getTouchLineStart: (_, __) => 0,
            getTouchLineEnd: (_, __) => double.infinity,
            getTouchedSpotIndicator: (barData, spotIndexes) => [
              for (final spotIndex in spotIndexes)
                if (barData.color == scheme.primary)
                  TouchedSpotIndicatorData(
                    FlLine(
                      color: scheme.primary.withOpacity(0.25),
                      strokeWidth: 1.25,
                      dashArray: const [5, 5],
                    ),
                    FlDotData(
                      show: true,
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                        radius: 4,
                        color: scheme.primary,
                        strokeWidth: 2,
                        strokeColor: scheme.surface,
                      ),
                    ),
                  )
                else
                  null,
            ],
            touchTooltipData: LineTouchTooltipData(
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              tooltipPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              tooltipMargin: 12,
              maxContentWidth: 180,
              tooltipBorderRadius: BorderRadius.circular(14),
              tooltipBorder: BorderSide(
                color: scheme.outlineVariant.withOpacity(0.35),
              ),
              getTooltipColor: (_) => scheme.surface.withOpacity(0.96),
              getTooltipItems: (spots) {
                final medianSpot = spots.where((spot) => spot.barIndex == p50Index).firstOrNull;
                if (medianSpot == null) {
                  return [for (final _ in spots) null];
                }
                final i = medianSpot.spotIndex;
                final year = _yearAt(medianSpot.x);
                final title = year == 0
                    ? 'Start'
                    : 'Year ${year.toStringAsFixed(year >= 10 ? 0 : 1)}';
                final text = [
                  title,
                  'P95 ${_money.format(bands.p95[i])}',
                  'P75 ${_money.format(bands.p75[i])}',
                  'Median ${_money.format(bands.p50[i])}',
                  'P25 ${_money.format(bands.p25[i])}',
                  'P05 ${_money.format(bands.p5[i])}',
                ].join('\n');
                return [
                  for (final spot in spots)
                    spot.barIndex == p50Index
                        ? LineTooltipItem(
                            text,
                            textTheme.bodySmall!.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          )
                        : null,
                ];
              },
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 56,
                interval: yInterval,
                getTitlesWidget: (value, meta) => Text(
                  _money.format(value),
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
                interval: xInterval <= 0 ? 1 : xInterval,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _bottomLabel(value),
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
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
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: startValue,
                color: scheme.primary.withOpacity(0.3),
                strokeWidth: 1.4,
                dashArray: const [6, 4],
              ),
            ],
            verticalLines: [
              if (retirementStartX != null)
                VerticalLine(
                  x: retirementStartX,
                  color: scheme.tertiary.withOpacity(0.45),
                  strokeWidth: 1.4,
                  dashArray: const [6, 4],
                ),
            ],
          ),
          lineBarsData: [
            boundary(bands.p5, scheme.error.withOpacity(0.18)),
            boundary(bands.p25, scheme.primary.withOpacity(0.26)),
            LineChartBarData(
              spots: _spots(bands.p50),
              isCurved: true,
              curveSmoothness: 0.18,
              gradient: LinearGradient(
                colors: [
                  scheme.primary,
                  scheme.tertiary,
                ],
              ),
              barWidth: 3.2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
            ),
            boundary(bands.p75, scheme.primary.withOpacity(0.26)),
            boundary(bands.p95, scheme.primary.withOpacity(0.18)),
          ],
          betweenBarsData: [
            BetweenBarsData(
              fromIndex: p5Index,
              toIndex: p95Index,
              gradient: LinearGradient(
                colors: [
                  scheme.primary.withOpacity(0.06),
                  scheme.primary.withOpacity(0.16),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            BetweenBarsData(
              fromIndex: p25Index,
              toIndex: p75Index,
              gradient: LinearGradient(
                colors: [
                  scheme.primary.withOpacity(0.18),
                  scheme.primary.withOpacity(0.30),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 450),
      ),
    );
  }
}
