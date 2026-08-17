import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../../providers/registry.dart';
import '../brand.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/key_field.dart';
import '../widgets/mq_dialog.dart';

/// Asks for one account's API key, where the user hit the wall.
///
/// It exists because of what the model menus used to do about a locked row:
/// nothing, or send you to the Models page. Both are the same failure -- you
/// were choosing a model, and the answer was to leave the screen you were on,
/// find the right card among fifteen, paste a key, come back, and remember what
/// you had been about to do. The key is four seconds of work; the round trip was
/// the expensive part.
///
/// Returns true when there is a key on the account by the time it closes, which
/// is the caller's cue to go ahead and pick the model that was locked.
Future<bool> askForApiKey(
  BuildContext context, {
  required AppState app,
  required String credentialId,
}) async {
  final credential = _find(app.registry, credentialId);
  if (credential == null) return false;

  final answer = await showMqModal<bool>(
    context: context,
    // A pasted key is cheap to lose but annoying to fetch twice, and the
    // backdrop is right where the pointer already is.
    dismissible: false,
    child: _KeyDialog(app: app, credential: credential),
  );
  return answer ?? app.settings.hasApiKey(credentialId);
}

CredentialEntry? _find(Registry registry, String id) {
  if (id.isEmpty) return null;
  for (final credential in registry.credentials()) {
    if (credential.id == id) return credential;
  }
  return null;
}

class _KeyDialog extends StatefulWidget {
  const _KeyDialog({required this.app, required this.credential});

  final AppState app;
  final CredentialEntry credential;

  @override
  State<_KeyDialog> createState() => _KeyDialogState();
}

class _KeyDialogState extends State<_KeyDialog> {
  /// Closes, reporting whether there is a key.
  ///
  /// The unfocus is load-bearing rather than tidy-up: [KeyField] writes what is
  /// in it when it loses the focus, so a key typed and never left is not saved
  /// yet at the moment this runs. Dropping the focus first is what commits it,
  /// and the frame in between is what lets the write land before the answer is
  /// read.
  Future<void> _done() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    closeMqModal(context, widget.app.settings.hasApiKey(widget.credential.id));
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final credential = widget.credential;

    return MqModalCard(
      width: 460,
      title: tr('Add your API key'),
      //: %1 is an account name such as "Google Gemini"
      subtitle: tr('%1 bills this key directly. Nothing goes through us.')
          .arg(credential.label),
      actions: [
        GhostButton(
          text: tr('Cancel'),
          onPressed: () => closeMqModal(context, false),
        ),
        PrimaryButton(text: tr('Done'), onPressed: _done),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Whose account this is, said with the mark rather than only with the
          // name: the menu row that sent you here was identified by that logo.
          Row(
            children: [
              ProviderMark(credential: credential.id, size: 30),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      credential.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: mq.textPrimary,
                        fontSize: MqTheme.fontBody,
                        fontWeight: FontWeight.w600,
                        letterSpacing: MqTheme.trackTitle,
                        height: MqTheme.lineTight,
                      ),
                    ),
                    if (credential.note.isNotEmpty)
                      Text(
                        credential.note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: mq.textTertiary,
                          fontSize: MqTheme.fontSmall,
                          height: MqTheme.lineTight,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: MqTheme.gapLarge),
          // The same control as the Models page, not a second one: the eye, the
          // save-on-Enter and the verdict line under the box are all behaviour
          // that took a while to get right once.
          KeyField(app: widget.app, credential: credential),
        ],
      ),
    );
  }
}
