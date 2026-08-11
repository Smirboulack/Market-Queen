import 'package:flutter/material.dart';

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
  });

  final double aspectRatio;
  final double radius;

  /// The kind being generated: a picture, a clip, a read.
  final String glyph;

  /// Shown under the glyph when the tile is big enough to hold a sentence
  /// without it turning into an ellipsis.
  final String label;

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
              builder: (context, constraints) => Center(
                child: PendingMark(
                  glyph: glyph,
                  label:
                      constraints.maxWidth >= 150 && constraints.maxHeight >= 130
                      ? label
                      : '',
                ),
              ),
            ),
        ],
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
    this.horizontal = false,
  });

  final String glyph;
  final String label;

  /// Laid out in a row rather than a column, for the wide short things: a
  /// voice-over's bar.
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final animation = SkeletonScope.maybeOf(context);

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
          MqIcon(glyph, size: 18, color: mq.textTertiary),
          const SizedBox(width: 10),
          spinner,
          if (text != null) ...[const SizedBox(width: 8), Flexible(child: text)],
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MqIcon(glyph, size: 22, color: mq.textTertiary),
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
  });

  final double height;
  final String glyph;
  final String label;

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
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: PendingMark(
                  glyph: glyph,
                  label: label,
                  horizontal: true,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
