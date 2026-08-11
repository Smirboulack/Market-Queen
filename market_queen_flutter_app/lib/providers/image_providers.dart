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

String _falImageSize(String aspect) {
  if (aspect == '16:9') return 'landscape_16_9';
  if (aspect == '1:1') return 'square_hd';
  return 'portrait_16_9';
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

  Future<Map<String, Object?>> deliverFromUrl(String url, String fallback) async {
    final (data, contentType) = await download(url);
    return deliver(data, Http.guessExtension(url, contentType, fallback));
  }
}

// ---------------------------------------------------------------------------
// Google Gemini - POST /v1beta/interactions
// ---------------------------------------------------------------------------
/// Nano Banana straight from Google rather than through a reseller.
///
/// It is here because it is the only way to draw a frame in this app without a
/// funded account: fal and Replicate both want money on the table before they
/// render anything, and this wants a Google account. Same models, same
/// pictures -- the difference is who is billed and whether there is a quota.
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
    report(editing
        ? tr('Building the opening frame from your product photo...')
        : tr('Generating the opening frame with %1...').arg(request.model));

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
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/interactions'),
      {
        'model': request.model,
        'input': input,
        'response_format': {
          'type': 'image',
          'mime_type': 'image/png',
          'aspect_ratio':
              request.aspectRatio.isEmpty ? '9:16' : request.aspectRatio,
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
    throw ProviderException(said.isEmpty
        ? tr('Gemini returned no image.')
        : tr('Gemini returned no image: %1').arg(said));
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

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'OpenAI');

    // With a product photo in hand, editing keeps the real product in frame.
    final canEdit = request.model.startsWith('gpt-image') &&
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
        // Without this the endpoint runs at `low`, which is its default and
        // which explicitly does not preserve faces: the person comes back
        // recognisably redrawn rather than edited. That is the whole job here
        // -- an actor has to still be the same actor, a bottle the same bottle
        // -- so it is worth the extra input tokens it costs.
        //
        // Left off gpt-image-1-mini, which is the one model in the family that
        // rejects the field.
        if (!request.model.contains('mini')) 'input_fidelity': 'high',
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
    final json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

    final b64 = HttpTask.jsonPath(json, 'data.0.b64_json');
    if (b64.isNotEmpty) return deliver(base64Decode(b64), 'png');

    final url = HttpTask.jsonPath(json, 'data.0.url');
    if (url.isEmpty) {
      final apiError = Http.extractApiError(response.body);
      throw ProviderException(
          apiError.isEmpty ? tr('OpenAI returned no image.') : apiError);
    }
    return deliverFromUrl(url, 'png');
  }
}

// ---------------------------------------------------------------------------
// fal.ai
// ---------------------------------------------------------------------------
class FalImageTask extends ImageTask {
  FalImageTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'fal.ai');

    final input = <String, Object?>{
      'prompt': request.prompt,
      'image_size': _falImageSize(request.aspectRatio),
      'num_images': 1,
    };

    if (request.referenceImageDataUri.isNotEmpty) {
      // Image-to-image models read this; text-to-image models ignore it. The
      // newer edit endpoints (nano-banana-pro/edit, flux-2-*/edit, ...) take a
      // list instead, so send both spellings and let each model pick the one it
      // knows.
      input['image_url'] = request.referenceImageDataUri;
      input['image_urls'] = [request.referenceImageDataUri];
    }

    final result = await submitFal(request.apiKey, request.model, input);

    var url = HttpTask.jsonPath(result, 'images.0.url');
    if (url.isEmpty) url = HttpTask.jsonPath(result, 'image.url');
    if (url.isEmpty) throw ProviderException(tr('fal.ai returned no image.'));

    return deliverFromUrl(url, 'png');
  }
}

// ---------------------------------------------------------------------------
// Replicate
// ---------------------------------------------------------------------------
class ReplicateImageTask extends ImageTask {
  ReplicateImageTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'Replicate');

    final input = <String, Object?>{
      'prompt': request.prompt,
      'aspect_ratio':
          request.aspectRatio.isEmpty ? '9:16' : request.aspectRatio,
      'output_format': 'png',
      if (request.referenceImageDataUri.isNotEmpty)
        'image_prompt': request.referenceImageDataUri,
    };

    final prediction = await submitReplicate(request.apiKey, request.model, input);
    final url = HttpTask.replicateOutputUrl(prediction);
    if (url.isEmpty) throw ProviderException(tr('Replicate returned no image.'));

    return deliverFromUrl(url, 'png');
  }
}
