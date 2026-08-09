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
// fal.ai
//
// Kling AI Avatar, VEED Fabric and InfiniTalk all take the same two inputs, so
// unlike the image-to-video models there is no per-family shaping to do. fal
// accepts a base64 data URI wherever it accepts a file url, and a few seconds
// of speech is small enough that uploading it separately would only add a
// failure mode.
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
