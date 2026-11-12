# Librairie Baobab (démo)

Librairie imaginaire, rendue côté serveur (Express), connectée avec `@droplet/id-node`.
Elle ne garde qu'une ligne par personne : l'identifiant Droplet ID, le pseudo (si partagé) et la liste d'envies.

```sh
cd ../../kits/node && npm install && cd ../../demos/baobab && npm install
EMETTEUR=http://localhost:8080 node serveur.js    # avec le serveur Droplet ID en local
```

Variables : `ADRESSE` (adresse publique), `EMETTEUR` (Droplet ID), `SECRET` (cookie signé, 32 caractères ou plus).
