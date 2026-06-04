import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/investment.dart';
import '../state/providers.dart';
import '../widgets/scrub_field.dart';

/// Create / edit / delete a single holding in a customer's investments
/// database. Mirrors [MemberFormScreen]; intentionally minimal (ticker +
/// quantity) since price/value come live from yfinance.
class InvestmentFormScreen extends ConsumerStatefulWidget {
  const InvestmentFormScreen({
    super.key,
    required this.householdId,
    this.existing,
  });

  final String householdId;
  final Investment? existing;

  @override
  ConsumerState<InvestmentFormScreen> createState() =>
      _InvestmentFormScreenState();
}

class _InvestmentFormScreenState extends ConsumerState<InvestmentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tickerController;
  double _quantity = 0;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _tickerController = TextEditingController(text: e?.ticker ?? '');
    _quantity = e?.quantity ?? 0;
  }

  @override
  void dispose() {
    _tickerController.dispose();
    super.dispose();
  }

  InvestmentDraft _buildDraft() {
    return InvestmentDraft(
      ticker: _tickerController.text.trim().toUpperCase(),
      quantity: _quantity,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_quantity <= 0) {
      setState(() => _error = 'Quantity must be greater than zero');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final svc = ref.read(investmentServiceProvider);
      if (_isEdit) {
        await svc.updateInvestment(
          householdId: widget.householdId,
          investmentId: widget.existing!.id,
          draft: _buildDraft(),
        );
      } else {
        final advisor = ref.read(currentAdvisorUidProvider);
        if (advisor == null) {
          throw StateError('Not signed in');
        }
        await svc.createInvestment(
          householdId: widget.householdId,
          advisorUid: advisor,
          draft: _buildDraft(),
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
        title: const Text('Delete this holding?'),
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
      await ref.read(investmentServiceProvider).deleteInvestment(
            householdId: widget.householdId,
            investmentId: widget.existing!.id,
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
        title: Text(_isEdit ? 'Edit holding' : 'New holding'),
        actions: [
          if (_isEdit)
            IconButton(
              key: const ValueKey('delete-investment'),
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
                key: const ValueKey('ticker-field'),
                controller: _tickerController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  UpperCaseTextFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9.\-]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Ticker symbol',
                  hintText: 'e.g. AAPL',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Ticker is required'
                    : null,
              ),
              const SizedBox(height: 12),
              ScrubField(
                key: const ValueKey('quantity-field'),
                label: 'Quantity (shares)',
                value: _quantity,
                kind: ScrubKind.money,
                suffixText: 'shares',
                minValue: 0,
                onChanged: (v) => setState(() => _quantity = v),
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const ValueKey('save-investment'),
                onPressed: _saving ? null : _save,
                child: Text(_isEdit ? 'Save changes' : 'Add holding'),
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
}

/// Upper-cases ticker input as the user types so the stored symbol matches
/// what Yahoo Finance expects.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
