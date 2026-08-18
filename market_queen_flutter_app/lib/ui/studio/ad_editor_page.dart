import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../../models/canvas_feed.dart';
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
  });

  final AppState app;

  /// Starts the pipeline. The composer decides when; the window owns the run.
  final VoidCallback onGenerate;

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

  /// The feed tile the running pipeline will fill.
  ///
  /// Held here rather than in the composer because the composer is no longer
  /// the only thing that can start a run: the refresh button on a finished ad
  /// asks for the same thing, and two places writing a pending tile is two
  /// places to keep the settling logic in step. `finished` also fires for a
  /// single-shot reshoot, so only the batch this page opened is settled by it.
  CanvasBatch? _adBatch;

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    app.pipeline.finished.listen(_onAdFinished);
  }

  @override
  void dispose() {
    app.pipeline.finished.remove(_onAdFinished);
    super.dispose();
  }

  /// Puts a pending ad in the feed and starts the pipeline behind it.
  ///
  /// One entry point for both ways in: the send button on the talking-actor
  /// tab, and "another take" on an ad already in the feed. Refused while one is
  /// already shooting -- the pipeline is single-file, and a second pending tile
  /// nothing is filling is worse than a button that does not respond.
  void _shootAd() {
    // The same two guards the send button applies, because the refresh button
    // on a finished ad reaches this without passing it: a run started with no
    // actor or no script is a pending tile that exists only to fail, and a
    // second run started over the first is a tile nothing will ever fill --
    // the pipeline settles one at a time.
    if (app.pipeline.running || !app.project.complete) return;

    final batch = CanvasBatch(
      id: CanvasFeed.newId(),
      kind: CanvasKind.ad,
      prompt: app.project.script.trim(),
      createdAt: DateTime.now(),
      modelLabel: app.runner.modelLabel('avatar'),
      modelId: app.runner.modelFor('avatar'),
      credential: app.registry.credentialFor(app.runner.providerFor('avatar')),
      aspectRatio: app.project.aspectRatio,
      seconds: app.project.maxSeconds,
      items: [CanvasItem(id: CanvasFeed.newId())],
    );
    app.project.feed.add(batch);
    _adBatch = batch;

    widget.onGenerate();
  }

  void _onAdFinished(({bool success, String outputFile}) result) {
    final batch = _adBatch;
    if (batch == null) return;
    _adBatch = null;

    app.project.feed.settle(
      batch.id,
      batch.items.first.id,
      status: result.success ? CanvasStatus.done : CanvasStatus.failed,
      path: result.outputFile,
      error: result.success ? '' : tr('The render did not finish. See the log.'),
      // What the run actually charged, which is a sum of a script pass, a
      // reading and a clip per shot rather than one model's line in the
      // catalogue -- so the tile can say what it cost like every other one.
      cost: app.pipeline.cost.total > 0 ? app.pipeline.cost.total : null,
    );
  }

  /// Another take of whatever is in [batch].
  ///
  /// Two different calls behind one gesture: a still or a clip is one request
  /// the runner repeats verbatim, while an ad is a whole pipeline run and the
  /// window owns those. The tile that asks does not have to know which.
  void _regenerate(CanvasBatch batch) {
    if (batch.kind == CanvasKind.ad) {
      _shootAd();
      return;
    }
    app.runner.regenerate(batch);
  }

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
            onRegenerate: _regenerate,
            bottomInset: _reserve,
          ),
        ),
        // A short fade so a tile scrolling past does not slide out from behind
        // the bar with a hard edge.
        //
        // Stopping short of the right edge is not a detail: the feed's
        // scrollbar lives in that strip, and a wash painted over it hid the
        // thumb at exactly the offset it rests at -- the bottom -- so the one
        // way to drag the feed was invisible whenever you were at the end of
        // it. Nothing but background is under the strip, so the seam does not
        // show.
        Positioned(
          left: 0,
          right: MqTheme.scrollbarLane,
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
              onGenerateAd: _shootAd,
              onBarHeight: _onBarHeight,
            ),
          ),
        ),
      ],
    );
  }
}
