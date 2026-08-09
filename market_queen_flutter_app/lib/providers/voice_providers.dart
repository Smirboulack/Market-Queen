import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../core/http_util.dart';
import '../i18n/translator.dart';
import 'provider_task.dart';
import 'types.dart';

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
      files.add(http.MultipartFile.fromBytes(
        'files',
        file.readAsBytesSync(),
        filename: p.basename(path),
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

/// Kept for the multipart bodies above, which need a content type when the
/// extension alone is ambiguous.
String mimeForPath(String path) =>
    lookupMimeType(path) ?? 'application/octet-stream';
