import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the app keeps its own files.
///
/// The directories are computed rather than asked of a plugin, so they land on
/// exactly the paths the Qt build used: an existing install keeps its settings,
/// its encrypted keys and its saved actors without a migration step.
class Paths {
  Paths._();

  static const organization = 'MarketQueen';
  static const application = 'Market Queen';

  /// Somewhere else to keep everything, for a run that must not touch the real
  /// install.
  ///
  /// This is the seam the test suite needs and did not have. Every store in the
  /// app -- settings.json, secrets.bin, actors.json, workspace.json -- is
  /// computed from [configDir], so a test that builds an `AppState` was
  /// building one on top of whoever ran it: `flutter test` wrote its fixtures
  /// into the real profile and its teardown deleted them again. The keys the
  /// suite happened to name were `gemini` and `anthropic`, which is why those
  /// two were the ones that kept vanishing between launches.
  ///
  /// Set it before anything reads a path -- `AppState.create()` is the first
  /// thing that does -- and put it back to null afterwards. `MQ_CONFIG_DIR`
  /// does the same job from outside the process, for a CI runner that would
  /// rather not trust every test file to remember.
  static String? overrideDir;

  /// %APPDATA%/MarketQueen/Market Queen, ~/.local/share/..., ~/Library/...
  ///
  /// Mirrors QStandardPaths::AppDataLocation, which appends the organisation
  /// and the application name to the platform's roaming data directory.
  static String get configDir {
    final env = Platform.environment;

    final redirect = overrideDir ?? env['MQ_CONFIG_DIR'];
    if (redirect != null && redirect.isNotEmpty) return redirect;

    if (Platform.isWindows) {
      final appData = env['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, organization, application);
      }
      return p.join(_home, 'AppData', 'Roaming', organization, application);
    }

    if (Platform.isMacOS) {
      return p.join(_home, 'Library', 'Application Support', organization, application);
    }

    final dataHome = env['XDG_DATA_HOME'];
    final base = (dataHome != null && dataHome.isNotEmpty)
        ? dataHome
        : p.join(_home, '.local', 'share');
    return p.join(base, organization, application);
  }

  /// Where generated projects live. User-overridable from the settings page.
  static String get defaultProjectsDir => p.join(_videosDir, 'Market Queen');

  /// Creates the directory if needed, returns the absolute path (empty on
  /// failure).
  static String ensureDir(String path) {
    if (path.isEmpty) return '';
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir.absolute.path;
    } on FileSystemException {
      return '';
    }
  }

  /// A filesystem-safe slug for project folder names.
  static String slugify(String text, {int maxLength = 40}) {
    final out = StringBuffer();
    var lastDash = false;
    var length = 0;

    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      if (_isLetterOrNumber(rune)) {
        out.write(char.toLowerCase());
        length += 1;
        lastDash = false;
      } else if (!lastDash && length > 0) {
        out.write('-');
        length += 1;
        lastDash = true;
      }
    }

    var slug = out.toString();
    while (slug.endsWith('-')) {
      slug = slug.substring(0, slug.length - 1);
    }
    if (slug.length > maxLength) {
      slug = slug.substring(0, maxLength);
      while (slug.endsWith('-')) {
        slug = slug.substring(0, slug.length - 1);
      }
    }
    return slug.isEmpty ? 'untitled' : slug;
  }

  // QChar::isLetterOrNumber, near enough: letters and digits in any script.
  static bool _isLetterOrNumber(int rune) {
    if (rune >= 0x30 && rune <= 0x39) return true; // 0-9
    if (rune >= 0x41 && rune <= 0x5A) return true; // A-Z
    if (rune >= 0x61 && rune <= 0x7A) return true; // a-z
    if (rune < 0x80) return false;
    // Anything beyond ASCII that is not punctuation or a separator.
    final char = String.fromCharCode(rune);
    return RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(char);
  }

  static String get _home {
    final env = Platform.environment;
    return env['USERPROFILE'] ?? env['HOME'] ?? Directory.current.path;
  }

  static String get _videosDir {
    if (Platform.isWindows) {
      final profile = Platform.environment['USERPROFILE'];
      if (profile != null && profile.isNotEmpty) return p.join(profile, 'Videos');
    }
    if (Platform.isMacOS) return p.join(_home, 'Movies');

    final videos = Directory(p.join(_home, 'Videos'));
    if (videos.existsSync()) return videos.path;
    return p.join(_home, 'Documents');
  }
}
