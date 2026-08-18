import 'package:flutter/foundation.dart';

import '../core/http_util.dart';
import '../core/log_model.dart';
import '../core/settings_store.dart';
import '../i18n/translator.dart';
import '../media/ffmpeg.dart';
import '../providers/provider_task.dart';
import '../providers/registry.dart';
import '../providers/text_providers.dart';
import '../providers/types.dart';
import '../providers/voice_profile.dart';
import 'asset_library.dart';
import 'prompt_doctor.dart';

/// What a vision model saw in a photograph, in the app's own vocabulary.
///
/// Every field here is an *inference*, and the voice one especially so: a
/// picture contains no voice. What a vision model can honestly say is that this
/// person plausibly sounds young, female-presenting, warm and conversational --
/// which is a casting brief, not a recovery. The interface is required to say
/// so; see [disclaimer].
@immutable
class ActorProfile {
  const ActorProfile({
    this.appearance = '',
    this.gender = '',
    this.age = '',
    this.tone = '',
    this.useCase = '',
    this.voiceDescription = '',
    this.action = '',
  });

  /// Reads the answer, keeping only values from the vocabularies the rest of
  /// the app searches on. A model that invents "young-adult" instead of
  /// "young" would otherwise write a filter that matches nobody.
  factory ActorProfile.fromJson(Map<String, Object?> json) {
    String vocab(String key, String traitKey) {
      final value = '${json[key] ?? ''}'.trim().toLowerCase();
      for (final trait in VoiceTrait.all) {
        if (trait.key != traitKey) continue;
        for (final option in trait.options) {
          if (option.$2 == value) return value;
        }
      }
      return '';
    }

    return ActorProfile(
      appearance: '${json['appearance'] ?? ''}'.trim(),
      gender: vocab('gender', 'voiceGender'),
      age: vocab('age', 'voiceAge'),
      tone: vocab('tone', 'voiceTone'),
      useCase: vocab('use', 'voiceUse'),
      voiceDescription: '${json['voice'] ?? ''}'.trim(),
      action: '${json['action'] ?? ''}'.trim(),
    );
  }

  /// How the person is described, for the image model and for the library card.
  final String appearance;

  /// ElevenLabs' own vocabulary, so the casting search can use them verbatim.
  final String gender;
  final String age;
  final String tone;
  final String useCase;

  /// The brief handed to Voice Design: what this person plausibly sounds like.
  final String voiceDescription;

  /// What they appear to be doing, which becomes the first draft of the motion
  /// prompt.
  final String action;

  bool get isEmpty => appearance.isEmpty && voiceDescription.isEmpty;

  /// The sentence the interface is obliged to show next to a designed voice.
  ///
  /// It is not a disclaimer for its own sake. "AI detected her voice" would be
  /// a false claim about a real person's body, and the honest version costs one
  /// line: the voice matches the profile, it is not the person's.
  static String get disclaimer => tr(
        'A voice generated to match this actor, not a recording of anyone. '
        'To use a real voice, clone it from your own audio.',
      );

  /// Everything the profile knows about the voice, written onto an actor.
  void applyTo(LibraryAsset actor) {
    if (gender.isNotEmpty) actor.setExtra('voiceGender', gender);
    if (age.isNotEmpty) actor.setExtra('voiceAge', age);
    if (tone.isNotEmpty) actor.setExtra('voiceTone', tone);
    actor.setExtra('voiceUse', useCase.isEmpty ? 'social_media' : useCase);

    if (action.isNotEmpty && actor.extraText(ActorAction.key).isEmpty) {
      actor.setExtra(ActorAction.key, action);
    }
    if (voiceDescription.isNotEmpty) {
      actor.setExtra('voiceDescription', voiceDescription);
    }
  }
}

/// Reads a photograph and says who is in it.
///
/// This is the whole of "create an actor from an image": the user hands over a
/// face and a name, and everything else -- the description, the casting brief,
/// the voice profile, the personality -- is worked out from the picture by a
/// vision model rather than asked for in a form. It runs on whichever writer
/// the user already has a key for, the one they chose for scripts first.
class ActorSmith extends ChangeNotifier {
  ActorSmith(this._settings, this._registry, this._log, this._doctor);

  final SettingsStore _settings;
  final Registry _registry;
  final LogModel _log;
  final PromptDoctor _doctor;

  ProviderTask? _task;
  String _error = '';
  bool _reading = false;

  bool get reading => _reading;
  String get error => _error;

  /// Who would do the reading, on the keys actually present. Empty when no
  /// writer has one -- the button then says what to do about it.
  PromptWriter get writer => _doctor.writer;

  @override
  void dispose() {
    cancel();
    super.dispose();
  }

  void cancel() {
    final task = _task;
    if (task != null && !task.isFinished) task.cancel();
    _task = null;
    _reading = false;
    notifyListeners();
  }

  /// Looks at [imagePath] and returns what it saw. Null on failure, with
  /// [error] set.
  Future<ActorProfile?> read(String imagePath) async {
    if (_reading) return null;

    final chosen = writer;
    if (!chosen.exists) {
      _setError(tr('No writer has a key yet. Add one under Models.'));
      return null;
    }

    // Through ffmpeg when the Dart codecs cannot read it: a photo dropped
    // straight off a phone is as likely to be HEIC as anything.
    final dataUri =
        await imageDataUri(Ffmpeg.resolve(_settings.ffmpegPath), imagePath);
    if (dataUri.isEmpty) {
      _setError(unreadableImage(imagePath));
      return null;
    }

    final task = ProviderFactory.text(
      chosen.providerId,
      TextRequest(
        apiKey: _settings.apiKey(_registry.credentialFor(chosen.providerId)),
        model: chosen.modelId,
        system: systemPrompt,
        user: userPrompt,
        imageDataUri: dataUri,
        // The answer is a small object. A ceiling stops a model that decides to
        // explain its reasoning from billing for a page of it.
        maxTokens: 900,
      ),
    );
    if (task == null) {
      _setError(tr('No writer called %1.').arg(chosen.providerId));
      return null;
    }

    _task = task;
    _error = '';
    _reading = true;
    notifyListeners();

    _log.info(tr('Reading the picture with %1.').arg(chosen.label));

    try {
      final result = await task.run();
      final profile = ActorProfile.fromJson(
        extractJsonObject('${result['text'] ?? ''}'),
      );

      _reading = false;
      notifyListeners();

      if (profile.isEmpty) {
        _setError(tr('The model could not describe this picture.'));
        return null;
      }
      return profile;
    } on ProviderException catch (error) {
      if (error is! TaskCancelled) {
        _log.error(tr('Could not read the picture: %1').arg(error.message));
        _error = error.message;
      }
      _reading = false;
      notifyListeners();
      return null;
    } finally {
      _task = null;
    }
  }

  void _setError(String message) {
    if (_error == message) return;
    _error = message;
    notifyListeners();
  }

  /// Visible for testing, and worth reading: the vocabularies are pinned to the
  /// ones the voice search actually honours, which is the difference between a
  /// brief that returns twelve voices and one that returns none.
  ///
  /// The instruction to describe rather than identify is not politeness. A
  /// model asked "who is this" will name a celebrity it half-recognises; asked
  /// what is in frame, it describes the person in front of it, which is the
  /// only thing this app can use.
  static String get systemPrompt =>
      'You look at one photograph of a person and describe what is in it, so '
      'that a video advertising tool can build a reusable character from it.\n'
      '\n'
      'Never identify anybody, never guess a name, and never say who somebody '
      'resembles. Describe only what is visible.\n'
      '\n'
      'You also propose a voice that would *suit* this person. You cannot hear '
      'them, and you must not pretend to: this is a casting suggestion based on '
      'how they present, not a recovery of a real voice.\n'
      '\n'
      'Answer with a single JSON object and nothing else:\n'
      '{\n'
      '  "appearance": "one or two sentences describing the person as a '
      'casting brief: apparent age range, build, hair, clothing, expression, '
      'and the room or place around them. Written for an image model, in '
      'English, no names",\n'
      '  "action": "what they appear to be doing, as a short instruction for a '
      'video model: how they hold themselves, their gestures, where they are '
      'looking",\n'
      '  "gender": "one of: female, male. Use the presentation in the photo. '
      'Leave it an empty string if it is genuinely not readable",\n'
      '  "age": "one of: young, middle_aged, old",\n'
      '  "tone": "one of: upbeat, excited, casual, confident, calm, chill, '
      'professional, deep",\n'
      '  "use": "one of: social_media, advertisement, conversational, '
      'narrative_story, informative_educational, characters_animation",\n'
      '  "voice": "a voice design brief of 30 to 250 characters, in English: '
      'the apparent age and gender presentation, the accent or language the '
      'setting suggests, the warmth, the pitch, the pace and the delivery. '
      'Write it as a description of a voice, not of a person",\n'
      '}';

  static String get userPrompt =>
      'Here is the photograph. Describe the person in it and propose a voice '
      'that would suit them. JSON only.';
}
