# Liaison Droplet Web

Le téléphone fourni dans `lib9.zip` utilise `POST /liaison/{canal}`. Le navigateur TypeScript du dépôt `Droplet-web` utilise `PUT` puis `GET` sur la même URL.

| Requête | Réponse | Rôle |
| --- | --- | --- |
| `PUT /liaison/{canal}` | `201`, `409` si réservé | Le navigateur réserve 16 octets aléatoires encodés en base64url avant d'afficher le QR. |
| `GET /liaison/{canal}` | `204` en attente, `200` avec enveloppe, `404` absent ou expiré | Le navigateur relève l'enveloppe chiffrée. |
| `POST /liaison/{canal}` | `200`, `404` expiré, `409` déjà publié | Le téléphone dépose `{v:1,cleTel,nonce,chiffre}` une seule fois. |

Les invitations expirent en 60 secondes. Le serveur limite la taille des enveloppes et le nombre d'invitations en mémoire. L'origine CORS autorisée est `https://web.dropletmesh.app`, modifiable via `DROPLET_WEB_ORIGIN` en développement. Les secrets de conversation ne transitent pas dans ces réponses.

Pour Railway, `Dockerfile.railway` expose le serveur sans Tor local, sur `0.0.0.0` et le port `PORT`. La version publique du dépôt GitHub est plus ancienne que l'annuaire effectivement en production : `/health` répond avec `pushConfigured` sur Railway, tandis que ce champ est absent ici. **Ne pas remplacer le service de production par ce répertoire tel quel.** Intégrer ces routes et leur middleware CORS dans le code actuel du serveur et exécuter `dart test` dans `droplet_directory/`. Le stockage des invitations doit être partagé si plusieurs instances répondent aux requêtes. Vérifier le flux avec un vrai téléphone et le site HTTPS avant de considérer la liaison opérationnelle.

La liaison transmet uniquement l'identité au navigateur. L'historique, l'envoi, les accusés et la révocation exigent un protocole multiappareil authentifié, absent du serveur public.
