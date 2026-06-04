import 'package:flutter/material.dart';

import 'scrub_field.dart';

/// Wraps [ScrubField] so callers can model an "unset" state distinctly
/// from a typed-or-scrubbed zero. The user opts the field into a value
/// by tapping a "Set" affordance; once set, the field behaves like a
/// normal [ScrubField]. Tapping "Clear" returns to the unset state.
class NullableScrubField extends StatefulWidget {
  const NullableScrubField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.kind,
    this.suffixText,
    this.minValue,
    this.maxValue,
    this.initialIfSet = 0,
  });

  final String label;
  final double? value;
  final ValueChanged<double?> onChanged;
  final ScrubKind kind;
  final String? suffixText;
  final double? minValue;
  final double? maxValue;

  /// Default numeric value used the first time the user opts in.
  final double initialIfSet;

  @override
  State<NullableScrubField> createState() => _NullableScrubFieldState();
}

class _NullableScrubFieldState extends State<NullableScrubField> {
  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    if (v == null) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: Row(
          children: [
            const Expanded(child: Text('—')),
            TextButton(
              key: ValueKey('${widget.label}-set'),
              onPressed: () => widget.onChanged(widget.initialIfSet),
              child: const Text('Set'),
            ),
          ],
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: ScrubField(
            label: widget.label,
            value: v,
            onChanged: widget.onChanged,
            kind: widget.kind,
            suffixText: widget.suffixText,
            minValue: widget.minValue,
            maxValue: widget.maxValue,
          ),
        ),
        IconButton(
          key: ValueKey('${widget.label}-clear'),
          tooltip: 'Clear',
          icon: const Icon(Icons.close),
          onPressed: () => widget.onChanged(null),
        ),
      ],
    );
  }
}
