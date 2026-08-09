import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/http_util.dart';
import '../i18n/translator.dart';

/// One in-flight provider operation.
///
/// Every provider call returns a task rather than a value: the API calls are
/// slow (a video generation is minutes) and must never block the UI. In Qt this
/// was a QObject emitting `succeeded`/`failed` exactly once; here it is a
/// Future that completes or throws [ProviderException], which lets the pipeline
/// read as the straight line it always was.
abstract class ProviderTask {
  final _listeners = <void Function(String)>[];

  bool _cancelled = false;
  bool _finished = false;
  Future<Map<String, Object?>>? _running;

  bool get isCancelled => _cancelled;
  bool get isFinished => _finished;

  void onProgress(void Function(String) listener) => _listeners.add(listener);

  void report(String message) {
    if (_finished || message.isEmpty) return;
    for (final listener in List.of(_listeners)) {
      listener(message);
    }
  }

  /// Runs the task, once. Repeated calls return the same future.
  Future<Map<String, Object?>> run() => _running ??= _guarded();

  Future<Map<String, Object?>> _guarded() async {
    try {
      final result = await execute();
      if (_cancelled) throw TaskCancelled();
      return result;
    } finally {
      _finished = true;
      dispose();
    }
  }

  /// Subclasses do the work here and throw [ProviderException] to fail.
  Future<Map<String, Object?>> execute();

  void cancel() {
    if (_finished) return;
    _cancelled = true;
    dispose();
  }

  /// Releases whatever the task holds open. Subclasses extend it.
  void dispose() {}

  /// Guard for providers that need a key.
  void requireKey(String apiKey, String providerLabel) {
    if (apiKey.isNotEmpty) return;
    throw ProviderException(
        tr('No API key for %1. Add it in Settings.').arg(providerLabel));
  }

  void throwIfCancelled() {
    if (_cancelled) throw TaskCancelled();
  }
}

enum PollState { pending, done, failed }

/// The verdict on one poll tick: whether to keep waiting, and why not.
class PollVerdict {
  const PollVerdict(this.state, [this.error = '']);

  static const pending = PollVerdict(PollState.pending);
  static const done = PollVerdict(PollState.done);

  final PollState state;
  final String error;
}

/// Base class for the HTTP-backed providers: request helpers, uniform error
/// reporting, cancellation, and long-poll support for queue-based APIs.
abstract class HttpTask extends ProviderTask {
  /// Its own client, so [cancel] can tear down whatever is in flight.
  final http.Client _client = http.Client();

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  // ---- Primitives -------------------------------------------------------

  Future<Map<String, dynamic>> postJson(
    Uri url,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final response = await _send(
      http.Request('POST', url)
        ..headers.addAll(Http.jsonHeaders(headers))
        ..body = jsonEncode(body),
      timeout,
    );
    return _decodeJson(response);
  }

  Future<Map<String, dynamic>> getJson(
    Uri url, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final response = await _send(
      http.Request('GET', url)..headers.addAll(Http.jsonHeaders(headers)),
      timeout,
    );
    return _decodeJson(response);
  }

  /// POSTs JSON and takes the raw body back -- the TTS endpoints answer with
  /// audio, not with a JSON envelope around it.
  Future<http.Response> postJsonForBytes(
    Uri url,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(minutes: 5),
  }) {
    return _send(
      http.Request('POST', url)
        ..headers.addAll(Http.jsonHeaders(headers))
        ..body = jsonEncode(body),
      timeout,
    );
  }

  Future<http.Response> postMultipart(
    Uri url, {
    Map<String, String> fields = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final request = http.MultipartRequest('POST', url)
      ..headers.addAll({'User-Agent': Http.userAgent, ...headers})
      ..files.addAll(files);

    fields.forEach((key, value) {
      if (value.isNotEmpty) request.fields[key] = value;
    });

    throwIfCancelled();
    final streamed = await _client.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed);
    throwIfCancelled();
    return response;
  }

  /// GET returning raw bytes, keeping the request's headers -- needed when the
  /// asset lives behind the provider's own auth.
  Future<http.Response> getBytes(
    Uri url, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(minutes: 5),
  }) {
    return _send(
      http.Request('GET', url)
        ..headers.addAll({'User-Agent': Http.userAgent, ...headers}),
      timeout,
    );
  }

  /// Downloads a generated asset from wherever the provider parked it.
  Future<(Uint8List, String)> download(String url) async {
    final response = await getBytes(Uri.parse(url));
    if (response.statusCode >= 400) {
      throw ProviderException(Http.describeError(response.statusCode, response.body));
    }
    return (response.bodyBytes, response.headers['content-type'] ?? '');
  }

  Future<http.Response> _send(http.BaseRequest request, Duration timeout) async {
    throwIfCancelled();
    try {
      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      throwIfCancelled();
      return response;
    } on TimeoutException {
      throwIfCancelled();
      throw ProviderException(tr('The provider did not return a result in time.'));
    } on http.ClientException catch (error) {
      // A cancelled task closes the client mid-flight; that is not a failure.
      throwIfCancelled();
      throw ProviderException(error.message);
    }
  }

  Map<String, dynamic> _decodeJson(http.Response response) {
    if (response.statusCode >= 400) {
      throw ProviderException(Http.describeError(response.statusCode, response.body));
    }
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map<String, dynamic>) {
      final head = response.body.length > 200
          ? response.body.substring(0, 200)
          : response.body;
      throw ProviderException(
          tr('Unexpected response from the API: %1').arg(head.replaceAll(RegExp(r'\s+'), ' ')));
    }
    return decoded;
  }

  // ---- Polling ----------------------------------------------------------

  /// Polls [url] until [check] reports done or failed, or the deadline passes.
  Future<Map<String, dynamic>> pollUntil(
    Uri url,
    Map<String, String> headers,
    PollVerdict Function(Map<String, dynamic>) check, {
    Duration interval = const Duration(seconds: 3),
    Duration timeout = const Duration(minutes: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (true) {
      throwIfCancelled();
      if (DateTime.now().isAfter(deadline)) {
        throw ProviderException(tr('The provider did not return a result in time.'));
      }

      final status = await getJson(url, headers: headers);
      final verdict = check(status);

      switch (verdict.state) {
        case PollState.done:
          return status;
        case PollState.failed:
          throw ProviderException(
              verdict.error.isEmpty ? tr('The generation failed.') : verdict.error);
        case PollState.pending:
          await Future<void>.delayed(interval);
      }
    }
  }

  // ---- Queue-based platforms --------------------------------------------
  //
  // fal.ai and Replicate both work the same way: submit a job, poll a status
  // url, then read the payload. Images and video share this code.

  /// Returns the completed fal payload, e.g. {"images":[{"url":...}]}.
  Future<Map<String, dynamic>> submitFal(
    String apiKey,
    String modelId,
    Map<String, Object?> input,
  ) async {
    final headers = {'Authorization': 'Key $apiKey'};

    report(tr('Queued on fal.ai (%1)...').arg(modelId));

    final queued = await postJson(
      Uri.parse('https://queue.fal.run/$modelId'),
      input,
      headers: headers,
    );

    final statusUrl = '${queued['status_url'] ?? ''}';
    final responseUrl = '${queued['response_url'] ?? ''}';
    if (statusUrl.isEmpty || responseUrl.isEmpty) {
      throw ProviderException(tr('fal.ai did not return a job handle.'));
    }

    await pollUntil(Uri.parse(statusUrl), headers, (status) {
      final state = '${status['status'] ?? ''}';
      if (state == 'COMPLETED') return PollVerdict.done;
      if (state == 'IN_QUEUE') {
        final position = (status['queue_position'] as num?)?.toInt() ?? -1;
        report(position >= 0
            ? tr('Waiting in queue (position %1)...').arg(position)
            : tr('Waiting in queue...'));
        return PollVerdict.pending;
      }
      if (state == 'IN_PROGRESS') {
        report(tr('Generating...'));
        return PollVerdict.pending;
      }
      return PollVerdict(
          PollState.failed, tr('fal.ai reported status "%1".').arg(state));
    });

    return getJson(Uri.parse(responseUrl), headers: headers);
  }

  /// Accepts "owner/name" or "owner/name:version"; returns the succeeded
  /// prediction object.
  Future<Map<String, dynamic>> submitReplicate(
    String apiToken,
    String model,
    Map<String, Object?> input,
  ) async {
    final headers = {'Authorization': 'Bearer $apiToken'};

    final Uri submitUrl;
    final body = <String, Object?>{'input': input};

    final colon = model.indexOf(':');
    if (colon > 0) {
      submitUrl = Uri.parse('https://api.replicate.com/v1/predictions');
      body['version'] = model.substring(colon + 1);
    } else {
      submitUrl =
          Uri.parse('https://api.replicate.com/v1/models/$model/predictions');
    }

    report(tr('Submitting to Replicate (%1)...').arg(model));

    final prediction = await postJson(submitUrl, body, headers: headers);
    final urls = prediction['urls'];
    final statusUrl = urls is Map ? '${urls['get'] ?? ''}' : '';
    if (statusUrl.isEmpty) {
      throw ProviderException(tr('Replicate did not return a prediction url.'));
    }

    return pollUntil(Uri.parse(statusUrl), headers, (status) {
      final state = '${status['status'] ?? ''}';
      if (state == 'succeeded') return PollVerdict.done;
      if (state == 'starting' || state == 'processing') {
        report(state == 'starting' ? tr('Starting up...') : tr('Generating...'));
        return PollVerdict.pending;
      }
      final error = '${status['error'] ?? ''}';
      return PollVerdict(
        PollState.failed,
        error.isEmpty ? tr('Replicate reported status "%1".').arg(state) : error,
      );
    });
  }

  /// First http(s) url in a Replicate `output` (string, array or object).
  static String replicateOutputUrl(Map<String, dynamic> prediction) {
    final output = prediction['output'];

    String asUrl(Object? value) {
      final text = value is String ? value : '';
      return text.startsWith('http') ? text : '';
    }

    if (output is String) return asUrl(output);

    if (output is List) {
      // Last entry first: models that stream partial results append the final
      // asset at the end.
      for (var i = output.length - 1; i >= 0; --i) {
        final url = asUrl(output[i]);
        if (url.isNotEmpty) return url;
      }
    }

    if (output is Map) {
      for (final key in ['video', 'url', 'image', 'output', 'audio']) {
        final url = asUrl(output[key]);
        if (url.isNotEmpty) return url;
      }
    }
    return '';
  }

  /// Reads a dotted path out of a decoded response: "choices.0.message.content".
  static String jsonPath(Map<String, dynamic> root, String dottedPath) {
    Object? value = root;
    for (final part in dottedPath.split('.')) {
      if (part.isEmpty) continue;
      final index = int.tryParse(part);
      if (index != null && value is List) {
        if (index < 0 || index >= value.length) return '';
        value = value[index];
      } else if (value is Map) {
        value = value[part];
      } else {
        return '';
      }
    }
    return value is String ? value : '';
  }
}
