import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/translator.dart';
import 'theme.dart';
import 'widgets/cards.dart';
import 'widgets/model_picker.dart';

/// Which model does what, by default, everywhere.
///
/// It used to be a folded section at the bottom of the studio rail, which meant
/// the one choice that changes both the look and the bill of every ad was the
/// hardest thing in the app to find. There is one place for it now, and the
/// studio simply uses whatever it says.
class ModelsPage extends StatelessWidget {
  const ModelsPage({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Providers come and go with the keys that unlock them.
      listenable: Listenable.merge([app.settings, app.registry]),
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(MqTheme.pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: tr('Models'),
              subtitle: tr(
                'The default for each kind of generation. Prices are per unit '
                'and come from the same catalogue the estimate uses.',
              ),
            ),
            const SizedBox(height: MqTheme.gapLarge),

            SectionCard(
              title: tr('Image'),
              subtitle: tr(
                'Actor and décor previews, and the still every shot starts '
                'from.',
              ),
              children: [
                ModelPicker(
                  app: app,
                  category: 'image',
                  label: tr('Pictures'),
                ),
              ],
            ),
            const SizedBox(height: MqTheme.gapLarge),

            SectionCard(
              title: tr('Video'),
              subtitle: tr(
                'Two of them: one lip-syncs a face to the voice-over, the '
                'other animates a still that has no face in it.',
              ),
              children: [
                ModelPicker(
                  app: app,
                  category: 'avatar',
                  label: tr('Talking shots'),
                ),
                ModelPicker(
                  app: app,
                  category: 'video',
                  label: tr('Product shots'),
                ),
              ],
            ),
            const SizedBox(height: MqTheme.gapLarge),

            SectionCard(
              title: tr('Audio'),
              subtitle: tr('The voice that reads your scenario.'),
              children: [
                ModelPicker(app: app, category: 'voice', label: tr('Voice')),
              ],
            ),
            const SizedBox(height: MqTheme.gapLarge),

            SectionCard(
              title: tr('Text'),
              subtitle: tr(
                'Only used by the three writing helpers under the scenario '
                'bar. Nothing writes your ad unless you ask it to.',
              ),
              children: [
                ModelPicker(app: app, category: 'text', label: tr('Writing')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
