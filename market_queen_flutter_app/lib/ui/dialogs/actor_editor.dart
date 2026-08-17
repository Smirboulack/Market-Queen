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
import '../widgets/voice_player.dart';
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
/// **Nothing on this screen scrolls.** Each section is laid out to the height
/// it is given, and the one thing allowed to overflow is the voice catalogue,
/// inside its own panel. That is not tidiness: this screen carries a player, a
/// portrait and a Save button that a scrolling page can put out of reach, and
/// the section you are working on has no business moving the actor you are
/// working on off the top of the window.
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

  /// The glyph for each section, and the only place it is decided: the rail and
  /// the overview's tiles both read it, so the wardrobe cannot be a hanger in
  /// one and a photo album in the other.
  static String iconFor(ActorSection section) => switch (section) {
        ActorSection.overview => 'layout-line',
        // A camera rather than a picture frame. This section is where the
        // photograph is taken or replaced, not where pictures are listed.
        ActorSection.appearance => 'camera-line',
        ActorSection.voice => 'user-voice-line',
        ActorSection.personality => 'emotion-line',
        // A hanger: a look is an outfit.
        ActorSection.looks => 'shirt-line',
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

  /// The screen's one player. Every disc on the page -- the card under the
  /// portrait, every row of the catalogue, all three designed takes -- drives
  /// this, so only one thing is ever making a noise and the card can show the
  /// progress of a voice that was started three sections ago.
  final AudioTransport _transport = AudioTransport();

  ActorSection _section = ActorSection.overview;

  /// Which of the wardrobe is in the big frame. Zero is the actor's own
  /// picture. Looking at a look is not the same as promoting it, so this
  /// changes nothing on the draft.
  int _showing = 0;

  /// Whether this window is big enough for the sections to be laid out to it.
  /// Settled once per build, in [build], and read by every section.
  bool _filled = true;

  /// Which voice the audition on disk was bought for.
  ///
  /// The booth keeps the last file it wrote and nothing else, so an audition
  /// outlives the voice that produced it. Without this, casting a second voice
  /// left the player showing the new name over the old recording -- the one
  /// mistake a player is not allowed to make.
  String _auditionedVoice = '';

  /// What each free-text field will take. Written down because the counter and
  /// the formatter have to agree, and because a ceiling somebody meets while
  /// typing has to have been visible before they started.
  static const int _nameLimit = 50;
  static const int _descriptionLimit = 250;

  /// The child takes the rest of the column on a page laid out to a height, and
  /// simply its own height on one that scrolls.
  Widget _grow(Widget child) => _filled ? Expanded(child: child) : child;

  @override
  void initState() {
    super.initState();
    widget.app.voiceBooth.addListener(_onBooth);
    // A design left over from the last actor edited is not this actor's.
    widget.app.voiceForge.reset();
  }

  @override
  void dispose() {
    widget.app.voiceBooth.removeListener(_onBooth);
    _transport.dispose();
    _name.dispose();
    _prompt.dispose();
    _action.dispose();
    _style.dispose();
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  /// An audition that has landed is played, not merely announced.
  ///
  /// The old screen bought one and left it on disk: the button said "Listen",
  /// the money was spent, and nothing came out of the speakers. Pressing play
  /// is the whole of what somebody meant, so the file goes straight into the
  /// transport the moment it exists.
  void _onBooth() {
    if (!mounted) return;
    final sample = widget.app.voiceBooth.samplePath;
    if (sample.isNotEmpty && !_transport.holds(sample)) {
      _auditionedVoice = _draft.extraText('voiceId');
      _transport.toggle(sample);
    }
    setState(() {});
  }

  /// The audition on disk, when it is still this voice's. Empty otherwise, so
  /// the card falls back to the provider's own sample rather than playing
  /// somebody else.
  String get _audition {
    final voice = _draft.extraText('voiceId');
    if (voice.isEmpty || voice != _auditionedVoice) return '';
    return widget.app.voiceBooth.samplePath;
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

  /// The room a section needs before it can be laid out to the page rather than
  /// down it.
  ///
  /// The design is 1280 x 775 on a 1440 x 900 window, and at that size nothing
  /// here scrolls. Below it something has to give, and the honest answer is a
  /// scrollbar on the one column that has more in it than there is room for --
  /// not a portrait squeezed to a stamp, and not a card silently clipping the
  /// field somebody is typing into. So the laid-out page is what you get on the
  /// window it was drawn for, and a short or narrow window falls back rather
  /// than overflowing.
  static const double _laidOutHeight = 540;
  static const double _laidOutWidth = 520;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 100).clamp(840.0, 1280.0);
    // 650 at the size this was drawn for, and the ceiling rather than the
    // number: the three columns are laid out to whatever this comes to, so a
    // laptop gets a shorter portrait and a shorter catalogue rather than a
    // scrollbar.
    final height = (screen.height - 250).clamp(430.0, 650.0);
    // What the right-hand column comes out at: the card's padding, the rail,
    // the portrait and the two gaps between them come off the top.
    final bodyWidth = width - MqTheme.gapLarge * 4 - 178 - 264;
    _filled = height >= _laidOutHeight && bodyWidth >= _laidOutWidth;

    return MqModalCard(
      width: width,
      title: tr('Edit the actor'),
      subtitle: tr("The actor's identity, appearance, voice and personality."),
      // At the far end of the footer, out of reach of Save. Two buttons that
      // differ by one being undoable should not be neighbours.
      leadingActions: [
        GhostButton(
          icon: 'delete-bin-line',
          text: tr('Delete the actor'),
          destructive: true,
          onPressed: _delete,
        ),
      ],
      actions: [
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
            SizedBox(width: 264, child: _identity()),
            const SizedBox(width: MqTheme.gapLarge),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  // ---- the rail ------------------------------------------------------------

  /// Which sections still have something in them nobody has answered.
  ///
  /// Not validation -- an actor with no reference pictures is saveable and
  /// works. It is the difference between a screen that lists five subjects and
  /// one that says which of them you have not finished, and it is the same
  /// answer in two places: the dot on the rail and the count on the overview.
  bool _unfinished(ActorSection section) => switch (section) {
        ActorSection.appearance => _draft.media.isEmpty,
        ActorSection.voice => _draft.extraText('voiceId').isEmpty,
        ActorSection.personality => ActorPersona.traitsOf(_draft).isEmpty,
        // A second look is an option, not an omission.
        _ => false,
      };

  int get _unfinishedCount =>
      ActorSection.values.where(_unfinished).length;

  Widget _rail() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in ActorSection.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: _RailRow(
              icon: ActorEditor.iconFor(section),
              label: ActorEditor.labelFor(section),
              selected: _section == section,
              unfinished: _unfinished(section),
              onTap: () => _go(section),
            ),
          ),
      ],
    );
  }

  // ---- the middle column ---------------------------------------------------

  /// Every look the actor has, the default first. The strip under the portrait
  /// and the grid in the Looks section are two views of this one list.
  List<({String name, String path})> get _wardrobe => [
        (name: tr('Default'), path: _draft.thumbnail),
        for (final look in ActorLooks.of(_draft))
          (name: look.name, path: look.path),
      ];

  /// Who this actor is, as one line under their name.
  ///
  /// It replaced five labelled rows -- Age, Gender, Language, Created, Changed
  /// -- in a bordered box. Three of those were the same three answers the
  /// Overview's own pickers were showing eight inches to the right, and a fact
  /// stated twice on one screen is a fact that can disagree with itself.
  String get _metaLine {
    final years = ActorIdentity.ageOf(_draft);
    final age = years > 0
        //: %1 is a whole number of years
        ? tr('%1 years old').arg(years)
        : VoiceTrait.labelFor('voiceAge', _draft.extraText('voiceAge'));
    final gender =
        VoiceTrait.labelFor('voiceGender', ActorIdentity.genderOf(_draft));
    final locale = VoiceLocale.find(_draft.extraText('voiceLocale'))?.label;

    return [
      if (gender.isNotEmpty) gender,
      age.isEmpty ? tr('Age not set') : age,
      // An unset language is not "none": it is whatever the ad is written in,
      // which is what the caster will actually search on.
      locale ?? tr('Same as the ad'),
    ].join(' · ');
  }

  Widget _identity() {
    final mq = context.mq;
    final wardrobe = _wardrobe;
    final shown =
        _showing < wardrobe.length ? wardrobe[_showing] : wardrobe.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The portrait takes what the fixed rows below it left. A 4:5 frame at
        // a fixed 330 is right at one window size and wrong at every other one;
        // the picture is cropped to fill either way.
        Expanded(
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
        const SizedBox(height: MqTheme.gap + 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                _name.text.trim().isEmpty ? _draft.name : _name.text.trim(),
                maxLines: 1,
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
        const SizedBox(height: 6),
        Text(
          _metaLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: mq.textSecondary,
            fontSize: MqTheme.fontSmall,
            height: MqTheme.lineTight,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          //: %1 and %2 are dates
          tr('Created %1 · changed %2')
              .arg(Format.day(_draft.createdAt))
              .arg(Format.day(_draft.updatedAt)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: mq.textTertiary,
            fontSize: MqTheme.fontMicro,
            height: MqTheme.lineTight,
          ),
        ),
        const SizedBox(height: MqTheme.gap + 2),
        _player(),
      ],
    );
  }

  /// The one player, under the portrait, on all five sections.
  ///
  /// It replaced three controls that all did some of this: "Quick listen" on
  /// the overview, "Test the voice" in the voice section's heading, and a
  /// "Listen" button that bought an audition and never played it. Who reads the
  /// ad is a fact about the person, so it belongs beside the person rather than
  /// in the section that happens to change it.
  Widget _player() {
    final booth = widget.app.voiceBooth;
    final sample = _audition;
    final preview = _draft.extraText('voicePreview');
    // What is already on disk first: an audition is this actor's own voice
    // reading with these four dials on, which the provider's stock sample is
    // not.
    final source = sample.isNotEmpty ? sample : preview;

    return VoicePlayerCard(
      transport: _transport,
      name: _draft.extraText('voiceName'),
      provenance: _provenance,
      source: source,
      busy: booth.auditioning,
      // Which of the two recordings this is, said plainly. A provider's sample
      // was made months ago and cannot carry the delivery dials, so somebody
      // who moves one and hears no difference is owed the reason rather than
      // left to conclude the dials are broken.
      note: booth.error.isNotEmpty
          ? booth.error
          : booth.auditioning
          ? tr('Buying a line…')
          : sample.isNotEmpty
          ? tr('Your read, with the delivery settings on it.')
          : preview.isNotEmpty
          ? tr("The provider's own sample. Free, and without the delivery "
              'settings.')
          : tr('Listening costs a fraction of a cent.'),
      onDetach: () {
        _auditionedVoice = '';
        _draft
          ..setExtra('voiceId', '')
          ..setExtra('voiceOwner', '')
          ..setExtra('voiceName', '')
          ..setExtra('voiceKind', '')
          ..setExtra('voiceDescription', '')
          ..setExtra('voicePreview', '');
        _transport.clear();
        _repaint();
      },
      // Nothing on disk and nothing free to fall back on: pressing play is how
      // somebody asks for a line to be read.
      onAudition: _draft.extraText('voiceId').isEmpty
          ? null
          : () => booth.audition(
                _draft.extras,
                tr('Honestly, I did not think this would work.'),
              ),
    );
  }

  String get _provenance => switch (_draft.extraText('voiceKind')) {
        'designed' => tr('Designed · ElevenLabs'),
        'cloned' => tr('Cloned from your recordings · ElevenLabs'),
        'library' => tr('Voice library · ElevenLabs'),
        _ => '',
      };

  /// How this actor came into being, as a badge.
  ///
  /// Two words at most. It sits beside the name on a 264px column, and a badge
  /// that needs a sentence is a caption pretending to be a badge.
  String get _madeLabel => switch (_draft.extraText('createdVia')) {
        'fromImage' => tr('From a photo'),
        'describe' => tr('Described'),
        _ => tr('Actor'),
      };

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

  /// The wardrobe as a row of thumbnails under the face, and the filmed take
  /// on the end of it.
  ///
  /// It is a viewer, not a picker: pressing a look changes which one is in the
  /// big frame and nothing else. Promoting one is a decision with consequences
  /// for every ad that casts this actor, and it lives in the Looks section
  /// where there is room to say so.
  ///
  /// The clip used to be a "Preview the actor" button that was disabled on
  /// every actor that had never been filmed -- which is most of them -- so the
  /// screen carried a dead control to say a clip did not exist. Here, an actor
  /// with no take simply has one fewer thumbnail.
  Widget _wardrobeStrip(List<({String name, String path})> wardrobe) {
    final take = _draft.extraText('takePath');

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
          if (take.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _StripTile(
                path: take,
                name: tr('The filmed take'),
                isClip: true,
                onTap: () => showMediaPreview(context, take),
              ),
            ),
          _StripAdd(onTap: _createLook),
        ],
      ),
    );
  }

  // ---- the right-hand column -----------------------------------------------

  Widget _body() {
    final section = switch (_section) {
      ActorSection.overview => _overview(),
      ActorSection.appearance => _appearance(),
      ActorSection.voice => _voice(),
      ActorSection.personality => _personality(),
      ActorSection.looks => _looks(),
    };

    return _filled ? section : SingleChildScrollView(child: section);
  }

  // ---- section: overview ---------------------------------------------------

  Widget _overview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: _filled ? MainAxisSize.max : MainAxisSize.min,
      children: [
        _SectionCard(
          title: tr('Identity'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final name = LabeledField(
                    controller: _name,
                    label: tr("Actor's name"),
                    maxLength: _nameLimit,
                    placeholder: widget.app.actors.suggestedName(),
                    hint: tr('The name the actor is cast under.'),
                    onChanged: (_) => setState(() {}),
                  );
                  final description = LabeledArea(
                    controller: _prompt,
                    label: tr('Description'),
                    areaHeight: 96,
                    maxLength: _descriptionLimit,
                    placeholder: tr('A woman in her twenties, tired, no '
                        'make-up, plain grey t-shirt…'),
                    onChanged: (_) => setState(() {}),
                  );
                  final hint = _Hint(
                    tr('Handed to the image model, and what the search box '
                        'matches on.'),
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
                        const SizedBox(height: 6),
                        hint,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: name),
                      const SizedBox(width: MqTheme.gap + 4),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            description,
                            const SizedBox(height: 6),
                            hint,
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: MqTheme.gap + 2),
              // Who the actor is, which is not a fact about their voice.
              // Changing the voice used to change both of these, so a woman of
              // 22 became "middle aged" the moment somebody picked a fuller
              // voice for her -- see [ActorIdentity].
              Wrap(
                spacing: MqTheme.gap,
                runSpacing: MqTheme.gap,
                children: [
                  SizedBox(width: 138, child: _ageField()),
                  SizedBox(width: 176, child: _genderField()),
                  SizedBox(width: 216, child: _languageField()),
                ],
              ),
              const SizedBox(height: 8),
              _Hint(tr('These three also aim the voice search.')),
            ],
          ),
        ),
        const SizedBox(height: MqTheme.gap),
        // Sized to its four lines rather than stretched to the bottom of the
        // column. A card that fills the page because the page is that tall is a
        // card with a hole in it.
        _SectionCard(
          title: tr('The actor so far'),
          action: Text(
            _unfinishedCount == 0
                ? tr('Nothing left to finish')
                //: %1 is a number of unfinished sections
                : tr('%1 thing(s) to finish').arg(_unfinishedCount),
            style: TextStyle(
              color: _unfinishedCount == 0
                  ? context.mq.textTertiary
                  : context.mq.warningText,
              fontSize: MqTheme.fontSmall,
            ),
          ),
          child: _statusGrid(),
        ),
      ],
    );
  }

  /// The four sections as a list: what each one holds, and the way into it.
  ///
  /// They used to carry a "Change" link underneath as well, which was a second
  /// target inside a tile that was already a target, doing the same thing.
  Widget _statusGrid() {
    final voice = _draft.extraText('voiceName');
    final looks = ActorLooks.of(_draft).length;

    final tiles = <Widget>[
      _StatusTile(
        icon: ActorEditor.iconFor(ActorSection.appearance),
        title: ActorEditor.labelFor(ActorSection.appearance),
        value: _draft.media.isEmpty
            ? tr('No reference picture')
            //: %1 is a number of pictures
            : tr('%1 reference picture(s)').arg(_draft.media.length),
        warn: _draft.media.isEmpty,
        onTap: () => _go(ActorSection.appearance),
      ),
      _StatusTile(
        icon: ActorEditor.iconFor(ActorSection.voice),
        title: ActorEditor.labelFor(ActorSection.voice),
        value: voice.isEmpty ? tr('Cast at render time') : voice,
        warn: voice.isEmpty,
        onTap: () => _go(ActorSection.voice),
      ),
      _StatusTile(
        icon: ActorEditor.iconFor(ActorSection.personality),
        title: ActorEditor.labelFor(ActorSection.personality),
        value: _personaSummary,
        warn: ActorPersona.traitsOf(_draft).isEmpty,
        onTap: () => _go(ActorSection.personality),
      ),
      _StatusTile(
        icon: ActorEditor.iconFor(ActorSection.looks),
        title: ActorEditor.labelFor(ActorSection.looks),
        value: looks == 0
            ? tr('The default look only')
            //: %1 is a number of looks besides the default
            : tr('%1 look(s) besides the default').arg(looks),
        onTap: () => _go(ActorSection.looks),
      ),
    ];

    // A list, not a grid of panels. Four bordered boxes inside a bordered card
    // was three frames deep for four short facts, and the boxes had to be
    // stretched to fill the card -- which put an inch of nothing under each
    // line. Rows separated by a hairline say the same thing and let the card be
    // the only frame.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < tiles.length; ++i) ...[
          if (i > 0) Container(height: 1, color: context.mq.borderSubtle),
          tiles[i],
        ],
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
          value: ActorIdentity.genderOf(_draft),
          options: [
            MenuEntry(tr('Not set'), ''),
            for (final option in trait.options)
              MenuEntry(option.$1, option.$2),
          ],
          onPicked: (value) =>
              setState(() => ActorIdentity.setGender(_draft, value)),
        ),
      ],
    );
  }

  /// The actor's age, in years.
  ///
  /// A number rather than one of the voice library's three bands, because a
  /// number is what somebody knows about the person they have just made and a
  /// band is what a search needs to be told. The band the voice is looked up
  /// under is worked out from it -- see [ActorIdentity.bandOf] -- so setting an
  /// age still narrows the voice search without being decided by it.
  Widget _ageField() {
    final years = ActorIdentity.ageOf(_draft);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FieldLabel(tr('Age')),
        const SizedBox(height: 6),
        StyledCombo<String>(
          value: years > 0 ? '$years' : '',
          options: [
            MenuEntry(tr('Not set'), ''),
            for (var age = ActorIdentity.minAge;
                age <= ActorIdentity.maxAge;
                ++age)
              //: %1 is a whole number of years
              MenuEntry(tr('%1 years old').arg(age), '$age'),
          ],
          onPicked: (value) => setState(
            () => ActorIdentity.setAge(_draft, int.tryParse(value) ?? 0),
          ),
        ),
      ],
    );
  }

  String get _personaSummary {
    final traits = ActorPersona.traitsOf(_draft);
    final energy = ActorPersona.energyOf(_draft);
    if (traits.isEmpty) return tr('Nothing said yet');
    return [
      traits.take(2).map(ActorPersona.labelFor).join(tr(', ')),
      //: %1 is a number between 0 and 1
      tr('energy %1').arg(energy.toStringAsFixed(2)),
    ].join(' · ');
  }

  // ---- section: appearance -------------------------------------------------

  Widget _appearance() {
    final mq = context.mq;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: _filled ? MainAxisSize.max : MainAxisSize.min,
      children: [
        _SectionCard(
          title: tr('Main picture'),
          subtitle: tr('The face every shot keeps. Everything else about this '
              'actor is built on it.'),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GhostButton(
                icon: 'camera-line',
                text: tr('Shoot it again'),
                onPressed: _reshoot,
              ),
              GhostButton(
                icon: 'upload-line',
                text: tr('Replace with a file'),
                onPressed: _replace,
              ),
            ],
          ),
        ),
        const SizedBox(height: MqTheme.gap),
        _grow(
          _SectionCard(
            title: tr('Reference pictures'),
            subtitle: tr('The first one is the face every shot keeps. Two or '
                'three angles is plenty.'),
            action: Text(
              //: %1 is a number of pictures
              tr('%1 picture(s)').arg(_draft.media.length),
              style: TextStyle(
                color: mq.textTertiary,
                fontSize: MqTheme.fontSmall,
              ),
            ),
            child: _grow(
              MediaDropZone(
                paths: _draft.media,
                title: tr('Drop pictures in'),
                hint: tr('PNG, JPG or WebP · or click to choose a file'),
                tileSize: 64,
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
            ),
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

  /// One card, four doors and the dials underneath.
  ///
  /// It used to be two cards -- "Choose a voice" and "Delivery" -- stacked in a
  /// scrolling column, with a shortlist that had its own scrollbar inside the
  /// first. Two scrollbars, one inside the other, and picking a voice meant
  /// scrolling the page back up to find the dials that change how it reads.
  Widget _voice() {
    return _SectionCard(
      title: tr('Voice'),
      subtitle: tr('Who reads the script, and how. The player on the left '
          'always plays the voice in place.'),
      action: _providerBadge(),
      child: _grow(
        VoicePicker(
          app: widget.app,
          draft: _draft,
          transport: _transport,
          onChanged: _repaint,
        ),
      ),
    );
  }

  /// Whether there is an account behind any of this, said once rather than
  /// discovered on each of the four tabs.
  Widget _providerBadge() {
    final mq = context.mq;
    final ready = widget.app.voiceForge.ready;

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radiusPill),
        border: Border.all(color: mq.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: ready ? mq.success : mq.warning,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            ready ? tr('ElevenLabs connected') : tr('No ElevenLabs key'),
            style: TextStyle(
              color: mq.textSecondary,
              fontSize: MqTheme.fontMicro,
            ),
          ),
        ],
      ),
    );
  }

  // ---- section: personality ------------------------------------------------

  Widget _personality() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: _filled ? MainAxisSize.max : MainAxisSize.min,
      children: [
        _SectionCard(
          title: tr('What is the actor doing?'),
          subtitle: tr('Handed to the video model as the motion for every shot '
              'the actor is in.'),
          child: LabeledArea(
            controller: _action,
            areaHeight: 64,
            maxLength: _descriptionLimit,
            placeholder: tr(
              'Talking to camera, holding the product, small natural gestures…',
            ),
          ),
        ),
        const SizedBox(height: MqTheme.gap),
        _grow(
          _SectionCard(
            title: tr('Personality'),
            subtitle: tr('All of this goes to the script writer as direction '
                'for this actor.'),
            child: _grow(
              PersonaEditor(
                draft: _draft,
                styleController: _style,
                fills: _filled,
                onChanged: _repaint,
              ),
            ),
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
      action: Text(
        //: %1 is a number of looks, counting the default
        tr('%1 look(s)').arg(looks.length + 1),
        style: TextStyle(color: mq.textTertiary, fontSize: MqTheme.fontSmall),
      ),
      child: _grow(
        SingleChildScrollView(
          // The wardrobe is the one grid with no ceiling on it -- an actor may
          // have twenty looks -- so it scrolls inside its own card rather than
          // taking the page with it.
          physics: _filled ? null : const NeverScrollableScrollPhysics(),
          child: Wrap(
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
        ),
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
///
/// [child] is laid out in a `Column`, so a section that should take the rest of
/// the card hands over an `Expanded` and one that should not simply does not.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle = '',
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget child;

  /// One control or one figure on the right of the heading: what this section
  /// holds, or the thing you do to it as a whole.
  final Widget? action;

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
              if (action != null) ...[
                const SizedBox(width: 10),
                action!,
              ],
            ],
          ),
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
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: context.mq.textTertiary,
        fontSize: MqTheme.fontSmall,
        height: MqTheme.lineTight,
      ),
    );
  }
}

/// A row of the section rail.
///
/// The dot is amber and five pixels across, and it is the only thing on the
/// rail that is not greyscale: "there is something here you have not answered"
/// is worth a colour, and a count in a pill would be a number nobody can act on
/// -- there is never more than one thing missing per section.
class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.unfinished = false,
  });

  final String icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool unfinished;

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
            if (unfinished) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: tr('Something here is not finished'),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: mq.warning,
                    shape: BoxShape.circle,
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

/// One line of the overview's status list: what a section holds, and the way
/// into it.
///
/// It says the *state*, not the count of things in it -- "No reference
/// picture", "Audrey - Energetic Commercial" -- because the state is the thing
/// somebody is checking, and it is amber when the state is "nobody has
/// answered this yet".
///
/// One line, one glyph, no frame of its own. It is inside a card already, and a
/// box drawn round every row of a list is a box round nothing.
class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.warn = false,
  });

  final String icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      snap: true,
      focusRadius: MqTheme.radiusSmall,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: states.active ? mq.surfaceHover : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        ),
        child: Row(
          children: [
            MqIcon(icon, size: 16, color: mq.textTertiary),
            const SizedBox(width: MqTheme.gap),
            SizedBox(
              // The four names line up, so the values start in one column and
              // the list reads down rather than zig-zagging.
              width: 92,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mq.textPrimary,
                  fontSize: MqTheme.fontLabel,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: MqTheme.gap),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: warn ? mq.warningText : mq.textTertiary,
                  fontSize: MqTheme.fontSmall,
                ),
              ),
            ),
            const SizedBox(width: 8),
            MqIcon(
              'arrow-right-s-line',
              size: 16,
              color: states.active ? mq.textSecondary : mq.textTertiary,
            ),
          ],
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
    required this.onTap,
    this.selected = false,
    this.isClip = false,
  });

  final String path;
  final String name;
  final VoidCallback onTap;
  final bool selected;

  /// The filmed take rather than a look: it opens in the previewer instead of
  /// going into the frame above, and carries a play badge to say so.
  final bool isClip;

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
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (path.isEmpty)
              Center(
                child: MqIcon(
                  isClip ? 'file-video-line' : 'user-smile-line',
                  size: 15,
                  color: mq.textTertiary,
                ),
              )
            else
              LocalImage(path),
            if (isClip)
              Center(
                child: Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: mq.overlay,
                    shape: BoxShape.circle,
                  ),
                  child: MqIcon('play-fill', size: 12, color: mq.textInverse),
                ),
              ),
          ],
        ),
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
