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

  Future<void> _create() async {
    final id = await createAsset(context, app: widget.app, kind: widget.kind);
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

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 96).clamp(560.0, 1020.0);
    final height = (screen.height - 120).clamp(420.0, 660.0);

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
        child: SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The rail is dropped rather than squeezed on a narrow window:
              // filters are the part of this screen you can do without.
              if (width > 760) ...[
                SizedBox(width: 176, child: _rail()),
                const SizedBox(width: MqTheme.gapLarge),
              ],
              Expanded(child: _grid()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rail() {
    final groups = _FilterGroup.of(widget.kind);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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

  Widget _grid() {
    final assets = _shown;
    final hidden = _library.count - assets.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchField(
          controller: _search,
          placeholder: _isActor ? tr('Search actors') : tr('Search scenes'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: MqTheme.gap),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 176,
              mainAxisExtent: 226,
              crossAxisSpacing: MqTheme.gap,
              mainAxisSpacing: MqTheme.gap,
            ),
            // The maker is the first tile rather than a button in the corner:
            // an empty library then reads as one thing to press instead of an
            // empty box with an instruction beside it.
            itemCount: assets.length + 1,
            itemBuilder: (context, index) => index == 0
                ? CreateAssetTile(kind: widget.kind, onTap: _create)
                : AssetCard(
                    asset: assets[index - 1],
                    onTap: () =>
                        closeMqModal(context, assets[index - 1].id),
                    onEdit: () => _edit(assets[index - 1]),
                    onDelete: () => _delete(assets[index - 1]),
                  ),
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

/// The two ways to make one, and the modal that asks which.
///
/// Returns the id of what was made, or null.
Future<String?> createAsset(
  BuildContext context, {
  required AppState app,
  required AssetKind kind,
}) async {
  final route = await showMqModal<_Route>(
    context: context,
    child: _HowToCreate(kind: kind),
  );
  if (route == null || !context.mounted) return null;

  return route == _Route.generate
      ? showAssetStudio(context, app: app, kind: kind)
      : showAssetImport(context, app: app, kind: kind);
}

enum _Route { generate, upload }

class _HowToCreate extends StatelessWidget {
  const _HowToCreate({required this.kind});

  final AssetKind kind;

  @override
  Widget build(BuildContext context) {
    final actor = kind == AssetKind.actor;

    return MqModalCard(
      width: 620,
      title: actor ? tr('Create an actor') : tr('Create a scene'),
      subtitle: tr('Two ways in. Both end with a picture you keep.'),
      // Through an [IntrinsicHeight]: the card is inside a scroll view, so its
      // height is unbounded, and stretching the row is the only way to make the
      // two doors match without a fixed height that clips the longer one.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: BigChoice(
                icon: 'sparkling-line',
                overline: tr('Generate'),
                title: tr('From a description and reference pictures'),
                subtitle: actor
                    ? tr('Say who they are. Iterate until the face is right.')
                    : tr('Say where it is. Iterate until the room is right.'),
                onPressed: () => closeMqModal(context, _Route.generate),
              ),
            ),
            const SizedBox(width: MqTheme.gap),
            Expanded(
              child: BigChoice(
                icon: 'upload-cloud-line',
                overline: tr('Import'),
                title: actor
                    ? tr('Turn a picture into an actor')
                    : tr('Turn a picture into a scene'),
                subtitle: tr('One you already have, from your own files.'),
                onPressed: () => closeMqModal(context, _Route.upload),
              ),
            ),
          ],
        ),
      ),
    );
  }
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

/// The first tile of a grid of actors or scenes: the way to make another one.
class CreateAssetTile extends StatelessWidget {
  const CreateAssetTile({super.key, required this.kind, required this.onTap});

  final AssetKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final actor = kind == AssetKind.actor;

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
                'add-line',
                size: 20,
                color: states.active ? mq.textPrimary : mq.textTertiary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              actor ? tr('Create an actor') : tr('Create a scene'),
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
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 11),
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
        child: Text(
          label,
          style: TextStyle(
            color: selected ? mq.onPrimary : mq.textSecondary,
            fontSize: MqTheme.fontSmall,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
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
