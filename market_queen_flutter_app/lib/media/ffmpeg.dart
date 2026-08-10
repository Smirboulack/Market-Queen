import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../core/http_util.dart';
import '../core/paths.dart';
import '../i18n/translator.dart';
import '../providers/provider_task.dart';

class Ffmpeg {
  Ffmpeg._();

  /// Looks for ffmpeg: the configured path first, then PATH, then the usual
  /// install locations. Returns an empty string when it is nowhere to be found.
  static String resolve(String configuredPath) {
    if (configuredPath.isNotEmpty && _isExecutable(configuredPath)) {
      return configuredPath;
    }

    final onPath = _findOnPath('ffmpeg');
    if (onPath.isNotEmpty) return onPath;

    const windowsCandidates = [
      r'C:/ffmpeg/bin/ffmpeg.exe',
      r'C:/Program Files/ffmpeg/bin/ffmpeg.exe',
    ];
    const unixCandidates = [
      '/usr/bin/ffmpeg',
      '/usr/local/bin/ffmpeg',
      '/opt/homebrew/bin/ffmpeg',
      '/snap/bin/ffmpeg',
    ];

    for (final candidate in Platform.isWindows ? windowsCandidates : unixCandidates) {
      if (_isExecutable(candidate)) return candidate;
    }
    return '';
  }

  static bool _isExecutable(String path) {
    if (path.isEmpty) return false;
    final file = File(path);
    if (!file.existsSync()) return false;
    if (Platform.isWindows) return true;
    // Cheap stand-in for QFileInfo::isExecutable on POSIX.
    return file.statSync().mode & 0x49 != 0;
  }

  static String _findOnPath(String name) {
    final pathVar = Platform.environment['PATH'] ?? '';
    if (pathVar.isEmpty) return '';

    final separator = Platform.isWindows ? ';' : ':';
    final names = Platform.isWindows ? ['$name.exe', '$name.bat', name] : [name];

    for (final dir in pathVar.split(separator)) {
      if (dir.isEmpty) continue;
      for (final candidate in names) {
        final full = p.join(dir, candidate);
        if (_isExecutable(full)) return full;
      }
    }
    return '';
  }

  /// Seconds parsed out of an ffmpeg "Duration: 00:00:12.34" banner, or -1.
  static double parseDuration(String log) {
    final match =
        RegExp(r'Duration:\s*(\d+):(\d{2}):(\d{2})\.(\d+)').firstMatch(log);
    if (match == null) return -1.0;

    final fraction = match.group(4)!;
    return int.parse(match.group(1)!) * 3600.0 +
        int.parse(match.group(2)!) * 60.0 +
        int.parse(match.group(3)!) +
        int.parse(fraction) / math.pow(10.0, fraction.length);
  }

  /// Escapes a filename for use inside a filtergraph argument.
  ///
  /// Inside a filtergraph, ':' separates options and '\' escapes; both appear
  /// in Windows paths. Callers should pass a bare file name and set the process
  /// working directory, but keep this safe either way.
  static String escapeFilterPath(String fileName) => fileName
      .replaceAll(r'\', '/')
      .replaceAll(':', r'\\:')
      .replaceAll("'", r"\\'");
}

/// Runs one ffmpeg command.
class FfmpegTask extends ProviderTask {
  FfmpegTask(this.executable, this.arguments, {this.workingDirectory = ''});

  final String executable;
  final List<String> arguments;
  final String workingDirectory;

  /// `ffmpeg -i <file>` exits non-zero when there is no output file; probing
  /// uses that on purpose.
  bool ignoreExitCode = false;

  Process? _process;
  String log = '';

  @override
  Future<Map<String, Object?>> execute() async {
    if (executable.isEmpty) {
      throw ProviderException(
          tr('FFmpeg was not found. Install it, or set its path in Settings.'));
    }

    final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory.isEmpty ? null : workingDirectory,
      );
    } on ProcessException {
      throw ProviderException(tr('Could not run FFmpeg (%1).').arg(executable));
    }
    _process = process;

    // Merged channels, as the Qt build had them: ffmpeg writes its banner and
    // its errors to stderr and nothing useful to stdout.
    final buffer = StringBuffer();
    void collect(String chunk) {
      buffer.write(chunk);
      // Keep the tail only: a long encode prints thousands of progress lines.
      if (buffer.length > 64000) {
        final text = buffer.toString();
        buffer
          ..clear()
          ..write(text.substring(text.length - 32000));
      }
    }

    final drained = Future.wait([
      process.stdout.transform(const SystemEncoding().decoder).forEach(collect),
      process.stderr.transform(const SystemEncoding().decoder).forEach(collect),
    ]);

    final exitCode = await process.exitCode;
    await drained;
    log = buffer.toString();
    _process = null;

    throwIfCancelled();

    if (exitCode != 0 && !ignoreExitCode) {
      // The last lines carry the actual reason.
      final lines = log.split('\n').where((line) => line.trim().isNotEmpty).toList();
      final tail = lines
          .sublist(math.max(0, lines.length - 4))
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      throw ProviderException(
          tr('FFmpeg failed (exit %1). %2').arg(exitCode).arg(tail));
    }

    return buildResult(exitCode);
  }

  /// What the task reports once the process exits. Subclasses extend it.
  Map<String, Object?> buildResult(int exitCode) => {
        'stderr': log,
        'exitCode': exitCode,
      };

  @override
  void dispose() {
    _process?.kill();
    _process = null;
    super.dispose();
  }
}

/// Reads the duration of a media file. Result adds { duration: double }.
class FfmpegProbeTask extends FfmpegTask {
  FfmpegProbeTask(String executable, String mediaPath)
      : super(executable, ['-hide_banner', '-i', mediaPath]) {
    ignoreExitCode = true;
  }

  @override
  Map<String, Object?> buildResult(int exitCode) => {
        ...super.buildResult(exitCode),
        'duration': Ffmpeg.parseDuration(log),
      };
}

/// A picture as a data: URI a model will accept, whatever it arrived as.
///
/// The Dart codecs read PNG, JPEG, WebP and GIF. Shops and phones increasingly
/// hand out neither: a product photo saved off a store page is as likely to be
/// AVIF as anything, and an iPhone screenshot is HEIC. Both used to reach the
/// model as bytes labelled "image/png" and come back as a 400 that blamed the
/// upload without naming the format.
///
/// So when the codecs cannot read it, ffmpeg -- which the render already needs
/// installed -- is asked to turn it into a PNG first. Empty when there is no
/// ffmpeg to ask, or when it cannot read the file either.
Future<String> imageDataUri(String executable, String path) async {
  final direct = Http.imageToDataUri(path);
  if (direct.isNotEmpty || executable.isEmpty || path.isEmpty) return direct;

  final converted = await transcodeImage(executable, path);
  return converted.isEmpty ? '' : Http.imageBytesToDataUri(converted);
}

/// Why [imageDataUri] came back empty, said in the one term that lets the user
/// do something about it: the format the file is actually in.
///
/// "Could not read the product photo" is what this used to be, and it sent
/// everybody looking at permissions and paths. The file was an AVIF.
String unreadableImage(String path) {
  final name = p.basename(path);
  final format = p.extension(path).replaceFirst('.', '').toUpperCase();

  if (format.isEmpty) {
    //: %1 is a file name
    return tr('Could not read %1.').arg(name);
  }
  //: %1 is a file name, %2 a format such as AVIF or HEIC
  return tr('Could not read %1: %2 is a format no model accepts, and FFmpeg '
          'could not convert it either. Save it as PNG or JPEG.')
      .arg(name)
      .arg(format);
}

/// One frame of [path], re-encoded as PNG. Empty when ffmpeg cannot read it.
Future<Uint8List> transcodeImage(String executable, String path) async {
  final directory = Paths.ensureDir(p.join(Paths.configDir, 'converted'));
  if (directory.isEmpty) return Uint8List(0);

  // Named for the source, so converting the same photo twice in one run does
  // not race with itself.
  final target = p.join(
    directory,
    '${path.hashCode.toUnsigned(32).toRadixString(16)}.png',
  );

  try {
    await FfmpegTask(executable, [
      '-hide_banner',
      '-y',
      '-i',
      path,
      // One frame, written over one file. Without both, an animated source
      // wants a "%03d" pattern in the name and refuses the plain one.
      '-frames:v',
      '1',
      '-update',
      '1',
      target,
    ]).run();
  } on ProviderException {
    return Uint8List(0);
  }

  final file = File(target);
  if (!file.existsSync()) return Uint8List(0);
  try {
    return file.readAsBytesSync();
  } on FileSystemException {
    return Uint8List(0);
  }
}

/// Pulls one frame out of a clip so the canvas has something to draw.
///
/// A tile that is a grey rectangle with a play glyph tells you a video exists;
/// a tile showing the video tells you which video it is, which is the only
/// question a feed of ten of them raises. The frame is taken a second in --
/// clips routinely open on black -- and written beside the clip as a .jpg, so
/// the extraction happens once per file and never again.
///
/// Returns the poster's path, or empty when there is no ffmpeg, no clip, or
/// ffmpeg could not read it. Never throws: a missing poster costs a thumbnail,
/// not a result.
Future<String> posterFrame(String executable, String videoPath) async {
  if (executable.isEmpty || videoPath.isEmpty) return '';

  final source = File(videoPath);
  if (!source.existsSync()) return '';

  final poster = '$videoPath.poster.jpg';
  final cached = File(poster);
  if (cached.existsSync() && cached.lengthSync() > 0) return poster;

  try {
    await FfmpegTask(executable, [
      '-hide_banner',
      '-y',
      // Seeking before -i is the fast path, and past the end of a very short
      // clip it simply lands on the last frame rather than failing.
      '-ss', '1',
      '-i', videoPath,
      '-frames:v', '1',
      '-q:v', '4',
      poster,
    ]).run();
  } on ProviderException {
    return '';
  }

  return cached.existsSync() ? poster : '';
}

/// Measures a media file, returning -1 when it cannot be read. Never throws:
/// the callers all have a fallback and none of them should lose a run over a
/// probe.
Future<double> probeDuration(String executable, String mediaPath) async {
  if (executable.isEmpty || mediaPath.isEmpty) return -1.0;
  try {
    final result = await FfmpegProbeTask(executable, mediaPath).run();
    return (result['duration'] as num?)?.toDouble() ?? -1.0;
  } on ProviderException {
    return -1.0;
  }
}
