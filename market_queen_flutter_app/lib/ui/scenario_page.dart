import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/translator.dart';
import 'icons.dart';
import 'theme.dart';

/// Storyboards: planning an ad shot by shot before any of it is bought.
///
/// Deliberately empty for now. The nav entry is here first because where a
/// thing lives is the decision that is expensive to change later -- it sits
/// directly under Create UGC because that is the order the work happens in --
/// and an announced empty room is a better placeholder than a row that appears
/// one day in a menu people have already learned.
class ScenarioPage extends StatelessWidget {
  const ScenarioPage({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Padding(
      padding: const EdgeInsets.all(MqTheme.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Storyboard'),
            style: TextStyle(
              color: mq.textPrimary,
              fontSize: MqTheme.fontHeading,
              fontWeight: FontWeight.w600,
              letterSpacing: MqTheme.trackHeading,
              height: MqTheme.lineTight,
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MqIcon('layout-line', size: 28, color: mq.textTertiary),
                    const SizedBox(height: MqTheme.gapLarge),
                    Text(
                      tr('Plan an ad shot by shot before you shoot it. Being '
                          'built.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: mq.textTertiary,
                        fontSize: MqTheme.fontBody,
                        height: MqTheme.lineBody,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
