import 'package:flutter/material.dart';

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
/// for, and a faint glyph in the middle so an empty grid still says what is
/// coming.
class SkeletonTile extends StatelessWidget {
  const SkeletonTile({super.key, this.aspectRatio = 1, this.radius = 10});

  final double aspectRatio;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio <= 0 ? 1 : aspectRatio,
      child: Skeleton(radius: radius),
    );
  }
}
