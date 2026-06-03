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

  group('GARCH comparison', () {
    test('SimulationConfig.gbm carries compareGarch into payload and json', () {
      final config = SimulationConfig.gbm(
        beginningValue: 10000,
        mu: 0.07,
        sigma: 0.15,
        years: 10,
        compareGarch: true,
      );
      expect(config.compareGarch, isTrue);
      expect(config.toCallablePayload()['compare_garch'], isTrue);
      final round = SimulationConfig.fromJson(config.toJson());
      expect(round.compareGarch, isTrue);
    });

    test('SimulationConfig defaults compareGarch to false', () {
      final config = SimulationConfig.gbm(
        beginningValue: 10000,
        mu: 0.07,
        sigma: 0.15,
        years: 10,
      );
      expect(config.compareGarch, isFalse);
      expect(config.toCallablePayload().containsKey('compare_garch'), isFalse);
    });

    test('SimulationResult parses optional comparison block', () {
      final json = {
        'bands': {
          'steps': [0.0, 1.0],
          'p5': [10000.0, 9500.0],
          'p25': [10000.0, 9800.0],
          'p50': [10000.0, 10100.0],
          'p75': [10000.0, 10400.0],
          'p95': [10000.0, 10800.0],
        },
        'histogram': {'counts': [1, 2, 1], 'edges': [9000.0, 10000.0, 11000.0, 12000.0]},
        'summary': {
          'mean': 10100.0, 'median': 10100.0,
          'p5': 9500.0, 'p95': 10800.0,
          'min': 9000.0, 'max': 12000.0,
          'prob_loss': 0.2, 'var_95': 500.0, 'success_rate': 0.8,
        },
        'comparison': {
          'model': 'gbm-garch',
          'bands': {
            'steps': [0.0, 1.0],
            'p5': [10000.0, 9300.0],
            'p25': [10000.0, 9700.0],
            'p50': [10000.0, 10100.0],
            'p75': [10000.0, 10500.0],
            'p95': [10000.0, 11000.0],
          },
          'histogram': {'counts': [2, 1, 1], 'edges': [9000.0, 10000.0, 11000.0, 12000.0]},
          'summary': {
            'mean': 10100.0, 'median': 10100.0,
            'p5': 9300.0, 'p95': 11000.0,
            'min': 8800.0, 'max': 12200.0,
            'prob_loss': 0.25, 'var_95': 700.0, 'success_rate': 0.75,
          },
        },
      };
      final result = SimulationResult.fromJson(json);
      expect(result.comparison, isNotNull);
      expect(result.comparison!.summary.p5, 9300.0);
    });

    test('SimulationResult.fromJson tolerates missing comparison', () {
      final json = {
        'bands': {
          'steps': [0.0], 'p5': [1.0], 'p25': [1.0],
          'p50': [1.0], 'p75': [1.0], 'p95': [1.0],
        },
        'histogram': {'counts': [1], 'edges': [0.0, 1.0]},
        'summary': {
          'mean': 1.0, 'median': 1.0, 'p5': 1.0, 'p95': 1.0,
          'min': 1.0, 'max': 1.0, 'prob_loss': 0.0,
          'var_95': 0.0, 'success_rate': 1.0,
        },
      };
      final result = SimulationResult.fromJson(json);
      expect(result.comparison, isNull);
    });
  });
}
