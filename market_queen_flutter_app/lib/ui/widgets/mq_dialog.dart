import 'package:flutter/material.dart';

import '../../i18n/translator.dart';
import '../icons.dart';
import '../theme.dart';
import 'buttons.dart';
import 'fields.dart';

/// Opens something over the page, with the page darkened behind it.
///
/// It used to blur the backdrop as well. That is gone: a `BackdropFilter` over
/// the whole window re-rasterised the live tree every frame, and a dialog that
/// closed while the filter was mid-composite took the frame down with it --
/// which is what the black screen on Enter actually looked like from the
/// outside. Darkening puts the canvas out of reach just as clearly and costs
/// one solid rectangle.
Future<T?> showMqModal<T>({
  required BuildContext context,
  required Widget child,
  bool dismissible = true,
}) {
  final mq = context.mq;

  return showGeneralDialog<T>(
    context: context,
    // The route paints the scrim itself so it fades with the card rather than
    // snapping in ahead of it.
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
                onTap: dismissible ? () => closeMqModal(context) : null,
                child: ColoredBox(color: mq.overlay),
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
                  // Transparent: the card paints its own surface.
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

/// Closes the modal [context] is inside, once.
///
/// Every dismissal in a dialog goes through here rather than calling
/// `Navigator.pop` directly, and the reason is the bug this replaced: two
/// dismissals could reach the navigator for one user action -- Enter popping
/// the route and the focus leaving the field behind it, or a Cancel click
/// blurring the field on the way down. The first pop closed the dialog; the
/// second popped whatever was underneath, which on a single-page desktop app is
/// the window's own route. The user saw a black screen, and on the way past,
/// the value the dialog was carrying got returned anyway -- so cancelling
/// created the project.
///
/// [ModalRoute.isCurrent] is the guard: a route that has already begun popping
/// stops being current, so the second call is a no-op.
void closeMqModal<T>(BuildContext context, [T? result]) {
  final route = ModalRoute.of(context);
  if (route == null || !route.isCurrent) return;
  Navigator.of(context).pop(result);
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
                    onPressed: () => closeMqModal(context),
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
    closeMqModal(context, name);
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
          onPressed: () => closeMqModal(context),
        ),
        PrimaryButton(text: widget.confirmLabel, onPressed: _submit),
      ],
      // Enter accepts, and only Enter: the field must not also commit when the
      // focus leaves it, or clicking Cancel would create the thing on its way
      // out of the field.
      child: LabeledField(
        controller: _name,
        label: widget.label,
        placeholder: widget.placeholder,
        autofocus: true,
        onSubmitted: (_) => _submit(),
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
            onPressed: () => closeMqModal(context, false),
          ),
          GhostButton(
            text: confirmLabel,
            destructive: true,
            onPressed: () => closeMqModal(context, true),
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
    this.overline = '',
    this.subtitle = '',
    this.enabled = true,
  });

  final String title;

  /// One word above the title, in caps: what this door *is* ("Generate",
  /// "Import"), as against the sentence under it explaining what it does.
  final String overline;

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
        // A floor rather than a height: the two doors are stretched to match
        // each other by the row they sit in, and a fixed height clipped the one
        // with the longer sentence on it.
        constraints: const BoxConstraints(minHeight: 176),
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
            if (overline.isNotEmpty) ...[
              Text(
                overline.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontMicro,
                  fontWeight: FontWeight.w600,
                  letterSpacing: MqTheme.trackOverline,
                ),
              ),
              const SizedBox(height: 6),
            ],
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
