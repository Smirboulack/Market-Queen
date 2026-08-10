import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../theme.dart';
import '../widgets/mq_dialog.dart';
import 'studio_card.dart';

/// One project's ads.
///
/// The same list as the one above it, a level down. An ad is a whole spot: one
/// product, one actor, one décor, one scenario -- so trying a second angle is
/// a second card here rather than a second scene inside the first.
class AdsPage extends StatelessWidget {
  const AdsPage({
    super.key,
    required this.app,
    required this.projectId,
    required this.onOpen,
  });

  final AppState app;
  final String projectId;
  final ValueChanged<String> onOpen;

  Future<void> _create(BuildContext context) async {
    final name = await askForName(
      context,
      title: tr('New UGC ad'),
      subtitle: tr('One spot: one person, one take, one thing to say.'),
      label: tr('Ad name'),
      placeholder: tr('e.g. Morning routine hook'),
      confirmLabel: tr('Create'),
      initial: app.workspace.suggestedAdName(projectId),
    );
    if (name == null) return;

    final ad = app.workspace.createAd(projectId, name);
    onOpen(ad.id);
  }

  Future<void> _rename(BuildContext context, String id, String current) async {
    final name = await askForName(
      context,
      title: tr('Rename the ad'),
      label: tr('Ad name'),
      placeholder: current,
      confirmLabel: tr('Rename'),
      initial: current,
    );
    if (name != null) app.workspace.renameAd(projectId, id, name);
  }

  Future<void> _delete(BuildContext context, String id, String name) async {
    final confirmed = await askToConfirm(
      context,
      //: %1 is the name of an ad
      title: tr('Delete "%1"?').arg(name),
      message: tr(
        'The scenario and its settings go with it. Videos already generated '
        'stay in your projects folder.',
      ),
      confirmLabel: tr('Delete the ad'),
    );
    if (confirmed) app.workspace.removeAd(projectId, id);
  }

  /// The first line of the scenario, which is what an ad is actually known by.
  String _summary(Map<String, Object?> document) {
    final product = document['product'];
    final name = product is Map ? '${product['name'] ?? ''}'.trim() : '';
    if (name.isNotEmpty) return name;

    final script = '${document['script'] ?? ''}'.trim();
    if (script.isEmpty) return tr('Empty');
    return script.split(RegExp(r'[.!?\n]')).first.trim();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.workspace,
      builder: (context, _) {
        final ads = app.workspace.adsByRecency(projectId);

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
              StudioNewButton(
                label: tr('+ Create a UGC ad'),
                onPressed: () => _create(context),
              ),
              const SizedBox(height: MqTheme.gapLarge),
              if (ads.isEmpty)
                StudioEmptyNote(
                  text: tr(
                    'No ad in this project yet. One ad is one spot: one '
                    'person, one take, one thing to say.',
                  ),
                ),
              Wrap(
                spacing: MqTheme.gap,
                runSpacing: MqTheme.gap,
                children: [
                  for (final ad in ads)
                    StudioCard(
                      icon: 'clapperboard-line',
                      name: ad.name,
                      updatedAt: ad.updatedAt,
                      detail: _summary(ad.document),
                      onOpen: () => onOpen(ad.id),
                      onRename: () => _rename(context, ad.id, ad.name),
                      onDuplicate: () =>
                          app.workspace.duplicateAd(projectId, ad.id),
                      onDelete: () => _delete(context, ad.id, ad.name),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
