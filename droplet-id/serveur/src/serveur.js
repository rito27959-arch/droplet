// ============================================================================
// DROPLET ID — le service. Un seul processus :
//   • OpenID Connect (oidc-provider)            /oauth2/*, /.well-known/*, /userinfo
//   • l'interaction (page QR)                    /interaction/*
//   • l'API des appareils (signée)               /v1/*
//   • le lien d'application                      /a/:demande
//   • en test seulement : l'appareil de test     /test/appareil
// ============================================================================

import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { creerFournisseur } from './oidc.js';
import { routesInteraction } from './interaction.js';
import { routesApi } from './api.js';
import { langueDe, pageAccueil, pageAppareilTest, pageErreur, pageLienApp } from './pages.js';
import { stockageMemoire } from './stockage/memoire.js';
import { stockagePostgres } from './stockage/postgres.js';
import { limiteur } from './limites.js';

const STATIQUES = {
  'droplet-id.css': 'text/css; charset=utf-8',
  'connexion.js': 'text/javascript; charset=utf-8',
  'appareil.js': 'text/javascript; charset=utf-8',
  'lien.js': 'text/javascript; charset=utf-8',
  'InstrumentSans.woff2': 'font/woff2',
  'favicon.svg': 'image/svg+xml',
};

const SECURITE = {
  'strict-transport-security': 'max-age=63072000; includeSubDomains',
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  'permissions-policy': 'camera=(), microphone=(), geolocation=(), payment=()',
  'cross-origin-opener-policy': 'same-origin',
};
const CSP_PAGES =
  "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'; connect-src 'self'; form-action 'self' https: http://localhost:*; frame-ancestors 'none'; base-uri 'none'";

function repondre(res, statut, corps, type = 'json') {
  if (res.headersSent) return;
  const html = type === 'html';
  res.writeHead(statut, {
    ...SECURITE,
    'content-type': html ? 'text/html; charset=utf-8' : 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    ...(html ? { 'content-security-policy': CSP_PAGES, 'x-frame-options': 'DENY' } : {}),
  });
  res.end(html ? corps : JSON.stringify(corps));
}

export async function demarrer(config) {
  const stockage = config.baseDeDonnees ? await stockagePostgres(config.baseDeDonnees) : stockageMemoire();
  const fournisseur = creerFournisseur({ config, stockage });
  const interaction = routesInteraction({ fournisseur, stockage, config, repondre });
  const api = routesApi({ fournisseur, stockage, config, repondre });
  const oidc = fournisseur.callback();
  const limiteApi = limiteur({ parMinute: 120 });
  const limitePages = limiteur({ parMinute: 60 });

  const ip = (req) => (config.derriereProxy ? String(req.headers['x-forwarded-for'] || '').split(',')[0].trim() : '') || req.socket.remoteAddress;

  const serveur = http.createServer(async (req, res) => {
    const url = new URL(req.url, config.emetteur);
    const chemin = url.pathname;
    try {
      // Fichiers statiques.
      if (chemin.startsWith('/static/')) {
        const nom = chemin.slice(8);
        const type = STATIQUES[nom];
        if (!type) return repondre(res, 404, { erreur: 'introuvable' });
        const contenu = await readFile(new URL(`../public/${nom}`, import.meta.url));
        res.writeHead(200, { ...SECURITE, 'content-type': type, 'cache-control': 'public, max-age=3600' });
        return res.end(contenu);
      }
      if (chemin === '/sante') return repondre(res, 200, { ok: true, stockage: stockage.nom });

      if (chemin.startsWith('/v1/')) {
        if (!limiteApi(ip(req))) return repondre(res, 429, { erreur: 'trop_de_requetes' });
        res.setHeader('access-control-allow-origin', '*'); // signé : pas de cookie, pas de risque CSRF
        if (req.method === 'OPTIONS') {
          res.writeHead(204, { 'access-control-allow-methods': 'GET,POST,DELETE', 'access-control-allow-headers': 'content-type,x-droplet-appareil,x-droplet-cle,x-droplet-ts,x-droplet-nonce,x-droplet-sig', 'access-control-max-age': '600' });
          return res.end();
        }
        if (await api(req, res, chemin)) return;
      }

      if (chemin.startsWith('/interaction/')) {
        if (req.method === 'GET' && !chemin.endsWith('/etat') && !limitePages(ip(req))) return repondre(res, 429, { erreur: 'trop_de_requetes' });
        if (await interaction(req, res, chemin, url)) return;
      }

      const langue = langueDe(req.headers, url.searchParams.get('langue') || undefined);
      if (/^\/a\/[A-Za-z0-9_-]{16,64}$/.test(chemin)) return repondre(res, 200, pageLienApp({ langue, test: config.environnementDeTest }), 'html');
      if (chemin === '/test/appareil') {
        if (!config.environnementDeTest) return repondre(res, 404, pageErreur({ langue, detail: 'introuvable' }), 'html');
        return repondre(res, 200, pageAppareilTest({ langue }), 'html');
      }
      if (chemin === '/' && req.method === 'GET') return repondre(res, 200, pageAccueil({ langue, test: config.environnementDeTest }), 'html');
      // Lien d'application Android : Droplet ouvrira /a/… directement.
      if (chemin === '/.well-known/assetlinks.json') {
        return repondre(res, 200, [
          {
            relation: ['delegate_permission/common.handle_all_urls'],
            target: { namespace: 'android_app', package_name: 'com.droplet.droplet', sha256_cert_fingerprints: (process.env.EMPREINTES_APP || '').split(',').filter(Boolean) },
          },
        ]);
      }

      for (const [k, v] of Object.entries(SECURITE)) res.setHeader(k, v);
      return oidc(req, res);
    } catch (e) {
      console.error('[droplet-id]', chemin, e);
      return repondre(res, 500, { erreur: 'erreur_interne' });
    }
  });

  await new Promise((ok) => serveur.listen(config.port, ok));
  return {
    serveur,
    stockage,
    fournisseur,
    async arreter() {
      await new Promise((ok) => serveur.close(ok));
      await stockage.fermer();
    },
  };
}
