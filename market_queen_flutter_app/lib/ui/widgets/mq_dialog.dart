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
    this.maxHeight = 0,
    this.showClose = true,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;
  final double width;

  /// A ceiling on the whole card, and the content is what gives way to it.
  ///
  /// Zero -- the default -- means the card is as tall as its contents and the
  /// modal scrolls if that is more than the window holds. That is right for a
  /// form: the fields are all the same size and scrolling past them is normal.
  ///
  /// It is wrong for a screen built around a feed. The casting studio sized
  /// its picture strip from the window and then added a header, a prompt bar
  /// and an action row underneath it, so the card came out taller than the
  /// screen it was measured against and the whole thing scrolled -- including
  /// the bar you type in and the button you press. Set this and the content is
  /// handed a [Flexible] slot instead, so it is the feed that shrinks and the
  /// controls that stay put.
  final double maxHeight;

  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        MqTheme.gapLarge,
        MqTheme.gap + 2,
        MqTheme.gapLarge,
        MqTheme.gapLarge,
      ),
      child: child,
    );

    return Container(
      width: width,
      // Only when a ceiling was asked for: a `Flexible` under an unbounded
      // column is an assertion, not a layout.
      constraints:
          maxHeight > 0 ? BoxConstraints(maxHeight: maxHeight) : null,
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
          if (maxHeight > 0) Flexible(child: content) else content,
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

/// One of the two doors of a "make a new one" modal, drawn as a card with a
/// picture on it.
///
/// It replaced a glyph-and-two-sentences version of the same choice. The glyph
/// was 26px of grey line art at the top of a 176px box, which made the two doors
/// read as list items rather than as the two things the modal is for -- and the
/// difference between them, describing somebody against photographing somebody,
/// is exactly the sort of thing a picture says faster than a paragraph.
///
/// The card is the target, not the button inside it. A button that is also a
/// nested tap target inside a pressable card gives the pointer two answers to
/// the same click and Tab two stops for one choice; the bar at the bottom is
/// drawn from the card's own hover state, which is what makes the whole card
/// light up as one object.
class IllustratedChoice extends StatelessWidget {
  const IllustratedChoice({
    super.key,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.icon,
    required this.onPressed,
    this.illustration = '',
    this.enabled = true,
  });

  final String title;

  /// Two lines at most: what this door does, said once. The card is about
  /// 250px wide and a third sentence pushes the button off the bottom of it.
  final String subtitle;

  /// The label on the bar at the bottom. The same words as the title, which is
  /// deliberate: the title names the door and the bar is the thing you press.
  final String action;

  /// Drawn on the plate when [illustration] is missing or absent, and beside
  /// the label on the bar either way.
  final String icon;

  /// An asset path. A file that is not in the bundle falls back to [icon]
  /// rather than throwing, on the same terms as every other artwork in the app.
  final String illustration;

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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: states.pressed
              ? mq.surfaceActive
              : states.hovered
              ? mq.surfaceHover
              : mq.surface,
          borderRadius: BorderRadius.circular(MqTheme.radius + 2),
          border: Border.all(
            color: states.active ? mq.borderStrong : mq.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _plate(mq),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: states.enabled ? mq.textPrimary : mq.textDisabled,
                fontSize: MqTheme.fontTitle,
                fontWeight: FontWeight.w600,
                letterSpacing: MqTheme.trackTitle,
                height: MqTheme.lineTight,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: mq.textTertiary,
                fontSize: MqTheme.fontSmall,
                height: MqTheme.lineBody,
              ),
            ),
            const SizedBox(height: 14),
            _bar(mq, states),
          ],
        ),
      ),
    );
  }

  /// The artwork, on its own light panel.
  Widget _plate(MqTheme mq) {
    return AspectRatio(
      aspectRatio: 3 / 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: mq.illustrationPlate,
          borderRadius: BorderRadius.circular(MqTheme.radius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: illustration.isEmpty
              ? Center(
                  child: MqIcon(icon, size: 34, color: mq.onIllustrationPlate),
                )
              : Image.asset(
                  illustration,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, _, _) => Center(
                    child: MqIcon(
                      icon,
                      size: 34,
                      color: mq.onIllustrationPlate,
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  /// The commit bar. Filled with ink, which is what this interface uses for
  /// "press this" -- the brand ramp is spent on the one button that actually
  /// starts spending money, and two ramps side by side would name neither.
  Widget _bar(MqTheme mq, MqStates states) {
    final fill = !states.enabled
        ? mq.surfaceTertiary
        : states.pressed
        ? mq.primaryActive
        : states.hovered
        ? mq.primaryHover
        : mq.primary;
    final ink = states.enabled ? mq.onPrimary : mq.textDisabled;

    return AnimatedContainer(
      duration: states.duration,
      height: 38,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              action,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                color: ink,
                fontSize: MqTheme.fontLabel,
                fontWeight: FontWeight.w600,
                letterSpacing: MqTheme.trackSmall,
              ),
            ),
          ),
          const SizedBox(width: 8),
          MqIcon('arrow-right-line', size: 15, color: ink),
        ],
      ),
    );
  }
}
