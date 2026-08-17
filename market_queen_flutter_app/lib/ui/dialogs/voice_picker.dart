import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app_state.dart';
import '../../core/http_util.dart';
import '../../i18n/translator.dart';
import '../../models/actor_smith.dart';
import '../../models/asset_library.dart';
import '../../models/voice_booth.dart';
import '../../models/voice_forge.dart';
import '../../models/voice_shelf.dart';
import '../../providers/types.dart';
import '../../providers/voice_profile.dart';
import '../../providers/voice_providers.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chip.dart';
import '../widgets/fields.dart';
import '../widgets/media_drop.dart';
import '../widgets/mq_dialog.dart';
import '../widgets/voice_player.dart';

/// The four ways an actor ends up with a voice.
///
/// The last three are genuinely different operations rather than three presets
/// of one, and the difference the user has to understand is about truth rather
/// than technique:
///
///  * [library] picks somebody who already exists and can be listened to first.
///  * [design] invents one from a description. It sounds like the brief; it is
///    nobody.
///  * [clone] copies a real voice off a recording, and is the only one of the
///    three where the app may say the voice *is* somebody's.
///
/// [mine] is not a fourth way of making one: it is everything the other three
/// already made. It exists because designing and cloning leave something
/// permanent on the account, and without a list of what is up there a voice
/// made for one actor was invisible to the next -- so the second actor got a
/// second design, and nobody could see, reuse or delete either.
enum VoiceRoute { mine, library, design, clone }

/// The voice section on its own, in the middle of the screen.
///
/// The composer's cast panel used to unfold the whole catalogue inside itself:
/// a 300px popover that already held a name, four dials and a note grew a
/// filter row, a scrolling list and a footer, and everything in it shrank to
/// make room. Choosing a voice is a job with a shortlist, five filters and a
/// play button per row -- it wants a table, not a drawer.
///
/// Saves through [onSaved] as it goes, on the same terms as the panel that
/// opens it: every control here is one value and changing it is the whole of
/// the intent, so there is nothing to cancel.
Future<void> showVoiceStudio(
  BuildContext context, {
  required AppState app,
  required LibraryAsset actor,
  required ValueChanged<LibraryAsset> onSaved,
}) {
  return showMqModal<void>(
    context: context,
    child: _VoiceStudio(app: app, actor: actor, onSaved: onSaved),
  );
}

class _VoiceStudio extends StatefulWidget {
  const _VoiceStudio({
    required this.app,
    required this.actor,
    required this.onSaved,
  });

  final AppState app;
  final LibraryAsset actor;
  final ValueChanged<LibraryAsset> onSaved;

  @override
  State<_VoiceStudio> createState() => _VoiceStudioState();
}

class _VoiceStudioState extends State<_VoiceStudio> {
  late final LibraryAsset _draft = widget.actor.copy();
  final AudioTransport _transport = AudioTransport();

  @override
  void dispose() {
    _transport.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 160).clamp(720.0, 1020.0);
    final height = (screen.height - 260).clamp(400.0, 620.0);

    return MqModalCard(
      width: width,
      //: %1 is an actor's name
      title: tr('The voice of %1').arg(_draft.name),
      subtitle: tr('Who reads the script, and how.'),
      actions: [
        PrimaryButton(
          text: tr('Done'),
          onPressed: () => closeMqModal(context),
        ),
      ],
      child: SizedBox(
        height: height,
        child: VoicePicker(
          app: widget.app,
          draft: _draft,
          transport: _transport,
          onChanged: () {
            widget.onSaved(_draft);
            setState(() {});
          },
        ),
      ),
    );
  }
}

/// The voice section: who reads the ad, and how.
///
/// Writes onto [draft] and nowhere else -- the caller decides when that draft
/// reaches the library -- so the same panel serves the creation wizard and the
/// editor's Voice section without either knowing about the other.
///
/// It does not play anything itself. Every disc on it drives [transport], which
/// belongs to the screen: the row you press and the player under the portrait
/// are two views of one transport, which is what stops three things playing at
/// once and what lets the card show the progress of a row you scrolled past.
class VoicePicker extends StatefulWidget {
  const VoicePicker({
    super.key,
    required this.app,
    required this.draft,
    required this.transport,
    required this.onChanged,
    this.suggestedDescription = '',
    this.bodyHeight = 330,
    this.showDials = true,
  });

  final AppState app;

  /// The actor being given a voice. Mutated in place.
  final LibraryAsset draft;

  /// The screen's one player.
  final AudioTransport transport;

  final VoidCallback onChanged;

  /// What the design box opens on. Filled in by the from-image route, where a
  /// vision model has already proposed one; empty everywhere else.
  final String suggestedDescription;

  /// How tall the route's own panel is when nobody has said.
  ///
  /// Two hosts, two answers. The editor gives this a card of a known height and
  /// wants the catalogue to be the one thing on the page that scrolls, so the
  /// panel takes whatever the tabs and the dials left. The wizard drops it into
  /// a scroll view, where there is no height to take a share of and a
  /// [Flexible] is an assertion rather than a layout -- so it gets this number
  /// instead. Which one applies is read off the constraints rather than passed
  /// in, so neither caller has to know the other exists.
  final double bodyHeight;

  /// The four interpretation dials, docked under the routes. Off in the wizard,
  /// where the actor has no voice yet and the dials would be four sliders for
  /// nobody.
  final bool showDials;

  @override
  State<VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends State<VoicePicker> {
  VoiceRoute _route = VoiceRoute.library;

  // ---- the library search
  List<LibraryVoice> _shortlist = const [];
  List<String> _relaxed = const [];
  bool _searching = false;
  String _searchError = '';

  /// Narrows the shortlist by name, here rather than at the provider.
  ///
  /// The brief is what fetches -- language, gender, age, use, tone -- and it
  /// comes back with a few dozen. Finding "Audrey" in those is a different job
  /// from asking for a different few dozen, and going back to the network for it
  /// would throw away the list you are looking at.
  final TextEditingController _byName = TextEditingController();

  // ---- designing
  late final TextEditingController _description = TextEditingController(
    text: widget.suggestedDescription,
  );
  String _designModel = VoiceForge.designModels.first.$1;
  int _picked = -1;

  /// A recording the design takes its colour from. Not a clone: the words
  /// still decide who this is, and the file only decides what they sound like.
  /// Only the v3 engine reads it, so it is offered only there.
  String _designReference = '';

  // ---- cloning
  final List<String> _samples = [];
  final TextEditingController _cloneName = TextEditingController();

  /// The most anybody may type into the two free-text boxes on this panel.
  ///
  /// The brief is a paragraph, not an essay: the design endpoint reads the
  /// first few sentences and a wall of text is how somebody ends up paying for
  /// three takes of a description that was never going to fit.
  static const int _briefLimit = 250;
  static const int _nameLimit = 50;

  LibraryAsset get _draft => widget.draft;

  VoiceForge get _forge => widget.app.voiceForge;

  VoiceShelf get _shelf => widget.app.voiceShelf;

  VoiceBooth get _booth => widget.app.voiceBooth;

  AudioTransport get _transport => widget.transport;

  /// Where the four dials stood when the last read was bought.
  ///
  /// The whole reason this exists: the dials only reach the provider on a
  /// text-to-speech call, so moving one and pressing play on a *free sample*
  /// changes nothing you can hear. That is not a bug in the plumbing -- the
  /// values do travel -- it is the interface failing to say that hearing them
  /// costs a read. Knowing what was last bought is what lets the button say
  /// "these are not the settings you are listening to".
  String _readSettings = '';

  /// The four values as one string, for comparing against [_readSettings].
  String get _dialState => [
        for (final dial in dials)
          _draft.extraNumber(dial.key, dial.fallback).toStringAsFixed(3),
      ].join(',');

  /// Whether a dial has moved since the last bought read.
  bool get _dialsDirty =>
      _draft.extraText('voiceId').isNotEmpty && _readSettings != _dialState;

  /// What a read of the audition line costs.
  String get _readCost {
    final cost = _booth.estimate(_auditionLine);
    return cost.known ? Format.estimated(cost.amount) : '';
  }

  /// What a bought read says. Short: this is a check on the delivery, not a
  /// performance, and every character of it is billed.
  String get _auditionLine =>
      tr('Honestly, I did not think this would work.');

  /// Buys one read of the actor's voice with the dials where they stand.
  void _readAloud() {
    _readSettings = _dialState;
    _booth.audition(_draft.extras, _auditionLine);
  }

  /// A fresh read plays itself, into the screen's own transport.
  void _onBooth() {
    if (!mounted) return;
    final sample = _booth.samplePath;
    if (sample.isNotEmpty && !_transport.holds(sample)) {
      _transport.toggle(sample);
    }
    setState(() {});
  }

  /// What the chosen engine will actually honour of the four dials.
  ///
  /// v3 is a different architecture: it takes no speed at all and has three
  /// stability settings rather than a continuum. Drawing four identical
  /// sliders over that is the interface telling a lie a user can only catch by
  /// paying for two reads and hearing no difference.
  ElevenLabsModel get _engine => ElevenLabsModel.of(
        widget.app.registry.resolveModel(
          _voiceProvider,
          widget.app.settings.prefString('voiceModel'),
        ),
      );

  @override
  void initState() {
    super.initState();
    // Listened to, never reset: this panel is mounted and unmounted as the
    // wizard is walked, and clearing the takes on mount would throw away three
    // designed voices somebody had already been billed for. Whoever opened the
    // screen resets the forge, once.
    _forge.addListener(_repaint);
    _shelf.addListener(_repaint);
    _transport.addListener(_repaint);
    _booth.addListener(_onBooth);
    // Straight to designing when somebody has already written the brief: the
    // from-image route arrives here with a voice profile in hand, and making
    // the user re-choose the door they came through is a step for nothing.
    if (widget.suggestedDescription.trim().isNotEmpty) {
      _route = VoiceRoute.design;
    }
    _seedBrief();
    _search();
    _shelf.load();
  }

  @override
  void dispose() {
    _forge.removeListener(_repaint);
    _shelf.removeListener(_repaint);
    _transport.removeListener(_repaint);
    _booth.removeListener(_onBooth);
    _description.dispose();
    _cloneName.dispose();
    _byName.dispose();
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  /// Puts a chosen voice on the actor. [kind] is what the card and the editor
  /// show as its provenance, and it is the only place the four routes are
  /// distinguishable after the fact.
  void _adopt({
    required String voiceId,
    required String name,
    String ownerId = '',
    required String kind,
    String description = '',
    String preview = '',
  }) {
    _draft
      ..setExtra('voiceId', voiceId)
      // Travels with the id: a library voice has to be put on the account
      // before it can speak, and the render may be the first thing that needs
      // it. Empty for a designed or cloned voice, which is already there.
      ..setExtra('voiceOwner', ownerId)
      ..setExtra('voiceName', name)
      ..setExtra('voiceKind', kind)
      ..setExtra('voiceDescription', description)
      // What the player under the portrait plays when nothing has been
      // auditioned yet. The provider's own sample, so hearing the voice you
      // just cast is free from every section of the editor.
      ..setExtra('voicePreview', preview);
    setState(() {});
    widget.onChanged();
  }

  // ---- the library ---------------------------------------------------------

  String get _voiceProvider => widget.app.registry.providerOrDefault(
        'voice',
        widget.app.settings.prefString('voiceProvider'),
      );

  /// Starts the voice search off from who the actor is.
  ///
  /// Somebody who has said their actor is a woman of 24 has already answered
  /// "which voices?", and should not have to answer it again in different words.
  /// So the brief opens on the person's own gender and age band -- the dependency
  /// runs this way round on purpose, and only this way: picking a voice never
  /// writes back onto the person. See [ActorIdentity].
  ///
  /// Written onto the draft rather than merged in at search time, and that
  /// matters. A default that is computed on every read cannot be cleared: the
  /// chip would show "Female", "Any" would store nothing, and nothing reads as
  /// "use the actor's" -- so the filter would snap straight back. A value the
  /// user can see is a value the user can take off.
  ///
  /// Once, on mount, and never over anything already there.
  void _seedBrief() {
    void seed(String key, String value) {
      if (value.isEmpty || _draft.extraText(key).isNotEmpty) return;
      _draft.setExtra(key, value);
    }

    seed('voiceGender', ActorIdentity.genderOf(_draft));
    seed('voiceAge', ActorIdentity.bandOf(_draft));
  }

  Future<void> _search({bool refresh = false}) async {
    final casting = widget.app.voiceCasting;
    final registry = widget.app.registry;
    final settings = widget.app.settings;
    final provider = _voiceProvider;
    final profile = VoiceProfile.from(_draft.extras);

    if (!refresh) {
      final known = casting.remembered(provider, profile);
      if (known != null) {
        setState(() {
          _shortlist = known.voices;
          _relaxed = known.relaxed;
          _searchError = '';
        });
        return;
      }
    }

    setState(() {
      _searching = true;
      _searchError = '';
    });

    try {
      final found = await casting.shortlist(
        providerId: provider,
        apiKey: settings.apiKey(registry.credentialFor(provider)),
        modelId: registry.resolveModel(
          provider,
          settings.prefString('voiceModel'),
        ),
        profile: profile,
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _shortlist = found.voices;
        _relaxed = found.relaxed;
        _searching = false;
      });
    } on ProviderException catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = error.message;
        _shortlist = const [];
      });
    }
  }

  void _briefChanged(String key, String value) {
    if (_draft.extraText(key) == value) return;
    _draft.setExtra(key, value);
    widget.onChanged();
    _search();
  }

  String get _resultLine {
    if (_searching) return tr('Looking for voices...');
    if (_searchError.isNotEmpty) return '';
    if (_shortlist.isEmpty) return tr('No voice matches this brief.');
    if (_relaxed.isEmpty) {
      //: %1 is a number of voices
      return tr('%1 voice(s) match the brief — a row casts one, the ribbon '
              'keeps it')
          .arg(_shortlist.length);
    }
    final dropped = _relaxed.map(VoiceProfile.filterLabel).join(tr(', '));
    //: %1 is a number of voices, %2 a list of criteria such as "age, tone"
    return tr('%1 voice(s) — widened on: %2')
        .arg(_shortlist.length)
        .arg(dropped);
  }

  // ---- designing -----------------------------------------------------------

  Future<void> _design() async {
    setState(() => _picked = -1);
    await _forge.design(
      description: _description.text,
      modelId: _designModel,
      referenceAudioPath: _takesReference ? _designReference : '',
    );
    if (!mounted) return;
    // Playing the first take straight away: the whole point of three is to
    // compare them, and a silent list of three identical rows is not a choice.
    if (_forge.takes.isNotEmpty) {
      setState(() => _picked = 0);
      _transport.toggle(_forge.takes.first.path);
    }
  }

  Future<void> _keepDesigned() async {
    if (_picked < 0) return;
    final take = _forge.takes[_picked];
    final kept = await _forge.keep(
      index: _picked,
      name: _voiceNameFor(),
      description: _description.text.trim(),
    );
    if (!mounted || kept.voiceId.isEmpty) return;

    _adopt(
      voiceId: kept.voiceId,
      name: kept.name,
      kind: 'designed',
      description: _description.text.trim(),
      // The take on disk, which is the only recording of this voice that
      // exists until somebody asks it to read a line.
      preview: take.path,
    );
    // It is on the account now, so the shelf has one more voice on it.
    await _shelf.load(refresh: true);
  }

  /// Whether the chosen engine will read a recording at all. v2 ignores one,
  /// and offering a control that is quietly discarded is worse than not
  /// offering it.
  bool get _takesReference => _designModel.toLowerCase().contains('v3');

  Future<void> _browseDesignReference() async {
    final file = await openFile(acceptedTypeGroups: const [audioTypeGroup]);
    if (file == null) return;
    setState(() => _designReference = file.path);
  }

  /// What the new voice is filed under on the ElevenLabs account. The actor's
  /// own name, so a library of thirty voices is readable from their side too.
  String _voiceNameFor() {
    final name = _draft.name.trim();
    return name.isEmpty ? tr('Market Queen voice') : name;
  }

  // ---- cloning -------------------------------------------------------------

  Future<void> _browseSamples() async {
    final files = await openFiles(acceptedTypeGroups: const [audioTypeGroup]);
    if (files.isEmpty) return;
    setState(() {
      for (final file in files) {
        if (!_samples.contains(file.path)) _samples.add(file.path);
      }
    });
  }

  Future<void> _clone() async {
    final cloned = await _forge.clone(
      name: _cloneName.text.trim().isEmpty
          ? _voiceNameFor()
          : _cloneName.text.trim(),
      samplePaths: _samples,
    );
    if (!mounted || cloned.voiceId.isEmpty) return;

    _adopt(
      voiceId: cloned.voiceId,
      name: cloned.name,
      kind: 'cloned',
      description: tr('Cloned from your own recordings.'),
    );
    await _shelf.load(refresh: true);
  }

  // ---- the shelf -----------------------------------------------------------

  /// Saves a shared-library voice onto the account, so the next actor can be
  /// given it without going through the search again.
  Future<void> _keepShared(LibraryVoice voice) async {
    final kept = await _shelf.keep(
      voiceId: voice.id,
      ownerId: voice.ownerId,
      name: voice.name,
    );
    if (!mounted || kept.isEmpty) return;
    // Keeping the voice the actor is already reading means the actor should
    // read the account's own copy: that is the id text-to-speech accepts.
    if (_draft.extraText('voiceId') == voice.id) {
      _draft
        ..setExtra('voiceId', kept)
        ..setExtra('voiceOwner', '');
      widget.onChanged();
    }
  }

  /// Takes a voice off the account for good.
  ///
  /// Asked about first, and in the words that matter: this is not the cross on
  /// the player, which only takes the voice off this one actor.
  Future<void> _deleteKept(AccountVoice voice) async {
    final confirmed = await askToConfirm(
      context,
      //: %1 is a voice's name
      title: tr('Delete "%1" from your account?').arg(voice.name),
      message: tr('It goes off every actor using it, and off the provider. '
          'Taking a voice off one actor is the cross on the player instead.'),
      confirmLabel: tr('Delete'),
    );
    if (!confirmed || !mounted) return;

    final gone = await _shelf.remove(voice.id);
    if (!gone || !mounted) return;

    // The actor was reading it. Saying nothing here would leave a name on the
    // card for a voice that no longer exists.
    if (_draft.extraText('voiceId') == voice.id) {
      _adopt(voiceId: '', name: '', kind: '');
      _transport.clear();
    }
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final measured = constraints.hasBoundedHeight;
        final route = switch (_route) {
          VoiceRoute.mine => _mineRoute(),
          VoiceRoute.library => _libraryRoute(),
          VoiceRoute.design => _designRoute(),
          VoiceRoute.clone => _cloneRoute(),
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: measured ? MainAxisSize.max : MainAxisSize.min,
          children: [
            _tabs(),
            const SizedBox(height: MqTheme.gap),
            if (measured)
              Expanded(child: route)
            else
              SizedBox(height: widget.bodyHeight, child: route),
            if (widget.showDials) _dials(),
          ],
        );
      },
    );
  }

  /// The four doors, as one control.
  ///
  /// A segmented control rather than the app's [SegmentedControl] because these
  /// carry glyphs: four one-word labels in a row are four grey words, and the
  /// ribbon, the shelf, the wand and the waveform are what make them readable
  /// at a glance in any language.
  Widget _tabs() {
    final mq = context.mq;

    const routes = <(VoiceRoute, String)>[
      (VoiceRoute.mine, 'bookmark-line'),
      (VoiceRoute.library, 'music-library-line'),
      (VoiceRoute.design, 'magic-line'),
      (VoiceRoute.clone, 'sound-module-line'),
    ];

    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        border: Border.all(color: mq.border),
      ),
      child: Row(
        children: [
          for (final (route, icon) in routes)
            Expanded(
              child: _Tab(
                icon: icon,
                label: labelForRoute(route),
                selected: _route == route,
                onTap: () => setState(() => _route = route),
              ),
            ),
        ],
      ),
    );
  }

  /// What each door is called. Public so the editor's rail and this control
  /// cannot drift apart.
  static String labelForRoute(VoiceRoute route) => switch (route) {
        VoiceRoute.mine => tr('My voices'),
        VoiceRoute.library => tr('Library'),
        VoiceRoute.design => tr('Design'),
        VoiceRoute.clone => tr('Clone'),
      };

  // ---- route: my voices ----------------------------------------------------

  Widget _mineRoute() {
    final mq = context.mq;
    final kept = _shelf.voices;
    final chosen = _draft.extraText('voiceId');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                tr('The voices kept on your provider account. Reusable on any '
                    'actor.'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontSmall,
                  height: MqTheme.lineTight,
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (kept.isNotEmpty)
              Text(
                //: %1 is a number of voices
                tr('%1 voice(s)').arg(kept.length),
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontSmall,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _Panel(
            child: kept.isEmpty
                ? _Empty(
                    text: _shelf.loading
                        ? tr('Reading your account…')
                        : _shelf.error.isNotEmpty
                        ? _shelf.error
                        : !_shelf.ready
                        ? tr('Add your ElevenLabs key under Models to see the '
                            'voices on your account.')
                        : tr('Nothing kept yet. Design one, clone one, or save '
                            'one from the library with the ribbon.'),
                    isError: _shelf.error.isNotEmpty,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(4),
                    itemCount: kept.length,
                    itemBuilder: (context, index) {
                      final voice = kept[index];
                      return _VoiceRow(
                        transport: _transport,
                        name: voice.name,
                        detail: _keptDetail(voice),
                        source: voice.previewUrl,
                        chosen: voice.id == chosen,
                        onChoose: () => _adopt(
                          voiceId: voice.id,
                          name: voice.name,
                          kind: switch (voice.category) {
                            'generated' => 'designed',
                            'cloned' || 'professional' => 'cloned',
                            _ => 'library',
                          },
                          description: voice.description,
                          preview: voice.previewUrl,
                        ),
                        trailing: _RowAction(
                          icon: 'delete-bin-line',
                          tip: tr('Delete from your provider account'),
                          destructive: true,
                          enabled: !_shelf.working,
                          onTap: () => _deleteKept(voice),
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tr('Deleting a voice takes it off the account and off every actor '
              'using it. The cross on the player only takes it off this one.'),
          style: TextStyle(
            color: mq.textTertiary,
            fontSize: MqTheme.fontSmall,
            height: MqTheme.lineTight,
          ),
        ),
      ],
    );
  }

  /// Where a kept voice came from and what it costs to keep -- the line under
  /// its name.
  String _keptDetail(AccountVoice voice) {
    final parts = <String>[
      VoiceShelf.provenanceOf(voice),
      if (voice.description.isNotEmpty) voice.description,
    ];
    return parts.join(' · ');
  }

  // ---- route: the library --------------------------------------------------

  /// The shortlist with the name box applied.
  List<LibraryVoice> get _listed {
    final needle = _byName.text.trim().toLowerCase();
    if (needle.isEmpty) return _shortlist;
    return [
      for (final voice in _shortlist)
        if (voice.name.toLowerCase().contains(needle)) voice,
    ];
  }

  Widget _libraryRoute() {
    final mq = context.mq;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _filterBar(),
        const SizedBox(height: 10),
        Expanded(child: _voiceList()),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _searchError.isEmpty ? _resultLine : _searchError,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _searchError.isEmpty ? mq.textTertiary : mq.error,
                  fontSize: MqTheme.fontSmall,
                  height: MqTheme.lineTight,
                ),
              ),
            ),
            const SizedBox(width: 8),
            MqIconButton(
              icon: _searching ? 'loader-4-line' : 'refresh-line',
              tip: tr('Search the library again'),
              size: 26,
              enabled: !_searching,
              onPressed: () => _search(refresh: true),
            ),
          ],
        ),
      ],
    );
  }

  /// The brief, on one line.
  ///
  /// Five chips carrying their values and nothing else. They used to read
  /// "Language · Same as the ad", "Gender · Female", "Age · Any" -- the field
  /// names taking two thirds of the row to say what the glyphs already say,
  /// while the values, which are the thing being scanned, were pushed off the
  /// end. The name is on hover, and an unset chip says "Any age" rather than
  /// going blank.
  Widget _filterBar() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        MqPickChip(
          label: tr('Language'),
          icon: 'translate-line',
          compact: true,
          menuWidth: 260,
          value: _draft.extraText('voiceLocale'),
          options: [
            MenuOption(tr('Same as the ad'), ''),
            for (final locale in VoiceLocale.all)
              MenuOption(locale.menuLabel, locale.id),
          ],
          onPicked: (value) => _briefChanged('voiceLocale', value),
        ),
        for (final trait in VoiceTrait.all)
          MqPickChip(
            label: trait.label,
            icon: _traitIcons[trait.key] ?? '',
            compact: true,
            value: _draft.extraText(trait.key),
            onPicked: (value) => _briefChanged(trait.key, value),
            options: [
              // Taking a filter off has to be as easy as putting it on, and an
              // empty one widens the search rather than emptying it. Its label
              // names the field, because in a compact chip it is the only
              // wording an unset filter has.
              MenuOption(_anyLabel(trait.key), ''),
              for (final option in trait.options)
                MenuOption(option.$1, option.$2),
            ],
          ),
      ],
    );
  }

  /// What "no filter" is called, per field. One phrase each rather than four
  /// chips all reading "Any".
  static String _anyLabel(String key) => switch (key) {
        'voiceGender' => tr('Any gender'),
        'voiceAge' => tr('Any age'),
        'voiceUse' => tr('Any use'),
        _ => tr('Any tone'),
      };

  /// A glyph per filter, so a row of five reads as five different questions
  /// rather than as five grey pills.
  static const Map<String, String> _traitIcons = {
    'voiceGender': 'user-line',
    'voiceAge': 'timer-line',
    'voiceUse': 'shopping-bag-3-line',
    'voiceTone': 'emotion-line',
  };

  Widget _voiceList() {
    final chosen = _draft.extraText('voiceId');
    final voices = _listed;

    return _Panel(
      child: Column(
        children: [
          // The search box heads the panel it filters, rather than sitting off
          // to the side of the chips: it does not narrow the brief, it narrows
          // the answer, and the answer is what is underneath it.
          _SearchHeader(
            controller: _byName,
            //: %1 is a number of voices
            placeholder: tr('Find a name among the %1 voices found')
                .arg(_shortlist.length),
            onChanged: (_) => setState(() {}),
          ),
          Expanded(
            child: voices.isEmpty
                ? _Empty(
                    text: _searching
                        ? tr('Looking for voices...')
                        : _byName.text.trim().isNotEmpty
                        ? tr('No voice by that name in this shortlist.')
                        : tr('Widen the brief, or reload.'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(4),
                    itemCount: voices.length,
                    itemBuilder: (context, index) {
                      final voice = voices[index];
                      final saved = _shelf.holds(voice.id);
                      return _VoiceRow(
                        transport: _transport,
                        name: voice.name,
                        tags: voiceTags(voice),
                        source: voice.previewUrl,
                        chosen: voice.id == chosen,
                        onChoose: () => _adopt(
                          voiceId: voice.id,
                          ownerId: voice.ownerId,
                          name: voice.name,
                          kind: 'library',
                          description: describeVoice(voice),
                          preview: voice.previewUrl,
                        ),
                        trailing: _RowAction(
                          icon: saved ? 'bookmark-fill' : 'bookmark-line',
                          tip: saved
                              ? tr('Already in My voices')
                              : tr('Keep in My voices'),
                          lit: saved,
                          enabled: !saved && !_shelf.working,
                          onTap: () => _keepShared(voice),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ---- route: designing ----------------------------------------------------

  Widget _designRoute() {
    final mq = context.mq;
    final cost = _forge.estimate(VoiceForge.defaultPreviewText, _designModel);
    final ready = _description.text.trim().length >= 20;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabeledArea(
          controller: _description,
          label: tr('What should the actor sound like?'),
          areaHeight: 82,
          maxLength: _briefLimit,
          placeholder: tr(
            'A young woman with a warm, slightly husky voice. American '
            'English, conversational, a little quick, like she is telling a '
            'friend about something she just found.',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Text(
          ActorProfile.disclaimer,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: mq.textTertiary,
            fontSize: MqTheme.fontSmall,
            height: MqTheme.lineTight,
          ),
        ),
        const SizedBox(height: MqTheme.gap),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MqPickChip(
                    label: tr('Engine'),
                    icon: 'equalizer-line',
                    compact: true,
                    value: _designModel,
                    options: [
                      for (final model in VoiceForge.designModels)
                        MenuOption(model.$2, model.$1),
                    ],
                    onPicked: (value) => setState(() => _designModel = value),
                  ),
                  // The middle ground between designing and cloning: a
                  // recording the engine takes the timbre from while the
                  // description still decides the delivery. Worth having
                  // because the commonest thing anybody has is a voice note
                  // that is not clean enough to clone.
                  if (_takesReference)
                    MqChip(
                      label: _designReference.isEmpty
                          ? tr('Reference audio')
                          : p.basename(_designReference),
                      icon: 'file-music-line',
                      active: _designReference.isNotEmpty,
                      tooltip: tr('Optional: a recording to take the timbre '
                          'from. The description still decides the delivery.'),
                      onPressed: _designReference.isEmpty
                          ? _browseDesignReference
                          : () => setState(() => _designReference = ''),
                    ),
                ],
              ),
            ),
            const SizedBox(width: MqTheme.gap),
            if (_forge.designing)
              GhostButton(
                text: tr('Cancel'),
                destructive: true,
                onPressed: _forge.cancel,
              )
            else
              SolidButton(
                icon: 'magic-line',
                text: cost.known
                    //: %1 is a price
                    ? tr('Generate 3 voices — %1')
                        .arg(Format.estimated(cost.amount))
                    : tr('Generate 3 voices'),
                enabled: ready && _forge.ready && !_forge.busy,
                tooltip: !_forge.ready
                    ? tr('Add your ElevenLabs key under Models first.')
                    : ready
                    ? ''
                    : tr('Describe the voice in a sentence or two first.'),
                onPressed: _design,
              ),
          ],
        ),
        if (_forge.error.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _forge.error,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: mq.error, fontSize: MqTheme.fontSmall),
          ),
        ],
        const SizedBox(height: MqTheme.gap + 2),
        Expanded(child: _takes()),
      ],
    );
  }

  /// The three candidates, side by side.
  ///
  /// Three rows one under another invited reading them in order; three cards
  /// invite comparing them, which is the whole reason there are three.
  Widget _takes() {
    final mq = context.mq;

    if (_forge.takes.isEmpty) {
      return _Panel(
        child: _Empty(
          text: _forge.designing
              ? tr('Designing three voices…')
              : tr('Three takes on the description appear here. Nothing is '
                  'kept until you say so.'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(tr('Listen, then keep one')),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _forge.takes.length; ++i) ...[
                if (i > 0) const SizedBox(width: MqTheme.gap),
                Expanded(
                  child: _TakeCard(
                    transport: _transport,
                    //: %1 is a number: the first, second or third take
                    label: tr('Take %1').arg(i + 1),
                    source: _forge.takes[i].path,
                    picked: _picked == i,
                    onPick: () => setState(() => _picked = i),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: MqTheme.gap),
        Row(
          children: [
            Expanded(
              child: Text(
                tr('Keeping a take adds it to My voices and gives it to the '
                    'actor. The other two are thrown away.'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontSmall,
                  height: MqTheme.lineTight,
                ),
              ),
            ),
            const SizedBox(width: MqTheme.gap),
            SolidButton(
              text: _forge.keeping
                  ? tr('Keeping…')
                  //: %1 is a number: the first, second or third take
                  : tr('Keep take %1').arg(_picked + 1),
              loading: _forge.keeping,
              enabled: _picked >= 0 && !_forge.busy,
              onPressed: _keepDesigned,
            ),
          ],
        ),
      ],
    );
  }

  // ---- route: cloning ------------------------------------------------------

  Widget _cloneRoute() {
    final mq = context.mq;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: MediaDropZone(
            paths: _samples,
            title: tr('Drop your recordings in'),
            hint: tr('MP3, WAV or M4A. One clean minute beats ten noisy ones.'),
            tileSize: 56,
            onAdded: (paths) => setState(() {
              for (final path in paths) {
                if (isAudioPath(path) && !_samples.contains(path)) {
                  _samples.add(path);
                }
              }
            }),
            onRemoved: (index) => setState(() => _samples.removeAt(index)),
          ),
        ),
        if (_forge.error.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _forge.error,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: mq.error, fontSize: MqTheme.fontSmall),
          ),
        ],
        const SizedBox(height: MqTheme.gap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 260,
              child: LabeledField(
                controller: _cloneName,
                label: tr('Name for the voice'),
                maxLength: _nameLimit,
                placeholder: _voiceNameFor(),
              ),
            ),
            const SizedBox(width: MqTheme.gapLarge),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 22),
                child: Text(
                  tr('Only clone a voice you own or have permission to use. '
                      'This one really is the voice in your files, and it '
                      'joins My voices.'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mq.textTertiary,
                    fontSize: MqTheme.fontSmall,
                    height: MqTheme.lineTight,
                  ),
                ),
              ),
            ),
            const SizedBox(width: MqTheme.gap),
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: Row(
                children: [
                  MqIconButton(
                    icon: 'attachment-line',
                    tip: tr('Add a recording'),
                    size: 32,
                    onPressed: _browseSamples,
                  ),
                  const SizedBox(width: 8),
                  if (_forge.cloning)
                    GhostButton(
                      text: tr('Cancel'),
                      destructive: true,
                      onPressed: _forge.cancel,
                    )
                  else
                    SolidButton(
                      text: tr('Clone this voice'),
                      enabled:
                          _samples.isNotEmpty && _forge.ready && !_forge.busy,
                      tooltip: _forge.ready
                          ? ''
                          : tr('Add your ElevenLabs key under Models first.'),
                      onPressed: _clone,
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---- the dials -----------------------------------------------------------

  /// The four dials, their ranges and where they sit when nobody has touched
  /// them. Written down once because Reset needs the same numbers the sliders
  /// draw from.
  static const List<({String key, double from, double to, double fallback})>
      dials = [
    (key: 'voiceSpeed', from: 0.7, to: 1.2, fallback: 1.0),
    (key: 'voiceStability', from: 0, to: 1, fallback: 0.45),
    (key: 'voiceSimilarity', from: 0, to: 1, fallback: 0.8),
    (key: 'voiceStyle', from: 0, to: 1, fallback: 0.35),
  ];

  static String _dialLabel(String key) => switch (key) {
        'voiceSpeed' => tr('Speed'),
        'voiceStability' => tr('Stability'),
        'voiceSimilarity' => tr('Similarity'),
        _ => tr('Style exaggeration'),
      };

  /// How the voice reads, docked under whichever door is open.
  ///
  /// They belong to the actor rather than to any of the four routes -- a speed
  /// set while looking at the library is still the speed after designing a new
  /// voice -- so they sit below all four rather than inside one, and are two
  /// across because that is how they are thought about: how fast and how like
  /// the original, how steady and how much colour.
  Widget _dials() {
    final mq = context.mq;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: MqTheme.gap),
        Container(height: 1, color: mq.divider),
        const SizedBox(height: MqTheme.gap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: TextStyle(
                    color: mq.textPrimary,
                    fontFamily: MqTheme.fontFamily,
                    fontSize: MqTheme.fontSmall,
                    fontWeight: FontWeight.w600,
                    letterSpacing: MqTheme.trackSmall,
                  ),
                  children: [
                    TextSpan(text: tr('Delivery')),
                    TextSpan(
                      text: tr(' — the difference between a human read and an '
                          'announcer'),
                      style: TextStyle(
                        color: mq.textTertiary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            MqLink(text: tr('Reset'), onPressed: _resetDials),
          ],
        ),
        const SizedBox(height: 2),
        LayoutBuilder(
          builder: (context, constraints) {
            // Under this a column is 130px, which is not a slider.
            final columns = constraints.maxWidth >= 420 ? 2 : 1;
            final width =
                (constraints.maxWidth - MqTheme.gapLarge * (columns - 1)) /
                    columns;
            final engine = _engine;

            return Wrap(
              spacing: MqTheme.gapLarge,
              runSpacing: 0,
              children: [
                for (final dial in dials)
                  SizedBox(
                    width: width,
                    child: LabeledSlider(
                      label: _dialLabel(dial.key),
                      value: _draft.extraNumber(dial.key, dial.fallback),
                      from: dial.from,
                      to: dial.to,
                      // A dial the engine throws away is drawn dead rather than
                      // drawn working. v3 takes no speed, and a slider that
                      // moves while nothing happens costs somebody two reads to
                      // find out.
                      enabled: dial.key != 'voiceSpeed' || engine.speed,
                      disabledHint: tr('This engine reads at its own pace.'),
                      // Snapped where the engine only has three settings, so
                      // the number on screen is the number it will be sent.
                      steps: dial.key == 'voiceStability'
                          ? engine.stabilitySteps
                          : const [],
                      onChanged: (value) => setState(() {
                        _draft.setExtra(dial.key, value);
                        widget.onChanged();
                      }),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        _readRow(),
      ],
    );
  }

  /// The line that makes the dials honest.
  ///
  /// They are not live controls on the sample: a provider's preview is a fixed
  /// recording of that voice, and no setting on this screen can change a file
  /// that was made months ago. The only thing that hears them is a fresh read,
  /// and a fresh read is billed -- so the button says so, and lights up as soon
  /// as a dial has moved away from whatever was last bought.
  Widget _readRow() {
    final mq = context.mq;
    final cast = _draft.extraText('voiceId').isNotEmpty;
    final dirty = _dialsDirty;
    final cost = _readCost;

    final label = _booth.auditioning
        ? tr('Reading…')
        : cost.isEmpty
        //: The button that spends money to hear the delivery settings applied
        ? tr('Hear these settings')
        //: %1 is a price
        : tr('Hear these settings — %1').arg(cost);

    return Row(
      children: [
        Expanded(
          child: Text(
            _booth.error.isNotEmpty
                ? _booth.error
                : dirty
                ? tr('Moved since the last read. The sample you can play is '
                    'the voice as it was recorded, not as you have set it.')
                : tr('These four are only heard on a read bought with them.'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _booth.error.isNotEmpty
                  ? mq.error
                  : dirty
                  ? mq.warningText
                  : mq.textTertiary,
              fontSize: MqTheme.fontSmall,
              height: MqTheme.lineTight,
            ),
          ),
        ),
        const SizedBox(width: MqTheme.gap),
        if (dirty)
          SolidButton(
            text: label,
            icon: 'volume-up-line',
            loading: _booth.auditioning,
            enabled: cast && !_booth.auditioning,
            onPressed: _readAloud,
          )
        else
          GhostButton(
            text: label,
            icon: 'volume-up-line',
            enabled: cast && !_booth.auditioning,
            onPressed: _readAloud,
          ),
      ],
    );
  }

  void _resetDials() => setState(() {
        for (final dial in dials) {
          _draft.setExtra(dial.key, dial.fallback);
        }
        widget.onChanged();
      });
}

// ---- the pieces the routes are built from -----------------------------------

/// One door of the voice control.
class _Tab extends StatelessWidget {
  const _Tab({
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
      focusRadius: MqTheme.radiusSmall - 2,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? mq.surfaceRaised
              : states.active
              ? mq.surfaceHover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall - 2),
          border: Border.all(
            color: selected ? mq.border : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MqIcon(
              icon,
              size: 15,
              color: selected ? mq.textPrimary : mq.textTertiary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  color: selected || states.active
                      ? mq.textPrimary
                      : mq.textSecondary,
                  fontSize: MqTheme.fontLabel,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  letterSpacing: MqTheme.trackSmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sunken panel a catalogue lives in. The one thing on this screen that
/// scrolls.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radius),
        border: Border.all(color: mq.border),
      ),
      child: child,
    );
  }
}

/// What a panel says when it has nothing in it.
class _Empty extends StatelessWidget {
  const _Empty({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isError ? mq.error : mq.textTertiary,
            fontSize: MqTheme.fontSmall,
            height: MqTheme.lineTight,
          ),
        ),
      ),
    );
  }
}

/// The search box at the head of the panel it filters.
class _SearchHeader extends StatefulWidget {
  const _SearchHeader({
    required this.controller,
    required this.placeholder,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchHeader> createState() => _SearchHeaderState();
}

class _SearchHeaderState extends State<_SearchHeader> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      height: 36,
      padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: mq.border)),
      ),
      child: Row(
        children: [
          MqIcon(
            'search-line',
            size: 15,
            color: _focus.hasFocus ? mq.textSecondary : mq.textTertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              onChanged: widget.onChanged,
              cursorColor: mq.primary,
              style: TextStyle(
                color: mq.textPrimary,
                fontSize: MqTheme.fontLabel,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                hintText: widget.placeholder,
                hintStyle: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontLabel,
                ),
              ),
            ),
          ),
          if (widget.controller.text.isNotEmpty)
            MqIconButton(
              icon: 'close-line',
              tip: tr('Clear'),
              size: 24,
              canRequestFocus: false,
              onPressed: () {
                widget.controller.clear();
                widget.onChanged('');
              },
            ),
        ],
      ),
    );
  }
}

/// One voice on offer: a way to hear it, who it is, and whether it is the one.
///
/// Play on the left, because listening is what you do to twenty of these and
/// choosing is what you do to one. The facts are tags rather than a sentence:
/// six of them run together with dots read as one long grey line, and the one
/// you are checking -- is this actually French? -- is never the one you find
/// first. The tick is on the right, where a list puts the state of a row.
///
/// The line at the very bottom is the transport's, and only the playing row
/// draws one: it is how a list of twenty says which of them is making the
/// noise.
class _VoiceRow extends StatelessWidget {
  const _VoiceRow({
    required this.transport,
    required this.name,
    required this.source,
    required this.chosen,
    required this.onChoose,
    this.tags = const [],
    this.detail = '',
    this.trailing,
  });

  final AudioTransport transport;
  final String name;

  /// What the disc plays: the provider's own sample.
  final String source;

  /// The facts, one per tag. Empty for a kept voice, which has [detail].
  final List<String> tags;

  /// One line under the name, for the rows that are not library listings.
  final String detail;

  final bool chosen;
  final VoidCallback onChoose;

  /// The row's own verb -- keep it, or delete it. Never "choose it": that is
  /// the row itself.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final loaded = transport.holds(source);

    return Pressable(
      onTap: onChoose,
      snap: true,
      focusRadius: MqTheme.radiusSmall,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        // No bottom padding: the transport gets that strip instead. It used to
        // be laid over the content, which put a moving line a pixel under the
        // row of tags -- and left it too thin to grab.
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 0),
        margin: const EdgeInsets.only(bottom: 3),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: chosen
              ? mq.primarySubtle
              : states.active
              ? mq.surfaceHover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          border: Border.all(
            color: chosen ? mq.primary : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                PlayDisc(
                  transport: transport,
                  source: source,
                  //: Playing the provider's own sample costs nothing
                  tip: tr('Listen — free'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: mq.textPrimary,
                          fontSize: MqTheme.fontLabel,
                          fontWeight:
                              chosen ? FontWeight.w600 : FontWeight.w500,
                          height: MqTheme.lineTight,
                        ),
                      ),
                      if (detail.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: mq.textTertiary,
                            fontSize: MqTheme.fontMicro + 0.5,
                            height: MqTheme.lineTight,
                          ),
                        ),
                      ],
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        // Clipped to one line: a voice with six tags must not
                        // make its row twice the height of the one above it.
                        SizedBox(
                          height: 18,
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: AlignmentDirectional.centerStart,
                              maxWidth: double.infinity,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final tag in tags) _VoiceTag(text: tag),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (loaded) ...[
                  TransportClock(transport: transport, source: source),
                  const SizedBox(width: 6),
                ],
                if (trailing != null) ...[trailing!, const SizedBox(width: 4)],
                // Held whether or not it is lit, so a row does not reflow when
                // it becomes the chosen one.
                SizedBox(
                  width: 18,
                  height: 18,
                  child: chosen
                      ? Tooltip(
                          message: tr("This actor's voice"),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: mq.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: MqIcon(
                                'check-line',
                                size: 12,
                                color: mq.onPrimary,
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
            // Held whether or not it is loaded, so choosing a row never shifts
            // the ones under it by a strip of twelve pixels.
            SizedBox(
              height: 12,
              child: loaded
                  ? TransportLine(transport: transport, source: source)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// The verb on the end of a voice row: keep it, or delete it.
///
/// Its own target inside the row rather than a second meaning for it. Pressing
/// the row always casts that voice, which is what you do once; this is what you
/// do to your shelf, which is a different subject entirely.
class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.tip,
    required this.onTap,
    this.lit = false,
    this.destructive = false,
    this.enabled = true,
  });

  final String icon;
  final String tip;
  final VoidCallback onTap;

  /// Already done -- the ribbon on a voice that is already kept. Drawn in ink
  /// and inert, because there is nothing left to press it for.
  final bool lit;

  final bool destructive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      enabled: enabled,
      onTap: onTap,
      tooltip: tip,
      focusRadius: MqTheme.radiusSmall,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: !states.active
              ? Colors.transparent
              : destructive
              ? mq.errorSubtle
              : mq.surfaceActive,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        ),
        child: MqIcon(
          icon,
          size: 15,
          color: lit
              ? mq.textPrimary
              : destructive && states.active
              ? mq.error
              : states.active
              ? mq.textPrimary
              : mq.textTertiary,
        ),
      ),
    );
  }
}

/// One fact about a voice, as a small pill.
class _VoiceTag extends StatelessWidget {
  const _VoiceTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      margin: const EdgeInsetsDirectional.only(end: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: mq.surface,
        borderRadius: BorderRadius.circular(MqTheme.radiusSmall - 2),
        border: Border.all(color: mq.border),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          color: mq.textTertiary,
          fontSize: MqTheme.fontMicro,
          height: 1.25,
        ),
      ),
    );
  }
}

/// One of the three designed candidates.
///
/// A radio and a transport in one card: picking it is the decision, playing it
/// is how the decision gets made, and the two are separate targets because
/// comparing three takes means pressing play far more often than pressing
/// choose.
class _TakeCard extends StatelessWidget {
  const _TakeCard({
    required this.transport,
    required this.label,
    required this.source,
    required this.picked,
    required this.onPick,
  });

  final AudioTransport transport;
  final String label;
  final String source;
  final bool picked;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onPick,
      snap: true,
      focusRadius: MqTheme.radius,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: picked
              ? mq.primarySubtle
              : states.active
              ? mq.surfaceHover
              : mq.surfaceSecondary,
          borderRadius: BorderRadius.circular(MqTheme.radius),
          border: Border.all(
            color: picked
                ? mq.primary
                : states.active
                ? mq.borderStrong
                : mq.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mq.textPrimary,
                      fontSize: MqTheme.fontLabel,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: picked ? mq.primary : mq.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: picked ? mq.primary : mq.borderStrong,
                    ),
                  ),
                  child: picked
                      ? MqIcon('check-line', size: 12, color: mq.onPrimary)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                PlayDisc(
                  transport: transport,
                  source: source,
                  tip: tr('Listen'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TransportLine(transport: transport, source: source),
                ),
                const SizedBox(width: 8),
                TransportClock(transport: transport, source: source),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
