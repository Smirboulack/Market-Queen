import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../../models/asset_library.dart';
import '../../providers/voice_profile.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/media_drop.dart';
import '../widgets/mq_dialog.dart';
import 'asset_editor.dart';
import 'asset_studio.dart';

/// Casting something into the ad: the library, straight away.
///
/// It used to be a modal asking whether you wanted to pick one or make one --
/// a question with an obvious answer that had to be answered every single time.
/// The library *is* the answer to both: the first tile in the grid makes a new
/// one, and everything after it is one you already have.
///
/// Returns the id that was cast, or null if the user backed out.
Future<String?> showAssetGallery(
  BuildContext context, {
  required AppState app,
  required AssetKind kind,
}) {
  return showMqModal<String>(
    context: context,
    child: _Gallery(app: app, kind: kind),
  );
}

/// One filter group down the left-hand rail: a heading and a row of toggles.
///
/// The values are the ones the assets already carry -- an actor's casting brief
/// and a scene's dials -- rather than a second set of tags to keep in step with
/// them. An asset that has never been given one simply does not answer to that
/// filter, which is the honest behaviour: it is unset, not "other".
class _FilterGroup {
  const _FilterGroup(this.key, this.label, this.options);

  final String key;
  final String label;

  /// Label shown, value stored on the asset.
  final List<(String, String)> options;

  static List<_FilterGroup> of(AssetKind kind) {
    if (kind == AssetKind.actor) {
      return [
        for (final trait in VoiceTrait.all)
          if (trait.key == 'voiceGender' || trait.key == 'voiceAge')
            _FilterGroup(trait.key, trait.label, trait.options),
      ];
    }
    return [
      for (final tweak in SceneTweak.all)
        if (tweak.key == 'space' || tweak.key == 'light')
          _FilterGroup(tweak.key, tweak.label, tweak.options),
    ];
  }
}

class _Gallery extends StatefulWidget {
  const _Gallery({required this.app, required this.kind});

  final AppState app;
  final AssetKind kind;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final TextEditingController _search = TextEditingController();

  /// One value per filter group, or nothing. Tapping the lit toggle clears it,
  /// so there is no "all" pill to explain.
  final Map<String, String> _filters = {};

  bool get _isActor => widget.kind == AssetKind.actor;

  AssetLibrary get _library =>
      _isActor ? widget.app.actors : widget.app.scenes;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<LibraryAsset> get _shown {
    final found = _library.search(_search.text);
    if (_filters.isEmpty) return found;
    return [
      for (final asset in found)
        if (_filters.entries.every(
          (filter) => asset.extraText(filter.key) == filter.value,
        ))
          asset,
    ];
  }

  // ---- actions -------------------------------------------------------------

  Future<void> _create(AssetRoute route) async {
    final id = await createAsset(
      context,
      app: widget.app,
      kind: widget.kind,
      route: route,
    );
    if (id != null && mounted) closeMqModal(context, id);
  }

  Future<void> _edit(LibraryAsset asset) async {
    final id = await showAssetEditor(
      context,
      app: widget.app,
      kind: widget.kind,
      asset: asset,
    );
    if (!mounted) return;
    // Saving from the pencil casts it too: you opened it to use it.
    if (id != null) {
      closeMqModal(context, id);
    } else {
      setState(() {});
    }
  }

  Future<void> _delete(LibraryAsset asset) async {
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
    if (!confirmed || !mounted) return;

    if (_isActor) {
      widget.app.deleteActor(asset.id);
    } else {
      widget.app.deleteScene(asset.id);
    }
    if (mounted) setState(() {});
  }

  // ---- build ---------------------------------------------------------------

  /// The shape of one tile, which is not the same question for the two kinds.
  ///
  /// An actor is a person and is photographed as one: a portrait, head and
  /// shoulders, and a tall narrow tile is exactly the crop you want of it. A
  /// scene is a room, a street, the inside of a car -- landscape, every time --
  /// and the same portrait tile was cutting the sides off every one of them and
  /// then stacking eight of them into a wall of slivers. The card underneath is
  /// one widget for both; only the cell it is given differs.
  ({double extent, double height}) get _cell => _isActor
      ? (extent: 176, height: 226)
      : (extent: 232, height: 172);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 96).clamp(560.0, 1020.0);
    // A ceiling rather than a height. It used to be both, so a library holding
    // four scenes opened a modal two thirds of which was empty white, with the
    // tiles pinned to the top of it.
    final maxHeight = (screen.height - 120).clamp(360.0, 660.0);

    return ListenableBuilder(
      listenable: _library,
      builder: (context, _) => MqModalCard(
        width: width,
        title: _isActor ? tr('Select an actor') : tr('Select a scene'),
        subtitle: _isActor
            ? tr('Everyone you have cast before, and one more click to make '
                'somebody new.')
            : tr('Everywhere you have filmed before, and one more click to '
                'build somewhere new.'),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The rail is dropped rather than squeezed on a narrow window:
              // filters are the part of this screen you can do without.
              //
              // No rule between the two, and deliberately: everything in this
              // row shrink-wraps so that four scenes get a short modal, and a
              // hairline tall enough to look like a divider would be the one
              // thing in it insisting on the full height.
              if (width > 760) ...[
                SizedBox(width: 168, child: _rail(context)),
                const SizedBox(width: MqTheme.gapLarge + 12),
              ],
              Expanded(child: _grid(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rail(BuildContext context) {
    final groups = _FilterGroup.of(widget.kind);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drops the first label onto the middle of the search box beside it,
          // instead of level with its top edge.
          const SizedBox(height: 9),
          for (final group in groups) ...[
            FieldLabel(group.label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final option in group.options)
                  _FilterPill(
                    label: option.$1,
                    selected: _filters[group.key] == option.$2,
                    onTap: () => setState(() {
                      if (_filters[group.key] == option.$2) {
                        _filters.remove(group.key);
                      } else {
                        _filters[group.key] = option.$2;
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: MqTheme.gapLarge),
          ],
          if (_filters.isNotEmpty)
            MqLink(
              text: tr('Clear the filters'),
              onPressed: () => setState(_filters.clear),
            ),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context) {
    final assets = _shown;
    final hidden = _library.count - assets.length;
    final cell = _cell;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SearchField(
          controller: _search,
          placeholder: _isActor ? tr('Search actors') : tr('Search scenes'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: MqTheme.gap),
        // Shrink-wrapped, and scrolling only once there is more than the
        // ceiling allows: three scenes take three tiles' worth of modal.
        Flexible(
          child: GridView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: cell.extent,
              mainAxisExtent: cell.height,
              crossAxisSpacing: MqTheme.gap,
              mainAxisSpacing: MqTheme.gap,
            ),
            // The two makers are the first two tiles rather than a button in
            // the corner: an empty library then reads as two things to press
            // instead of an empty box with an instruction beside it. They used
            // to be one tile that opened a modal asking which of the two you
            // meant -- a question with two answers, both of which are right
            // here, one click earlier.
            itemCount: assets.length + AssetRoute.values.length,
            itemBuilder: (context, index) {
              if (index < AssetRoute.values.length) {
                final route = AssetRoute.values[index];
                return CreateAssetTile(
                  kind: widget.kind,
                  route: route,
                  onTap: () => _create(route),
                );
              }
              final asset = assets[index - AssetRoute.values.length];
              return AssetCard(
                asset: asset,
                onTap: () => closeMqModal(context, asset.id),
                onEdit: () => _edit(asset),
                onDelete: () => _delete(asset),
              );
            },
          ),
        ),
        if (hidden > 0) ...[
          const SizedBox(height: 8),
          Text(
            //: %1 is a number of actors or scenes
            tr('%1 hidden by the search and filters').arg(hidden),
            style: TextStyle(
              color: context.mq.textTertiary,
              fontSize: MqTheme.fontSmall,
            ),
          ),
        ],
      ],
    );
  }
}

/// The two ways to make an actor or a scene.
enum AssetRoute { generate, upload }

/// Opens whichever of the two the user pressed.
///
/// Returns the id of what was made, or null.
///
/// There used to be a modal between the tile and this, asking which of the two
/// was meant -- a question the tile itself now answers, one click and one
/// window earlier.
Future<String?> createAsset(
  BuildContext context, {
  required AppState app,
  required AssetKind kind,
  AssetRoute route = AssetRoute.generate,
}) {
  return route == AssetRoute.generate
      ? showAssetStudio(context, app: app, kind: kind)
      : showAssetImport(context, app: app, kind: kind);
}

/// One actor or scene, as a card. Used by the gallery and by both library
/// pages, so a face looks the same wherever it turns up.
class AssetCard extends StatelessWidget {
  const AssetCard({
    super.key,
    required this.asset,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.chosen = false,
  });

  final LibraryAsset asset;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
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
        padding: const EdgeInsets.all(7),
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
                  if (onEdit != null || onDelete != null)
                    PositionedDirectional(
                      end: 3,
                      top: 3,
                      child: IgnorePointer(
                        ignoring: !states.active,
                        child: AnimatedOpacity(
                          opacity: states.active ? 1 : 0,
                          duration: states.duration,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: mq.surface.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(
                                MqTheme.radiusSmall,
                              ),
                              border: Border.all(color: mq.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (onEdit != null)
                                  MqIconButton(
                                    icon: 'edit-line',
                                    tip: tr('Edit'),
                                    size: 26,
                                    onPressed: onEdit,
                                  ),
                                if (onDelete != null)
                                  MqIconButton(
                                    icon: 'delete-bin-line',
                                    tip: tr('Delete'),
                                    size: 26,
                                    destructive: true,
                                    onPressed: onDelete,
                                  ),
                              ],
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

/// One of the two tiles at the head of a grid of actors or scenes: the two ways
/// to make another one.
class CreateAssetTile extends StatelessWidget {
  const CreateAssetTile({
    super.key,
    required this.kind,
    required this.onTap,
    this.route = AssetRoute.generate,
  });

  final AssetKind kind;
  final AssetRoute route;
  final VoidCallback onTap;

  bool get _generating => route == AssetRoute.generate;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final actor = kind == AssetKind.actor;

    final label = _generating
        ? (actor ? tr('Create an actor') : tr('Create a scene'))
        : (actor
            ? tr('Turn a picture into an actor')
            : tr('Turn a picture into a scene'));

    return Pressable(
      onTap: onTap,
      snap: true,
      focusRadius: MqTheme.radius,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: states.pressed
              ? mq.surfaceTertiary
              : states.hovered
              ? mq.surfaceHover
              : mq.surfaceSecondary,
          borderRadius: BorderRadius.circular(MqTheme.radius),
          border: Border.all(
            color: states.active ? mq.borderStrong : mq.border,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: mq.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: states.active ? mq.borderStrong : mq.border,
                ),
              ),
              child: MqIcon(
                _generating ? 'sparkling-line' : 'upload-cloud-line',
                size: 20,
                color: states.active ? mq.textPrimary : mq.textTertiary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: mq.textPrimary,
                fontSize: MqTheme.fontLabel,
                fontWeight: FontWeight.w600,
                height: MqTheme.lineTight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A filter toggle on the rail. Smaller and quieter than a chip: there are
/// eight of them on screen and none of them is an action.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      focusRadius: MqTheme.radiusPill,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        // A floor rather than a height. "Lumière du jour par la fenêtre" is
        // three times the width of the rail it sits in, and a pill that
        // insists on one line simply overflowed it -- by two hundred pixels,
        // in stripes, on every frame the modal was open. It wraps now.
        constraints: const BoxConstraints(minHeight: 28),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? mq.primary
              : states.active
              ? mq.surfaceHover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radiusPill),
          border: Border.all(
            color: selected
                ? mq.primary
                : states.active
                ? mq.borderStrong
                : mq.border,
          ),
        ),
        // A row rather than `alignment: center` alone: a Container that is
        // given an alignment and no width expands to fill whatever it is
        // handed, which in a Wrap is the whole rail -- so every pill came out
        // full width and stacked. A min-size row shrink-wraps to the word and
        // centres it; the flexible text is what lets a long one fold instead
        // of running off the end.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? mq.onPrimary : mq.textSecondary,
                  fontSize: MqTheme.fontSmall,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  height: MqTheme.lineTight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The search box above the grid: a magnifier and a field, no label.
class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.controller,
    required this.placeholder,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final FocusNode _focus = FocusNode();
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: FieldFrame(
        focused: _focus.hasFocus,
        hovered: _hovered,
        child: SizedBox(
          height: MqTheme.fieldHeight,
          child: Row(
            children: [
              const SizedBox(width: 11),
              MqIcon('search-line', size: 16, color: mq.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  onChanged: widget.onChanged,
                  cursorColor: mq.primary,
                  style: TextStyle(
                    color: mq.textPrimary,
                    fontSize: MqTheme.fontBody,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                    hintText: widget.placeholder,
                    hintStyle: TextStyle(
                      color: mq.textTertiary,
                      fontSize: MqTheme.fontBody,
                    ),
                  ),
                ),
              ),
              if (widget.controller.text.isNotEmpty)
                MqIconButton(
                  icon: 'close-line',
                  tip: tr('Clear'),
                  size: 26,
                  onPressed: () {
                    widget.controller.clear();
                    widget.onChanged('');
                  },
                ),
              const SizedBox(width: 5),
            ],
          ),
        ),
      ),
    );
  }
}
