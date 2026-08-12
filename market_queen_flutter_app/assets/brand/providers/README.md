# Provider marks

A square PNG named after the **credential id** in `lib/providers/registry.dart`.
The Models page and the composer's model menu pick it up at run time; an account
with no file gets a drawn two-letter tile instead. A missing file is a supported
state, not an error — the page renders either way.

## Two sheets, and why

`<credential>w.png` is the **white sheet**, used in the dark theme and only
there. Half of these marks are black on transparent and disappear against a dark
surface; the other half are full-colour and read on both, so they need no second
file.

The `w` file is looked for first in dark mode and quietly skipped when it is not
there — so whether a logo needs a light version is answered by putting a file in
this folder, never by editing a list in the code.

| File          | Drawn                                        |
| ------------- | -------------------------------------------- |
| `openai.png`  | light theme — and dark too, if there is no `w`|
| `openaiw.png` | dark theme                                    |
| *(neither)*   | a two-letter tile, both themes                |

## The accounts

| File             | Account            | White sheet |
| ---------------- | ------------------ | ----------- |
| `openai.png`     | OpenAI             | yes         |
| `gemini.png`     | Google Gemini      | —           |
| `anthropic.png`  | Anthropic          | yes         |
| `xai.png`        | xAI                | yes         |
| `minimax.png`    | MiniMax            | —           |
| `ltx.png`        | LTX (Lightricks)   | yes         |
| `bytedance.png`  | BytePlus ModelArk  | —           |
| `bfl.png`        | Black Forest Labs  | yes         |
| `heygen.png`     | HeyGen             | —           |
| `elevenlabs.png` | ElevenLabs         | yes         |
| `luma.png`       | Luma               | —           |
| `ideogram.png`   | Ideogram           | yes         |
| `bria.png`       | Bria               | —           |
| `groq.png`       | Groq               | yes         |
| `fal.png`        | Kling (via fal.ai) | —           |

`kling.png` is in the folder and is **not used**: the account's credential id is
`fal`, so `fal.png` is the file the card reads. The account is *labelled* "Kling
(via fal.ai)" in the interface, so if the Kling mark is the more recognisable of
the two, rename it over `fal.png`.

## Licensing

These are other people's trademarks. Whether they belong in the repository of a
build you ship is a licensing call, not a detail of the interface — the code
works with the folder empty. Most of these companies publish a brand or press
kit with the terms attached; that is where the files should come from.

## What to put in

- Square, transparent background, 128px or larger. Drawn at 30px on the Models
  page and 18px in the model menu, so anything with fine detail or a wordmark
  in it will be a smudge — use the **mark**, not the logotype.
- `BoxFit.contain`, never cropped: a wide logotype is letterboxed rather than
  having its ends cut off.
