// ============================================================================
// @droplet/id-node — Droplet ID côté serveur (Node.js), par-dessus
// `openid-client` (bibliothèque certifiée OpenID).
//
//   const did = await DropletIdServeur.creer({ clientId, redirectUri });
//   const { url, attente } = await did.commencer();     // garder `attente`
//   const session = await did.terminer(urlDeRetour, attente);
//
// Avec Express, en trois lignes : voir `routesExpress()`.
// ============================================================================

import * as oidc from 'openid-client';
import { createHmac, timingSafeEqual } from 'node:crypto';

export const EMETTEUR = 'https://id.dropletmesh.app';
export const EMETTEUR_TEST = 'https://id-test.dropletmesh.app';

export class DropletIdServeur {
  /**
   * @param {object} o
   * @param {string} o.clientId
   * @param {string} o.redirectUri
   * @param {string} [o.clientSecret]  site « confidentiel » (sinon PKCE seul)
   * @param {string} [o.emetteur]
   * @param {string[]} [o.portees]
   */
  static async creer({ clientId, redirectUri, clientSecret, emetteur = EMETTEUR, portees = ['openid'], _http = false }) {
    const auth = clientSecret ? oidc.ClientSecretPost(clientSecret) : oidc.None();
    const conf = await oidc.discovery(new URL(emetteur), clientId, clientSecret ? { client_secret: clientSecret } : undefined, auth, _http ? { execute: [oidc.allowInsecureRequests] } : undefined);
    return new DropletIdServeur(conf, { clientId, redirectUri, portees: portees.includes('openid') ? portees : ['openid', ...portees] });
  }

  constructor(conf, o) {
    this.conf = conf;
    this.o = o;
  }

  /** Rend l'adresse de Droplet ID et `attente` (à garder jusqu'au retour, côté serveur). */
  async commencer({ langue } = {}) {
    const verifier = oidc.randomPKCECodeVerifier();
    const attente = { verifier, state: oidc.randomState(), nonce: oidc.randomNonce() };
    const url = oidc.buildAuthorizationUrl(this.conf, {
      redirect_uri: this.o.redirectUri,
      scope: this.o.portees.join(' '),
      code_challenge: await oidc.calculatePKCECodeChallenge(verifier),
      code_challenge_method: 'S256',
      state: attente.state,
      nonce: attente.nonce,
      ...(langue ? { ui_locales: langue } : {}),
    });
    return { url: url.href, attente };
  }

  /**
   * Au retour : vérifie tout (state, PKCE, signature et contenu de l'ID token)
   * et rend la session. Lève une erreur `access_denied` si la personne a refusé.
   */
  async terminer(urlDeRetour, attente) {
    if (!attente) throw Object.assign(new Error('Aucune connexion en cours'), { code: 'state' });
    const t = await oidc.authorizationCodeGrant(this.conf, new URL(urlDeRetour), {
      pkceCodeVerifier: attente.verifier,
      expectedState: attente.state,
      expectedNonce: attente.nonce,
      idTokenExpected: true,
    });
    const claims = t.claims();
    let pseudo = null;
    if (this.o.portees.includes('profile')) {
      const info = await oidc.fetchUserInfo(this.conf, t.access_token, claims.sub);
      pseudo = info.preferred_username ?? null;
    }
    return { sub: claims.sub, pseudo, idToken: t.id_token, accessToken: t.access_token, refreshToken: t.refresh_token ?? null, expireLe: Date.now() + (t.expires_in ?? 0) * 1000 };
  }

  /** Adresse pour terminer aussi la session Droplet ID. */
  urlDeDeconnexion(idToken, retour) {
    return oidc.buildEndSessionUrl(this.conf, { id_token_hint: idToken, ...(retour ? { post_logout_redirect_uri: retour } : {}) }).href;
  }

  /**
   * Routes Express prêtes : GET `connexion` et GET `retour`. La connexion en
   * cours est gardée dans un cookie signé (HttpOnly, 10 minutes) ; la
   * session finale est confiée à `ouvrirSession(req, res, session)`.
   */
  routesExpress({ secret, connexion = '/connexion', retour = new URL(this.o.redirectUri).pathname, ouvrirSession, apres = '/', echec = '/?erreur=connexion' }) {
    if (!secret || secret.length < 32) throw new Error('`secret` : au moins 32 caractères');
    const signer = (v) => {
      const texte = Buffer.from(JSON.stringify(v)).toString('base64url');
      return `${texte}.${createHmac('sha256', secret).update(texte).digest('base64url')}`;
    };
    const lire = (brut) => {
      const [texte, sig] = String(brut ?? '').split('.');
      if (!texte || !sig) return null;
      const attendu = createHmac('sha256', secret).update(texte).digest();
      const recu = Buffer.from(sig, 'base64url');
      if (recu.length !== attendu.length || !timingSafeEqual(recu, attendu)) return null;
      return JSON.parse(Buffer.from(texte, 'base64url').toString());
    };
    const securise = this.o.redirectUri.startsWith('https:');
    const cookie = (valeur, age) => `droplet_id_attente=${valeur}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${age}${securise ? '; Secure' : ''}`;
    const lireCookie = (req) => (req.headers.cookie ?? '').split(/;\s*/).find((c) => c.startsWith('droplet_id_attente='))?.slice(19);

    return (req, res, suite) => {
      const chemin = req.path ?? new URL(req.url, 'http://x').pathname;
      if (req.method === 'GET' && chemin === connexion) {
        this.commencer({ langue: req.query?.langue })
          .then(({ url, attente }) => {
            res.setHeader('set-cookie', cookie(signer(attente), 600));
            res.redirect(url);
          })
          .catch(suite);
        return;
      }
      if (req.method === 'GET' && chemin === retour) {
        const attente = lire(lireCookie(req));
        res.setHeader('set-cookie', cookie('', 0));
        const urlComplete = new URL(req.originalUrl ?? req.url, this.o.redirectUri);
        this.terminer(urlComplete.href, attente)
          .then(async (session) => {
            await ouvrirSession(req, res, session);
            if (!res.headersSent) res.redirect(apres);
          })
          .catch((e) => {
            if (!res.headersSent) res.redirect(`${echec}&code=${encodeURIComponent(e.code ?? e.error ?? 'erreur')}`);
          });
        return;
      }
      suite();
    };
  }
}
