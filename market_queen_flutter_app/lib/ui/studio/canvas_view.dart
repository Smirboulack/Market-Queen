import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app_state.dart';
import '../../core/clipboard_media.dart';
import '../../core/platform_util.dart';
import '../../i18n/translator.dart';
import '../../models/asset_library.dart' show isAudioPath, isVideoPath;
import '../../models/canvas_feed.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/media_drop.dart';
import '../widgets/media_preview.dart';
import '../widgets/skeleton.dart';
import '../widgets/video_player.dart';
import '../widgets/video_poster.dart';

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

  /// Whether the newest tile is the one being looked at.
  ///
  /// Tracked continuously rather than read when it is needed, and that is the
  /// whole trick: by the time a resize has happened the old extent is gone, so
  /// "were we at the bottom" has to have been answered before it.
  bool _atBottom = true;

  /// The viewport the feed was last laid out in.
  Size _viewport = Size.zero;

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

  /// Something changed the shape of the feed: the composer grew a line, the
  /// settings column opened, the window was dragged bigger.
  ///
  /// All three move the bottom of the scrollable, and all three should leave
  /// somebody who was watching the newest tile still watching it. Anywhere else
  /// in the feed the offset is already preserved for us and is left alone --
  /// snapping the middle of a list to the end would be worse than the bug.
  void _keepAnchored() {
    if (!_atBottom) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.pixels >= position.maxScrollExtent) return;
      // Jumped, not animated: this follows a resize, and a resize that also
      // slides is two movements where the user made none.
      _scroll.jumpTo(position.maxScrollExtent);
    });
  }

  @override
  void didUpdateWidget(CanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bottomInset != widget.bottomInset) _keepAnchored();
  }

  /// The tallest a single result is allowed to be drawn.
  ///
  /// Two ceilings, and the smaller of the two wins. [_BatchBlock.maxTileEdge] is
  /// the one that usually applies: a result in a feed is a thumbnail you glance
  /// at and open, the way a picture in a chat is, not a page-width poster. The
  /// other is what is actually on screen -- the canvas less the composer
  /// standing in front of it -- which only bites on a short window, and keeps a
  /// result you have just waited for inside the space you are looking at.
  double _maxTileHeight(double viewportHeight) => math.min(
    _BatchBlock.maxTileEdge,
    math.max(240.0, (viewportHeight - widget.bottomInset) * 0.78),
  );

  /// Kept up to date by every scroll, so [_keepAnchored] never has to guess.
  ///
  /// The slack is a few pixels rather than zero: a feed resting at the end can
  /// sit a fraction of a pixel short of its own extent, and an equality test
  /// there would decide you had scrolled away.
  bool _onScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    _atBottom = metrics.pixels >= metrics.maxScrollExtent - 8;
    return false;
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
      // The window itself is a thing that resizes the feed, and it does it
      // without any of our own state changing -- so the viewport is watched
      // here rather than reacted to somewhere else.
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.biggest != _viewport) {
            _viewport = constraints.biggest;
            _keepAnchored();
          }

          return ListenableBuilder(
            listenable: _feed,
            builder: (context, _) {
              final batches = _feed.batches;
              if (batches.isEmpty) {
                return _EmptyCanvas(bottomInset: widget.bottomInset);
              }

              // Centred on the same axis as the prompt bar and capped to the
              // same width, so the two are one column rather than a feed that
              // spans the monitor with a bar floating in the middle of it. The
              // padding does the centring rather than a SizedBox inside the
              // list, which keeps the scrollbar on the window's own edge.
              final side = math.max(
                MqTheme.pagePadding,
                (constraints.maxWidth - MqTheme.contentMaxWidth) / 2,
              );

              return NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: ListView.separated(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(
                    side,
                    MqTheme.gapLarge,
                    side,
                    MqTheme.gapLarge + widget.bottomInset,
                  ),
                  itemCount: batches.length,
                  separatorBuilder: (context, _) =>
                      const SizedBox(height: MqTheme.gapLarge + 6),
                  itemBuilder: (context, index) => _BatchBlock(
                    app: widget.app,
                    batch: batches[index],
                    maxTileHeight: _maxTileHeight(constraints.maxHeight),
                    onOpenRender: widget.onOpenRender,
                    onRemove: () => _feed.remove(batches[index].id),
                  ),
                ),
              );
            },
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

/// One press of the send button, and the tiles it produced.
///
/// Only the tiles. There used to be a line above them repeating the prompt, the
/// model and the time -- and the prompt was still sitting in the bar you had
/// just typed it into, three inches below. A feed of pictures with a caption
/// over every one of them is a feed you read instead of look at. The only text
/// left is the text of something that went wrong, which is the one thing the
/// picture cannot say for itself.
class _BatchBlock extends StatelessWidget {
  const _BatchBlock({
    required this.app,
    required this.batch,
    required this.maxTileHeight,
    required this.onOpenRender,
    required this.onRemove,
  });

  final AppState app;
  final CanvasBatch batch;

  /// The ceiling on one tile, worked out by the feed from how much of the
  /// canvas is actually visible.
  final double maxTileHeight;

  final VoidCallback onOpenRender;

  /// Takes the whole batch off the canvas. Reached from the right-click menu of
  /// a failure, which has no tile of its own to remove.
  final VoidCallback onRemove;

  /// How wide a tile wants to be. Below this the grid drops a column rather
  /// than shrinking every tile past the point of being readable.
  static const double _idealTile = 210;

  /// The longest edge any single result is drawn at.
  ///
  /// A generation in the feed is the size of a picture in a chat thread, and
  /// for the same reason: the feed is a record of what you asked for, read by
  /// scrolling past it, and the way to look closely at one is to open it --
  /// which is one click on the tile. Without this a single 16:9 clip took the
  /// entire column and a 1:1 still was five hundred pixels square, so two
  /// results in a row were already a page of scrolling.
  static const double maxTileEdge = 320;

  /// Five abreast is as fine as the grid gets. Past it a still is a thumbnail,
  /// and the whole reason to ask for ten at once is to be able to tell them
  /// apart.
  static const int _maxColumns = 5;

  static const double _gap = 10;

  /// How many columns this batch is laid out in.
  ///
  /// Driven by how many results there are as much as by how much room there is:
  /// a batch is a grid whose cell is a share of it, so the more you asked for
  /// the smaller each one comes back -- ten stills read as a contact sheet
  /// rather than as ten pages to scroll past. Asking for two must not put two
  /// tiles in a five-column grid and leave three holes.
  static int columnsFor(int count, double width) {
    final room = (width / _idealTile).floor().clamp(1, _maxColumns);
    return count < room ? math.max(1, count) : room;
  }

  @override
  Widget build(BuildContext context) {
    if (batch.allFailed) {
      return _MediaMenu(
        onRemove: batch.running ? null : onRemove,
        child: _Failure(message: batch.firstError),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(batch.items.length, constraints.maxWidth);
        final share =
            (constraints.maxWidth - _gap * (columns - 1)) / columns;

        // A cell is its share of the grid, until that would draw it larger than
        // a result in a feed should be: capped on the height by the ceiling the
        // feed works out, and on the width by the same edge, so whatever the
        // shape the tile fits in one square and a wide clip is no bigger than a
        // tall one.
        //
        // A recording is the exception: it is a row with a play button in it
        // and has no shape to cap, so squeezing it to the width of a portrait
        // frame would leave a scrubber nobody can aim at.
        final width = batch.kind == CanvasKind.audio
            ? share
            : math.min(
                math.min(share, maxTileEdge),
                maxTileHeight * _ratioOf(batch),
              );

        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          // Centred, so a batch that does not fill its last row -- or a single
          // result narrowed by the ceiling above -- sits under the prompt that
          // asked for it rather than against the left margin.
          alignment: WrapAlignment.end,
          children: [
            for (final item in batch.items)
              SizedBox(
                width: width,
                child: _ResultTile(
                  app: app,
                  batch: batch,
                  item: item,
                  onOpenRender: onOpenRender,
                  onRemove: () =>
                      app.project.feed.removeItem(batch.id, item.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Width over height for whatever this batch was asked for, 1 when the ratio
/// is missing or unreadable.
double _ratioOf(CanvasBatch batch) {
  final parts = batch.aspectRatio.split(':');
  if (parts.length != 2) return 1;
  final width = double.tryParse(parts[0]) ?? 0;
  final height = double.tryParse(parts[1]) ?? 0;
  if (width <= 0 || height <= 0) return 1;
  return width / height;
}

/// The right-click menu on anything the canvas produced.
///
/// The file is on disk already -- every generation is written the moment it
/// lands -- so the four things anybody wants from a result are all file
/// operations, and none of them belongs on a hover strip that can only hold
/// three glyphs. A context menu is where a desktop keeps them.
class _MediaMenu extends StatelessWidget {
  const _MediaMenu({
    required this.child,
    this.path = '',
    this.onRemove,
  });

  final Widget child;

  /// Empty while the result is still pending or came back empty: the menu then
  /// offers only the removal.
  final String path;

  /// Null while requests are still out for this batch -- removing then would
  /// leave them writing into something nobody can see.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Secondary only: the primary tap belongs to whatever is underneath, and
      // both gestures can live on the same pixels without an arena between
      // them.
      onSecondaryTapDown: (details) => _open(context, details.globalPosition),
      child: child,
    );
  }

  Future<void> _open(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final hasFile = path.isNotEmpty && File(path).existsSync();
    final picked = await showMenu<_MediaAction>(
      context: context,
      // Shape, colour and elevation come from `popupMenuTheme`, like every
      // other menu in the app.
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      constraints: const BoxConstraints(minWidth: 240),
      items: [
        if (hasFile) ...[
          _entry(context, _MediaAction.reveal, 'folder-line', tr('Show file')),
          _entry(
            context,
            _MediaAction.saveAs,
            'download-line',
            tr('Save as...'),
          ),
          _entry(
            context,
            _MediaAction.copy,
            'file-copy-line',
            isVideoPath(path)
                ? tr('Copy the video')
                : isAudioPath(path)
                ? tr('Copy the recording')
                : tr('Copy the picture'),
          ),
        ],
        if (hasFile && onRemove != null) const PopupMenuDivider(height: 9),
        if (onRemove != null)
          _entry(
            context,
            _MediaAction.remove,
            'delete-bin-line',
            tr('Remove from the canvas'),
            destructive: true,
          ),
      ],
    );

    if (picked == null || !context.mounted) return;

    switch (picked) {
      case _MediaAction.reveal:
        await PlatformUtil.revealPath(path);
      case _MediaAction.saveAs:
        await _saveAs(path);
      case _MediaAction.copy:
        await ClipboardMedia.copyFile(path);
      case _MediaAction.remove:
        onRemove?.call();
    }
  }

  PopupMenuItem<_MediaAction> _entry(
    BuildContext context,
    _MediaAction value,
    String icon,
    String label, {
    bool destructive = false,
  }) {
    final mq = context.mq;
    final ink = destructive ? mq.errorText : mq.textPrimary;

    return PopupMenuItem<_MediaAction>(
      value: value,
      height: 38,
      child: Row(
        children: [
          MqIcon(icon, size: 16, color: ink),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(color: ink, fontSize: MqTheme.fontLabel),
          ),
        ],
      ),
    );
  }

  /// A copy, wherever they ask for it. The generated file itself stays where it
  /// was written -- "save as" on something already saved is an export, and
  /// moving the original would break the tile that points at it.
  Future<void> _saveAs(String path) async {
    final extension = p.extension(path).replaceFirst('.', '');
    final location = await getSaveLocation(
      suggestedName: p.basename(path),
      acceptedTypeGroups: [
        if (extension.isNotEmpty)
          XTypeGroup(label: extension.toUpperCase(), extensions: [extension]),
      ],
    );
    if (location == null) return;

    try {
      await File(path).copy(location.path);
    } on FileSystemException {
      // The dialog picked somewhere unwritable. Nothing was moved and nothing
      // was lost; the original is still where it was.
    }
  }
}

enum _MediaAction { reveal, saveAs, copy, remove }

/// One result, at whatever stage it is at.
class _ResultTile extends StatefulWidget {
  const _ResultTile({
    required this.app,
    required this.batch,
    required this.item,
    required this.onOpenRender,
    required this.onRemove,
  });

  final AppState app;
  final CanvasBatch batch;
  final CanvasItem item;
  final VoidCallback onOpenRender;
  final VoidCallback onRemove;

  @override
  State<_ResultTile> createState() => _ResultTileState();
}

class _ResultTileState extends State<_ResultTile> {
  bool _hovered = false;

  /// Whether the player has been stood up in place of the poster.
  ///
  /// One-way: once a clip has been played it keeps its player, so pausing and
  /// starting again does not reopen the file. It is the press of play that
  /// mounts it, never the tile appearing -- a feed of twenty clips must not
  /// stand up twenty decoders to show twenty thumbnails.
  bool _playing = false;

  double get _ratio => _ratioOf(widget.batch);

  bool get _isPicture => widget.batch.kind == CanvasKind.image;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return _MediaMenu(
      path: item.status == CanvasStatus.done ? item.path : '',
      // A tile still being generated is not one to pull out from under the
      // request that is about to fill it.
      onRemove: item.status == CanvasStatus.pending ? null : widget.onRemove,
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final item = widget.item;

    if (widget.batch.kind == CanvasKind.audio) return _AudioTile(item: item);

    return switch (item.status) {
      CanvasStatus.pending => SkeletonTile(
        aspectRatio: _ratio,
        glyph: _glyph,
        label: _pendingLabel,
      ),
      CanvasStatus.failed => AspectRatio(
        aspectRatio: _ratio,
        child: _Failure(message: item.error, compact: true),
      ),
      CanvasStatus.done => _done(context),
    };
  }

  /// What the tile is waiting for, drawn on the skeleton so a long wait reads
  /// as a wait rather than as a failure nobody reported.
  String get _glyph => switch (widget.batch.kind) {
    CanvasKind.video => 'clapperboard-line',
    CanvasKind.ad => 'user-voice-line',
    CanvasKind.audio => 'volume-up-line',
    CanvasKind.image => 'image-line',
  };

  String get _pendingLabel => switch (widget.batch.kind) {
    CanvasKind.video => tr('Filming...'),
    CanvasKind.ad => tr('Shooting the ad...'),
    CanvasKind.audio => tr('Recording...'),
    CanvasKind.image => tr('Drawing...'),
  };

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
                else if (_playing)
                  InlineVideo(path: item.path)
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
                        onFullscreen: _isPicture ? null : _openFullscreen,
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
  /// having generated ten.
  ///
  /// A clip plays where it is. It used to be handed to whatever the machine had
  /// registered for .mp4, which is the wrong answer twice: a second window
  /// lands on top of the studio, and the thing you were comparing it against is
  /// now behind it. The tile is the play button, the button in the corner is
  /// full screen, and both stay inside the app.
  void _open() {
    if (_isPicture) {
      showImageLightbox(context, widget.item.path);
      return;
    }
    // Once the player is up it owns its own taps -- pausing and resuming is its
    // job, not the tile's.
    if (!_playing) setState(() => _playing = true);
  }

  /// Full screen takes the clip off the tile rather than standing beside it.
  /// Two players on one file is two soundtracks.
  Future<void> _openFullscreen() async {
    if (_playing) setState(() => _playing = false);
    await showVideoLightbox(context, widget.item.path);
  }
}

/// Full screen, show in folder, the escape hatch to the system player, and --
/// for a finished ad -- the way through to its run detail.
class _TileActions extends StatelessWidget {
  const _TileActions({required this.path, this.onDetail, this.onFullscreen});

  final String path;
  final VoidCallback? onDetail;

  /// Clips only. Stills have the lightbox, which the tile itself opens.
  final VoidCallback? onFullscreen;

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
          if (onFullscreen != null)
            MqIconButton(
              icon: 'fullscreen-line',
              tip: tr('Play full screen'),
              size: 24,
              onPressed: onFullscreen,
            ),
          // Still here, but no longer what pressing play does: an explicit
          // "somewhere else", for the times you want the file in something
          // that can scrub it frame by frame.
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

/// A clip at rest: its own first frame, a play badge, and how long it runs.
///
/// The frame comes from the shared extractor, which draws nothing until ffmpeg
/// has produced one -- so the plate underneath is what shows in the meantime,
/// and forever on a machine with no ffmpeg.
class _VideoPoster extends StatelessWidget {
  const _VideoPoster({
    required this.app,
    required this.path,
    required this.seconds,
  });

  final AppState app;
  final String path;
  final double seconds;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: mq.surfaceTertiary),
        VideoPosterImage(ffmpegPath: app.ffmpegPath, path: path),
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
        if (seconds > 0)
          Positioned(
            left: 6,
            bottom: 6,
            child: _Stamp(text: '${seconds.round()}s'),
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

/// A voice-over: nothing to look at, so it is a row rather than a tile, and it
/// plays in the row.
class _AudioTile extends StatelessWidget {
  const _AudioTile({required this.item});

  final CanvasItem item;

  @override
  Widget build(BuildContext context) {
    if (item.status == CanvasStatus.pending) {
      return SkeletonBar(glyph: 'volume-up-line', label: tr('Recording...'));
    }
    if (item.status == CanvasStatus.failed) {
      return _Failure(message: item.error);
    }
    return InlineAudio(path: item.path);
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

