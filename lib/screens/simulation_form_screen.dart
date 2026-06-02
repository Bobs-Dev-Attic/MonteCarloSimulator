import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/simulation_config.dart';
import '../state/providers.dart';
import 'results_screen.dart';

/// Form for configuring and launching a GBM or retirement simulation.
class SimulationFormScreen extends ConsumerStatefulWidget {
  const SimulationFormScreen({super.key});

  @override
  ConsumerState<SimulationFormScreen> createState() =>
      _SimulationFormScreenState();
}

class _SimulationFormScreenState extends ConsumerState<SimulationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  String _model = 'gbm';
  bool _busy = false;
  String? _error;

  // GBM fields.
  final _beginningValue = TextEditingController(text: '10000');
  final _mu = TextEditingController(text: '7');
  final _sigma = TextEditingController(text: '15');
  final _years = TextEditingController(text: '10');

  // Retirement fields.
  final _startingBalance = TextEditingController(text: '100000');
  final _annualContribution = TextEditingController(text: '15000');
  final _yearsToRetire = TextEditingController(text: '25');
  final _retirementYears = TextEditingController(text: '30');
  final _annualWithdrawal = TextEditingController(text: '60000');
  final _meanReturn = TextEditingController(text: '6');
  final _stdReturn = TextEditingController(text: '12');
  final _inflation = TextEditingController(text: '2.5');

  final _nSims = TextEditingController(text: '10000');

  @override
  void dispose() {
    for (final c in [
      _beginningValue, _mu, _sigma, _years, _startingBalance,
      _annualContribution, _yearsToRetire, _retirementYears, _annualWithdrawal,
      _meanReturn, _stdReturn, _inflation, _nSims,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
  int _i(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  SimulationConfig _buildConfig() {
    final nSims = _i(_nSims);
    if (_model == 'gbm') {
      return SimulationConfig.gbm(
        beginningValue: _d(_beginningValue),
        mu: _d(_mu) / 100, // percent -> fraction
        sigma: _d(_sigma) / 100,
        years: _d(_years),
        nSims: nSims,
      );
    }
    return SimulationConfig.retirement(
      startingBalance: _d(_startingBalance),
      annualContribution: _d(_annualContribution),
      yearsToRetire: _i(_yearsToRetire),
      retirementYears: _i(_retirementYears),
      annualWithdrawal: _d(_annualWithdrawal),
      meanReturn: _d(_meanReturn) / 100,
      stdReturn: _d(_stdReturn) / 100,
      inflation: _d(_inflation) / 100,
      nSims: nSims,
    );
  }

  Future<void> _runSimulation() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final config = _buildConfig();
      final result = await ref.read(simulationServiceProvider).run(config);

      final user = ref.read(authStateProvider).valueOrNull;
      if (user != null) {
        await ref.read(firestoreServiceProvider).saveSimulation(
              uid: user.uid,
              config: config,
              result: result,
            );
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultsScreen(result: result, config: config),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Simulation')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'gbm', label: Text('Portfolio (GBM)')),
                ButtonSegment(value: 'retirement', label: Text('Retirement')),
              ],
              selected: {_model},
              onSelectionChanged: (s) => setState(() => _model = s.first),
            ),
            const SizedBox(height: 16),
            if (_model == 'gbm') ..._gbmFields() else ..._retirementFields(),
            const Divider(height: 32),
            _numField(_nSims, 'Number of simulations', isInt: true),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _runSimulation,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: Text(_busy ? 'Running…' : 'Run simulation'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _gbmFields() => [
        _numField(_beginningValue, 'Beginning value (\$)'),
        _numField(_mu, 'Expected annual return (%)'),
        _numField(_sigma, 'Volatility / std dev (%)'),
        _numField(_years, 'Time horizon (years)'),
      ];

  List<Widget> _retirementFields() => [
        _numField(_startingBalance, 'Starting balance (\$)'),
        _numField(_annualContribution, 'Annual contribution (\$)'),
        _numField(_yearsToRetire, 'Years until retirement', isInt: true),
        _numField(_retirementYears, 'Years in retirement', isInt: true),
        _numField(_annualWithdrawal, 'Annual withdrawal (\$)'),
        _numField(_meanReturn, 'Mean annual return (%)'),
        _numField(_stdReturn, 'Return volatility (%)'),
        _numField(_inflation, 'Inflation (%)'),
      ];

  Widget _numField(TextEditingController c, String label, {bool isInt = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: c,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        keyboardType: TextInputType.numberWithOptions(decimal: !isInt),
        validator: (v) {
          final parsed = isInt ? int.tryParse(v ?? '') : double.tryParse(v ?? '');
          if (parsed == null) return 'Enter a valid number';
          return null;
        },
      ),
    );
  }
}
