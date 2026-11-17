// ============================================================================
// Les pages de la console développeurs (HTML rendu côté serveur, sans
// framework). Une barre en haut, la liste des apps, et pour chaque app une
// colonne de sections : Aperçu, Identifiants, Écran de connexion, Adresses,
// Mise en production, Journal, Supprimer.
// ============================================================================

import { GOUTTE } from '../pages.js';
import { statique } from '../statiques.js';
import { TYPES, hotesDe } from './apps.js';

const e = (s) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

const I = {
  apps: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></svg>',
  plus: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
  apercu: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 19V9M10 19V5M16 19v-7M22 19H2" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
  cle: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="8" cy="15" r="4" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="m11 12 8-8m-3 3 3 3m-6 0 2 2" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
  ecran: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="3" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M8 10h8M8 14h5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
  lien: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
  fusee: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 19l3-1 8-8a6 6 0 0 0 2-6 6 6 0 0 0-6 2l-8 8-1 3zM9 15l-2-2M14 6l4 4" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round"/></svg>',
  journal: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8.5" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M12 7.5V12l3 2" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
  corbeille: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h16M10 7V4h4v3M6 7l1 13h10l1-13" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round"/></svg>',
  copier: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="8" y="8" width="12" height="12" rx="2.5" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2" fill="none" stroke="currentColor" stroke-width="1.8"/></svg>',
  ok: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12.5 4.5 4.5L19 7.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  non: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8.5" fill="none" stroke="currentColor" stroke-width="1.8"/></svg>',
  doc: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 3h7l5 5v13H7zM14 3v5h5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></svg>',
  attention: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 4 2.5 20h19L12 4zM12 10v4M12 17h.01" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
};

const DOCS = 'https://developpeurs-id.dropletmesh.app';

const NOMS_TYPES = {
  serveur: ['Site avec serveur', 'PHP, Node, Python, Go… Le serveur garde un secret.'],
  navigateur: ['App web dans le navigateur', 'React, Vue, JavaScript seul. Pas de secret : PKCE.'],
  mobile: ['App mobile', 'Flutter, Kotlin, Swift. Pas de secret : PKCE.'],
};

const STATUTS = {
  test: ['Test', 'test'],
  verification: ['Vérification en cours', 'verification'],
  production: ['En production', 'production'],
};

const MESSAGES = {
  obligatoire: 'Ce champ est obligatoire.',
  longueur_nom: 'Entre 2 et 40 caractères.',
  type_inconnu: 'Choisissez un type.',
  adresse_invalide: 'Adresse invalide.',
  https_obligatoire: 'Adresse en https:// (http:// seulement pour localhost).',
  sans_fragment: 'Pas de # dans une adresse de retour.',
  trop_d_adresses: '10 adresses au plus.',
  trop_d_apps: 'Vous avez atteint 20 apps. Supprimez-en une pour en créer une autre.',
};
const message = (code) => {
  if (!code) return '';
  const [c, adresse] = code.split(/:(.*)/s);
  return `${MESSAGES[c] ?? c}${adresse ? ` <code>${e(adresse)}</code>` : ''}`;
};

const texteListe = (v) => (Array.isArray(v) ? v.join('\n') : (v ?? ''));
const date = (iso) => new Date(iso).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' });
const dateHeure = (iso) => new Date(iso).toLocaleString('fr-FR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', timeZone: 'Africa/Douala' });

// ── Le gabarit ──────────────────────────────────────────────────────────
function gabarit({ titre, corps, session, csrf, test, classe = '' }) {
  const compte = session
    ? `<div class="compte-haut">
        <span class="avatar-mini" aria-hidden="true">${e((session.pseudo || 'D').charAt(0).toUpperCase())}</span>
        <span class="qui"><b>${e(session.pseudo || 'Développeur')}</b><span>${e(session.sub.slice(0, 8))}…</span></span>
        <form method="post" action="/console/deconnexion"><input type="hidden" name="_csrf" value="${e(csrf)}"><button class="discret">Se déconnecter</button></form>
      </div>`
    : '';
  return `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex">
<meta name="color-scheme" content="light dark">
<title>${e(titre)} · Console Droplet ID</title>
<link rel="icon" href="${statique('favicon.svg')}" type="image/svg+xml">
<link rel="preload" href="/static/InstrumentSans.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="${statique('console.css')}">
</head>
<body class="${classe}">
${test ? '<div class="bandeau-test">Service de TEST — les apps créées ici marchent sur id-test.dropletmesh.app</div>' : ''}
<header class="haut">
  <a class="marque" href="/console/apps"><span class="goutte-marque">${GOUTTE}</span><span>Droplet ID <b>Console</b></span></a>
  <nav class="liens-haut"><a href="${DOCS}">Documentation</a><a href="${DOCS}/#bac-a-sable">Bac à sable</a></nav>
  ${compte}
</header>
${corps}
<script src="${statique('console-ui.js')}" defer></script>
</body>
</html>`;
}

const copiable = (valeur, { secret = false, etiquette = 'Copier' } = {}) =>
  `<div class="copiable${secret ? ' secret' : ''}"><code>${e(valeur)}</code><button type="button" class="copier" data-copier="${e(valeur)}" aria-label="${e(etiquette)}">${I.copier}<span>Copier</span></button></div>`;

const tuileApp = (app, logo, classe = '') =>
  logo
    ? `<span class="tuile-app ${classe}"><img src="${e(logo)}" alt="" width="40" height="40"></span>`
    : `<span class="tuile-app sans-logo ${classe}">${e(app.infos.nom.charAt(0).toUpperCase())}</span>`;

const pastille = (statut) => {
  const [texte, cls] = STATUTS[statut] ?? STATUTS.test;
  return `<span class="pastille ${cls}">${texte}</span>`;
};

// ── Une app : la colonne de gauche et l'en-tête ─────────────────────────
function cadreApp(ctx, onglet, contenu) {
  const { app, logo } = ctx;
  const id = app.clientId;
  const lien = (nom, chemin, icone, texte) =>
    `<a href="/console/apps/${id}${chemin}"${onglet === nom ? ' aria-current="page"' : ''}>${icone}<span>${texte}</span></a>`;
  return gabarit({
    titre: app.infos.nom,
    session: ctx.session,
    csrf: ctx.csrf,
    test: ctx.test,
    corps: `<div class="coque">
  <aside class="cote">
    <a class="retour-apps" href="/console/apps">${I.apps}<span>Toutes les apps</span></a>
    <div class="app-courante">${tuileApp(app, logo)}<div><b>${e(app.infos.nom)}</b>${pastille(app.statut)}</div></div>
    <nav class="sections" aria-label="Sections de l'app">
      ${lien('apercu', '', I.apercu, 'Aperçu')}
      ${lien('identifiants', '/identifiants', I.cle, 'Identifiants')}
      ${lien('ecran', '/ecran', I.ecran, 'Écran de connexion')}
      ${lien('adresses', '/adresses', I.lien, 'Adresses de retour')}
      ${lien('production', '/production', I.fusee, 'Mise en production')}
      ${lien('journal', '/journal', I.journal, 'Journal')}
      ${lien('supprimer', '/supprimer', I.corbeille, 'Supprimer')}
    </nav>
  </aside>
  <main class="contenu">${contenu}</main>
</div>`,
  });
}

const enTete = (titre, texte = '') => `<header class="en-tete"><h1>${titre}</h1>${texte ? `<p>${texte}</p>` : ''}</header>`;
const enregistre = (ctx) => (ctx.enregistre ? `<p class="note ok" role="status">${I.ok}<span>Enregistré. Les changements s'appliquent dès la prochaine connexion.</span></p>` : '');
const champCsrf = (ctx) => `<input type="hidden" name="_csrf" value="${e(ctx.csrf)}">`;

// ── Accueil (non connecté) ──────────────────────────────────────────────
export function pageAccueilConsole({ erreur, test }) {
  const msg = { expire: 'La connexion a expiré. Recommencez.', refuse: 'Connexion annulée.' }[erreur];
  return gabarit({
    titre: 'Bienvenue',
    test,
    classe: 'accueil-console',
    corps: `<main class="porte">
  <section class="porte-texte">
    <h1>Ajoutez « Continuer avec Droplet ID » à votre site ou votre app.</h1>
    <p>Créez une app, recevez son identifiant, choisissez où revenir après la connexion. Vos utilisateurs se connectent avec leur téléphone, sans mot de passe, sans e-mail, sans numéro.</p>
    ${msg ? `<p class="note attention" role="alert">${I.attention}<span>${msg}</span></p>` : ''}
    <a class="bouton-droplet" href="/console/connexion">${GOUTTE}<span>Se connecter avec Droplet ID</span></a>
    <p class="petit">Pas encore de compte ? Il se crée dans l'app Droplet, en un geste, au moment de scanner.</p>
  </section>
  <ol class="porte-etapes">
    <li><b>Créez une app</b><span>Nom, type, adresse de retour. Identifiant immédiat.</span></li>
    <li><b>Ajoutez le bouton</b><span>Un kit pour JavaScript, React, Node, Python, PHP, Go, Flutter, Kotlin.</span></li>
    <li><b>Essayez sur le service de test</b><span>Avec l'app Droplet, ou l'appareil de test dans le navigateur.</span></li>
    <li><b>Passez en production</b><span>Une vérification rapide de votre écran de connexion.</span></li>
  </ol>
</main>`,
  });
}

// ── La liste des apps ───────────────────────────────────────────────────
export function pageApps({ session, csrf, test, lignes }) {
  const vide = `<div class="etat-vide">
    <div class="etat-vide-illu" aria-hidden="true">${GOUTTE}</div>
    <h2>Votre première app</h2>
    <p>Une app, c'est un site ou une application qui propose « Continuer avec Droplet ID ». Il faut moins d'une minute pour la créer.</p>
    <a class="bouton principal" href="/console/apps/nouvelle">${I.plus}<span>Créer une app</span></a>
  </div>`;
  const tableau = `<div class="tableau" role="table" aria-label="Vos apps">
    <div class="ligne entete" role="row"><span role="columnheader">App</span><span role="columnheader">Type</span><span role="columnheader">Statut</span><span role="columnheader" class="nombre">Utilisateurs</span><span role="columnheader" class="nombre">Connexions (7 j)</span></div>
    ${lignes
      .map(
        ({ app, utilisateurs, semaine, logo }) => `<a class="ligne" role="row" href="/console/apps/${app.clientId}">
      <span role="cell" class="app-cellule">${tuileApp(app, logo)}<span><b>${e(app.infos.nom)}</b><code>${e(app.clientId)}</code></span></span>
      <span role="cell" class="doux">${NOMS_TYPES[app.infos.type][0]}</span>
      <span role="cell">${pastille(app.statut)}</span>
      <span role="cell" class="nombre">${utilisateurs}</span>
      <span role="cell" class="nombre">${semaine}</span>
    </a>`,
      )
      .join('')}
  </div>`;
  return gabarit({
    titre: 'Vos apps',
    session,
    csrf,
    test,
    corps: `<main class="page-large">
  <header class="en-tete ligne-titre"><div><h1>Vos apps</h1><p>${lignes.length ? `${lignes.length} app${lignes.length > 1 ? 's' : ''}` : 'Aucune app pour l’instant.'}</p></div>
  ${lignes.length ? `<a class="bouton principal" href="/console/apps/nouvelle">${I.plus}<span>Créer une app</span></a>` : ''}</header>
  ${lignes.length ? tableau : vide}
</main>`,
  });
}

// ── Créer une app ───────────────────────────────────────────────────────
function champ({ nom, etiquette, valeur, aide, erreur, type = 'text', placeholder = '', requis = false, zone = false }) {
  const id = `c-${nom}`;
  const attrs = `id="${id}" name="${nom}" ${requis ? 'required' : ''} placeholder="${e(placeholder)}" ${erreur ? `aria-invalid="true" aria-describedby="${id}-e"` : aide ? `aria-describedby="${id}-a"` : ''}`;
  return `<div class="champ${erreur ? ' en-erreur' : ''}">
    <label for="${id}">${etiquette}</label>
    ${zone ? `<textarea ${attrs} rows="4" spellcheck="false">${e(valeur)}</textarea>` : `<input type="${type}" ${attrs} value="${e(valeur)}" ${type === 'url' ? 'inputmode="url" spellcheck="false" autocapitalize="off"' : ''}>`}
    ${erreur ? `<p class="erreur-champ" id="${id}-e">${message(erreur)}</p>` : aide ? `<p class="aide" id="${id}-a">${aide}</p>` : ''}
  </div>`;
}

export function pageNouvelleApp({ session, csrf, test, infos, erreurs }) {
  const types = Object.entries(NOMS_TYPES)
    .map(
      ([cle, [titre, texte]]) => `<label class="choix">
      <input type="radio" name="type" value="${cle}" ${infos.type === cle ? 'checked' : ''}>
      <span><b>${titre}</b><span>${texte}</span></span>
    </label>`,
    )
    .join('');
  return gabarit({
    titre: 'Créer une app',
    session,
    csrf,
    test,
    corps: `<main class="page-etroite">
  <a class="retour" href="/console/apps">← Vos apps</a>
  ${enTete('Créer une app', 'Tout se modifie ensuite, sauf le type.')}
  <form method="post" action="/console/apps" class="formulaire" novalidate>
    <input type="hidden" name="_csrf" value="${e(csrf)}">
    ${champ({ nom: 'nom', etiquette: "Nom de l'app", valeur: infos.nom, aide: 'Affiché aux personnes qui se connectent : « Se connecter à … ».', erreur: erreurs.nom, requis: true, placeholder: 'Ma boutique' })}
    <fieldset class="champ${erreurs.type ? ' en-erreur' : ''}"><legend>Type</legend><div class="choix-liste">${types}</div>
      ${erreurs.type ? `<p class="erreur-champ">${message(erreurs.type)}</p>` : ''}</fieldset>
    ${champ({ nom: 'site', etiquette: 'Adresse du site', valeur: infos.site, type: 'url', aide: 'La page d’accueil de votre site ou de votre app.', erreur: erreurs.site, requis: true, placeholder: 'https://ma-boutique.cm' })}
    ${champ({ nom: 'redirections', etiquette: 'Adresses de retour', valeur: texteListe(infos.redirections), zone: true, aide: 'Où Droplet ID renvoie la personne après la connexion. Une par ligne. Pour développer : <code>http://localhost:3000/connexion/retour</code>. App mobile : <code>cm.monapp:/connexion</code>.', erreur: erreurs.redirections, requis: true, placeholder: 'https://ma-boutique.cm/connexion/retour' })}
    ${champ({ nom: 'logo', etiquette: 'Logo (facultatif)', valeur: infos.logo, type: 'url', aide: 'Une image carrée (SVG, PNG, JPEG ou WebP, 256 Ko au plus), montrée à côté de votre nom.', erreur: erreurs.logo, placeholder: 'https://ma-boutique.cm/logo.svg' })}
    <label class="interrupteur-ligne"><span><b>Demander un pseudo</b><span>La personne peut refuser ; vous recevez alors seulement un identifiant.</span></span><input type="checkbox" name="profil" value="1" ${infos.profil ? 'checked' : ''}></label>
    <div class="actions-form"><a class="bouton secondaire" href="/console/apps">Annuler</a><button class="bouton principal">Créer l'app</button></div>
  </form>
</main>`,
  });
}

// ── Aperçu : chiffres, courbe, intégration ──────────────────────────────
function courbe(jours) {
  const max = Math.max(1, ...jours.map((j) => j.nombre));
  const l = 100 / jours.length;
  const barres = jours
    .map((j, i) => {
      const h = (j.nombre / max) * 100;
      return `<rect x="${(i * l + l * 0.18).toFixed(2)}" y="${(100 - h).toFixed(2)}" width="${(l * 0.64).toFixed(2)}" height="${Math.max(h, j.nombre ? 2 : 0.6).toFixed(2)}" rx="0.6" class="${j.nombre ? '' : 'zero'}"><title>${e(new Date(j.jour).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' }))} : ${j.nombre}</title></rect>`;
    })
    .join('');
  return `<figure class="courbe">
    <svg viewBox="0 0 100 100" preserveAspectRatio="none" role="img" aria-label="Connexions par jour sur 30 jours">${barres}</svg>
    ${jours.every((j) => !j.nombre) ? '<p class="rien">Pas encore de connexion. Essayez votre app sur le service de test.</p>' : ''}
    <figcaption><span>${e(new Date(jours[0].jour).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' }))}</span><span>Aujourd'hui</span></figcaption>
  </figure>`;
}

function exemples(ctx) {
  const { app, emetteur } = ctx;
  const id = app.clientId;
  const retour = (app.infos.redirections ?? [])[0] ?? 'https://…';
  const portees = app.infos.profil ? "['openid', 'profile']" : "['openid']";
  const emetteurJs = emetteur;
  const secret = app.infos.type === 'serveur';
  const S = secret ? 'process.env.DROPLET_ID_SECRET' : '';
  const kits = {
    serveur: [
      ['Node.js', `import express from 'express';
import { DropletIdServeur } from '@droplet/id-node';

const did = await DropletIdServeur.creer({
  clientId: '${id}',
  clientSecret: ${S},
  redirectUri: '${retour}',
  emetteur: '${emetteurJs}',
  portees: ${portees},
});

const app = express();
app.use(did.routesExpress({
  secret: process.env.SECRET_SESSION,
  ouvrirSession: (req, res, { sub, pseudo }) => { /* votre session */ },
}));`],
      ['Python', `from droplet_id import DropletId
import os

did = DropletId(
    "${id}",
    "${retour}",
    client_secret=os.environ["DROPLET_ID_SECRET"],
    emetteur="${emetteurJs}",
    portees=${portees.replace(/'/g, '"')},
)
url, attente = did.commencer()      # gardez « attente » en session, redirigez vers url
session = did.terminer(url_de_retour, attente)
session["sub"]`],
      ['PHP', `<?php
$did = new DropletMesh\\DropletId(
    '${id}',
    '${retour}',
    getenv('DROPLET_ID_SECRET'),
    '${emetteurJs}',
    ${portees},
);
[$url, $_SESSION['droplet_id_attente']] = $did->commencer();
header("Location: $url");`],
      ['Go', `did, err := dropletid.Nouveau(ctx, dropletid.Options{
    ClientID:     "${id}",
    ClientSecret: os.Getenv("DROPLET_ID_SECRET"),
    RedirectURI:  "${retour}",
    Emetteur:     "${emetteurJs}",
    Portees:      []string{${portees.slice(1, -1).replace(/'/g, '"')}},
})
url, attente := did.Commencer()`],
    ],
    navigateur: [
      ['JavaScript', `import { DropletId, boutonDropletId } from '@droplet/id';

const did = new DropletId({
  clientId: '${id}',
  redirectUri: '${retour}',
  emetteur: '${emetteurJs}',
  portees: ${portees},
});

if (did.estUnRetour()) {
  const { sub, pseudo } = await did.terminerConnexion();
} else {
  document.body.append(boutonDropletId({ onClick: () => did.connecter() }));
}`],
      ['React', `<DropletIdProvider
  clientId="${id}"
  redirectUri="${retour}"
  emetteur="${emetteurJs}"
  portees={${portees}}
>
  <App />
</DropletIdProvider>`],
    ],
    mobile: [
      ['Flutter', `final did = DropletId(
  clientId: '${id}',
  redirectUri: '${retour}',
  emetteur: '${emetteurJs}',
  portees: ${portees},
);
final session = await did.connecter();   // session.sub`],
      ['Kotlin', `val did = DropletId(
    context,
    clientId = "${id}",
    redirectUri = Uri.parse("${retour}"),
    emetteur = Uri.parse("${emetteurJs}"),
    portees = listOf(${portees.slice(1, -1).replace(/'/g, '"')}),
)`],
    ],
  }[app.infos.type];
  const onglets = kits.map(([nom], i) => `<button type="button" role="tab" id="o-${i}" aria-controls="p-${i}" aria-selected="${i === 0}">${nom}</button>`).join('');
  const panneaux = kits.map(([nom, code], i) => `<div role="tabpanel" id="p-${i}" aria-labelledby="o-${i}"${i ? ' hidden' : ''}><div class="code"><button type="button" class="copier sur-code" data-copier="${e(code)}">${I.copier}<span>Copier</span></button><pre><code>${e(code)}</code></pre></div></div>`).join('');
  return `<section class="carte-section">
    <h2>Intégrer en deux minutes</h2>
    <p class="doux">Le code est déjà rempli avec les identifiants de cette app.${secret ? ' Le secret se met dans une variable d’environnement, jamais dans le code.' : ''} <a href="${DOCS}">Toute la documentation</a></p>
    <div class="onglets" role="tablist" aria-label="Langage">${onglets}</div>
    ${panneaux}
  </section>`;
}

export function pageApercu(ctx) {
  const { app, utilisateurs, jours } = ctx;
  const total = jours.reduce((n, j) => n + j.nombre, 0);
  const prod = app.statut === 'production';
  const etapes = [
    ['Créer l’app', true],
    ['Faire une première connexion de test', total > 0],
    ['Compléter l’écran de connexion', Boolean(app.infos.logo && app.infos.politique)],
    ['Passer en production', prod],
  ];
  const fait = etapes.filter(([, ok]) => ok).length;
  return cadreApp(
    ctx,
    'apercu',
    `${enTete(e(app.infos.nom), `Créée le ${date(app.creeLe)} · ${NOMS_TYPES[app.infos.type][0]}`)}
  ${fait < etapes.length ? `<section class="carte-section progression">
    <div class="progression-tete"><h2>Pour démarrer</h2><span>${fait} sur ${etapes.length}</span></div>
    <div class="barre" aria-hidden="true"><i style="width:${(fait / etapes.length) * 100}%"></i></div>
    <ol>${etapes.map(([t, ok]) => `<li class="${ok ? 'fait' : ''}">${ok ? I.ok : I.non}<span>${t}</span></li>`).join('')}</ol>
  </section>` : ''}
  <section class="chiffres-cle">
    <div><span>Utilisateurs</span><b>${utilisateurs}</b><small>personnes ayant accepté votre app</small></div>
    <div><span>Connexions</span><b>${total}</b><small>ces 30 derniers jours</small></div>
    <div><span>Identifiant</span>${copiable(app.clientId)}</div>
  </section>
  <section class="carte-section">
    <h2>Connexions par jour</h2>
    ${courbe(jours)}
  </section>
  ${exemples(ctx)}`,
  );
}

// ── Identifiants ────────────────────────────────────────────────────────
export function pageIdentifiants(ctx) {
  const { app, emetteur, secretNeuf, creee } = ctx;
  const serveur = app.infos.type === 'serveur';
  const secretBloc = serveur
    ? secretNeuf
      ? `<div class="note attention fort" role="alert">${I.attention}<span><b>Copiez ce secret maintenant.</b> Il ne sera plus jamais affiché. Rangez-le dans une variable d’environnement de votre serveur.</span></div>
         ${copiable(secretNeuf, { secret: true })}`
      : `<p class="doux">Le secret n’est montré qu’une fois, à sa création. Perdu ou exposé ? Créez-en un nouveau : l’ancien cessera de marcher aussitôt.</p>
         <form method="post" action="/console/apps/${app.clientId}/secret" data-confirmer="Créer un nouveau secret ? L’ancien cessera de marcher immédiatement.">${champCsrf(ctx)}<button class="bouton secondaire">Créer un nouveau secret</button></form>`
    : `<p class="doux">${app.infos.type === 'mobile' ? 'Une app mobile' : 'Une app dans le navigateur'} ne peut pas garder de secret : elle utilise PKCE, que les kits gèrent pour vous.</p>`;
  return cadreApp(
    ctx,
    'identifiants',
    `${creee ? `<div class="note ok grand" role="status">${I.ok}<span><b>${e(app.infos.nom)} est créée.</b> Elle marche dès maintenant sur le service de test.</span></div>` : ''}
  ${enTete('Identifiants', 'Ce dont votre code a besoin pour parler à Droplet ID.')}
  <section class="carte-section">
    <dl class="valeurs">
      <dt>Identifiant (client_id)</dt><dd>${copiable(app.clientId)}</dd>
      <dt>Secret (client_secret)</dt><dd>${secretBloc}</dd>
      <dt>Émetteur (issuer)</dt><dd>${copiable(emetteur)}</dd>
      <dt>Découverte OpenID</dt><dd>${copiable(`${emetteur}/.well-known/openid-configuration`)}</dd>
      <dt>Authentification</dt><dd><span><code>${TYPES[app.infos.type].methode}</code> · PKCE (S256) obligatoire · flux « code »</span></dd>
    </dl>
  </section>
  ${creee ? `<p><a class="bouton principal" href="/console/apps/${app.clientId}">Voir comment l’intégrer</a></p>` : ''}`,
  );
}

// ── Écran de connexion (avec aperçu) ────────────────────────────────────
function apercuEcran(ctx) {
  const { app, logo } = ctx;
  const hote = (() => {
    try {
      return new URL(app.infos.site).host;
    } catch {
      return '';
    }
  })();
  return `<div class="apercu-ecran" aria-label="Aperçu de l’écran de connexion" data-apercu>
    <div class="apercu-carte">
      <div class="apercu-liaison">${tuileApp(app, logo, 'apercu-logo')}<span class="fil"><i></i><i></i><i></i></span><span class="tuile-app droplet">${GOUTTE}</span></div>
      <p class="apercu-titre">Se connecter à <span data-apercu-nom>${e(app.infos.nom)}</span></p>
      <p class="apercu-sous">avec Droplet ID · <span data-apercu-hote>${e(hote)}</span></p>
      <div class="apercu-qr" aria-hidden="true"></div>
      <div class="apercu-partage"><b>${e(app.infos.nom)} recevra</b><span>Un identifiant propre à ce site</span>${app.infos.profil ? '<span>Votre pseudo, si vous l’acceptez</span>' : ''}</div>
    </div>
  </div>`;
}

export function pageEcran(ctx) {
  const { app, erreurs = {} } = ctx;
  return cadreApp(
    ctx,
    'ecran',
    `${enTete('Écran de connexion', 'Ce que voient les personnes au moment de se connecter.')}
  ${enregistre(ctx)}
  <div class="deux-colonnes">
    <form method="post" action="/console/apps/${app.clientId}/ecran" class="formulaire carte-section" novalidate>
      ${champCsrf(ctx)}
      ${champ({ nom: 'nom', etiquette: "Nom de l'app", valeur: app.infos.nom, erreur: erreurs.nom, requis: true })}
      ${champ({ nom: 'site', etiquette: 'Adresse du site', valeur: app.infos.site, type: 'url', erreur: erreurs.site, requis: true })}
      ${champ({ nom: 'logo', etiquette: 'Logo', valeur: app.infos.logo, type: 'url', aide: 'Carré, SVG/PNG/JPEG/WebP, 256 Ko au plus. Droplet ID le télécharge et le convertit lui-même.', erreur: erreurs.logo })}
      ${champ({ nom: 'politique', etiquette: 'Politique de confidentialité', valeur: app.infos.politique, type: 'url', aide: 'Obligatoire pour passer en production.', erreur: erreurs.politique })}
      ${champ({ nom: 'conditions', etiquette: "Conditions d'utilisation", valeur: app.infos.conditions, type: 'url', erreur: erreurs.conditions })}
      <label class="interrupteur-ligne"><span><b>Demander un pseudo</b><span>Ajoute la portée <code>profile</code> aux exemples de code.</span></span><input type="checkbox" name="profil" value="1" ${app.infos.profil ? 'checked' : ''}></label>
      <div class="actions-form"><button class="bouton principal">Enregistrer</button></div>
    </form>
    ${apercuEcran(ctx)}
  </div>`,
  );
}

// ── Adresses de retour ──────────────────────────────────────────────────
export function pageAdresses(ctx) {
  const { app, erreurs = {} } = ctx;
  const plusieurs = Array.isArray(app.infos.redirections) && hotesDe(app.infos).size > 1;
  return cadreApp(
    ctx,
    'adresses',
    `${enTete('Adresses de retour', 'Droplet ID ne renvoie jamais vers une adresse qui n’est pas dans cette liste.')}
  ${enregistre(ctx)}
  <form method="post" action="/console/apps/${app.clientId}/adresses" class="formulaire carte-section" novalidate>
    ${champCsrf(ctx)}
    ${champ({ nom: 'redirections', etiquette: 'Après la connexion', valeur: texteListe(app.infos.redirections), zone: true, aide: 'Une par ligne, 10 au plus. Exactement l’adresse que votre code envoie (redirect_uri).', erreur: erreurs.redirections, requis: true })}
    ${champ({ nom: 'deconnexions', etiquette: 'Après la déconnexion (facultatif)', valeur: texteListe(app.infos.deconnexions), zone: true, aide: 'Pour <code>post_logout_redirect_uri</code>.', erreur: erreurs.deconnexions })}
    ${plusieurs ? `<p class="note">${I.doc}<span>Plusieurs domaines : l’identifiant d’une personne reste le même sur tous, car il est calculé à partir de l’app.</span></p>` : ''}
    <div class="actions-form"><button class="bouton principal">Enregistrer</button></div>
  </form>`,
  );
}

// ── Mise en production ──────────────────────────────────────────────────
export function pretPourProduction(ctx) {
  const { app, jours } = ctx;
  const web = (app.infos.redirections ?? []).filter((a) => !a.startsWith('http://'));
  return [
    { ok: Boolean(app.infos.logo), texte: 'Un logo', aide: 'Écran de connexion › Logo' },
    { ok: Boolean(app.infos.politique), texte: 'Une politique de confidentialité', aide: 'Écran de connexion' },
    { ok: web.length > 0, texte: 'Au moins une adresse de retour hors localhost', aide: 'Adresses de retour' },
    { ok: jours.some((j) => j.nombre > 0), texte: 'Au moins une connexion réussie sur le service de test', aide: 'Essayez avec l’app Droplet ou l’appareil de test' },
  ];
}

export function pageProduction(ctx) {
  const { app } = ctx;
  const liste = pretPourProduction(ctx);
  const pret = liste.every((c) => c.ok);
  let etat;
  if (app.statut === 'production') etat = `<div class="note ok grand">${I.ok}<span><b>En production.</b> L’app marche sur id.dropletmesh.app, avec le même identifiant.</span></div>`;
  else if (app.statut === 'verification') etat = `<div class="note grand">${I.journal}<span><b>Vérification en cours.</b> L’équipe Droplet examine votre écran de connexion et votre politique de confidentialité ; le statut changera ici. En attendant, l’app continue de marcher sur le service de test.</span></div>`;
  else
    etat = `<form method="post" action="/console/apps/${app.clientId}/production" class="carte-section envoi">
      ${champCsrf(ctx)}
      <p>${pret ? 'Tout est prêt. Nous vérifions que l’écran de connexion ne trompe personne (nom, logo, site), puis l’app est activée sur le service de production.' : 'Il reste quelques points avant de pouvoir demander la mise en production.'}</p>
      <button class="bouton principal" ${pret ? '' : 'disabled'}>Demander la mise en production</button>
    </form>`;
  return cadreApp(
    ctx,
    'production',
    `${enTete('Mise en production', 'Sur le service de test, tout le monde peut créer une app. En production, chaque app est vérifiée, comme chez Google ou Apple.')}
  <section class="carte-section">
    <ul class="liste-verif">${liste.map((c) => `<li class="${c.ok ? 'fait' : ''}">${c.ok ? I.ok : I.non}<span><b>${c.texte}</b>${c.ok ? '' : `<small>${c.aide}</small>`}</span></li>`).join('')}</ul>
  </section>
  ${etat}`,
  );
}

// ── Journal ─────────────────────────────────────────────────────────────
export function pageJournal(ctx) {
  return cadreApp(
    ctx,
    'journal',
    `${enTete('Journal', 'Chaque changement fait sur cette app, du plus récent au plus ancien.')}
  <section class="carte-section"><ol class="journal">${ctx.journal.map((j) => `<li><time datetime="${j.quand}">${dateHeure(j.quand)}</time><span>${e(j.quoi)}</span></li>`).join('') || '<li>Rien pour l’instant.</li>'}</ol></section>`,
  );
}

// ── Supprimer ───────────────────────────────────────────────────────────
export function pageSupprimer(ctx) {
  const { app, erreur } = ctx;
  return cadreApp(
    ctx,
    'supprimer',
    `${enTete('Supprimer l’app')}
  <section class="carte-section danger">
    <p>Les personnes connectées à <b>${e(app.infos.nom)}</b> seront déconnectées, et l’identifiant <code>${e(app.clientId)}</code> cessera de marcher. On ne peut pas revenir en arrière.</p>
    <form method="post" action="/console/apps/${app.clientId}/supprimer" class="formulaire">
      ${champCsrf(ctx)}
      <div class="champ${erreur ? ' en-erreur' : ''}"><label for="c-confirmation">Tapez <b>${e(app.infos.nom)}</b> pour confirmer</label>
      <input id="c-confirmation" name="confirmation" autocomplete="off" data-doit-valoir="${e(app.infos.nom)}">
      ${erreur ? '<p class="erreur-champ">Le nom ne correspond pas.</p>' : ''}</div>
      <div class="actions-form"><button class="bouton danger" data-active-si-valide>Supprimer définitivement</button></div>
    </form>
  </section>`,
  );
}

export function pageIntrouvable({ session, csrf, test }) {
  return gabarit({
    titre: 'Introuvable',
    session,
    csrf,
    test,
    corps: `<main class="page-etroite">${enTete('Cette page n’existe pas', 'Ou cette app ne vous appartient pas.')}<p><a class="bouton secondaire" href="/console/apps">Revenir à vos apps</a></p></main>`,
  });
}
