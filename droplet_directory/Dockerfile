# ── DropletDirectory (.onion) ─────────────────────────────────────────
# Serveur annuaire .onion pour Droplet.
# Exécuté comme service caché Tor sur un VPS.
# ─────────────────────────────────────────────────────────────────────

FROM dart:stable-sdk AS build

WORKDIR /app

COPY pubspec.yaml ./
RUN dart pub get

COPY . .

RUN mkdir -p bin && dart compile exe lib/server.dart -o bin/server

# ── Image finale avec Tor ───────────────────────────────────────────
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    tor \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copier le binaire Dart compilé.
COPY --from=build /app/bin/server /app/server

# Copier la config Tor.
COPY torrc /etc/tor/torrc

# Script de démarrage : lance Tor + le serveur.
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

EXPOSE 8080

CMD ["/app/start.sh"]
