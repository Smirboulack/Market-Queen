import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../app_state.dart';
import '../../core/http_util.dart';
import '../../i18n/translator.dart';
import '../../models/ad_project.dart';
import '../../models/asset_library.dart';
import '../../models/image_forge.dart';
import '../../providers/types.dart';
import '../../providers/voice_profile.dart';
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
  String _lastSample = '';

  /// Who the brief turned up, best first, and how much of it had to be given
  /// up to turn up anybody.
  List<LibraryVoice> _shortlist = const [];
  List<String> _relaxed = const [];
  bool _searching = false;
  String _searchError = '';

  /// The user's own voices, only fetched if they ask for them: a cloned voice
  /// is a choice no brief can express.
  List<VoiceOption> _accountVoices = const [];
  bool _showAccount = false;

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
      // The list has to be right the moment the editor opens, not after the
      // first chip is touched: an actor with no brief is still a brief -- a
      // voice in the language the ad is written in.
      _search();
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
    setState(() => _accountVoices = event.voices);
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
  //
  // The brief is not a filter over a list that was already downloaded -- there
  // are ten thousand voices and no such list exists. It is the query. Every
  // chip below goes into the Voice Library search in the exact spelling that
  // search honours, and what comes back is what is shown.
  //
  // That distinction is the whole feature. Filtering client-side is how a
  // French brief used to come back read by an American: the app asked for
  // everything, then hoped.

  String get _voiceProvider {
    final id = widget.app.settings.prefString('voiceProvider');
    return id.isEmpty ? widget.app.registry.defaultProvider('voice') : id;
  }

  VoiceProfile get _profile => VoiceProfile.from(_draft.extras);

  /// Runs the brief past the provider. Cached for a day unless [refresh].
  ///
  /// [briefChanged] is what tells the search whether it is allowed to re-cast:
  /// touching a chip is meant to change who reads the ad, merely opening the
  /// editor is not.
  Future<void> _search({bool refresh = false, bool briefChanged = false}) async {
    final casting = widget.app.voiceCasting;
    final settings = widget.app.settings;
    final registry = widget.app.registry;
    final provider = _voiceProvider;
    final profile = _profile;

    if (!refresh) {
      final known = casting.remembered(provider, profile);
      if (known != null) {
        setState(() {
          _shortlist = known.voices;
          _relaxed = known.relaxed;
          _searchError = '';
        });
        _castDefault(briefChanged);
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
        modelId: registry.resolveModel(provider, settings.prefString('voiceModel')),
        profile: profile,
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _shortlist = found.voices;
        _relaxed = found.relaxed;
        _searching = false;
      });
      _castDefault(briefChanged);
    } on ProviderException catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = error.message;
        _shortlist = const [];
        _relaxed = const [];
      });
    }
  }

  /// Fills in the voice, or moves it when the brief moved.
  ///
  /// An actor with nothing chosen gets the top of the list, so a voice is never
  /// simply missing. A [briefChanged] search re-casts even over an existing
  /// choice -- editing the brief is meant to change who reads the ad, and
  /// leaving yesterday's voice selected under today's brief is the lie this
  /// screen exists to stop telling. Nothing else touches a choice already made.
  void _castDefault(bool briefChanged) {
    if (_shortlist.isEmpty) return;
    if (!briefChanged && _draft.extraText('voiceId').isNotEmpty) return;

    setState(() => _choose(_shortlist.first));
  }

  void _choose(LibraryVoice voice) {
    _draft
      ..setExtra('voiceId', voice.id)
      // Travels with the id: a library voice has to be put on the account
      // before it can speak, and the render may be the first to need it.
      ..setExtra('voiceOwner', voice.ownerId)
      ..setExtra('voiceName', voice.name);
  }

  /// A few seconds of the real voice, hosted by the provider. No credits, no
  /// key, no wait -- which is what makes comparing six of them bearable.
  void _preview(String url) {
    if (url.isEmpty) return;
    (_player ??= Player()).open(Media(url));
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
        _brief(),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                _resultLine,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _relaxed.isEmpty ? mq.textTertiary : mq.textSecondary,
                  fontSize: MqTheme.fontSmall,
                ),
              ),
            ),
            MqIconButton(
              icon: _searching ? 'loader-4-line' : 'refresh-line',
              tip: tr('Search the library again'),
              size: 32,
              enabled: !_searching,
              onPressed: () => _search(refresh: true),
            ),
            const SizedBox(width: 2),
            MqIconButton(
              icon: booth.auditioning ? 'loader-4-line' : 'play-fill',
              tip: cost.known
                  //: %1 is a price
                  ? tr('Hear them say a line — %1')
                      .arg(Format.estimated(cost.amount))
                  : tr('Hear them say a line'),
              size: 32,
              enabled: !booth.auditioning && _draft.extraText('voiceId').isNotEmpty,
              onPressed: () => booth.audition(_draft.extras, _audition.text),
            ),
          ],
        ),
        if (_searchError.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            _searchError,
            style: TextStyle(color: mq.error, fontSize: MqTheme.fontSmall),
          ),
        ],
        const SizedBox(height: 6),
        _voiceList(),
        const SizedBox(height: 6),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: MqLink(
            text: _showAccount
                ? tr('Hide my own voices')
                : tr('Use one of my own voices'),
            onPressed: () {
              setState(() => _showAccount = !_showAccount);
              if (_showAccount && _accountVoices.isEmpty) {
                widget.app.loadVoices(_voiceProvider);
              }
            },
          ),
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

  /// How the search went, in one line. When filters had to be dropped it says
  /// which ones, because "some filters were relaxed" leaves the user guessing
  /// at exactly the moment they need to know what to change.
  String get _resultLine {
    if (_searching) return tr('Looking for voices...');
    if (_searchError.isNotEmpty) return '';
    if (_shortlist.isEmpty) {
      return tr('No voice matches this brief.');
    }
    if (_relaxed.isEmpty) {
      //: %1 is a number of voices
      return tr('%1 voice(s) match').arg(_shortlist.length);
    }
    final dropped =
        _relaxed.map(VoiceProfile.filterLabel).join(tr(', '));
    //: %1 is a number of voices, %2 a list of criteria such as "age, tone"
    return tr('%1 voice(s) — widened on: %2').arg(_shortlist.length).arg(dropped);
  }

  /// The brief itself. Every chip is optional: what is left unsaid widens the
  /// search rather than blocking it, and the language chip falls back to the
  /// one the ad is written in.
  Widget _brief() {
    return Wrap(
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
    );
  }

  void _briefChanged(String key, String value) {
    if (_draft.extraText(key) == value) return;
    setState(() => _draft.setExtra(key, value));
    _search(briefChanged: true);
  }

  Widget _voiceList() {
    final mq = context.mq;
    final chosen = _draft.extraText('voiceId');

    // A choice the current search does not return still has to be visible --
    // an actor cast last week under another brief, or one of the account's own
    // voices. Silently showing six voices with none of them ticked would read
    // as "your voice is gone".
    final elsewhere = chosen.isNotEmpty &&
        !_shortlist.any((voice) => voice.id == chosen) &&
        !(_showAccount && _accountVoices.any((voice) => voice.id == chosen));

    final rows = <Widget>[
      if (elsewhere)
        _VoiceRow(
          name: _draft.extraText('voiceName').isEmpty
              ? chosen
              : _draft.extraText('voiceName'),
          traits: tr('chosen earlier · outside this brief'),
          chosen: true,
          previewUrl: '',
          onChoose: () {},
          onPreview: () {},
        ),
      for (final voice in _shortlist)
        _VoiceRow(
          name: voice.name,
          traits: describeVoice(voice),
          chosen: voice.id == chosen,
          previewUrl: voice.previewUrl,
          onChoose: () => setState(() => _choose(voice)),
          onPreview: () => _preview(voice.previewUrl),
        ),
      if (_showAccount)
        for (final voice in _accountVoices)
          _VoiceRow(
            name: voice.label,
            traits: voice.description.isEmpty
                ? tr('on your account')
                //: %1 lists a voice's traits
                : tr('on your account · %1').arg(voice.description),
            chosen: voice.id == chosen,
            previewUrl: '',
            onChoose: () => setState(() {
              _draft
                ..setExtra('voiceId', voice.id)
                ..setExtra('voiceOwner', '')
                ..setExtra('voiceName', voice.label);
            }),
            onPreview: () {},
          ),
    ];

    if (rows.isEmpty) {
      return Text(
        _searching ? '' : tr('Widen the brief, or reload.'),
        style: TextStyle(color: mq.textTertiary, fontSize: MqTheme.fontSmall),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 186),
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        border: Border.all(color: mq.border),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(3),
        children: rows,
      ),
    );
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

/// One candidate: who they are, and what about them matched.
///
/// The traits line is not decoration. It is the receipt for the search -- six
/// rows all reading `fr-FR · Femme · Jeune · Réseaux sociaux` is how the user
/// sees that the chips did something, and one row that does not is how they
/// see a filter had to be given up.
class _VoiceRow extends StatelessWidget {
  const _VoiceRow({
    required this.name,
    required this.traits,
    required this.chosen,
    required this.previewUrl,
    required this.onChoose,
    required this.onPreview,
  });

  final String name;
  final String traits;
  final bool chosen;

  /// Empty for a voice with nothing to play: the account's own, which the paid
  /// audition covers anyway.
  final String previewUrl;

  final VoidCallback onChoose;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onChoose,
      snap: true,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: chosen
              ? mq.surfaceActive
              : states.active
              ? mq.surfaceHover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
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
                  if (traits.isNotEmpty)
                    Text(
                      traits,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: mq.textTertiary,
                        fontSize: MqTheme.fontSmall,
                      ),
                    ),
                ],
              ),
            ),
            if (previewUrl.isNotEmpty) ...[
              const SizedBox(width: 6),
              MqIconButton(
                icon: 'play-fill',
                //: Playing the provider's own sample costs nothing
                tip: tr('Listen — free'),
                size: 28,
                onPressed: onPreview,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
