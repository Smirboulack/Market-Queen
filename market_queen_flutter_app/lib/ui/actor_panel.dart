import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../app_state.dart';
import '../core/pricing.dart';
import '../i18n/translator.dart';
import '../providers/types.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets/buttons.dart';
import 'widgets/chip.dart';
import 'widgets/fields.dart';
import 'widgets/image_drop_grid.dart';
import 'widgets/prompt_bar.dart';

/// The casting drawer.
///
/// Three prompt bars, one under the other: who they are, where they are, how
/// they sound. No labelled fields, no stacked dropdowns -- the optional traits
/// are chips inside the first bar, and the four voice settings hide behind four
/// presets, because nobody tunes similarity_boost by hand on the first pass.
class ActorPanel extends StatefulWidget {
  const ActorPanel({super.key, required this.app, required this.onClose});

  final AppState app;
  final VoidCallback onClose;

  @override
  State<ActorPanel> createState() => _ActorPanelState();
}

class _ActorPanelState extends State<ActorPanel> {
  final _brief = TextEditingController();
  final _decor = TextEditingController();
  final _audition = TextEditingController();

  final Player _player = Player();

  CostEstimate _castCost = CostEstimate.unknown;
  CostEstimate _auditionCost = CostEstimate.unknown;
  bool _fineTuning = false;

  List<VoiceOption> _voices = const [];
  String _lastSample = '';

  @override
  void initState() {
    super.initState();
    _audition.text = tr('Honestly, I did not think this would work.');
    _resync();
    _refreshCosts();

    widget.app.project.cleared.addListener(_resync);
    widget.app.project.actorReset.addListener(_resync);
    widget.app.voiceBooth.addListener(_onBooth);
    widget.app.voicesLoaded.listen(_onVoicesLoaded);
    widget.app.voicesFailed.listen(_onVoicesFailed);
  }

  @override
  void dispose() {
    widget.app.project.cleared.removeListener(_resync);
    widget.app.project.actorReset.removeListener(_resync);
    widget.app.voiceBooth.removeListener(_onBooth);
    widget.app.voicesLoaded.remove(_onVoicesLoaded);
    widget.app.voicesFailed.remove(_onVoicesFailed);
    _brief.dispose();
    _decor.dispose();
    _audition.dispose();
    _player.dispose();
    super.dispose();
  }

  Map<String, Object?> get _actor => widget.app.project.actor;

  String _setting(String key) => '${_actor[key] ?? ''}';

  double _number(String key, double fallback) {
    final value = _actor[key];
    return value is num ? value.toDouble() : fallback;
  }

  String _trait(String key) {
    final traits = _actor['traits'];
    return traits is Map ? '${traits[key] ?? ''}' : '';
  }

  void _setTrait(String key, String value) {
    final traits = _actor['traits'];
    final next = <String, Object?>{
      if (traits is Map) ...traits.cast<String, Object?>(),
      key: value,
    };
    widget.app.project.setActorField('traits', next);
  }

  void _resync() {
    if (!mounted) return;
    setState(() {
      _brief.text = _setting('brief');
      _decor.text = _setting('decor');
    });
  }

  void _refreshCosts() {
    setState(() {
      _castCost = widget.app.casting.estimate(4);
      _auditionCost = widget.app.voiceBooth.estimate(_audition.text);
    });
  }

  /// A fresh audition plays itself: hearing the actor is the whole point of the
  /// button that produced it.
  void _onBooth() {
    final sample = widget.app.voiceBooth.samplePath;
    if (sample.isEmpty || sample == _lastSample) return;
    _lastSample = sample;
    _player.open(Media(Uri.file(sample).toString()));
  }

  void _onVoicesLoaded(({String providerId, List<VoiceOption> voices}) event) {
    if (!mounted) return;
    setState(() => _voices = event.voices);
  }

  void _onVoicesFailed(({String providerId, String error}) event) {
    widget.app.log.error(tr('Could not load voices: %1').arg(event.error));
  }

  String get _voiceLabel {
    final id = _setting('voiceId');
    if (id.isEmpty) return '';
    for (final voice in _voices) {
      if (voice.id == id) {
        return voice.description.isEmpty
            ? voice.label
            : '${voice.label} — ${voice.description}';
      }
    }
    return id;
  }

  Future<void> _pickVoice() async {
    if (_voices.isEmpty) {
      await widget.app.loadVoices(
          widget.app.settings.prefString('voiceProvider', 'elevenlabs'));
      if (!mounted) return;
    }
    if (_voices.isEmpty) return;

    final mq = context.mq;
    final picked = await showMenu<String>(
      context: context,
      color: mq.surface,
      surfaceTintColor: Colors.transparent,
      constraints: const BoxConstraints(minWidth: 240, maxHeight: 360),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        side: BorderSide(color: mq.border),
      ),
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width - 420,
        220,
        40,
        0,
      ),
      items: [
        for (final voice in _voices)
          PopupMenuItem<String>(
            value: voice.id,
            height: 32,
            child: Text(
              voice.description.isEmpty
                  ? voice.label
                  : '${voice.label} — ${voice.description}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: voice.id == _setting('voiceId') ? mq.accent : mq.text,
                fontSize: MqTheme.fontSmall,
              ),
            ),
          ),
      ],
    );

    if (picked != null) widget.app.project.setActorField('voiceId', picked);
  }

  Future<void> _pickReferences() async {
    final files = await openFiles(acceptedTypeGroups: const [imageTypeGroup]);
    if (files.isEmpty) return;
    widget.app.project.addImages('actor', [for (final f in files) f.path]);
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final app = widget.app;
    final project = app.project;

    return Container(
      decoration: BoxDecoration(
        color: mq.surface,
        border: Border.all(color: mq.border),
      ),
      padding: const EdgeInsets.all(MqTheme.gapLarge),
      child: ListenableBuilder(
        // One rebuild source for the whole drawer: the project owns the actor,
        // casting owns the candidates, the booth owns the audition.
        listenable: Listenable.merge([project, app.casting, app.voiceBooth, app.actors]),
        builder: (context, _) {
          final portrait = '${project.actor['portraitPath'] ?? ''}';
          final references = project.imagesFor('actor');

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    tr('Actor'),
                    style: TextStyle(
                      color: mq.text,
                      fontSize: MqTheme.fontTitle,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  MqIconButton(icon: 'close-line', onPressed: widget.onClose),
                ],
              ),
              const SizedBox(height: MqTheme.gap),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (app.actors.count > 0) ...[
                        _savedActors(mq),
                        const SizedBox(height: MqTheme.gap),
                      ],
                      _castingBar(mq, references),
                      const SizedBox(height: 8),
                      _castingStatus(mq, portrait, references),
                      if (app.casting.error.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          app.casting.error,
                          style: TextStyle(
                              color: mq.danger, fontSize: MqTheme.fontSmall),
                        ),
                      ],
                      const SizedBox(height: MqTheme.gap),
                      _candidates(mq, portrait),
                      const SizedBox(height: MqTheme.gap),
                      PromptBar(
                        controller: _decor,
                        placeholder: tr('Where they are. A small bathroom, '
                            'towels on the floor…'),
                        minHeight: 40,
                        submitIcon: 'check-line',
                        onChanged: (text) =>
                            project.setActorField('decor', text),
                        onSubmitted: (text) =>
                            project.setActorField('decor', text),
                      ),
                      const SizedBox(height: MqTheme.gap),
                      _auditionBar(mq),
                      const SizedBox(height: 8),
                      _presets(),
                      const SizedBox(height: 8),
                      _fineTuneToggle(mq),
                      if (_fineTuning) ...[
                        const SizedBox(height: 6),
                        _sliders(),
                      ],
                      if (app.voiceBooth.error.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          app.voiceBooth.error,
                          style: TextStyle(
                              color: mq.danger, fontSize: MqTheme.fontSmall),
                        ),
                      ],
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
              if (portrait.isNotEmpty) ...[
                const SizedBox(height: MqTheme.gap),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${project.actor['name'] ?? ''}'.isEmpty
                            ? app.actors.suggestedName()
                            : '${project.actor['name']}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: mq.textDim,
                          fontSize: MqTheme.fontSmall,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PrimaryButton(
                      text: '${project.actor['id'] ?? ''}'.isEmpty
                          ? tr('Keep this actor')
                          : tr('Update'),
                      onPressed: () {
                        final id = app.actors.save(project.actor);
                        final kept = app.actors.actor(id);
                        project.setActorField('id', id);
                        project.setActorField('name', kept['name']);
                        if (kept['portraitPath'] != null) {
                          project.setActorField(
                              'portraitPath', kept['portraitPath']);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _savedActors(MqTheme mq) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Your actors'),
          style: TextStyle(
            color: mq.textFaint,
            fontSize: MqTheme.fontSmall,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.app.actors.count,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final saved = widget.app.actors.actors[index];
              final id = '${saved['id'] ?? ''}';
              final current = '${widget.app.project.actor['id'] ?? ''}' == id;

              return _SavedActor(
                path: '${saved['portraitPath'] ?? ''}',
                current: current,
                onTap: () => widget.app.project.applyActor(saved),
                onRemove: () => widget.app.actors.remove(id),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _castingBar(MqTheme mq, List<String> references) {
    final project = widget.app.project;

    return PromptBar(
      controller: _brief,
      placeholder: tr('Describe the person. Ordinary face, ordinary room.'),
      minHeight: 56,
      busy: widget.app.casting.running,
      submitIcon: 'magic-line',
      onChanged: (text) => project.setActorField('brief', text),
      onSubmitted: (text) {
        project.setActorField('brief', text);
        widget.app.casting.generate(project.actor);
      },
      chips: [
        MqChoiceChip(
          label: tr('Gender'),
          value: _trait('gender'),
          onPicked: (v) => _setTrait('gender', v),
          options: [
            MenuOption(tr('a woman'), 'a woman'),
            MenuOption(tr('a man'), 'a man'),
            MenuOption(tr('a non-binary person'), 'a non-binary person'),
          ],
        ),
        MqChoiceChip(
          label: tr('Age'),
          value: _trait('age'),
          onPicked: (v) => _setTrait('age', v),
          options: [
            MenuOption(tr('early twenties'), 'around 22 years old'),
            MenuOption(tr('late twenties'), 'around 27 years old'),
            MenuOption(tr('thirties'), 'around 35 years old'),
            MenuOption(tr('forties'), 'around 45 years old'),
            MenuOption(tr('fifties or older'), 'around 58 years old'),
          ],
        ),
        MqChoiceChip(
          label: tr('Dress'),
          value: _trait('style'),
          onPicked: (v) => _setTrait('style', v),
          options: [
            MenuOption(tr('casual'), 'dressed casually in a plain t-shirt'),
            MenuOption(tr('sportswear'), 'in sportswear'),
            MenuOption(tr('office'), 'in office clothes'),
            MenuOption(tr('streetwear'), 'in streetwear'),
          ],
        ),
        MqChoiceChip(
          label: tr('Energy'),
          value: _trait('energy'),
          onPicked: (v) => _setTrait('energy', v),
          options: [
            MenuOption(tr('calm'), 'calm, low energy'),
            MenuOption(tr('upbeat'), 'upbeat and animated'),
            MenuOption(tr('just woke up'), 'tired, just woke up'),
            MenuOption(tr('warm'), 'warm and friendly'),
          ],
        ),
        MqChip(
          label: tr('Reference'),
          //: %1 is a count of photos
          value: references.isEmpty
              ? ''
              : tr('%1 photo(s)').arg(references.length),
          icon: references.isEmpty ? 'image-add-line' : 'image-line',
          onPressed: _pickReferences,
        ),
      ],
    );
  }

  Widget _castingStatus(MqTheme mq, String portrait, List<String> references) {
    final casting = widget.app.casting;

    return Row(
      children: [
        Expanded(
          child: Text(
            casting.running
                //: %1 and %2 are counts of portraits
                ? tr('Casting... %1 of %2')
                    .arg(casting.received)
                    .arg(casting.requested)
                : _castCost.known
                    //: %1 is a price
                    ? tr('Four faces for %1')
                        .arg(Format.estimated(_castCost.amount))
                    : tr('price unknown'),
            style: TextStyle(color: mq.textFaint, fontSize: MqTheme.fontSmall),
          ),
        ),
        if (casting.running)
          Pressable(
            onTap: casting.cancel,
            builder: (context, hovered, pressed) => Text(
              tr('Cancel'),
              style: TextStyle(color: mq.danger, fontSize: MqTheme.fontSmall),
            ),
          ),
        if (references.isNotEmpty && portrait != references.first)
          Pressable(
            onTap: () => widget.app.project
                .setActorField('portraitPath', references.first),
            builder: (context, hovered, pressed) => Text(
              tr('Use my photo'),
              style: TextStyle(color: mq.accent, fontSize: MqTheme.fontSmall),
            ),
          ),
      ],
    );
  }

  Widget _candidates(MqTheme mq, String portrait) {
    final candidates = widget.app.casting.candidates;
    if (candidates.isEmpty && portrait.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final candidate in candidates)
          _Face(
            path: candidate.path,
            chosen: portrait == candidate.path,
            onTap: () => widget.app.project
                .setActorField('portraitPath', candidate.path),
          ),
        // The kept portrait stays visible after a batch is replaced.
        if (portrait.isNotEmpty && candidates.isEmpty)
          _Face(path: portrait, chosen: true, onTap: null),
      ],
    );
  }

  Widget _auditionBar(MqTheme mq) {
    return PromptBar(
      controller: _audition,
      placeholder: tr('A line to hear them say…'),
      minHeight: 40,
      busy: widget.app.voiceBooth.auditioning,
      submitIcon: 'play-fill',
      onChanged: (text) => setState(
          () => _auditionCost = widget.app.voiceBooth.estimate(text)),
      onSubmitted: (text) =>
          widget.app.voiceBooth.audition(widget.app.project.actor, text),
      chips: [
        MqChip(
          label: tr('Voice'),
          value: _voiceLabel,
          icon: 'mic-line',
          opensMenu: true,
          onPressed: _pickVoice,
        ),
        MqChip(
          label: tr('Load voices'),
          icon: 'refresh-line',
          onPressed: () => widget.app.loadVoices(
              widget.app.settings.prefString('voiceProvider', 'elevenlabs')),
        ),
      ],
    );
  }

  /// Four presets instead of four sliders: nobody sets similarity_boost by hand
  /// before they have heard anything.
  Widget _presets() {
    const presets = [
      (label: 'Natural', s: 0.35, m: 0.80, y: 0.45),
      (label: 'Composed', s: 0.65, m: 0.85, y: 0.20),
      (label: 'Lively', s: 0.25, m: 0.75, y: 0.60),
      (label: 'Intense', s: 0.15, m: 0.70, y: 0.80),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final preset in presets)
          MqChip(
            label: tr(preset.label),
            active: (_number('voiceStability', 0.45) - preset.s).abs() < 0.01 &&
                (_number('voiceStyle', 0.35) - preset.y).abs() < 0.01,
            onPressed: () {
              widget.app.project.setActorField('voiceStability', preset.s);
              widget.app.project.setActorField('voiceSimilarity', preset.m);
              widget.app.project.setActorField('voiceStyle', preset.y);
            },
          ),
      ],
    );
  }

  Widget _fineTuneToggle(MqTheme mq) {
    return Row(
      children: [
        Text(
          _auditionCost.known ? Format.estimated(_auditionCost.amount) : '',
          style: TextStyle(color: mq.textFaint, fontSize: MqTheme.fontSmall),
        ),
        const Spacer(),
        Pressable(
          onTap: () => setState(() => _fineTuning = !_fineTuning),
          builder: (context, hovered, pressed) => Text(
            _fineTuning ? tr('Hide the sliders') : tr('Fine-tune'),
            style: TextStyle(color: mq.accent, fontSize: MqTheme.fontSmall),
          ),
        ),
      ],
    );
  }

  Widget _sliders() {
    final project = widget.app.project;

    return Column(
      children: [
        LabeledSlider(
          label: tr('Stability'),
          value: _number('voiceStability', 0.45),
          onChanged: (v) => project.setActorField('voiceStability', v),
        ),
        LabeledSlider(
          label: tr('Similarity'),
          value: _number('voiceSimilarity', 0.8),
          onChanged: (v) => project.setActorField('voiceSimilarity', v),
        ),
        LabeledSlider(
          label: tr('Style'),
          value: _number('voiceStyle', 0.35),
          onChanged: (v) => project.setActorField('voiceStyle', v),
        ),
        LabeledSlider(
          label: tr('Speed'),
          from: 0.7,
          to: 1.2,
          value: _number('voiceSpeed', 1.0),
          onChanged: (v) => project.setActorField('voiceSpeed', v),
        ),
      ],
    );
  }
}

class _SavedActor extends StatefulWidget {
  const _SavedActor({
    required this.path,
    required this.current,
    required this.onTap,
    required this.onRemove,
  });

  final String path;
  final bool current;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_SavedActor> createState() => _SavedActorState();
}

class _SavedActorState extends State<_SavedActor> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 56,
          height: 76,
          decoration: BoxDecoration(
            color: mq.background,
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
            border: Border.all(
              color: widget.current
                  ? mq.accent
                  : _hovered
                      ? mq.borderStrong
                      : mq.border,
              width: widget.current ? 2 : 1,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(MqTheme.radiusSmall - 1),
                child: LocalImage(widget.path),
              ),
              if (_hovered)
                Positioned(
                  right: 1,
                  top: 1,
                  child: MqIconButton(
                    icon: 'close-line',
                    destructive: true,
                    size: 20,
                    onPressed: widget.onRemove,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Face extends StatefulWidget {
  const _Face({required this.path, required this.chosen, required this.onTap});

  final String path;
  final bool chosen;
  final VoidCallback? onTap;

  @override
  State<_Face> createState() => _FaceState();
}

class _FaceState extends State<_Face> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 84,
          height: 112,
          decoration: BoxDecoration(
            color: mq.background,
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
            border: Border.all(
              color: widget.chosen
                  ? mq.accent
                  : _hovered
                      ? mq.borderStrong
                      : mq.border,
              width: widget.chosen ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall - 1),
            child: LocalImage(widget.path),
          ),
        ),
      ),
    );
  }
}
