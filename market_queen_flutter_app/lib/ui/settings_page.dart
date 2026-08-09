import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/platform_util.dart';
import '../i18n/translator.dart';
import '../providers/registry.dart';
import 'theme.dart';
import 'widgets/buttons.dart';
import 'widgets/cards.dart';
import 'widgets/fields.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.app});

  final AppState app;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _ffmpeg = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ffmpeg.text = widget.app.settings.ffmpegPath;
  }

  @override
  void dispose() {
    _ffmpeg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;

    return ListenableBuilder(
      listenable: Listenable.merge([app.settings, app.registry]),
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            MqTheme.pagePadding,
            4,
            MqTheme.pagePadding,
            MqTheme.gapLarge,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: tr('Settings'),
                subtitle: tr(
                  'Keys are encrypted on this machine and sent only '
                  'to the provider they belong to.',
                ),
              ),
              const SizedBox(height: MqTheme.gapLarge),

              _appearance(context),
              const SizedBox(height: MqTheme.gapLarge),
              _apiKeys(context),
              const SizedBox(height: MqTheme.gapLarge),
              _files(context),
              const SizedBox(height: MqTheme.gapLarge),
              _prices(context),
              const SizedBox(height: MqTheme.gapLarge),
              _about(context),
            ],
          ),
        );
      },
    );
  }

  Widget _appearance(BuildContext context) {
    final mq = context.mq;
    final app = widget.app;

    Widget label(String text) => SizedBox(
      width: 130,
      child: Text(
        text,
        style: TextStyle(
          color: mq.textSecondary,
          fontSize: MqTheme.fontSmall,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return SectionCard(
      title: tr('Appearance'),
      subtitle: tr('The interface language applies immediately, no restart.'),
      children: [
        Row(
          children: [
            label(tr('Theme')),
            SegmentedControl<bool>(
              value: app.settings.darkMode,
              onPicked: (dark) => app.settings.darkMode = dark,
              options: [
                MenuEntry(tr('Light'), false),
                MenuEntry(tr('Dark'), true),
              ],
            ),
            const Spacer(),
          ],
        ),
        Row(
          children: [
            label(tr('Language')),
            StyledCombo<String>(
              width: 260,
              value: app.translator.currentLanguage,
              onPicked: (code) => app.settings.uiLanguage = code,
              options: [
                for (final language in Translator.languages)
                  MenuEntry(language.label, language.code),
              ],
            ),
            const SizedBox(width: 8),
            GhostButton(
              text: tr('Use system language'),
              onPressed: () => app.settings.uiLanguage = '',
            ),
            const Spacer(),
          ],
        ),
      ],
    );
  }

  Widget _apiKeys(BuildContext context) {
    return SectionCard(
      title: tr('API keys'),
      subtitle: tr(
        'You only need the ones you actually use. An empty field '
        'means the provider is off.',
      ),
      children: [
        for (final credential in widget.app.registry.credentials())
          KeyField(app: widget.app, credential: credential),
      ],
    );
  }

  Widget _files(BuildContext context) {
    final mq = context.mq;
    final app = widget.app;

    return SectionCard(
      title: tr('Files'),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Projects folder'),
              style: TextStyle(
                color: mq.textSecondary,
                fontSize: MqTheme.fontSmall,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: LabeledField(
                    key: ValueKey(app.settings.projectsDir),
                    controller: TextEditingController(
                      text: app.settings.projectsDir,
                    ),
                    readOnly: true,
                  ),
                ),
                const SizedBox(width: 8),
                GhostButton(
                  text: tr('Change'),
                  onPressed: () async {
                    final folder = await getDirectoryPath(
                      confirmButtonText: tr('Choose where projects are saved'),
                    );
                    if (folder != null) app.settings.projectsDir = folder;
                  },
                ),
                const SizedBox(width: 8),
                GhostButton(
                  text: tr('Open'),
                  onPressed: () =>
                      PlatformUtil.openPath(app.settings.projectsDir),
                ),
              ],
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListenableBuilder(
              listenable: app.ffmpegPathChanged,
              builder: (context, _) {
                final resolved = app.ffmpegPath;
                return Row(
                  children: [
                    Text(
                      tr('FFmpeg'),
                      style: TextStyle(
                        color: mq.textSecondary,
                        fontSize: MqTheme.fontSmall,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: resolved.isNotEmpty ? mq.success : mq.warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        resolved.isNotEmpty ? resolved : tr('not found'),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: mq.textTertiary,
                          fontSize: MqTheme.fontSmall,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: LabeledField(
                    controller: _ffmpeg,
                    placeholder: tr('Leave empty to use the one on your PATH'),
                    onEditingComplete: (text) => app.settings.ffmpegPath = text,
                  ),
                ),
                const SizedBox(width: 8),
                GhostButton(
                  text: tr('Locate'),
                  onPressed: () async {
                    final file = await openFile();
                    if (file == null) return;
                    _ffmpeg.text = file.path;
                    app.settings.ffmpegPath = file.path;
                  },
                ),
                const SizedBox(width: 8),
                GhostButton(
                  text: tr('Download'),
                  onPressed: () => PlatformUtil.openExternal(
                    'https://ffmpeg.org/download.html',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              tr(
                'FFmpeg merges the clip, the voice-over and the subtitles into '
                'the final MP4. Without it the app still generates every '
                'piece, but cannot assemble them.',
              ),
              style: TextStyle(
                color: mq.textTertiary,
                fontSize: MqTheme.fontSmall,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _prices(BuildContext context) {
    final mq = context.mq;
    final pricing = widget.app.pricing;

    return SectionCard(
      title: tr('Prices'),
      subtitle: tr(
        'Used for the cost estimate. They are what the providers '
        'publish, not what they billed you.',
      ),
      children: [
        Text(
          pricing.overridden
              //: %1 is a date
              ? tr(
                  'Using your own price list, last edited %1.',
                ).arg(pricing.updated)
              : tr(
                  "Checked against the providers' pricing pages on %1. Drop a "
                  'pricing.json in the config folder to use your own.',
                ).arg(pricing.updated),
          style: TextStyle(
            color: mq.textSecondary,
            fontSize: MqTheme.fontLabel,
          ),
        ),
        Text(
          pricing.overridePath,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: mq.textTertiary, fontSize: MqTheme.fontSmall),
        ),
      ],
    );
  }

  Widget _about(BuildContext context) {
    final mq = context.mq;
    final app = widget.app;

    return SectionCard(
      title: tr('About'),
      children: [
        Text(
          tr(
            'Market Queen %1 - free and open source. There is no account and '
            'no server: every request goes straight from your machine to '
            'the provider you picked, with your key.',
          ).arg(app.version),
          style: TextStyle(
            color: mq.textSecondary,
            fontSize: MqTheme.fontLabel,
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: GhostButton(
            text: tr('Config folder'),
            onPressed: () => PlatformUtil.openPath(app.settings.configLocation),
          ),
        ),
      ],
    );
  }
}

/// One API key: hidden by default, saved on edit, never leaves the machine.
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

  void _onKeys() {
    if (mounted) setState(() {});
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
                text: tr('Get a key'),
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
                  onEditingComplete: (text) {
                    settings.setApiKey(credential.id, text);
                    setState(() => _saved = true);
                    Future.delayed(const Duration(milliseconds: 1900), () {
                      if (mounted) setState(() => _saved = false);
                    });
                  },
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
