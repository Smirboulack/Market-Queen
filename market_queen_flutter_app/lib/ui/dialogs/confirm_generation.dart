import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/pricing.dart';
import '../../i18n/translator.dart';
import '../../models/studio_runner.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/mq_dialog.dart';

/// The last thing between a video prompt and the bill.
///
/// It exists for one reason: video is where the money is, and the three
/// mistakes below are the ones that turn a paid generation into a wasted one --
/// they are not caught by any validation, and they are all invisible until the
/// clip comes back wrong. Three lines of prose and a price is cheaper than a
/// reshoot.
///
/// It can be turned off, and the switch is on the modal itself, because a
/// confirmation you cannot dismiss forever is a nag.
///
/// Returns true when the user went ahead.
Future<bool> confirmGeneration(
  BuildContext context, {
  required AppState app,
  required GenerationOrder order,
}) async {
  if (app.settings.pref<bool>('skipGenerationConfirm', false) == true) {
    return true;
  }

  final answer = await showMqModal<bool>(
    context: context,
    child: _ConfirmCard(app: app, order: order),
  );
  return answer ?? false;
}

class _ConfirmCard extends StatefulWidget {
  const _ConfirmCard({required this.app, required this.order});

  final AppState app;
  final GenerationOrder order;

  @override
  State<_ConfirmCard> createState() => _ConfirmCardState();
}

class _ConfirmCardState extends State<_ConfirmCard> {
  bool _skipNextTime = false;

  @override
  Widget build(BuildContext context) {
    final estimate = widget.app.runner.estimate(widget.order);

    return MqModalCard(
      title: tr('Confirm video generation'),
      width: 560,
      actions: [
        // The switch is applied on the way out rather than as it is flicked:
        // ticking it and then cancelling should not silence a dialog you did
        // not go through with.
        GhostButton(
          text: tr('Cancel'),
          onPressed: () => closeMqModal(context, false),
        ),
        PrimaryButton(
          text: tr('Generate video'),
          onPressed: () {
            if (_skipNextTime) {
              widget.app.settings.setPref('skipGenerationConfirm', true);
            }
            closeMqModal(context, true);
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Overline(text: tr('Suggestions')),
          const SizedBox(height: 8),
          _Suggestions(),
          const SizedBox(height: MqTheme.gapLarge),
          _Overline(text: tr('What this will cost')),
          const SizedBox(height: 8),
          _CostLine(app: widget.app, order: widget.order, estimate: estimate),
          const SizedBox(height: MqTheme.gap + 2),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: StyledCheck(
              text: tr("Don't show this again"),
              checked: _skipNextTime,
              onChanged: (value) => setState(() => _skipNextTime = value),
            ),
          ),
        ],
      ),
    );
  }
}

class _Overline extends StatelessWidget {
  const _Overline({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: context.mq.textTertiary,
        fontSize: MqTheme.fontMicro,
        fontWeight: FontWeight.w600,
        letterSpacing: MqTheme.trackOverline,
      ),
    );
  }
}

/// The three things worth checking, each in one line of its own.
class _Suggestions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    final advice = <({String title, String detail})>[
      (
        title: tr('Avoid violent, racist or adult content'),
        detail: tr(
          'Providers refuse it and charge for the attempt all the same.',
        ),
      ),
      (
        title: tr('Check your spelling'),
        detail: tr('A typo in the prompt comes back as a typo on screen.'),
      ),
      (
        title: tr('Punctuate properly'),
        detail: tr(
          'A missing full stop changes the pacing; a stray question mark '
          'changes the tone.',
        ),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radius),
        border: Border.all(color: mq.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < advice.length; ++i) ...[
            if (i > 0) Container(height: 1, color: mq.divider),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: MqIcon(
                      'check-line',
                      size: 15,
                      color: mq.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          advice[i].title,
                          style: TextStyle(
                            color: mq.textPrimary,
                            fontSize: MqTheme.fontLabel,
                            fontWeight: FontWeight.w600,
                            height: MqTheme.lineTight,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          advice[i].detail,
                          style: TextStyle(
                            color: mq.textTertiary,
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
          ],
        ],
      ),
    );
  }
}

/// What is about to be bought, and for how much.
///
/// The figure is the app's own estimate against the price catalogue, not a
/// credit balance: there is nothing to meter here, the keys are the user's own
/// and the bill arrives from the provider.
class _CostLine extends StatelessWidget {
  const _CostLine({
    required this.app,
    required this.order,
    required this.estimate,
  });

  final AppState app;
  final GenerationOrder order;
  final CostEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    final facts = <String>[
      //: %1 is a number of clips
      tr('%1 clip(s)').arg(order.count),
      //: %1 is a duration in seconds
      tr('%1 s each').arg(order.seconds),
      order.aspectRatio,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radius),
        border: Border.all(color: mq.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.runner.modelLabel('video', order.seconds),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mq.textPrimary,
                    fontSize: MqTheme.fontLabel,
                    fontWeight: FontWeight.w600,
                    height: MqTheme.lineTight,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  facts.join(' · '),
                  style: TextStyle(
                    color: mq.textTertiary,
                    fontSize: MqTheme.fontSmall,
                    height: MqTheme.lineTight,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: MqTheme.gap),
          Text(
            // No price in the catalogue is said plainly rather than guessed at:
            // an invented figure on a spending confirmation is worse than none.
            estimate.known
                ? Format.estimated(estimate.amount)
                : tr('price unknown'),
            style: TextStyle(
              color: estimate.known ? mq.textPrimary : mq.textTertiary,
              fontSize: MqTheme.fontTitle,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
