import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/translator.dart';
import '../brand.dart';
import '../icons.dart';
import '../theme.dart';

/// The shape of a thing that is on its way.
///
/// This is what replaced the full-page progress screen. A generation used to
/// take you somewhere else to watch a bar fill; now the tiles it will occupy
/// appear in the canvas the instant you press send, at the right size and in
/// the right place, and each one fills itself in as its request lands. Nothing
/// on the page moves when a result arrives, because its space was already
/// reserved -- which is the entire argument for a skeleton over a spinner.
///
/// One controller drives every skeleton on screen through an inherited ticker,
/// so a grid of ten shimmers as one surface rather than ten objects that
/// happened to start at slightly different times.
class SkeletonScope extends StatefulWidget {
  const SkeletonScope({super.key, required this.child});

  final Widget child;

  static Animation<double>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_SkeletonTicker>()
      ?.animation;

  @override
  State<SkeletonScope> createState() => _SkeletonScopeState();
}

class _SkeletonScopeState extends State<SkeletonScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _SkeletonTicker(animation: _controller, child: widget.child);
}

class _SkeletonTicker extends InheritedWidget {
  const _SkeletonTicker({required this.animation, required super.child});

  final Animation<double> animation;

  @override
  bool updateShouldNotify(_SkeletonTicker oldWidget) =>
      oldWidget.animation != animation;
}

/// A rounded rectangle with a highlight travelling across it.
///
/// Sizes itself to its parent unless told otherwise, so the same widget is a
/// tile in a grid, a line of text, or a whole card.
class Skeleton extends StatelessWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height,
    this.radius = MqTheme.radius,
  });

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final animation = SkeletonScope.maybeOf(context);

    final base = mq.surfaceSecondary;
    final crest = mq.dark ? mq.surfaceActive : mq.surfaceTertiary;

    // No scope above us: still draw the shape, just without the shimmer. A
    // skeleton that only exists inside one particular subtree would be a trap
    // for whoever reuses it.
    if (animation == null) {
      return _Plate(width: width, height: height, radius: radius, fill: base);
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // -1 → 2 rather than 0 → 1: the band has to start fully off one edge
        // and finish fully off the other, or the shimmer pops.
        final travel = -1.0 + animation.value * 3.0;

        return _Plate(
          width: width,
          height: height,
          radius: radius,
          fill: base,
          gradient: LinearGradient(
            colors: [base, crest, base],
            stops: const [0.0, 0.5, 1.0],
            begin: Alignment(travel - 1, -0.4),
            end: Alignment(travel + 1, 0.4),
          ),
        );
      },
    );
  }
}

class _Plate extends StatelessWidget {
  const _Plate({
    required this.radius,
    required this.fill,
    this.width,
    this.height,
    this.gradient,
  });

  final double? width;
  final double? height;
  final double radius;
  final Color fill;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: gradient == null ? fill : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A skeleton shaped like a result tile: the aspect ratio the batch was asked
/// for, and -- in the middle of it -- what is being made and the fact that it
/// is still being made.
///
/// The shimmer alone was not enough. A video takes minutes, and a rectangle
/// quietly breathing for two of them is indistinguishable from a rectangle that
/// is stuck: people pressed send again, or gave up and reloaded. So the tile
/// now says both things a wait has to say -- what is coming, by the glyph of
/// its kind, and that something is still happening, by a mark that turns.
class SkeletonTile extends StatelessWidget {
  const SkeletonTile({
    super.key,
    this.aspectRatio = 1,
    this.radius = 10,
    this.glyph = '',
    this.label = '',
    this.mark = '',
    this.since,
    this.maxSeconds = 0,
  });

  final double aspectRatio;
  final double radius;

  /// The kind being generated: a picture, a clip, a read.
  final String glyph;

  /// Shown under the glyph when the tile is big enough to hold a sentence
  /// without it turning into an ellipsis.
  final String label;

  /// The credential id of the account this is being bought from, so the tile
  /// says *who* is drawing it as well as what. A ten-minute wait on a clip and
  /// a ten-second one on a still look identical while both are grey
  /// rectangles.
  final String mark;

  /// When the request left, and how long the app will wait. Together they draw
  /// the clock along the bottom edge.
  final DateTime? since;
  final int maxSeconds;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio <= 0 ? 1 : aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Skeleton(radius: radius),
          if (glyph.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                // A tile squeezed into a ten-across contact sheet has room for
                // the glyph and nothing else. The clock goes first and the
                // sentence second, because on a small tile the turning mark
                // already says "working" and only the clock says "for how
                // much longer".
                final roomy =
                    constraints.maxWidth >= 150 && constraints.maxHeight >= 130;
                final clock = since != null && constraints.maxWidth >= 110;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: PendingMark(
                        glyph: glyph,
                        mark: mark,
                        label: roomy ? label : '',
                      ),
                    ),
                    if (clock)
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: Center(
                          child: PendingClock(
                            since: since!,
                            maxSeconds: maxSeconds,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

/// How long this has been running, against how long it is allowed to.
///
/// The one thing a skeleton could not say. A clip takes minutes, and a
/// rectangle breathing for three of them is indistinguishable from one that
/// has died -- people press send again, and pay twice. A number that goes up
/// every second is proof of life, and the ceiling beside it turns "is this
/// broken?" into "there are four minutes left in this".
///
/// Past the ceiling it keeps counting rather than freezing or hiding: the
/// request is genuinely still out at that point -- the timeout is enforced on
/// the socket, not by this -- and a clock that stops while the tile spins on
/// would be the same lie in a new place.
class PendingClock extends StatefulWidget {
  const PendingClock({super.key, required this.since, this.maxSeconds = 0});

  final DateTime since;
  final int maxSeconds;

  /// "0:07", "2:14", "1:03:20" -- minutes and seconds, hours only if it ever
  /// comes to that.
  static String clock(int totalSeconds) {
    final seconds = totalSeconds < 0 ? 0 : totalSeconds;
    final minutes = seconds ~/ 60;
    String two(int value) => value.toString().padLeft(2, '0');

    if (minutes < 60) return '$minutes:${two(seconds % 60)}';
    return '${minutes ~/ 60}:${two(minutes % 60)}:${two(seconds % 60)}';
  }

  @override
  State<PendingClock> createState() => _PendingClockState();
}

class _PendingClockState extends State<PendingClock> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // One second, and only while a tile is actually pending: the widget is
    // built by the pending branch alone, so a finished batch takes its timers
    // with it.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final elapsed = DateTime.now().difference(widget.since).inSeconds;

    final text = widget.maxSeconds > 0
        //: %1 is elapsed time like "0:42", %2 the limit like "8:00"
        ? tr('%1 · max %2')
              .arg(PendingClock.clock(elapsed))
              .arg(PendingClock.clock(widget.maxSeconds))
        : PendingClock.clock(elapsed);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: mq.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: mq.textTertiary,
          fontSize: MqTheme.fontMicro,
          height: 1.2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// What sits in the middle of anything that is on its way: the glyph of the
/// kind, a turning mark, and -- when there is room -- a word.
///
/// The mark is driven by the shared skeleton ticker rather than a controller of
/// its own, so ten tiles turn in step with each other and with their own
/// shimmer instead of drifting apart.
class PendingMark extends StatelessWidget {
  const PendingMark({
    super.key,
    required this.glyph,
    this.label = '',
    this.mark = '',
    this.horizontal = false,
  });

  final String glyph;
  final String label;

  /// The account being bought from, drawn beside the kind glyph. Two facts,
  /// and they answer different questions: the glyph says a clip is coming, the
  /// logo says it is coming from Veo -- which is what tells you whether to
  /// expect ten seconds or three minutes, and whose bill it lands on.
  final String mark;

  /// Laid out in a row rather than a column, for the wide short things: a
  /// voice-over's bar.
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final animation = SkeletonScope.maybeOf(context);

    /// The kind, and -- where there is one -- who is making it. The logo is
    /// drawn small and beside rather than over: it is context, not the
    /// subject.
    Widget kind(double glyphSize, double markSize) {
      final icon = MqIcon(glyph, size: glyphSize, color: mq.textTertiary);
      if (mark.isEmpty) return icon;

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          SizedBox(width: glyphSize * 0.4),
          Opacity(
            // Held back to the weight of the glyph it stands next to, so a
            // full-colour logo does not become the loudest thing in a feed of
            // grey rectangles.
            opacity: 0.7,
            child: ProviderMark(credential: mark, size: markSize),
          ),
        ],
      );
    }

    final spinner = SizedBox(
      width: 14,
      height: 14,
      child: animation == null
          ? MqIcon('loader-4-line', size: 14, color: mq.textTertiary)
          : RotationTransition(
              turns: animation,
              child: MqIcon('loader-4-line', size: 14, color: mq.textTertiary),
            ),
    );

    final text = label.isEmpty
        ? null
        : Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontSmall,
              height: MqTheme.lineTight,
            ),
          );

    if (horizontal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          kind(18, 16),
          const SizedBox(width: 10),
          spinner,
          if (text != null) ...[const SizedBox(width: 8), Flexible(child: text)],
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        kind(22, 20),
        const SizedBox(height: 10),
        if (text == null)
          spinner
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [spinner, const SizedBox(width: 8), Flexible(child: text)],
          ),
      ],
    );
  }
}

/// The wide, short skeleton: a voice-over on its way, which has no picture to
/// reserve room for but the same need to say it is working.
class SkeletonBar extends StatelessWidget {
  const SkeletonBar({
    super.key,
    this.height = 56,
    this.glyph = '',
    this.label = '',
    this.mark = '',
    this.since,
    this.maxSeconds = 0,
  });

  final double height;
  final String glyph;
  final String label;
  final String mark;
  final DateTime? since;
  final int maxSeconds;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Skeleton(height: height),
          if (glyph.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: PendingMark(
                        glyph: glyph,
                        label: label,
                        mark: mark,
                        horizontal: true,
                      ),
                    ),
                  ),
                  // The bar is wide and short, so the clock sits at the far
                  // end of the same line rather than under anything.
                  if (since != null)
                    PendingClock(since: since!, maxSeconds: maxSeconds),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
