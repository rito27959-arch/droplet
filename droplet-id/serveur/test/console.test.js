// La console développeurs, de bout en bout : se connecter AVEC Droplet ID,
// créer une app, s'y connecter, voir les statistiques, changer le secret,
// les adresses, la mise en production, la suppression. Et les protections.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import * as oidc from 'openid-client';
import { demarrer } from '../src/serveur.js';
import { nouvelleCleDeSignature } from '../src/config.js';
import { nouvelAppareil, nouveauNavigateur } from './outils.js';

const PORT = 19000 + Math.floor(Math.random() * 1000);
const BASE = `http://localhost:${PORT}`;
let service;

before(async () => {
  service = await demarrer({
    port: PORT,
    emetteur: BASE,
    baseDeDonnees: process.env.TEST_DATABASE_URL ?? null,
    jwks: { keys: [nouvelleCleDeSignature('test')] },
    clesCookies: ['cle-de-test-cookies-0123456789abcdef'],
    selPairwise: 'sel-de-test',
    clients: [],
    environnementDeTest: true,
    console: true,
    dureeDemande: 120,
    fenetreSignature: 300,
    derriereProxy: false,
  });
});
after(() => service.arreter());

/** Suit les redirections (mêmes cookies) jusqu'à une adresse qui commence par `fin`. */
async function suivre(nav, r, fin) {
  while (r.status >= 300 && r.status < 400) {
    const ou = new URL(r.headers.get('location'), BASE);
    if (fin && ou.href.startsWith(fin)) return ou;
    r = await nav.aller(ou.href);
  }
  return r;
}

/** Approuve la page d'interaction ouverte dans `nav` avec `tel`. */
async function approuver(nav, interaction, tel, { portees = ['openid'], pseudo } = {}) {
  const page = await (await nav.aller(interaction)).text();
  const demandeId = page.match(/\/a\/([A-Za-z0-9_-]{16,})/)[1];
  const code = page.match(/class="chiffres" aria-label="(\d\d)"/)[1];
  const d = await tel.appeler('POST', `/v1/demandes/${demandeId}/decision`, { decision: 'approuver', code, portees, pseudo });
  assert.equal(d.statut, 200, JSON.stringify(d.corps));
  const t = await nav.aller(`${interaction}/terminer`, { method: 'POST' });
  return new URL((await t.json()).redirection, BASE);
}

/** Un développeur connecté à la console : son navigateur et son jeton CSRF. */
async function developpeur(pseudo) {
  const tel = nouvelAppareil(BASE);
  await tel.creerCompte();
  const nav = nouveauNavigateur();
  const r = await nav.aller(`${BASE}/console/connexion`);
  assert.equal(r.status, 303);
  const interaction = await suivre(nav, r, `${BASE}/interaction/`);
  const suite = await approuver(nav, interaction.href, tel, { portees: ['openid', 'profile'], pseudo });
  const fin = await suivre(nav, await nav.aller(suite.href));
  assert.equal(fin.status, 200, 'arrivé sur la console');
  const page = await fin.text();
  assert.match(page, new RegExp(pseudo));
  return { nav, tel, csrf: page.match(/name="_csrf" value="([^"]+)"/)[1] };
}

const envoyer = (dev, chemin, champs, { csrf = dev.csrf, origine = BASE } = {}) =>
  dev.nav.aller(`${BASE}${chemin}`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded', origin: origine },
    body: new URLSearchParams({ _csrf: csrf, ...champs }).toString(),
  });

test('la porte de la console, puis la connexion avec Droplet ID', async () => {
  const r = await fetch(`${BASE}/console`);
  assert.equal(r.status, 200);
  assert.match(await r.text(), /Se connecter avec Droplet ID/);
  // Une page protégée sans session renvoie vers la connexion.
  const p = await fetch(`${BASE}/console/apps`, { redirect: 'manual' });
  assert.equal(p.status, 303);
  assert.match(p.headers.get('location'), /^\/oauth2\/auth\?client_id=console&/);
  const dev = await developpeur('Ada');
  const apps = await (await dev.nav.aller(`${BASE}/console/apps`)).text();
  assert.match(apps, /Votre première app/);
});

test('créer une app « serveur », s’y connecter avec son secret, voir les chiffres', async () => {
  const dev = await developpeur('Bilal');

  // Sans jeton CSRF, ou depuis une autre origine : refusé.
  assert.equal((await envoyer(dev, '/console/apps', { nom: 'X' }, { csrf: 'faux' })).status, 403);
  assert.equal((await envoyer(dev, '/console/apps', { nom: 'X' }, { origine: 'https://pirate.example' })).status, 403);

  // Erreurs claires.
  const mauvais = await envoyer(dev, '/console/apps', { nom: 'A', type: 'serveur', site: 'http://exemple.com', redirections: '' });
  assert.equal(mauvais.status, 422);
  const pm = await mauvais.text();
  assert.match(pm, /Entre 2 et 40 caractères/);
  assert.match(pm, /https:\/\/ \(http:\/\/ seulement pour localhost\)/);
  assert.match(pm, /Ce champ est obligatoire/);

  const cree = await envoyer(dev, '/console/apps', {
    nom: 'Boutique Bilal',
    type: 'serveur',
    site: 'http://localhost:7101',
    redirections: 'http://localhost:7101/retour',
    profil: '1',
  });
  assert.equal(cree.status, 201);
  const page = await cree.text();
  const clientId = page.match(/app_[A-Za-z0-9_-]{16}/)[0];
  const secret = page.match(/dsec_[A-Za-z0-9_-]{43}/)[0];
  assert.match(page, /Copiez ce secret maintenant/);

  // Le secret n'est plus jamais réaffiché.
  const ident = await (await dev.nav.aller(`${BASE}/console/apps/${clientId}/identifiants`)).text();
  assert.doesNotMatch(ident, /dsec_/);

  // L'app marche tout de suite : vrai flux OpenID avec secret + PKCE.
  const conf = await oidc.discovery(new URL(BASE), clientId, secret, oidc.ClientSecretBasic(secret), { execute: [oidc.allowInsecureRequests] });
  const verifier = oidc.randomPKCECodeVerifier();
  const state = oidc.randomState();
  const url = oidc.buildAuthorizationUrl(conf, {
    redirect_uri: 'http://localhost:7101/retour', scope: 'openid profile', state,
    code_challenge: await oidc.calculatePKCECodeChallenge(verifier), code_challenge_method: 'S256',
  });
  const visiteur = nouvelAppareil(BASE);
  await visiteur.creerCompte();
  const nav = nouveauNavigateur();
  const inter = await suivre(nav, await nav.aller(url.href), `${BASE}/interaction/`);
  const page2 = await (await nav.aller(inter.href)).text();
  assert.match(page2, /Se connecter à Boutique Bilal/);
  const suite = await approuver(nav, inter.href, visiteur, { portees: ['openid', 'profile'], pseudo: 'Client1' });
  const retour = await suivre(nav, await nav.aller(suite.href), 'http://localhost:7101/retour');
  const jetons = await oidc.authorizationCodeGrant(conf, retour, { pkceCodeVerifier: verifier, expectedState: state });
  assert.ok(jetons.claims().sub);
  assert.equal((await oidc.fetchUserInfo(conf, jetons.access_token, jetons.claims().sub)).preferred_username, 'Client1');

  // Les chiffres de l'app.
  const apercu = await (await dev.nav.aller(`${BASE}/console/apps/${clientId}`)).text();
  assert.match(apercu, /<span>Utilisateurs<\/span><b>1<\/b>/);
  assert.match(apercu, /<span>Connexions<\/span><b>1<\/b>/);
  assert.match(apercu, new RegExp(`clientId: &#39;${clientId}&#39;`), 'exemple de code prérempli');
  const liste = await (await dev.nav.aller(`${BASE}/console/apps`)).text();
  assert.match(liste, /Boutique Bilal/);

  // Nouveau secret : l'ancien cesse de marcher.
  const nouveau = await (await envoyer(dev, `/console/apps/${clientId}/secret`, {})).text();
  const secret2 = nouveau.match(/dsec_[A-Za-z0-9_-]{43}/)[0];
  assert.notEqual(secret2, secret);
  const ancien = await fetch(`${BASE}/oauth2/token`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded', authorization: `Basic ${Buffer.from(`${clientId}:${secret}`).toString('base64')}` },
    body: 'grant_type=refresh_token&refresh_token=x',
  });
  assert.equal(ancien.status, 401);
  assert.equal((await ancien.json()).error, 'invalid_client');

  // Journal.
  const journal = await (await dev.nav.aller(`${BASE}/console/apps/${clientId}/journal`)).text();
  assert.match(journal, /App créée \(serveur\)/);
  assert.match(journal, /Nouveau secret/);
});

test('modifier, protections entre développeurs, production, suppression', async () => {
  const dev = await developpeur('Chloé');
  const autre = await developpeur('Dan');
  const cree = await (await envoyer(dev, '/console/apps', { nom: 'Kiosque', type: 'navigateur', site: 'http://localhost:7201', redirections: 'http://localhost:7201/' })).text();
  const clientId = cree.match(/app_[A-Za-z0-9_-]{16}/)[0];
  assert.doesNotMatch(cree, /dsec_/, 'pas de secret pour une app dans le navigateur');

  // Un autre développeur ne voit ni ne modifie l'app.
  assert.equal((await autre.nav.aller(`${BASE}/console/apps/${clientId}`)).status, 404);
  assert.equal((await envoyer(autre, `/console/apps/${clientId}/supprimer`, { confirmation: 'Kiosque' })).status, 404);

  // Adresses : refus d'une adresse http publique, puis enregistrement.
  const refus = await envoyer(dev, `/console/apps/${clientId}/adresses`, { redirections: 'http://exemple.com/retour' });
  assert.equal(refus.status, 422);
  const ok = await envoyer(dev, `/console/apps/${clientId}/adresses`, { redirections: 'http://localhost:7201/\nhttp://localhost:7201/autre', deconnexions: '' });
  assert.equal(ok.status, 303);
  const client = await service.stockage.adaptateur('Client').find(clientId);
  assert.deepEqual(client.redirect_uris, ['http://localhost:7201/', 'http://localhost:7201/autre']);
  assert.equal(client.token_endpoint_auth_method, 'none');

  // Écran de connexion.
  assert.equal((await envoyer(dev, `/console/apps/${clientId}/ecran`, { nom: 'Kiosque Douala', site: 'http://localhost:7201', logo: '', politique: 'https://kiosque.example/confidentialite', conditions: '' })).status, 303);
  assert.equal((await service.stockage.adaptateur('Client').find(clientId)).client_name, 'Kiosque Douala');

  // Production : refusée tant que la liste n'est pas complète.
  assert.equal((await envoyer(dev, `/console/apps/${clientId}/production`, {})).status, 422);
  assert.equal((await service.stockage.app(clientId)).statut, 'test');

  // Suppression : le nom exact est demandé.
  assert.equal((await envoyer(dev, `/console/apps/${clientId}/supprimer`, { confirmation: 'kiosque' })).status, 422);
  assert.equal((await envoyer(dev, `/console/apps/${clientId}/supprimer`, { confirmation: 'Kiosque Douala' })).status, 303);
  assert.equal(await service.stockage.app(clientId), null);
  assert.equal(await service.stockage.adaptateur('Client').find(clientId), undefined);
});

test('déconnexion de la console', async () => {
  const dev = await developpeur('Eve');
  const r = await envoyer(dev, '/console/deconnexion', {});
  assert.equal(r.status, 303);
  assert.equal((await dev.nav.aller(`${BASE}/console/apps`)).status, 303, 'il faut se reconnecter');
});

test('origine « null » (Referrer-Policy: no-referrer) : acceptée seulement si Sec-Fetch-Site dit même origine', async () => {
  const dev = await developpeur('Fatou');
  const corps = new URLSearchParams({ _csrf: dev.csrf, nom: 'Null', type: 'navigateur', site: 'http://localhost:7301', redirections: 'http://localhost:7301/' }).toString();
  const h = { 'content-type': 'application/x-www-form-urlencoded', origin: 'null' };
  assert.equal((await dev.nav.aller(`${BASE}/console/apps`, { method: 'POST', headers: { ...h, 'sec-fetch-site': 'cross-site' }, body: corps })).status, 403);
  assert.equal((await dev.nav.aller(`${BASE}/console/apps`, { method: 'POST', headers: { ...h, 'sec-fetch-site': 'same-origin' }, body: corps })).status, 201);
});
