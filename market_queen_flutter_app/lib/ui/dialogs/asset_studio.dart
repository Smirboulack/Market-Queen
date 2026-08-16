import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../../models/ad_project.dart';
import '../../models/asset_library.dart';
import '../../models/image_forge.dart';
import '../../models/prompt_doctor.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chip.dart';
import '../widgets/fields.dart';
import '../widgets/media_drop.dart';
import '../widgets/model_picker.dart';
import '../widgets/mq_dialog.dart';

/// Making an actor or a scene out of a description.
///
/// It is a conversation, not a form. You say who they are, three of them come
/// back, you pick one or say what to change and three more come back off the
/// one you picked. That last part is the whole point: the picture you chose
/// goes back in as the reference for the next round, which is what makes it
/// possible to land a face and *then* put it in a kitchen, rather than
/// re-rolling the dice and hoping the face survives.
///
/// Returns the id of what was saved, or null if the user backed out.
Future<String?> showAssetStudio(
  BuildContext context, {
  required AppState app,
  required AssetKind kind,
  LibraryAsset? asset,
}) {
  return showMqModal<String>(
    context: context,
    // Half an hour of iterating must not be thrown away by a stray click on
    // the backdrop.
    dismissible: false,
    child: _Studio(app: app, kind: kind, asset: asset),
  );
}

/// One press of Generate: what was asked for, and what came back.
class _Round {
  _Round(this.prompt, this.images);

  final String prompt;
  final List<String> images;
}

class _Studio extends StatefulWidget {
  const _Studio({required this.app, required this.kind, this.asset});

  final AppState app;
  final AssetKind kind;

  /// Set when an existing actor or scene is being re-shot rather than made.
  final LibraryAsset? asset;

  @override
  State<_Studio> createState() => _StudioState();
}

class _StudioState extends State<_Studio> {
  late final LibraryAsset _draft =
      widget.asset?.copy() ?? LibraryAsset(name: _library.suggestedName());

  late final TextEditingController _name = TextEditingController(
    text: _draft.name,
  );
  final TextEditingController _prompt = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();

  /// Everything asked for this session, oldest first.
  final List<_Round> _rounds = [];

  /// Pictures the user dropped in as a starting point. Separate from the
  /// picture they have chosen: the reference is what they brought, the choice
  /// is what the model made of it.
  final List<String> _references = [];

  /// Whether the batch in the air has already been filed into a round.
  bool _awaiting = false;

  bool get _isActor => widget.kind == AssetKind.actor;

  AssetLibrary get _library => _isActor ? widget.app.actors : widget.app.scenes;

  ImageForge get _forge =>
      _isActor ? widget.app.actorForge : widget.app.sceneForge;

  /// How many come back per press. Three fills a row and is enough to see the
  /// model's range without tripling the bill of a single try.
  static const int _perRound = 3;

  @override
  void initState() {
    super.initState();
    _forge.reset();
    _forge.addListener(_onForge);
    _prompt.addListener(_repaint);
  }

  @override
  void dispose() {
    _forge.removeListener(_onForge);
    _prompt
      ..removeListener(_repaint)
      ..dispose();
    _name.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  /// Files a finished batch as a round of its own.
  ///
  /// The forge keeps only the newest batch, so the history has to be copied out
  /// of it as each one lands -- otherwise pressing Generate a second time wipes
  /// the row you were still choosing from.
  void _onForge() {
    if (!mounted) return;

    if (_awaiting && !_forge.running && _forge.images.isNotEmpty) {
      _awaiting = false;
      _rounds.add(_Round(_lastAsked, List.of(_forge.images)));
      // The newest row is the one being chosen from.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      });
    }

    setState(() {});
  }

  String _lastAsked = '';

  // ---- generating ----------------------------------------------------------

  /// What is actually sent. The realism scaffold does the heavy lifting; the
  /// user's sentence is the subject inside it.
  String _fullPrompt(String description) {
    final casting = widget.app.casting;
    if (_isActor) {
      return casting.buildPortraitPrompt(description: description);
    }
    return casting.buildScenePrompt(
      description: description,
      tweaks: AdProject.sceneTweakFragments(_draft),
    );
  }

  /// The picture the next round is built on: the one currently chosen, or
  /// failing that whatever the user brought in.
  List<String> get _seed => [
    if (_draft.previewPath.isNotEmpty) _draft.previewPath,
    ..._references,
  ];

  void _generate() {
    final asked = _prompt.text.trim();
    if (asked.isEmpty && _seed.isEmpty) return;

    _lastAsked = asked;
    _awaiting = true;
    _prompt.clear();

    _forge.generate(
      prompt: _fullPrompt(asked),
      aspectRatio: _aspect,
      references: _seed,
      count: _perRound,
    );
  }

  String get _aspect {
    final saved = widget.app.settings.prefString('assetAspect');
    // Both are shot vertical by default, because the ad is.
    return saved.isEmpty ? '9:16' : saved;
  }

  /// The wand, on the same key as the composer's: a description of a person or
  /// a place is a prompt like any other, and this is the one screen where a
  /// vague one costs three pictures to find out about.
  Widget _improveButton() {
    final doctor = widget.app.promptDoctor;
    final rewriter = doctor.writer;

    return ListenableBuilder(
      listenable: doctor,
      builder: (context, _) => MqIconButton(
        icon: doctor.busy ? 'loader-4-line' : 'sparkling-line',
        tip: !rewriter.exists
            ? tr('Add a key for a writer under API keys to improve prompts.')
            //: %1 is a model name, %2 an account such as "OpenAI"
            : tr(
                'Improve this prompt with %1 — billed to your %2 account',
              ).arg(rewriter.label).arg(rewriter.account),
        size: 32,
        enabled: rewriter.exists && !doctor.busy,
        onPressed: _improve,
      ),
    );
  }

  Future<void> _improve() async {
    final improved = await widget.app.promptDoctor.improve(
      prompt: _prompt.text,
      kind: _isActor ? PromptKind.actor : PromptKind.scene,
    );
    if (!mounted || improved.isEmpty) return;

    _prompt.value = TextEditingValue(
      text: improved,
      selection: TextSelection.collapsed(offset: improved.length),
    );
  }

  Future<void> _browse() async {
    final files = await openFiles(acceptedTypeGroups: const [imageTypeGroup]);
    _addReferences([for (final file in files) file.path]);
  }

  void _addReferences(List<String> paths) {
    setState(() {
      for (final path in paths) {
        if (path.isEmpty || isVideoPath(path) || _references.contains(path)) {
          continue;
        }
        _references.add(path);
      }
    });
  }

  void _save() {
    _draft
      ..name = _name.text.trim()
      ..prompt = _describe();
    _draft.media
      ..clear()
      ..addAll(_references);

    final id = _library.save(_draft);
    if (mounted) closeMqModal(context, id);
  }

  /// What the asset is described by, once it is saved: everything that was
  /// asked for, in order. It is what the search box matches on and what the
  /// pipeline is handed, so a face refined over four rounds is not filed under
  /// the last three words the user typed.
  String _describe() {
    final asked = [
      for (final round in _rounds)
        if (round.prompt.trim().isNotEmpty) round.prompt.trim(),
    ];
    return asked.isEmpty ? _draft.prompt : asked.join('. ');
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 120).clamp(520.0, 880.0);
    final height = (screen.height - 200).clamp(300.0, 460.0);
    final chosen = _draft.previewPath.isNotEmpty;

    return MqModalCard(
      width: width,
      title: _isActor ? tr('Define your actor') : tr('Define your scene'),
      subtitle: _isActor
          ? tr(
              'Describe them, pick the one that is closest, then say what to '
              'change.',
            )
          : tr(
              'Describe it, pick the one that is closest, then say what to '
              'change.',
            ),
      actions: [
        // Flexible rather than 200 wide: the two buttons beside it are as long
        // as whatever language the app is in makes them, and a fixed field is
        // what pushed the row off the end of the card in French.
        Expanded(
          child: LabeledField(
            controller: _name,
            placeholder: _library.suggestedName(),
          ),
        ),
        GhostButton(text: tr('Cancel'), onPressed: () => closeMqModal(context)),
        PrimaryButton(
          text: _isActor ? tr('Select this actor') : tr('Select this scene'),
          enabled: chosen,
          tooltip: chosen ? '' : tr('Pick one of the pictures first.'),
          onPressed: _save,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: height,
            child: _rounds.isEmpty && !_forge.running
                ? _EmptyStudio(isActor: _isActor)
                : _conversation(),
          ),
          const SizedBox(height: MqTheme.gap),
          _promptBar(),
        ],
      ),
    );
  }

  Widget _conversation() {
    return SingleChildScrollView(
      controller: _scroll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final round in _rounds) ...[
            if (round.prompt.isNotEmpty) _Asked(text: round.prompt),
            const SizedBox(height: 10),
            _Candidates(
              paths: round.images,
              chosen: _draft.previewPath,
              onPicked: (path) => setState(() => _draft.previewPath = path),
            ),
            const SizedBox(height: MqTheme.gapLarge),
          ],
          if (_forge.running) ...[
            if (_lastAsked.isNotEmpty) _Asked(text: _lastAsked),
            const SizedBox(height: 10),
            _Candidates(paths: const [], chosen: '', onPicked: (_) {}),
            const SizedBox(height: 8),
            Text(
              //: %1 and %2 are counts of pictures
              tr(
                'Generating… %1 of %2',
              ).arg(_forge.received).arg(_forge.requested),
              style: TextStyle(
                color: context.mq.textTertiary,
                fontSize: MqTheme.fontSmall,
              ),
            ),
          ],
          if (_forge.error.isNotEmpty)
            Text(
              _forge.error,
              style: TextStyle(
                color: context.mq.error,
                fontSize: MqTheme.fontSmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _promptBar() {
    final mq = context.mq;
    final cost = _forge.estimate(_perRound);
    final ready = _prompt.text.trim().isNotEmpty || _seed.isNotEmpty;

    return DropTarget(
      onDragDone: (detail) =>
          _addReferences([for (final file in detail.files) file.path]),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
        decoration: BoxDecoration(
          color: mq.surfaceSecondary,
          borderRadius: BorderRadius.circular(MqTheme.radius),
          border: Border.all(color: mq.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_references.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _references.length; ++i)
                    MediaTile(
                      path: _references[i],
                      size: 46,
                      onRemove: () => setState(() => _references.removeAt(i)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, maxHeight: 120),
              // Enter generates and Shift+Enter breaks the line, the same way
              // round as the composer's own bar.
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter): () {
                    if (!_forge.running) _generate();
                  },
                },
                child: TextField(
                  controller: _prompt,
                  focusNode: _focus,
                  maxLines: null,
                  cursorColor: mq.primary,
                  style: TextStyle(
                    color: mq.textPrimary,
                    fontSize: MqTheme.fontBody,
                    height: MqTheme.lineBody,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: _rounds.isEmpty
                        ? (_isActor
                              ? tr(
                                  'Young adult, fitness coach, plain grey '
                                  't-shirt…',
                                )
                              : tr(
                                  'A small kitchen, morning light, worktop a '
                                  'little cluttered…',
                                ))
                        : tr('Say what to change…'),
                    hintStyle: TextStyle(
                      color: mq.textTertiary,
                      fontSize: MqTheme.fontBody,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                // Wrapped and flexible: the model chip carries whatever the
                // provider called the model, and one long name must push the
                // row onto a second line rather than off the end of the card.
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      MqIconButton(
                        icon: 'image-add-line',
                        tip: tr('Add a reference picture'),
                        size: 32,
                        onPressed: _browse,
                      ),
                      _improveButton(),
                      MqPickChip(
                        label: tr('Format'),
                        value: _aspect,
                        options: [
                          MenuOption(tr('Vertical 9:16'), '9:16'),
                          MenuOption(tr('Square 1:1'), '1:1'),
                          MenuOption(tr('Wide 16:9'), '16:9'),
                        ],
                        onPicked: (value) => setState(
                          () =>
                              widget.app.settings.setPref('assetAspect', value),
                        ),
                      ),
                      // Bring your own keys means bringing your own model: the
                      // one this will be bought from is named here, next to the
                      // button that buys it.
                      ModelChip(app: widget.app, category: 'image'),
                    ],
                  ),
                ),
                const SizedBox(width: MqTheme.gap),
                if (_forge.running)
                  GhostButton(
                    text: tr('Cancel'),
                    destructive: true,
                    onPressed: _forge.cancel,
                  )
                else
                  GhostButton(
                    text: cost.known
                        //: %1 is a price
                        ? tr('Generate — %1').arg(Format.estimated(cost.amount))
                        : tr('Generate'),
                    enabled: ready,
                    onPressed: _generate,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Nothing generated yet: three empty frames and one sentence.
class _EmptyStudio extends StatelessWidget {
  const _EmptyStudio({required this.isActor});

  final bool isActor;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
            children: [
              for (var i = 0; i < 3; ++i) ...[
                if (i > 0) const SizedBox(width: MqTheme.gap),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: mq.surfaceSecondary,
                      borderRadius: BorderRadius.circular(MqTheme.radius),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: MqTheme.gapLarge),
        Text(
          tr("Let's start"),
          style: TextStyle(
            color: mq.textPrimary,
            fontSize: MqTheme.fontTitle,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            isActor
                ? tr(
                    'Write who they are underneath. Add a picture to work '
                    'from if you have one, and press Generate.',
                  )
                : tr(
                    'Write where it is underneath. Add a picture to work '
                    'from if you have one, and press Generate.',
                  ),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontSmall,
              height: MqTheme.lineBody,
            ),
          ),
        ),
      ],
    );
  }
}

/// What was asked for, on the right, the way a sent message reads.
class _Asked extends StatelessWidget {
  const _Asked({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: mq.surfaceSecondary,
            borderRadius: BorderRadius.circular(MqTheme.radius),
            border: Border.all(color: mq.border),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: mq.textPrimary,
              fontSize: MqTheme.fontLabel,
              height: MqTheme.lineBody,
            ),
          ),
        ),
      ),
    );
  }
}

/// One round's pictures, side by side. An empty list draws the placeholders a
/// batch in the air will fill.
class _Candidates extends StatelessWidget {
  const _Candidates({
    required this.paths,
    required this.chosen,
    required this.onPicked,
  });

  final List<String> paths;
  final String chosen;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final count = paths.isEmpty ? 3 : paths.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Choose one'),
          style: TextStyle(color: mq.textTertiary, fontSize: MqTheme.fontSmall),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < count; ++i) ...[
              if (i > 0) const SizedBox(width: MqTheme.gap),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: i < paths.length
                      ? _Candidate(
                          path: paths[i],
                          chosen: paths[i] == chosen,
                          onTap: () => onPicked(paths[i]),
                        )
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            color: mq.surfaceSecondary,
                            borderRadius: BorderRadius.circular(MqTheme.radius),
                          ),
                        ),
                ),
              ),
            ],
            // A short row keeps the tiles the same size as a full one.
            for (var i = count; i < 3; ++i) ...[
              const SizedBox(width: MqTheme.gap),
              const Expanded(child: SizedBox.shrink()),
            ],
          ],
        ),
      ],
    );
  }
}

class _Candidate extends StatelessWidget {
  const _Candidate({
    required this.path,
    required this.chosen,
    required this.onTap,
  });

  final String path;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      snap: true,
      focusRadius: MqTheme.radius,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        decoration: BoxDecoration(
          color: mq.background,
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
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            LocalImage(path),
            if (chosen)
              PositionedDirectional(
                end: 6,
                top: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: mq.primary,
                    shape: BoxShape.circle,
                  ),
                  child: MqIcon('check-line', size: 14, color: mq.onPrimary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- the other door --------------------------------------------------------

/// Turning a picture the user already has into an actor or a scene.
///
/// Nothing is generated and nothing is bought: the file becomes the still, and
/// that still is what every shot is built on. Returns the id, or null.
Future<String?> showAssetImport(
  BuildContext context, {
  required AppState app,
  required AssetKind kind,
}) {
  return showMqModal<String>(
    context: context,
    dismissible: false,
    child: _Import(app: app, kind: kind),
  );
}

class _Import extends StatefulWidget {
  const _Import({required this.app, required this.kind});

  final AppState app;
  final AssetKind kind;

  @override
  State<_Import> createState() => _ImportState();
}

class _ImportState extends State<_Import> {
  late final TextEditingController _name = TextEditingController(
    text: _library.suggestedName(),
  );
  final TextEditingController _description = TextEditingController();

  String _picture = '';

  bool get _isActor => widget.kind == AssetKind.actor;

  AssetLibrary get _library => _isActor ? widget.app.actors : widget.app.scenes;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    final id = _library.save(
      LibraryAsset(
        name: _name.text.trim(),
        prompt: _description.text.trim(),
        previewPath: _picture,
        media: [_picture],
      ),
    );
    closeMqModal(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return MqModalCard(
      width: 620,
      title: _isActor
          ? tr('Turn a picture into an actor')
          : tr('Turn a picture into a scene'),
      subtitle: tr(
        'Nothing is generated here. The file you hand over is the '
        'picture every shot is built on.',
      ),
      actions: [
        GhostButton(text: tr('Cancel'), onPressed: () => closeMqModal(context)),
        PrimaryButton(
          text: _isActor ? tr('Create the actor') : tr('Create the scene'),
          enabled: _picture.isNotEmpty,
          tooltip: _picture.isEmpty ? tr('Choose a picture first.') : '',
          onPressed: _save,
        ),
      ],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 186,
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: _picture.isEmpty
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: mq.surfaceSecondary,
                        borderRadius: BorderRadius.circular(MqTheme.radius),
                        border: Border.all(color: mq.border),
                      ),
                      child: Center(
                        child: MqIcon(
                          _isActor ? 'user-smile-line' : 'scene-line',
                          size: 24,
                          color: mq.textTertiary,
                        ),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(MqTheme.radius),
                        border: Border.all(color: mq.borderStrong),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: LocalImage(_picture),
                    ),
            ),
          ),
          const SizedBox(width: MqTheme.gapLarge),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MediaDropZone(
                  paths: _picture.isEmpty ? const [] : [_picture],
                  title: tr('Drop a picture in'),
                  hint: tr('PNG, JPG or WebP.'),
                  tileSize: 56,
                  onAdded: (paths) {
                    final picture = paths.firstWhere(
                      (path) => !isVideoPath(path),
                      orElse: () => '',
                    );
                    if (picture.isNotEmpty) {
                      setState(() => _picture = picture);
                    }
                  },
                  onRemoved: (_) => setState(() => _picture = ''),
                ),
                const SizedBox(height: MqTheme.gap),
                LabeledField(controller: _name, label: tr('Name')),
                const SizedBox(height: MqTheme.gap),
                LabeledArea(
                  controller: _description,
                  label: tr('Description (optional)'),
                  areaHeight: 64,
                  placeholder: _isActor
                      ? tr('A woman in her twenties, no make-up…')
                      : tr('A small bathroom, one window…'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
