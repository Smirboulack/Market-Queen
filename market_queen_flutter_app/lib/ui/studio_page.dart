import 'package:flutter/material.dart';

import '../app_state.dart';
import 'actor_rail.dart';
import 'render_view.dart';
import 'scenario_workspace.dart';

/// The studio: the script in the middle, everything the ad is made of on the
/// right.
///
/// There is no step rail any more and no recap panel. The three steps were only
/// ever a way to make one screen fit on three, and the recap only existed to
/// carry the context the steps kept hiding -- with the product and the actor
/// permanently on the rail, neither has anything left to do.
class StudioPage extends StatelessWidget {
  const StudioPage({
    super.key,
    required this.app,
    required this.rendering,
    required this.onBackToScript,
  });

  final AppState app;

  /// Whether the middle column is showing the run rather than the script. The
  /// window owns it, because Generate lives up in the bar.
  final bool rendering;
  final VoidCallback onBackToScript;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          // IndexedStack rather than a swap: the composer keeps its half-typed
          // line and the script keeps its scroll while a render is watched.
          child: IndexedStack(
            index: rendering ? 1 : 0,
            children: [
              ScenarioWorkspace(app: app),
              RenderView(app: app, onBack: onBackToScript),
            ],
          ),
        ),
        ActorRail(app: app),
      ],
    );
  }
}
