# Super Infinity

**A free, open-source desktop app that generates UGC video ads. Bring your own API keys.**

Tools like Arcads, HeyGen or Speel are mostly orchestrators: they chain an LLM, an image
model, a video model and a text-to-speech API behind a nice interface, then charge a
monthly subscription on top of the model costs. Super Infinity is that orchestrator, as a
native desktop app, with no account, no server and no markup. You paste your own API keys,
and you pay the providers directly for what you use.

```
Product + brief
      │
      ├─ 1. Script      (OpenAI / Claude / Gemini)
      ├─ 2. Frame       (gpt-image-1 / Flux via fal.ai or Replicate)
      ├─ 3. Voice-over  (ElevenLabs / OpenAI TTS)
      ├─ 4. Video       (Kling / Wan / Hailuo / Luma, image-to-video)
      ├─ 5. Subtitles   (Whisper)
      └─ 6. Final cut   (FFmpeg)
                │
          final.mp4
```

## Status

Early V1. The whole pipeline runs end to end and every provider below is implemented, but
it has only been exercised on a small number of models so far. Expect rough edges on the
less common ones. Issues and PRs welcome.

## Install

Grab the build for your OS from the [releases page](../../releases):

| OS      | File                              |
| ------- | --------------------------------- |
| Windows | `SuperInfinity-windows.zip`       |
| macOS   | `SuperInfinity-macos.dmg`         |
| Linux   | `SuperInfinity-linux.AppImage`    |

You also need **[FFmpeg](https://ffmpeg.org/download.html)** on your machine: it merges the
clip, the voice-over and the subtitles into the final MP4. The app finds it automatically
if it is on your `PATH`, otherwise point at it in *Settings*. Everything else is bundled.

## Interface

Light theme by default, dark on request — both switch instantly from *Settings*, and the
window title bar follows.

The UI ships in **English, French, Spanish, German, Italian, Portuguese, Dutch, Polish,
Russian, Simplified Chinese and Arabic**, including a fully mirrored right-to-left layout
for Arabic. On first run it follows your system locale; you can pin a language afterwards.
Switching applies immediately, with no restart.

## Providers

You only need keys for the providers you actually pick.

| Step      | Providers                                                       | Key                     |
| --------- | --------------------------------------------------------------- | ----------------------- |
| Script    | OpenAI, Anthropic, Google Gemini                                  | one of them             |
| Frame     | OpenAI Images (`gpt-image-1`), fal.ai, Replicate                  | one of them             |
| Video     | fal.ai *(Kling, Hailuo, Wan, Luma)*, Replicate                    | one of them             |
| Voice     | ElevenLabs, OpenAI TTS                                            | one of them             |
| Subtitles | OpenAI Whisper                                                    | OpenAI (optional)       |

Model ids are editable: if a provider ships a new model tomorrow, type its id in the box,
no update needed. The `owner/name` and `owner/name:version` forms both work on Replicate,
and any model id from [fal.ai/models](https://fal.ai/models) works on fal.

Keys can also come from the environment (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`,
`GEMINI_API_KEY`, `FAL_KEY`, `REPLICATE_API_TOKEN`, `ELEVENLABS_API_KEY`), which is handy
if you already have them exported.

## Where your data goes

- Requests go straight from your machine to the provider you selected. There is no server
  in between and no telemetry.
- Keys are stored in `settings`/`secrets.bin` under your platform config directory,
  encrypted with ChaCha20 and authenticated with HMAC-SHA256 using a key derived from your
  machine identity. That stops a stray backup or a synced folder from leaking them; it is
  not a defence against malware already running as you. An OS keychain backend is the
  planned follow-up.
- Every run writes its own folder (script, frame, voice, clip, subtitles, final cut) so you
  can reuse or fix any single piece by hand.

## Build from source

Requires Qt 6.5+, CMake 3.21+ and a C++20 compiler.

```bash
cmake -S . -B build -DCMAKE_PREFIX_PATH=/path/to/Qt/6.x.x/your_kit
cmake --build build
```

On Windows with the Qt online installer's MinGW kit:

```bash
cmake -S . -B build -G Ninja -DCMAKE_PREFIX_PATH=C:/Qt/6.11.1/mingw_64
```

To produce a self-contained folder (Windows/macOS):

```bash
cmake --install build --prefix dist
```

## Architecture

```
src/
├── core/        settings + encrypted key store, logging, HTTP helpers
├── providers/   one class per API, behind ProviderTask
├── media/       FFmpeg process wrapper
├── pipeline/    the state machine that chains the steps
├── i18n/        runtime language switching
└── app/         the object QML talks to
qml/             the interface
i18n/            translations: <lang>.json + generated .ts
assets/          icons + the Windows resource script
```

**Icons.** Windows draws two different icons for one window: `ICON_SMALL` in the title bar
and `ICON_BIG` in the taskbar. They get different artwork on purpose — at 16px the full
character is a smudge, a face still reads. Regenerate both from the source images with:

```bash
python tools/make_icons.py path/to/head.png path/to/full.png
```

Every provider call returns a `ProviderTask` that emits `succeeded`/`failed` once and then
deletes itself. Nothing blocks the UI thread, including the multi-minute video jobs, which
are polled through the queue APIs.

**Adding a provider** means writing one `HttpTask` subclass and adding one entry to
`Registry.cpp`. The UI and the pipeline pick it up with no further changes.

**Translating.** The strings live in `i18n/<lang>.json` as a flat
`"english source": "translation"` map — much easier to review in a pull request than Qt's
XML. The `.ts`/`.qm` files are generated from them:

```bash
cmake --build build --target update_translations && python tools/fill_translations.py && cmake --build build
```

To add a language: create `i18n/<code>.json`, add the code to `APP_LANGUAGES` in
`CMakeLists.txt` and to `kLanguages` in `src/i18n/Translator.cpp` (set `rightToLeft` if it
applies). `python tools/fill_translations.py --list` prints every string that needs one.

## Roadmap

- OS keychain for the API keys
- Multiple shots per ad instead of one looping clip
- Batch mode: one product, N variants
- In-app preview player
- Caption styling in the UI

## License

MIT, by **SegfaultLabs**. The models you call have their own terms and their own pricing.
