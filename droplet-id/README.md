# Droplet ID

Se connecter à des sites et des applications **sans numéro, sans e-mail, sans nom**.
La personne approuve sur son téléphone ; chaque site reçoit un identifiant qui ne vaut que pour lui.

> Phase de test : tout tourne dans l'environnement **test** (aucune donnée réelle).

| Dossier | Contenu |
|---|---|
| `serveur/` | Le service OpenID Connect (`oidc-provider`), l'API signée des appareils, la page de connexion QR, l'appareil de test. |
| `kits/js` | `@droplet/id` — navigateur, sans dépendance, bouton officiel |
| `kits/react` | `@droplet/id-react` — `DropletIdProvider`, `useDropletId`, `DropletIdButton` |
| `kits/node` | `@droplet/id-node` — serveur Node.js, routes Express prêtes |
| `kits/python` | `droplet-id` — Python, Flask inclus |
| `kits/php` | `dropletmesh/droplet-id` — PHP sans dépendance |
| `kits/go` | Go, par-dessus `coreos/go-oidc` |
| `kits/flutter` | `droplet_id` — Flutter, par-dessus `flutter_appauth`, bouton officiel |
| `kits/kotlin` | Android (Kotlin), par-dessus AppAuth, bouton Compose |
| `kits/essais` | Essai de bout en bout de chaque kit serveur contre un vrai service |
| `demos/kola` | Kola Café (imaginaire) — React |
| `demos/baobab` | Librairie Baobab (imaginaire) — Node.js côté serveur |
| `developpeurs/` | Le portail développeurs et son bac à sable |

## En ligne (test)

- Service : https://id-test.dropletmesh.app
- Développeurs : https://developpeurs-id.dropletmesh.app
- Démos : https://demo-kola.dropletmesh.app · https://demo-baobab.dropletmesh.app

## Lancer en local

```sh
cd serveur && npm install && npm run dev        # http://localhost:8080, appareil de test inclus
npm test                                          # 10 essais de bout en bout (TEST_DATABASE_URL pour PostgreSQL)
cd ../kits/essais && node e2e.mjs                 # chaque kit serveur, connexion vérifiée
```

## Sécurité, en bref

- OpenID Connect standard ; PKCE `S256` obligatoire ; `redirect_uri` exacte.
- `sub` différent pour chaque site (HMAC d'un sel secret), stable pour un même site.
- Aucune portée `email` ni `phone` : elles n'existent pas.
- L'appareil signe chaque requête en Ed25519 (clé propre à Droplet ID, distincte de la clé des messages) ; anti-rejeu par nonce et fenêtre de 5 minutes.
- Le nombre à deux chiffres affiché à l'écran se **tape** sur le téléphone (1 chance sur 90 au hasard), une seule tentative.
- Secrets (`JWKS`, `CLES_COOKIES`, `SEL_PAIRWISE`) uniquement dans les variables du service.

Voir aussi le document technique « Droplet ID - Document technique.md ».
