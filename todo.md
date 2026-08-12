- Enlever la sélection "Auto - meilleure modèle pour ce plan" de partout.

- Pour la colonne de réglage plutôt que de la faire apparaitre en haut de la zone de prompt s'il n y a pas la place, il faudrait plutôt le faire apparaitre comme un menu contextuel qui apparaitra directement au dessus du bouton. Et évitant de se fait de faire varier la width de la barre de prompt.

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

- corriger l'UI dans la modale de sélection de la scène. 

- Ajouter la possibilité de pouvoir se cloner sois-même grâce à l'api de Heygen en utilisant le modèle Avatar. 

- Mettre à jour les tarifications manquantes : 

```
Voici uniquement **GPT Image 2**, avec les coûts de génération publiés par OpenAI. ([OpenAI Developers][1])

| Qualité    |  1024×1024 |  1024×1536 |  1536×1024 |
| ---------- | ---------: | ---------: | ---------: |
| **Low**    | **$0.006** | **$0.005** | **$0.005** |
| **Medium** | **$0.053** | **$0.041** | **$0.041** |
| **High**   | **$0.211** | **$0.165** | **$0.165** |

**À retenir pour Market Queen :**

* **Low 1024² : $0.006/image**
* **Medium 1024² : $0.053/image**
* **High 1024² : $0.211/image**
* Les résolutions **2K et 4K sont également disponibles**, avec un coût calculé selon les tokens générés.
* GPT Image 2 est facturé à **$30 / 1M tokens de sortie image** et **$8 / 1M tokens d'entrée image**. ([OpenAI Developers][2])

Donc pour de la génération d'images UGC, **Medium à $0.053/image** est probablement le chiffre le plus intéressant à retenir pour tes calculs de coût.

[1]: https://developers.openai.com/api/docs/guides/image-generation?utm_source=chatgpt.com "Image generation"
[2]: https://developers.openai.com/api/docs/models/gpt-image-2?utm_source=chatgpt.com "GPT Image 2 Model"


Oui. J’ai vérifié la **tarification officielle BytePlus ModelArk** actuelle. Il faut toutefois distinguer **Seedream 5.0 Lite** et le nouveau **Seedream 5.0 Pro**.

### Seedream 5.0 Pro

| Élément                                |      Prix officiel |
| -------------------------------------- | -----------------: |
| **Image d'entrée — 1ère image**        |       **Gratuite** |
| **Image d'entrée — à partir de la 2e** | **$0.003 / image** |
| **Image de sortie ≤ 2,36 MP**          | **$0.045 / image** |
| **Image de sortie > 2,36 MP**          |  **$0.09 / image** |

Le modèle officiel est `dola-seedream-5-0-pro-260628`. ([BytePlus Docs][1])

### Seedream 5.0 Lite

| Modèle                | Image d'entrée |    Image de sortie |
| --------------------- | -------------: | -----------------: |
| **Seedream 5.0 Lite** |   **Gratuite** | **$0.035 / image** |

Le modèle officiel est `seedream-5-0-lite-260128`. ([BytePlus Docs][1])

### Pour Market Queen

Si tu génères une image **sans image de référence** :

| Modèle                |  ≤ 2,36 MP |  > 2,36 MP |
| --------------------- | ---------: | ---------: |
| **Seedream 5.0 Pro**  | **$0.045** |  **$0.09** |
| **Seedream 5.0 Lite** | **$0.035** | **$0.035** |

Donc **Seedream 5.0 Lite à $0.035/image** est particulièrement intéressant pour ton pipeline UGC. Le tarif officiel chinois de Volcengine confirme également un prix de **¥0,22/image** pour Seedream 5.0 Lite. ([Volcengine][2])

[Tarification officielle BytePlus ModelArk](https://docs.byteplus.com/docs/ModelArk/1099320?utm_source=chatgpt.com)

**Attention :** si par « Seedream 5.0 » tu parles spécifiquement du **Pro**, alors le chiffre à retenir est **$0.045/image jusqu'à 2,36 MP** et **$0.09 au-delà**.

[1]: https://docs.byteplus.com/docs/ModelArk/1099320?utm_source=chatgpt.com "Pricing--ModelArk-Byteplus"
[2]: https://www.volcengine.com/product/ark?utm_source=chatgpt.com "火山方舟"

Oui. J’ai vérifié les tarifs **API officiels actuels** des fournisseurs. Voici les chiffres utiles pour ton calcul de coût dans Market Queen.

### 🎬 Luma — Ray 2 / Ray Flash 2

Luma a fait évoluer sa gamme : **Ray2** et **Ray2 Flash** sont les anciens modèles vidéo, tandis que l’API actuelle met notamment en avant Ray3.2. ([Luma Labs][1])

| Modèle         |           720p |          1080p | 4K |
| -------------- | -------------: | -------------: | -: |
| **Ray2 Flash** | **$0.015/sec** |  **$0.03/sec** |  — |
| **Ray2**       | **$0.048/sec** | **$0.096/sec** |  — |

⚠️ **Point important :** Ray2 est indiqué par Luma comme disponible dans Dream Machine mais « available in the Luma API soon » sur sa page Ray2. Donc si ton objectif est **l'API directement**, je ne considérerais pas Ray2 comme une option API fiable aujourd'hui. ([Luma Labs][2])

---

## 🔊 MiniMax Speech 2.8

Ici le prix est extrêmement simple : **facturation au caractère d'entrée**.

| Modèle               |                     Prix |
| -------------------- | -----------------------: |
| **Speech 2.8 Turbo** |  **$60 / 1M caractères** |
| **Speech 2.8 HD**    | **$100 / 1M caractères** |

Donc :

|              Texte | Turbo |     HD |
| -----------------: | ----: | -----: |
|   1 000 caractères | $0.06 |  $0.10 |
|   5 000 caractères | $0.30 |  $0.50 |
|  10 000 caractères | $0.60 |  $1.00 |
| 100 000 caractères | $6.00 | $10.00 |
|      1M caractères |   $60 |   $100 |

Ce sont les tarifs **Pay-As-You-Go officiels MiniMax**. ([MiniMax API Docs][3])

---

# 🗣️ Gemini 2.5 TTS

Google facture les modèles TTS **au token audio généré**, pas à la seconde ni au caractère.

### Gemini 2.5 Flash TTS

|                  |            Standard |       Batch |
| ---------------- | ------------------: | ----------: |
| **Input texte**  |   $0.50 / 1M tokens |  $0.25 / 1M |
| **Output audio** | **$10 / 1M tokens** | **$5 / 1M** |

### Gemini 2.5 Pro TTS

|                  |            Standard |        Batch |
| ---------------- | ------------------: | -----------: |
| **Input texte**  |      $1 / 1M tokens |   $0.50 / 1M |
| **Output audio** | **$20 / 1M tokens** | **$10 / 1M** |

([Google AI for Developers][4])

Les modèles sont actuellement encore désignés **Preview** dans la documentation Google :

* `gemini-2.5-flash-preview-tts`
* `gemini-2.5-pro-preview-tts`

([Google AI for Developers][4])

### Pour comparer directement les TTS

| Modèle                       | Unité de facturation |     Prix |
| ---------------------------- | -------------------- | -------: |
| **MiniMax Speech 2.8 Turbo** | 1M caractères        |  **$60** |
| **MiniMax Speech 2.8 HD**    | 1M caractères        | **$100** |
| **Gemini 2.5 Flash TTS**     | 1M audio tokens      |  **$10** |
| **Gemini 2.5 Pro TTS**       | 1M audio tokens      |  **$20** |

**Attention à cette dernière comparaison :** on ne peut pas comparer directement `$60 / 1M caractères` avec `$10 / 1M audio tokens`, car ce ne sont pas les mêmes unités. Pour ton pipeline UGC, il faut plutôt convertir un **script de 15/30/45 secondes en coût réel**.

Si tu veux, je peux te faire ensuite un **tableau unique de tous les modèles que tu viens de sélectionner (GPT Image 2 + Seedream 5 + Luma + MiniMax + Gemini)** avec **le coût exact d'une génération UGC de 30 secondes**, afin de voir quel fournisseur est réellement le moins cher.

[1]: https://lumalabs.ai/?utm_source=chatgpt.com "Luma | AI Agents for Creative Work"
[2]: https://lumalabs.ai/ray2?utm_source=chatgpt.com "Luma Ray2"
[3]: https://platform.minimax.io/docs/guides/pricing-paygo?utm_source=chatgpt.com "Pay as You Go - Models - MiniMax API Docs"
[4]: https://ai.google.dev/gemini-api/docs/pricing "Gemini Developer API pricing  |  Gemini API  |  Google AI for Developers"

Oui. Pour **Gemini 3.1 Pro**, le tarif API officiel actuel est celui de **Gemini 3.1 Pro Preview**. Google le facture au token. ([Google AI for Developers][1])

### Gemini 3.1 Pro — API

| Type                                    |                   Standard |          Batch |
| --------------------------------------- | -------------------------: | -------------: |
| **Input** texte / image / vidéo / audio |      **$2.00 / 1M tokens** | **$1.00 / 1M** |
| **Output** (réponse + reasoning)        |     **$12.00 / 1M tokens** | **$6.00 / 1M** |
| **Context cache**                       |      **$0.20 / 1M tokens** |              — |
| Stockage du cache                       | **$1 / 1M tokens / heure** |              — |

([Google AI for Developers][1])

### Pour Market Queen

Si tu l'utilises pour **générer le script d'une pub UGC**, le coût sera généralement extrêmement faible.

Par exemple, avec :

* 5 000 tokens d'entrée
* 2 000 tokens de sortie

→ `5 000 × $2 / 1M` = **$0.010**
→ `2 000 × $12 / 1M` = **$0.024**

**Total ≈ $0.034 par génération de script.**

Et contrairement à un modèle image/vidéo, **Gemini 3.1 Pro ne facture pas par seconde de vidéo** : c'est du token-based pricing. Il dispose également d'un contexte allant jusqu'à **1M tokens**. ([docs.cloud.google.com][2])

À noter : **Gemini 3.1 Pro n'a pas de free tier dans l'API**, même s'il est accessible gratuitement dans Google AI Studio pour l'essai. ([Google AI for Developers][3])

[1]: https://ai.google.dev/gemini-api/docs/pricing?utm_source=chatgpt.com "Gemini Developer API pricing"
[2]: https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/gemini/3-1-pro?utm_source=chatgpt.com "Gemini 3.1 Pro | Gemini Enterprise Agent Platform"
[3]: https://ai.google.dev/gemini-api/docs/gemini-3?utm_source=chatgpt.com "Gemini 3 Developer Guide - Interactions API"

```

- Supprimer les autre modèles d'images d'openai on gardera juste gpt-image-2.

- Ajouter une fonctionnalité pour améliorer le prompt de l'utilisateur dans chaque mode "Acteurs parlants, Image, Vidéo ou dans les options avancés". ça doit utiliser un modèle LLM gratuit et permettre de pouvoir améliorer contextuellement le prompt de l'utilisateur afin d'essayer d'atteindre un meilleur résutlat.

- Améliorer l'UI de réglage de l'acteur pour la voix car actuellement c'est vraiment dégueulasse. 

- Centrer le fil de génération au milieu mais pouvant prendre tout l'espace en largeur. Faire en sorte que les générations, si produit en multiple, soit dans un grid et avec pour chaque taille de cellule une taille proportionnelle à la taille du grid, pour éviter que ça soit trop grand. 

- S'assurer que si on lance les générations en plusieurs exemplaires, ces générations soient bien lancer en même temps/parallèles. Pour ne pas que le temps d'attente soit additionnel. 

- Ajouter les icônes et logo officiel dans le menu modèles pour aider l'utilisateur à voir trouver tout de suite ce qu'il cherche. 

- Changer la navigation dans le volet des menus à gauches. 