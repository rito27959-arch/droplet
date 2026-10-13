# Sécurité de Droplet Drop

**Aucune cryptographie maison.** rustls (TLS 1.3, fournisseur `ring`),
rcgen (ECDSA P-256), SHA-256, BLAKE3.

| Menace | Protection |
|---|---|
| Écoute du réseau | TLS 1.3 sur chaque connexion |
| Usurpation d'un appareil | empreinte de certificat épinglée (annonce, QR) ; la poignée de main prouve la possession de la clé |
| Envoi non sollicité | accord explicite (ou règle de confiance choisie par l'utilisateur) ; expiration de l'offre après 2 min |
| Intrus dans une distribution | jeton de 256 bits comparé à temps constant ; invitation limitée dans le temps ; identité de l'hôte épinglée |
| Fichier abîmé ou falsifié | empreinte de chaque bloc + du fichier entier ; rien n'est livré avant vérification |
| Écriture hors du dossier | chemins renettoyés à la réception (`..`, racines, noms réservés Windows, caractères interdits, profondeur) ; vérification finale `starts_with` |
| Écrasement | nom libre (« nom (1).ext ») |
| Disque plein | espace libre vérifié avant d'accepter |
| Allocation démesurée | longueurs de trames bornées ; manifeste borné (100 000 fichiers, 4 Tio) |
| Martèlement | 20 échecs / minute / IP → connexions ignorées ; 128 poignées de main simultanées au plus |
| Programme reçu | jamais exécuté ; avertissement à l'offre |

La clé privée de l'appareil est stockée dans le dossier de données de
l'application (droits 600 sous Unix).
