import 'package:flutter/material.dart';

/// The four places a vertical ad ends up, drawn rather than bundled.
///
/// Material's icon font carries almost none of these, and shipping four brand
/// SVGs to get four 16px glyphs is a lot of asset for a row that only answers
/// one question: does the format you picked suit the place you are posting to.
/// They are monochrome and take their colour from the caller, like every other
/// glyph in the app.
enum AdPlatform { tiktok, instagram, facebook, youtube }

extension AdPlatformInfo on AdPlatform {
  String get label => switch (this) {
    AdPlatform.tiktok => 'TikTok',
    AdPlatform.instagram => 'Instagram',
    AdPlatform.facebook => 'Facebook',
    AdPlatform.youtube => 'YouTube',
  };

  /// The shape this platform is really built around. Clicking the glyph picks
  /// it.
  String get nativeAspect => switch (this) {
    AdPlatform.tiktok => '9:16',
    AdPlatform.instagram => '9:16',
    AdPlatform.facebook => '1:1',
    AdPlatform.youtube => '16:9',
  };

  /// Every shape this platform will take without letterboxing the ad.
  Set<String> get aspects => switch (this) {
    AdPlatform.tiktok => const {'9:16'},
    AdPlatform.instagram => const {'9:16', '1:1'},
    AdPlatform.facebook => const {'1:1', '9:16'},
    AdPlatform.youtube => const {'16:9', '9:16'},
  };
}

class PlatformMark extends StatelessWidget {
  const PlatformMark(
    this.platform, {
    super.key,
    this.size = 18,
    required this.color,
  });

  final AdPlatform platform;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MarkPainter(platform, color)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.platform, this.color);

  final AdPlatform platform;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Everything below is drawn in a 24x24 box and scaled to whatever the caller
    // asked for, so one set of numbers serves every size on screen.
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    switch (platform) {
      case AdPlatform.instagram:
        canvas.drawRRect(
          RRect.fromLTRBR(2.9, 2.9, 21.1, 21.1, const Radius.circular(5.8)),
          stroke,
        );
        canvas.drawCircle(const Offset(12, 12), 4.4, stroke);
        canvas.drawCircle(const Offset(17.1, 6.9), 1.2, fill);

      case AdPlatform.facebook:
        canvas.drawCircle(const Offset(12, 12), 9.1, stroke);
        canvas.drawPath(_facebookF, fill);

      case AdPlatform.youtube:
        canvas.drawRRect(
          RRect.fromLTRBR(2.2, 5.2, 21.8, 18.8, const Radius.circular(4.6)),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(10.3, 8.8)
            ..lineTo(16.1, 12.0)
            ..lineTo(10.3, 15.2)
            ..close(),
          fill,
        );

      case AdPlatform.tiktok:
        canvas.drawPath(_tiktokNote, fill);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.platform != platform || old.color != color;
}

/// The "f", as one filled outline rather than a text glyph: a letter drawn by
/// the font would be a different shape on every machine.
final Path _facebookF = Path()
  ..moveTo(15.1, 7.4)
  ..lineTo(13.6, 7.4)
  ..cubicTo(11.9, 7.4, 11.2, 8.4, 11.2, 10.0)
  ..lineTo(11.2, 11.3)
  ..lineTo(9.5, 11.3)
  ..lineTo(9.5, 13.5)
  ..lineTo(11.2, 13.5)
  ..lineTo(11.2, 19.6)
  ..lineTo(13.6, 19.6)
  ..lineTo(13.6, 13.5)
  ..lineTo(15.3, 13.5)
  ..lineTo(15.6, 11.3)
  ..lineTo(13.6, 11.3)
  ..lineTo(13.6, 10.3)
  ..cubicTo(13.6, 9.8, 13.8, 9.6, 14.3, 9.6)
  ..lineTo(15.1, 9.6)
  ..close();

/// The eighth note: flag top right, stem down, loop bottom left.
final Path _tiktokNote = Path()
  ..moveTo(13.1, 3.0)
  ..lineTo(16.1, 3.0)
  ..cubicTo(16.4, 5.3, 17.7, 6.7, 20.0, 6.9)
  ..lineTo(20.0, 9.8)
  ..cubicTo(18.5, 9.8, 17.2, 9.4, 16.1, 8.7)
  ..lineTo(16.1, 14.7)
  ..cubicTo(16.1, 18.2, 13.3, 21.0, 9.8, 21.0)
  ..cubicTo(6.3, 21.0, 3.5, 18.2, 3.5, 14.7)
  ..cubicTo(3.5, 11.2, 6.3, 8.4, 9.8, 8.4)
  ..lineTo(10.4, 8.4)
  ..lineTo(10.4, 11.4)
  ..lineTo(9.8, 11.4)
  ..cubicTo(8.0, 11.4, 6.5, 12.9, 6.5, 14.7)
  ..cubicTo(6.5, 16.5, 8.0, 18.0, 9.8, 18.0)
  ..cubicTo(11.6, 18.0, 13.1, 16.5, 13.1, 14.7)
  ..close();
