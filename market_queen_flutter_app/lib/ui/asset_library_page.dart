import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/translator.dart';
import '../models/asset_library.dart';
import 'dialogs/actor_editor.dart';
import 'dialogs/asset_gallery.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets/buttons.dart';
import 'widgets/cards.dart';
import 'widgets/mq_dialog.dart';

/// The Actors page and the Scenes page: the same page twice.
///
/// A cast is worth keeping. Landing a face that reads as real takes several
/// tries, and a room that looks lived-in takes a few more -- once either works
/// it should never have to be found again, in this ad or the next twenty.
///
/// Which is also why it fills up with the tries that did not work, and why the
/// grid can be selected: clearing out a dozen near-misses one confirmation
/// dialog at a time is a chore nobody does, so the near-misses stay.
class AssetLibraryPage extends StatefulWidget {
  const AssetLibraryPage({super.key, required this.app, required this.kind});

  final AppState app;
  final AssetKind kind;

  @override
  State<AssetLibraryPage> createState() => _AssetLibraryPageState();
}

class _AssetLibraryPageState extends State<AssetLibraryPage> {
  /// Ids, not indexes: the library re-sorts itself under us when anything is
  /// renamed or added, and a set of positions would then be pointing at the
  /// wrong cards.
  final Set<String> _selected = {};

  AppState get app => widget.app;

  bool get _isActor => widget.kind == AssetKind.actor;

  AssetLibrary get _library => _isActor ? app.actors : app.scenes;

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  void _selectAll() {
    setState(() {
      _selected
        ..clear()
        ..addAll([for (final asset in _library.assets) asset.id]);
    });
  }

  /// Drops any id that is no longer in the library.
  ///
  /// Deleting somewhere else -- the editor, another window on the same
  /// library -- would otherwise leave the count claiming more than the grid
  /// holds, and "Delete 5" would delete three.
  Set<String> _live() {
    final ids = {for (final asset in _library.assets) asset.id};
    return {..._selected.where(ids.contains)};
  }

  Future<void> _create() =>
      createAsset(context, app: app, kind: widget.kind);

  Future<void> _edit(LibraryAsset asset) =>
      editAsset(context, app: app, kind: widget.kind, asset: asset);

  /// A second copy, under its own name and its own id.
  ///
  /// What it is for: an actor who works, wanted again with one thing changed --
  /// a different voice for a different market, the same face for a second
  /// brand. Doing that by editing the original loses the original.
  void _duplicate(LibraryAsset asset) {
    final copy = asset.copy()
      ..id = ''
      //: %1 is the name of the actor or scene being copied
      ..name = tr('%1 (copy)').arg(asset.name);
    _library.save(copy);
  }

  Future<void> _createLook(LibraryAsset asset) async {
    final look = await showLookMaker(context, app: app, actor: asset);
    if (look == null) return;

    final draft = asset.copy();
    ActorLooks.save(draft, [...ActorLooks.of(draft), look]);
    _library.save(draft);
  }

  void _remove(String id) {
    if (_isActor) {
      app.deleteActor(id);
    } else {
      app.deleteScene(id);
    }
  }

  Future<void> _deleteOne(LibraryAsset asset) async {
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

    _remove(asset.id);
  }

  /// Deletes everything ticked, behind one confirmation rather than one each.
  Future<void> _deleteSelected() async {
    final ids = _live();
    if (ids.isEmpty) return;

    final confirmed = await askToConfirm(
      context,
      title: _isActor
          //: %1 is a number of actors
          ? tr('Delete %1 actors?').arg(ids.length)
          //: %1 is a number of scenes
          : tr('Delete %1 scenes?').arg(ids.length),
      message: _isActor
          ? tr('They are taken off every ad that cast them. Nothing already '
              'generated changes.')
          : tr('They are taken off every ad that used them. Nothing already '
              'generated changes.'),
      confirmLabel: tr('Delete'),
    );
    if (!confirmed) return;

    for (final id in ids) {
      _remove(id);
    }
    _clearSelection();
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
              // The bar only exists while something is ticked. A permanent
              // "Select" mode to enter and leave would be a mode; a bar that
              // appears when there is something to act on is just the answer.
              if (_selecting) ...[
                const SizedBox(height: MqTheme.gap),
                _SelectionBar(
                  count: _live().length,
                  total: assets.length,
                  onSelectAll: _selectAll,
                  onClear: _clearSelection,
                  onDelete: _deleteSelected,
                ),
              ],
              const SizedBox(height: MqTheme.gapLarge),
              Expanded(
                child: GridView.builder(
                  // An actor's card carries two more lines than a scene's --
                  // who they read as, and where their voice came from -- and
                  // a shared height would have taken those out of the picture
                  // above them.
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 186,
                    mainAxisExtent: _isActor ? 256 : 238,
                    crossAxisSpacing: MqTheme.gap,
                    mainAxisSpacing: MqTheme.gap,
                  ),
                  // The same first tile as the gallery, for the same reason: an
                  // empty library reads as something to press rather than as an
                  // empty box with an instruction beside it.
                  itemCount: assets.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return CreateAssetTile(
                        kind: widget.kind,
                        onTap: _create,
                      );
                    }
                    final asset = assets[index - 1];
                    return AssetCard(
                      asset: asset,
                      selecting: _selecting,
                      selected: _selected.contains(asset.id),
                      onToggleSelect: () => _toggle(asset.id),
                      onTap: () => _edit(asset),
                      onEdit: () => _edit(asset),
                      onDelete: () => _deleteOne(asset),
                      onDuplicate: () => _duplicate(asset),
                      // Only an actor has a wardrobe. A scene is the place,
                      // and a second version of it is a second scene.
                      onCreateLook:
                          _isActor ? () => _createLook(asset) : null,
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

/// What is ticked, and the two things to do about it.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.total,
    required this.onSelectAll,
    required this.onClear,
    required this.onDelete,
  });

  final int count;
  final int total;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radius),
        border: Border.all(color: mq.border),
      ),
      child: Row(
        children: [
          MqIcon('check-line', size: 15, color: mq.textSecondary),
          const SizedBox(width: 8),
          Text(
            //: %1 is a number of selected items
            tr('%1 selected').arg(count),
            style: TextStyle(
              color: mq.textPrimary,
              fontSize: MqTheme.fontLabel,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 14),
          if (count < total)
            MqLink(text: tr('Select all'), onPressed: onSelectAll),
          const Spacer(),
          GhostButton(text: tr('Cancel'), onPressed: onClear),
          const SizedBox(width: 8),
          GhostButton(
            text: tr('Delete'),
            destructive: true,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
