# Droplet — audit de fond et mise à niveau « publiable »

**Date :** 13 août 2026
**Portée :** l'ensemble du dépôt (Dart, Kotlin, Gradle, manifeste Android)
**Vérifications :** `flutter analyze` propre sur tout le dépôt · 68/68 tests ·
APK debug compilé · **compilation release en cours de validation** (R8 vient
d'être activé — voir §3.7)

---

## Ce qui était demandé

Trois choses :

1. l'application se ferme quand on ouvre la carte ;
2. les animations de cœurs de la conversation sont très lentes ;
3. analyser le projet de fond en comble et l'amener au statut de projet
   publiable.

Ce document répond aux trois, dans cet ordre, et se termine par ce qui
reste **honnêtement** à faire avant une mise en ligne.

---

## 1. Les animations de cœurs — résolu, cause certaine

### Ce qui n'allait pas

L'animation construisait, **pour chacun des 28 cœurs et à chaque image** :

```
Positioned → Transform.rotate → Transform.scale → Opacity → Text('❤️')
```

Deux coûts s'additionnaient, tous deux invisibles à la lecture du code :

**Le premier, et de loin le pire : `Opacity`.** Ce widget n'est pas un
réglage de couleur. Il oblige le moteur de rendu à dessiner tout son
contenu dans une **image hors-écran séparée**, puis à recomposer cette
image par-dessus le reste — ce qu'on appelle un « saveLayer ». Vingt-huit
allers-retours hors-écran par image, soixante fois par seconde.

**Le second : `Text('❤️')`.** Chaque cœur avait une taille tirée au
hasard, donc 28 tailles de police différentes, chacune remise en page et
re-rastérisée.

À quoi s'ajoutait la reconstruction de ~140 widgets par image, et un
`MediaQuery.of(context)` appelé 28 fois par image.

La pluie de confettis souffrait exactement du même défaut, en pire : 45
particules.

### Ce qui a été fait

Les deux effets sont passés en **un seul `CustomPaint`** :

| | Avant | Après |
|---|---|---|
| Widgets reconstruits par image | ~140 (cœurs) / ~225 (confettis) | **0** |
| Rendus hors-écran par image | 29 / 45 | **0** |
| Mise en page de texte par image | 28 | **0** |
| Objets `Paint` créés par image | 28 / 45 | **1** |

Le cœur est devenu une **forme vectorielle** (deux courbes de Bézier,
construite une fois pour toutes) mise à l'échelle par le canevas. La
transparence est portée par la couleur du pinceau — donc gratuite. Et le
peintre est branché directement sur le contrôleur d'animation
(`super(repaint: animation)`), ce qui veut dire que Flutter **ne
reconstruit plus aucun widget** pendant les 1,8 seconde : il se contente
de redessiner.

Un garde-fou a été ajouté : **une salve à la fois**. Cinq double-taps
rapides empilaient cinq animations simultanées.

Le champ d'étincelles (`message_effects.dart`) était déjà un
`CustomPaint`, mais fabriquait un objet `Paint` par étincelle et par
image — quatre mille objets jetables par seconde. Un seul pinceau
réutilisé désormais.

**Vérifié par :** 5 nouveaux tests (`test/effets_overlay_test.dart`) qui
échouent si un `Opacity` ou un `Text` réapparaît dans ces overlays, et si
les salves se remettent à s'empiler.

---

## 2. Le plantage de la carte — trois défauts réels corrigés, cause non confirmée

**Je dois être franc sur ce point : je n'ai pas pu reproduire le
plantage.** Le téléphone s'est déconnecté (`adb devices` ne renvoie plus
rien) avant que j'aie pu capturer le journal système. Une app qui « se
ferme » sans écran rouge est presque toujours tuée par le **système**
(mémoire, plantage natif, descripteurs épuisés) — et ces causes-là ne
laissent aucune trace côté Dart. Sans `adb logcat` au moment des faits,
désigner un coupable serait une supposition présentée comme un
diagnostic.

En revanche, l'analyse du code a mis au jour **trois défauts réels**, dont
un très sérieux, et tous trois sont corrigés.

### 2.1 Une fuite de sockets, à chaque pas de l'utilisateur ⚠️

Le fournisseur de tuiles était fabriqué **à l'intérieur de `build()`** :

```dart
TileLayer(
  tileProvider: OfflineFirstTileProvider(allowNetwork: !_offlineOnly),
```

Or `OfflineFirstTileProvider` possède un `http.Client` — donc un pool de
connexions, donc des **descripteurs de fichiers** ouverts vers les quatre
sous-domaines du CDN.

Et `build()` est rappelé à chaque relevé GPS (tous les 10 mètres), à
chaque check-in de sécurité reçu, à chaque tap sur la carte.

J'ai vérifié le comportement de `flutter_map` 8.3.1 dans son code source :

```dart
// tile_layer.dart, ligne 517
@override
void dispose() {
  …
  widget.tileProvider.dispose();
```

`dispose()` ferme le fournisseur — mais **`didUpdateWidget` ne le fait
pas**. Chaque nouveau fournisseur remplaçait donc le précédent sans que
personne ne referme l'ancien. Marcher dix minutes avec la carte ouverte
abandonnait des dizaines de clients HTTP vivants, chacun avec ses
sockets. Un processus Android qui épuise son quota de descripteurs est
tué **sans message et sans écran d'erreur** — exactement le symptôme
décrit.

Effet secondaire visible, lui aussi expliqué : les téléchargements de
tuiles en cours étaient coupés net à chaque pas, d'où des cases qui
restaient vides pendant qu'on se déplace.

**Corrigé :** un seul fournisseur, créé dans `initState`, refermé dans
`dispose`, remplacé uniquement lors du basculement en ligne / hors
connexion (avec fermeture explicite de l'ancien).

Au passage : `MapController` était créé par l'écran mais jamais refermé —
`FlutterMap` ne libère que les contrôleurs qu'il crée lui-même. Corrigé
aussi.

### 2.2 Des coordonnées venues du réseau, jamais vérifiées ⚠️

Les positions affichées sur la carte **ne sont pas mesurées ici** : elles
arrivent d'autres appareils, par le mesh. Et Droplet n'a **aucun serveur
central** qui aurait pu les valider au passage.

Rien ne les vérifiait. J'ai contrôlé le code de `latlong2` 0.10.1 :

```dart
const LatLng(this.latitude, this.longitude);   // aucune validation
```

Une latitude de 400, ou `NaN` — GPS défaillant, trame abîmée par une
liaison Bluetooth médiocre, ou message fabriqué — passe donc sans
broncher. C'est plus loin que ça casse : la projection Web Mercator fait
passer la valeur dans un logarithme, qui rend l'infini, qui devient une
coordonnée d'écran `NaN`, qui descend jusqu'au moteur de rendu. À ce
stade il n'y a plus de message exploitable : juste une carte qui refuse
de s'afficher.

**Autrement dit : n'importe quel pair pouvait décider si votre carte
s'affiche.**

**Corrigé :** filtre à l'entrée (`_coordonneesSaines`) — valeurs finies,
latitude strictement entre −90 et 90 (les pôles exacts font diverger la
projection), longitude entre −180 et 180.

Corrigé aussi : `me.accuracy.clamp(8, 120)` ne rattrapait pas un `NaN` —
les comparaisons avec `NaN` étant toutes fausses, `clamp` le renvoie tel
quel.

### 2.3 Une tuile abîmée empoisonnait sa zone pour de bon

Le décodage d'une tuile venant du cache n'était pas protégé. Une écriture
interrompue, une réponse tronquée — et l'exception remontait. Pire :
comme la tuile restait en base, **elle rejouait l'erreur à chaque
affichage de cette zone, indéfiniment**.

**Corrigé :** décodage protégé, et la tuile fautive est **supprimée** du
cache (`OfflineTileStore.evict`) pour se laisser retélécharger. Le cache
ne touche jamais aux cartes `.mbtiles` importées par l'utilisateur, qui
ne nous appartiennent pas.

Et l'ordre a été inversé côté réseau : une tuile n'est **rangée qu'après
avoir été prouvée lisible**. Auparavant, une page d'erreur renvoyée par un
portail captif était enregistrée comme si c'était une image.

### 2.4 Ce qui a été ajouté pour trancher la question

L'application n'avait **aucun mécanisme de capture d'erreur** : ni
`FlutterError.onError`, ni `PlatformDispatcher.instance.onError`, ni
`runZonedGuarded`. Une erreur non attrapée ne laissait donc strictement
aucune trace une fois l'app relancée. C'est précisément ce qui rend ce
plantage-ci si difficile à cerner.

`lib/core/services/crash_journal.dart` branche désormais les **deux**
crochets d'erreur de Flutter et écrit dans un journal local
(`droplet-erreurs.log`, 64 Ko glissants, aucun envoi réseau, aucun contenu
de message). Il tranche une question utile : **si l'app se ferme et que le
journal est vide, la cause n'est pas côté Dart** — c'est le natif ou le
système.

La mémoire d'images a par ailleurs été bornée à 48 Mo (le défaut de
Flutter est 100 Mo, pensé pour un écran de bureau). Chaque tuile décodée
pèse 256 Ko : parcourir une carte suffisait à remplir ce budget, et
Android ferme les apps qui pèsent trop lourd — sans message.

> **Ce qu'il reste à faire, et que je ne peux pas faire seul :**
> rebrancher le téléphone, ouvrir la carte jusqu'au plantage, puis relever
> `adb logcat`. Une signature native (`SIGSEGV`, `lowmemorykiller`,
> `too many open files`) donnera la réponse définitive. Les trois défauts
> ci-dessus sont réels et valaient d'être corrigés quoi qu'il arrive,
> mais je ne peux pas affirmer que l'un d'eux était *le* coupable.

---

## 3. Audit de fond

### 3.1 Fuites de ressources — sain

Audit automatisé de toutes les classes `State` du projet, pour neuf types
de ressources devant être libérées (`AnimationController`,
`StreamSubscription`, `Timer`, `TextEditingController`, `ScrollController`,
`PageController`, `FocusNode`, `TabController`, `VideoPlayerController`).

**Résultat : aucune fuite.** Les deux cas signalés par l'outil
(`status_viewer_screen.dart`) sont des faux positifs — vérifiés à la main,
ils sont bien libérés.

La seule fuite réelle du projet était le fournisseur de tuiles (§2.1).

### 3.2 Coût de rendu dans les listes — sain

Recherche des filtres coûteux (`BackdropFilter`, `ImageFiltered`,
`ShaderMask`, `Opacity`) à l'intérieur des constructeurs d'éléments de
liste — le péché classique qui fait saccader un défilement.

**Résultat : aucun.** Les effets de verre sont sur les barres fixes, pas
sur le contenu qui défile.

### 3.3 Deux coûts cachés dans l'écran de conversation — corrigés

**Une recherche en O(n²) dans le chemin de défilement.** Retrouver le
message cité se faisait ainsi, dans le constructeur de **chaque bulle** :

```dart
replied = messages.where((x) => x.id == m.replyToId).firstOrNull;
```

Soit un balayage de toute la conversation, par bulle citée et par image.
Dans un fil de mille messages où l'on se répond souvent : des dizaines de
milliers de comparaisons soixante fois par seconde, **pendant le
défilement**, c'est-à-dire au pire moment. Remplacé par un index construit
une fois par image.

**Un décodage JSON complet, deux fois par image.**
`StorageService.getPeerRecord()` n'est pas une lecture de champ : il
redécode en JSON **toute la table des pairs connus**. Il était appelé deux
fois dans `build()`. Une seule lecture désormais.

**Et un annuaire de `GlobalKey` qui ne se vidait jamais** — une clé par
message affiché, conservée pour le reste de la session. Nettoyé au-delà
d'un seuil.

### 3.4 Un défaut visible corrigé : l'identifiant brut en titre

Une conversation s'intitulait `baee7a1f92f5e7d51b92…` au lieu du
pseudonyme. La cause : le pseudonyme n'était cherché que dans la liste des
pairs **connectés à cet instant**.

Or dans une application mesh, **l'état normal d'un contact est d'être hors
de portée**. On ouvre une conversation pour relire, pour écrire un message
qui partira plus tard. Ce n'était donc pas un cas rare : l'identifiant
brut apparaissait dès qu'on s'éloignait de quelques mètres.

La table des pairs déjà rencontrés — qui, elle, survit aux déconnexions —
est désormais interrogée en premier. En tout dernier recours, pour un pair
dont on n'a jamais appris le nom, on affiche `Pair baee7a1f` plutôt que
soixante-quatre caractères hexadécimaux.

### 3.5 Une perte de données silencieuse : le « message illisible » ⚠️

Le message `🔒 Message illisible (clé de chiffrement manquante)` qui
restait indéfiniment dans la liste des conversations n'était pas un défaut
d'affichage. **C'était une perte de données définitive.**

Le mécanisme : quand un message chiffré arrive avant qu'on connaisse la
clé publique de son auteur, c'est le **texte de substitution** qui est
enregistré à sa place. Le vrai contenu ne subsiste que sous forme
chiffrée, dans une liste `_pendingDecryptions` — **en mémoire vive
uniquement**.

Tant que l'application restait ouverte, la reprise fonctionnait : au
premier « hello » du bon auteur, le message était réparé. Mais si l'app se
fermait avant que la clé n'arrive, le chiffré disparaissait avec le
processus.

Or dans une application mesh, **c'est le cas le plus fréquent** : on
reçoit un message relayé par un tiers, on range son téléphone, et on ne
croise l'auteur que le lendemain. Le message restait alors barré d'un
cadenas pour toujours — alors que tout ce qui manquait était une clé qui
finissait par arriver.

**Corrigé :** la liste est désormais enregistrée sur le disque et relue au
démarrage, **avant** que le mesh ne démarre — pour que le premier
« hello » venu puisse réparer immédiatement. Conserver ces octets
n'affaiblit rien : ils sont déjà chiffrés, et sans la clé du pair ils ne
disent pas plus à qui lirait le stockage qu'ils n'en disaient sur le
réseau.

Un second défaut a été trouvé au passage dans la reprise : les chiffrés
étaient retirés de la liste **avant** la tentative de déchiffrement (à
raison — pour qu'un second « hello » simultané ne les traite pas en
double), mais **n'étaient pas rendus** si la clé se révélait finalement
inexploitable. Ils sont désormais remis en attente.

> Cette correction n'est **pas couverte par un test** : le dépôt n'a pas
> d'infrastructure permettant d'instancier `StorageService` hors appareil.
> Le changement reste contenu — il ajoute la persistance d'une liste qui
> existait déjà et ne touche pas à la logique de déchiffrement — mais il
> mérite une vérification sur appareil : recevoir un message d'un pair
> inconnu, **fermer l'app**, puis rencontrer ce pair.

### 3.6 Le blocage de publication le plus concret : la signature ⚠️

Le projet signait sa version « release » avec **la clé de débogage** —
c'est le modèle Flutter par défaut, laissé tel quel :

```kotlin
// TODO: Add your own signing config for the release build.
signingConfig = signingConfigs.getByName("debug")
```

Trois conséquences, dont une irréversible :

- **Google Play refuse** tout APK/AAB signé avec la clé de débogage.
- Cette clé est celle du SDK Android, **identique sur toutes les machines
  du monde** : n'importe qui peut fabriquer une « mise à jour » de Droplet
  que le téléphone acceptera d'installer par-dessus.
- Android identifie une application **par sa signature**. Publier avec une
  clé puis vouloir en changer oblige les utilisateurs à désinstaller et
  réinstaller — en perdant **toutes** leurs données locales. Or Droplet n'a
  pas de serveur : messages, contacts et clés de chiffrement ne vivent que
  sur l'appareil. Une désinstallation, ici, c'est une perte définitive.

**Fait :** `android/app/build.gradle.kts` lit désormais la clé dans
`android/key.properties` (déjà ignoré par git, ainsi que `*.jks` et
`*.keystore`). En son absence, la compilation retombe sur la clé de
débogage **avec un avertissement explicite** plutôt qu'un échec
silencieux — le projet reste compilable par quelqu'un qui n'a pas la clé.

**À faire par vous** (je ne peux pas générer un secret à votre place) :

```bash
keytool -genkey -v -keystore ~/droplet-release.jks \
        -keyalg RSA -keysize 2048 -validity 10000 -alias droplet
```

puis `android/key.properties` :

```
storeFile=/home/…/droplet-release.jks
storePassword=…
keyAlias=droplet
keyPassword=…
```

⚠️ **Ce fichier `.jks` est irremplaçable.** Le perdre, c'est perdre la
possibilité de publier la moindre mise à jour de Droplet, pour toujours.
Il se sauvegarde ailleurs que sur la machine de travail.

### 3.7 Minification R8 activée

La compilation release ne réduisait pas le code. C'est un enjeu de poids,
mais aussi de surface : Droplet embarque du code cryptographique et de
transport réseau, et réduire ce qui est réellement présent dans l'APK
réduit d'autant ce qu'un attaquant peut examiner.

`android/app/proguard-rules.pro` a été écrit avec les règles de
conservation nécessaires. Le point délicat est que R8 raisonne
statiquement : il ne voit pas les classes appelées **par réflexion depuis
le moteur Flutter** ni **depuis le natif par JNI**. Il conclut qu'elles
sont mortes et les supprime — et le symptôme est traître : la compilation
réussit, l'app démarre, et elle plante seulement quand on atteint la
fonction concernée.

Sont explicitement épargnés : Flutter et ses greffons, `MediaBridge.kt`
(atteint par nom de chaîne via MethodChannel), SQLite, le service premier
plan et les receveurs de diffusion (instanciés **par le système** depuis
le manifeste), les notifications et Gson, WebRTC, la géolocalisation,
Bluetooth/Wi-Fi Direct.

Les attributs `SourceFile` et `LineNumberTable` sont conservés : sans eux,
une pile d'appels de release n'a plus ni nom de fichier ni numéro de
ligne. Pour une app qui n'a **aucun serveur de télémétrie** — donc dont le
seul diagnostic possible est le journal local et ce que l'utilisateur veut
bien envoyer — s'en priver reviendrait à renoncer à corriger quoi que ce
soit après publication.

---

## Ce qui reste avant publication

Classé par ce qui bloque réellement.

### Bloquants

| # | Sujet | Pourquoi |
|---|---|---|
| 1 | **Générer la clé de signature** | Sans elle, Play refuse l'envoi. Voir §3.5 — ne peut pas être fait à votre place. |
| 2 | **Confirmer le plantage de la carte** | Les trois défauts corrigés sont réels, mais la cause exacte n'est pas prouvée. Reproduire avec `adb logcat` branché. |
| 3 | **Valider la version release sur appareil** | R8 vient d'être activé. Une classe supprimée à tort ne se voit qu'à l'exécution — parcourir **toutes** les fonctions : appel, carte, statuts, import de carte, notifications, service premier plan. |
| 4 | **Politique de confidentialité** | Play l'exige pour `ACCESS_FINE_LOCATION`, `CAMERA`, `RECORD_AUDIO`, `READ_MEDIA_*`. Droplet a un argument solide — rien ne quitte l'appareil — encore faut-il l'écrire. |
| 5 | **Déclaration des permissions sensibles** | La localisation en arrière-plan et le service premier plan `dataSync` demandent une justification écrite au moment de l'envoi. |

### Importants, non bloquants

| # | Sujet | Pourquoi |
|---|---|---|
| 6 | **Session réelle à deux appareils** | Le banc à faux pair (`RAPPORT_SESSION_DEUX_PAIRS.md`) a trouvé le mensonge de livraison, mais il ne remplace pas deux vrais téléphones : la portée BLE, les coupures, la thermique ne se simulent pas. |
| 7 | **Valider la réparation des messages illisibles** | Corrigé (§3.5), mais non couvert par un test : à vérifier sur appareil. |
| 8 | **Vérifier l'enregistrement vidéo au frais** | La panne était thermique (Thermal Status 4). À revalider sur un appareil sous 3. |
| 9 | **Trois écrans non commentés** | `backup_export_screen.dart`, `share_target_screen.dart`, `contribution_screen.dart` — le reste du projet l'est intégralement. |

### Ce que cet audit n'a pas couvert

Par honnêteté sur les limites :

- **La cryptographie n'a pas été auditée** ligne à ligne. Ratchet, clés de
  groupe et vérification d'empreinte relèvent d'une revue spécialisée.
- **Aucune mesure de consommation batterie** sur une longue durée, avec le
  service premier plan actif.
- **Aucun test sur autre chose qu'un Pixel 6 Pro.** Les couches Bluetooth
  et Wi-Fi Direct des constructeurs diffèrent notablement.
- **Aucun test d'accessibilité** (lecteur d'écran, gros caractères,
  contrastes).

---

## Récapitulatif des fichiers modifiés

| Fichier | Nature |
|---|---|
| `lib/shared/widgets/heart_burst_overlay.dart` | Réécrit en `CustomPaint` + anti-empilement |
| `lib/shared/widgets/confetti_overlay.dart` | Réécrit en `CustomPaint` + anti-empilement |
| `lib/shared/widgets/message_effects.dart` | Pinceau réutilisé |
| `lib/features/maps/map_screen.dart` | Fuite de sockets, validation des coordonnées, `NaN`, `MapController` |
| `lib/features/maps/offline_tile_provider.dart` | Décodage protégé, ordre décoder-puis-ranger |
| `lib/features/maps/offline_tile_store.dart` | `evict()` |
| `lib/features/chat/chat_screen.dart` | O(n²) supprimé, JSON dédoublé, titre, `GlobalKey` |
| `lib/core/repositories/mesh_repository.dart` | Messages en attente de clé persistés |
| `lib/features/settings/settings_screen.dart` | Écran de lecture du journal d'erreurs |
| `lib/core/services/crash_journal.dart` | **Nouveau** — boîte noire |
| `lib/main.dart` | Journal branché, mémoire d'images bornée |
| `android/app/build.gradle.kts` | Signature de publication, R8 |
| `android/app/proguard-rules.pro` | **Nouveau** — règles de conservation |
| `test/effets_overlay_test.dart` | **Nouveau** — 5 tests |
