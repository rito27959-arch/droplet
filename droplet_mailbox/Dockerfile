# ── La boîte aux lettres Droplet sur Railway ────────────────────────────────────
# Compilé en un seul binaire natif, posé sur une Debian minimale avec
# les certificats (pour parler à Firebase). Railway fournit PORT ; le
# volume est monté sur /data.
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml ./
RUN dart pub get
COPY . .
RUN dart pub get --offline
RUN mkdir -p bin && dart compile exe lib/server.dart -o bin/server

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/bin/server /app/server
EXPOSE 8081
CMD ["/app/server"]
