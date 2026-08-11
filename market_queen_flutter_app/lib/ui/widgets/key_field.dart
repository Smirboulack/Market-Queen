import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/platform_util.dart';
import '../../i18n/translator.dart';
import '../../providers/registry.dart';
import '../theme.dart';
import 'buttons.dart';
import 'fields.dart';

/// One API key: hidden by default, saved on edit, never leaves the machine.
///
/// Lives next to the models it unlocks rather than in a settings screen of its
/// own. A list of key fields on one page and a list of model names on another
/// never said which unlocked which, and the answer is not guessable -- one
/// OpenAI key covers the writer, the stills, Sora and the voice-over, while
/// LTX's covers exactly one row. Drawn inside a panel, the pairing is the
/// layout.
class KeyField extends StatefulWidget {
  const KeyField({super.key, required this.app, required this.credential});

  final AppState app;
  final CredentialEntry credential;

  @override
  State<KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends State<KeyField> {
  final _controller = TextEditingController();

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
    super.dispose();
  }

  /// The same key can be on screen twice -- OpenAI appears in four panels --
  /// so a field that is not the one being typed into still has to catch up.
  void _onKeys() {
    if (!mounted) return;
    final stored = widget.app.settings.apiKey(widget.credential.id);
    if (stored != _controller.text) _controller.text = stored;
    setState(() {});
  }

  /// Saves the key and flashes the confirmation. Wired to both Enter and the
  /// focus leaving the field: pasting a key and clicking away is as common as
  /// pasting one and pressing Enter, and neither should lose it.
  void _commit(String text) {
    widget.app.settings.setApiKey(widget.credential.id, text);
    setState(() => _saved = true);
    Future.delayed(const Duration(milliseconds: 1900), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final settings = widget.app.settings;
    final credential = widget.credential;

    final fromEnvironment = settings.apiKeyFromEnvironment(credential.id);
    final hasKey = settings.hasApiKey(credential.id);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radius),
        border: Border.all(color: mq.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: hasKey ? mq.success : mq.borderStrong,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                credential.label,
                style: TextStyle(
                  color: mq.textPrimary,
                  fontSize: MqTheme.fontBody,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (credential.free) ...[
                const SizedBox(width: 8),
                Text(
                  tr('Free tier'),
                  style: TextStyle(
                    color: mq.successText,
                    fontSize: MqTheme.fontSmall,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  credential.note,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mq.textTertiary,
                    fontSize: MqTheme.fontSmall,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GhostButton(
                text: credential.free ? tr('Get a free key') : tr('Get a key'),
                onPressed: () =>
                    PlatformUtil.openExternal(credential.signupUrl),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: LabeledField(
                  controller: _controller,
                  obscure: !_reveal,
                  placeholder: fromEnvironment
                      ? tr(
                          'Using %1 from your environment',
                        ).arg(credential.envVar)
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
            ],
          ),
          AnimatedOpacity(
            opacity: _saved ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Text(
              tr('Saved.'),
              style: TextStyle(color: mq.success, fontSize: MqTheme.fontSmall),
            ),
          ),
        ],
      ),
    );
  }
}
