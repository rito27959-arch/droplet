#!/bin/bash
# ── Script de démarrage pour DropletDirectory ───────────────────────
# Lance Tor (pour le service caché) puis le serveur Dart.

set -e

echo "[Directory] Démarrage..."

# Créer le répertoire pour les données Tor si nécessaire.
mkdir -p /var/lib/tor/droplet_directory
chmod 700 /var/lib/tor/droplet_directory

# Lancer Tor en arrière-plan.
echo "[Directory] Démarrage de Tor..."
tor -f /etc/tor/torrc &
TOR_PID=$!

# Attendre que Tor soit prêt (attendre que le fichier hostname existe).
echo "[Directory] Attente de Tor..."
for i in $(seq 1 60); do
  if [ -f /var/lib/tor/droplet_directory/hostname ]; then
    ONION=$(cat /var/lib/tor/droplet_directory/hostname)
    echo "[Directory] ✓ Service caché disponible: $ONION"
    break
  fi
  sleep 2
done

if [ ! -f /var/lib/tor/droplet_directory/hostname ]; then
  echo "[Directory] ✗ Tor n'a pas démarré à temps"
  exit 1
fi

# Lancer le serveur Dart.
echo "[Directory] Démarrage du serveur annuaire..."
exec /app/server --port 8080 --host 127.0.0.1
