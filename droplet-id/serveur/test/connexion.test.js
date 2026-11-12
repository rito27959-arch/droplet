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
  { client_id: 'site-a', client_name: 'Site A', redirect_uris: ['http://localhost:7001/retour'], logo_uri: `http://localhost:${PORT + 1}/logo.svg` },
  { client_id: 'site-b', client_name: 'Site B', redirect_uris: ['http://localhost:7002/retour'] },
];
let service;
let siteLogo;

before(async () => {
  // Le site A publie son logo (SVG) ; le service le télécharge lui-même.
  const { createServer } = await import('node:http');
  siteLogo = createServer((req, res) => {
    if (req.url !== '/logo.svg') return res.writeHead(404).end();
    res.writeHead(200, { 'content-type': 'image/svg+xml' });
    res.end('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#c23a46"/></svg>');
  }).listen(PORT + 1);
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
after(() => { service.arreter(); siteLogo.close(); });

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
  assert.match(c.page, /<s>Numéro<\/s><s>E-mail<\/s><s>Nom<\/s>|<s>Phone number<\/s>/);
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

// ── Rester connecté ─────────────────────────────────────────────────────
/** Lance une connexion dans un navigateur existant ; rend la 1re réponse. */
async function lancer(nav, clientId, scope = 'openid') {
  const conf = await oidc.discovery(new URL(BASE), clientId, undefined, oidc.None(), { execute: [oidc.allowInsecureRequests] });
  const verifier = oidc.randomPKCECodeVerifier();
  const state = oidc.randomState();
  const redirect = CLIENTS.find((c) => c.client_id === clientId).redirect_uris[0];
  const url = oidc.buildAuthorizationUrl(conf, { redirect_uri: redirect, scope, code_challenge: await oidc.calculatePKCECodeChallenge(verifier), code_challenge_method: 'S256', state });
  const r = await nav.aller(url.href);
  return { conf, verifier, state, redirect, nav, r };
}

/** Suit les redirections jusqu'au site. */
async function jusquAuSite(c, r) {
  while (r.status >= 300 && r.status < 400 && !r.headers.get('location').startsWith(c.redirect)) {
    r = await c.nav.aller(new URL(r.headers.get('location'), BASE).href);
  }
  return new URL(r.headers.get('location'));
}

test('session mémorisée : cookie persistant, « Continuer » sans téléphone, puis retour direct', async () => {
  const tel = nouvelAppareil(BASE);
  await tel.creerCompte();
  const nav = nouveauNavigateur();

  // 1. Première connexion, au téléphone.
  const a = await lancer(nav, 'site-a');
  const inter = new URL(a.r.headers.get('location'), BASE);
  const page = await (await nav.aller(inter.href)).text();
  const demandeId = page.match(/\/a\/([A-Za-z0-9_-]{16,})/)[1];
  const code = page.match(/class="chiffres" aria-label="(\d\d)"/)[1];
  await tel.appeler('POST', `/v1/demandes/${demandeId}/decision`, { decision: 'approuver', code, portees: ['openid'] });
  const t = await nav.aller(`${inter.href}/terminer`, { method: 'POST' });
  const subA = (await jetons(a, await jusquAuSite(a, await nav.aller(new URL((await t.json()).redirection, BASE).href)))).claims().sub;

  // Le cookie de session survit à la fermeture du navigateur (Expires/Max-Age).
  const session = nav.brut.filter((c) => /^_session=/.test(c) && !/expires=Thu, 01 Jan 1970/i.test(c)).pop();
  assert.ok(session, 'cookie de session posé');
  assert.match(session, /expires=|max-age=/i, 'cookie persistant, pas un cookie de session navigateur');

  // 2. Un autre site : « Continuer vers Site B », sans téléphone.
  const b = await lancer(nav, 'site-b', 'openid profile');
  const interB = new URL(b.r.headers.get('location'), BASE);
  const pageB = await (await nav.aller(interB.href)).text();
  assert.match(pageB, /action="\/interaction\/[^"]+\/continuer"/);
  assert.doesNotMatch(pageB, /<svg class="code"/, 'pas de QR');
  // « Utiliser un autre compte » ramène au QR.
  assert.match(await (await nav.aller(`${interB.href}?autre=1`)).text(), /<svg class="code"/);
  const fin = await nav.aller(`${interB.href}/continuer`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: 'profil=1&pseudo=Ngono',
  });
  assert.equal(fin.status, 303);
  const tb = await jetons(b, await jusquAuSite(b, await nav.aller(new URL(fin.headers.get('location'), BASE).href)));
  assert.notEqual(tb.claims().sub, subA, 'identifiant propre au site');
  assert.equal((await oidc.fetchUserInfo(b.conf, tb.access_token, tb.claims().sub)).preferred_username, 'Ngono');
  assert.ok((await tel.appeler('GET', '/v1/connexions')).corps.connexions.some((x) => x.client_id === 'site-b'), 'visible dans l’app');

  // 3. Retour sur le site A : aucune page, droit au site.
  const a2 = await lancer(nav, 'site-a');
  const retour = await jusquAuSite(a2, a2.r);
  assert.ok(retour.searchParams.get('code'));
  assert.equal((await jetons(a2, retour)).claims().sub, subA);
});

test('appareil retiré : plus de « Continuer », retour au QR', async () => {
  const tel = nouvelAppareil(BASE);
  await tel.creerCompte();
  const nav = nouveauNavigateur();
  const a = await lancer(nav, 'site-a');
  const inter = new URL(a.r.headers.get('location'), BASE);
  const page = await (await nav.aller(inter.href)).text();
  const demandeId = page.match(/\/a\/([A-Za-z0-9_-]{16,})/)[1];
  const code = page.match(/class="chiffres" aria-label="(\d\d)"/)[1];
  await tel.appeler('POST', `/v1/demandes/${demandeId}/decision`, { decision: 'approuver', code, portees: ['openid'] });
  const t = await nav.aller(`${inter.href}/terminer`, { method: 'POST' });
  await jusquAuSite(a, await nav.aller(new URL((await t.json()).redirection, BASE).href));

  await tel.appeler('DELETE', `/v1/appareils/${tel.appareilId}`);
  const b = await lancer(nav, 'site-b');
  const pageB = await (await nav.aller(new URL(b.r.headers.get('location'), BASE).href)).text();
  assert.match(pageB, /<svg class="code"/);
  const refus = await nav.aller(`${new URL(b.r.headers.get('location'), BASE).href}/continuer`, { method: 'POST', body: '' });
  assert.equal(refus.status, 303);
  assert.match(refus.headers.get('location'), /^\/interaction\//);
});

test('pages aide, confidentialité, conditions', async () => {
  for (const p of ['aide', 'confidentialite', 'conditions']) {
    const r = await fetch(`${BASE}/${p}?langue=en`);
    assert.equal(r.status, 200);
    assert.match(await r.text(), /<article class="document">/);
  }
});

test('feuille de style versionnée : une nouvelle version change d’adresse', async () => {
  const page = await (await fetch(`${BASE}/aide`)).text();
  const css = page.match(/href="(\/static\/droplet-id\.css\?v=[A-Za-z0-9_-]{10})"/)[1];
  const r = await fetch(BASE + css);
  assert.equal(r.status, 200);
  assert.match(r.headers.get('cache-control'), /immutable/);
  const ancien = await fetch(`${BASE}/static/droplet-id.css`);
  assert.equal(ancien.headers.get('cache-control'), 'no-cache');
});

test('le logo du site : téléchargé par le service, converti en PNG, montré à la place de l’initiale', async () => {
  const c = await commencer('site-a');
  const src = c.page.match(/<img src="(\/logo\/site-a\?v=[A-Za-z0-9_-]{10})"/)[1];
  const r = await fetch(BASE + src);
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('content-type'), 'image/png');
  const octets = Buffer.from(await r.arrayBuffer());
  assert.equal(octets.subarray(1, 4).toString(), 'PNG');
  // Sans logo : l'initiale.
  const b = await commencer('site-b');
  assert.match(b.page, /<span class="tuile tuile-site">S<\/span>/);
  // L'app reçoit l'adresse du logo servi par le service.
  const tel = nouvelAppareil(BASE);
  await tel.creerCompte();
  const lu = await tel.appeler('GET', `/v1/demandes/${c.demandeId}`);
  assert.equal(lu.corps.client.logo, BASE + src);
});

test('« Ouvrir dans Droplet » : lien d’intention Android vers droplet://droplet/a/<demande>, page web en secours', async () => {
  const c = await commencer('site-a');
  const lien = c.page.match(/data-android="([^"]+)"/)[1].replace(/&amp;/g, '&');
  const hote = new URL(BASE).host;
  assert.ok(lien.startsWith(`intent://droplet/a/${c.demandeId}?e=${encodeURIComponent(hote)}#Intent;scheme=droplet;`));
  assert.match(lien, new RegExp(`S\\.browser_fallback_url=${encodeURIComponent(`${BASE}/a/${c.demandeId}`).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')};end$`));
});
