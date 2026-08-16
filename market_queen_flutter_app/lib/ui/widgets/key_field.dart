import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/platform_util.dart';
import '../../i18n/translator.dart';
import '../../providers/registry.dart';
import '../icons.dart';
import '../theme.dart';
import 'buttons.dart';

/// One API key: a label, a field, and an eye inside its right edge.
///
/// It used to be two different controls -- a full-width input while the key was
/// missing, collapsing to a line of dots with Change and Show links once it was
/// there. Two shapes meant two sets of behaviour to keep straight, and it is
/// where the show/hide bug lived: revealing moved the focus, losing the focus
/// counted as finishing, and finishing swapped the control out from under the
/// press.
///
/// One shape now, and it is the ordinary password field everybody already
/// knows: the value is always in the box, the eye at the end of the box shows
/// or hides it, and nothing about looking at a key changes what is stored.
/// Typing saves on Enter or as soon as the field is left.
class KeyField extends StatefulWidget {
  const KeyField({super.key, required this.app, required this.credential});

  final AppState app;
  final CredentialEntry credential;

  @override
  State<KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends State<KeyField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  bool _reveal = false;
  bool _saved = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.app.settings.apiKey(widget.credential.id);
    _hadText = _controller.text.isNotEmpty;
    // The eye only exists once there is something behind the dots, so the box
    // has to rebuild as the first character is typed. The field redraws itself
    // from the controller; this widget does not, and without it somebody
    // pasting into an empty box got no eye until something else happened to
    // rebuild the page.
    _controller.addListener(_onTyped);
    _focus.addListener(_onFocus);
    // The same key can be on screen twice; every instance catches up.
    widget.app.settings.apiKeysChanged.addListener(_onKeys);
  }

  @override
  void dispose() {
    widget.app.settings.apiKeysChanged.removeListener(_onKeys);
    _controller.removeListener(_onTyped);
    _focus.removeListener(_onFocus);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Only when it changes whether there is anything to reveal -- a rebuild per
  /// keystroke would be a rebuild per keystroke.
  bool _hadText = false;

  void _onTyped() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText == _hadText || !mounted) return;
    setState(() => _hadText = hasText);
  }

  void _onFocus() {
    if (!mounted) return;
    // Leaving the field is one of the two ways to finish. Hiding again on the
    // way out is the safe default: a key left readable on a screen somebody
    // has walked away from is the one state this control should not persist.
    if (!_focus.hasFocus) {
      _save();
      _reveal = false;
    }
    setState(() {});
  }

  void _onKeys() {
    if (!mounted) return;
    final stored = widget.app.settings.apiKey(widget.credential.id);
    if (stored != _controller.text && !_focus.hasFocus) {
      _controller.text = stored;
    }
    setState(() {});
  }

  /// Writes what is in the box, and says so briefly. A no-op when nothing has
  /// changed, so simply passing through a field does not flash a confirmation
  /// at somebody who typed nothing.
  void _save() {
    final text = _controller.text.trim();
    if (text == widget.app.settings.apiKey(widget.credential.id)) return;

    widget.app.settings.setApiKey(widget.credential.id, text);
    setState(() => _saved = true);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  /// Show / hide, and nothing else: it does not save, does not close anything,
  /// and does not take the focus.
  void _toggleReveal() => setState(() => _reveal = !_reveal);

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final settings = widget.app.settings;
    final credential = widget.credential;

    final fromEnvironment = settings.apiKeyFromEnvironment(credential.id);
    final stored = settings.hasApiKey(credential.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            MqIcon('key-line', size: 13, color: mq.textTertiary),
            const SizedBox(width: 6),
            Text(
              tr('API key'),
              style: TextStyle(
                color: mq.textSecondary,
                fontSize: MqTheme.fontSmall,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            // The confirmation replaces the status word rather than sitting
            // beside it, so the row never grows.
            if (_saved)
              Text(
                tr('Saved'),
                style: TextStyle(
                  color: mq.success,
                  fontSize: MqTheme.fontMicro,
                  fontWeight: FontWeight.w600,
                ),
              )
            else if (fromEnvironment)
              Text(
                //: %1 is an environment variable name like OPENAI_API_KEY
                tr('from %1').arg(credential.envVar),
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontMicro,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        _control(context, stored),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                credential.note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontMicro,
                  height: MqTheme.lineBody,
                ),
              ),
            ),
            const SizedBox(width: 10),
            MqLink(
              text: tr('Get a key'),
              fontSize: MqTheme.fontMicro,
              onPressed: () => PlatformUtil.openExternal(credential.signupUrl),
            ),
          ],
        ),
      ],
    );
  }

  /// The box: the input, and the eye pinned inside its right edge.
  Widget _control(BuildContext context, bool stored) {
    final mq = context.mq;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: MqTheme.hoverDuration,
        height: 36,
        decoration: BoxDecoration(
          color: mq.surface,
          borderRadius: BorderRadius.circular(MqTheme.radius),
          border: Border.all(
            color: _focus.hasFocus
                ? mq.borderStrong
                : _hovered
                ? mq.borderStrong
                : mq.border,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                obscureText: !_reveal,
                // A key is an opaque string, so it is set in figures that line
                // up rather than in the prose face the rest of the app uses.
                style: TextStyle(
                  color: mq.textPrimary,
                  fontSize: MqTheme.fontLabel,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                cursorColor: mq.primary,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 10,
                  ),
                  hintText: tr('Paste your key'),
                  hintStyle: TextStyle(
                    color: mq.textTertiary,
                    fontSize: MqTheme.fontLabel,
                  ),
                ),
              ),
            ),
            // Nothing to reveal on an empty box, so the eye only appears once
            // there is something behind the dots.
            if (_controller.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: MqIconButton(
                  icon: _reveal ? 'eye-off-line' : 'eye-line',
                  tip: _reveal ? tr('Hide') : tr('Show'),
                  size: 28,
                  canRequestFocus: false,
                  onPressed: _toggleReveal,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
