// ============================================================================
// Le fournisseur OpenID Connect, confié à `oidc-provider` (bibliothèque
// certifiée par l'OpenID Foundation). Nous ne réglons que la politique :
//
//   • un identifiant différent par site (« pairwise ») ;
//   • PKCE obligatoire, flux « authorization code » uniquement ;
//   • aucune portée e-mail ni téléphone : elles n'existent pas ;
//   • jetons courts, refresh tokens à usage unique ;
//   • la connexion et l'accord se font sur le téléphone (voir interaction.js).
// ============================================================================

import Provider from 'oidc-provider';
import { createHmac } from 'node:crypto';
import { pageErreur } from './pages.js';

export function creerFournisseur({ config, stockage }) {
  const fournisseur = new Provider(config.emetteur, {
    adapter: (modele) => stockage.adaptateur(modele),
    clients: config.clients,
    clientDefaults: {
      grant_types: ['authorization_code', 'refresh_token'],
      response_types: ['code'],
      token_endpoint_auth_method: 'none',
      subject_type: 'pairwise',
      id_token_signed_response_alg: 'ES256',
    },
    jwks: config.jwks,
    cookies: { keys: config.clesCookies },

    // Un `sub` par site : HMAC(sel secret, compte ‖ secteur du site). Stable
    // pour un même site, impossible à recouper d'un site à l'autre.
    subjectTypes: ['pairwise'],
    async pairwiseIdentifier(ctx, compteId, client) {
      return createHmac('sha256', config.selPairwise).update(`${compteId}|${client.sectorIdentifier}`).digest('base64url');
    },

    pkce: { required: () => true },
    scopes: ['openid', 'offline_access'],
    claims: { openid: ['sub'], profile: ['preferred_username', 'picture'], amr: null, auth_time: null },

    async findAccount(ctx, compteId) {
      const compte = await stockage.compte(compteId);
      if (!compte) return undefined;
      return {
        accountId: compteId,
        async claims(usage, portee) {
          const r = { sub: compteId };
          // Le pseudo est choisi par la personne POUR CE SITE, et seulement
          // si elle a accepté la portée `profile`.
          if (portee?.split(' ').includes('profile')) {
            const accord = await stockage.accord(compteId, ctx.oidc.client.clientId);
            if (accord?.portees?.includes('profile') && accord.pseudo) r.preferred_username = accord.pseudo;
          }
          return r;
        },
      };
    },

    interactions: { url: (ctx, interaction) => `/interaction/${interaction.uid}` },

    features: {
      devInteractions: { enabled: false },
      revocation: { enabled: true },
      userinfo: { enabled: true },
      rpInitiatedLogout: {
        enabled: true,
        async logoutSource(ctx, form) {
          // Déconnexion sans écran intermédiaire : le formulaire part seul.
          ctx.body = `<!doctype html><meta charset="utf-8"><title>Droplet ID</title><body>${form}<script>document.forms[0].submit()</script></body>`;
        },
      },
    },

    routes: {
      authorization: '/oauth2/auth',
      token: '/oauth2/token',
      userinfo: '/userinfo',
      jwks: '/.well-known/jwks.json',
      revocation: '/oauth2/revoke',
      end_session: '/oauth2/sessions/logout',
    },

    ttl: {
      AuthorizationCode: 60,
      IdToken: 300,
      AccessToken: 600,
      RefreshToken: 30 * 24 * 3600,
      Interaction: 600,
      Session: 14 * 24 * 3600,
      Grant: 365 * 24 * 3600,
    },
    rotateRefreshToken: true,

    // Les sites web (applications d'une seule page) appellent /oauth2/token
    // depuis le navigateur : autorisé seulement depuis l'origine d'une de
    // LEURS adresses de retour.
    clientBasedCORS(ctx, origine, client) {
      return client.redirectUris.some((u) => new URL(u).origin === origine);
    },

    async renderError(ctx, out) {
      ctx.type = 'html';
      ctx.body = pageErreur({ langue: ctx.acceptsLanguages('fr', 'en') || 'fr', detail: out.error });
    },
  });

  fournisseur.proxy = config.derriereProxy;
  return fournisseur;
}
