import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../core/http_util.dart';
import '../i18n/translator.dart';
import 'provider_task.dart';
import 'types.dart';

/// Puts reference material in fal's storage and hands back the urls, grouped
/// the way the endpoint wants them.
///
/// A task of its own rather than a step inside the video task, because it
/// happens once for a whole batch: ten variations off the same reference clip
/// should upload it once, and a cancelled batch should stop mid-upload rather
/// than finish pushing 200 MB nobody is waiting for.
class FalReferenceUploadTask extends HttpTask {
  FalReferenceUploadTask({
    required this.apiKey,
    this.images = const [],
    this.videos = const [],
    this.audios = const [],
  });

  final String apiKey;
  final List<UploadFile> images;
  final List<UploadFile> videos;
  final List<UploadFile> audios;

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(apiKey, 'fal.ai');
    return {
      'images': await _upload(images),
      'videos': await _upload(videos),
      'audios': await _upload(audios),
    };
  }

  Future<List<String>> _upload(List<UploadFile> files) async {
    final urls = <String>[];
    for (final file in files) {
      report(tr('Uploading %1...').arg(file.name));
      urls.add(await uploadToFal(apiKey, file.data, file.contentType, file.name));
    }
    return urls;
  }
}

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

    final references = request.references;
    if (references.isEmpty && request.imageDataUri.isEmpty) {
      throw ProviderException(tr('No opening frame to animate.'));
    }

    final model = request.model;
    final input = <String, Object?>{'prompt': request.prompt};

    if (!references.isEmpty) {
      // A reference model has no opening frame to place: the material is the
      // input, and the prompt reaches it by handle. Sending an `image_url` here
      // as well would be a field the endpoint never declared.
      input.addAll(references.toInput());
      input.addAll(request.extraInput);
    } else if (request.extraInput.isNotEmpty || request.imageField.isNotEmpty) {
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
// LTX (Lightricks) - submit, get a job id, poll the same path.
//
// The cheapest current-generation clip on the list and the only one billed by
// the second with no minimum, which is why it is the default: it is the one
// model whose price can be quoted exactly before the run.
// ---------------------------------------------------------------------------
class LtxVideoTask extends VideoTask {
  LtxVideoTask(super.request);

  static const _base = 'https://api.ltx.io/v2';

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'LTX');
    if (request.imageDataUri.isEmpty) {
      throw ProviderException(tr('No opening frame to animate.'));
    }

    final headers = {'Authorization': 'Bearer ${request.apiKey}'};
    report(tr('Sending the shot to %1...').arg(request.model));

    final queued = await postJson(
      Uri.parse('$_base/image-to-video'),
      {
        'model': request.model,
        'image_uri': request.imageDataUri,
        'prompt': request.prompt,
        'duration': request.durationSeconds,
        // 720p is where the three-cents-a-second price lives; anything higher
        // doubles the bill for a frame nobody is going to inspect at that size
        // in a vertical ad.
        'resolution': '720p',
        'generate_audio': false,
      },
      headers: headers,
    );

    final jobId = '${queued['id'] ?? ''}';
    if (jobId.isEmpty) {
      throw ProviderException(tr('LTX did not return a job handle.'));
    }

    final finished = await pollUntil(
      Uri.parse('$_base/image-to-video/$jobId'),
      headers,
      (status) {
        final state = '${status['status'] ?? ''}';
        if (state == 'completed') return PollVerdict.done;
        if (state == 'queued' || state == 'processing' || state == 'running') {
          report(tr('Generating...'));
          return PollVerdict.pending;
        }
        final error = '${status['error'] ?? ''}';
        return PollVerdict(
          PollState.failed,
          error.isEmpty ? tr('LTX reported status "%1".').arg(state) : error,
        );
      },
    );

    return deliverFromUrl(HttpTask.jsonPath(finished, 'result.video_url'));
  }
}

// ---------------------------------------------------------------------------
// BytePlus ModelArk - Seedance.
//
// The prompt carries the shot settings as trailing switches ("--resolution
// 720p"), which is ModelArk's own convention, and the reference material rides
// in the same `content` list as the text. Seedance 2.x reads @Image1 / @Video1
// out of the prompt, which is the same handle scheme the reference models use
// on fal, so a prompt written for one works on the other.
// ---------------------------------------------------------------------------
class SeedanceVideoTask extends VideoTask {
  SeedanceVideoTask(super.request);

  static const _base = 'https://ark.ap-southeast.bytepluses.com/api/v3';

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'BytePlus');

    final references = request.references;
    if (references.isEmpty && request.imageDataUri.isEmpty) {
      throw ProviderException(tr('No opening frame to animate.'));
    }

    final headers = {'Authorization': 'Bearer ${request.apiKey}'};
    final content = <Map<String, Object?>>[
      {'type': 'text', 'text': request.prompt},
    ];

    if (references.isEmpty) {
      content.add({
        'type': 'image_url',
        'image_url': {'url': request.imageDataUri},
        'role': 'first_frame',
      });
    } else {
      // Every piece of material is one entry, in the order the prompt names
      // them: @Image1 is the first image, @Video1 the first clip.
      for (final url in references.images) {
        content.add({
          'type': 'image_url',
          'image_url': {'url': url},
          'role': 'reference_image',
        });
      }
      for (final url in references.videos) {
        content.add({
          'type': 'video_url',
          'video_url': {'url': url},
          'role': 'reference_video',
        });
      }
      for (final url in references.audios) {
        content.add({
          'type': 'audio_url',
          'audio_url': {'url': url},
          'role': 'reference_audio',
        });
      }
    }

    report(tr('Sending the shot to %1...').arg(request.model));

    final queued = await postJson(
      Uri.parse('$_base/contents/generations/tasks'),
      {
        'model': request.model,
        'content': content,
        'resolution': '720p',
        'ratio': request.aspectRatio.isEmpty ? '9:16' : request.aspectRatio,
        'duration': request.durationSeconds,
        'generate_audio': false,
        'watermark': false,
      },
      headers: headers,
    );

    final taskId = '${queued['id'] ?? ''}';
    if (taskId.isEmpty) {
      throw ProviderException(tr('BytePlus did not return a job handle.'));
    }

    final finished = await pollUntil(
      Uri.parse('$_base/contents/generations/tasks/$taskId'),
      headers,
      (status) {
        final state = '${status['status'] ?? ''}';
        if (state == 'succeeded') return PollVerdict.done;
        if (state == 'queued' || state == 'running') {
          report(tr('Generating...'));
          return PollVerdict.pending;
        }
        final error = status['error'];
        final message = error is Map ? '${error['message'] ?? ''}' : '';
        return PollVerdict(
          PollState.failed,
          message.isEmpty
              ? tr('BytePlus reported status "%1".').arg(state)
              : message,
        );
      },
    );

    return deliverFromUrl(HttpTask.jsonPath(finished, 'content.video_url'));
  }
}

// ---------------------------------------------------------------------------
// Google Veo - predictLongRunning, then poll the operation by name.
//
// The only model in the app that writes its own soundtrack in the same pass,
// and the only one whose output is deleted by the provider after two days --
// so the download is not optional housekeeping, it is the whole result.
// ---------------------------------------------------------------------------
class VeoVideoTask extends VideoTask {
  VeoVideoTask(super.request);

  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  /// 4, 6 or 8 seconds -- nothing in between, and 8 is forced above 720p.
  int get _seconds {
    if (request.durationSeconds <= 4) return 4;
    if (request.durationSeconds <= 6) return 6;
    return 8;
  }

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'Google Gemini');
    if (request.imageDataUri.isEmpty) {
      throw ProviderException(tr('No opening frame to animate.'));
    }

    final headers = {'x-goog-api-key': request.apiKey};

    var mimeType = '';
    final bytes = Http.dataUriPayload(
      request.imageDataUri,
      mimeType: (value) => mimeType = value,
    );
    if (bytes.isEmpty) {
      throw ProviderException(tr('Could not read the opening frame.'));
    }

    report(tr('Sending the shot to %1...').arg(request.model));

    final started = await postJson(
      Uri.parse('$_base/models/${request.model}:predictLongRunning'),
      {
        'instances': [
          {
            'prompt': request.prompt,
            'image': {
              'bytesBase64Encoded': base64Encode(bytes),
              'mimeType': mimeType,
            },
          },
        ],
        'parameters': {
          'aspectRatio': request.aspectRatio == '16:9' ? '16:9' : '9:16',
          'resolution': '720p',
          'durationSeconds': _seconds,
        },
      },
      headers: headers,
    );

    final operation = '${started['name'] ?? ''}';
    if (operation.isEmpty) {
      throw ProviderException(tr('Veo did not return a job handle.'));
    }

    final finished = await pollUntil(
      Uri.parse('$_base/$operation'),
      headers,
      (status) {
        if (status['done'] == true) {
          final error = status['error'];
          final message = error is Map ? '${error['message'] ?? ''}' : '';
          return message.isEmpty
              ? PollVerdict.done
              : PollVerdict(PollState.failed, message);
        }
        report(tr('Generating...'));
        return PollVerdict.pending;
      },
    );

    final url = HttpTask.jsonPath(
        finished, 'response.generateVideoResponse.generatedSamples.0.video.uri');
    if (url.isEmpty) throw ProviderException(tr('Veo returned no video.'));

    // The file sits behind the same key that made it, so the download has to
    // carry the header rather than being a plain fetch.
    report(tr('Downloading the clip...'));
    final response = await getBytes(Uri.parse(url), headers: headers);
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

// ---------------------------------------------------------------------------
// MiniMax - two generations of API on one key.
//
// H3 is the current model and takes reference material; the Hailuo models are
// the previous generation and take one opening frame. They are different
// endpoints with different bodies, so the model id picks the path.
// ---------------------------------------------------------------------------
class MiniMaxVideoTask extends VideoTask {
  MiniMaxVideoTask(super.request);

  static const _base = 'https://api.minimax.io';

  bool get _isH3 => request.model.toUpperCase().contains('H3');

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'MiniMax');

    final references = request.references;
    if (references.isEmpty && request.imageDataUri.isEmpty) {
      throw ProviderException(tr('No opening frame to animate.'));
    }

    final headers = {'Authorization': 'Bearer ${request.apiKey}'};
    report(tr('Sending the shot to %1...').arg(request.model));

    final taskId = _isH3
        ? await _submitH3(headers)
        : await _submitHailuo(headers);

    // Both generations report through the v1 query endpoint, and it answers
    // with a file id rather than a url -- the file has to be fetched by a
    // second call before there is anything to download.
    final finished = await pollUntil(
      Uri.parse('$_base/v1/query/video_generation?task_id=$taskId'),
      headers,
      (status) {
        final state = '${status['status'] ?? ''}';
        if (state == 'Success') return PollVerdict.done;
        if (state == 'Queueing' || state == 'Preparing' || state == 'Processing') {
          report(tr('Generating...'));
          return PollVerdict.pending;
        }
        return PollVerdict(
            PollState.failed, tr('MiniMax reported status "%1".').arg(state));
      },
    );

    final fileId = '${finished['file_id'] ?? ''}';
    if (fileId.isEmpty) throw ProviderException(tr('MiniMax returned no video.'));

    final file = await getJson(
      Uri.parse('$_base/v1/files/retrieve?file_id=$fileId'),
      headers: headers,
    );
    return deliverFromUrl(HttpTask.jsonPath(file, 'file.download_url'));
  }

  Future<String> _submitH3(Map<String, String> headers) async {
    final references = request.references;
    final content = <Map<String, Object?>>[
      {'type': 'text', 'text': request.prompt},
    ];

    if (references.isEmpty) {
      content.add({
        'type': 'image_url',
        'image_url': request.imageDataUri,
        'role': 'first_frame',
      });
    } else {
      for (final url in references.images) {
        content.add({'type': 'image_url', 'image_url': url});
      }
      for (final url in references.videos) {
        content.add({
          'type': 'video_url',
          'video_url': url,
          'role': 'reference_video',
        });
      }
      for (final url in references.audios) {
        content.add({
          'type': 'audio_url',
          'audio_url': url,
          'role': 'reference_audio',
        });
      }
    }

    final queued = await postJson(
      Uri.parse('$_base/v2/video_generation'),
      {
        'model': request.model,
        'content': content,
        'resolution': '768P',
        'duration': request.durationSeconds.clamp(4, 15),
        'ratio': request.aspectRatio.isEmpty ? '9:16' : request.aspectRatio,
      },
      headers: headers,
    );

    final taskId = '${queued['task_id'] ?? ''}';
    if (taskId.isEmpty) {
      throw ProviderException(tr('MiniMax did not return a job handle.'));
    }
    return taskId;
  }

  Future<String> _submitHailuo(Map<String, String> headers) async {
    final queued = await postJson(
      Uri.parse('$_base/v1/video_generation'),
      {
        'model': request.model,
        'prompt': request.prompt,
        'first_frame_image': request.imageDataUri,
        // 6 or 10 -- the Hailuo models take nothing else.
        'duration': request.durationSeconds > 7 ? 10 : 6,
        'resolution': '768P',
      },
      headers: headers,
    );

    final taskId = '${queued['task_id'] ?? ''}';
    if (taskId.isEmpty) {
      // The failure lands inside base_resp rather than as an HTTP error.
      final message = HttpTask.jsonPath(queued, 'base_resp.status_msg');
      throw ProviderException(message.isEmpty
          ? tr('MiniMax did not return a job handle.')
          : message);
    }
    return taskId;
  }
}

// ---------------------------------------------------------------------------
// xAI - Grok Imagine video. Submit, then poll by request id.
// ---------------------------------------------------------------------------
class XaiVideoTask extends VideoTask {
  XaiVideoTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'xAI');
    if (request.imageDataUri.isEmpty) {
      throw ProviderException(tr('No opening frame to animate.'));
    }

    final headers = {'Authorization': 'Bearer ${request.apiKey}'};
    report(tr('Sending the shot to %1...').arg(request.model));

    final queued = await postJson(
      Uri.parse('https://api.x.ai/v1/videos/generations'),
      {
        'model': request.model,
        'prompt': request.prompt,
        'image_url': request.imageDataUri,
        'duration': request.durationSeconds,
      },
      headers: headers,
    );

    final requestId = '${queued['request_id'] ?? ''}';
    if (requestId.isEmpty) {
      throw ProviderException(tr('xAI did not return a job handle.'));
    }

    final finished = await pollUntil(
      Uri.parse('https://api.x.ai/v1/videos/$requestId'),
      headers,
      (status) {
        final state = '${status['status'] ?? ''}';
        if (state == 'done') return PollVerdict.done;
        if (state == 'failed' || state == 'error') {
          return PollVerdict(PollState.failed, tr('The generation failed.'));
        }
        final progress = (status['progress'] as num?)?.toInt() ?? -1;
        report(progress >= 0
            ? tr('Generating... %1%').arg(progress)
            : tr('Generating...'));
        return PollVerdict.pending;
      },
    );

    return deliverFromUrl(HttpTask.jsonPath(finished, 'video.url'));
  }
}

// ---------------------------------------------------------------------------
// Luma - Ray. Create a generation, poll it by id.
//
// The one model here that takes a closing frame as well as an opening one, and
// that can carry on from a clip it made earlier by pointing a keyframe at that
// generation's id instead of at a picture.
// ---------------------------------------------------------------------------
class LumaVideoTask extends VideoTask {
  LumaVideoTask(super.request);

  static const _base = 'https://api.lumalabs.ai/dream-machine/v1';

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'Luma');
    if (request.imageDataUri.isEmpty) {
      throw ProviderException(tr('No opening frame to animate.'));
    }

    final headers = {'Authorization': 'Bearer ${request.apiKey}'};
    report(tr('Sending the shot to %1...').arg(request.model));

    final created = await postJson(
      Uri.parse('$_base/generations/video'),
      {
        'model': request.model,
        'prompt': request.prompt,
        'keyframes': {
          'frame0': {'type': 'image', 'url': request.imageDataUri},
        },
        'resolution': '720p',
        // "5s" or "9s" -- Luma takes the unit, not a bare number.
        'duration': request.durationSeconds > 7 ? '9s' : '5s',
        'aspect_ratio':
            request.aspectRatio.isEmpty ? '9:16' : request.aspectRatio,
      },
      headers: headers,
    );

    final id = '${created['id'] ?? ''}';
    if (id.isEmpty) {
      throw ProviderException(tr('Luma did not return a job handle.'));
    }

    final finished = await pollUntil(
      Uri.parse('$_base/generations/$id'),
      headers,
      (status) {
        final state = '${status['state'] ?? ''}';
        if (state == 'completed') return PollVerdict.done;
        if (state == 'queued' || state == 'dreaming') {
          report(state == 'queued' ? tr('Waiting in queue...') : tr('Generating...'));
          return PollVerdict.pending;
        }
        final reason = '${status['failure_reason'] ?? ''}';
        return PollVerdict(
          PollState.failed,
          reason.isEmpty ? tr('Luma reported state "%1".').arg(state) : reason,
        );
      },
    );

    return deliverFromUrl(HttpTask.jsonPath(finished, 'assets.video'));
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
