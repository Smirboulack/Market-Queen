# Market Queen — plan V2

Document de travail interne (FR). Le README reste la doc publique.

---

## 1. Diagnostic honnête de la V1

Ce qui marche : le pipeline tourne de bout en bout, l'architecture provider
(`ProviderTask` + `Registry`) est propre et extensible, l'UI est lisible,
la persistance par dossier + `project.json` est une bonne décision.

Ce qui ne marche pas, et que **aucune** des idées de la liste ChatGPT ne corrige :

> `src/pipeline/Pipeline.cpp:588-598`
>
> Le clip vidéo (5 s ou 10 s) est **étiré jusqu'à +35 %** ou **bouclé** pour
> couvrir une voix-off de 20 à 45 s.

C'est le défaut visible n°1 de chaque pub produite. Un ralenti de 35 % sur un
visage qui parle, ça se voit immédiatement ; une boucle, encore plus. Tant que
ce point n'est pas réglé, ajouter des templates, des hooks ou des avatars
revient à décorer un produit dont le livrable est mauvais.

Deuxième manque structurel : **aucune notion de coût nulle part**. Sur un
produit BYOK dont l'argument de vente est « tu paies les modèles au prix
coûtant », c'est le trou le plus étrange.

---

## 2. Principe directeur

> **Simple par défaut, profond à la demande.**

Règle non négociable pour toute la V2 : le chemin
`nom du produit → Générer` doit rester fonctionnel et rester le chemin par
défaut. Chaque nouveauté est soit un réglage avec une valeur par défaut
correcte, soit une option qui n'apparaît **qu'après** le premier résultat.

Test à appliquer à chaque feature : *est-ce qu'un utilisateur qui ignore cette
fonctionnalité obtient quand même une bonne pub ?* Si non, la valeur par défaut
est mauvaise.

---

## 3. Ce que je garde et ce que je jette du plan ChatGPT

| Idée | Verdict | Pourquoi |
| --- | --- | --- |
| Système de scènes | **Garder — priorité absolue** | C'est la seule idée qui corrige le vrai défaut. Tout le reste en dépend. |
| Templates UGC | Garder, mais **en données, pas en code** | 9 « workflows » distincts = 9 chemins à maintenir. En réalité un template = une liste de *beats* dans un fichier JSON. Zéro code pipeline. |
| Contrôle du coût | **Garder — à faire en premier** | Le moins risqué, le plus aligné avec le positionnement, et c'est le garde-fou dont le multi-scènes a besoin. |
| Générateur de hooks | Garder, mais **texte d'abord** | Générer 10 hooks coûte ~0,005 $. Générer 10 pubs coûte ~10 $. La valeur est de choisir avant de payer. |
| Variations | Garder, **après** les scènes | Sinon on multiplie un livrable défectueux. |
| Créateurs / avatars | Garder, mais **après** les scènes | La « cohérence du personnage » n'a aucun sens tant qu'il n'y a qu'un seul plan. |
| Bibliothèque d'assets | Garder, version minimale | Produits + créateurs suffisent. Pas de gestionnaire de fichiers. |
| Auto multi-modèles | Garder, **en dernier** | Nécessite les prix (V2.0) et les contraintes par plan (V2.1) pour être autre chose qu'un `if`. |
| Creative Lab 5×3×2 = 30 pubs | **Rejeter tel quel** | 30 rendus vidéo ≈ 30 à 45 $ en BYOK, en un clic, sans validation. C'est l'exact inverse de « meilleur résultat pour son argent ». Remplacé par : explorer en texte, rendre à la carte, avec plafond de budget. |
| Refonte de l'UI en éditeur | Garder, **comme conséquence** | L'UI doit suivre le modèle de données, pas le précéder. L'éditeur apparaît naturellement en V2.3. |

---

## 4. L'ordre

Six jalons. Chacun est livrable seul, chacun a un critère de sortie.

### V2.0 — Le compteur (coût dynamique) — ✅ livré

**Objectif** : à tout instant, l'utilisateur voit ce que le bouton Générer va lui
coûter, et après coup ce qu'il a réellement coûté.

> **Livré.** `src/core/Pricing.{h,cpp}` + `resources/pricing.json` (33 modèles
> tarifés, 43 marqués `unknown`), carte d'estimation dans le panneau de droite,
> prix unitaire dans chaque sélecteur de modèle, coût réel écrit dans
> `project.json` et affiché dans la bibliothèque, garde-fou `check_pricing.py`
> branché sur ctest. Les 16 nouvelles chaînes sont traduites dans les 10 langues.

**Nouveau**

- `src/core/Pricing.{h,cpp}` — catalogue de prix + moteur d'estimation
- `resources/pricing.json` — les prix, en **données**, embarqué en Qt resource,
  surchargeable par un fichier dans le dossier de config

```jsonc
{
  "schemaVersion": 1,
  "updated": "2026-08-08",
  "models": {
    // vidéo : au second
    "fal-ai/kling-video/v2.1/master/image-to-video": {
      "unit": "second", "amount": 0.095, "minUnits": 5,
      "source": "https://fal.ai/models/fal-ai/kling-video"
    },
    // image : à la requête
    "gpt-image-1":            { "unit": "image",   "amount": 0.04 },
    // TTS : aux 1000 caractères
    "eleven_multilingual_v2": { "unit": "kchars",  "amount": 0.30 },
    // LLM : au million de tokens
    "gpt-4.1":                { "unit": "tokens",  "in": 2.00, "out": 8.00 },
    // transcription : à la minute
    "whisper-1":              { "unit": "minute",  "amount": 0.006 }
  }
}
```

> ⚠️ Les chiffres ci-dessus sont des **exemples de forme**, pas des prix
> vérifiés. À l'implémentation, chaque entrée doit être sourcée sur la page
> tarifaire du fournisseur, avec l'URL dans le champ `source`.

**API exposée à QML**

```cpp
// Renvoie { lines: [{step, label, detail, amount, known}], total, hasUnknown }
Q_INVOKABLE QVariantMap estimate(const QVariantMap &request) const;
```

Le lookup se fait **par id de modèle**, indépendamment du `Registry` : un id
collé via « Other model id… » retourne simplement `known: false` et s'affiche
« prix inconnu » au lieu de casser.

**UI** — un `EstimateCard` dans le panneau de droite de `CreatePage.qml`, juste
au-dessus du bouton Générer, recalculé à chaque changement du formulaire :

```
ESTIMATION

Script        GPT-4.1              ~$0.01
Image         Nano Banana          ~$0.04
Voix          Eleven Multilingual  ~$0.09
Vidéo         Kling 2.1 · 10 s     ~$0.95
Sous-titres   Whisper              ~$0.01
──────────────────────────────────────────
Total estimé                       ~$1.10

  [ GÉNÉRER ]
```

Et dans le sélecteur de modèle lui-même, le prix unitaire à côté de chaque
entrée (`Kling 2.1 Master — $0.095/s`), pour que le choix se fasse en
connaissance de cause **avant** de regarder le total.

**Coût réel après coup** : le `Pipeline` compte les unités réellement
consommées (caractères envoyés au TTS, secondes de clip obtenues, images
générées) et écrit un objet `cost` dans `project.json`. La `LibraryPage`
affiche le coût sur chaque carte, plus un total par mois.

**Règles d'honnêteté** (importantes, c'est un argument de vente) :
- toujours écrit « estimé » / « ~ », jamais présenté comme une facture
- un modèle sans prix connu affiche « ? » et exclut le total du chiffre affiché
  (« ~$0.15 + 1 modèle au prix inconnu »)
- lien vers la page tarifaire du fournisseur depuis chaque ligne
- date de mise à jour du catalogue visible dans les Réglages

**Fichiers touchés** : `Pricing.*` (nouveau), `resources/pricing.json` (nouveau),
`CreatePage.qml`, `ModelPicker.qml`, `PickerWithCustom.qml`, `LibraryPage.qml`,
`Pipeline.cpp` (comptage), `LibraryModel.*`, `CMakeLists.txt`.

**Critère de sortie** : chaque id de modèle du `Registry` a soit un prix, soit une
entrée explicite `"unknown": true`. Un test CTest échoue si un modèle du
`Registry` n'est dans aucun des deux cas.

**Pourquoi en premier** : aucun risque architectural, livrable seul, valeur
immédiate — et surtout, le multi-scènes va multiplier la facture par 3 à 5.
Livrer ça sans compteur serait irresponsable sur un outil BYOK.

---

### V2.1 — Le plan de coupe (multi-scènes) — ✅ livré

**Objectif** : supprimer définitivement l'étirement et la boucle. Une pub =
N plans distincts, chacun avec sa durée réelle, concaténés.

> **Livré, avec un écart assumé sur le plan initial.**
>
> **Les timings Whisper ne sont pas utilisés.** La voix off est une prise unique
> qui n'est **jamais coupée** — seule l'image l'est. Une répartition
> proportionnelle à la longueur de chaque réplique est donc exacte à la fraction
> de seconde près, et cette erreur est invisible : elle change juste le moment du
> plan de coupe. Ça supprime une dépendance API, un mode d'échec, et la
> divergence entre sous-titres activés et désactivés. Whisper reste strictement
> ce qu'il était : les sous-titres.
>
> **Pas de contrôle « nombre de plans ».** Il découle de la durée :
> `clamp(ceil(durée / 5), 2, 10)`. Cinq secondes est le plancher de facturation
> de tous les modèles vidéo, donc chaque plan est acheté à ce plancher sans
> gaspillage, et aucun plan ne dépasse ce qu'un modèle sait produire — donc plus
> jamais de boucle. Un contrôle de plus aurait été un contrôle de plus à rater ;
> il aura sa place dans le storyboard de la V2.3.
>
> Montage en une passe ffmpeg : `trim` par plan → `scale`/`pad` sur un canevas
> commun (les modèles rendent à des tailles différentes et `concat` refuse de
> les joindre) → `concat` → sous-titres → mux. Le dernier plan tient sur sa
> dernière image pour couvrir un clip revenu trop court, et `-shortest` recale
> le tout sur la voix off. Validé avec ffmpeg sur trois sources volontairement
> dépareillées (720x1280@24, 1920x1080@30, 1080x1080@25) : sortie 1080x1920@30
> d'une durée exactement égale à l'audio.

**Refonte du modèle de données** (`Pipeline.h`)

```cpp
struct Shot {
    int      index;
    QString  line;          // la phrase dite pendant ce plan
    QString  imagePrompt;
    QString  videoPrompt;
    QString  framePath;
    QString  clipPath;
    double   start = 0.0;   // position dans la voix-off
    double   duration = 0.0;
    QString  imageModel, videoModel;   // pour le journal et le coût
};

struct RunState {
    // ... champs existants qui restent globaux (voix, srt, final)
    QList<Shot> shots;
};
```

**Nouvel ordre des étapes** — c'est le point de conception clé :

```
1. Script      → renvoie shots[] (une réplique + 2 prompts par plan)
2. Voix-off    → UNE seule prise pour tout le script
3. Timings     → Whisper (déjà là pour les sous-titres) donne les mots datés
                 → on en déduit la durée exacte de chaque plan
4. Frames      → N images, en parallèle
5. Vidéos      → N clips, chacun à SA durée exacte
6. Montage     → concat + audio + sous-titres
```

Trois bénéfices d'un coup :

1. **Une seule prise de voix** préserve la prosodie (du TTS découpé plan par
   plan s'entend immédiatement) et ne coûte pas plus cher.
2. **Whisper devient porteur** : il servait juste aux sous-titres, il donne
   maintenant les points de coupe. Fallback si les sous-titres sont désactivés :
   découpe proportionnelle au nombre de caractères de chaque réplique.
3. **On connaît la durée de chaque plan avant d'acheter la vidéo** — plus de
   secondes payées pour rien, plus d'étirement, plus de boucle.

**Montage** : demuxer `concat` (on écrit un `shots.txt` dans le dossier du
projet) puis une passe de filtergraph. `FfmpegTask` prend déjà des arguments
libres et un répertoire de travail : **aucune nouvelle classe à écrire**.

**Contrat des providers de texte** : le schéma JSON demandé au LLM passe de
`{script, hook, imagePrompt, videoPrompt}` à `{hook, caption, shots:[{line,
imagePrompt, videoPrompt}]}`. Un point de modification par provider dans
`TextProviders.cpp`.

**Contrôle utilisateur** : un unique sélecteur `Plans : 1 · 2 · 3 · 4 · 5`,
défaut **3**. `Plans = 1` reproduit exactement le comportement V1 — c'est le
filet de sécurité si un modèle vidéo se comporte mal. L'estimation de la V2.0
réagit en direct : passer de 1 à 4 plans fait visiblement monter le total, donc
l'arbitrage qualité/prix est explicite.

**UI** : `StepList` devient hiérarchique (`Vidéos — 2/4`), sinon l'utilisateur
regarde une barre figée pendant 6 minutes.

**Migration** : `project.json` passe en `schemaVersion: 2`. `LibraryModel` doit
lire les deux formats — les anciens projets ne doivent pas disparaître de la
bibliothèque.

**Risque** : c'est le refactor porteur du plan. À faire d'un bloc, avec `Plans =
1` comme chemin de repli testé.

**Critère de sortie** : une pub de 30 s en 4 plans, sans aucun `setpts` ni
`stream_loop` dans la commande ffmpeg finale.

---

### V2.2 — Les formats (templates UGC) — *données pures*

Une fois les plans en place, un template n'est plus une fonctionnalité : c'est
un fichier.

`resources/formats.json` :

```jsonc
{
  "problem-solution": {
    "label": "Problème → Solution",
    "defaultShots": 4,
    "beats": [
      { "name": "hook",     "intent": "Nommer la frustration en une phrase" },
      { "name": "problem",  "intent": "Montrer le problème concrètement" },
      { "name": "solution", "intent": "Introduire le produit comme la réponse" },
      { "name": "cta",      "intent": "Dire quoi faire maintenant" }
    ]
  }
  // testimonial, unboxing, review, before-after, storytelling, demo, tiktok-made-me
}
```

Les *beats* sont injectés dans le prompt du script et mappés 1:1 sur les plans.
**Zéro ligne dans le pipeline.** Ajouter un format = une PR sur un JSON, ce qui
est exactement ce qu'on veut sur un projet open source.

**UI** : une rangée de puces en haut de la carte « The ad ». Défaut :
*Talking head*. Le nombre de plans de la V2.1 s'ajuste au format choisi mais
reste modifiable.

---

### V2.3 — Le storyboard (contrôle plan par plan + lecteur)

**C'est ici, et seulement ici, que l'UI devient un éditeur.**

Après une génération, le panneau de droite se transforme en bande de plans :

```
┌────┬────┬────┬────┐
│ 01 │ 02 │ 03 │ 04 │
│ ▰  │ ▰  │ ▰  │ ▰  │
│3.2s│4.1s│2.8s│3.4s│
└────┴────┴────┴────┘

PLAN 02 · 4,1 s · Kling 2.1 · ~$0.39

« Je pensais que c'était encore un gadget TikTok. »

Visuel : femme en salle de bain, lumière du matin

[ Modifier la réplique ]  [ Modifier le prompt ]
[ Régénérer ce plan — ~$0.43 ]
```

**Régénérer un seul plan** est la fonctionnalité qui incarne le mieux le
positionnement : réparer un plan raté coûte 0,40 $ au lieu de relancer une pub à
1,50 $. Techniquement c'est direct une fois la V2.1 faite : re-exécuter
frame + vidéo pour un index, puis relancer le montage.

**Lecteur intégré** : `QtMultimedia` (`MediaPlayer` + `VideoOutput`). Ajoute une
dépendance `Qt6::Multimedia` au `CMakeLists.txt` — à vérifier sur les trois
plateformes de la CI avant de s'engager.

---

### V2.4 — Variations (texte d'abord, budget plafonné)

Deux temps, séparés volontairement :

**Explorer — quasi gratuit**

```
HOOKS                              généré pour ~$0.01

01  « J'aurais aimé trouver ça plus tôt. »           ○
02  « Personne ne m'avait parlé de ça. »             ●
03  « Honnêtement je n'y croyais pas. »              ●
...
10  « TikTok m'a fait acheter ça. »                  ○

[ Régénérer ]   [ 2 sélectionnés → Écrire les scripts ]
```

**Rendre — payant, explicite**

```
FILE D'ATTENTE

2 pubs sélectionnées · 3 plans chacune
Coût estimé                        ~$2.20
Plafond de budget    [ $5.00 ]

[ Lancer les 2 ]
```

Le plafond arrête la file dès qu'il est atteint, plutôt que de découvrir la
facture après. Rendu séquentiel, annulable entre deux pubs.

---

### V2.5 — Créateurs et produits (bibliothèque minimale)

**Créateur** = portrait de référence + persona + `voiceId` + réglages caméra et
environnement par défaut. Le portrait est injecté comme image de référence dans
le prompt de **chaque** plan — `nano-banana/edit`, `flux-kontext` et
`gpt-image-1` acceptent tous une image d'entrée, donc l'infrastructure existe
déjà (`ImageRequest::referenceImageDataUri`).

**Produit** = nom, description, photos, couleurs de marque. « Nouvelle pub pour
Nike Air Max » pré-remplit le formulaire.

Stockage : JSON dans le dossier de config + un dossier `creators/` pour les
images. On réutilise les patterns de `SettingsStore`. Deux nouvelles pages dans
`SideNav`, pas plus.

**Pourquoi ici** : la cohérence d'un personnage n'a rien à unifier tant qu'il n'y
a qu'un plan par pub.

---

### V2.6 — Routage automatique des modèles

`Registry::resolveModel` fait aujourd'hui du *pattern matching* sur des chaînes
(`contains("kling")`, `contains("hailuo")`). Ça ne survivra pas au multi-plans.

Remplacer par une table de capacités, à côté des prix :

```jsonc
"fal-ai/kling-video/v2.1/master/image-to-video": {
  "maxDuration": 10, "i2v": true, "aspects": ["9:16","1:1","16:9"], "tier": "quality"
}
```

`Auto` devient alors une vraie fonction de classement : *le modèle le moins cher
qui satisfait les contraintes de ce plan*, réglé par un curseur unique
**Économique · Équilibré · Qualité** — un seul contrôle, pas un mode « Manual /
Auto » qui oblige à comprendre quinze modèles.

Dépend de V2.0 (prix) et V2.1 (contraintes par plan). D'où sa place en dernier.

---

## 5. Ce que devient l'interface

Pas de refonte. Le shell (`SideNav` + `StackLayout`) ne bouge pas. La colonne de
gauche de `CreatePage` reste un formulaire — c'est ce qui rend l'outil
immédiatement compréhensible, il ne faut pas le perdre.

C'est **le panneau de droite** qui évolue, en trois incréments :

| Étape | Panneau de droite |
| --- | --- |
| V1 | `StepList` + journal |
| V2.0 | `EstimateCard` + `StepList` + journal |
| V2.1 | `EstimateCard` + `StepList` hiérarchique + journal |
| V2.3 | Lecteur + storyboard + journal repliable |

L'« éditeur » de la maquette ChatGPT arrive donc tout seul, sans jour de refonte
UI, et sans jamais casser le chemin simple.

---

## 6. Hors périmètre V2 (à dire non explicitement)

- Application web, comptes, serveur — le desktop sans compte *est* le produit
- Neuf workflows codés en dur
- Creative Lab qui rend 30 pubs d'un clic
- Éditeur timeline avec keyframes
- Publication vers TikTok / Meta
- Génération musique / SFX

---

## 7. Récapitulatif

| Jalon | Contenu | Risque | Corrige |
| --- | --- | --- | --- |
| **V2.0** | Coût dynamique + coût réel | Faible | Le trou du positionnement BYOK |
| **V2.1** | Multi-plans | **Élevé** | Le défaut visible n°1 |
| **V2.2** | Formats UGC (données) | Faible | La variété créative |
| **V2.3** | Storyboard + régénération + lecteur | Moyen | Le contrôle et le gaspillage |
| **V2.4** | Variations texte-d'abord + budget | Faible | La production en volume |
| **V2.5** | Créateurs + produits | Moyen | La cohérence et la répétition |
| **V2.6** | Routage auto | Faible | Le choix des modèles |

Si l'ordre doit être écourté : **V2.0 + V2.1 + V2.2 constituent déjà une V2
défendable.** Le reste est du confort.
