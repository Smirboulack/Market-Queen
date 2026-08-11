import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/platform_util.dart';
import '../../i18n/translator.dart';
import '../../providers/registry.dart';
import '../theme.dart';
import 'buttons.dart';
import 'fields.dart';

/// One API key, in the panel that uses it.
///
/// Two shapes, because the two states are not equally interesting. A key that
/// is missing is the only thing on the card worth doing something about, so it
/// gets the field, the placeholder and the button. A key that is already there
/// is settled, and a 40px input repeating forty dots is forty pixels of noise
/// on every provider you have already configured -- so it collapses to a line
/// saying which key it is, with a way back into editing.
///
/// The same key can be on screen in several panels at once (OpenAI is on four),
/// so every instance listens for the change and catches up.
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

  bool _editing = false;
  bool _reveal = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.app.settings.apiKey(widget.credential.id);
    widget.app.settings.apiKeysChanged.addListener(_onKeys);
  }

  @override
  void dispose() {
    widget.app.settings.apiKeysChanged.removeListener(_onKeys);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onKeys() {
    if (!mounted) return;
    final stored = widget.app.settings.apiKey(widget.credential.id);
    if (stored != _controller.text && !_focus.hasFocus) {
      _controller.text = stored;
    }
    setState(() {});
  }

  /// Saves the key and flashes the confirmation. Wired to both Enter and the
  /// focus leaving the field: pasting a key and clicking away is as common as
  /// pasting one and pressing Enter, and neither should lose it.
  void _commit(String text) {
    widget.app.settings.setApiKey(widget.credential.id, text);
    setState(() {
      _saved = true;
      // Back to the settled line once there is something to settle on. An
      // emptied field is a key being removed, and that stays open so it does
      // not look like the deletion failed.
      _editing = text.trim().isEmpty;
      _reveal = false;
    });
    Future.delayed(const Duration(milliseconds: 1900), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  /// The last four characters, which is enough to tell two accounts apart and
  /// not enough to be worth anything to anyone reading over a shoulder.
  String _masked(String key) {
    if (key.length <= 4) return '••••';
    return '••••••••${key.substring(key.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.app.settings;
    final credential = widget.credential;

    final key = settings.apiKey(credential.id);
    final fromEnvironment = settings.apiKeyFromEnvironment(credential.id);

    return key.isEmpty || _editing
        ? _open(context, fromEnvironment)
        : _settled(context, key, fromEnvironment);
  }

  /// The compact line: what is stored, and the way back in.
  Widget _settled(BuildContext context, String key, bool fromEnvironment) {
    final mq = context.mq;

    return Row(
      children: [
        Text(
          tr('API key'),
          style: TextStyle(
            color: mq.textSecondary,
            fontSize: MqTheme.fontSmall,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _masked(key),
          style: TextStyle(
            color: mq.textPrimary,
            fontSize: MqTheme.fontLabel,
            fontWeight: FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (fromEnvironment) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              //: %1 is an environment variable name like OPENAI_API_KEY
              tr('from %1').arg(credentialEnv),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: mq.textTertiary,
                fontSize: MqTheme.fontSmall,
              ),
            ),
          ),
        ],
        const Spacer(),
        if (_saved)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(
              tr('Saved.'),
              style: TextStyle(color: mq.success, fontSize: MqTheme.fontSmall),
            ),
          ),
        MqLink(
          text: tr('Change'),
          onPressed: () {
            setState(() => _editing = true);
            // Straight into the field: the only reason to press Change is to
            // paste something.
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _focus.requestFocus(),
            );
          },
        ),
      ],
    );
  }

  String get credentialEnv => widget.credential.envVar;

  /// The field, shown while there is nothing stored or while it is being
  /// changed.
  Widget _open(BuildContext context, bool fromEnvironment) {
    final mq = context.mq;
    final credential = widget.credential;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // What this account is for, said once and only here: while the field is
        // open is exactly when somebody is deciding whether to go and sign up
        // for it, and it is dead weight on every card already configured.
        if (credential.note.isNotEmpty) ...[
          Text(
            credential.note,
            style: TextStyle(
              color: mq.textSecondary,
              fontSize: MqTheme.fontSmall,
              height: MqTheme.lineBody,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: LabeledField(
                controller: _controller,
                focusNode: _focus,
                obscure: !_reveal,
                placeholder: fromEnvironment
                    ? tr('Using %1 from your environment').arg(credential.envVar)
                    : tr('Paste your key'),
                onEditingComplete: _commit,
                onSubmitted: _commit,
              ),
            ),
            const SizedBox(width: 8),
            GhostButton(
              text: _reveal ? tr('Hide') : tr('Show'),
              checked: _reveal,
              onPressed: () => setState(() => _reveal = !_reveal),
            ),
            const SizedBox(width: 6),
            GhostButton(
              text: credential.free ? tr('Get a free key') : tr('Get a key'),
              onPressed: () => PlatformUtil.openExternal(credential.signupUrl),
            ),
          ],
        ),
        AnimatedOpacity(
          opacity: _saved ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              tr('Saved.'),
              style: TextStyle(color: mq.success, fontSize: MqTheme.fontSmall),
            ),
          ),
        ),
      ],
    );
  }
}
