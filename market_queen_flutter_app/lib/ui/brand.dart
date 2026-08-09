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

  final double size;

  /// The in-app and taskbar artwork. The crown is the *window* icon and lives in
  /// the platform folders, not here.
  static const String logoAsset = 'assets/brand/logo.png';

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.26),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          logoAsset,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, _, _) => _Fallback(size: size),
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

    return ColoredBox(
      color: mq.primary,
      child: Center(
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
      ),
    );
  }
}
