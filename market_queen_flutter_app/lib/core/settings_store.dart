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

    final secrets = File(_secretsFile);
    if (secrets.existsSync()) {
      try {
        final plain = SecretBox.unseal(secrets.readAsBytesSync(), SecretBox.deviceKey());
        // A failed unseal means the file came from another machine or was
        // tampered with; we start from an empty set rather than crash.
        if (plain != null) {
          final decoded = jsonDecode(utf8.decode(plain));
          if (decoded is Map<String, dynamic>) {
            decoded.forEach((key, value) => _secrets[key] = '$value');
          }
        }
      } on Exception {
        // Same.
      }
    }

    _prefs.putIfAbsent('projectsDir', () => Paths.defaultProjectsDir);
    _loading = false;
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
      File(_secretsFile).writeAsBytesSync(blob);
    } on FileSystemException {
      // Same.
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

  void setPref(String key, Object? value) {
    if (_prefs[key] == value) return;
    _prefs[key] = value;
    save();
  }

  // ---- Secrets ----------------------------------------------------------
  //
  // Reading falls back to the provider's conventional environment variable, so
  // CI and power users can avoid the on-disk store entirely.

  static const _environmentVariables = <String, String>{
    'openai': 'OPENAI_API_KEY',
    'anthropic': 'ANTHROPIC_API_KEY',
    'gemini': 'GEMINI_API_KEY',
    'fal': 'FAL_KEY',
    'replicate': 'REPLICATE_API_TOKEN',
    'elevenlabs': 'ELEVENLABS_API_KEY',
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
