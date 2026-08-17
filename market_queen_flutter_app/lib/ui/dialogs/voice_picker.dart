import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../../core/http_util.dart';
import '../../models/actor_smith.dart';
import '../../models/asset_library.dart';
import '../../models/voice_forge.dart';
import '../../providers/types.dart';
import '../../providers/voice_profile.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chip.dart';
import '../widgets/fields.dart';
import '../widgets/media_drop.dart';

/// The three ways an actor ends up with a voice.
///
/// They are genuinely different operations rather than three presets of one,
/// and the difference the user has to understand is about truth rather than
/// technique:
///
///  * [library] picks somebody who already exists and can be listened to first.
///  * [design] invents one from a description. It sounds like the brief; it is
///    nobody.
///  * [clone] copies a real voice off a recording, and is the only one of the
///    three where the app may say the voice *is* somebody's.
enum VoiceRoute { library, design, clone }

/// The voice step: pick one, invent one, or clone one.
///
/// Writes onto [draft] and nowhere else -- the caller decides when that draft
/// reaches the library -- so the same panel serves the creation wizard and the
/// editor's Voice section without either knowing about the other.
class VoicePicker extends StatefulWidget {
  const VoicePicker({
    super.key,
    required this.app,
    required this.draft,
    required this.onChanged,
    this.suggestedDescription = '',
  });

  final AppState app;

  /// The actor being given a voice. Mutated in place.
  final LibraryAsset draft;

  final VoidCallback onChanged;

  /// What the design box opens on. Filled in by the from-image route, where a
  /// vision model has already proposed one; empty everywhere else.
  final String suggestedDescription;

  @override
  State<VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends State<VoicePicker> {
  Player? _player;

  VoiceRoute _route = VoiceRoute.library;

  // ---- the library search
  List<LibraryVoice> _shortlist = const [];
  List<String> _relaxed = const [];
  bool _searching = false;
  String _searchError = '';

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

  LibraryAsset get _draft => widget.draft;

  VoiceForge get _forge => widget.app.voiceForge;

  @override
  void initState() {
    super.initState();
    // Listened to, never reset: this panel is mounted and unmounted as the
    // wizard is walked, and clearing the takes on mount would throw away three
    // designed voices somebody had already been billed for. Whoever opened the
    // screen resets the forge, once.
    _forge.addListener(_repaint);
    // Straight to designing when somebody has already written the brief: the
    // from-image route arrives here with a voice profile in hand, and making
    // the user re-choose the door they came through is a step for nothing.
    if (widget.suggestedDescription.trim().isNotEmpty) {
      _route = VoiceRoute.design;
    }
    _search();
  }

  @override
  void dispose() {
    _forge.removeListener(_repaint);
    _description.dispose();
    _cloneName.dispose();
    _player?.dispose();
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  void _play(String source) {
    if (source.isEmpty) return;
    (_player ??= Player()).open(Media(source));
  }

  /// Puts a chosen voice on the actor. [kind] is what the card and the editor
  /// show as its provenance, and it is the only place the three routes are
  /// distinguishable after the fact.
  void _adopt({
    required String voiceId,
    required String name,
    String ownerId = '',
    required String kind,
    String description = '',
  }) {
    _draft
      ..setExtra('voiceId', voiceId)
      // Travels with the id: a library voice has to be put on the account
      // before it can speak, and the render may be the first thing that needs
      // it. Empty for a designed or cloned voice, which is already there.
      ..setExtra('voiceOwner', ownerId)
      ..setExtra('voiceName', name)
      ..setExtra('voiceKind', kind)
      ..setExtra('voiceDescription', description);
    setState(() {});
    widget.onChanged();
  }

  // ---- the library ---------------------------------------------------------

  String get _voiceProvider => widget.app.registry.providerOrDefault(
        'voice',
        widget.app.settings.prefString('voiceProvider'),
      );

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
      return tr('%1 voice(s) match').arg(_shortlist.length);
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
    if (_forge.takes.isNotEmpty) _play(_forge.takes.first.path);
  }

  Future<void> _keepDesigned() async {
    if (_picked < 0) return;
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
    );
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
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _chosenRow(),
        const SizedBox(height: MqTheme.gap),
        // One word each. The heading above already says these are voices, and
        // three "... a voice" labels is the same noun three times in a control
        // narrow enough that the noun is what gets cut.
        SegmentedControl<VoiceRoute>(
          value: _route,
          options: [
            MenuEntry(tr('Library'), VoiceRoute.library),
            MenuEntry(tr('Design'), VoiceRoute.design),
            MenuEntry(tr('Clone'), VoiceRoute.clone),
          ],
          onPicked: (route) => setState(() => _route = route),
        ),
        const SizedBox(height: MqTheme.gap),
        switch (_route) {
          VoiceRoute.library => _libraryRoute(),
          VoiceRoute.design => _designRoute(),
          VoiceRoute.clone => _cloneRoute(),
        },
      ],
    );
  }

  /// Who is cast right now, and where they came from. Always on screen, in
  /// every mode: it is what the three tabs are competing to change, and a
  /// choice you cannot see is one you make twice.
  Widget _chosenRow() {
    final mq = context.mq;
    final name = _draft.extraText('voiceName');
    final kind = _draft.extraText('voiceKind');

    final provenance = switch (kind) {
      'designed' => tr('Designed · ElevenLabs'),
      'cloned' => tr('Cloned from your recordings · ElevenLabs'),
      'library' => tr('Voice library · ElevenLabs'),
      _ => '',
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radius),
        border: Border.all(color: name.isEmpty ? mq.border : mq.borderStrong),
      ),
      child: Row(
        children: [
          MqIcon(
            name.isEmpty ? 'mic-line' : 'user-voice-line',
            size: 17,
            color: name.isEmpty ? mq.textTertiary : mq.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name.isEmpty ? tr('No voice yet') : name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: name.isEmpty ? mq.textTertiary : mq.textPrimary,
                    fontSize: MqTheme.fontBody,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (provenance.isNotEmpty)
                  Text(
                    provenance,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mq.textTertiary,
                      fontSize: MqTheme.fontSmall,
                    ),
                  ),
              ],
            ),
          ),
          if (name.isNotEmpty)
            MqIconButton(
              icon: 'close-line',
              tip: tr('Take the voice off'),
              size: 26,
              onPressed: () => _adopt(voiceId: '', name: '', kind: ''),
            ),
        ],
      ),
    );
  }

  // ---- route: the library --------------------------------------------------

  Widget _libraryRoute() {
    final mq = context.mq;
    final chosen = _draft.extraText('voiceId');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            MqPickChip(
              label: tr('Language'),
              icon: 'translate-line',
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
              MqChoiceChip(
                label: trait.label,
                value: _draft.extraText(trait.key),
                onPicked: (value) => _briefChanged(trait.key, value),
                options: [
                  for (final option in trait.options)
                    MenuOption(option.$1, option.$2),
                ],
              ),
          ],
        ),
        const SizedBox(height: MqTheme.gap),
        Container(
          constraints: const BoxConstraints(maxHeight: 240),
          decoration: BoxDecoration(
            color: mq.surfaceSecondary,
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
            border: Border.all(color: mq.border),
          ),
          child: _shortlist.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    _searching ? '' : tr('Widen the brief, or reload.'),
                    style: TextStyle(
                      color: mq.textTertiary,
                      fontSize: MqTheme.fontSmall,
                    ),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(3),
                  children: [
                    for (final voice in _shortlist)
                      _VoiceRow(
                        name: voice.name,
                        detail: describeVoice(voice),
                        chosen: voice.id == chosen,
                        onChoose: () => _adopt(
                          voiceId: voice.id,
                          ownerId: voice.ownerId,
                          name: voice.name,
                          kind: 'library',
                          description: describeVoice(voice),
                        ),
                        onPlay: voice.previewUrl.isEmpty
                            ? null
                            : () => _play(voice.previewUrl),
                        //: Playing the provider's own sample costs nothing
                        playTip: tr('Listen — free'),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                _searchError.isEmpty ? _resultLine : _searchError,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _searchError.isEmpty ? mq.textTertiary : mq.error,
                  fontSize: MqTheme.fontSmall,
                ),
              ),
            ),
            MqIconButton(
              icon: _searching ? 'loader-4-line' : 'refresh-line',
              tip: tr('Search the library again'),
              size: 28,
              enabled: !_searching,
              onPressed: () => _search(refresh: true),
            ),
          ],
        ),
      ],
    );
  }

  // ---- route: designing ----------------------------------------------------

  Widget _designRoute() {
    final mq = context.mq;
    final cost = _forge.estimate(VoiceForge.defaultPreviewText, _designModel);
    final ready = _description.text.trim().length >= 20;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LabeledArea(
          controller: _description,
          label: tr('What should they sound like?'),
          areaHeight: 76,
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
                          ? tr('Add a recording')
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
              GhostButton(
                text: cost.known
                    //: %1 is a price
                    ? tr('Generate 3 voices — %1')
                        .arg(Format.estimated(cost.amount))
                    : tr('Generate 3 voices'),
                enabled: ready && _forge.ready && !_forge.busy,
                onPressed: _design,
              ),
          ],
        ),
        if (!_forge.ready) ...[
          const SizedBox(height: 8),
          Text(
            tr('Add your ElevenLabs key under Models first.'),
            style: TextStyle(color: mq.warningText, fontSize: MqTheme.fontSmall),
          ),
        ],
        if (_forge.error.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _forge.error,
            style: TextStyle(color: mq.error, fontSize: MqTheme.fontSmall),
          ),
        ],
        if (_forge.designing) ...[
          const SizedBox(height: MqTheme.gap),
          Text(
            tr('Designing three voices…'),
            style: TextStyle(color: mq.textTertiary, fontSize: MqTheme.fontSmall),
          ),
        ],
        if (_forge.takes.isNotEmpty) ...[
          const SizedBox(height: MqTheme.gap),
          FieldLabel(tr('Listen, then keep one')),
          const SizedBox(height: 8),
          for (var i = 0; i < _forge.takes.length; ++i)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _VoiceRow(
                //: %1 is a number: the first, second or third take
                name: tr('Take %1').arg(i + 1),
                detail: _forge.spokenText,
                chosen: _picked == i,
                onChoose: () {
                  setState(() => _picked = i);
                  _play(_forge.takes[i].path);
                },
                onPlay: () => _play(_forge.takes[i].path),
                playTip: tr('Listen'),
                framed: true,
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('Keeping one puts it on your ElevenLabs account. The '
                      'other two are thrown away.'),
                  style: TextStyle(
                    color: mq.textTertiary,
                    fontSize: MqTheme.fontSmall,
                    height: MqTheme.lineTight,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GhostButton(
                text: _forge.keeping ? tr('Keeping…') : tr('Keep this voice'),
                enabled: _picked >= 0 && !_forge.busy,
                onPressed: _keepDesigned,
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ---- route: cloning ------------------------------------------------------

  Widget _cloneRoute() {
    final mq = context.mq;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        MediaDropZone(
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
        const SizedBox(height: MqTheme.gap),
        LabeledField(
          controller: _cloneName,
          label: tr('Name for the voice'),
          placeholder: _voiceNameFor(),
        ),
        const SizedBox(height: 8),
        Text(
          tr('Only clone a voice you own or have permission to use. This one '
              'really is the voice in your files.'),
          style: TextStyle(
            color: mq.textTertiary,
            fontSize: MqTheme.fontSmall,
            height: MqTheme.lineTight,
          ),
        ),
        if (_forge.error.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _forge.error,
            style: TextStyle(color: mq.error, fontSize: MqTheme.fontSmall),
          ),
        ],
        const SizedBox(height: MqTheme.gap),
        Row(
          children: [
            MqIconButton(
              icon: 'attachment-line',
              tip: tr('Add a recording'),
              size: 32,
              onPressed: _browseSamples,
            ),
            const Spacer(),
            if (_forge.cloning)
              GhostButton(
                text: tr('Cancel'),
                destructive: true,
                onPressed: _forge.cancel,
              )
            else
              GhostButton(
                text: tr('Clone this voice'),
                enabled: _samples.isNotEmpty && _forge.ready && !_forge.busy,
                onPressed: _clone,
              ),
          ],
        ),
      ],
    );
  }
}

/// One voice on offer: who they are, what about them matched, and a way to
/// hear them.
class _VoiceRow extends StatelessWidget {
  const _VoiceRow({
    required this.name,
    required this.detail,
    required this.chosen,
    required this.onChoose,
    required this.playTip,
    this.onPlay,
    this.framed = false,
  });

  final String name;
  final String detail;
  final bool chosen;
  final VoidCallback onChoose;
  final VoidCallback? onPlay;
  final String playTip;

  /// Designed takes sit on the card rather than inside a list, so they carry
  /// their own outline.
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onChoose,
      snap: true,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: chosen
              ? mq.surfaceActive
              : states.active
              ? mq.surfaceHover
              : framed
              ? mq.surfaceSecondary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          border: framed
              ? Border.all(color: chosen ? mq.primary : mq.border)
              : null,
        ),
        child: Row(
          children: [
            MqIcon(
              chosen ? 'check-line' : 'mic-line',
              size: 15,
              color: chosen ? mq.primary : mq.textTertiary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mq.textPrimary,
                      fontSize: MqTheme.fontLabel,
                      fontWeight: chosen ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: mq.textTertiary,
                        fontSize: MqTheme.fontSmall,
                      ),
                    ),
                ],
              ),
            ),
            if (onPlay != null) ...[
              const SizedBox(width: 6),
              MqIconButton(
                icon: 'play-fill',
                tip: playTip,
                size: 26,
                onPressed: onPlay,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
