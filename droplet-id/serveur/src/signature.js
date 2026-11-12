// ============================================================================
// LES REQUÊTES SIGNÉES DES APPAREILS
// ----------------------------------------------------------------------------
// Chaque appareil a une paire de clés Ed25519 PROPRE À DROPLET ID (distincte
// de la clé X25519 des messages). La clé privée ne quitte jamais l'appareil.
//
// En-têtes :
//   X-Droplet-Appareil  l'identifiant de l'appareil   (ou, à la création du
//   X-Droplet-Cle       compte, sa clé publique brute en base64url)
//   X-Droplet-Ts        l'heure (secondes Unix)
//   X-Droplet-Nonce     16 octets aléatoires (base64url), neufs à chaque fois
//   X-Droplet-Sig       base64url( Ed25519( MÉTHODE \n chemin \n heure \n
//                                           nonce \n sha256-hex(corps) ) )
//
// Refusé : signature fausse, plus vieille que 5 minutes ou déjà vue, appareil
// inconnu ou révoqué.
// ============================================================================

import { createHash, createPublicKey, verify } from 'node:crypto';

export class ErreurSignature extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

/** Le texte signé, identique côté appareil (voir les kits). */
export function texteASigner(methode, chemin, ts, nonce, corps) {
  const empreinte = createHash('sha256').update(corps ?? '').digest('hex');
  return `${methode.toUpperCase()}\n${chemin}\n${ts}\n${nonce}\n${empreinte}`;
}

export function clePublique(brute64) {
  const brute = Buffer.from(brute64, 'base64url');
  if (brute.length !== 32) throw new ErreurSignature('cle_invalide');
  return createPublicKey({ key: { kty: 'OKP', crv: 'Ed25519', x: brute.toString('base64url') }, format: 'jwk' });
}

/**
 * Vérifie une requête. Rend `{ appareil }` (appareil enregistré) ou
 * `{ clePub }` (création de compte).
 */
export async function verifierRequete({ methode, chemin, entetes, corps, stockage, fenetre }) {
  const ts = Number(entetes['x-droplet-ts']);
  const nonce = entetes['x-droplet-nonce'];
  const sig = entetes['x-droplet-sig'];
  const idAppareil = entetes['x-droplet-appareil'];
  const cleBrute = entetes['x-droplet-cle'];
  if (!ts || !nonce || !sig || (!idAppareil && !cleBrute)) throw new ErreurSignature('signature_absente');
  if (!/^[A-Za-z0-9_-]{16,64}$/.test(nonce)) throw new ErreurSignature('nonce_invalide');
  if (Math.abs(Date.now() / 1000 - ts) > fenetre) throw new ErreurSignature('signature_perimee');

  let appareil = null;
  let cle;
  if (idAppareil) {
    appareil = await stockage.appareil(idAppareil);
    if (!appareil) throw new ErreurSignature('appareil_inconnu');
    if (appareil.revoqueLe) throw new ErreurSignature('appareil_revoque');
    cle = clePublique(appareil.clePub);
  } else {
    cle = clePublique(cleBrute);
  }

  const ok = verify(null, Buffer.from(texteASigner(methode, chemin, ts, nonce, corps)), cle, Buffer.from(sig, 'base64url'));
  if (!ok) throw new ErreurSignature('signature_fausse');
  // Le nonce n'est retenu qu'APRÈS une signature valide : un inconnu ne peut
  // pas « griller » les nonces de quelqu'un d'autre.
  if (!(await stockage.nonceNeuf(nonce, fenetre * 2))) throw new ErreurSignature('signature_rejouee');
  return appareil ? { appareil } : { clePub: cleBrute };
}
