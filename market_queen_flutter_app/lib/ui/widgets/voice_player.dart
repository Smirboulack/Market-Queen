import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../i18n/translator.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';
import 'buttons.dart';

/// One player for a whole screen.
///
/// The actor editor used to have three ways to hear a voice -- a "Quick listen"
/// row on the overview, a "Test the voice" button in the voice section's
/// heading, and a play disc on every row of the shortlist -- and no way at all
/// to know which of them was making the noise, whether it was still going, or
/// how much of it was left. Three transports also meant three things could play
/// at once.
///
/// So there is one, it is owned by the screen rather than by any section of it,
/// and every play button on the page is a view onto it: pressing the disc on a
/// row and pressing the disc under the portrait are the same transport when
/// they point at the same audio, which is what lets the row and the card show
/// each other's progress.
///
/// The [Player] is built on the first press rather than in the constructor.
/// media_kit needs its native side initialised, which a widget test does not do
/// -- and a screen nobody pressed play on has no business opening an audio
/// device.
class AudioTransport extends ChangeNotifier {
  Player? _player;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// How far through, 0 to 1.
  ///
  /// Its own listenable rather than part of the notifier: it ticks several
  /// times a second and only two-pixel lines and one clock read it. Rebuilding
  /// a section of the editor at that rate to move a line is not a trade worth
  /// making.
  final ValueNotifier<double> progress = ValueNotifier(0);

  /// The same again, as a position, for the clock beside the bar.
  final ValueNotifier<Duration> elapsed = ValueNotifier(Duration.zero);

  String _source = '';
  bool _playing = false;
  Duration _duration = Duration.zero;

  /// What is loaded: a local path or a preview URL. Empty before the first
  /// press.
  String get source => _source;

  bool get playing => _playing;

  /// How long the loaded audio runs. Zero until the decoder has said.
  Duration get duration => _duration;

  /// Whether [source] is the audio that is playing right now.
  bool isPlaying(String source) =>
      _playing && source.isNotEmpty && source == _source;

  /// Whether [source] is loaded, playing or paused.
  bool holds(String source) => source.isNotEmpty && source == _source;

  /// Plays [source], or pauses it if it is already the one playing.
  ///
  /// The button changes on the press rather than on the player's answer.
  /// `stream.playing` comes back over a platform channel a frame or three
  /// later, and a play button that waits for it reads as a click that did not
  /// register -- so the state is set here and the stream is left to confirm it.
  void toggle(String source) {
    if (source.isEmpty) return;

    final player = _ensure();
    if (source == _source) {
      if (_playing) {
        _playing = false;
        player.pause();
      } else {
        _playing = true;
        player.play();
      }
      notifyListeners();
      return;
    }

    _source = source;
    _playing = true;
    _duration = Duration.zero;
    progress.value = 0;
    elapsed.value = Duration.zero;
    notifyListeners();
    player.open(Media(source));
  }

  /// Jumps to [fraction] of the way through, 0 to 1.
  ///
  /// The bar moves immediately and the player is told after: a scrub that waits
  /// for the decoder to seek before the line follows the pointer feels like a
  /// control that is fighting you.
  void seekTo(double fraction) {
    if (_source.isEmpty || _duration <= Duration.zero) return;
    final clamped = fraction.clamp(0.0, 1.0);
    final position = Duration(
      milliseconds: (_duration.inMilliseconds * clamped).round(),
    );
    progress.value = clamped;
    elapsed.value = position;
    _player?.seek(position);
  }

  /// Stops and forgets what was loaded -- for when the audio itself goes away:
  /// the voice is taken off the actor, or the take it belonged to is discarded.
  void clear() {
    if (_source.isEmpty) return;
    _player?.stop();
    _source = '';
    _playing = false;
    _duration = Duration.zero;
    progress.value = 0;
    elapsed.value = Duration.zero;
    notifyListeners();
  }

  Player _ensure() {
    final existing = _player;
    if (existing != null) return existing;

    final player = Player();
    _player = player;
    _subscriptions.addAll([
      player.stream.playing.listen((playing) {
        if (_playing == playing) return;
        _playing = playing;
        notifyListeners();
      }),
      player.stream.duration.listen((duration) {
        if (_duration == duration) return;
        _duration = duration;
        notifyListeners();
      }),
      player.stream.position.listen((position) {
        final total = _duration.inMilliseconds;
        elapsed.value = position;
        progress.value =
            total <= 0 ? 0 : (position.inMilliseconds / total).clamp(0.0, 1.0);
      }),
      // A clip that has run out is not a paused clip: the disc goes back to
      // play and the bar goes back to nothing, rather than sitting full.
      player.stream.completed.listen((completed) {
        if (!completed) return;
        progress.value = 0;
        elapsed.value = Duration.zero;
        notifyListeners();
      }),
    ]);
    return player;
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    progress.dispose();
    elapsed.dispose();
    _player?.dispose();
    super.dispose();
  }
}

/// The round play button, and the one control that says what the transport is
/// doing: it is a pause while its own audio is running and a play the rest of
/// the time.
///
/// [filled] is the disc under the portrait -- ink, because it is the transport
/// for the whole screen. The rows use the outlined one.
class PlayDisc extends StatelessWidget {
  const PlayDisc({
    super.key,
    required this.transport,
    required this.source,
    this.size = 30,
    this.filled = false,
    this.tip = '',
    this.enabled = true,
    this.onEmpty,
    this.emptyTip = '',
  });

  final AudioTransport transport;

  /// What this disc plays. Empty means there is nothing to hear, and the disc
  /// says so rather than disappearing -- a control that comes and goes moves
  /// everything beside it.
  final String source;

  final double size;
  final bool filled;
  final String tip;
  final bool enabled;

  /// What to do when there is nothing on disk yet.
  ///
  /// For the one player that can go and fetch its own audio: a voice with no
  /// free sample has to be bought a line before it can be heard, and pressing
  /// play is exactly what somebody means by that. Left null, an empty source is
  /// simply a dead disc.
  final VoidCallback? onEmpty;

  final String emptyTip;

  @override
  Widget build(BuildContext context) {
    // Listening here rather than in the screen that hosts it. A play button
    // whose glyph depends on a transport has to be rebuilt by that transport,
    // or it shows "play" while the audio is already running -- which is exactly
    // what it did when only the voice panel happened to be listening.
    return ListenableBuilder(
      listenable: transport,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final mq = context.mq;
    final loadable = source.isNotEmpty || onEmpty != null;
    final live = enabled && loadable;
    final running = transport.isPlaying(source);

    return Pressable(
      enabled: live,
      onTap: source.isNotEmpty ? () => transport.toggle(source) : onEmpty,
      tooltip: !live
          ? tr('No sample for this voice')
          : running
          ? tr('Pause')
          : source.isEmpty && emptyTip.isNotEmpty
          ? emptyTip
          : tip,
      focusRadius: MqTheme.radiusPill,
      builder: (context, states) {
        // Playing wins over hover: the black disc *is* the "it is running"
        // signal, and letting the pointer lighten it takes that away at the
        // exact moment somebody is reaching for it.
        final Color fill;
        final Color line;
        if (running) {
          fill = mq.primary;
          line = mq.primary;
        } else if (states.pressed) {
          fill = mq.surfaceActive;
          line = mq.borderStrong;
        } else if (states.hovered) {
          fill = mq.surfaceHover;
          line = filled ? mq.borderStrong : mq.primary;
        } else {
          fill = filled ? mq.surfaceSecondary : mq.surface;
          line = mq.border;
        }

        return AnimatedContainer(
          duration: states.duration,
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: line),
          ),
          child: MqIcon(
            running ? 'pause-fill' : 'play-fill',
            size: size * 0.47,
            color: running
                ? mq.onPrimary
                : live
                ? mq.textPrimary
                : mq.textDisabled,
          ),
        );
      },
    );
  }
}

/// The line that fills as the audio runs, and the handle that moves it.
///
/// It reports and it scrubs, and the second half is why it is not two pixels
/// tall: a nine-second sample is exactly the length where "play that bit again"
/// matters, and a two-pixel line is a target nobody can hit. So the widget is
/// [hitHeight] tall and mostly empty, the line itself is drawn [height] in the
/// middle of it, and the handle appears under the pointer rather than sitting
/// on a bar that is not playing anything.
///
/// The empty space is also the fix for the crowding: given its own strip, the
/// line stops sitting on the row of tags above it.
class TransportLine extends StatefulWidget {
  const TransportLine({
    super.key,
    required this.transport,
    required this.source,
    this.height = 3,
    this.hitHeight = 12,
  });

  final AudioTransport transport;
  final String source;
  final double height;

  /// How tall the target is. The line is drawn in the middle of it.
  final double hitHeight;

  @override
  State<TransportLine> createState() => _TransportLineState();
}

class _TransportLineState extends State<TransportLine> {
  bool _hovered = false;
  bool _dragging = false;

  double _fractionAt(Offset local, double width) =>
      width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return ListenableBuilder(
      listenable: widget.transport,
      builder: (context, _) {
        final live = widget.transport.holds(widget.source) &&
            widget.transport.duration > Duration.zero;

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            void scrub(Offset local) =>
                widget.transport.seekTo(_fractionAt(local, width));

            return MouseRegion(
              cursor: live
                  ? SystemMouseCursors.click
                  : MouseCursor.defer,
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Nothing loaded means nothing to seek in, and a bar that
                // swallows the click without doing anything is worse than one
                // that lets the row underneath have it.
                onTapDown: live ? (d) => scrub(d.localPosition) : null,
                onHorizontalDragStart: live
                    ? (d) {
                        setState(() => _dragging = true);
                        scrub(d.localPosition);
                      }
                    : null,
                onHorizontalDragUpdate:
                    live ? (d) => scrub(d.localPosition) : null,
                onHorizontalDragEnd:
                    live ? (_) => setState(() => _dragging = false) : null,
                onHorizontalDragCancel:
                    live ? () => setState(() => _dragging = false) : null,
                child: SizedBox(
                  height: widget.hitHeight,
                  child: Center(
                    child: ValueListenableBuilder<double>(
                      valueListenable: widget.transport.progress,
                      builder: (context, value, _) {
                        final played = live ? value : 0.0;
                        final handle = live && (_hovered || _dragging);

                        return Stack(
                          clipBehavior: Clip.none,
                          alignment: AlignmentDirectional.centerStart,
                          children: [
                            ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(widget.height / 2),
                              child: SizedBox(
                                height: widget.height,
                                width: double.infinity,
                                child: ColoredBox(
                                  color: mq.surfaceTertiary,
                                  child: FractionallySizedBox(
                                    alignment:
                                        AlignmentDirectional.centerStart,
                                    widthFactor: played,
                                    child: ColoredBox(color: mq.primary),
                                  ),
                                ),
                              ),
                            ),
                            if (handle)
                              Positioned(
                                // Centred on the playhead and kept inside the
                                // track at both ends, so it never hangs off
                                // the edge of the row it is drawn in.
                                left: (width - 12) * played,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: mq.surface,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: mq.primary,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Elapsed over total, as a clock. Tabular, so the row does not twitch as the
/// digits change.
class TransportClock extends StatelessWidget {
  const TransportClock({
    super.key,
    required this.transport,
    required this.source,
  });

  final AudioTransport transport;
  final String source;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return ListenableBuilder(
      listenable: transport,
      builder: (context, _) {
        final live = transport.holds(source);
        final total = Format.clock(live ? transport.duration : Duration.zero);

        return ValueListenableBuilder<Duration>(
          valueListenable: transport.elapsed,
          builder: (context, value, _) => Text(
            //: %1 is how far into a clip playback is, %2 how long it runs
            tr('%1 / %2')
                .arg(Format.clock(live ? value : Duration.zero))
                .arg(total),
            style: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontMicro,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}

/// The voice this actor has, under their portrait, on every section.
///
/// It replaced three separate controls, and the argument for putting it here is
/// the same one that puts the portrait here: who reads the ad is a fact about
/// the person, not about the section you happen to be in. Changing the voice in
/// the voice section moves this card; hearing it from the Looks section costs
/// nothing.
///
/// The cross detaches the voice from *this actor*. It does not delete anything
/// -- that verb lives on the shelf, next to a bin -- and the tooltip says so.
class VoicePlayerCard extends StatelessWidget {
  const VoicePlayerCard({
    super.key,
    required this.transport,
    required this.name,
    required this.provenance,
    required this.source,
    this.note = '',
    this.busy = false,
    this.onDetach,
    this.onAudition,
  });

  final AudioTransport transport;

  /// The cast voice's name, empty when the actor has none yet.
  final String name;

  /// Where it came from: designed, cloned, or the library.
  final String provenance;

  /// What the disc plays: the last audition, or the voice's own preview.
  final String source;

  /// One line under the bar. The cost of listening, or whatever the booth is
  /// complaining about.
  final String note;

  /// An audition is being bought. The disc waits rather than lying about
  /// having something to play.
  final bool busy;

  final VoidCallback? onDetach;

  /// Buys a line in this voice, for a voice with no free sample to fall back
  /// on. Pressing play is what somebody means by it.
  final VoidCallback? onAudition;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final cast = name.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(10),
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
            children: [
              if (busy)
                SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(mq.textTertiary),
                      ),
                    ),
                  ),
                )
              else
                PlayDisc(
                  transport: transport,
                  source: source,
                  size: 34,
                  filled: true,
                  enabled: cast,
                  tip: tr('Listen'),
                  onEmpty: onAudition,
                  emptyTip: tr('Hear a line in this voice'),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cast ? name : tr('No voice yet'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cast ? mq.textPrimary : mq.textTertiary,
                        fontSize: MqTheme.fontSmall + 0.5,
                        fontWeight: FontWeight.w600,
                        height: MqTheme.lineTight,
                      ),
                    ),
                    if (provenance.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        provenance,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: mq.textTertiary,
                          fontSize: MqTheme.fontMicro,
                          height: MqTheme.lineTight,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (cast && onDetach != null)
                MqIconButton(
                  icon: 'close-line',
                  tip: tr('Take the voice off this actor'),
                  size: 24,
                  onPressed: onDetach,
                ),
            ],
          ),
          // The bar carries its own breathing room now, so the gaps around it
          // are the difference rather than the whole of it.
          const SizedBox(height: 4),
          TransportLine(transport: transport, source: source, hitHeight: 14),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mq.textTertiary,
                    fontSize: MqTheme.fontMicro,
                    height: MqTheme.lineTight,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TransportClock(transport: transport, source: source),
            ],
          ),
        ],
      ),
    );
  }
}
