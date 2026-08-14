import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// A panel that hangs above the control that opened it.
///
/// It exists because the composer's settings used to be a *column*, welded to
/// the side of the prompt bar. That cost the bar three hundred pixels of width
/// whenever it was open, and on a window too narrow to afford them the panel
/// jumped above the prompt instead -- so pressing the cog moved the caret, and
/// the bar was two different widths depending on what was showing and how wide
/// the window happened to be. A control that changes what the *next* generation
/// looks like should not resize the thing you are typing in.
///
/// Drawn in the overlay, it costs the page nothing: the bar keeps its full
/// width open or shut, and the panel grows upward over the canvas from the
/// button's own corner, which is where the eye already is.
///
/// Put this in an [OverlayPortal.overlayChildLayoutBuilder] whose `child` is the
/// button it belongs to, and hand it the [OverlayChildLayoutInfo] that builder
/// is given.
///
/// It used to hang off a [CompositedTransformFollower] instead, and that had to
/// go: a follower layer only establishes its paint transform when the frame is
/// composited, so anything inside one that needs to know where it is on screen
/// during layout cannot be told. A [Tooltip] is exactly that -- it is an
/// overlay child of its own -- so hovering any button inside one of these
/// panels threw "the paint transform cannot be reliably computed because of
/// RenderFollowerLayer(s)" and took the frame down with it. The panel is
/// positioned from the button's own paint transform now, which is settled by
/// the time this builds.
class PopoverLayer extends StatelessWidget {
  const PopoverLayer({
    super.key,
    required this.info,
    required this.width,
    required this.onDismiss,
    required this.child,
  });

  /// Where the button is, how big it is, and how big the overlay is -- handed
  /// over by the portal, in the overlay's own coordinates.
  final OverlayChildLayoutInfo info;

  final double width;

  /// Anywhere outside the panel closes it, the way a menu does.
  final VoidCallback onDismiss;

  final Widget child;

  /// Between the top of the button and the bottom of the panel.
  static const double gap = 8;

  /// Kept clear above the panel, so it can never run off the top of a short
  /// window. The panels cap their own height as well; this is the floor under
  /// that, for the window nobody sized for.
  static const double _headroom = 8;

  /// The button's rectangle, in overlay coordinates.
  Rect get _anchor {
    final origin = MatrixUtils.transformPoint(
      info.childPaintTransform,
      Offset.zero,
    );
    return origin & info.childSize;
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final overlay = info.overlaySize;
    final anchor = _anchor;

    // The panel's bottom-right corner sits just above the button's top-right
    // one: it opens upward, away from the bar, and stays anchored to the same
    // edge whatever it holds. Clamped so a button near the left edge cannot
    // push it off the page.
    final right = (overlay.width - anchor.right)
        .clamp(0.0, math.max(0.0, overlay.width - width))
        .toDouble();
    final bottom = math.max(0.0, overlay.height - anchor.top + gap);

    return Stack(
      children: [
        // Invisible but opaque, which is the pair of properties a menu barrier
        // needs: nothing is darkened -- the canvas underneath stays readable,
        // which is the whole reason to be setting something while looking at
        // it -- and the press that dismisses does only that. Translucent, the
        // same press would also reach the cog underneath and reopen the panel
        // it had just shut.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          right: right,
          bottom: bottom,
          width: width,
          child: DecoratedBox(
            // The panel paints its own surface and its own outline; this is
            // only the shadow under it. It has one now because it floats over
            // the feed rather than sitting in the row -- a hairline border
            // alone leaves it looking printed on the tiles behind it.
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(MqTheme.radiusLarge),
              boxShadow: [
                BoxShadow(
                  color: mq.dark
                      ? const Color(0x99000000)
                      : const Color(0x1F000000),
                  blurRadius: 26,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(200, anchor.top - gap - _headroom),
              ),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}
