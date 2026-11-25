// L'attestation pour Droplet Pay : signée, liée à l'appareil qui la demande,
// avec un identifiant de compte propre au service.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createPublicKey, randomBytes, verify } from 'node:crypto';
import { demarrer } from '../src/serveur.js';
import { clePriveeEd25519, nouvelleCleDeSignature } from '../src/config.js';
import { nouvelAppareil } from './outils.js';

const PORT = 19000 + Math.floor(Math.random() * 1000);
const BASE = `http://localhost:${PORT}`;
const graine = randomBytes(32).toString('base64url');
const cle = clePriveeEd25519(graine);
let service;

function configDeTest(surcharges = {}) {
  return {
    port: PORT,
    emetteur: BASE,
    baseDeDonnees: process.env.TEST_DATABASE_URL ?? null,
    jwks: { keys: [nouvelleCleDeSignature('test')] },
    clesCookies: ['cle-de-test-cookies-0123456789abcdef'],
    selPairwise: 'sel-de-test',
    clients: [],
    environnementDeTest: true,
    dureeDemande: 120,
    fenetreSignature: 300,
    derriereProxy: false,
    cleAttestation: cle,
    ...surcharges,
  };
}

before(async () => { service = await demarrer(configDeTest()); });
after(() => service.arreter());

function lire(jeton) {
  const [pre, corps, sig] = jeton.split('.');
  assert.equal(pre, 'DIA1');
  const ok = verify(null, Buffer.from(`DIA1\n${corps}`), createPublicKey(cle), Buffer.from(sig, 'base64url'));
  return { ok, charge: JSON.parse(Buffer.from(corps, 'base64url').toString()) };
}

test('un appareil obtient une attestation signée qui le nomme', async () => {
  const a = nouvelAppareil(BASE);
  await a.creerCompte();
  const r = await a.appeler('POST', '/v1/attestations', { aud: 'droplet-pay' });
  assert.equal(r.statut, 200);
  const { ok, charge } = lire(r.corps.attestation);
  assert.equal(ok, true);
  assert.equal(charge.iss, BASE);
  assert.equal(charge.aud, 'droplet-pay');
  assert.equal(charge.appareil, a.appareilId);
  assert.equal(charge.cle, a.clePub);
  assert.notEqual(charge.sub, a.compteId); // jamais le vrai identifiant
  assert.ok(charge.exp - charge.iat <= 300);
});

test('deux appareils du même compte reçoivent le même identifiant de service', async () => {
  const a = nouvelAppareil(BASE);
  await a.creerCompte();
  const s1 = lire((await a.appeler('POST', '/v1/attestations', { aud: 'droplet-pay' })).corps.attestation).charge.sub;
  const s2 = lire((await a.appeler('POST', '/v1/attestations', { aud: 'droplet-pay' })).corps.attestation).charge.sub;
  assert.equal(s1, s2);
  const b = nouvelAppareil(BASE);
  await b.creerCompte();
  const s3 = lire((await b.appeler('POST', '/v1/attestations', { aud: 'droplet-pay' })).corps.attestation).charge.sub;
  assert.notEqual(s1, s3);
});

test('service inconnu ou requête non signée : refusé', async () => {
  const a = nouvelAppareil(BASE);
  await a.creerCompte();
  assert.equal((await a.appeler('POST', '/v1/attestations', { aud: 'autre' })).corps.erreur, 'service_inconnu');
  const r = await fetch(`${BASE}/v1/attestations`, { method: 'POST', body: '{"aud":"droplet-pay"}' });
  assert.equal(r.status, 401);
});
