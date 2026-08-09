import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/translator.dart';
import '../models/ad_project.dart';
import '../pipeline/pipeline.dart';
import 'icons.dart';
import 'recap_panel.dart';
import 'step_product.dart';
import 'step_scenario.dart';
import 'step_summary.dart';
import 'theme.dart';
import 'widgets/buttons.dart';
import 'widgets/cards.dart';

/// The studio: steps on the left, the step being edited in the middle, a live
/// recap on the right.
///
/// The centre fills the window rather than scrolling as a whole, because the
/// scenario step owns its own scroll region: the written lines scroll, the
/// prompt bar stays put at the bottom, and the actor drawer needs the full
/// height. The steps that are just content bring their own scroll view.
class StudioPage extends StatelessWidget {
  const StudioPage({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.project,
      builder: (context, _) {
        final project = app.project;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepRail(
              currentStep: project.currentStep,
              stepStates: project.stepStates,
              canStartOver: project.furthestStep > 0,
              onStepPicked: (index) => project.currentStep = index,
              onStartOver: project.clear,
              pipeline: app.pipeline,
            ),
            Expanded(
              child: IndexedStack(
                index: project.currentStep,
                children: [
                  _Scrolled(child: StepProduct(app: app)),
                  StepScenario(app: app),
                  _Scrolled(child: StepSummary(app: app)),
                ],
              ),
            ),
            RecapPanel(app: app),
          ],
        );
      },
    );
  }
}

class _Scrolled extends StatelessWidget {
  const _Scrolled({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        MqTheme.pagePadding,
        4,
        MqTheme.gapLarge,
        MqTheme.gapLarge,
      ),
      child: child,
    );
  }
}

/// The three steps, in order, with their state.
///
/// A step is reachable once every step before it is satisfied, which makes the
/// first pass linear and every pass after it free. Unreachable steps stay
/// visible but inert: seeing what comes next is the point of a rail.
class StepRail extends StatelessWidget {
  const StepRail({
    super.key,
    required this.currentStep,
    required this.stepStates,
    required this.canStartOver,
    required this.onStepPicked,
    required this.onStartOver,
    required this.pipeline,
  });

  final int currentStep;
  final List<StepStatus> stepStates;
  final bool canStartOver;
  final ValueChanged<int> onStepPicked;
  final VoidCallback onStartOver;
  final Pipeline pipeline;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    final labels = [
      (
        title: tr('Product'),
        hint: tr('What you are selling'),
        icon: 'shopping-bag-3-line',
      ),
      (
        title: tr('Scenario'),
        hint: tr('Who speaks, and what'),
        icon: 'draft-line',
      ),
      (
        title: tr('Summary'),
        hint: tr('Check and generate'),
        icon: 'check-double-line',
      ),
    ];

    return Container(
      // Wide enough for the hints to be sentences. At 200 the type scale
      // clipped every one of them ("What you are sell...", "Check and
      // gener..."), which is worse than not having them.
      width: 224,
      decoration: BoxDecoration(
        color: mq.surface,
        border: Border(right: BorderSide(color: mq.border)),
      ),
      padding: const EdgeInsets.all(MqTheme.gap + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Overline(tr('YOUR AD')),
          const SizedBox(height: 10),
          for (var i = 0; i < labels.length; ++i)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: _RailRow(
                title: labels[i].title,
                hint: labels[i].hint,
                icon: labels[i].icon,
                current: currentStep == i,
                state: i < stepStates.length
                    ? stepStates[i]
                    : const StepStatus(false, false),
                onTap: () => onStepPicked(i),
              ),
            ),
          const Spacer(),
          ListenableBuilder(
            listenable: pipeline,
            builder: (context, _) {
              if (!canStartOver || pipeline.running) {
                return const SizedBox.shrink();
              }
              return SizedBox(
                width: double.infinity,
                child: GhostButton(
                  text: tr('Start over'),
                  destructive: true,
                  onPressed: onStartOver,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.title,
    required this.hint,
    required this.icon,
    required this.current,
    required this.state,
    required this.onTap,
  });

  final String title;
  final String hint;
  final String icon;
  final bool current;
  final StepStatus state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final reachable = state.reachable;

    return Pressable(
      enabled: reachable,
      onTap: onTap,
      // Grouped rows snap both ways, like the side nav.
      snap: true,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: current
              ? mq.surfaceActive
              : states.pressed
              ? mq.surfaceActive
              : states.hovered
              ? mq.surfaceHover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        ),
        child: Row(
          children: [
            // Number, or a tick once the step holds together. A finished step
            // is the one thing on this rail worth spending pink on.
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: state.valid
                    ? mq.primary
                    : current
                    ? mq.primarySubtle
                    : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: state.valid
                      ? mq.primary
                      : current
                      ? mq.primaryMuted
                      : reachable
                      ? mq.borderStrong
                      : mq.border,
                ),
              ),
              child: MqIcon(
                state.valid ? 'check-line' : icon,
                size: 14,
                color: state.valid
                    ? mq.onPrimary
                    : current
                    ? mq.primaryText
                    : reachable
                    ? mq.textTertiary
                    : mq.textDisabled,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      // Unreachable steps stay legible instead of being faded
                      // out wholesale: seeing what comes next is the point of
                      // a rail, and 40% opacity is not seeing it.
                      color: !reachable
                          ? mq.textDisabled
                          : current || states.active
                          ? mq.textPrimary
                          : mq.textSecondary,
                      fontSize: MqTheme.fontBody,
                      fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                      height: MqTheme.lineTight,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: reachable ? mq.textTertiary : mq.textDisabled,
                      fontSize: MqTheme.fontSmall,
                      height: MqTheme.lineTight,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
