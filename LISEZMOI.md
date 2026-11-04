# Correctifs du 4 novembre 2026

Deux fichiers à copier dans le projet Droplet, en remplaçant les anciens
(mêmes chemins) :

| Fichier | Correction |
|---|---|
| `lib/features/chats/chats_screen.dart` | Écran d'accueil : l'heure des discussions revient au bord droit |
| `lib/core/services/miroir_appareils.dart` | Notifications de Droplet Web onglet fermé : le téléphone signale les lots qui contiennent un message reçu |

Puis : `flutter pub get` et `flutter build apk --release --split-per-abi`.
