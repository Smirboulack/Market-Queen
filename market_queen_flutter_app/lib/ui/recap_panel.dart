import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/translator.dart';
import 'theme.dart';
import 'widgets/cards.dart';
import 'widgets/image_drop_grid.dart';
import 'widgets/panels.dart';

/// What the ad is made of, always visible, always current.
///
/// This is what replaces "fill the form and hope": every step leaves something
/// here, so the context of the previous steps never leaves the screen, and each
/// block doubles as a way back to the step that produced it.
class RecapPanel extends StatelessWidget {
  const RecapPanel({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final project = app.project;
    final states = project.stepStates;

    VoidCallback? jump(int step) =>
        states[step].reachable ? () => project.currentStep = step : null;

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: mq.surface,
        border: Border(left: BorderSide(color: mq.border)),
      ),
      padding: const EdgeInsets.all(MqTheme.gapLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Overline(tr('YOUR AD')),
          const SizedBox(height: MqTheme.gap),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _productBlock(context, jump(0)),
                  const SizedBox(height: MqTheme.gap),
                  _actorBlock(context, jump(1)),
                  const SizedBox(height: MqTheme.gap),
                  _scriptBlock(context, jump(1)),
                ],
              ),
            ),
          ),
          const SizedBox(height: MqTheme.gap),
          Container(height: 1, color: mq.divider),
          const SizedBox(height: MqTheme.gap),
          ListenableBuilder(
            listenable: app.pipeline,
            builder: (context, _) {
              if (!project.complete) {
                return Text(
                  tr(
                    'The estimate appears once the three steps are filled in.',
                  ),
                  style: TextStyle(
                    color: mq.textTertiary,
                    fontSize: MqTheme.fontSmall,
                  ),
                );
              }
              if (app.pipeline.running || app.pipeline.outputFile.isNotEmpty) {
                return const SizedBox.shrink();
              }
              return EstimateCard(app: app, request: project.toRequest());
            },
          ),
        ],
      ),
    );
  }

  Widget _productBlock(BuildContext context, VoidCallback? onTap) {
    final mq = context.mq;
    final project = app.project;
    final images = project.imagesFor('product');
    final audience = '${project.product['audience'] ?? ''}';

    return RecapBlock(
      title: tr('Product'),
      stepIndexTap: onTap,
      filled: project.stepStates[0].valid,
      placeholder: tr('Not set yet'),
      children: [
        Text(
          '${project.product['name'] ?? ''}',
          style: TextStyle(
            color: mq.textPrimary,
            fontSize: MqTheme.fontBody,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (audience.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            audience,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: mq.textSecondary,
              fontSize: MqTheme.fontSmall,
            ),
          ),
        ],
        // Reference images, as thumbnails: the point of collecting several is
        // being able to see them all at a glance.
        if (images.isNotEmpty) ...[
          const SizedBox(height: 5),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (var i = 0; i < images.length; ++i)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: mq.surfaceSecondary,
                    borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
                    // The primary reference is outlined here too, so the two
                    // views never disagree about which picture the models get.
                    border: Border.all(
                      color: i == 0 ? mq.primary : mq.border,
                      width: i == 0 ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: LocalImage(images[i]),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _actorBlock(BuildContext context, VoidCallback? onTap) {
    final mq = context.mq;
    final project = app.project;
    final portrait = '${project.actor['portraitPath'] ?? ''}';
    final name = '${project.actor['name'] ?? ''}';
    final brief = '${project.actor['brief'] ?? ''}';
    final decor = '${project.actor['decor'] ?? ''}';

    return RecapBlock(
      title: tr('Actor'),
      stepIndexTap: onTap,
      filled: portrait.isNotEmpty,
      placeholder: tr('No one cast yet'),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 64,
              decoration: BoxDecoration(
                color: mq.surfaceSecondary,
                borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
                border: Border.all(color: mq.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: LocalImage(portrait),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? tr('Not saved') : name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mq.textPrimary,
                      fontSize: MqTheme.fontSmall,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    brief,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mq.textSecondary,
                      fontSize: MqTheme.fontSmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (decor.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            decor,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontSmall,
            ),
          ),
        ],
      ],
    );
  }

  Widget _scriptBlock(BuildContext context, VoidCallback? onTap) {
    final mq = context.mq;
    final project = app.project;

    return RecapBlock(
      title: tr('Script'),
      stepIndexTap: onTap,
      filled: project.scenes.count > 0,
      placeholder: tr('Nothing written yet'),
      children: [
        Text(
          //: %1 is a duration in seconds, e.g. "13.5 s"
          tr('%1 s spoken').arg(project.spokenSeconds.toStringAsFixed(1)),
          style: TextStyle(
            color: mq.textPrimary,
            fontSize: MqTheme.fontBody,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          project.spokenScript(),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: mq.textSecondary,
            fontSize: MqTheme.fontSmall,
          ),
        ),
      ],
    );
  }
}
