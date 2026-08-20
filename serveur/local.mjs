/**
 * FAIT TOURNER LE WORKER SUR VOTRE MACHINE, sans Cloudflare.
 *
 *   1. copiez vos identifiants dans serveur/.dev.vars
 *   2. node serveur/local.mjs
 *   3. http://localhost:8787
 *
 * ⚠️ POURQUOI CE FICHIER EXISTE.
 *
 * Déployer pour découvrir qu'une clé est fausse, qu'un numéro est
 * refusé ou qu'un champ a changé de nom coûte un aller-retour à chaque
 * essai — et chaque essai en production peut débiter quelqu'un.
 *
 * Ce script exécute EXACTEMENT le même code que Cloudflare exécutera :
 * il importe le `fetch` du Worker et lui passe de vraies requêtes. Node
 * embarque la même API WebCrypto et le même objet `Request`/`Response`.
 * Ce qui marche ici marchera là-bas.
 *
 * Le seul élément simulé est le stockage KV — remplacé par une Map en
 * mémoire, ce qui suffit à vérifier qu'une référence ne sert qu'une
 * fois pendant une session d'essai.
 */

import { createServer } from 'node:http';
import { readFileSync, existsSync } from 'node:fs';
import worker from './index.js';

const PORT = 8787;
const FICHIER = new URL('./.dev.vars', import.meta.url);

// ── Les identifiants ────────────────────────────────────────────
if (!existsSync(FICHIER)) {
  console.error(`
Aucun fichier serveur/.dev.vars.

Créez-le avec vos identifiants Fapshi (il est déjà dans .gitignore) :

  FAPSHI_USER=votre_apiuser
  FAPSHI_KEY=votre_apikey
  LICENCE_D=...   (voir ~/.droplet-keys/worker-secrets.txt)
  LICENCE_X=...

Laissez FAPSHI_BASE absent pour rester en bac à sable.
`);
  process.exit(66);
}

const env = {};
for (const ligne of readFileSync(FICHIER, 'utf8').split('\n')) {
  const m = ligne.match(/^\s*([A-Z_]+)\s*=\s*(.*)$/);
  if (m) env[m[1]] = m[2].trim();
}

for (const requis of ['FAPSHI_USER', 'FAPSHI_KEY', 'LICENCE_D', 'LICENCE_X']) {
  if (!env[requis]) {
    console.error(`${requis} manque dans serveur/.dev.vars`);
    process.exit(66);
  }
}

// ── Le KV simulé ────────────────────────────────────────────────
const memoire = new Map();
env.DEJA_SERVI = {
  get: async (k) => memoire.get(k) ?? null,
  put: async (k, v) => void memoire.set(k, v),
};

// ── Le serveur ──────────────────────────────────────────────────
createServer(async (req, res) => {
  const corps = req.method === 'POST' ? await lireCorps(req) : undefined;
  const requete = new Request(`http://localhost:${PORT}${req.url}`, {
    method: req.method,
    headers: req.headers,
    body: corps,
  });

  const reponse = await worker.fetch(requete, env);
  const texte = await reponse.text();

  console.log(`${req.method} ${req.url} → ${reponse.status}  ${texte.slice(0, 160)}`);

  res.writeHead(reponse.status, {
    'Content-Type': reponse.headers.get('Content-Type') ?? 'application/json',
  });
  res.end(texte);
}).listen(PORT, () => {
  const mode = env.FAPSHI_BASE ? 'PRODUCTION — argent réel' : 'bac à sable';
  console.log(`Worker Droplet sur http://localhost:${PORT}  (${mode})`);
  console.log(`
Essai :
  curl -s http://localhost:${PORT}/sante

  curl -s -X POST http://localhost:${PORT}/payer \\
    -H 'Content-Type: application/json' \\
    -d '{"appareil":"a1b2-c3d4-e5f6-0718","offre":"pack","telephone":"678963221"}'

  curl -s 'http://localhost:${PORT}/licence?reference=LA_REFERENCE'
`);
});

function lireCorps(req) {
  return new Promise((ok) => {
    const bouts = [];
    req.on('data', (c) => bouts.push(c));
    req.on('end', () => ok(Buffer.concat(bouts).toString('utf8')));
  });
}
