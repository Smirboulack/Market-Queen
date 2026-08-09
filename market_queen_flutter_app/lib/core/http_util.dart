import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
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

    // {"detail": "..."} or {"detail": [{"msg": "..."}]} - fal, Replicate
    final detail = decoded['detail'];
    if (detail is String && detail.isNotEmpty) return detail;
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map) {
        final msg = first['msg'];
        if (msg is String && msg.isNotEmpty) return msg;
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

  /// Encodes a local image as a data: URI, re-compressing to JPEG when the file
  /// is large. Providers accept these in place of a hosted URL, which lets the
  /// app stay storage-free.
  static String imageToDataUri(String path, {int maxBytes = 2 * 1024 * 1024}) {
    final file = File(path);
    if (!file.existsSync()) return '';

    Uint8List data;
    try {
      data = file.readAsBytesSync();
    } on FileSystemException {
      return '';
    }
    if (data.isEmpty) return '';

    var mime = lookupMimeType(path, headerBytes: data.take(64).toList()) ?? '';
    if (!mime.startsWith('image/')) mime = 'image/png';

    if (data.length > maxBytes) {
      final decoded = img.decodeImage(data);
      if (decoded != null) {
        final resized = (decoded.width > 2048 || decoded.height > 2048)
            ? img.copyResize(
                decoded,
                width: decoded.width >= decoded.height ? 2048 : null,
                height: decoded.height > decoded.width ? 2048 : null,
                interpolation: img.Interpolation.average,
              )
            : decoded;
        final recompressed = img.encodeJpg(resized, quality: 88);
        if (recompressed.isNotEmpty) {
          data = Uint8List.fromList(recompressed);
          mime = 'image/jpeg';
        }
      }
    }

    return 'data:$mime;base64,${base64Encode(data)}';
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
