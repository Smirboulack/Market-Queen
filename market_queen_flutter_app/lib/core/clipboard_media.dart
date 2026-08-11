import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/asset_library.dart' show isImagePath, isMediaPath;
import 'paths.dart';

/// What Ctrl+V can put in the composer.
///
/// Flutter's own clipboard reaches text and nothing else, which is the whole
/// problem: the two things anybody actually pastes into a prompt bar are a
/// screenshot and a file copied out of the file manager, and neither is text.
/// So the platform clipboard is read through the shell instead -- once, and
/// only when there was no text to paste, so an ordinary Ctrl+V never waits on a
/// subprocess.
class ClipboardMedia {
  ClipboardMedia._();

  /// Where a pasted screenshot is written.
  ///
  /// The app's own data directory rather than the system temp: the file has to
  /// outlive the paste by long enough to be uploaded with the request, and a
  /// temp sweeper does not know that.
  static String get _pasteDir {
    final directory = Paths.ensureDir(p.join(Paths.configDir, 'pasted'));
    if (directory.isNotEmpty) _prune(directory);
    return directory;
  }

  /// How long a pasted screenshot is kept.
  ///
  /// It only has to outlive the request it was pasted into, and nothing else
  /// ever looks in this folder -- so without a sweep it is a directory that
  /// only grows, out of sight, for as long as the app is installed.
  static const _keepFor = Duration(days: 7);

  static void _prune(String directory) {
    final cutoff = DateTime.now().subtract(_keepFor);
    try {
      for (final entry in Directory(directory).listSync()) {
        if (entry is! File) continue;
        if (entry.statSync().modified.isAfter(cutoff)) continue;
        entry.deleteSync();
      }
    } on FileSystemException {
      // A file somebody still has open is a file that stays. It will be swept
      // on some later paste.
    }
  }

  /// The media files named by a piece of clipboard *text*.
  ///
  /// Copying a path out of an address bar, a terminal or a chat message is a
  /// perfectly ordinary way to hand a file over, and it costs nothing to
  /// notice. Anything that is not an existing media file leaves the text to be
  /// pasted as text.
  static List<String> pathsIn(String text) {
    final found = <String>[];
    for (var line in text.split(RegExp(r'[\r\n]+'))) {
      line = line.trim();
      // Dropped from a browser, or quoted by a shell.
      if (line.length > 1 && line.startsWith('"') && line.endsWith('"')) {
        line = line.substring(1, line.length - 1);
      }
      if (line.startsWith('file://')) {
        final uri = Uri.tryParse(line);
        if (uri == null) continue;
        line = uri.toFilePath();
      }
      if (line.isEmpty || !isMediaPath(line)) continue;
      if (File(line).existsSync()) found.add(line);
    }
    return found;
  }

  /// The files on the system clipboard, and a screenshot written out as one.
  ///
  /// Empty on anything it cannot read, which is the honest answer everywhere
  /// but Windows: pasting a picture is a shell call, and a shell that is not
  /// installed is not a failure worth reporting to somebody who pressed Ctrl+V
  /// on an empty clipboard.
  static Future<List<String>> readFiles() async {
    final directory = _pasteDir;
    if (directory.isEmpty) return const [];

    try {
      final result = await switch (Platform.operatingSystem) {
        'windows' => _runWindows(directory),
        'macos' => _runMacOS(directory),
        'linux' => _runLinux(directory),
        _ => Future.value(''),
      };

      return [
        for (final line in result.split(RegExp(r'[\r\n]+')))
          if (line.trim().isNotEmpty &&
              isMediaPath(line.trim()) &&
              File(line.trim()).existsSync())
            line.trim(),
      ];
    } on ProcessException {
      return const [];
    }
  }

  /// Puts a generated file on the clipboard, both ways at once.
  ///
  /// As a file, so it can be dropped into a folder, an upload field or a chat
  /// window; and -- for a picture -- as a bitmap as well, so it can be pasted
  /// straight into something that takes an image rather than a path. A clip can
  /// only ever be the file: no application takes a pasted video frame buffer.
  ///
  /// Returns whether it landed, so the caller can say nothing rather than
  /// claiming a copy that did not happen.
  static Future<bool> copyFile(String path) async {
    if (path.isEmpty || !File(path).existsSync()) return false;

    try {
      return await switch (Platform.operatingSystem) {
        'windows' => _copyWindows(path),
        'macos' => _copyMacOS(path),
        'linux' => _copyLinux(path),
        _ => Future.value(false),
      };
    } on ProcessException {
      return false;
    }
  }

  static Future<bool> _copyWindows(String path) async {
    // Read through a stream rather than `Image.FromFile`, which holds the file
    // open for as long as the bitmap lives -- and the bitmap lives as long as
    // the clipboard does, which would leave the app unable to overwrite its own
    // output.
    const script =
        'Add-Type -AssemblyName System.Windows.Forms,System.Drawing; '
        r'$p=$env:MQ_COPY_PATH; '
        r'$o=New-Object Windows.Forms.DataObject; '
        r'$c=New-Object Collections.Specialized.StringCollection; '
        r'$c.Add($p) | Out-Null; '
        r'$o.SetFileDropList($c); '
        r"if($env:MQ_COPY_IMAGE -eq '1')"
        r'{ $b=[IO.File]::ReadAllBytes($p); '
        r'$m=New-Object IO.MemoryStream(,$b); '
        r'$o.SetImage([Drawing.Image]::FromStream($m)) } '
        r'[Windows.Forms.Clipboard]::SetDataObject($o,$true)';

    final result = await Process.run(
      'powershell.exe',
      const ['-NoProfile', '-NonInteractive', '-STA', '-Command', script],
      environment: {
        'MQ_COPY_PATH': path,
        'MQ_COPY_IMAGE': isImagePath(path) ? '1' : '0',
      },
    );
    return result.exitCode == 0;
  }

  static Future<bool> _copyMacOS(String path) async {
    final result = await Process.run('osascript', [
      '-e',
      isImagePath(path)
          ? 'set the clipboard to (read POSIX file "$path" as «class PNGf»)'
          : 'set the clipboard to POSIX file "$path"',
    ]);
    return result.exitCode == 0;
  }

  static Future<bool> _copyLinux(String path) async {
    final result = await Process.run('sh', [
      '-c',
      'printf "file://%s" "$path" | '
          'xclip -selection clipboard -t text/uri-list',
    ]);
    return result.exitCode == 0;
  }

  /// One PowerShell hop: the file drop list if there is one, otherwise the
  /// bitmap, saved as a PNG. Both come off `System.Windows.Forms.Clipboard`,
  /// which needs a single-threaded apartment -- hence `-STA`.
  ///
  /// The target folder goes through the environment rather than into the
  /// script, so a path with a quote or a space in it cannot break the command
  /// line. The script itself is written with single quotes only for the same
  /// reason: Dart quotes the whole `-Command` argument, and a double quote
  /// inside it would come out escaped in a way PowerShell does not read back.
  static Future<String> _runWindows(String directory) async {
    const script =
        'Add-Type -AssemblyName System.Windows.Forms,System.Drawing; '
        r'$d=[Windows.Forms.Clipboard]::GetDataObject(); '
        r'if($d -and $d.GetDataPresent([Windows.Forms.DataFormats]::FileDrop))'
        r'{ $d.GetData([Windows.Forms.DataFormats]::FileDrop) | %{ $_ } } '
        r'elseif([Windows.Forms.Clipboard]::ContainsImage())'
        r"{ $i=[Windows.Forms.Clipboard]::GetImage(); "
        r"$p=Join-Path $env:MQ_PASTE_DIR "
        r"('paste-'+[DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff')+'.png'); "
        r'$i.Save($p,[Drawing.Imaging.ImageFormat]::Png); $p }';

    final result = await Process.run(
      'powershell.exe',
      const ['-NoProfile', '-NonInteractive', '-STA', '-Command', script],
      environment: {'MQ_PASTE_DIR': directory},
    );
    return '${result.stdout}';
  }

  /// AppleScript can hand back the clipboard as PNG data, and can write it out
  /// itself, which saves decoding a hex dump on this side.
  static Future<String> _runMacOS(String directory) async {
    final target = p.join(directory, 'paste-${_stamp()}.png');
    final result = await Process.run('osascript', [
      '-e',
      'set target to POSIX file "$target"',
      '-e',
      'set handle to open for access target with write permission',
      '-e',
      'try',
      '-e',
      'write (the clipboard as «class PNGf») to handle',
      '-e',
      'end try',
      '-e',
      'close access handle',
    ]);
    if (result.exitCode != 0) return '';
    final file = File(target);
    // An empty file is what a clipboard with no picture on it leaves behind.
    if (!file.existsSync() || file.lengthSync() == 0) {
      if (file.existsSync()) file.deleteSync();
      return '';
    }
    return target;
  }

  /// xclip if it is there, and nothing if it is not.
  static Future<String> _runLinux(String directory) async {
    final target = p.join(directory, 'paste-${_stamp()}.png');
    final result = await Process.run('sh', [
      '-c',
      'xclip -selection clipboard -t image/png -o > "$target"',
    ]);
    final file = File(target);
    if (result.exitCode != 0 || !file.existsSync() || file.lengthSync() == 0) {
      if (file.existsSync()) file.deleteSync();
      return '';
    }
    return target;
  }

  static String _stamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}'
        '-${now.millisecond.toString().padLeft(3, '0')}';
  }
}
