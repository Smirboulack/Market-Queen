import 'package:flutter/material.dart';

import '../theme.dart';

/// The frame every text input sits in: hover and focus move the border, and
/// only the way back to rest fades.
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
        ? mq.accent
        : (hovered && !readOnly)
            ? mq.borderStrong
            : mq.border;

    return AnimatedContainer(
      duration: MqTheme.hoverDuration,
      decoration: BoxDecoration(
        color: fill ?? (readOnly ? mq.background : mq.surfaceAlt),
        borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        border: Border.all(color: line),
      ),
      child: child,
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
    this.onChanged,
    this.onEditingComplete,
  });

  final String label;
  final String placeholder;
  final String hint;
  final TextEditingController? controller;
  final bool readOnly;
  final bool obscure;
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
          Text(
            widget.label,
            style: TextStyle(
              color: mq.textDim,
              fontSize: MqTheme.fontSmall,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
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
                readOnly: widget.readOnly,
                obscureText: widget.obscure,
                onChanged: widget.onChanged,
                onSubmitted: widget.onEditingComplete,
                cursorColor: mq.accent,
                style: TextStyle(color: mq.text, fontSize: MqTheme.fontBody),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  hintText: widget.placeholder,
                  hintStyle:
                      TextStyle(color: mq.textFaint, fontSize: MqTheme.fontBody),
                ),
              ),
            ),
          ),
        ),
        if (widget.hint.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            widget.hint,
            style: TextStyle(color: mq.textFaint, fontSize: MqTheme.fontSmall),
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
          Text(
            widget.label,
            style: TextStyle(
              color: mq.textDim,
              fontSize: MqTheme.fontSmall,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
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
                cursorColor: mq.accent,
                style: TextStyle(color: mq.text, fontSize: MqTheme.fontBody),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(8),
                  hintText: widget.placeholder,
                  hintStyle:
                      TextStyle(color: mq.textFaint, fontSize: MqTheme.fontBody),
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
            Text(
              label,
              style: TextStyle(
                color: mq.textDim,
                fontSize: MqTheme.fontSmall,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              value.toStringAsFixed(decimals),
              style: TextStyle(
                color: mq.text,
                fontSize: MqTheme.fontSmall,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: mq.accent,
            inactiveTrackColor: mq.surfaceHover,
            thumbColor: mq.surface,
            overlayShape: SliderComponentShape.noOverlay,
            thumbShape: _RingThumb(mq.accent),
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
            style: TextStyle(color: mq.textFaint, fontSize: MqTheme.fontSmall),
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

/// Checkbox in the app's look: hover ring on the box, pointing-hand cursor.
class StyledCheck extends StatefulWidget {
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
  State<StyledCheck> createState() => _StyledCheckState();
}

class _StyledCheckState extends State<StyledCheck> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onChanged(!widget.checked),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: MqTheme.hoverDuration,
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: widget.checked ? mq.accent : mq.surfaceAlt,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: widget.checked
                      ? mq.accent
                      : _hovered
                          ? mq.borderStrong
                          : mq.border,
                ),
              ),
              child: widget.checked
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                widget.text,
                style: TextStyle(
                  color: mq.textDim,
                  fontSize: MqTheme.fontSmall + 1,
                ),
              ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: mq.surfaceAlt,
        borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        border: Border.all(color: mq.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _Segment(
                label: option.label,
                selected: option.value == value,
                onTap: () => onPicked(option.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          // Segments touch each other, so hover snaps both ways: sliding across
          // the pill never lights two.
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.selected
                ? mq.accent
                : _hovered
                    ? mq.surfaceHover
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall - 2),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.selected ? Colors.white : mq.textDim,
              fontSize: MqTheme.fontSmall + 1,
              fontWeight: widget.selected ? FontWeight.w600 : FontWeight.normal,
            ),
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
  bool _hovered = false;
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

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _showMenu,
        child: AnimatedContainer(
          duration: MqTheme.hoverDuration,
          width: widget.width,
          height: MqTheme.fieldHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _open ? mq.surfaceHover : mq.surfaceAlt,
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
            border: Border.all(
              color: _open
                  ? mq.accent
                  : _hovered
                      ? mq.borderStrong
                      : mq.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  current,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: mq.text, fontSize: MqTheme.fontBody),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: _hovered || _open ? mq.text : mq.textDim,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu() async {
    final mq = context.mq;
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final topLeft =
        box.localToGlobal(Offset(0, box.size.height + 4), ancestor: overlay);

    setState(() => _open = true);

    final picked = await showMenu<T>(
      context: context,
      color: mq.surface,
      surfaceTintColor: Colors.transparent,
      constraints: BoxConstraints(minWidth: box.size.width, maxHeight: 320),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        side: BorderSide(color: mq.borderStrong),
      ),
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
                color: option.value == widget.value ? mq.accent : mq.text,
                fontSize: MqTheme.fontBody,
                fontWeight: option.value == widget.value
                    ? FontWeight.w600
                    : FontWeight.normal,
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
          const SizedBox(height: 5),
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
