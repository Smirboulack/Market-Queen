import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../i18n/translator.dart';
import '../icons.dart';
import '../theme.dart';
import 'buttons.dart';
import 'fields.dart';

/// Opens something over the page, with the page blurred behind it.
///
/// The blur is the point: a modal that only dims looks like a panel that
/// happens to be in front, and the studio has enough panels. Blurring puts the
/// canvas out of reach visually as well as functionally, which is what makes a
/// naming prompt feel like a decision rather than a field.
Future<T?> showMqModal<T>({
  required BuildContext context,
  required Widget child,
  bool dismissible = true,
}) {
  final mq = context.mq;

  return showGeneralDialog<T>(
    context: context,
    // We paint our own scrim under the blur; the stock barrier would sit above
    // it and cancel the effect out.
    barrierColor: Colors.transparent,
    barrierDismissible: false,
    barrierLabel: tr('Close'),
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (context, animation, secondary) => const SizedBox.shrink(),
    transitionBuilder: (context, animation, secondary, _) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );

      return FadeTransition(
        opacity: curve,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: dismissible ? () => Navigator.of(context).pop() : null,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: ColoredBox(
                    color: mq.overlay.withValues(alpha: mq.dark ? 0.5 : 0.28),
                  ),
                ),
              ),
            ),
            // Clicks inside the card are the card's, never the backdrop's.
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.98, end: 1).animate(curve),
                  // A dialog route is mounted beside the Scaffold, not inside
                  // it, so there is no Material overhead any more. Text fields,
                  // the selection toolbar and the ambient body text style all
                  // need one -- without it every modal that holds a field
                  // throws "No Material widget found" on the first frame.
                  //
                  // Transparent: the card paints its own surface, and a second
                  // opaque layer here would sit over the blur.
                  child: Material(
                    type: MaterialType.transparency,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(MqTheme.gapLarge),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// The card every modal is drawn in: a heading, the content, and the actions
/// on the bottom right.
class MqModalCard extends StatelessWidget {
  const MqModalCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle = '',
    this.actions = const [],
    this.width = 520,
    this.showClose = true,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;
  final double width;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: mq.surface,
        borderRadius: BorderRadius.circular(MqTheme.radiusLarge),
        border: Border.all(color: mq.border),
        boxShadow: [
          BoxShadow(
            color: mq.dark ? const Color(0x8C000000) : const Color(0x1F000000),
            blurRadius: 34,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(MqTheme.gapLarge, 18, 14, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: mq.textPrimary,
                          fontSize: MqTheme.fontTitle,
                          fontWeight: FontWeight.w600,
                          letterSpacing: MqTheme.trackTitle,
                          height: MqTheme.lineTight,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
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
                if (showClose) ...[
                  const SizedBox(width: 8),
                  MqIconButton(
                    icon: 'close-line',
                    tip: tr('Close'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MqTheme.gapLarge,
              MqTheme.gap + 2,
              MqTheme.gapLarge,
              MqTheme.gapLarge,
            ),
            child: child,
          ),
          if (actions.isNotEmpty) ...[
            Container(height: 1, color: mq.divider),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < actions.length; ++i) ...[
                    if (i > 0) const SizedBox(width: 8),
                    actions[i],
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Asks for a name and nothing else. What "+ New project" and "Create a UGC
/// ad" open.
///
/// Returns the name, or null when the user backed out.
Future<String?> askForName(
  BuildContext context, {
  required String title,
  required String label,
  required String placeholder,
  required String confirmLabel,
  String subtitle = '',
  String initial = '',
}) {
  return showMqModal<String>(
    context: context,
    child: _NamePrompt(
      title: title,
      subtitle: subtitle,
      label: label,
      placeholder: placeholder,
      confirmLabel: confirmLabel,
      initial: initial,
    ),
  );
}

class _NamePrompt extends StatefulWidget {
  const _NamePrompt({
    required this.title,
    required this.subtitle,
    required this.label,
    required this.placeholder,
    required this.confirmLabel,
    required this.initial,
  });

  final String title;
  final String subtitle;
  final String label;
  final String placeholder;
  final String confirmLabel;
  final String initial;

  @override
  State<_NamePrompt> createState() => _NamePromptState();
}

class _NamePromptState extends State<_NamePrompt> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );

  @override
  void initState() {
    super.initState();
    // Opening onto a selected suggestion: typing replaces it, Enter accepts it.
    _name.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _name.text.length,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return MqModalCard(
      title: widget.title,
      subtitle: widget.subtitle,
      width: 460,
      actions: [
        GhostButton(
          text: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        PrimaryButton(text: widget.confirmLabel, onPressed: _submit),
      ],
      child: LabeledField(
        controller: _name,
        label: widget.label,
        placeholder: widget.placeholder,
        autofocus: true,
        onEditingComplete: (_) => _submit(),
      ),
    );
  }
}

/// A yes/no the user cannot undo. Returns false when they back out.
Future<bool> askToConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final answer = await showMqModal<bool>(
    context: context,
    child: Builder(
      builder: (context) => MqModalCard(
        title: title,
        width: 440,
        actions: [
          GhostButton(
            text: tr('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          GhostButton(
            text: confirmLabel,
            destructive: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
        child: Text(
          message,
          style: TextStyle(
            color: context.mq.textSecondary,
            fontSize: MqTheme.fontBody,
          ),
        ),
      ),
    ),
  );

  return answer ?? false;
}

/// One of the two big choices a picker modal offers: pick something you already
/// have, or make a new one.
class BigChoice extends StatelessWidget {
  const BigChoice({
    super.key,
    required this.title,
    required this.icon,
    required this.onPressed,
    this.subtitle = '',
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final String icon;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      enabled: enabled,
      onTap: onPressed,
      focusRadius: MqTheme.radius,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        height: 176,
        padding: const EdgeInsets.all(18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: states.pressed
              ? mq.surfaceActive
              : states.hovered
              ? mq.surfaceHover
              : mq.surfaceSecondary,
          borderRadius: BorderRadius.circular(MqTheme.radius),
          border: Border.all(
            color: states.active ? mq.borderStrong : mq.border,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MqIcon(
              icon,
              size: 26,
              color: !states.enabled
                  ? mq.textDisabled
                  : states.active
                  ? mq.primary
                  : mq.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: states.enabled ? mq.textPrimary : mq.textDisabled,
                fontSize: MqTheme.fontBody,
                fontWeight: FontWeight.w600,
                height: MqTheme.lineTight,
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
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
    );
  }
}
