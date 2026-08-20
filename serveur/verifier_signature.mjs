/**
 * Contrôle AVANT déploiement : le Worker signe-t-il des licences que
 * l'application accepte ?
 *
 *   node serveur/verifier_signature.mjs <code-appareil> <pack|pro>
 *
 * ⚠️ POURQUOI CE CONTRÔLE EXISTE.
 *
 * Cloudflare Workers et Dart ne partagent aucune ligne de code, et la
 * signature Ed25519 est l'endroit exact où deux plateformes peuvent se
 * croire d'accord sans l'être : nom d'algorithme (`Ed25519` contre
 * l'ancien `NODE-ED25519`), forme de la clé importée, bourrage base64.
 * Chacune de ces divergences produit une licence d'apparence normale que
 * l'application refuse — après le paiement.
 *
 * Ce script appelle la VRAIE fonction du Worker, avec les VRAIS secrets,
 * et écrit la licence obtenue. On la donne ensuite à vérifier au code
 * Dart réel. Si les deux sont d'accord ici, ils le seront en production.
 *
 * Node embarque la même API WebCrypto que les Workers : aucun paquet à
 * installer.
 */

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { signerLicence } from './index.js';

const [, , appareil, offre] = process.argv;
if (!appareil || !offre) {
  console.error('usage : node verifier_signature.mjs <appareil> <pack|pro>');
  process.exit(64);
}

// Les secrets sont lus depuis le fichier protégé, jamais écrits ici.
const brut = readFileSync(`${homedir()}/.droplet-keys/worker-secrets.txt`, 'utf8');
const lire = (nom) => {
  const m = brut.match(new RegExp(`^${nom}=(.+)$`, 'm'));
  if (!m) throw new Error(`${nom} absent du fichier de secrets`);
  return m[1].trim();
};

const env = { LICENCE_D: lire('LICENCE_D'), LICENCE_X: lire('LICENCE_X') };

const licence = await signerLicence(env, appareil.replaceAll('-', ''), offre);
console.log(licence);
