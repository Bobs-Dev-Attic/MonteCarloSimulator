/// Configuration for a single Monte Carlo run.
///
/// [model] is either `"gbm"` (portfolio/asset forecast) or `"retirement"`.
/// [inputs] holds the model-specific parameters that get passed straight to the
/// Cloud Function, so the field names here mirror the Python keyword arguments.
class SimulationConfig {
  const SimulationConfig({
    required this.model,
    required this.inputs,
    this.nSims = 10000,
    this.seed,
  });

  final String model;
  final Map<String, dynamic> inputs;
  final int nSims;
  final int? seed;

  /// Convenience constructor for a GBM portfolio forecast.
  factory SimulationConfig.gbm({
    required double beginningValue,
    required double mu,
    required double sigma,
    required double years,
    int stepsPerYear = 252,
    double contributionPerStep = 0.0,
    int nSims = 10000,
    int? seed,
  }) {
    return SimulationConfig(
      model: 'gbm',
      nSims: nSims,
      seed: seed,
      inputs: {
        'beginning_value': beginningValue,
        'mu': mu,
        'sigma': sigma,
        'years': years,
        'steps_per_year': stepsPerYear,
        'contribution_per_step': contributionPerStep,
      },
    );
  }

  /// Convenience constructor for a retirement accumulation + withdrawal run.
  factory SimulationConfig.retirement({
    required double startingBalance,
    required double annualContribution,
    required int yearsToRetire,
    required int retirementYears,
    required double annualWithdrawal,
    required double meanReturn,
    required double stdReturn,
    double inflation = 0.0,
    int nSims = 10000,
    int? seed,
  }) {
    return SimulationConfig(
      model: 'retirement',
      nSims: nSims,
      seed: seed,
      inputs: {
        'starting_balance': startingBalance,
        'annual_contribution': annualContribution,
        'years_to_retire': yearsToRetire,
        'retirement_years': retirementYears,
        'annual_withdrawal': annualWithdrawal,
        'mean_return': meanReturn,
        'std_return': stdReturn,
        'inflation': inflation,
      },
    );
  }

  /// Payload sent to the `runSimulation` callable function.
  Map<String, dynamic> toCallablePayload() => {
        'model': model,
        'inputs': inputs,
        'n_sims': nSims,
        if (seed != null) 'seed': seed,
      };

  /// Serialized form stored in Firestore.
  Map<String, dynamic> toJson() => {
        'model': model,
        'inputs': inputs,
        'nSims': nSims,
        if (seed != null) 'seed': seed,
      };

  factory SimulationConfig.fromJson(Map<String, dynamic> json) {
    return SimulationConfig(
      model: json['model'] as String,
      inputs: Map<String, dynamic>.from(json['inputs'] as Map),
      nSims: (json['nSims'] as num?)?.toInt() ?? 10000,
      seed: (json['seed'] as num?)?.toInt(),
    );
  }
}
