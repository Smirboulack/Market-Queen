import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../../models/actor_smith.dart';
import '../../models/asset_library.dart';
import '../../models/voice_forge.dart';
import '../../providers/voice_profile.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/media_drop.dart';
import '../widgets/media_preview.dart';
import '../widgets/model_picker.dart';
import '../widgets/mq_dialog.dart';
import '../widgets/video_player.dart';
import '../widgets/voice_player.dart';
import 'asset_studio.dart';
import 'voice_picker.dart';

/// The two ways an actor is made.
///
/// They are not two forms of the same thing. [describe] is a conversation with
/// an image model that the user drives; [fromImage] is a photograph the app
/// reads and builds everything else out of. What they have in common is what
/// comes out: an actor with a face, a voice and a personality.
enum ActorRoute { describe, fromImage }

/// Makes an actor, in steps. Returns the id, or null if it was abandoned.
Future<String?> showActorWizard(
  BuildContext context, {
  required AppState app,
  ActorRoute route = ActorRoute.describe,
}) {
  return showMqModal<String>(
    context: context,
    // Half an hour of iterating, and a voice that cost real money, must not be
    // thrown away by a stray click on the backdrop.
    dismissible: false,
    child: _Wizard(app: app, route: route),
  );
}

/// One stage of the wizard.
enum _Step { look, photo, action, voice, take }

class _Wizard extends StatefulWidget {
  const _Wizard({required this.app, required this.route});

  final AppState app;
  final ActorRoute route;

  @override
  State<_Wizard> createState() => _WizardState();
}

class _WizardState extends State<_Wizard> {
  late final LibraryAsset _draft =
      LibraryAsset(name: widget.app.actors.suggestedName())
        ..setExtra('createdVia', widget.route.name);

  /// Empty on purpose. The draft already carries the suggested name, so what
  /// this holds is what the user actually typed -- and [_commit] only writes it
  /// when there is something in it.
  final TextEditingController _name = TextEditingController();

  final TextEditingController _action = TextEditingController();
  final TextEditingController _style = TextEditingController();
  final TextEditingController _line = TextEditingController();

  late final List<_Step> _steps = widget.route == ActorRoute.fromImage
      ? const [_Step.photo, _Step.voice, _Step.take]
      : const [_Step.look, _Step.action, _Step.voice, _Step.take];

  int _at = 0;

  /// What the vision model made of the photograph, on the image route.
  ActorProfile? _profile;

  /// The picture the image route was handed. Kept apart from the draft's own
  /// still until the reading succeeds, so a failed analysis leaves nothing
  /// half-built behind.
  String _photo = '';

  /// Held here rather than inside the panel, because the panel is unmounted
  /// the moment you step off its page and everything asked for so far would go
  /// with it.
  final List<ForgeRound> _history = [];

  /// One player for the whole wizard, for the same reason the editor has one:
  /// the voice step is a page of play buttons and only one of them may be
  /// making a noise.
  final AudioTransport _transport = AudioTransport();

  _Step get _step => _steps[_at];

  @override
  void initState() {
    super.initState();
    _line.text = _defaultLine;
    widget.app.actorSmith.addListener(_repaint);
    widget.app.actorReel
      ..reset()
      ..addListener(_repaint);
    // Reset here rather than in the voice step: that step is mounted and
    // unmounted every time the user walks past it, and resetting on mount threw
    // away three voices somebody had just paid to design.
    widget.app.voiceForge.reset();
  }

  @override
  void dispose() {
    widget.app.actorSmith.removeListener(_repaint);
    widget.app.actorReel.removeListener(_repaint);
    _transport.dispose();
    _name.dispose();
    _action.dispose();
    _style.dispose();
    _line.dispose();
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  /// What the take says when the user has not written a line. Short, ordinary,
  /// and the sort of sentence a UGC ad actually opens on -- a phonetic drill
  /// would tell you nothing about whether this actor can sell anything.
  String get _defaultLine =>
      tr('Okay so I have been using this for two weeks and I genuinely cannot '
          'go back.');

  // ---- moving between the steps -------------------------------------------

  /// Whether the step on screen has what it needs to be left.
  bool get _canAdvance => switch (_step) {
        _Step.look => _draft.previewPath.isNotEmpty,
        _Step.photo => _draft.previewPath.isNotEmpty,
        // Neither of these is required. An actor with no stated action is one
        // who talks to camera, which is the default anyway.
        _Step.action => true,
        _Step.voice => true,
        _Step.take => true,
      };

  String get _blockedReason => switch (_step) {
        _Step.look => tr('Pick one of the pictures first.'),
        _Step.photo => tr('Add a picture and read it first.'),
        _ => '',
      };

  void _next() {
    if (!_canAdvance) return;
    _commit();
    if (_at < _steps.length - 1) setState(() => _at += 1);
  }

  void _back() {
    if (_at == 0) return;
    _commit();
    setState(() => _at -= 1);
  }

  /// Writes the fields of the step being left onto the draft. Called on every
  /// move rather than only at the end, so stepping back and forth cannot lose
  /// what was typed.
  void _commit() {
    // Never blanks it: leaving the last step without typing a name keeps the
    // suggestion, and a voice designed two steps earlier was already filed on
    // the ElevenLabs account under it.
    final typed = _name.text.trim();
    if (typed.isNotEmpty) _draft.name = typed;
    _draft.setExtra(ActorPersona.actionKey, _action.text.trim());
    _draft.setExtra(ActorPersona.styleKey, _style.text.trim());
  }

  void _finish() {
    _commit();
    final id = widget.app.actors.save(_draft);
    if (mounted) closeMqModal(context, id);
  }

  // ---- the image route -----------------------------------------------------

  /// Everything the photograph is worth: a description, a personality, a voice
  /// profile, and three voices designed from it.
  ///
  /// One button, four calls. The user asked for an actor, not for a pipeline,
  /// and the only decision left to them at the end of it is which of the three
  /// voices sounds right.
  Future<void> _readPhoto() async {
    if (_photo.isEmpty) return;

    final profile = await widget.app.actorSmith.read(_photo);
    if (!mounted || profile == null) return;

    _draft
      ..previewPath = _photo
      ..prompt = profile.appearance;
    if (!_draft.media.contains(_photo)) _draft.media.add(_photo);
    profile.applyTo(_draft);

    _action.text = profile.action;
    _style.text = profile.speakingStyle;

    setState(() => _profile = profile);

    // Straight on to the voices: the analysis has already written the brief,
    // and stopping here to show it would be showing the user their own photo
    // back with adjectives on it.
    if (profile.voiceDescription.isNotEmpty) {
      _next();
      await widget.app.voiceForge.design(
        description: profile.voiceDescription,
        modelId: VoiceForge.designModels.first.$1,
      );
    }
  }

  // ---- the take ------------------------------------------------------------

  Future<void> _film() async {
    _commit();
    final reel = widget.app.actorReel;

    await reel.film(
      actor: {
        ..._draft.extras,
        'voiceStability': _draft.extraNumber('voiceStability', 0.45),
        'voiceSimilarity': _draft.extraNumber('voiceSimilarity', 0.8),
        'voiceStyle': _draft.extraNumber('voiceStyle', 0.35),
        'voiceSpeed': _draft.extraNumber('voiceSpeed', 1.0),
      },
      portraitPath: _draft.previewPath,
      line: _line.text,
      motionPrompt: _action.text.trim(),
    );

    if (!mounted || reel.clipPath.isEmpty) return;
    // Kept on the actor: it is the proof the three parts fit together, and the
    // library card shows it rather than a still that never moves.
    _draft.setExtra('takePath', reel.clipPath);
    setState(() {});
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final size = studioSize(MediaQuery.sizeOf(context));
    final last = _at == _steps.length - 1;

    return MqModalCard(
      width: size.width,
      maxHeight: size.height,
      title: tr('Create an actor'),
      subtitle: _subtitleFor(_step),
      actions: [
        if (_at > 0) GhostButton(text: tr('Back'), onPressed: _back),
        GhostButton(text: tr('Cancel'), onPressed: () => closeMqModal(context)),
        // Finishing early is allowed from the moment there is a face: a voice
        // and a take both cost money, and an actor without them is still a
        // usable actor.
        if (!last && _draft.previewPath.isNotEmpty)
          GhostButton(text: tr('Save and close'), onPressed: _finish),
        if (last)
          PrimaryButton(text: tr('Save this actor'), onPressed: _finish)
        else
          PrimaryButton(
            text: tr('Next'),
            enabled: _canAdvance,
            tooltip: _canAdvance ? '' : _blockedReason,
            onPressed: _next,
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepRail(steps: _steps, at: _at, labelFor: _labelFor),
          const SizedBox(height: MqTheme.gapLarge),
          // The step takes whatever the rail, the header and the buttons left
          // behind, and decides for itself whether it scrolls. Only one of
          // them does not: the appearance step is a feed with a bar under it,
          // and a feed inside a scroll view is two scrollbars arguing.
          Expanded(child: _body()),
        ],
      ),
    );
  }

  String _labelFor(_Step step) => switch (step) {
        _Step.look => tr('Appearance'),
        _Step.photo => tr('Photo'),
        _Step.action => tr('Action'),
        _Step.voice => tr('Voice'),
        _Step.take => tr('Bring the actor to life'),
      };

  String _subtitleFor(_Step step) => switch (step) {
        _Step.look => tr('Describe the actor, pick the one that is closest, then say what to change.'),
        _Step.photo => tr('One picture. Everything else is read off it.'),
        _Step.action => tr('What the actor does while talking, and the personality behind it.'),
        _Step.voice => tr('Pick a voice, invent one, or clone your own.'),
        _Step.take => tr('A name, and one short clip bought from the same '
            'two models a real shot uses.'),
      };

  Widget _body() => switch (_step) {
        _Step.look => _lookStep(),
        _Step.photo => SingleChildScrollView(child: _photoStep()),
        _Step.action => SingleChildScrollView(child: _actionStep()),
        _Step.voice => SingleChildScrollView(child: _voiceStep()),
        _Step.take => SingleChildScrollView(child: _takeStep()),
      };

  // ---- step: the look ------------------------------------------------------

  Widget _lookStep() {
    return AssetForge(
      app: widget.app,
      kind: AssetKind.actor,
      draft: _draft,
      history: _history,
      onChanged: () => setState(() {}),
    );
  }

  // ---- step: the photograph ------------------------------------------------

  Widget _photoStep() {
    final mq = context.mq;
    final smith = widget.app.actorSmith;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 240,
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: _photo.isEmpty
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: mq.surfaceSecondary,
                      borderRadius: BorderRadius.circular(MqTheme.radius),
                      border: Border.all(color: mq.border),
                    ),
                    child: Center(
                      child: MqIcon(
                        'user-smile-line',
                        size: 26,
                        color: mq.textTertiary,
                      ),
                    ),
                  )
                : Pressable(
                    onTap: () => showMediaPreview(context, _photo),
                    tooltip: tr('View full size'),
                    focusRadius: MqTheme.radius,
                    builder: (context, states) => AnimatedContainer(
                      duration: states.duration,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(MqTheme.radius),
                        border: Border.all(
                          color: states.active ? mq.primary : mq.borderStrong,
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: LocalImage(_photo),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: MqTheme.gapLarge),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              MediaDropZone(
                paths: _photo.isEmpty ? const [] : [_photo],
                title: tr("Drop the actor's picture in"),
                hint: tr('PNG, JPG or WebP. One person, face visible.'),
                tileSize: 56,
                onAdded: (paths) {
                  final picture = paths.firstWhere(
                    (path) => isImagePath(path),
                    orElse: () => '',
                  );
                  if (picture.isNotEmpty) setState(() => _photo = picture);
                },
                onRemoved: (_) => setState(() => _photo = ''),
              ),
              const SizedBox(height: MqTheme.gapLarge),
              _Explainer(
                icon: 'sparkling-line',
                title: tr('What happens next'),
                lines: [
                  tr('The picture is read: apparent age, presentation, style and the room around it.'),
                  tr('That becomes a casting brief and a personality.'),
                  tr('A voice profile is inferred from it, and three voices '
                      'are designed to match.'),
                  ActorProfile.disclaimer,
                ],
              ),
              if (smith.error.isNotEmpty) ...[
                const SizedBox(height: MqTheme.gap),
                Text(
                  smith.error,
                  style: TextStyle(color: mq.error, fontSize: MqTheme.fontSmall),
                ),
              ],
              if (_profile != null) ...[
                const SizedBox(height: MqTheme.gap),
                _Readout(profile: _profile!),
              ],
              const SizedBox(height: MqTheme.gapLarge),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      smith.writer.exists
                          //: %1 is a model name, %2 an account such as "OpenAI"
                          ? tr('Read with %1 — billed to your %2 account')
                              .arg(smith.writer.label)
                              .arg(smith.writer.account)
                          : tr('No writer has a key yet. Add one under '
                              'Models.'),
                      style: TextStyle(
                        color: mq.textTertiary,
                        fontSize: MqTheme.fontSmall,
                        height: MqTheme.lineTight,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GhostButton(
                    text: smith.reading
                        ? tr('Reading the picture…')
                        : tr('Read this picture'),
                    enabled: _photo.isNotEmpty &&
                        smith.writer.exists &&
                        !smith.reading,
                    onPressed: _readPhoto,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---- step: what they do --------------------------------------------------

  Widget _actionStep() {
    final mq = context.mq;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 240, child: _portrait()),
        const SizedBox(width: MqTheme.gapLarge),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              LabeledArea(
                controller: _action,
                label: tr('What is the actor doing?'),
                areaHeight: 72,
                placeholder: tr(
                  'Talking to camera, holding the product in one hand, small '
                  'natural gestures, glancing down at it now and then…',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr('This is handed to the video model as the motion for every shot the actor is in.'),
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontSmall,
                  height: MqTheme.lineTight,
                ),
              ),
              const SizedBox(height: MqTheme.gapLarge),
              PersonaEditor(
                draft: _draft,
                styleController: _style,
                onChanged: () => setState(() {}),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---- step: the voice -----------------------------------------------------

  Widget _voiceStep() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _portrait(),
              const SizedBox(height: MqTheme.gap),
              // Who is cast, under the face they are being cast for. It is what
              // the four tabs are competing to change, and a choice you cannot
              // see is one you make twice.
              VoicePlayerCard(
                transport: _transport,
                name: _draft.extraText('voiceName'),
                provenance: _provenance,
                source: _draft.extraText('voicePreview'),
                note: tr('Playing the sample is free.'),
                onDetach: () => setState(() {
                  for (final key in const [
                    'voiceId',
                    'voiceOwner',
                    'voiceName',
                    'voiceKind',
                    'voiceDescription',
                    'voicePreview',
                  ]) {
                    _draft.setExtra(key, '');
                  }
                  _transport.clear();
                }),
              ),
            ],
          ),
        ),
        const SizedBox(width: MqTheme.gapLarge),
        Expanded(
          child: VoicePicker(
            app: widget.app,
            draft: _draft,
            transport: _transport,
            // No dials here. The actor has no voice yet on most of the way
            // through this step, and four sliders for nobody is a form to fill
            // in before the decision they modify has been made.
            showDials: false,
            suggestedDescription: _profile?.voiceDescription ?? '',
            onChanged: () => setState(() {}),
          ),
        ),
      ],
    );
  }

  /// Where the cast voice came from, in the words the card has room for.
  String get _provenance => switch (_draft.extraText('voiceKind')) {
        'designed' => tr('Designed · ElevenLabs'),
        'cloned' => tr('Cloned from your recordings · ElevenLabs'),
        'library' => tr('Voice library · ElevenLabs'),
        _ => '',
      };

  // ---- step: the take ------------------------------------------------------

  Widget _takeStep() {
    final mq = context.mq;
    final reel = widget.app.actorReel;
    final cost = reel.estimate(_line.text);
    final hasVoice = _draft.extraText('voiceId').isNotEmpty ||
        VoiceTrait.all.any((trait) => _draft.extraText(trait.key).isNotEmpty);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 300,
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: reel.clipPath.isEmpty
                ? _portraitBox(mq)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(MqTheme.radius),
                    child: InlineVideo(path: reel.clipPath, loop: true),
                  ),
          ),
        ),
        const SizedBox(width: MqTheme.gapLarge),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The name, last. Asking for it first meant naming somebody
              // before you had seen their face, which is a question with no
              // answer yet -- so it got the suggestion, and libraries filled up
              // with "Actor 3". By here there is a face, a voice and a way of
              // moving to name.
              LabeledField(
                controller: _name,
                label: tr("Actor's name"),
                placeholder: widget.app.actors.suggestedName(),
                hint: tr('What you will look for the actor under later.'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: MqTheme.gap),
              LabeledArea(
                controller: _line,
                label: tr('What does the actor say?'),
                areaHeight: 72,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: MqTheme.gap),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ModelChip(app: widget.app, category: 'avatar'),
                        ModelChip(app: widget.app, category: 'voice'),
                      ],
                    ),
                  ),
                  const SizedBox(width: MqTheme.gap),
                  if (reel.running)
                    GhostButton(
                      text: tr('Cancel'),
                      destructive: true,
                      onPressed: reel.cancel,
                    )
                  else
                    GhostButton(
                      text: cost.known
                          //: %1 is a price
                          ? tr('Film the actor — %1')
                              .arg(Format.estimated(cost.amount))
                          : tr('Film the actor'),
                      enabled: hasVoice && _line.text.trim().isNotEmpty,
                      onPressed: _film,
                    ),
                ],
              ),
              if (!hasVoice) ...[
                const SizedBox(height: 8),
                Text(
                  tr('Go back and give the actor a voice first — there is nothing to lip-sync to yet.'),
                  style: TextStyle(
                    color: mq.warningText,
                    fontSize: MqTheme.fontSmall,
                  ),
                ),
              ],
              if (reel.running) ...[
                const SizedBox(height: MqTheme.gap),
                Text(
                  reel.stage.isEmpty ? tr('Working…') : reel.stage,
                  style: TextStyle(
                    color: mq.textTertiary,
                    fontSize: MqTheme.fontSmall,
                  ),
                ),
              ],
              if (reel.error.isNotEmpty) ...[
                const SizedBox(height: MqTheme.gap),
                Text(
                  reel.error,
                  style: TextStyle(color: mq.error, fontSize: MqTheme.fontSmall),
                ),
              ],
              const SizedBox(height: MqTheme.gapLarge),
              _Explainer(
                icon: 'information-line',
                title: tr('Why this step exists'),
                lines: [
                  tr('A face and a voice can each be right while the pair of '
                      'them is wrong, and that is only obvious in motion.'),
                  tr('This buys the same two things a real shot buys, from '
                      'the same models, so it is a rehearsal rather than a '
                      'mock-up.'),
                  tr('You can skip it and save the actor now.'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _portrait() => AspectRatio(
        aspectRatio: 3 / 4,
        child: _portraitBox(context.mq),
      );

  Widget _portraitBox(MqTheme mq) {
    if (_draft.previewPath.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: mq.surfaceSecondary,
          borderRadius: BorderRadius.circular(MqTheme.radius),
          border: Border.all(color: mq.border),
        ),
        child: Center(
          child: MqIcon('user-smile-line', size: 26, color: mq.textTertiary),
        ),
      );
    }

    return Pressable(
      onTap: () => showMediaPreview(context, _draft.previewPath),
      tooltip: tr('View full size'),
      focusRadius: MqTheme.radius,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(MqTheme.radius),
          border: Border.all(
            color: states.active ? mq.primary : mq.borderStrong,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: LocalImage(_draft.previewPath),
      ),
    );
  }
}

/// Where you are, and how far there is to go.
///
/// Numbered rather than a bare progress bar: the steps are not interchangeable
/// -- appearance, then action, then voice, then motion -- and their order is
/// the argument the screen is making about what an actor is.
class _StepRail extends StatelessWidget {
  const _StepRail({
    required this.steps,
    required this.at,
    required this.labelFor,
  });

  final List<_Step> steps;
  final int at;
  final String Function(_Step) labelFor;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Row(
      children: [
        for (var i = 0; i < steps.length; ++i) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: i <= at ? mq.borderStrong : mq.borderSubtle,
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i < at
                      ? mq.primary
                      : i == at
                      ? mq.surfaceActive
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: i <= at ? mq.borderStrong : mq.border,
                  ),
                ),
                child: i < at
                    ? MqIcon('check-line', size: 13, color: mq.onPrimary)
                    : Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: i == at ? mq.textPrimary : mq.textTertiary,
                          fontSize: MqTheme.fontMicro,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Text(
                labelFor(steps[i]),
                style: TextStyle(
                  color: i == at ? mq.textPrimary : mq.textTertiary,
                  fontSize: MqTheme.fontLabel,
                  fontWeight: i == at ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A short list of what is about to happen, or why it is worth doing.
///
/// The two screens that need one are the two where the app spends the user's
/// money on something they did not explicitly ask for -- reading a photo, and
/// filming a take -- and on both, "what am I paying for" is a fair question to
/// answer before the button rather than after it.
class _Explainer extends StatelessWidget {
  const _Explainer({
    required this.icon,
    required this.title,
    required this.lines,
  });

  final String icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radius),
        border: Border.all(color: mq.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              MqIcon(icon, size: 15, color: mq.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: mq.textPrimary,
                    fontSize: MqTheme.fontLabel,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '·  ',
                    style: TextStyle(
                      color: mq.textTertiary,
                      fontSize: MqTheme.fontSmall,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: TextStyle(
                        color: mq.textTertiary,
                        fontSize: MqTheme.fontSmall,
                        height: MqTheme.lineBody,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// What the vision model came back with, in the user's words rather than in
/// JSON. Shown because an app that quietly decides somebody is "middle-aged and
/// professional" should be willing to say so where it can be corrected.
class _Readout extends StatelessWidget {
  const _Readout({required this.profile});

  final ActorProfile profile;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    final tags = <String>[
      if (profile.gender.isNotEmpty)
        VoiceTrait.labelFor('voiceGender', profile.gender),
      if (profile.age.isNotEmpty) VoiceTrait.labelFor('voiceAge', profile.age),
      if (profile.tone.isNotEmpty)
        VoiceTrait.labelFor('voiceTone', profile.tone),
      for (final trait in profile.traits) ActorPersona.labelFor(trait),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(MqTheme.radius),
        border: Border.all(color: mq.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FieldLabel(tr('What the picture said')),
          const SizedBox(height: 8),
          Text(
            profile.appearance,
            style: TextStyle(
              color: mq.textSecondary,
              fontSize: MqTheme.fontSmall,
              height: MqTheme.lineBody,
            ),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              tags.join(' · '),
              style: TextStyle(
                color: mq.textTertiary,
                fontSize: MqTheme.fontSmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The personality block: the traits, the energy and the free-text direction.
///
/// Its own widget because it is wanted in two places that must not drift --
/// the wizard's action step and the editor's Personality section -- and it is
/// the one part of an actor with nothing to look at, so a second copy of it
/// would never be noticed going wrong.
class PersonaEditor extends StatelessWidget {
  const PersonaEditor({
    super.key,
    required this.draft,
    required this.styleController,
    required this.onChanged,
    this.fills = false,
  });

  final LibraryAsset draft;
  final TextEditingController styleController;
  final VoidCallback onChanged;

  /// Lay out to a slot of a known height rather than to the content.
  ///
  /// The editor gives this a card on a page that does not scroll, so the dial
  /// and the pills go side by side -- they are read together, "how much and of
  /// what" -- and the free-text box takes the rest of the card. The wizard
  /// gives it a column in a scroll view, where side by side would put a slider
  /// and six pills in 300px, so it keeps the stack.
  final bool fills;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final chosen = ActorPersona.traitsOf(draft);

    Widget pills(List<(String, String)> options) => Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final option in options)
              _TraitPill(
                label: option.$1,
                selected: chosen.contains(option.$2),
                onTap: () {
                  ActorPersona.toggleTrait(draft, option.$2);
                  onChanged();
                },
              ),
          ],
        );

    final energy = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LabeledSlider(
          label: tr('Energy'),
          value: ActorPersona.energyOf(draft),
          onChanged: (value) {
            draft.setExtra(ActorPersona.energyKey, value);
            onChanged();
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final end in [tr('Level'), tr('Buzzing')])
              Text(
                end,
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontMicro,
                ),
              ),
          ],
        ),
      ],
    );

    final traits = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FieldLabel(tr('Tone')),
        const SizedBox(height: 8),
        pills(ActorPersona.tones),
        const SizedBox(height: MqTheme.gap),
        FieldLabel(tr('Style')),
        const SizedBox(height: 8),
        pills(ActorPersona.styles),
      ],
    );

    final talk = LabeledArea(
      controller: styleController,
      label: tr('How the actor talks'),
      areaHeight: 64,
      fills: fills,
      placeholder: tr(
        'Speaks naturally and never sounds like an advert. Short '
        'sentences, a bit of humour.',
      ),
    );

    if (fills) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: energy),
              const SizedBox(width: MqTheme.gapLarge),
              Expanded(child: traits),
            ],
          ),
          const SizedBox(height: MqTheme.gap + 2),
          Expanded(child: talk),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        energy,
        const SizedBox(height: MqTheme.gap),
        traits,
        const SizedBox(height: MqTheme.gap),
        talk,
        const SizedBox(height: 6),
        Text(
          tr('All of this goes to the script writer as direction for this '
              'actor.'),
          style: TextStyle(
            color: mq.textTertiary,
            fontSize: MqTheme.fontSmall,
            height: MqTheme.lineTight,
          ),
        ),
      ],
    );
  }
}

/// One personality trait, on or off. Several at once, so it is a toggle rather
/// than a menu -- nobody is one adjective.
class _TraitPill extends StatelessWidget {
  const _TraitPill({
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
