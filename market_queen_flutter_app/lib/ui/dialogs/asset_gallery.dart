import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../../models/asset_library.dart';
import '../../providers/voice_profile.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/file_menu.dart';
import '../widgets/media_drop.dart';
import '../widgets/media_preview.dart';
import '../widgets/mq_dialog.dart';
import 'actor_editor.dart';
import 'actor_wizard.dart';
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

  AssetLibrary get _library => _isActor ? widget.app.actors : widget.app.scenes;

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
    final id = await editAsset(
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
          ? tr(
              'It is taken off every ad that cast it. Nothing already '
              'generated changes.',
            )
          : tr(
              'It is taken off every ad that used it. Nothing already '
              'generated changes.',
            ),
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
      ? (extent: 176, height: 244)
      : (extent: 232, height: 172);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 96).clamp(560.0, 1020.0);
    // A height, not a ceiling. A window that grows and shrinks with whatever
    // the search happens to match is a window that moves under the cursor
    // between two keystrokes; the grid inside scrolls instead. The subtraction
    // is the room the header, the card padding and the modal's own margin take
    // around it.
    final height = (screen.height - 220).clamp(400.0, 640.0);

    return ListenableBuilder(
      listenable: _library,
      builder: (context, _) => MqModalCard(
        width: width,
        title: _isActor ? tr('Select an actor') : tr('Select a scene'),
        subtitle: _isActor
            ? tr(
                'Everyone you have cast before, and one more click to make '
                'somebody new.',
              )
            : tr(
                'Everywhere you have filmed before, and one more click to '
                'build somewhere new.',
              ),
        child: SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The rail is dropped rather than squeezed on a narrow window:
              // filters are the part of this screen you can do without.
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
      children: [
        AssetSearchField(
          controller: _search,
          placeholder: _isActor ? tr('Search actors') : tr('Search scenes'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: MqTheme.gap),
        // Takes whatever height is left over and scrolls inside it: the modal
        // is the same size whether the library holds three faces or ninety.
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: cell.extent,
              mainAxisExtent: cell.height,
              crossAxisSpacing: MqTheme.gap,
              mainAxisSpacing: MqTheme.gap,
            ),
            // The maker is the first tile rather than a button in the corner:
            // an empty library then reads as something to press instead of an
            // empty box with an instruction beside it.
            //
            // One tile, not two. It was two for a while -- "create" and "turn a
            // picture into one" -- and that put the *method* on the grid before
            // the intent, so the first decision anybody made about a new actor
            // was a technical one. There is one thing to press now, and it asks
            // which way you want to go once you have pressed it.
            itemCount: assets.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return CreateAssetTile(kind: widget.kind, onTap: _create);
              }
              final asset = assets[index - 1];
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

/// Makes one, whichever way the user chooses.
///
/// Asks first, in a small modal, and the question is worth asking: describing
/// somebody and photographing somebody are not two settings of one screen, they
/// are two different jobs with different inputs, and putting both doors on the
/// library grid meant every new actor started with a decision about *method*
/// before anybody had thought about the person.
///
/// Returns the id of what was made, or null when the user backed out of either
/// window.
Future<String?> createAsset(
  BuildContext context, {
  required AppState app,
  required AssetKind kind,
}) async {
  final route = await askForAssetRoute(context, kind: kind);
  if (route == null || !context.mounted) return null;

  // An actor is not a picture: it has a voice, a way of moving and a
  // personality, and neither door is finished until all three exist. Both lead
  // into the same wizard, which differs only in where it starts.
  if (kind == AssetKind.actor) {
    return showActorWizard(
      context,
      app: app,
      route: route == AssetRoute.generate
          ? ActorRoute.describe
          : ActorRoute.fromImage,
    );
  }

  return route == AssetRoute.generate
      ? showAssetStudio(context, app: app, kind: kind)
      : showAssetImport(context, app: app, kind: kind);
}

/// Opens the right editor for the kind.
///
/// An actor gets a screen of its own -- five sections and the face on screen
/// throughout -- and a scene gets the one card it fits on.
Future<String?> editAsset(
  BuildContext context, {
  required AppState app,
  required AssetKind kind,
  required LibraryAsset asset,
}) {
  if (kind == AssetKind.actor) {
    return showActorEditor(context, app: app, actor: asset);
  }
  return showAssetEditor(context, app: app, kind: kind, asset: asset);
}

/// "Describe them, or hand over a photograph?"
///
/// Two illustrated doors rather than two lines of grey text with a small glyph
/// over them. The choice is between describing somebody and photographing
/// somebody, and a picture of a written profile beside a picture of a scanned
/// face says which is which before either sentence is read.
///
/// Returns null when the user closed it, which cancels the whole creation
/// rather than falling through to a default.
Future<AssetRoute?> askForAssetRoute(
  BuildContext context, {
  required AssetKind kind,
}) {
  final actor = kind == AssetKind.actor;

  return showMqModal<AssetRoute>(
    context: context,
    child: Builder(
      builder: (context) => MqModalCard(
        width: 600,
        title: actor ? tr('Create an actor') : tr('Create a scene'),
        subtitle: tr('Two ways in.'),
        // Stretched so the two doors are the same height whichever of them
        // has the longer sentence on it, and wrapped in an IntrinsicHeight
        // because the card's content sits in a scroll view: a stretching Row
        // under an unbounded height asks its children for an infinite one.
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: IllustratedChoice(
                  title: actor
                      ? tr('Write who the actor is')
                      : tr('Write where it is'),
                  subtitle: actor
                      ? tr('Describe the face, the voice and the personality. '
                          'We build the profile from that.')
                      : tr('Say it in a sentence and pick from what comes '
                          'back.'),
                  action: actor
                      ? tr('Write who the actor is')
                      : tr('Write where it is'),
                  icon: 'sparkling-line',
                  // Artwork for the actor doors only: these two renders are a
                  // written profile and a face being read off a card, and
                  // neither is a thing you can say about a room. The scene
                  // modal falls back to the glyph on the same plate.
                  illustration: actor
                      ? 'assets/illustrations/create_with_prompt.png'
                      : '',
                  onPressed: () => closeMqModal(context, AssetRoute.generate),
                ),
              ),
              const SizedBox(width: MqTheme.gap),
              Expanded(
                child: IllustratedChoice(
                  title: tr('Use a photograph'),
                  subtitle: actor
                      ? tr('Bring a clear photo of the face. We read the '
                          'profile off the picture.')
                      : tr('The file you hand over is the picture every shot '
                          'is built on.'),
                  action: tr('Use a photograph'),
                  icon: 'upload-cloud-line',
                  illustration: actor
                      ? 'assets/illustrations/create_with_image.png'
                      : '',
                  onPressed: () => closeMqModal(context, AssetRoute.upload),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
    this.onToggleSelect,
    this.selected = false,
    this.selecting = false,
    this.onDuplicate,
    this.onCreateLook,
  });

  final LibraryAsset asset;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool chosen;

  /// The two things a right-click offers that a hover strip has no room for.
  /// Left null in the casting gallery, where the card is a thing to pick rather
  /// than a thing to manage.
  final VoidCallback? onDuplicate;
  final VoidCallback? onCreateLook;

  /// Set on the pages where several can be picked out at once. Null in the
  /// casting gallery, where picking one is the whole point and picking two
  /// would mean nothing.
  final VoidCallback? onToggleSelect;

  /// Ticked.
  final bool selected;

  /// Whether a selection is under way anywhere in the grid.
  ///
  /// It changes what a plain press does: with nothing selected the card opens,
  /// and once anything is selected the card joins or leaves the selection.
  /// That is the rule every file manager uses, and the alternative -- always
  /// having to hit the small box -- makes picking six things six small
  /// targets.
  final bool selecting;

  /// Actors carry an identity, a voice and a casting brief; scenes carry none
  /// of them. The card tells them apart by what the asset has rather than by
  /// being handed a kind, so the two library pages keep sharing one widget.
  bool get _isActor =>
      asset.extras.containsKey(ActorIdentity.ageKey) ||
      asset.extras.containsKey(ActorIdentity.genderKey) ||
      asset.extras.containsKey('voiceGender') ||
      asset.extras.containsKey('voiceName') ||
      asset.extras.containsKey('createdVia');

  /// Who they are, and where their voice came from: "24 years old · Female",
  /// then "Designed". The dot-separated line the mock-ups have under every face.
  Widget _voiceLine(MqTheme mq) {
    final facts = ActorIdentity.summary(asset);

    final voice = asset.extraText('voiceName');
    final provenance = switch (asset.extraText('voiceKind')) {
      'designed' => tr('Designed'),
      'cloned' => tr('Cloned'),
      'library' => tr('Library'),
      _ => voice.isEmpty ? tr('Cast at render time') : voice,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (facts.isNotEmpty)
          Text(
            facts,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontSmall,
              height: MqTheme.lineTight,
            ),
          ),
        const SizedBox(height: 2),
        Row(
          children: [
            MqIcon(
              voice.isEmpty ? 'mic-line' : 'user-voice-line',
              size: 12,
              color: voice.isEmpty ? mq.textTertiary : mq.textSecondary,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                provenance,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontSmall,
                  height: MqTheme.lineTight,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final thumbnail = asset.thumbnail;

    // Lit like a chosen card, because that is what it is: the two never
    // appear on the same page, so one look serves both.
    final marked = chosen || selected;

    // The right-click menu is where the actions that will not fit on a hover
    // strip live. A card has room for two glyphs and an actor has five things
    // worth doing to it, and the two that were cut -- duplicating one, giving
    // one another outfit -- are exactly the ones you reach for once a face
    // finally works.
    return MediaMenu(
      path: thumbnail,
      actions: [
        if (!selecting) ...[
          if (onEdit != null)
            MediaMenuAction(
              icon: 'edit-line',
              label: tr('Edit'),
              onPressed: onEdit!,
            ),
          if (onDuplicate != null)
            MediaMenuAction(
              icon: 'file-copy-line',
              label: tr('Duplicate'),
              onPressed: onDuplicate!,
            ),
          if (onCreateLook != null)
            MediaMenuAction(
              icon: 'shirt-line',
              label: tr('Create a look'),
              onPressed: onCreateLook!,
            ),
          if (thumbnail.isNotEmpty)
            MediaMenuAction(
              icon: 'fullscreen-line',
              label: tr('View full size'),
              onPressed: () => showMediaPreview(context, thumbnail),
            ),
        ],
      ],
      onRemove: selecting ? null : onDelete,
      removeLabel: tr('Delete'),
      child: _card(context, mq, thumbnail, marked),
    );
  }

  Widget _card(
    BuildContext context,
    MqTheme mq,
    String thumbnail,
    bool marked,
  ) {
    return Pressable(
      onTap: selecting && onToggleSelect != null ? onToggleSelect : onTap,
      // Cards sit in a grid: hover snaps both ways, fill and border together.
      snap: true,
      focusRadius: MqTheme.radius,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: selected
              ? mq.primarySubtle
              : states.pressed
              ? mq.surfaceTertiary
              : states.hovered
              ? mq.surfaceHover
              : mq.surfaceSecondary,
          borderRadius: BorderRadius.circular(MqTheme.radius),
          border: Border.all(
            color: marked
                ? mq.primary
                : states.active
                ? mq.borderStrong
                : mq.border,
            width: marked ? 2 : 1,
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
                  // The tick, top left. Present once anything is selected --
                  // so the grid says at a glance which are in and which are
                  // out -- and otherwise only under the pointer.
                  if (onToggleSelect != null)
                    PositionedDirectional(
                      start: 3,
                      top: 3,
                      child: IgnorePointer(
                        ignoring: !states.active && !selecting,
                        child: AnimatedOpacity(
                          opacity: states.active || selecting ? 1 : 0,
                          duration: states.duration,
                          child: _SelectBox(
                            selected: selected,
                            onTap: onToggleSelect!,
                          ),
                        ),
                      ),
                    ),
                  // Edit and delete stand down while a selection is running:
                  // they act on one card, and the bar above is acting on
                  // several.
                  if ((onEdit != null || onDelete != null) && !selecting)
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
            const SizedBox(height: 2),
            // An actor is a person, and the two things worth knowing about one
            // at a glance are who they read as and how they sound -- not the
            // first line of the prompt that drew them, which is what this said
            // before and which is the same eleven words on every card in a
            // library built from one brief.
            if (_isActor)
              _voiceLine(mq)
            else if (asset.prompt.trim().isNotEmpty)
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
        ),
      ),
    );
  }
}

/// The tick in the corner of a card that can be selected.
class _SelectBox extends StatelessWidget {
  const _SelectBox({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      tooltip: selected ? tr('Deselect') : tr('Select'),
      focusRadius: 5,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? mq.primary
              : mq.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected
                ? mq.primary
                : states.active
                ? mq.borderStrong
                : mq.border,
          ),
        ),
        child: selected
            ? MqIcon('check-line', size: 13, color: mq.onPrimary)
            : null,
      ),
    );
  }
}

/// The tile at the head of a grid of actors or scenes: the way to make another
/// one.
class CreateAssetTile extends StatelessWidget {
  const CreateAssetTile({super.key, required this.kind, required this.onTap});

  final AssetKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final actor = kind == AssetKind.actor;

    final label = actor ? tr('Create an actor') : tr('Create a scene');

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
        // Padding and nothing else: no width, no height, no alignment. A
        // Container given an alignment expands to fill what it is handed --
        // in a Wrap that is the whole rail -- so every pill used to come out
        // full width and stack one per line. Sized to its own word, it is a
        // pill; a long one still folds onto a second line inside the rail
        // rather than overflowing it.
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? mq.onPrimary : mq.textSecondary,
            fontSize: MqTheme.fontSmall,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            height: MqTheme.lineTight,
          ),
        ),
      ),
    );
  }
}

/// The search box above a grid of actors or scenes: a magnifier, a field and
/// a cross once there is something to clear.
///
/// Shared with the library pages rather than copied into them -- the gallery and
/// the Actors page are two views of one list and searching it should not be two
/// slightly different boxes.
class AssetSearchField extends StatefulWidget {
  const AssetSearchField({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String> onChanged;

  @override
  State<AssetSearchField> createState() => _AssetSearchFieldState();
}

class _AssetSearchFieldState extends State<AssetSearchField> {
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
