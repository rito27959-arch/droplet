# Droplet Web

Vos discussions Droplet dans le navigateur, même téléphone éteint —
web.dropletmesh.app. Le modèle et le plan sont dans l'étude « Droplet Web —
étude de faisabilité ».

## État : les fondations

- L'écran de liaison : code QR renouvelé toutes les 60 s, avec une paire de
  clés X25519 propre à ce navigateur ; mode clair et sombre ; 10 langues
  (celle du navigateur) ; adaptation au téléphone (pas de code à scanner).
- Le système de design de l'app (`lib/design/`, copié de
  `lib/design_system/`) : mêmes couleurs, même typographie.

La suite (certificat signé par le téléphone, file dans la boîte aux lettres,
discussions) attend les serveurs consolidés — étape 1 du plan.

## Lancer

```sh
cd droplet_web
flutter pub get
flutter run -d chrome
```

## Construire

```sh
flutter build web --release      # le site final dans build/web
```

## Publication

Chaque push sur `main` est construit et publié par Vercel
(`vercel-build.sh` télécharge Flutter, puis `flutter build web`), sur
web.dropletmesh.app.

Aperçu de l'interface avec des discussions d'exemple : ajoutez `?apercu` à
l'adresse.
