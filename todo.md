- Retravailler chaque modèle indépendemment pour en exploiter correctement les paramètres et option.

- Ajouter la fonctionnalité pour cloner la voix et pour générer une voix grâce à l'api d'elevenLabs.

- Ajouter la fonctionnalité pour générer une voix grâce au speech to generate voice d'eleven labs.

CREATE VOICE

```
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ ✨ Design Voice │ │ 🎤 Clone Voice  │ │ 📚 Voice Library│
│                 │ │                 │ │                 │
│ Describe the    │ │ Upload an audio │ │ Choose an       │
│ voice you want  │ │ sample          │ │ existing voice  │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

- ![alt text](image.png) Si on décide de cloner avec sa propre voix, alors il faudrait lire un text. Le screen shot provient de Heygen.

- Ajouter la possibilité de pouvoir se cloner sois-même grâce à l'api de Heygen en utilisant le modèle Avatar. 

- Améliorer l'UI de réglage de l'acteur pour la voix car actuellement c'est vraiment dégueulasse. 

- S'assurer que si on lance les générations en plusieurs exemplaires, ces générations soient bien lancer en même temps/parallèles. Pour ne pas que le temps d'attente soit additionnel. 

- `kling.png` est dans `assets/brand/providers/` mais n'est utilisé nulle part : l'id du credential est `fal`, donc c'est `fal.png` que la carte lit. La carte s'appelle pourtant « Kling (via fal.ai) » — si la marque Kling parle plus, renommer `kling.png` par-dessus `fal.png`.

- Dans les exemples il faudra mettre de très bonnes vidéo UGC réalisé à l'aide du logiciel. Si on clique sur un exemple, alors ça nous ramène vers une fiche qui montre quel prompt a été utilisé, quelle modèle, le prix etc. Tout ce qui a pu permettre de générer cette vidéo. Dans la façon de présenter, ça sera uniquement une Card vertical qui montre la vidéo, et juste en dessous le prix de la génération, comme ça l'utilisateur voit directement ce qui est faisable et à quel prix.

- Dans le studio, on pourra mettre un bouton qui, lorsqu'on appuie dessus, lance un tutoriel d'un workflow éprouvé et produisant un résultat très correct. Tout sera montrer avec des petites animations à chaque fois pour que ça soit très clair pour l'utilisateur. 

- Il manque encore le tarif sur le modèle Seedream 5.0 il le faut absolument. Je ne veux aucun modèle sans tarif, c'est non négociable.

- Il faut aussi ajouter le modèle OmniHuman 1.5 de ByteDance pour les acteurs parlants d'après ce que me dis chatGPT : 

```
Oui. Pour **Market Queen**, je ne chercherais pas à intégrer beaucoup de modèles : il vaut mieux avoir **quelques modèles réellement différenciés**, avec chacun un rôle clair.

Tu as déjà :

* **HeyGen Avatar III**
* **HeyGen Avatar IV**
* **HeyGen Avatar V**
* **Kling Avatar V2 Standard**
* **Kling Avatar V2 Pro**

À mon avis, le gros manque dans ta sélection actuelle est **ByteDance OmniHuman**, et côté Kling il faut surtout regarder les générations **Video 3.0 / 3.0 Omni**, plutôt que d'empiler les anciennes variantes.

### Ma sélection
```
| Fournisseur   | Modèle                         | Intérêt pour Market Queen                                                       | Je l'intègre ?                       |
| ------------- | ------------------------------ | ------------------------------------------------------------------------------- | ------------------------------------ |
| **ByteDance** | **OmniHuman 1.5**              | Très bon avatar à partir d'une image + audio, mouvements/expressions naturelles | **🔥 Oui**                           |
| **ByteDance** | OmniHuman 1                    | Ancienne génération                                                             | ❌                                    |
| **Kling**     | **Avatar V2 Standard**         | Bon rapport qualité/coût                                                        | ✅ Tu l'as                            |
| **Kling**     | **Avatar V2 Pro**              | Qualité supérieure, production premium                                          | ✅ Tu l'as                            |
| **Kling**     | **Video 3.0 Omni**             | Génération vidéo multimodale + audio natif + personnages                        | **🔥 Oui, mais rôle différent**      |
| **Kling**     | Video 2.6 Audio                | Très bon pour talking character, mais génération précédente                     | ⚠️ seulement si coût/API intéressant |
| Kling         | Avatar V1 / anciennes versions | Dépassé                                                                         | ❌                                    |
```
---

## 1. Le modèle que j'ajouterais en priorité : **ByteDance OmniHuman 1.5**

C'est probablement **le plus intéressant pour compléter ta gamme actuelle**.

OmniHuman est spécifiquement conçu pour transformer **une image + une piste audio** en humain parlant, avec synchronisation labiale, expressions et mouvements corporels. OmniHuman a notamment été entraîné sur une très grande quantité de données de mouvement humain. ([Fal.ai][1])

Et surtout, **OmniHuman 1.5 est suffisamment différent de HeyGen/Kling pour justifier sa présence**.

Ton pipeline pourrait devenir :

> Image produit → génération acteur → ElevenLabs → **OmniHuman 1.5**

### Pourquoi je le mettrais dans Market Queen

Parce que tu peux le positionner comme :

**ByteDance OmniHuman 1.5 — Natural / Expressive**

L'utilisateur choisit alors :

* HeyGen → avatar commercial très propre
* Kling → avatar plus cinématique
* OmniHuman → mouvement humain plus naturel / expressif

C'est beaucoup plus intéressant que d'avoir 8 modèles qui produisent finalement le même type de vidéo.

---

# 2. Kling : ne t'arrête surtout pas à Avatar V2

Tu as actuellement :

**Kling Avatar V2 Standard**
**Kling Avatar V2 Pro**

Ils restent pertinents. La documentation officielle de Kling décrit Avatar 2.0 comme capable de produire des avatars avec expressions, gestes et mouvements corporels, et jusqu'à des scènes longues. ([Kling AI][2])

Mais en 2026, **Kling 3.0 est devenu beaucoup plus intéressant à surveiller**.

Kling présente désormais **Video 3.0 et Video 3.0 Omni** comme sa nouvelle génération, avec notamment une architecture multimodale et une liaison entre identité visuelle et voix. ([Kling AI][3])

Et la fonction **Video 3.0 Omni** permet notamment de fournir une vidéo de référence de 3–8 secondes ou plusieurs références avec audio pour conserver l'identité et les caractéristiques vocales du personnage. ([Kling AI][4])

### Mais attention

Je ne remplacerais **pas** automatiquement Avatar V2 Pro par Video 3.0 Omni.

Ils ne répondent pas exactement au même besoin.

**Avatar V2**

> Image → acteur parlant

**Video 3.0 Omni**

> Références + prompt + audio → scène vidéo beaucoup plus contrôlable

Donc pour Market Queen :

### Avatar V2 = UGC classique

Exemple :

> « Une femme de 25 ans présente ce sérum face caméra. »

### Video 3.0 Omni = UGC avancé

Exemple :

> « Une femme tient le produit dans sa main, marche dans sa salle de bain, regarde la caméra puis montre le produit en parlant. »

C'est une différence fonctionnelle importante.

---

# 3. Je garderais donc cette architecture

Je ferais une séparation dans Market Queen entre **Talking Avatar** et **AI Video Actor**.

### 🗣️ Talking Avatar

| Modèle                       | Positionnement           |
| ---------------------------- | ------------------------ |
| **HeyGen Avatar V**          | Premium / dernier HeyGen |
| **HeyGen Avatar IV**         | Alternative              |
| **HeyGen Avatar III**        | Legacy / compatibilité   |
| **Kling Avatar V2 Standard** | **Best value**           |
| **Kling Avatar V2 Pro**      | **Best quality**         |
| **ByteDance OmniHuman 1.5**  | **Natural / expressive** |

Mais je mettrais **Avatar III derrière** dans l'interface.

Tu n'as pas forcément besoin de supprimer le modèle de ton backend, mais je ne le présenterais pas comme une nouveauté.

---

# 4. Et une deuxième catégorie : "AI Actor"

C'est là que **Kling 3.0 Omni** devient très intéressant.

Par exemple :

### AI Actor

**Kling Video 3.0 Omni**

> Create an entire UGC scene with your actor.

L'utilisateur pourrait avoir :

**Actor**

* Generated female
* Generated male
* Upload photo

**Voice**

* ElevenLabs

**Action**

* Talking to camera
* Holding product
* Applying product
* Walking
* Demonstrating product

**Scene**

* Bedroom
* Bathroom
* Kitchen
* Street
* Car
* Office

Et là tu commences à avoir quelque chose de beaucoup plus puissant qu'un simple générateur de talking head.

---

# 5. Ce que je supprimerais / n'ajouterais pas

Je serais assez agressif sur les modèles obsolètes.

### ❌ ByteDance OmniHuman 1

Je ne l'intégrerais pas en 2026 si **OmniHuman 1.5** est disponible via ton fournisseur/API.

Il n'apporte pas suffisamment de différenciation pour justifier un choix supplémentaire.

### ❌ Kling Avatar V1

Même logique.

### ⚠️ Kling 2.6 Audio

C'est intéressant technologiquement : Kling 2.6 Audio permettait déjà du monologue face caméra avec expressions et lip-sync synchronisé. ([Kling AI][5])

Mais **je ne l'ajouterais pas comme modèle utilisateur** si tu as déjà Avatar V2 et surtout les capacités 3.0.

Il peut éventuellement être utile **en backend comme fallback** si son prix/latence est nettement meilleur.

---

# 6. Ce que je ferais concrètement pour Market Queen V1/V2

Je viserais seulement **6 modèles visibles** :

### 🎙️ Talking Avatar

**HeyGen**

* Avatar V
* Avatar IV

**Kling**

* Avatar V2 Standard
* Avatar V2 Pro

**ByteDance**

* OmniHuman 1.5

### 🎬 Full AI Actor

**Kling**

* Video 3.0 Omni

Et éventuellement :

> **HeyGen Avatar III** → caché dans `Legacy models`

---

## Et surtout : ne mets pas tous les modèles au même niveau

Je ferais plutôt quelque chose comme :

**AI Actor**

`Recommended` → **OmniHuman 1.5**

`Best Value` → **Kling Avatar V2 Standard**

`Best Quality` → **HeyGen Avatar V**

`Premium` → **Kling Avatar V2 Pro**

`Cinematic` → **Kling Video 3.0 Omni**

Ça donne immédiatement une raison de choisir chaque modèle.

---

### Mon classement pour ton cas

Si ton objectif est **UGC publicitaire réaliste**, je partirais actuellement sur :

**🥇 ByteDance OmniHuman 1.5** — à ajouter absolument
**🥈 HeyGen Avatar V** — à conserver
**🥉 Kling Avatar V2 Pro** — à conserver
**4. Kling Avatar V2 Standard** — excellent choix économique
**5. HeyGen Avatar IV** — à conserver comme alternative
**6. Kling Video 3.0 Omni** — à intégrer, mais dans une catégorie différente

Et **je ne construirais pas Market Queen autour de modèles plus anciens simplement pour avoir une longue liste de modèles**. La tendance actuelle va clairement vers des modèles qui combinent identité, audio, expressions, gestes et génération de scène plutôt que vers le simple « photo → tête qui parle ». Kling 3.0 illustre précisément cette évolution. ([Kling AI][4])

Si ton objectif est de **réduire le coût API de Market Queen**, le prochain truc que je regarderais serait surtout **le prix réel par seconde + résolution + durée + vitesse de ces 6 modèles**, parce que ça peut complètement changer l'ordre du classement.

[1]: https://fal.ai/models/fal-ai/bytedance/omnihuman?utm_source=chatgpt.com "OmniHuman: State of the Art AI Avatar Video Generator ..."
[2]: https://kling.ai/quickstart/kling-ai-avatar-2-user-guide?utm_source=chatgpt.com "Kling AI Avatar 2.0 User Guide"
[3]: https://kling.ai/?utm_source=chatgpt.com "Kling AI: Next-Generation AI Creative Studio"
[4]: https://kling.ai/blog/kling-video-3-omni-native-lip-sync-audio-guide?utm_source=chatgpt.com "Kling Video 3.0 Omni Audio: Native Lip Sync & Multilingual ..."
[5]: https://kling.ai/quickstart/klingai-video-26-audio-user-guide?utm_source=chatgpt.com "Kling Video 2.6 Audio User Guide"
```


- Ajouter la possibilité de pouvoir annuler une génération en cours pour ne pas être facturé. (Si possible, je ne sais pas si c'est possible de le faire).

- Ajouter l'option de sous-titre automatique dans les réglages de génération de vidéo.

- Dégradation, il faut pouvoir ajouter référence image, vidéos et audio si le modèle le permet, dans le mode vidéo. Par exemple Seedance 2.5 est capable de prendre en référence des images, vidéos et audios. Aussi il faudra détecter dynamiquement si l'utilisateur a ajouter des références (images/vidéos/audios) ou non pour aller taper dans le bon endpoint et pour pas qu'il ait besoin de choisir le modèle 2.5 référence explicitement. Ca va de soit pour tous les modèles bien sûr.

