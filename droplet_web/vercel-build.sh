#!/usr/bin/env bash
# Construit Droplet Web sur Vercel, qui n'a pas Flutter : on le télécharge
# (branche stable, sans historique), on le garde en cache entre deux
# constructions quand Vercel le permet, puis on construit le site.
set -euo pipefail

if [ ! -x "flutter/bin/flutter" ]; then
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git flutter
fi
export PATH="$PWD/flutter/bin:$PATH"

flutter --version
flutter config --enable-web --no-analytics
flutter pub get
flutter build web --release --no-tree-shake-icons
