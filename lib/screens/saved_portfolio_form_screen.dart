import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/saved_portfolio.dart';
import '../state/providers.dart';
import 'investment_form_screen.dart' show UpperCaseTextFormatter;

const _periodOptions = ['1y', '2y', '5y', '10y', 'max'];

/// A single editable ticker/weight row. Owns its controllers so they survive
/// rebuilds and can be disposed cleanly.
class _Row {
  _Row({String ticker = '', double weight = 1}) {
    tickerCtrl = TextEditingController(text: ticker);
    weightCtrl = TextEditingController(
      text: weight == weight.roundToDouble()
          ? weight.toStringAsFixed(0)
          : weight.toString(),
    );
  }

  late final TextEditingController tickerCtrl;
  late final TextEditingController weightCtrl;

  void dispose() {
    tickerCtrl.dispose();
    weightCtrl.dispose();
  }
}

/// Create / edit / delete a saved (model) portfolio: a name, a target horizon
/// for estimation, and a list of ticker + weight rows.
class SavedPortfolioFormScreen extends ConsumerStatefulWidget {
  const SavedPortfolioFormScreen({
    super.key,
    required this.householdId,
    this.existing,
    this.initialHoldings,
  });

  final String householdId;
  final SavedPortfolio? existing;

  /// Pre-filled rows for a brand-new portfolio (e.g. "save current holdings").
  /// Ignored when [existing] is provided.
  final List<PortfolioHolding>? initialHoldings;

  @override
  ConsumerState<SavedPortfolioFormScreen> createState() =>
      _SavedPortfolioFormScreenState();
}

class _SavedPortfolioFormScreenState
    extends ConsumerState<SavedPortfolioFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late String _period;
  late final List<_Row> _rows;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _period = e?.period ?? '5y';
    final seed = e?.holdings ?? widget.initialHoldings;
    if (seed != null && seed.isNotEmpty) {
      _rows = [
        for (final h in seed) _Row(ticker: h.ticker, weight: h.weight),
      ];
    } else {
      _rows = [_Row(), _Row()]; // start with two blank rows
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _addRow() => setState(() => _rows.add(_Row()));

  void _removeRow(int i) {
    setState(() {
      _rows.removeAt(i).dispose();
    });
  }

  SavedPortfolioDraft _buildDraft() {
    final holdings = <PortfolioHolding>[];
    for (final r in _rows) {
      final ticker = r.tickerCtrl.text.trim();
      if (ticker.isEmpty) continue;
      final weight = double.tryParse(r.weightCtrl.text.trim()) ?? 0;
      holdings.add(PortfolioHolding(ticker: ticker, weight: weight));
    }
    return SavedPortfolioDraft(
      name: _nameCtrl.text.trim(),
      holdings: holdings,
      period: _period,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final draft = _buildDraft();
    if (draft.holdings.isEmpty) {
      setState(() => _error = 'Add at least one ticker');
      return;
    }
    if (draft.holdings.any((h) => h.weight <= 0)) {
      setState(() => _error = 'Weights must be greater than zero');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final svc = ref.read(savedPortfolioServiceProvider);
      if (_isEdit) {
        await svc.updatePortfolio(
          householdId: widget.householdId,
          portfolioId: widget.existing!.id,
          draft: draft,
        );
      } else {
        final advisor = ref.read(currentAdvisorUidProvider);
        if (advisor == null) throw StateError('Not signed in');
        await svc.createPortfolio(
          householdId: widget.householdId,
          advisorUid: advisor,
          draft: draft,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this portfolio?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(savedPortfolioServiceProvider).deletePortfolio(
            householdId: widget.householdId,
            portfolioId: widget.existing!.id,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit portfolio' : 'New portfolio'),
        actions: [
          if (_isEdit)
            IconButton(
              key: const ValueKey('delete-portfolio'),
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _confirmDelete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('portfolio-name-field'),
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Portfolio name',
                  hintText: 'e.g. 60/40 Growth',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('period-field'),
                initialValue: _period,
                decoration: const InputDecoration(
                  labelText: 'History window (for estimation)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final p in _periodOptions)
                    DropdownMenuItem(value: p, child: Text(p)),
                ],
                onChanged: (p) {
                  if (p != null) setState(() => _period = p);
                },
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Holdings',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _rows.length; i++) _holdingRow(i),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('add-row'),
                  onPressed: _addRow,
                  icon: const Icon(Icons.add),
                  label: const Text('Add ticker'),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('save-portfolio'),
                onPressed: _saving ? null : _save,
                child: Text(_isEdit ? 'Save changes' : 'Create portfolio'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _holdingRow(int i) {
    final row = _rows[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: row.tickerCtrl,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                UpperCaseTextFormatter(),
                FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9.\-]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Ticker',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: row.weightCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Weight',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close),
            onPressed: _rows.length <= 1 ? null : () => _removeRow(i),
          ),
        ],
      ),
    );
  }
}
