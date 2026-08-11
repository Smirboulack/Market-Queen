import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'http_util.dart';

/// The few OS-level things the UI asks for: open a link, open a file, show it
/// in the file manager.
class PlatformUtil {
  PlatformUtil._();

  static Future<void> openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> openPath(String path) async {
    final local = Http.toLocalPath(path);
    if (local.isEmpty) return;
    if (!File(local).existsSync() && !Directory(local).existsSync()) return;
    await launchUrl(Uri.file(local));
  }

  /// Opens the containing folder with the file selected where the platform
  /// supports it.
  static Future<void> revealPath(String path) async {
    final local = Http.toLocalPath(path);
    if (local.isEmpty) return;

    final isDir = Directory(local).existsSync();
    final exists = isDir || File(local).existsSync();
    if (!exists) {
      final parent = p.dirname(local);
      if (Directory(parent).existsSync()) await launchUrl(Uri.file(parent));
      return;
    }

    try {
      if (Platform.isWindows) {
        // Two arguments rather than one, and the difference is not cosmetic.
        // Explorer takes everything after `/select,` as the path, but Dart
        // wraps any single argument containing a space in quotes -- and the
        // projects folder is `...\Videos\Market Queen\...` by default, so it
        // always has one. Explorer does not parse a quoted `/select,`: it gave
        // up silently and opened Documents instead, every single time. Split in
        // two, only the path carries the space, and the quotes land where
        // Explorer expects them.
        await Process.start('explorer.exe', ['/select,', p.normalize(local)]);
        return;
      }
      if (Platform.isMacOS) {
        await Process.start('open', ['-R', local]);
        return;
      }
    } on ProcessException {
      // Fall through to the plain open below.
    }

    await launchUrl(Uri.file(isDir ? local : p.dirname(local)));
  }
}
