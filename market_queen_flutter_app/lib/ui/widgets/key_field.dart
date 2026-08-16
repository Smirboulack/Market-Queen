import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/platform_util.dart';
import '../../i18n/translator.dart';
import '../../providers/key_check.dart';
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
  bool _hovered = false;

  /// The verification of whatever is currently stored: null while nothing has
  /// been checked, non-null once an answer is in.
  KeyCheckResult? _result;

  /// The check in flight, kept so a second paste cancels the first: two
  /// answers arriving out of order would leave the field showing the verdict
  /// on a key that is no longer in it.
  KeyCheckTask? _checking;

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
    _checking?.cancel();
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

  /// Writes what is in the box and asks the provider whether it works.
  ///
  /// A no-op when nothing has changed, so passing through a field does not
  /// re-check a key that was already checked -- these are network calls, and
  /// the ones that matter happen when a key is actually pasted.
  void _save() {
    final text = _controller.text.trim();
    if (text == widget.app.settings.apiKey(widget.credential.id)) return;

    widget.app.settings.setApiKey(widget.credential.id, text);
    _verify(text);
  }

  /// Asks the provider. Nothing is blocked while it runs: the key is already
  /// saved, and the answer only changes what the line under the field says.
  Future<void> _verify(String key) async {
    _checking?.cancel();

    if (key.isEmpty) {
      setState(() {
        _checking = null;
        _result = null;
      });
      return;
    }

    final task = KeyCheckTask(
      credentialId: widget.credential.id,
      apiKey: key,
    );
    setState(() {
      _checking = task;
      _result = null;
    });

    final result = await task.check();
    // A newer paste has already started its own check, or the page has gone.
    if (!mounted || _checking != task) return;

    setState(() {
      _checking = null;
      _result = result;
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
            if (fromEnvironment)
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
        const SizedBox(height: 7),
        // The verdict, where the description was. They share the line because
        // they are wanted at opposite moments: what an account is for matters
        // while you decide whether to get a key, and whether the key works
        // matters the instant after you paste one.
        _status(context, stored),
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
            // Keys stored in an earlier session are not re-checked on every
            // visit -- that would be fifteen requests for opening a page --
            // so there is a way to ask.
            if (stored && _checking == null && KeyProbe.supports(credential.id))
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: MqLink(
                  text: _result == null ? tr('Check') : tr('Check again'),
                  fontSize: MqTheme.fontMicro,
                  onPressed: () => _verify(_controller.text.trim()),
                ),
              ),
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

  /// The one line that says where the key stands: checking, works, refused, or
  /// nothing at all when there is no key to say anything about.
  ///
  /// It is a line rather than a badge because two of the four answers are
  /// sentences -- a provider that refuses a key usually says why, and "your
  /// account has no credit" is a different afternoon from "that key does not
  /// exist".
  Widget _status(BuildContext context, bool stored) {
    final mq = context.mq;

    if (_checking != null) {
      return Row(
        children: [
          SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: mq.textTertiary,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            //: %1 is an account name such as "OpenAI"
            tr('Checking with %1...').arg(widget.credential.label),
            style: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontMicro,
            ),
          ),
        ],
      );
    }

    final result = _result;
    if (result == null || !stored) return const SizedBox(height: 15);

    final (String glyph, Color ink) = switch (result.verdict) {
      KeyVerdict.valid => ('check-line', mq.successText),
      KeyVerdict.invalid => ('error-warning-line', mq.errorText),
      // Neither good news nor bad: the key is saved and unproven, which is
      // exactly what the grey says.
      _ => ('information-line', mq.textTertiary),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: MqIcon(glyph, size: 12, color: ink),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            keyVerdictLabel(result),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ink,
              fontSize: MqTheme.fontMicro,
              height: MqTheme.lineBody,
            ),
          ),
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
            // A refused key marks its own box, so a grid of fifteen shows
            // which one to go back to without reading fifteen status lines.
            color: _result?.verdict == KeyVerdict.invalid
                ? mq.error
                : _focus.hasFocus
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
