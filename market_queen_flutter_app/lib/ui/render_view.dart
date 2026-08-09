import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/platform_util.dart';
import '../i18n/translator.dart';
import 'format.dart';
import 'storyboard.dart';
import 'theme.dart';
import 'widgets/buttons.dart';
import 'widgets/cards.dart';
import 'widgets/panels.dart';

/// What Generate opens onto: the run, and what it produced.
///
/// It replaces the wizard's third step, minus the settings -- the format, the
/// subtitles and the models all live on the rail now, so there is nothing left
/// to check here. By the time you are looking at this, money is being spent.
class RenderView extends StatelessWidget {
  const RenderView({
    super.key,
    required this.app,
    required this.onBack,
    this.onNewAd,
  });

  final AppState app;

  /// Back to the scenario. Available while a run is going: watching it is
  /// optional, and the next ad can be written while this one renders.
  final VoidCallback onBack;

  /// Starts a fresh ad in the same project. The most likely next move once one
  /// has landed, and the reason the ad you just shot is not overwritten to do
  /// it.
  final VoidCallback? onNewAd;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return ListenableBuilder(
      listenable: app.pipeline,
      builder: (context, _) {
        final pipeline = app.pipeline;
        final busy = pipeline.running;
        final done = pipeline.outputFile.isNotEmpty;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            MqTheme.pagePadding,
            MqTheme.gapLarge,
            MqTheme.pagePadding,
            MqTheme.gapLarge * 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PageHeader(
                      title: busy
                          ? tr('Shooting your ad')
                          : done
                          ? tr('Your ad is ready')
                          : tr('Nothing rendered yet'),
                      subtitle: busy
                          ? tr(
                              'Every step buys something from a provider. You can '
                              'go back to the script while it runs.',
                            )
                          : done && pipeline.cost.lines.isNotEmpty
                          //: %1 is a price
                          ? tr(
                              'Cost so far %1. Fixing one scene costs a fraction '
                              'of starting over.',
                            ).arg(Format.estimated(pipeline.cost.total))
                          : tr('Press Generate above to shoot this one.'),
                    ),
                  ),
                  const SizedBox(width: MqTheme.gap),
                  GhostButton(
                    text: tr('← Back to the script'),
                    onPressed: onBack,
                  ),
                ],
              ),
              const SizedBox(height: MqTheme.gapLarge),

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
                          color: mq.textSecondary,
                          fontSize: MqTheme.fontSmall,
                        ),
                      ),
                    if (busy)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: GhostButton(
                          text: tr('Cancel'),
                          destructive: true,
                          onPressed: pipeline.cancel,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: MqTheme.gapLarge),
              ],

              // The ad, and the one scene you might want to redo.
              if (done) ...[
                SectionCard(
                  title: tr('The cut'),
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
                        if (onNewAd != null)
                          GhostButton(
                            text: tr('Start a new ad'),
                            enabled: !busy,
                            onPressed: onNewAd,
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
                      color: mq.textSecondary,
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
          ),
        );
      },
    );
  }
}
