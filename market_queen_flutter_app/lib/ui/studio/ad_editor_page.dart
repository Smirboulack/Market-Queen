import 'package:flutter/material.dart';

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
  /// a prompt grown to four lines, or the reference well on the clip shelf all
  /// make it taller, and the feed went on reserving 250px for a bar that had
  /// become 380 -- so the newest result, the one you had just waited for, ended
  /// up underneath it with no way to scroll it out.
  static const double composerReserve = 250;

  @override
  State<AdEditorPage> createState() => _AdEditorPageState();
}

class _AdEditorPageState extends State<AdEditorPage> {
  double _reserve = AdEditorPage.composerReserve;

  /// The prompt block's height, plus the margin it stands on.
  ///
  /// Only the prompt block: the settings column and the cast panels grow
  /// upward over the canvas and are deliberately not counted, because a control
  /// that changes what the *next* generation looks like must not shift the ones
  /// already on screen.
  void _onBarHeight(double height) {
    final reserve = height + MqTheme.gapLarge;
    if (!mounted || (reserve - _reserve).abs() < 0.5) return;
    setState(() => _reserve = reserve);
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
              onBarHeight: _onBarHeight,
            ),
          ),
        ),
      ],
    );
  }
}
