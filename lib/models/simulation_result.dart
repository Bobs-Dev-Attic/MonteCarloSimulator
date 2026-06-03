/// Aggregated output of a Monte Carlo run, as returned by the Cloud Function
/// and persisted to Firestore. Mirrors the structure produced by
/// `functions/montecarlo/aggregate.py`.
class PercentileBands {
  const PercentileBands({
    required this.steps,
    required this.p5,
    required this.p25,
    required this.p50,
    required this.p75,
    required this.p95,
  });

  final List<double> steps;
  final List<double> p5;
  final List<double> p25;
  final List<double> p50;
  final List<double> p75;
  final List<double> p95;

  factory PercentileBands.fromJson(Map<String, dynamic> json) {
    List<double> nums(String key) =>
        (json[key] as List).map((e) => (e as num).toDouble()).toList();
    return PercentileBands(
      steps: nums('steps'),
      p5: nums('p5'),
      p25: nums('p25'),
      p50: nums('p50'),
      p75: nums('p75'),
      p95: nums('p95'),
    );
  }

  Map<String, dynamic> toJson() => {
        'steps': steps,
        'p5': p5,
        'p25': p25,
        'p50': p50,
        'p75': p75,
        'p95': p95,
      };
}

class Histogram {
  const Histogram({required this.counts, required this.edges});

  final List<int> counts;
  final List<double> edges;

  factory Histogram.fromJson(Map<String, dynamic> json) => Histogram(
        counts: (json['counts'] as List).map((e) => (e as num).toInt()).toList(),
        edges: (json['edges'] as List).map((e) => (e as num).toDouble()).toList(),
      );

  Map<String, dynamic> toJson() => {'counts': counts, 'edges': edges};
}

class SummaryStats {
  const SummaryStats({
    required this.mean,
    required this.median,
    required this.p5,
    required this.p95,
    required this.min,
    required this.max,
    required this.probLoss,
    required this.var95,
    required this.successRate,
  });

  final double mean;
  final double median;
  final double p5;
  final double p95;
  final double min;
  final double max;
  final double probLoss;
  final double var95;
  final double successRate;

  factory SummaryStats.fromJson(Map<String, dynamic> json) {
    double n(String k) => (json[k] as num).toDouble();
    return SummaryStats(
      mean: n('mean'),
      median: n('median'),
      p5: n('p5'),
      p95: n('p95'),
      min: n('min'),
      max: n('max'),
      probLoss: n('prob_loss'),
      var95: n('var_95'),
      successRate: n('success_rate'),
    );
  }

  Map<String, dynamic> toJson() => {
        'mean': mean,
        'median': median,
        'p5': p5,
        'p95': p95,
        'min': min,
        'max': max,
        'prob_loss': probLoss,
        'var_95': var95,
        'success_rate': successRate,
      };
}

class SimulationResult {
  const SimulationResult({
    required this.bands,
    required this.histogram,
    required this.summary,
    this.comparison,
  });

  final PercentileBands bands;
  final Histogram histogram;
  final SummaryStats summary;
  final SimulationResult? comparison;

  factory SimulationResult.fromJson(Map<String, dynamic> json) {
    final compRaw = json['comparison'];
    return SimulationResult(
      bands: PercentileBands.fromJson(
          Map<String, dynamic>.from(json['bands'] as Map)),
      histogram: Histogram.fromJson(
          Map<String, dynamic>.from(json['histogram'] as Map)),
      summary: SummaryStats.fromJson(
          Map<String, dynamic>.from(json['summary'] as Map)),
      comparison: compRaw == null
          ? null
          : SimulationResult.fromJson(Map<String, dynamic>.from(compRaw as Map)),
    );
  }

  Map<String, dynamic> toJson() => {
        'bands': bands.toJson(),
        'histogram': histogram.toJson(),
        'summary': summary.toJson(),
        if (comparison != null) 'comparison': comparison!.toJson(),
      };
}
