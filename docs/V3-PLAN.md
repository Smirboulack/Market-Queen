# Market Queen — plan V3 : le studio

Document de travail interne (FR). Le README reste la doc publique.
Remplace `V2-PLAN.md`, abandonné après le premier test de bout en bout.

---

## 1. Pourquoi on jette le formulaire

La V2.1 a supprimé l'étirement et la boucle. Le premier vrai test — une pub
parfum en 4 plans, $1.70 — a montré que ça ne suffisait pas : le livrable
ressemble à un spot TV des années 2010, pas à une vidéo de créateur.

Deux causes, et seule la seconde est corrigeable par des prompts :

**L'acteur ne parle pas.** Les 30 modèles vidéo du `Registry` sont tous du
*image-to-video* muet. La voix ElevenLabs est plaquée par-dessus une vidéo où
les lèvres ne disent pas le texte. Sur un plan où le sujet regarde l'objectif,
le cerveau le détecte en moins d'une seconde. C'est **le** défaut structurel, et
aucun réglage de prompt ne le corrige.

**Le formulaire produit une pub, pas un personnage.** Six champs texte qui
partent d'un coup dans un LLM ne permettent ni d'itérer sur l'acteur, ni de le
réutiliser, ni de l'entendre avant de payer la vidéo. L'utilisateur ne construit
rien : il remplit et il espère.

Arcads règle les deux en inversant l'ordre : on caste un acteur d'abord, on lui
fait dire un texte ensuite. C'est ce modèle qu'on adopte.

---

## 2. Principe directeur

> **On ne remplit pas un formulaire, on monte un tournage.**

Trois règles qui remplacent le « simple par défaut » de la V2 :

1. **L'acteur est l'unité de valeur.** Il se crée, s'écoute, se sauvegarde et se
   réutilise. Une pub est un acteur + un script, pas une requête.
2. **L'utilisateur écrit les mots, l'IA fait la direction visuelle.** On n'écrit
   plus le script à sa place. On traduit ses répliques en plans.
3. **Rien de payant sans écoute ni aperçu préalable.** Un portrait coûte $0.04,
   une écoute de voix $0.002, une pub $1. L'ordre des étapes doit refléter cet
   écart de trois ordres de grandeur.

Test à appliquer : *est-ce que l'utilisateur peut juger le résultat d'une étape
avant de payer la suivante ?* Si non, l'étape est mal placée.

---

## 3. Le déverrouillage technique : les modèles avatar

Vérifié sur fal.ai, catalogue d'août 2026 :

| Modèle | Entrées | Prix | Note |
| --- | --- | --- | --- |
| `fal-ai/kling-video/ai-avatar/v2/standard` | image + audio | **$0.0562/s** | défaut |
| `fal-ai/kling-video/ai-avatar/v2/pro` | image + audio | $0.115/s | qualité |
| `veed/fabric-1.0` | image + audio | $0.08/s (480p) · $0.15/s (720p) | alternative |
| `fal-ai/infinitalk` | image + audio | $0.20/s | haut de gamme |

Trois conséquences, toutes bonnes :

**C'est moins cher que ce qu'on fait aujourd'hui.** Kling AI Avatar Standard est
à $0.0562/s contre $0.084/s pour le Kling 3.0 i2v utilisé sur le test. La pub
Hugo Boss (13,5 s de parole) passerait de $1.68 à **$0.76** de vidéo — et avec
les lèvres synchronisées.

**La durée de la vidéo suit automatiquement celle de l'audio.** C'est
exactement ce que tu demandes en supprimant le réglage de durée, et ça fait
disparaître d'un coup tout l'échafaudage de la V2.1 : plus de plancher de
facturation à 5 s, plus de `Pricing::clipSeconds`, plus de `planShotTimings`,
plus de recalage `-shortest`. **La durée d'une scène, c'est la durée de son
audio.** Un fait, plus une estimation.

**L'audio doit exister par scène**, puisque c'est une entrée du modèle. Ça
inverse la décision « une seule prise de voix » de la V2.1. Le remède est dans
l'API ElevenLabs : les champs `previous_text` / `next_text` donnent au modèle le
contexte des répliques voisines, donc la prosodie reste continue d'une scène à
l'autre. À valider en premier au jalon S5 — c'est le seul risque réel du plan.

---

## 4. Le modèle de données

```cpp
struct Product {
    QString name, description, audience;
    QStringList imagePaths;      // N images, plus une seule
};

struct Voice {
    QString providerId, voiceId, modelId;
    double  stability = 0.45, similarity = 0.8, style = 0.35, speed = 1.0;
    QString clonedFromPath;      // si la voix vient d'un fichier importé
};

struct Actor {
    QString id, name;
    QString portraitPath;        // le plan de référence, injecté partout
    QStringList referencePaths;  // photos fournies par l'utilisateur
    QVariantMap traits;          // genre, âge, morphologie, style... facultatifs
    QString brief;               // le prompt libre
    QString decor;               // où il se trouve
    Voice   voice;
};

struct Scene {
    QString id;
    QString line;                // écrite par l'utilisateur, jamais par l'IA
    QString actorId;             // prévu pour le multi-acteurs, un seul pour l'instant
    enum Kind { Talking, BRoll } kind = Talking;
    QString imagePrompt, videoPrompt;   // dérivés par le LLM, éditables
    QString framePath, voicePath, clipPath;
    double  duration = 0.0;      // = durée de voicePath, mesurée
};

struct AdProject {
    Product      product;
    Actor        actor;
    QList<Scene> scenes;
    QString      aspectRatio = "9:16";
    bool         captions = true;
    QVariantMap  models;         // surcharges manuelles, vide = auto
};
```

Ce qui **disparaît** : `durationSeconds`, `Pricing::shotCount`,
`Pricing::clipSeconds`, `splitOwnScript`, `planShotTimings`, `avatarBrief` comme
champ texte libre.

Ce qui **survit intact** : le moteur `Pricing`, `ProviderTask` + `Registry`,
`LibraryModel`, la passe de montage ffmpeg, `SettingsStore`, `Crypto`.

`project.json` passe en `schemaVersion: 3`. `LibraryModel` lit les trois
formats — les projets existants ne disparaissent pas.

---

## 5. Le nouveau pipeline

```
1. Direction visuelle → 1 appel LLM : (acteur + décor + produit + répliques)
                        → imagePrompt/videoPrompt par scène       ~$0.01
2. Voix par scène     → N appels TTS, chaînés par previous/next_text
                        → la durée de chaque scène est mesurée ici
3. Frames             → N images, portrait de l'acteur en référence
4. Vidéos             → Talking : modèle avatar (image + audio)
                        B-roll  : image-to-video classique
5. Montage            → concat + sous-titres + mux
```

L'étape 1 est le seul appel LLM restant, et il ne touche jamais aux mots
prononcés.

---

## 6. L'interface

Trois zones, le shell `SideNav` + `StackLayout` ne bouge pas.

```
┌──────────────┬────────────────────────────┬──────────────────┐
│  ÉTAPES      │      PANNEAU ACTIF         │   RÉCAPITULATIF  │
│              │                            │                  │
│ ● Produit    │                            │  Produit    ✓    │
│ ● Acteur     │   (l'étape en cours,       │  [img][img]      │
│ ○ Script     │    plein écran)            │                  │
│ ○ Résumé     │                            │  Acteur     ✓    │
│              │                            │  [portrait]      │
│              │                            │  Voix · Sarah    │
│              │                            │                  │
│              │                            │  Script     …    │
│              │                            │  4 scènes · 14 s │
│              │                            │  ───────────     │
│              │                            │  ~$0.94          │
└──────────────┴────────────────────────────┴──────────────────┘
```

**Navigation** : linéaire au premier passage, libre ensuite. Une étape validée
devient cliquable — dans le rail de gauche comme dans le récapitulatif. C'est ce
qui réconcilie « onboarding » et « edits à volonté ».

**Le récapitulatif de droite** remplace `EstimateCard` en l'absorbant : il
montre le contenu de chaque étape (vignettes produit, portrait de l'acteur, nom
de la voix, nombre de scènes et durée parlée) et le coût estimé en bas, toujours
à jour.

**Les modèles disparaissent du flux principal.** Chaque panneau a un repli
« Avancé » qui expose son choix de modèle. Par défaut, Market Queen décide.

---

## 7. Les jalons

**Les sept sont livrés.** Chacun l’était seul et testable seul. **L'application génère une pub à la fin
de chaque jalon** — S0 branche le nouveau modèle sur l'ancien pipeline, et
`CreatePage` reste accessible jusqu'à S6.

### S0 — Les fondations : modèle + shell — ✅ livré

Le socle. Aucune fonctionnalité visible, mais rien d'autre ne peut atterrir sans.

- `src/app/AdProject.{h,cpp}` — le modèle ci-dessus, exposé à QML, autosauvé
- `qml/StudioPage.qml` — le shell trois zones, le rail d'étapes, le récap
- Un adaptateur `AdProject → Pipeline::start(QVariantMap)` pour que la
  génération continue de marcher avec le pipeline actuel
- `project.json` en `schemaVersion: 3`, lecture des v1/v2 préservée

**Sortie** : on crée un projet, on navigue entre trois panneaux, on génère.

### S1 — Étape 1 : le produit — ✅ livré

Le plus petit jalon, il sert à valider le shell et le récapitulatif sur un cas
réel.

- `ImageDropField` → `ImageDropGrid` : N images, réordonnables, supprimables,
  une marquée comme principale
- Nom, description, audience
- Vignettes dans le récapitulatif

**Sortie** : le contexte produit est complet et visible en permanence.

### S2 — Étape 2a : le casting — ✅ livré

**Le jalon le plus important du plan.** C'est ici que se joue le réalisme.

- Génération de portrait par texte, avec un **moteur de prompt anti-publicité** :
  appareil photo nommé (frontale 26 mm, f/1.8), défauts imposés (exposition
  inégale, fenêtre cramée, texture de peau et pores visibles, mèches rebelles),
  cadrage décentré, décor réellement encombré, et interdiction explicite du
  vocabulaire de hero shot
- Paramètres structurés **facultatifs** : genre, tranche d'âge, morphologie,
  cheveux, style vestimentaire, énergie — ils complètent le prompt libre, ils ne
  le remplacent pas
- Images de référence en entrée, en alternative ou en complément du texte
- Génération par lots de 4, on choisit, on relance
- Champ **décor**
- Bibliothèque d'acteurs : sauvegarde, réutilisation, duplication
- Le portrait retenu devient la référence de **chaque** frame de scène —
  l'infrastructure existe (`ImageRequest::referenceImageDataUri`)

**Sortie** : on obtient un acteur qui passe pour une personne réelle filmée au
téléphone, et on le retrouve dans la pub suivante.

### S3 — Étape 2b : la voix — ✅ livré

- Sélection dans les voix du compte ElevenLabs
- Curseurs stabilité / similarité / style / vitesse — ils sont déjà envoyés,
  codés en dur à `VoiceProviders.cpp:43`, il n'y a qu'à les remonter
- **Bouton d'écoute** : une phrase d'essai synthétisée pour ~$0.002, avant tout
  engagement
- Clonage de voix **par import de fichier** (mp3/wav) via l'API ElevenLabs
- La voix est attachée à l'acteur et sauvegardée avec lui

**Sortie** : on entend l'acteur parler avant d'avoir dépensé un dollar en vidéo.

### S4 — Étape 3 : le script — ✅ livré

- Éditeur scène par scène : ajouter, supprimer, réordonner ; une réplique par
  scène
- **Guidage marketing non contraignant** : les beats (hook, problème, solution,
  preuve, CTA) apparaissent en placeholder fantôme, jamais imposés
- Par scène : type *parlant* ou *b-roll produit*
- Bouton **Direction visuelle** — un appel LLM dérive `imagePrompt` et
  `videoPrompt` de l'acteur, du décor, du produit et de la réplique ; les deux
  restent éditables à la main
- Durée estimée par scène (mots ÷ 2,6) et cumulée, affichée en direct

**Sortie** : un script découpé, dirigé visuellement, sans durée imposée.

### S5 — Le rendu parlant — ✅ livré

Le jalon risqué. À faire d'un bloc.

- Nouvelle catégorie de provider `avatar` dans le `Registry` (image + audio →
  vidéo lip-syncée), avec les quatre modèles de la section 3 et leurs prix
- TTS **par scène**, chaîné par `previous_text` / `next_text` — **à valider en
  tout premier**, avant d'écrire le reste du jalon
- Réécriture du pipeline selon la section 5
- Les scènes b-roll gardent le chemin image-to-video actuel
- Montage : concat des scènes, sous-titres, mux

**Sortie** : une pub où les lèvres suivent la voix, sans étirement, dont la
durée est celle du script. Critère : aucun `setpts`, aucun `stream_loop`, aucun
`-shortest` dans la commande ffmpeg.

### S6 — Le résumé et le studio — ✅ livré

- Panneau de résumé final : vue globale, coût détaillé, bouton Générer
- Après génération : bande de scènes, **régénération d'une scène seule**
- Lecteur intégré (`Qt6::Multimedia` — à vérifier sur les trois OS de la CI)
- Suppression de `CreatePage.qml`

**Sortie** : le formulaire disparaît.

---

## 8. Ce que ça coûte, en pratique

La pub Hugo Boss refaite dans le nouveau système, 13,5 s parlées, 4 scènes :

| Poste | Modèle | Coût |
| --- | --- | --- |
| Direction visuelle | GPT-5 mini | ~$0.01 |
| Voix (4 scènes) | Eleven Turbo v2.5 | ~$0.01 |
| Frames (4) | Seedream 5 Lite edit | ~$0.14 |
| Vidéo parlante | Kling AI Avatar v2 Std | ~$0.76 |
| Sous-titres | Whisper | ~$0.01 |
| **Total** | | **~$0.93** |

Contre $1.70 aujourd'hui, avec les lèvres synchronisées. Le casting de l'acteur
se paie une fois (~$0.16 pour quatre variantes) et se réutilise à l'infini.

---

## 9. Hors périmètre V3

- Multi-acteurs par scène — le champ `Scene::actorId` existe, l'UI viendra après
- Capture micro intégrée — l'import de fichier couvre le besoin d'abord
- Musique et SFX
- Éditeur timeline avec keyframes
- Publication vers TikTok / Meta
- Application web, comptes, serveur

---

## 10. Décisions actées

| Question | Décision |
| --- | --- |
| Comment l'acteur parle | Modèle avatar dédié (image + audio → lip-sync) |
| Découpage du script | L'utilisateur découpe et écrit, l'IA dirige visuellement |
| Clonage de voix | Import de fichier d'abord, micro plus tard |
| Nombre d'acteurs | Un seul, champ prévu au niveau scène |
| Durée de la vidéo | Supprimée — c'est la durée de l'audio généré |
| Navigation | Linéaire au premier passage, libre ensuite |
| Choix des modèles | Repliés dans « Avancé » par étape, auto par défaut |
