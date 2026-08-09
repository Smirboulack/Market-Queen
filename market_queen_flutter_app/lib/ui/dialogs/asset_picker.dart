import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../../models/asset_library.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/media_drop.dart';
import '../widgets/mq_dialog.dart';
import 'asset_editor.dart';

/// Casting something into the ad: pick one you already have, or make one.
///
/// Two doors and nothing else on the first screen. Putting the library grid
/// straight in front of somebody with an empty library is how the old rail read
/// -- an empty strip above a form -- and it never said that making a new actor
/// was the other half of the choice.
///
/// Returns the id that was cast, or null if the user backed out.
Future<String?> showAssetPicker(
  BuildContext context, {
  required AppState app,
  required AssetKind kind,
}) async {
  final library = kind == AssetKind.actor ? app.actors : app.decors;

  final choice = await showMqModal<_Door>(
    context: context,
    child: _Doors(kind: kind, hasExisting: library.count > 0),
  );
  if (choice == null || !context.mounted) return null;

  if (choice == _Door.create) {
    return showAssetEditor(context, app: app, kind: kind);
  }

  return showAssetChooser(context, app: app, kind: kind);
}

/// The library, as a grid to choose from. Also what the "Replace" action on a
/// cast actor or décor opens straight onto.
Future<String?> showAssetChooser(
  BuildContext context, {
  required AppState app,
  required AssetKind kind,
}) {
  return showMqModal<String>(
    context: context,
    child: _Chooser(app: app, kind: kind),
  );
}

enum _Door { existing, create }

class _Doors extends StatelessWidget {
  const _Doors({required this.kind, required this.hasExisting});

  final AssetKind kind;
  final bool hasExisting;

  @override
  Widget build(BuildContext context) {
    final actor = kind == AssetKind.actor;

    return MqModalCard(
      width: 620,
      title: actor ? tr('Add an actor') : tr('Add a décor'),
      subtitle: actor
          ? tr('Who is on camera?')
          : tr('Where is this filmed?'),
      child: Row(
        children: [
          Expanded(
            child: BigChoice(
              icon: 'user-line',
              title: actor
                  ? tr('Pick or edit an existing actor')
                  : tr('Pick or edit an existing décor'),
              subtitle: hasExisting
                  ? tr('From your library.')
                  : tr('Your library is empty for now.'),
              enabled: hasExisting,
              onPressed: () => Navigator.of(context).pop(_Door.existing),
            ),
          ),
          const SizedBox(width: MqTheme.gap),
          Expanded(
            child: BigChoice(
              icon: 'user-add-line',
              title: actor ? tr('Create an actor') : tr('Create a décor'),
              subtitle: tr('Pictures, clips, or a sentence.'),
              onPressed: () => Navigator.of(context).pop(_Door.create),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chooser extends StatefulWidget {
  const _Chooser({required this.app, required this.kind});

  final AppState app;
  final AssetKind kind;

  @override
  State<_Chooser> createState() => _ChooserState();
}

class _ChooserState extends State<_Chooser> {
  AssetLibrary get _library =>
      widget.kind == AssetKind.actor ? widget.app.actors : widget.app.decors;

  Future<void> _edit(LibraryAsset asset) async {
    final id = await showAssetEditor(
      context,
      app: widget.app,
      kind: widget.kind,
      asset: asset,
    );
    if (!mounted) return;
    // Saving from here casts it too: you opened it to use it.
    if (id != null) {
      Navigator.of(context).pop(id);
    } else {
      setState(() {});
    }
  }

  Future<void> _create() async {
    final id = await showAssetEditor(
      context,
      app: widget.app,
      kind: widget.kind,
    );
    if (!mounted) return;
    if (id != null) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final actor = widget.kind == AssetKind.actor;

    return ListenableBuilder(
      listenable: _library,
      builder: (context, _) {
        final assets = _library.assets;

        return MqModalCard(
          width: 640,
          title: actor ? tr('Your actors') : tr('Your décors'),
          subtitle: tr('Click to cast. The pencil opens it for changes.'),
          actions: [
            GhostButton(
              text: actor ? tr('New actor') : tr('New décor'),
              onPressed: _create,
            ),
          ],
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 148,
                mainAxisExtent: 186,
                crossAxisSpacing: MqTheme.gap,
                mainAxisSpacing: MqTheme.gap,
              ),
              itemCount: assets.length,
              itemBuilder: (context, index) => AssetCard(
                asset: assets[index],
                onTap: () => Navigator.of(context).pop(assets[index].id),
                onEdit: () => _edit(assets[index]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One actor or décor, as a card. Used by the chooser and by both library
/// pages, so a face looks the same wherever it turns up.
class AssetCard extends StatelessWidget {
  const AssetCard({
    super.key,
    required this.asset,
    required this.onTap,
    this.onEdit,
    this.chosen = false,
  });

  final LibraryAsset asset;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final bool chosen;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final thumbnail = asset.thumbnail;

    return Pressable(
      onTap: onTap,
      // Cards sit in a grid: hover snaps both ways, fill and border together.
      snap: true,
      focusRadius: MqTheme.radius,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: states.pressed
              ? mq.surfaceTertiary
              : states.hovered
              ? mq.surfaceHover
              : mq.surfaceSecondary,
          borderRadius: BorderRadius.circular(MqTheme.radius),
          border: Border.all(
            color: chosen
                ? mq.primary
                : states.active
                ? mq.borderStrong
                : mq.border,
            width: chosen ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: mq.background,
                      borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: thumbnail.isEmpty
                        ? Center(
                            child: MqIcon(
                              'user-smile-line',
                              size: 22,
                              color: mq.textTertiary,
                            ),
                          )
                        : LocalImage(thumbnail),
                  ),
                  if (onEdit != null)
                    PositionedDirectional(
                      end: 2,
                      top: 2,
                      child: IgnorePointer(
                        ignoring: !states.active,
                        child: AnimatedOpacity(
                          opacity: states.active ? 1 : 0,
                          duration: states.duration,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: mq.surface.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(
                                MqTheme.radiusSmall,
                              ),
                            ),
                            child: MqIconButton(
                              icon: 'edit-line',
                              tip: tr('Edit'),
                              size: 24,
                              onPressed: onEdit,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              asset.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: mq.textPrimary,
                fontSize: MqTheme.fontLabel,
                fontWeight: FontWeight.w600,
                height: MqTheme.lineTight,
              ),
            ),
            if (asset.prompt.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                asset.prompt.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontSmall,
                  height: MqTheme.lineTight,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
