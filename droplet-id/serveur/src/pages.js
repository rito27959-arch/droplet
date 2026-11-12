// ============================================================================
// Les pages HTML de Droplet ID (connexion, lien d'app, erreurs, accueil,
// appareil de test). Français et anglais. Aucun script ni police tiers : tout
// est servi par le service lui-même (voir la politique de sécurité, CSP).
// ============================================================================

const echapper = (s) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

export const GOUTTE = `<svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M12 2.2c-3.6 4.9-6 8.4-6 11.6a6 6 0 0 0 12 0c0-3.2-2.4-6.7-6-11.6Z"/></svg>`;
const BOUCLIER = `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10Z"/><path d="m9 12 2 2 4-4"/></svg>`;
const TELEPHONE = `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="2" width="12" height="20" rx="2.5"/><path d="M11 18h2"/></svg>`;

export const TEXTES = {
  fr: {
    titreConnexion: (site) => `Se connecter à ${site}`,
    leadConnexion: 'Avec Droplet ID : approuvez sur votre téléphone.',
    codeEtiquette: 'Tapez ce nombre sur votre téléphone',
    etapes: ['Ouvrez Droplet et scannez ce code.', 'Tapez le nombre affiché ci-dessus.', 'Approuvez la connexion.'],
    etats: {
      attente: 'En attente de votre téléphone…',
      vue: 'Demande ouverte sur votre téléphone',
      approuvee: 'Approuvé. Retour vers le site…',
      refusee: 'Connexion refusée sur le téléphone.',
      annulee: 'Mauvais nombre tapé : la demande est annulée.',
      expiree: 'Ce code a expiré.',
      erreur: 'Connexion au service perdue. Nouvelle tentative…',
    },
    nouveauCode: 'Nouveau code',
    ouvrirDroplet: 'Ouvrir dans Droplet',
    appareilTest: "Approuver avec l'appareil de test",
    promesse: (site, profil) =>
      `${site} recevra un identifiant propre à ce site${profil ? ', et le pseudo que vous choisirez' : ''}. Ni numéro, ni e-mail, ni nom.`,
    annuler: (site) => `Annuler et revenir à ${site}`,
    bandeauTest: 'Environnement de test — aucune donnée réelle',
    pied: 'Droplet ID · Connecté, jamais exposé.',
    titreLien: 'Ouvrir dans Droplet',
    texteLien: "Ce lien s'ouvre dans l'app Droplet. Si rien ne se passe, ouvrez-le sur le téléphone où Droplet est installé, ou scannez le code depuis l'app.",
    erreurTitre: 'Cette connexion ne peut pas continuer',
    erreurTexte: 'Revenez sur le site et recommencez. Si le problème continue, écrivez à contact@dropletmesh.app.',
    accueilTitre: 'Connecté, jamais exposé.',
    accueilTexte:
      "Droplet ID permet de se connecter à des sites et des applications sans numéro de téléphone, sans e-mail et sans nom. On approuve sur son téléphone ; chaque site reçoit un identifiant qui ne vaut que pour lui.",
  },
  en: {
    titreConnexion: (site) => `Sign in to ${site}`,
    leadConnexion: 'With Droplet ID: approve on your phone.',
    codeEtiquette: 'Type this number on your phone',
    etapes: ['Open Droplet and scan this code.', 'Type the number shown above.', 'Approve the sign-in.'],
    etats: {
      attente: 'Waiting for your phone…',
      vue: 'Request opened on your phone',
      approuvee: 'Approved. Returning to the site…',
      refusee: 'Sign-in declined on the phone.',
      annulee: 'Wrong number typed: the request was cancelled.',
      expiree: 'This code has expired.',
      erreur: 'Lost connection to the service. Retrying…',
    },
    nouveauCode: 'New code',
    ouvrirDroplet: 'Open in Droplet',
    appareilTest: 'Approve with the test device',
    promesse: (site, profil) =>
      `${site} will receive an identifier unique to this site${profil ? ', and the username you choose' : ''}. No phone number, no email, no name.`,
    annuler: (site) => `Cancel and go back to ${site}`,
    bandeauTest: 'Test environment — no real data',
    pied: 'Droplet ID · Connected, never exposed.',
    titreLien: 'Open in Droplet',
    texteLien: "This link opens in the Droplet app. If nothing happens, open it on the phone where Droplet is installed, or scan the code from the app.",
    erreurTitre: "This sign-in can't continue",
    erreurTexte: 'Go back to the site and try again. If the problem persists, write to contact@dropletmesh.app.',
    accueilTitre: 'Connected, never exposed.',
    accueilTexte:
      'Droplet ID lets you sign in to websites and apps with no phone number, no email and no name. You approve on your phone; each site receives an identifier that only works for it.',
  },
};

export function langueDe(entetes, parametre) {
  const demande = (parametre || '').split(' ')[0];
  if (demande === 'fr' || demande === 'en') return demande;
  const al = (entetes['accept-language'] || '').toLowerCase();
  const fr = al.indexOf('fr');
  const en = al.indexOf('en');
  if (fr === -1 && en === -1) return 'fr';
  if (fr === -1) return 'en';
  if (en === -1) return 'fr';
  return fr < en ? 'fr' : 'en';
}

function gabarit({ langue, titre, corps, test, scripts = [], chemin = '' }) {
  const t = TEXTES[langue];
  const autre = langue === 'fr' ? 'en' : 'fr';
  const lien = (l) => `${chemin}${chemin.includes('?') ? '&' : '?'}langue=${l}`;
  return `<!doctype html>
<html lang="${langue}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<meta name="referrer" content="no-referrer">
<title>${echapper(titre)} · Droplet ID</title>
<link rel="preload" href="/static/InstrumentSans.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/static/droplet-id.css">
<link rel="icon" href="/static/favicon.svg" type="image/svg+xml">
<meta name="theme-color" content="#f5f7f9" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#061019" media="(prefers-color-scheme: dark)">
</head>
<body>
${test ? `<div class="test" role="note">${t.bandeauTest}</div>` : ''}
<header class="top">
  <a class="marque" href="/">${GOUTTE}<span>Droplet ID</span></a>
  ${chemin ? `<nav class="langues" aria-label="Langue / Language">
    <a href="${echapper(lien('fr'))}" ${langue === 'fr' ? 'aria-current="true"' : ''} lang="fr">FR</a>
    <a href="${echapper(lien('en'))}" ${langue === 'en' ? 'aria-current="true"' : ''} lang="en">EN</a>
  </nav>` : ''}
</header>
<main>${corps}</main>
<footer class="bas">${t.pied}</footer>
${scripts.map((s) => `<script src="${s}" defer></script>`).join('')}
</body>
</html>`;
}

/** La page de connexion : QR, code de correspondance, état en direct. */
export function pageConnexion({ langue, test, uid, demande, client, qrSvg, lienApp }) {
  const t = TEXTES[langue];
  const site = client.clientName || client.clientId;
  const hote = (() => {
    try { return new URL(client.clientUri || client.redirectUris[0]).host; } catch { return ''; }
  })();
  const initiale = echapper(site.trim().charAt(0).toUpperCase());
  const profil = demande.portees.includes('profile');
  const [a, b] = demande.code.split('');
  const corps = `
<section class="carte" data-connexion data-uid="${echapper(uid)}" data-expire="${echapper(demande.expireLe)}" data-duree="120" data-langue="${langue}">
  <div class="site">
    <div class="logo">${client.logoUri ? `<img src="${echapper(client.logoUri)}" alt="">` : initiale}</div>
    <div><div class="nom">${echapper(site)}</div>${hote ? `<div class="hote">${echapper(hote)}</div>` : ''}</div>
  </div>
  <h1>${echapper(t.titreConnexion(site))}</h1>
  <p class="lead">${t.leadConnexion}</p>

  <div class="scan">
    <div class="qr" data-qr>
      ${qrSvg}
      <div class="goutte">${GOUTTE}</div>
      <svg class="temps" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true"><rect x="1.5" y="1.5" width="97" height="97" rx="13" pathLength="100" stroke-dasharray="100" stroke-dashoffset="0"/></svg>
    </div>
    <div class="correspondance">
      <p class="etiquette">${t.codeEtiquette}</p>
      <div class="chiffres" aria-label="${echapper(demande.code)}"><span>${a}</span><span>${b}</span></div>
    </div>
  </div>

  <ol class="etapes">${t.etapes.map((e) => `<li>${e.replace('ci-dessus', `ci-dessus (${demande.code})`).replace('as above', `as above (${demande.code})`)}</li>`).join('')}</ol>

  <div class="etat" data-etat="attente" role="status" aria-live="polite"><span class="point" aria-hidden="true"></span><span data-texte>${t.etats.attente}</span></div>

  <div class="actions">
    <a class="bouton seulement-mobile" href="${echapper(lienApp)}">${TELEPHONE}${t.ouvrirDroplet}</a>
    ${test ? `<a class="bouton test-b" href="/test/appareil#${echapper(demande.demandeId)}" target="_blank" rel="noopener">${t.appareilTest}</a>` : ''}
    <button class="bouton discret cache" type="button" data-nouveau>${t.nouveauCode}</button>
  </div>

  <p class="promesse">${BOUCLIER}<span>${echapper(t.promesse(site, profil))}</span></p>
  <form method="post" action="/interaction/${echapper(uid)}/annuler"><button class="annuler" style="background:none;border:0;width:100%;cursor:pointer;font:inherit" type="submit">${echapper(t.annuler(site))}</button></form>
</section>
<script type="application/json" id="textes">${JSON.stringify(t.etats).replace(/</g, '\\u003c')}</script>`;
  return gabarit({ langue, titre: t.titreConnexion(site), corps, test, scripts: ['/static/connexion.js'], chemin: `/interaction/${uid}` });
}

export function pageLienApp({ langue, test }) {
  const t = TEXTES[langue];
  const corps = `<section class="carte"><h1>${t.titreLien}</h1><p class="lead">${t.texteLien}</p>
  ${test ? `<div class="actions"><a class="bouton test-b" data-vers-test href="/test/appareil">${t.appareilTest}</a></div>` : ''}</section>`;
  return gabarit({ langue, titre: t.titreLien, corps, test, scripts: test ? ['/static/lien.js'] : [] });
}

export function pageErreur({ langue = 'fr', detail, test }) {
  const t = TEXTES[langue] ?? TEXTES.fr;
  const corps = `<section class="carte"><h1>${t.erreurTitre}</h1><p class="lead">${t.erreurTexte}</p>${detail ? `<p class="petit">Code : <code>${echapper(detail)}</code></p>` : ''}</section>`;
  return gabarit({ langue, titre: t.erreurTitre, corps, test });
}

export function pageAccueil({ langue, test }) {
  const t = TEXTES[langue];
  const corps = `<section class="page"><h1>${t.accueilTitre}</h1><p class="lead">${t.accueilTexte}</p>
  <ul class="liste">
    <li><a href="/.well-known/openid-configuration">/.well-known/openid-configuration</a></li>
    <li><a href="https://labs.dropletmesh.app">Droplet Labs</a></li>
  </ul></section>`;
  return gabarit({ langue, titre: 'Droplet ID', corps, test, chemin: '/' });
}

/** L'appareil de test : un « téléphone » dans le navigateur, en test seulement. */
export function pageAppareilTest({ langue }) {
  const fr = langue === 'fr';
  const corps = `
<section class="carte appareil" data-appareil data-langue="${langue}">
  <div class="site"><div class="logo">${GOUTTE}</div><div><div class="nom">${fr ? 'Appareil de test' : 'Test device'}</div><div class="hote">${fr ? 'Clé Ed25519 gardée dans ce navigateur' : 'Ed25519 key kept in this browser'}</div></div></div>
  <p class="petit" style="margin-top:1rem">${fr
    ? "Remplace le téléphone pour essayer Droplet ID. Existe seulement dans l'environnement de test. Dans la vraie vie, c'est l'app Droplet qui approuve."
    : 'Stands in for the phone to try Droplet ID. Exists only in the test environment. In real life, the Droplet app approves.'}</p>

  <div data-pas-de-compte class="cache">
    <h1>${fr ? 'Créer un compte de test' : 'Create a test account'}</h1>
    <p class="lead">${fr ? 'Aucune donnée : juste une clé, créée ici.' : 'No data: just a key, created here.'}</p>
    <div class="actions"><button class="bouton" data-creer>${fr ? 'Créer le compte' : 'Create account'}</button></div>
  </div>

  <div data-compte class="cache">
    <p class="petit">${fr ? 'Appareil' : 'Device'} <code data-id></code></p>
    <div data-sans-demande>
      <h1>${fr ? 'Aucune demande' : 'No request'}</h1>
      <p class="lead">${fr ? 'Collez le lien affiché sous le QR, ou ouvrez cette page depuis « Approuver avec l’appareil de test ».' : 'Paste the link shown under the QR, or open this page from “Approve with the test device”.'}</p>
      <label class="champ">${fr ? 'Lien ou identifiant de la demande' : 'Request link or id'}<input type="text" data-saisie autocomplete="off"></label>
      <div class="actions"><button class="bouton discret" data-charger>${fr ? 'Ouvrir la demande' : 'Open request'}</button></div>
    </div>
    <div data-demande class="cache">
      <div class="site" style="margin-top:1.2rem"><div class="logo" data-logo></div><div><div class="nom" data-nom></div><div class="hote" data-hote></div></div></div>
      <h1 data-titre></h1>
      <label class="champ">${fr ? 'Tapez le nombre affiché sur l’écran de connexion' : 'Type the number shown on the sign-in screen'}
        <input class="nombre" type="text" inputmode="numeric" pattern="[0-9]*" maxlength="2" autocomplete="off" data-code aria-describedby="aide-code"></label>
      <p class="petit" id="aide-code">${fr ? 'Si vous ne voyez pas d’écran de connexion devant vous, refusez : quelqu’un essaie peut-être d’entrer dans votre compte.' : 'If there is no sign-in screen in front of you, decline: someone may be trying to get into your account.'}</p>
      <div data-profil class="cache">
        <label class="portee"><input type="checkbox" data-accepter-profil checked> ${fr ? 'Partager un pseudo avec ce site' : 'Share a username with this site'}</label>
        <label class="champ">${fr ? 'Pseudo pour ce site' : 'Username for this site'}<input type="text" data-pseudo maxlength="40" autocomplete="off"></label>
      </div>
      <div class="actions">
        <button class="bouton" data-approuver disabled>${fr ? 'Approuver' : 'Approve'}</button>
        <button class="bouton discret" data-refuser>${fr ? 'Refuser' : 'Decline'}</button>
      </div>
    </div>
    <div class="etat cache" data-resultat role="status" aria-live="polite"><span class="point"></span><span data-texte></span></div>
    <details style="margin-top:1.4rem"><summary class="petit">${fr ? 'Sites connectés' : 'Connected sites'}</summary><ul class="liste" data-connexions></ul></details>
    <div class="actions"><button class="bouton discret" data-oublier>${fr ? 'Oublier cet appareil' : 'Forget this device'}</button></div>
  </div>
</section>`;
  return gabarit({ langue, titre: fr ? 'Appareil de test' : 'Test device', corps, test: true, scripts: ['/static/appareil.js'], chemin: '/test/appareil' });
}
