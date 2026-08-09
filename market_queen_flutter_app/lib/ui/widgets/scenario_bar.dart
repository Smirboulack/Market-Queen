import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../advice.dart';
import '../theme.dart';
import 'buttons.dart';
import 'chip.dart';

/// One of the three things the model can do to a scenario you have written.
class RewriteAction {
  const RewriteAction(this.id, this.label, this.icon, this.instruction);

  final String id;
  final String label;
  final String icon;

  /// What the model is actually told. Kept next to the label so the chip and
  /// the prompt cannot say different things.
  final String instruction;

  static List<RewriteAction> get all => [
    RewriteAction(
      'enhance',
      tr('Improve with AI'),
      'magic-line',
      'Rewrite this scenario so it lands harder, without inventing any claim '
          'that is not already in it. Keep it roughly the same length and keep '
          'it as one continuous take.',
    ),
    RewriteAction(
      'shorten',
      tr('Shorten'),
      'text-shorten',
      'Cut this scenario to the shortest version that still says the same '
          'thing. Aim for about twenty seconds of speech.',
    ),
    RewriteAction(
      'punchier',
      tr('Make it punchier'),
      'flashlight-line',
      'Rewrite this scenario with more bite: stronger verbs, no hedging, no '
          'filler words. Same meaning, same length or shorter.',
    ),
  ];
}

/// The bar the ad is written in.
///
/// It is the whole studio now. What used to be a right-hand rail of thirty
/// controls is a row of four chips: the ceiling on the length, the shape, the
/// subtitles, and the lightbulb that offers advice instead of imposing it.
/// Everything else about the ad is said in the box in the middle, in the user's
/// own words, because that is the only description of a UGC ad that comes back
/// sounding like one.
class ScenarioBar extends StatefulWidget {
  const ScenarioBar({
    super.key,
    required this.app,
    required this.controller,
    required this.onGenerate,
  });

  final AppState app;

  /// Owned by the page, so the text survives the panels above folding.
  final TextEditingController controller;

  final VoidCallback onGenerate;

  @override
  State<ScenarioBar> createState() => _ScenarioBarState();
}

class _ScenarioBarState extends State<ScenarioBar> {
  final FocusNode _focus = FocusNode();
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    widget.app.lineDoctor.rewritten.listen(_onRewritten);
  }

  @override
  void dispose() {
    widget.app.lineDoctor.rewritten.remove(_onRewritten);
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  void _onFocus() => setState(() {});

  /// A rewrite lands back in the field it came from, selected, so a bad one is
  /// one keystroke from being replaced and a good one is already saved.
  void _onRewritten(String script) {
    if (!mounted) return;
    widget.controller.text = script;
    widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: script.length,
    );
    widget.app.project.setScript(script);
    _focus.requestFocus();
  }

  void _runAction(RewriteAction action) {
    widget.app.lineDoctor.rewrite(
      request: widget.app.request(),
      action: action.id,
      instruction: action.instruction,
      text: widget.controller.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: _focus.hasFocus || _hovered
            ? Duration.zero
            : MqTheme.hoverDuration,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: mq.surface,
          borderRadius: BorderRadius.circular(MqTheme.radiusLarge),
          border: Border.all(
            color: _focus.hasFocus
                ? mq.primary
                : _hovered
                ? mq.borderStrong
                : mq.border,
          ),
          // The bar is the thing you are addressing; with the caret in it, it
          // should be unmistakably the live object on the page.
          boxShadow: _focus.hasFocus
              ? [
                  BoxShadow(
                    color: mq.focusRing.withValues(alpha: 0.22),
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: ListenableBuilder(
          listenable: Listenable.merge([
            widget.app.project,
            widget.app.lineDoctor,
            widget.app.pipeline,
          ]),
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _settingsRow(),
              const SizedBox(height: MqTheme.gap),
              _field(),
              if (widget.app.lineDoctor.error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  widget.app.lineDoctor.error,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mq.error,
                    fontSize: MqTheme.fontSmall,
                  ),
                ),
              ],
              const SizedBox(height: MqTheme.gap),
              _actionsRow(),
            ],
          ),
        ),
      ),
    );
  }

  // ---- the settings row ----------------------------------------------------

  Widget _settingsRow() {
    final project = widget.app.project;

    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              MqPickChip(
                label: tr('Maximum length'),
                icon: 'timer-line',
                value: project.maxSeconds == 0 ? '' : '${project.maxSeconds}',
                onPicked: (value) =>
                    project.setMaxSeconds(int.tryParse(value) ?? 0),
                options: [
                  MenuOption(tr('As long as it takes'), ''),
                  MenuOption(tr('15 s'), '15'),
                  MenuOption(tr('20 s'), '20'),
                  MenuOption(tr('30 s'), '30'),
                  MenuOption(tr('45 s'), '45'),
                  MenuOption(tr('60 s'), '60'),
                ],
              ),
              MqPickChip(
                label: tr('Format'),
                icon: 'layout-line',
                value: project.aspectRatio,
                onPicked: project.setAspectRatio,
                options: [
                  MenuOption(tr('Vertical 9:16'), '9:16'),
                  MenuOption(tr('Square 1:1'), '1:1'),
                  MenuOption(tr('Wide 16:9'), '16:9'),
                ],
              ),
              MqChip(
                label: tr('Auto subtitles'),
                icon: 'check-double-line',
                active: project.captions,
                onPressed: () => project.setCaptions(!project.captions),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Builder(
          builder: (anchor) => MqChip(
            label: tr('Advice'),
            icon: 'lightbulb-line',
            active: false,
            onPressed: () => showScenarioAdvice(anchor),
          ),
        ),
      ],
    );
  }

  // ---- the field -----------------------------------------------------------

  Widget _field() {
    final mq = context.mq;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 96, maxHeight: 260),
      // Enter breaks the line here, unlike every other input in the app: this
      // is a paragraph, not a message, and Generate costs money.
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): DoNothingIntent(),
        },
        child: TextField(
          controller: widget.controller,
          focusNode: _focus,
          maxLines: null,
          expands: false,
          cursorColor: mq.primary,
          onChanged: widget.app.project.setScript,
          style: TextStyle(
            color: mq.textPrimary,
            fontSize: MqTheme.fontBody,
            height: MqTheme.lineBody,
          ),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintText: tr(
              'Write the scenario of your UGC ad, as precisely as you can.',
            ),
            hintStyle: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontBody,
            ),
          ),
        ),
      ),
    );
  }

  // ---- the actions row -----------------------------------------------------

  Widget _actionsRow() {
    final mq = context.mq;
    final app = widget.app;
    final doctor = app.lineDoctor;
    final project = app.project;
    final pipeline = app.pipeline;
    final hasText = widget.controller.text.trim().isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final action in RewriteAction.all)
                MqChip(
                  label: action.label,
                  icon: action.icon,
                  active: false,
                  leading: doctor.action == action.id
                      ? SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(mq.primary),
                          ),
                        )
                      : null,
                  // A rewrite with nothing to rewrite is not an action.
                  enabled: hasText && !doctor.running,
                  onPressed: () => _runAction(action),
                ),
            ],
          ),
        ),
        const SizedBox(width: MqTheme.gap),
        PrimaryButton(
          text: pipeline.running ? tr('Generating…') : tr('Generate'),
          icon: 'magic-line',
          loading: pipeline.running,
          enabled: project.complete && !pipeline.running,
          //: %1 is a list like "a product, an actor"
          tooltip: project.missing.isEmpty
              ? ''
              : tr('Still needs %1.').arg(project.missing.join(', ')),
          onPressed: widget.onGenerate,
        ),
      ],
    );
  }
}
