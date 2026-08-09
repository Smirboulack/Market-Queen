import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../i18n/translator.dart';
import '../icons.dart';
import '../theme.dart';
import 'buttons.dart';
import 'chip.dart';
import 'image_drop_grid.dart';

/// A block of the right-hand rail: a heading, an optional line under it, an
/// optional action on the right, and the controls.
///
/// Sections are separated by a rule rather than by being boxed, because the rail
/// is already a panel: cards inside a panel inside a window is one frame too
/// many, and it costs 32px of width the trait pickers need.
class RailSection extends StatefulWidget {
  const RailSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle = '',
    this.trailing,
    this.collapsible = false,
    this.initiallyOpen = true,
    this.first = false,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final List<Widget> children;

  /// Sections that are settings rather than content fold away.
  final bool collapsible;
  final bool initiallyOpen;

  /// The topmost section draws no rule above itself.
  final bool first;

  @override
  State<RailSection> createState() => _RailSectionState();
}

class _RailSectionState extends State<RailSection> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final open = !widget.collapsible || _open;

    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  color: mq.textPrimary,
                  fontSize: MqTheme.fontTitle,
                  fontWeight: FontWeight.w600,
                  letterSpacing: MqTheme.trackTitle,
                  height: MqTheme.lineTight,
                ),
              ),
              if (widget.subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  widget.subtitle,
                  style: TextStyle(
                    color: mq.textTertiary,
                    fontSize: MqTheme.fontSmall,
                    height: MqTheme.lineTight,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (widget.trailing != null) ...[
          const SizedBox(width: 8),
          widget.trailing!,
        ],
        if (widget.collapsible) ...[
          const SizedBox(width: 4),
          MqIconButton(
            icon: open ? 'arrow-up-s-line' : 'arrow-down-s-line',
            onPressed: () => setState(() => _open = !_open),
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.first) ...[
          const SizedBox(height: MqTheme.gapLarge),
          Container(height: 1, color: mq.divider),
          const SizedBox(height: MqTheme.gapLarge),
        ],
        // The whole heading toggles a foldable section, not just the chevron:
        // a 26px target for something you open twenty times a session is mean.
        if (widget.collapsible)
          Pressable(
            onTap: () => setState(() => _open = !_open),
            canRequestFocus: false,
            builder: (context, _) => heading,
          )
        else
          heading,
        if (open) ...[
          const SizedBox(height: MqTheme.gap),
          for (var i = 0; i < widget.children.length; ++i) ...[
            if (i > 0) const SizedBox(height: 10),
            widget.children[i],
          ],
        ],
      ],
    );
  }
}

/// The rail's own picker: the name of the setting above the value it holds, in
/// one box, two across.
///
/// Not [StyledCombo], which is a single line and needs a caption above it -- at
/// 400px wide, six captioned combos in a column is the whole rail. Folding the
/// caption inside the box is what fits six of them into three rows.
class RailPicker extends StatefulWidget {
  const RailPicker({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onPicked,
    this.placeholder = '',
  });

  final String label;
  final List<MenuOption<String>> options;
  final String value;
  final ValueChanged<String> onPicked;

  /// Shown in place of the value when nothing is set.
  final String placeholder;

  @override
  State<RailPicker> createState() => _RailPickerState();
}

class _RailPickerState extends State<RailPicker> {
  bool _open = false;

  String get _currentLabel {
    for (final option in widget.options) {
      if (option.value == widget.value) return option.label;
    }
    return '';
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

    final picked = await showMenu<String>(
      context: context,
      constraints: BoxConstraints(minWidth: box.size.width, maxHeight: 320),
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy,
        overlay.size.width - topLeft.dx - box.size.width,
        0,
      ),
      items: [
        // "Doesn't matter" is an option, not the absence of one: taking a trait
        // back off has to be as easy as putting it on.
        for (final option in [
          MenuOption(tr("doesn't matter"), ''),
          ...widget.options,
        ])
          PopupMenuItem<String>(
            value: option.value,
            height: 34,
            child: Text(
              option.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: option.value == widget.value
                    ? mq.primaryText
                    : mq.textPrimary,
                fontSize: MqTheme.fontLabel,
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

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final current = _currentLabel;

    return Pressable(
      onTap: _showMenu,
      builder: (context, states) {
        // An open menu outranks the pointer: the box stays lit underneath it
        // even though the barrier has taken the hover away.
        final line = _open
            ? mq.primary
            : states.active
            ? mq.borderStrong
            : mq.border;

        return AnimatedContainer(
          duration: _open ? Duration.zero : states.duration,
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: _open || states.active ? mq.surfaceHover : mq.surface,
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall + 2),
            border: Border.all(color: line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: mq.textTertiary,
                        fontSize: MqTheme.fontMicro,
                        height: MqTheme.lineTight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      current.isEmpty ? widget.placeholder : current,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: current.isEmpty
                            ? mq.textTertiary
                            : mq.textPrimary,
                        fontSize: MqTheme.fontLabel,
                        fontWeight: current.isEmpty
                            ? FontWeight.w400
                            : FontWeight.w500,
                        height: MqTheme.lineTight,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              MqIcon(
                'arrow-down-s-line',
                size: 17,
                color: states.active || _open ? mq.textPrimary : mq.textTertiary,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Two [RailPicker]s side by side, which is how all six traits are laid out.
class RailPickerRow extends StatelessWidget {
  const RailPickerRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; ++i) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

/// Where photos of the actor go in: drop them, or browse for them.
///
/// It stays a drop target once it has pictures -- the tiles appear inside it
/// rather than replacing it, so adding a second reference is the same gesture as
/// the first.
class RailDropZone extends StatefulWidget {
  const RailDropZone({
    super.key,
    required this.images,
    required this.onFilesAdded,
    required this.onRemoveRequested,
    this.title = '',
    this.hint = '',
  });

  final List<String> images;
  final ValueChanged<List<String>> onFilesAdded;
  final ValueChanged<int> onRemoveRequested;
  final String title;
  final String hint;

  @override
  State<RailDropZone> createState() => _RailDropZoneState();
}

class _RailDropZoneState extends State<RailDropZone> {
  bool _dragging = false;

  Future<void> _browse() async {
    final files = await openFiles(acceptedTypeGroups: const [imageTypeGroup]);
    if (files.isEmpty) return;
    widget.onFilesAdded([for (final file in files) file.path]);
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final empty = widget.images.isEmpty;

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        final paths = [for (final file in detail.files) file.path];
        if (paths.isNotEmpty) widget.onFilesAdded(paths);
      },
      child: Pressable(
        onTap: _browse,
        focusRadius: MqTheme.radius,
        builder: (context, states) => AnimatedContainer(
          // Drag-over works like hover: instant in, fill and border together,
          // fade only on the way out.
          duration: _dragging ? Duration.zero : states.duration,
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: empty ? 20 : 12),
          decoration: BoxDecoration(
            color: _dragging
                ? mq.primarySubtle
                : states.active
                ? mq.surfaceHover
                : mq.surfaceSecondary,
            borderRadius: BorderRadius.circular(MqTheme.radius),
            border: Border.all(
              color: _dragging
                  ? mq.primary
                  : states.active
                  ? mq.borderStrong
                  : mq.border,
            ),
          ),
          child: empty
              ? Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        MqIcon(
                          'image-add-line',
                          size: 19,
                          color: states.active ? mq.textSecondary : mq.textTertiary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.title,
                          style: TextStyle(
                            color: mq.textPrimary,
                            fontSize: MqTheme.fontBody,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (widget.hint.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        widget.hint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: mq.textTertiary,
                          fontSize: MqTheme.fontSmall,
                        ),
                      ),
                    ],
                  ],
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < widget.images.length; ++i)
                      _Thumb(
                        path: widget.images[i],
                        onRemove: () => widget.onRemoveRequested(i),
                      ),
                    _AddThumb(onTap: _browse),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Thumb extends StatefulWidget {
  const _Thumb({required this.path, required this.onRemove});

  final String path;
  final VoidCallback onRemove;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final fade = _hovered ? Duration.zero : MqTheme.hoverDuration;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: fade,
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: mq.background,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          border: Border.all(color: _hovered ? mq.borderStrong : mq.border),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(MqTheme.radiusSmall - 1),
              child: LocalImage(widget.path),
            ),
            Positioned(
              right: 1,
              top: 1,
              child: IgnorePointer(
                ignoring: !_hovered,
                child: AnimatedOpacity(
                  opacity: _hovered ? 1 : 0,
                  duration: fade,
                  child: MqIconButton(
                    icon: 'close-line',
                    destructive: true,
                    size: 20,
                    onPressed: widget.onRemove,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddThumb extends StatelessWidget {
  const _AddThumb({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        width: 58,
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: states.active ? mq.surfaceHover : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          border: Border.all(
            color: states.active ? mq.borderStrong : mq.border,
          ),
        ),
        child: MqIcon(
          'add-line',
          size: 18,
          color: states.active ? mq.textSecondary : mq.textTertiary,
        ),
      ),
    );
  }
}
