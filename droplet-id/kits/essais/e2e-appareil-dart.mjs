// L'app Droplet (son protocole Dart, lib/features/droplet_id/protocole.dart)
// approuve une vraie connexion : le site reçoit son code. Lancé en CI, à la
// racine du dépôt, après `flutter pub get`.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import * as oidc from '../../serveur/node_modules/openid-client/build/index.js';
import { demarrer } from '../../serveur/src/serveur.js';
import { nouvelleCleDeSignature } from '../../serveur/src/config.js';
import { nouveauNavigateur } from '../../serveur/test/outils.js';

const run = promisify(execFile);
const BASE = 'http://localhost:18950';
const RETOUR = 'http://localhost:7300/retour';
const service = await demarrer({
  port: 18950, emetteur: BASE, baseDeDonnees: null, jwks: { keys: [nouvelleCleDeSignature('dart')] },
  clesCookies: ['cle-dart-0123456789abcdef0123456789'], selPairwise: 'sel', clients: [{ client_id: 'site-dart', client_name: 'Site Dart', redirect_uris: [RETOUR] }],
  environnementDeTest: true, dureeDemande: 120, fenetreSignature: 300, derriereProxy: false,
});
const etat = `${mkdtempSync(`${tmpdir()}/did-`)}/etat.json`;
const dart = (...a) => run('dart', ['run', 'tool/droplet_id_appareil.dart', BASE, etat, ...a], { encoding: 'utf8' });
try {
  await dart('creer');
  const conf = await oidc.discovery(new URL(BASE), 'site-dart', undefined, oidc.None(), { execute: [oidc.allowInsecureRequests] });
  const verifier = oidc.randomPKCECodeVerifier();
  const state = oidc.randomState();
  const url = oidc.buildAuthorizationUrl(conf, { redirect_uri: RETOUR, scope: 'openid profile', code_challenge: await oidc.calculatePKCECodeChallenge(verifier), code_challenge_method: 'S256', state });
  const nav = nouveauNavigateur();
  const inter = new URL((await nav.aller(url.href)).headers.get('location'), BASE);
  const page = await (await nav.aller(inter.href)).text();
  const demande = page.match(/\/a\/([A-Za-z0-9_-]{16,})/)[1];
  const code = page.match(/class="chiffres" aria-label="(\d\d)"/)[1];
  const { stdout } = await dart('approuver', demande, code, 'Effi');
  console.log('appareil Dart :', stdout.trim());
  const { redirection } = await (await nav.aller(`${inter.href}/terminer`, { method: 'POST' })).json();
  let r = await nav.aller(new URL(redirection, BASE).href);
  while (!r.headers.get('location').startsWith(RETOUR)) r = await nav.aller(new URL(r.headers.get('location'), BASE).href);
  const t = await oidc.authorizationCodeGrant(conf, new URL(r.headers.get('location')), { pkceCodeVerifier: verifier, expectedState: state });
  const info = await oidc.fetchUserInfo(conf, t.access_token, t.claims().sub);
  if (info.preferred_username !== 'Effi') throw new Error('pseudo absent');
  console.log(`✓ app Droplet (Dart) : connexion approuvée, jetons reçus, sub ${t.claims().sub.slice(0, 10)}…`);
} catch (e) {
  console.error('✗ app Droplet (Dart) :', e.stderr ?? e.message);
  process.exitCode = 1;
} finally {
  await service.arreter();
}
