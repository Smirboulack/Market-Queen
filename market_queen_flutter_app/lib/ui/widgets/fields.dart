import 'package:flutter/material.dart';

import '../theme.dart';
import 'buttons.dart';

/// The frame every text input sits in: hover and focus move the border, and
/// only the way back to rest fades.
///
/// Focus adds a ring outside the border rather than thickening it. A border
/// that grows from 1px to 2px on focus moves every character in the field by
/// half a pixel, and on a field you are typing into that is the one place a
/// wobble is guaranteed to be noticed.
class FieldFrame extends StatelessWidget {
  const FieldFrame({
    super.key,
    required this.child,
    required this.focused,
    required this.hovered,
    this.readOnly = false,
    this.fill,
  });

  final Widget child;
  final bool focused;
  final bool hovered;
  final bool readOnly;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final line = focused
        ? mq.primary
        : (hovered && !readOnly)
        ? mq.borderStrong
        : mq.border;

    return AnimatedContainer(
      duration: focused || hovered ? Duration.zero : MqTheme.hoverDuration,
      decoration: BoxDecoration(
        color: fill ?? (readOnly ? mq.background : mq.surfaceSecondary),
        borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        border: Border.all(color: line),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: mq.focusRing.withValues(alpha: 0.22),
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

/// The caption above a field. One weight, one colour, everywhere.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.mq.textSecondary,
        fontSize: MqTheme.fontSmall,
        fontWeight: FontWeight.w500,
        letterSpacing: MqTheme.trackSmall,
      ),
    );
  }
}

/// A single-line text field with an optional label above and hint below.
class LabeledField extends StatefulWidget {
  const LabeledField({
    super.key,
    this.label = '',
    this.placeholder = '',
    this.hint = '',
    this.controller,
    this.readOnly = false,
    this.obscure = false,
    this.autofocus = false,
    this.onChanged,
    this.onEditingComplete,
  });

  final String label;
  final String placeholder;
  final String hint;
  final TextEditingController? controller;
  final bool readOnly;
  final bool obscure;

  /// For the one field a modal opens onto: a dialog that asks for a name and
  /// then makes you click into it is a dialog with an extra step.
  final bool autofocus;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onEditingComplete;

  @override
  State<LabeledField> createState() => _LabeledFieldState();
}

class _LabeledFieldState extends State<LabeledField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      // Committing on focus loss is what `onEditingFinished` did in QML.
      if (!_focus.hasFocus) widget.onEditingComplete?.call(_controller.text);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.isNotEmpty) ...[
          FieldLabel(widget.label),
          const SizedBox(height: 6),
        ],
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: FieldFrame(
            focused: _focus.hasFocus,
            hovered: _hovered,
            readOnly: widget.readOnly,
            child: SizedBox(
              height: MqTheme.fieldHeight,
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                readOnly: widget.readOnly,
                obscureText: widget.obscure,
                onChanged: widget.onChanged,
                onSubmitted: widget.onEditingComplete,
                cursorColor: mq.primary,
                style: TextStyle(
                  color: widget.readOnly ? mq.textSecondary : mq.textPrimary,
                  fontSize: MqTheme.fontBody,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 9,
                  ),
                  hintText: widget.placeholder,
                  hintStyle: TextStyle(
                    color: mq.textTertiary,
                    fontSize: MqTheme.fontBody,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.hint.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            widget.hint,
            style: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontSmall,
            ),
          ),
        ],
      ],
    );
  }
}

/// A multi-line field that grows with its content instead of scrolling inside
/// itself: an inner scroll view would swallow the wheel and freeze the page
/// scroll whenever the pointer happened to be over a text box.
class LabeledArea extends StatefulWidget {
  const LabeledArea({
    super.key,
    this.label = '',
    this.placeholder = '',
    this.areaHeight = 96,
    this.controller,
    this.onChanged,
  });

  final String label;
  final String placeholder;
  final double areaHeight;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  State<LabeledArea> createState() => _LabeledAreaState();
}

class _LabeledAreaState extends State<LabeledArea> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.isNotEmpty) ...[
          FieldLabel(widget.label),
          const SizedBox(height: 6),
        ],
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: FieldFrame(
            focused: _focus.hasFocus,
            hovered: _hovered,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: widget.areaHeight),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                maxLines: null,
                onChanged: widget.onChanged,
                cursorColor: mq.primary,
                style: TextStyle(
                  color: mq.textPrimary,
                  fontSize: MqTheme.fontBody,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(10),
                  hintText: widget.placeholder,
                  hintStyle: TextStyle(
                    color: mq.textTertiary,
                    fontSize: MqTheme.fontBody,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A voice setting.
///
/// The number is always on screen next to the label: these four values are the
/// difference between a read that sounds human and one that sounds like an
/// announcer, and "somewhere left of centre" is not something you can come back
/// to tomorrow and reproduce.
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.from = 0.0,
    this.to = 1.0,
    this.decimals = 2,
    this.hint = '',
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double from;
  final double to;
  final int decimals;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            FieldLabel(label),
            const Spacer(),
            Text(
              value.toStringAsFixed(decimals),
              style: TextStyle(
                color: mq.textPrimary,
                fontSize: MqTheme.fontSmall,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: mq.primary,
            inactiveTrackColor: mq.surfaceTertiary,
            thumbColor: mq.surface,
            overlayShape: SliderComponentShape.noOverlay,
            thumbShape: _RingThumb(mq.primary),
          ),
          child: Slider(
            value: value.clamp(from, to),
            min: from,
            max: to,
            onChanged: onChanged,
          ),
        ),
        if (hint.isNotEmpty)
          Text(
            hint,
            style: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontSmall,
            ),
          ),
      ],
    );
  }
}

class _RingThumb extends SliderComponentShape {
  const _RingThumb(this.ring);

  final Color ring;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(16, 16);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(
      center,
      8,
      Paint()..color = sliderTheme.thumbColor ?? Colors.white,
    );
    canvas.drawCircle(
      center,
      7,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}

/// Checkbox in the app's look: the whole row is the target, not the 16px box.
class StyledCheck extends StatelessWidget {
  const StyledCheck({
    super.key,
    required this.text,
    required this.checked,
    required this.onChanged,
  });

  final String text;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: () => onChanged(!checked),
      builder: (context, states) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: states.duration,
            width: 17,
            height: 17,
            decoration: BoxDecoration(
              color: checked
                  ? (states.pressed
                        ? mq.primaryActive
                        : states.hovered
                        ? mq.primaryHover
                        : mq.primary)
                  : states.active
                  ? mq.surfaceHover
                  : mq.surfaceSecondary,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: checked
                    ? Colors.transparent
                    : states.active
                    ? mq.borderStrong
                    : mq.border,
              ),
            ),
            child: checked
                ? Icon(Icons.check, size: 12, color: mq.onPrimary)
                : null,
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: states.active ? mq.textPrimary : mq.textSecondary,
                fontSize: MqTheme.fontLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two or three mutually exclusive options in one pill.
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onPicked,
  });

  final List<MenuEntry<T>> options;
  final T value;
  final ValueChanged<T> onPicked;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        border: Border.all(color: mq.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            _Segment(
              label: option.label,
              selected: option.value == value,
              onTap: () => onPicked(option.value),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      // Segments touch each other, so hover snaps both ways: sliding across
      // the pill never lights two.
      snap: true,
      focusRadius: MqTheme.radiusSmall - 2,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // The selected segment is raised, not painted: this control is a
          // setting, and a pink one would outrank the Generate button.
          color: selected
              ? mq.surfaceRaised
              : states.active
              ? mq.surfaceHover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall - 2),
          border: Border.all(color: selected ? mq.border : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? mq.textPrimary
                : states.active
                ? mq.textPrimary
                : mq.textSecondary,
            fontSize: MqTheme.fontLabel,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            letterSpacing: MqTheme.trackSmall,
          ),
        ),
      ),
    );
  }
}

class MenuEntry<T> {
  const MenuEntry(this.label, this.value);

  final String label;
  final T value;
}

/// Fixed-choice picker.
///
/// There is deliberately no inline editing: free text lives in its own field
/// next to the combo (see [PickerWithCustom]).
class StyledCombo<T> extends StatefulWidget {
  const StyledCombo({
    super.key,
    required this.options,
    required this.value,
    required this.onPicked,
    this.width,
  });

  final List<MenuEntry<T>> options;
  final T? value;
  final ValueChanged<T> onPicked;
  final double? width;

  @override
  State<StyledCombo<T>> createState() => _StyledComboState<T>();
}

class _StyledComboState<T> extends State<StyledCombo<T>> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    var current = '';
    for (final option in widget.options) {
      if (option.value == widget.value) {
        current = option.label;
        break;
      }
    }

    return Pressable(
      onTap: _showMenu,
      builder: (context, states) {
        // An open menu outranks the pointer: the combo stays lit underneath it
        // even though the barrier has taken the hover away.
        final line = _open
            ? mq.primary
            : states.active
            ? mq.borderStrong
            : mq.border;

        return AnimatedContainer(
          duration: _open ? Duration.zero : states.duration,
          width: widget.width,
          height: MqTheme.fieldHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _open || states.active
                ? mq.surfaceHover
                : mq.surfaceSecondary,
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
            border: Border.all(color: line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  current,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mq.textPrimary,
                    fontSize: MqTheme.fontBody,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: states.active || _open
                    ? mq.textPrimary
                    : mq.textTertiary,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showMenu() async {
    final mq = context.mq;
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final topLeft = box.localToGlobal(
      Offset(0, box.size.height + 4),
      ancestor: overlay,
    );

    setState(() => _open = true);

    final picked = await showMenu<T>(
      context: context,
      constraints: BoxConstraints(minWidth: box.size.width, maxHeight: 320),
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy,
        overlay.size.width - topLeft.dx - box.size.width,
        0,
      ),
      items: [
        for (final option in widget.options)
          PopupMenuItem<T>(
            value: option.value,
            height: 34,
            child: Text(
              option.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: option.value == widget.value
                    ? mq.primaryText
                    : mq.textPrimary,
                fontSize: MqTheme.fontBody,
                fontWeight: option.value == widget.value
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ),
      ],
    );

    if (!mounted) return;
    setState(() => _open = false);
    if (picked != null) widget.onPicked(picked);
  }
}

/// A fixed list of choices, plus a last "Other..." entry that reveals a
/// free-text field. Everything the user picks is a real option; typing is
/// opt-in, so the combo itself stays a plain click target.
class PickerWithCustom extends StatefulWidget {
  const PickerWithCustom({
    super.key,
    required this.options,
    required this.value,
    required this.onValueEdited,
    this.customLabel = '',
    this.customPlaceholder = '',
  });

  final List<MenuEntry<String>> options;
  final String value;
  final ValueChanged<String> onValueEdited;
  final String customLabel;
  final String customPlaceholder;

  @override
  State<PickerWithCustom> createState() => _PickerWithCustomState();
}

class _PickerWithCustomState extends State<PickerWithCustom> {
  static const _customToken = '__custom__';

  final TextEditingController _custom = TextEditingController();
  bool _isCustom = false;

  @override
  void initState() {
    super.initState();
    _sync(widget.value);
  }

  @override
  void didUpdateWidget(PickerWithCustom oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && widget.value != _custom.text) {
      _sync(widget.value);
    }
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  /// Selects [value] if it is one of the options, otherwise drops it into the
  /// free-text field so a saved custom value survives a restart.
  void _sync(String value) {
    final known = widget.options.any((option) => option.value == value);
    _isCustom = value.isNotEmpty && !known;
    if (_isCustom) _custom.text = value;
  }

  @override
  Widget build(BuildContext context) {
    final entries = [
      ...widget.options,
      MenuEntry(widget.customLabel, _customToken),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StyledCombo<String>(
          options: entries,
          value: _isCustom ? _customToken : widget.value,
          onPicked: (picked) {
            setState(() => _isCustom = picked == _customToken);
            // The custom token is internal and must never leak out as a value.
            widget.onValueEdited(_isCustom ? _custom.text.trim() : picked);
          },
        ),
        if (_isCustom) ...[
          const SizedBox(height: 6),
          LabeledField(
            controller: _custom,
            placeholder: widget.customPlaceholder,
            onChanged: (text) => widget.onValueEdited(text.trim()),
          ),
        ],
      ],
    );
  }
}
