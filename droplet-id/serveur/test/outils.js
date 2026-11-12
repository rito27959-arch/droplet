// Outils de test : un « appareil » (clé Ed25519, requêtes signées) et un
// « navigateur » (fetch + cookies, sans suivre les redirections).
import { createHash, generateKeyPairSync, randomBytes, sign } from 'node:crypto';

export function nouvelAppareil(base) {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  const clePub = publicKey.export({ format: 'jwk' }).x;
  const a = {
    clePub,
    appareilId: null,
    compteId: null,
    /** Rend { statut, corps, entetes } ; `rejouer` renvoie exactement la même requête. */
    async appeler(methode, chemin, corps, { creation = false, entetesFixes } = {}) {
      const texte = corps ? JSON.stringify(corps) : '';
      const ts = Math.floor(Date.now() / 1000);
      const nonce = randomBytes(16).toString('base64url');
      const empreinte = createHash('sha256').update(texte).digest('hex');
      const sig = sign(null, Buffer.from(`${methode}\n${chemin}\n${ts}\n${nonce}\n${empreinte}`), privateKey).toString('base64url');
      const entetes = entetesFixes ?? {
        'content-type': 'application/json',
        'x-droplet-ts': String(ts),
        'x-droplet-nonce': nonce,
        'x-droplet-sig': sig,
        ...(creation ? { 'x-droplet-cle': clePub } : { 'x-droplet-appareil': a.appareilId }),
      };
      const r = await fetch(base + chemin, { method: methode, headers: entetes, body: texte || undefined });
      return { statut: r.status, corps: await r.json().catch(() => null), entetes };
    },
    async creerCompte() {
      const r = await a.appeler('POST', '/v1/comptes', { nom: 'Téléphone de test' }, { creation: true });
      a.appareilId = r.corps.appareil_id;
      a.compteId = r.corps.compte_id;
      return r;
    },
  };
  return a;
}

export function nouveauNavigateur() {
  const cookies = new Map();
  const brut = [];
  return {
    brut,
    async aller(url, options = {}) {
      const r = await fetch(url, {
        ...options,
        redirect: 'manual',
        headers: { ...(options.headers ?? {}), cookie: [...cookies].map(([k, v]) => `${k}=${v}`).join('; ') },
      });
      for (const c of r.headers.getSetCookie()) {
        brut.push(c);
        const [paire] = c.split(';');
        const i = paire.indexOf('=');
        cookies.set(paire.slice(0, i), paire.slice(i + 1));
      }
      return r;
    },
  };
}
