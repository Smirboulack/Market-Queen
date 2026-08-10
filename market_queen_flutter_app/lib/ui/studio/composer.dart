import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../../models/asset_library.dart';
import '../../models/canvas_feed.dart';
import '../../models/studio_runner.dart';
import '../dialogs/asset_editor.dart' show AssetKind;
import '../dialogs/asset_picker.dart';
import '../dialogs/confirm_generation.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chip.dart';
import '../widgets/media_drop.dart';
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

  ComposerTab _tab = ComposerTab.actors;
  bool _settingsOpen = false;
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
  List<String> get _refs => _references[_tab]!;

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

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        app.project,
        app.pipeline,
        app.runner,
        app.settings,
      ]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ComposerTabBar(
              current: _tab,
              onPicked: (tab) => setState(() => _tab = tab),
            ),
          ),
          const SizedBox(height: MqTheme.gap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _bar()),
              // The settings live beside the bar rather than inside it: they
              // are read once per session and the prompt is rewritten twenty
              // times, so they must not take room from it.
              if (_settingsOpen) ...[
                const SizedBox(width: MqTheme.gap),
                SizedBox(
                  // Wide enough for "fal.ai · Kling 3.0 Turbo Pro" without an
                  // ellipsis, which is the longest thing that ever lands here.
                  width: 330,
                  child: ComposerSettings(
                    app: app,
                    tab: _tab,
                    onClose: () => setState(() => _settingsOpen = false),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
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
      constraints: BoxConstraints(
        minHeight: _spec.tall ? 84 : 44,
        maxHeight: 220,
      ),
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
        height: 84,
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
            onRemove: () => setState(() => _refs.removeAt(i)),
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
        if (_tab == ComposerTab.actors) ...[
          _CharacterCount(controller: _prompt),
          const SizedBox(width: 10),
        ],
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
          tip: _settingsOpen ? tr('Hide the settings') : tr('Settings'),
          size: 32,
          onPressed: () => setState(() => _settingsOpen = !_settingsOpen),
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
      final decor = app.decors.byId(project.decorId);

      return [
        MqChip(
          label: tr('Add an actor'),
          value: actor?.name ?? '',
          icon: actor == null ? 'user-add-line' : '',
          portrait: actor?.thumbnail ?? '',
          onPressed: () => _cast(AssetKind.actor),
        ),
        MqChip(
          label: tr('Add a décor'),
          value: decor?.name ?? '',
          icon: decor == null ? 'image-add-line' : '',
          onPressed: () => _cast(AssetKind.decor),
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
    final id = await showAssetPicker(context, app: app, kind: kind);
    if (id == null) return;
    if (kind == AssetKind.actor) {
      app.project.setActor(id);
    } else {
      app.project.setDecor(id);
    }
  }
}

class _SendIntent extends Intent {
  const _SendIntent();
}

/// "0 / 1500". A script longer than that is not an ad, and knowing before the
/// send button says so is what stops it being written twice.
class _CharacterCount extends StatelessWidget {
  const _CharacterCount({required this.controller});

  final TextEditingController controller;

  static const int limit = 1500;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final used = controller.text.characters.length;

    return Text(
      '$used / $limit',
      style: TextStyle(
        color: used > limit ? mq.warningText : mq.textTertiary,
        fontSize: MqTheme.fontSmall,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
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
