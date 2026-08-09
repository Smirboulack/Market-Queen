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
