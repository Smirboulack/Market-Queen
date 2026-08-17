import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'paths.dart';
import 'secret_box.dart';
import 'signal.dart';

/// Persists user preferences (plain JSON) and API keys (encrypted blob) under
/// the platform config directory.
class SettingsStore extends ChangeNotifier {
  SettingsStore() {
    _load();
  }

  /// Raised separately from [notifyListeners] so a key field can refresh
  /// without every themed widget rebuilding.
  final Signal apiKeysChanged = Signal();

  Map<String, dynamic> _prefs = {};
  final Map<String, String> _secrets = {};
  bool _loading = false;

  /// Set when secrets.bin was on disk and could not be opened.
  ///
  /// It matters because of what the next write would otherwise do. An
  /// unreadable file leaves [_secrets] empty, which is the same state as a fresh
  /// install -- so the next key typed used to seal a one-entry map straight over
  /// the top of fourteen keys nobody could read but which were still there. The
  /// flag turns that into a rename: the file is kept, under a name that says
  /// what happened, and only then replaced.
  bool _secretsUnreadable = false;

  /// True when the store found keys it could not open. The UI does not surface
  /// it today; it exists so a support question has an answer.
  bool get secretsUnreadable => _secretsUnreadable;

  String get _settingsFile => p.join(Paths.configDir, 'settings.json');
  String get _secretsFile => p.join(Paths.configDir, 'secrets.bin');

  String get configLocation => Paths.configDir;

  void _load() {
    _loading = true;

    final settings = File(_settingsFile);
    if (settings.existsSync()) {
      try {
        final decoded = jsonDecode(settings.readAsStringSync());
        if (decoded is Map<String, dynamic>) _prefs = decoded;
      } on FormatException {
        // A corrupt file starts from defaults rather than blocking startup.
      }
    }

    _loadSecrets();

    _prefs.putIfAbsent('projectsDir', () => Paths.defaultProjectsDir);
    _loading = false;
  }

  void _loadSecrets() {
    final secrets = File(_secretsFile);
    if (!secrets.existsSync()) return;

    try {
      final blob = secrets.readAsBytesSync();
      final keys = SecretBox.candidateKeys();

      for (var i = 0; i < keys.length; ++i) {
        final plain = SecretBox.unseal(blob, keys[i]);
        if (plain == null) continue;

        final decoded = jsonDecode(utf8.decode(plain));
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((key, value) => _secrets[key] = '$value');
        }
        // Opened under a fallback key: written from a shell that set `USER`
        // and opened from one that did not, or the other way round. Sealing it
        // again under the primary key is what stops the next launch depending
        // on how this one was started.
        if (i > 0) _saveSecrets();
        return;
      }

      // Every key was refused. The file is real and holds something; it just
      // was not written by this machine, or not by this account, or it is
      // damaged. Either way it is not ours to overwrite silently.
      _secretsUnreadable = true;
    } on Exception {
      // Unreadable for a reason that is not the cipher -- a truncated file, a
      // permission problem. Treated the same way: kept, not clobbered.
      _secretsUnreadable = true;
    }
  }

  void save() {
    if (_loading) return;
    if (Paths.ensureDir(Paths.configDir).isEmpty) return;

    try {
      File(_settingsFile)
          .writeAsStringSync(const JsonEncoder.withIndent('    ').convert(_prefs));
    } on FileSystemException {
      // Nothing useful to do: the next edit tries again.
    }
  }

  void _saveSecrets() {
    if (Paths.ensureDir(Paths.configDir).isEmpty) return;

    final obj = <String, String>{
      for (final entry in _secrets.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    };

    final blob = SecretBox.seal(
      Uint8List.fromList(utf8.encode(jsonEncode(obj))),
      SecretBox.deviceKey(),
    );

    try {
      if (_secretsUnreadable) _setUnreadableAside();
      File(_secretsFile).writeAsBytesSync(blob);
    } on FileSystemException {
      // Same.
    }
  }

  /// Renames a secrets file we could not open, so writing over it is not a
  /// deletion. Done once: after the rename there is nothing left to protect.
  void _setUnreadableAside() {
    _secretsUnreadable = false;
    try {
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      File(_secretsFile).renameSync('$_secretsFile.unreadable-$stamp');
    } on FileSystemException {
      // Nothing to move aside, or nowhere to move it to. The write below is
      // what the user asked for either way.
    }
  }

  // ---- Preferences ------------------------------------------------------

  String get projectsDir {
    final dir = '${_prefs['projectsDir'] ?? ''}';
    return dir.isEmpty ? Paths.defaultProjectsDir : dir;
  }

  set projectsDir(String dir) {
    if (dir == projectsDir) return;
    _prefs['projectsDir'] = dir.isEmpty ? Paths.defaultProjectsDir : dir;
    save();
    notifyListeners();
  }

  String get ffmpegPath => '${_prefs['ffmpegPath'] ?? ''}';

  set ffmpegPath(String path) {
    if (path == ffmpegPath) return;
    _prefs['ffmpegPath'] = path;
    save();
    notifyListeners();
  }

  /// Light is the default; the choice is remembered.
  bool get darkMode => _prefs['darkMode'] == true;

  set darkMode(bool dark) {
    if (dark == darkMode) return;
    _prefs['darkMode'] = dark;
    save();
    notifyListeners();
  }

  /// Empty means "follow the system locale".
  String get uiLanguage => '${_prefs['uiLanguage'] ?? ''}';

  set uiLanguage(String code) {
    if (code == uiLanguage) return;
    _prefs['uiLanguage'] = code;
    save();
    notifyListeners();
  }

  /// Free-form preferences (last used models, toggles, ...).
  T? pref<T>(String key, [T? fallback]) {
    final value = _prefs[key];
    return value is T ? value : fallback;
  }

  String prefString(String key, [String fallback = '']) {
    final value = _prefs[key];
    return value == null ? fallback : '$value';
  }

  /// Writes a free-form preference and tells the interface.
  ///
  /// The notification is not optional bookkeeping: the composer's model, format
  /// and length menus all write through here, and without it a picked model
  /// stayed on the old name until the panel was closed and opened again -- the
  /// value had changed, nothing had been asked to redraw.
  void setPref(String key, Object? value) {
    if (_prefs[key] == value) return;
    _prefs[key] = value;
    save();
    notifyListeners();
  }

  // ---- The model shortlist ----------------------------------------------
  //
  // The Models page no longer picks a default for each kind of generation --
  // that choice moved into the composer, next to the prompt it applies to. What
  // the page does now is decide which models are *offered* there, because a
  // provider's full catalogue is thirty entries deep and two thirds of it is
  // last year's.
  //
  // Stored as the hidden set rather than the visible one, so a model added in a
  // future release shows up for everybody instead of being invisible to every
  // existing install.



  // The shortlist of models a user could switch on and off lived here. It is
  // gone: which models the app offers is a decision the app makes now, per
  // provider, so that nobody has to audit a hundred names to find the four
  // that are worth using. What is still theirs is which of the offered models
  // any one generation runs on -- that is the picker in the studio.
  //
  // Anything a previous version wrote under `hiddenModels` is simply ignored;
  // it costs a few bytes in settings.json and nothing else.

  // ---- Secrets ----------------------------------------------------------
  //
  // Reading falls back to the provider's conventional environment variable, so
  // CI and power users can avoid the on-disk store entirely.

  static const _environmentVariables = <String, String>{
    'openai': 'OPENAI_API_KEY',
    'anthropic': 'ANTHROPIC_API_KEY',
    'gemini': 'GEMINI_API_KEY',
    'xai': 'XAI_API_KEY',
    'minimax': 'MINIMAX_API_KEY',
    'ltx': 'LTXV_API_KEY',
    'bytedance': 'ARK_API_KEY',
    'bfl': 'BFL_API_KEY',
    'heygen': 'HEYGEN_API_KEY',
    'luma': 'LUMAAI_API_KEY',
    'ideogram': 'IDEOGRAM_API_KEY',
    'bria': 'BRIA_API_TOKEN',
    'groq': 'GROQ_API_KEY',
    'elevenlabs': 'ELEVENLABS_API_KEY',
    'fal': 'FAL_KEY',
  };

  String apiKey(String credentialId) {
    final stored = _secrets[credentialId];
    if (stored != null && stored.isNotEmpty) return stored;

    final envName = _environmentVariables[credentialId];
    if (envName != null) {
      final value = Platform.environment[envName];
      if (value != null && value.isNotEmpty) return value.trim();
    }
    return '';
  }

  bool hasApiKey(String credentialId) => apiKey(credentialId).isNotEmpty;

  bool apiKeyFromEnvironment(String credentialId) {
    if ((_secrets[credentialId] ?? '').isNotEmpty) return false;
    final envName = _environmentVariables[credentialId];
    if (envName == null) return false;
    return (Platform.environment[envName] ?? '').isNotEmpty;
  }

  void setApiKey(String credentialId, String value) {
    final trimmed = value.trim();
    if ((_secrets[credentialId] ?? '') == trimmed) return;

    if (trimmed.isEmpty) {
      _secrets.remove(credentialId);
    } else {
      _secrets[credentialId] = trimmed;
    }

    _saveSecrets();
    apiKeysChanged.emit();
    notifyListeners();
  }
}
