#!/bin/bash
# ── Script de démarrage pour DropletMailbox ─────────────────────────
# Lance Tor (pour le service caché) puis le serveur Dart.

set -e

echo "[Mailbox] Démarrage..."

mkdir -p /var/lib/tor/droplet_mailbox
chmod 700 /var/lib/tor/droplet_mailbox

echo "[Mailbox] Démarrage de Tor..."
tor -f /etc/tor/torrc &
TOR_PID=$!

echo "[Mailbox] Attente de Tor..."
for i in $(seq 1 60); do
  if [ -f /var/lib/tor/droplet_mailbox/hostname ]; then
    ONION=$(cat /var/lib/tor/droplet_mailbox/hostname)
    echo "[Mailbox] ✓ Service caché disponible: $ONION"
    break
  fi
  sleep 2
done

if [ ! -f /var/lib/tor/droplet_mailbox/hostname ]; then
  echo "[Mailbox] ✗ Tor n'a pas démarré à temps"
  exit 1
fi

echo "[Mailbox] Démarrage du serveur mailbox..."
exec /app/server --port 8081 --host 127.0.0.1
