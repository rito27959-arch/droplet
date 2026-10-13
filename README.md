# Droplet Drop

**Partagez librement** — des fichiers de toutes tailles, à un appareil ou à
une salle entière, sur un réseau local, sans Internet.

- **Moteur en Rust** (`crates/`) : transfert par blocs vérifiés (BLAKE3),
  TLS 1.3 mutuel à empreintes épinglées, reprise après coupure, envoi
  simultané à plusieurs appareils, sessions **Group Drop**, découverte
  mDNS, historique SQLite.
- **Interface Flutter** (`apps/droplet_drop_flutter/`) : Android, iOS,
  Windows, macOS, Linux ; design system *Droplet Liquid* ; thèmes clair et
  sombre ; dix langues.

## Ce qui est vérifié (tests réels, `cargo test`)

| Test | Ce qu'il prouve |
|---|---|
| `envoi_direct_avec_dossier` | fichiers + dossiers + fichier vide, contenu identique, jamais d'écrasement |
| `refus_et_empreinte_epinglee` | refus respecté ; un appareil qui usurpe une empreinte est rejeté à la poignée de main |
| `appareil_de_confiance_sans_question` | règle de confiance |
| `reprise_apres_coupure_reelle_et_bloc_abime` | le destinataire « meurt » à 30 % de 400 Mo, un bloc est abîmé sur son disque ; à son retour, reprise depuis la carte des blocs, bloc abîmé détecté et renvoyé |
| `pause_puis_reprise` | pause / reprise côté expéditeur |
| `dix_destinataires` | 10 envois simultanés indépendants |
| `group_drop_session` | 10 participants rejoignent par invitation, l'hôte lance ; un intrus au faux jeton est refusé |
| `session_expiree` | une invitation expirée ne permet plus d'entrer |
| `malveillant.rs` | chemins piégés (`../../`), données fausses jamais livrées, trames démesurées, manifeste absurde, client sans certificat |
| `mesures_volumineuses` | 1 Go → 2 appareils, 200 Mo → 30 appareils (`DROP_TEST_GRAND=1`) |

Mesures sur une machine de développement (2 cœurs, réseau local de la
machine, empreintes comprises) : **1 Go vers 2 appareils en 6,2 s ;
200 Mo vers 30 appareils en 12,2 s**, chaque copie vérifiée. Sur un vrai
Wi-Fi, c'est le débit radio qui limite.

## Construire

```sh
# Moteur
cargo test --release --workspace --exclude rust_lib_droplet_drop

# Application (Flutter stable + Rust stable)
cd apps/droplet_drop_flutter
flutter run                     # ou : flutter build apk | windows | macos | linux | ios
```

Le pont Rust ↔ Dart est généré par `flutter_rust_bridge_codegen generate`
(version 2.13.0) ; la CI le régénère et le recommite.

Les icônes viennent de `docs/icone-source.png` :
`python3 scripts/icones/generer_icones.py`.
Les textes (10 langues) : `python3 scripts/textes/generer.py`.

## Documents

- `docs/protocol/PROTOCOLE.md` — le protocole sur la connexion
- `docs/security/SECURITE.md` — le modèle de sécurité
- `docs/deployment/PUBLICATION.md` — signature et publication

## Ce qui n'est pas encore fait

- **Distribution collaborative** (phase 5) : les destinataires ne
  redistribuent pas encore les blocs entre eux. Le manifeste par blocs
  vérifiés est prêt pour cela.
- Lien vérifié `drop.dropletmesh.app` et intégration dans Droplet
  Messenger.
- Signature des applications (comptes développeur nécessaires).
