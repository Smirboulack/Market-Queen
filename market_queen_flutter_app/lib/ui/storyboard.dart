import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app_state.dart';
import '../core/pricing.dart';
import '../i18n/translator.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets/buttons.dart';
import 'widgets/image_drop_grid.dart';

/// The finished ad, and the one scene you want to redo.
///
/// This is the payoff of keeping every shot as its own file: a bad scene costs
/// a few cents to re-shoot, against a dollar to relaunch the whole ad. Nothing
/// else in the app changes the economics of iterating this much.
class Storyboard extends StatefulWidget {
  const Storyboard({super.key, required this.app});

  final AppState app;

  @override
  State<Storyboard> createState() => _StoryboardState();
}

class _StoryboardState extends State<Storyboard> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  int _selected = 0;
  String _loaded = '';
  CostEstimate _redoCost = CostEstimate.unknown;

  @override
  void initState() {
    super.initState();
    _refreshCost();
    widget.app.pipeline.addListener(_onPipeline);
  }

  @override
  void dispose() {
    widget.app.pipeline.removeListener(_onPipeline);
    _player.dispose();
    super.dispose();
  }

  void _onPipeline() {
    if (!mounted) return;
    _refreshCost();
    _syncSource();
  }

  void _refreshCost() {
    setState(() => _redoCost = widget.app.pipeline.regenerateEstimate(_selected));
  }

  void _syncSource() {
    final file = widget.app.pipeline.outputFile;
    if (file.isEmpty || file == _loaded) return;
    _loaded = file;
    _player.open(Media(Uri.file(file).toString()), play: false);
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final pipeline = widget.app.pipeline;
    final shots = pipeline.shots;

    _syncSource();

    final current = (_selected >= 0 && _selected < shots.length)
        ? shots[_selected]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ------------------------------------------------------------ player
        Container(
          height: 320,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(MqTheme.radius),
            border: Border.all(color: mq.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Video(
            controller: _controller,
            controls: AdaptiveVideoControls,
            fill: Colors.black,
          ),
        ),
        const SizedBox(height: MqTheme.gap),

        // ------------------------------------------------------------- strip
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < shots.length; ++i)
              _Cell(
                path: shots[i].framePath,
                index: i,
                duration: shots[i].duration,
                current: _selected == i,
                onTap: () {
                  setState(() => _selected = i);
                  _refreshCost();
                  // Jump the player to where this scene starts.
                  _player.seek(Duration(
                      milliseconds: (shots[i].start * 1000).round()));
                },
              ),
          ],
        ),
        const SizedBox(height: MqTheme.gap),

        // ----------------------------------------------------------- details
        if (current != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(MqTheme.gap),
            decoration: BoxDecoration(
              color: mq.surfaceAlt,
              borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
              border: Border.all(color: mq.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  //: %1 is a shot number
                  tr('Scene %1').arg(_selected + 1),
                  style: TextStyle(
                    color: mq.textDim,
                    fontSize: MqTheme.fontSmall,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '« ${current.line} »',
                  style:
                      TextStyle(color: mq.text, fontSize: MqTheme.fontBody),
                ),
                if (current.imagePrompt.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    current.imagePrompt,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: mq.textFaint, fontSize: MqTheme.fontSmall),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    GhostButton(
                      text: pipeline.running
                          ? tr('Re-shooting...')
                          : _redoCost.known
                              //: %1 is a price
                              ? tr('Re-shoot this scene — %1')
                                  .arg(Format.estimated(_redoCost.amount))
                              : tr('Re-shoot this scene'),
                      enabled: !pipeline.running,
                      onPressed: () => pipeline.regenerateShot(_selected),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        tr('The voice-over is kept, so it is not paid for again.'),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            color: mq.textFaint, fontSize: MqTheme.fontSmall),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Cell extends StatefulWidget {
  const _Cell({
    required this.path,
    required this.index,
    required this.duration,
    required this.current,
    required this.onTap,
  });

  final String path;
  final int index;
  final double duration;
  final bool current;
  final VoidCallback onTap;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 72,
          height: 96,
          decoration: BoxDecoration(
            color: mq.surfaceAlt,
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
            border: Border.all(
              color: widget.current
                  ? mq.accent
                  : _hovered
                      ? mq.borderStrong
                      : mq.border,
              width: widget.current ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              LocalImage(widget.path),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 16,
                  alignment: Alignment.center,
                  color: mq.background.withValues(alpha: 0.85),
                  child: Text(
                    //: %1 is a shot number, %2 a duration in seconds
                    tr('%1 · %2s')
                        .arg(widget.index + 1)
                        .arg(widget.duration.toStringAsFixed(1)),
                    style: TextStyle(
                        color: mq.textDim, fontSize: MqTheme.fontSmall),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
