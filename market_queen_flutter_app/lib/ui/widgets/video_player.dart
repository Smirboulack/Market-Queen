import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../../i18n/translator.dart';
import '../icons.dart';
import '../theme.dart';
import 'buttons.dart';
import 'mq_dialog.dart';

/// A clip that plays where it stands.
///
/// This is what replaced handing the file to the operating system. Pressing
/// play used to launch whatever the machine had registered for .mp4, which
/// throws a second window over the app, starts from a cold player, and leaves
/// you alt-tabbing back to the thing you were reviewing. A generated clip is
/// looked at ten times in a row while a prompt is tuned; it belongs on the same
/// surface as the prompt.
class InlineVideo extends StatefulWidget {
  const InlineVideo({
    super.key,
    required this.path,
    this.autoPlay = true,
    this.loop = false,
    this.showProgress = true,
  });

  final String path;

  /// On in the feed: the press that mounted this widget was a press of play.
  final bool autoPlay;

  final bool loop;

  /// The hairline along the bottom edge. Off in the lightbox, which has a real
  /// seek bar of its own.
  final bool showProgress;

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// Position is its own listenable rather than widget state: it ticks several
  /// times a second, and rebuilding the whole tile -- the video texture
  /// included -- at that rate to move a two-pixel line is not a trade worth
  /// making.
  final ValueNotifier<double> _progress = ValueNotifier(0);

  bool _playing = false;
  bool _hovered = false;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();

    _subscriptions.addAll([
      _player.stream.playing.listen((playing) {
        if (mounted) setState(() => _playing = playing);
      }),
      _player.stream.duration.listen((duration) {
        if (mounted) setState(() => _duration = duration);
      }),
      _player.stream.position.listen((position) {
        final total = _duration.inMilliseconds;
        _progress.value = total <= 0
            ? 0
            : (position.inMilliseconds / total).clamp(0.0, 1.0);
      }),
    ]);

    _player.setPlaylistMode(
      widget.loop ? PlaylistMode.single : PlaylistMode.none,
    );
    _open();
  }

  @override
  void didUpdateWidget(InlineVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _open();
  }

  void _open() {
    // A file that has been moved or swept away since the feed was written is a
    // black rectangle either way; opening it is what turns it into a stream of
    // decoder errors in the log.
    if (!File(widget.path).existsSync()) return;
    _player.open(
      Media(Uri.file(widget.path).toString()),
      play: widget.autoPlay,
    );
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _progress.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _player.playOrPause,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: _controller,
              controls: NoVideoControls,
              fill: Colors.black,
            ),
            // Paused, the badge is the invitation. Playing, it is only there
            // while the pointer is on the clip, so a clip you are watching is
            // a clip and nothing else.
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: !_playing || _hovered ? 1 : 0,
                duration: MqTheme.hoverDuration,
                child: Center(
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: mq.surface.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      border: Border.all(color: mq.border),
                    ),
                    child: MqIcon(
                      _playing ? 'pause-fill' : 'play-fill',
                      size: 18,
                      color: mq.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.showProgress)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _progress,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 2,
                      backgroundColor: Colors.black.withValues(alpha: 0.35),
                      valueColor: AlwaysStoppedAnimation(mq.textInverse),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A voice-over that plays where it stands.
///
/// There is nothing to look at, so it is a row: a play button, the file name,
/// and a line that fills as it goes. Same argument as the clips -- an audition
/// you listen to twice should not open a media player twice.
class InlineAudio extends StatefulWidget {
  const InlineAudio({super.key, required this.path});

  final String path;

  @override
  State<InlineAudio> createState() => _InlineAudioState();
}

class _InlineAudioState extends State<InlineAudio> {
  late final Player _player = Player();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final ValueNotifier<double> _progress = ValueNotifier(0);

  bool _playing = false;
  bool _opened = false;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _subscriptions.addAll([
      _player.stream.playing.listen((playing) {
        if (mounted) setState(() => _playing = playing);
      }),
      _player.stream.duration.listen((duration) {
        if (mounted) setState(() => _duration = duration);
      }),
      _player.stream.position.listen((position) {
        final total = _duration.inMilliseconds;
        _progress.value = total <= 0
            ? 0
            : (position.inMilliseconds / total).clamp(0.0, 1.0);
      }),
    ]);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _progress.dispose();
    _player.dispose();
    super.dispose();
  }

  /// Opened on the first press rather than on mount: a feed with twenty
  /// voice-overs in it would otherwise stand up twenty decoders to show twenty
  /// rows nobody has asked to hear.
  void _toggle() {
    if (!_opened) {
      if (!File(widget.path).existsSync()) return;
      _opened = true;
      _player.open(Media(Uri.file(widget.path).toString()));
      return;
    }
    _player.playOrPause();
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: _toggle,
      focusRadius: MqTheme.radius,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: states.active ? mq.surfaceHover : mq.surfaceSecondary,
          borderRadius: BorderRadius.circular(MqTheme.radius),
          border: Border.all(color: states.active ? mq.borderStrong : mq.border),
        ),
        child: Row(
          children: [
            MqIcon(
              _playing ? 'pause-fill' : 'play-fill',
              size: 20,
              color: mq.textPrimary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.basename(widget.path),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mq.textSecondary,
                      fontSize: MqTheme.fontSmall,
                      height: MqTheme.lineTight,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ValueListenableBuilder<double>(
                    valueListenable: _progress,
                    builder: (context, value, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: value,
                        minHeight: 3,
                        backgroundColor: mq.surfaceTertiary,
                        valueColor: AlwaysStoppedAnimation(mq.textTertiary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            MqIcon('sound-module-line', size: 18, color: mq.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// One clip, as large as the window will allow, still inside the app.
///
/// The counterpart of the picture lightbox, and the answer to the other half of
/// the same complaint: full screen should mean full screen *here*, not a second
/// application.
Future<void> showVideoLightbox(BuildContext context, String path) {
  return showMqModal<void>(
    context: context,
    child: Builder(
      builder: (context) {
        final mq = context.mq;
        final size = MediaQuery.sizeOf(context);

        return SizedBox(
          // A concrete size rather than a constraint: the modal centres its
          // child inside a scroll view, and a player has no opinion about how
          // big it wants to be. Letterboxing inside a black box is what every
          // other player does with the leftover room.
          width: (size.width - 160).clamp(360.0, 1600.0),
          height: (size.height - 160).clamp(240.0, 1000.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(MqTheme.radiusLarge),
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _LightboxVideo(path: path),
                  Positioned(
                    right: 10,
                    top: 10,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: mq.surface.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(
                          MqTheme.radiusSmall,
                        ),
                        border: Border.all(color: mq.border),
                      ),
                      child: MqIconButton(
                        icon: 'fullscreen-exit-line',
                        tip: tr('Close'),
                        size: 28,
                        onPressed: () => closeMqModal(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// The lightbox's own player. Its controls are the stock adaptive ones -- at
/// this size there is room for a real seek bar, and the same set the render
/// view has used all along.
class _LightboxVideo extends StatefulWidget {
  const _LightboxVideo({required this.path});

  final String path;

  @override
  State<_LightboxVideo> createState() => _LightboxVideoState();
}

class _LightboxVideoState extends State<_LightboxVideo> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  @override
  void initState() {
    super.initState();
    if (File(widget.path).existsSync()) {
      _player.open(Media(Uri.file(widget.path).toString()));
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Video(
    controller: _controller,
    controls: AdaptiveVideoControls,
    fill: Colors.black,
  );
}
