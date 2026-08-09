import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../../models/asset_library.dart';
import '../dialogs/asset_editor.dart';
import '../dialogs/asset_picker.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/media_drop.dart';
import '../widgets/panels.dart';
import '../widgets/scenario_bar.dart';
import '../widgets/section_panel.dart';

/// Where an ad is written.
///
/// One column down the middle, and the bar you write in pinned to the foot of
/// it. Everything that used to live in a 400px rail on the right is now two
/// folding panels above the bar: the product, and who is in the scene. They
/// fold because they are filled in once and read never, while the scenario is
/// rewritten twenty times.
///
/// There is no scene list. A UGC ad is one person, in one room, saying one
/// thing, filmed in one take -- writing it as five labelled beats produced
/// five-part adverts, which is exactly what a UGC ad is not.
class AdEditorPage extends StatefulWidget {
  const AdEditorPage({
    super.key,
    required this.app,
    required this.onGenerate,
  });

  final AppState app;
  final VoidCallback onGenerate;

  @override
  State<AdEditorPage> createState() => _AdEditorPageState();
}

class _AdEditorPageState extends State<AdEditorPage> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _audience = TextEditingController();
  final _scenario = TextEditingController();

  bool _productOpen = true;
  bool _castOpen = true;

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    _resync();
    app.project.reloaded.addListener(_resync);
  }

  @override
  void dispose() {
    app.project.reloaded.removeListener(_resync);
    _name.dispose();
    _description.dispose();
    _audience.dispose();
    _scenario.dispose();
    super.dispose();
  }

  /// The fields hold their own text once the user is typing, so opening a
  /// different ad has to push its contents in rather than hope they follow.
  void _resync() {
    if (!mounted) return;
    final project = app.project;
    setState(() {
      _name.text = '${project.product['name'] ?? ''}';
      _description.text = '${project.product['description'] ?? ''}';
      _audience.text = '${project.product['audience'] ?? ''}';
      _scenario.text = project.script;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              MqTheme.pagePadding,
              MqTheme.gapLarge,
              MqTheme.pagePadding,
              MqTheme.gap,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _canvasWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _productPanel(),
                    const SizedBox(height: MqTheme.gap),
                    _castPanel(),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MqTheme.pagePadding,
            0,
            MqTheme.pagePadding,
            MqTheme.gap,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _canvasWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ScenarioBar(
                    app: app,
                    controller: _scenario,
                    onGenerate: widget.onGenerate,
                  ),
                  const SizedBox(height: 10),
                  _costLine(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Wide enough for a sentence to read as a sentence, narrow enough that the
  /// eye does not have to travel to the far edge of a 27" monitor to find the
  /// Generate button.
  static const double _canvasWidth = 980;

  // ---- the product ---------------------------------------------------------

  Widget _productPanel() {
    final project = app.project;

    return ListenableBuilder(
      listenable: project,
      builder: (context, _) => SectionPanel(
        title: tr('Product or service'),
        subtitle: tr('What you are selling.'),
        required: true,
        open: _productOpen,
        onToggled: () => setState(() => _productOpen = !_productOpen),
        trailing: _productOpen ? null : _summary(_name.text),
        children: [
          LabeledField(
            controller: _name,
            placeholder: tr('Product or service name'),
            onChanged: (text) => project.setProductField('name', text),
          ),
          LabeledField(
            controller: _description,
            placeholder: tr('What it does, what it is for'),
            onChanged: (text) => project.setProductField('description', text),
          ),
          LabeledField(
            controller: _audience,
            placeholder: tr('Who it is for'),
            onChanged: (text) => project.setProductField('audience', text),
          ),
          MediaDropZone(
            paths: project.media,
            tall: true,
            title: tr('Add photos of the product'),
            hint: tr('The first one is the reference every shot is drawn '
                'from. Clips are welcome too.'),
            onAdded: project.addMedia,
            onRemoved: project.removeMedia,
            onPrimary: project.setPrimaryMedia,
          ),
        ],
      ),
    );
  }

  Widget? _summary(String text) {
    if (text.trim().isEmpty) return null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Text(
        text.trim(),
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: TextStyle(
          color: context.mq.textTertiary,
          fontSize: MqTheme.fontSmall,
        ),
      ),
    );
  }

  // ---- who is in the scene -------------------------------------------------

  Widget _castPanel() {
    return ListenableBuilder(
      listenable: Listenable.merge([app.project, app.actors, app.decors]),
      builder: (context, _) {
        final project = app.project;
        final actor = project.actorIds.isEmpty
            ? null
            : app.actors.byId(project.actorIds.first);
        final decor = app.decors.byId(project.decorId);

        return SectionPanel(
          title: tr('Actor and décor'),
          subtitle: tr('Who is in the scene?'),
          required: true,
          open: _castOpen,
          onToggled: () => setState(() => _castOpen = !_castOpen),
          trailing: _castOpen
              ? null
              : _summary(
                  [
                    if (actor != null) actor.name,
                    if (decor != null) decor.name,
                  ].join(' · '),
                ),
          children: [
            _CastSlot(
              heading: tr('Actor'),
              addLabel: tr('+ Add an actor'),
              asset: actor,
              onAdd: () => _pick(AssetKind.actor),
              onEdit: () => _edit(AssetKind.actor, actor!),
              onReplace: () => _replace(AssetKind.actor),
              onRemove: project.clearActor,
            ),
            const SizedBox(height: 6),
            _CastSlot(
              heading: tr('Décor'),
              addLabel: tr('+ Add a décor'),
              asset: decor,
              onAdd: () => _pick(AssetKind.decor),
              onEdit: () => _edit(AssetKind.decor, decor!),
              onReplace: () => _replace(AssetKind.decor),
              onRemove: project.clearDecor,
            ),
          ],
        );
      },
    );
  }

  void _cast(AssetKind kind, String? id) {
    if (id == null) return;
    if (kind == AssetKind.actor) {
      app.project.setActor(id);
    } else {
      app.project.setDecor(id);
    }
  }

  Future<void> _pick(AssetKind kind) async =>
      _cast(kind, await showAssetPicker(context, app: app, kind: kind));

  Future<void> _replace(AssetKind kind) async =>
      _cast(kind, await showAssetChooser(context, app: app, kind: kind));

  Future<void> _edit(AssetKind kind, LibraryAsset asset) async {
    final id = await showAssetEditor(
      context,
      app: app,
      kind: kind,
      asset: asset,
    );
    _cast(kind, id);
  }

  // ---- the running total ---------------------------------------------------

  Widget _costLine() {
    final mq = context.mq;

    return ListenableBuilder(
      listenable: app.project,
      builder: (context, _) {
        final project = app.project;
        final request = app.request();
        final breakdown = app.pricing.estimate(request);
        final seconds = project.spokenSeconds;

        return Row(
          children: [
            Builder(
              builder: (anchor) => Pressable(
                onTap: () => _showBreakdown(anchor, request),
                focusRadius: MqTheme.radiusSmall,
                builder: (context, states) => AnimatedContainer(
                  duration: states.duration,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: states.active ? mq.surfaceHover : Colors.transparent,
                    borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        //: %1 is a price
                        tr('Estimated cost %1').arg(
                          Format.estimated(breakdown.total),
                        ),
                        style: TextStyle(
                          color: states.active
                              ? mq.textPrimary
                              : mq.textSecondary,
                          fontSize: MqTheme.fontSmall,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 5),
                      MqIcon(
                        'information-line',
                        size: 13,
                        color: mq.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: MqTheme.gap),
            if (seconds > 0)
              Text(
                //: %1 is a duration in seconds
                tr('about %1 s spoken').arg(seconds.toStringAsFixed(1)),
                style: TextStyle(
                  color: project.overLength ? mq.warningText : mq.textTertiary,
                  fontSize: MqTheme.fontSmall,
                ),
              ),
            const Spacer(),
            if (project.overLength)
              Text(
                //: %1 is a duration in seconds
                tr('Longer than the %1 s you allowed.').arg(project.maxSeconds),
                style: TextStyle(
                  color: mq.warningText,
                  fontSize: MqTheme.fontSmall,
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _showBreakdown(
    BuildContext anchor,
    Map<String, Object?> request,
  ) async {
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);

    await showMenu<void>(
      context: anchor,
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 340),
      position: RelativeRect.fromLTRB(
        origin.dx,
        // Above the line rather than below it: there is no room under it.
        origin.dy - 340,
        overlay.size.width - origin.dx - 340,
        0,
      ),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: 320,
            child: EstimateCard(app: app, request: request),
          ),
        ),
      ],
    );
  }
}

/// An actor or a décor in the ad: an outlined button while the slot is empty,
/// the thing itself once it is filled.
///
/// Clicking what is cast opens it for changes rather than swapping it, because
/// tweaking the description is the common act and replacing is the rare one --
/// which is why replacing is a named link and not the whole card.
class _CastSlot extends StatelessWidget {
  const _CastSlot({
    required this.heading,
    required this.addLabel,
    required this.asset,
    required this.onAdd,
    required this.onEdit,
    required this.onReplace,
    required this.onRemove,
  });

  final String heading;
  final String addLabel;
  final LibraryAsset? asset;
  final VoidCallback onAdd;
  final VoidCallback onEdit;
  final VoidCallback onReplace;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final cast = asset;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: TextStyle(
            color: mq.textSecondary,
            fontSize: MqTheme.fontLabel,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (cast == null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: GhostButton(text: addLabel, onPressed: onAdd),
          )
        else
          Pressable(
            onTap: onEdit,
            focusRadius: MqTheme.radius,
            builder: (context, states) => AnimatedContainer(
              duration: states.duration,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: states.active ? mq.surfaceHover : mq.surfaceSecondary,
                borderRadius: BorderRadius.circular(MqTheme.radius),
                border: Border.all(
                  color: states.active ? mq.borderStrong : mq.border,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 56,
                    decoration: BoxDecoration(
                      color: mq.background,
                      borderRadius: BorderRadius.circular(
                        MqTheme.radiusSmall,
                      ),
                      border: Border.all(color: mq.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: cast.thumbnail.isEmpty
                        ? Center(
                            child: MqIcon(
                              'user-smile-line',
                              size: 18,
                              color: mq.textTertiary,
                            ),
                          )
                        : LocalImage(cast.thumbnail),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cast.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: mq.textPrimary,
                            fontSize: MqTheme.fontBody,
                            fontWeight: FontWeight.w600,
                            height: MqTheme.lineTight,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          cast.prompt.trim().isEmpty
                              ? tr('Described by its references.')
                              : cast.prompt.trim(),
                          maxLines: 2,
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
                  const SizedBox(width: MqTheme.gap),
                  MqLink(text: tr('Replace'), onPressed: onReplace),
                  const SizedBox(width: 6),
                  MqIconButton(
                    icon: 'close-line',
                    tip: tr('Take it off this ad'),
                    destructive: true,
                    onPressed: onRemove,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
