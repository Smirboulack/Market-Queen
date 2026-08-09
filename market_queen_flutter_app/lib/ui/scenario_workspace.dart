import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/pricing.dart';
import '../i18n/translator.dart';
import 'format.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets/buttons.dart';
import 'widgets/chip.dart';
import 'widgets/composer.dart';
import 'widgets/panels.dart';
import 'widgets/platform_marks.dart';
import 'widgets/script_line.dart';

/// The middle column: the script, and the bar you write it in.
///
/// One line, one scene, still -- that has not changed. What changed is that it
/// is no longer step two of three: the product and the actor are on the rail to
/// the right and Generate is in the bar above, so this panel is only ever about
/// the words.
class ScenarioWorkspace extends StatefulWidget {
  const ScenarioWorkspace({super.key, required this.app});

  final AppState app;

  @override
  State<ScenarioWorkspace> createState() => _ScenarioWorkspaceState();
}

class _ScenarioWorkspaceState extends State<ScenarioWorkspace> {
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final ScrollController _thread = ScrollController();

  /// Roughly the composer's own height, so the last line of the script can be
  /// scrolled clear of it instead of living underneath it.
  static const double _composerReserve = 196;

  bool _composerOpen = true;
  String _beat = 'hook';
  String _nextKind = 'talking';
  int _selected = 0;
  CostEstimate _directCost = CostEstimate.unknown;

  @override
  void initState() {
    super.initState();
    _refreshCost();
    widget.app.project.requestChanged.addListener(_refreshCost);
    widget.app.director.directed.listen(_onDirected);
    widget.app.lineDoctor.rewritten.listen(_onRewritten);
  }

  @override
  void dispose() {
    widget.app.project.requestChanged.removeListener(_refreshCost);
    widget.app.director.directed.remove(_onDirected);
    widget.app.lineDoctor.rewritten.remove(_onRewritten);
    _composer.dispose();
    _composerFocus.dispose();
    _thread.dispose();
    super.dispose();
  }

  void _onDirected(List<Map<String, Object?>> shots) =>
      widget.app.project.applyDirection(shots);

  /// A rewrite lands back in the field it came from, selected, so a bad one is
  /// one keystroke from being replaced and a good one is ready to send.
  void _onRewritten(String line) {
    if (!mounted) return;
    _composer.text = line;
    _composer.selection = TextSelection(
      baseOffset: 0,
      extentOffset: line.length,
    );
    _composerFocus.requestFocus();
  }

  void _refreshCost() {
    final next = widget.app.director.estimate(widget.app.project.toRequest());
    if (!mounted) return;
    setState(() => _directCost = next);
  }

  void _send(String text) {
    // A failed rewrite has nothing to say about the line that replaced it.
    widget.app.lineDoctor.clearError();
    final scenes = widget.app.project.scenes;
    scenes.add(text, _beat);
    final row = scenes.count - 1;
    if (_nextKind == 'broll') scenes.setField(row, 'kind', 'broll');
    _composer.clear();
    setState(() {
      _nextKind = 'talking';
      _selected = row;
      // The beat walks forward on its own: nobody writes two hooks in a row,
      // and re-picking a tab is one click when they do.
      _beat = _nextBeat();
    });
    _scrollToEnd();
  }

  String _nextBeat() {
    final beats = Beat.all;
    for (var i = 0; i < beats.length; ++i) {
      if (beats[i].id == _beat) {
        return i + 1 < beats.length ? beats[i + 1].id : beats.last.id;
      }
    }
    return _beat;
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_thread.hasClients) return;
      _thread.animateTo(
        _thread.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _newScene() {
    setState(() => _composerOpen = true);
    _composer.clear();
    _composerFocus.requestFocus();
  }

  void _runAction(RewriteAction action) {
    widget.app.lineDoctor.rewrite(
      request: widget.app.project.toRequest(),
      action: action.id,
      instruction: action.instruction,
      text: _composer.text,
      beat: _beat,
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.app.project;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MqTheme.pagePadding,
        MqTheme.gapLarge,
        MqTheme.pagePadding,
        MqTheme.gap + 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const SizedBox(height: MqTheme.gap + 2),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                project.scenes,
                widget.app.director,
                widget.app.lineDoctor,
              ]),
              builder: (context, _) => Stack(
                children: [
                  Positioned.fill(child: _sheet()),
                  PositionedDirectional(
                    top: 10,
                    end: 10,
                    child: Column(children: _sheetTools()),
                  ),
                  if (_composerOpen)
                    PositionedDirectional(
                      start: 44,
                      end: 44,
                      bottom: 14,
                      child: Composer(
                        controller: _composer,
                        focusNode: _composerFocus,
                        beat: _beat,
                        busyAction: widget.app.lineDoctor.action,
                        error: widget.app.lineDoctor.error,
                        canAct: !widget.app.lineDoctor.running,
                        onBeatPicked: (id) => setState(() => _beat = id),
                        onSubmitted: _send,
                        onAction: _runAction,
                        onClose: () => setState(() => _composerOpen = false),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: MqTheme.gap),
          ListenableBuilder(
            // The director owns its own error; everything else on this row is
            // the project's.
            listenable: Listenable.merge([project, widget.app.director]),
            builder: (context, _) => _footer(),
          ),
        ],
      ),
    );
  }

  // ---- header --------------------------------------------------------------

  Widget _header() {
    final mq = context.mq;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Scenario'),
                style: TextStyle(
                  color: mq.textPrimary,
                  fontSize: MqTheme.fontHeading,
                  fontWeight: FontWeight.w600,
                  letterSpacing: MqTheme.trackHeading,
                  height: MqTheme.lineTight,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr('Write what they say. One line, one scene.'),
                style: TextStyle(
                  color: mq.textSecondary,
                  fontSize: MqTheme.fontLabel,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: MqTheme.gap),
        ListenableBuilder(
          listenable: widget.app.project.scenes,
          builder: (context, _) => _scenePicker(),
        ),
        const SizedBox(width: 8),
        GhostButton(text: tr('+ New scene'), onPressed: _newScene),
      ],
    );
  }

  /// Which line the sheet is pointing at. On a script of twenty lines this is
  /// the difference between finding scene 14 and scrolling for it.
  Widget _scenePicker() {
    final scenes = widget.app.project.scenes;
    if (scenes.count == 0) {
      return MqChip(label: tr('No scenes yet'), enabled: false);
    }

    final at = _selected.clamp(0, scenes.count - 1);

    // Built through a Builder so the menu can anchor itself under the chip
    // rather than under the whole workspace.
    return Builder(
      builder: (anchor) => MqChip(
        //: %1 is a scene number
        label: tr('Scene %1').arg(at + 1),
        icon: 'clapperboard-line',
        opensMenu: true,
        active: true,
        onPressed: () => _pickScene(anchor, at),
      ),
    );
  }

  Future<void> _pickScene(BuildContext anchor, int at) async {
    final mq = anchor.mq;
    final scenes = widget.app.project.scenes;
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchor).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final origin = box.localToGlobal(
      Offset(0, box.size.height + 4),
      ancestor: overlay,
    );

    final picked = await showMenu<int>(
      context: anchor,
      constraints: const BoxConstraints(minWidth: 260, maxHeight: 360),
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy,
        overlay.size.width - origin.dx - 300,
        0,
      ),
      items: [
        for (var i = 0; i < scenes.count; ++i)
          PopupMenuItem<int>(
            value: i,
            height: 34,
            child: Text(
              //: %1 is a scene number, %2 the line it says
              tr('%1. %2').arg(i + 1).arg(
                    scenes.scenes[i].line.isEmpty
                        ? tr('(empty)')
                        : scenes.scenes[i].line,
                  ),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: i == at ? mq.primaryText : mq.textPrimary,
                fontSize: MqTheme.fontLabel,
              ),
            ),
          ),
      ],
    );

    if (picked != null && mounted) setState(() => _selected = picked);
  }

  // ---- the sheet -----------------------------------------------------------

  Widget _sheet() {
    final mq = context.mq;
    final scenes = widget.app.project.scenes;

    return Container(
      decoration: BoxDecoration(
        color: mq.surface,
        borderRadius: BorderRadius.circular(MqTheme.radiusLarge),
        border: Border.all(color: mq.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: scenes.count == 0
          ? _emptySheet()
          : ListView.builder(
              controller: _thread,
              padding: EdgeInsets.fromLTRB(
                14,
                14,
                14,
                _composerOpen ? _composerReserve : 16,
              ),
              itemCount: scenes.count,
              itemBuilder: (context, index) {
                final scene = scenes.scenes[index];
                return ScriptLine(
                  // Keyed on the scene's own id: editing one line must not
                  // rebuild -- and so unfocus -- the field being typed into.
                  key: ValueKey(scene.id),
                  position: index,
                  total: scenes.count,
                  line: scene.line,
                  kind: scene.kind,
                  beat: scene.beat,
                  imagePrompt: scene.imagePrompt,
                  seconds: scenes.seconds(index),
                  directed: scene.directed,
                  selected: index == _selected,
                  onSelected: () => setState(() => _selected = index),
                  onLineEdited: (text) => scenes.setField(index, 'line', text),
                  onKindToggled: () => scenes.setField(
                    index,
                    'kind',
                    scene.kind == 'broll' ? 'talking' : 'broll',
                  ),
                  onMoveRequested: (to) => scenes.move(index, to),
                  onRemoveRequested: () => scenes.remove(index),
                );
              },
            ),
    );
  }

  Widget _emptySheet() {
    final mq = context.mq;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        18,
        24,
        _composerOpen ? _composerReserve : 24,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '1',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: mq.textDisabled,
                fontSize: MqTheme.fontLabel,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              tr('Start with the hook. You have three seconds.'),
              style: TextStyle(
                color: mq.textTertiary,
                fontSize: MqTheme.fontBody,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _sheetTools() {
    final director = widget.app.director;
    final scenes = widget.app.project.scenes;

    return [
      Builder(
        builder: (anchor) => _SheetTool(
          icon: 'lightbulb-line',
          tip: tr('How the five beats work'),
          onPressed: () => _showTips(anchor),
        ),
      ),
      const SizedBox(height: 4),
      _SheetTool(
        icon: director.running ? 'loader-4-line' : 'magic-line',
        tip: director.running
            ? tr('Directing…')
            : _directCost.known
            //: %1 is a price
            ? tr('Direct the shots — %1').arg(
                Format.estimated(_directCost.amount),
              )
            : tr('Direct the shots'),
        onPressed: director.running || scenes.count == 0
            ? null
            : () => director.direct(widget.app.project.toRequest()),
      ),
    ];
  }

  Future<void> _showTips(BuildContext anchor) async {
    final mq = anchor.mq;
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchor).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    // Hung off the button's left edge: the rail is to its right and there is no
    // room that way.
    final origin = box.localToGlobal(
      Offset(0, box.size.height + 6),
      ancestor: overlay,
    );

    await showMenu<void>(
      context: anchor,
      constraints: const BoxConstraints(minWidth: 320, maxWidth: 360),
      position: RelativeRect.fromLTRB(
        origin.dx - 330,
        origin.dy,
        overlay.size.width - origin.dx - box.size.width,
        0,
      ),
      items: [
        for (final beat in Beat.all)
          PopupMenuItem<void>(
            enabled: false,
            height: 44,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  beat.label,
                  style: TextStyle(
                    color: mq.textPrimary,
                    fontSize: MqTheme.fontLabel,
                    fontWeight: FontWeight.w600,
                    height: MqTheme.lineTight,
                  ),
                ),
                Text(
                  beat.advice,
                  style: TextStyle(
                    color: mq.textSecondary,
                    fontSize: MqTheme.fontSmall,
                    height: MqTheme.lineTight,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---- footer --------------------------------------------------------------

  Widget _footer() {
    final mq = context.mq;
    final project = widget.app.project;
    final director = widget.app.director;
    final seconds = project.spokenSeconds;
    final target = project.targetSeconds;
    final over = target > 0 && seconds > target;

    return Row(
      children: [
        Text(
          //: %1 is a count of scenes, %2 a duration in seconds
          tr('%1 scene(s) · %2 s')
              .arg(project.scenes.count)
              .arg(seconds.toStringAsFixed(1)),
          style: TextStyle(
            color: over ? mq.warningText : mq.textSecondary,
            fontSize: MqTheme.fontSmall,
          ),
        ),
        const SizedBox(width: 14),
        _EstimateButton(app: widget.app),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            director.error.isNotEmpty
                ? director.error
                : over
                //: %1 is a duration in seconds
                ? tr('Longer than the %1 s you are aiming for.').arg(target)
                : tr('15 to 30 s converts best'),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: director.error.isNotEmpty
                  ? mq.error
                  : over
                  ? mq.warningText
                  : mq.textTertiary,
              fontSize: MqTheme.fontSmall,
            ),
          ),
        ),
        const SizedBox(width: 14),
        _BestFor(
          aspect: project.aspectRatio,
          onPicked: project.setAspectRatio,
        ),
      ],
    );
  }
}

/// One of the two glyphs floating over the sheet.
class _SheetTool extends StatelessWidget {
  const _SheetTool({
    required this.icon,
    required this.tip,
    required this.onPressed,
  });

  final String icon;
  final String tip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      enabled: onPressed != null,
      onTap: onPressed,
      tooltip: tip,
      focusRadius: MqTheme.radiusSmall + 2,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: states.pressed
              ? mq.surfaceActive
              : states.hovered
              ? mq.surfaceHover
              : mq.surfaceSecondary,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall + 2),
          border: Border.all(
            color: states.active ? mq.borderStrong : mq.border,
          ),
        ),
        child: MqIcon(
          icon,
          size: 16,
          color: !states.enabled
              ? mq.textDisabled
              : states.active
              ? mq.textPrimary
              : mq.textSecondary,
        ),
      ),
    );
  }
}

/// The running total, and the breakdown behind it.
///
/// A single figure on the footer is the one everybody reads; the panel it opens
/// is what stops that figure from being a number you have to trust.
class _EstimateButton extends StatelessWidget {
  const _EstimateButton({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return ListenableBuilder(
      listenable: app.project,
      builder: (context, _) {
        final request = app.project.toRequest();
        final breakdown = app.pricing.estimate(request);

        return Pressable(
          onTap: () => _show(context, request),
          focusRadius: MqTheme.radiusSmall,
          builder: (context, states) => AnimatedContainer(
            duration: states.duration,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: states.active ? mq.surfaceHover : Colors.transparent,
              borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
            ),
            child: Text(
              //: %1 is a price
              tr('Est. cost %1').arg(Format.estimated(breakdown.total)),
              style: TextStyle(
                color: states.active ? mq.textPrimary : mq.textSecondary,
                fontSize: MqTheme.fontSmall,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _show(
    BuildContext context,
    Map<String, Object?> request,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final anchor = box.localToGlobal(Offset.zero, ancestor: overlay);

    await showMenu<void>(
      context: context,
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 340),
      position: RelativeRect.fromLTRB(
        anchor.dx,
        // Above the footer rather than below it: there is no room under it.
        anchor.dy - 320,
        overlay.size.width - anchor.dx - 340,
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

/// Which platforms the chosen shape suits, and the way to change it.
class _BestFor extends StatelessWidget {
  const _BestFor({required this.aspect, required this.onPicked});

  final String aspect;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tr('Best for'),
          style: TextStyle(
            color: mq.textTertiary,
            fontSize: MqTheme.fontSmall,
          ),
        ),
        const SizedBox(width: 8),
        for (final platform in AdPlatform.values)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 4),
            child: Pressable(
              onTap: () => onPicked(platform.nativeAspect),
              //: %1 is a platform name, %2 an aspect ratio like 9:16
              tooltip: tr('%1 — %2')
                  .arg(platform.label)
                  .arg(platform.nativeAspect),
              focusRadius: MqTheme.radiusSmall,
              builder: (context, states) {
                final suits = platform.aspects.contains(aspect);
                return AnimatedContainer(
                  duration: states.duration,
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: states.active
                        ? mq.surfaceHover
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
                  ),
                  child: PlatformMark(
                    platform,
                    size: 17,
                    // Dim rather than hidden: the ones this shape does not suit
                    // are the reason the row is worth reading.
                    color: suits
                        ? (states.active ? mq.textPrimary : mq.textSecondary)
                        : mq.textDisabled,
                  ),
                );
              },
            ),
          ),
        _AspectMenu(aspect: aspect, onPicked: onPicked),
      ],
    );
  }
}

class _AspectMenu extends StatelessWidget {
  const _AspectMenu({required this.aspect, required this.onPicked});

  final String aspect;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      tooltip: tr('Aspect ratio'),
      focusRadius: MqTheme.radiusSmall,
      onTap: () async {
        final box = context.findRenderObject() as RenderBox?;
        final overlay =
            Overlay.of(context).context.findRenderObject() as RenderBox?;
        if (box == null || overlay == null) return;

        final anchor = box.localToGlobal(Offset.zero, ancestor: overlay);

        final picked = await showMenu<String>(
          context: context,
          constraints: const BoxConstraints(minWidth: 180),
          position: RelativeRect.fromLTRB(
            anchor.dx - 150,
            anchor.dy - 150,
            overlay.size.width - anchor.dx - 30,
            0,
          ),
          items: [
            for (final option in const [
              ('9:16', 'Vertical'),
              ('1:1', 'Square'),
              ('16:9', 'Wide'),
            ])
              PopupMenuItem<String>(
                value: option.$1,
                height: 34,
                child: Text(
                  '${option.$1}   ${tr(option.$2)}',
                  style: TextStyle(
                    color: option.$1 == aspect
                        ? mq.primaryText
                        : mq.textPrimary,
                    fontSize: MqTheme.fontLabel,
                    fontWeight: option.$1 == aspect
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
          ],
        );

        if (picked != null) onPicked(picked);
      },
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: states.active ? mq.surfaceHover : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        ),
        child: MqIcon(
          'arrow-down-s-line',
          size: 16,
          color: states.active ? mq.textPrimary : mq.textTertiary,
        ),
      ),
    );
  }
}
