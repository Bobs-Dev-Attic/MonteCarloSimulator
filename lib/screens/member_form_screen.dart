import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/member.dart';
import '../state/providers.dart';
import '../widgets/nullable_scrub_field.dart';
import '../widgets/relation_labels.dart';
import '../widgets/scrub_field.dart';

class MemberFormScreen extends ConsumerStatefulWidget {
  const MemberFormScreen({
    super.key,
    required this.householdId,
    this.existing,
  });

  final String householdId;
  final Member? existing;

  @override
  ConsumerState<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends ConsumerState<MemberFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late MemberRelation _relation;
  DateTime? _dob;
  double? _currentAge;
  double? _retirementAge;
  double? _lifeExpectancy;
  double? _annualIncome;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _relation = e?.relation ?? MemberRelation.primary;
    _dob = e?.dateOfBirth;
    _currentAge = e?.currentAge?.toDouble();
    _retirementAge = e?.retirementAge?.toDouble();
    _lifeExpectancy = e?.lifeExpectancy?.toDouble();
    _annualIncome = e?.annualIncome;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1900, 1, 1),
      lastDate: now,
      initialDate: _dob ?? DateTime(now.year - 30, now.month, now.day),
    );
    if (picked != null) {
      setState(() => _dob = picked);
    }
  }

  MemberDraft _buildDraft() {
    return MemberDraft(
      name: _nameController.text.trim(),
      relation: _relation,
      dateOfBirth: _dob,
      currentAge: _currentAge?.round(),
      retirementAge: _retirementAge?.round(),
      lifeExpectancy: _lifeExpectancy?.round(),
      annualIncome: _annualIncome,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final svc = ref.read(memberServiceProvider);
      if (_isEdit) {
        await svc.updateMember(
          householdId: widget.householdId,
          memberId: widget.existing!.id,
          draft: _buildDraft(),
        );
      } else {
        final advisor = ref.read(currentAdvisorUidProvider);
        if (advisor == null) {
          throw StateError('Not signed in');
        }
        await svc.createMember(
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
        title: const Text('Delete this member?'),
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
    try {
      await ref.read(memberServiceProvider).deleteMember(
            householdId: widget.householdId,
            memberId: widget.existing!.id,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit member' : 'New member'),
        actions: [
          if (_isEdit)
            IconButton(
              key: const ValueKey('delete-member'),
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
                key: const ValueKey('name-field'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<MemberRelation>(
                key: const ValueKey('relation-field'),
                initialValue: _relation,
                decoration: const InputDecoration(
                  labelText: 'Relation',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final r in MemberRelation.values)
                    DropdownMenuItem(value: r, child: Text(relationLabel(r))),
                ],
                onChanged: (r) {
                  if (r != null) setState(() => _relation = r);
                },
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date of birth',
                  border: OutlineInputBorder(),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _dob == null
                            ? '—'
                            : '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('dob-field'),
                      onPressed: _pickDob,
                      child: Text(_dob == null ? 'Set' : 'Change'),
                    ),
                    if (_dob != null)
                      IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _dob = null),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              NullableScrubField(
                key: const ValueKey('age-field'),
                label: 'Current age',
                value: _currentAge,
                kind: ScrubKind.integer,
                minValue: 0,
                maxValue: 120,
                initialIfSet: 40,
                onChanged: (v) => setState(() => _currentAge = v),
              ),
              const SizedBox(height: 12),
              NullableScrubField(
                key: const ValueKey('retirement-field'),
                label: 'Retirement age',
                value: _retirementAge,
                kind: ScrubKind.years,
                minValue: 0,
                maxValue: 100,
                initialIfSet: 65,
                onChanged: (v) => setState(() => _retirementAge = v),
              ),
              const SizedBox(height: 12),
              NullableScrubField(
                key: const ValueKey('lifeexp-field'),
                label: 'Life expectancy',
                value: _lifeExpectancy,
                kind: ScrubKind.years,
                minValue: 0,
                maxValue: 120,
                initialIfSet: 90,
                onChanged: (v) => setState(() => _lifeExpectancy = v),
              ),
              const SizedBox(height: 12),
              NullableScrubField(
                key: const ValueKey('income-field'),
                label: 'Annual income',
                value: _annualIncome,
                kind: ScrubKind.money,
                minValue: 0,
                suffixText: 'USD',
                initialIfSet: 100000,
                onChanged: (v) => setState(() => _annualIncome = v),
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const ValueKey('save-member'),
                onPressed: _saving ? null : _save,
                child: Text(_isEdit ? 'Save changes' : 'Add member'),
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
