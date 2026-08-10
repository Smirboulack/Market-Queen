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
/// for the product name, its description, its audience, the actor and the décor
/// before anything could happen, with the writing squeezed underneath. All of
/// it is gone. Somebody who opens an ad studio is already advertising
/// something; being made to fill in a form saying so was a gate, not a step.
/// What is left asks for exactly one thing, in the user's own words, and shows
/// what came back in the space the form used to occupy.
class AdEditorPage extends StatelessWidget {
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

  /// How much of the bottom of the canvas the composer stands in front of.
  ///
  /// Roughly the height of the bar with an empty prompt: enough that the last
  /// tile in the feed can be scrolled clear of it. It is a fixed number on
  /// purpose -- a measured one would change every time the settings column
  /// opened, which is exactly the shuffling this layout exists to stop.
  static const double composerReserve = 250;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    // The composer floats over the canvas instead of sitting under it. Stacked
    // in a column, its settings panel added its own height to the row and the
    // feed above shrank by that much every time the gear was pressed -- the
    // canvas visibly jumping on a control that is supposed to affect only what
    // the next generation will look like. Anchored to the bottom of a stack, it
    // grows into empty background and the feed never moves.
    return Stack(
      children: [
        Positioned.fill(
          child: CanvasView(
            app: app,
            onOpenRender: onOpenRender,
            bottomInset: composerReserve,
          ),
        ),
        // A short fade so a tile scrolling past does not slide out from behind
        // the bar with a hard edge.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: composerReserve,
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
            child: Composer(app: app, onGenerateAd: onGenerate),
          ),
        ),
      ],
    );
  }
}
