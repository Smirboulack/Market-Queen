import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/translator.dart';
import '../models/asset_library.dart';
import 'dialogs/asset_editor.dart';
import 'dialogs/asset_picker.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets/buttons.dart';
import 'widgets/cards.dart';

/// The Actors page and the Décors page: the same page twice.
///
/// A cast is worth keeping. Landing a face that reads as real takes several
/// tries, and a room that looks lived-in takes a few more -- once either works
/// it should never have to be found again, in this ad or the next twenty.
class AssetLibraryPage extends StatelessWidget {
  const AssetLibraryPage({super.key, required this.app, required this.kind});

  final AppState app;
  final AssetKind kind;

  bool get _isActor => kind == AssetKind.actor;

  AssetLibrary get _library => _isActor ? app.actors : app.decors;

  Future<void> _create(BuildContext context) =>
      showAssetEditor(context, app: app, kind: kind);

  Future<void> _edit(BuildContext context, LibraryAsset asset) =>
      showAssetEditor(context, app: app, kind: kind, asset: asset);

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return ListenableBuilder(
      listenable: _library,
      builder: (context, _) {
        final assets = _library.assets;

        return Padding(
          padding: const EdgeInsets.all(MqTheme.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PageHeader(
                      title: _isActor ? tr('Actors') : tr('Décors'),
                      subtitle: _isActor
                          ? tr('The people your ads are filmed with. Cast one '
                              'into any ad from the studio.')
                          : tr('The places your ads are filmed in. Light and '
                              'mood are optional dials, not requirements.'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GhostButton(
                    text: _isActor ? tr('+ New actor') : tr('+ New décor'),
                    onPressed: () => _create(context),
                  ),
                ],
              ),
              const SizedBox(height: MqTheme.gapLarge),
              Expanded(
                child: assets.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MqIcon(
                              _isActor ? 'user-line' : 'image-line',
                              size: 30,
                              color: mq.textTertiary,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _isActor
                                  ? tr('No actor yet')
                                  : tr('No décor yet'),
                              style: TextStyle(
                                color: mq.textSecondary,
                                fontSize: MqTheme.fontBody,
                              ),
                            ),
                            const SizedBox(height: MqTheme.gap),
                            PrimaryButton(
                              text: _isActor
                                  ? tr('Create an actor')
                                  : tr('Create a décor'),
                              icon: 'add-line',
                              onPressed: () => _create(context),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 172,
                              mainAxisExtent: 214,
                              crossAxisSpacing: MqTheme.gap,
                              mainAxisSpacing: MqTheme.gap,
                            ),
                        itemCount: assets.length,
                        itemBuilder: (context, index) => AssetCard(
                          asset: assets[index],
                          // The card is the edit affordance here: there is
                          // nothing else to do with an actor on its own page.
                          onTap: () => _edit(context, assets[index]),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
