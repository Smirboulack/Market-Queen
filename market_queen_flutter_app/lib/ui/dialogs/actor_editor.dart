import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../../models/asset_library.dart';
import '../../providers/voice_profile.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/file_menu.dart';
import '../widgets/media_drop.dart';
import '../widgets/media_preview.dart';
import '../widgets/mq_dialog.dart';
import '../widgets/video_player.dart';
import 'actor_wizard.dart';
import 'asset_studio.dart';
import 'voice_picker.dart';

/// Changing an actor that already exists.
///
/// Not the same shape as the scene editor, and deliberately so. A scene is a
/// picture with four dials on it and fits on one card; an actor is a person --
/// a face, a voice, a personality and a wardrobe -- and pouring four unrelated
/// subjects into one scrolling form is what made the old screen read as a
/// database record with a photograph stapled to the corner.
///
/// So: the actor down the left, always visible, and one subject at a time down
/// the right. The user is managing a character, not filling in a row.
///
/// Returns the id if it was saved, or null.
Future<String?> showActorEditor(
  BuildContext context, {
  required AppState app,
  required LibraryAsset actor,
}) {
  return showMqModal<String>(
    context: context,
    // Half-typed direction and a voice that cost money must not vanish on a
    // stray click.
    dismissible: false,
    child: ActorEditor(app: app, actor: actor),
  );
}

/// The sections of an actor. The order is the argument: who they are, what they
/// look like, how they sound, how they behave, and what else they can wear.
enum ActorSection { overview, appearance, voice, personality, looks }

class ActorEditor extends StatefulWidget {
  const ActorEditor({super.key, required this.app, required this.actor});

  final AppState app;
  final LibraryAsset actor;

  @override
  State<ActorEditor> createState() => _ActorEditorState();
}

class _ActorEditorState extends State<ActorEditor> {
  late final LibraryAsset _draft = widget.actor.copy();

  late final TextEditingController _name =
      TextEditingController(text: _draft.name);
  late final TextEditingController _prompt =
      TextEditingController(text: _draft.prompt);
  late final TextEditingController _action =
      TextEditingController(text: _draft.extraText(ActorPersona.actionKey));
  late final TextEditingController _style =
      TextEditingController(text: _draft.extraText(ActorPersona.styleKey));

  ActorSection _section = ActorSection.overview;

  @override
  void initState() {
    super.initState();
    widget.app.voiceBooth.addListener(_repaint);
    // A design left over from the last actor edited is not this actor's.
    widget.app.voiceForge.reset();
  }

  @override
  void dispose() {
    widget.app.voiceBooth.removeListener(_repaint);
    _name.dispose();
    _prompt.dispose();
    _action.dispose();
    _style.dispose();
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  void _save() {
    _collect();
    final id = widget.app.actors.save(_draft);
    if (mounted) closeMqModal(context, id);
  }

  /// Pulls the four text fields onto the draft. Everything else on this screen
  /// writes straight through as it is changed; only text has to be gathered,
  /// because committing on every keystroke would re-sort the library under the
  /// cursor.
  void _collect() {
    _draft
      ..name = _name.text.trim()
      ..prompt = _prompt.text.trim()
      ..setExtra(ActorPersona.actionKey, _action.text.trim())
      ..setExtra(ActorPersona.styleKey, _style.text.trim());
  }

  Future<void> _delete() async {
    final confirmed = await askToConfirm(
      context,
      title: tr('Delete this actor?'),
      message: tr('It is taken off every ad that cast it. Nothing already '
          'generated changes.'),
      confirmLabel: tr('Delete'),
    );
    if (!confirmed || !mounted) return;

    widget.app.deleteActor(_draft.id);
    if (mounted) closeMqModal(context);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 120).clamp(720.0, 1080.0);
    final height = (screen.height - 260).clamp(420.0, 620.0);

    return MqModalCard(
      width: width,
      title: tr('Edit the actor'),
      subtitle: tr('Who they are, how they look, how they sound and how they '
          'behave.'),
      actions: [
        GhostButton(text: tr('Delete'), destructive: true, onPressed: _delete),
        GhostButton(text: tr('Cancel'), onPressed: () => closeMqModal(context)),
        PrimaryButton(text: tr('Save changes'), onPressed: _save),
      ],
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 236, child: _identity()),
            const SizedBox(width: MqTheme.gapLarge),
            SizedBox(width: 168, child: _rail()),
            const SizedBox(width: MqTheme.gapLarge),
            Expanded(
              child: SingleChildScrollView(child: _body()),
            ),
          ],
        ),
      ),
    );
  }

  // ---- the left-hand column ------------------------------------------------

  /// The actor themselves, on screen the whole time.
  ///
  /// This is the point of the layout: every control on the right changes
  /// something about the person in this frame, and a face you have to scroll
  /// back to is a face you stop checking against.
  Widget _identity() {
    final mq = context.mq;
    final take = _draft.extraText('takePath');
    final voice = _draft.extraText('voiceName');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: take.isEmpty
              ? _portrait()
              : ClipRRect(
                  borderRadius: BorderRadius.circular(MqTheme.radius),
                  child: InlineVideo(
                    path: take,
                    autoPlay: false,
                    loop: true,
                  ),
                ),
        ),
        const SizedBox(height: MqTheme.gap),
        Text(
          _name.text.trim().isEmpty ? _draft.name : _name.text.trim(),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: mq.textPrimary,
            fontSize: MqTheme.fontTitle,
            fontWeight: FontWeight.w600,
            letterSpacing: MqTheme.trackTitle,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _facts.isEmpty ? tr('No casting brief yet') : _facts,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: mq.textTertiary, fontSize: MqTheme.fontSmall),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            MqIcon(
              voice.isEmpty ? 'mic-line' : 'user-voice-line',
              size: 15,
              color: voice.isEmpty ? mq.textTertiary : mq.primary,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                voice.isEmpty ? tr('No voice') : voice,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: voice.isEmpty ? mq.textTertiary : mq.textSecondary,
                  fontSize: MqTheme.fontSmall,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Gender, age and language in the words the chips use. What the card under
  /// the picture says, and what the casting search is actually filtering on.
  String get _facts {
    final parts = <String>[
      VoiceTrait.labelFor('voiceGender', _draft.extraText('voiceGender')),
      VoiceTrait.labelFor('voiceAge', _draft.extraText('voiceAge')),
      VoiceLocale.find(_draft.extraText('voiceLocale'))?.label ?? '',
    ];
    return parts.where((part) => part.isNotEmpty).join(' · ');
  }

  Widget _portrait() {
    final mq = context.mq;
    if (_draft.thumbnail.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: mq.surfaceSecondary,
          borderRadius: BorderRadius.circular(MqTheme.radius),
          border: Border.all(color: mq.border),
        ),
        child: Center(
          child: MqIcon('user-smile-line', size: 26, color: mq.textTertiary),
        ),
      );
    }

    return MediaMenu(
      path: _draft.thumbnail,
      actions: [
        MediaMenuAction(
          icon: 'fullscreen-line',
          label: tr('View full size'),
          onPressed: () => showMediaPreview(context, _draft.thumbnail),
        ),
      ],
      child: Pressable(
        onTap: () => showMediaPreview(context, _draft.thumbnail),
        tooltip: tr('View full size'),
        focusRadius: MqTheme.radius,
        builder: (context, states) => AnimatedContainer(
          duration: states.duration,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MqTheme.radius),
            border: Border.all(
              color: states.active ? mq.borderStrong : mq.border,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: LocalImage(_draft.thumbnail),
        ),
      ),
    );
  }

  // ---- the section rail ----------------------------------------------------

  Widget _rail() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final section in ActorSection.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _RailRow(
              icon: _iconFor(section),
              label: _labelFor(section),
              selected: _section == section,
              onTap: () => setState(() => _section = section),
            ),
          ),
      ],
    );
  }

  String _labelFor(ActorSection section) => switch (section) {
        ActorSection.overview => tr('Overview'),
        ActorSection.appearance => tr('Appearance'),
        ActorSection.voice => tr('Voice'),
        ActorSection.personality => tr('Personality'),
        ActorSection.looks => tr('Looks'),
      };

  String _iconFor(ActorSection section) => switch (section) {
        ActorSection.overview => 'information-line',
        ActorSection.appearance => 'image-line',
        ActorSection.voice => 'user-voice-line',
        ActorSection.personality => 'emotion-line',
        ActorSection.looks => 'gallery-line',
      };

  Widget _body() => switch (_section) {
        ActorSection.overview => _overview(),
        ActorSection.appearance => _appearance(),
        ActorSection.voice => _voice(),
        ActorSection.personality => _personality(),
        ActorSection.looks => _looks(),
      };

  // ---- section: overview ---------------------------------------------------

  Widget _overview() {
    final mq = context.mq;
    final via = _draft.extraText('createdVia');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LabeledField(
          controller: _name,
          label: tr('Name'),
          placeholder: widget.app.actors.suggestedName(),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: MqTheme.gap),
        LabeledArea(
          controller: _prompt,
          label: tr('Who they are'),
          areaHeight: 92,
          placeholder: tr('A woman in her twenties, tired, no make-up, plain '
              'grey t-shirt…'),
        ),
        const SizedBox(height: 6),
        Text(
          tr('This is what the image model is told, and what the search box '
              'matches on.'),
          style: TextStyle(
            color: mq.textTertiary,
            fontSize: MqTheme.fontSmall,
            height: MqTheme.lineTight,
          ),
        ),
        const SizedBox(height: MqTheme.gapLarge),
        _Facts(
          rows: [
            (
              tr('Made'),
              switch (via) {
                'fromImage' => tr('From a photograph'),
                'describe' => tr('From a description'),
                _ => tr('Unknown'),
              }
            ),
            (tr('Voice'), _voiceProvenance),
            (tr('Looks'), '${ActorLooks.of(_draft).length + 1}'),
            (tr('Created'), Format.day(_draft.createdAt)),
            (tr('Last changed'), Format.day(_draft.updatedAt)),
          ],
        ),
      ],
    );
  }

  String get _voiceProvenance {
    final name = _draft.extraText('voiceName');
    if (name.isEmpty) return tr('Cast from the brief at render time');
    return switch (_draft.extraText('voiceKind')) {
      'designed' => tr('%1 · designed').arg(name),
      'cloned' => tr('%1 · cloned').arg(name),
      _ => tr('%1 · voice library').arg(name),
    };
  }

  // ---- section: appearance -------------------------------------------------

  Widget _appearance() {
    final mq = context.mq;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FieldLabel(tr('Main picture')),
        const SizedBox(height: 8),
        Text(
          tr('The face every shot keeps. Everything else about this actor is '
              'built on it.'),
          style: TextStyle(
            color: mq.textTertiary,
            fontSize: MqTheme.fontSmall,
            height: MqTheme.lineTight,
          ),
        ),
        const SizedBox(height: MqTheme.gap),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            GhostButton(text: tr('Shoot it again'), onPressed: _reshoot),
            GhostButton(text: tr('Replace with a file'), onPressed: _replace),
          ],
        ),
        const SizedBox(height: MqTheme.gapLarge),
        MediaDropZone(
          paths: _draft.media,
          title: tr('Reference pictures'),
          hint: tr('The first one is the face every shot keeps.'),
          tileSize: 56,
          onAdded: (paths) => setState(() {
            for (final path in paths) {
              if (!_draft.media.contains(path)) _draft.media.add(path);
            }
          }),
          onRemoved: (index) => setState(() => _draft.media.removeAt(index)),
          onPrimary: (index) => setState(() {
            _draft.media.insert(0, _draft.media.removeAt(index));
          }),
        ),
      ],
    );
  }

  /// Back into the studio to shoot the picture again, carrying everything this
  /// actor already knows -- so "same person, but outdoors" is one sentence
  /// rather than starting over.
  Future<void> _reshoot() async {
    _collect();
    final id = await showAssetStudio(
      context,
      app: widget.app,
      kind: AssetKind.actor,
      asset: _draft,
    );
    if (id != null && mounted) closeMqModal(context, id);
  }

  Future<void> _replace() async {
    final file = await openFile(acceptedTypeGroups: const [imageTypeGroup]);
    if (file == null || !mounted) return;
    setState(() {
      _draft.previewPath = file.path;
      if (!_draft.media.contains(file.path)) _draft.media.insert(0, file.path);
    });
  }

  // ---- section: voice ------------------------------------------------------

  Widget _voice() {
    final mq = context.mq;
    final booth = widget.app.voiceBooth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        VoicePicker(
          app: widget.app,
          draft: _draft,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: MqTheme.gapLarge),
        FieldLabel(tr('Delivery')),
        const SizedBox(height: 8),
        Text(
          tr('The difference between a read that sounds human and one that '
              'sounds like an announcer.'),
          style: TextStyle(
            color: mq.textTertiary,
            fontSize: MqTheme.fontSmall,
            height: MqTheme.lineTight,
          ),
        ),
        const SizedBox(height: 8),
        _dial(tr('Speed'), 'voiceSpeed', 0.7, 1.2, 1.0),
        _dial(tr('Stability'), 'voiceStability', 0, 1, 0.45),
        _dial(tr('Similarity'), 'voiceSimilarity', 0, 1, 0.8),
        _dial(tr('Style exaggeration'), 'voiceStyle', 0, 1, 0.35),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                booth.error.isEmpty
                    ? tr('Hearing them costs a fraction of a cent.')
                    : booth.error,
                style: TextStyle(
                  color: booth.error.isEmpty ? mq.textTertiary : mq.error,
                  fontSize: MqTheme.fontSmall,
                  height: MqTheme.lineTight,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GhostButton(
              text: booth.auditioning ? tr('Listening…') : tr('Hear them'),
              enabled: !booth.auditioning &&
                  _draft.extraText('voiceId').isNotEmpty,
              onPressed: () => booth.audition(
                _draft.extras,
                tr('Honestly, I did not think this would work.'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dial(
    String label,
    String key,
    double from,
    double to,
    double fallback,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: LabeledSlider(
        label: label,
        value: _draft.extraNumber(key, fallback),
        from: from,
        to: to,
        onChanged: (value) => setState(() => _draft.setExtra(key, value)),
      ),
    );
  }

  // ---- section: personality ------------------------------------------------

  Widget _personality() {
    final mq = context.mq;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LabeledArea(
          controller: _action,
          label: tr('What are they doing?'),
          areaHeight: 64,
          placeholder: tr(
            'Talking to camera, holding the product, small natural gestures…',
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tr('Handed to the video model as the motion for every shot they are '
              'in.'),
          style: TextStyle(
            color: mq.textTertiary,
            fontSize: MqTheme.fontSmall,
            height: MqTheme.lineTight,
          ),
        ),
        const SizedBox(height: MqTheme.gapLarge),
        PersonaEditor(
          draft: _draft,
          styleController: _style,
          onChanged: () => setState(() {}),
        ),
      ],
    );
  }

  // ---- section: looks ------------------------------------------------------

  /// The wardrobe.
  ///
  /// An actor is not one photograph. Sarah at a desk and Sarah in a gym are the
  /// same person, and the alternative -- one actor per outfit -- means casting,
  /// voicing and describing her once per outfit and then keeping the copies in
  /// step by hand.
  Widget _looks() {
    final mq = context.mq;
    final looks = ActorLooks.of(_draft);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tr('The same person, dressed for a different ad. The default is the '
              'main picture; anything else you add can be picked per ad.'),
          style: TextStyle(
            color: mq.textTertiary,
            fontSize: MqTheme.fontSmall,
            height: MqTheme.lineBody,
          ),
        ),
        const SizedBox(height: MqTheme.gap),
        Wrap(
          spacing: MqTheme.gap,
          runSpacing: MqTheme.gap,
          children: [
            _LookTile(
              name: tr('Default'),
              path: _draft.thumbnail,
              isDefault: true,
              onTap: () => showMediaPreview(context, _draft.thumbnail),
            ),
            for (final look in looks)
              _LookTile(
                name: look.name,
                path: look.path,
                onTap: () => showMediaPreview(context, look.path),
                onMakeDefault: () => setState(() {
                  // Swapping rather than overwriting: the picture standing down
                  // becomes a look of its own, so promoting one can never lose
                  // the one it replaced.
                  final previous = _draft.previewPath;
                  final updated = [
                    for (final entry in ActorLooks.of(_draft))
                      if (entry.id != look.id) entry,
                    if (previous.isNotEmpty)
                      ActorLook(
                        id: ActorLooks.newId(),
                        name: tr('Previous'),
                        path: previous,
                        prompt: _draft.prompt,
                      ),
                  ];
                  _draft.previewPath = look.path;
                  ActorLooks.save(_draft, updated);
                }),
                onRemove: () => setState(() {
                  ActorLooks.save(_draft, [
                    for (final entry in ActorLooks.of(_draft))
                      if (entry.id != look.id) entry,
                  ]);
                }),
              ),
            _AddLookTile(onTap: _createLook),
          ],
        ),
        if (looks.isEmpty) ...[
          const SizedBox(height: MqTheme.gap),
          Text(
            tr('No extra looks yet.'),
            style: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontSmall,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _createLook() async {
    final look = await showLookMaker(context, app: widget.app, actor: _draft);
    if (look == null || !mounted) return;
    setState(() {
      ActorLooks.save(_draft, [...ActorLooks.of(_draft), look]);
    });
  }
}

/// A row of the section rail.
class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      snap: true,
      focusRadius: MqTheme.radiusSmall,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? mq.surfaceActive
              : states.active
              ? mq.surfaceHover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        ),
        child: Row(
          children: [
            MqIcon(
              icon,
              size: 15,
              color: selected ? mq.textPrimary : mq.textTertiary,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? mq.textPrimary : mq.textSecondary,
                  fontSize: MqTheme.fontLabel,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A label-and-value list, for the facts nobody edits.
class _Facts extends StatelessWidget {
  const _Facts({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; ++i) ...[
          if (i > 0) ...[
            const SizedBox(height: 8),
            Container(height: 1, color: mq.borderSubtle),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  rows[i].$1,
                  style: TextStyle(
                    color: mq.textSecondary,
                    fontSize: MqTheme.fontLabel,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  rows[i].$2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: mq.textPrimary,
                    fontSize: MqTheme.fontLabel,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One look in the wardrobe.
class _LookTile extends StatelessWidget {
  const _LookTile({
    required this.name,
    required this.path,
    required this.onTap,
    this.isDefault = false,
    this.onMakeDefault,
    this.onRemove,
  });

  final String name;
  final String path;
  final VoidCallback onTap;
  final bool isDefault;
  final VoidCallback? onMakeDefault;
  final VoidCallback? onRemove;

  static const double width = 118;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return SizedBox(
      width: width,
      child: MediaMenu(
        path: path,
        actions: [
          MediaMenuAction(
            icon: 'fullscreen-line',
            label: tr('View full size'),
            onPressed: onTap,
          ),
          if (onMakeDefault != null)
            MediaMenuAction(
              icon: 'star-line',
              label: tr('Make this the default'),
              onPressed: onMakeDefault!,
            ),
        ],
        onRemove: onRemove,
        removeLabel: tr('Remove this look'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: Pressable(
                onTap: onTap,
                snap: true,
                focusRadius: MqTheme.radius,
                builder: (context, states) => AnimatedContainer(
                  duration: states.duration,
                  decoration: BoxDecoration(
                    color: mq.background,
                    borderRadius: BorderRadius.circular(MqTheme.radius),
                    border: Border.all(
                      color: isDefault
                          ? mq.primary
                          : states.active
                          ? mq.borderStrong
                          : mq.border,
                      width: isDefault ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: path.isEmpty
                      ? Center(
                          child: MqIcon(
                            'user-smile-line',
                            size: 20,
                            color: mq.textTertiary,
                          ),
                        )
                      : LocalImage(path),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: mq.textPrimary,
                fontSize: MqTheme.fontSmall,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isDefault)
              Text(
                tr('Used when nothing else is picked'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontMicro,
                  height: MqTheme.lineTight,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddLookTile extends StatelessWidget {
  const _AddLookTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return SizedBox(
      width: _LookTile.width,
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Pressable(
          onTap: onTap,
          snap: true,
          focusRadius: MqTheme.radius,
          builder: (context, states) => AnimatedContainer(
            duration: states.duration,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: states.active ? mq.surfaceHover : mq.surfaceSecondary,
              borderRadius: BorderRadius.circular(MqTheme.radius),
              border: Border.all(
                color: states.active ? mq.borderStrong : mq.border,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MqIcon(
                  'add-line',
                  size: 20,
                  color: states.active ? mq.textSecondary : mq.textTertiary,
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Create a look'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: mq.textSecondary,
                    fontSize: MqTheme.fontSmall,
                    height: MqTheme.lineTight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- making a look ---------------------------------------------------------

/// Another picture of the same actor: same face, different clothes or place.
///
/// It is the casting studio again, seeded with the actor's own picture as the
/// reference -- which is exactly what keeps the face -- so nothing new had to
/// be built for it. Returns the look, or null.
Future<ActorLook?> showLookMaker(
  BuildContext context, {
  required AppState app,
  required LibraryAsset actor,
}) {
  return showMqModal<ActorLook>(
    context: context,
    dismissible: false,
    child: _LookMaker(app: app, actor: actor),
  );
}

class _LookMaker extends StatefulWidget {
  const _LookMaker({required this.app, required this.actor});

  final AppState app;
  final LibraryAsset actor;

  @override
  State<_LookMaker> createState() => _LookMakerState();
}

class _LookMakerState extends State<_LookMaker> {
  /// A throwaway asset, only ever used to drive the forge: the look it produces
  /// is copied out of it and this is dropped.
  late final LibraryAsset _draft = LibraryAsset(
    name: widget.actor.name,
    prompt: widget.actor.prompt,
    media: [
      if (widget.actor.previewPath.isNotEmpty) widget.actor.previewPath,
    ],
  );

  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    closeMqModal(
      context,
      ActorLook(
        id: ActorLooks.newId(),
        name: _name.text.trim().isEmpty ? tr('New look') : _name.text.trim(),
        path: _draft.previewPath,
        prompt: _draft.prompt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = studioSize(MediaQuery.sizeOf(context));
    final chosen = _draft.previewPath.isNotEmpty;

    return MqModalCard(
      width: size.width,
      //: %1 is an actor's name
      title: tr('A new look for %1').arg(widget.actor.name),
      subtitle: tr('Their own picture goes in as the reference, so the face '
          'survives. Say what changes.'),
      actions: [
        GhostButton(text: tr('Cancel'), onPressed: () => closeMqModal(context)),
        PrimaryButton(
          text: tr('Keep this look'),
          enabled: chosen,
          tooltip: chosen ? '' : tr('Pick one of the pictures first.'),
          onPressed: _save,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 360,
            child: LabeledField(
              controller: _name,
              label: tr('What is this look called?'),
              placeholder: tr('Business, Gym, Evening…'),
            ),
          ),
          const SizedBox(height: MqTheme.gap),
          AssetForge(
            app: widget.app,
            kind: AssetKind.actor,
            draft: _draft,
            height: size.height,
            onChanged: () => setState(() {}),
          ),
        ],
      ),
    );
  }
}
