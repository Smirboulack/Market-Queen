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
/// Three columns: where you are, who you are looking at, and the one subject
/// you are changing. The middle column never moves, because every control on
/// the right is a claim about the person in it.
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

  /// Public so a test can walk the sections by name rather than by index.
  static String labelFor(ActorSection section) => switch (section) {
        ActorSection.overview => tr('Overview'),
        ActorSection.appearance => tr('Appearance'),
        ActorSection.voice => tr('Voice'),
        ActorSection.personality => tr('Personality'),
        ActorSection.looks => tr('Looks'),
      };

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

  /// Which of the wardrobe is in the big frame. Zero is the actor's own
  /// picture. Looking at a look is not the same as promoting it, so this
  /// changes nothing on the draft.
  int _showing = 0;

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

  void _go(ActorSection section) => setState(() => _section = section);

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 100).clamp(840.0, 1280.0);
    final height = (screen.height - 250).clamp(430.0, 720.0);

    return MqModalCard(
      width: width,
      title: tr('Edit the actor'),
      subtitle: tr("The actor's identity, appearance, voice and personality."),
      actions: [
        GhostButton(
          text: tr('Delete the actor'),
          destructive: true,
          onPressed: _delete,
        ),
        GhostButton(text: tr('Cancel'), onPressed: () => closeMqModal(context)),
        PrimaryButton(text: tr('Save changes'), onPressed: _save),
      ],
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 178, child: _rail()),
            const SizedBox(width: MqTheme.gapLarge),
            SizedBox(
              width: 264,
              child: SingleChildScrollView(child: _identity()),
            ),
            const SizedBox(width: MqTheme.gapLarge),
            Expanded(child: SingleChildScrollView(child: _body())),
          ],
        ),
      ),
    );
  }

  // ---- the rail ------------------------------------------------------------

  Widget _rail() {
    final looks = ActorLooks.of(_draft).length;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final section in ActorSection.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: _RailRow(
              icon: _iconFor(section),
              label: ActorEditor.labelFor(section),
              selected: _section == section,
              // Only where there is something to count. A "0" beside Looks
              // says what the empty section already says, twice.
              count: section == ActorSection.looks && looks > 0 ? looks : 0,
              onTap: () => _go(section),
            ),
          ),
      ],
    );
  }

  String _iconFor(ActorSection section) => switch (section) {
        ActorSection.overview => 'layout-line',
        ActorSection.appearance => 'image-line',
        ActorSection.voice => 'user-voice-line',
        ActorSection.personality => 'emotion-line',
        ActorSection.looks => 'gallery-line',
      };

  // ---- the middle column ---------------------------------------------------

  /// Every look the actor has, the default first. The strip under the portrait
  /// and the grid in the Looks section are two views of this one list.
  List<({String name, String path})> get _wardrobe => [
        (name: tr('Default'), path: _draft.thumbnail),
        for (final look in ActorLooks.of(_draft))
          (name: look.name, path: look.path),
      ];

  Widget _identity() {
    final mq = context.mq;
    final wardrobe = _wardrobe;
    final shown =
        _showing < wardrobe.length ? wardrobe[_showing] : wardrobe.first;
    final take = _draft.extraText('takePath');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 4 / 5,
          child: Stack(
            children: [
              Positioned.fill(child: _portrait(shown.path)),
              // The way into the picture, on the picture. Everything else about
              // an actor is edited on the right; the face is the one thing you
              // reach for by pointing at it.
              PositionedDirectional(
                end: 8,
                top: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: mq.surface.withValues(alpha: 0.92),
                    shape: BoxShape.circle,
                    border: Border.all(color: mq.border),
                  ),
                  child: MqIconButton(
                    icon: 'edit-line',
                    tip: tr('Change the picture'),
                    size: 30,
                    onPressed: () => _go(ActorSection.appearance),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _wardrobeStrip(wardrobe),
        const SizedBox(height: MqTheme.gap),
        Row(
          children: [
            Flexible(
              child: Text(
                _name.text.trim().isEmpty ? _draft.name : _name.text.trim(),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mq.textPrimary,
                  fontSize: MqTheme.fontTitle,
                  fontWeight: FontWeight.w600,
                  letterSpacing: MqTheme.trackTitle,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Capped, and not by taste: a Row lays its inflexible children out
            // with an unbounded main axis, so a badge with a long translation
            // in it takes three hundred pixels of a two-hundred-and-sixty pixel
            // column and pushes the name off the end. The ceiling is what makes
            // that impossible rather than merely unlikely.
            Flexible(child: _Pill(label: _madeLabel)),
          ],
        ),
        if (_prompt.text.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            _prompt.text.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontSmall,
              height: MqTheme.lineTight,
            ),
          ),
        ],
        const SizedBox(height: MqTheme.gap),
        _Facts(rows: _factRows),
        const SizedBox(height: MqTheme.gap),
        GhostButton(
          text: tr('Preview the actor'),
          enabled: take.isNotEmpty,
          onPressed: () => showMediaPreview(context, take),
        ),
        if (take.isEmpty) ...[
          const SizedBox(height: 6),
          Text(
            tr('No clip of the actor yet. One is filmed on the last step of the creation wizard.'),
            style: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontSmall,
              height: MqTheme.lineTight,
            ),
          ),
        ],
      ],
    );
  }

  /// How this actor came into being, as a badge.
  ///
  /// Two words at most. It sits beside the name on a 264px column, and a badge
  /// that needs a sentence is a caption pretending to be a badge.
  String get _madeLabel => switch (_draft.extraText('createdVia')) {
        'fromImage' => tr('From a photo'),
        'describe' => tr('Described'),
        _ => tr('Actor'),
      };

  List<({String icon, String label, String value})> get _factRows {
    final age = VoiceTrait.labelFor('voiceAge', _draft.extraText('voiceAge'));
    final gender =
        VoiceTrait.labelFor('voiceGender', _draft.extraText('voiceGender'));
    final locale = VoiceLocale.find(_draft.extraText('voiceLocale'))?.label;

    return [
      (icon: 'timer-line', label: tr('Age'), value: age.isEmpty ? _unset : age),
      (
        icon: 'user-line',
        label: tr('Gender'),
        value: gender.isEmpty ? _unset : gender,
      ),
      (
        icon: 'translate-line',
        label: tr('Language'),
        // An unset language is not "none": it is whatever the ad is written
        // in, which is what the caster will actually search on.
        value: locale ?? tr('Same as the ad'),
      ),
      (
        icon: 'calendar-line',
        label: tr('Created'),
        value: Format.day(_draft.createdAt),
      ),
      (
        icon: 'history-line',
        label: tr('Last changed'),
        value: Format.day(_draft.updatedAt),
      ),
    ];
  }

  String get _unset => tr('Not set');

  Widget _portrait(String path) {
    final mq = context.mq;
    if (path.isEmpty) {
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
      path: path,
      actions: [
        MediaMenuAction(
          icon: 'fullscreen-line',
          label: tr('View full size'),
          onPressed: () => showMediaPreview(context, path),
        ),
      ],
      child: Pressable(
        onTap: () => showMediaPreview(context, path),
        tooltip: tr('View full size'),
        focusRadius: MqTheme.radius,
        builder: (context, states) => AnimatedContainer(
          duration: states.duration,
          decoration: BoxDecoration(
            color: mq.background,
            borderRadius: BorderRadius.circular(MqTheme.radius),
            border: Border.all(
              color: states.active ? mq.borderStrong : mq.border,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: LocalImage(path),
        ),
      ),
    );
  }

  /// The wardrobe as a row of thumbnails under the face.
  ///
  /// It is a viewer, not a picker: pressing one changes which look is in the
  /// big frame and nothing else. Promoting one is a decision with consequences
  /// for every ad that casts this actor, and it lives in the Looks section
  /// where there is room to say so.
  Widget _wardrobeStrip(List<({String name, String path})> wardrobe) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          for (var i = 0; i < wardrobe.length; ++i)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _StripTile(
                path: wardrobe[i].path,
                name: wardrobe[i].name,
                selected: i == _showing,
                onTap: () => setState(() => _showing = i),
              ),
            ),
          _StripAdd(onTap: _createLook),
        ],
      ),
    );
  }

  // ---- the right-hand column -----------------------------------------------

  Widget _body() => switch (_section) {
        ActorSection.overview => _overview(),
        ActorSection.appearance => _appearance(),
        ActorSection.voice => _voice(),
        ActorSection.personality => _personality(),
        ActorSection.looks => _looks(),
      };

  // ---- section: overview ---------------------------------------------------

  Widget _overview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionCard(
          title: tr('General'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final name = LabeledField(
                    controller: _name,
                    label: tr("Actor's name"),
                    placeholder: widget.app.actors.suggestedName(),
                    onChanged: (_) => setState(() {}),
                  );
                  final description = LabeledArea(
                    controller: _prompt,
                    label: tr('Description'),
                    areaHeight: 76,
                    placeholder: tr('A woman in her twenties, tired, no '
                        'make-up, plain grey t-shirt…'),
                    onChanged: (_) => setState(() {}),
                  );

                  // Side by side where there is room, stacked where there is
                  // not: this column is the one that gives when the window
                  // narrows, and a two-up row of fields at 300px is two
                  // unusable fields.
                  if (constraints.maxWidth < 520) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        name,
                        const SizedBox(height: MqTheme.gap),
                        description,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: name),
                      const SizedBox(width: MqTheme.gap),
                      Expanded(child: description),
                    ],
                  );
                },
              ),
              const SizedBox(height: 6),
              _Hint(tr('The description is what the image model is told, and '
                  'what the search box matches on.')),
              const SizedBox(height: MqTheme.gap),
              Wrap(
                spacing: MqTheme.gap,
                runSpacing: MqTheme.gap,
                children: [
                  SizedBox(width: 216, child: _languageField()),
                  SizedBox(width: 216, child: _genderField()),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: MqTheme.gap),
        _SectionCard(
          title: tr('At a glance'),
          child: Wrap(
            spacing: MqTheme.gap,
            runSpacing: MqTheme.gap,
            children: [
              _SummaryTile(
                icon: 'image-line',
                title: tr('Appearance'),
                //: %1 is a number of pictures
                value: tr('%1 picture(s)').arg(_draft.media.length),
                action: tr('Change'),
                onTap: () => _go(ActorSection.appearance),
              ),
              _SummaryTile(
                icon: 'user-voice-line',
                title: tr('Voice'),
                value: _voiceSummary,
                action: tr('Change'),
                onTap: () => _go(ActorSection.voice),
              ),
              _SummaryTile(
                icon: 'emotion-line',
                title: tr('Personality'),
                value: _personaSummary,
                action: tr('Change'),
                onTap: () => _go(ActorSection.personality),
              ),
              _SummaryTile(
                icon: 'gallery-line',
                title: tr('Looks'),
                //: %1 is a number of looks
                value: tr('%1 look(s)').arg(_wardrobe.length),
                action: tr('Manage'),
                onTap: () => _go(ActorSection.looks),
              ),
            ],
          ),
        ),
        const SizedBox(height: MqTheme.gap),
        _SectionCard(title: tr('Quick listen'), child: _audition()),
      ],
    );
  }

  Widget _languageField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FieldLabel(tr('Main language')),
        const SizedBox(height: 6),
        StyledCombo<String>(
          value: _draft.extraText('voiceLocale'),
          options: [
            MenuEntry(tr('Same as the ad'), ''),
            for (final locale in VoiceLocale.all)
              MenuEntry(locale.menuLabel, locale.id),
          ],
          onPicked: (value) =>
              setState(() => _draft.setExtra('voiceLocale', value)),
        ),
      ],
    );
  }

  Widget _genderField() {
    final trait = VoiceTrait.all.firstWhere((t) => t.key == 'voiceGender');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FieldLabel(tr('Gender')),
        const SizedBox(height: 6),
        StyledCombo<String>(
          value: _draft.extraText('voiceGender'),
          options: [
            MenuEntry(tr("doesn't matter"), ''),
            for (final option in trait.options)
              MenuEntry(option.$1, option.$2),
          ],
          onPicked: (value) =>
              setState(() => _draft.setExtra('voiceGender', value)),
        ),
      ],
    );
  }

  String get _voiceSummary {
    final name = _draft.extraText('voiceName');
    if (name.isEmpty) return tr('Cast at render time');
    return switch (_draft.extraText('voiceKind')) {
      'designed' => tr('Designed'),
      'cloned' => tr('Cloned'),
      _ => tr('Library'),
    };
  }

  String get _personaSummary {
    final traits = ActorPersona.traitsOf(_draft);
    if (traits.isEmpty) return tr('Not set');
    return traits.take(2).map(ActorPersona.labelFor).join(tr(', '));
  }

  /// The one control worth having on two screens: hearing them.
  ///
  /// It is on the Overview because it is the fastest answer to "is this actor
  /// right", and in the Voice section because that is where you have just
  /// changed something and want to hear what it did.
  Widget _audition() {
    final mq = context.mq;
    final booth = widget.app.voiceBooth;

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: mq.surfaceSecondary,
            shape: BoxShape.circle,
            border: Border.all(color: mq.border),
          ),
          child: MqIcon(
            booth.auditioning ? 'loader-4-line' : 'play-fill',
            size: 16,
            color: mq.textSecondary,
          ),
        ),
        const SizedBox(width: MqTheme.gap),
        Expanded(
          child: Text(
            booth.error.isEmpty
                ? tr('Hear a line in this voice. It costs a fraction of a cent.')
                : booth.error,
            style: TextStyle(
              color: booth.error.isEmpty ? mq.textTertiary : mq.error,
              fontSize: MqTheme.fontSmall,
              height: MqTheme.lineTight,
            ),
          ),
        ),
        const SizedBox(width: MqTheme.gap),
        GhostButton(
          text: booth.auditioning ? tr('Listening…') : tr('Listen'),
          enabled: !booth.auditioning && _draft.extraText('voiceId').isNotEmpty,
          onPressed: () => booth.audition(
            _draft.extras,
            tr('Honestly, I did not think this would work.'),
          ),
        ),
      ],
    );
  }

  // ---- section: appearance -------------------------------------------------

  Widget _appearance() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionCard(
          title: tr('Main picture'),
          subtitle: tr('The face every shot keeps. Everything else about this '
              'actor is built on it.'),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GhostButton(text: tr('Shoot it again'), onPressed: _reshoot),
              GhostButton(text: tr('Replace with a file'), onPressed: _replace),
            ],
          ),
        ),
        const SizedBox(height: MqTheme.gap),
        _SectionCard(
          title: tr('Reference pictures'),
          subtitle: tr('The first one is the face every shot keeps.'),
          child: MediaDropZone(
            paths: _draft.media,
            title: tr('Drop pictures in'),
            hint: tr('PNG, JPG or WebP.'),
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
      _showing = 0;
    });
  }

  // ---- section: voice ------------------------------------------------------

  Widget _voice() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionCard(
          title: tr('Voice'),
          subtitle: tr('Pick a voice, invent one, or clone your own.'),
          child: VoicePicker(
            app: widget.app,
            draft: _draft,
            onChanged: () => setState(() {}),
          ),
        ),
        const SizedBox(height: MqTheme.gap),
        _SectionCard(
          title: tr('Delivery'),
          subtitle: tr('The difference between a read that sounds human and '
              'one that sounds like an announcer.'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _dial(tr('Speed'), 'voiceSpeed', 0.7, 1.2, 1.0),
              _dial(tr('Stability'), 'voiceStability', 0, 1, 0.45),
              _dial(tr('Similarity'), 'voiceSimilarity', 0, 1, 0.8),
              _dial(tr('Style exaggeration'), 'voiceStyle', 0, 1, 0.35),
              const SizedBox(height: 8),
              _audition(),
            ],
          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionCard(
          title: tr('What is the actor doing?'),
          subtitle: tr('Handed to the video model as the motion for every shot the actor is in.'),
          child: LabeledArea(
            controller: _action,
            areaHeight: 64,
            placeholder: tr(
              'Talking to camera, holding the product, small natural gestures…',
            ),
          ),
        ),
        const SizedBox(height: MqTheme.gap),
        _SectionCard(
          title: tr('Personality'),
          subtitle: tr('All of this goes to the script writer as direction for '
              'this actor.'),
          child: PersonaEditor(
            draft: _draft,
            styleController: _style,
            onChanged: () => setState(() {}),
          ),
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

    return _SectionCard(
      title: tr('Looks'),
      subtitle: tr('The same person, dressed for a different ad. The default '
          'is the main picture; anything else you add can be picked per ad.'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
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
                    // Swapping rather than overwriting: the picture standing
                    // down becomes a look of its own, so promoting one can
                    // never lose the one it replaced.
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
                    _showing = 0;
                  }),
                  onRemove: () => setState(() {
                    ActorLooks.save(_draft, [
                      for (final entry in ActorLooks.of(_draft))
                        if (entry.id != look.id) entry,
                    ]);
                    _showing = 0;
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
      ),
    );
  }

  Future<void> _createLook() async {
    _collect();
    final look = await showLookMaker(context, app: widget.app, actor: _draft);
    if (look == null || !mounted) return;
    setState(() {
      ActorLooks.save(_draft, [...ActorLooks.of(_draft), look]);
    });
  }
}

// ---- the pieces the sections are built from --------------------------------

/// One subject, in its own frame.
///
/// The sections used to be bare stacks of controls, which made a screen with
/// four unrelated things on it read as one long form. A card with a heading is
/// what says "this part is about the voice, and it ends here".
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle = '',
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: mq.surface,
        borderRadius: BorderRadius.circular(MqTheme.radius),
        border: Border.all(color: mq.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
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
          const SizedBox(height: MqTheme.gap + 2),
          child,
        ],
      ),
    );
  }
}

/// A grey line under a field.
class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.mq.textTertiary,
        fontSize: MqTheme.fontSmall,
        height: MqTheme.lineTight,
      ),
    );
  }
}

/// A row of the section rail.
class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count = 0,
  });

  final String icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int count;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      snap: true,
      focusRadius: MqTheme.radiusSmall,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
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
              size: 16,
              color: selected ? mq.textPrimary : mq.textTertiary,
            ),
            const SizedBox(width: 10),
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
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: mq.surfaceTertiary,
                  borderRadius: BorderRadius.circular(MqTheme.radiusPill),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: mq.textSecondary,
                    fontSize: MqTheme.fontMicro,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The small badge beside the actor's name: how they were made.
class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radiusPill),
        border: Border.all(color: mq.border),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: TextStyle(
          color: mq.textTertiary,
          fontSize: MqTheme.fontMicro,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
      ),
    );
  }
}

/// A label-and-value list, for the facts nobody edits here.
class _Facts extends StatelessWidget {
  const _Facts({required this.rows});

  final List<({String icon, String label, String value})> rows;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radius),
        border: Border.all(color: mq.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; ++i) ...[
            if (i > 0) ...[
              const SizedBox(height: 7),
              Container(height: 1, color: mq.borderSubtle),
              const SizedBox(height: 7),
            ],
            Row(
              children: [
                MqIcon(rows[i].icon, size: 14, color: mq.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    rows[i].label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mq.textSecondary,
                      fontSize: MqTheme.fontSmall,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    rows[i].value,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: mq.textPrimary,
                      fontSize: MqTheme.fontSmall,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One tile of the overview's summary: what a section holds, and a way into it.
class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.action,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String value;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return SizedBox(
      width: 148,
      child: Pressable(
        onTap: onTap,
        snap: true,
        focusRadius: MqTheme.radius,
        builder: (context, states) => AnimatedContainer(
          duration: states.duration,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: states.active ? mq.surfaceHover : mq.surfaceSecondary,
            borderRadius: BorderRadius.circular(MqTheme.radius),
            border: Border.all(
              color: states.active ? mq.borderStrong : mq.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: mq.surface,
                  borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
                  border: Border.all(color: mq.border),
                ),
                child: MqIcon(icon, size: 15, color: mq.textSecondary),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mq.textPrimary,
                  fontSize: MqTheme.fontLabel,
                  fontWeight: FontWeight.w600,
                  height: MqTheme.lineTight,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontSmall,
                  height: MqTheme.lineTight,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                action,
                style: TextStyle(
                  color: mq.textPrimary,
                  fontSize: MqTheme.fontSmall,
                  fontWeight: FontWeight.w600,
                  decoration: states.active
                      ? TextDecoration.underline
                      : TextDecoration.none,
                  decorationColor: mq.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One thumbnail of the strip under the portrait.
class _StripTile extends StatelessWidget {
  const _StripTile({
    required this.path,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String path;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      tooltip: name,
      focusRadius: MqTheme.radiusSmall,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        width: 46,
        height: 52,
        decoration: BoxDecoration(
          color: mq.background,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          border: Border.all(
            color: selected
                ? mq.primary
                : states.active
                ? mq.borderStrong
                : mq.border,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: path.isEmpty
            ? Center(
                child: MqIcon(
                  'user-smile-line',
                  size: 15,
                  color: mq.textTertiary,
                ),
              )
            : LocalImage(path),
      ),
    );
  }
}

class _StripAdd extends StatelessWidget {
  const _StripAdd({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      tooltip: tr('Create a look'),
      focusRadius: MqTheme.radiusSmall,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        width: 46,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: states.active ? mq.surfaceHover : mq.surfaceSecondary,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          border: Border.all(color: states.active ? mq.borderStrong : mq.border),
        ),
        child: MqIcon(
          'add-line',
          size: 16,
          color: states.active ? mq.textSecondary : mq.textTertiary,
        ),
      ),
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
      maxHeight: size.height,
      //: %1 is an actor's name
      title: tr('A new look for %1').arg(widget.actor.name),
      subtitle: tr("The actor's own picture goes in as the reference, so the face survives. Say what changes."),
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
          Expanded(
            child: AssetForge(
              app: widget.app,
              kind: AssetKind.actor,
              draft: _draft,
              onChanged: () => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }
}
