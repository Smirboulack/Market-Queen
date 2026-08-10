# fal.ai catalogue

A snapshot of everything fal.ai offers, pulled through the platform API on
**2026-08-10**, plus the three scripts that pulled it. No inference was ever
requested — this only reads the catalogue and the price list.

| File | What it is |
| --- | --- |
| `fal_models.json` | All 1434 models, raw, exactly as `/v1/models` returns them |
| `fal_models_pricing.json` | Unit price per endpoint, from `/v1/models/pricing` |
| `fal_models_complete.json` | The two merged, one entry per model |
| `fal_catalog.json` | Normalised: `id`, `name`, `provider`, `category`, `pricing`, `model_url`, and the untouched response under `raw` |

1434 models found, 1433 priced. The one exception is
`fal-ai/decart/lucy-5b/image-to-video`, which the pricing endpoint 404s on —
it is still listed but appears to have been withdrawn.

## Refreshing it

The key never goes in a file or on a command line that gets logged:

```bash
export FAL_KEY="your-fal-key"
```

```bash
python tools/fal-catalog/fetch_models.py tools/fal-catalog
```

```bash
python tools/fal-catalog/fetch_pricing.py tools/fal-catalog
```

Then fold the prices the estimator can use into the app's own catalogue:

```bash
python tools/fal-catalog/update_pricing.py tools/fal-catalog market_queen_flutter_app
```

## What `update_pricing.py` will and will not convert

`assets/resources/pricing.json` counts in units the estimator can predict before
a run: seconds, images, videos, thousands of characters, minutes. fal bills in
those *and* in several that have no fixed relationship to anything countable in
advance — "compute seconds" depends on how long the GPU takes, and the token
buckets depend on the clip.

Those are left alone rather than converted with an invented factor. Seedance
2.0 bills `0.014 units` for a clip that really costs cents to dollars; treating
a unit as a video would print a penny on the confirmation screen, which is the
one number a user should be able to trust. A model whose unit cannot be
converted keeps whatever estimate the catalogue already carried, and is marked
`"unknown": true` only if it had none.

Of the 61 models the app offers from fal: **45 now carry the exact live price**,
6 keep their previous approximation, and 10 are honestly unknown.

## Model schemas

Durations, resolutions and the audio switch are *not* taken from this snapshot.
They are read per model, at runtime, from the model's own OpenAPI document
(`https://fal.ai/api/openapi/queue/openapi.json?endpoint_id=…`) by
`lib/providers/fal_schema.dart`, and cached under the config directory. Each
endpoint declares a different set — Hailuo offers 6 and 10 seconds, Kling v3
every second from 3 to 15, Veo spells them "4s"/"6s"/"8s" — and a model rejects
any field it has not declared.
