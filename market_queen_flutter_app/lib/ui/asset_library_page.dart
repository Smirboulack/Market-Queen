import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/translator.dart';
import '../models/asset_library.dart';
import 'dialogs/asset_editor.dart';
import 'dialogs/asset_gallery.dart';
import 'theme.dart';
import 'widgets/cards.dart';
import 'widgets/mq_dialog.dart';

/// The Actors page and the Scenes page: the same page twice.
///
/// A cast is worth keeping. Landing a face that reads as real takes several
/// tries, and a room that looks lived-in takes a few more -- once either works
/// it should never have to be found again, in this ad or the next twenty.
class AssetLibraryPage extends StatelessWidget {
  const AssetLibraryPage({super.key, required this.app, required this.kind});

  final AppState app;
  final AssetKind kind;

  bool get _isActor => kind == AssetKind.actor;

  AssetLibrary get _library => _isActor ? app.actors : app.scenes;

  Future<void> _create(BuildContext context, AssetRoute route) =>
      createAsset(context, app: app, kind: kind, route: route);

  Future<void> _edit(BuildContext context, LibraryAsset asset) =>
      showAssetEditor(context, app: app, kind: kind, asset: asset);

  Future<void> _delete(BuildContext context, LibraryAsset asset) async {
    final confirmed = await askToConfirm(
      context,
      //: %1 is the name of an actor or a scene
      title: tr('Delete "%1"?').arg(asset.name),
      message: _isActor
          ? tr('It is taken off every ad that cast it. Nothing already '
              'generated changes.')
          : tr('It is taken off every ad that used it. Nothing already '
              'generated changes.'),
      confirmLabel: tr('Delete'),
    );
    if (!confirmed) return;

    if (_isActor) {
      app.deleteActor(asset.id);
    } else {
      app.deleteScene(asset.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _library,
      builder: (context, _) {
        final assets = _library.assets;

        return Padding(
          padding: const EdgeInsets.all(MqTheme.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: _isActor ? tr('Actors') : tr('Scenes'),
                subtitle: _isActor
                    ? tr('The people your ads are filmed with. Cast one into '
                        'any ad from the studio.')
                    : tr('The places your ads are filmed in. Cast one into '
                        'any ad from the studio.'),
              ),
              const SizedBox(height: MqTheme.gapLarge),
              Expanded(
                child: GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 186,
                        mainAxisExtent: 238,
                        crossAxisSpacing: MqTheme.gap,
                        mainAxisSpacing: MqTheme.gap,
                      ),
                  // The same two first tiles as the gallery, for the same
                  // reason: an empty library reads as something to press rather
                  // than as an empty box with an instruction beside it.
                  itemCount: assets.length + AssetRoute.values.length,
                  itemBuilder: (context, index) {
                    if (index < AssetRoute.values.length) {
                      final route = AssetRoute.values[index];
                      return CreateAssetTile(
                        kind: kind,
                        route: route,
                        onTap: () => _create(context, route),
                      );
                    }
                    final asset = assets[index - AssetRoute.values.length];
                    return AssetCard(
                      asset: asset,
                      onTap: () => _edit(context, asset),
                      onEdit: () => _edit(context, asset),
                      onDelete: () => _delete(context, asset),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
