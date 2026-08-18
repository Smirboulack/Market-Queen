import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
// MiniMax Speech - POST /v1/t2a_v2
//
// The audio comes back hex-encoded inside the JSON rather than as a file, which
// is unusual but saves a round trip. `emotion` and `speed` are per request
// rather than baked into the voice, so the same voice can read one line warmly
// and the next one flat.
// ---------------------------------------------------------------------------
/// MiniMax returns audio hex-encoded inside its JSON rather than as a file --
/// unusual, but it saves a round trip. Empty when the string is not a whole
/// number of bytes, which is what "no audio" looks like from here.
Uint8List decodeHexAudio(String hex) {
  if (hex.isEmpty || hex.length.isOdd) return Uint8List(0);
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; ++i) {
    final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    if (byte == null) return Uint8List(0);
    out[i] = byte;
  }
  return out;
}

class MiniMaxVoiceTask extends VoiceTask {
  MiniMaxVoiceTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'MiniMax');
    report(tr('Recording the voice-over...'));

    final response = await postJson(
      Uri.parse('https://api.minimax.io/v1/t2a_v2'),
      {
        'model': request.model,
        'text': request.text,
        'stream': false,
        'output_format': 'hex',
        'voice_setting': {
          'voice_id': request.voiceId.isEmpty ? 'Friendly_Person' : request.voiceId,
          'speed': request.speed,
        },
        'audio_setting': {
          'format': 'mp3',
          'sample_rate': 44100,
          'bitrate': 128000,
          'channel': 1,
        },
      },
      headers: {'Authorization': 'Bearer ${request.apiKey}'},
    );

    final audio = decodeHexAudio(HttpTask.jsonPath(response, 'data.audio'));
    if (audio.isEmpty) {
      // MiniMax answers 200 with the failure inside base_resp, so an HTTP-level
      // check would report success on an empty file.
      final message = HttpTask.jsonPath(response, 'base_resp.status_msg');
      throw ProviderException(message.isEmpty
          ? tr('MiniMax returned no audio.')
          : tr('MiniMax returned no audio: %1').arg(message));
    }

    return {'data': audio, 'extension': 'mp3'};
  }
}

// ---------------------------------------------------------------------------
// Whisper subtitles
// ---------------------------------------------------------------------------

/// "00:00:03,300" -- the timestamp shape SRT insists on.
String _srtStamp(double seconds) {
  final total = (seconds * 1000).round().clamp(0, 359999999);
  String pad(int value, int width) => '$value'.padLeft(width, '0');
  return '${pad(total ~/ 3600000, 2)}:${pad((total ~/ 60000) % 60, 2)}:'
      '${pad((total ~/ 1000) % 60, 2)},${pad(total % 1000, 3)}';
}

/// Groq serves the same Whisper weights as OpenAI, on a free tier.
///
/// The one thing it will not do is hand back SRT: `json`, `verbose_json` and
/// `text` are the whole list, so the timings come as segments and the file is
/// cut here. That is the only difference from [WhisperCaptionTask] -- the
/// result is the same subtitle file the pipeline was already burning in.
class GroqCaptionTask extends HttpTask {
  GroqCaptionTask(this.request);

  final TranscribeRequest request;

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'Groq');

    final audio = File(request.audioPath);
    if (!audio.existsSync()) {
      throw ProviderException(tr('Could not read the voice-over file.'));
    }
    final audioData = audio.readAsBytesSync();

    report(tr('Timing the subtitles...'));

    final response = await postMultipart(
      Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions'),
      headers: {'Authorization': 'Bearer ${request.apiKey}'},
      fields: {
        'model': request.model,
        'response_format': 'verbose_json',
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

    // Decoded from the bytes rather than from `body`: without a charset on the
    // response, `http` falls back to latin-1 and every accent in the subtitles
    // comes out mangled.
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    } on FormatException {
      decoded = null;
    }
    final segments = decoded is Map ? decoded['segments'] : null;

    final srt = StringBuffer();
    var index = 0;

    if (segments is List) {
      for (final segment in segments) {
        if (segment is! Map) continue;
        final text = '${segment['text'] ?? ''}'.trim();
        if (text.isEmpty) continue;

        final start = (segment['start'] as num?)?.toDouble() ?? 0;
        final end = (segment['end'] as num?)?.toDouble() ?? start;

        index += 1;
        srt
          ..writeln(index)
          ..writeln('${_srtStamp(start)} --> ${_srtStamp(end)}')
          ..writeln(text)
          ..writeln();
      }
    }

    if (index == 0) {
      throw ProviderException(tr('Whisper returned an empty transcript.'));
    }
    return {'srt': srt.toString()};
  }
}

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
// Voice design - POST /v1/text-to-voice/design
//
// A voice out of a sentence describing it. Three takes come back per call and
// only one line of preview text is billed for all three, which is why the whole
// feature costs about what one audition does.
//
// Nothing here creates anything on the account: a take is a `generated_voice_id`
// that lives inside the design call until [ElevenLabsVoiceSaveTask] keeps it.
// That separation is the reason the user can listen to three and throw two
// away without three voices appearing in their library.
// ---------------------------------------------------------------------------
class ElevenLabsVoiceDesignTask extends HttpTask {
  ElevenLabsVoiceDesignTask(this.request);

  final VoiceDesignRequest request;

  /// Their floor, and worth enforcing here rather than discovering as a 422:
  /// a three-word description is not a brief anyone would want three takes of.
  static const int minDescription = 20;

  /// The preview line has to be 100–1000 characters or absent. A short one is
  /// not an error -- it just means the engine writes its own.
  static const int minPreviewText = 100;
  static const int maxPreviewText = 1000;

  /// Only the v3 engine takes a recording to colour the result.
  bool get _takesReference => request.model.toLowerCase().contains('v3');

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'ElevenLabs');

    final description = request.description.trim();
    if (description.length < minDescription) {
      throw ProviderException(
        //: %1 is a number of characters
        tr('Describe the voice in at least %1 characters.').arg(minDescription),
      );
    }

    report(tr('Designing the voice...'));

    final preview = request.previewText.trim();
    final usable = preview.length >= minPreviewText
        ? (preview.length > maxPreviewText
            ? preview.substring(0, maxPreviewText)
            : preview)
        : '';

    final reference = _takesReference ? request.referenceAudioBase64 : '';

    final response = await postJson(
      Uri.parse('https://api.elevenlabs.io/v1/text-to-voice/design'),
      {
        'voice_description': description,
        'model_id': request.model,
        if (usable.isNotEmpty)
          'text': usable
        else
          'auto_generate_text': true,
        'loudness': request.loudness,
        'guidance_scale': request.guidance,
        if (request.seed > 0) 'seed': request.seed,
        if (reference.isNotEmpty) ...{
          'reference_audio_base64': reference,
          'prompt_strength': request.promptStrength,
        },
      },
      headers: {'xi-api-key': request.apiKey},
      // Three takes of a paragraph is not a fast call.
      timeout: const Duration(minutes: 5),
    );

    final takes = <VoicePreview>[];
    final raw = response['previews'];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        final id = '${entry['generated_voice_id'] ?? ''}';
        if (id.isEmpty) continue;

        Uint8List audio;
        try {
          audio = base64Decode('${entry['audio_base_64'] ?? ''}');
        } on FormatException {
          audio = Uint8List(0);
        }
        if (audio.isEmpty) continue;

        takes.add(VoicePreview(
          generatedVoiceId: id,
          audio: audio,
          extension: _extensionOf('${entry['media_type'] ?? ''}'),
          durationSeconds: (entry['duration_secs'] as num?)?.toDouble() ?? 0,
          language: '${entry['language'] ?? ''}',
        ));
      }
    }

    if (takes.isEmpty) {
      throw ProviderException(tr('ElevenLabs returned no voice previews.'));
    }

    return {'previews': takes, 'text': '${response['text'] ?? ''}'};
  }

  /// "audio/mpeg" -> "mp3". The endpoint answers in mp3 unless asked
  /// otherwise, but the media type is what it actually sent.
  static String _extensionOf(String mediaType) {
    final type = mediaType.toLowerCase();
    if (type.contains('wav')) return 'wav';
    if (type.contains('ogg')) return 'ogg';
    if (type.contains('pcm')) return 'pcm';
    return 'mp3';
  }
}

/// Keeps one of the three designed takes as a real voice on the account.
///
/// POST /v1/text-to-voice. The takes that were listened to and passed over are
/// sent with it: ElevenLabs asks for them, and they are the only signal their
/// designer gets about what a rejection looks like.
class ElevenLabsVoiceSaveTask extends HttpTask {
  ElevenLabsVoiceSaveTask(this.request);

  final VoiceSaveRequest request;

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'ElevenLabs');
    if (request.generatedVoiceId.isEmpty) {
      throw ProviderException(tr('Pick one of the takes first.'));
    }

    report(tr('Adding the voice to your account...'));

    final response = await postJson(
      Uri.parse('https://api.elevenlabs.io/v1/text-to-voice'),
      {
        'voice_name': request.name.trim().isEmpty
            ? tr('Market Queen voice')
            : request.name.trim(),
        'voice_description': request.description.trim(),
        'generated_voice_id': request.generatedVoiceId,
        if (request.passedOver.isNotEmpty)
          'played_not_selected_voice_ids': request.passedOver,
      },
      headers: {'xi-api-key': request.apiKey},
    );

    final voiceId = '${response['voice_id'] ?? ''}';
    if (voiceId.isEmpty) {
      throw ProviderException(tr('ElevenLabs did not return a voice id.'));
    }
    return {'voiceId': voiceId, 'name': '${response['name'] ?? request.name}'};
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

/// The same endpoint, read for the shelf rather than for a dropdown.
///
/// [ElevenLabsVoiceListTask] flattens a voice to a name and a line of
/// descriptors, which is all a model picker needs. The shelf needs to play one,
/// say where it came from, and know whether it is the account's copy of a
/// shared voice -- so it keeps the fields rather than joining them, and an
/// account with nothing on it is an empty list rather than an error: a user who
/// has designed no voices yet is in a normal state, not a failed one.
class ElevenLabsAccountVoicesTask extends HttpTask {
  ElevenLabsAccountVoicesTask(this.apiKey);

  final String apiKey;

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(apiKey, 'ElevenLabs');

    final response = await getJson(
      Uri.parse('https://api.elevenlabs.io/v1/voices'),
      headers: {'xi-api-key': apiKey},
    );

    final voices = <AccountVoice>[];
    final array = response['voices'];
    if (array is! List) return {'voices': voices};

    for (final value in array) {
      if (value is! Map) continue;
      final id = '${value['voice_id'] ?? ''}';
      if (id.isEmpty) continue;

      final sharing = value['sharing'];
      final labels = value['labels'];

      // The labels are the only description most voices carry: a designed one
      // has the brief it was made from, a cloned one has nothing at all.
      final descriptors = <String>[];
      if (labels is Map) {
        for (final key in ['accent', 'gender', 'age', 'use_case']) {
          final descriptor = '${labels[key] ?? ''}';
          if (descriptor.isNotEmpty) descriptors.add(descriptor);
        }
      }

      voices.add(AccountVoice(
        id: id,
        name: '${value['name'] ?? ''}',
        category: '${value['category'] ?? ''}',
        description: '${value['description'] ?? ''}'.trim().isEmpty
            ? descriptors.join(' · ')
            : '${value['description']}',
        previewUrl: '${value['preview_url'] ?? ''}',
        sharedId: sharing is Map ? '${sharing['original_voice_id'] ?? ''}' : '',
      ));
    }

    return {'voices': voices};
  }
}

/// Takes a voice off the account for good.
///
/// The one destructive call in the voice code, and it is deliberately not the
/// same gesture as taking a voice off an actor: this reaches every actor that
/// was using it, and the provider has no undo.
class ElevenLabsVoiceDeleteTask extends HttpTask {
  ElevenLabsVoiceDeleteTask({required this.apiKey, required this.voiceId});

  final String apiKey;
  final String voiceId;

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(apiKey, 'ElevenLabs');
    if (voiceId.isEmpty) throw ProviderException(tr('No voice to delete.'));

    report(tr('Removing the voice from your account...'));

    await deleteJson(
      Uri.parse('https://api.elevenlabs.io/v1/voices/$voiceId'),
      headers: {'xi-api-key': apiKey},
    );
    return {'voiceId': voiceId};
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

// ---------------------------------------------------------------------------
// MiniMax voices you make yourself
//
// The same three verbs ElevenLabs has -- design one, clone one, list what is on
// the account -- against a different shape of API, and the differences are not
// cosmetic:
//
//  * **The name is the id.** MiniMax has no separate display name: the
//    `voice_id` you hand it *is* what the voice is called, forever, and it has
//    to be at least eight characters, start with a letter and carry both
//    letters and digits. [MiniMaxVoiceId.from] is what turns a person's answer
//    to "what should this voice be called" into one.
//  * **Designing creates.** ElevenLabs hands back three previews that exist
//    only inside the call, and nothing reaches the account until one is kept.
//    MiniMax's design endpoint takes the id up front and the voice exists as
//    soon as it answers -- so the name has to be asked for *before* the button
//    is pressed, not after a take has been chosen.
//  * **Cloning is two calls.** The sample is uploaded to the files endpoint
//    first and referred to by id, rather than being posted with the request.
// ---------------------------------------------------------------------------

/// The one base the app talks to MiniMax through -- see [MiniMaxVideoTask],
/// which uses the same host and the same bearer auth.
const _miniMaxBase = 'https://api.minimax.io';

Map<String, String> _miniMaxHeaders(String apiKey) => {
      'Authorization': 'Bearer $apiKey',
    };

/// Turns a name somebody typed into an id MiniMax will accept.
///
/// Their rules, all four of them: letters and digits only, at least eight
/// characters, a letter first, and at least one digit somewhere. A name that
/// already satisfies them is passed through unchanged, so a voice called
/// "Sarah2024" is filed under exactly that and is recognisable on their side
/// too. Everything else is padded from the clock rather than from a counter,
/// because two voices made in two sessions must not collide.
class MiniMaxVoiceId {
  MiniMaxVoiceId._();

  static final _allowed = RegExp(r'[^A-Za-z0-9]');

  static String from(String name) {
    var id = name.trim().replaceAll(_allowed, '');
    // It has to begin with a letter, so a name that starts with a digit -- or
    // is nothing but digits -- is given one rather than being rejected.
    if (id.isEmpty || !RegExp(r'^[A-Za-z]').hasMatch(id)) id = 'Voice$id';

    final stamp = DateTime.now().millisecondsSinceEpoch.toString();
    if (!RegExp(r'[0-9]').hasMatch(id)) {
      id = '$id${stamp.substring(stamp.length - 4)}';
    }
    if (id.length < 8) {
      id = '$id${stamp.substring(stamp.length - (8 - id.length))}';
    }
    // Their ceiling. A long name is cut from the end, which keeps the part
    // somebody actually reads.
    return id.length > 64 ? id.substring(0, 64) : id;
  }
}

/// MiniMax answers 200 with the failure inside `base_resp`, so every call has
/// to be checked twice: once for the HTTP status and once for this.
void _requireMiniMaxOk(Map<String, dynamic> response) {
  final code = HttpTask.jsonNumber(response, 'base_resp.status_code');
  if (code == 0) return;
  final message = HttpTask.jsonPath(response, 'base_resp.status_msg');
  throw ProviderException(
    message.isEmpty
        //: %1 is a numeric error code
        ? tr('MiniMax refused the request (code %1).').arg(code.round())
        : message,
  );
}

/// A voice out of a description -- POST /v1/voice_design.
///
/// One take rather than three, and the voice is real the moment this returns:
/// unlike ElevenLabs there is nothing to keep afterwards, which is why the name
/// is a required field on the form rather than a question asked at the end.
class MiniMaxVoiceDesignTask extends HttpTask {
  MiniMaxVoiceDesignTask({
    required this.apiKey,
    required this.description,
    required this.previewText,
    required this.voiceId,
  });

  final String apiKey;
  final String description;
  final String previewText;
  final String voiceId;

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(apiKey, 'MiniMax');
    if (description.trim().isEmpty) {
      throw ProviderException(tr('Describe the voice in a sentence or two '
          'first.'));
    }

    report(tr('Designing the voice...'));

    final response = await postJson(
      Uri.parse('$_miniMaxBase/v1/voice_design'),
      {
        'prompt': description.trim(),
        'preview_text': previewText.trim(),
        'voice_id': voiceId,
      },
      headers: _miniMaxHeaders(apiKey),
      timeout: const Duration(minutes: 5),
    );
    _requireMiniMaxOk(response);

    final audio = decodeHexAudio(HttpTask.jsonPath(response, 'trial_audio'));
    return {
      'voiceId': voiceId,
      // The trial is the only recording of this voice that exists until
      // somebody asks it to read a line, so it is worth keeping even when the
      // response carried none.
      'audio': audio,
      'extension': 'mp3',
    };
  }
}

/// A voice off the user's own recordings -- POST /v1/files/upload, then
/// POST /v1/voice_clone.
class MiniMaxVoiceCloneTask extends HttpTask {
  MiniMaxVoiceCloneTask({
    required this.apiKey,
    required this.voiceId,
    required this.samplePaths,
  });

  final String apiKey;
  final String voiceId;
  final List<String> samplePaths;

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(apiKey, 'MiniMax');
    if (samplePaths.isEmpty) {
      throw ProviderException(tr('Add at least one audio sample to clone '
          'from.'));
    }

    // One file, not a pile. MiniMax clones from a single recording, so sending
    // the second and third would be sending them nowhere -- and the panel says
    // as much before the button is pressed.
    final path = samplePaths.first;
    final file = File(path);
    if (!file.existsSync()) {
      throw ProviderException(tr('None of the samples could be read.'));
    }
    final data = file.readAsBytesSync();

    report(tr('Uploading the samples...'));

    final upload = await postMultipart(
      Uri.parse('$_miniMaxBase/v1/files/upload'),
      headers: _miniMaxHeaders(apiKey),
      fields: {'purpose': 'voice_clone'},
      files: [
        http.MultipartFile.fromBytes(
          'file',
          data,
          filename: p.basename(path),
          contentType: Http.mediaTypeOf(path, data),
        ),
      ],
      timeout: const Duration(minutes: 10),
    );

    if (upload.statusCode >= 400) {
      throw ProviderException(
          Http.describeError(upload.statusCode, upload.body));
    }

    Map<String, dynamic> uploaded;
    try {
      final decoded = jsonDecode(upload.body);
      uploaded = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      uploaded = <String, dynamic>{};
    }
    _requireMiniMaxOk(uploaded);

    // Their id is a number in JSON and a string in the request that follows.
    final fileId = HttpTask.jsonNumber(uploaded, 'file.file_id');
    final fileIdText = fileId > 0
        ? fileId.toStringAsFixed(0)
        : HttpTask.jsonPath(uploaded, 'file.file_id');
    if (fileIdText.isEmpty) {
      throw ProviderException(tr('MiniMax did not accept the recording.'));
    }

    report(tr('Cloning the voice...'));

    final cloned = await postJson(
      Uri.parse('$_miniMaxBase/v1/voice_clone'),
      {'file_id': fileIdText, 'voice_id': voiceId},
      headers: _miniMaxHeaders(apiKey),
      timeout: const Duration(minutes: 10),
    );
    _requireMiniMaxOk(cloned);

    return {'voiceId': voiceId};
  }
}

/// What the user has made on their MiniMax account -- POST /v1/get_voice.
///
/// Only what they made: the system presets are on every account ever opened and
/// are already offered by the Library route, so listing them here would be the
/// same twelve voices twice.
class MiniMaxAccountVoicesTask extends HttpTask {
  MiniMaxAccountVoicesTask(this.apiKey);

  final String apiKey;

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(apiKey, 'MiniMax');

    final response = await postJson(
      Uri.parse('$_miniMaxBase/v1/get_voice'),
      {'voice_type': 'all'},
      headers: _miniMaxHeaders(apiKey),
    );
    _requireMiniMaxOk(response);

    final voices = <AccountVoice>[
      ..._read(response['voice_cloning'], 'cloned'),
      ..._read(response['voice_generation'], 'generated'),
    ];
    return {'voices': voices};
  }

  /// One of their two lists. The description comes back as an array of lines
  /// rather than a string, and a voice with none is the ordinary case.
  List<AccountVoice> _read(Object? raw, String category) {
    if (raw is! List) return const [];

    return [
      for (final entry in raw)
        if (entry is Map)
          AccountVoice(
            id: '${entry['voice_id'] ?? ''}',
            // MiniMax keeps no display name, so the id is the name -- which is
            // exactly why the panel makes one out of what the user typed.
            name: '${entry['voice_name'] ?? entry['voice_id'] ?? ''}',
            category: category,
            description: switch (entry['description']) {
              final List lines => lines.join(' '),
              final Object value => '$value',
              _ => '',
            },
          ),
    ];
  }
}

/// Takes a made voice off the MiniMax account -- POST /v1/delete_voice.
class MiniMaxVoiceDeleteTask extends HttpTask {
  MiniMaxVoiceDeleteTask({
    required this.apiKey,
    required this.voiceId,
    required this.cloned,
  });

  final String apiKey;
  final String voiceId;

  /// Their two buckets. A designed voice deleted as a cloned one is a 400, so
  /// which list it came off has to travel with it.
  final bool cloned;

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(apiKey, 'MiniMax');

    final response = await postJson(
      Uri.parse('$_miniMaxBase/v1/delete_voice'),
      {
        'voice_type': cloned ? 'voice_cloning' : 'voice_generation',
        'voice_id': voiceId,
      },
      headers: _miniMaxHeaders(apiKey),
    );
    _requireMiniMaxOk(response);
    return const {};
  }
}

/// MiniMax ships a fixed set of system voices, named rather than numbered.
/// A cloned voice's id can be typed in instead.
class MiniMaxVoiceListTask extends ProviderTask {
  static const _voices = <VoiceOption>[
    VoiceOption('Friendly_Person', 'Friendly_Person', 'upbeat, casual'),
    VoiceOption('Wise_Woman', 'Wise_Woman', 'warm, mature'),
    VoiceOption('Inspirational_girl', 'Inspirational_girl', 'young, energetic'),
    VoiceOption('Lively_Girl', 'Lively_Girl', 'lively, female'),
    VoiceOption('Calm_Woman', 'Calm_Woman', 'calm, female'),
    VoiceOption('Casual_Guy', 'Casual_Guy', 'relaxed, male'),
    VoiceOption('Deep_Voice_Man', 'Deep_Voice_Man', 'deep, male'),
    VoiceOption('Young_Knight', 'Young_Knight', 'bright, male'),
    VoiceOption('Determined_Man', 'Determined_Man', 'firm, male'),
    VoiceOption('Elegant_Man', 'Elegant_Man', 'polished, male'),
    VoiceOption('Sweet_Girl_2', 'Sweet_Girl_2', 'soft, female'),
    VoiceOption('Patient_Man', 'Patient_Man', 'measured, male'),
  ];

  @override
  Future<Map<String, Object?>> execute() async => {'voices': _voices};
}

