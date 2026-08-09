import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../../models/ad_project.dart';
import '../../models/asset_library.dart';
import '../../models/image_forge.dart';
import '../../providers/types.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chip.dart';
import '../widgets/fields.dart';
import '../widgets/media_drop.dart';
import '../widgets/model_picker.dart';
import '../widgets/mq_dialog.dart';

/// The two things that can be cast in an ad. They are edited by one widget
/// because they are one shape: references, a description, and a still.
enum AssetKind { actor, decor }

/// Opens the editor over whatever is behind it. Returns the id of the asset
/// that was saved, or null if the user backed out.
Future<String?> showAssetEditor(
  BuildContext context, {
  required AppState app,
  required AssetKind kind,
  LibraryAsset? asset,
}) {
  return showMqModal<String>(
    context: context,
    // A form with half-typed text in it must not vanish on a stray click.
    dismissible: false,
    child: AssetEditor(app: app, kind: kind, asset: asset),
  );
}

/// Where an actor or a décor is described.
///
/// There are no trait pickers any more, for either. The user is already saying
/// who this is -- in pictures, in clips, in a sentence -- and asking them to
/// then also pick "Age: 30s" from a list only gave the model a second, blunter
/// description to disagree with the first.
///
/// A décor keeps a row of dials, which is the one place they earn their keep:
/// light and time of day are what a written description leaves vague, and they
/// are the two things that decide whether a room reads as real.
class AssetEditor extends StatefulWidget {
  const AssetEditor({
    super.key,
    required this.app,
    required this.kind,
    this.asset,
  });

  final AppState app;
  final AssetKind kind;

  /// The asset being edited, or null to start from nothing.
  final LibraryAsset? asset;

  @override
  State<AssetEditor> createState() => _AssetEditorState();
}

class _AssetEditorState extends State<AssetEditor> {
  late final LibraryAsset _draft =
      widget.asset?.copy() ?? LibraryAsset(name: _library.suggestedName());

  late final TextEditingController _name = TextEditingController(
    text: _draft.name,
  );
  late final TextEditingController _prompt = TextEditingController(
    text: _draft.prompt,
  );
  final TextEditingController _audition = TextEditingController();

  Player? _player;

  bool _models = false;
  List<VoiceOption> _voices = const [];
  String _lastSample = '';

  bool get _isActor => widget.kind == AssetKind.actor;

  AssetLibrary get _library =>
      _isActor ? widget.app.actors : widget.app.decors;

  ImageForge get _forge =>
      _isActor ? widget.app.actorForge : widget.app.decorForge;

  @override
  void initState() {
    super.initState();
    _forge.reset();
    _forge.addListener(_onForge);

    if (_isActor) {
      _audition.text = tr('Honestly, I did not think this would work.');
      widget.app.voiceBooth.addListener(_onBooth);
      widget.app.voicesLoaded.listen(_onVoicesLoaded);
    }
  }

  @override
  void dispose() {
    _forge.removeListener(_onForge);
    if (_isActor) {
      widget.app.voiceBooth.removeListener(_onBooth);
      widget.app.voicesLoaded.remove(_onVoicesLoaded);
    }
    _name.dispose();
    _prompt.dispose();
    _audition.dispose();
    _player?.dispose();
    super.dispose();
  }

  void _onForge() {
    if (mounted) setState(() {});
  }

  /// A fresh audition plays itself: hearing them is the whole point of the
  /// button that produced it.
  void _onBooth() {
    if (!mounted) return;
    setState(() {});
    final sample = widget.app.voiceBooth.samplePath;
    if (sample.isEmpty || sample == _lastSample) return;
    _lastSample = sample;
    (_player ??= Player()).open(Media(Uri.file(sample).toString()));
  }

  void _onVoicesLoaded(({String providerId, List<VoiceOption> voices}) event) {
    if (!mounted) return;
    setState(() => _voices = event.voices);
  }

  // ---- actions -------------------------------------------------------------

  /// What is actually sent to the image model. The realism scaffold does the
  /// heavy lifting; the user's sentence is the subject inside it.
  String get _fullPrompt {
    final casting = widget.app.casting;
    if (_isActor) {
      return casting.buildPortraitPrompt(description: _prompt.text.trim());
    }
    return casting.buildScenePrompt(
      description: _prompt.text.trim(),
      tweaks: AdProject.decorTweakFragments(_draft),
    );
  }

  void _generate() {
    _forge.generate(
      prompt: _fullPrompt,
      // Both are shot vertical, because the ad is.
      aspectRatio: '9:16',
      references: _draft.media,
      count: 2,
    );
  }

  void _save() {
    _draft
      ..name = _name.text.trim()
      ..prompt = _prompt.text.trim();
    final id = _library.save(_draft);
    if (mounted) Navigator.of(context).pop(id);
  }

  Future<void> _delete() async {
    final confirmed = await askToConfirm(
      context,
      title: _isActor ? tr('Delete this actor?') : tr('Delete this décor?'),
      message: _isActor
          ? tr('It is taken off every ad that cast it. Nothing already '
              'generated changes.')
          : tr('It is taken off every ad that used it. Nothing already '
              'generated changes.'),
      confirmLabel: tr('Delete'),
    );
    if (!confirmed || !mounted) return;

    if (_isActor) {
      widget.app.deleteActor(_draft.id);
    } else {
      widget.app.deleteDecor(_draft.id);
    }
    if (mounted) Navigator.of(context).pop();
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final existing = _draft.id.isNotEmpty;

    return MqModalCard(
      width: 640,
      title: existing
          ? (_isActor ? tr('Edit the actor') : tr('Edit the décor'))
          : (_isActor ? tr('Create an actor') : tr('Create a décor')),
      subtitle: _isActor
          ? tr('Photos, clips, or just a sentence. Whatever describes them '
              'best.')
          : tr('Where the ad is filmed. Photos, clips, or just a sentence.'),
      actions: [
        if (existing)
          GhostButton(
            text: tr('Delete'),
            destructive: true,
            onPressed: _delete,
          ),
        GhostButton(
          text: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        PrimaryButton(text: tr('Save'), onPressed: _save),
      ],
      child: ConstrainedBox(
        // Tall enough to work in, short enough that the buttons stay on screen
        // on a laptop.
        constraints: const BoxConstraints(maxHeight: 460),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabeledField(
                controller: _name,
                label: tr('Name'),
                placeholder: _library.suggestedName(),
              ),
              const SizedBox(height: MqTheme.gap),
              MediaDropZone(
                paths: _draft.media,
                title: tr('Add photos or clips'),
                hint: _isActor
                    ? tr('The first picture is the face every shot keeps.')
                    : tr('The first picture is the room every shot keeps.'),
                onAdded: (paths) => setState(() {
                  for (final path in paths) {
                    if (!_draft.media.contains(path)) _draft.media.add(path);
                  }
                }),
                onRemoved: (index) =>
                    setState(() => _draft.media.removeAt(index)),
                onPrimary: (index) => setState(() {
                  _draft.media.insert(0, _draft.media.removeAt(index));
                }),
              ),
              const SizedBox(height: MqTheme.gap),
              LabeledArea(
                controller: _prompt,
                label: tr('Description'),
                areaHeight: 80,
                placeholder: _isActor
                    ? tr('A woman in her twenties, tired, no make-up, plain '
                        'grey t-shirt…')
                    : tr('A small bathroom, towels on the floor, one window…'),
                onChanged: (text) => setState(() => _draft.prompt = text),
              ),
              if (!_isActor) ...[
                const SizedBox(height: MqTheme.gap),
                _tweaks(),
              ],
              if (_isActor) ...[
                const SizedBox(height: MqTheme.gap),
                _voice(),
              ],
              const SizedBox(height: MqTheme.gap),
              _previewSection(),
            ],
          ),
        ),
      ),
    );
  }

  // ---- décor dials ---------------------------------------------------------

  Widget _tweaks() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(tr('Optional')),
        const SizedBox(height: 7),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tweak in DecorTweak.all)
              MqChoiceChip(
                label: tweak.label,
                value: _draft.extraText(tweak.key),
                onPicked: (value) =>
                    setState(() => _draft.setExtra(tweak.key, value)),
                options: [
                  for (final option in tweak.options)
                    MenuOption(option.$1, option.$2),
                ],
              ),
          ],
        ),
      ],
    );
  }

  // ---- the voice -----------------------------------------------------------

  String get _voiceLabel {
    final id = _draft.extraText('voiceId');
    if (id.isEmpty) return '';
    for (final voice in _voices) {
      if (voice.id == id) {
        return voice.description.isEmpty
            ? voice.label
            : '${voice.label} — ${voice.description}';
      }
    }
    return id;
  }

  Widget _voice() {
    final mq = context.mq;
    final booth = widget.app.voiceBooth;
    final cost = booth.estimate(_audition.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(tr('Voice')),
        const SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: Builder(
                builder: (anchor) => _VoiceButton(
                  label: _voiceLabel,
                  onPressed: () => _pickVoice(anchor),
                ),
              ),
            ),
            const SizedBox(width: 6),
            MqIconButton(
              icon: 'refresh-line',
              tip: tr('Reload the voice list'),
              size: 34,
              onPressed: () => widget.app.loadVoices(
                widget.app.settings.prefString('voiceProvider', 'elevenlabs'),
              ),
            ),
            const SizedBox(width: 2),
            MqIconButton(
              icon: booth.auditioning ? 'loader-4-line' : 'play-fill',
              tip: cost.known
                  //: %1 is a price
                  ? tr('Hear them — %1').arg(Format.estimated(cost.amount))
                  : tr('Hear them'),
              size: 34,
              enabled: !booth.auditioning,
              onPressed: () => booth.audition(_draft.extras, _audition.text),
            ),
          ],
        ),
        if (booth.error.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            booth.error,
            style: TextStyle(color: mq.error, fontSize: MqTheme.fontSmall),
          ),
        ],
      ],
    );
  }

  Future<void> _pickVoice(BuildContext anchor) async {
    if (_voices.isEmpty) {
      await widget.app.loadVoices(
        widget.app.settings.prefString('voiceProvider', 'elevenlabs'),
      );
      if (!mounted || !anchor.mounted) return;
    }
    if (_voices.isEmpty) return;

    final picked = await showChipMenu<String>(
      anchor,
      current: _draft.extraText('voiceId'),
      width: 380,
      options: [
        for (final voice in _voices)
          MenuOption(
            voice.description.isEmpty
                ? voice.label
                : '${voice.label} — ${voice.description}',
            voice.id,
          ),
      ],
    );

    if (picked != null && mounted) {
      setState(() => _draft.setExtra('voiceId', picked));
    }
  }

  // ---- the stills ----------------------------------------------------------

  /// What the model came back with, and the one that was kept.
  ///
  /// There is no placeholder box when it is empty: a still only exists once
  /// something has been generated, and a grey rectangle saying "nothing yet"
  /// was only ever taking up the room the description needs.
  Widget _previewSection() {
    final mq = context.mq;
    final cost = _forge.estimate(2);
    final stills = _forge.images;
    final kept = _draft.previewPath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _isActor
                    ? tr('Nothing is generated until you ask. A preview only '
                        'helps you recognise them later.')
                    : tr('Nothing is generated until you ask. A preview only '
                        'helps you recognise it later.'),
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontSmall,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (_forge.running)
              MqLink(
                text: tr('Cancel'),
                destructive: true,
                onPressed: _forge.cancel,
              )
            else
              GhostButton(
                text: cost.known
                    //: %1 is a price
                    ? tr('Preview — %1').arg(Format.estimated(cost.amount))
                    : tr('Preview'),
                onPressed: _generate,
              ),
          ],
        ),
        if (_forge.running) ...[
          const SizedBox(height: 8),
          Text(
            //: %1 and %2 are counts of pictures
            tr('Generating… %1 of %2')
                .arg(_forge.received)
                .arg(_forge.requested),
            style: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontSmall,
            ),
          ),
        ],
        if (_forge.error.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _forge.error,
            style: TextStyle(color: mq.error, fontSize: MqTheme.fontSmall),
          ),
        ],
        if (stills.isNotEmpty || kept.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 108,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final still in stills)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: _Still(
                      path: still,
                      chosen: kept == still,
                      onTap: () => setState(() => _draft.previewPath = still),
                    ),
                  ),
                // The kept one stays visible after a batch replaces it.
                if (kept.isNotEmpty && !stills.contains(kept))
                  _Still(path: kept, chosen: true, onTap: () {}),
              ],
            ),
          ),
        ],
        const SizedBox(height: MqTheme.gap),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: MqLink(
            text: _models ? tr('Hide the model') : tr('Choose the model'),
            onPressed: () => setState(() => _models = !_models),
          ),
        ),
        if (_models) ...[
          const SizedBox(height: 8),
          ModelPicker(
            app: widget.app,
            category: 'image',
            label: tr('Pictures'),
          ),
        ],
      ],
    );
  }
}

/// A generated still, and whether it is the one being kept.
class _Still extends StatelessWidget {
  const _Still({required this.path, required this.chosen, required this.onTap});

  final String path;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      // A strip of thumbnails: sweeping it must not leave a wake.
      snap: true,
      builder: (context, states) => Container(
        width: 81,
        height: 108,
        decoration: BoxDecoration(
          color: mq.background,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          border: Border.all(
            color: chosen
                ? mq.primary
                : states.active
                ? mq.borderStrong
                : mq.border,
            width: chosen ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall - 1),
          child: LocalImage(path),
        ),
      ),
    );
  }
}

/// The voice picker. Not a chip: the list only exists after a round trip to the
/// provider, so it has to be a button that fetches rather than a menu that is
/// empty until it is.
class _VoiceButton extends StatelessWidget {
  const _VoiceButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onPressed,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: states.active ? mq.surfaceHover : mq.surfaceSecondary,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          border: Border.all(
            color: states.active ? mq.borderStrong : mq.border,
          ),
        ),
        child: Row(
          children: [
            MqIcon(
              'mic-line',
              size: 16,
              color: label.isEmpty ? mq.textTertiary : mq.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label.isEmpty ? tr('Choose a voice') : label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: label.isEmpty ? mq.textTertiary : mq.textPrimary,
                  fontSize: MqTheme.fontLabel,
                ),
              ),
            ),
            const SizedBox(width: 6),
            MqIcon(
              'arrow-down-s-line',
              size: 16,
              color: states.active ? mq.textPrimary : mq.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
