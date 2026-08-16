import '../core/http_util.dart';
import '../i18n/translator.dart';
import 'provider_task.dart';

/// How a key came back from its provider.
enum KeyVerdict {
  /// The provider answered, and answered as somebody who recognises the key.
  valid,

  /// The provider answered and said no: wrong key, revoked, wrong account.
  invalid,

  /// The provider could not be reached at all, or answered something that says
  /// nothing about the key -- a 500, a timeout, no network. Deliberately not
  /// [invalid]: telling somebody their key is bad because their wifi dropped
  /// is the one mistake this feature must not make.
  unreachable,

  /// This provider publishes nothing a key can be checked against for free.
  /// The key is saved and may well be perfect; we simply do not know.
  unchecked,
}

class KeyCheckResult {
  const KeyCheckResult(this.verdict, [this.message = '']);

  final KeyVerdict verdict;

  /// The provider's own words, when it gave any. Shown as-is: "insufficient
  /// quota" and "invalid api key" are different problems and the user is the
  /// one who has to tell them apart.
  final String message;

  bool get ok => verdict == KeyVerdict.valid;
}

/// One free, read-only endpoint per account, used to answer "does this key
/// work" the moment it is pasted.
///
/// Every probe below is a GET that lists something -- the models on the
/// account, the account itself. They are chosen on two rules and nothing else:
///
///  * **It must cost nothing.** A probe that generated a picture to prove a key
///    works would bill somebody a cent for pasting a key, and several cents for
///    pasting it wrong twice.
///  * **It must be documented.** An invented URL that 404s reads exactly like a
///    rejected key, which would tell people their working key is broken. An
///    account with nothing suitable published is reported as [unchecked]
///    rather than guessed at -- see the list at the bottom of this table.
class KeyProbe {
  const KeyProbe(this.url, this.headers);

  final String url;

  /// Built from the key, because the six accounts that can be checked spell
  /// authentication five different ways.
  final Map<String, String> Function(String key) headers;

  /// Bearer tokens, which is most of them.
  static Map<String, String> _bearer(String key) => {
    'Authorization': 'Bearer $key',
  };

  static const Map<String, KeyProbe> byCredential = {
    'openai': KeyProbe('https://api.openai.com/v1/models', _bearer),
    'xai': KeyProbe('https://api.x.ai/v1/models', _bearer),
    'groq': KeyProbe('https://api.groq.com/openai/v1/models', _bearer),
    // ModelArk is OpenAI-compatible on this path: 200 with a key it knows,
    // 401 with one it does not.
    'bytedance': KeyProbe(
      'https://ark.ap-southeast.bytepluses.com/api/v3/models',
      _bearer,
    ),
    'gemini': KeyProbe(
      'https://generativelanguage.googleapis.com/v1beta/models',
      _googleKey,
    ),
    'anthropic': KeyProbe(
      'https://api.anthropic.com/v1/models',
      _anthropicKey,
    ),
    'elevenlabs': KeyProbe(
      'https://api.elevenlabs.io/v1/user',
      _elevenLabsKey,
    ),
    // Not here, and not by oversight: fal, LTX, MiniMax, Black Forest Labs,
    // HeyGen, Luma, Ideogram and Bria. None of them publishes a read-only
    // endpoint this app can call for nothing, and the alternative -- firing a
    // real generation to see whether it is refused -- would charge the user
    // for typing. Their keys are saved unchecked and said to be.
  };

  static Map<String, String> _googleKey(String key) => {'x-goog-api-key': key};

  static Map<String, String> _anthropicKey(String key) => {
    'x-api-key': key,
    'anthropic-version': '2023-06-01',
  };

  static Map<String, String> _elevenLabsKey(String key) => {'xi-api-key': key};

  static bool supports(String credentialId) =>
      byCredential.containsKey(credentialId);
}

/// Asks the provider whether it recognises a key.
///
/// A task like any other, so it cancels with the page and shares the app's
/// timeouts -- but a short one: this runs while somebody watches a spinner in a
/// text field, and a key that is going to be refused is refused immediately.
class KeyCheckTask extends HttpTask {
  KeyCheckTask({required this.credentialId, required this.apiKey});

  final String credentialId;
  final String apiKey;

  static const _timeout = Duration(seconds: 20);

  @override
  Future<Map<String, Object?>> execute() async {
    final result = await check();
    return {'verdict': result.verdict.name, 'message': result.message};
  }

  /// The verdict, in the shape the interface wants it.
  Future<KeyCheckResult> check() async {
    if (apiKey.trim().isEmpty) {
      return const KeyCheckResult(KeyVerdict.unchecked);
    }

    final probe = KeyProbe.byCredential[credentialId];
    if (probe == null) return const KeyCheckResult(KeyVerdict.unchecked);

    try {
      // `getBytes` rather than `getJson`, because the status code *is* the
      // answer here: getJson throws on anything past 400 and would turn a
      // plain "no" into an exception with the body already discarded.
      final response = await getBytes(
        Uri.parse(probe.url),
        headers: probe.headers(apiKey.trim()),
        timeout: _timeout,
      );

      final code = response.statusCode;
      final message = Http.extractApiError(response.body);

      if (code >= 200 && code < 300) {
        return const KeyCheckResult(KeyVerdict.valid);
      }

      // 401 and 403 are how most of them say "not you".
      if (code == 401 || code == 403) {
        return KeyCheckResult(KeyVerdict.invalid, message);
      }

      // 402 and 429 mean the key is real and the account is out of money or
      // out of patience. That is a true answer to "is this key valid" and a
      // useless one to act on, so it comes back valid with the provider's own
      // words attached.
      if (code == 402 || code == 429) {
        return KeyCheckResult(KeyVerdict.valid, message);
      }

      // And then the two that answer a bad key with 400: xAI says "Incorrect
      // API key provided", Gemini says "API key not valid". A 400 can also be
      // a genuinely malformed request, so the body decides rather than the
      // status -- checked against the message, because reporting "we could not
      // reach the provider" to somebody whose key was just refused by name is
      // the unhelpful half of both answers.
      if (code == 400 && _readsAsRejection(message)) {
        return KeyCheckResult(KeyVerdict.invalid, message);
      }

      // Anything else is the provider having a bad day, not the key being
      // wrong.
      return KeyCheckResult(
        KeyVerdict.unreachable,
        Http.describeError(code, response.body),
      );
    } on ProviderException catch (error) {
      if (error is TaskCancelled) rethrow;
      return KeyCheckResult(KeyVerdict.unreachable, error.message);
    }
  }

  /// Whether a 400 is the provider saying the key is wrong.
  ///
  /// Matched on the provider's own wording, which is the only thing that
  /// distinguishes it from a malformed request. Both live phrasings are
  /// covered -- "Incorrect API key provided" and "API key not valid" -- and
  /// anything unrecognised falls through to [KeyVerdict.unreachable], which is
  /// the safe direction: an unproven key is a smaller lie than a working one
  /// called broken.
  static bool _readsAsRejection(String message) {
    final text = message.toLowerCase();
    if (!text.contains('key')) return false;
    return text.contains('invalid') ||
        text.contains('not valid') ||
        text.contains('incorrect') ||
        text.contains('unauthorized') ||
        text.contains('unauthorised');
  }
}

/// What each verdict says, in one line, under the field.
String keyVerdictLabel(KeyCheckResult result) => switch (result.verdict) {
  KeyVerdict.valid => result.message.isEmpty
      ? tr('Key works.')
      //: %1 is the provider's own message, e.g. "insufficient quota"
      : tr('Key works, but the account says: %1').arg(result.message),
  KeyVerdict.invalid => result.message.isEmpty
      ? tr('This provider does not recognise that key.')
      //: %1 is the provider's own message
      : tr('Key refused: %1').arg(result.message),
  KeyVerdict.unreachable => tr('Could not reach the provider to check it. The '
      'key is saved.'),
  KeyVerdict.unchecked => tr('Saved. This provider offers no way to check a '
      'key without spending anything.'),
};
