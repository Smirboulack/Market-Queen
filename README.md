# Market Queen

**A free, open-source desktop app that generates UGC video ads. Bring your own API keys.**

Tools like Arcads, HeyGen or Speel are mostly orchestrators: they chain an LLM, an image
model, a video model and a text-to-speech API behind a nice interface, then charge a
monthly subscription on top of the model costs. Market Queen is that orchestrator, as a
native desktop app, with no account, no server and no markup. You paste your own API keys,
and you pay the providers directly for what you use.

```
Product + brief
      │
      ├─ 1. Script      (OpenAI / Claude / Gemini)      → N shots
      ├─ 2. Voice-over  (ElevenLabs / OpenAI TTS)       → one take, measured
      ├─ 3. Frames      (gpt-image-1 / Flux via fal.ai) → one still per shot
      ├─ 4. Shots       (Kling / Wan / Hailuo / Luma)   → one clip per shot
      ├─ 5. Subtitles   (Whisper)
      └─ 6. Final cut   (FFmpeg)                        → trim, concat, mux
                │
          final.mp4
```

The ad is cut into shots rather than being one clip on a loop. The voice-over is
recorded first, in a single take, and how long each shot holds the screen is that shot's
share of it — so nothing is ever stretched or looped to fill time.

## Status

Early V1. The whole pipeline runs end to end and every provider below is implemented, but
it has only been exercised on a small number of models so far. Expect rough edges on the
less common ones. Issues and PRs welcome.

## Install

Grab the build for your OS from the [releases page](../../releases):

| OS      | File                              |
| ------- | --------------------------------- |
| Windows | `MarketQueen-windows.zip`       |
| macOS   | `MarketQueen-macos.dmg`         |
| Linux   | `MarketQueen-linux.AppImage`    |

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

| Step      | Providers | Models |
| --------- | --------- | ------ |
| Script    | OpenAI, Anthropic, Google Gemini | GPT-5, Claude 5, Gemini 2.5 |
| Frame     | fal.ai, OpenAI Images, Replicate | Nano Banana, FLUX (Ultra / Kontext / dev / schnell), Seedream 4, Imagen 4, Ideogram 3, Recraft V3, Qwen Image, GPT Image 1, DALL·E 3, SD 3.5 |
| Video     | fal.ai, Replicate, OpenAI (Sora) | Kling 2.1, Veo 3, Seedance 1 Pro/Lite, Hailuo 02, Runway Gen-3, Luma Ray 2, Wan 2.2, Pika 2.2, PixVerse 4.5, Sora 2 |
| Voice     | ElevenLabs, OpenAI TTS, fal.ai voices | Eleven v3, GPT-4o mini TTS, MiniMax Speech 02, Kokoro, Chatterbox |
| Subtitles | OpenAI Whisper | Whisper |

Every list is a fixed set of choices plus a final **Other…** entry: pick that and a text
field appears for a model id the catalogue does not know yet. The `owner/name` and
`owner/name:version` forms both work on Replicate, and any id from
[fal.ai/models](https://fal.ai/models) works on fal — so a model released tomorrow is
usable today, without an update.

Image and video default to **Auto**, which resolves to the first model in the list (they
are ordered best-first) and switches to a family that can render 10 seconds in one take
when the voice-over is long. Whatever it settles on is written to the activity log, so you
always know what you were billed for.

Midjourney is not in the list: it has no public API.

## What it costs

Every model shows its unit price where you pick it — `Kling 2.1 Master   $0.28/s` — and the
panel on the right adds up what the next click on *Generate* will spend, updating as you
change the form:

```
ESTIMATED COST                    prices 08/08/2026

Script                                      ~$0.01
Voice-over                                  ~$0.03
Frames         4 x                          ~$0.16
Shots          20 s                         ~$5.60
Subtitles                                   ~$0.00
──────────────────────────────────────────────────
Total                                       ~$5.80
```

Video is almost always the bill, and cutting an ad into shots buys a clip for each one.
Switching the video model is the single change that moves the total by an order of
magnitude — the same 20-second ad is `~$1.80` on Hailuo 02 Pro and `~$5.80` on Kling 2.1
Master. That is exactly what the per-model prices are there to make obvious before you
spend anything.

How many shots an ad is cut into follows from its length: every shot is kept at or under
five seconds, the shortest clip every video model sells, so each one is bought at that floor
with nothing paid for and left unused. You choose the length; there is no second control to
get wrong.

Afterwards the run records what it actually consumed — tokens the writer billed, characters
sent to the voice, seconds of clip returned — into `project.json`, and the library shows it
per ad and as a running total.

Prices come from `resources/pricing.json`, checked against each provider's own pricing page.
A model with no public per-request price is reported as unknown and left out of the total
rather than counted as free. Drop your own `pricing.json` into the config folder to override
the lot. It is an estimate, never a bill — the providers charge you, we only do the sums.

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
- Every run writes its own folder — the script and its shot list, the voice-over, one still
  and one clip per shot, the subtitles and the final cut — so you can reuse or fix any
  single piece by hand.

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
├── core/        settings + encrypted key store, pricing, logging, HTTP helpers
├── providers/   one class per API, behind ProviderTask
├── media/       FFmpeg process wrapper
├── pipeline/    the state machine that chains the steps
├── i18n/        runtime language switching
└── app/         the object QML talks to
qml/             the interface
i18n/            translations: <lang>.json + generated .ts
resources/       pricing.json, the model price list
assets/          icons + the Windows resource script
```

**Prices.** `resources/pricing.json` is data, not code, so a provider changing its rates is
a one-line pull request rather than a release. Every model id in `Registry.cpp` has to
appear there, priced or explicitly `"unknown": true` — `tools/check_pricing.py` (wired up as
the `pricing_catalogue` ctest) fails if one is missing, which is what stops a new model from
quietly vanishing out of the estimate.

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

Next up are ad formats, then per-shot regeneration. The full plan is in
[docs/V2-PLAN.md](docs/V2-PLAN.md).

- UGC ad formats (problem/solution, testimonial, unboxing, ...)
- Per-shot regeneration and an in-app preview player
- Batch mode: one product, N variants, with a budget cap
- Auto model routing by cost and capability
- OS keychain for the API keys
- Caption styling in the UI

## License

MIT, by **SegfaultLabs**. The models you call have their own terms and their own pricing.
