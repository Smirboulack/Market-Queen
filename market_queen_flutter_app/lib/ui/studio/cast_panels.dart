import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../../models/asset_library.dart';
import '../dialogs/voice_picker.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chip.dart';
import '../widgets/fields.dart';
import '../widgets/media_drop.dart';
import '../widgets/voice_player.dart';

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
  /// The panel's own player. One transport, so the disc, the bar and the clock
  /// are three views of one thing rather than three states that can disagree.
  final AudioTransport _transport = AudioTransport();

  /// Where the dials stood when the last read was bought.
  ///
  /// A provider applies these on a text-to-speech call and nowhere else, so
  /// what is on disk after a read is that read -- not this actor as they stand
  /// now. Moving a dial makes the recording stale, and the disc has to buy a
  /// new one rather than replay the old one under a changed label.
  String _readSettings = '';

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
    if (_isActor) widget.app.voiceBooth.addListener(_onBooth);
  }

  @override
  void dispose() {
    if (_isActor) widget.app.voiceBooth.removeListener(_onBooth);
    _transport.dispose();
    super.dispose();
  }

  /// A fresh read plays itself: hearing them is the whole point of having
  /// bought it.
  void _onBooth() {
    if (!mounted) return;
    final sample = widget.app.voiceBooth.samplePath;
    if (sample.isNotEmpty && !_transport.holds(sample)) {
      _transport.toggle(sample);
    }
    setState(() {});
  }

  // ---- hearing the actor ---------------------------------------------------

  /// The four dials as one string, for telling a fresh read from a stale one.
  String _dialState(LibraryAsset asset) => [
        for (final dial in _dials)
          asset.extraNumber(dial.$2, dial.$5).toStringAsFixed(3),
      ].join(',');

  /// The read on disk, when it is still the read these dials describe.
  String _readOf(LibraryAsset asset) =>
      _readSettings == _dialState(asset) ? widget.app.voiceBooth.samplePath : '';

  /// Buys one read of the ad's own first line, in the voice as it now stands.
  ///
  /// The ad's request rather than the asset's extras: it is what the render
  /// will send, so what you hear is what you buy.
  void _readAloud(LibraryAsset asset) {
    _readSettings = _dialState(asset);
    widget.app.voiceBooth.audition(widget.app.request(), _line);
  }

  /// Opens the catalogue in the middle of the screen rather than inside this
  /// 300px column.
  Future<void> _changeVoice(LibraryAsset asset) async {
    await showVoiceStudio(
      context,
      app: widget.app,
      actor: asset,
      onSaved: (draft) {
        _library.save(draft);
        if (mounted) setState(() {});
      },
    );
    if (mounted) setState(() {});
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

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final asset = _asset;

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

  /// The four ElevenLabs dials, in the order they matter: name, key, range and
  /// where they sit untouched. They are the difference between a read that
  /// sounds human and one that sounds like an announcer.
  static List<(String, String, double, double, double)> get _dials => [
        (tr('Speed'), 'voiceSpeed', 0.7, 1.2, 1.0),
        (tr('Stability'), 'voiceStability', 0, 1, 0.45),
        (tr('Similarity'), 'voiceSimilarity', 0, 1, 0.8),
        (tr('Style exaggeration'), 'voiceStyle', 0, 1, 0.35),
      ];

  List<Widget> _actorRows(LibraryAsset asset) {
    final mq = context.mq;
    final booth = widget.app.voiceBooth;
    final chosen = asset.extraText('voiceName');
    final cast = asset.extraText('voiceId').isNotEmpty;
    final read = _readOf(asset);

    return [
      PanelRow(
        label: tr('Voice'),
        child: Pressable(
          onTap: () => _changeVoice(asset),
          tooltip: tr('Choose a voice'),
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
                'arrow-right-s-line',
                size: 15,
                color: states.active ? mq.textPrimary : mq.textTertiary,
              ),
            ],
          ),
        ),
      ),
      for (final dial in _dials)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: LabeledSlider(
            label: dial.$1,
            value: asset.extraNumber(dial.$2, dial.$5),
            from: dial.$3,
            to: dial.$4,
            onChanged: (value) => _set(dial.$2, value),
          ),
        ),
      const SizedBox(height: 8),
      // The player, where a "Hear the voice" button used to be. A button that
      // spends money and then leaves you looking at a button is the wrong shape
      // for this: what you want next is to hear it again, from halfway, without
      // paying twice -- which is a transport, not a verb.
      Row(
        children: [
          if (booth.auditioning)
            const SizedBox(
              width: 30,
              height: 30,
              child: Center(
                child: SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            PlayDisc(
              transport: _transport,
              source: read,
              enabled: cast,
              tip: tr('Listen'),
              // Nothing on disk for these settings: pressing play is how
              // somebody asks for the line to be read with them.
              onEmpty: () => _readAloud(asset),
              emptyTip: tr('Read the line with these settings'),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: TransportLine(transport: _transport, source: read),
          ),
          const SizedBox(width: 8),
          TransportClock(transport: _transport, source: read),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        booth.error.isNotEmpty
            ? booth.error
            : !cast
            ? tr('Choose a voice first.')
            : read.isEmpty
            ? tr('These settings are only heard on a read, which costs a '
                'fraction of a cent.')
            : tr('Your read of the first line, with these settings on it.'),
        style: TextStyle(
          color: booth.error.isNotEmpty ? mq.error : mq.textTertiary,
          fontSize: MqTheme.fontSmall,
          height: MqTheme.lineTight,
        ),
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
