# Publier Droplet Drop

La CI (`.github/workflows/droplet-drop.yml`) compile **sans signature** :
APK Android, Windows, Linux, macOS et iOS. Pour publier :

- **Android** : créer une clé (`keytool -genkey -v -keystore droplet-drop.jks …`),
  la déclarer dans `android/key.properties` (non versionné), puis
  `flutter build appbundle` pour le Play Store.
- **iOS / macOS** : compte Apple Developer ; dans Xcode, choisir l'équipe
  (Runner → Signing), puis Archive. L'app demande l'accès au réseau local
  (`NSLocalNetworkUsageDescription`, `NSBonjourServices`).
- **Windows** : installateur MSIX (`msix` de pub.dev) ou Inno Setup sur le
  dossier `build/windows/x64/runner/Release` ; signer avec un certificat
  de signature de code pour éviter l'alerte SmartScreen.
- **Linux** : le dossier `bundle` en archive, ou un AppImage / Flatpak.

Pare-feu Windows : à la première ouverture, Windows demande d'autoriser
Droplet Drop sur les réseaux privés — c'est nécessaire pour recevoir.
