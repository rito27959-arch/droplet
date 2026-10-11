# Liaison Droplet Web

Le téléphone fourni dans `lib9.zip` utilise `POST /liaison/{canal}`. Le navigateur TypeScript du dépôt `Droplet-web` utilise `PUT` puis `GET` sur la même URL.

| Requête | Réponse | Rôle |
| --- | --- | --- |
| `PUT /liaison/{canal}` | `201`, `409` si réservé | Le navigateur réserve 16 octets aléatoires encodés en base64url avant d'afficher le QR. |
| `GET /liaison/{canal}` | `204` en attente, `200` avec enveloppe, `404` absent ou expiré | Le navigateur relève l'enveloppe chiffrée. |
| `POST /liaison/{canal}` | `200`, `404` expiré, `409` déjà publié | Le téléphone dépose `{v:1,cleTel,nonce,chiffre}` une seule fois. |

Les invitations expirent en 60 secondes. Le serveur limite la taille des enveloppes et le nombre d'invitations en mémoire. L'origine CORS autorisée est `https://web.dropletmesh.app`, modifiable via `DROPLET_WEB_ORIGIN` en développement. Les secrets de conversation ne transitent pas dans ces réponses.

L'archive `droplet server.zip` fournit une version de l'annuaire qui porte déjà Firebase, les sauvegardes et les clés Signal. Ces fichiers sont repris ici, avec les trois routes de liaison et leur middleware CORS. Le `Dockerfile` expose maintenant le service sur Railway sans Tor local, sur `0.0.0.0` et le port `PORT` ; `Dockerfile.tor` et `start.sh` gardent le déploiement Tor séparé. Vérifier la configuration de la racine du service Railway avant un redéploiement.

Exécuter `dart pub get`, `dart test` et `dart compile exe lib/server.dart` dans `droplet_directory/`. Le stockage des invitations est en mémoire : garder une seule instance ou utiliser un magasin partagé avec expiration atomique. Vérifier le flux avec un vrai téléphone et le site HTTPS avant de considérer la liaison opérationnelle.

La liaison transmet uniquement l'identité au navigateur. L'historique, l'envoi, les accusés et la révocation exigent un protocole multiappareil authentifié, absent de ce serveur.
