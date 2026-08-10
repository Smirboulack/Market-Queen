import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../core/http_util.dart';
import '../i18n/translator.dart';
import 'provider_task.dart';
import 'types.dart';

abstract class VideoTask extends HttpTask {
  VideoTask(this.request);

  final VideoRequest request;

  Future<Map<String, Object?>> deliverFromUrl(String url) async {
    if (url.isEmpty) throw ProviderException(tr('The provider returned no video.'));

    report(tr('Downloading the clip...'));
    final (data, contentType) = await download(url);
    if (data.isEmpty) throw ProviderException(tr('The downloaded clip was empty.'));

    return {
      'data': data,
      'extension': Http.guessExtension(url, contentType, 'mp4'),
    };
  }
}

// ---------------------------------------------------------------------------
// fal.ai
//
// Every model on fal has its own input schema and rejects unknown fields, so we
// only send the options a model family is known to accept. prompt + image_url
// is the common denominator for image-to-video.
// ---------------------------------------------------------------------------
class FalVideoTask extends VideoTask {
  FalVideoTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'fal.ai');
    if (request.imageDataUri.isEmpty) {
      throw ProviderException(tr('No opening frame to animate.'));
    }

    final model = request.model;
    final input = <String, Object?>{'prompt': request.prompt};

    if (request.extraInput.isNotEmpty || request.imageField.isNotEmpty) {
      // The caller read this model's own schema. It knows what the opening
      // frame is called here and which of duration, resolution and audio the
      // model actually declares, so nothing is added on top of it.
      final field = request.imageField.isEmpty
          ? 'image_url'
          : request.imageField;
      input[field] = request.imageDataUri;
      input.addAll(request.extraInput);
    } else {
      // No schema to hand -- offline, or a model id typed in by hand. Fall back
      // to what the families are known to accept.
      input['image_url'] = request.imageDataUri;
      if (model.contains('kling')) {
        input['duration'] = request.durationSeconds > 7 ? '10' : '5';
      } else if (model.contains('hailuo')) {
        input['duration'] = request.durationSeconds > 7 ? '10' : '6';
      } else if (model.contains('luma')) {
        input['aspect_ratio'] = request.aspectRatio;
      }
    }

    final result = await submitFal(request.apiKey, model, input);

    var url = HttpTask.jsonPath(result, 'video.url');
    if (url.isEmpty) url = HttpTask.jsonPath(result, 'videos.0.url');
    if (url.isEmpty) url = HttpTask.jsonPath(result, 'url');
    return deliverFromUrl(url);
  }
}

// ---------------------------------------------------------------------------
// Replicate
//
// Same story: the first-frame parameter is called `start_image` on Kling and
// `image` almost everywhere else.
// ---------------------------------------------------------------------------
class ReplicateVideoTask extends VideoTask {
  ReplicateVideoTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'Replicate');
    if (request.imageDataUri.isEmpty) {
      throw ProviderException(tr('No opening frame to animate.'));
    }

    final input = <String, Object?>{'prompt': request.prompt};

    if (request.model.contains('kling')) {
      input['start_image'] = request.imageDataUri;
      input['duration'] = request.durationSeconds > 7 ? 10 : 5;
      input['aspect_ratio'] = request.aspectRatio;
    } else {
      input['image'] = request.imageDataUri;
    }

    final prediction = await submitReplicate(request.apiKey, request.model, input);
    return deliverFromUrl(HttpTask.replicateOutputUrl(prediction));
  }
}

// ---------------------------------------------------------------------------
// OpenAI Sora - POST /v1/videos, poll, then download the rendered file.
// ---------------------------------------------------------------------------

/// Sora only renders a fixed set of resolutions, and the reference frame has to
/// match the chosen one exactly.
({int width, int height}) _soraSize(String aspectRatio) =>
    aspectRatio == '16:9' ? (width: 1280, height: 720) : (width: 720, height: 1280);

/// 4, 8 or 12 seconds -- nothing in between.
String _soraSeconds(int requested) {
  if (requested <= 4) return '4';
  if (requested <= 8) return '8';
  return '12';
}

/// Scale to cover, then centre-crop, so the frame fills the target exactly
/// without distortion.
Uint8List _fitToSize(Uint8List imageData, int targetWidth, int targetHeight) {
  final decoded = img.decodeImage(imageData);
  if (decoded == null) return Uint8List(0);

  final scale = (targetWidth / decoded.width) > (targetHeight / decoded.height)
      ? targetWidth / decoded.width
      : targetHeight / decoded.height;

  final scaled = img.copyResize(
    decoded,
    width: (decoded.width * scale).ceil(),
    height: (decoded.height * scale).ceil(),
    interpolation: img.Interpolation.cubic,
  );

  final cropped = img.copyCrop(
    scaled,
    x: (scaled.width - targetWidth) ~/ 2,
    y: (scaled.height - targetHeight) ~/ 2,
    width: targetWidth,
    height: targetHeight,
  );

  return Uint8List.fromList(img.encodePng(cropped));
}

class SoraVideoTask extends VideoTask {
  SoraVideoTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'OpenAI');
    if (request.imageDataUri.isEmpty) {
      throw ProviderException(tr('No opening frame to animate.'));
    }

    final size = _soraSize(request.aspectRatio);
    final frame = _fitToSize(
      Http.dataUriPayload(request.imageDataUri),
      size.width,
      size.height,
    );
    if (frame.isEmpty) {
      throw ProviderException(tr('Could not prepare the opening frame for Sora.'));
    }

    report(tr('Sending the shot to Sora (%1)...').arg(request.model));

    final submitted = await postMultipart(
      Uri.parse('https://api.openai.com/v1/videos'),
      headers: {'Authorization': 'Bearer ${request.apiKey}'},
      fields: {
        'model': request.model,
        'prompt': request.prompt,
        'seconds': _soraSeconds(request.durationSeconds),
        'size': '${size.width}x${size.height}',
      },
      files: [
        http.MultipartFile.fromBytes(
          'input_reference',
          frame,
          filename: 'frame.png',
          // _fitToSize re-encodes to PNG; saying so is what keeps the part from
          // going up as an unnamed binary blob.
          contentType: Http.mediaType('image/png'),
        ),
      ],
    );

    Object? decoded;
    try {
      decoded = jsonDecode(submitted.body);
    } on FormatException {
      decoded = null;
    }
    final videoId =
        decoded is Map ? '${decoded['id'] ?? ''}' : '';
    if (videoId.isEmpty) {
      final apiError = Http.extractApiError(submitted.body);
      throw ProviderException(
          apiError.isEmpty ? tr('Sora did not return a job id.') : apiError);
    }

    await _pollJob(videoId);
    return _fetchContent(videoId);
  }

  Future<void> _pollJob(String videoId) async {
    await pollUntil(
      Uri.parse('https://api.openai.com/v1/videos/$videoId'),
      {'Authorization': 'Bearer ${request.apiKey}'},
      (status) {
        final state = '${status['status'] ?? ''}';
        if (state == 'completed') return PollVerdict.done;
        if (state == 'queued' || state == 'in_progress') {
          final progress = (status['progress'] as num?)?.toInt() ?? -1;
          report(progress >= 0
              ? tr('Sora is rendering... %1%').arg(progress)
              : tr('Sora is rendering...'));
          return PollVerdict.pending;
        }
        final error = status['error'];
        final message = error is Map ? '${error['message'] ?? ''}' : '';
        return PollVerdict(
          PollState.failed,
          message.isEmpty ? tr('Sora reported status "%1".').arg(state) : message,
        );
      },
    );
  }

  Future<Map<String, Object?>> _fetchContent(String videoId) async {
    report(tr('Downloading the clip...'));

    final response = await getBytes(
      Uri.parse('https://api.openai.com/v1/videos/$videoId/content'),
      headers: {'Authorization': 'Bearer ${request.apiKey}'},
    );
    if (response.statusCode >= 400) {
      throw ProviderException(
          Http.describeError(response.statusCode, response.body));
    }
    if (response.bodyBytes.isEmpty) {
      throw ProviderException(tr('The downloaded clip was empty.'));
    }

    return {'data': response.bodyBytes, 'extension': 'mp4'};
  }
}
