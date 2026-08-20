# Droplet — Guide de rétro-ingénierie

> **À quoi sert ce document.** Comprendre Droplet de fond en comble : où se
> trouve chaque chose, à quoi elle sert, comment la modifier, et ce qui casse
> si l'on s'y prend mal. Écrit pour être lu dans l'ordre une première fois,
> puis consulté par recherche (`Ctrl+F`) ensuite.
>
> **Comment l'utiliser avant une soutenance.** Lisez les parties 1 à 3 en
> entier — c'est une heure. Puis faites les six parcours guidés de la partie 4
> avec le code ouvert à côté : c'est ce qui transforme une lecture en
> compréhension. La partie 8 anticipe les questions du jury.

---

## Table des matières

1. [Le projet en cinq minutes](#1-le-projet-en-cinq-minutes)
2. [Les huit couches](#2-les-huit-couches)
3. [La carte du projet — où est quoi](#3-la-carte-du-projet--où-est-quoi)
4. [Six parcours guidés](#4-six-parcours-guidés)
5. [Fiches par module](#5-fiches-par-module)
6. [Les décisions de conception et leur raison](#6-les-décisions-de-conception-et-leur-raison)
7. [Recettes — « je veux modifier… »](#7-recettes--je-veux-modifier)
8. [Questions de jury probables](#8-questions-de-jury-probables)
9. [Glossaire](#9-glossaire)

---

## 1. Le projet en cinq minutes

**Ce que fait Droplet.** Deux téléphones proches l'un de l'autre s'échangent des
messages chiffrés sans passer par Internet, sans opérateur et sans serveur. Si
le destinataire est trop loin, un téléphone situé entre les deux relaie le
message sans jamais pouvoir le lire.

**Les trois idées qui font tout le reste.**

1. **Chaque appareil est un nœud complet.** Il n'y a pas de client et de
   serveur : chaque téléphone découvre, envoie, reçoit, relaie et stocke. C'est
   pourquoi il n'existe aucun code « côté serveur » à chercher — il n'y en a
   pas.

2. **Trois radios, pas une.** Bluetooth Low Energy pour découvrir et faire
   passer de petits messages, Wi-Fi local et Wi-Fi Direct pour les fichiers et
   la voix. Le code choisit automatiquement laquelle utiliser selon leur santé
   mesurée.

3. **Le contenu est chiffré de bout en bout.** Les relais transportent des
   octets qu'ils ne peuvent pas déchiffrer. Cela découle de l'idée 1 : si
   n'importe quel téléphone peut relayer, il ne faut surtout pas qu'il puisse
   lire.

**Les chiffres.** 45 185 lignes de Dart, 93 fichiers, 26 écrans, 17 services,
8 tables, 63 tests.

**Le point d'entrée.** `lib/main.dart` → `runApp()` → routeur → premier écran.
Si vous ne deviez ouvrir qu'un seul fichier pour comprendre l'architecture, ce
serait `lib/core/repositories/mesh_repository.dart` : c'est le chef d'orchestre.

---

## 2. Les huit couches

Le code est organisé en couches. **Une couche basse ne connaît jamais une
couche haute.** Le transport ignore ce qu'est un « message » : il ne voit que
des octets et un numéro de type.

| # | Couche | Où | Rôle |
|---|--------|-----|------|
| 1 | Présentation | `lib/features/`, `lib/design_system/` | Les 26 écrans et les composants visuels |
| 2 | État | `lib/core/providers/` | Expose l'état à l'interface (Riverpod) |
| 3 | Métier | `lib/core/repositories/mesh_repository.dart` | Orchestre envoi, réception, relais |
| 4 | Sécurité | `lib/core/services/crypto_service.dart` | Clés, chiffrement, déchiffrement |
| 5 | Persistance | `lib/core/services/storage_service.dart`, `lib/core/database/` | SQLite via Drift |
| 6 | Fiabilité | `lib/core/network/premium_message_queue.dart` | File, priorités, relances |
| 7 | Routage | `lib/core/protocol/droplet_mesh_protocol.dart` | Table de routage, congestion, dédup |
| 8 | Transport | `lib/core/services/*_transport.dart` | BLE, Wi-Fi local, Wi-Fi Direct |

**Pourquoi c'est important pour votre soutenance.** Si on vous demande « où
ajouteriez-vous une fonctionnalité X ? », la réponse se déduit de cette table.
Un nouveau type de message ? Couches 3 et 1. Un nouveau transport ? Couche 8
uniquement, sans toucher au reste.

---

## 3. La carte du projet — où est quoi

### 3.1 Le noyau (`lib/core/`)

#### Repositories — le chef d'orchestre

| Fichier | Lignes | Rôle |
|---------|-------:|------|
| `repositories/mesh_repository.dart` | 2 260 | **Le fichier central.** Envoi, réception, relais, groupes, statuts, accusés |

C'est ici que tout converge. Les fonctions à connaître :

- `init(myId, myPseudo)` — démarre tout (ligne ~301)
- `sendMessage(...)` — envoi d'un message 1:1 ou diffusion (~862)
- `sendFile(...)` — envoi d'un fichier
- `sendGroupMessage(...)` — envoi en groupe
- `_handleIncomingMessage(data)` — **réception : le point d'entrée de tout ce
  qui arrive** (~584)
- `_reliableOnSend(task)` — ce que la file appelle pour émettre (~105)
- `sendHello(targetId)` — annonce ma clé publique (~907)

#### Services — les 17 briques techniques

| Fichier | Lignes | Rôle | Modifier si… |
|---------|-------:|------|--------------|
| `mesh_transport_service.dart` | 1 432 | Orchestre les 3 transports, choisit le meilleur | vous ajoutez un transport ou changez la stratégie de choix |
| `storage_service.dart` | 1 302 | Accès à la base, fichiers reçus, pairs connus | vous ajoutez une donnée à persister |
| `ble_mesh_transport.dart` | 724 | Bluetooth : découverte + envoi | problème BLE |
| `local_wifi_transport.dart` | 640 | Wi-Fi local : sockets TCP + balises UDP | problème Wi-Fi |
| `native_p2p_transport.dart` | 591 | Wi-Fi Direct via Nearby Connections | problème Wi-Fi Direct |
| `webrtc_call_service.dart` | 475 | Appels audio 1:1 | fonctionnalité d'appel |
| `crypto_service.dart` | 438 | **Toute la cryptographie** | jamais sans raison sérieuse |
| `ble_mesh_protocol.dart` | 363 | Découpage BLE en fragments de 19 octets | taille des fragments |
| `group_webrtc_call_service.dart` | 356 | Appels de groupe (4 max) | |
| `backup_service.dart` | 308 | Sauvegarde chiffrée de l'identité | |
| `notification_service.dart` | 250 | Notifications système Android | |
| `call_signaling_service.dart` | 216 | Signalisation d'appel via le mesh | |
| `app_icon_service.dart` | 167 | Changement d'icône (13 variantes) | |
| `mesh_foreground_service.dart` | 138 | Service persistant Android | |
| `media_service.dart` | 113 | Pont natif : durée vidéo, découpe, galerie, thermique | |
| `share_intent_service.dart` | 71 | Réception d'un partage depuis une autre app | |
| `call_ringer_service.dart` | 71 | Sonnerie et vibration d'appel | |

#### Réseau, protocole, état, modèles, base

| Fichier | Lignes | Rôle |
|---------|-------:|------|
| `network/premium_message_queue.dart` | 362 | File d'envoi : priorités, 5 relances, délai exponentiel |
| `network/network_manager.dart` | 368 | Santé des liens, heartbeats, reconnexion |
| `protocol/droplet_mesh_protocol.dart` | 361 | Routage, congestion AIMD, filtre de Bloom |
| `providers/mesh_provider.dart` | 1 479 | Tous les providers Riverpod du mesh |
| `providers/appearance_provider.dart` | 81 | Mode clair / sombre |
| `providers/thermal_provider.dart` | 79 | Surveillance de la surchauffe |
| `models/mesh_message.dart` | 869 | `MeshMessage`, `PeerRecord`, `GroupInfo`, `ConnectedPeer` |
| `models/status_media.dart` | 221 | Médias des statuts |
| `models/voice_note_meta.dart` | 182 | Métadonnées vocales encodées dans le nom de fichier |
| `database/app_database.dart` | 309 | **Les 8 tables** |
| `database/app_database.g.dart` | 5 463 | Généré par Drift — ne jamais modifier à la main |

### 3.2 Les écrans (`lib/features/`)

| Dossier | Fichiers principaux | Lignes |
|---------|--------------------|-------:|
| `chat/` | `chat_screen.dart` (3 642), `chat_info_screen.dart`, `message_context_menu.dart`, `voice_note.dart`, `sticker_picker.dart`, `location_message.dart`, `security_code_screen.dart`, `qr_scan_screen.dart`, `new_message_screen.dart` | ~6 400 |
| `status/` | `status_composer.dart` (1 820), `status_viewer_screen.dart` (1 211) | ~3 000 |
| `maps/` | `map_screen.dart` (845), `offline_tile_store.dart`, `offline_tile_provider.dart`, `offline_maps_screen.dart` | ~1 800 |
| `chats/` | `chats_screen.dart` — liste des conversations | 712 |
| `onboarding/` | `onboarding_screen.dart` (999), `splash_screen.dart` | ~1 100 |
| `call/` | `call_screen.dart`, `group_call_screen.dart` | ~860 |
| `settings/` | `settings_screen.dart`, `app_icon_screen.dart`, `backup_export_screen.dart` | ~1 080 |
| `news/` | `news_screen.dart` — les statuts | 496 |
| `safety/` | `safety_screen.dart`, `emergency_mode_screen.dart` | 617 |
| `group/` | `group_info_screen.dart`, `group_create_screen.dart` | 619 |
| `peers/`, `calls/`, `mesh/`, `home/`, `share/`, `contribution/` | un écran chacun | ~1 300 |

### 3.3 Le système de design (`lib/design_system/`)

| Fichier | Rôle |
|---------|------|
| `ouro_colors.dart` | **La palette.** Clair et sombre. Accesseurs statiques |
| `ouro_typography.dart` | L'échelle typographique complète |
| `design_tokens.dart` | Espacements, rayons, durées |
| `ouro_theme.dart` | Assemble le thème Flutter |
| `ouro_tab_bar.dart` | La barre d'onglets flottante (731 lignes) |
| `ouro_scaffold.dart` | Grand titre repliable, bouton retour |
| `ouro_list.dart` | Listes groupées à séparateurs décalés |
| `glassmorphism.dart` | Matériaux translucides, feuilles modales |
| `ouro_glass.dart` | Verre liquide (shader) + repli thermique |
| `ouro_alert.dart`, `ouro_spinner.dart`, `ouro_pressable.dart`, `ouro_haptics.dart` | Composants |

### 3.4 Le natif Android

| Fichier | Rôle |
|---------|------|
| `android/app/src/main/kotlin/.../MainActivity.kt` | Enregistre les ponts natifs, gère les 13 alias d'icône |
| `android/app/src/main/kotlin/.../MediaBridge.kt` | Durée vidéo, découpe MP4, galerie, état thermique |
| `android/app/src/main/AndroidManifest.xml` | Permissions, 13 `activity-alias`, service premier plan |

---

## 4. Six parcours guidés

> Faites-les avec le code ouvert. C'est la partie qui remplace « j'ai lu le
> projet » par « je comprends le projet ».

### Parcours 1 — J'envoie un message, que se passe-t-il ?

1. **`lib/features/chat/chat_screen.dart`** → `_send()`
   L'utilisateur appuie sur envoyer. La méthode lit le champ de texte.

2. **`lib/core/providers/mesh_provider.dart`** → `MeshNotifier.sendMessage()`
   Le message est d'abord **enregistré localement** avec le statut « en
   attente ». *Pourquoi d'abord ? Pour qu'il s'affiche immédiatement, même si
   le réseau met dix secondes.*

3. **`mesh_repository.dart`** → `sendMessage()` (~862)
   - `_encryptForPeer(targetId, content)` chiffre le contenu
   - construit le JSON `{c, s, t, e, n, m}`
   - préfixe deux octets : `[nombre de sauts][type]`
   - appelle `_enqueueReliable(...)`

4. **`premium_message_queue.dart`** → `enqueue()` puis `_processEntry()`
   La file appelle le rappel `onSend`, qui est…

5. **`mesh_repository.dart`** → `_reliableOnSend(task)` (~105)
   Lit le type dans l'octet 1, tente `sendViaRoute`, se rabat sur la diffusion.

6. **`mesh_transport_service.dart`** → `sendViaRoute()` → `sendToPeer()`
   Choisit le transport le plus sain, essaie **séquentiellement**, renvoie un
   booléen.

7. **`ble_mesh_transport.dart`** ou `local_wifi_transport.dart`
   Découpe et écrit sur la radio. Renvoie `true` si tout est parti.

8. **Retour** : si `false`, la file programme une relance (0,2 s, 0,4 s, 0,8 s,
   1,6 s, 3,2 s). Après cinq échecs, le message passe « échoué ».

> **Le point que le jury peut creuser** : à l'étape 6, `sendToPeer` renvoyait
> `void` dans la version initiale. Le refus du transport n'était donc pas
> détectable, et l'étape 8 ne se déclenchait jamais. C'est le défaut du
> chapitre 17.4 du rapport.

### Parcours 2 — Un message arrive, que se passe-t-il ?

1. **Transport** → émet sur le flux `incomingData`

2. **`mesh_transport_service.dart`** → contrôle anti-saturation
   (150 paquets/s max par pair), puis retransmet l'événement

3. **`mesh_repository.dart`** → `_handleIncomingMessage(data)` (~584)
   C'est **le point d'entrée de tout ce qui arrive**. Il :
   - lit l'octet de type pour aiguiller (message, accusé, hello, statut…)
   - vérifie l'identifiant contre la déduplication
   - si le message m'est destiné → déchiffre et enregistre
   - sinon → décrémente les sauts et relaie

4. **`crypto_service.dart`** → `decryptBytes(clé, chiffré, nonce)`

5. **`storage_service.dart`** → enregistre en base

6. **`mesh_provider.dart`** → émet sur `newMessageEvents`

7. **`chat_screen.dart`** → l'écran écoute, la bulle apparaît

> **Cas particulier à connaître** : si la clé publique de l'émetteur n'est pas
> encore connue, `resolveIncomingContent` (~452) place le message dans une file
> d'attente et `_retryPendingDecryptions` (~516) le reprend dès que la clé
> arrive. C'est ce qui produit « Message illisible » quand la clé n'arrive
> jamais.

### Parcours 3 — Le relais : comment un message traverse un téléphone

Dans `_handleIncomingMessage` :

1. L'identifiant est cherché dans le filtre de Bloom, puis dans
   `SeenMessageIds`. **Déjà vu → on ignore.** Sans cela, tempête de
   rediffusions.
2. L'identifiant est ajouté à la table des vus.
3. Le message m'est-il destiné (`targetId == myId`) ? Non.
4. L'octet 0 (nombre de sauts) est-il supérieur à zéro ? Oui → décrémenté.
5. `broadcastToConnectedPeers(data, excludePeerId: émetteur)` renvoie le
   message à tous mes voisins **sauf celui qui me l'a donné**.

**Le contenu n'est jamais déchiffré.** Le relais ne possède pas la clé.

### Parcours 4 — Le chiffrement, concrètement

1. **À la création de l'identité** — `onboarding_screen.dart` appelle
   `CryptoService.ensureIdentityKeyPair()` : une paire X25519 est générée, la
   privée va dans le stockage sécurisé, la publique est conservée.

2. **À la rencontre d'un pair** — chacun envoie un message `hello` contenant sa
   clé publique (`sendHello`, ~907 ; réception `_handleHello`, ~946).

3. **Au premier message** — `sharedKeyWithPeer(peerId, clePublique)` calcule le
   secret partagé par ECDH. **Mis en cache** (512 entrées) : l'opération de
   courbe elliptique n'est pas refaite à chaque message.

4. **Chiffrement** — `encryptBytes(clé, données)` renvoie *deux* valeurs : le
   texte chiffré (avec le code d'authentification concaténé) et un **nonce
   nouveau à chaque appel**.

5. **Déchiffrement** — l'inverse. Si le message a été altéré, le mode GCM le
   détecte et le déchiffrement échoue.

**Pour les groupes** c'est différent : voir `_advanceMySenderKey()`
(`mesh_repository.dart` ligne 1883) et le principe des Sender Keys en
partie 6.

### Parcours 5 — La découverte d'un pair

1. Les trois transports annoncent leur présence en continu (rythme adaptatif
   selon batterie et premier/arrière-plan).
2. À la détection, chaque transport émet sur `peerEvents`.
3. `mesh_transport_service.dart` fusionne : **un même pair peut être vu par
   plusieurs transports**, il est fusionné en un seul `ConnectedPeer` avec un
   ensemble de transports.
4. `mesh_repository.dart` écoute `peerEvents` et envoie un `hello` en
   diffusion.
5. `mesh_provider.dart` expose `meshPeerListProvider` — l'interface se met à
   jour.

> **Piège** : Nearby (Wi-Fi Direct) identifie les appareils par adresse MAC, pas
> par identifiant Droplet. La table `_nearbyToDropletId` fait le pont.

### Parcours 6 — De l'écran à la base de données

Pour comprendre comment l'interface reste synchronisée :

1. `chats_screen.dart` fait `ref.watch(conversationsProvider)`
2. Ce provider, dans `mesh_provider.dart`, lit `StorageService`
3. Quand un message arrive, `MeshNotifier` met à jour son état
4. Riverpod notifie tous les widgets qui observent
5. Flutter reconstruit uniquement ceux-là

**L'interface ne connaît jamais le réseau.** Elle observe un état. C'est ce qui
permet de tester la logique sans écran.

---

## 5. Fiches par module

### Fiche — `mesh_repository.dart` (2 260 lignes)

**Où** `lib/core/repositories/`
**À quoi ça sert** Le chef d'orchestre. Tout passe par lui.

**Structure interne**
- lignes 100–200 : file fiable (`_reliableOnSend`, `_enqueueReliable`)
- lignes 200–280 : les flux d'événements exposés à l'interface
- lignes 300–400 : `init()` et `dispose()`
- lignes 400–560 : résolution des clés, déchiffrements en attente
- lignes 580–860 : **réception** (`_handleIncomingMessage` et ses branches)
- lignes 860–1 200 : **envoi** (messages, hello, typing, accusés, réactions)
- lignes 1 200–1 500 : statuts et check-in de sécurité
- lignes 1 500–1 900 : relais et groupes
- lignes 1 900–2 260 : fichiers

**Comment le modifier** Pour ajouter un type de message : créer un `kind`,
l'émettre dans une nouvelle méthode `sendXxx`, l'aiguiller dans
`_handleIncomingMessage`, exposer un `Stream`.

**Ce qui casse si vous vous trompez** Oublier la déduplication → tempête réseau.
Oublier de décrémenter les sauts → boucle infinie.

---

### Fiche — `mesh_transport_service.dart` (1 432 lignes)

**Où** `lib/core/services/`
**À quoi ça sert** Cacher aux couches hautes qu'il existe trois radios.

**Les fonctions clés**
- `sendToPeer(peerId, data, type)` → **`Future<bool>`** : essaie les transports
  un par un, dans l'ordre de santé, s'arrête au premier qui accepte
- `sendViaRoute(peerId, data, type)` → direct si joignable, sinon via le
  prochain saut connu
- `broadcastToConnectedPeers(data)` → **`Future<bool>`** : vrai si au moins un
  pair a pris la charge
- `_getCandidateTransports(peer, type)` → l'ordre de préférence,
  **exclut BLE si `type >= 0x20`**

**Comment ajouter un transport** Créer la classe avec les trois flux
(`peerEvents`, `incomingData`, `healthEvents`) et un `sendToPeer` renvoyant
`bool` ; l'ajouter dans `_sendVia` et `_getCandidateTransports`. Aucune autre
couche à toucher.

**Ce qui casse** Faire renvoyer `void` à un `sendToPeer` — c'est exactement le
défaut corrigé.

---

### Fiche — `premium_message_queue.dart` (362 lignes)

**Où** `lib/core/network/`
**À quoi ça sert** Garantir qu'un message part, ou qu'on sache qu'il n'est pas
parti.

**Paramètres** `maxRetries = 5`, `defaultTimeout = 30 s`, 5 envois en parallèle
au plus.

**Délai de relance** `2^tentative × 100 ms`, plafonné à 30 s, plus une gigue
aléatoire. *La gigue évite que dix messages échoués au même instant ne
réessaient tous ensemble.*

**Priorités** `critical` > `high` > `normal` > `low` > `background`. Un message
1:1 est `high`, une diffusion `normal`, un `hello` `low`.

---

### Fiche — `crypto_service.dart` (438 lignes)

**Où** `lib/core/services/`
**Règle d'or** N'appelez jamais une bibliothèque de crypto ailleurs. Tout passe
par ce fichier.

**Les fonctions**
- `ensureIdentityKeyPair()` → crée ou récupère mon identité
- `sharedKeyWithPeer(peerId, cléPublique)` → secret ECDH, mis en cache
- `encryptBytes(clé, données)` / `decryptBytes(clé, chiffré, nonce)`
- `ratchetForward(chaîne)` / `fastForward(...)` → groupes
- `computeSafetyNumber(...)` → 5 000 tours de SHA-256, 12 groupes de chiffres
- `deriveBackupKey(motDePasse)` → sauvegarde chiffrée

**Ce qui casse** Réutiliser un nonce avec la même clé compromet le chiffrement.
C'est pourquoi `encryptBytes` en génère un neuf à chaque appel — ne le mettez
jamais en cache.

---

### Fiche — `chat_screen.dart` (3 642 lignes)

**Où** `lib/features/chat/`
**Pourquoi si gros** Il concentre texte, fichiers, images, vidéos, vocaux,
positions, autocollants, réactions, réponses, recherche, accusés.

**Repères de lecture**
- `_ChatScreenState` — l'état : lecture audio, enregistrement, recherche
- `_send()` — envoi
- `_startRecording()` / `_stopRecording()` — vocal
- `_openMessageActions(m)` — le menu contextuel
- `_runSearch()` / `_jumpToMessage()` — recherche
- `_MessageBubble` — **la bulle** ; c'est ici qu'on change l'apparence
- `_InputBar` — la barre de saisie
- `_VideoBubble`, `_ImageBubble` — médias

**Comment ajouter un type de bulle** Dans `_MessageBubble.build`, ajouter une
branche selon `message.type` ou le type MIME, puis créer le widget.

---

### Fiche — le code natif Android

**Où** `android/app/src/main/kotlin/com/droplet/droplet/`
**Pourquoi du natif** Deux choses que Flutter ne sait pas faire seul :
changer l'icône de l'application, et manipuler la vidéo. 477 lignes de Kotlin
au total — c'est peu, et c'est voulu : **tout ce qui peut rester en Dart y
reste**.

**Le principe des ponts natifs.** Dart et Kotlin communiquent par
`MethodChannel` : un canal nommé, sur lequel Dart envoie un nom de méthode et
des arguments, et reçoit une réponse. Deux canaux existent :

| Canal | Côté Dart | Côté Kotlin |
|-------|-----------|-------------|
| `com.droplet.droplet/app_icon` | `app_icon_service.dart` | `MainActivity.kt` |
| `com.droplet.droplet/media` | `media_service.dart` | `MediaBridge.kt` |

Pour ajouter une fonction native : déclarer la méthode dans le `when` côté
Kotlin, et l'appeler via `_channel.invokeMethod('nom', {args})` côté Dart.
**Prévoyez toujours le cas où le natif échoue** — `media_service.dart` renvoie
`null` ou une valeur de repli plutôt que de propager l'exception.

---

#### `MainActivity.kt` (120 lignes) — les 13 icônes

**Le problème.** Android fige l'icône d'une application au moment de
l'installation : elle est lue dans le manifeste et ne peut pas être remplacée à
l'exécution.

**La solution.** Déclarer **plusieurs points d'entrée** vers la même activité —
des `activity-alias`, chacun avec sa propre icône — et n'en garder qu'un seul
activé. Le lanceur affiche l'icône de l'alias actif ; les autres sont
désactivés, donc invisibles.

Le manifeste déclare donc 13 alias : `.LauncherDefault` puis `.LauncherV1` à
`.LauncherV12`. `aliases()` les énumère (`listOf(defaultAlias) + (1..12)`).

**Deux pièges à connaître — ce sont d'excellentes réponses de soutenance.**

1. **L'ordre est critique.** `applyIcon()` **active** le nouvel alias *avant* de
   désactiver l'ancien. Dans l'ordre inverse, si le processus était tué entre
   les deux, l'application n'aurait plus **aucun** point d'entrée activé : elle
   disparaîtrait du lanceur, sans aucun moyen de la rouvrir.

2. **Le changement ferme l'application.** Désactiver le composant par lequel
   l'app a été lancée revient à couper la branche sur laquelle on est assis :
   Android termine le processus. C'est le comportement normal, y compris chez
   les grandes applications — l'interface prévient donc l'utilisateur avant.

**Comment ajouter une 14ᵉ icône**
1. Déposer l'image source dans `assets/icon/variants/droplet_13.png`
2. `python3 tool/build_icon_variants.py` (étendre la boucle à `range(1, 14)`)
3. Ajouter un `<activity-alias android:name=".LauncherV13">` au manifeste
4. `MainActivity.kt` → `(1..13)`
5. `app_icon_service.dart` → ajouter l'entrée dans la liste des variantes

Oublier l'étape 3 ou 4 produit un échec silencieux : l'utilisateur choisit
l'icône, rien ne se passe.

---

#### `MediaBridge.kt` (357 lignes) — vidéo, galerie, température

Trois services, exposés par le canal `media` :

**`videoDurationMs(path)`** — durée d'une vidéo, ou `-1` si illisible.

**`trimVideo(path, maxMs)`** — coupe une vidéo à la durée voulue.
*Pourquoi c'est en natif* : couper une vidéo ne consiste pas à tronquer des
octets. Un MP4 est un conteneur qui décrit où se trouve chaque image, et les
images dépendent les unes des autres. La solution habituelle — embarquer
ffmpeg — ajouterait plusieurs dizaines de méga-octets. Android sait le faire
nativement : `MediaExtractor` lit les échantillons, `MediaMuxer` les réécrit
**sans les décoder** — instantané et sans perte.

Quatre subtilités que le code traite explicitement :
- une durée illisible (`-1`) n'est **pas** une durée trop longue : on renvoie
  le fichier tel quel plutôt que de le casser ;
- l'orientation doit être recopiée (`setOrientationHint`), sinon une vidéo
  filmée en portrait ressort couchée ;
- chaque piste s'arrête **pour elle-même** : l'image et le son ne franchissent
  pas la limite au même moment, et sortir de la boucle au premier échantillon
  trop tardif interrompait la copie trop tôt ;
- le résultat est **vérifié** avant d'être renvoyé (taille, durée relisible),
  sinon on rend l'original.

**`saveToGallery(path, name, mime)`** — dépose un fichier reçu dans la galerie.
*Pourquoi en natif* : depuis Android 10, une application n'écrit plus librement
dans les dossiers publics. Il faut passer par `MediaStore`, qui range le fichier
au bon endroit et prévient la galerie. Le drapeau `IS_PENDING` le masque tant
que la copie n'est pas terminée.

**`thermalStatus()`** — niveau de surchauffe, de 0 à 6.
*Pourquoi une messagerie s'en soucie* : **à partir de 3, Android coupe les
encodeurs vidéo**. La caméra continue d'afficher son aperçu, le micro
d'enregistrer, mais plus une image n'atteint l'encodeur. C'est ce qui produisait
un fichier ne contenant que du son. Cette valeur sert à deux choses : prévenir
l'utilisateur avant qu'il ne filme pour rien, et désactiver automatiquement les
effets graphiques coûteux (`thermal_provider.dart` → `ouro_glass.dart`).

**Comment déboguer le natif**
```bash
adb logcat | grep -E "MediaBridge|MPEG4Writer|Camera"
adb shell dumpsys thermalservice | grep "Thermal Status"
```

---

### Fiche — les trois transports

| | BLE | Wi-Fi local | Wi-Fi Direct |
|--|-----|-------------|--------------|
| Fichier | `ble_mesh_transport.dart` | `local_wifi_transport.dart` | `native_p2p_transport.dart` |
| Découverte | scan + publicité GATT | balises UDP + nsd | Nearby Connections |
| Transmission | écritures de 19 octets | socket TCP | API Nearby |
| Charge max | **512 octets** | illimitée | grande |
| Fichiers | **refusés** (`type >= 0x20`) | oui | oui |
| Débit | ~950 o/s | ~1 Mo/s | rapide |
| Piège connu | reste inactif si le démarrage échoue (corrigé) | isolation des clients sur certains points d'accès | **une seule connexion à la fois** (BUSY) |

---

## 6. Les décisions de conception et leur raison

> **Ce sont les questions que pose un jury.** Chaque décision est présentée
> avec l'alternative écartée et pourquoi.

### Pourquoi le compteur de sauts dans le premier octet ?

Il doit être lisible et modifiable **sans déchiffrer**. Un relais décrémente
ce compteur ; s'il était dans la partie chiffrée, il faudrait la clé — ce qui
ruinerait le chiffrement de bout en bout.

### Pourquoi un filtre de Bloom en plus de la table `SeenMessageIds` ?

La vérification a lieu **à chaque paquet reçu**. Un accès disque à chaque fois
serait coûteux. Le filtre répond « certainement pas vu » ou « peut-être vu » ;
seul le second cas déclenche une lecture en base. Dimensionné à 50 000 entrées
pour 0,1 % de faux positifs.

*Alternative écartée* : tout garder en mémoire — impossible, la table doit
survivre au redémarrage.

### Pourquoi les Sender Keys pour les groupes ?

Chiffrer individuellement pour chaque membre multiplierait le trafic par le
nombre de destinataires. À deux messages par seconde en Bluetooth, un groupe de
cinq deviendrait inutilisable. Avec les Sender Keys, on chiffre **une fois**.

*Prix à payer* : il faut gérer les messages arrivant dans le désordre, d'où le
compteur et les clés sautées.

### Pourquoi `GroupMembers` n'efface jamais une ligne ?

Sans serveur, deux appareils en désaccord ne peuvent trancher qu'en comparant
des dates. Si l'un a effacé la ligne, il n'a plus rien à comparer, et l'ajout
plus ancien de l'autre l'emporterait à tort. On inscrit donc `removedAt`
(technique du « tombstone »).

### Pourquoi la métrique de routage tient compte de la batterie ?

`0,4 × latence + 0,4 × (1 − fiabilité) + 0,2 × (1 − batterie)`

Router systématiquement par l'appareil le plus rapide viderait sa batterie et
ferait **disparaître le meilleur relais** du maillage. C'est ce qui distingue
un réseau de téléphones d'un réseau d'équipements fixes.

### Pourquoi le Bluetooth refuse les fichiers ?

19 octets par écriture. Une photo de 250 Ko = ~13 000 écritures ≈ 4 minutes
d'antenne pour une seule photo. Le refus est le bon choix.

*Conséquence assumée* : sans Wi-Fi, pas de fichiers. Le rapport le dit.

### Pourquoi la clé privée n'est pas dans la base ?

Une sauvegarde de la base ne doit pas emporter l'identité. Elle vit dans le
Keystore Android via `flutter_secure_storage`.

### Pourquoi `sendToPeer` renvoie un booléen ?

**C'est la correction majeure du projet.** Elle renvoyait `void` : un refus du
transport était indiscernable d'un succès, et la file comptait le message comme
livré. Mesuré : 130 annoncés, 110 reçus.

---

## 7. Recettes — « je veux modifier… »

### …la couleur principale de l'application
`lib/design_system/ouro_colors.dart` → `accent`. Vérifiez les deux modes.

### …ajouter un écran
1. Créer `lib/features/<domaine>/mon_ecran.dart`
2. L'enregistrer dans `lib/main.dart` (`GoRoute`)
3. Choisir la transition : `_pushPage` (descente) ou `_modalPage` (parenthèse)

### …ajouter un champ à un message
1. `lib/core/database/app_database.dart` → colonne dans `MeshMessages`
2. `lib/core/models/mesh_message.dart` → champ + `fromJson`/`toJson`
3. `flutter pub run build_runner build --delete-conflicting-outputs`
4. Gérer la migration de schéma dans `app_database.dart`

### …ajouter un type de message sur le réseau
1. Choisir un `kind` dans `mesh_repository.dart`
2. Écrire `sendMonType(...)` sur le modèle de `sendReaction`
3. Aiguiller dans `_handleIncomingMessage`
4. Exposer un `Stream` et l'écouter dans un provider
5. **Attention** : type ≥ 0x20 ⇒ refusé en Bluetooth

### …changer le nombre de relances
`lib/core/network/premium_message_queue.dart` → `maxRetries`. Le délai est dans
`retryDelay`.

### …changer la portée du relais
Deux constantes, à ne pas confondre :
- `lib/core/repositories/mesh_repository.dart` ligne 857 →
  `kDefaultHopCount = 5` : le nombre de sauts inscrit dans **chaque message
  émis**. C'est celle qui compte en pratique.
- `lib/core/protocol/droplet_mesh_protocol.dart` ligne 22 → `maxHops = 10` :
  la borne du protocole de routage.

### …déboguer un problème réseau
```bash
flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb logcat | grep -E "MeshRepo|BLE|NativeP2P|LocalWifi"
```
Les traces sont préfixées par module — sans ce filtre, elles se noient.

### …lancer les tests
```bash
flutter analyze          # analyse statique
flutter test             # 63 tests
flutter test test/two_peer_session_test.dart   # le banc à deux pairs
```

---

## 8. Questions de jury probables

> Pour chacune : la réponse courte, puis **où pointer dans le code**.

**« Où est le serveur ? »**
Il n'y en a pas. Chaque appareil exécute la pile complète. Montrez le diagramme
de déploiement, ou `main.dart` : aucune URL, aucun client HTTP pour la
messagerie.

**« Comment un message trouve-t-il son destinataire sans serveur ? »**
Deux mécanismes. Si le pair est joignable directement, envoi direct
(`sendViaRoute`). Sinon, table de routage alimentée par la métrique composite,
et à défaut diffusion avec compteur de sauts et déduplication.

**« Qu'est-ce qui empêche un message de tourner en boucle ? »**
Deux garde-fous indépendants : le compteur de sauts (octet 0, décrémenté à
chaque relais, abandonné à zéro) et la déduplication par identifiant
(`SeenMessageIds` + filtre de Bloom).

**« Un relais peut-il lire les messages ? »**
Non. La clé de session est dérivée entre l'émetteur et le destinataire
uniquement. `_handleIncomingMessage` : si le message ne m'est pas destiné, il
est relayé **sans passer par `decryptBytes`**.

**« Comment savez-vous que le chiffrement fonctionne ? »**
Le banc à deux pairs : le correspondant dérive son secret de son côté et
déchiffre réellement. Un test vérifie que les 25 messages d'un lot sont
déchiffrés à l'identique. `test/two_peer_session_test.dart`.

**« Quel est votre taux de fiabilité ? »**
100 % en Wi-Fi. En Bluetooth, 100 % pour les messages courts, 0 % pour les
fichiers — refusés par le transport, et **signalés comme échoués**. La nuance
est le résultat principal du projet : avant correction, l'application annonçait
130 livrés pour 110 réellement reçus.

**« Le relais multi-hop, l'avez-vous testé ? »**
*Réponse honnête* : le protocole est implémenté et testé unitairement, mais la
validation terrain exige trois appareils dont deux hors de portée. Elle n'a pas
été faite. C'est la première perspective du chapitre 20.

**« Pourquoi Flutter et pas du natif ? »**
Base de code unique pour deux plateformes, et l'écosystème fournit des plugins
pour les trois radios. *Limite assumée* : les technologies de proximité
employées sont spécifiques à Android ; le portage iOS exigerait
MultipeerConnectivity.

**« Combien de temps pour envoyer une photo ? »**
En Wi-Fi, quelques secondes. En Bluetooth, elle ne part pas — c'est un choix :
13 000 écritures de 19 octets prendraient plusieurs minutes.

**« Quelle est la faille de votre modèle de sécurité ? »**
Trois, assumées : pas d'autorité de certification (TOFU) ; un appareil
déverrouillé donne accès à tout ; les **métadonnées circulent en clair** — les
relais doivent savoir à qui router. Un observateur sait qui parle à qui, sans
savoir de quoi.

**« Pourquoi avoir écrit du code natif ? »**
Deux choses seulement, et par nécessité. Changer l'icône : Android la fige à
l'installation, la seule méthode officielle passe par des `activity-alias`
activés depuis le code natif. Manipuler la vidéo : la découpe exige de réécrire
le conteneur MP4, et l'alternative — embarquer ffmpeg — ajouterait plusieurs
dizaines de méga-octets. 477 lignes de Kotlin sur 45 000 lignes de projet.

**« Pourquoi lisez-vous la température du téléphone ? »**
Parce qu'à partir du niveau 3, Android coupe les encodeurs vidéo sans le dire.
Nous l'avons découvert en cherchant pourquoi un enregistrement produisait un
fichier ne contenant que du son. La valeur sert désormais à prévenir
l'utilisateur, et à désactiver automatiquement les effets graphiques coûteux.

**« Si vous aviez trois mois de plus ? »**
Dans l'ordre : essai sur trois appareils, état « en attente de Wi-Fi » pour les
fichiers, fragmentation applicative au-delà de 512 octets, mesure de batterie.

---

## 9. Glossaire

| Terme | Ce que ça veut dire ici |
|-------|------------------------|
| **AIMD** | Contrôle de congestion : on augmente doucement le débit, on le divise brutalement en cas d'échec |
| **Backoff exponentiel** | Chaque relance attend deux fois plus longtemps |
| **Filtre de Bloom** | Structure qui répond « certainement pas » ou « peut-être », sans stocker les données |
| **ECDH** | Deux appareils calculent le même secret sans jamais l'échanger |
| **GATT** | Le protocole d'échange du Bluetooth Low Energy |
| **Gigue (jitter)** | Délai aléatoire ajouté pour éviter que tout le monde réessaie ensemble |
| **Hop count** | Nombre de relais restants avant abandon |
| **LWW** | *Last Write Wins* — en cas de conflit, la date la plus récente gagne |
| **MTU** | Taille maximale d'un paquet. En BLE sans négociation : 20 octets |
| **Nonce** | Nombre utilisé une seule fois. Public, mais jamais réutilisé |
| **PDR** | *Packet Delivery Ratio* — proportion de paquets arrivés |
| **Ratchet** | Clé qui avance à chaque message ; une clé compromise ne révèle pas les précédentes |
| **Sender Key** | Chaîne de clés propre à chaque membre d'un groupe |
| **Squelch / TOFU** | *Trust On First Use* — on fait confiance à la première clé vue, on alerte si elle change |
| **Store-and-forward** | Garder un message jusqu'à ce qu'un chemin existe |
| **Tombstone** | Marquer comme supprimé au lieu d'effacer, pour pouvoir arbitrer plus tard |

---

## Dernier conseil

Si vous ne devez retenir qu'une chose pour la soutenance : **ce projet ne se
défend pas sur ce qu'il fait, mais sur ce qu'il sait de lui-même.**

N'importe qui peut montrer une application qui envoie des messages. Peu de
projets étudiants peuvent dire : *« nous annoncions 100 % de livraison, nous
avons construit le moyen de le vérifier, et nous avons découvert que c'était
faux. »*

C'est votre meilleur argument. Il est vrai, il est mesuré, et il est
reproductible en une commande.
