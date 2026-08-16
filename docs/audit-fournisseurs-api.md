# Audit API — 17 fournisseurs directs (sortie de fal.ai / Replicate)

Date de l'audit : **11 août 2026**
Périmètre : uniquement les documentations, API references, catalogues et pages de prix **officielles** de chaque fournisseur.
Règle appliquée : rien n'est déduit. Toute information non explicitement documentée est marquée `NOT DOCUMENTED` ou `REQUIRES VERIFICATION`.

---

## Avertissements préliminaires (à lire avant toute décision produit)

### 1. VEED n'a pas d'API propre — elle est distribuée **par fal.ai**

La page officielle `veed.io/api` indique littéralement, pour obtenir l'accès : *« Sign up on fal.ai and grab your API key »*, et l'exemple d'intégration utilise le SDK `@fal-ai/client`. Les modèles exposés (Fabric 1.0, Lip Sync 2.0, Subtitles, Green Screen, Background Removal) le sont **via fal**. Seule la « Live Avatar API » a une waitlist propre.

**Conséquence** : VEED est incompatible avec la règle « pas d'agrégateur ». Soit on l'exclut, soit on accepte une exception fal **uniquement** pour VEED.
Source : https://www.veed.io/api

### 2. Krea **est** un agrégateur

Le catalogue Krea API revend Kling 1.0→3.0/O1, Veo 2/3/3.1, Seedance, Hailuo, Wan, LTX-2.3, Runway, Grok Imagine, Luma Ray-2, Vidu, Ideogram, Imagen, Seedream, Nano Banana, GPT-Image… exactement le même modèle économique que fal.ai et Replicate, avec une marge (ex. Kling 3.0 std revendu 0,1764 $/s).

**Conséquence** : par la règle posée, Krea doit être classé « agrégateur » au même titre que fal/Replicate, et exclu — sauf si tu veux le garder comme *fallback unique* pour les modèles sans API directe.
Source : https://www.krea.ai/docs/llms.txt, https://www.krea.ai/docs/developers/introduction.md

### 3. Kling : portail international sous authentification

Le portail développeur global (`app.klingai.com/global/dev`) exige une connexion : impossible de vérifier sans compte les **prix en USD** et le **domaine international**. Tout ce qui suit sur Kling provient du portail chinois public `klingai.com/document-api` (prix en ¥/积分, domaine `api-beijing.klingai.com`, avec `api.klingai.com` également listé).
→ **Domaine international + tarifs USD : REQUIRES VERIFICATION** (connexion compte requise).

### 4. Fournisseurs à contrainte d'activation

| Fournisseur | Contrainte |
|---|---|
| BytePlus ModelArk | Seedance 2.0 / 2.5 : solde compte **> 30 USD** ou resource pack acheté |
| Alibaba Model Studio | Le host contient un `{WorkspaceId}` ; clés **non interchangeables entre régions** |
| PixVerse | Système de crédits prépayés (achat par paliers 10 $ → 5 000 $) |
| Krea | Balance USD API séparée, minimum 5 $ ; API doit être activée sur le workspace |
| HeyGen | Wallet USD prépayé, facturation « API tier » quand on utilise `x-api-key` |

---

# Section 1 — Provider overview

| # | Fournisseur | API directe BYOK | Domaine API | Auth | Catégories utiles à Market Queen |
|---|---|---|---|---|---|
| 1 | **Kling AI** (Kuaishou) | ✅ | `https://api-beijing.klingai.com` (CN) · `https://api.klingai.com` | `Authorization: Bearer <API Key>` | Vidéo, Avatar/lip-sync, Image, TTS |
| 2 | **MiniMax** | ✅ | `https://api.minimax.io` (+ `api-uw.minimax.io`) | `Authorization: Bearer <key>` | Vidéo, TTS, LLM, Image, Musique |
| 3 | **LTX / Lightricks** | ✅ | `https://api.ltx.io` | `Authorization: Bearer <key>` | Vidéo (T2V/I2V/A2V/extend/retake/reframe) |
| 4 | **xAI** | ✅ | `https://api.x.ai/v1` | Bearer | LLM, Image, Vidéo, Voice |
| 5 | **OpenAI** | ✅ | `https://api.openai.com/v1` | Bearer | LLM, Image, Vidéo (Sora), TTS, STT |
| 6 | **Krea** | ⚠️ agrégateur | `https://api.krea.ai` | Bearer | Image, Vidéo (revente) |
| 7 | **ElevenLabs** | ✅ | `https://api.elevenlabs.io` (+ US/EU/IN/SG) | `xi-api-key` | TTS, STT, voice cloning, music |
| 8 | **ByteDance / BytePlus ModelArk** | ✅ | `https://ark.ap-southeast.bytepluses.com/api/v3` · `https://ark.eu-west.bytepluses.com/api/v3` | Bearer | Vidéo (Seedance), Image (Seedream), LLM |
| 9 | **Alibaba Model Studio** | ✅ | `https://{WorkspaceId}.<region>.maas.aliyuncs.com` | `Bearer $DASHSCOPE_API_KEY` | Vidéo (Wan), Image (Qwen-Image), LLM |
| 10 | **Google Gemini API** | ✅ | `https://generativelanguage.googleapis.com/v1beta` | `key=` ou header | LLM, Image (Nano Banana), Vidéo (Veo), TTS |
| 11 | **Bria AI** | ✅ | `https://engine.prod.bria-api.com/v2` | `api_token` | Image gen/edit, product shot, video edit |
| 12 | **Black Forest Labs** | ✅ | `https://api.bfl.ai` | `x-key` | Image (FLUX.2/1), **Vidéo (FLUX 3)** |
| 13 | **VEED** | ❌ (via fal.ai) | — | — | Lip-sync (Fabric 1.0) |
| 14 | **HeyGen** | ✅ | `https://api.heygen.com` | `x-api-key` ou Bearer OAuth2 | Avatar parlant, lip-sync, TTS, traduction |
| 15 | **Luma AI** | ✅ | `https://api.lumalabs.ai/dream-machine/v1` | Bearer | Vidéo (Ray), Image (Photon/Uni) |
| 16 | **Ideogram** | ✅ | `https://api.ideogram.ai` | `Api-Key` | Image (typographie, character ref) |
| 17 | **PixVerse** | ✅ | `https://app-api.pixverse.ai/openapi/v2` | `API-KEY` + `Ai-trace-id` | Vidéo, lip-sync, effets, avatar |

---

# Section 2 — All API models

## 2.1 Kling AI

Source : https://klingai.com/document-api/api/get-started/authentication et pages `/document-api/api/video/*`

**Architecture API 2.0** : « modèle = endpoint ». La version du modèle est **dans le path**, plus dans un paramètre `model_name` (l'ancien style est marqué « legacy » dans la doc).

| Model | Endpoint (path) | Statut | Résolutions | Durée | Audio | Références |
|---|---|---|---|---|---|---|
| Kling 3.0 Turbo | `/image-to-video/kling-3.0-turbo`, `/text-to-video/kling-3.0-turbo` | NEW / AVAILABLE | 720p, 1080p | 3–15 s | tarif « 有声 » uniquement → `REQUIRES VERIFICATION` sur le paramètre | first_frame seulement (pas de last_frame) |
| Kling 3.0 | `/image-to-video/kling-3.0`, `/text-to-video/kling-3.0` | AVAILABLE (HOT) | 720p, 1080p, **4k** | 3–15 s | `audio: native \| off` | first_frame, last_frame, `element` (max 3 sujets) |
| **Kling 3.0 Omni** | `/omni-video/kling-3.0-omni` | AVAILABLE (HOT) | 720p, 1080p, 4k | 3–15 s | `native \| original \| off` | first_frame, last_frame, `refer_image`, **`feature_video`**, **`base_video`** (édition vidéo), `element` |
| Kling O1 | `/document-api/api/video/o1` | AVAILABLE | 720p, 1080p | `NOT DOCUMENTED` ici | — | avec/sans vidéo de référence (visible dans la grille tarifaire) |
| Kling 2.6 | `/document-api/api/video/2-6` | AVAILABLE | 720p, 1080p | — | avec/sans voix, + voix imposée | — |
| Kling 2.5 Turbo | `/document-api/api/video/2-5-turbo` | AVAILABLE | 720p, 1080p | — | muet | — |
| Kling 2.1 / 2.1 Master / 2.0 Master / 1.6 / 1.5 / 1.0 | legacy | AVAILABLE (tarifés) | 720p/1080p | — | muet | 1.6 : multi-image ref + édition multimodale + extension |
| **Digital human (数字人)** | `POST /v1/videos/avatar/image2video` | AVAILABLE | 720p, 1080p | jusqu'à **300 s** (durée = audio) | audio fourni en entrée | image + audio + prompt de mouvement |
| Motion control (动作控制) | `/document-api/api/video/motion-control` | AVAILABLE (HOT) | 720p, 1080p | — | — | — |
| Audio generation | `/document-api/api/video/audio-generation` | AVAILABLE | — | — | text→SFX, video→SFX, voice cloning | — |
| Kling Image 3.0 / 3.0 Omni / Image O1 | `/document-api/api/image/*` | AVAILABLE | — | — | — | — |

**Capacité clé multi-shot** : format de prompt normalisé `镜头 n, m, words; 镜头 n, m, words;` — max **6 plans**, somme des durées = durée totale, 512 caractères par plan. Les sujets sont adressés par `@Nom`, les médias par `@image_1`, `@video_1`.

**Contraintes fichiers (Kling 3.0 / Omni)**
- Images : `.jpg/.jpeg/.png`, ≤ 50 MB, ≥ 300 px, ratio entre 1:2.5 et 2.5:1
- Vidéos : `.mp4/.mov`, ≤ 200 MB, durée 3 s → 15,5 s, 700–4553 px, aire ≤ 8 294 400 px, ratio 0.4–2, 24–60 fps (sortie toujours 24 fps)
- Digital human : image ≤ 10 MB ; audio `.mp3/.wav/.m4a/.aac` ≤ 5 MB, 2 s → 300 s
- Prompt : ≤ 3072 caractères (recommandé ≤ 2500)
- **Résultats purgés après 30 jours**

**Limites de combinaison Omni** (documentées explicitement) :
- sans vidéo de réf + sujets multi-images : images de réf + sujets ≤ 7
- sans vidéo + sujets vidéo-personnage : ≤ 3
- avec vidéo de réf : images + sujets ≤ 4, et 1 seul sujet vidéo-personnage
- `feature_video` → `multi_shot` doit être `true` et `audio` doit être `off`
- `base_video` (édition) → pas de first/last frame, pas de multi-shot, `audio ≠ native`

---

## 2.2 MiniMax

Sources : https://platform.minimax.io/docs/guides/models-intro.md, `/docs/api-reference/video-generation-v2-create.md`, `/docs/api-reference/video-generation-i2v.md`, `/docs/api-reference/speech-t2a-http.md`

### Vidéo

| Model ID | Statut officiel | API | Résolution | Durée | Entrées |
|---|---|---|---|---|---|
| **MiniMax-H3** | **Current** | v2 : `POST /v2/video_generation` | `768P`, `2K` | **4–15 s** (entier) | text + 0–2 first/last frame + ≤ 9 images réf + ≤ 3 vidéos réf + ≤ 3 audios réf |
| MiniMax-Hailuo-2.3 | **Legacy** | v1 : `POST /v1/video_generation` | 512P/720P/768P/1080P | 6 ou 10 s | first_frame_image |
| MiniMax-Hailuo-2.3-Fast | Legacy | v1 | idem | 6/10 s | first_frame_image |
| MiniMax-Hailuo-02 | Legacy | v1 | idem | 6/10 s | first_frame_image |
| I2V-01-Director / I2V-01-live / I2V-01 | Legacy | v1 | — | — | first_frame_image |

Formats acceptés (H3) : vidéo H.264/H.265 (≤ 50 MB), image JPG/PNG/WEBP/HEIC/HEIF (≤ 30 MB, 256–5760 px), audio WAV/MP3 (≤ 15 MB, 2–15 s). Prompt ≤ 7000 caractères.

### Audio / TTS

| Model ID | Statut |
|---|---|
| `speech-2.8-hd`, `speech-2.8-turbo` | Current |
| `speech-2.6-hd`, `speech-2.6-turbo` | Legacy |
| `speech-02-hd`, `speech-02-turbo` | Legacy |
| `speech-01-hd`, `speech-01-turbo` | acceptés par l'endpoint T2A |

### LLM / Image / Musique
`MiniMax-M3` (courant, 1M contexte), `M2.7`, `M2.7-highspeed` (courants) ; `M2.5`, `M2.5-highspeed`, `M2.1`, `M2.1-highspeed`, `M2` (legacy).
Image : `image-01`. Musique : `music-3.0`, `music-2.6`, `music-cover` (courants), `music-2.0` (legacy).

---

## 2.3 LTX / Lightricks

Sources : https://docs.ltx.io/models.md, `/pricing.md`, `/authentication.md`, `/api-documentation/api-reference/*`

| Model ID | Statut | Résolutions | fps | Notes |
|---|---|---|---|---|
| `ltx-2-5-fast` | GA | jusqu'à 4K | 24 et 48 | durée automatique possible (`duration: null`) |
| `ltx-2-5-pro` | GA | jusqu'à 1080p | 24 | jeu de fonctionnalités le plus large avec 2-3-pro |
| `ltx-2-3-fast` | GA | jusqu'à 4K | 24/48 | |
| `ltx-2-3-pro` | GA | jusqu'à 4K | 24/48 | seul modèle supportant `retake` et `extend` |
| `ltx-2-fast`, `ltx-2-pro` | **DEPRECATED — suppression le 15 août 2026** | — | — | migrer vers 2.3 |

Endpoints par capacité : text-to-video, image-to-video, audio-to-video, retake, extend, video-to-video HDR, video-to-video reframe (versions sync et async).
Audio natif : `generate_audio` par défaut `true`.
`camera_motion` : `dolly_in`, `dolly_out`, `dolly_left`, `dolly_right`, `jib_up`, `jib_down`, `static`, `focus_shift`.

---

## 2.4 xAI

Sources : https://docs.x.ai/developers/models, https://docs.x.ai/developers/pricing, https://docs.x.ai/

| Model ID | Type | Contexte | Statut |
|---|---|---|---|
| `grok-4.5` (alias `grok-4.5-latest`) | Texte | 500k | Stable (cutoff 1 fév. 2026) |
| `grok-4.3` | Texte | 1M | Stable |
| `grok-4.20-0309-reasoning` | Texte | 1M | Stable |
| `grok-4.20-0309-non-reasoning` | Texte | 1M | Stable |
| `grok-4.20-multi-agent-0309` | Texte | 1M | Stable |
| `grok-build-0.1` | Texte | 256k | **Beta** |
| `grok-imagine-image` | Image | — | Stable |
| `grok-imagine-image-quality` | Image | — | Stable |
| `grok-imagine-video` | Vidéo | — | Stable |
| `grok-imagine-video-1.5` | Vidéo | — | Stable |
| `grok-voice-think-fast-1.0` / `-2.0` | Speech-to-speech | — | Stable |

APIs annoncées : Responses API, Voice API, Imagine API (Images : génération + édition), Imagine API (Video : génération + édition), Code API. Compatible client OpenAI.
**Chemins exacts des endpoints Imagine video : `NOT DOCUMENTED` dans les pages accessibles (`/developers/imagine/video` → 404). REQUIRES VERIFICATION.**

---

## 2.5 OpenAI

Sources : https://developers.openai.com/api/docs/models.md, `/api/docs/pricing`, `/api/docs/api-reference/videos`, `/api/docs/api-reference/models`

### Vidéo
`sora-2`, `sora-2-pro` — snapshots documentés dans l'enum de `/v1/videos` : `sora-2-2025-10-06`, `sora-2-pro-2025-10-06`, `sora-2-2025-12-08`.

### Image
`gpt-image-2`, `gpt-image-1.5`, `gpt-image-1`, `gpt-image-1-mini`, `chatgpt-image-latest`.

### Texte (extraits pertinents)
Flagship : `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna` (+ alias `gpt-5.6` = sol).
Série 5 : `gpt-5`, `gpt-5-mini`, `gpt-5-nano`, `gpt-5-pro`, `gpt-5-codex`, `gpt-5.1*`, `gpt-5.2*`, `gpt-5.3*`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.4-nano`, `gpt-5.4-pro`, `gpt-5.5`, `gpt-5.5-pro`, `gpt-5.6-cyber`.
Legacy : `gpt-4o`, `gpt-4o-mini`, `gpt-4.1*`, `gpt-4*`, `gpt-3.5-turbo`, série `o1`/`o3`/`o4-mini`.

### Audio
TTS : `gpt-4o-mini-tts`, `tts-1`, `tts-1-hd`.
STT : `gpt-transcribe`, `gpt-live-transcribe`, `gpt-4o-transcribe`, `gpt-4o-mini-transcribe`, `gpt-4o-transcribe-diarize`, `whisper`.
Realtime : `gpt-realtime`, `gpt-realtime-1.5`, `gpt-realtime-2`, `gpt-realtime-2.1`, `gpt-realtime-2.1-mini`, `gpt-realtime-translate`, `gpt-realtime-whisper`, `gpt-realtime-mini` (**Deprecated**).

### Embeddings / modération
`text-embedding-3-large`, `text-embedding-3-small`, `text-embedding-ada-002`, `omni-moderation-latest`, `text-moderation-latest`, `text-moderation-stable`.

---

## 2.6 Krea (agrégateur)

Source : https://www.krea.ai/docs/llms.txt
Pattern d'endpoint : `POST /generate/{image|video}/{provider}/{model-id}`.
Catalogue vidéo : `kling-1.0 → 3.0`, `kling-o1`, `hailuo`, `hailuo-02`, `hailuo-23`, `hailuo-23-fast`, `wan-21/22/25`, `veo-2`, `veo-3`, `veo-3-fast`, `veo-31`, `veo-31-fast`, `veo-31-lite`, `gemini-omni-flash`, `seedance-pro`, `seedance-pro-fast`, `seedance-20*`, `seedance-20-fast*`, `seedance-20-mini`, `ltx-video-2.3-22b`, `vidu-q3`, `ray-2`, `runway-gen-3/4/45`, `runway-aleph`, `grok-imagine`, `grok-imagine-15`.
Catalogue image : krea-2-medium/large/medium-turbo, flux, flux-kontext, flux-11-pro(-ultra), nano-banana / -2 / -2-lite / -pro, ideogram-20a-turbo, ideogram-30, imagen-3/4/4-fast/4-ultra, runway-gen-4, chatgpt-image, chatgpt-2, luma-uni-1, seedream-4 / -5-lite / -5-pro, qwen-2512, z-image, seededit.

---

## 2.7 ElevenLabs

Sources : https://elevenlabs.io/docs/models, https://elevenlabs.io/docs/api-reference/models/list

| Model ID | Type | Langues | Limite caractères | Latence | Statut |
|---|---|---|---|---|---|
| `eleven_v3` | TTS expressif | 70+ | 5 000 | — | Current |
| `eleven_ttv_v3` | Text-to-Voice | 70+ | — | — | Current |
| `eleven_multilingual_v2` | TTS | 29 | 10 000 | — | Current |
| `eleven_flash_v2_5` | TTS temps réel | 32 | 40 000 | ~75 ms | Current |
| `eleven_flash_v2` | TTS temps réel | EN | 30 000 | ~75 ms | Current |
| `eleven_multilingual_v1` | TTS | — | 10 000 | — | superseded |
| `eleven_turbo_v2_5` | TTS | 32 | — | — | **Deprecated** → flash_v2_5 |
| `eleven_turbo_v2` | TTS | EN | — | — | **Deprecated** → flash_v2 |
| `scribe_v2` | STT | 90+ | — | — | Current (diarisation ≤ 32 locuteurs, 65 types d'entités, keyterms ≤ 1000) |
| `scribe_v2_realtime` | STT streaming | 90+ | — | ~150 ms | Current |
| `scribe_v1` | STT | 90+ | — | — | **Deprecated** |
| `eleven_multilingual_sts_v2` | Voice changer | 29 | — | — | Current |
| `eleven_english_sts_v2` / `_v1` | Voice changer | EN | 10 000 | — | Current / superseded |
| `eleven_multilingual_ttv_v2` | Voice design | 29 | — | — | Current |
| `eleven_text_to_sound_v2` | SFX | — | — | — | Current |
| `music_v2` / `music_v1` | Musique | EN/ES/DE/JA+ | — | — | Current / superseded |

---

## 2.8 ByteDance / BytePlus ModelArk

Source : https://docs.byteplus.com/en/docs/ModelArk/1330310 (Model list, mise à jour 7 août 2026)

### Vidéo

| Model ID | Capacités | Sortie | Rate limits (default) |
|---|---|---|---|
| `dreamina-seedance-2-5-260628` | **Multimodal reference-to-video**, reference-to-video, **video editing**, **video extension**, I2V first+last, I2V first, T2V | 480p, 720p · 24 fps · **4–30 s** · .mp4/.mov | ent. 600 RPM / 10 conc. — indiv. 180 RPM / 3 conc. |
| `dreamina-seedance-2-0-260128` | idem | 480p, 720p, 1080p, **4K (10-bit)** · 24 fps · 4–15 s | idem ; 4K : 15 RPM / 1 conc. |
| `dreamina-seedance-2-0-fast-260128` | idem | 480p, 720p · 24 fps · 4–15 s | idem |
| `dreamina-seedance-2-0-mini-260615` | idem | 480p, 720p · 24 fps · 4–15 s | idem |
| `seedance-1-5-pro-251215` | I2V first+last, I2V first, T2V | 480p/720p/1080p · 24 fps · 4–12 s | 600 RPM / 10 conc. ; flex 500B TPD |
| `seedance-1-0-pro-250528` | I2V first+last, I2V first, T2V | 480p/720p/1080p · 24 fps · 2–12 s | idem |
| `seedance-1-0-pro-fast-251015` | I2V first, T2V | 480p/720p/1080p · 24 fps · 2–12 s | idem |

Capacités Omni **Seedance 2.5** : 0–30 images de réf, 0–10 vidéos de réf, 0–10 audios de réf, prompt optionnel ; **entrée audio seule supportée**.
Capacités Omni **Seedance 2.0** : 0–9 images, 0–3 vidéos, 0–3 audios ; audio seul **non** supporté (au moins 1 image ou vidéo requise).

### Image

| Model ID | Capacités | Rate limit |
|---|---|---|
| `dola-seedream-5-0-pro-260628` | T2I, single I2I, multi-reference I2I | 500 IPM |
| `seedream-5-0-lite-260128` | + batch | 500 IPM |
| `seedream-4-5-251128` | + batch | 500 IPM |
| `seedream-4-0-250828` | + batch | 500 IPM |
| `seededit-3-0-i2i-250628` | édition I2I | (tarifé) |

### LLM (extrait)
`dola-seed-2-1-turbo-260628`, `seed-2-0-pro-260328`, `seed-2-0-lite-260428/260228`, `seed-2-0-mini-260428/260215`, `seed-2-0-code-preview-260328`, `seed-1-8-251228`, `seed-1-6-250915/250615`, `seed-1-6-flash-250715/250615`, `glm-5-2-260617`, `glm-4-7-251222`, `deepseek-v4-pro-260425`, `deepseek-v4-flash-260425`, `deepseek-v4-flash-ga-260731`, `deepseek-v3-2-251201`, `gpt-oss-120b-250805`.
Embeddings multimodaux : `skylark-embedding-vision-251215`, `-250615`.
3D : `Hyper3d-Rodin-Gen2`, `Hitem3d-2.0`.

---

## 2.9 Alibaba Cloud Model Studio

Sources : https://www.alibabacloud.com/help/en/model-studio/image-to-video-api-reference, `/text-to-video-api-reference`, `/what-is-model-studio`, `/model-pricing`

### Vidéo (Wan)

| Model ID | Résolutions | Durée | Audio input |
|---|---|---|---|
| `wan2.7-t2v`, `wan2.7-t2v-2026-06-12` | 720P, 1080P (défaut 1080P) | 2–15 s (défaut 5) | `audio_url` WAV/MP3 2–30 s ≤ 15 MB |
| `wan2.6-i2v`, `wan2.6-i2v-flash`, `wan2.6-i2v-us` | 720P, 1080P | 2–15 s (défaut 5) | oui (2.6/2.5) ; `shot_type: single\|multi` |
| `wan2.5-i2v-preview` | 480P, 720P, 1080P | 5 ou 10 s | oui |
| `wan2.2-i2v-plus`, `wan2.2-i2v-flash` | flash : 480P/720P | fixe 5 s | non |
| `wan2.1-i2v-turbo`, `wan2.1-i2v-plus` | turbo : 480P/720P | 3, 4, 5 s | non |

Prompt : 1500 caractères (2.6/2.5), 800 (2.2/2.1). Image : JPEG/PNG/BMP/WEBP, 240–8000 px, 20 MB (2.6/2.5) ou 10 MB (2.2/2.1).
**URL vidéo valable 24 h seulement.**

### Image
`qwen-image-2.0-pro`, `qwen-image-2.0`, `qwen-image-max`, `qwen-image-plus`, `qwen-image` ; édition : `qwen-image-edit-max`, `qwen-image-edit-plus`, `qwen-image-edit`.

---

## 2.10 Google Gemini API

Sources : https://ai.google.dev/gemini-api/docs/models, `/docs/veo`, `/docs/pricing`, https://ai.google.dev/api/models

### Vidéo
| Model ID | Statut |
|---|---|
| `veo-3.1-generate-preview` | **Preview** |
| `veo-3.1-fast-generate-preview` | **Preview** |
| Veo 3.1 Lite | **Preview** — ID exact `REQUIRES VERIFICATION` |
| `gemini-omni-flash` | **Preview** |

Paramètres Veo : `aspectRatio` `16:9` (défaut) / `9:16` ; `resolution` `720p` (défaut) / `1080p` / `4k` (1080p et 4k → 8 s obligatoires ; 4k indisponible sur Lite) ; `durationSeconds` 4 / 6 / 8 ; `personGeneration` `allow_all` / `allow_adult` ; entrées `image`, `lastFrame`, `referenceImages` (**max 3**), `video` (extension).
**Audio natif** sur toutes les variantes Veo 3.1. 24 fps. 1 vidéo par requête. **Fichiers conservés 2 jours.**

### Image
`gemini-3.1-flash-image` (Nano Banana 2, stable), `gemini-3.1-flash-lite-image` (Nano Banana 2 Lite, stable), `gemini-3-pro-image` (Nano Banana Pro, stable), `gemini-2.5-flash-image` (Nano Banana, stable), `imagen-4.0-generate` (**DEPRECATED — arrêt 17 août 2026**).

### Texte
Stable : `gemini-3.6-flash`, `gemini-3.5-flash`, `gemini-3.5-flash-lite`, `gemini-3.1-flash-lite`, `gemini-2.5-pro`, `gemini-2.5-flash`, `gemini-2.5-flash-lite`.
Preview : `gemini-3.1-pro-preview`, `gemini-3-flash-preview`.

### TTS
`gemini-2.5-flash-preview-tts`, `gemini-2.5-pro-preview-tts` (stable) ; `gemini-3.1-flash-tts-preview` (preview).

---

## 2.11 Bria AI

Sources : https://docs.bria.ai/, `/image-generation/endpoints/*`, https://bria.ai/pricing

Familles : **Fibo** (génération), Fibo Lite, Fibo Structured Prompt, Fibo Edit, Image Editing (background removal / generation, gen fill, eraser, expansion, increase resolution), Product Shot Editing, **Video Editing** (removal/replacement/green screen, resolution, eraser), Tailored Generation (modèles sur mesure), Ads Generation, Attribution Service.
Numéros de version des modèles : `NOT DOCUMENTED` sur les pages accessibles.
Argument différenciant officiel : **indemnisation IP** (plafonnée en PAYG, illimitée en Enterprise) — modèles entraînés sur données licenciées.

---

## 2.12 Black Forest Labs

Sources : https://docs.bfl.ml/llms.txt, `/flux_3/flux3_video.md`, `/flux_2/flux2_overview.md`, `/quick_start/pricing.md`, https://api.bfl.ai/openapi.json

### Vidéo — FLUX 3
Endpoint unique `POST /v1/flux-3-video`, avec 4 modes exclusifs :
| Mode | Entrée requise | Capacité |
|---|---|---|
| `t2v` | `prompt` | text-to-video |
| `i2v` | `keyframes` (URL/base64, 1 image = départ, 2 = départ+fin, paires `[secondes, image]` = ancrage temporel) | image-to-video, first/last frame, keyframes datés |
| `v2v` | `start_video` (mp4 URL/base64) | **continuation de vidéo** |
| `draft_enhance` | `draft_cache` | re-rendu haute qualité d'un draft |

`resolution` : `hd` (défaut) / `fhd`. `duration` : 5–20 s entiers, ou `auto` (défaut). `aspect_ratio` : `auto`, `21:9`, `2:1`, `16:9`, `4:3`, `1:1`, `3:4`, `9:16`. `generate_audio` : **true par défaut**. `safety_tolerance` 0–4 (défaut 2). `draft` bool.

### Image — FLUX.2 / FLUX.1
Endpoints : `/v1/flux-2-max`, `/v1/flux-2-pro`, `/v1/flux-2-pro-preview`, `/v1/flux-2-flex`, `/v1/flux-2-klein-9b`, `/v1/flux-2-klein-9b-preview`, `/v1/flux-2-klein-4b`, `/v1/flux-pro-1.1` + ultra, `/v1/flux-kontext-pro`, `/v1/flux-kontext-max`, `/v1/flux-dev`, fill/expand, outpaint, erase, deblur, **virtual try-on** (v1 et v2), finetunes.
Références multiples : **klein ≤ 4**, **max/pro/flex ≤ 8 en API** (10 en playground), dev recommandé ≤ 6. Sortie jusqu'à **4 MP**.
Corps FLUX.2 [pro] : `prompt`, `input_image` → `input_image_8`, `width`/`height` (min 64), `seed`, `safety_tolerance` 0–5 (défaut 2), `output_format` jpeg/png/webp, `disable_pup`, `webhook_url` (≤ 2083 car.), `webhook_secret`.

---

## 2.13 VEED — `NOT AVAILABLE AS A DIRECT API`

Modèles annoncés (mais servis par fal.ai) : **Fabric 1.0** (image→vidéo animée par audio + prompt), **Lip Sync 2.0** (video→video), Subtitles, Green Screen, Background Removal. **Live Avatar API : WAITLIST.**

---

## 2.14 HeyGen

Sources : https://developers.heygen.com/reference/create-video.md, `/models.md`, `/avatar-iv.md`, `/docs/pricing.md`, `/llms.txt`

### Moteurs d'avatar (paramètre `engine.type` sur `POST /v3/videos`)

| Engine | Valeur API | Sujets supportés | Spécificités |
|---|---|---|---|
| Avatar V | `avatar_v` | Digital Twin | opt-in explicite + éligibilité ; `motion_prompt`, cross-reference animation |
| **Avatar IV** | `avatar_iv` | Digital Twin, Photo Avatar, Studio Avatar, **image arbitraire**, prompt | **défaut pour les nouvelles intégrations** ; `motion_prompt` (gestes/mains en langage naturel), `expressiveness` high/medium/low (défaut low) |
| Avatar III | `avatar_iii` | Digital Twin, Photo Avatar, Studio Avatar | opt-in ; **sortie 4K** ; pas de `motion_prompt` |
| Cinematic Avatar | `type: "cinematic_avatar"` | 1–3 look IDs + références (images/vidéos/audio) | 4–15 s ou `auto_duration`, 720p/1080p, 16:9 / 9:16 / 1:1 |

Types de job racine : `avatar`, `image`, `cinematic_avatar`, `studio` (scènes ordonnées).
Résolutions : `4k` / `1080p` / `720p`. Ratios : `16:9`, `9:16`, `4:5`, `5:4`, `1:1`, `auto`.
Voix : `voice_id` + `voice_settings` (speed, pitch, volume, locale, engine_settings), ou `audio_url` / `audio_asset_id`.
Autres : `background` (color/image), `remove_background`, `output_format` mp4/webm, `caption` (SRT), `watermark`, `callback_url`, `callback_id`, header `Idempotency-Key` (24 h).

### Autres familles d'endpoints
Lipsync (speed / precision), Video Translation, Voices (search, design, clone, generate speech), Photo Avatar, Avatar consent/groups/looks, Templates, HyperFrames, Batch (videos, translations, lipsyncs, assets), AI Clipping, Filler-word removal, Brand kits/glossary, Proofread, Webhooks complets (endpoints, event types, signing secret rotation).

---

## 2.15 Luma AI

Sources : https://docs.lumalabs.ai/docs/video-generation.md, `/reference/creategeneration.md`, `/reference/generateimage.md`, https://lumalabs.ai/api/pricing

### Vidéo
Endpoints : `POST /dream-machine/v1/generations` (guide) et `POST /dream-machine/v1/generations/video` (référence).
`model` (requis) : **`ray-2`** ou **`ray-flash-2`**.
`resolution` : `540p` / `720p` / `1080p` / `4k`. `duration` : `"5s"` / `"9s"`. `aspect_ratio` : `1:1`, `16:9`, `9:16`, `4:3`, `3:4`, `21:9`, `9:21` (défaut 16:9).
`keyframes.frame0/frame1` : `{type:"image", url}` **ou** `{type:"generation", id}` → extension, reverse-extension, interpolation entre deux générations.
`concepts[]` (styles, liste via `/generations/concepts/list`), `loop`, `callback_url`.
États : `queued` → `dreaming` → `completed` / `failed`.

Prix (page Ray2) : **`ray-flash-2` 0,015 $/s en 720p, 0,03 $/s en 1080p** ; **`ray-2` 0,048 $/s en 720p, 0,096 $/s en 1080p**. Ce sont les deux lignes retenues dans `pricing.json`, l'app demandant du 720p.

⚠️ **Écart doc/pricing** : la grille tarifaire officielle facture **Ray3.2** et **Uni-1.1 / Uni-1.1 Max**, alors que l'API reference n'énumère que `ray-2` / `ray-flash-2` et `photon-1` / `photon-flash-1`. Les identifiants API de Ray 3.2 et Uni-1.1 sont **`REQUIRES VERIFICATION`**. Luma présente par ailleurs Ray2 comme « available in the Luma API soon » : une requête sur cet id peut être refusée par le compte avant d'être facturée. Luma redirige aussi vers `docs.agents.lumalabs.ai` (404 sur `llms.txt`).

### Image
`POST /dream-machine/v1/generations/image` — `model` : `photon-1` / `photon-flash-1` ; `image_ref[]` (url+weight), `style_ref[]`, `character_ref.identity0.images[]`, `modify_image_ref`, `aspect_ratio`, `format` jpg/png, `sync`, `sync_timeout`, `callback_url`.

Autres endpoints : `listgenerations`, `getgeneration`, `deletegeneration`, `upscalegeneration`, `addaudiotogeneration`, `reframeimage`, `reframevideo`, `modifyvideo`, `getconcepts`, `getcredits`, `ping`.

---

## 2.16 Ideogram

Sources : https://developer.ideogram.ai/ideogram-api/api-overview, `/api-reference/api-reference/generate-v4.md`, `/generate-v3.md`, https://ideogram.ai/api-pricing

| Endpoint | Méthode | Notes |
|---|---|---|
| `POST /v1/ideogram-v4/generate` | multipart | `text_prompt` **ou** `json_prompt` (exclusifs), `resolution`, `rendering_speed` (**`FLASH` renvoie 400 actuellement**), `enable_copyright_detection` |
| `POST /v1/ideogram-v4/generate` (async) | | variante asynchrone |
| `POST /v1/ideogram-v3/generate` | multipart | `prompt`, `aspect_ratio`, `resolution` (~70 valeurs énumérées de 512×1536 à 1536×640), `rendering_speed`, `magic_prompt`, `style_type` (`AUTO`, `GENERAL`, `REALISTIC`, `DESIGN`, `FICTION`), `num_images`, `seed`, `negative_prompt`, `style_reference_images` (JPEG/PNG/WebP ≤ 10 MB), **`character_reference_images` + `character_reference_images_mask`**, `color_palette`, `style_codes` (hex 8 car.), `style_preset`, `custom_model_uri` (`model/<name>/version/<version>`) |
| `/v1/ideogram-v3/generate-transparent`, `/remix-v4`, `/remix-v3`, `/inpaint-v3`, `/reframe-v3`, `/replace-background-v3`, `/edit-with-prompt`, `/upscale`, `/describe-v4`, `/magic-prompt-v4`, `/remove-background`, `/remove-object`, `/layerize-text-v3`, `/resize-ad-async`, `/get-generation` | | + entraînement de modèles custom (datasets, train, list, get) |

Réponse : `created`, `data[]` avec `prompt`, `resolution`, `is_image_safe`, `seed`, `url`, `style_type`.
OpenAPI officiel : https://developer.ideogram.ai/openapi.json

---

## 2.17 PixVerse

Sources : https://docs.platform.pixverse.ai/llms.txt, `/model-overview-2140345m0.md`, `/pricing-796039m0.md`, `/image-to-video-generation-13016633e0.md`

| Model | Capacités | Durées | Qualités |
|---|---|---|---|
| **C1** | T2V, I2V, transition, reference-to-video / Fusion — « cinematic and reference-based » | 1–15 s | 360p, 720p, 1080p |
| **V6** | T2V, I2V, transition, **video extension**, Fusion — « general generation and production » | 1–15 s | 360p, 540p, 720p, 1080p |
| v5.6, v5.5, v5, v4.5, v4, v3.5 | legacy (toujours acceptés par l'enum `model`) | 5 ou 8 s | 360p→1080p |

Capacités transverses : Restyle, Swap (+ swap mask), Mimic / Motion control, Modify, Sound Effects, **Lip Sync (TTS intégré)**, Image Template, Upscale video, **Avatar**, Viral Recreation Agent, Multi-transition.

Body `POST /openapi/v2/video/img/generate` : `model`, `img_id` (obtenu via upload), `prompt` (≤ 5000), `duration`, `quality`, `seed` (0–2147483647), `template_id`, `img_ids[]`, `generate_audio_switch` (v5.5/5.6/v6/c1), `generate_multi_clip_switch` (v5.5/v6), `sound_effect_switch` + `sound_effect_content` (v5 et moins), `lip_sync_tts_switch` + `lip_sync_tts_content` (~140 car. UTF-8) + `lip_sync_tts_speaker_id` (v5 et moins).

---

# Section 3 — All endpoints

## Kling AI
| Méthode | URL | Rôle |
|---|---|---|
| POST | `https://api-beijing.klingai.com/image-to-video/kling-3.0` | I2V 3.0 |
| POST | `.../image-to-video/kling-3.0-turbo` | I2V 3.0 Turbo |
| POST | `.../text-to-video/kling-3.0[-turbo]` | T2V |
| POST | `.../omni-video/kling-3.0-omni` | Omni (réfs image/vidéo/sujet + édition vidéo) |
| POST | `.../v1/videos/avatar/image2video` | Digital human (lip-sync) |
| GET | `.../v1/videos/avatar/image2video/{task_id}` | statut avatar |
| GET | `.../v1/videos/avatar/image2video?pageNum&pageSize` | liste avatar |
| GET | `.../tasks?task_ids=` ou `?external_task_ids=` | statut (batch, séparateur `,`) |
| POST | `.../tasks` | liste par curseur (`start_time`, `end_time`, `cursor`, `limit` ≤ 500, `filters` sur `status` / `product_type`) |

Auth : `Authorization: Bearer <API Key>` + `Content-Type: application/json`. Ancien schéma AK/SK (JWT) : **legacy**, réservé aux endpoints de l'ancien standard (ceux où la version est dans `model_name`).
Async : oui. Polling **et** `callback_url` (protocole Callback documenté).
Statuts : `submitted` → `processing` → `succeeded` / `failed`.
Réponse enrichie d'un bloc `billing[]` (`charge_type` cash/unit, `amount`, `list_price`) → **coût réel récupérable par API**.

## MiniMax
| Méthode | URL |
|---|---|
| POST | `https://api.minimax.io/v2/video_generation` (H3) |
| GET | `https://api.minimax.io/v2/query/video_generation/{task_id}` |
| POST | `https://api.minimax.io/v1/video_generation` (Hailuo legacy) |
| POST | `https://api.minimax.io/v1/t2a_v2` (TTS ; miroir `https://api-uw.minimax.io/v1/t2a_v2`) |
| — | WebSocket T2A, async long-text T2A (create/query) |
| — | voice cloning (upload clone audio, upload prompt, clone), voice design, voice get/delete |
| — | image T2I / I2I, music generation, lyrics, music cover preprocess |
| — | files : upload, list, retrieve, retrieve content, delete |
| GET | `/v1/models` (compat OpenAI) et liste modèles compat Anthropic |

Auth : Bearer. Async + `callback_url`. Erreurs normalisées : 400/401/402/422/429/500 avec `{type, error:{type,message,http_code}, request_id}`.

## LTX
| Méthode | URL |
|---|---|
| POST | `https://api.ltx.io/v2/text-to-video` · `/v2/image-to-video` · `/v2/audio-to-video` · `/v2/retake` · `/v2/extend` |
| POST | versions async : `submit-*` + `/v2/video-to-video-hdr`, `/v2/video-to-video-reframe` |
| GET | `https://api.ltx.io/v2/image-to-video/{id}` (poll → `result.video_url`) |
| POST | upload : `create-upload` |

Auth : `Authorization: Bearer` (base documentée `https://api.ltx.io/v1` sur la page auth, endpoints en `/v2`). Réponse création : **202** `{id, created_at}`. Erreur auth : 401 `authentication_error`. OpenAPI : https://docs.ltx.io/openapi.json

## xAI
Base `https://api.x.ai/v1`, Bearer. APIs : Responses, Voice, Imagine Images (generate/edit), Imagine Video (generate/edit), Code. **Chemins exacts : REQUIRES VERIFICATION** (pages `/developers/imagine/*` non accessibles). Rate limits : `NOT DOCUMENTED`.

## OpenAI — Videos API
| Méthode | Path | Rôle |
|---|---|---|
| POST | `/videos` | créer (`prompt` requis, `model`, `seconds` `"4"\|"8"\|"12"`, `size` `720x1280\|1280x720\|1024x1792\|1792x1024`, `input_reference` `{file_id}` ou `{image_url}`) |
| GET | `/videos` | lister (`after`, `limit`, `order`) |
| GET | `/videos/{video_id}` | statut |
| DELETE | `/videos/{video_id}` | supprimer |
| GET | `/videos/{video_id}/content?variant=video\|thumbnail\|spritesheet` | télécharger |
| POST | `/videos/{video_id}/remix` | remix (`prompt`) |
| POST | `/videos/edits` | éditer (`prompt`, `video.id`) |
| POST | `/videos/extensions` | étendre (`seconds` `"4"\|"8"\|"12"\|"16"\|"20"`, `video.id`) |
| POST | `/videos/characters` · GET `/videos/characters/{id}` | **cameo / personnage depuis une vidéo** |
| GET | `/models`, `/models/{model}`, DELETE `/models/{model}` | découverte dynamique |

Statuts : `queued` → `in_progress` → `completed` / `failed` ; champ `progress`, `expires_at`, `remixed_from_video_id`.

## ElevenLabs
`POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id}` — header `xi-api-key` ; query `output_format` (défaut `mp3_44100_128`), `enable_logging`, `optimize_streaming_latency` 0–4 ; body `text`, `model_id` (défaut `eleven_multilingual_v2`), `language_code`, `voice_settings` {`stability` 0.5, `similarity_boost` 0.75, `use_speaker_boost` true, `style` 0, `speed` 1}, `previous_text`, `next_text`, `seed`, `apply_text_normalization`.
`GET /v1/models` — découverte dynamique, renvoie `model_id`, flags `can_do_text_to_speech`, `can_do_voice_conversion`, `can_use_style`, `can_use_speaker_boost`, `serves_pro_voices`, `requires_alpha_access`, `token_cost_factor`, `max_characters_request_*`, `languages[]`, `model_rates.character_cost_multiplier`, `concurrency_group`.
Résidence de données : `api.elevenlabs.io`, `api.us.elevenlabs.io`, `api.eu.residency.elevenlabs.io`, `api.in.residency.elevenlabs.io`, `api.sg.residency.elevenlabs.io`.
*(Variante `/with-timestamps` : non listée sur la page consultée → `REQUIRES VERIFICATION`.)*

## BytePlus ModelArk
| Méthode | URL |
|---|---|
| POST | `https://ark.ap-southeast.bytepluses.com/api/v3/contents/generations/tasks` |
| GET | retrieve / list / cancel-delete video generation task (même racine) |
| POST | Image generation API, 3D API, Embeddings multimodal, Chat API, Responses API, Files API, Batch, Context caching, Managed Agents, Tokenization |

Auth : `Authorization: Bearer $ARK_API_KEY`. Compatible OpenAI API (endpoints dédiés).
Body vidéo : `model`, `content[]`, `callback_url`, `return_last_frame`, `service_tier` (`default`), `execution_expires_after` (défaut 172800 s), `generate_audio` (défaut true), `draft` (défaut false), `safety_identifier`, `priority`, `resolution`, `ratio`, `duration`, `omni_reference_task_type` (défaut `auto`), `frames`, `output_format` (défaut mp4), `seed` (défaut -1), `camera_fixed` (défaut false), `watermark` (défaut false). Réponse : `{id}`.
Adressage des références dans le prompt : `@Image1`, `@Video1`, … (identique au schéma déjà utilisé dans Market Queen via fal).

## Alibaba Model Studio
POST `https://{WorkspaceId}.<region>.maas.aliyuncs.com/api/v1/services/aigc/video-generation/video-synthesis`
Headers : `Content-Type: application/json`, `Authorization: Bearer $DASHSCOPE_API_KEY`, **`X-DashScope-Async: enable` (obligatoire)**.
Poll : `GET .../api/v1/tasks/{task_id}` → `PENDING` → `RUNNING` → `SUCCEEDED`/`FAILED`.
Mode compatible OpenAI : `.../compatible-mode/v1`.

## Google Gemini
`POST https://generativelanguage.googleapis.com/v1beta/models/{model}:predictLongRunning` (Veo), puis polling `operations.get`.
`GET /v1beta/models?pageSize=&pageToken=` et `GET /v1beta/{name=models/*}` — découverte dynamique (`supportedGenerationMethods` permet de filtrer par capacité). Auth `key=$GEMINI_API_KEY`.

## Bria
`POST https://engine.prod.bria-api.com/v2/image/generate` — header `api_token`. Combinaisons d'entrée exclusives : `prompt` | `images` | `images`+`prompt` | `structured_prompt` | `structured_prompt`+`prompt`, + `seed`. Réponse : `image_url` + `structured_prompt` (JSON réutilisable → régénération déterministe).
Rate limits : Free Trial 10 rpm/endpoint · Starter 60 rpm · Pro & Enterprise 1000 rpm.

## Black Forest Labs
`POST https://api.bfl.ai/v1/{endpoint}` avec header `x-key`. Réponse `{id, polling_url, cost?, input_mp?, output_mp?}` ou variante webhook `{id, status, webhook_url, …}`. Poll `polling_url` jusqu'à `Ready` ; autres statuts : `Error`, `Request Moderated`, `Content Moderated`. `GET /v1/get_result`, `GET` crédits, finetunes (details/list/delete). OpenAPI : https://api.bfl.ai/openapi.json
**Le coût est renvoyé dans la réponse de création** (`cost`) → estimation exacte sans table locale.

## HeyGen
`POST https://api.heygen.com/v3/videos` ; `GET /v3/videos/{id}`, list, delete ; lipsync CRUD ; video translation CRUD ; voices (list/get/clone/design/generate-speech) ; assets upload ; webhooks (create/list/update/delete/rotate secret/event types) ; batch. OpenAPI : https://developers.heygen.com/openapi/external-api.json

## Luma / Ideogram / PixVerse
Voir §2.15, §2.16, §2.17. PixVerse : `POST https://app-api.pixverse.ai/openapi/v2/video/img/generate`, headers `API-KEY` + `Ai-trace-id` (UUID unique par requête) ; statut via `get-video-generation-status` ; **webhooks documentés** ; upload image / upload video-audio ; `get-user-credit-balance`.

---

# Section 4 — Pricing

> Prix conservés dans la devise et l'unité natives du fournisseur.

## 4.1 Vidéo — comparatif normalisé (référence : 5 s, 1080p, avec audio quand disponible)

| Fournisseur | Modèle | Tarif natif | ≈ coût 5 s |
|---|---|---|---|
| **BytePlus** | Seedance 2.0 mini (promo -60 %) | 3,5 $/M tokens (liste) | **~0,15 $** (720p, ~0,03 $/s) |
| **BytePlus** | Seedance 2.0 fast (promo -25 %) | 5,6 $/M tokens (liste) | ~0,45 $ (720p, ~0,09 $/s) |
| **LTX** | ltx-2-3-fast | 0,03–0,24 $/s (720p→4K) | 0,15 $ (720p) |
| **LTX** | ltx-2-3-pro | 0,04–0,32 $/s | 0,20 $ (720p) |
| **LTX** | ltx-2-5-fast | 0,09–0,30 $/s | 0,45 $ (720p) |
| **LTX** | ltx-2-5-pro | 0,12–0,17 $/s | 0,60–0,85 $ |
| **xAI** | grok-imagine-video | 0,050 $/s | 0,25 $ |
| **xAI** | grok-imagine-video-1.5 | 0,080 $/s | 0,40 $ |
| **Luma** | Ray3.2 T2V/I2V 1080p | 1,20 $ / 5 s | 1,20 $ (540p : 0,15 $) |
| **Google** | Veo 3.1 Lite | 0,05 $/s (720p), 0,08 $/s (1080p) | 0,40 $ (1080p) |
| **Google** | Veo 3.1 Fast | 0,10 $/s (720p), 0,12 $/s (1080p), 0,30 $/s (4K) | 0,60 $ |
| **Google** | Veo 3.1 | 0,40 $/s (720p/1080p), 0,60 $/s (4K) | 2,00 $ |
| **OpenAI** | sora-2 (720p) | 0,10 $/s (batch 0,05) | 0,50 $ |
| **OpenAI** | sora-2-pro | 0,30 $/s (720p), 0,70 $/s (1080p) | 1,50 $ / 3,50 $ |
| **BFL** | FLUX 3 video full | 0,17 $/s HD, 0,29 $/s FHD | 0,85 $ / 1,45 $ |
| **BFL** | FLUX 3 video draft | 0,06 $/s | 0,30 $ |
| **BFL** | FLUX 3 continuation full | 0,43 $/s HD, 0,54 $/s FHD | 2,15 $ / 2,70 $ |
| **BytePlus** | Dreamina Seedance 2.5 | 10,70 $/M tokens (sans vidéo en entrée) / 6,40 (avec) | 720p 16:9 : **1,156 $** (0,231 $/s) ; 480p : 0,514 $ |
| **BytePlus** | Seedance 1.0 pro | 2,5 $/M tokens (offline 1,25) | selon résolution |
| **BytePlus** | Seedance 1.5 pro | 2,4 $/M avec audio, 1,2 sans (offline ÷2) | selon résolution |
| **Kling** (CN) | Kling 3.0 muet | 0,6 ¥/s (720p), 0,8 (1080p), 3,0 (4K) | 4,0 ¥ (1080p) |
| **Kling** (CN) | Kling 3.0 avec voix | 0,9 ¥/s (720p), 1,2 (1080p), 3,0 (4K) | 6,0 ¥ |
| **Kling** (CN) | Kling 3.0 Turbo (avec son) | 0,8 ¥/s (720p), 1,0 (1080p) | 5,0 ¥ |
| **Kling** (CN) | Kling 3.0 Omni sans vidéo réf, sans son | 0,6 / 0,8 / 3,0 ¥/s | 4,0 ¥ |
| **Kling** (CN) | Kling 3.0 Omni avec vidéo réf, sans son | 0,9 / 1,2 / 3,0 ¥/s | 6,0 ¥ |
| **Kling** (CN) | Kling 2.6 muet | 0,3 / 0,5 ¥/s | 2,5 ¥ |
| **Kling** (CN) | Kling 2.5 Turbo muet | 0,3 / 0,5 ¥/s | 2,5 ¥ |
| **Kling** (CN) | Digital human | 0,4 ¥/s (720p), 0,8 (1080p) | 4,0 ¥ |
| **PixVerse** | V6 1080p sans audio | 18 crédits/s (23 avec audio) | 90 crédits (~0,90 $ à 10 $/1000 cr.) |
| **PixVerse** | V6 720p sans audio | 9 crédits/s (12 avec audio) | 45 crédits |
| **PixVerse** | C1 1080p | 19 crédits/s (24 avec audio) | 95 crédits |
| **HeyGen** | Avatar IV Photo Avatar | 0,05 $/s | 0,25 $ |
| **HeyGen** | Avatar IV/V Digital Twin, Studio | 0,0667 $/s | 0,33 $ |
| **HeyGen** | Avatar III Digital Twin/Studio | 0,0167 $/s | 0,08 $ |
| **HeyGen** | Cinematic Avatar | **7,00 $ / vidéo** (forfait 4–15 s) | 7,00 $ |
| **VEED** (via fal) | Fabric 1.0 | 0,08–0,20 $/s | 0,40–1,00 $ |
| **VEED** (via fal) | Lip Sync 2.0 | 0,07 $/s | 0,35 $ |
| **MiniMax** | H3 | pay-as-you-go — **prix par vidéo/seconde `NOT DOCUMENTED`** sur les pages publiques | — |
| **MiniMax** | Hailuo (packages uniquement) | 1 pt = 768p/6s ; 2 pts = 1080p/6s ; 0,7 pt = 2.3-Fast 768p/6s | packages 1 000 $ / 3 760 pts → **~0,266 $/pt** |
| **Alibaba** | Wan | **`NOT DOCUMENTED`** sur la page model-pricing consultée | — |
| **Krea** (agrégateur) | Kling 3.0 std/pro/4k | 0,1764 / 0,2352 / 0,441 $/s (0,2646 / 0,3528 avec audio) | 0,88–2,21 $ |
| **Krea** (agrégateur) | LTX-2.3 22B | 0,1798 $ (5 s) → 0,7126 $ (20 s) ; +LoRA ~+12 % | 0,18 $ |

**Note MiniMax** : « Video packages support Hailuo video models. **MiniMax H3 is not supported yet** » → H3 en PAYG ou contact commercial.

## 4.2 Image

| Fournisseur | Modèle | Prix |
|---|---|---|
| BytePlus | `dola-seedream-5-0-pro` | 0,045 $/img (≤ 2,36 MP) · 0,09 $ au-delà ; 1re image d'entrée gratuite puis 0,003 $ |
| BytePlus | `seedream-5-0-lite` | 0,035 $/img (entrée gratuite) |
| BytePlus | `seedream-4-5` | 0,04 $/img |
| BytePlus | `seedream-4-0`, `seededit-3-0-i2i` | 0,03 $/img |
| BFL | FLUX.2 klein 4B | 0,014 $ + 0,001 $/MP |
| BFL | FLUX.2 klein 9B | 0,015 $ + 0,002 $/MP |
| BFL | FLUX.2 pro | à partir de 0,03 $/MP (édition 0,045) |
| BFL | FLUX.2 flex | 0,05–0,06 $/MP |
| BFL | FLUX.2 max | à partir de 0,07 $/MP |
| BFL | FLUX.1 Kontext pro / max | 0,04 $ / 0,08 $ |
| BFL | FLUX 1.1 pro / Ultra / Raw / Fill | 0,04 / 0,06 / 0,06 / 0,05 $ |
| Google | `gemini-2.5-flash-image` | 0,039 $/img (batch 0,0195) |
| Google | `gemini-3.1-flash-image` | 0,045–0,151 $/img selon résolution (batch 0,022–0,076) |
| Google | Imagen 4 (deprecated) | Fast 0,02 / Standard 0,04 / Ultra 0,06 $ |
| Ideogram | 4.0 Turbo / Default / Quality | 0,03 / 0,06 / 0,10 $ |
| Ideogram | 3.0 Flash·Turbo / Default / Quality | 0,03 / 0,06 / 0,09 $ |
| Ideogram | 3.0 **+ Character Reference** | 0,10 / 0,15 / 0,20 $ |
| Ideogram | Edit (instructional) / Describe / Describe V4 / Upscale | 0,20 / 0,01 / 0,015 / 0,06 $ |
| Bria | Fibo / Fibo Lite / Structured Prompt | 0,03 / 0,02 / 0,02 $ |
| Bria | Background removal | 0,018 $ · Eraser / Expansion / Increase resolution 0,02 $ · Fibo Edit / BG generation / Gen fill 0,03 $ |
| Bria | **Video editing** | 0,0225 $/s (removal, replacement, green screen) · 0,02 $/s (resolution, eraser) |
| Luma | Uni-1.1 / Uni-1.1 Max (2048 px) | T2I 0,0404 / 0,1000 $ · edit 0,0434 / 0,1030 · 1 réf 0,0434 / 0,1030 · 2 réfs 0,0464 / 0,1060 · 8 réfs 0,0644 / 0,1240 |
| Alibaba (SG) | qwen-image-2.0-pro / -max | 0,075 $/img (100 img offertes) |
| Alibaba (SG) | qwen-image-2.0 / qwen-image | 0,035 $/img |
| Alibaba (SG) | qwen-image-plus / edit-plus | 0,03 $/img · qwen-image-edit 0,045 $ |
| MiniMax | `image-01` | 0,0035 $/img |
| xAI | grok-imagine-image / -quality | 0,02 / 0,05 $/img |
| OpenAI | gpt-image-2 / 1.5 / 1 | facturé **au token** : entrée 8 / 8 / 10 $ par M, sortie 30 / 32 / 40 $ par M (batch -50 %) |
| OpenAI | **gpt-image-2, par image** | 1024² : low 0,006 · medium 0,053 · high 0,211 — 1024×1536 et 1536×1024 : low 0,005 · medium 0,041 · high 0,165. 2K / 4K : calculés aux tokens. Source : `developers.openai.com/api/docs/guides/image-generation` (guide, pas la page pricing) |

## 4.3 Audio / TTS / STT

| Fournisseur | Service | Prix |
|---|---|---|
| ElevenLabs | Flash / Turbo | 0,05 $ / 1 000 caractères |
| ElevenLabs | Multilingual v2 / v3 | 0,10 $ / 1 000 caractères |
| ElevenLabs | Scribe v2 | 0,22 $/h (+0,070 entity detection, +0,050 keyterms) |
| ElevenLabs | Scribe v2 Realtime | 0,39 $/h |
| ElevenLabs | Music / Voice changer / Voice isolator / SFX | 0,150 / 0,120 / 0,120 / 0,120 $ par minute |
| ElevenLabs | Dubbing v1 / v2 | 0,33–0,50 $/min / 2,20 $/min |
| ElevenLabs | Plans | Starter 6 $ · Creator 22 $ · Pro 99 $ · Scale 299 $ · Business 990 $ /mois |
| OpenAI | tts-1 / tts-1-hd | 15 $ / 30 $ par M caractères |
| OpenAI | gpt-4o-transcribe, Whisper | 0,006 $/min |
| Google | Gemini 2.5 Flash TTS | 0,50 $/M in (texte) → 10 $/M out (audio) — batch 0,25 / 5 |
| Google | Gemini 2.5 Pro TTS | 1,00 $/M in → 20 $/M out — batch 0,50 / 10 |
| Google | Gemini 3.1 Flash TTS preview | 1,00 $/M in → 20 $/M out |
| HeyGen | TTS (Starfish) | 0,000667 $/s |
| Kling (CN) | 语音合成 (synthèse) | 0,05 ¥/appel · SFX text/video 0,25 ¥ · voice cloning 0,05 ¥ · lip-sync 0,5 ¥/5 s |
| MiniMax | `speech-2.8-turbo` / `speech-2.8-hd` | **60 $ / 100 $ par M de caractères d'entrée** (PAYG, page `pricing-paygo`). Les paliers d'abonnement de `pricing-speech` sont une autre grille, pas la seule |

**Conversion des TTS Google vers le tarif au caractère.** Le reste de l'app
facture la voix off au caractère, Google au token audio. L'audio Gemini vaut
**25 tokens par seconde** (1 M de tokens ≈ 11,1 h), et le pipeline lit un script
à 2,6 mots/s d'environ 6 caractères — donc 1 000 caractères ≈ 64 s ≈ 1 600
tokens : **0,016 $ Flash, 0,032 $ Pro**. Le texte d'entrée s'ajoute à 0,50 /
1,00 $ par M de tokens, soit moins d'un dixième de centime pour une pub entière,
et n'est pas compté. La vitesse de lecture est la nôtre, pas celle de Google :
le chiffre est marqué `approx` dans `pricing.json`.

## 4.4 LLM (extraits utiles pour l'écriture de script)

| Modèle | Input / M | Cached / M | Output / M |
|---|---|---|---|
| `gemini-3.1-pro-preview` | 2,00 $ | 0,20 $ (cache) | 12,00 $ (réponse + raisonnement ; **pas** de free tier API) |
| `gemini-3.5-flash` | 1,50 $ | — | 9,00 $ (**free tier**) |
| `gemini-3.6-flash` | 1,50 $ | — | 7,50 $ (free tier) |
| `gemini-3.5-flash-lite` | 0,30 $ | — | 2,50 $ (free tier) |
| `gemini-2.5-flash` | 0,30 $ (audio 1,00) | — | 2,50 $ (free tier) |
| `gpt-5.6-luna` | 0,20 $ | 0,02 $ | 1,20 $ |
| `gpt-5.6-terra` | 2,00 $ | 0,20 $ | 12,00 $ |
| `gpt-5.6-sol` | 5,00 $ | 0,50 $ | 30,00 $ |
| `grok-4.5` (<200k) | 2,00 $ | 0,30 $ | 6,00 $ |
| `grok-4.3` (<200k) | 1,25 $ | 0,20 $ | 2,50 $ |
| `MiniMax-M3` (≤512k) | 0,30 $ | — | 1,20 $ |
| `seed-2-0-mini-260428` [0,128] | 0,10 $ | 0,02 $ | 0,40 $ |
| `seed-1-6-flash-250715` [0,128] | 0,075 $ | 0,015 $ | 0,30 $ |

## 4.5 Free tier / prérequis financiers

| Fournisseur | Free tier | Prépaiement obligatoire |
|---|---|---|
| Google Gemini | **Oui** — « Free of charge » sur Flash, Flash-Lite, 2.5 Pro, embeddings ; **pas** sur image/vidéo | Non |
| Bria | **100 générations gratuites**, sans carte | Non (PAYG dès 0,018 $/gén.) |
| Alibaba | **100 images offertes** par modèle image (Singapour) | Non |
| BytePlus | 2 M tokens gratuits par compte (`REQUIRES VERIFICATION` — trouvé hors doc primaire) ; 3D : 150 K/500 K tokens offerts | **Seedance 2.0/2.5 : solde > 30 $ ou resource pack** |
| BFL | Non documenté | Oui (crédits Stripe ; 1 crédit = 0,01 $) |
| Krea | Aucun | Oui (balance API, min. 5 $) |
| PixVerse | Non documenté | Oui (crédits) |
| HeyGen | `NOT DOCUMENTED` | Oui (wallet USD) |
| ElevenLabs | plan gratuit existant (hors page API pricing) | Abonnement mensuel |
| Luma | Non | Plan Build PAYG ; plan Scale = min. 4 unités |
| OpenAI / xAI / MiniMax / Ideogram / LTX / Kling | Non documenté | PAYG |

---

# Section 5 — Capabilities matrix

Légende : T2V texte→vidéo · I2V image→vidéo · R2V référence→vidéo · A2V audio→vidéo · T2I texte→image · I2I image→image
✅ documenté · ❌ non supporté · — non applicable · ? `NOT DOCUMENTED`

| Provider | Model | T2V | I2V | R2V | A2V | T2I | I2I | Video Edit | Video Extend | Lip Sync | Audio Native | 1080p | 4K | Max Duration | API Price |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Kling | kling-3.0 | ✅ | ✅ | ✅ (`element` ×3) | ❌ | — | — | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | 15 s | 0,8 ¥/s @1080p muet |
| Kling | kling-3.0-omni | ✅ | ✅ | ✅ (img+vidéo+sujets) | ❌ | — | — | ✅ (`base_video`) | ✅ | ❌ | ✅ (+`original`) | ✅ | ✅ | 15 s | 0,8–1,2 ¥/s @1080p |
| Kling | kling-3.0-turbo | ✅ | ✅ (first frame) | ❌ | ❌ | — | — | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | 15 s | 1,0 ¥/s @1080p |
| Kling | digital human | ❌ | ✅ | ❌ | ✅ | — | — | ❌ | ❌ | ✅ | entrée | ✅ | ❌ | **300 s** | 0,8 ¥/s @1080p |
| MiniMax | MiniMax-H3 | ✅ | ✅ | ✅ (9 img/3 vid/3 audio) | ✅ | — | — | ? | ? | ? | ? | ✅ (2K) | ❌ | 15 s | ? |
| MiniMax | Hailuo-2.3 | ✅ | ✅ | ❌ | ❌ | — | — | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | 10 s | 2 pts / 6 s @1080p |
| LTX | ltx-2-3-pro | ✅ | ✅ | ❌ | ✅ | — | — | ✅ (retake) | ✅ | ❌ | ✅ | ✅ | ✅ | ? (extend ~21 s facturés) | 0,04–0,32 $/s |
| LTX | ltx-2-5-fast | ✅ | ✅ | ❌ | ✅ | — | — | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | auto | 0,09–0,30 $/s |
| xAI | grok-imagine-video-1.5 | ✅ | ? | ❌ | ❌ | — | — | ✅ (édition annoncée) | ? | ❌ | ? | ? | ? | ? | 0,080 $/s |
| OpenAI | sora-2-pro | ✅ | ✅ (`input_reference`) | ✅ (`/videos/characters`) | ❌ | — | — | ✅ (`/videos/edits`) | ✅ (→20 s) | ❌ | ✅ | ✅ | ❌ | 12 s (+ extensions) | 0,30–0,70 $/s |
| Google | veo-3.1 | ✅ | ✅ (+`lastFrame`) | ✅ (3 images) | ❌ | — | — | ❌ | ✅ (`video`) | ❌ | ✅ | ✅ | ✅ | 8 s | 0,40–0,60 $/s |
| Google | veo-3.1-lite | ✅ | ✅ | ✅ | ❌ | — | — | ❌ | ✅ | ❌ | ✅ | ✅ | ❌ | 8 s | 0,05–0,08 $/s |
| BytePlus | dreamina-seedance-2-5 | ✅ | ✅ (first+last) | ✅ (30 img/10 vid/10 audio) | ✅ | — | — | ✅ | ✅ | ? | ✅ | ❌ (720p max) | ❌ | **30 s** | ~0,231 $/s @720p |
| BytePlus | dreamina-seedance-2-0 | ✅ | ✅ | ✅ (9/3/3) | ❌ | — | — | ✅ | ✅ | ? | ✅ | ✅ | ✅ | 15 s | 7,0 $/M tokens |
| BytePlus | seedream-5-0-pro | — | — | — | — | ✅ | ✅ (multi-réf) | — | — | — | — | — | — | — | 0,045–0,09 $/img |
| Alibaba | wan2.6-i2v | ❌ | ✅ | ❌ | ✅ (`audio_url`) | — | — | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | 15 s | ? |
| Alibaba | wan2.7-t2v | ✅ | ❌ | ❌ | ✅ | — | — | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | 15 s | ? |
| BFL | FLUX 3 video | ✅ | ✅ (keyframes datés) | ❌ | ❌ | — | — | ❌ | ✅ (`v2v`) | ❌ | ✅ | ✅ (fhd) | ❌ | **20 s** | 0,17–0,29 $/s |
| BFL | flux-2-pro | — | — | — | — | ✅ | ✅ (8 réfs) | — | — | — | — | — | — | — | dès 0,03 $/MP |
| HeyGen | Avatar IV | ❌ | ✅ (image arbitraire) | ✅ (`cinematic_avatar`) | ✅ | — | — | ❌ | ❌ | ✅ | entrée | ✅ | ❌ (4K sur III) | ? | 0,05–0,0667 $/s |
| Luma | ray-2 | ✅ | ✅ (frame0/frame1) | ✅ (`concepts`) | ❌ | — | — | ✅ (`modifyvideo`) | ✅ (keyframe `generation`) | ❌ | ✅ (`addaudio`) | ✅ | ✅ | 9 s | 1,20 $/5 s @1080p |
| Luma | photon-1 | — | — | — | — | ✅ | ✅ (`character_ref`) | — | — | — | — | — | — | — | 0,0404 $ |
| Ideogram | v3 / v4 | — | — | — | — | ✅ | ✅ (`character_reference_images`) | — | — | — | — | — | — | — | 0,03–0,20 $/img |
| PixVerse | V6 | ✅ | ✅ | ✅ (Fusion) | ✅ (TTS lipsync) | ❌ | ❌ | ✅ (modify/restyle/swap) | ✅ (extend) | ✅ | ✅ | ✅ | ❌ | 15 s | 18–23 cr/s @1080p |
| PixVerse | C1 | ✅ | ✅ | ✅ (Fusion) | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | 15 s | 19–24 cr/s @1080p |
| Bria | Fibo | — | — | — | — | ✅ | ✅ | ✅ (video editing) | ❌ | ❌ | — | — | — | — | 0,03 $/img |
| VEED (fal) | Fabric 1.0 | ❌ | ✅ | ❌ | ✅ | — | — | ❌ | ❌ | ✅ | entrée | ❌ (720p max) | ❌ | ? | 0,08–0,20 $/s |
| Krea | (revente) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | var. | +marge |

---

# Section 6 — Regional availability

| Fournisseur | Régions / endpoints |
|---|---|
| **Kling** | `api-beijing.klingai.com` — « ce domaine s'adresse aux utilisateurs dont les serveurs sont en Chine ». `api.klingai.com` également listé sur la page d'authentification. Portail global `app.klingai.com/global/dev` = **compte requis** → domaine international `REQUIRES VERIFICATION` |
| **MiniMax** | `api.minimax.io` (global) + `api-uw.minimax.io` (mentionné sur T2A). Plateforme chinoise distincte (`minimaxi.com`) hors périmètre de cette doc |
| **BytePlus ModelArk** | `ap-southeast-1` : `https://ark.ap-southeast.bytepluses.com/api/v3` — **tous** les modèles du Model list. `eu-west-1` : `https://ark.eu-west.bytepluses.com/api/v3` — **uniquement `seed-2-0` et `seedream-5-0-lite`**. Administration API : `ark.ap-southeast-1.byteplusapi.com` (signature HMAC-SHA256) |
| **Alibaba Model Studio** | 6 régions : Singapour (`ap-southeast-1`), US Virginie (`dashscope-us.aliyuncs.com`), Chine Pékin (`cn-beijing` / `dashscope.aliyuncs.com`), Hong Kong (`cn-hongkong`), Japon Tokyo (`ap-northeast-1`), Allemagne Francfort (`eu-central-1`). **Clés API non interchangeables entre régions.** Host = `{WorkspaceId}.<region>.maas.aliyuncs.com` (sauf US Virginie). Prix **différents** entre Singapour et Pékin (ex. qwen-image-2.0 : 0,035 $ vs 0,028671 $) |
| **ElevenLabs** | `api.elevenlabs.io` (défaut), `api.us.elevenlabs.io`, `api.eu.residency.elevenlabs.io`, `api.in.residency.elevenlabs.io`, `api.sg.residency.elevenlabs.io` |
| **BFL** | `api.bfl.ai` (hosts régionaux `api.eu.bfl.ai` / `api.us.bfl.ai` **non confirmés** dans la doc consultée → `REQUIRES VERIFICATION`) |
| **Google, OpenAI, xAI, LTX, Luma, Ideogram, PixVerse, HeyGen, Bria, Krea** | Endpoint unique global documenté ; restrictions géographiques `NOT DOCUMENTED` |
| **Google Veo** | `personGeneration` varie selon le cas d'usage/région (« varies by use case ») — restriction documentée sans liste de pays |

---

# Section 7 — Deprecated / preview / non disponible

## DEPRECATED
| Fournisseur | Élément | Détail |
|---|---|---|
| LTX | `ltx-2-fast`, `ltx-2-pro` | **suppression le 15 août 2026** |
| Google | `imagen-4.0-generate` | **arrêt le 17 août 2026** |
| ElevenLabs | `eleven_turbo_v2_5`, `eleven_turbo_v2`, `scribe_v1` | remplacements : flash_v2_5, flash_v2, scribe_v2 |
| OpenAI | `gpt-realtime-mini` | marqué Deprecated |
| Kling | schéma AK/SK (JWT), endpoints « legacy » à `model_name` | remplacés par API 2.0 (version dans le path) + Bearer |
| MiniMax | Hailuo-2.3 / 2.3-Fast / 02, I2V-01*, speech-2.6-*, speech-02-*, M2/M2.1/M2.5 | statut **Legacy** (toujours servis) |

## PREVIEW / BETA
| Fournisseur | Élément |
|---|---|
| Google | `veo-3.1-generate-preview`, `veo-3.1-fast-generate-preview`, Veo 3.1 Lite, `gemini-omni-flash`, `gemini-3.1-pro-preview`, `gemini-3-flash-preview`, TTS 3.1, embeddings 2, Lyria 3 |
| BFL | `flux-2-pro-preview`, `flux-2-klein-9b-preview` |
| xAI | `grok-build-0.1` (Beta) |
| Alibaba | `wan2.5-i2v-preview` |
| BytePlus | `seed-2-0-code-preview-260328` ; Model Unit = **Beta sur invitation** |

## WAITLIST
- **VEED Live Avatar API**

## NOT AVAILABLE THROUGH API / CONSUMER ONLY
- **VEED** : aucune API directe ; distribution par fal.ai (voir avertissement §1)

## REGION RESTRICTED
- BytePlus `eu-west-1` : seulement `seed-2-0` et `seedream-5-0-lite`
- Alibaba : catalogue et prix différents entre Singapour et Pékin

## ENTERPRISE / conditions d'accès
- HeyGen Avatar V : opt-in + **contrôle d'éligibilité**
- HeyGen Avatar III : opt-in explicite
- BytePlus Seedance 2.0/2.5 : solde > 30 $ ou resource pack
- Bria Enterprise : indemnisation IP illimitée, on-prem/BYOC
- Luma plan Scale : minimum 4 unités
- MiniMax : « API Pricing (for enterprises) » vs « Subscription Plans (individuals) »

---

# Section 8 — Best models for Market Queen

Classement par cas d'usage, **modèles avec API directe uniquement** (VEED et Krea exclus par la règle « pas d'agrégateur »).

### 1. UGC creator talking to camera
1. **HeyGen Avatar IV** (`avatar_iv`) — image arbitraire + script/audio + `motion_prompt` + `expressiveness`. 0,05 $/s photo avatar. Le seul à contrôler les gestes en langage naturel.
2. **Kling digital human** — image + audio jusqu'à **300 s**, 0,4–0,8 ¥/s. Durée = durée de l'audio, exactement le comportement dont la pipeline a besoin.
3. **PixVerse V6 lip-sync** — TTS intégré (`lip_sync_tts_*`) mais limité aux versions ≤ v5 pour ces champs → vérifier.

### 2. Creator + product reference
1. **Kling 3.0 Omni** — `element` (sujet persistant depuis images ou vidéo) + `refer_image` produit, adressés `@Nom` dans le prompt. C'est le seul à séparer explicitement « personnage » et « objet de référence ».
2. **BytePlus Seedance 2.5** — jusqu'à 30 images de référence, `@Image1…`.
3. **Google Veo 3.1** — `referenceImages` max 3, audio natif.

### 3. Product B-roll
1. **LTX ltx-2-3-fast** — 0,03 $/s en 720p, le moins cher du marché à qualité correcte, 4K disponible, audio natif.
2. **BytePlus Seedance 2.0 mini** (promo ~0,03 $/s en 720p jusqu'au 7 sept. 2026).
3. **Veo 3.1 Lite** — 0,05 $/s, audio natif.

### 4. Product hero shot (image)
1. **BFL FLUX.2 pro** — 8 images de référence en API, 4 MP, cohérence produit ; 0,03 $/MP.
2. **BytePlus seedream-5-0-pro** — multi-reference I2I, 0,045 $/img.
3. **Google `gemini-3.1-flash-image`** (Nano Banana 2) — 0,045 $, édition directe de la photo produit. ⚠️ watermark SynthID invisible.
4. **Bria Fibo** — si l'indemnisation IP compte (0,03 $/img, données licenciées).

### 5. Talking avatar
1. **HeyGen** — v3 `POST /v3/videos`, 4 moteurs, 4K sur Avatar III, captions SRT, batch, webhooks. Le plus complet.
2. **Kling digital human**.

### 6. Lip sync
1. **HeyGen Lipsync** (speed / precision) — 0,0333–0,0667 $/s.
2. **Kling 对口型** — 0,5 ¥ / 5 s.
3. **PixVerse** speech/lipsync generation.

### 7. Audio-driven video
1. **BytePlus Seedance 2.5** — **entrée audio seule supportée** (unique dans le panel), 10 clips audio de référence.
2. **LTX audio-to-video** — facturé sur la durée de l'audio d'entrée (0,10–0,17 $/s).
3. **Alibaba wan2.6-i2v** — `audio_url` 3–30 s.
4. **Kling digital human**.

### 8. Image-to-video
1. **Kling 3.0** (first+last frame, 4K, audio natif, 15 s).
2. **LTX ltx-2-3-pro** (`image_uri` + `last_frame_uri` + `camera_motion` énuméré).
3. **BFL FLUX 3 `i2v`** — keyframes horodatés `[secondes, image]` : contrôle temporel unique dans le panel.
4. **Veo 3.1** (`image` + `lastFrame`).

### 9. Multi-shot UGC
1. **Kling 3.0 / 3.0 Omni** — format multi-plans natif `镜头 n, m, words;`, **6 plans max**, somme = durée totale. C'est exactement la structure « une pub = n plans » de Market Queen, gérée par le modèle en un seul appel.
2. **BytePlus Seedance 2.5** — 30 s de narration continue.
3. **PixVerse V6** — `generate_multi_clip_switch`.

### 10. Final commercial-quality video
1. **Kling 3.0 4K** (3,0 ¥/s) ou **Seedance 2.0 4K**.
2. **Veo 3.1 4K** (0,60 $/s) — audio natif, mais 8 s max.
3. **LTX 2.5 pro** puis **LTX video-to-video HDR / reframe** pour le mastering et le recadrage 9:16.
4. **Luma Ray upscale + addaudio** pour la finition.

### Trois choix par défaut recommandés
| Rôle | Modèle | Raison |
|---|---|---|
| Défaut économique | `ltx-2-3-fast` 720p | 0,03 $/s, audio natif, facturation à la seconde lisible |
| Défaut qualité | `kling-3.0-omni` 1080p | multi-plans + sujets + vidéo de référence + édition vidéo dans **un seul** endpoint |
| Défaut acteur parlant | HeyGen `avatar_iv` | 0,05 $/s, image arbitraire, gestes pilotés |

---

# Section 9 — Recommended API integration architecture

## 9.1 Ce qui change par rapport à l'existant

L'abstraction actuelle (`ProviderTask` + `Registry` + `ProviderEntry`) est déjà la bonne forme : une entrée de catalogue + une classe de tâche. Ce qu'il faut changer :

1. **`credential` devient obligatoire par volet**, pas global. Aujourd'hui `CredentialEntry` est une liste plate dans `Settings`. La demande est : la clé se saisit **dans le menu Modèles**, dans le volet concerné.
2. **Le catalogue devient donnée, pas code.** `registry.dart` code en dur ~150 `ModelEntry`. Avec 17 fournisseurs et leurs paramètres (résolutions, durées, ratios, champs de référence), ça n'est plus tenable en Dart littéral. → fichier `assets/catalog/providers.json` versionné, chargé au démarrage.
3. **Suppression de `fal_schema.dart`.** Ce fichier lit dynamiquement le schéma d'un endpoint fal pour construire l'`extraInput`. Avec des APIs directes, le schéma est connu et figé : il descend dans le catalogue JSON.

## 9.2 Modèle de données du catalogue

```
Provider
  id, label, capabilities: [llm, avatar, image, video, audio]
  auth: { scheme: bearer|header, headerName, extraHeaders[] }
  baseUrls: { default, byRegion{} }
  signupUrl, docsUrl
  requirements: { minBalanceUsd?, prepaid?, activationNote? }
  discovery: { endpoint?, method?, responsePath? }   // /v1/models, models.list…

Model
  id (exact), providerId, panel (llm|avatar|image|video|audio)
  label, version, status (stable|preview|beta|deprecated|waitlist)
  endpoint: { method, path, async: bool, pollPath?, callbackField? }
  capabilities: { t2v,i2v,r2v,a2v,t2i,i2i,videoEdit,videoExtend,lipSync,audioNative }
  constraints: {
    resolutions[], aspectRatios[], durations[] | {min,max}, fps[],
    maxRefImages, maxRefVideos, maxRefAudios,
    imageFormats[], maxImageBytes, videoFormats[], maxVideoBytes,
    promptMaxChars
  }
  fields: { imageField, lastFrameField, refImagesField, refVideosField,
            refAudiosField, audioSwitchField, resolutionField, durationField }
  pricing: { unit: per_second|per_image|per_video|per_mtoken|per_credit,
             currency, tiers[{resolution, audio, value}], minimum? }
  regions[]
  sources[]   // URL officielle par fait
```

Le bloc `fields` est la généralisation directe de `VideoRequest.imageField` / `VideoReferences.*Field` déjà présents dans `types.dart` : le contrat existe, il change juste de source (catalogue au lieu du schéma fal).

## 9.3 Les cinq volets du menu Modèles

| Volet | Fournisseurs éligibles (API directe) |
|---|---|
| **LLM** | OpenAI, Google Gemini, xAI, MiniMax, Alibaba (Qwen), BytePlus (Seed/DeepSeek/GLM) — *Anthropic déjà présent* |
| **Acteurs parlants** | HeyGen, Kling (digital human), PixVerse (lip-sync), *(VEED si exception fal acceptée)* |
| **Images** | Black Forest Labs, Google Gemini, OpenAI, Ideogram, Bria, BytePlus (Seedream), Alibaba (Qwen-Image), Luma (Photon), MiniMax, xAI |
| **Vidéos** | Kling, BytePlus (Seedance), LTX, Google (Veo), OpenAI (Sora), MiniMax (H3), Luma (Ray), PixVerse, Alibaba (Wan), Black Forest Labs (FLUX 3) |
| **Audio** | ElevenLabs, MiniMax (speech-*), OpenAI (TTS+Whisper), Google (Gemini TTS), Kling (音频生成) |

Le filtrage vient du champ `panel` du catalogue — aucun fournisseur vidéo n'apparaît dans LLM, comme demandé.

Flux dans un volet : **choisir fournisseur → saisir la clé → cocher les modèles à activer**. Les modèles cochés alimentent les listes déroulantes du composer. Un fournisseur sans clé reste visible mais grisé, avec son `signupUrl` et sa contrainte (`solde > 30 $`, `prépayé`, `free tier`).

## 9.4 Transport : trois patterns seulement

Les 17 fournisseurs se ramènent à trois formes.

**A. Submit + poll** (Kling, MiniMax, LTX, BytePlus, Alibaba, BFL, Luma, PixVerse, HeyGen, OpenAI Videos, Ideogram async)
```
POST <createPath>  → { taskId }
GET  <pollPath>    → status ∈ {pending, running, done, failed}
```
Une seule classe `AsyncJobTask` paramétrée par : chemin de création, chemin de polling, chemin JSON du taskId, chemin JSON du statut, mapping des valeurs de statut, chemin JSON de l'URL de sortie. Les six variantes de nommage observées (`task_id`/`id`, `status`/`task_status`/`state`, `succeeded`/`succeed`/`completed`/`SUCCEEDED`/`Ready`) sont de la donnée, pas du code.

**B. Synchrone** (ElevenLabs TTS, OpenAI TTS/Whisper, Gemini generateContent, LLM en général) — réponse immédiate.

**C. Long-running operation Google** (Veo) — `:predictLongRunning` puis `operations.get`. Cas particulier assumé.

**Webhooks** : documentés chez Kling (`callback_url` + protocole Callback), MiniMax (`callback_url`), BytePlus (`callback_url`), Luma (`callback_url`), BFL (`webhook_url` + `webhook_secret`), HeyGen (`callback_url` + endpoints webhook complets), PixVerse, LTX (`X-Webhook-URL`), Krea. **Inutilisables depuis une app desktop sans serveur** → rester sur le polling, mais garder le champ dans le catalogue.

## 9.5 Estimation de coût avant envoi

Trois qualités de source, à traiter différemment :

| Niveau | Fournisseurs | Traitement |
|---|---|---|
| **Prix rendu par l'API** | BFL (`cost` dans la réponse de création), Kling (`billing[]` dans le statut) | afficher le montant réel |
| **Prix par seconde/image publié** | LTX, xAI, Google, OpenAI, Luma, HeyGen, Ideogram, Bria, Alibaba, PixVerse (crédits) | table locale × durée/résolution/audio |
| **Prix par token de sortie** | BytePlus Seedance | formule officielle : `tokens ≈ (durée_entrée + durée_sortie) × largeur × hauteur × fps / 1024`, avec **minimums** quand l'entrée contient une vidéo. Réel dans `usage.completion_tokens` après coup → afficher une fourchette, pas un chiffre |

C'est exactement la raison pour laquelle le code actuel met Kling en tête de liste plutôt que Seedance : garder cette logique, mais l'exprimer dans le catalogue via `pricing.unit`.

## 9.6 Découverte dynamique des modèles

Endpoints de listing officiellement documentés :
- OpenAI `GET /v1/models`
- Google `GET /v1beta/models` (+ `supportedGenerationMethods` → filtrage par capacité)
- ElevenLabs `GET /v1/models` (+ flags de capacité et `model_rates`)
- MiniMax listes compatibles OpenAI et Anthropic
- Kling `GET /tasks` (tâches, pas modèles) + `账号信息查询` / `抵扣明细查询`
- BytePlus `ListEndpoints` (endpoints d'inférence, signature HMAC-SHA256 — pas un catalogue de modèles)
- PixVerse `get-user-credit-balance`
- Luma `getcredits`
- BFL `get-the-users-credits`

**Aucun** fournisseur vidéo n'expose de catalogue de modèles interrogeable avec capacités et prix. Le catalogue reste donc la source de vérité, avec un enrichissement opportuniste par ces endpoints là où ils existent (utile surtout pour valider une clé et afficher le solde).

> **Implémenté le 11 août 2026** — `lib/providers/capabilities.dart`. Les capacités sont déclarées en Dart (`ModelCapabilities.declared`) plutôt qu'en JSON : elles sont typées, vérifiées à la compilation, et un test échoue si un modèle vidéo du registre n'en a pas. Chaque entrée porte durées, résolutions, ratios, commutateur audio et plafonds de références, d'après les sources de la section 3. `lib/providers/model_schemas.dart` arbitre entre cette table et la lecture dynamique du schéma fal, qui ne sert plus qu'aux deux endpoints Kling.

## 9.7 Ordre de migration proposé

1. **Catalogue JSON + chargeur** — remplace le corps de `registry.dart`, aucune UI changée.
2. **`AsyncJobTask` générique** — remplace `FalVideoTask`/`ReplicateVideoTask` par une seule implémentation pilotée par la donnée.
3. **Volets du menu Modèles** — déplacer la saisie des clés depuis Réglages, une carte par fournisseur.
4. **Fournisseurs par ordre de valeur** : LTX (le plus simple : Bearer + un POST + un GET) → BytePlus → Kling → Google Veo → HeyGen → ElevenLabs (déjà fait) → le reste.
5. **Retrait de fal/Replicate** en dernier, une fois les équivalents directs couverts : `fal_schema.dart`, les `ProviderEntry` `fal-*` / `replicate-*`, les credentials correspondants.

## 9.8 Points bloquants à lever avant de coder

| # | Point | Action |
|---|---|---|
| 1 | Kling international : domaine + tarifs USD | créer un compte sur `app.klingai.com/global/dev` et relever la page d'authentification + la grille de prix |
| 2 | MiniMax H3 : prix unitaire | non publié → demander au support ou n'exposer H3 qu'avec la mention « prix non publié » |
| 3 | ~~MiniMax speech : prix par caractère~~ | **levé** — 60 $ / 100 $ par M de caractères sur `pricing-paygo` (turbo / hd) |
| 4 | Alibaba Wan : prix | absent de `model-pricing` → chercher la page dédiée ou marquer non estimable |
| 5 | Alibaba : obtention du `WorkspaceId` | l'utilisateur devra le saisir en plus de la clé → prévoir un second champ dans la carte fournisseur |
| 6 | xAI Imagine : chemins d'endpoints image/vidéo | pages non publiques → relever depuis la console |
| 7 | ~~OpenAI : prix **par image** des `gpt-image-*`~~ | **levé pour gpt-image-2** — la grille par qualité est dans le guide image-generation, pas sur la page pricing. 1.5 et 1 mini sont sortis du catalogue |
| 8 | Luma : IDs API de Ray 3.2 et Uni-1.1 | facturés mais absents de l'API reference ; `ray-2` / `ray-flash-2` sont en revanche tarifés (0,048 / 0,015 $/s en 720p) |
| 9 | VEED | décider : exclusion, ou exception fal explicite |
| 10 | Krea | décider : exclusion, ou fallback agrégateur unique |

---

# Source of truth — index des URLs

| Fournisseur | URLs officielles utilisées |
|---|---|
| Kling | https://klingai.com/document-api/api/get-started/authentication · `/api/video/3-0-omni` · `/api/video/3-0-turbo` · `/api/video/avatar` · `/document-api/guides/get-started/overview` (grille prix vidéo) · https://app.klingai.com/global/dev (compte requis) |
| MiniMax | https://platform.minimax.io/docs/api-reference/api-overview · `/docs/guides/video-generation` · `/docs/api-reference/video-generation-v2-create.md` · `/video-generation-i2v.md` · `/speech-t2a-http.md` · `/docs/guides/models-intro.md` · `/docs/pricing/overview` · `/docs/guides/pricing-paygo` · `/pricing-video` · `/pricing-speech` · `/docs/llms.txt` |
| LTX | https://docs.ltx.io/models.md · `/pricing.md` · `/authentication.md` · `/api-documentation/api-reference/async-video-generation/submit-image-to-video.md` · `/llms.txt` · `/openapi.json` (docs.ltx.video redirige vers docs.ltx.io) |
| xAI | https://docs.x.ai/ · `/developers/models` · `/developers/pricing` |
| OpenAI | https://developers.openai.com/api/docs/models.md · `/api/docs/pricing` · `/api/docs/api-reference/videos` · `/api/docs/api-reference/models` (platform.openai.com redirige) |
| Krea | https://www.krea.ai/docs/llms.txt · `/docs/developers/introduction.md` · `/docs/developers/api-keys-and-billing.md` · `/docs/api-reference/video/kling-30.md` · `/video/ltx-23-22b.md` |
| ElevenLabs | https://elevenlabs.io/docs/models · `/docs/api-reference/models/list` · `/docs/api-reference/text-to-speech/convert` · https://elevenlabs.io/pricing/api |
| BytePlus | https://docs.byteplus.com/en/docs/ModelArk/1330310 (Model list) · `/1544106` (Pricing) · `/1520757` (Create video task) · `/Video_Generation_API` · https://docs.byteplus.com/api/docs/ModelArk/1262430 (ListEndpoints) |
| Alibaba | https://www.alibabacloud.com/help/en/model-studio/what-is-model-studio · `/model-pricing` · `/image-to-video-api-reference` · `/text-to-video-api-reference` |
| Google | https://ai.google.dev/gemini-api/docs/models · `/docs/veo` · `/docs/pricing` · https://ai.google.dev/api/models |
| Bria | https://docs.bria.ai/ · `/image-generation/endpoints/text-to-image-base` · https://bria.ai/pricing |
| BFL | https://docs.bfl.ai/ (redirige docs.bfl.ml) · `/llms.txt` · `/flux_3/flux3_video.md` · `/flux_2/flux2_overview.md` · `/quick_start/pricing.md` · `/quick_start/get_started.md` · `/api-reference/models/generate-or-edit-an-image-with-flux2-[pro].md` · https://api.bfl.ai/openapi.json |
| VEED | https://www.veed.io/api |
| HeyGen | https://developers.heygen.com/llms.txt · `/reference/create-video.md` · `/models.md` · `/avatar-iv.md` · `/reference` · `/docs/pricing` · `/openapi/external-api.json` |
| Luma | https://docs.lumalabs.ai/llms.txt · `/docs/video-generation.md` · `/reference/creategeneration.md` · `/reference/generateimage.md` · https://lumalabs.ai/api/pricing |
| Ideogram | https://developer.ideogram.ai/llms.txt · `/ideogram-api/api-overview` · `/api-reference/api-reference/generate-v4.md` · `/generate-v3.md` · https://ideogram.ai/api-pricing · https://developer.ideogram.ai/openapi.json |
| PixVerse | https://docs.platform.pixverse.ai/llms.txt · `/model-overview-2140345m0.md` · `/pricing-796039m0.md` · `/image-to-video-generation-13016633e0.md` |

## Pages officielles inaccessibles pendant l'audit
| URL | Raison |
|---|---|
| `app.klingai.com/global/dev/document-api/*` | HTTP 446 en fetch ; redirection vers login en navigateur |
| `docs.x.ai/developers/imagine/video` | 404 |
| `developers.heygen.com/docs/create-video`, `/docs/create-video-v2` | 404 (remplacés par `/reference/create-video`) |
| `docs.byteplus.com/**` (via fetch simple) | contenu rendu côté client — récupéré en navigateur |
| `docs.agents.lumalabs.ai/llms.txt` | 404 |
| `www.veed.io/api/docs` | page vide |
