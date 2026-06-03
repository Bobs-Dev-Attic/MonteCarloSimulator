# Results screen redesign — minimize scrolling

## Purpose

Reshape the results screen so a user can see results and tweak inputs
without scrolling on a normal desktop window. Replace the scroll-stacked
"hero summary → fan chart → histogram → summary → controls" layout with
a top-aligned controls panel, a one-row hero strip, and a `TabBar` of
charts that fills the remaining viewport. Replace the sliders with
drag-scrub text fields that double as keyboard-typeable inputs.

## Non-goals

- Touch-first drag interaction (mobile/web-touch will type into the
  field; the scrub handle is a mouse affordance).
- Persisting the active tab to Firestore or `SharedPreferences`.
- Custom tab-transition animations beyond Material defaults.
- Replacing widgets on screens other than `simulation_form_screen.dart`
  and `results_screen.dart`.

## Information architecture

```
┌────────────────────────────────────────────────────────────────┐
│  ←  Portfolio Results                                          │  AppBar (existing)
├────────────────────────────────────────────────────────────────┤
│  [Beginning $10,000] [Return 7.0%] [Vol 15.0%] [Years 10]      │  ScrubField row 1
│  [# sims 10,000]  [⏵ Compare with GARCH(1,1)]                  │  ScrubField row 2 + toggle
│                                          [ Reset ] [ Rerun ]   │  Action row
├────────────────────────────────────────────────────────────────┤
│  Median $19,521 │ 95% VaR $4,213 │ 5–95 $8,210 → $32,418       │  Hero pill strip (one row)
├────────────────────────────────────────────────────────────────┤
│ [ Fan chart ] [ Histogram ] [ Summary ]                        │  TabBar
│ ┌────────────────────────────────────────────────────────────┐ │
│ │                                                            │ │
│ │              tab body (full remaining height)              │ │
│ │                                                            │ │
│ └────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────┘
```

## Component-level design

### `ScrubField` (new widget — `lib/widgets/scrub_field.dart`)

A `StatefulWidget` that wraps `TextFormField`. Public interface:

```dart
class ScrubField extends StatefulWidget {
  const ScrubField({
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
  final ScrubKind kind;   // years, integer, percent, money
  final String? suffixText;
  final double? minValue;
  final double? maxValue;
}

enum ScrubKind { integer, years, percent, money }
```

**Internal behavior:**
- A `TextEditingController` is the single source of truth for the
  displayed string. On every text change, the field parses the value,
  clamps it to `[minValue, maxValue]` if set, and fires `onChanged`.
- When `widget.value` changes from the outside (e.g. drag updated it),
  the controller text is reset to match.
- To the right of the input, a `MouseRegion` + `GestureDetector` wraps
  an `Icon(Icons.drag_indicator, size: 18)`. The `MouseRegion` shows
  `SystemMouseCursors.resizeLeftRight` on hover.
- `onHorizontalDragUpdate.delta.dx` accumulates pixels since drag start;
  the per-pixel step is determined by `kind` and `value`:

  | `kind`   | step per pixel               | `Shift` (×10)     | `Alt` (÷10)       |
  |----------|------------------------------|-------------------|-------------------|
  | integer  | 1                            | 10                | (no-op, min 1)    |
  | years    | 1                            | 10                | (no-op, min 1)    |
  | percent  | 0.1 (as displayed percent)   | 1.0               | 0.01              |
  | money    | max(1, 0.01 × current_value) | ×10               | ÷10               |

- Hard `HardwareKeyboard.instance.isShiftPressed` / `isAltPressed` is
  read every drag tick.
- The new value is clamped against `minValue`/`maxValue` and passed to
  `onChanged`.

**Why this works as a drop-in replacement:**
- The widget renders as a `TextFormField` with a suffix icon — usable
  from keyboard, screen reader, and copy/paste exactly like the
  existing `_numField`.
- The drag handle is opt-in: ignoring the icon yields normal text-field
  behavior.

### `ResultsTabs` (new widget — `lib/widgets/results_tabs.dart`)

A `StatefulWidget` that owns a `TabController` with three tabs. Body
is an `Expanded` `TabBarView` containing three sub-widgets the screen
provides:

```dart
class ResultsTabs extends StatefulWidget {
  const ResultsTabs({
    required this.fanTab,
    required this.histogramTab,
    required this.summaryTab,
  });
  // ...
}
```

The tab labels are static (`Fan chart`, `Histogram`, `Summary`). The
widget is intentionally dumb about comparison mode — the parent screen
constructs the tab bodies with comparison-aware content already inside.

### `results_screen.dart` (modified)

- Drop the `ListView` outer scroll container; replace with a `Column`:
  - Inputs panel (`_InputsPanel` private widget) — Wrap of `ScrubField`s
    plus the `Compare with GARCH` `SwitchListTile.adaptive`.
  - Action row — `Row(MainAxisAlignment.end, children: [Reset, Rerun])`.
  - Hero strip — the existing `_InfoPill`s reused, packed into a single
    `Row` (overflow → wrap to two rows on narrow widths).
  - `ResultsTabs(...)` wrapped in `Expanded` so it fills remaining
    height.
- Three tab-body builders on `_ResultsScreenState`:
  - `_buildFanTab()` — calls existing `_resultSection` once when no
    comparison, twice (stacked) when comparison is present, but only
    the fan chart + label, no histogram or summary card.
  - `_buildHistogramTab()` — same pattern with just the
    `TerminalHistogram`.
  - `_buildSummaryTab()` — single `SummaryStatsCard` when no
    comparison; two cards in a `Row` on wide screens, `Column` on
    narrow (`LayoutBuilder` decides).
- Delete the existing `_resultSection` body composition and split into
  `_fanSection`, `_histogramSection`, `_summarySection` private helpers
  so each tab can include only its own widget without duplicating the
  shared y-range computation.
- Delete `_ParameterSlider` (replaced by `ScrubField`).
- Keep `_HeroSummary` but compress to a single `Row` of three `_InfoPill`s
  with no wrap initially; wrap to two rows below a 600 px breakpoint.

### `simulation_form_screen.dart` (modified)

- Replace every `_numField` with a `ScrubField` of the appropriate
  `ScrubKind`.
- Pack the GBM tab's four parameter fields into a `Wrap` (1, 2, or 4
  columns by available width). The "Compare with GARCH(1,1)"
  `SwitchListTile` stays inline below the parameter fields.
- Same treatment for the retirement tab's eight fields.
- `_numField` and its supporting validators come out.

### Layout heuristics

A small helper `int _columnsFor(double width)` returns:
- `4` if width ≥ 720
- `2` if width ≥ 420
- `1` otherwise.

`Wrap(spacing: 12, runSpacing: 12, ...)` with each `ScrubField`
constrained to `SizedBox(width: (panelWidth - gutters) / cols)` gives
the responsive packing without a `LayoutBuilder` per field. The
`LayoutBuilder` lives at the inputs panel level.

## Tab-body composition when comparison is on

The existing `_sharedYRangeWithComparison()` helper from
`results_screen.dart` is preserved. The fan tab calls it and passes the
shared range to both `FanChart`s. The histogram tab does NOT share a
range (counts and bin edges differ naturally; visually independent is
fine).

For the summary tab, side-by-side rendering uses `LayoutBuilder`:
```
if (width >= 600) Row([gbmCard, gap, garchCard])
else              Column([gbmCard, gap, garchCard])
```

## Testing

### Unit / widget tests (new — `test/scrub_field_test.dart`)

1. **Drag right increases value, drag left decreases.** Pump a
   `ScrubField(kind: integer, value: 10, ...)`, simulate a
   `GestureDetector` `onHorizontalDragUpdate` of `+5 px`, expect
   `onChanged` to fire with `15`.
2. **Money kind scales step by current value.** Drag `+10 px` on
   `value: 10_000` produces `~11_000` (1% × 10 px × 10_000); same
   drag on `value: 500_000` produces `~550_000`.
3. **Min/max clamp.** Drag past `maxValue` clamps and emits the bound.
4. **Typing into the field still works** and emits `onChanged` with the
   typed value.
5. **Empty / invalid text** does not throw; `onChanged` is not called.

### Widget test (new — `test/results_screen_tabs_test.dart`)

1. Pump `ResultsScreen` with a non-comparison result; expect
   `find.byType(TabBar)` and three `Tab` widgets.
2. Tap the `Histogram` tab; expect `find.byType(TerminalHistogram)` is
   visible and `find.byType(FanChart)` is not.
3. Pump with a comparison result; switch to `Fan chart` tab; expect
   exactly two `FanChart`s in the tab body.

### Manual

- Resize the Chrome window; inputs reflow 4 → 2 → 1 columns.
- Drag the grip on every field type; verify sensitivity feels right.
- Run with comparison off and on; flip tabs without losing inputs.

## Risks and open questions

- **Drag start within the field text area.** If a user click-drags on
  the text itself (not the grip icon), should that select text (current
  TextFormField behavior) or scrub? Spec choice: **text selection
  wins** — the grip icon is the only scrub target. This keeps the
  field's keyboard / copy-paste UX intact.
- **Slider removal on the rerun panel.** The results screen currently
  exposes inputs the form screen doesn't (e.g., `Beginning value` for
  rerun). All current sliders map cleanly to `ScrubField` kinds; no
  expressivity is lost.
- **Comparison summary side-by-side fit.** On a 600–800 px window two
  `SummaryStatsCard`s side-by-side may be cramped. The spec says
  `≥600 px` for side-by-side; if cramped in practice, widen the
  breakpoint in a follow-up.
- **The action row separation.** With drag-scrub fields available on
  every input, some users may forget to click `Rerun` after editing.
  Out of scope: live-rerun-on-edit (would burn function invocations
  on every drag tick).
