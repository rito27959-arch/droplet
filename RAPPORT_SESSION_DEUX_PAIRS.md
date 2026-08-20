# Session à deux pairs — ce que le banc d'essai a constaté

**Date :** 13 août 2026
**Banc :** `test/two_peer_session_test.dart`
**Lot :** 100 messages texte · 20 fichiers de 250 Ko · 10 positions

---

## Comment lire ce rapport

Le faux pair n'a de faux que **la radio**. Tout le reste est le vrai code de
Droplet : les vraies clés X25519, le vrai secret partagé, le vrai AES-GCM, la
vraie enveloppe de `sendMessage`, la vraie file `PremiumMessageQueue` avec ses
relances et son backoff exponentiel. Le pair **déchiffre réellement** ce qu'il
reçoit et refuse ce qui est abîmé — sans quoi les chiffres ci-dessous ne
voudraient rien dire.

Deux temps sont donnés, et ils ne doivent jamais être confondus :

| | Ce que c'est |
|---|---|
| **Temps logiciel** | Mesuré pour de vrai : chiffrement, mise en forme, file, relances |
| **Temps antenne** | **Calculé** à partir de la taille réelle des trames et du débit du transport |

Personne ne peut simuler honnêtement un Bluetooth qui traverse un mur. Le
temps d'antenne est donc une arithmétique, pas une mesure. Il reste utile :
il repose sur la taille de fragment que le code utilise réellement.

**Ce banc ne remplace pas un essai à deux téléphones.** Il répond à la moitié
des questions — celle qui dépend du code. L'autre moitié (portée, murs,
batterie, coupures en pleine transmission) exige deux appareils.

---

## Les mesures

### Wi-Fi local

```
Envois mis en file        : 130
Arrivés                   : 130  (100,00 %)
Perdus définitivement     : 0
Refusés par le transport  : 0
Réellement reçus par B    : 130
Tentatives totales        : 131
Relances par message      : 0,008
Octets réellement émis    : 5 485 Kio
Temps LOGICIEL (mesuré)   : 8,1 s
Temps ANTENNE (calculé)   : 6,5 s
Latence médiane en file   : 2,4 ms
```

### Bluetooth LE

```
Envois mis en file        : 130
Arrivés                   : 130  (100,00 %)   ← à lire avec la ligne suivante
Perdus définitivement     : 0
Refusés par le transport  : 20
Réellement reçus par B    : 110               ← 20 de moins
Tentatives totales        : 138
Relances par message      : 0,062
Octets réellement émis    : 20,5 Kio
Temps LOGICIEL (mesuré)   : 4,1 s
Temps ANTENNE (calculé)   : 50,5 s
Latence médiane en file   : 1,5 ms
```

---

## Constat n° 1 — Un message peut être compté « livré » sans jamais partir

**C'est le résultat le plus important de cette session.**

En Bluetooth, la file annonce **130 livrés sur 130**. Le pair n'en a reçu que
**110**. Les vingt fichiers ont été écartés par le transport, et **ce refus a
été rapporté comme un succès**.

La cause tient en deux lignes, dans `mesh_transport_service.dart` :

```dart
Future<bool> sendViaRoute(String peerId, Uint8List data, {int type = 0x00}) async {
  if (_peers.containsKey(peerId)) {
    await sendToPeer(peerId, data, type: type);
    return true;                                  // ← toujours vrai
  }
```

`sendToPeer` ne renvoie **rien** (`Future<void>`). `sendViaRoute` renvoie donc
`true` dès lors qu'un pair est *connu*, avant même de savoir si quoi que ce
soit est parti. En face, `ble_mesh_transport.dart` écarte silencieusement :

```dart
if (type >= 0x20) { debugPrint('[BLE] Refusé …'); return; }
if (data.length > _maxPayloadSize) { debugPrint('[BLE] Refusé …'); return; }
```

Un `debugPrint`, et le message est perdu. La file le compte comme délivré,
l'interface affiche deux coches, l'utilisateur croit avoir envoyé.

**Conséquence directe :** le taux de livraison affiché par l'application est,
en l'état, **un taux d'émission tentée**, pas un taux de réception. Toute
mesure de fiabilité faite sur ce chiffre est fausse — y compris celle que je
recommandais de faire à deux appareils.

**Ce qu'il faudrait :** que `sendToPeer` renvoie un booléen, que chaque
transport dise s'il a accepté la charge, et que `sendViaRoute` propage ce
résultat. La file sait déjà relancer ; il lui manque seulement d'être
prévenue.

---

## Constat n° 2 — À 210 caractères, un message cesse de passer en Bluetooth

Taille réelle des trames chiffrées, mesurée avec des identifiants de
64 caractères hexadécimaux (ce que produit `generateCryptoIdentity`) :

| Contenu | Trame | Limite BLE |
|---|---:|---|
| « Ok » | **233 o** | 512 o |
| Message ordinaire (38 caractères) | **281 o** | 512 o |
| 200 caractères | **497 o** | 512 o — il reste 15 octets |
| 300 caractères | **633 o** | **dépassée** |

**233 octets d'enveloppe pour deux caractères de texte.** Le poids vient des
deux identifiants de 64 caractères (`s` et `t`), du base64 du chiffré et de
celui du nonce.

Le seuil de rupture est donc autour de **210 caractères** — la longueur d'un
SMS un peu bavard. Au-delà, en Bluetooth seul, le message est écarté **et
compté comme livré** (constat n° 1). Aucun avertissement, aucune trace visible
par l'utilisateur.

**Deux corrections possibles, cumulables :**
1. Raccourcir l'enveloppe — les identifiants pourraient voyager en binaire
   plutôt qu'en hexadécimal (32 octets au lieu de 64 caractères), ce qui rend
   ~64 octets par message.
2. Fragmenter au niveau applicatif quand la charge dépasse la limite du
   transport choisi, au lieu de la refuser.

---

## Constat n° 3 — Sans Wi-Fi, aucun fichier ne circule

`ble_mesh_transport.dart` porte ce commentaire :

> « BLE ne porte jamais de fichier ni de flux audio. »

**C'est une bonne décision**, et le banc le confirme par le calcul : le
protocole découpe en fragments de **19 octets** (`kMaxBleWriteSize - 1`, sans
négociation de MTU). Une photo de 250 Ko représente environ 13 000 écritures ;
les vingt fichiers du lot demanderaient **plus d'une heure et demie
d'antenne**. Les refuser est le bon choix.

Mais la conséquence doit être assumée et dite : **le partage de fichiers de
Droplet dépend entièrement du Wi-Fi local ou du Wi-Fi Direct.** En Bluetooth
seul — c'est-à-dire dans une bonne partie des situations où une messagerie
maillée a un intérêt — photos, vidéos et messages vocaux ne partent pas.

Aujourd'hui l'application ne le dit pas. Elle devrait : un message vocal ou
une photo mis en attente faute de Wi-Fi mérite un état visible
(« en attente d'une liaison Wi-Fi »), pas deux coches.

---

## Constat n° 4 — Le logiciel n'est pas le goulot d'étranglement

C'est la bonne nouvelle, et elle est nette.

- **130 envois chiffrés, mis en forme et mis en file en 8,1 s** — soit environ
  **62 ms par envoi**, dont l'essentiel est le chiffrement de 250 Ko pour les
  fichiers.
- **Latence médiane en file : 1,5 à 2,4 ms.** La file ne fait pas attendre.
- **0,008 relance par message en Wi-Fi, 0,062 en Bluetooth** — le backoff
  exponentiel absorbe la perte sans jamais abandonner : **zéro message perdu
  définitivement** sur les deux profils, y compris à 3 % de perte.

La file d'attente, le chiffrement et les relances tiennent le lot sans
difficulté. **Tout le temps est dans la radio**, ce qui est le bon endroit.

---

## Constat n° 5 — Le Bluetooth coûte cher, même pour du texte

110 messages texte et positions = **20,5 Kio réellement émis**, soit **50,5 s
d'antenne** — environ **0,46 s par message**.

Ce n'est pas un problème en soi, mais cela fixe le régime : en Bluetooth seul,
Droplet fait passer à peu près **deux messages par seconde** dans le meilleur
des cas. Une conversation animée à plusieurs, ou un rattrapage après une
reconnexion, dépassera vite ce débit — et c'est là que la file, la priorité et
le regossip deviennent décisifs.

---

## Ce que ce banc ne dit pas

À vérifier avec deux téléphones, et par rien d'autre :

- **La portée réelle**, et ce qui se passe à la limite (le lien se dégrade-t-il
  ou tombe-t-il d'un coup ?).
- **Une coupure en pleine transmission de fichier** — la reprise fonctionne-t-elle ?
- **La consommation de batterie** sur une heure d'usage normal.
- **Le relais à trois appareils** : A ne voit pas C, B relaie. Jamais testé.
- **La découverte** : combien de temps avant que deux appareils se voient ?

---

---

## Correction appliquée — les échecs remontent désormais jusqu'à la file

Le constat n° 1 a été corrigé le jour même. La vérité est propagée sur les
quatre couches :

| Couche | Avant | Après |
|---|---|---|
| `BleMeshTransport.sendToPeer` | `Future<void>`, trois refus muets | `Future<bool>` |
| `LocalWifiTransport.sendToPeer` | `Future<void>`, levait parfois | `Future<bool>` |
| `NativeP2PTransport.sendToPeer` | `Future<void>`, muet si ID inconnu | `Future<bool>` |
| `MeshTransportService.sendToPeer` | `Future<void>` | `Future<bool>` |
| `sendViaRoute` | `return true` si le pair est connu | rend le verdict du transport |
| `broadcastToConnectedPeers` | `Future<void>` | `Future<bool>` — compte les succès réels |
| `_reliableOnSend` | `return connectedPeerCount > 0` | rend ce que la diffusion a fait |

**Trois défauts secondaires trouvés en chemin :**

1. **`_sendChunks` ne disait pas qu'il avait abandonné.** Il s'arrêtait au
   premier morceau en échec — la bonne décision — mais sans le signaler. Un
   message coupé en deux est perdu : le destinataire ne peut pas le
   rassembler. Il rend maintenant `false`.

2. **Le score de santé récompensait les transports qui jetaient le plus.**
   `_recordSuccess` était appelé dès que `_sendVia` rendait la main sans
   exception — donc y compris après un refus. Le Bluetooth, qui écarte le
   plus de charges, remontait donc en tête du classement des transports sains.

3. **Le type de contenu n'atteignait jamais le transport.** `_reliableOnSend`
   appelait `sendViaRoute` sans passer `type`, donc toujours `0x00`. Le
   Bluetooth ne pouvait pas reconnaître un fichier avant de buter sur sa
   limite de taille. Le type est maintenant relu dans l'en-tête de la trame,
   là où il est déjà écrit.

**Et un envoi en double supprimé :** `sendToPeer` lançait tous les transports
candidats **en parallèle** et gardait le premier qui répondait. Quand deux
liens fonctionnaient, le même message partait deux fois — et le Bluetooth, le
plus lent et le plus coûteux, payait un trajet dont personne n'avait besoin.
Les transports sont maintenant essayés l'un après l'autre, dans l'ordre de
santé déjà calculé, et on s'arrête au premier qui accepte.

### Mesure après correction — même lot, même profil Bluetooth

```
Envois mis en file        : 130
Arrivés                   : 110  (84,62 %)   ← n'annonce plus 100 %
Perdus définitivement     : 20               ← les fichiers, signalés
Refusés par le transport  : 100              ← 20 fichiers × 5 tentatives
Réellement reçus par B    : 110              ← égal aux « arrivés »
Relances par message      : 0,982
```

**L'invariant est rétabli : `arrivés == réellement reçus`.** Le chiffre de
livraison de l'application veut de nouveau dire quelque chose.

Un test conserve la trace du défaut (`sans le correctif, le banc voit la
livraison mensongère`) : si `sendViaRoute` recommençait un jour à répondre
« oui » sans rien envoyer, c'est exactement l'écart que l'on reverrait.

**63 tests passent.**

---

## Priorités qui découlent de ces constats

1. ~~**Faire remonter les échecs de transport.**~~ ✅ **Fait** — voir la section
   ci-dessus.
2. **Dire à l'utilisateur qu'un fichier attend du Wi-Fi**, au lieu de lui
   montrer deux coches. Les fichiers sont désormais signalés en échec, ce qui
   est honnête mais brutal : « échec » alors que le message part dès qu'un
   Wi-Fi apparaît serait un mensonge en sens inverse. Il faut un état
   intermédiaire, « en attente d'une liaison Wi-Fi ».
3. **Alléger l'enveloppe**, ou fragmenter au-dessus de 512 octets — sans quoi
   un message de plus de ~210 caractères échoue en Bluetooth. Il échoue
   désormais VISIBLEMENT, ce qui est déjà mieux que de disparaître, mais il
   devrait simplement passer.
4. **Alors seulement**, l'essai à deux appareils : il donnera enfin un chiffre
   qui veut dire quelque chose.
