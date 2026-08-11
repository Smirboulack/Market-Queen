import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/http_util.dart';
import '../i18n/translator.dart';
import 'provider_task.dart';
import 'types.dart';

/// gpt-image-1 and dall-e-3 accept different size strings.
String _openAiSize(String model, String aspect) {
  final dalle = model.startsWith('dall-e');
  if (aspect == '16:9') return dalle ? '1792x1024' : '1536x1024';
  if (aspect == '1:1') return '1024x1024';
  return dalle ? '1024x1792' : '1024x1536';
}

abstract class ImageTask extends HttpTask {
  ImageTask(this.request);

  final ImageRequest request;

  Map<String, Object?> deliver(Uint8List data, String extension) {
    if (data.isEmpty) {
      throw ProviderException(tr('The provider returned an empty image.'));
    }
    return {'data': data, 'extension': extension};
  }

  Future<Map<String, Object?>> deliverFromUrl(
    String url,
    String fallback,
  ) async {
    final (data, contentType) = await download(url);
    return deliver(data, Http.guessExtension(url, contentType, fallback));
  }
}

// ---------------------------------------------------------------------------
// Google Gemini - POST /v1beta/interactions
// ---------------------------------------------------------------------------
/// Nano Banana straight from Google rather than through a reseller.
///
/// It is here because it is one of only two ways to draw a frame in this app
/// without a funded account -- Bria's hundred free generations being the other.
/// Same models as any reseller sells, same pictures; the difference is who is
/// billed and whether there is a quota at all.
///
/// Note the endpoint. Images moved to the Interactions API, so this does not
/// share a shape with the `:generateContent` call the script writer makes on
/// the very same key: the prompt and the photo go in a flat `input` list of
/// typed blocks, and the picture comes back at the top level.
class GeminiImageTask extends ImageTask {
  GeminiImageTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'Google Gemini');

    final editing = request.referenceImageDataUri.isNotEmpty;
    report(
      editing
          ? tr('Building the opening frame from your product photo...')
          : tr('Generating the opening frame with %1...').arg(request.model),
    );

    final input = <Map<String, Object?>>[
      {'type': 'text', 'text': request.prompt},
    ];

    // The photo rides along as a block of its own, which is what turns this
    // from "draw something like the product" into an edit of the real one.
    if (editing) {
      var mimeType = '';
      final bytes = Http.dataUriPayload(
        request.referenceImageDataUri,
        mimeType: (value) => mimeType = value,
      );
      if (bytes.isNotEmpty && mimeType.isNotEmpty) {
        input.add({
          'type': 'image',
          'mime_type': mimeType,
          'data': base64Encode(bytes),
        });
      }
    }

    final response = await postJson(
      Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/interactions',
      ),
      {
        'model': request.model,
        'input': input,
        'response_format': {
          'type': 'image',
          'mime_type': 'image/png',
          'aspect_ratio': request.aspectRatio.isEmpty
              ? '9:16'
              : request.aspectRatio,
        },
      },
      headers: {'x-goog-api-key': request.apiKey},
    );

    final image = _imageBlock(response);
    if (image != null) {
      final data = _decodeBase64('${image['data'] ?? ''}');
      if (data.isNotEmpty) {
        return deliver(
          data,
          Http.guessExtension('', '${image['mime_type'] ?? ''}', 'png'),
        );
      }
    }

    // A refusal is a paragraph of prose where the picture should have been, and
    // that paragraph says exactly what it objected to. Losing it behind
    // "returned no image" costs the user the one clue they had.
    final said = '${response['output_text'] ?? ''}'.trim();
    throw ProviderException(
      said.isEmpty
          ? tr('Gemini returned no image.')
          : tr('Gemini returned no image: %1').arg(said),
    );
  }

  /// The generated picture, from the shortcut field or from the output list.
  Map<String, Object?>? _imageBlock(Map<String, dynamic> response) {
    final shortcut = response['output_image'];
    if (shortcut is Map && '${shortcut['data'] ?? ''}'.isNotEmpty) {
      return shortcut.cast<String, Object?>();
    }

    final output = response['output'];
    if (output is List) {
      for (final block in output) {
        if (block is Map &&
            block['type'] == 'image' &&
            '${block['data'] ?? ''}'.isNotEmpty) {
          return block.cast<String, Object?>();
        }
      }
    }
    return null;
  }

  Uint8List _decodeBase64(String value) {
    if (value.isEmpty) return Uint8List(0);
    try {
      return base64Decode(value);
    } on FormatException {
      return Uint8List(0);
    }
  }
}

// ---------------------------------------------------------------------------
// OpenAI Images
// ---------------------------------------------------------------------------
class OpenAiImageTask extends ImageTask {
  OpenAiImageTask(super.request);

  bool supportsInputFidelity(String model) {
    return model == 'gpt-image-1';
  }

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'OpenAI');

    // With a product photo in hand, editing keeps the real product in frame.
    final canEdit =
        request.model.startsWith('gpt-image') &&
        request.referenceImageDataUri.isNotEmpty;
    return canEdit ? _edit() : _generate();
  }

  Future<Map<String, Object?>> _generate() async {
    report(tr('Generating the opening frame with %1...').arg(request.model));

    final body = <String, Object?>{
      'model': request.model,
      'prompt': request.prompt,
      'size': _openAiSize(request.model, request.aspectRatio),
      'n': 1,
      // gpt-image-1 always answers with base64 and rejects response_format.
      if (request.model.startsWith('dall-e')) 'response_format': 'b64_json',
    };

    final response = await postJson(
      Uri.parse('https://api.openai.com/v1/images/generations'),
      body,
      headers: {'Authorization': 'Bearer ${request.apiKey}'},
    );

    final b64 = HttpTask.jsonPath(response, 'data.0.b64_json');
    if (b64.isNotEmpty) return deliver(base64Decode(b64), 'png');

    final url = HttpTask.jsonPath(response, 'data.0.url');
    if (url.isEmpty) throw ProviderException(tr('OpenAI returned no image.'));
    return deliverFromUrl(url, 'png');
  }

  Future<Map<String, Object?>> _edit() async {
    report(tr('Building the opening frame from your product photo...'));

    var mimeType = '';
    final imageBytes = Http.dataUriPayload(
      request.referenceImageDataUri,
      mimeType: (value) => mimeType = value,
    );
    if (imageBytes.isEmpty) return _generate();

    // The type has to be declared, not implied by the file name: `http` sends
    // every part as application/octet-stream otherwise, and the edits endpoint
    // rejects that outright however the part is named.
    final contentType = Http.mediaType(mimeType);

    final response = await postMultipart(
      Uri.parse('https://api.openai.com/v1/images/edits'),
      headers: {'Authorization': 'Bearer ${request.apiKey}'},
      fields: {
        'model': request.model,
        'prompt': request.prompt,
        'size': _openAiSize(request.model, request.aspectRatio),
        'n': '1',
        // input_fidelity is supported by gpt-image-1 but not by gpt-image-1-mini
        // or gpt-image-2.
        if (supportsInputFidelity(request.model)) 'input_fidelity': 'high',
      },
      files: [
        http.MultipartFile.fromBytes(
          'image[]',
          imageBytes,
          filename: 'product.${contentType.subtype}',
          contentType: contentType,
        ),
      ],
    );

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    final json = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};

    final b64 = HttpTask.jsonPath(json, 'data.0.b64_json');
    if (b64.isNotEmpty) return deliver(base64Decode(b64), 'png');

    final url = HttpTask.jsonPath(json, 'data.0.url');
    if (url.isEmpty) {
      final apiError = Http.extractApiError(response.body);
      throw ProviderException(
        apiError.isEmpty ? tr('OpenAI returned no image.') : apiError,
      );
    }
    return deliverFromUrl(url, 'png');
  }
}

// ---------------------------------------------------------------------------
// Black Forest Labs - POST /v1/<model>, then poll the url it hands back.
//
// One endpoint per model rather than a model field, so the id from the
// catalogue is the path. The reply carries `cost` in credits, which is the only
// provider in the app that prices the job before it runs it.
// ---------------------------------------------------------------------------

/// FLUX.2 takes pixels; FLUX.1 Kontext takes a ratio string. Both are here
/// because the two generations are on the same key and the same host.
({int width, int height}) _fluxSize(String aspect) => switch (aspect) {
  '16:9' => (width: 1536, height: 864),
  '1:1' => (width: 1024, height: 1024),
  _ => (width: 864, height: 1536),
};

class BflImageTask extends ImageTask {
  BflImageTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'Black Forest Labs');

    final headers = {'x-key': request.apiKey};
    final editing = request.referenceImageDataUri.isNotEmpty;
    report(
      editing
          ? tr('Building the opening frame from your product photo...')
          : tr('Generating the opening frame with %1...').arg(request.model),
    );

    final body = <String, Object?>{'prompt': request.prompt};

    // The FLUX.2 endpoints size in pixels and have no aspect_ratio field;
    // Kontext is the other way round. Sending the wrong one is a 422, so the
    // two are kept apart rather than sending both and hoping.
    if (request.model.startsWith('flux-2')) {
      final size = _fluxSize(request.aspectRatio);
      body['width'] = size.width;
      body['height'] = size.height;
    } else {
      body['aspect_ratio'] = request.aspectRatio.isEmpty
          ? '9:16'
          : request.aspectRatio;
    }

    if (editing) {
      // BFL wants the payload on its own -- the "data:image/png;base64," part
      // is ours to strip, and leaving it on is a silent 422.
      final bytes = Http.dataUriPayload(request.referenceImageDataUri);
      if (bytes.isNotEmpty) body['input_image'] = base64Encode(bytes);
    }

    final queued = await postJson(
      Uri.parse('https://api.bfl.ai/v1/${request.model}'),
      body,
      headers: headers,
    );

    final pollingUrl = '${queued['polling_url'] ?? ''}';
    if (pollingUrl.isEmpty) {
      throw ProviderException(
        tr('Black Forest Labs did not return a job handle.'),
      );
    }

    // The credits are quoted on the way in; one credit is one cent. Worth
    // saying out loud, because it is the real number rather than our estimate.
    final cost = queued['cost'];
    if (cost is num && cost > 0) {
      report(tr('Costing %1 credits...').arg(cost.toString()));
    }

    final finished = await pollUntil(Uri.parse(pollingUrl), headers, (status) {
      final state = '${status['status'] ?? ''}';
      if (state == 'Ready') return PollVerdict.done;
      if (state == 'Pending' || state == 'Queued' || state == 'Processing') {
        report(tr('Generating...'));
        return PollVerdict.pending;
      }
      // "Request Moderated" and "Content Moderated" are the two refusals, and
      // saying which one it was is the difference between fixing the prompt and
      // fixing the photo.
      return PollVerdict(
        PollState.failed,
        tr('FLUX reported status "%1".').arg(state),
      );
    });

    final url = HttpTask.jsonPath(finished, 'result.sample');
    if (url.isEmpty) {
      throw ProviderException(tr('Black Forest Labs returned no image.'));
    }
    return deliverFromUrl(url, 'png');
  }
}

// ---------------------------------------------------------------------------
// BytePlus ModelArk - Seedream. Synchronous: one POST, picture in the reply.
// ---------------------------------------------------------------------------
class SeedreamImageTask extends ImageTask {
  SeedreamImageTask(super.request);

  /// Pixel sizes rather than the "2K" shorthand, so the frame comes back in the
  /// shape the storyboard asked for instead of whatever the model inferred from
  /// the prose. Both are inside ModelArk's published pixel and ratio bounds.
  String get _size => switch (request.aspectRatio) {
    '16:9' => '2048x1152',
    '1:1' => '1536x1536',
    _ => '1152x2048',
  };

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'BytePlus');

    final editing = request.referenceImageDataUri.isNotEmpty;
    report(
      editing
          ? tr('Building the opening frame from your product photo...')
          : tr('Generating the opening frame with %1...').arg(request.model),
    );

    final response = await postJson(
      Uri.parse(
        'https://ark.ap-southeast.bytepluses.com/api/v3/images/generations',
      ),
      {
        'model': request.model,
        'prompt': request.prompt,
        'size': _size,
        'response_format': 'url',
        // On by default, and it is a visible "AI generated" badge burned into
        // the bottom-right corner -- not something to ship in an ad.
        'watermark': false,
        // Seedream can return a whole related set from one prompt. That is a
        // different feature from the one frame this pipeline asked for, and it
        // bills per image, so it stays off.
        if (!request.model.contains('5-0-pro'))
          'sequential_image_generation': 'disabled',
        // Takes the data: URI as-is, prefix included, unlike BFL.
        if (editing) 'image': request.referenceImageDataUri,
      },
      headers: {'Authorization': 'Bearer ${request.apiKey}'},
    );

    final b64 = HttpTask.jsonPath(response, 'data.0.b64_json');
    if (b64.isNotEmpty) return deliver(base64Decode(b64), 'png');

    final url = HttpTask.jsonPath(response, 'data.0.url');
    if (url.isEmpty) {
      // A refused image comes back as an error object inside data[0] rather
      // than as an HTTP error, so the useful message is in there.
      final refusal = HttpTask.jsonPath(response, 'data.0.error.message');
      throw ProviderException(
        refusal.isEmpty
            ? tr('Seedream returned no image.')
            : tr('Seedream returned no image: %1').arg(refusal),
      );
    }
    return deliverFromUrl(url, 'jpg');
  }
}

// ---------------------------------------------------------------------------
// Ideogram - multipart, and the rendering speed rides in the model id.
// ---------------------------------------------------------------------------

/// "ideogram-v3:QUALITY" -> ("v3", "QUALITY"). The catalogue keeps them joined
/// because the user picks one thing, not two.
({String version, String speed}) _ideogramModel(String modelId) {
  final colon = modelId.indexOf(':');
  if (colon < 0) return (version: modelId, speed: 'DEFAULT');
  return (
    version: modelId.substring(0, colon),
    speed: modelId.substring(colon + 1),
  );
}

class IdeogramImageTask extends ImageTask {
  IdeogramImageTask(super.request);

  /// One of Ideogram's own enumerated sizes -- it rejects anything else.
  String get _resolution => switch (request.aspectRatio) {
    '16:9' => '1344x768',
    '1:1' => '1024x1024',
    _ => '768x1344',
  };

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'Ideogram');
    return request.model == 'upscale' ? _upscale() : _generate();
  }

  Future<Map<String, Object?>> _generate() async {
    final model = _ideogramModel(request.model);
    report(tr('Generating the opening frame with %1...').arg(request.model));

    final files = <http.MultipartFile>[];
    // A product photo goes in as a style reference rather than as something to
    // edit: Ideogram's generate endpoint has no image-to-image, and a style
    // reference is what keeps the palette and the finish consistent across the
    // shots of one ad.
    if (request.referenceImageDataUri.isNotEmpty) {
      var mimeType = '';
      final bytes = Http.dataUriPayload(
        request.referenceImageDataUri,
        mimeType: (value) => mimeType = value,
      );
      if (bytes.isNotEmpty) {
        final contentType = Http.mediaType(mimeType);
        files.add(
          http.MultipartFile.fromBytes(
            'style_reference_images',
            bytes,
            filename: 'reference.${contentType.subtype}',
            contentType: contentType,
          ),
        );
      }
    }

    final response = await postMultipart(
      Uri.parse(
        'https://api.ideogram.ai/v1/ideogram-${model.version}/generate',
      ),
      headers: {'Api-Key': request.apiKey},
      fields: {
        'prompt': request.prompt,
        'resolution': _resolution,
        'rendering_speed': model.speed,
        'num_images': '1',
      },
      files: files,
    );

    return _readImage(response, tr('Ideogram returned no image.'));
  }

  Future<Map<String, Object?>> _upscale() async {
    var mimeType = '';
    final bytes = Http.dataUriPayload(
      request.referenceImageDataUri,
      mimeType: (value) => mimeType = value,
    );
    if (bytes.isEmpty) {
      throw ProviderException(tr('No picture to enlarge.'));
    }

    report(tr('Enlarging...'));
    final contentType = Http.mediaType(mimeType);

    final response = await postMultipart(
      Uri.parse('https://api.ideogram.ai/upscale'),
      headers: {'Api-Key': request.apiKey},
      // image_request is required even when empty: the endpoint is a 422
      // without it, and the defaults inside it are the ones we want.
      fields: {
        'image_request': jsonEncode(<String, Object?>{
          if (request.prompt.isNotEmpty) 'prompt': request.prompt,
        }),
      },
      files: [
        http.MultipartFile.fromBytes(
          'image_file',
          bytes,
          filename: 'source.${contentType.subtype}',
          contentType: contentType,
        ),
      ],
    );

    return _readImage(response, tr('Ideogram returned no enlarged image.'));
  }

  Future<Map<String, Object?>> _readImage(
    http.Response response,
    String emptyMessage,
  ) async {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    final json = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};

    final url = HttpTask.jsonPath(json, 'data.0.url');
    if (url.isEmpty) {
      final apiError = Http.extractApiError(response.body);
      throw ProviderException(apiError.isEmpty ? emptyMessage : apiError);
    }
    return deliverFromUrl(url, 'png');
  }
}

// ---------------------------------------------------------------------------
// Bria - generation and the enlarger, both synchronous.
// ---------------------------------------------------------------------------
class BriaImageTask extends ImageTask {
  BriaImageTask(super.request);

  static const _base = 'https://engine.prod.bria-api.com/v2';

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'Bria');
    return request.model == 'increase_resolution' ? _enlarge() : _generate();
  }

  Future<Map<String, Object?>> _generate() async {
    report(tr('Generating the opening frame with %1...').arg(request.model));

    final response = await postJson(
      Uri.parse('$_base/image/generate'),
      {
        'prompt': request.prompt,
        'model': request.model,
        'aspect_ratio': request.aspectRatio.isEmpty
            ? '9:16'
            : request.aspectRatio,
        if (request.referenceImageDataUri.isNotEmpty)
          'images': [request.referenceImageDataUri],
      },
      headers: {'api_token': request.apiKey},
    );

    final url = '${response['image_url'] ?? ''}';
    if (url.isEmpty) throw ProviderException(tr('Bria returned no image.'));
    return deliverFromUrl(url, 'png');
  }

  Future<Map<String, Object?>> _enlarge() async {
    if (request.referenceImageDataUri.isEmpty) {
      throw ProviderException(tr('No picture to enlarge.'));
    }

    report(tr('Enlarging...'));
    final response = await postJson(
      Uri.parse('$_base/image/increase_resolution'),
      {'image_url': request.referenceImageDataUri, 'desired_increase': 2},
      headers: {'api_token': request.apiKey},
    );

    final url = '${response['image_url'] ?? ''}'.isNotEmpty
        ? '${response['image_url']}'
        : '${response['result_url'] ?? ''}';
    if (url.isEmpty) {
      throw ProviderException(tr('Bria returned no enlarged image.'));
    }
    return deliverFromUrl(url, 'png');
  }
}

// ---------------------------------------------------------------------------
// xAI - Grok Imagine. Two endpoints, generate and edit, both synchronous.
// ---------------------------------------------------------------------------
class XaiImageTask extends ImageTask {
  XaiImageTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'xAI');

    final editing = request.referenceImageDataUri.isNotEmpty;
    report(
      editing
          ? tr('Building the opening frame from your product photo...')
          : tr('Generating the opening frame with %1...').arg(request.model),
    );

    final response = await postJson(
      Uri.parse(
        editing
            ? 'https://api.x.ai/v1/images/edits'
            : 'https://api.x.ai/v1/images/generations',
      ),
      {
        'model': request.model,
        'prompt': request.prompt,
        if (editing)
          'image': {'url': request.referenceImageDataUri, 'type': 'image_url'},
      },
      headers: {'Authorization': 'Bearer ${request.apiKey}'},
    );

    final url = HttpTask.jsonPath(response, 'data.0.url');
    if (url.isEmpty) throw ProviderException(tr('xAI returned no image.'));
    return deliverFromUrl(url, 'jpg');
  }
}
