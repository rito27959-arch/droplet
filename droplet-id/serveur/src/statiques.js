// Fichiers statiques versionnés : chaque URL porte l'empreinte du fichier
// (?v=…). Un fichier modifié change d'adresse, donc un navigateur ne peut
// jamais garder une ancienne feuille de style avec une nouvelle page.
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

export const STATIQUES = {
  'droplet-id.css': 'text/css; charset=utf-8',
  'connexion.js': 'text/javascript; charset=utf-8',
  'continuer.js': 'text/javascript; charset=utf-8',
  'appareil.js': 'text/javascript; charset=utf-8',
  'lien.js': 'text/javascript; charset=utf-8',
  'InstrumentSans.woff2': 'font/woff2',
  'favicon.svg': 'image/svg+xml',
};

export const contenus = {};
const empreintes = {};
for (const nom of Object.keys(STATIQUES)) {
  contenus[nom] = readFileSync(new URL(`../public/${nom}`, import.meta.url));
  empreintes[nom] = createHash('sha256').update(contenus[nom]).digest('base64url').slice(0, 10);
}

/** L'adresse versionnée d'un fichier statique. */
export const statique = (nom) => `/static/${nom}?v=${empreintes[nom]}`;
export const empreinte = (nom) => empreintes[nom];
