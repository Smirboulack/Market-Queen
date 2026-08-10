import 'dart:io';

import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/platform_util.dart';
import '../../i18n/translator.dart';
import '../../media/ffmpeg.dart';
import '../../models/canvas_feed.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/media_drop.dart';
import '../widgets/mq_dialog.dart';
import '../widgets/skeleton.dart';
import 'studio_card.dart';

/// The middle of the studio: everything this ad has generated, oldest at the
/// top, newest at the bottom.
///
/// It is a conversation, not a document. You ask for something in the bar
/// underneath and the answer appears here -- as skeletons the moment the
/// request leaves, filled in one by one as the results land. There is no
/// separate render screen to be sent to and nothing to come back from, which is
/// the whole point: the thing you asked for and the thing you got are on the
/// same surface.
class CanvasView extends StatefulWidget {
  const CanvasView({
    super.key,
    required this.app,
    required this.onOpenRender,
    this.bottomInset = 0,
  });

  final AppState app;

  /// The finished ads carry a way through to their run detail -- the shot list,
  /// the per-scene reshoot, the log. That view still exists; it is simply no
  /// longer where Generate takes you.
  final VoidCallback onOpenRender;

  /// How much of the bottom edge the composer stands in front of. The feed
  /// scrolls under it and pads itself by this much so the newest tile can still
  /// be brought clear.
  final double bottomInset;

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  final ScrollController _scroll = ScrollController();

  int _lastCount = 0;

  CanvasFeed get _feed => widget.app.project.feed;

  @override
  void initState() {
    super.initState();
    _feed.addListener(_onFeed);
    _lastCount = _feed.batches.length;
  }

  @override
  void dispose() {
    _feed.removeListener(_onFeed);
    _scroll.dispose();
    super.dispose();
  }

  /// Follows the newest batch down, and only on a new batch.
  ///
  /// Scrolling on every notification would yank the view out from under
  /// somebody reading an older result while ten tiles fill in behind them.
  void _onFeed() {
    final count = _feed.batches.length;
    if (count <= _lastCount) {
      _lastCount = count;
      return;
    }
    _lastCount = count;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return SkeletonScope(
      child: ListenableBuilder(
        listenable: _feed,
        builder: (context, _) {
          final batches = _feed.batches;
          if (batches.isEmpty) {
            return _EmptyCanvas(bottomInset: widget.bottomInset);
          }

          return ListView.separated(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(
              MqTheme.pagePadding,
              MqTheme.gapLarge,
              MqTheme.pagePadding,
              MqTheme.gapLarge + widget.bottomInset,
            ),
            itemCount: batches.length,
            separatorBuilder: (context, _) =>
                const SizedBox(height: MqTheme.gapLarge + 6),
            itemBuilder: (context, index) => _BatchBlock(
              app: widget.app,
              batch: batches[index],
              onOpenRender: widget.onOpenRender,
              onRemove: () => _feed.remove(batches[index].id),
            ),
          );
        },
      ),
    );
  }
}

/// Nothing generated yet.
///
/// Two stacked cards and one sentence. It says what the surface is for without
/// putting a button on it: the bar underneath is the only way in, and pointing
/// somewhere else would be a second answer to the same question.
class _EmptyCanvas extends StatelessWidget {
  const _EmptyCanvas({this.bottomInset = 0});

  /// Keeps the invitation in the middle of the *visible* canvas rather than the
  /// middle of the surface the composer covers the bottom of.
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 92,
              height: 74,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 6,
                    child: Container(
                      width: 46,
                      height: 62,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          MqTheme.radiusSmall,
                        ),
                        border: Border.all(color: mq.border),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 52,
                      height: 68,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: mq.surface,
                        borderRadius: BorderRadius.circular(
                          MqTheme.radiusSmall,
                        ),
                        border: Border.all(color: mq.borderStrong),
                      ),
                      child: MqIcon(
                        'movie-2-line',
                        size: 20,
                        color: mq.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MqTheme.gapLarge),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                tr(
                  'Everything you generate lands here: talking actors, videos, '
                  'images.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontBody,
                  height: MqTheme.lineBody,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One press of the send button: what was asked for, and the tiles it produced.
class _BatchBlock extends StatelessWidget {
  const _BatchBlock({
    required this.app,
    required this.batch,
    required this.onOpenRender,
    required this.onRemove,
  });

  final AppState app;
  final CanvasBatch batch;
  final VoidCallback onOpenRender;
  final VoidCallback onRemove;

  /// How wide a tile wants to be. Below this the grid drops a column rather
  /// than shrinking every tile past the point of being readable.
  static const double _idealTile = 210;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context),
        const SizedBox(height: 10),
        if (batch.allFailed)
          _Failure(message: batch.firstError)
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = (constraints.maxWidth / _idealTile)
                  .floor()
                  .clamp(1, 5);
              const gap = 10.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final item in batch.items)
                    SizedBox(
                      width: width,
                      child: _ResultTile(
                        app: app,
                        batch: batch,
                        item: item,
                        onOpenRender: onOpenRender,
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _header(BuildContext context) {
    final mq = context.mq;

    final facts = <String>[
      if (batch.modelLabel.isNotEmpty) batch.modelLabel,
      if (batch.aspectRatio.isNotEmpty) batch.aspectRatio,
      formatStamp(batch.createdAt),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: MqIcon(_glyph, size: 15, color: mq.textTertiary),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                batch.prompt.isEmpty ? _fallbackTitle : batch.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mq.textPrimary,
                  fontSize: MqTheme.fontLabel,
                  height: MqTheme.lineTight,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                facts.join(' · '),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontSmall,
                  height: MqTheme.lineTight,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: MqTheme.gap),
        MqIconButton(
          icon: 'delete-bin-line',
          tip: tr('Remove from the canvas'),
          destructive: true,
          // Removing while requests are still out would leave them writing into
          // a batch nobody can see.
          enabled: !batch.running,
          onPressed: onRemove,
        ),
      ],
    );
  }

  String get _glyph => switch (batch.kind) {
    CanvasKind.video => 'clapperboard-line',
    CanvasKind.ad => 'user-voice-line',
    CanvasKind.audio => 'volume-up-line',
    CanvasKind.image => 'image-line',
  };

  String get _fallbackTitle => switch (batch.kind) {
    CanvasKind.video => tr('Video'),
    CanvasKind.ad => tr('Talking actor'),
    CanvasKind.audio => tr('Voice-over'),
    CanvasKind.image => tr('Image'),
  };
}

/// One result, at whatever stage it is at.
class _ResultTile extends StatefulWidget {
  const _ResultTile({
    required this.app,
    required this.batch,
    required this.item,
    required this.onOpenRender,
  });

  final AppState app;
  final CanvasBatch batch;
  final CanvasItem item;
  final VoidCallback onOpenRender;

  @override
  State<_ResultTile> createState() => _ResultTileState();
}

class _ResultTileState extends State<_ResultTile> {
  bool _hovered = false;

  double get _ratio {
    final parts = widget.batch.aspectRatio.split(':');
    if (parts.length != 2) return 1;
    final width = double.tryParse(parts[0]) ?? 0;
    final height = double.tryParse(parts[1]) ?? 0;
    if (width <= 0 || height <= 0) return 1;
    return width / height;
  }

  bool get _isPicture => widget.batch.kind == CanvasKind.image;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    if (widget.batch.kind == CanvasKind.audio) return _AudioTile(item: item);

    return switch (item.status) {
      CanvasStatus.pending => SkeletonTile(aspectRatio: _ratio),
      CanvasStatus.failed => AspectRatio(
        aspectRatio: _ratio,
        child: _Failure(message: item.error, compact: true),
      ),
      CanvasStatus.done => _done(context),
    };
  }

  Widget _done(BuildContext context) {
    final mq = context.mq;
    final item = widget.item;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Pressable(
        onTap: _open,
        focusRadius: MqTheme.radius,
        builder: (context, states) => AspectRatio(
          aspectRatio: _ratio,
          child: AnimatedContainer(
            duration: states.duration,
            decoration: BoxDecoration(
              color: mq.surfaceSecondary,
              borderRadius: BorderRadius.circular(MqTheme.radius),
              border: Border.all(
                color: states.active ? mq.borderStrong : mq.border,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_isPicture)
                  LocalImage(item.path)
                else
                  _VideoPoster(
                    app: widget.app,
                    path: item.path,
                    seconds: item.seconds,
                  ),
                // The actions only exist under the pointer, and the tile itself
                // is the target for the obvious one, so a tile you are not on
                // is only ever the picture.
                Positioned(
                  right: 6,
                  top: 6,
                  child: IgnorePointer(
                    ignoring: !_hovered,
                    child: AnimatedOpacity(
                      opacity: _hovered ? 1 : 0,
                      duration: MqTheme.hoverDuration,
                      child: _TileActions(
                        path: item.path,
                        onDetail: widget.batch.kind == CanvasKind.ad
                            ? widget.onOpenRender
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A still opens in a lightbox, because looking closely at it is the point of
  /// having generated ten. Anything that moves or makes a noise goes to the
  /// system player, which can actually play it.
  void _open() {
    if (_isPicture) {
      showImageLightbox(context, widget.item.path);
    } else {
      PlatformUtil.openPath(widget.item.path);
    }
  }
}

/// Play, show in folder, and -- for a finished ad -- the way through to its
/// run detail.
class _TileActions extends StatelessWidget {
  const _TileActions({required this.path, this.onDetail});

  final String path;
  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: mq.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(MqTheme.radiusPill),
        border: Border.all(color: mq.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onDetail != null)
            MqIconButton(
              icon: 'layout-line',
              tip: tr('Shot by shot'),
              size: 24,
              onPressed: onDetail,
            ),
          MqIconButton(
            icon: 'external-link-line',
            tip: tr('Open in my player'),
            size: 24,
            onPressed: () => PlatformUtil.openPath(path),
          ),
          MqIconButton(
            icon: 'folder-line',
            tip: tr('Show file'),
            size: 24,
            onPressed: () => PlatformUtil.revealPath(path),
          ),
        ],
      ),
    );
  }
}

/// A clip's first readable frame, pulled with ffmpeg the first time the tile is
/// drawn and cached on disk from then on.
///
/// Without ffmpeg -- or before the frame comes back -- the tile is a plain
/// surface with a play badge, which is what it used to be always.
class _VideoPoster extends StatefulWidget {
  const _VideoPoster({
    required this.app,
    required this.path,
    required this.seconds,
  });

  final AppState app;
  final String path;
  final double seconds;

  @override
  State<_VideoPoster> createState() => _VideoPosterState();
}

class _VideoPosterState extends State<_VideoPoster> {
  /// Extraction is per file and its result never changes, so it is remembered
  /// for the life of the process: scrolling a long feed must not re-run ffmpeg
  /// on every tile that leaves and re-enters the viewport.
  static final Map<String, String> _cache = {};

  String _poster = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_VideoPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _load();
  }

  Future<void> _load() async {
    final cached = _cache[widget.path];
    if (cached != null) {
      setState(() => _poster = cached);
      return;
    }

    final found = await posterFrame(widget.app.ffmpegPath, widget.path);
    _cache[widget.path] = found;
    if (mounted) setState(() => _poster = found);
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_poster.isEmpty)
          ColoredBox(color: mq.surfaceTertiary)
        else
          LocalImage(_poster),
        Center(
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: mq.surface.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              border: Border.all(color: mq.border),
            ),
            child: MqIcon('play-fill', size: 18, color: mq.textPrimary),
          ),
        ),
        if (widget.seconds > 0)
          Positioned(
            left: 6,
            bottom: 6,
            child: _Stamp(text: '${widget.seconds.round()}s'),
          ),
      ],
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: mq.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        border: Border.all(color: mq.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: mq.textSecondary,
          fontSize: MqTheme.fontMicro,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A voice-over: nothing to look at, so it is a row rather than a tile.
class _AudioTile extends StatelessWidget {
  const _AudioTile({required this.item});

  final CanvasItem item;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    if (item.status == CanvasStatus.pending) {
      return const Skeleton(height: 56);
    }
    if (item.status == CanvasStatus.failed) {
      return _Failure(message: item.error);
    }

    return Pressable(
      onTap: () => PlatformUtil.openPath(item.path),
      focusRadius: MqTheme.radius,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: states.active ? mq.surfaceHover : mq.surfaceSecondary,
          borderRadius: BorderRadius.circular(MqTheme.radius),
          border: Border.all(
            color: states.active ? mq.borderStrong : mq.border,
          ),
        ),
        child: Row(
          children: [
            MqIcon('play-fill', size: 20, color: mq.textPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.path.split(Platform.pathSeparator).last,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mq.textSecondary,
                  fontSize: MqTheme.fontSmall,
                ),
              ),
            ),
            const SizedBox(width: 8),
            MqIcon('sound-module-line', size: 18, color: mq.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// What a request that came back empty leaves behind.
///
/// It stays in the feed rather than vanishing: a batch of ten where the third
/// failed should say so in the third tile's place, and the reason belongs next
/// to the gap it explains.
class _Failure extends StatelessWidget {
  const _Failure({required this.message, this.compact = false});

  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      alignment: compact ? Alignment.center : AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radius),
        border: Border.all(color: mq.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: compact
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          MqIcon('error-warning-line', size: 18, color: mq.textTertiary),
          const SizedBox(height: 8),
          Text(
            message.isEmpty ? tr('Nothing came back.') : message,
            maxLines: compact ? 3 : 4,
            overflow: TextOverflow.ellipsis,
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              color: mq.textSecondary,
              fontSize: MqTheme.fontSmall,
              height: MqTheme.lineTight,
            ),
          ),
        ],
      ),
    );
  }
}

/// One picture, as large as the window will allow.
Future<void> showImageLightbox(BuildContext context, String path) {
  return showMqModal<void>(
    context: context,
    child: Builder(
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width - 120,
          maxHeight: MediaQuery.sizeOf(context).height - 120,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(MqTheme.radiusLarge),
          child: LocalImage(path, fit: BoxFit.contain),
        ),
      ),
    ),
  );
}
