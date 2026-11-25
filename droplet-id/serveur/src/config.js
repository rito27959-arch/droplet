// ============================================================================
// La configuration de Droplet ID, lue dans l'environnement.
// Aucun secret n'est écrit dans le code : en production, chaque valeur
// sensible vient des variables du service (Railway).
// ============================================================================

import { readFileSync } from 'node:fs';
import { createPrivateKey, generateKeyPairSync, randomBytes } from 'node:crypto';

const env = process.env;

function exiger(nom, enDev) {
  const v = env[nom];
  if (v) return v;
  if (env.NODE_ENV === 'production') throw new Error(`Variable manquante : ${nom}`);
  return enDev();
}

/**
 * Une clé de signature ES256 (P-256) au format JWK privé, pour le dev.
 * ES256 plutôt qu'EdDSA : toutes les bibliothèques OpenID la vérifient
 * (PHP, Python, Java, .NET…), EdDSA pas encore partout.
 */
export function nouvelleCleDeSignature(kid = 'dev') {
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  return { ...privateKey.export({ format: 'jwk' }), kid, alg: 'ES256', use: 'sig' };
}
const cleDeDev = () => nouvelleCleDeSignature();

export const config = {
  port: Number(env.PORT ?? 8080),
  /** L'adresse publique du service : c'est aussi l'« issuer » des jetons. */
  emetteur: (env.EMETTEUR ?? `http://localhost:${env.PORT ?? 8080}`).replace(/\/$/, ''),
  /** Base PostgreSQL ; sans elle, tout reste en mémoire (dev et tests). */
  baseDeDonnees: env.DATABASE_URL ?? null,
  /** Clés de signature des jetons (JWKS privé, JSON). */
  jwks: JSON.parse(exiger('JWKS', () => JSON.stringify({ keys: [cleDeDev()] }))),
  /** Clés des cookies de session (liste séparée par des virgules). */
  clesCookies: exiger('CLES_COOKIES', () => randomBytes(32).toString('base64url')).split(','),
  /** Le sel des identifiants « pairwise » (un par site). Ne jamais le changer. */
  selPairwise: exiger('SEL_PAIRWISE', () => randomBytes(32).toString('base64url')),
  /** Les sites et apps autorisés (fichier JSON). */
  clients: JSON.parse(readFileSync(env.CLIENTS ?? new URL('../clients.json', import.meta.url), 'utf8')),
  /** Environnement de test : bandeau visible et « appareil de test » dans le navigateur. */
  environnementDeTest: env.ENVIRONNEMENT_DE_TEST === '1',
  /** Durée de vie d'une demande de connexion, en secondes. */
  dureeDemande: 120,
  /** Fenêtre de validité d'une requête signée, en secondes. */
  fenetreSignature: 300,
  /** Derrière le proxy de Railway : faire confiance à X-Forwarded-*. */
  derriereProxy: env.DERRIERE_PROXY === '1',
  /**
   * La clé qui signe les attestations pour Droplet Pay (graine Ed25519 de
   * 32 octets, base64url, dans ATTESTATION_GRAINE). Facultative : sans elle,
   * /v1/attestations répond 503 et rien d'autre ne change.
   */
  cleAttestation: env.ATTESTATION_GRAINE ? clePriveeEd25519(env.ATTESTATION_GRAINE) : null,
};

/** Une clé privée Ed25519 à partir de sa graine brute (32 octets, base64url). */
export function clePriveeEd25519(graine64) {
  const graine = Buffer.from(graine64, 'base64url');
  if (graine.length !== 32) throw new Error('ATTESTATION_GRAINE : 32 octets attendus');
  return createPrivateKey({ key: Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), graine]), format: 'der', type: 'pkcs8' });
}
