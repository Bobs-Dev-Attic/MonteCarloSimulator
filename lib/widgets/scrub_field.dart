import 'package:flutter/material.dart';

/// Family of value units a [ScrubField] can carry. Drives per-pixel
/// drag sensitivity and (later) display formatting.
enum ScrubKind { integer, years, percent, money }

/// A numeric text input with a drag handle on the right.
///
/// Typing edits the value as a normal [TextFormField]. Horizontally
/// dragging the trailing grip icon scrubs the numeric value at a
/// sensitivity that depends on [kind].
class ScrubField extends StatefulWidget {
  const ScrubField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.kind,
    this.suffixText,
    this.minValue,
    this.maxValue,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ScrubKind kind;
  final String? suffixText;
  final double? minValue;
  final double? maxValue;

  @override
  State<ScrubField> createState() => _ScrubFieldState();
}

class _ScrubFieldState extends State<ScrubField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
  }

  @override
  void didUpdateWidget(covariant ScrubField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) {
      final formatted = _format(widget.value);
      if (_controller.text != formatted) {
        _controller.text = formatted;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _format(double v) {
    switch (widget.kind) {
      case ScrubKind.integer:
      case ScrubKind.years:
        return v.round().toString();
      case ScrubKind.percent:
      case ScrubKind.money:
        return v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
    }
  }

  double _clamp(double v) {
    if (widget.minValue != null && v < widget.minValue!) return widget.minValue!;
    if (widget.maxValue != null && v > widget.maxValue!) return widget.maxValue!;
    return v;
  }

  void _onTextChanged(String text) {
    final parsed = double.tryParse(text);
    if (parsed == null) return;
    final clamped = _clamp(parsed);
    widget.onChanged(clamped);
  }

  double _stepPerPixel() {
    switch (widget.kind) {
      case ScrubKind.integer:
      case ScrubKind.years:
        return 1.0;
      case ScrubKind.percent:
        return 0.1;
      case ScrubKind.money:
        final v = widget.value.abs();
        return v < 100 ? 1.0 : v * 0.01;
    }
  }

  double _accumDx = 0.0;
  double _startValue = 0.0;

  void _onDragStart(DragStartDetails _) {
    _accumDx = 0.0;
    _startValue = widget.value;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _accumDx += details.delta.dx;
    final next = _clamp(_startValue + _accumDx * _stepPerPixel());
    if (next == widget.value) return;
    widget.onChanged(next);
  }

  void _onPointerMove(PointerMoveEvent event) {
    _accumDx += event.delta.dx;
    final next = _clamp(_startValue + _accumDx * _stepPerPixel());
    if (next == widget.value) return;
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _controller,
      onChanged: _onTextChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.suffixText,
        suffixIcon: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            key: const ValueKey('scrub-handle'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            child: Listener(
              onPointerDown: (_) {
                _accumDx = 0.0;
                _startValue = widget.value;
              },
              onPointerMove: _onPointerMove,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.drag_indicator,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
