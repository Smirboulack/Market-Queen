import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../i18n/translator.dart';
import 'version.dart';

/// Shared HTTP plumbing: headers, error shapes and the data: URIs the
/// providers accept in place of a hosted file.
class Http {
  Http._();

  static const userAgent = 'MarketQueen/$appVersion';

  /// One client for the whole app: keeps connections alive between API calls.
  static final http.Client client = http.Client();

  static Map<String, String> jsonHeaders([Map<String, String> extra = const {}]) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': userAgent,
        ...extra,
      };

  /// Pulls the most common error shapes out of an API response body.
  static String extractApiError(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return '';
    }
    if (decoded is! Map) return '';

    // {"error": {"message": "..."}} - OpenAI, Anthropic, Google
    final error = decoded['error'];
    if (error is Map) {
      for (final key in ['message', 'detail', 'type']) {
        final value = error[key];
        if (value is String && value.isNotEmpty) return value;
      }
    }
    if (error is String && error.isNotEmpty) return error;

    // {"detail": "..."} or {"detail": [{"msg": "..."}]} - fal, BFL, Ideogram
    final detail = decoded['detail'];
    if (detail is String && detail.isNotEmpty) return detail;
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map) {
        final msg = first['msg'];
        if (msg is String && msg.isNotEmpty) return msg;
      }
    }
    // {"detail": {"message": "..."}} - ElevenLabs. Without this the whole JSON
    // blob lands in the log, which is how a one-line "this model does not take
    // that field" reads as a wall of nothing.
    if (detail is Map) {
      for (final key in ['message', 'msg', 'status', 'code']) {
        final value = detail[key];
        if (value is String && value.isNotEmpty) return value;
      }
    }

    for (final key in ['message', 'title']) {
      final value = decoded[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return '';
  }

  /// Human-readable error out of a finished response, including the provider's
  /// own error body when there is one -- that message is usually what the user
  /// needs ("insufficient quota", "invalid api key", ...).
  static String describeError(int statusCode, String body) {
    final apiMessage = extractApiError(body);
    final base = 'HTTP $statusCode';

    if (apiMessage.isNotEmpty) return '$base - ${_simplified(apiMessage)}';
    if (body.isNotEmpty) {
      final head = body.length > 400 ? body.substring(0, 400) : body;
      return '$base - ${_simplified(head)}';
    }
    return base;
  }

  static String _simplified(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// What bytes actually are, whatever the file is called.
  ///
  /// The extension is a claim, not evidence. A shop's AVIF saved as ".png" is
  /// exactly the file that sails through every check here and comes back from
  /// the model as a 400, so nothing downstream is allowed to trust the name.
  static String sniffMime(List<int> data) =>
      lookupMimeType('', headerBytes: data.take(64).toList()) ?? '';

  /// The image formats every model in the app will look at.
  ///
  /// Anything else has to be turned into one of these before it is sent.
  /// Labelling an AVIF "image/png" does not make it readable -- it only moves
  /// the rejection one API call further away from the cause.
  static const acceptedImageMimes = <String>{
    'image/png',
    'image/jpeg',
    'image/webp',
    'image/gif',
  };

  /// Encodes a local image as a data: URI a model will accept, converting and
  /// re-compressing as needed. Providers take these in place of a hosted URL,
  /// which lets the app stay storage-free.
  ///
  /// Empty when the file cannot be read or decoded -- a shop's AVIF, a phone's
  /// HEIC. That is not a failure to paper over: the caller has ffmpeg to try
  /// instead, and something to tell the user if that fails too.
  static String imageToDataUri(String path, {int maxBytes = 2 * 1024 * 1024}) {
    final file = File(path);
    if (!file.existsSync()) return '';

    Uint8List data;
    try {
      data = file.readAsBytesSync();
    } on FileSystemException {
      return '';
    }
    return imageBytesToDataUri(data, maxBytes: maxBytes);
  }

  /// The same, for bytes that never were a file -- a frame just generated, or
  /// a picture something else has already converted.
  static String imageBytesToDataUri(
    Uint8List data, {
    int maxBytes = 2 * 1024 * 1024,
  }) {
    if (data.isEmpty) return '';

    var bytes = data;
    var mime = sniffMime(data);

    // A format nothing reads and a file too big to inline are one problem with
    // one answer: decode it, and hand over something everybody takes.
    if (!acceptedImageMimes.contains(mime) || bytes.length > maxBytes) {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return '';

      final resized = (decoded.width > 2048 || decoded.height > 2048)
          ? img.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? 2048 : null,
              height: decoded.height > decoded.width ? 2048 : null,
              interpolation: img.Interpolation.average,
            )
          : decoded;

      // PNG while there is transparency worth keeping, JPEG once there is not:
      // a photograph re-encoded as PNG is several times the size and no better.
      final png = resized.hasAlpha ? img.encodePng(resized) : const <int>[];
      if (png.isNotEmpty && png.length <= maxBytes) {
        bytes = Uint8List.fromList(png);
        mime = 'image/png';
      } else {
        final jpeg = img.encodeJpg(resized, quality: 88);
        if (jpeg.isEmpty) return '';
        bytes = Uint8List.fromList(jpeg);
        mime = 'image/jpeg';
      }
    }

    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  /// The content type one part of a multipart upload declares.
  ///
  /// `http` defaults every part to application/octet-stream and never looks at
  /// the filename, which is what OpenAI's uploads were rejecting: a PNG called
  /// product.png, sent as a binary blob.
  static MediaType mediaType(String mimeType) {
    final parts = mimeType.split(';').first.trim().split('/');
    if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return MediaType(parts[0], parts[1]);
    }
    return MediaType('application', 'octet-stream');
  }

  /// The content type of a file about to be uploaded, read from its bytes and
  /// falling back to its name.
  static MediaType mediaTypeOf(String path, List<int> data) {
    final sniffed = sniffMime(data);
    if (sniffed.isNotEmpty) return mediaType(sniffed);
    return mediaType(lookupMimeType(path) ?? '');
  }

  /// Encodes any local file as a data: URI, verbatim. Used for the few seconds
  /// of speech a talking shot is lip-synced to -- small enough that uploading
  /// it separately would only add a failure mode.
  static String fileToDataUri(String path, {int maxBytes = 12 * 1024 * 1024}) {
    final file = File(path);
    if (!file.existsSync()) return '';

    Uint8List data;
    try {
      data = file.readAsBytesSync();
    } on FileSystemException {
      return '';
    }
    if (data.isEmpty || data.length > maxBytes) return '';

    final mime = lookupMimeType(path, headerBytes: data.take(64).toList()) ??
        'application/octet-stream';
    return 'data:$mime;base64,${base64Encode(data)}';
  }

  /// Decodes "data:&lt;mime&gt;;base64,&lt;payload&gt;" back into raw bytes.
  static Uint8List dataUriPayload(String uri, {void Function(String)? mimeType}) {
    if (!uri.startsWith('data:')) return Uint8List(0);
    final comma = uri.indexOf(',');
    if (comma < 0) return Uint8List(0);

    if (mimeType != null) {
      final semicolon = uri.indexOf(';');
      final end = (semicolon > 0 && semicolon < comma) ? semicolon : comma;
      mimeType(uri.substring(5, end));
    }
    try {
      return base64Decode(uri.substring(comma + 1));
    } on FormatException {
      return Uint8List(0);
    }
  }

  static const _knownExtensions = {
    'png', 'jpg', 'jpeg', 'webp', 'gif',
    'mp4', 'mov', 'webm', 'mp3', 'wav',
    'm4a', 'ogg', 'flac',
  };

  static const _extensionByMime = {
    'image/png': 'png',
    'image/jpeg': 'jpg',
    'image/webp': 'webp',
    'video/mp4': 'mp4',
    'video/webm': 'webm',
    'video/quicktime': 'mov',
    'audio/mpeg': 'mp3',
    'audio/mp3': 'mp3',
    'audio/wav': 'wav',
    'audio/x-wav': 'wav',
    'audio/mp4': 'm4a',
    'audio/ogg': 'ogg',
  };

  static String guessExtension(String url, String contentType, String fallback) {
    final path = Uri.tryParse(url)?.path ?? '';
    final suffix = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (_knownExtensions.contains(suffix)) return suffix;

    final ct = contentType.split(';').first.trim().toLowerCase();
    return _extensionByMime[ct] ?? fallback;
  }

  /// A local path out of either a file: URL or a plain path.
  static String toLocalPath(String value) {
    if (value.startsWith('file:')) {
      try {
        return Uri.parse(value).toFilePath();
      } on ArgumentError {
        return value;
      }
    }
    return value;
  }

  static String toFileUrl(String path) {
    if (path.isEmpty || path.startsWith('file:')) return path;
    return Uri.file(path).toString();
  }
}

/// Thrown by the provider tasks; the message is already user-facing.
class ProviderException implements Exception {
  ProviderException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Raised when a task is cancelled, so the pipeline can tell it apart from a
/// genuine failure.
class TaskCancelled extends ProviderException {
  TaskCancelled() : super(tr('Cancelled.'));
}
