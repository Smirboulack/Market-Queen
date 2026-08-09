import 'package:flutter/material.dart';

import '../i18n/translator.dart';
import 'theme.dart';

/// The shape most UGC ads that convert happen to have.
///
/// It used to be the interface: five tabs, one line each, and an ad that came
/// out sounding like five ads stapled together. It is advice now and nothing
/// else -- a page you open from the lightbulb, ignore, and close. A person
/// filming themselves does not stop between the hook and the problem, and a
/// script written in five boxes reads like one that did.
class AdviceBeat {
  const AdviceBeat(this.label, this.advice);

  final String label;
  final String advice;

  static List<AdviceBeat> get all => [
    AdviceBeat(
      tr('The hook'),
      tr('The first three seconds. Name the frustration, not the product.'),
    ),
    AdviceBeat(
      tr('The problem'),
      tr('Make it concrete. One thing that failed, not a category of things.'),
    ),
    AdviceBeat(
      tr('The solution'),
      tr('Bring it in as what finally worked, not as a product launch.'),
    ),
    AdviceBeat(
      tr('The benefit'),
      tr('One detail beats three adjectives. "Two weeks", not "fast".'),
    ),
    AdviceBeat(
      tr('The sign-off'),
      tr('Casual and singular. One action, said the way a friend would.'),
    ),
  ];
}

/// Hangs the advice off whatever asked for it.
///
/// A popover rather than a modal: it is something to glance at with one hand
/// still on the keyboard, and blurring the page to read five sentences would
/// be the app taking its own tips more seriously than the user does.
Future<void> showScenarioAdvice(BuildContext anchor) async {
  final mq = anchor.mq;
  final box = anchor.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return;

  const width = 360.0;
  final origin = box.localToGlobal(
    Offset(0, box.size.height + 6),
    ancestor: overlay,
  );

  // Hung off the button's right edge, because the button is itself at the
  // right edge of the bar and there is no room the other way.
  final left = (origin.dx + box.size.width - width).clamp(
    MqTheme.gap,
    overlay.size.width - width - MqTheme.gap,
  );

  await showMenu<void>(
    context: anchor,
    constraints: const BoxConstraints(minWidth: width, maxWidth: width),
    position: RelativeRect.fromLTRB(
      left,
      origin.dy,
      overlay.size.width - left - width,
      0,
    ),
    items: [
      PopupMenuItem<void>(
        enabled: false,
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('A shape that tends to work'),
                style: TextStyle(
                  color: mq.textPrimary,
                  fontSize: MqTheme.fontLabel,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr(
                  'Not a form to fill in. Write it as one continuous take, the '
                  'way you would actually say it.',
                ),
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontSmall,
                  height: MqTheme.lineTight,
                ),
              ),
              const SizedBox(height: 12),
              for (final beat in AdviceBeat.all) ...[
                Text(
                  beat.label,
                  style: TextStyle(
                    color: mq.textPrimary,
                    fontSize: MqTheme.fontSmall,
                    fontWeight: FontWeight.w600,
                    height: MqTheme.lineTight,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  beat.advice,
                  style: TextStyle(
                    color: mq.textSecondary,
                    fontSize: MqTheme.fontSmall,
                    height: MqTheme.lineTight,
                  ),
                ),
                const SizedBox(height: 9),
              ],
              Text(
                tr('15 to 30 s converts best.'),
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
