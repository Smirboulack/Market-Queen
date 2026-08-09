import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../app_state.dart';
import '../core/pricing.dart';
import '../i18n/translator.dart';
import '../providers/types.dart';
import 'format.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets/buttons.dart';
import 'widgets/chip.dart';
import 'widgets/fields.dart';
import 'widgets/image_drop_grid.dart';
import 'widgets/model_picker.dart';
import 'widgets/prompt_bar.dart';
import 'widgets/rail.dart';

/// The right-hand rail: everything the ad is made of that is not the words.
///
/// This is what the wizard's three steps collapsed into. The product is at the
/// top because it feeds everything under it, the actor is the bulk of it, and
/// the two folded sections at the bottom are the settings you touch once.
///
/// It is one scroll, not a stack of cards: the rail is already a panel, and
/// boxing each section inside it would cost the 32px the trait pickers need to
/// sit two across.
class ActorRail extends StatefulWidget {
  const ActorRail({super.key, required this.app});

  final AppState app;

  @override
  State<ActorRail> createState() => _ActorRailState();
}

class _ActorRailState extends State<ActorRail> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _audience = TextEditingController();
  final _brief = TextEditingController();
  final _decor = TextEditingController();
  final _audition = TextEditingController();

  final Player _player = Player();

  CostEstimate _castCost = CostEstimate.unknown;
  CostEstimate _auditionCost = CostEstimate.unknown;
  bool _fineTuning = false;
  bool _advancedModels = false;

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
    _name.dispose();
    _description.dispose();
    _audience.dispose();
    _brief.dispose();
    _decor.dispose();
    _audition.dispose();
    _player.dispose();
    super.dispose();
  }

  AppState get app => widget.app;

  Map<String, Object?> get _actor => app.project.actor;

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
    app.project.setActorField('traits', next);
  }

  /// The fields hold their own text once the user is typing, so a change made
  /// behind their back -- Start over, loading a saved actor -- has to be pushed
  /// in rather than inferred.
  void _resync() {
    if (!mounted) return;
    final product = app.project.product;
    setState(() {
      _name.text = '${product['name'] ?? ''}';
      _description.text = '${product['description'] ?? ''}';
      _audience.text = '${product['audience'] ?? ''}';
      _brief.text = _setting('brief');
      _decor.text = _setting('decor');
    });
  }

  void _refreshCosts() {
    setState(() {
      _castCost = app.casting.estimate(4);
      _auditionCost = app.voiceBooth.estimate(_audition.text);
    });
  }

  /// A fresh audition plays itself: hearing the actor is the whole point of the
  /// button that produced it.
  void _onBooth() {
    final sample = app.voiceBooth.samplePath;
    if (sample.isEmpty || sample == _lastSample) return;
    _lastSample = sample;
    _player.open(Media(Uri.file(sample).toString()));
  }

  void _onVoicesLoaded(({String providerId, List<VoiceOption> voices}) event) {
    if (!mounted) return;
    setState(() => _voices = event.voices);
  }

  void _onVoicesFailed(({String providerId, String error}) event) {
    app.log.error(tr('Could not load voices: %1').arg(event.error));
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

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      width: MqTheme.railWidth,
      decoration: BoxDecoration(
        color: mq.surface,
        border: Border(left: BorderSide(color: mq.border)),
      ),
      child: ListenableBuilder(
        // One rebuild source for the whole rail: the project owns the product
        // and the actor, casting owns the candidates, the booth owns the
        // audition.
        listenable: Listenable.merge([
          app.project,
          app.casting,
          app.voiceBooth,
          app.actors,
        ]),
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            MqTheme.gapLarge,
            MqTheme.gapLarge,
            MqTheme.gapLarge,
            MqTheme.gapLarge * 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _productSection(),
              _actorSection(),
              _voiceSection(),
              _scriptSettingsSection(),
              _outputSection(),
            ],
          ),
        ),
      ),
    );
  }

  // ---- product -------------------------------------------------------------

  Widget _productSection() {
    final project = app.project;
    final images = project.imagesFor('product');

    return RailSection(
      first: true,
      title: tr('Product'),
      subtitle: tr('What you are selling.'),
      collapsible: true,
      children: [
        LabeledField(
          controller: _name,
          placeholder: tr('e.g. Lumen glow serum'),
          onChanged: (text) => project.setProductField('name', text),
        ),
        LabeledArea(
          controller: _description,
          areaHeight: 66,
          placeholder: tr(
            'A vitamin C serum that clears dull skin in two weeks.',
          ),
          onChanged: (text) => project.setProductField('description', text),
        ),
        LabeledField(
          controller: _audience,
          placeholder: tr('Who it is for'),
          onChanged: (text) => project.setProductField('audience', text),
        ),
        RailDropZone(
          images: images,
          title: tr('Add product pictures'),
          hint: tr('The first one is the reference every shot is drawn from.'),
          onFilesAdded: (paths) => project.addImages('product', paths),
          onRemoveRequested: (index) => project.removeImage('product', index),
        ),
      ],
    );
  }

  // ---- actor ---------------------------------------------------------------

  Widget _actorSection() {
    final mq = context.mq;
    final project = app.project;
    final portrait = '${project.actor['portraitPath'] ?? ''}';
    final references = project.imagesFor('actor');

    return RailSection(
      title: tr('Actor'),
      subtitle: tr("Who's in the scene?"),
      trailing: GhostButton(
        text: tr('+ New actor'),
        onPressed: project.newActor,
      ),
      children: [
        if (app.actors.count > 0) _savedActors(),
        RailDropZone(
          images: references,
          title: tr('Add reference'),
          hint: tr('Upload a photo, or let the model cast one below.'),
          onFilesAdded: (paths) => project.addImages('actor', paths),
          onRemoveRequested: (index) => project.removeImage('actor', index),
        ),
        PromptBar(
          controller: _brief,
          placeholder: tr(
            'Describe your actor…\ne.g. a woman in her 20s, casual outfit, natural light',
          ),
          minHeight: 54,
          busy: app.casting.running,
          submitIcon: 'magic-line',
          onChanged: (text) => project.setActorField('brief', text),
          onSubmitted: (text) {
            project.setActorField('brief', text);
            app.casting.generate(project.actor);
          },
        ),
        RailPickerRow(
          children: [
            RailPicker(
              label: tr('Gender'),
              value: _trait('gender'),
              placeholder: tr('Any'),
              onPicked: (v) => _setTrait('gender', v),
              options: [
                MenuOption(tr('Woman'), 'a woman'),
                MenuOption(tr('Man'), 'a man'),
                MenuOption(tr('Non-binary'), 'a non-binary person'),
              ],
            ),
            RailPicker(
              label: tr('Age'),
              value: _trait('age'),
              placeholder: tr('Any'),
              onPicked: (v) => _setTrait('age', v),
              options: [
                MenuOption(tr('20–25'), 'around 22 years old'),
                MenuOption(tr('25–30'), 'around 27 years old'),
                MenuOption(tr('30s'), 'around 35 years old'),
                MenuOption(tr('40s'), 'around 45 years old'),
                MenuOption(tr('50+'), 'around 58 years old'),
              ],
            ),
          ],
        ),
        RailPickerRow(
          children: [
            RailPicker(
              label: tr('Ethnicity'),
              value: _trait('ethnicity'),
              placeholder: tr('Any'),
              onPicked: (v) => _setTrait('ethnicity', v),
              options: [
                MenuOption(tr('Mediterranean'), 'with Mediterranean features'),
                MenuOption(
                  tr('Northern European'),
                  'with Northern European features',
                ),
                MenuOption(tr('East Asian'), 'with East Asian features'),
                MenuOption(tr('South Asian'), 'with South Asian features'),
                MenuOption(tr('Black'), 'with Black African features'),
                MenuOption(tr('Latin American'), 'with Latin American features'),
                MenuOption(tr('Middle Eastern'), 'with Middle Eastern features'),
              ],
            ),
            RailPicker(
              label: tr('Look'),
              value: _trait('look'),
              placeholder: tr('Any'),
              onPicked: (v) => _setTrait('look', v),
              options: [
                MenuOption(tr('Natural'), 'bare-faced, no make-up'),
                MenuOption(tr('Tidy'), 'lightly made up and tidy'),
                MenuOption(tr('Polished'), 'full make-up, hair done'),
                MenuOption(tr('Just woke up'), 'hair unbrushed, no make-up'),
              ],
            ),
          ],
        ),
        RailPickerRow(
          children: [
            RailPicker(
              label: tr('Dress'),
              value: _trait('style'),
              placeholder: tr('Any'),
              onPicked: (v) => _setTrait('style', v),
              options: [
                MenuOption(tr('Casual'), 'dressed casually in a plain t-shirt'),
                MenuOption(tr('Sportswear'), 'in sportswear'),
                MenuOption(tr('Office'), 'in office clothes'),
                MenuOption(tr('Streetwear'), 'in streetwear'),
              ],
            ),
            RailPicker(
              label: tr('Energy'),
              value: _trait('energy'),
              placeholder: tr('Any'),
              onPicked: (v) => _setTrait('energy', v),
              options: [
                MenuOption(tr('Confident'), 'confident, direct to camera'),
                MenuOption(tr('Calm'), 'calm, low energy'),
                MenuOption(tr('Upbeat'), 'upbeat and animated'),
                MenuOption(tr('Warm'), 'warm and friendly'),
              ],
            ),
          ],
        ),
        LabeledField(
          controller: _decor,
          label: tr('Where they are'),
          placeholder: tr('A small bathroom, towels on the floor…'),
          onChanged: (text) => project.setActorField('decor', text),
        ),
        _actorPreview(portrait),
        if (app.casting.error.isNotEmpty)
          Text(
            app.casting.error,
            style: TextStyle(color: mq.error, fontSize: MqTheme.fontSmall),
          ),
        if (portrait.isNotEmpty) _keepActor(),
      ],
    );
  }

  Widget _savedActors() {
    final mq = context.mq;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Your actors'),
          style: TextStyle(
            color: mq.textTertiary,
            fontSize: MqTheme.fontMicro,
            fontWeight: FontWeight.w600,
            letterSpacing: MqTheme.trackOverline,
          ),
        ),
        const SizedBox(height: 7),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: app.actors.count,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final saved = app.actors.actors[index];
              final id = '${saved['id'] ?? ''}';

              return _Portrait(
                path: '${saved['portraitPath'] ?? ''}',
                width: 54,
                height: 72,
                chosen: '${app.project.actor['id'] ?? ''}' == id,
                onTap: () => app.project.applyActor(saved),
                onRemove: () => app.actors.remove(id),
              );
            },
          ),
        ),
      ],
    );
  }

  /// The faces the casting model came back with, and the one that was kept.
  ///
  /// This is the section the mock-up calls "Actor preview": it is not a preview
  /// of anything abstract, it is the four portraits a batch produced. Clicking
  /// one is what casts the ad.
  Widget _actorPreview(String portrait) {
    final mq = context.mq;
    final casting = app.casting;
    final candidates = casting.candidates;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              tr('Actor preview'),
              style: TextStyle(
                color: mq.textSecondary,
                fontSize: MqTheme.fontSmall,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 5),
            Tooltip(
              message: tr(
                'The faces the last casting run produced. Click one to cast it.',
              ),
              child: MqIcon(
                'information-line',
                size: 14,
                color: mq.textTertiary,
              ),
            ),
            const Spacer(),
            if (casting.running)
              MqLink(
                text: tr('Cancel'),
                destructive: true,
                onPressed: casting.cancel,
              )
            else
              Text(
                _castCost.known
                    //: %1 is a price
                    ? tr('Four faces for %1').arg(
                        Format.estimated(_castCost.amount),
                      )
                    : tr('price unknown'),
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontSmall,
                ),
              ),
          ],
        ),
        const SizedBox(height: 7),
        if (candidates.isEmpty && portrait.isEmpty)
          Container(
            height: 96,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: mq.surfaceSecondary,
              borderRadius: BorderRadius.circular(MqTheme.radius),
              border: Border.all(color: mq.border),
            ),
            child: Text(
              casting.running
                  //: %1 and %2 are counts of portraits
                  ? tr('Casting… %1 of %2')
                      .arg(casting.received)
                      .arg(casting.requested)
                  : tr('Nobody cast yet.'),
              style: TextStyle(
                color: mq.textTertiary,
                fontSize: MqTheme.fontSmall,
              ),
            ),
          )
        else
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final candidate in candidates)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: _Portrait(
                      path: candidate.path,
                      width: 72,
                      height: 96,
                      chosen: portrait == candidate.path,
                      onTap: () => app.project.setActorField(
                        'portraitPath',
                        candidate.path,
                      ),
                    ),
                  ),
                // The kept portrait stays visible after a batch is replaced.
                if (portrait.isNotEmpty && candidates.isEmpty)
                  _Portrait(
                    path: portrait,
                    width: 72,
                    height: 96,
                    chosen: true,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _keepActor() {
    final mq = context.mq;
    final project = app.project;
    final references = project.imagesFor('actor');
    final portrait = '${project.actor['portraitPath'] ?? ''}';

    return Row(
      children: [
        if (references.isNotEmpty && portrait != references.first)
          MqLink(
            text: tr('Use my photo'),
            onPressed: () =>
                project.setActorField('portraitPath', references.first),
          )
        else
          Expanded(
            child: Text(
              '${project.actor['name'] ?? ''}'.isEmpty
                  ? app.actors.suggestedName()
                  : '${project.actor['name']}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: mq.textSecondary,
                fontSize: MqTheme.fontSmall,
              ),
            ),
          ),
        const SizedBox(width: 8),
        GhostButton(
          text: '${project.actor['id'] ?? ''}'.isEmpty
              ? tr('Keep this actor')
              : tr('Update'),
          onPressed: () {
            final id = app.actors.save(project.actor);
            final kept = app.actors.actor(id);
            project.setActorField('id', id);
            project.setActorField('name', kept['name']);
            if (kept['portraitPath'] != null) {
              project.setActorField('portraitPath', kept['portraitPath']);
            }
          },
        ),
      ],
    );
  }

  // ---- voice ---------------------------------------------------------------

  Widget _voiceSection() {
    final mq = context.mq;

    return RailSection(
      title: tr('Voice'),
      children: [
        Row(
          children: [
            Expanded(
              child: Builder(
                builder: (anchor) => _VoiceButton(
                  label: _voiceLabel,
                  onPressed: () => _pickVoice(anchor),
                ),
              ),
            ),
            const SizedBox(width: 6),
            MqIconButton(
              icon: 'refresh-line',
              tip: tr('Reload the voice list'),
              size: 34,
              onPressed: () => app.loadVoices(
                app.settings.prefString('voiceProvider', 'elevenlabs'),
              ),
            ),
            const SizedBox(width: 2),
            MqIconButton(
              icon: app.voiceBooth.auditioning ? 'loader-4-line' : 'play-fill',
              tip: _auditionCost.known
                  //: %1 is a price
                  ? tr('Hear them — %1').arg(
                      Format.estimated(_auditionCost.amount),
                    )
                  : tr('Hear them'),
              size: 34,
              enabled: !app.voiceBooth.auditioning,
              onPressed: () =>
                  app.voiceBooth.audition(app.project.actor, _audition.text),
            ),
          ],
        ),
        _tone(),
        Row(
          children: [
            const Spacer(),
            MqLink(
              text: _fineTuning ? tr('Hide the sliders') : tr('Fine-tune'),
              onPressed: () => setState(() => _fineTuning = !_fineTuning),
            ),
          ],
        ),
        if (_fineTuning) _sliders(),
        if (app.voiceBooth.error.isNotEmpty)
          Text(
            app.voiceBooth.error,
            style: TextStyle(color: mq.error, fontSize: MqTheme.fontSmall),
          ),
      ],
    );
  }

  Future<void> _pickVoice(BuildContext anchor) async {
    if (_voices.isEmpty) {
      await app.loadVoices(
        app.settings.prefString('voiceProvider', 'elevenlabs'),
      );
      if (!mounted) return;
    }
    if (_voices.isEmpty || !anchor.mounted) return;

    final mq = anchor.mq;
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchor).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final origin = box.localToGlobal(
      Offset(0, box.size.height + 4),
      ancestor: overlay,
    );

    final picked = await showMenu<String>(
      context: anchor,
      constraints: BoxConstraints(minWidth: box.size.width, maxHeight: 360),
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy,
        overlay.size.width - origin.dx - box.size.width,
        0,
      ),
      items: [
        for (final voice in _voices)
          PopupMenuItem<String>(
            value: voice.id,
            height: 34,
            child: Text(
              voice.description.isEmpty
                  ? voice.label
                  : '${voice.label} — ${voice.description}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: voice.id == _setting('voiceId')
                    ? mq.primaryText
                    : mq.textPrimary,
                fontSize: MqTheme.fontLabel,
              ),
            ),
          ),
      ],
    );

    if (picked != null) app.project.setActorField('voiceId', picked);
  }

  /// Four presets instead of four sliders: nobody sets similarity_boost by hand
  /// before they have heard anything.
  Widget _tone() {
    const presets = [
      (label: 'Natural', s: 0.35, m: 0.80, y: 0.45),
      (label: 'Calm', s: 0.65, m: 0.85, y: 0.20),
      (label: 'Energetic', s: 0.25, m: 0.75, y: 0.60),
      (label: 'Serious', s: 0.15, m: 0.70, y: 0.80),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(tr('Tone')),
        const SizedBox(height: 7),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in presets)
              MqChip(
                label: tr(preset.label),
                active:
                    (_number('voiceStability', 0.45) - preset.s).abs() < 0.01 &&
                    (_number('voiceStyle', 0.35) - preset.y).abs() < 0.01,
                onPressed: () {
                  app.project.setActorField('voiceStability', preset.s);
                  app.project.setActorField('voiceSimilarity', preset.m);
                  app.project.setActorField('voiceStyle', preset.y);
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _sliders() {
    final project = app.project;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabeledField(
          controller: _audition,
          label: tr('The audition line'),
          placeholder: tr('A line to hear them say…'),
          onChanged: (text) =>
              setState(() => _auditionCost = app.voiceBooth.estimate(text)),
        ),
        const SizedBox(height: 6),
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

  // ---- script settings -----------------------------------------------------

  Widget _scriptSettingsSection() {
    final project = app.project;

    return RailSection(
      title: tr('Script settings'),
      collapsible: true,
      children: [
        RailPickerRow(
          children: [
            RailPicker(
              label: tr('Language'),
              value: _setting('language'),
              placeholder: tr('Follow the app'),
              onPicked: (v) => project.setActorField('language', v),
              options: [
                for (final language in Translator.languages)
                  MenuOption(language.label, language.englishLabel),
              ],
            ),
            RailPicker(
              label: tr('Length'),
              value: project.targetSeconds == 0
                  ? ''
                  : '${project.targetSeconds}',
              placeholder: tr('Auto'),
              onPicked: (v) =>
                  project.setTargetSeconds(int.tryParse(v) ?? 0),
              options: [
                MenuOption(tr('15 s'), '15'),
                MenuOption(tr('30 s'), '30'),
                MenuOption(tr('45 s'), '45'),
                MenuOption(tr('60 s'), '60'),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ---- output --------------------------------------------------------------

  Widget _outputSection() {
    final project = app.project;

    return RailSection(
      title: tr('Output'),
      subtitle: tr('The shape is set on the bar below the script.'),
      collapsible: true,
      initiallyOpen: false,
      children: [
        StyledCheck(
          text: tr('Burn in subtitles (uses OpenAI Whisper)'),
          checked: project.captions,
          onChanged: project.setCaptions,
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: GhostButton(
            text: _advancedModels
                ? tr('Hide models')
                : tr('Choose models manually'),
            onPressed: () => setState(() => _advancedModels = !_advancedModels),
          ),
        ),
        if (_advancedModels) ...[
          ModelPicker(app: app, category: 'text', label: tr('Writing')),
          ModelPicker(app: app, category: 'image', label: tr('Frames')),
          ModelPicker(app: app, category: 'avatar', label: tr('Talking shots')),
          ModelPicker(app: app, category: 'video', label: tr('Product shots')),
          ModelPicker(app: app, category: 'voice', label: tr('Voice')),
        ],
      ],
    );
  }
}

/// The voice picker. Not a [RailPicker]: the list only exists after a round
/// trip to the provider, so it has to be a button that fetches, not a combo
/// with an empty menu.
class _VoiceButton extends StatelessWidget {
  const _VoiceButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onPressed,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: states.active ? mq.surfaceHover : mq.surfaceSecondary,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          border: Border.all(
            color: states.active ? mq.borderStrong : mq.border,
          ),
        ),
        child: Row(
          children: [
            MqIcon(
              'mic-line',
              size: 16,
              color: label.isEmpty ? mq.textTertiary : mq.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label.isEmpty ? tr('Choose a voice') : label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: label.isEmpty ? mq.textTertiary : mq.textPrimary,
                  fontSize: MqTheme.fontLabel,
                ),
              ),
            ),
            const SizedBox(width: 6),
            MqIcon(
              'arrow-down-s-line',
              size: 16,
              color: states.active ? mq.textPrimary : mq.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// A face: a saved actor, or one of a batch's candidates.
class _Portrait extends StatelessWidget {
  const _Portrait({
    required this.path,
    required this.width,
    required this.height,
    required this.chosen,
    this.onTap,
    this.onRemove,
  });

  final String path;
  final double width;
  final double height;
  final bool chosen;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      enabled: onTap != null,
      onTap: onTap,
      // A strip of thumbnails: sweeping it must not leave a wake.
      snap: true,
      builder: (context, states) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: mq.background,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          border: Border.all(
            color: chosen
                ? mq.primary
                : states.active
                ? mq.borderStrong
                : mq.border,
            width: chosen ? 2 : 1,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(MqTheme.radiusSmall - 1),
              child: LocalImage(path),
            ),
            if (onRemove != null)
              Positioned(
                right: 1,
                top: 1,
                child: IgnorePointer(
                  ignoring: !states.active,
                  child: AnimatedOpacity(
                    opacity: states.active ? 1 : 0,
                    duration: states.duration,
                    child: MqIconButton(
                      icon: 'close-line',
                      destructive: true,
                      size: 20,
                      onPressed: onRemove,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
