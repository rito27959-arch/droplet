// ============================================================================
// Librairie Baobab — un site de démonstration rendu côté serveur (Express),
// connecté avec le kit Node de Droplet ID. La librairie n'existe pas.
//
// Ce que le site garde : une liste d'envies par identifiant Droplet ID. Rien
// d'autre — il n'a jamais su le nom, le numéro ou l'e-mail de personne.
// ============================================================================

import express from 'express';
import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { DropletIdServeur, EMETTEUR_TEST } from '../../kits/node/src/index.js';

const PORT = Number(process.env.PORT ?? 3000);
const ADRESSE = (process.env.ADRESSE ?? `http://localhost:${PORT}`).replace(/\/$/, '');
const EMETTEUR = process.env.EMETTEUR ?? EMETTEUR_TEST;
const SECRET = process.env.SECRET ?? randomBytes(32).toString('hex');

const did = await DropletIdServeur.creer({
  clientId: 'demo-baobab',
  redirectUri: `${ADRESSE}/connexion/retour`,
  emetteur: EMETTEUR,
  portees: ['openid', 'profile'],
  _http: EMETTEUR.startsWith('http:'),
});

// ── Session : un cookie signé qui ne contient que { sub, pseudo } ────────
const signer = (v) => {
  const t = Buffer.from(JSON.stringify(v)).toString('base64url');
  return `${t}.${createHmac('sha256', SECRET).update(t).digest('base64url')}`;
};
const lireSession = (req) => {
  const brut = (req.headers.cookie ?? '').split(/;\s*/).find((c) => c.startsWith('baobab='))?.slice(7);
  const [t, s] = String(brut ?? '').split('.');
  if (!t || !s) return null;
  const a = createHmac('sha256', SECRET).update(t).digest();
  const b = Buffer.from(s, 'base64url');
  return a.length === b.length && timingSafeEqual(a, b) ? JSON.parse(Buffer.from(t, 'base64url').toString()) : null;
};
const secure = ADRESSE.startsWith('https:') ? '; Secure' : '';

// ── Le catalogue (livres imaginaires) ─────────────────────────────────
const LIVRES = [
  { id: 'sous-le-baobab', titre: 'Sous le baobab, la pluie', auteur: 'Mireille Ngo Bassa', prix: 6500, couleur: '#d9822b', motif: 'pluie' },
  { id: 'route-de-kribi', titre: 'La route de Kribi', auteur: 'Joël Atangana', prix: 5000, couleur: '#2f6f8f', motif: 'vagues' },
  { id: 'code-du-marche', titre: 'Le code du marché Mokolo', auteur: 'Sandrine Fotso', prix: 7200, couleur: '#7a3b69', motif: 'grille' },
  { id: 'nuits-de-mvog', titre: 'Les nuits de Mvog-Mbi', auteur: 'Aboubakar Hamadou', prix: 5800, couleur: '#3e7a4b', motif: 'etoiles' },
  { id: 'mesh', titre: 'Petit traité des réseaux sans antenne', auteur: 'Collectif Droplet', prix: 3500, couleur: '#1f2a52', motif: 'points' },
  { id: 'lettres-a-ma-soeur', titre: 'Lettres à ma sœur restée à Bafoussam', auteur: 'Christelle Kamga', prix: 6000, couleur: '#b5473a', motif: 'lignes' },
];
const envies = new Map(); // sub → Set(id) — en mémoire : c'est une démo

const echapper = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const fcfa = (n) => `${n.toLocaleString('fr-FR').replace(/ /g, ' ')} FCFA`;

function couverture(l) {
  const motifs = {
    pluie: '<path d="M20 10v16M44 4v22M68 14v18M32 34v16M56 30v20" stroke="currentColor" stroke-width="3" stroke-linecap="round"/>',
    vagues: '<path d="M0 30c12-10 24 10 36 0s24 10 36 0M0 46c12-10 24 10 36 0s24 10 36 0" stroke="currentColor" stroke-width="3" fill="none"/>',
    grille: '<path d="M0 18h80M0 38h80M20 0v60M50 0v60" stroke="currentColor" stroke-width="3"/>',
    etoiles: '<circle cx="16" cy="14" r="3" fill="currentColor"/><circle cx="52" cy="22" r="2" fill="currentColor"/><circle cx="34" cy="42" r="3.5" fill="currentColor"/><circle cx="66" cy="48" r="2.5" fill="currentColor"/>',
    points: '<g fill="currentColor"><circle cx="14" cy="14" r="4"/><circle cx="40" cy="26" r="4"/><circle cx="66" cy="12" r="4"/><circle cx="28" cy="48" r="4"/><circle cx="58" cy="46" r="4"/></g><path d="M14 14 40 26 66 12M40 26 28 48 58 46 40 26" stroke="currentColor" stroke-width="2" fill="none"/>',
    lignes: '<path d="M8 14h64M8 24h50M8 34h58M8 44h40" stroke="currentColor" stroke-width="3" stroke-linecap="round"/>',
  };
  return `<div class="couv" style="--c:${l.couleur}"><svg viewBox="0 0 80 60" aria-hidden="true">${motifs[l.motif]}</svg><span class="couv-titre">${echapper(l.titre)}</span><span class="couv-auteur">${echapper(l.auteur)}</span></div>`;
}

function page({ session, mesEnvies, erreur }) {
  const liste = LIVRES.map((l) => {
    const aime = mesEnvies?.has(l.id);
    return `<li class="livre">
      ${couverture(l)}
      <div class="infos"><h3>${echapper(l.titre)}</h3><p class="auteur">${echapper(l.auteur)}</p><p class="prix">${fcfa(l.prix)}</p></div>
      ${session ? `<form method="post" action="/envies/${l.id}"><button class="envie" aria-pressed="${aime ? 'true' : 'false'}">${aime ? 'Dans mes envies' : 'Ajouter à mes envies'}</button></form>` : ''}
    </li>`;
  }).join('');
  const nb = mesEnvies?.size ?? 0;
  return `<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex">
<title>Librairie Baobab — démo Droplet ID</title>
<link rel="preload" href="/static/InstrumentSans.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/static/baobab.css"><link rel="icon" href="/static/favicon.svg" type="image/svg+xml"></head>
<body>
<div class="demo">Site de démonstration — la Librairie Baobab n’existe pas. Elle montre Droplet ID côté serveur (Node.js).</div>
<header class="entete">
  <a class="logo" href="/"><svg viewBox="0 0 32 32" aria-hidden="true"><path d="M13 30V17c-5 0-9-2.5-9-6 0-3 3-5 6-5 1-3 4-4 6-4s5 1 6 4c3 0 6 2 6 5 0 3.5-4 6-9 6v13z"/></svg>Librairie Baobab</a>
  <nav>${session
    ? `<span class="qui">${session.pseudo ? `Bonjour, <strong>${echapper(session.pseudo)}</strong>` : 'Connecté'}</span><a class="sortir" href="/deconnexion">Se déconnecter</a>`
    : `<a class="droplet-id-bouton" data-variante="clair" data-taille="petit" href="/connexion"><svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M12 2.2c-3.6 4.9-6 8.4-6 11.6a6 6 0 0 0 12 0c0-3.2-2.4-6.7-6-11.6Z"/></svg><span>Continuer avec Droplet ID</span></a>`}</nav>
</header>
<main>
  <section class="ouverture">
    <h1>Des livres d’ici,<br>une liste d’envies<br>qui ne sait pas qui vous êtes.</h1>
    <p class="chapo">${session
      ? nb ? `Vous avez <strong>${nb}</strong> livre${nb > 1 ? 's' : ''} dans vos envies. Ils vous attendent ici, sur n’importe quel appareil où vous vous connectez avec Droplet ID.` : 'Ajoutez des livres à vos envies : ils vous attendront ici, sur n’importe quel appareil où vous vous connectez avec Droplet ID.'
      : 'Connectez-vous pour garder une liste d’envies. La librairie ne recevra qu’un identifiant fait pour elle : ni numéro, ni e-mail, ni nom.'}</p>
    ${erreur ? `<p class="erreur">${erreur === 'access_denied' ? 'Connexion annulée.' : `La connexion n’a pas abouti (${echapper(erreur)}).`}</p>` : ''}
  </section>
  ${session ? `<aside class="registre"><h2>Le registre de la librairie</h2><p>Voici, en entier, la ligne que la Librairie Baobab garde à votre sujet :</p>
    <table><thead><tr><th scope="col">Identifiant Droplet ID</th><th scope="col">Pseudo</th><th scope="col">Envies</th></tr></thead>
    <tbody><tr><td><code>${echapper(session.sub)}</code></td><td>${echapper(session.pseudo ?? '—')}</td><td>${nb}</td></tr></tbody></table></aside>` : ''}
  <section aria-labelledby="rayon"><h2 id="rayon" class="rayon">Nouveautés</h2><ul class="livres">${liste}</ul></section>
</main>
<footer class="pied"><p>Démonstration de <a href="https://developpeurs-id.dropletmesh.app">Droplet ID</a> en environnement de test. Rendu côté serveur avec <code>@droplet/id-node</code>.</p></footer>
</body></html>`;
}

const app = express();
app.disable('x-powered-by');
app.set('trust proxy', 1);
app.use((req, res, suite) => {
  res.set({
    'content-security-policy': "default-src 'self'; style-src 'self'; style-src-attr 'unsafe-inline'; img-src 'self' data:; font-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
    'referrer-policy': 'strict-origin-when-cross-origin',
    'x-content-type-options': 'nosniff',
  });
  suite();
});
app.use('/static', express.static(new URL('./public', import.meta.url).pathname, { maxAge: '1h' }));

// Droplet ID : /connexion et /connexion/retour, en une ligne.
app.use(did.routesExpress({
  secret: SECRET,
  ouvrirSession: (req, res, s) => res.append('set-cookie', `baobab=${signer({ sub: s.sub, pseudo: s.pseudo })}; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000${secure}`),
  apres: '/',
  echec: '/?x=1',
}));

app.get('/deconnexion', (req, res) => {
  res.set('set-cookie', `baobab=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0${secure}`).redirect('/');
});

app.post('/envies/:id', (req, res) => {
  const s = lireSession(req);
  if (!s || !LIVRES.some((l) => l.id === req.params.id)) return res.redirect('/');
  const e = envies.get(s.sub) ?? new Set();
  e.has(req.params.id) ? e.delete(req.params.id) : e.add(req.params.id);
  envies.set(s.sub, e);
  res.redirect(303, '/#rayon');
});

app.get('/', (req, res) => {
  const s = lireSession(req);
  res.type('html').send(page({ session: s, mesEnvies: s ? envies.get(s.sub) : null, erreur: req.query.code }));
});

app.get('/sante', (req, res) => res.json({ ok: true }));
app.listen(PORT, () => console.log(`[baobab] ${ADRESSE} → Droplet ID ${EMETTEUR}`));
