import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/platform_util.dart';
import '../i18n/translator.dart';
import 'format.dart';
import 'storyboard.dart';
import 'theme.dart';
import 'widgets/buttons.dart';
import 'widgets/cards.dart';
import 'widgets/fields.dart';
import 'widgets/model_picker.dart';
import 'widgets/panels.dart';

/// Step 3 -- the last look before anything is paid for.
///
/// The right-hand recap already carries the content, so this panel is about the
/// render itself: the format, the subtitles, the price, and the progress once
/// it is running.
class StepSummary extends StatefulWidget {
  const StepSummary({super.key, required this.app});

  final AppState app;

  @override
  State<StepSummary> createState() => _StepSummaryState();
}

class _StepSummaryState extends State<StepSummary> {
  bool _advancedOpen = false;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final app = widget.app;
    final project = app.project;

    return ListenableBuilder(
      listenable: app.pipeline,
      builder: (context, _) {
        final pipeline = app.pipeline;
        final busy = pipeline.running;
        final done = pipeline.outputFile.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Ready to shoot'),
              style: TextStyle(
                color: mq.text,
                fontSize: MqTheme.fontHeading,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              //: %1 is a duration in seconds
              tr('About %1 s of video, lip-synced to your lines. '
                      'Nothing is charged until you press generate.')
                  .arg(project.spokenSeconds.toStringAsFixed(1)),
              style: TextStyle(color: mq.textDim, fontSize: MqTheme.fontBody),
            ),
            const SizedBox(height: MqTheme.gapLarge),

            SectionCard(
              title: tr('Output'),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Format'),
                          style: TextStyle(
                            color: mq.textDim,
                            fontSize: MqTheme.fontSmall,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        StyledCombo<String>(
                          width: 150,
                          options: const [
                            MenuEntry('9:16', '9:16'),
                            MenuEntry('1:1', '1:1'),
                            MenuEntry('16:9', '16:9'),
                          ],
                          value: project.aspectRatio,
                          onPicked: project.setAspectRatio,
                        ),
                      ],
                    ),
                    const Spacer(),
                  ],
                ),
                StyledCheck(
                  text: tr('Burn in subtitles (uses OpenAI Whisper)'),
                  checked: project.captions,
                  onChanged: project.setCaptions,
                ),
              ],
            ),
            const SizedBox(height: MqTheme.gapLarge),

            // The models are here, folded away: choosing them is not part of
            // making an ad, it is something you do once and forget.
            SectionCard(
              title: tr('Advanced'),
              subtitle: tr('Which models do the work. The defaults are sensible.'),
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: GhostButton(
                    text: _advancedOpen
                        ? tr('Hide models')
                        : tr('Choose models manually'),
                    onPressed: () =>
                        setState(() => _advancedOpen = !_advancedOpen),
                  ),
                ),
                if (_advancedOpen) ...[
                  ModelPicker(app: app, category: 'image', label: tr('Frames')),
                  ModelPicker(
                      app: app, category: 'avatar', label: tr('Talking shots')),
                  ModelPicker(
                      app: app, category: 'video', label: tr('Product shots')),
                  ModelPicker(app: app, category: 'voice', label: tr('Voice')),
                ],
              ],
            ),
            const SizedBox(height: MqTheme.gapLarge),

            Row(
              children: [
                GhostButton(
                  text: tr('Back'),
                  enabled: !busy,
                  onPressed: () => project.currentStep = 1,
                ),
                const Spacer(),
                if (busy) ...[
                  GhostButton(
                    text: tr('Cancel'),
                    destructive: true,
                    onPressed: pipeline.cancel,
                  ),
                  const SizedBox(width: 8),
                ],
                PrimaryButton(
                  text: busy ? tr('Generating...') : tr('Generate the ad'),
                  loading: busy,
                  enabled: project.complete && !busy,
                  onPressed: () => pipeline.start(project.toRequest()),
                ),
              ],
            ),
            const SizedBox(height: MqTheme.gapLarge),

            // Progress, steps and log only matter once something is running.
            if (busy || done || pipeline.progress > 0) ...[
              SectionCard(
                children: [
                  ProgressBar(value: pipeline.progress),
                  StepList(steps: pipeline.steps),
                  if (pipeline.status.isNotEmpty)
                    Text(
                      pipeline.status,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: mq.textDim, fontSize: MqTheme.fontSmall),
                    ),
                ],
              ),
              const SizedBox(height: MqTheme.gapLarge),
            ],

            // Result: the ad, and the one scene you might want to redo.
            if (done) ...[
              SectionCard(
                title: tr('Your ad is ready'),
                //: %1 is a price
                subtitle: pipeline.cost.lines.isNotEmpty
                    ? tr('Cost so far %1. Fixing one scene costs a fraction of '
                            'starting over.')
                        .arg(Format.estimated(pipeline.cost.total))
                    : tr('Fixing one scene costs a fraction of starting over.'),
                children: [
                  Storyboard(app: app),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      GhostButton(
                        text: tr('Open in my player'),
                        onPressed: () =>
                            PlatformUtil.openPath(pipeline.outputFile),
                      ),
                      GhostButton(
                        text: tr('Show file'),
                        onPressed: () =>
                            PlatformUtil.revealPath(pipeline.outputFile),
                      ),
                      GhostButton(
                        text: tr('Start a new ad'),
                        enabled: !busy,
                        onPressed: () {
                          project.clear();
                          project.currentStep = 0;
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: MqTheme.gapLarge),
            ],

            Row(
              children: [
                Text(
                  tr('Activity'),
                  style: TextStyle(
                    color: mq.textDim,
                    fontSize: MqTheme.fontSmall,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                GhostButton(text: tr('Clear'), onPressed: app.log.clear),
              ],
            ),
            const SizedBox(height: 8),
            LogPanel(log: app.log),
          ],
        );
      },
    );
  }
}
