# ── DropletServer (Railway) ──────────────────────────────────────────
# Serveur de signaling WebRTC + TURN pour les appels audio/vidéo.
# Déployé sur Railway.app
# ─────────────────────────────────────────────────────────────────────

FROM dart:stable-sdk AS build

WORKDIR /app

# Copier les dépendances d'abord (cache Docker).
COPY pubspec.yaml ./
RUN dart pub get

# Copier le code.
COPY . .

# Compiler en mode release.
RUN mkdir -p bin && dart compile exe lib/server.dart -o bin/server

# ── Image finale ────────────────────────────────────────────────────
FROM scratch

# Copier les binaires Dart.
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/server

# Railway fournit le port via la variable PORT.
ENV PORT=8082
EXPOSE ${PORT}

ENTRYPOINT ["/app/server"]
CMD ["--port", "8082", "--host", "0.0.0.0"]
