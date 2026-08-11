import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../app_state.dart';
import '../../core/http_util.dart';
import '../../i18n/translator.dart';
import '../../models/asset_library.dart';
import '../../providers/types.dart';
import '../../providers/voice_profile.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chip.dart';
import '../widgets/fields.dart';
import '../widgets/media_drop.dart';

/// The column that opens when the cast actor or scene on the bar is pressed.
///
/// It is where the settings that belong to *this ad's* casting live, as against
/// the ones that belong to the library entry. The distinction is what the old
/// editor got wrong: an actor's voice is not a property of the actor the way
/// their face is -- it is how they read this script -- and burying it four
/// scrolls down a creation form meant nobody ever touched the four dials that
/// decide whether the read sounds human or like an announcer.
///
/// It writes straight through to the library entry and saves as it goes. There
/// is no Save button because there is nothing to cancel: every control here is
/// one value, and changing it is the whole of the intent.
class CastPanel extends StatefulWidget {
  const CastPanel({
    super.key,
    required this.app,
    required this.kind,
    required this.onClose,
    required this.onReplace,
  });

  final AppState app;
  final AssetKind kind;
  final VoidCallback onClose;

  /// Opens the gallery to cast somebody else.
  final VoidCallback onReplace;

  /// The panel matches the settings column: same slot, same width, same cap.
  static const double maxHeight = 460;

  @override
  State<CastPanel> createState() => _CastPanelState();
}

class _CastPanelState extends State<CastPanel> {
  Player? _player;

  /// Who the brief turned up, best first, and what had to be given up to turn
  /// up anybody at all.
  List<LibraryVoice> _shortlist = const [];
  List<String> _relaxed = const [];
  bool _searching = false;
  String _searchError = '';
  bool _voicesOpen = false;

  String _lastSample = '';

  bool get _isActor => widget.kind == AssetKind.actor;

  AssetLibrary get _library =>
      _isActor ? widget.app.actors : widget.app.scenes;

  LibraryAsset? get _asset {
    final project = widget.app.project;
    if (_isActor) {
      return project.actorIds.isEmpty
          ? null
          : widget.app.actors.byId(project.actorIds.first);
    }
    return widget.app.scenes.byId(project.sceneId);
  }

  @override
  void initState() {
    super.initState();
    if (_isActor) {
      widget.app.voiceBooth.addListener(_onBooth);
      _search();
    }
  }

  @override
  void dispose() {
    if (_isActor) widget.app.voiceBooth.removeListener(_onBooth);
    _player?.dispose();
    super.dispose();
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

  /// Writes one value on the cast asset and puts it back in the library.
  ///
  /// Saved on every change rather than on a button: the panel is a set of
  /// dials, and a dial you have to remember to commit is a dial that silently
  /// does nothing.
  void _set(String key, Object? value) {
    final asset = _asset;
    if (asset == null) return;
    final draft = asset.copy()..setExtra(key, value);
    _library.save(draft);
    setState(() {});
  }

  // ---- the voice -----------------------------------------------------------

  String get _voiceProvider {
    final id = widget.app.settings.prefString('voiceProvider');
    return id.isEmpty ? widget.app.registry.defaultProvider('voice') : id;
  }

  /// Runs the actor's brief past the provider. Cached for a day unless
  /// [refresh].
  Future<void> _search({bool refresh = false}) async {
    final asset = _asset;
    if (asset == null) return;

    final casting = widget.app.voiceCasting;
    final registry = widget.app.registry;
    final settings = widget.app.settings;
    final provider = _voiceProvider;
    final profile = VoiceProfile.from(asset.extras);

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

  // ---- build ---------------------------------------------------------------

  /// Whose brief the shortlist on screen belongs to. Casting somebody else
  /// without this leaves the previous actor's voices sitting under the new
  /// one's name, which is the sort of thing nobody notices until the render.
  String _searchedFor = '';

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final asset = _asset;

    if (_isActor && asset != null && asset.id != _searchedFor) {
      _searchedFor = asset.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search();
      });
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: CastPanel.maxHeight),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
        decoration: BoxDecoration(
          color: mq.surface,
          borderRadius: BorderRadius.circular(MqTheme.radiusLarge),
          border: Border.all(color: mq.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(asset),
            const SizedBox(height: MqTheme.gap),
            if (asset == null)
              Text(
                _isActor
                    ? tr('Nobody is cast in this ad yet.')
                    : tr('No scene is set for this ad yet.'),
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontSmall,
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: _isActor
                        ? _actorRows(asset)
                        : _sceneRows(asset),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(LibraryAsset? asset) {
    final mq = context.mq;

    return Row(
      children: [
        if (asset != null && asset.thumbnail.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
            child: SizedBox(
              width: 30,
              height: 30,
              child: LocalImage(asset.thumbnail),
            ),
          ),
          const SizedBox(width: 9),
        ],
        Expanded(
          child: Text(
            asset?.name ?? (_isActor ? tr('Actor') : tr('Scene')),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: mq.textPrimary,
              fontSize: MqTheme.fontBody,
              fontWeight: FontWeight.w600,
              letterSpacing: MqTheme.trackTitle,
            ),
          ),
        ),
        MqIconButton(
          icon: 'shuffle-line',
          tip: _isActor ? tr('Cast somebody else') : tr('Film somewhere else'),
          size: 24,
          onPressed: widget.onReplace,
        ),
        MqIconButton(
          icon: 'close-line',
          tip: tr('Close'),
          size: 24,
          onPressed: widget.onClose,
        ),
      ],
    );
  }

  // ---- the actor's read ----------------------------------------------------

  List<Widget> _actorRows(LibraryAsset asset) {
    final mq = context.mq;
    final booth = widget.app.voiceBooth;
    final chosen = asset.extraText('voiceName');

    return [
      PanelRow(
        label: tr('Voice'),
        child: Pressable(
          onTap: () => setState(() => _voicesOpen = !_voicesOpen),
          focusRadius: MqTheme.radiusSmall,
          builder: (context, states) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  chosen.isEmpty ? tr('Choose one') : chosen,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: chosen.isEmpty ? mq.textTertiary : mq.textPrimary,
                    fontSize: MqTheme.fontLabel,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              MqIcon(
                _voicesOpen ? 'arrow-up-s-line' : 'arrow-down-s-line',
                size: 15,
                color: states.active ? mq.textPrimary : mq.textTertiary,
              ),
            ],
          ),
        ),
      ),
      if (_voicesOpen) ...[
        _brief(asset),
        const SizedBox(height: 8),
        _voiceList(asset),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                _resultLine,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mq.textTertiary,
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
        if (_searchError.isNotEmpty)
          Text(
            _searchError,
            style: TextStyle(color: mq.error, fontSize: MqTheme.fontSmall),
          ),
        const SizedBox(height: 10),
      ],
      // The four ElevenLabs dials, in the order they matter. They are the
      // difference between a read that sounds human and one that sounds like an
      // announcer, and until now they were on no screen at all.
      _slider(asset, tr('Speed'), 'voiceSpeed', 0.7, 1.2, 1.0),
      _slider(asset, tr('Stability'), 'voiceStability', 0, 1, 0.45),
      _slider(asset, tr('Similarity'), 'voiceSimilarity', 0, 1, 0.8),
      _slider(asset, tr('Style exaggeration'), 'voiceStyle', 0, 1, 0.35),
      const SizedBox(height: 4),
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
                asset.extraText('voiceId').isNotEmpty,
            // The ad's own request, not the asset's extras: it is what the
            // render will send, so what you hear is what you buy.
            onPressed: () => booth.audition(widget.app.request(), _line),
          ),
        ],
      ),
    ];
  }

  /// What the audition says. The ad's own first sentence when there is one --
  /// hearing the actual script is worth more than hearing a stock line -- and a
  /// stock line when the script is still empty.
  String get _line {
    final script = widget.app.project.script.trim();
    if (script.isEmpty) {
      return tr('Honestly, I did not think this would work.');
    }
    final first = script.split(RegExp(r'(?<=[.!?])\s+')).first.trim();
    return first.length > 220 ? first.substring(0, 220) : first;
  }

  Widget _slider(
    LibraryAsset asset,
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
        value: asset.extraNumber(key, fallback),
        from: from,
        to: to,
        onChanged: (value) => _set(key, value),
      ),
    );
  }

  /// The casting brief. Every chip is optional: what is left unsaid widens the
  /// search rather than blocking it.
  Widget _brief(LibraryAsset asset) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          MqPickChip(
            label: tr('Language'),
            icon: 'translate-line',
            menuWidth: 260,
            value: asset.extraText('voiceLocale'),
            options: [
              MenuOption(tr('Same as the ad'), ''),
              for (final locale in VoiceLocale.all)
                MenuOption(locale.menuLabel, locale.id),
            ],
            onPicked: (value) => _briefChanged(asset, 'voiceLocale', value),
          ),
          for (final trait in VoiceTrait.all)
            MqChoiceChip(
              label: trait.label,
              value: asset.extraText(trait.key),
              onPicked: (value) => _briefChanged(asset, trait.key, value),
              options: [
                for (final option in trait.options)
                  MenuOption(option.$1, option.$2),
              ],
            ),
        ],
      ),
    );
  }

  void _briefChanged(LibraryAsset asset, String key, String value) {
    if (asset.extraText(key) == value) return;
    _set(key, value);
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

  Widget _voiceList(LibraryAsset asset) {
    final mq = context.mq;
    final chosen = asset.extraText('voiceId');

    if (_shortlist.isEmpty) {
      return Text(
        _searching ? '' : tr('Widen the brief, or reload.'),
        style: TextStyle(color: mq.textTertiary, fontSize: MqTheme.fontSmall),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 150),
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        border: Border.all(color: mq.border),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(3),
        children: [
          for (final voice in _shortlist)
            _VoiceRow(
              name: voice.name,
              traits: describeVoice(voice),
              chosen: voice.id == chosen,
              previewUrl: voice.previewUrl,
              onChoose: () {
                final draft = asset.copy()
                  ..setExtra('voiceId', voice.id)
                  // Travels with the id: a library voice has to be put on the
                  // account before it can speak, and the render may be the
                  // first thing that needs it.
                  ..setExtra('voiceOwner', voice.ownerId)
                  ..setExtra('voiceName', voice.name);
                _library.save(draft);
                setState(() {});
              },
              onPreview: () {
                if (voice.previewUrl.isEmpty) return;
                (_player ??= Player()).open(Media(voice.previewUrl));
              },
            ),
        ],
      ),
    );
  }

  // ---- the scene's dials ---------------------------------------------------

  List<Widget> _sceneRows(LibraryAsset asset) {
    return [
      for (var i = 0; i < SceneTweak.all.length; ++i)
        PanelRow(
          label: SceneTweak.all[i].label,
          divider: i < SceneTweak.all.length - 1,
          child: _PanelPick(
            value: asset.extraText(SceneTweak.all[i].key),
            options: [
              MenuOption(tr("doesn't matter"), ''),
              for (final option in SceneTweak.all[i].options)
                MenuOption(option.$1, option.$2),
            ],
            onPicked: (value) => _set(SceneTweak.all[i].key, value),
          ),
        ),
    ];
  }
}

/// A label on the left, its control on the right, and -- unless it is the last
/// one -- a hairline under it.
///
/// The same row the settings column uses, so the three panels that share that
/// slot are the same object with different contents rather than three
/// near-identical layouts drifting apart.
class PanelRow extends StatelessWidget {
  const PanelRow({
    super.key,
    required this.label,
    required this.child,
    this.divider = true,
  });

  final String label;
  final Widget child;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Padding(
      padding: EdgeInsets.only(bottom: divider ? 4 : 0),
      child: Column(
        children: [
          // The value is capped at a share of the row and the label takes
          // whatever is left, rather than the two splitting it in a fixed
          // ratio. Both other arrangements truncate something.
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mq.textSecondary,
                      fontSize: MqTheme.fontLabel,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.62,
                  ),
                  child: child,
                ),
              ],
            ),
          ),
          if (divider) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: mq.borderSubtle),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

/// The right-hand half of a panel row: the current value, and a chevron.
class _PanelPick extends StatelessWidget {
  const _PanelPick({
    required this.value,
    required this.options,
    required this.onPicked,
  });

  final String value;
  final List<MenuOption<String>> options;
  final ValueChanged<String> onPicked;

  String get _label {
    for (final option in options) {
      if (option.value == value) return option.label;
    }
    return options.isEmpty ? '' : options.first.label;
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Builder(
      builder: (anchor) => Pressable(
        onTap: () async {
          final picked = await showChipMenu<String>(
            anchor,
            options: options,
            current: value,
            width: 240,
          );
          if (picked != null) onPicked(picked);
        },
        focusRadius: MqTheme.radiusSmall,
        builder: (context, states) => AnimatedContainer(
          duration: states.duration,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: states.active ? mq.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _label,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: value.isEmpty ? mq.textTertiary : mq.textPrimary,
                    fontSize: MqTheme.fontLabel,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              MqIcon(
                'arrow-down-s-line',
                size: 15,
                color: states.active ? mq.textPrimary : mq.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One candidate: who they are, and what about them matched.
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
                size: 26,
                onPressed: onPreview,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
