import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app_state.dart';
import '../../core/clipboard_media.dart';
import '../../core/pricing.dart';
import '../../i18n/translator.dart';
import '../../models/asset_library.dart';
import '../../models/canvas_feed.dart';
import '../../models/prompt_doctor.dart';
import '../../models/studio_runner.dart';
import '../../providers/capabilities.dart';
import '../../providers/model_schemas.dart';
import '../dialogs/asset_gallery.dart';
import '../dialogs/confirm_generation.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chip.dart';
import '../widgets/dashed_box.dart';
import '../widgets/measured.dart';
import '../widgets/media_drop.dart';
import '../widgets/media_preview.dart';
import '../widgets/popover.dart';
import 'cast_panels.dart';
import 'composer_tabs.dart';
import 'mentions.dart';

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
    this.onBarHeight,
  });

  final AppState app;

  /// Runs the full pipeline. It stays outside this widget because the window
  /// owns the run -- the composer only says when.
  final VoidCallback onGenerateAd;

  /// How tall the prompt block is, whenever that changes.
  ///
  /// The prompt block only: the tab row and the bar. Not the settings column
  /// and not a cast panel, which are allowed to grow over the canvas and must
  /// cost the feed underneath nothing at all -- see [MeasuredHeight].
  final ValueChanged<double>? onBarHeight;

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
  ///
  /// They colour the handles they recognise as you type -- see
  /// [MentionController]. The set of handles is rewritten on every build from
  /// what is actually attached, so a reference removed unlights the token that
  /// named it in the same frame.
  final Map<ComposerTab, MentionController> _prompts = {
    for (final tab in ComposerTab.values) tab: MentionController(),
  };

  /// What was dropped into the bar, per tab. Session-local on purpose: a
  /// reference is part of the request you are composing, not part of the ad.
  final Map<ComposerTab, List<String>> _references = {
    for (final tab in ComposerTab.values) tab: <String>[],
  };

  final FocusNode _focus = FocusNode();

  /// The panel that hangs over the canvas. Wide enough for "Kling 3.0 Turbo
  /// Pro" without an ellipsis, which is about the longest thing that lands in
  /// it.
  static const double _panelWidth = 320;

  /// The bar stops widening at the studio's own column width, which the feed
  /// above it is capped to as well -- see [MqTheme.contentMaxWidth].
  static const double _barMaxWidth = MqTheme.contentMaxWidth;

  /// How much room the prompt gets before it has anything in it. The same on
  /// every tab, so the bar is one shape.
  static const double _fieldMinHeight = 104;

  /// Under this, the settings fold into a single button with a sheet behind
  /// it.
  ///
  /// The mode pills and the settings share one line, and one of them has to
  /// give when it runs out. It is the settings: they are a list, a list reads
  /// perfectly well stacked, and the modes are the thing you actually came to
  /// press.
  static const double _foldSettingsBelow = 1000;

  ComposerTab _tab = ComposerTab.actors;

  /// The advanced modes taken out of "See more", in the order they were added.
  /// They sit on the pill row beside the three permanent ones until they are
  /// put away again.
  final List<ComposerTab> _extras = [];

  /// Which of the three panels is showing, if any. They share one slot because
  /// they answer one question -- "what exactly is about to be generated" -- and
  /// two of them open at once would be two answers.
  _Panel _panel = _Panel.none;

  /// One portal per panel, each hanging off the button that opens it.
  ///
  /// They are separate rather than one shared portal because the panel is
  /// positioned from its own button's paint transform, and a portal only knows
  /// where its own child is.
  final Map<_Panel, OverlayPortalController> _portals = {
    for (final panel in _Panel.values) panel: OverlayPortalController(),
  };

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

  MentionController get _prompt => _prompts[_tab]!;

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

  // ---- what the prompt can point at ---------------------------------------

  /// Whether this tab's field names the things attached to it.
  ///
  /// Every free prompt does: the handles are what the model is handed, whatever
  /// shelf it comes off. The two source-only tabs have no prompt to name
  /// anything in.
  bool get _namesReferences => _spec.prompted;

  /// Whether the cast is addressable here.
  ///
  /// Only in the talking-actor mode, and that is not a detail. That mode runs
  /// on a different model from the other two -- an avatar model, which is
  /// handed the actor and the scene as part of the request -- so "@Marie" means
  /// something there and nothing at all on the picture or the clip shelf, where
  /// no actor was ever sent.
  bool get _namesCast => _tab == ComposerTab.actors;

  /// The actor and the scene the ad is cast with, in that order.
  List<LibraryAsset> get _castAssets {
    final project = app.project;
    final actor = project.actorIds.isEmpty
        ? null
        : app.actors.byId(project.actorIds.first);
    final scene = app.scenes.byId(project.sceneId);

    return [
      for (final asset in [actor, scene])
        if (asset != null && asset.name.trim().isNotEmpty) asset,
    ];
  }

  /// Everything the current prompt can address by name: each reference in the
  /// bar under the handle the runner will send it as, then -- in the
  /// talking-actor mode only -- the cast.
  List<Mention> get _mentions {
    if (!_namesReferences) return const [];

    final handles = referenceHandles(_refs);
    return [
      for (var i = 0; i < _refs.length; ++i)
        Mention(handle: handles[i], label: p.basename(_refs[i])),
      if (_namesCast)
        for (final asset in _castAssets)
          Mention(handle: castHandle(asset.name), label: asset.name),
    ];
  }

  // ---- how much this tab will take ----------------------------------------

  /// Worked out once per build pass and cleared at the top of it.
  ({int images, int videos, int audios})? _limitsThisPass;

  /// What the chosen model will accept, per kind.
  ///
  /// Only the video shelf has models that disagree: a reference endpoint
  /// declares three lists and how long each may be, while an ordinary
  /// image-to-video one takes a single opening frame and no lists at all.
  /// Everywhere else the answer is the tab's own, because the shelf has one
  /// shape.
  ({int images, int videos, int audios}) get _limits =>
      _limitsThisPass ??= _readLimits();

  ({int images, int videos, int audios}) _readLimits() {
    final kinds = _spec.referenceKinds;

    if (_tab == ComposerTab.video) {
      final providerId = app.runner.providerFor('video');
      final capabilities = app.modelSchemas.capabilities(
        providerId,
        app.runner.modelFor('video', _seconds),
      );

      if (capabilities.takesReferences) {
        // A directly-called provider has nowhere to host a file, so what it
        // will read as base64 is what it can be handed at all -- which is per
        // modality and not the same on the two of them. Saying so with the
        // counter is better than accepting the drop and refusing it at send.
        final limits = ModelSchemas.fetches(providerId)
            ? capabilities.referenceLimits
            : capabilities.inlineLimits;

        // Every list closed to us, but the model still animates a still: it is
        // an image-to-video endpoint as far as this bar is concerned.
        if (limits.images == 0 && limits.videos == 0 && limits.audios == 0) {
          return capabilities.imageField.isEmpty
              ? limits
              : (images: 1, videos: 0, audios: 0);
        }
        return limits;
      }

      // A model that declares no lists: one opening frame, which is exactly
      // what the runner sends it. A model that also shoots from the prompt
      // still only has room for the one.
      if (capabilities.known) return (images: 1, videos: 0, audios: 0);

      // Nothing read yet -- a fetch still in flight, no network, or a provider
      // that publishes no schema at all. Locking the bar down on the strength
      // of not knowing would be the worst of the three answers: the send path
      // trims what a model will not take anyway, and the counters correct
      // themselves the moment the schema lands.
      return (
        images: ModelCapabilities.platformMaxImages,
        videos: ModelCapabilities.platformMaxVideos,
        audios: ModelCapabilities.platformMaxAudios,
      );
    }

    int room(MediaKind kind) {
      if (!kinds.contains(kind)) return 0;
      return _spec.multipleReferences ? _openEnded : 1;
    }

    return (
      images: room(MediaKind.image),
      videos: room(MediaKind.video),
      audios: room(MediaKind.audio),
    );
  }

  /// "As many as you like" -- for the shelves that have no declared ceiling.
  /// High enough never to be reached by hand, and still a number, so the same
  /// counting code serves every tab.
  static const int _openEnded = 99;

  /// How many of [kind] are already in the bar.
  int _countOf(MediaKind kind) =>
      _refs.where((path) => mediaKindOf(path) == kind).length;

  int _limitOf(MediaKind kind) => switch (kind) {
    MediaKind.image => _limits.images,
    MediaKind.video => _limits.videos,
    MediaKind.audio => _limits.audios,
  };

  /// The kinds this tab is currently offering, in a fixed order so the buttons
  /// never reshuffle under the pointer.
  List<MediaKind> get _acceptedKinds => [
    for (final kind in MediaKind.values)
      if (_limitOf(kind) > 0) kind,
  ];

  /// Types a handle at the caret, spaced the way somebody would have typed it.
  ///
  /// The tiles and the cast chips both lead here, because the alternative is
  /// remembering whether the clip dropped in second was @Video1 or @Video2.
  void _insertHandle(String handle) {
    final text = _prompt.text;
    final selection = _prompt.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;

    final lead = start > 0 && !_isBlank(text.codeUnitAt(start - 1)) ? ' ' : '';
    final trail = end < text.length && _isBlank(text.codeUnitAt(end)) ? '' : ' ';
    final inserted = '$lead$handle$trail';

    _rewrite(text.replaceRange(start, end, inserted), start + inserted.length);
    _focus.requestFocus();
  }

  /// Writes a new value into the prompt from outside the keyboard.
  ///
  /// Everything that edits the field by hand goes through here, because two
  /// things have to happen together: the controller takes the text and the
  /// caret, and -- on the script tab -- so does the ad. `onChanged` fires for
  /// typing only, so a programmatic edit that skipped this would be lost at the
  /// next save.
  void _rewrite(String text, int caret) {
    _prompt.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    );
    if (_tab == ComposerTab.actors) app.project.setScript(text);
  }

  static bool _isBlank(int codeUnit) =>
      codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D;

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

  /// The frame size and the quality step, for the picture models that offer
  /// them. Read through the model's own declaration, so a value saved under one
  /// model is never sent to another that has never heard of it.
  ImageCapabilities get _imageModel =>
      ImageCapabilities.of(app.runner.modelFor(_spec.category));

  String get _imageSize =>
      _imageModel.sizeOr(app.settings.prefString('${_spec.category}Size'));

  String get _imageQuality => _imageModel.qualityOr(
    app.settings.prefString('${_spec.category}Quality'),
  );

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
    final order = _order(withSources: true);

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

  /// Opens a file dialog for one kind, and only that kind.
  ///
  /// One button per kind instead of a single paperclip over an "images, video &
  /// audio" filter: the old dialog let you attach a clip to the picture tab,
  /// which was then silently dropped on the way out, and gave no hint that the
  /// video tab took recordings at all.
  Future<void> _browse(MediaKind kind) async {
    final files = await openFiles(
      acceptedTypeGroups: [
        switch (kind) {
          MediaKind.image => imageTypeGroup,
          MediaKind.video => videoTypeGroup,
          MediaKind.audio => audioTypeGroup,
        },
      ],
    );
    if (files.isEmpty) return;
    _addReferences([for (final file in files) file.path]);
  }

  /// Ctrl+V, taken over from the text field.
  ///
  /// Text still pastes as text, and that path is checked first: it is one
  /// platform-channel call, so an ordinary paste waits on nothing. Only when
  /// the clipboard holds no text at all is the shell asked -- and that is
  /// exactly the case where it holds a screenshot or a file copied out of the
  /// file manager, the two things people try to paste into a prompt bar and the
  /// two things that used to silently do nothing.
  Future<void> _paste() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text ?? '';

    if (text.trim().isNotEmpty) {
      // A path copied out of an address bar or a chat message is a file, not a
      // sentence, and pasting it as prose is never what was meant.
      final paths = _spec.takesReferences
          ? ClipboardMedia.pathsIn(text)
          : const <String>[];
      if (paths.isNotEmpty) {
        _addReferences(paths);
        return;
      }

      final current = _prompt.text;
      final selection = _prompt.selection;
      final start = selection.isValid ? selection.start : current.length;
      final end = selection.isValid ? selection.end : current.length;
      _rewrite(current.replaceRange(start, end, text), start + text.length);
      return;
    }

    if (!_spec.takesReferences) return;
    final files = await ClipboardMedia.readFiles();
    if (files.isNotEmpty && mounted) _addReferences(files);
  }

  /// Takes what it can of [paths] and quietly leaves the rest.
  ///
  /// Two filters, and they are different questions. A kind this mode does not
  /// take is refused outright -- a clip dropped on the picture tab is a
  /// category error, not a full shelf. A kind it does take but has no room left
  /// for is refused because the model said so, and the counter under the bar is
  /// what explains it.
  void _addReferences(List<String> paths) {
    final accepted = <String>[];
    final room = {
      for (final kind in MediaKind.values) kind: _limitOf(kind) - _countOf(kind),
    };

    for (final path in paths) {
      if (path.isEmpty || _refs.contains(path) || accepted.contains(path)) {
        continue;
      }
      final kind = mediaKindOf(path);
      if (_limitOf(kind) <= 0) continue;

      // The single-source tabs take one file and replace it rather than
      // collecting a pile nobody can tell apart.
      if (!_spec.multipleReferences) {
        accepted
          ..clear()
          ..add(path);
        break;
      }

      if ((room[kind] ?? 0) <= 0) continue;
      room[kind] = room[kind]! - 1;
      accepted.add(path);
    }

    if (accepted.isEmpty) return;

    if (_tab == ComposerTab.actors) {
      // Through the ad, which de-duplicates, normalises file:// URLs and marks
      // itself dirty so the reference is saved with the document.
      app.project.addMedia(accepted);
      return;
    }

    setState(() {
      if (!_spec.multipleReferences) _refs.clear();
      _refs.addAll(accepted);
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
        app.modelSchemas,
      ]),
      // The panels are drawn in the overlay rather than in this row, and that
      // is the whole geometry of the composer now: the bar is one width, always
      // -- capped, centred, and never asked to make room for anything.
      //
      // They used to be a column welded to the bar's right edge, with a
      // mirrored gutter on the left to keep the bar's middle on the page's
      // middle, and a second layout underneath for windows too narrow to
      // afford the column, where the panel stacked over the bar instead. Both
      // shapes moved the caret when the cog was pressed. A panel that says what
      // the *next* generation will look like has no business resizing the field
      // you are typing the current one into -- so it hangs above its own button
      // now, over the canvas, costing the bar nothing.
      //
      // The tab row lives inside the bar's own column rather than above the
      // whole thing, so it stays centred on the bar.
      builder: (context, _) {
        // Worked out once per pass. The bar asks what the model will take a
        // dozen times a frame -- for the buttons, for the counters, for every
        // drop -- and the answer comes from the schema store, which is cheap
        // but not free. This is the outermost thing that runs on a rebuild, so
        // it is where the answer goes stale.
        _limitsThisPass = null;
        return _layout();
      },
    );
  }

  Widget _layout() {
    // Escape closes the open panel, the way it closes any menu. Only while one
    // is open: the rest of the time the key belongs to whatever else wants it.
    return CallbackShortcuts(
      bindings: {
        if (_open) const SingleActivator(LogicalKeyboardKey.escape): _closePanel,
      },
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: SizedBox(
            width: math.min(_barMaxWidth, constraints.maxWidth),
            // The feed reserves room for exactly this much and nothing else.
            // There is nothing else left to reserve for: the panels are in
            // the overlay, so opening one moves not one tile.
            child: MeasuredHeight(
              onChanged: (height) => widget.onBarHeight?.call(height),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Modes anchored left, settings anchored right, on one line
                  // above the bar.
                  //
                  // The settings are out of the prompt bar entirely. Inside it
                  // they competed with the thing you are typing -- six framed
                  // pills wrapping under a text field is a lot of furniture
                  // around one sentence -- and they are not about the sentence
                  // at all: they are what the next generation will be, which
                  // belongs with the mode that decides it.
                  // Modes at one end, settings at the other, spanning the
                  // same width as the prompt underneath. The two are opposite
                  // kinds of choice -- what you are making, and what it will
                  // be like -- so they sit at opposite ends rather than
                  // crowding into the middle together.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: ComposerTabBar(
                          current: _tab,
                          extras: _extras,
                          onPicked: _pickTab,
                          onRemoved: _dropTab,
                        ),
                      ),
                      const SizedBox(width: MqTheme.gap),
                      // Under the breakpoint the settings fold into one
                      // button. It is the modes that keep their words: they
                      // are what you came to press, and a row of unlabelled
                      // glyphs is a row you learn rather than read.
                      if (constraints.maxWidth < _foldSettingsBelow)
                        _anchored(
                          _Panel.settings,
                          MqIconButton(
                            icon: 'equalizer-line',
                            tip: tr('Settings'),
                            size: 32,
                            onPressed: () => _show(_Panel.settings),
                          ),
                          () => _SettingsSheet(
                            items: _settings(),
                            onClose: _closePanel,
                          ),
                        )
                      else
                        Flexible(child: _SettingsRow(items: _settings())),
                    ],
                  ),
                  const SizedBox(height: MqTheme.gap),
                  _bar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _open => _panel != _Panel.none;

  /// Toggles a panel. Every change of [_panel] goes through here or
  /// [_closePanel], because the overlay has to be told as well -- and told from
  /// outside a build, which is why the portals are driven here rather than read
  /// off the state in [_layout].
  void _show(_Panel panel) {
    if (_panel == panel) {
      _closePanel();
      return;
    }
    _hidePortal(_panel);
    setState(() => _panel = panel);
    _portals[panel]?.show();
  }

  void _closePanel() {
    if (!_open) return;
    _hidePortal(_panel);
    setState(() => _panel = _Panel.none);
  }

  /// `hide` on a controller that has never been shown is an assertion failure,
  /// and [_Panel.none] never is.
  void _hidePortal(_Panel panel) {
    final portal = _portals[panel];
    if (portal != null && portal.isShowing) portal.hide();
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
              // The clip shelf carries its references in a framed well of its
              // own rather than as a loose row: it is the one mode that takes
              // all three kinds, each against its own ceiling, and a row of
              // thumbnails cannot say "three of nine pictures, none of three
              // clips". Everywhere else that frame would be a box drawn around
              // one number.
              if (_showsReferenceWell) ...[
                if (_spec.prompted) const SizedBox(height: 12),
                _referenceWell(),
              ] else if (_refs.isNotEmpty) ...[
                if (_spec.prompted) const SizedBox(height: 12),
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

    // Rewritten rather than kept in step: it is a plain field on the
    // controller, read while the text is painted, and recomputing it here is
    // cheaper than remembering every way a reference can come and go.
    _prompt.handles = [for (final mention in _mentions) mention.handle];

    return ConstrainedBox(
      // One floor for every tab, and it is the script's. A 44px prompt and an
      // 84px one are two differently sized objects in the same place on the
      // page, and switching between them made the bar jump; the taller of the
      // two is also the one that invites a sentence rather than three words.
      constraints: const BoxConstraints(minHeight: _fieldMinHeight, maxHeight: 220),
      // Enter sends; Shift+Enter breaks the line. The chat convention, and the
      // one asked for: reaching for the mouse to press an arrow you are looking
      // straight at, once per generation, is the wrong price for the safety of
      // a two-key send -- and the send button is disabled until the request is
      // actually complete, which is the real guard against a careless one.
      //
      // Ctrl+Enter still sends, so a hand that learned the old shortcut is not
      // punished for it. Shift+Enter is deliberately not in this map at all: a
      // [SingleActivator] only matches when every modifier it does *not* name
      // is up, so the combination reaches the field untouched and breaks the
      // line. Binding it to [DoNothingIntent] would have been worse than
      // useless -- that action consumes the key, which is exactly how Enter
      // came to do nothing at all here.
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): _SendIntent(),
          SingleActivator(LogicalKeyboardKey.enter, control: true):
              _SendIntent(),
          SingleActivator(LogicalKeyboardKey.enter, meta: true): _SendIntent(),
          // Taken off the field, which can only ever paste text. This one
          // decides between text and media itself -- see [_paste].
          SingleActivator(LogicalKeyboardKey.keyV, control: true):
              _PasteIntent(),
          SingleActivator(LogicalKeyboardKey.keyV, meta: true): _PasteIntent(),
        },
        child: Actions(
          actions: {
            _SendIntent: CallbackAction<_SendIntent>(
              onInvoke: (_) {
                _send();
                return null;
              },
            ),
            _PasteIntent: CallbackAction<_PasteIntent>(
              onInvoke: (_) {
                _paste();
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

    // The source-only tabs take exactly one kind, so the invitation opens that
    // one dialog rather than a filter covering all three.
    final kind = _acceptedKinds.isEmpty ? MediaKind.image : _acceptedKinds.first;

    return Pressable(
      onTap: () => _browse(kind),
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

  /// Whether this tab draws the framed reference well under its prompt.
  bool get _showsReferenceWell => _tab == ComposerTab.video;

  Widget _referenceRow() {
    // The handles have to be computed over the whole list rather than per tile:
    // "@Image2" only means anything relative to the picture that came first.
    final handles = _namesReferences
        ? referenceHandles(_refs)
        : const <String>[];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [
        for (var i = 0; i < _refs.length; ++i)
          if (handles.isEmpty)
            MediaTile(
              path: _refs[i],
              size: _tileSize,
              ffmpegPath: app.ffmpegPath,
              onTap: () => showMediaPreview(context, _refs[i]),
              onRemove: () => _removeReference(i),
            )
          else
            _NamedReference(
              path: _refs[i],
              handle: handles[i],
              size: _tileSize,
              ffmpegPath: app.ffmpegPath,
              onOpen: () => showMediaPreview(context, _refs[i]),
              onRemove: () => _removeReference(i),
              onInsert: () => _insertHandle(handles[i]),
            ),
      ],
    );
  }

  static const double _tileSize = 54;

  /// The framed well under the clip shelf's prompt.
  ///
  /// A dashed box, because a dashed box means "put things here" in a way a
  /// hairline panel does not -- and, along the bottom of it, how many of each
  /// kind are in and how many the chosen model will take. Those numbers were
  /// previously discoverable only by sending too many and reading the
  /// rejection.
  Widget _referenceWell() {
    final mq = context.mq;
    final handles = referenceHandles(_refs);

    return DashedBox(
      color: _dragging ? mq.textTertiary : mq.borderStrong,
      radius: MqTheme.radius,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_refs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Center(
                  child: MqIcon(
                    'image-add-line',
                    size: 22,
                    color: mq.textTertiary,
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  for (var i = 0; i < _refs.length; ++i)
                    _NamedReference(
                      path: _refs[i],
                      handle: handles[i],
                      size: _tileSize,
                      ffmpegPath: app.ffmpegPath,
                      onOpen: () => showMediaPreview(context, _refs[i]),
                      onRemove: () => _removeReference(i),
                      onInsert: () => _insertHandle(handles[i]),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            _CounterLine(
              counts: [
                for (final kind in _acceptedKinds)
                  (kind: kind, used: _countOf(kind), limit: _limitOf(kind)),
              ],
            ),
          ],
        ),
      ),
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
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // The buttons and every setting share one wrapping row.
        //
        // The settings used to be behind a cog: press it, a panel opened over
        // the canvas with six labelled rows in it, change one, close it. Four
        // actions to answer a question you can already see the answer to --
        // and the one thing that *was* on the bar, the model name, opened that
        // same panel, so the most direct-looking control on screen was a
        // shortcut to the slowest.
        //
        // Every setting is its own chip now, showing its own value, and each
        // opens only its own menu. Pressing "Best" asks about quality and
        // nothing else.
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: _leadingActions(),
          ),
        ),
        const SizedBox(width: 10),
        if (_spec.batched) ...[
          _Stepper(
            value: _count,
            max: _spec.maxCount,
            onChanged: _setCount,
          ),
          const SizedBox(width: 10),
        ],
        Container(width: 1, height: 24, color: mq.divider),
        const SizedBox(width: 10),
        // What the press costs, then the two buttons that act on the prompt.
        // In that order because that is the sentence: this is what it will
        // cost, here is how to make it better first, here is how to send it.
        if (_meterPrice.isNotEmpty) ...[
          _PriceTag(price: _meterPrice),
          const SizedBox(width: 10),
        ],
        if (_spec.prompted) ...[
          _improveButton(),
          const SizedBox(width: 8),
        ],
        GradientSendButton(
          enabled: readiness.ready,
          busy: busy,
          spinner: _spinner,
          tooltip: readiness.ready
              ? tr('Generate  ·  Enter')
              : readiness.reason,
          onPressed: _send,
        ),
      ],
    );
  }

  // ---- the settings, above the bar -----------------------------------------

  /// Every choice this tab offers, as data.
  ///
  /// Data rather than widgets because there are two ways to draw them and one
  /// list behind both: a row of text buttons when there is room, and a sheet
  /// under a single button when there is not. Building the widgets twice is
  /// how the two drift apart.
  List<_Setting> _settings() {
    final project = app.project;
    final items = <_Setting>[];

    if (_spec.category.isNotEmpty) {
      final models = _modelOptions();
      // Everything on this shelf has been switched off under Models, or none
      // of it has a key. Said rather than left blank -- and `showMenu` asserts
      // on an empty list, so an empty menu would be a crash rather than a
      // shrug.
      if (models.isEmpty) {
        items.add(_Notice(tr('No model enabled')));
      } else {
        items.add(
          _Choice(
            label: tr('Model'),
            value: app.runner.modelLabel(_spec.category, _seconds),
            current: '${app.runner.providerFor(_spec.category)}'
                '|${app.runner.modelFor(_spec.category, _seconds)}',
            options: models,
            menuWidth: 340,
            onPicked: (value) {
              final parts = value.split('|');
              if (parts.length != 2) return;
              app.settings
                ..setPref('${_spec.category}Provider', parts[0])
                ..setPref('${_spec.category}Model', parts[1]);
              setState(() {});
            },
          ),
        );
      }
    }

    // OpenAI's sizes are whole frames -- "1536 x 1024 · landscape" is a shape
    // as well as a size -- so a Format setting beside it would be a second
    // control for one decision. Every other model takes the two as separate
    // fields and keeps both.
    final picture = ImageCapabilities.of(app.runner.modelFor(_spec.category));
    final framed = _tab == ComposerTab.image && picture.sizeSetsShape;

    if (_spec.picksAspect && !framed) {
      // What the model actually draws. Empty means the three every model here
      // takes; Gemini publishes ten, and a portrait 4:5 for a feed post is not
      // something to approximate with 9:16.
      final ratios = _tab == ComposerTab.image && picture.aspectRatios.isNotEmpty
          ? picture.aspectRatios
          : const ['9:16', '1:1', '16:9'];

      items.add(
        _Choice(
          label: tr('Format'),
          value: ratioLabel(_aspect),
          current: _aspect,
          options: [
            for (final ratio in ratios) MenuOption(ratioLabel(ratio), ratio),
          ],
          onPicked: (value) {
            if (_tab == ComposerTab.actors) {
              project.setAspectRatio(value);
            } else {
              app.settings.setPref('${_spec.category}Aspect', value);
            }
            setState(() {});
          },
        ),
      );
    }

    if (_tab == ComposerTab.image) {
      if (picture.picksSize) {
        items.add(
          _Choice(
            label: tr('Size'),
            value: sizeLabel(_imageSize),
            current: _imageSize,
            options: [
              for (final size in picture.sizes)
                MenuOption(sizeLabel(size), size),
            ],
            menuWidth: 260,
            onPicked: (value) {
              app.settings.setPref('${_spec.category}Size', value);
              setState(() {});
            },
          ),
        );
      }
      if (picture.picksQuality) {
        items.add(
          _Choice(
            label: tr('Quality'),
            value: qualityLabel(_imageQuality),
            current: _imageQuality,
            options: [
              for (final quality in picture.qualities)
                MenuOption(qualityLabel(quality), quality),
            ],
            onPicked: (value) {
              app.settings.setPref('${_spec.category}Quality', value);
              setState(() {});
            },
          ),
        );
      }
    }

    if (_tab == ComposerTab.video) items.addAll(_videoSettings());
    if (_tab == ComposerTab.actors) items.addAll(_adSettings());

    return items;
  }

  /// Length, resolution and the soundtrack switch, as the chosen model
  /// declares them -- Hailuo offers 6 and 10 seconds and nothing between,
  /// Seedance 2.5 takes any whole number up to thirty.
  List<_Setting> _videoSettings() {
    final capabilities = app.modelSchemas.capabilities(
      app.runner.providerFor('video'),
      app.runner.modelFor('video', _seconds),
    );

    final lengths = <MenuOption<String>>[
      for (final token in capabilities.durationChoices)
        if (ModelCapabilities.secondsOf(token) > 0)
          MenuOption(
            //: %1 is a whole number of seconds
            tr('%1 s').arg(ModelCapabilities.secondsOf(token)),
            '${ModelCapabilities.secondsOf(token)}',
          ),
    ];

    return [
      _Choice(
        label: tr('Length'),
        //: %1 is a whole number of seconds
        value: tr('%1 s').arg(_seconds),
        current: '$_seconds',
        // Still fetching, or a model with no length input at all. The two
        // commonest lengths are offered meanwhile rather than an empty menu.
        options: lengths.isEmpty
            ? [
                MenuOption(tr('%1 s').arg(5), '5'),
                MenuOption(tr('%1 s').arg(10), '10'),
              ]
            : lengths,
        onPicked: (value) {
          app.settings.setPref('videoSeconds', int.tryParse(value) ?? 5);
          setState(() {});
        },
      ),
      if (capabilities.resolutions.isNotEmpty)
        _Choice(
          label: tr('Quality'),
          value: _resolution(capabilities),
          current: _resolution(capabilities),
          options: [
            for (final value in capabilities.resolutions)
              MenuOption(value, value),
          ],
          onPicked: (value) {
            app.settings.setPref('videoResolution', value);
            setState(() {});
          },
        ),
      // Only the models that can make sound get the switch. Offering it on one
      // that cannot would be a control that does nothing.
      if (capabilities.supportsAudio)
        _Switch(
          label: tr('Audio'),
          value: app.settings.pref<bool>('videoAudio', true) ?? true,
          tooltip: tr(
            'Let the model generate a soundtrack as well as the picture.',
          ),
          onChanged: (value) {
            app.settings.setPref('videoAudio', value);
            setState(() {});
          },
        ),
    ];
  }

  /// The ad's own three: how long it may run, whether it is subtitled, and
  /// whether the director may cut away to the product.
  List<_Setting> _adSettings() {
    final project = app.project;

    return [
      _Choice(
        label: tr('Max length'),
        value: project.maxSeconds == 0
            ? tr('As long as it takes')
            //: %1 is a whole number of seconds
            : tr('%1 s').arg(project.maxSeconds),
        current: project.maxSeconds == 0 ? '' : '${project.maxSeconds}',
        options: [
          MenuOption(tr('As long as it takes'), ''),
          MenuOption(tr('15 s'), '15'),
          MenuOption(tr('20 s'), '20'),
          MenuOption(tr('30 s'), '30'),
          MenuOption(tr('45 s'), '45'),
          MenuOption(tr('60 s'), '60'),
        ],
        onPicked: (value) => project.setMaxSeconds(int.tryParse(value) ?? 0),
      ),
      // "Subtitled", not "Subtitles": the pill row already has a mode called
      // Subtitles -- the one that burns them into an existing clip -- and two
      // controls with the same word on the same screen doing different things
      // is a coin toss.
      _Switch(
        label: tr('Subtitled'),
        value: project.captions,
        onChanged: project.setCaptions,
      ),
      _Switch(
        label: tr('Product shots'),
        value: project.broll,
        tooltip: project.broll
            ? tr('The lines about the product are filmed on the product, with '
                'your voice over them.')
            : tr('Every line is filmed on the actor.'),
        onChanged: project.setBroll,
      ),
    ];
  }

  /// Provider and model in one menu.
  ///
  /// Nobody chooses a provider -- they choose a model, and the provider is a
  /// fact about it. Only models the Models page has left switched on appear.
  List<MenuOption<String>> _modelOptions() {
    final registry = app.registry;
    final providers = registry.providers(_spec.category);
    final named = providers.length > 1;

    final options = <MenuOption<String>>[];
    for (final provider in providers) {
      for (final model in provider.models) {
        final price = Format.unitPriceLabel(app.pricing.unitPrice(model.id));
        options.add(
          MenuOption(
            [
              if (named) '${provider.label} · ',
              model.label,
              if (price.isNotEmpty) '   $price',
            ].join(),
            '${provider.id}|${model.id}',
            mark: provider.credential,
          ),
        );
      }
    }
    return options;
  }

  /// The saved resolution when this model still offers it, otherwise whatever
  /// the model itself defaults to. Switching from a model with 4k to one
  /// without must not leave "4k" showing under a model that has never heard
  /// of it.
  String _resolution(ModelCapabilities capabilities) {
    final saved = app.settings.prefString('videoResolution');
    return capabilities.resolutions.contains(saved)
        ? saved
        : capabilities.firstResolution;
  }

  // ---- what this press will buy --------------------------------------------

  /// The order the meter and the settings both price: exactly what the bar
  /// would send if it were pressed now.
  ///
  /// Built in one place so the two figures cannot disagree, and carrying the
  /// shot settings -- the resolution and the soundtrack switch -- because on
  /// the models that bill by output token those are what move the number. A
  /// Seedance second at 1080p is four times one at 480p, and quoting the one
  /// while the settings say the other is worse than quoting nothing.
  GenerationOrder get pricedOrder => _order();

  /// [withSources] is the only difference between the order that gets priced
  /// and the order that gets sent: the references and the voice come along
  /// only for the real thing. Everything that affects the bill is on both.
  GenerationOrder _order({bool withSources = false}) => GenerationOrder(
    kind: _spec.kind,
    category: _spec.category,
    prompt: _spec.prompted ? _prompt.text.trim() : '',
    references: withSources ? List.of(_refs) : const [],
    aspectRatio: _aspect,
    seconds: _seconds,
    count: _count,
    voiceSource: withSources && _tab == ComposerTab.audio
        ? app.request()
        : const {},
    resolution: app.settings.prefString('videoResolution'),
    audio: app.settings.pref<bool>('videoAudio', true) ?? true,
    size: _imageSize,
    quality: _imageQuality,
  );

  /// Whether pressing send would actually buy anything.
  ///
  /// Not the same question as [_readiness], and the difference is the talking
  /// actor: that tab is also switched off while an ad is already shooting, and
  /// a run in progress is precisely when what the *next* one costs is still
  /// worth knowing. What makes an ad unpriceable is having nothing to shoot --
  /// no script, or nobody to read it -- which is what the pipeline's own
  /// completeness test says.
  bool get _pricable => _tab == ComposerTab.actors
      ? app.project.complete
      : _readiness.ready;

  /// What one press costs, as text, or empty when there is nothing to price.
  ///
  /// Nothing to price is the common case and it used to be the confusing one:
  /// with an empty prompt the bar quoted the model's own rate -- "$0.15/s" --
  /// beside a send button that was switched off. That is not what this press
  /// costs, because this press is not going to happen; it is a property of the
  /// model, and the model menu is where a model's rate belongs.
  String get _meterPrice {
    if (!_pricable) return '';

    // A talking actor buys a whole run -- a script pass, a reading, a frame
    // and a clip per shot -- so it is the ad's own estimate rather than the
    // single-order one.
    if (_tab == ComposerTab.actors) {
      final breakdown = app.pricing.estimate(app.request());
      return breakdown.lines.length > breakdown.unknownCount
          ? Format.estimated(breakdown.total)
          : '';
    }

    final estimate = app.runner.estimate(pricedOrder);
    return estimate.known ? Format.estimated(estimate.amount) : '';
  }

  /// Wraps the button a panel hangs off in its own portal.
  ///
  /// The panel is positioned from its own button's paint transform, so it has
  /// to be a portal around that button rather than one shared portal around
  /// the bar.
  Widget _anchored(_Panel panel, Widget button, Widget Function() body) {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portals[panel]!,
      overlayChildBuilder: (context, info) => PopoverLayer(
        info: info,
        width: _panelWidth,
        onDismiss: _closePanel,
        child: body(),
      ),
      child: button,
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
        // Three things you can do to a cast actor, and all three are on the one
        // bubble: press the name to swap them, the cog for the read, the cross
        // to take them off. Nothing is behind a menu, because all three are
        // single clicks you make constantly.
        _CastChip(
          label: tr('Add an actor'),
          emptyIcon: 'user-add-line',
          name: actor?.name ?? '',
          portrait: actor?.thumbnail ?? '',
          replaceTip: tr('Cast somebody else'),
          settingsTip: tr('Voice and delivery'),
          clearTip: tr('Take this actor off the ad'),
          lit: _panel == _Panel.actor,
          settingsPortal: _portals[_Panel.actor]!,
          settingsPanel: (context, info) => PopoverLayer(
            info: info,
            width: _panelWidth,
            onDismiss: _closePanel,
            child: CastPanel(
              app: app,
              kind: AssetKind.actor,
              onClose: _closePanel,
              onReplace: () => _cast(AssetKind.actor),
            ),
          ),
          onPressed: () => _cast(AssetKind.actor),
          onSettings: () => _show(_Panel.actor),
          onCleared: () {
            project.clearActor();
            if (_panel == _Panel.actor) _closePanel();
          },
        ),
        _CastChip(
          label: tr('Add a scene'),
          emptyIcon: 'scene-line',
          name: scene?.name ?? '',
          portrait: scene?.thumbnail ?? '',
          replaceTip: tr('Film somewhere else'),
          settingsTip: tr('Light and mood'),
          clearTip: tr('Take this scene off the ad'),
          lit: _panel == _Panel.scene,
          settingsPortal: _portals[_Panel.scene]!,
          settingsPanel: (context, info) => PopoverLayer(
            info: info,
            width: _panelWidth,
            onDismiss: _closePanel,
            child: CastPanel(
              app: app,
              kind: AssetKind.scene,
              onClose: _closePanel,
              onReplace: () => _cast(AssetKind.scene),
            ),
          ),
          onPressed: () => _cast(AssetKind.scene),
          onSettings: () => _show(_Panel.scene),
          onCleared: () {
            project.clearScene();
            if (_panel == _Panel.scene) _closePanel();
          },
        ),
        // The product itself. An ad is usually *about* something, and the
        // frame model can only put it on screen if it has been shown it --
        // until this button existed the only way in was the drag-and-drop
        // nobody discovers.
        ..._referenceButtons(),
      ];
    }

    return _referenceButtons();
  }

  /// The wand: hands what is written to a writer and puts back a fuller
  /// version of it.
  ///
  /// A menu rather than a single action. A rewrite is a paid call like any
  /// other, and which account pays for it was inherited from the writer picked
  /// for scripts -- a different job, often a different budget. So the button
  /// asks, with the price of this particular rewrite beside each model, and
  /// choosing one runs it.
  ///
  /// The glyph is the one thing on the bar drawn in brand colour. It is the
  /// only control here that improves what you already have rather than
  /// spending on something new, and it is easy to never notice.
  Widget _improveButton() {
    final doctor = app.promptDoctor;

    return ListenableBuilder(
      listenable: doctor,
      builder: (context, _) {
        final writers = doctor.writers;

        return Builder(
          builder: (anchor) => MqIconButton(
            icon: doctor.busy ? 'loader-4-line' : 'sparkling-line',
            tip: writers.isEmpty
                ? tr('Add a key for a writer under API keys to improve '
                    'prompts.')
                : tr('Improve this prompt'),
            size: 32,
            tint: doctor.busy ? null : context.mq.primary,
            enabled: writers.isNotEmpty && !doctor.busy,
            onPressed: () => _pickWriter(anchor, writers),
          ),
        );
      },
    );
  }

  /// Opens the writer menu and runs the rewrite on whichever was chosen.
  Future<void> _pickWriter(
    BuildContext anchor,
    List<PromptWriter> writers,
  ) async {
    // Priced per writer, for this prompt, at this length. The figures differ
    // by two orders of magnitude across the list -- a Flash model against
    // Opus on the same paragraph -- which is exactly why the menu exists.
    final options = [
      for (final writer in writers)
        MenuOption(
          [
            writer.label,
            if (_rewritePrice(writer).isNotEmpty) '   ${_rewritePrice(writer)}',
          ].join(),
          '${writer.providerId}|${writer.modelId}',
        ),
    ];
    if (options.isEmpty) return;

    final current = writers.first;
    final picked = await showChipMenu<String>(
      anchor,
      options: options,
      current: '${current.providerId}|${current.modelId}',
      width: 300,
    );
    if (picked == null) return;

    final parts = picked.split('|');
    if (parts.length != 2) return;

    await _improvePrompt(
      using: writers.firstWhere(
        (writer) => writer.providerId == parts[0] && writer.modelId == parts[1],
        orElse: () => current,
      ),
    );
  }

  /// What one rewrite on [writer] would cost, as text.
  ///
  /// Sized from what is actually going to be sent: the instruction for this
  /// kind of prompt, plus what is in the field. The answer's length is the
  /// model's decision, so it is taken as twice the prompt with a floor -- an
  /// estimate, and drawn with a tilde like every other one.
  String _rewritePrice(PromptWriter writer) {
    final system = PromptDoctor.systemPromptFor(_promptKind);
    final asked = _prompt.text.trim();
    if (asked.isEmpty) return '';

    final inTokens = Pricing.tokensIn(system) + Pricing.tokensIn(asked);
    final outTokens = math.max(200.0, Pricing.tokensIn(asked) * 2);

    final cost = app.pricing.tokenCost(
      writer.modelId,
      inTokens: inTokens,
      outTokens: outTokens,
    );
    return cost.known ? Format.estimated(cost.amount) : '';
  }

  // ---- the prompt doctor ---------------------------------------------------

  /// What the rewriter is being asked to write, on this tab.
  PromptKind get _promptKind => switch (_tab) {
    ComposerTab.actors => PromptKind.script,
    ComposerTab.audio => PromptKind.voice,
    ComposerTab.video => PromptKind.video,
    _ => PromptKind.image,
  };

  /// Hands the prompt to a writer and puts back what came out.
  ///
  /// The caret lands at the end of the new text, and nothing is lost when it
  /// fails: an empty answer leaves the field exactly as it was and the reason
  /// goes to the log.
  Future<void> _improvePrompt({PromptWriter? using}) async {
    final doctor = app.promptDoctor;
    if (doctor.busy) return;

    final improved = await doctor.improve(
      prompt: _prompt.text,
      kind: _promptKind,
      using: using,
      // What the ad is of, when there is an ad -- the actor and the scene are
      // in the frame whether or not the prompt says so.
      context: _tab == ComposerTab.actors
          ? [
              for (final asset in _castAssets) '${asset.name}: ${asset.prompt}',
            ].join('\n')
          : '',
    );
    if (!mounted || improved.isEmpty) return;

    _rewrite(improved, improved.length);
  }

  /// One button per kind of reference this mode takes, each with its own glyph.
  ///
  /// There used to be a single paperclip over a filter that accepted all three,
  /// which said nothing about what the mode wanted, nothing about what the
  /// model would take, and let you attach a clip to the picture shelf where it
  /// was silently dropped on the way out. A button that is not there is the
  /// clearest possible statement that a kind is not accepted.
  List<Widget> _referenceButtons() {
    final full = <MediaKind, bool>{
      for (final kind in MediaKind.values)
        kind: _spec.multipleReferences && _countOf(kind) >= _limitOf(kind),
    };

    return [
      for (final kind in _acceptedKinds)
        MqIconButton(
          icon: switch (kind) {
            MediaKind.image => 'image-add-line',
            MediaKind.video => 'file-video-line',
            MediaKind.audio => 'file-music-line',
          },
          tip: full[kind] == true
              ? switch (kind) {
                  //: %1 is a number of files
                  MediaKind.image => tr('%1 pictures is all this model takes')
                      .arg(_limitOf(kind)),
                  //: %1 is a number of files
                  MediaKind.video => tr('%1 clips is all this model takes')
                      .arg(_limitOf(kind)),
                  //: %1 is a number of files
                  MediaKind.audio => tr('%1 recordings is all this model takes')
                      .arg(_limitOf(kind)),
                }
              : switch (kind) {
                  MediaKind.image => _spec.multipleReferences
                      ? tr('Add pictures')
                      : tr('Choose the picture'),
                  MediaKind.video => _spec.multipleReferences
                      ? tr('Add clips')
                      : tr('Choose the clip'),
                  MediaKind.audio => tr('Add a recording'),
                },
          size: 32,
          enabled: full[kind] != true,
          onPressed: () => _browse(kind),
        ),
    ];
  }

  Future<void> _cast(AssetKind kind) async {
    final project = app.project;
    final first = kind == AssetKind.actor
        ? project.actorIds.isEmpty
        : project.sceneId.isEmpty;

    final id = await showAssetGallery(context, app: app, kind: kind);
    if (id == null) return;
    if (kind == AssetKind.actor) {
      project.setActor(id);
    } else {
      project.setScene(id);
    }

    // Straight into its panel the first time, because the next question after
    // casting somebody is always how they should sound. Not on a swap: by then
    // you know where the cog is, and a panel opening on every replacement is a
    // panel you close on every replacement.
    if (first && mounted) {
      _show(kind == AssetKind.actor ? _Panel.actor : _Panel.scene);
    }
  }
}

class _SendIntent extends Intent {
  const _SendIntent();
}

class _PasteIntent extends Intent {
  const _PasteIntent();
}

/// A reference with the name the prompt calls it by written underneath.
///
/// The handle is not a label the interface made up: `@Image1` is literally what
/// the model is handed, in the order the runner uploads them. Putting it on the
/// tile is the only place it can be checked against the picture it belongs to
/// -- and pressing the tile types it, because counting which of four dropped
/// clips is @Video2 is not something anybody should be doing.
/// A reference with the name the prompt calls it by written underneath.
///
/// Two targets, one under the other, and they are deliberately not the same
/// one. The thumbnail opens the file, because that is what pressing a
/// thumbnail does everywhere; the handle types itself into the prompt, because
/// that is what a handle is for. Both on the tile would have meant guessing
/// which of the two somebody wanted every time they clicked.
class _NamedReference extends StatelessWidget {
  const _NamedReference({
    required this.path,
    required this.handle,
    required this.size,
    required this.onOpen,
    required this.onRemove,
    required this.onInsert,
    this.ffmpegPath = '',
  });

  final String path;
  final String handle;
  final double size;
  final String ffmpegPath;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final VoidCallback onInsert;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The tile keeps its own remove badge, which sits inside it and wins
        // the tap for the few pixels it covers.
        MediaTile(
          path: path,
          size: size,
          ffmpegPath: ffmpegPath,
          onTap: onOpen,
          onRemove: onRemove,
        ),
        const SizedBox(height: 3),
        Pressable(
          onTap: onInsert,
          //: %1 is a handle such as "@Image1"
          tooltip: tr('Write %1 into the prompt').arg(handle),
          focusRadius: MqTheme.radiusSmall,
          builder: (context, states) => SizedBox(
            width: size,
            child: Text(
              handle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              // The same blue the prompt lights the token in, so the two read
              // as one thing seen twice rather than as two labels.
              style: TextStyle(
                color: mq.info,
                fontSize: MqTheme.fontMicro,
                fontWeight: FontWeight.w600,
                height: 1.2,
                decoration: states.active
                    ? TextDecoration.underline
                    : TextDecoration.none,
                decorationColor: mq.info,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "3/9 pictures · 0/3 clips · 0/3 recordings", under the well they belong to.
///
/// The ceilings are the model's own, off its schema. They differ enough between
/// endpoints -- nine pictures on one, four on the next -- that a fixed number
/// would be wrong most of the time, and the only place they were written down
/// before was the rejection that came back after the upload.
class _CounterLine extends StatelessWidget {
  const _CounterLine({required this.counts});

  final List<({MediaKind kind, int used, int limit})> counts;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Wrap(
      spacing: 10,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final entry in counts)
          Tooltip(
            // The per-file ceiling hangs off each count rather than being
            // stated once underneath: the three are nowhere near each other --
            // thirty megabytes for a picture against two hundred for a clip --
            // so one number for all of them would be wrong twice.
            //: %1 is a size such as "200 MB"
            message: tr('Up to %1 a file').arg(_sizeLimit(entry.kind)),
            child: Text(
              switch (entry.kind) {
                //: %1 is how many are attached, %2 how many the model takes
                MediaKind.image => tr('%1/%2 pictures'),
                MediaKind.video => tr('%1/%2 clips'),
                MediaKind.audio => tr('%1/%2 recordings'),
              }.arg(entry.used).arg(entry.limit),
              style: TextStyle(
                color: entry.used >= entry.limit
                    ? mq.textSecondary
                    : mq.textTertiary,
                fontSize: MqTheme.fontMicro,
                fontWeight: entry.used > 0 ? FontWeight.w600 : FontWeight.w400,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }

  static String _sizeLimit(MediaKind kind) {
    final bytes = switch (kind) {
      MediaKind.image => ModelCapabilities.maxImageBytes,
      MediaKind.video => ModelCapabilities.maxVideoBytes,
      MediaKind.audio => ModelCapabilities.maxAudioBytes,
    };
    return '${bytes ~/ (1024 * 1024)} MB';
  }
}

/// Which panel the overlay is showing.
///
/// The settings one is only reachable on a narrow window: with room, every
/// setting is its own button on the row above the bar -- see [_SettingsRow] --
/// and each opens a menu of its own rather than a panel of everything.
enum _Panel { none, settings, actor, scene }

/// The actor or the scene on the ad.
///
/// Empty, it is a plain chip that opens the library. Cast, it is one bubble
/// carrying all three things you do to a casting: the face and the name swap
/// them, the cog opens their settings, the cross takes them off. They used to
/// be a chip with a cross floating beside it, which read as two controls that
/// happened to be adjacent, and the settings were reachable from neither.
class _CastChip extends StatefulWidget {
  const _CastChip({
    required this.label,
    required this.emptyIcon,
    required this.name,
    required this.replaceTip,
    required this.settingsTip,
    required this.clearTip,
    required this.onPressed,
    required this.onSettings,
    required this.onCleared,
    required this.settingsPortal,
    required this.settingsPanel,
    this.portrait = '',
    this.lit = false,
  });

  final String label;
  final String emptyIcon;
  final String name;
  final String portrait;

  final String replaceTip;
  final String settingsTip;
  final String clearTip;

  final VoidCallback onPressed;
  final VoidCallback onSettings;
  final VoidCallback onCleared;

  /// The panel hangs off the cog, not off the whole bubble, so it opens over
  /// the button that was actually pressed -- which is why the portal is wrapped
  /// around that button here rather than around the chip.
  final OverlayPortalController settingsPortal;
  final OverlayChildLayoutBuilder settingsPanel;

  /// True while this chip's panel is the one open, so the bar says which of the
  /// two the panel belongs to.
  final bool lit;

  @override
  State<_CastChip> createState() => _CastChipState();
}

class _CastChipState extends State<_CastChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    if (widget.name.isEmpty) {
      return MqChip(
        label: widget.label,
        icon: widget.emptyIcon,
        onPressed: widget.onPressed,
      );
    }

    // One frame around the three targets. Hover lights the whole bubble, and
    // each button lights itself inside it, so it is always clear both that the
    // bubble is live and which part of it is under the pointer.
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: _hovered ? Duration.zero : MqTheme.hoverDuration,
        height: 30,
        padding: const EdgeInsets.only(left: 5, right: 3),
        decoration: BoxDecoration(
          color: widget.lit
              ? mq.surfaceActive
              : _hovered
              ? mq.surfaceHover
              : mq.surfaceSecondary,
          borderRadius: BorderRadius.circular(MqTheme.radiusPill),
          border: Border.all(
            color: widget.lit || _hovered ? mq.borderStrong : mq.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Pressable(
                onTap: widget.onPressed,
                tooltip: widget.replaceTip,
                focusRadius: MqTheme.radiusPill,
                builder: (context, states) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.portrait.isNotEmpty) ...[
                        ClipOval(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: File(widget.portrait).existsSync()
                                ? Image.file(
                                    File(widget.portrait),
                                    fit: BoxFit.cover,
                                  )
                                : ColoredBox(color: mq.surfaceTertiary),
                          ),
                        ),
                        const SizedBox(width: 7),
                      ],
                      Flexible(
                        child: Text(
                          widget.name,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: TextStyle(
                            color: states.active
                                ? mq.textPrimary
                                : mq.textSecondary,
                            fontSize: MqTheme.fontLabel,
                            fontWeight: FontWeight.w500,
                            letterSpacing: MqTheme.trackSmall,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Container(width: 1, height: 16, color: mq.border),
            const SizedBox(width: 2),
            OverlayPortal.overlayChildLayoutBuilder(
              controller: widget.settingsPortal,
              overlayChildBuilder: widget.settingsPanel,
              child: MqIconButton(
                icon: 'settings-3-line',
                tip: widget.settingsTip,
                size: 22,
                onPressed: widget.onSettings,
              ),
            ),
            MqIconButton(
              icon: 'close-line',
              tip: widget.clearTip,
              size: 22,
              destructive: true,
              onPressed: widget.onCleared,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The settings, as data and as two ways of drawing them
// ---------------------------------------------------------------------------

/// One thing the next generation will be.
///
/// Data rather than a widget because it is drawn twice: as a text button on
/// the row above the bar, and as a labelled line in the sheet that replaces
/// that row when there is no space for it.
abstract class _Setting {
  const _Setting();

  String get label;
}

/// A setting with a menu behind it.
class _Choice extends _Setting {
  const _Choice({
    required this.label,
    required this.value,
    required this.current,
    required this.options,
    required this.onPicked,
    this.menuWidth = 220,
  });

  @override
  final String label;

  /// What it is set to, in words. Not always the stored value: "Best" stands
  /// for `high`, "1536 x 1024 · landscape" for `1536x1024`.
  final String value;

  /// The stored value, which is what the menu ticks.
  final String current;

  final List<MenuOption<String>> options;
  final ValueChanged<String> onPicked;
  final double menuWidth;
}

/// A setting with two states. The label is the value: the ad either is
/// subtitled or it is not.
class _Switch extends _Setting {
  const _Switch({
    required this.label,
    required this.value,
    required this.onChanged,
    this.tooltip = '',
  });

  @override
  final String label;

  final bool value;
  final ValueChanged<bool> onChanged;
  final String tooltip;
}

/// A setting that cannot be set, because there is nothing to set it to.
class _Notice extends _Setting {
  const _Notice(this.label);

  @override
  final String label;
}

/// The settings as one line of text buttons, hairlines between them.
///
/// No frames, no fills, no labels: the values alone read as a sentence --
/// "Seedream 4.5 | 2K | Best" -- and a word naming each of them would be six
/// nouns to read past to reach the six answers. What each one means is in its
/// tooltip. The rules are only there to keep two adjacent values from reading
/// as one phrase; they are the lightest line the theme has.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.items});

  final List<_Setting> items;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    final children = <Widget>[];
    for (var i = 0; i < items.length; ++i) {
      if (i > 0) {
        children.add(
          Container(
            width: 1,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            color: mq.divider,
          ),
        );
      }
      children.add(_SettingButton(item: items[i]));
    }

    return Wrap(
      spacing: 0,
      runSpacing: 2,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

/// One setting on that line.
class _SettingButton extends StatelessWidget {
  const _SettingButton({required this.item});

  final _Setting item;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final setting = item;

    if (setting is _Notice) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          setting.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: mq.warningText,
            fontSize: MqTheme.fontLabel,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    /// The frame every one of them shares: nothing at rest, a faint wash under
    /// the pointer. That wash is the whole affordance, which is why the text
    /// is padded enough to give it a shape to be.
    Widget shell(MqStates states, Widget child) => AnimatedContainer(
      duration: states.duration,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: states.pressed
            ? mq.surfaceActive
            : states.hovered
            ? mq.surfaceHover
            : Colors.transparent,
        borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
      ),
      child: child,
    );

    if (setting is _Switch) {
      return Pressable(
        tooltip: setting.tooltip,
        focusRadius: MqTheme.radiusSmall,
        onTap: () => setting.onChanged(!setting.value),
        builder: (context, states) {
          final ink = !setting.value
              ? (states.active ? mq.textSecondary : mq.textTertiary)
              : (states.active ? mq.textPrimary : mq.textSecondary);

          return shell(
            states,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MqIcon(
                  setting.value ? 'check-line' : 'close-line',
                  size: 13,
                  color: ink,
                ),
                const SizedBox(width: 5),
                Text(
                  setting.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    color: ink,
                    fontSize: MqTheme.fontLabel,
                    fontWeight: setting.value
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    final choice = setting as _Choice;
    return Builder(
      // Its own anchor: the menu opens under this value rather than under the
      // row, which is what makes six of them in a line navigable.
      builder: (anchor) => Pressable(
        //: %1 is a setting's name such as "Quality"
        tooltip: tr('Change the %1').arg(choice.label.toLowerCase()),
        focusRadius: MqTheme.radiusSmall,
        onTap: () async {
          final picked = await showChipMenu<String>(
            anchor,
            options: choice.options,
            current: choice.current,
            width: choice.menuWidth,
          );
          if (picked != null) choice.onPicked(picked);
        },
        builder: (context, states) => shell(
          states,
          // Capped, because a model name is whatever the provider called it
          // and "Kling AI Avatar v2 Standard" must not take the row into a
          // second line on its own.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              choice.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                color: states.active ? mq.textPrimary : mq.textSecondary,
                fontSize: MqTheme.fontLabel,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The same settings, stacked, for the window that has no room for the row.
///
/// Label on the left and value on the right, which is the shape a settings
/// list has everywhere: the row above the bar can drop the labels because the
/// six values sit side by side and read as a sentence, and a vertical list
/// cannot -- one value per line with nothing beside it says nothing.
class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.items, required this.onClose});

  final List<_Setting> items;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
      decoration: BoxDecoration(
        color: mq.surface,
        borderRadius: BorderRadius.circular(MqTheme.radiusLarge),
        border: Border.all(color: mq.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('Settings'),
                  style: TextStyle(
                    color: mq.textPrimary,
                    fontSize: MqTheme.fontBody,
                    fontWeight: FontWeight.w600,
                    letterSpacing: MqTheme.trackTitle,
                  ),
                ),
              ),
              MqIconButton(
                icon: 'close-line',
                tip: tr('Close'),
                size: 24,
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: mq.textSecondary,
                        fontSize: MqTheme.fontLabel,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _SettingButton(item: item),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// What the press will cost, beside the button that presses it.
///
/// Not a control: there is nothing to choose. It is the sum of every setting
/// on the row above, and it sits here rather than up there with them because
/// this is where the decision is made -- the last thing read before the send
/// button.
class _PriceTag extends StatelessWidget {
  const _PriceTag({required this.price});

  final String price;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Text(
      price,
      style: TextStyle(
        color: mq.textSecondary,
        fontSize: MqTheme.fontLabel,
        fontWeight: FontWeight.w600,
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
