import 'package:flutter/material.dart';

import 'theme.dart';

/// The app's own mark, wherever the interface shows itself: the nav header, and
/// anywhere else a "this is Market Queen" is wanted.
///
/// The artwork is an asset rather than a drawing, and a *missing* asset is a
/// supported state: the pink "MQ" tile below is what shipped before there was a
/// logo, and it is what you get until `assets/brand/logo.png` exists. That is
/// deliberate -- an app that will not start because a picture is absent is worse
/// than one that starts with a placeholder.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 34});

  /// How tall the mark is drawn. The width follows the artwork's own
  /// proportions rather than being forced square, because forcing it square
  /// would mean cropping -- and the mark is a picture, not a glyph.
  final double size;

  /// The one piece of artwork the app carries. Every platform icon is generated
  /// from this same file.
  static const String logoAsset = 'assets/brand/logo.png';

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: Image.asset(
        logoAsset,
        height: size,
        // Never `cover`: it fills the box by cutting the edges off, which on a
        // 1362x1155 picture takes the phone out of frame.
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, _, _) => _Fallback(size: size),
      ),
    );
  }
}

/// The mark for one of the accounts the app buys from.
///
/// Seventeen providers on five shelves is a page you scan rather than read, and
/// a column of identical grey headings gives the eye nothing to aim at. This is
/// what it aims at.
///
/// The artwork is a drop-in, exactly like the app's own mark: put a square PNG
/// at `assets/brand/providers/<credential>.png` -- `openai.png`, `gemini.png`
/// -- and it is picked up at run time. None ship with the app. They are other
/// people's trademarks, and bundling fifteen of them into the repository is a
/// licensing decision for whoever ships the build rather than a detail of the
/// interface, so until one is dropped in the fallback below is what draws: the
/// account's initials in a plain tile. That is monochrome on purpose -- see the
/// palette in [MqTheme] -- so a page of them stays a page of one colour.
class ProviderMark extends StatelessWidget {
  const ProviderMark({super.key, required this.credential, this.size = 30});

  /// The credential id from the registry: `openai`, `bytedance`, `fal`.
  final String credential;

  final double size;

  static String assetFor(String credential) =>
      'assets/brand/providers/$credential.png';

  /// Two letters per account, written down rather than sliced off the label:
  /// three different accounts begin with a B, two with a G, and an initial that
  /// three cards share is worse than no initial at all.
  ///
  /// ElevenLabs is the one that is not initials. "11" *is* their mark, and it
  /// is more recognisable than "EL" would be.
  static const Map<String, String> _initials = {
    'openai': 'OA',
    'gemini': 'GE',
    'anthropic': 'AN',
    'xai': 'XA',
    'minimax': 'MM',
    'ltx': 'LX',
    'bytedance': 'BP',
    'bfl': 'BF',
    'heygen': 'HG',
    'elevenlabs': '11',
    'luma': 'LM',
    'ideogram': 'ID',
    'bria': 'BR',
    'groq': 'GQ',
    'fal': 'KL',
  };

  static String initialsFor(String credential) {
    final known = _initials[credential];
    if (known != null) return known;
    final trimmed = credential.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, trimmed.length < 2 ? 1 : 2).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.asset(
        assetFor(credential),
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, _, _) =>
            _Monogram(text: initialsFor(credential), size: size),
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.text, required this.size});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: mq.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: mq.textSecondary,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w600,
          letterSpacing: MqTheme.trackSmall,
          height: 1,
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    // Sized here rather than by the parent: the real mark carries its own
    // proportions, so there is no box around this one to inherit.
    return Container(
      width: size,
      height: size,
      color: mq.primary,
      alignment: Alignment.center,
      child: Text(
        // Not translated: it is the product's initials.
        'MQ',
        style: TextStyle(
          color: mq.onPrimary,
          fontSize: size * 0.35,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          height: 1,
        ),
      ),
    );
  }
}
