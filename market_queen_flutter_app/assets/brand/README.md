# Brand artwork

One mark, everywhere: `logo.png`.

It is read at runtime by `BrandMark` (`lib/ui/brand.dart`) for the nav header,
and every platform icon file in the repo is generated from it. If it ever goes
missing the nav header falls back to a drawn pink "MQ" tile rather than crashing.

The picture is **never cropped**. It is 1362×1155 — wider than it is tall — and
that is how it is drawn: `BrandMark` sizes it by height and lets the width
follow. Icon formats all want a square, so the difference is made up with
transparent margin above and below, not by cutting the sides off.

## What is generated from it

- `windows/runner/resources/app_icon.ico` — 16/24/32/48/64/128/256. This is
  `IDI_APP_ICON`, the only icon resource, so it serves the exe, the title bar,
  Alt+Tab and the taskbar button alike.
- `web/favicon.png` (16), `web/icons/Icon-{192,512}.png` — transparent margin.
- `web/icons/Icon-maskable-{192,512}.png` — centred in the middle 80% of an
  opaque white square, because a maskable icon is cropped to whatever shape the
  platform likes and has to stay opaque.
- `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png` — every size
  the iconset declares, up to 1024.

Linux has no icon file; the window manager reads the `.desktop` entry.

## Regenerating

The icons are committed, so replacing `logo.png` means regenerating them. The
generator was a throwaway Pillow script: centre the picture on a square canvas
of `max(width, height)` — `max(width, height) × 1.25` on white for the maskable
pair — then resize that canvas to each target size. No cropping at any step.
