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
    ScriptMode.directVisuals =>
      tr('Directing the shots with %1...').arg(request.model),
    ScriptMode.rewriteLine => tr('Rewriting the line with %1...').arg(
      request.model,
    ),
    ScriptMode.writeScript => tr('Writing the script with %1...').arg(
      request.model,
    ),
  };

  String get systemPrompt {
    if (request.mode == ScriptMode.rewriteLine) {
      return 'You are a senior UGC (user generated content) ad writer. You are handed '
          'one spoken line from a short vertical video ad and one instruction. Rewrite '
          'that line and nothing else.\n'
          '\n'
          'Rules:\n'
          '- Only words that will be spoken out loud. No stage directions, no emojis, '
          'no hashtags, no markdown, no quotation marks.\n'
          '- Sound like a real person talking to a friend: contractions, short '
          'sentences, one idea per sentence.\n'
          '- Keep the meaning and the language of the original line.\n'
          '- Return one line, not several. It has to fit in a single shot.\n'
          '\n'
          'Answer with a single JSON object and nothing else:\n'
          '{"shots": [{"line": "the rewritten line"}]}';
    }

    if (request.mode == ScriptMode.directVisuals) {
      return 'You are the director of a vertical UGC video ad. The spoken lines are '
          'already written and are not yours to change: your only job is to say what '
          'the camera sees while each one is said.\n'
          '\n'
          '${request.directionRules}'
          '\n\n'
          'Answer with a single JSON object and nothing else:\n'
          '{\n'
          '  "shots": [\n'
          '    {\n'
          '      "imagePrompt": "the still this shot starts from: the person, what '
          'they are doing with their hands, the framing, the room, the light",\n'
          '      "videoPrompt": "how it moves over its few seconds: one small human '
          'gesture and one small camera movement"\n'
          '    }\n'
          '  ]\n'
          '}\n'
          'Return exactly one entry per line you were given, in the same order.';
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
    if (request.mode == ScriptMode.rewriteLine) {
      // The beat is what the line is *for*; without it "make it punchier" has
      // no idea whether it is sharpening a hook or a call to action.
      const beatBriefs = <String, String>{
        'hook': 'the hook -- the first three seconds, the line that has to stop '
            'the scroll',
        'problem': 'the problem -- the frustration the viewer recognises',
        'solution': 'the solution -- how the product enters, casually, not as an '
            'advert',
        'benefit': 'the benefit -- one specific, concrete result',
        'cta': 'the call to action -- what to do next, said casually',
      };

      final prompt = StringBuffer()
        ..write(_sectionIfSet('Product', request.productName))
        ..write(_sectionIfSet('What it is', request.productDescription))
        ..write(_sectionIfSet('Target audience', request.audience))
        ..write(_sectionIfSet('The person on camera', request.avatarBrief))
        ..write(
          _sectionIfSet('This line is', beatBriefs[request.beat] ?? ''),
        )
        ..write('\nThe line:\n"${request.lines.isEmpty ? '' : request.lines.first}"\n')
        ..write('\nInstruction: ${request.rewriteInstruction}\n')
        ..write('\nRewrite it now. JSON only.');

      return prompt.toString();
    }

    if (request.mode == ScriptMode.directVisuals) {
      final prompt = StringBuffer()
        ..write(_sectionIfSet('Product', request.productName))
        ..write(_sectionIfSet('What it is', request.productDescription))
        ..write(_sectionIfSet('The person on camera', request.actorBrief))
        ..write(_sectionIfSet('Where they are', request.actorDecor))
        ..write('\nThe lines, in order:\n');

      for (var i = 0; i < request.lines.length; ++i) {
        // A b-roll scene is the one place the person may leave the frame:
        // saying so per line is what stops the model inventing cutaways
        // everywhere else.
        final kind = (i < request.kinds.length && request.kinds[i] == 'broll')
            ? ' [no face on screen, show the product being used or held instead]'
            : '';
        // The beat tells the model what the line is doing, which is what stops
        // a hook and a sign-off being framed identically.
        final beat = (i < request.beats.length && request.beats[i].isNotEmpty)
            ? ' [${request.beats[i]}]'
            : '';
        prompt.write('${i + 1}. "${request.lines[i]}"$beat$kind\n');
      }

      if (request.referenceImageDataUri.isNotEmpty) {
        prompt.write('\nA photo of the product is attached. Describe the real product '
            'accurately wherever it appears: same shape, same colours, same label.\n');
      }

      prompt.write('\nDirect these ${request.lines.length} shot(s) now. JSON only.');
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
      ..write('Language: ${request.language.isEmpty ? 'English' : request.language}\n')
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

  /// Turns whatever the model said into the `shots` shape everything downstream
  /// expects.
  Map<String, Object?> deliver(String rawText, int inputTokens, int outputTokens) {
    if (rawText.trim().isEmpty) {
      throw ProviderException(tr('The model returned an empty answer.'));
    }

    final obj = _extractJsonObject(rawText);

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
// OpenAI - POST /v1/chat/completions
// ---------------------------------------------------------------------------
class OpenAiScriptTask extends ScriptTask {
  OpenAiScriptTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'OpenAI');
    report(progressLabel);

    final base =
        request.baseUrl.isEmpty ? 'https://api.openai.com/v1' : request.baseUrl;

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
