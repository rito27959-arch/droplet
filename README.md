# Droplet

Une messagerie qui fonctionne **sans internet, sans opérateur et sans
serveur**. Les messages passent de téléphone en téléphone, chiffrés, par
Bluetooth et par Wi-Fi.

Conçue et développée à Yaoundé.

---

## Le principe

Toutes les messageries supposent que le réseau est là. Le jour où la
couverture tombe — coupure, zone blanche, crédit épuisé — elles
s'arrêtent toutes ensemble, exactement au moment où l'on a le plus
besoin de joindre quelqu'un.

Droplet part de l'hypothèse inverse : **il n'y a pas de réseau**.

Votre téléphone possède déjà deux radios capables d'atteindre un autre
téléphone sans passer par quoi que ce soit. Droplet ne fait rien d'autre
que s'en servir :

| Transport | Portée | Usage |
|---|---|---|
| Bluetooth LE | ~10 à 100 m | découverte, messages |
| Wi-Fi local | débit élevé | fichiers, appels |
| Wi-Fi Direct | ~50 à 200 m | sans infrastructure |

Hors de portée directe, le message emprunte les appareils qui se
trouvent entre les deux — **jusqu'à cinq de suite**. Et s'il n'y a
personne, il attend sur le téléphone et repart dès qu'un appareil passe
à portée : c'est le stockage et retransmission.

## Ce qu'elle sait faire

- Conversations et groupes — réponses citées, réactions, accusés de
  réception, recherche
- Appels audio et vidéo (liaison Wi-Fi : le Bluetooth, à dix-neuf octets
  par écriture, ne peut pas porter de la voix)
- Photos, vidéos, fichiers, notes vocales
- Statuts, effacés après vingt-quatre heures
- Carte hors connexion, positions partagées par le maillage
- Signal « je vais bien » et mode d'urgence

## Sécurité

- **Identité** : paire de clés X25519 créée sur l'appareil, clé privée
  dans le coffre du système, jamais en base
- **Messages privés** : ECDH → HKDF → AES-256-GCM, nonce aléatoire par
  message
- **Groupes** : cliquet à clé d'expéditeur, dérivation HMAC par message
- **Relais** : un téléphone qui fait suivre un message transporte des
  octets qu'il ne peut pas lire

## Ce qu'elle ne sait PAS faire

Une application qui ne parle que de ses qualités demande qu'on la croie
sur parole.

- **Elle ne remplace pas internet.** Elle joint le voisinage, étendu par
  les relais — pas l'autre bout du pays.
- **Elle ne cache pas votre présence.** Pour se trouver, les appareils
  s'annoncent. Le contenu est illisible, la présence ne l'est pas.
- **Elle est plus lente qu'un réseau.** Un message relayé peut attendre
  des heures qu'un chemin s'ouvre.
- **Elle n'a rien pour vous rendre votre identité.** Pas de serveur
  signifie pas de récupération de compte : sans sauvegarde exportée, un
  téléphone perdu emporte tout.
- **Seule, elle ne sert à rien.** Un maillage se construit à plusieurs.

## Installation

Android 7.0 ou plus récent. Les versions sont publiées dans
[Releases](../../releases/latest) — un fichier par architecture :

| Fichier | Pour |
|---|---|
| `app-arm64-v8a-release.apk` | la plupart des téléphones récents |
| `app-armeabi-v7a-release.apk` | téléphones plus anciens |
| `app-x86_64-release.apk` | émulateurs, quelques tablettes |

L'application sait aussi **s'envoyer elle-même** par Bluetooth ou Wi-Fi
Direct : ni l'expéditeur ni le destinataire n'a besoin de connexion.
C'est le seul mode de distribution cohérent avec ce qu'elle prétend
être.

## Construire

```bash
flutter pub get
flutter test                                    # 139 tests
flutter build apk --release --split-per-abi
```

La signature de publication demande un `android/key.properties`, qui
n'est pas dans ce dépôt — voir `android/app/build.gradle.kts`.

## Le site

`site/index.html` est la source ; `python3 site/construire.py` produit
la version déployable dans `site/public/`.

## État

**Phase de test.** L'application fonctionne, elle n'est pas finie. Si
vous l'essayez : Réglages → Journal des erreurs → **Envoyer**. Droplet
n'ayant aucun serveur, aucun rapport de plantage ne remonte nulle part —
sans votre envoi, le défaut n'existe pour personne.

## Licence

MIT — voir [LICENSE](LICENSE).
