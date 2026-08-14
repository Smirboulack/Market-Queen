import 'dart:convert';
import 'dart:math' as math;

import '../core/http_util.dart';
import '../i18n/translator.dart';
import 'provider_task.dart';
import 'types.dart';

/// Roughly 2.6 spoken words per second for an energetic UGC read.
int _targetWordCount(int seconds) => (seconds * 2.6).toInt().clamp(20, 400);

String _sectionIfSet(String label, String value) =>
    value.trim().isEmpty ? '' : '$label: ${value.trim()}\n';

/// Models like to answer with ```json ... ``` or with a sentence before the
/// object. Pull out the first balanced JSON object instead of failing.
Map<String, dynamic> _extractJsonObject(String text) {
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    decoded = null;
  }
  if (decoded is Map<String, dynamic>) return decoded;

  final start = text.indexOf('{');
  if (start < 0) return {};

  var depth = 0;
  var inString = false;
  var escaped = false;

  for (var i = start; i < text.length; ++i) {
    final char = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    if (char == '"') {
      inString = true;
    } else if (char == '{') {
      depth += 1;
    } else if (char == '}') {
      depth -= 1;
      if (depth == 0) {
        try {
          final candidate = jsonDecode(text.substring(start, i + 1));
          return candidate is Map<String, dynamic> ? candidate : {};
        } on FormatException {
          return {};
        }
      }
    }
  }
  return {};
}

/// Shared prompt building and answer parsing for the three script writers.
abstract class ScriptTask extends HttpTask {
  ScriptTask(this.request);

  final ScriptRequest request;

  String get progressLabel => switch (request.mode) {
    ScriptMode.rewriteScript => tr('Reworking the scenario with %1...').arg(
      request.model,
    ),
    ScriptMode.planShots => tr('Planning the shots with %1...').arg(
      request.model,
    ),
    ScriptMode.writeScript => tr('Writing the script with %1...').arg(
      request.model,
    ),
  };

  String get systemPrompt {
    if (request.mode == ScriptMode.planShots) {
      return 'You are the director of a UGC (user generated content) video ad. The '
          'script is already written and already cut into shots. You may not change '
          'a single word of it: you are deciding what the camera is on for each '
          'shot, and describing the picture.\n'
          '\n'
          'A shot is one of two kinds:\n'
          '- "talking": the actor is on camera saying that line, mouth lip-synced '
          'to it.\n'
          '- "broll": the line is still heard, as voice-over, but the camera is on '
          'the product, the screen, the packaging or the actor\'s hands. No face '
          'speaking to camera.\n'
          '\n'
          'Rules:\n'
          '- Most shots are "talking". Make a shot "broll" when its line describes '
          'the product, shows it, names what it does or lists a feature. Roughly '
          'one shot in three, and never two in a row.\n'
          '- The first shot and the last shot are always "talking": a hook has to '
          'come from a face, and so does the call to action.\n'
          '- Consecutive shots must look clearly different. Change the angle, the '
          'distance or the framing -- never the person, the product or the room.\n'
          '- imagePrompt: a photographic prompt for the still this shot opens on. '
          'What is in frame, how it is framed, the light, the phone-camera look. A '
          'broll shot has nobody\'s face in it.\n'
          '- videoPrompt: how the shot moves over its few seconds. Small, '
          'handheld, real.\n'
          '- Write both prompts in English whatever language the script is in: '
          'they are read by an image model, not by a viewer.\n'
          '\n'
          'Answer with a single JSON object and nothing else: one entry per shot, '
          'in the order you were given them, the same number of entries.\n'
          '{"shots": [{"kind": "talking", "imagePrompt": "...", '
          '"videoPrompt": "..."}]}';
    }

    if (request.mode == ScriptMode.rewriteScript) {
      return 'You are a senior UGC (user generated content) ad writer. You are handed '
          'the scenario of a short vertical video ad and one instruction. Rewrite that '
          'scenario and nothing else.\n'
          '\n'
          'Rules:\n'
          '- Only words that will be spoken out loud. No stage directions, no scene '
          'headings, no emojis, no hashtags, no markdown, no quotation marks.\n'
          '- Sound like a real person talking to a friend: contractions, short '
          'sentences, one idea per sentence.\n'
          '- Keep the meaning, the claims and the language of the original. Invent no '
          'claim that is not already in it.\n'
          '- It is one continuous take of one person talking. Never break it into '
          'scenes, parts or numbered beats.\n'
          '\n'
          'Answer with a single JSON object and nothing else:\n'
          '{"script": "the rewritten scenario"}';
    }

    return 'You are a senior UGC (user generated content) ad writer. You write short '
        'vertical video ads that look like a real person filmed themselves, not like '
        'a brand commercial.\n'
        '\n'
        'Rules for the spoken script:\n'
        '- Open with a scroll-stopping hook in the first 3 seconds.\n'
        '- Sound like a real person talking to a friend: contractions, short sentences, '
        'one idea per sentence.\n'
        '- No stage directions, no emojis, no hashtags, no markdown, no quotation marks.\n'
        '- Only words that will be spoken out loud.\n'
        '- End with one clear, casual call to action.\n'
        '\n'
        'The ad is cut into shots. Each shot is one camera setup that stays on screen '
        'for about five seconds while its line is spoken. Consecutive shots must look '
        'clearly different -- change the angle, the framing or what is in the frame -- '
        'but keep the same person, the same product and the same place throughout.\n'
        '\n'
        'Answer with a single JSON object and nothing else, using exactly these keys:\n'
        '{\n'
        '  "hook": "the first spoken line, under 15 words",\n'
        '  "caption": "a short on-screen title, under 8 words",\n'
        '  "shots": [\n'
        '    {\n'
        '      "line": "the words spoken while this shot is on screen",\n'
        '      "kind": "talking if the actor is on camera saying the line, broll if '
        'the line is voice-over over the product, the screen or their hands. Roughly '
        'one shot in three is broll, never two in a row, never the first or the last",\n'
        '      "imagePrompt": "a photographic prompt for this shot: the person, their '
        'expression, how they hold the product, the framing, the room, the lighting and '
        'the phone-camera look",\n'
        '      "videoPrompt": "how this shot should move over its few seconds: subtle '
        'handheld camera, small natural gestures"\n'
        '    }\n'
        '  ]\n'
        '}';
  }

  String get userPrompt {
    if (request.mode == ScriptMode.planShots) {
      final prompt = StringBuffer()
        ..write(_sectionIfSet('Product', request.productName))
        ..write(_sectionIfSet('What it is', request.productDescription))
        ..write(_sectionIfSet('Target audience', request.audience))
        ..write(_sectionIfSet('The person on camera', request.avatarBrief))
        ..write(_sectionIfSet('Where they are', request.extraInstructions))
        ..write('\nThe ${request.lines.length} shots, in order:\n');

      for (var i = 0; i < request.lines.length; ++i) {
        prompt.write('${i + 1}. ${request.lines[i]}\n');
      }

      if (request.referenceImageDataUri.isNotEmpty) {
        prompt.write('\nA photo of the product is attached. Describe the real '
            'product accurately in every imagePrompt: same shape, same colours, '
            'same label.\n');
      }

      prompt.write('\nGive me exactly ${request.lines.length} entries, in the same '
          'order. JSON only.');
      return prompt.toString();
    }

    if (request.mode == ScriptMode.rewriteScript) {
      final prompt = StringBuffer()
        ..write(_sectionIfSet('Product', request.productName))
        ..write(_sectionIfSet('What it is', request.productDescription))
        ..write(_sectionIfSet('Target audience', request.audience))
        ..write(_sectionIfSet('The person on camera', request.avatarBrief))
        ..write(_sectionIfSet('Where they are', request.extraInstructions))
        ..write(
          '\nThe scenario:\n"""\n'
          '${request.lines.isEmpty ? '' : request.lines.first}\n"""\n',
        )
        ..write('\nInstruction: ${request.rewriteInstruction}\n')
        ..write('\nRewrite it now. JSON only.');

      return prompt.toString();
    }

    final words = _targetWordCount(request.durationSeconds);
    final perShot = math.max(1, words ~/ math.max(1, request.shotCount));

    final prompt = StringBuffer()
      ..write(_sectionIfSet('Product', request.productName))
      ..write(_sectionIfSet('What it is', request.productDescription))
      ..write(_sectionIfSet('Target audience', request.audience))
      ..write(_sectionIfSet('Tone', request.tone))
      ..write(_sectionIfSet('Person on camera', request.avatarBrief))
      ..write(_sectionIfSet('Extra instructions', request.extraInstructions))
      // Defaulting to English wrote English ads for people who had just filled
      // in the entire brief in their own language.
      ..write(request.language.isEmpty
          ? 'Write it in the same language as the brief above.\n'
          : 'Language: ${request.language}\n')
      ..write('Target length: about ${request.durationSeconds} seconds, '
          'so roughly $words spoken words.\n')
      ..write('Write it as exactly ${request.shotCount} shots, so about $perShot words '
          'per shot. Split the script where the thought changes, not mid-sentence.\n');

    if (request.referenceImageDataUri.isNotEmpty) {
      prompt.write('\nA photo of the product is attached. Describe the real product '
          'accurately in imagePrompt: same shape, same colours, same label.\n');
    }

    prompt.write('\nWrite the ad now. JSON only.');
    return prompt.toString();
  }

  /// Anything that is not an explicit product shot is someone talking.
  ///
  /// A shot with no face in it is the exception, so a model that answered with
  /// a word we do not recognise must not silently produce one -- a talking shot
  /// that should have been b-roll is a dull ad, a b-roll shot that should have
  /// been talking is an ad with nobody in it.
  static String shotKind(Object? value) =>
      '${value ?? ''}'.trim().toLowerCase() == 'broll' ? 'broll' : 'talking';

  /// A camera on each shot of a scenario the user wrote.
  ///
  /// The lines are deliberately not read back. The model was handed them
  /// numbered and answers by position, so taking only the kind and the two
  /// prompts is what makes "it will not rewrite your words" a property of the
  /// code rather than a line in a prompt.
  Map<String, Object?> _deliverPlan(
    Map<String, dynamic> object,
    int inputTokens,
    int outputTokens,
  ) {
    final plan = <Map<String, Object?>>[];

    final rawShots = object['shots'];
    if (rawShots is List) {
      for (final value in rawShots) {
        if (value is! Map) continue;
        plan.add({
          'kind': shotKind(value['kind']),
          'imagePrompt': '${value['imagePrompt'] ?? ''}'.trim(),
          'videoPrompt': '${value['videoPrompt'] ?? ''}'.trim(),
        });
      }
    }

    if (plan.isEmpty) {
      throw ProviderException(tr('The model returned no shot plan.'));
    }

    return {
      'plan': plan,
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
    };
  }

  /// Turns whatever the model said into the `shots` shape everything downstream
  /// expects.
  Map<String, Object?> deliver(String rawText, int inputTokens, int outputTokens) {
    if (rawText.trim().isEmpty) {
      throw ProviderException(tr('The model returned an empty answer.'));
    }

    final obj = _extractJsonObject(rawText);

    if (request.mode == ScriptMode.planShots) {
      return _deliverPlan(obj, inputTokens, outputTokens);
    }

    final shots = <Map<String, Object?>>[];
    final lines = <String>[];

    final rawShots = obj['shots'];
    if (rawShots is List) {
      for (final value in rawShots) {
        if (value is! Map) continue;
        final line = '${value['line'] ?? ''}'.trim();
        if (line.isEmpty) continue;
        lines.add(line);
        shots.add({
          'line': line,
          'kind': shotKind(value['kind']),
          'imagePrompt': '${value['imagePrompt'] ?? ''}'.trim(),
          'videoPrompt': '${value['videoPrompt'] ?? ''}'.trim(),
        });
      }
    }

    var script = lines.join(' ');

    // Some models answer in the shape we asked for before shots existed, and a
    // model that ignored the JSON instruction altogether still gave us usable
    // copy. Both become a single shot rather than a failed run; the pipeline
    // splits it up afterwards.
    if (shots.isEmpty) {
      script = '${obj['script'] ?? ''}'.trim();
      if (script.isEmpty && obj.isEmpty) script = rawText.trim();
      if (script.isNotEmpty) {
        shots.add({
          'line': script,
          'kind': 'talking',
          'imagePrompt': '${obj['imagePrompt'] ?? ''}'.trim(),
          'videoPrompt': '${obj['videoPrompt'] ?? ''}'.trim(),
        });
      }
    }

    if (script.isEmpty) {
      throw ProviderException(tr('The model answer did not contain a script.'));
    }

    var hook = '${obj['hook'] ?? ''}'.trim();
    if (hook.isEmpty) {
      hook = script.split(RegExp(r'[.!?]')).first.trim();
    }

    return {
      'hook': hook,
      'script': script,
      'shots': shots,
      'caption': '${obj['caption'] ?? ''}'.trim(),
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
    };
  }

  /// Splits "data:image/png;base64,AAAA" into its media type and payload.
  (String, String) splitDataUri(String uri) {
    final comma = uri.indexOf(',');
    final semicolon = uri.indexOf(';');
    if (comma <= 0 || semicolon <= 5 || semicolon > comma) return ('', '');
    return (uri.substring(5, semicolon), uri.substring(comma + 1));
  }
}

// ---------------------------------------------------------------------------
// One question, one paragraph back
//
// The same three wire formats as the writers above, without the JSON schema:
// used by the prompt doctor, which hands a model somebody's half-written prompt
// and takes back a better one. It is a separate pair of classes rather than a
// fourth mode on [ScriptTask] because nothing about it is a shot list -- no
// hook, no caption, no shots, nothing to parse.
// ---------------------------------------------------------------------------

abstract class TextTask extends HttpTask {
  TextTask(this.request);

  final TextRequest request;

  /// What came back, trimmed of the quotes and the "Here is your prompt:" a
  /// model sometimes wraps it in.
  Map<String, Object?> deliver(String text) {
    var answer = text.trim();
    if (answer.isEmpty) {
      throw ProviderException(tr('The model returned an empty answer.'));
    }

    // A fenced block is the commonest wrapper, and the fence is never part of
    // the prompt.
    if (answer.startsWith('```')) {
      final firstBreak = answer.indexOf('\n');
      final lastFence = answer.lastIndexOf('```');
      if (firstBreak > 0 && lastFence > firstBreak) {
        answer = answer.substring(firstBreak + 1, lastFence).trim();
      }
    }
    if (answer.length > 1 && answer.startsWith('"') && answer.endsWith('"')) {
      answer = answer.substring(1, answer.length - 1).trim();
    }

    return {'text': answer};
  }
}

class OpenAiTextTask extends TextTask {
  OpenAiTextTask(super.request, {this.host = '', this.vendor = 'OpenAI'});

  final String host;
  final String vendor;

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, vendor);

    final fallback = host.isEmpty ? 'https://api.openai.com/v1' : host;
    final base = request.baseUrl.isEmpty ? fallback : request.baseUrl;

    final response = await postJson(
      Uri.parse('$base/chat/completions'),
      {
        'model': request.model,
        'messages': [
          {'role': 'system', 'content': request.system},
          {'role': 'user', 'content': request.user},
        ],
      },
      headers: {'Authorization': 'Bearer ${request.apiKey}'},
    );

    return deliver(HttpTask.jsonPath(response, 'choices.0.message.content'));
  }
}

class AnthropicTextTask extends TextTask {
  AnthropicTextTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'Anthropic');

    final response = await postJson(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      {
        'model': request.model,
        'max_tokens': request.maxTokens,
        'system': request.system,
        'messages': [
          {'role': 'user', 'content': request.user},
        ],
      },
      headers: {
        'x-api-key': request.apiKey,
        'anthropic-version': '2023-06-01',
      },
    );

    final blocks = response['content'];
    if (blocks is List) {
      for (final block in blocks) {
        if (block is Map && block['type'] == 'text') {
          return deliver('${block['text'] ?? ''}');
        }
      }
    }
    return deliver('');
  }
}

class GeminiTextTask extends TextTask {
  GeminiTextTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'Google Gemini');

    final response = await postJson(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/'
          '${request.model}:generateContent'),
      {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': request.user},
            ],
          },
        ],
        'systemInstruction': {
          'parts': [
            {'text': request.system},
          ],
        },
      },
      headers: {'x-goog-api-key': request.apiKey},
    );

    return deliver(
      HttpTask.jsonPath(response, 'candidates.0.content.parts.0.text'),
    );
  }
}

// ---------------------------------------------------------------------------
// OpenAI - POST /v1/chat/completions
//
// Also drives xAI and MiniMax. Both publish an endpoint that speaks this exact
// wire format on their own host, so what would otherwise be two more writers is
// one line in the factory: the same body, the same parsing, a different address
// and the user's key for that provider.
// ---------------------------------------------------------------------------
class OpenAiScriptTask extends ScriptTask {
  OpenAiScriptTask(super.request, {this.host = '', this.vendor = 'OpenAI'});

  /// Set by the factory for the compatible providers. The request's own
  /// [ScriptRequest.baseUrl] still wins, so a user-configured gateway is not
  /// overridden by the provider we think we are talking to.
  final String host;
  final String vendor;

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, vendor);
    report(progressLabel);

    final fallback = host.isEmpty ? 'https://api.openai.com/v1' : host;
    final base = request.baseUrl.isEmpty ? fallback : request.baseUrl;

    final userContent = <Map<String, Object?>>[
      {'type': 'text', 'text': userPrompt},
      if (request.referenceImageDataUri.isNotEmpty)
        {
          'type': 'image_url',
          'image_url': {'url': request.referenceImageDataUri},
        },
    ];

    final response = await postJson(
      Uri.parse('$base/chat/completions'),
      {
        'model': request.model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userContent},
        ],
        'response_format': {'type': 'json_object'},
      },
      headers: {'Authorization': 'Bearer ${request.apiKey}'},
    );

    final usage = response['usage'];
    return deliver(
      HttpTask.jsonPath(response, 'choices.0.message.content'),
      usage is Map ? (usage['prompt_tokens'] as num?)?.toInt() ?? 0 : 0,
      usage is Map ? (usage['completion_tokens'] as num?)?.toInt() ?? 0 : 0,
    );
  }
}

// ---------------------------------------------------------------------------
// Anthropic - POST /v1/messages
// ---------------------------------------------------------------------------
class AnthropicScriptTask extends ScriptTask {
  AnthropicScriptTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'Anthropic');
    report(progressLabel);

    final content = <Map<String, Object?>>[];
    if (request.referenceImageDataUri.isNotEmpty) {
      final (mediaType, payload) = splitDataUri(request.referenceImageDataUri);
      if (mediaType.isNotEmpty) {
        content.add({
          'type': 'image',
          'source': {'type': 'base64', 'media_type': mediaType, 'data': payload},
        });
      }
    }
    content.add({'type': 'text', 'text': userPrompt});

    final response = await postJson(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      {
        'model': request.model,
        'max_tokens': 2000,
        'system': systemPrompt,
        'messages': [
          {'role': 'user', 'content': content},
        ],
      },
      headers: {
        'x-api-key': request.apiKey,
        'anthropic-version': '2023-06-01',
      },
    );

    final usage = response['usage'];
    final inputTokens = usage is Map ? (usage['input_tokens'] as num?)?.toInt() ?? 0 : 0;
    final outputTokens = usage is Map ? (usage['output_tokens'] as num?)?.toInt() ?? 0 : 0;

    // Skip any leading thinking blocks and take the first text block.
    final blocks = response['content'];
    if (blocks is List) {
      for (final block in blocks) {
        if (block is Map && block['type'] == 'text') {
          return deliver('${block['text'] ?? ''}', inputTokens, outputTokens);
        }
      }
    }
    return deliver('', inputTokens, outputTokens);
  }
}

// ---------------------------------------------------------------------------
// Google Gemini - POST /v1beta/models/{model}:generateContent
// ---------------------------------------------------------------------------
class GeminiScriptTask extends ScriptTask {
  GeminiScriptTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'Google Gemini');
    report(progressLabel);

    final parts = <Map<String, Object?>>[
      {'text': userPrompt},
    ];
    if (request.referenceImageDataUri.isNotEmpty) {
      final (mimeType, payload) = splitDataUri(request.referenceImageDataUri);
      if (mimeType.isNotEmpty) {
        parts.add({
          'inline_data': {'mime_type': mimeType, 'data': payload},
        });
      }
    }

    final response = await postJson(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/'
          '${request.model}:generateContent'),
      {
        'contents': [
          {'role': 'user', 'parts': parts},
        ],
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt},
          ],
        },
        'generationConfig': {'responseMimeType': 'application/json'},
      },
      headers: {'x-goog-api-key': request.apiKey},
    );

    final usage = response['usageMetadata'];
    return deliver(
      HttpTask.jsonPath(response, 'candidates.0.content.parts.0.text'),
      usage is Map ? (usage['promptTokenCount'] as num?)?.toInt() ?? 0 : 0,
      usage is Map ? (usage['candidatesTokenCount'] as num?)?.toInt() ?? 0 : 0,
    );
  }
}
