import 'package:flutter/material.dart';

import '../../media/ffmpeg.dart';
import 'media_drop.dart';

/// A clip's first readable frame, pulled with ffmpeg the first time it is drawn
/// and kept from then on.
///
/// Draws nothing at all until the frame is there -- and nothing ever, without
/// ffmpeg -- so every caller stacks it over whatever it wants shown in the
/// meantime. That is the whole reason it is a widget of its own rather than
/// part of one tile: the canvas wants a grey plate behind it, the reference row
/// wants a film glyph, and neither should have to own the extraction.
class VideoPosterImage extends StatefulWidget {
  const VideoPosterImage({
    super.key,
    required this.ffmpegPath,
    required this.path,
    this.fit = BoxFit.cover,
  });

  final String ffmpegPath;
  final String path;
  final BoxFit fit;

  /// The seam widget tests reach for.
  ///
  /// Drawing a reference tile would otherwise spawn ffmpeg, and a subprocess
  /// started inside a test's fake clock outlives the test that started it --
  /// for a frame no assertion is going to look at. Off, the tile draws whatever
  /// its caller stacked underneath, which is the same thing a machine without
  /// ffmpeg sees.
  @visibleForTesting
  static bool extraction = true;

  @override
  State<VideoPosterImage> createState() => _VideoPosterImageState();
}

class _VideoPosterImageState extends State<VideoPosterImage> {
  /// Extraction is per file and its result never changes, so it is remembered
  /// for the life of the process: scrolling a long feed must not re-run ffmpeg
  /// on every tile that leaves and re-enters the viewport.
  static final Map<String, String> _cache = {};

  String _poster = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(VideoPosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.ffmpegPath != widget.ffmpegPath) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!VideoPosterImage.extraction ||
        widget.ffmpegPath.isEmpty ||
        widget.path.isEmpty) {
      return;
    }

    final cached = _cache[widget.path];
    if (cached != null) {
      setState(() => _poster = cached);
      return;
    }

    final found = await posterFrame(widget.ffmpegPath, widget.path);
    _cache[widget.path] = found;
    if (mounted) setState(() => _poster = found);
  }

  @override
  Widget build(BuildContext context) => _poster.isEmpty
      ? const SizedBox.shrink()
      : LocalImage(_poster, fit: widget.fit);
}
