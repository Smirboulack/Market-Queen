import 'dart:convert';

import '../core/http_util.dart';
import '../i18n/translator.dart';
import 'capabilities.dart';
import 'provider_task.dart';
import 'types.dart';

/// Roughly 2.6 spoken words per second for an energetic UGC read.
int _targetWordCount(int seconds) => (seconds * 2.6).toInt().clamp(20, 400);

String _sectionIfSet(String label, String value) =>
    value.trim().isEmpty ? '' : '$label: ${value.trim()}\n';

/// Models like to answer with ```json ... ``` or with a sentence before the
/// object. Pull out the first balanced JSON object instead of failing.
///
/// Public because the writers are no longer the only thing that asks a model
/// for a JSON answer: reading a face out of a photograph does too, and the
/// three ways a model can wrap an object are the same wherever it is asked.
Map<String, dynamic> extractJsonObject(String text) {
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
    ScriptMode.writeScript => tr('Writing the script with %1...').arg(
      request.model,
    ),
  };

  /// What the "direction" key is for, said differently depending on whether
  /// the engine can be directed at all. Asked for unconditionally either
  /// way: a model given a key it must leave empty answers more reliably
  /// than one given a schema that changes shape between calls.
  String get _directionKeyHint => request.deliveryTags
      ? 'the same words again with delivery tags added -- '
          '${DeliveryTags.vocabulary.join(', ')} -- and nothing else changed'
      : 'leave this an empty string';

  /// The rules for the direction, when there is an engine that reads it.
  String get _directionRules => !request.deliveryTags
      ? ''
      : '\n'
          'The "direction" field is the read, not a rewrite. Copy the script '
          'word for word and insert delivery tags into it.\n'
          '- Use only these tags: ${DeliveryTags.vocabulary.join(', ')}.\n'
          '- Three or four in the whole ad, at most. A tag on every sentence '
          'reads as a performance rather than as a person, and it is tiring '
          'to listen to.\n'
          '- Put them where the delivery actually turns: the hook, a genuine '
          'laugh, the beat before the call to action.\n'
          '- Never change, add or remove a single spoken word.\n'
          '${request.performerBrief.isEmpty ? '' : 'Direct it for this '
              'person: ${request.performerBrief}\n'}';

  String get systemPrompt {
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
        'It is filmed as one continuous take of one person talking to their own '
        'phone. There are no scenes and no cuts, so write it as one flowing read '
        'rather than as separate beats.\n'
        '\n'
        'Answer with a single JSON object and nothing else, using exactly these keys:\n'
        '{\n'
        '  "hook": "the first spoken line, under 15 words",\n'
        '  "caption": "a short on-screen title, under 8 words",\n'
        '  "script": "every word spoken, start to finish",\n'
        '  "direction": "$_directionKeyHint",\n'
        '  "imagePrompt": "a photographic prompt for the still this is filmed on: '
        'the person, their expression, how they hold the product, the framing, the '
        'room, the lighting and the phone-camera look",\n'
        '  "videoPrompt": "how they move while they talk: subtle handheld camera, '
        'small natural gestures"\n'
        '}'
        '$_directionRules';
  }

  String get userPrompt {
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
          'so roughly $words spoken words.\n');

    if (request.referenceImageDataUri.isNotEmpty) {
      prompt.write('\nA photo of the product is attached. Describe the real product '
          'accurately in imagePrompt: same shape, same colours, same label.\n');
    }

    prompt.write('\nWrite the ad now. JSON only.');
    return prompt.toString();
  }

  /// Turns whatever the model said into the one read the pipeline films.
  Map<String, Object?> deliver(String rawText, int inputTokens, int outputTokens) {
    if (rawText.trim().isEmpty) {
      throw ProviderException(tr('The model returned an empty answer.'));
    }

    final obj = extractJsonObject(rawText);

    // The read, in the shape asked for -- and in the two shapes models keep
    // answering in anyway: the shot list this used to ask for, and plain prose
    // from a model that ignored the JSON instruction. All three are one take.
    var script = '${obj['script'] ?? ''}'.trim();

    if (script.isEmpty) {
      final lines = <String>[];
      final rawShots = obj['shots'];
      if (rawShots is List) {
        for (final value in rawShots) {
          if (value is! Map) continue;
          final line = '${value['line'] ?? ''}'.trim();
          if (line.isNotEmpty) lines.add(line);
        }
      }
      script = lines.join(' ');
    }

    if (script.isEmpty && obj.isEmpty) script = rawText.trim();

    if (script.isEmpty) {
      throw ProviderException(tr('The model answer did not contain a script.'));
    }

    var hook = '${obj['hook'] ?? ''}'.trim();
    if (hook.isEmpty) {
      hook = script.split(RegExp(r'[.!?]')).first.trim();
    }

    // The direction is only worth keeping when it is the same words. A model
    // that rewrote them under this key has produced a second script, and a
    // second script read aloud is not the ad that was approved.
    var direction = '${obj['direction'] ?? ''}'.trim();
    if (direction.isNotEmpty &&
        DeliveryTags.strip(direction).replaceAll(RegExp(r'\s+'), ' ') !=
            script.replaceAll(RegExp(r'\s+'), ' ')) {
      direction = '';
    }

    return {
      'hook': hook,
      'script': script,
      'direction': direction,
      'caption': '${obj['caption'] ?? ''}'.trim(),
      'imagePrompt': '${obj['imagePrompt'] ?? ''}'.trim(),
      'videoPrompt': '${obj['videoPrompt'] ?? ''}'.trim(),
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

  /// Splits "data:image/png;base64,AAAA" into its media type and payload.
  /// Empty when there is no picture, which is the ordinary case.
  (String, String) splitDataUri(String uri) {
    final comma = uri.indexOf(',');
    final semicolon = uri.indexOf(';');
    if (comma <= 0 || semicolon <= 5 || semicolon > comma) return ('', '');
    return (uri.substring(5, semicolon), uri.substring(comma + 1));
  }

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

    // A plain string when there is no picture: the compatible hosts accept the
    // parts array too, but a bare string is what every one of them documents
    // and the one shape none of them can get wrong.
    final Object content = request.imageDataUri.isEmpty
        ? request.user
        : <Map<String, Object?>>[
            {'type': 'text', 'text': request.user},
            {
              'type': 'image_url',
              'image_url': {'url': request.imageDataUri},
            },
          ];

    final response = await postJson(
      Uri.parse('$base/chat/completions'),
      {
        'model': request.model,
        'messages': [
          {'role': 'system', 'content': request.system},
          {'role': 'user', 'content': content},
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

    final content = <Map<String, Object?>>[];
    if (request.imageDataUri.isNotEmpty) {
      final (mediaType, payload) = splitDataUri(request.imageDataUri);
      if (mediaType.isNotEmpty) {
        content.add({
          'type': 'image',
          'source': {'type': 'base64', 'media_type': mediaType, 'data': payload},
        });
      }
    }
    content.add({'type': 'text', 'text': request.user});

    final response = await postJson(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      {
        'model': request.model,
        'max_tokens': request.maxTokens,
        'system': request.system,
        'messages': [
          {'role': 'user', 'content': content},
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

    final parts = <Map<String, Object?>>[
      {'text': request.user},
    ];
    if (request.imageDataUri.isNotEmpty) {
      final (mimeType, payload) = splitDataUri(request.imageDataUri);
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
