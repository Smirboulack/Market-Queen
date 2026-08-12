# Provider marks

Optional. Drop a square PNG in here named after the **credential id** in
`lib/providers/registry.dart`, and the Models page and the composer's model menu
pick it up at run time:

| File               | Account               |
| ------------------ | --------------------- |
| `openai.png`       | OpenAI                |
| `gemini.png`       | Google Gemini         |
| `anthropic.png`    | Anthropic             |
| `xai.png`          | xAI                   |
| `minimax.png`      | MiniMax               |
| `ltx.png`          | LTX (Lightricks)      |
| `bytedance.png`    | BytePlus ModelArk     |
| `bfl.png`          | Black Forest Labs     |
| `heygen.png`       | HeyGen                |
| `elevenlabs.png`   | ElevenLabs            |
| `luma.png`         | Luma                  |
| `ideogram.png`     | Ideogram              |
| `bria.png`         | Bria                  |
| `groq.png`         | Groq                  |
| `fal.png`          | Kling (via fal.ai)    |

Anything without a file falls back to a drawn two-letter tile — see
`ProviderMark` in `lib/ui/brand.dart`. A missing file is a supported state, not
an error: the page renders either way.

## Why none of them ship

They are other people's trademarks. Bundling fifteen of them into the repository
is a licensing call for whoever ships a build, not a detail of the interface, so
the folder is left empty and the interface draws initials until it is filled.
Most of these companies publish a brand or press kit with the terms attached;
that is where the files should come from.

## What to put in

- Square, transparent background, 128px or larger. Drawn at 30px on the Models
  page and 18px in the model menu, so anything with fine detail or a wordmark
  in it will be a smudge — use the **mark**, not the logotype.
- The interface is greyscale by design. A full-colour mark will work and will be
  the only colour on the page; a monochrome one will sit better next to
  everything else.
- `BoxFit.contain`, never cropped: a wide logotype is letterboxed rather than
  having its ends cut off.
