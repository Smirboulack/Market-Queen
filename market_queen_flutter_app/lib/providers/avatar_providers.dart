import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/http_util.dart';
import '../i18n/translator.dart';
import 'provider_task.dart';
import 'types.dart';

abstract class AvatarTask extends HttpTask {
  AvatarTask(this.request);

  final AvatarRequest request;

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
// HeyGen - upload the line, POST /v3/videos, poll, download.
//
// The only provider in the app that animates a photograph nobody registered
// first: `type: "image"` takes the frame straight from the canvas, where the
// other engines want an avatar created on the account beforehand. That is what
// makes it usable from a pipeline -- the actor is whatever the storyboard just
// drew, not a fixture set up by hand in a web app last week.
//
// The engine is chosen by which job is created, not by a field:
//
//   Avatar IV   `type: "image"`  -- the frame goes in the request. One call.
//   Avatar V    `type: "avatar"` -- keyed by a look id, so the frame is
//   Avatar III                      registered as a photo avatar first and the
//                                   job points at that. Three calls and a wait.
//
// An image job takes no `engine` at all and the body schema refuses unknown
// fields, so putting one there fails the request before anything renders. That
// is the whole difference, and it is why the two paths are written out
// separately rather than sharing one body with a flag in it.
// ---------------------------------------------------------------------------
class HeyGenAvatarTask extends AvatarTask {
  HeyGenAvatarTask(super.request);

  static const _base = 'https://api.heygen.com/v3';

  /// The engine that animates a bare photograph, with no look to register.
  static const _photoEngine = 'avatar_iv';

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'HeyGen');
    if (request.imageDataUri.isEmpty) {
      throw ProviderException(tr('No frame to animate.'));
    }
    if (request.audioDataUri.isEmpty) {
      throw ProviderException(
          tr('No audio for this shot, so there is nothing to lip-sync to.'));
    }

    final headers = {'x-api-key': request.apiKey};
    final engine = request.model.isEmpty ? _photoEngine : request.model;

    // The line has to be somewhere HeyGen can fetch it from before the job is
    // created: `audio_url` is validated as a public URL and refuses a data:
    // URI outright. So the few seconds of speech go up as an asset first and
    // the job refers to it by id. The frame does not need this -- both jobs
    // take base64 inline, as long as it is tagged as such.
    report(tr('Uploading the line to HeyGen...'));
    final audioAssetId =
        await _uploadAsset(headers, request.audioDataUri, 'line');

    // The line is already recorded, so HeyGen is asked to lip-sync to it rather
    // than to read the text again in a voice of its own. That is what keeps one
    // actor sounding like one actor across the whole ad.
    final body = <String, Object?>{
      'audio_asset_id': audioAssetId,
      'resolution': '1080p',
      'aspect_ratio':
          request.aspectRatio.isEmpty ? '9:16' : request.aspectRatio,
      'output_format': 'mp4',
    };

    var lookId = '';
    if (engine == _photoEngine) {
      body['type'] = 'image';
      body['image'] = _imageInput();
      // The difference between a head that talks and a person who gestures.
      if (request.prompt.isNotEmpty) body['motion_prompt'] = request.prompt;
      body['expressiveness'] = 'medium';
    } else {
      lookId = await _registerLook(headers, engine);
      body['type'] = 'avatar';
      body['avatar_id'] = lookId;
      body['engine'] = {'type': engine};
      // No motion_prompt on this path, and it is not an oversight. Avatar III
      // has no motion to direct, and Avatar V refuses one outright on a photo
      // avatar whose group holds no reference look -- which is exactly what a
      // look created a moment ago is.
    }

    report(tr('Sending the shot to HeyGen (%1)...').arg(engine));

    try {
      final created =
          await postJson(Uri.parse('$_base/videos'), body, headers: headers);

      final videoId = HttpTask.jsonPath(created, 'data.video_id');
      if (videoId.isEmpty) {
        throw ProviderException(tr('HeyGen did not return a job handle.'));
      }

      final finished = await pollUntil(
        Uri.parse('$_base/videos/$videoId'),
        headers,
        (status) {
          final state = HttpTask.jsonPath(status, 'data.status');
          if (state == 'completed') return PollVerdict.done;
          if (state == 'waiting' ||
              state == 'pending' ||
              state == 'processing') {
            report(tr('Generating...'));
            return PollVerdict.pending;
          }
          // v3 says why in a field of its own rather than in an error object,
          // and that message is the only thing telling a photo it would not
          // animate apart from a render that fell over.
          var message = HttpTask.jsonPath(status, 'data.failure_message');
          if (message.isEmpty) {
            message = HttpTask.jsonPath(status, 'data.error.message');
          }
          return PollVerdict(
            PollState.failed,
            message.isEmpty
                ? tr('HeyGen reported status "%1".').arg(state)
                : message,
          );
        },
      );

      var url = HttpTask.jsonPath(finished, 'data.video_url');
      if (url.isEmpty) url = HttpTask.jsonPath(finished, 'data.url');
      return await deliverFromUrl(url);
    } finally {
      // The look existed to carry one frame into one job. Left behind it is a
      // new avatar in the user's HeyGen library per shot per run, which is a
      // hundred of them inside a week.
      await _forgetLook(headers, lookId);
    }
  }

  /// Registers the frame as a photo avatar and returns the look id.
  ///
  /// This is the whole of what Avatar V and III need that Avatar IV does not:
  /// they only exist on the `avatar` job, which names its subject by look id.
  /// The photograph does not have to be of anybody registered beforehand -- it
  /// is registered here, from the still the storyboard just drew.
  Future<String> _registerLook(
      Map<String, String> headers, String engine) async {
    report(tr('Registering the frame with HeyGen...'));

    final created = await postJson(
      Uri.parse('$_base/avatars'),
      {
        'type': 'photo',
        'name': 'Market Queen ${DateTime.now().millisecondsSinceEpoch}',
        'file': _imageInput(),
      },
      headers: headers,
    );

    final lookId = HttpTask.jsonPath(created, 'data.avatar_item.id');
    if (lookId.isEmpty) {
      throw ProviderException(
          tr('HeyGen would not make an avatar out of this frame.'));
    }

    var engines = _stringList(created, ['data', 'avatar_item', 'supported_api_engines']);

    // Training is asynchronous and the status is only there for a private
    // avatar, so an absent one means there is nothing to wait for.
    if (HttpTask.jsonPath(created, 'data.avatar_item.status') == 'processing') {
      final look = await pollUntil(
        Uri.parse('$_base/avatars/looks/$lookId'),
        headers,
        (body) {
          final state = HttpTask.jsonPath(body, 'data.status');
          if (state.isEmpty || state == 'completed') return PollVerdict.done;
          if (state == 'processing') {
            report(tr('Training the avatar...'));
            return PollVerdict.pending;
          }
          if (state == 'pending_consent') {
            return PollVerdict(
                PollState.failed,
                tr('HeyGen is holding this avatar until consent is recorded in '
                    'a browser. Avatar IV animates the same frame without it.'));
          }
          final message = HttpTask.jsonPath(body, 'data.error.message');
          return PollVerdict(
            PollState.failed,
            message.isEmpty
                ? tr('HeyGen reported status "%1".').arg(state)
                : message,
          );
        },
        interval: const Duration(seconds: 5),
      );
      engines = _stringList(look, ['data', 'supported_api_engines']);
    }

    // Avatar V and III are opt-in per account, and the look itself is where
    // HeyGen says whether this one has it. Reading it here turns a rejected
    // render into a sentence before the job is ever created.
    if (engines.isNotEmpty && !engines.contains(engine)) {
      throw ProviderException(tr('Your HeyGen account is not cleared for %1. '
              'Ask HeyGen to enable it, or film this actor on Avatar IV.')
          .arg(engine));
    }

    return lookId;
  }

  /// Deletes a look this task created. Best effort: the video is already on
  /// disk by the time this runs, and failing the shot over the tidying up
  /// would be losing the thing that was paid for.
  Future<void> _forgetLook(Map<String, String> headers, String lookId) async {
    if (lookId.isEmpty || isCancelled) return;
    try {
      await deleteJson(Uri.parse('$_base/avatars/looks/$lookId'),
          headers: headers);
    } on ProviderException {
      // Left in the library. Untidy, not broken.
    }
  }

  /// The frame, in the shape the `image` and `file` fields expect.
  ///
  /// It is a tagged union rather than a string: a bare data: URI is read as a
  /// url and rejected for not being one.
  Map<String, Object?> _imageInput() {
    final uri = request.imageDataUri;
    if (!uri.startsWith('data:')) return {'type': 'url', 'url': uri};

    final comma = uri.indexOf(',');
    if (comma < 0) throw ProviderException(tr('No frame to animate.'));

    final semicolon = uri.indexOf(';');
    final end = (semicolon > 0 && semicolon < comma) ? semicolon : comma;
    final mimeType = uri.substring(5, end);

    return {
      'type': 'base64',
      'media_type': mimeType.isEmpty ? 'image/png' : mimeType,
      'data': uri.substring(comma + 1),
    };
  }

  /// A list of strings out of a decoded response. [HttpTask.jsonPath] reads
  /// one value; `supported_api_engines` is an array.
  static List<String> _stringList(Map<String, dynamic> root, List<String> path) {
    Object? value = root;
    for (final key in path) {
      if (value is! Map) return const [];
      value = value[key];
    }
    if (value is! List) return const [];
    return [for (final item in value) '$item'];
  }

  /// Puts a file in HeyGen's own asset store and returns the id it landed on.
  ///
  /// One multipart POST, up to 32 MB, and the id comes back ready for whichever
  /// field wanted a hosted file.
  Future<String> _uploadAsset(
    Map<String, String> headers,
    String dataUri,
    String stem,
  ) async {
    var mimeType = '';
    final bytes =
        Http.dataUriPayload(dataUri, mimeType: (value) => mimeType = value);
    if (bytes.isEmpty) {
      throw ProviderException(tr('HeyGen would not accept the upload.'));
    }

    final response = await postMultipart(
      Uri.parse('$_base/assets'),
      headers: headers,
      files: [
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          // HeyGen reads the format off the name, so it is built from the
          // bytes rather than from the part's subtype: audio/mpeg would
          // otherwise arrive as a file called line.mpeg.
          filename: '$stem.${Http.guessExtension('', mimeType, 'mp3')}',
          contentType: Http.mediaType(mimeType),
        ),
      ],
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
    final assetId = decoded is Map<String, dynamic>
        ? HttpTask.jsonPath(decoded, 'data.asset_id')
        : '';
    if (assetId.isEmpty) {
      throw ProviderException(tr('HeyGen would not accept the upload.'));
    }
    return assetId;
  }
}

// ---------------------------------------------------------------------------
// Kling AI Avatar, through fal.ai.
//
// The one reseller path left in the app, and it is a funding decision rather
// than a technical one: Kling sells its own API in packs of several hundred
// dollars that expire, which is the wrong shape for somebody trying this out.
// fal resells the same model by the second. Nothing else is allowed here.
//
// fal accepts a base64 data URI wherever it accepts a file url, and a few
// seconds of speech is small enough that uploading it separately would only add
// a failure mode.
// ---------------------------------------------------------------------------
class FalAvatarTask extends AvatarTask {
  FalAvatarTask(super.request);

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'fal.ai');
    if (request.imageDataUri.isEmpty) {
      throw ProviderException(tr('No frame to animate.'));
    }
    if (request.audioDataUri.isEmpty) {
      throw ProviderException(
          tr('No audio for this shot, so there is nothing to lip-sync to.'));
    }

    final input = <String, Object?>{
      'image_url': request.imageDataUri,
      'audio_url': request.audioDataUri,
      if (request.prompt.isNotEmpty) 'prompt': request.prompt,
    };

    final result = await submitFal(request.apiKey, request.model, input);

    var url = HttpTask.jsonPath(result, 'video.url');
    if (url.isEmpty) url = HttpTask.jsonPath(result, 'videos.0.url');
    if (url.isEmpty) url = HttpTask.jsonPath(result, 'url');
    return deliverFromUrl(url);
  }
}

// ---------------------------------------------------------------------------
// ByteDance OmniHuman 1.5, through fal.ai.
//
// The second and last thing bought through a reseller, and for the same kind of
// reason as Kling: OmniHuman is served from BytePlus behind an account that has
// to be set up and funded before it answers at all, and fal resells the same
// weights by the second. It moves to the direct API the day that account is
// ready; nothing above this class knows which host it came from.
//
// What it is *for* is different from the other two, which is why it is its own
// entry rather than one more model id on the Kling one: HeyGen animates a
// portrait cleanly, Kling animates it cinematically, and OmniHuman moves the
// whole body -- gestures, weight shifts, the head turning to follow a thought.
// It is the one that reads as a person rather than as a photograph talking.
//
// Its two resolutions are not a quality dial but a length one: 1080p refuses
// audio over thirty seconds and 720p takes a minute of it.
// ---------------------------------------------------------------------------
class FalOmniHumanTask extends AvatarTask {
  FalOmniHumanTask(super.request);

  /// What fal caps each resolution at, in seconds of audio.
  static const int secondsAt1080p = 30;
  static const int secondsAt720p = 60;

  @override
  Future<Map<String, Object?>> execute() async {
    requireKey(request.apiKey, 'fal.ai');
    if (request.imageDataUri.isEmpty) {
      throw ProviderException(tr('No frame to animate.'));
    }
    if (request.audioDataUri.isEmpty) {
      throw ProviderException(
          tr('No audio for this shot, so there is nothing to lip-sync to.'));
    }

    final input = <String, Object?>{
      'image_url': request.imageDataUri,
      'audio_url': request.audioDataUri,
      // Whatever the shot's motion prompt says, verbatim: OmniHuman reads it as
      // direction for the body rather than as a description of the frame.
      if (request.prompt.isNotEmpty) 'prompt': request.prompt,
      if (request.resolution.isNotEmpty) 'resolution': request.resolution,
    };

    final result = await submitFal(request.apiKey, request.model, input);

    var url = HttpTask.jsonPath(result, 'video.url');
    if (url.isEmpty) url = HttpTask.jsonPath(result, 'videos.0.url');
    if (url.isEmpty) url = HttpTask.jsonPath(result, 'url');
    return deliverFromUrl(url);
  }
}
