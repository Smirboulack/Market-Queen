# Brand artwork

Two marks, two jobs.

| File        | Where it shows                                              |
| ----------- | ----------------------------------------------------------- |
| `logo.png`  | The nav header, the taskbar/dock button, and the exe icon    |
| `crown.png` | The window's title bar, and the web favicon                  |

`logo.png` is the only one read at runtime, by `BrandMark`
(`lib/ui/brand.dart`). If it is ever missing the nav header falls back to a
drawn pink "MQ" tile rather than crashing.

`crown.png` is never read at runtime. It is kept here as the artwork of record
for the platform icon files, which are generated from these two and committed.

## What was generated from them

- `windows/runner/resources/app_icon.ico` — the character, at 16/24/32/48/64/128/256.
  This is `IDI_APP_ICON`, so it is the exe icon and the window class icon, which
  is what Explorer, Alt+Tab and the taskbar button use.
- `windows/runner/resources/window_icon.ico` — the crown, at 16/20/24/32/48/64/128.
  This is `IDI_WINDOW_ICON`; `Win32Window::Create` sets it as `ICON_SMALL`, which
  is the title bar and nothing else. Its 16–24px entries are cropped to the
  central pear gem: a whole tiara squeezed into 16px is a gold hairline.
- `web/favicon.png`, `web/icons/Icon-{192,512}.png` — the crown, transparent.
- `web/icons/Icon-maskable-{192,512}.png` — the crown inside the middle 80% of
  an opaque white canvas, because a maskable icon is cropped to whatever shape
  the platform likes.
- `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png` — the
  character, at every size the iconset declares.

Linux has no icon file; the window manager reads the `.desktop` entry.

## Regenerating

There is no build step: the icons above are committed, and replacing either
source means regenerating them. The generator was a throwaway Pillow script —
crop the character to a square on its full height anchored right (the source is
1362×1155 and the head sits right of centre), trim the crown to its alpha bounds
and centre it on a square, then write each target size.
