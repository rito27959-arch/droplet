// ============================================================================
// @droplet/id — se connecter avec Droplet ID depuis un site web.
//
//   import { DropletId } from '@droplet/id';
//   const did = new DropletId({ clientId: 'mon-site', redirectUri: location.origin + '/' });
//   bouton.onclick = () => did.connecter();               // part vers Droplet ID
//   const session = await did.terminerConnexion();        // au retour : { sub, pseudo, … }
//
// Standard OpenID Connect : flux « authorization code » + PKCE (S256), state
// et nonce, ID token vérifié (signature ES256 via JWKS, émetteur, audience,
// expiration, nonce). Aucune dépendance.
// ============================================================================

export const EMETTEUR = 'https://id.dropletmesh.app';
export const EMETTEUR_TEST = 'https://id-test.dropletmesh.app';

const CLE = 'droplet-id';
const enc = new TextEncoder();

const b64url = (octets) => btoa(String.fromCharCode(...new Uint8Array(octets))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const deB64url = (s) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(s.length / 4) * 4, '=')), (c) => c.charCodeAt(0));
const aleatoire = (n = 32) => b64url(crypto.getRandomValues(new Uint8Array(n)));

const stockage = {
  lire(k) { try { return JSON.parse(sessionStorage.getItem(`${CLE}:${k}`)); } catch { return null; } },
  ecrire(k, v) { try { v == null ? sessionStorage.removeItem(`${CLE}:${k}`) : sessionStorage.setItem(`${CLE}:${k}`, JSON.stringify(v)); } catch { /* navigation privée : on garde en mémoire */ } },
};

export class ErreurDropletId extends Error {
  constructor(code, description) {
    super(description ? `${code}: ${description}` : code);
    this.name = 'ErreurDropletId';
    this.code = code;
  }
}

export class DropletId {
  /**
   * @param {object} o
   * @param {string} o.clientId        identifiant du site, donné à l'enregistrement
   * @param {string} o.redirectUri     adresse de retour, EXACTEMENT celle enregistrée
   * @param {string} [o.emetteur]      https://id.dropletmesh.app (ou EMETTEUR_TEST)
   * @param {string[]} [o.portees]     ['openid'] ; ajouter 'profile' pour le pseudo
   * @param {'fr'|'en'} [o.langue]
   */
  constructor({ clientId, redirectUri, emetteur = EMETTEUR, portees = ['openid'], langue } = {}) {
    if (!clientId || !redirectUri) throw new ErreurDropletId('configuration', 'clientId et redirectUri sont obligatoires');
    this.clientId = clientId;
    this.redirectUri = redirectUri;
    this.emetteur = emetteur.replace(/\/$/, '');
    this.portees = portees.includes('openid') ? portees : ['openid', ...portees];
    this.langue = langue;
    this._session = stockage.lire('session');
    this._config = null;
  }

  async configuration() {
    if (this._config) return this._config;
    const r = await fetch(`${this.emetteur}/.well-known/openid-configuration`);
    if (!r.ok) throw new ErreurDropletId('decouverte', `HTTP ${r.status}`);
    const c = await r.json();
    if (c.issuer !== this.emetteur) throw new ErreurDropletId('decouverte', 'émetteur inattendu');
    return (this._config = c);
  }

  /** Part vers Droplet ID. */
  async connecter() {
    location.assign(await this.urlDeConnexion());
  }

  /** L'adresse de connexion (si vous préférez gérer la redirection vous-même). */
  async urlDeConnexion() {
    const c = await this.configuration();
    const verifier = aleatoire(32);
    const challenge = b64url(await crypto.subtle.digest('SHA-256', enc.encode(verifier)));
    const state = aleatoire(16);
    const nonce = aleatoire(16);
    stockage.ecrire('attente', { verifier, state, nonce, redirectUri: this.redirectUri });
    const u = new URL(c.authorization_endpoint);
    u.search = new URLSearchParams({
      client_id: this.clientId,
      response_type: 'code',
      redirect_uri: this.redirectUri,
      scope: this.portees.join(' '),
      code_challenge: challenge,
      code_challenge_method: 'S256',
      state,
      nonce,
      ...(this.langue ? { ui_locales: this.langue } : {}),
    }).toString();
    return u.href;
  }

  /** Vrai si l'adresse actuelle est un retour de Droplet ID. */
  estUnRetour(url = location.href) {
    const p = new URL(url).searchParams;
    return p.has('state') && (p.has('code') || p.has('error'));
  }

  /**
   * Au retour sur `redirectUri` : échange le code, vérifie l'ID token, et
   * rend la session. Nettoie l'adresse (retire code et state).
   * @returns {Promise<{sub:string, pseudo:string|null, idToken:string, accessToken:string, expireLe:number}>}
   */
  async terminerConnexion(url = location.href) {
    const u = new URL(url);
    const p = u.searchParams;
    const attente = stockage.lire('attente');
    stockage.ecrire('attente', null);
    if (p.get('error')) throw new ErreurDropletId(p.get('error'), p.get('error_description') ?? '');
    if (!attente || p.get('state') !== attente.state) throw new ErreurDropletId('state', 'réponse inattendue (state)');
    if (p.get('iss') && p.get('iss') !== this.emetteur) throw new ErreurDropletId('iss', 'émetteur inattendu');

    const c = await this.configuration();
    const r = await fetch(c.token_endpoint, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code: p.get('code'),
        redirect_uri: attente.redirectUri,
        client_id: this.clientId,
        code_verifier: attente.verifier,
      }),
    });
    const t = await r.json();
    if (!r.ok) throw new ErreurDropletId(t.error ?? 'jeton', t.error_description);
    const claims = await this.verifierIdToken(t.id_token, attente.nonce);

    let pseudo = null;
    if (this.portees.includes('profile')) {
      const i = await fetch(c.userinfo_endpoint, { headers: { authorization: `Bearer ${t.access_token}` } });
      if (i.ok) pseudo = (await i.json()).preferred_username ?? null;
    }
    this._session = { sub: claims.sub, pseudo, idToken: t.id_token, accessToken: t.access_token, expireLe: Date.now() + t.expires_in * 1000 };
    stockage.ecrire('session', this._session);
    if (typeof history !== 'undefined' && url === location.href) {
      ['code', 'state', 'iss'].forEach((k) => u.searchParams.delete(k));
      history.replaceState(history.state, '', u.pathname + (u.search || '') + u.hash);
    }
    return this._session;
  }

  /** Vérifie un ID token : signature (JWKS), émetteur, audience, dates, nonce. */
  async verifierIdToken(jwt, nonce) {
    const [h, c, s] = String(jwt).split('.');
    if (!s) throw new ErreurDropletId('id_token', 'format');
    const entete = JSON.parse(new TextDecoder().decode(deB64url(h)));
    const claims = JSON.parse(new TextDecoder().decode(deB64url(c)));
    if (entete.alg !== 'ES256') throw new ErreurDropletId('id_token', `algorithme ${entete.alg}`);
    const { jwks_uri } = await this.configuration();
    const { keys } = await (await fetch(jwks_uri)).json();
    const jwk = keys.find((k) => k.kid === entete.kid) ?? keys[0];
    const cle = await crypto.subtle.importKey('jwk', { kty: jwk.kty, crv: jwk.crv, x: jwk.x, y: jwk.y }, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
    const ok = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, cle, deB64url(s), enc.encode(`${h}.${c}`));
    if (!ok) throw new ErreurDropletId('id_token', 'signature');
    const maintenant = Math.floor(Date.now() / 1000);
    if (claims.iss !== this.emetteur) throw new ErreurDropletId('id_token', 'émetteur');
    if (claims.aud !== this.clientId && !(Array.isArray(claims.aud) && claims.aud.includes(this.clientId))) throw new ErreurDropletId('id_token', 'audience');
    if (claims.exp < maintenant - 60) throw new ErreurDropletId('id_token', 'expiré');
    if (nonce && claims.nonce !== nonce) throw new ErreurDropletId('id_token', 'nonce');
    return claims;
  }

  /** La session en cours, ou null. */
  utilisateur() {
    const s = this._session;
    return s && s.expireLe > Date.now() ? { sub: s.sub, pseudo: s.pseudo } : null;
  }

  /** Oublie la session ici ; avec `partout`, termine aussi la session Droplet ID. */
  async deconnecter({ partout = false, retour } = {}) {
    const s = this._session;
    this._session = null;
    stockage.ecrire('session', null);
    if (partout && s) {
      const c = await this.configuration();
      const u = new URL(c.end_session_endpoint);
      u.search = new URLSearchParams({ id_token_hint: s.idToken, client_id: this.clientId, ...(retour ? { post_logout_redirect_uri: retour } : {}) }).toString();
      location.assign(u.href);
    }
  }
}

// ── Le bouton officiel ────────────────────────────────────────────────
export const GOUTTE_SVG = '<svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M12 2.2c-3.6 4.9-6 8.4-6 11.6a6 6 0 0 0 12 0c0-3.2-2.4-6.7-6-11.6Z"/></svg>';
const TEXTES = { fr: 'Continuer avec Droplet ID', en: 'Continue with Droplet ID' };
export const STYLE_BOUTON = `
.droplet-id-bouton{all:unset;box-sizing:border-box;display:inline-flex;align-items:center;justify-content:center;gap:.6em;
  height:var(--did-h,48px);padding:0 1.25em;border-radius:999px;cursor:pointer;
  font:600 15px/1 system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;letter-spacing:-.005em;
  background:#0a1a24;color:#fff;transition:transform .15s,filter .15s;-webkit-tap-highlight-color:transparent}
.droplet-id-bouton svg{width:1.25em;height:1.25em;color:#3d9bff}
.droplet-id-bouton:hover{filter:brightness(1.15)}
.droplet-id-bouton:active{transform:scale(.98)}
.droplet-id-bouton:focus-visible{outline:2px solid #0a7cff;outline-offset:3px}
.droplet-id-bouton[data-variante=clair]{background:#fff;color:#0a1a24;box-shadow:inset 0 0 0 1px #d6dee4}
.droplet-id-bouton[data-variante=clair] svg{color:#0a7cff}
.droplet-id-bouton[data-variante=bleu]{background:#0a7cff;color:#fff}
.droplet-id-bouton[data-variante=bleu] svg{color:#fff}
.droplet-id-bouton[data-taille=petit]{--did-h:40px;font-size:14px}
.droplet-id-bouton[data-taille=grand]{--did-h:56px;font-size:16px}
.droplet-id-bouton[data-pleine-largeur]{display:flex;width:100%}
.droplet-id-bouton[aria-busy=true]{opacity:.7;pointer-events:none}`;

function injecterStyle() {
  if (typeof document === 'undefined' || document.getElementById('droplet-id-style')) return;
  const s = document.createElement('style');
  s.id = 'droplet-id-style';
  s.textContent = STYLE_BOUTON;
  document.head.append(s);
}

/**
 * Crée le bouton officiel « Continuer avec Droplet ID ».
 * @param {{ langue?: 'fr'|'en', variante?: 'sombre'|'clair'|'bleu', taille?: 'petit'|'moyen'|'grand', pleineLargeur?: boolean, onClick?: Function }} [o]
 */
export function boutonDropletId({ langue = 'fr', variante = 'sombre', taille = 'moyen', pleineLargeur = false, onClick } = {}) {
  injecterStyle();
  const b = document.createElement('button');
  b.type = 'button';
  b.className = 'droplet-id-bouton';
  b.dataset.variante = variante;
  b.dataset.taille = taille;
  if (pleineLargeur) b.dataset.pleineLargeur = '';
  b.innerHTML = `${GOUTTE_SVG}<span>${TEXTES[langue] ?? TEXTES.fr}</span>`;
  if (onClick) b.addEventListener('click', async (e) => { b.setAttribute('aria-busy', 'true'); try { await onClick(e); } finally { b.removeAttribute('aria-busy'); } });
  return b;
}
