// De bout en bout : un site lance la connexion, un appareil l'approuve, le
// site reçoit ses jetons. Puis les cas d'attaque.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import * as oidc from 'openid-client';
import { demarrer } from '../src/serveur.js';
import { nouvelleCleDeSignature } from '../src/config.js';
import { nouvelAppareil, nouveauNavigateur } from './outils.js';

const PORT = 18000 + Math.floor(Math.random() * 1000);
const BASE = `http://localhost:${PORT}`;
const CLIENTS = [
  { client_id: 'site-a', client_name: 'Site A', redirect_uris: ['http://localhost:7001/retour'] },
  { client_id: 'site-b', client_name: 'Site B', redirect_uris: ['http://localhost:7002/retour'] },
];
let service;

before(async () => {
  service = await demarrer({
    port: PORT,
    emetteur: BASE,
    baseDeDonnees: process.env.TEST_DATABASE_URL ?? null, // PostgreSQL si fourni, sinon mémoire
    jwks: { keys: [nouvelleCleDeSignature('test')] },
    clesCookies: ['cle-de-test-cookies-0123456789abcdef'],
    selPairwise: 'sel-de-test',
    clients: CLIENTS,
    environnementDeTest: true,
    dureeDemande: 120,
    fenetreSignature: 300,
    derriereProxy: false,
  });
});
after(() => service.arreter());

/** Démarre une connexion pour `clientId` ; rend la page et de quoi finir. */
async function commencer(clientId, scope = 'openid') {
  const conf = await oidc.discovery(new URL(BASE), clientId, undefined, oidc.None(), { execute: [oidc.allowInsecureRequests] });
  const verifier = oidc.randomPKCECodeVerifier();
  const challenge = await oidc.calculatePKCECodeChallenge(verifier);
  const state = oidc.randomState();
  const redirect = CLIENTS.find((c) => c.client_id === clientId).redirect_uris[0];
  const url = oidc.buildAuthorizationUrl(conf, { redirect_uri: redirect, scope, code_challenge: challenge, code_challenge_method: 'S256', state });
  const nav = nouveauNavigateur();
  const r1 = await nav.aller(url.href);
  assert.equal(r1.status, 303);
  const interaction = new URL(r1.headers.get('location'), BASE);
  assert.match(interaction.pathname, /^\/interaction\//);
  const page = await (await nav.aller(interaction.href)).text();
  const demandeId = page.match(/\/a\/([A-Za-z0-9_-]{16,})/)[1];
  const code = page.match(/class="chiffres" aria-label="(\d\d)"/)[1];
  return { conf, verifier, state, redirect, nav, interaction, page, demandeId, code };
}

/** Le navigateur termine : suit la redirection jusqu'au site. */
async function finir(c) {
  const t = await c.nav.aller(`${c.interaction.href}/terminer`, { method: 'POST' });
  const { redirection } = await t.json();
  let r = await c.nav.aller(new URL(redirection, BASE).href);
  while (r.status >= 300 && r.status < 400 && !r.headers.get('location').startsWith(c.redirect)) {
    r = await c.nav.aller(new URL(r.headers.get('location'), BASE).href);
  }
  return new URL(r.headers.get('location'));
}

async function jetons(c, retour) {
  return oidc.authorizationCodeGrant(c.conf, retour, { pkceCodeVerifier: c.verifier, expectedState: c.state });
}

test('la page de connexion montre un QR, le nombre, et rien de personnel', async () => {
  const c = await commencer('site-a');
  assert.match(c.page, /<svg class="code"/);
  assert.match(c.page, /Ni numéro, ni e-mail, ni nom|No phone number, no email, no name/);
  assert.equal((await (await c.nav.aller(`${c.interaction.href}/etat`)).json()).etat, 'attente');
});

test('connexion complète : approuvée sur l’appareil, jetons reçus', async () => {
  const tel = nouvelAppareil(BASE);
  assert.equal((await tel.creerCompte()).statut, 201);
  const c = await commencer('site-a', 'openid profile');

  const lu = await tel.appeler('GET', `/v1/demandes/${c.demandeId}`);
  assert.equal(lu.statut, 200);
  assert.equal(lu.corps.client.nom, 'Site A');
  assert.deepEqual(lu.corps.portees, ['openid', 'profile']);
  assert.equal(lu.corps.codes, undefined, 'le nombre à taper n’est jamais envoyé au téléphone');
  assert.equal((await (await c.nav.aller(`${c.interaction.href}/etat`)).json()).etat, 'vue');

  const ok = await tel.appeler('POST', `/v1/demandes/${c.demandeId}/decision`, { decision: 'approuver', code: c.code, portees: ['openid', 'profile'], pseudo: 'Effi' });
  assert.equal(ok.statut, 200);

  const retour = await finir(c);
  assert.ok(retour.searchParams.get('code'));
  const t = await jetons(c, retour);
  const claims = t.claims();
  assert.ok(claims.sub);
  assert.notEqual(claims.sub, tel.compteId, 'le site ne voit jamais l’identifiant interne');
  assert.equal(claims.email, undefined);

  const info = await oidc.fetchUserInfo(c.conf, t.access_token, claims.sub);
  assert.equal(info.preferred_username, 'Effi');
});

test('un identifiant différent par site, stable pour un même site', async () => {
  const tel = nouvelAppareil(BASE);
  await tel.creerCompte();
  const sub = async (clientId) => {
    const c = await commencer(clientId);
    await tel.appeler('GET', `/v1/demandes/${c.demandeId}`);
    await tel.appeler('POST', `/v1/demandes/${c.demandeId}/decision`, { decision: 'approuver', code: c.code, portees: ['openid'] });
    return (await jetons(c, await finir(c))).claims().sub;
  };
  const a1 = await sub('site-a');
  const b1 = await sub('site-b');
  const a2 = await sub('site-a');
  assert.notEqual(a1, b1);
  assert.equal(a1, a2);
});

test('mauvais nombre : demande annulée, le site reçoit access_denied', async () => {
  const tel = nouvelAppareil(BASE);
  await tel.creerCompte();
  const c = await commencer('site-a');
  const faux = c.code === '42' ? '43' : '42';
  const r = await tel.appeler('POST', `/v1/demandes/${c.demandeId}/decision`, { decision: 'approuver', code: faux, portees: ['openid'] });
  assert.equal(r.statut, 403);
  // Pas de deuxième essai.
  const r2 = await tel.appeler('POST', `/v1/demandes/${c.demandeId}/decision`, { decision: 'approuver', code: c.code, portees: ['openid'] });
  assert.equal(r2.statut, 410);
  const retour = await finir(c);
  assert.equal(retour.searchParams.get('error'), 'access_denied');
});

test('refus sur le téléphone : access_denied', async () => {
  const tel = nouvelAppareil(BASE);
  await tel.creerCompte();
  const c = await commencer('site-b');
  await tel.appeler('POST', `/v1/demandes/${c.demandeId}/decision`, { decision: 'refuser' });
  assert.equal((await finir(c)).searchParams.get('error'), 'access_denied');
});

test('requête rejouée, signature fausse, appareil inconnu : refusées', async () => {
  const tel = nouvelAppareil(BASE);
  await tel.creerCompte();
  const premiere = await tel.appeler('GET', '/v1/connexions');
  assert.equal(premiere.statut, 200);
  const rejeu = await tel.appeler('GET', '/v1/connexions', null, { entetesFixes: premiere.entetes });
  assert.equal(rejeu.statut, 401);
  assert.equal(rejeu.corps.erreur, 'signature_rejouee');

  const fausse = await tel.appeler('GET', '/v1/connexions', null, { entetesFixes: { ...premiere.entetes, 'x-droplet-nonce': 'AAAAAAAAAAAAAAAAAAAAAA', 'x-droplet-sig': premiere.entetes['x-droplet-sig'] } });
  assert.equal(fausse.corps.erreur, 'signature_fausse');

  const vieille = await tel.appeler('GET', '/v1/connexions', null, { entetesFixes: { ...premiere.entetes, 'x-droplet-ts': String(Math.floor(Date.now() / 1000) - 3600) } });
  assert.equal(vieille.corps.erreur, 'signature_perimee');

  const sansSignature = await fetch(`${BASE}/v1/connexions`);
  assert.equal(sansSignature.status, 401);
});

test('un appareil retiré ne peut plus rien faire', async () => {
  const tel = nouvelAppareil(BASE);
  await tel.creerCompte();
  assert.equal((await tel.appeler('DELETE', `/v1/appareils/${tel.appareilId}`)).statut, 200);
  const r = await tel.appeler('GET', '/v1/connexions');
  assert.equal(r.statut, 401);
  assert.equal(r.corps.erreur, 'appareil_revoque');
});

test('retirer un site révoque ses jetons', async () => {
  const tel = nouvelAppareil(BASE);
  await tel.creerCompte();
  const c = await commencer('site-a');
  await tel.appeler('POST', `/v1/demandes/${c.demandeId}/decision`, { decision: 'approuver', code: c.code, portees: ['openid'] });
  const t = await jetons(c, await finir(c));
  const liste = await tel.appeler('GET', '/v1/connexions');
  assert.equal(liste.corps.connexions[0].client_id, 'site-a');
  await tel.appeler('DELETE', '/v1/connexions/site-a');
  await assert.rejects(oidc.fetchUserInfo(c.conf, t.access_token, t.claims().sub));
});

test('sans PKCE ou avec une adresse de retour inconnue : refusé', async () => {
  const sansPkce = await fetch(`${BASE}/oauth2/auth?client_id=site-a&response_type=code&scope=openid&redirect_uri=${encodeURIComponent('http://localhost:7001/retour')}`, { redirect: 'manual' });
  assert.match(sansPkce.headers.get('location') ?? '', /error=invalid_request/);
  const mauvaisRetour = await fetch(`${BASE}/oauth2/auth?client_id=site-a&response_type=code&scope=openid&code_challenge=${'a'.repeat(43)}&code_challenge_method=S256&redirect_uri=${encodeURIComponent('https://pirate.example/retour')}`, { redirect: 'manual' });
  assert.equal(mauvaisRetour.status, 400);
});

test('les portées e-mail et téléphone n’existent pas', async () => {
  const conf = await (await fetch(`${BASE}/.well-known/openid-configuration`)).json();
  assert.ok(!conf.scopes_supported.includes('email'));
  assert.ok(!conf.scopes_supported.includes('phone'));
  assert.deepEqual(conf.subject_types_supported, ['pairwise']);
  assert.deepEqual(conf.code_challenge_methods_supported, ['S256']);
});
