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

  /// The composer stops widening here. Past it the send button ends up at the
  /// far edge of a 27" monitor while the caret is in the middle of the screen,
  /// and a prompt bar you have to travel to is a prompt bar you stop using.
  static const double _composerWidth = 1180;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: CanvasView(app: app, onOpenRender: onOpenRender),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MqTheme.pagePadding,
            0,
            MqTheme.pagePadding,
            MqTheme.gapLarge,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _composerWidth),
              child: Composer(app: app, onGenerateAd: onGenerate),
            ),
          ),
        ),
      ],
    );
  }
}
