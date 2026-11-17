// ============================================================================
// LA CONSOLE DÉVELOPPEURS — /console
// ----------------------------------------------------------------------------
// • Le développeur se connecte AVEC Droplet ID (la console est un client
//   OpenID Connect comme les autres : flux « code » + PKCE + secret).
// • Il crée ses apps : identifiant, secret, adresses de retour, logo, écran
//   de connexion. Chaque app est un client dynamique, actif tout de suite
//   sur le service de TEST ; la production se demande (vérification).
// • Cookies : session signée (HMAC), chemin /console, HttpOnly, SameSite=Lax.
//   Chaque formulaire porte un jeton anti-CSRF, et l'origine est vérifiée.
// ============================================================================

import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { MAX_APPS, hotesDe, metadonnees, nouvelIdentifiant, nouveauSecret, verifierInfos } from './apps.js';
import * as P from './pages-console.js';

const DUREE_SESSION = 7 * 24 * 3600; // secondes
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');

export const CLIENT_CONSOLE = 'console';

/** Le client OpenID de la console elle-même (enregistré avec les clients fixes). */
export function clientConsole(config) {
  return {
    client_id: CLIENT_CONSOLE,
    client_secret: createHmac('sha256', config.clesCookies[0]).update('client-console').digest('base64url'),
    client_name: 'Console Droplet ID',
    client_uri: `${config.emetteur}/console`,
    logo_uri: `${config.emetteur}/static/favicon.svg`,
    redirect_uris: [`${config.emetteur}/console/retour`],
    post_logout_redirect_uris: [`${config.emetteur}/console`],
    token_endpoint_auth_method: 'client_secret_basic',
  };
}

export function routesConsole({ fournisseur, stockage, config, repondre, logos }) {
  const cle = config.clesCookies[0];
  const securise = config.emetteur.startsWith('https:');
  const origine = new URL(config.emetteur).origin;
  const client = clientConsole(config);

  // ── Cookies signés ──────────────────────────────────────────────────
  const signer = (valeur) => `${valeur}.${createHmac('sha256', cle).update(valeur).digest('base64url')}`;
  const verifier = (signe) => {
    const i = String(signe ?? '').lastIndexOf('.');
    if (i < 1) return null;
    const valeur = signe.slice(0, i);
    const attendu = Buffer.from(createHmac('sha256', cle).update(valeur).digest('base64url'));
    const recu = Buffer.from(signe.slice(i + 1));
    if (attendu.length !== recu.length || !timingSafeEqual(attendu, recu)) return null;
    try {
      const o = JSON.parse(Buffer.from(valeur, 'base64url').toString());
      return o.exp > Date.now() / 1000 ? o : null;
    } catch {
      return null;
    }
  };
  const cookies = (req) => Object.fromEntries(String(req.headers.cookie ?? '').split(/;\s*/).filter(Boolean).map((c) => [c.slice(0, c.indexOf('=')), c.slice(c.indexOf('=') + 1)]));
  const poser = (nom, valeur, duree) =>
    `${nom}=${valeur}; Path=/console; HttpOnly; SameSite=Lax; Max-Age=${duree}${securise ? '; Secure' : ''}`;

  const session = (req) => verifier(cookies(req).dc_session);
  const jeton = (s) => createHmac('sha256', cle).update(`csrf|${s.sub}|${s.exp}`).digest('base64url');

  const rediriger = (res, ou, enTetes = {}) => {
    res.writeHead(303, { location: ou, 'cache-control': 'no-store', ...enTetes });
    res.end();
  };

  function lireFormulaire(req) {
    return new Promise((ok, ko) => {
      let corps = '';
      req.setEncoding('utf8');
      req.on('data', (x) => {
        corps += x;
        if (corps.length > 16384) {
          ko(new Error('trop_grand'));
          req.destroy();
        }
      });
      req.on('end', () => ok(Object.fromEntries(new URLSearchParams(corps))));
      req.on('error', ko);
    });
  }

  // ── Connexion à la console, avec Droplet ID ─────────────────────────
  function commencer(res, retour = '/console/apps') {
    const verifierPkce = randomBytes(32).toString('base64url');
    const attente = { state: randomBytes(16).toString('base64url'), nonce: randomBytes(16).toString('base64url'), v: verifierPkce, r: retour, exp: Math.floor(Date.now() / 1000) + 600 };
    const q = new URLSearchParams({
      client_id: CLIENT_CONSOLE,
      redirect_uri: client.redirect_uris[0],
      response_type: 'code',
      scope: 'openid profile',
      state: attente.state,
      nonce: attente.nonce,
      code_challenge: createHash('sha256').update(verifierPkce).digest('base64url'),
      code_challenge_method: 'S256',
    });
    rediriger(res, `/oauth2/auth?${q}`, { 'set-cookie': poser('dc_attente', signer(b64(attente)), 600) });
  }

  async function terminer(req, res, url) {
    const attente = verifier(cookies(req).dc_attente);
    const effacer = poser('dc_attente', '', 0);
    if (!attente || url.searchParams.get('state') !== attente.state) return rediriger(res, '/console?erreur=expire', { 'set-cookie': effacer });
    if (url.searchParams.get('error')) return rediriger(res, '/console?erreur=refuse', { 'set-cookie': effacer });
    const r = await fetch(`${config.emetteur}/oauth2/token`, {
      method: 'POST',
      headers: {
        'content-type': 'application/x-www-form-urlencoded',
        authorization: `Basic ${Buffer.from(`${CLIENT_CONSOLE}:${client.client_secret}`).toString('base64')}`,
      },
      body: new URLSearchParams({ grant_type: 'authorization_code', code: url.searchParams.get('code') ?? '', redirect_uri: client.redirect_uris[0], code_verifier: attente.v }),
    });
    if (!r.ok) return rediriger(res, '/console?erreur=expire', { 'set-cookie': effacer });
    const t = await r.json();
    // Reçu directement du service, en TLS : on vérifie l'émetteur, le
    // destinataire, le nonce et l'expiration.
    const c = JSON.parse(Buffer.from(t.id_token.split('.')[1], 'base64url').toString());
    if (c.iss !== config.emetteur || c.aud !== CLIENT_CONSOLE || c.nonce !== attente.nonce || c.exp < Date.now() / 1000) {
      return rediriger(res, '/console?erreur=expire', { 'set-cookie': effacer });
    }
    let pseudo = null;
    const u = await fetch(`${config.emetteur}/userinfo`, { headers: { authorization: `Bearer ${t.access_token}` } });
    if (u.ok) pseudo = (await u.json()).preferred_username ?? null;
    const s = { sub: c.sub, pseudo, exp: Math.floor(Date.now() / 1000) + DUREE_SESSION };
    const retour = /^\/console\/[a-z0-9/_-]*$/i.test(attente.r) ? attente.r : '/console/apps';
    rediriger(res, retour, { 'set-cookie': [effacer, poser('dc_session', signer(b64(s)), DUREE_SESSION)] });
  }

  // ── Les apps ────────────────────────────────────────────────────────
  async function enregistrerClient(clientId, infos, secret) {
    await stockage.adaptateur('Client').upsert(clientId, metadonnees(clientId, infos, { secret, emetteur: config.emetteur }));
  }
  const secretActuel = async (clientId) => (await stockage.adaptateur('Client').find(clientId))?.client_secret;

  async function contexte(s, app) {
    const [utilisateurs, jours, logo] = await Promise.all([
      stockage.utilisateursDe(app.clientId),
      stockage.connexionsParJour(app.clientId, 30),
      app.infos.logo ? logos.adresse({ clientId: app.clientId, logoUri: app.infos.logo }) : null,
    ]);
    return { session: s, csrf: jeton(s), app, utilisateurs, jours, logo, emetteur: config.emetteur, test: config.environnementDeTest };
  }

  return async function routes(req, res, chemin, url) {
    if (!chemin.startsWith('/console')) return false;
    const html = (statut, page) => repondre(res, statut, page, 'html');

    // Publique : la liste des adresses d'une app (sector_identifier_uri).
    const ms = chemin.match(/^\/console\/secteur\/(app_[A-Za-z0-9_-]{16})$/);
    if (ms && req.method === 'GET') {
      const app = await stockage.app(ms[1]);
      if (!app) return repondre(res, 404, { erreur: 'introuvable' }), true;
      return repondre(res, 200, app.infos.redirections), true;
    }

    if (chemin === '/console/connexion' && req.method === 'GET') return commencer(res, url.searchParams.get('r') || '/console/apps'), true;
    if (chemin === '/console/retour' && req.method === 'GET') return (await terminer(req, res, url)), true;

    const s = session(req);
    if (chemin === '/console' || chemin === '/console/') {
      if (s) return rediriger(res, '/console/apps'), true;
      return html(200, P.pageAccueilConsole({ erreur: url.searchParams.get('erreur'), test: config.environnementDeTest })), true;
    }
    if (!s) {
      if (req.method === 'GET') return commencer(res, chemin), true;
      return repondre(res, 401, { erreur: 'non_connecte' }), true;
    }

    // Toute écriture : même origine + jeton du formulaire.
    let f = {};
    if (req.method === 'POST') {
      // Les pages envoient « Referrer-Policy: no-referrer » : le navigateur
      // annonce alors l'origine « null » ; Sec-Fetch-Site dit si c'est bien nous.
      const o = req.headers.origin;
      const site = req.headers['sec-fetch-site'];
      const memeOrigine = o === origine || (o === 'null' && site === 'same-origin') || (!o && (!site || site === 'same-origin'));
      if (!memeOrigine || (site && site !== 'same-origin')) return repondre(res, 403, { erreur: 'origine' }), true;
      f = await lireFormulaire(req);
      const attendu = Buffer.from(jeton(s));
      const recu = Buffer.from(String(f._csrf ?? ''));
      if (attendu.length !== recu.length || !timingSafeEqual(attendu, recu)) return repondre(res, 403, { erreur: 'csrf' }), true;
    } else if (req.method !== 'GET') {
      return repondre(res, 405, { erreur: 'methode' }), true;
    }

    if (chemin === '/console/deconnexion' && req.method === 'POST') {
      return rediriger(res, '/console', { 'set-cookie': poser('dc_session', '', 0) }), true;
    }

    const base = { session: s, csrf: jeton(s), test: config.environnementDeTest, emetteur: config.emetteur };

    if (chemin === '/console/apps') {
      if (req.method === 'POST') {
        const mesApps = await stockage.appsDe(s.sub);
        const v = verifierInfos({ ...f, profil: f.profil ?? '0' });
        if (mesApps.length >= MAX_APPS) v.erreurs = { ...v.erreurs, nom: 'trop_d_apps' };
        if (v.erreurs) return html(422, P.pageNouvelleApp({ ...base, infos: { ...v.infos, redirections: f.redirections }, erreurs: v.erreurs })), true;
        const clientId = nouvelIdentifiant();
        const secret = v.infos.type === 'serveur' ? nouveauSecret() : undefined;
        await stockage.creerApp({ clientId, proprietaire: s.sub, statut: 'test', infos: v.infos });
        await enregistrerClient(clientId, v.infos, secret);
        await stockage.journaliser(clientId, `App créée (${v.infos.type})`);
        const app = await stockage.app(clientId);
        return html(201, P.pageIdentifiants({ ...(await contexte(s, app)), secretNeuf: secret, creee: true })), true;
      }
      const mesApps = await stockage.appsDe(s.sub);
      const lignes = await Promise.all(
        mesApps.map(async (a) => ({
          app: a,
          utilisateurs: await stockage.utilisateursDe(a.clientId),
          semaine: (await stockage.connexionsParJour(a.clientId, 7)).reduce((n, j) => n + j.nombre, 0),
          logo: a.infos.logo ? await logos.adresse({ clientId: a.clientId, logoUri: a.infos.logo }) : null,
        })),
      );
      return html(200, P.pageApps({ ...base, lignes })), true;
    }
    if (chemin === '/console/apps/nouvelle' && req.method === 'GET') return html(200, P.pageNouvelleApp({ ...base, infos: { type: 'serveur', profil: false }, erreurs: {} })), true;

    const m = chemin.match(/^\/console\/apps\/(app_[A-Za-z0-9_-]{16})(?:\/(identifiants|ecran|adresses|production|journal|supprimer|secret))?$/);
    if (!m) return html(404, P.pageIntrouvable(base)), true;
    const app = await stockage.app(m[1]);
    // L'app d'un autre développeur n'existe pas, vue d'ici.
    if (!app || app.proprietaire !== s.sub) return html(404, P.pageIntrouvable(base)), true;
    const onglet = m[2] ?? 'apercu';

    if (req.method === 'POST') {
      if (onglet === 'ecran' || onglet === 'adresses') {
        const champs = onglet === 'ecran' ? { nom: f.nom, site: f.site, logo: f.logo, politique: f.politique, conditions: f.conditions, profil: f.profil ?? '0' } : { redirections: f.redirections, deconnexions: f.deconnexions };
        const v = verifierInfos(champs, app.infos);
        if (v.erreurs) {
          const brut = onglet === 'adresses' ? { redirections: f.redirections, deconnexions: f.deconnexions } : {};
          return html(422, (onglet === 'ecran' ? P.pageEcran : P.pageAdresses)({ ...(await contexte(s, { ...app, infos: { ...v.infos, ...brut } })), erreurs: v.erreurs })), true;
        }
        await stockage.majApp(app.clientId, { infos: v.infos });
        await enregistrerClient(app.clientId, v.infos, await secretActuel(app.clientId));
        await stockage.journaliser(app.clientId, onglet === 'ecran' ? 'Écran de connexion modifié' : 'Adresses de retour modifiées');
        return rediriger(res, `/console/apps/${app.clientId}/${onglet}?enregistre=1`), true;
      }
      if (onglet === 'secret') {
        if (app.infos.type !== 'serveur') return html(400, P.pageIntrouvable(base)), true;
        const secret = nouveauSecret();
        await enregistrerClient(app.clientId, app.infos, secret);
        await stockage.journaliser(app.clientId, 'Nouveau secret (l’ancien ne marche plus)');
        return html(200, P.pageIdentifiants({ ...(await contexte(s, app)), secretNeuf: secret })), true;
      }
      if (onglet === 'production') {
        const ctx = await contexte(s, app);
        if (!P.pretPourProduction(ctx).every((c) => c.ok)) return html(422, P.pageProduction(ctx)), true;
        await stockage.majApp(app.clientId, { statut: 'verification' });
        await stockage.journaliser(app.clientId, 'Mise en production demandée');
        return rediriger(res, `/console/apps/${app.clientId}/production`), true;
      }
      if (onglet === 'supprimer') {
        if (String(f.confirmation ?? '').trim() !== app.infos.nom) return html(422, P.pageSupprimer({ ...(await contexte(s, app)), erreur: true })), true;
        await stockage.supprimerApp(app.clientId);
        return rediriger(res, '/console/apps?supprimee=1'), true;
      }
      return repondre(res, 405, { erreur: 'methode' }), true;
    }

    const ctx = { ...(await contexte(s, app)), enregistre: url.searchParams.get('enregistre') === '1' };
    const pages = {
      apercu: P.pageApercu,
      identifiants: P.pageIdentifiants,
      ecran: P.pageEcran,
      adresses: P.pageAdresses,
      production: P.pageProduction,
      journal: async (c) => P.pageJournal({ ...c, journal: await stockage.journalDe(app.clientId) }),
      supprimer: P.pageSupprimer,
    };
    if (!pages[onglet]) return html(404, P.pageIntrouvable(base)), true;
    return html(200, await pages[onglet](ctx)), true;
  };
}

export { hotesDe };
