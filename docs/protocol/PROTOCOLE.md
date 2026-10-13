# Le protocole de Droplet Drop (v1)

## Transport

TCP, port 47321 par défaut (un autre si occupé), **TLS 1.3 uniquement**,
ALPN `droplet-drop/1`, authentification **mutuelle** par certificats
auto-signés ECDSA P-256. L'identité d'un appareil est l'empreinte SHA-256
de son certificat ; celui qui se connecte l'épingle (annonce mDNS ou QR).

## Trames

`[genre: u8][longueur: u32 BE][contenu]`

- genre 1 : contrôle, JSON (≤ 32 Mio)
- genre 2 : données, `[fichier u32][bloc u32][décalage u32][octets ≤ 1 Mio]`

## Manifeste

Pour chaque fichier : `id`, `chemin` relatif (« / »), `taille`,
`taille_bloc` (4 Mio par défaut), l'empreinte BLAKE3 de **chaque bloc**, et
celle du fichier entier. Le récepteur le valide (bornes, cohérence) et
renettoie les chemins.

## Envoi direct

```
E → D  Bonjour {v, appareil}         D → E  Bonjour
E → D  Offre {offre, manifeste}
D → E  Reponse {acceptee, deja: [carte des blocs par fichier], raison}
E → D  tranches…, Fin
D → E  Manquants {fichier, blocs}    (blocs abîmés ou manquants) → E renvoie, Fin
D → E  Recu
```

À tout moment : `Annuler`, `Pause` (le partiel est gardé).

## Group Drop

```
P → H  Bonjour                       H → P  Bonjour
P → H  Rejoindre {session, jeton}
H → P  Refus {raison} | Attente | Offre
… puis comme l'envoi direct, H expéditeur.
```

Invitation : `https://drop.dropletmesh.app/rejoindre/#<base64url(JSON)>`
(le décodeur accepte tout texte et ne lit que ce qui suit le dernier « # » ;
les anciens liens `dropletdrop://rejoindre#…` restent valides) avec adresses et
port de l'hôte, empreinte de l'hôte (épinglée), identifiant de session
(128 bits), jeton (256 bits), nom, expiration.

## Reprise

Le récepteur garde `<réception>/.droplet-drop/partiels/<clé>/` : l'état
(manifeste, expéditeur, carte des blocs, enregistrée toutes les 2 s) et
les fichiers `.part` à leur taille finale. La clé dépend du manifeste ET
de l'empreinte de l'expéditeur. Une offre identique du même expéditeur
reprend sans redemander l'accord.

## Fin

Tous les blocs présents → relecture complète, bloc par bloc et fichier
entier → déplacement à l'emplacement final sans écraser
(« nom (1).ext ») → `Recu`.
