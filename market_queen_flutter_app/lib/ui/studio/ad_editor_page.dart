import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../app_state.dart';
import '../theme.dart';
import 'canvas_view.dart';
import 'composer.dart';

/// Where an ad is made.
///
/// Two things: a canvas that scrolls, and a bar you address it from. That is
/// the whole screen.
///
/// It replaced a page built the other way round -- a block in the middle asking
/// for the product name, its description, its audience, the actor and the scene
/// before anything could happen, with the writing squeezed underneath. All of
/// it is gone. Somebody who opens an ad studio is already advertising
/// something; being made to fill in a form saying so was a gate, not a step.
/// What is left asks for exactly one thing, in the user's own words, and shows
/// what came back in the space the form used to occupy.
class AdEditorPage extends StatefulWidget {
  const AdEditorPage({
    super.key,
    required this.app,
    required this.onGenerate,
    required this.onOpenRender,
  });

  final AppState app;

  /// Starts the pipeline. The composer decides when; the window owns the run.
  final VoidCallback onGenerate;

  /// The way through to a finished ad's shot list, from its tile in the canvas.
  final VoidCallback onOpenRender;

  /// What the canvas holds clear at the bottom before the composer has been
  /// measured -- roughly the bar with an empty prompt in it.
  ///
  /// Only ever the first frame's guess. It used to be the answer for every
  /// frame, and that was the bug: the bar is not one height. A reference row,
  /// a prompt grown to four lines, or the settings column stacked over it on a
  /// narrow window all make it taller, and the feed went on reserving 250px for
  /// a bar that had become 380 -- so the newest result, the one you had just
  /// waited for, ended up underneath it with no way to scroll it out.
  static const double composerReserve = 250;

  @override
  State<AdEditorPage> createState() => _AdEditorPageState();
}

class _AdEditorPageState extends State<AdEditorPage> {
  double _reserve = AdEditorPage.composerReserve;

  void _onComposerHeight(double height) {
    if (!mounted || (height - _reserve).abs() < 0.5) return;
    setState(() => _reserve = height);
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    // The composer floats over the canvas instead of sitting under it. Stacked
    // in a column, its settings panel added its own height to the row and the
    // feed above shrank by that much every time the gear was pressed -- the
    // canvas visibly jumping on a control that is supposed to affect only what
    // the next generation will look like. Anchored to the bottom of a stack, it
    // grows into empty background and the feed never moves; the feed only pads
    // itself by however tall it turned out to be.
    return Stack(
      children: [
        Positioned.fill(
          child: CanvasView(
            app: widget.app,
            onOpenRender: widget.onOpenRender,
            bottomInset: _reserve,
          ),
        ),
        // A short fade so a tile scrolling past does not slide out from behind
        // the bar with a hard edge.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: _reserve,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    mq.background.withValues(alpha: 0),
                    mq.background,
                  ],
                  stops: const [0, 0.35],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _MeasuredHeight(
            onChanged: _onComposerHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                MqTheme.pagePadding,
                0,
                MqTheme.pagePadding,
                MqTheme.gapLarge,
              ),
              child: Composer(
                app: widget.app,
                onGenerateAd: widget.onGenerate,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Reports how tall its child turned out to be, after every layout that
/// changes it.
///
/// A layout that has to know a sibling's height is usually a layout that should
/// be rearranged instead -- but not here: the composer deliberately floats over
/// the canvas rather than sitting beside it in a column, precisely so that
/// growing does not push the feed around. The one thing the feed still has to
/// know is how much of its bottom edge is covered.
class _MeasuredHeight extends SingleChildRenderObjectWidget {
  const _MeasuredHeight({
    required this.onChanged,
    required Widget super.child,
  });

  final ValueChanged<double> onChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasuredHeight(onChanged);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasuredHeight renderObject,
  ) {
    renderObject.onChanged = onChanged;
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
