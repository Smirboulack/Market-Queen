# Brand artwork

Two marks, two jobs. Drop the files here with exactly these names; nothing has
to be rebuilt beyond the app itself.

| File        | Where it shows                                     | Wanted            |
| ----------- | -------------------------------------------------- | ----------------- |
| `logo.png`  | The nav header, and the desktop taskbar/dock button | square, ≥ 512 px  |
| `crown.png` | The window icon and the web favicon                 | square, ≥ 512 px, transparent background |

`logo.png` is read at runtime by `BrandMark` (`lib/ui/brand.dart`). Until it
exists the nav header falls back to the pink "MQ" tile, so a missing file is
never a crash.

`crown.png` is *not* read at runtime: the window icon and the favicon are
platform files that have to be generated from it once.

- Windows — `windows/runner/resources/app_icon.ico` (multi-size .ico: 16, 32,
  48, 64, 128, 256)
- Web — `web/favicon.png`, plus `web/icons/Icon-{192,512}.png` and the two
  maskable variants
- macOS — `macos/Runner/Assets.xcassets/AppIcon.appiconset/`
- Linux — no icon file; the window manager uses the `.desktop` entry

The crown is a wide, short shape on a transparent field, so it needs padding
before it is squared off or it will be rendered as a two-pixel-tall smear at
16 px.
