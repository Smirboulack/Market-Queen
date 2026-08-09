import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/pricing.dart';
import '../i18n/translator.dart';
import 'actor_panel.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets/buttons.dart';
import 'widgets/chip.dart';
import 'widgets/prompt_bar.dart';
import 'widgets/scene_bubble.dart';

/// Step 2 -- the scenario: who says it, and what they say.
///
/// One step, two halves, and no form in either. The words go into a prompt bar
/// and come out as numbered lines above it, one per send -- which is both what
/// a chat input does and exactly the shape the pipeline needs, since every
/// scene buys its own audio and its own clip.
///
/// The actor is a chip in that bar rather than a panel of its own: casting is
/// something you do *while* writing, and you recast the moment a line stops
/// sounding like the person you picked.
class StepScenario extends StatefulWidget {
  const StepScenario({super.key, required this.app});

  final AppState app;

  @override
  State<StepScenario> createState() => _StepScenarioState();
}

class _StepScenarioState extends State<StepScenario> {
  final TextEditingController _bar = TextEditingController();
  final ScrollController _thread = ScrollController();

  bool _drawerOpen = false;
  String _nextKind = 'talking';
  CostEstimate _directCost = CostEstimate.unknown;

  @override
  void initState() {
    super.initState();
    _refreshCost();
    widget.app.project.requestChanged.addListener(_refreshCost);
    widget.app.director.directed.listen(_onDirected);
  }

  @override
  void dispose() {
    widget.app.project.requestChanged.removeListener(_refreshCost);
    widget.app.director.directed.remove(_onDirected);
    _bar.dispose();
    _thread.dispose();
    super.dispose();
  }

  void _onDirected(List<Map<String, Object?>> shots) =>
      widget.app.project.applyDirection(shots);

  void _refreshCost() {
    final next = widget.app.director.estimate(widget.app.project.toRequest());
    if (!mounted) return;
    setState(() => _directCost = next);
  }

  String _hint(int written) {
    final beats = [
      tr('Name the frustration in one sentence. You have three seconds.'),
      tr('Make it concrete. What did you try that failed?'),
      tr('Introduce it as what finally worked, not as a product.'),
      tr('One specific detail. A number, a timeframe, a moment.'),
      tr('Say what to do next, casually.'),
    ];
    return written < beats.length
        ? beats[written]
        : tr('Keep going, or leave it here.');
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final project = widget.app.project;
    final scenes = project.scenes;

    final portrait = '${project.actor['portraitPath'] ?? ''}';
    final actorName = () {
      final name = '${project.actor['name'] ?? ''}';
      return name.isEmpty ? tr('Actor') : name;
    }();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              MqTheme.pagePadding,
              4,
              MqTheme.gapLarge,
              MqTheme.gapLarge,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Scenario'),
                  style: TextStyle(
                    color: mq.text,
                    fontSize: MqTheme.fontHeading,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr('Write what they say. One line, one scene.'),
                  style: TextStyle(color: mq.textDim, fontSize: MqTheme.fontBody),
                ),
                const SizedBox(height: MqTheme.gap),

                // The lines already written, newest at the bottom, like a
                // thread.
                Expanded(
                  child: ListenableBuilder(
                    listenable: scenes,
                    builder: (context, _) {
                      if (scenes.count == 0) {
                        return Center(
                          child: Text(
                            tr('Nothing written yet. The first line is the hook — '
                                'you have three seconds.'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: mq.textFaint,
                              fontSize: MqTheme.fontSmall,
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        controller: _thread,
                        itemCount: scenes.count,
                        separatorBuilder: (_, _) => const SizedBox(height: 2),
                        itemBuilder: (context, index) {
                          final scene = scenes.scenes[index];
                          return SceneBubble(
                            // Keyed on the scene's own id: editing one line
                            // must not rebuild the field being typed into.
                            key: ValueKey(scene.id),
                            position: index,
                            total: scenes.count,
                            line: scene.line,
                            kind: scene.kind,
                            imagePrompt: scene.imagePrompt,
                            seconds: scenes.seconds(index),
                            directed: scene.directed,
                            onLineEdited: (text) =>
                                scenes.setField(index, 'line', text),
                            onKindToggled: () => scenes.setField(
                              index,
                              'kind',
                              scene.kind == 'broll' ? 'talking' : 'broll',
                            ),
                            onMoveRequested: (to) => scenes.move(index, to),
                            onRemoveRequested: () => scenes.remove(index),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: MqTheme.gap),

                ListenableBuilder(
                  listenable: scenes,
                  builder: (context, _) => PromptBar(
                    controller: _bar,
                    placeholder: _hint(scenes.count),
                    onSubmitted: (text) {
                      scenes.add(text);
                      if (_nextKind == 'broll') {
                        scenes.setField(scenes.count - 1, 'kind', 'broll');
                        setState(() => _nextKind = 'talking');
                      }
                      _bar.clear();
                    },
                    chips: [
                      MqChip(
                        portrait: portrait,
                        icon: portrait.isEmpty ? 'user-add-line' : '',
                        label: tr('Pick an actor'),
                        value: portrait.isEmpty ? '' : actorName,
                        accent: portrait.isEmpty,
                        opensMenu: true,
                        onPressed: () => setState(() => _drawerOpen = true),
                      ),
                      MqChip(
                        label: tr('Talking'),
                        value: _nextKind == 'broll' ? tr('Product shot') : '',
                        icon: _nextKind == 'broll'
                            ? 'image-line'
                            : 'user-smile-line',
                        onPressed: () => setState(() =>
                            _nextKind = _nextKind == 'broll' ? 'talking' : 'broll'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: MqTheme.gap),

                // One elastic cell in the middle: it carries the error when
                // there is one, the advice when there is not, and shrinks to
                // nothing before anything else moves.
                ListenableBuilder(
                  listenable: widget.app.director,
                  builder: (context, _) {
                    final director = widget.app.director;
                    return Row(
                      children: [
                        Text(
                          //: %1 is a count of scenes, %2 a duration in seconds
                          tr('%1 scene(s) · %2 s')
                              .arg(scenes.count)
                              .arg(project.spokenSeconds.toStringAsFixed(1)),
                          style: TextStyle(
                            color: mq.textDim,
                            fontSize: MqTheme.fontSmall,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            director.error.isNotEmpty
                                ? director.error
                                : tr('15 to 30 s converts best'),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: director.error.isNotEmpty
                                  ? mq.danger
                                  : mq.textFaint,
                              fontSize: MqTheme.fontSmall,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        MqChip(
                          label: director.running
                              ? tr('Directing…')
                              : tr('Direct the shots'),
                          detail: !director.running && _directCost.known
                              ? Format.estimated(_directCost.amount)
                              : '',
                          icon: 'magic-line',
                          enabled: !director.running && scenes.count > 0,
                          onPressed: () => director.direct(project.toRequest()),
                        ),
                        const SizedBox(width: 8),
                        PrimaryButton(
                          text: tr('Next: review'),
                          enabled: project.stepStates[1].valid,
                          onPressed: () => project.currentStep = 2,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        // The casting drawer.
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          width: _drawerOpen ? 400 : 0,
          child: _drawerOpen
              ? ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 400,
                    maxWidth: 400,
                    child: ActorPanel(
                      app: widget.app,
                      onClose: () => setState(() => _drawerOpen = false),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
