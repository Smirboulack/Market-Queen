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
// HeyGen - POST /v3/videos, poll, download.
//
// The only provider in the app that animates a photograph nobody registered
// first: `type: "image"` takes the frame straight from the canvas, where the
// other engines want an avatar created on the account beforehand. That is what
// makes it usable from a pipeline -- the actor is whatever the storyboard just
// drew, not a fixture set up by hand in a web app last week.
//
// The model id from the catalogue is the *engine*, not a model: HeyGen has one
// endpoint and chooses the renderer from `engine.type`.
// ---------------------------------------------------------------------------
class HeyGenAvatarTask extends AvatarTask {
  HeyGenAvatarTask(super.request);

  static const _base = 'https://api.heygen.com/v3';

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
    report(tr('Sending the shot to HeyGen (%1)...').arg(request.model));

    final created = await postJson(
      Uri.parse('$_base/videos'),
      {
        'type': 'image',
        'image': request.imageDataUri,
        // The line is already recorded, so HeyGen is asked to lip-sync to it
        // rather than to read the text again in a voice of its own. That is
        // what keeps one actor sounding like one actor across the whole ad.
        'audio_url': request.audioDataUri,
        'engine': {'type': request.model},
        'resolution': '1080p',
        'aspect_ratio': '9:16',
        'output_format': 'mp4',
        // Avatar IV only. It is the difference between a head that talks and a
        // person who gestures, and it is ignored by the other engines.
        if (request.prompt.isNotEmpty && request.model == 'avatar_iv')
          'motion_prompt': request.prompt,
        if (request.model == 'avatar_iv') 'expressiveness': 'medium',
      },
      headers: headers,
    );

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
        if (state == 'waiting' || state == 'pending' || state == 'processing') {
          report(tr('Generating...'));
          return PollVerdict.pending;
        }
        final message = HttpTask.jsonPath(status, 'data.error.message');
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
    return deliverFromUrl(url);
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
