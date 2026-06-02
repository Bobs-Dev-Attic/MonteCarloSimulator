import 'package:flutter_test/flutter_test.dart';
import 'package:monte_carlo_simulator/models/simulation_config.dart';
import 'package:monte_carlo_simulator/models/simulation_result.dart';

void main() {
  group('SimulationConfig', () {
    test('gbm factory builds the expected callable payload', () {
      final config = SimulationConfig.gbm(
        beginningValue: 10000,
        mu: 0.07,
        sigma: 0.15,
        years: 10,
        nSims: 5000,
        seed: 42,
      );
      final payload = config.toCallablePayload();
      expect(payload['model'], 'gbm');
      expect(payload['n_sims'], 5000);
      expect(payload['seed'], 42);
      expect((payload['inputs'] as Map)['beginning_value'], 10000);
      expect((payload['inputs'] as Map)['mu'], 0.07);
    });

    test('retirement factory round-trips through json', () {
      final config = SimulationConfig.retirement(
        startingBalance: 100000,
        annualContribution: 15000,
        yearsToRetire: 25,
        retirementYears: 30,
        annualWithdrawal: 60000,
        meanReturn: 0.06,
        stdReturn: 0.12,
        inflation: 0.025,
      );
      final restored = SimulationConfig.fromJson(config.toJson());
      expect(restored.model, 'retirement');
      expect(restored.inputs['years_to_retire'], 25);
      expect(restored.inputs['mean_return'], 0.06);
    });
  });

  group('SimulationResult parsing', () {
    test('parses the Cloud Function payload shape', () {
      final json = {
        'bands': {
          'steps': [0, 1, 2],
          'p5': [100.0, 98, 95],
          'p25': [100.0, 101, 102],
          'p50': [100.0, 103, 106],
          'p75': [100.0, 105, 110],
          'p95': [100.0, 108, 118],
        },
        'histogram': {
          'counts': [2, 5, 3],
          'edges': [90.0, 100, 110, 120],
        },
        'summary': {
          'mean': 106.0,
          'median': 105.0,
          'p5': 95.0,
          'p95': 118.0,
          'min': 90.0,
          'max': 120.0,
          'prob_loss': 0.2,
          'var_95': 5.0,
          'success_rate': 0.8,
        },
      };
      final result = SimulationResult.fromJson(json);
      expect(result.bands.p50.last, 106.0);
      expect(result.histogram.counts, [2, 5, 3]);
      expect(result.summary.successRate, 0.8);
      expect(result.summary.probLoss, 0.2);
    });
  });
}
