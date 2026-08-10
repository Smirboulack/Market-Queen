import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/http_util.dart';
import '../i18n/translator.dart';
import 'provider_task.dart';
import 'types.dart';
import 'voice_profile.dart';

abstract class VoiceTask extends HttpTask {
  VoiceTask(this.request);

  final VoiceRequest request;
}

// ---------------------------------------------------------------------------
// ElevenLabs
// ---------------------------------------------------------------------------

/// What one ElevenLabs engine accepts.
///
/// They do not all take the same body. v3 is a different architecture: it
/// rejects the continuity fields outright, takes no speed, and quantises its
/// stability to three named settings. Sending it the v2 body is a 400 and a
/// failed run, not a warning -- so what a model accepts is declared here, once,
/// instead of being discovered in production.
class ElevenLabsModel {
  const ElevenLabsModel({
    this.stitching = true,
    this.speed = true,
    this.stabilitySteps = const [],
  });

  /// previous_text / next_text: the context that keeps a scene-by-scene read
  /// sounding like one performance.
  final bool stitching;

  final bool speed;

  /// When set, the only stability values the engine will take. Anything else is
  /// snapped to the nearest one.
  final List<double> stabilitySteps;

  /// Creative, Natural, Robust -- v3 has no continuum between them.
  static const v3 = ElevenLabsModel(
    stitching: false,
    speed: false,
    stabilitySteps: [0.0, 0.5, 1.0],
  );

  static const classic = ElevenLabsModel();

  /// Matched on the id rather than looked up in a table, so a model typed into
  /// "Other..." -- or a v3 variant we have not heard of yet -- still gets a body
  /// it can accept.
  static ElevenLabsModel of(String modelId) =>
      modelId.toLowerCase().contains('v3') ? v3 : classic;

  double snapStability(double value) {
    if (stabilitySteps.isEmpty) return value;
    var closest = stabilitySteps.first;
    for (final step in stabilitySteps) {
      if ((step - value).abs() < (closest - value).abs()) closest = step;
    }
    return closest;
  }

  /// The request body for one line, with everything this engine cannot take
  /// left out.
  Map<String, Object?> body(VoiceRequest request) {
    final settings = <String, Object?>{
      'stability': snapStability(request.stability),
      'similarity_boost': request.similarity,
      'style': request.style,
      'use_speaker_boost': true,
      // Only sent when it is actually asked for: a default of 1.0 changes
      // nothing anyway.
      if (speed && (request.speed - 1.0).abs() > 1e-9) 'speed': request.speed,
    };

    return <String, Object?>{
      'text': request.text,
      'model_id': request.model,
      'voice_settings': settings,
      if (stitching && request.previousText.isNotEmpty)
        'previous_text': request.previousText,
      if (stitching && request.nextText.isNotEmpty)
        'next_text': request.nextText,
    };
  }
}

class ElevenLabsVoiceTask extends VoiceTask {
  ElevenLabsVoiceTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'ElevenLabs');
    if (request.voiceId.isEmpty) {
      throw ProviderException(tr('Pick an ElevenLabs voice first.'));
    }

    report(tr('Recording the voice-over...'));

    final url = Uri.parse(
      'https://api.elevenlabs.io/v1/text-to-speech/${request.voiceId}'
      '?output_format=mp3_44100_128',
    );

    final body = ElevenLabsModel.of(request.model).body(request);

    final response = await postJsonForBytes(
      url,
      body,
      headers: {'xi-api-key': request.apiKey, 'Accept': 'audio/mpeg'},
    );

    if (response.statusCode >= 400) {
      throw ProviderException(
          Http.describeError(response.statusCode, response.body));
    }
    if (response.bodyBytes.isEmpty) {
      throw ProviderException(tr('ElevenLabs returned no audio.'));
    }

    return {'data': response.bodyBytes, 'extension': 'mp3'};
  }
}

// ---------------------------------------------------------------------------
// OpenAI TTS
// ---------------------------------------------------------------------------
class OpenAiVoiceTask extends VoiceTask {
  OpenAiVoiceTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'OpenAI');
    report(tr('Recording the voice-over...'));

    final body = <String, Object?>{
      'model': request.model,
      'input': request.text,
      'voice': request.voiceId.isEmpty ? 'alloy' : request.voiceId,
      'response_format': 'mp3',
    };

    // `speed` only exists on the tts-1 family.
    if (request.model.startsWith('tts-1') && (request.speed - 1.0).abs() > 1e-9) {
      body['speed'] = request.speed;
    } else if (request.model.startsWith('gpt-4o')) {
      body['instructions'] =
          'Speak like a real person filming a casual selfie video: '
          'upbeat, natural, conversational, not like an announcer.';
    }

    final response = await postJsonForBytes(
      Uri.parse('https://api.openai.com/v1/audio/speech'),
      body,
      headers: {'Authorization': 'Bearer ${request.apiKey}'},
    );

    if (response.statusCode >= 400) {
      throw ProviderException(
          Http.describeError(response.statusCode, response.body));
    }
    if (response.bodyBytes.isEmpty) {
      throw ProviderException(tr('OpenAI returned no audio.'));
    }

    return {'data': response.bodyBytes, 'extension': 'mp3'};
  }
}

// ---------------------------------------------------------------------------
// fal.ai voices
// ---------------------------------------------------------------------------
class FalVoiceTask extends VoiceTask {
  FalVoiceTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'fal.ai');
    report(tr('Recording the voice-over...'));

    final model = request.model;
    final input = <String, Object?>{};

    if (model.contains('minimax')) {
      input['text'] = request.text;
      if (request.voiceId.isNotEmpty) {
        input['voice_setting'] = {'voice_id': request.voiceId};
      }
    } else if (model.contains('elevenlabs')) {
      input['text'] = request.text;
      if (request.voiceId.isNotEmpty) input['voice'] = request.voiceId;
    } else if (model.contains('kokoro')) {
      input['prompt'] = request.text;
      if (request.voiceId.isNotEmpty) input['voice'] = request.voiceId;
    } else {
      input['text'] = request.text;
    }

    final result = await submitFal(request.apiKey, model, input);

    var url = HttpTask.jsonPath(result, 'audio.url');
    if (url.isEmpty) url = HttpTask.jsonPath(result, 'audio_url');
    if (url.isEmpty) url = HttpTask.jsonPath(result, 'url');
    if (url.isEmpty) throw ProviderException(tr('fal.ai returned no audio.'));

    final (data, contentType) = await download(url);
    if (data.isEmpty) throw ProviderException(tr('fal.ai returned no audio.'));

    return {
      'data': data,
      'extension': Http.guessExtension(url, contentType, 'mp3'),
    };
  }
}

// ---------------------------------------------------------------------------
// Whisper subtitles
// ---------------------------------------------------------------------------
class WhisperCaptionTask extends HttpTask {
  WhisperCaptionTask(this.request);

  final TranscribeRequest request;

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'OpenAI');

    final audio = File(request.audioPath);
    if (!audio.existsSync()) {
      throw ProviderException(tr('Could not read the voice-over file.'));
    }
    final audioData = audio.readAsBytesSync();

    report(tr('Timing the subtitles...'));

    final response = await postMultipart(
      Uri.parse('https://api.openai.com/v1/audio/transcriptions'),
      headers: {'Authorization': 'Bearer ${request.apiKey}'},
      fields: {
        'model': request.model,
        'response_format': 'srt',
        // Left out entirely when we do not know: an empty language is not the
        // same request as no language, and Whisper detects it perfectly well
        // from the audio we just had read aloud.
        if (request.language.isNotEmpty) 'language': request.language,
      },
      files: [
        http.MultipartFile.fromBytes(
          'file',
          audioData,
          filename: p.basename(request.audioPath),
          contentType: Http.mediaTypeOf(request.audioPath, audioData),
        ),
      ],
    );

    if (response.statusCode >= 400) {
      throw ProviderException(
          Http.describeError(response.statusCode, response.body));
    }

    final srt = response.body.trim();
    if (srt.isEmpty) {
      throw ProviderException(tr('Whisper returned an empty transcript.'));
    }
    return {'srt': srt};
  }
}

// ---------------------------------------------------------------------------
// Voice cloning
// ---------------------------------------------------------------------------
class ElevenLabsVoiceCloneTask extends HttpTask {
  ElevenLabsVoiceCloneTask(this.request);

  final VoiceCloneRequest request;

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'ElevenLabs');

    if (request.samplePaths.isEmpty) {
      throw ProviderException(tr('Add at least one audio sample to clone from.'));
    }

    report(tr('Uploading the samples...'));

    final files = <http.MultipartFile>[];
    for (final path in request.samplePaths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final data = file.readAsBytesSync();
      files.add(http.MultipartFile.fromBytes(
        'files',
        data,
        filename: p.basename(path),
        contentType: Http.mediaTypeOf(path, data),
      ));
    }

    if (files.isEmpty) {
      throw ProviderException(tr('None of the samples could be read.'));
    }

    final response = await postMultipart(
      Uri.parse('https://api.elevenlabs.io/v1/voices/add'),
      headers: {'xi-api-key': request.apiKey},
      fields: {'name': request.name, 'description': request.description},
      files: files,
      timeout: const Duration(minutes: 10),
    );

    if (response.statusCode >= 400) {
      throw ProviderException(
          Http.describeError(response.statusCode, response.body));
    }

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    final voiceId = decoded is Map ? '${decoded['voice_id'] ?? ''}' : '';
    if (voiceId.isEmpty) {
      throw ProviderException(tr('ElevenLabs did not return a voice id.'));
    }

    return {'voiceId': voiceId, 'name': request.name};
  }
}

// ---------------------------------------------------------------------------
// Voice catalogues
// ---------------------------------------------------------------------------
class ElevenLabsVoiceListTask extends HttpTask {
  ElevenLabsVoiceListTask(this.apiKey);

  final String apiKey;

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(apiKey, 'ElevenLabs');

    final response = await getJson(
      Uri.parse('https://api.elevenlabs.io/v1/voices'),
      headers: {'xi-api-key': apiKey},
    );

    final voices = <VoiceOption>[];
    final array = response['voices'];
    if (array is List) {
      for (final value in array) {
        if (value is! Map) continue;
        final labels = value['labels'];

        final descriptors = <String>[];
        if (labels is Map) {
          for (final key in ['accent', 'gender', 'age', 'use_case', 'description']) {
            final descriptor = '${labels[key] ?? ''}';
            if (descriptor.isNotEmpty) descriptors.add(descriptor);
          }
        }

        voices.add(VoiceOption(
          '${value['voice_id'] ?? ''}',
          '${value['name'] ?? ''}',
          descriptors.join(' - '),
        ));
      }
    }

    if (voices.isEmpty) {
      throw ProviderException(tr('No voices on this ElevenLabs account.'));
    }
    return {'voices': voices};
  }
}

// ---------------------------------------------------------------------------
// Casting: a brief in, a shortlist out
// ---------------------------------------------------------------------------

/// Searches ElevenLabs' shared library for the voices a [VoiceProfile]
/// describes.
///
/// The brief becomes the query. That is the whole design: the library is past
/// ten thousand voices and cannot be pulled down and sifted here, so what the
/// user asked for is what the server is asked for -- in the exact spelling it
/// honours, which is lower case and snake_case throughout. `gender=Female` and
/// `use_cases=Social Media` return nothing; `female` and `social_media` return
/// hundreds.
///
/// Two things are kept strictly apart:
///
///  * **Filtering** decides who is eligible, and is done by the API.
///  * **Ranking** decides who is shown first, and is done here.
///
/// Ranking never promotes a voice past a filter. An American voice cannot rank
/// its way into a French brief, because it was never in the result set and is
/// dropped again on the way out if it somehow is.
class ElevenLabsVoiceSearchTask extends HttpTask {
  ElevenLabsVoiceSearchTask({
    required this.apiKey,
    required this.profile,
    this.limit = 6,
  });

  final String apiKey;
  final VoiceProfile profile;

  /// Five right voices beat fifty of which five are right.
  final int limit;

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(apiKey, 'ElevenLabs');
    report(tr('Looking for voices...'));

    final filters = Map<String, String>.of(profile.filters);

    // Only what this brief actually set can be given up; asking the same
    // question five times is not a search.
    final droppable = [
      for (final key in VoiceProfile.relaxationOrder)
        if (filters.containsKey(key)) key,
    ];
    final relaxed = <String>[];

    for (var step = 0; ; ++step) {
      final found = await _search(filters);
      if (found.isNotEmpty) {
        return {'voices': _rank(found), 'relaxed': relaxed};
      }
      if (step >= droppable.length) {
        return {'voices': const <LibraryVoice>[], 'relaxed': relaxed};
      }
      relaxed.add(droppable[step]);
      filters.remove(droppable[step]);
    }
  }

  Future<List<LibraryVoice>> _search(Map<String, String> filters) async {
    final Map<String, dynamic> response;
    try {
      response = await getJson(
        Uri.https('api.elevenlabs.io', '/v1/shared-voices', {
          'page_size': '100',
          // The voices people are actually cloning, rather than the newest
          // upload nobody has heard.
          'sort': 'trending',
          ...filters,
        }),
        headers: {'xi-api-key': apiKey},
      );
    } on ProviderException catch (error) {
      if (error is TaskCancelled) rethrow;
      // A plan that cannot reach the library, or a key that was refused. Either
      // way there is nothing to rank; the caller falls back to the account.
      _error = error.message;
      return const [];
    }

    final raw = response['voices'];
    if (raw is! List) return const [];

    final wanted = profile.language;
    return [
      for (final entry in raw)
        if (entry is Map)
          LibraryVoice.fromShared(entry.cast<String, Object?>()),
    ].where((voice) {
      // The language is a contract, not a preference. This is belt and braces
      // over the API filter, and it is the line that would have caught the
      // accent bug: `accent` is scoped per language, so `language=fr` with an
      // English accent value used to come back full of English voices.
      if (wanted.isNotEmpty && voice.language != wanted) return false;
      return voice.id.isNotEmpty;
    }).toList();
  }

  /// Out of a hundred, weighted by how much a mismatch costs the ad.
  ///
  /// Everything here already passed the filters that were still in force, so
  /// this is really scoring the parts of the brief that had to be *dropped* to
  /// find anybody: when region was given up, the voices that happen to be from
  /// the right region still come first.
  int _score(LibraryVoice voice) {
    var score = 0;
    if (profile.language.isNotEmpty && voice.language == profile.language) {
      score += 40;
    }
    if (profile.region.isNotEmpty && voice.locale == profile.region) score += 25;
    if (profile.gender.isNotEmpty && voice.gender == profile.gender) score += 15;
    if (profile.age.isNotEmpty && voice.age == profile.age) score += 10;
    if (profile.useCase.isNotEmpty && voice.useCase == profile.useCase) {
      score += 10;
    }
    if (profile.tone.isNotEmpty && voice.descriptive == profile.tone) score += 5;
    return score;
  }

  /// Everything that is not the brief: whether the owner vouches for the
  /// language, whether it costs extra, how many people chose it. Kept as a
  /// separate rung of the sort rather than added to the score, so no amount of
  /// popularity can ever outrank one trait the user asked for.
  int _standing(LibraryVoice voice) =>
      (voice.verified ? 4 : 0) + (voice.premiumRate ? 0 : 2) + (voice.free ? 1 : 0);

  List<LibraryVoice> _rank(List<LibraryVoice> voices) {
    final ordered = List<LibraryVoice>.of(voices)
      ..sort((a, b) {
        final byScore = _score(b).compareTo(_score(a));
        if (byScore != 0) return byScore;
        final byStanding = _standing(b).compareTo(_standing(a));
        if (byStanding != 0) return byStanding;
        final byUse = b.clonedBy.compareTo(a.clonedBy);
        if (byUse != 0) return byUse;
        // Last resort, so the same brief keeps returning the same order.
        return a.id.compareTo(b.id);
      });

    return ordered.take(limit).toList();
  }

  String _error = '';

  /// Why the search came back empty, when the library itself refused us.
  String get error => _error;
}

/// Puts a shared voice on the user's account, which is what lets it speak.
///
/// A library voice is a listing, not something text-to-speech will accept: the
/// copy gets its own id and that is the one the endpoint takes. Done once per
/// voice, on first use rather than on every search -- a shortlist of six must
/// not adopt six.
class ElevenLabsVoiceAdoptTask extends HttpTask {
  ElevenLabsVoiceAdoptTask({
    required this.apiKey,
    required this.voiceId,
    required this.ownerId,
    this.name = '',
  });

  final String apiKey;
  final String voiceId;
  final String ownerId;
  final String name;

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(apiKey, 'ElevenLabs');
    if (voiceId.isEmpty) throw ProviderException(tr('No voice to add.'));
    // Nothing to adopt: it is already an account voice.
    if (ownerId.isEmpty) return {'voiceId': voiceId};

    final owned = await _ownedCopy();
    if (owned.isNotEmpty) return {'voiceId': owned};

    report(tr('Adding the voice to your account...'));

    try {
      final response = await postJson(
        Uri.parse('https://api.elevenlabs.io/v1/voices/add/$ownerId/$voiceId'),
        {'new_name': name.trim().isEmpty ? tr('Market Queen voice') : name.trim()},
        headers: {'xi-api-key': apiKey},
      );
      final added = '${response['voice_id'] ?? ''}';
      if (added.isNotEmpty) return {'voiceId': added};
    } on ProviderException catch (error) {
      if (error is TaskCancelled) rethrow;
      // Best effort: hand back the shared id and let ElevenLabs have the last
      // word rather than lose the run over an add that may not be needed.
    }
    return {'voiceId': voiceId};
  }

  /// The account's own copy, if this voice was adopted before.
  Future<String> _ownedCopy() async {
    final Map<String, dynamic> response;
    try {
      response = await getJson(
        Uri.parse('https://api.elevenlabs.io/v1/voices'),
        headers: {'xi-api-key': apiKey},
      );
    } on ProviderException catch (error) {
      if (error is TaskCancelled) rethrow;
      return '';
    }

    final voices = response['voices'];
    if (voices is! List) return '';

    for (final entry in voices) {
      if (entry is! Map) continue;
      final id = '${entry['voice_id'] ?? ''}';
      if (id == voiceId) return id;

      final sharing = entry['sharing'];
      if (sharing is Map && '${sharing['original_voice_id'] ?? ''}' == voiceId) {
        return id;
      }
    }
    return '';
  }
}

/// OpenAI has no voices endpoint: the set is fixed and documented.
class OpenAiVoiceListTask extends ProviderTask {
  static const _voices = <VoiceOption>[
    VoiceOption('alloy', 'alloy', 'neutral, balanced'),
    VoiceOption('ash', 'ash', 'warm, grounded'),
    VoiceOption('ballad', 'ballad', 'soft, expressive'),
    VoiceOption('coral', 'coral', 'bright, friendly'),
    VoiceOption('echo', 'echo', 'calm, even'),
    VoiceOption('fable', 'fable', 'storytelling'),
    VoiceOption('nova', 'nova', 'energetic, young'),
    VoiceOption('onyx', 'onyx', 'deep, male'),
    VoiceOption('sage', 'sage', 'measured'),
    VoiceOption('shimmer', 'shimmer', 'light, upbeat'),
    VoiceOption('verse', 'verse', 'conversational'),
  ];

  @override
  Future<Map<String, Object?>> execute() async => {'voices': _voices};
}

/// fal has no voices endpoint either: each engine ships its own named set.
/// These are the MiniMax, ElevenLabs and Kokoro presets; any other id can be
/// typed in.
class FalVoiceListTask extends ProviderTask {
  static const _voices = <VoiceOption>[
    VoiceOption('Wise_Woman', 'Wise_Woman', 'MiniMax - warm, mature'),
    VoiceOption('Friendly_Person', 'Friendly_Person', 'MiniMax - upbeat, casual'),
    VoiceOption('Inspirational_girl', 'Inspirational_girl', 'MiniMax - young, energetic'),
    VoiceOption('Deep_Voice_Man', 'Deep_Voice_Man', 'MiniMax - deep, male'),
    VoiceOption('Calm_Woman', 'Calm_Woman', 'MiniMax - calm, female'),
    VoiceOption('Casual_Guy', 'Casual_Guy', 'MiniMax - relaxed, male'),
    VoiceOption('Lively_Girl', 'Lively_Girl', 'MiniMax - lively, female'),
    VoiceOption('Rachel', 'Rachel', 'ElevenLabs - natural, female'),
    VoiceOption('Aria', 'Aria', 'ElevenLabs - expressive, female'),
    VoiceOption('Josh', 'Josh', 'ElevenLabs - young, male'),
    VoiceOption('af_heart', 'af_heart', 'Kokoro - American female'),
    VoiceOption('am_adam', 'am_adam', 'Kokoro - American male'),
  ];

  @override
  Future<Map<String, Object?>> execute() async => {'voices': _voices};
}

