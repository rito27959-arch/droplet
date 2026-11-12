// ============================================================================
// LES LOGOS DES SITES
// ----------------------------------------------------------------------------
// Le logo déclaré par chaque site (logo_uri) est téléchargé par le SERVICE,
// jamais par le navigateur de la personne : le site ne voit pas qui ouvre la
// page de connexion. Il est converti en PNG 128×128 (un SVG ne peut donc rien
// exécuter) et servi depuis /logo/<client_id>, pour les pages et pour l'app.
// ============================================================================

import { createHash } from 'node:crypto';
import { Resvg } from '@resvg/resvg-js';

const TAILLE_MAX = 256 * 1024;
const DUREE_OK = 24 * 3600 * 1000;
const DUREE_ECHEC = 10 * 60 * 1000;
const TYPES = ['image/svg+xml', 'image/png', 'image/jpeg', 'image/webp'];

export function logos({ environnementDeTest = false, _fetch = fetch } = {}) {
  const cache = new Map(); // clientId → { png, type, empreinte, jusqua }
  const enCours = new Map();

  const autorise = (u) => u.protocol === 'https:' || (environnementDeTest && u.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(u.hostname));

  async function telecharger(adresse) {
    const u = new URL(adresse);
    if (!autorise(u)) return null;
    const r = await _fetch(u, { redirect: 'follow', signal: AbortSignal.timeout(3000), headers: { accept: TYPES.join(', ') } });
    if (!r.ok) return null;
    const type = (r.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
    if (!TYPES.includes(type)) return null;
    const octets = Buffer.from(await r.arrayBuffer());
    if (octets.length > TAILLE_MAX) return null;
    if (type === 'image/svg+xml') {
      const png = new Resvg(octets, { fitTo: { mode: 'width', value: 128 }, font: { loadSystemFonts: false } }).render().asPng();
      return { octets: png, type: 'image/png' };
    }
    return { octets, type };
  }

  /** Le logo d'un client (PNG ou image) ou null. Ne lève jamais. */
  async function logo(client) {
    if (!client?.logoUri) return null;
    const id = client.clientId;
    const c = cache.get(id);
    if (c && c.jusqua > Date.now() && c.adresse === client.logoUri) return c.octets ? c : null;
    if (!enCours.has(id)) {
      enCours.set(
        id,
        telecharger(client.logoUri)
          .catch(() => null)
          .then((x) => {
            const e = x
              ? { ...x, adresse: client.logoUri, empreinte: createHash('sha256').update(x.octets).digest('base64url').slice(0, 10), jusqua: Date.now() + DUREE_OK }
              : { adresse: client.logoUri, jusqua: Date.now() + DUREE_ECHEC };
            cache.set(id, e);
            enCours.delete(id);
            return e;
          }),
      );
    }
    const e = await enCours.get(id);
    return e.octets ? e : null;
  }

  /** L'adresse versionnée du logo (relative), ou null : la page montre alors l'initiale. */
  async function adresse(client) {
    const l = await logo(client);
    return l ? `/logo/${encodeURIComponent(client.clientId)}?v=${l.empreinte}` : null;
  }

  return { logo, adresse };
}
