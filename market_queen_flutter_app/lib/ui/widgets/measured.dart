import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Reports how tall its child turned out to be, after every layout that changes
/// it.
///
/// A layout that has to know another widget's height is usually a layout that
/// should be rearranged instead -- but not here: the composer deliberately
/// floats over the canvas rather than sitting beside it in a column, precisely
/// so that growing does not push the feed around. The one thing the feed still
/// has to know is how much of its bottom edge is covered.
///
/// What is wrapped matters as much as the number. Wrapping the whole composer
/// meant the settings column counted, and opening it moved the feed by four
/// hundred pixels -- exactly the shuffling the floating layout exists to
/// prevent. Only the prompt block belongs inside this; the panels are supposed
/// to grow over the canvas and cost the feed nothing.
class MeasuredHeight extends SingleChildRenderObjectWidget {
  const MeasuredHeight({
    super.key,
    required this.onChanged,
    required Widget super.child,
  });

  final ValueChanged<double> onChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasuredHeight(onChanged);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMeasuredHeight).onChanged = onChanged;
  }
}

class _RenderMeasuredHeight extends RenderProxyBox {
  _RenderMeasuredHeight(this.onChanged);

  ValueChanged<double> onChanged;

  double _reported = -1;

  @override
  void performLayout() {
    super.performLayout();
    if (size.height == _reported) return;
    _reported = size.height;

    // After the frame, never during it: the callback rebuilds the page this
    // render object is inside, and marking a widget dirty in the middle of its
    // own layout is the one thing the framework will not have.
    final height = size.height;
    SchedulerBinding.instance.addPostFrameCallback((_) => onChanged(height));
  }
}
