import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../../models/asset_library.dart';
import '../../models/canvas_feed.dart';
import '../../models/studio_runner.dart';
import '../dialogs/asset_gallery.dart';
import '../dialogs/confirm_generation.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chip.dart';
import '../widgets/media_drop.dart';
import 'cast_panels.dart';
import 'composer_tabs.dart';

/// The bar the whole studio is driven from.
///
/// One object with a tab across the top of it, in place of the two folding
/// panels and the settings rail that used to surround the canvas. What it can
/// make -- a talking actor, a clip, a still, a read, subtitles, a bigger
/// picture -- is a row of pills, and the rest of the bar reshapes itself under
/// whichever one is lit. That is the whole model: one prompt, one send button,
/// and a column of settings that only appears when asked for.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.app,
    required this.onGenerateAd,
  });

  final AppState app;

  /// Runs the full pipeline. It stays outside this widget because the window
  /// owns the run -- the composer only says when.
  final VoidCallback onGenerateAd;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> with TickerProviderStateMixin {
  late final AnimationController _spinner = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// One controller per tab, so switching to check a setting and coming back
  /// does not lose a half-written prompt.
  final Map<ComposerTab, TextEditingController> _prompts = {
    for (final tab in ComposerTab.values) tab: TextEditingController(),
  };

  /// What was dropped into the bar, per tab. Session-local on purpose: a
  /// reference is part of the request you are composing, not part of the ad.
  final Map<ComposerTab, List<String>> _references = {
    for (final tab in ComposerTab.values) tab: <String>[],
  };

  final FocusNode _focus = FocusNode();

  /// The panel beside the bar. Wide enough for "Kling 3.0 Turbo Pro" without an
  /// ellipsis, which is about the longest thing that lands in it.
  static const double _panelWidth = 320;

  /// What that panel costs when it stands beside the bar: itself, plus the same
  /// again mirrored on the left so the bar's centre is the page's centre.
  static const double _gutter = _panelWidth + MqTheme.gap;

  /// The bar stops widening here. Past it the send button ends up at the far
  /// edge of a 27" monitor while the caret is in the middle of the screen, and
  /// a prompt bar you have to travel to is a prompt bar you stop using.
  static const double _barMaxWidth = 1180;

  /// The narrowest the bar is allowed to be while a panel stands beside it.
  ///
  /// Below this the layout changes shape rather than shrinking: the panel comes
  /// out of the row and sits above the bar instead. Squeezing was the wrong
  /// answer twice over -- the prompt ended up narrower than a paragraph, and the
  /// panel's own rows ended up as a label and an ellipsis.
  static const double _barComfortable = 640;

  /// How much room the prompt gets before it has anything in it. The same on
  /// every tab, so the bar is one shape.
  static const double _fieldMinHeight = 104;

  ComposerTab _tab = ComposerTab.actors;

  /// The advanced modes taken out of "See more", in the order they were added.
  /// They sit on the pill row beside the three permanent ones until they are
  /// put away again.
  final List<ComposerTab> _extras = [];

  /// Which of the three panels is showing, if any. They share one slot because
  /// they answer one question -- "what exactly is about to be generated" -- and
  /// two of them open at once would be two answers.
  _Panel _panel = _Panel.none;

  bool _hovered = false;
  bool _dragging = false;

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_repaint);
    for (final controller in _prompts.values) {
      controller.addListener(_repaint);
    }

    // The script tab writes straight into the ad, so it starts from it and
    // follows it when a different ad is opened underneath.
    _prompts[ComposerTab.actors]!.text = app.project.script;
    app.project.reloaded.addListener(_onAdChanged);
    app.pipeline.finished.listen(_onAdFinished);
  }

  @override
  void dispose() {
    app.project.reloaded.removeListener(_onAdChanged);
    app.pipeline.finished.remove(_onAdFinished);
    _focus.removeListener(_repaint);
    _focus.dispose();
    for (final controller in _prompts.values) {
      controller
        ..removeListener(_repaint)
        ..dispose();
    }
    _spinner.dispose();
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  void _onAdChanged() {
    if (!mounted) return;
    setState(() => _prompts[ComposerTab.actors]!.text = app.project.script);
  }

  // ---- the ad the pipeline is shooting -------------------------------------

  /// The feed tile the running pipeline will fill. Held rather than looked up,
  /// because `finished` also fires for a single-shot reshoot and only the batch
  /// this composer started should be settled by it.
  CanvasBatch? _adBatch;

  void _onAdFinished(({bool success, String outputFile}) result) {
    final batch = _adBatch;
    if (batch == null) return;
    _adBatch = null;

    app.project.feed.settle(
      batch.id,
      batch.items.first.id,
      status: result.success ? CanvasStatus.done : CanvasStatus.failed,
      path: result.outputFile,
      error: result.success ? '' : tr('The render did not finish. See the log.'),
    );
  }

  // ---- sending -------------------------------------------------------------

  TextEditingController get _prompt => _prompts[_tab]!;

  /// What is attached to the bar on this tab.
  ///
  /// The talking-actor tab reads and writes the ad's own reference media rather
  /// than a session list: a photo of the product is part of the ad -- the
  /// pipeline hands it to the frame model -- and it has to still be there
  /// tomorrow. Every other tab is composing a one-off request, so its
  /// references live and die with it.
  List<String> get _refs =>
      _tab == ComposerTab.actors ? app.project.media : _references[_tab]!;

  ComposerSpec get _spec => ComposerSpec.of(_tab);

  int get _count {
    if (!_spec.batched) return 1;
    final saved = app.settings.pref<int>('${_spec.category}Count', 0) ?? 0;
    return saved < 1 ? 1 : (saved > _spec.maxCount ? _spec.maxCount : saved);
  }

  void _setCount(int value) {
    final clamped = value.clamp(1, _spec.maxCount);
    app.settings.setPref('${_spec.category}Count', clamped);
    setState(() {});
  }

  int get _seconds {
    final saved = app.settings.pref<int>('videoSeconds', 0) ?? 0;
    return saved < 1 ? 5 : saved;
  }

  String get _aspect {
    final saved = app.settings.prefString('${_spec.category}Aspect');
    return saved.isEmpty ? app.project.aspectRatio : saved;
  }

  /// Whether the send button is live, and why not when it is not.
  ({bool ready, String reason}) get _readiness {
    final project = app.project;

    switch (_tab) {
      case ComposerTab.actors:
        if (app.pipeline.running) {
          return (ready: false, reason: tr('An ad is already being shot.'));
        }
        if (project.complete) return (ready: true, reason: '');
        return (
          ready: false,
          //: %1 is a list like "an actor, a script"
          reason: tr('Still needs %1.').arg(project.missing.join(', ')),
        );

      case ComposerTab.captions:
        return _refs.any(isVideoPath)
            ? (ready: true, reason: '')
            : (ready: false, reason: tr('Drop in the clip to subtitle.'));

      case ComposerTab.upscale:
        return _refs.any((path) => !isVideoPath(path))
            ? (ready: true, reason: '')
            : (ready: false, reason: tr('Drop in the picture to enlarge.'));

      default:
        return _prompt.text.trim().isEmpty
            ? (ready: false, reason: tr('Write a prompt first.'))
            : (ready: true, reason: '');
    }
  }

  Future<void> _send() async {
    if (!_readiness.ready) return;

    switch (_tab) {
      case ComposerTab.actors:
        _shootAd();
      case ComposerTab.captions:
        await app.runner.burnCaptions(
          videoPath: _refs.firstWhere(isVideoPath),
        );
        setState(_refs.clear);
      case ComposerTab.upscale:
        await app.runner.send(
          GenerationOrder(
            kind: CanvasKind.image,
            category: 'upscale',
            prompt: _prompt.text.trim(),
            references: [_refs.firstWhere((path) => !isVideoPath(path))],
            aspectRatio: '',
            count: 1,
          ),
        );
        setState(_refs.clear);
      default:
        await _sendPrompted();
    }
  }

  Future<void> _sendPrompted() async {
    final order = GenerationOrder(
      kind: _spec.kind,
      category: _spec.category,
      prompt: _prompt.text.trim(),
      references: List.of(_refs),
      aspectRatio: _aspect,
      seconds: _seconds,
      count: _count,
      voiceSource: _tab == ComposerTab.audio ? app.request() : const {},
      resolution: app.settings.prefString('videoResolution'),
      audio: app.settings.pref<bool>('videoAudio', true) ?? true,
    );

    // Only video asks twice. It is the only kind where one careless press is
    // worth dollars rather than cents.
    if (_tab == ComposerTab.video) {
      final go = await confirmGeneration(context, app: app, order: order);
      if (!go) return;
    }

    await app.runner.send(order);
  }

  /// Puts a pending ad in the feed and starts the pipeline behind it.
  void _shootAd() {
    final batch = CanvasBatch(
      id: CanvasFeed.newId(),
      kind: CanvasKind.ad,
      prompt: app.project.script.trim(),
      createdAt: DateTime.now(),
      modelLabel: app.runner.modelLabel('avatar'),
      aspectRatio: app.project.aspectRatio,
      items: [CanvasItem(id: CanvasFeed.newId())],
    );
    app.project.feed.add(batch);
    _adBatch = batch;

    widget.onGenerateAd();
  }

  // ---- references ----------------------------------------------------------

  Future<void> _browse() async {
    final files = await openFiles(acceptedTypeGroups: const [mediaTypeGroup]);
    if (files.isEmpty) return;
    _addReferences([for (final file in files) file.path]);
  }

  void _addReferences(List<String> paths) {
    if (_tab == ComposerTab.actors) {
      // Through the ad, which de-duplicates, normalises file:// URLs and marks
      // itself dirty so the reference is saved with the document.
      app.project.addMedia(paths);
      return;
    }

    setState(() {
      for (final path in paths) {
        if (path.isEmpty || _refs.contains(path)) continue;
        // The single-source tabs take one file and replace it rather than
        // collecting a pile nobody can tell apart.
        if (!_spec.multipleReferences) _refs.clear();
        _refs.add(path);
        if (!_spec.multipleReferences) break;
      }
    });
  }

  void _removeReference(int index) {
    if (_tab == ComposerTab.actors) {
      app.project.removeMedia(index);
      return;
    }
    setState(() => _refs.removeAt(index));
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        app.project,
        app.pipeline,
        app.runner,
        app.settings,
        // A model schema arriving turns the Length menu from two guesses into
        // the model's real list, so the column has to hear about it.
        app.falSchemas,
      ]),
      // The panels live beside the bar rather than inside it: they are read
      // once and the prompt is rewritten twenty times, so they must not take
      // room from it. Two rules hold the row together, and one changes shape:
      //
      //  - the panel is the third child of one row, hung off a shared bottom
      //    edge by [CrossAxisAlignment.end], so it grows upward instead of
      //    leaving the bar floating with a hole underneath it;
      //  - the whole row is bottom-anchored over the canvas by the page, so a
      //    tall panel takes its room from empty background rather than from the
      //    feed. Opening one moves nothing;
      //  - and when the window cannot afford a column beside a readable bar,
      //    the panel comes out of the row and stacks above it instead. See
      //    [_wideEnough]: the prompt keeps the whole width either way, which is
      //    the point -- a permanently half-width prompt bar to hold room for a
      //    panel that is shut nine tenths of the time is a bad trade.
      //
      // The tab row lives inside the bar's own column rather than above the
      // whole thing, so it stays centred on the bar.
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final beside = _open && _wideEnough(constraints.maxWidth);
          final gutter = beside ? _gutter : 0.0;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(width: gutter),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _barMaxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_open && !beside) ...[
                          _panelBody(),
                          const SizedBox(height: MqTheme.gap),
                        ],
                        Center(
                          child: ComposerTabBar(
                            current: _tab,
                            extras: _extras,
                            onPicked: _pickTab,
                            onRemoved: _dropTab,
                          ),
                        ),
                        const SizedBox(height: MqTheme.gap),
                        _bar(),
                      ],
                    ),
                  ),
                ),
              ),
              if (beside)
                SizedBox(
                  width: gutter,
                  child: Padding(
                    padding: const EdgeInsets.only(left: MqTheme.gap),
                    child: _panelBody(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  bool get _open => _panel != _Panel.none;

  /// Whether a column beside the bar still leaves a bar worth typing in.
  bool _wideEnough(double width) => width - 2 * _gutter >= _barComfortable;

  void _show(_Panel panel) =>
      setState(() => _panel = _panel == panel ? _Panel.none : panel);

  /// Whichever panel is open, in the slot the layout gave it.
  Widget _panelBody() {
    void close() => setState(() => _panel = _Panel.none);

    return switch (_panel) {
      _Panel.none => const SizedBox.shrink(),
      _Panel.settings => ComposerSettings(app: app, tab: _tab, onClose: close),
      _Panel.actor => CastPanel(
        app: app,
        kind: AssetKind.actor,
        onClose: close,
        onReplace: () => _cast(AssetKind.actor),
      ),
      _Panel.scene => CastPanel(
        app: app,
        kind: AssetKind.scene,
        onClose: close,
        onReplace: () => _cast(AssetKind.scene),
      ),
    };
  }

  /// A pill was pressed, or a mode was chosen out of "See more". Either way the
  /// composer switches to it; an advanced one also earns a pill of its own.
  void _pickTab(ComposerTab tab) {
    setState(() {
      _tab = tab;
      if (ComposerSpec.secondary.contains(tab) && !_extras.contains(tab)) {
        _extras.add(tab);
      }
    });
  }

  /// The cross on an advanced pill. Putting away the mode you are standing in
  /// falls back to the talking actor, which is where the studio starts.
  void _dropTab(ComposerTab tab) {
    setState(() {
      _extras.remove(tab);
      if (_tab == tab) _tab = ComposerTab.actors;
    });
  }

  Widget _bar() {
    final mq = context.mq;

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        _addReferences([for (final file in detail.files) file.path]);
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: _focus.hasFocus || _hovered || _dragging
              ? Duration.zero
              : MqTheme.hoverDuration,
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
          decoration: BoxDecoration(
            color: mq.surface,
            borderRadius: BorderRadius.circular(MqTheme.radiusLarge),
            border: Border.all(
              // Focus darkens the outline by one step and does nothing else.
              // It used to tint it and lay a coloured halo behind it, which put
              // the loudest object on the page around an empty text box.
              color: _dragging
                  ? mq.textTertiary
                  : _focus.hasFocus
                  ? mq.borderStrong
                  : _hovered
                  ? mq.borderStrong
                  : mq.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_spec.prompted) _field(),
              if (_refs.isNotEmpty) ...[
                if (_spec.prompted) const SizedBox(height: 10),
                _referenceRow(),
              ],
              if (!_spec.prompted && _refs.isEmpty) _dropInvitation(),
              const SizedBox(height: 10),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field() {
    final mq = context.mq;

    return ConstrainedBox(
      // One floor for every tab, and it is the script's. A 44px prompt and an
      // 84px one are two differently sized objects in the same place on the
      // page, and switching between them made the bar jump; the taller of the
      // two is also the one that invites a sentence rather than three words.
      constraints: const BoxConstraints(minHeight: _fieldMinHeight, maxHeight: 220),
      // Enter breaks the line; Ctrl+Enter sends. The other way round is the
      // chat convention and it is wrong here -- every send costs money, and a
      // prompt is a paragraph rather than a message.
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): DoNothingIntent(),
          SingleActivator(LogicalKeyboardKey.enter, control: true):
              _SendIntent(),
          SingleActivator(LogicalKeyboardKey.enter, meta: true): _SendIntent(),
        },
        child: Actions(
          actions: {
            _SendIntent: CallbackAction<_SendIntent>(
              onInvoke: (_) {
                _send();
                return null;
              },
            ),
          },
          child: TextField(
            controller: _prompt,
            focusNode: _focus,
            maxLines: null,
            onChanged: _tab == ComposerTab.actors
                ? app.project.setScript
                : null,
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
              hintText: _spec.placeholder,
              hintStyle: TextStyle(
                color: mq.textTertiary,
                fontSize: MqTheme.fontBody,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// What the two source-only tabs show in place of a prompt.
  Widget _dropInvitation() {
    final mq = context.mq;

    return Pressable(
      onTap: _browse,
      focusRadius: MqTheme.radius,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        height: _fieldMinHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: states.active ? mq.surfaceHover : mq.surfaceSecondary,
          borderRadius: BorderRadius.circular(MqTheme.radius),
          border: Border.all(
            color: states.active ? mq.borderStrong : mq.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MqIcon('image-add-line', size: 18, color: mq.textTertiary),
            const SizedBox(width: 10),
            Text(
              _spec.placeholder,
              style: TextStyle(
                color: mq.textSecondary,
                fontSize: MqTheme.fontLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _referenceRow() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < _refs.length; ++i)
          MediaTile(
            path: _refs[i],
            size: 54,
            onRemove: () => _removeReference(i),
          ),
      ],
    );
  }

  Widget _footer() {
    final mq = context.mq;
    final readiness = _readiness;
    final busy = _tab == ComposerTab.actors && app.pipeline.running;

    if (busy && !_spinner.isAnimating) {
      _spinner.repeat();
    } else if (!busy && _spinner.isAnimating) {
      _spinner
        ..stop()
        ..value = 0;
    }

    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: _leadingActions(),
          ),
        ),
        const SizedBox(width: MqTheme.gap),
        if (_spec.batched) ...[
          _Stepper(
            value: _count,
            max: _spec.maxCount,
            onChanged: _setCount,
          ),
          const SizedBox(width: 10),
        ],
        MqIconButton(
          icon: 'equalizer-line',
          tip: _panel == _Panel.settings
              ? tr('Hide the settings')
              : tr('Settings'),
          size: 32,
          onPressed: () => _show(_Panel.settings),
        ),
        const SizedBox(width: 8),
        Container(width: 1, height: 24, color: mq.divider),
        const SizedBox(width: 10),
        GradientSendButton(
          enabled: readiness.ready,
          busy: busy,
          spinner: _spinner,
          tooltip: readiness.ready
              ? tr('Generate  ·  Ctrl+Enter')
              : readiness.reason,
          onPressed: _send,
        ),
      ],
    );
  }

  /// The buttons on the left of the footer. They are the tab's own: casting an
  /// actor belongs to the ad, attaching a reference belongs to a prompt, and
  /// neither means anything on the other's tab.
  List<Widget> _leadingActions() {
    if (_tab == ComposerTab.actors) {
      final project = app.project;
      final actor = project.actorIds.isEmpty
          ? null
          : app.actors.byId(project.actorIds.first);
      final scene = app.scenes.byId(project.sceneId);

      return [
        // Empty, the chip opens the gallery. Cast, it opens that actor's own
        // panel -- the voice and the four dials the read is shaped with -- and
        // swapping them is a button inside it. Which way round is deliberate:
        // once somebody is cast you tune them twenty times and replace them
        // once.
        _CastChip(
          label: tr('Add an actor'),
          emptyIcon: 'user-add-line',
          name: actor?.name ?? '',
          portrait: actor?.thumbnail ?? '',
          clearTip: tr('Take this actor off the ad'),
          lit: _panel == _Panel.actor,
          onPressed: actor == null
              ? () => _cast(AssetKind.actor)
              : () => _show(_Panel.actor),
          onCleared: () {
            project.clearActor();
            if (_panel == _Panel.actor) setState(() => _panel = _Panel.none);
          },
        ),
        _CastChip(
          label: tr('Add a scene'),
          emptyIcon: 'scene-line',
          name: scene?.name ?? '',
          portrait: scene?.thumbnail ?? '',
          clearTip: tr('Take this scene off the ad'),
          lit: _panel == _Panel.scene,
          onPressed: scene == null
              ? () => _cast(AssetKind.scene)
              : () => _show(_Panel.scene),
          onCleared: () {
            project.clearScene();
            if (_panel == _Panel.scene) setState(() => _panel = _Panel.none);
          },
        ),
        // The product itself. An ad is usually *about* something, and the
        // frame model can only put it on screen if it has been shown it --
        // until this button existed the only way in was the drag-and-drop
        // nobody discovers.
        MqIconButton(
          icon: 'attachment-line',
          tip: tr('Attach a photo or a clip of the product'),
          size: 32,
          onPressed: _browse,
        ),
      ];
    }

    if (!_spec.takesReferences) return const [];

    return [
      MqIconButton(
        icon: 'image-add-line',
        tip: _spec.multipleReferences
            ? tr('Add references')
            : tr('Choose the source file'),
        size: 32,
        onPressed: _browse,
      ),
    ];
  }

  Future<void> _cast(AssetKind kind) async {
    final id = await showAssetGallery(context, app: app, kind: kind);
    if (id == null) return;
    if (kind == AssetKind.actor) {
      app.project.setActor(id);
    } else {
      app.project.setScene(id);
    }
    // Straight into its panel: something has just been cast, and the next
    // question is always how it should sound or how it should look.
    if (mounted) {
      setState(
        () => _panel = kind == AssetKind.actor ? _Panel.actor : _Panel.scene,
      );
    }
  }
}

class _SendIntent extends Intent {
  const _SendIntent();
}

/// Which of the three panels the slot beside the bar is showing.
enum _Panel { none, settings, actor, scene }

/// The actor or the scene on the ad: a chip that casts one, and once one is
/// cast, the way into its settings.
///
/// The cross is a second target rather than a second meaning for the chip,
/// because casting one used to be a one-way door: the picker could replace it
/// and nothing could empty it.
class _CastChip extends StatelessWidget {
  const _CastChip({
    required this.label,
    required this.emptyIcon,
    required this.name,
    required this.clearTip,
    required this.onPressed,
    required this.onCleared,
    this.portrait = '',
    this.lit = false,
  });

  final String label;
  final String emptyIcon;
  final String name;
  final String portrait;
  final String clearTip;
  final VoidCallback onPressed;
  final VoidCallback onCleared;

  /// True while this chip's panel is the one open, so the bar says which of the
  /// two the column on the right belongs to.
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final chip = MqChip(
      label: label,
      value: name,
      icon: name.isEmpty ? emptyIcon : '',
      portrait: portrait,
      opensMenu: name.isNotEmpty,
      active: lit ? true : null,
      onPressed: onPressed,
    );

    if (name.isEmpty) return chip;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip,
        const SizedBox(width: 2),
        MqIconButton(
          icon: 'close-line',
          tip: clearTip,
          size: 24,
          destructive: true,
          onPressed: onCleared,
        ),
      ],
    );
  }
}

/// How many at once. A minus, a number, a plus -- the whole control.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        border: Border.all(color: mq.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MqIconButton(
            icon: 'subtract-line',
            tip: tr('One fewer'),
            size: 26,
            enabled: value > 1,
            onPressed: () => onChanged(value - 1),
          ),
          SizedBox(
            width: 24,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: mq.textPrimary,
                fontSize: MqTheme.fontLabel,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          MqIconButton(
            icon: 'add-line',
            tip: tr('One more'),
            size: 26,
            enabled: value < max,
            onPressed: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}
