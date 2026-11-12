// ============================================================================
// Les pages HTML de Droplet ID : connexion (QR + nombre), « continuer en tant
// que », lien d'app, erreurs, accueil, aide, confidentialité, conditions, et
// l'appareil de test. Français et anglais. Aucun script ni police tiers :
// tout est servi par le service lui-même (CSP stricte).
// ============================================================================

const echapper = (s) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

export const GOUTTE = `<svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M12 2.2c-3.6 4.9-6 8.4-6 11.6a6 6 0 0 0 12 0c0-3.2-2.4-6.7-6-11.6Z"/></svg>`;
const ICONES = {
  telephone: `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="6.5" y="2.5" width="11" height="19" rx="2.5"/><path d="M11 18.5h2"/></svg>`,
  oui: `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12.5 4.5 4.5L19 7.5"/></svg>`,
  non: `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>`,
  qr: `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3.5" y="3.5" width="6" height="6" rx="1"/><rect x="14.5" y="3.5" width="6" height="6" rx="1"/><rect x="3.5" y="14.5" width="6" height="6" rx="1"/><path d="M14.5 14.5h2.5v2.5M20.5 14.5v6h-6"/></svg>`,
  cadenas: `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="10.5" width="14" height="10" rx="2.5"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5"/></svg>`,
};

export const TEXTES = {
  fr: {
    avec: 'avec Droplet ID',
    titreConnexion: (site) => `Se connecter à ${site}`,
    codeEtiquette: 'Sur votre téléphone, tapez',
    etapes: ['Ouvrez Droplet, puis Réglages › Droplet ID › Scanner.', 'Visez ce code.', 'Tapez le nombre ci-contre et approuvez.'],
    etats: {
      attente: 'En attente de votre téléphone',
      vue: 'Demande ouverte sur votre téléphone',
      approuvee: 'Approuvé. Retour vers le site…',
      refusee: 'Connexion refusée sur le téléphone.',
      annulee: 'Mauvais nombre tapé : demande annulée.',
      expiree: 'Ce code a expiré.',
      erreur: 'Connexion au service perdue. Nouvelle tentative…',
    },
    nouveauCode: 'Afficher un nouveau code',
    ouvrirDroplet: 'Ouvrir dans Droplet',
    montrerQr: 'Approuver avec un autre téléphone',
    appareilTest: "Approuver avec l'appareil de test",
    recevra: (site) => `${site} recevra`,
    recoit: ['Un identifiant propre à ce site'],
    recoitPseudo: 'Le pseudo que vous choisirez',
    jamais: 'Jamais',
    jamaisListe: ['Numéro', 'E-mail', 'Nom'],
    annuler: (site) => `Annuler et revenir à ${site}`,
    bandeauTest: 'Environnement de test — aucune donnée réelle',
    titreContinuer: (site) => `Continuer vers ${site}`,
    compte: 'Votre Droplet ID',
    compteDetail: (appareil, date) => `Déjà connecté sur ce navigateur · téléphone « ${appareil} »${date ? `, depuis le ${date}` : ''}`,
    continuer: 'Continuer',
    autreCompte: 'Utiliser un autre Droplet ID',
    partagerPseudo: 'Partager un pseudo avec ce site',
    pseudoPourSite: 'Pseudo pour ce site',
    pied: ['Aide', 'Confidentialité', 'Conditions'],
    titreLien: 'Ouvrir dans Droplet',
    texteLien: "Ce lien s'ouvre dans l'app Droplet, sur le téléphone où elle est installée. Si rien ne se passe, ouvrez Droplet puis Réglages › Droplet ID › Scanner, et visez le code affiché sur l'ordinateur.",
    erreurTitre: 'Cette connexion ne peut pas continuer',
    erreurTexte: 'Revenez sur le site et recommencez. Si le problème continue, écrivez à contact@dropletmesh.app en indiquant le code ci-dessous.',
    accueilTitre: 'Connecté, jamais exposé.',
    accueilTexte:
      "Droplet ID permet de se connecter à des sites et des applications sans numéro de téléphone, sans e-mail et sans nom. On approuve sur son téléphone ; chaque site reçoit un identifiant qui ne vaut que pour lui.",
    accueilLiens: ['Développeurs', 'Droplet Labs'],
  },
  en: {
    avec: 'with Droplet ID',
    titreConnexion: (site) => `Sign in to ${site}`,
    codeEtiquette: 'On your phone, type',
    etapes: ['Open Droplet, then Settings › Droplet ID › Scan.', 'Point it at this code.', 'Type the number shown and approve.'],
    etats: {
      attente: 'Waiting for your phone',
      vue: 'Request opened on your phone',
      approuvee: 'Approved. Returning to the site…',
      refusee: 'Sign-in declined on the phone.',
      annulee: 'Wrong number typed: request cancelled.',
      expiree: 'This code has expired.',
      erreur: 'Lost connection to the service. Retrying…',
    },
    nouveauCode: 'Show a new code',
    ouvrirDroplet: 'Open in Droplet',
    montrerQr: 'Approve with another phone',
    appareilTest: 'Approve with the test device',
    recevra: (site) => `${site} will receive`,
    recoit: ['An identifier unique to this site'],
    recoitPseudo: 'The username you choose',
    jamais: 'Never',
    jamaisListe: ['Phone number', 'Email', 'Name'],
    annuler: (site) => `Cancel and go back to ${site}`,
    bandeauTest: 'Test environment — no real data',
    titreContinuer: (site) => `Continue to ${site}`,
    compte: 'Your Droplet ID',
    compteDetail: (appareil, date) => `Already signed in on this browser · phone “${appareil}”${date ? `, since ${date}` : ''}`,
    continuer: 'Continue',
    autreCompte: 'Use another Droplet ID',
    partagerPseudo: 'Share a username with this site',
    pseudoPourSite: 'Username for this site',
    pied: ['Help', 'Privacy', 'Terms'],
    titreLien: 'Open in Droplet',
    texteLien: 'This link opens in the Droplet app, on the phone where it is installed. If nothing happens, open Droplet, then Settings › Droplet ID › Scan, and point it at the code on the computer.',
    erreurTitre: "This sign-in can't continue",
    erreurTexte: 'Go back to the site and try again. If the problem persists, write to contact@dropletmesh.app with the code below.',
    accueilTitre: 'Connected, never exposed.',
    accueilTexte:
      'Droplet ID lets you sign in to websites and apps with no phone number, no email and no name. You approve on your phone; each site receives an identifier that only works for it.',
    accueilLiens: ['Developers', 'Droplet Labs'],
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

function gabarit({ langue, titre, corps, test, scripts = [], chemin = '', classe = '' }) {
  const t = TEXTES[langue];
  const lien = (l) => `${chemin || '/'}${(chemin || '/').includes('?') ? '&' : '?'}langue=${l}`;
  const q = `?langue=${langue}`;
  return `<!doctype html>
<html lang="${langue}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex">
<meta name="referrer" content="no-referrer">
<title>${echapper(titre)} – Droplet ID</title>
<link rel="preload" href="/static/InstrumentSans.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/static/droplet-id.css">
<link rel="icon" href="/static/favicon.svg" type="image/svg+xml">
<meta name="theme-color" content="#f3f5f8" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#05080c" media="(prefers-color-scheme: dark)">
</head>
<body class="${classe}">
${test ? `<div class="test" role="note">${t.bandeauTest}</div>` : ''}
<main>${corps}</main>
<footer class="bas">
  <nav aria-label="Droplet ID">
    <a href="/aide${q}">${t.pied[0]}</a><a href="/confidentialite${q}">${t.pied[1]}</a><a href="/conditions${q}">${t.pied[2]}</a>
  </nav>
  <nav class="langues" aria-label="Langue / Language">
    <a href="${echapper(lien('fr'))}" ${langue === 'fr' ? 'aria-current="true"' : ''} lang="fr">Français</a>
    <a href="${echapper(lien('en'))}" ${langue === 'en' ? 'aria-current="true"' : ''} lang="en">English</a>
  </nav>
</footer>
${scripts.map((s) => `<script src="${s}" defer></script>`).join('')}
</body>
</html>`;
}

/** Le site ⋯ Droplet ID : les deux tuiles reliées, en tête de chaque page de connexion. */
function liaison(client) {
  const site = client.clientName || client.clientId;
  const initiale = echapper(site.trim().charAt(0).toUpperCase());
  return `<div class="liaison" aria-hidden="true">
    <span class="tuile tuile-site">${client.logoUri ? `<img src="${echapper(client.logoUri)}" alt="">` : initiale}</span>
    <span class="fil"><i></i><i></i><i></i></span>
    <span class="tuile tuile-droplet">${GOUTTE}</span>
  </div>`;
}

const hoteDe = (client) => {
  try { return new URL(client.clientUri || client.redirectUris[0]).host; } catch { return ''; }
};

function partage({ t, site, profil }) {
  return `<section class="partage" aria-label="${echapper(t.recevra(site))}">
    <h2>${echapper(t.recevra(site))}</h2>
    <ul class="oui">${[...t.recoit, ...(profil ? [t.recoitPseudo] : [])].map((x) => `<li>${ICONES.oui}${x}</li>`).join('')}</ul>
    <p class="jamais"><span>${t.jamais}</span>${t.jamaisListe.map((x) => `<s>${x}</s>`).join('')}</p>
  </section>`;
}

/** La page de connexion : QR, nombre à taper, état en direct. */
export function pageConnexion({ langue, test, uid, demande, client, qrSvg, lienApp }) {
  const t = TEXTES[langue];
  const site = client.clientName || client.clientId;
  const hote = hoteDe(client);
  const profil = demande.portees.includes('profile');
  const [a, b] = demande.code.split('');
  const corps = `
<section class="carte" data-connexion data-uid="${echapper(uid)}" data-expire="${echapper(demande.expireLe)}" data-duree="120" data-langue="${langue}">
  ${liaison(client)}
  <h1>${echapper(t.titreConnexion(site))}</h1>
  <p class="sous">${t.avec}${hote ? ` · <span class="hote">${echapper(hote)}</span>` : ''}</p>

  <a class="bouton principal seulement-mobile" href="${echapper(lienApp)}">${ICONES.telephone}${t.ouvrirDroplet}</a>
  <button class="lien-discret seulement-mobile" type="button" data-montrer-qr>${ICONES.qr}${t.montrerQr}</button>

  <div class="scan" data-scan>
    <div class="qr" data-qr>
      ${qrSvg}
      <span class="goutte">${GOUTTE}</span>
      <svg class="temps" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true"><rect x="1.5" y="1.5" width="97" height="97" rx="16" pathLength="100" stroke-dasharray="100" stroke-dashoffset="0"/></svg>
    </div>
    <div class="nombre">
      <p class="etiquette">${t.codeEtiquette}</p>
      <div class="chiffres" aria-label="${echapper(demande.code)}"><span>${a}</span><span>${b}</span></div>
    </div>
    <ol class="etapes">${t.etapes.map((e) => `<li>${e}</li>`).join('')}</ol>
  </div>

  <div class="etat" data-etat="attente" role="status" aria-live="polite"><span class="point" aria-hidden="true"></span><span data-texte>${t.etats.attente}</span></div>
  <div class="actions">
    ${test ? `<a class="bouton test-b" href="/test/appareil#${echapper(demande.demandeId)}" target="_blank" rel="noopener">${t.appareilTest}</a>` : ''}
    <button class="bouton secondaire cache" type="button" data-nouveau>${t.nouveauCode}</button>
  </div>

  ${partage({ t, site, profil })}

  <form method="post" action="/interaction/${echapper(uid)}/annuler" class="annuler"><button type="submit">${echapper(t.annuler(site))}</button></form>
</section>
<script type="application/json" id="textes">${JSON.stringify(t.etats).replace(/</g, '\\u003c')}</script>`;
  return gabarit({ langue, titre: t.titreConnexion(site), corps, test, scripts: ['/static/connexion.js'], chemin: `/interaction/${uid}` });
}

/** Déjà connecté dans ce navigateur : « Continuer vers … » en un geste. */
export function pageContinuer({ langue, test, uid, client, portees, appareil, depuis }) {
  const t = TEXTES[langue];
  const site = client.clientName || client.clientId;
  const hote = hoteDe(client);
  const profil = portees.includes('profile');
  const date = depuis ? new Date(depuis).toLocaleDateString(langue === 'fr' ? 'fr-FR' : 'en-GB', { day: 'numeric', month: 'long', year: 'numeric' }) : '';
  const corps = `
<section class="carte">
  ${liaison(client)}
  <h1>${echapper(t.titreContinuer(site))}</h1>
  <p class="sous">${t.avec}${hote ? ` · <span class="hote">${echapper(hote)}</span>` : ''}</p>
  <form method="post" action="/interaction/${echapper(uid)}/continuer" class="continuer">
    <div class="compte">
      <span class="avatar">${GOUTTE}</span>
      <span><b>${t.compte}</b><span>${echapper(t.compteDetail(appareil, date))}</span></span>
      ${ICONES.cadenas}
    </div>
    ${profil ? `<label class="interrupteur"><input type="checkbox" name="profil" value="1" checked data-bascule-pseudo><span>${t.partagerPseudo}</span></label>
    <label class="champ" data-champ-pseudo>${t.pseudoPourSite}<input type="text" name="pseudo" maxlength="40" autocomplete="nickname"></label>` : ''}
    ${partage({ t, site, profil })}
    <button class="bouton principal" type="submit">${t.continuer}</button>
  </form>
  <a class="bouton secondaire" href="/interaction/${echapper(uid)}?autre=1&langue=${langue}">${t.autreCompte}</a>
  <form method="post" action="/interaction/${echapper(uid)}/annuler" class="annuler"><button type="submit">${echapper(t.annuler(site))}</button></form>
</section>`;
  return gabarit({ langue, titre: t.titreContinuer(site), corps, test, scripts: ['/static/continuer.js'], chemin: `/interaction/${uid}` });
}

export function pageLienApp({ langue, test }) {
  const t = TEXTES[langue];
  const corps = `<section class="carte">
  <div class="liaison seule" aria-hidden="true"><span class="tuile tuile-droplet">${GOUTTE}</span></div>
  <h1>${t.titreLien}</h1><p class="texte">${t.texteLien}</p>
  ${test ? `<div class="actions"><a class="bouton test-b" data-vers-test href="/test/appareil">${t.appareilTest}</a></div>` : ''}</section>`;
  return gabarit({ langue, titre: t.titreLien, corps, test, scripts: test ? ['/static/lien.js'] : [] });
}

export function pageErreur({ langue = 'fr', detail, test }) {
  const t = TEXTES[langue] ?? TEXTES.fr;
  const corps = `<section class="carte">
  <div class="liaison seule" aria-hidden="true"><span class="tuile tuile-erreur">${ICONES.non}</span></div>
  <h1>${t.erreurTitre}</h1><p class="texte">${t.erreurTexte}</p>${detail ? `<p class="code-erreur"><code>${echapper(detail)}</code></p>` : ''}</section>`;
  return gabarit({ langue, titre: t.erreurTitre, corps, test });
}

export function pageAccueil({ langue, test }) {
  const t = TEXTES[langue];
  const corps = `<section class="accueil">
  <span class="tuile tuile-droplet grande">${GOUTTE}</span>
  <h1>${t.accueilTitre}</h1><p class="texte">${t.accueilTexte}</p>
  <p class="liens"><a class="bouton principal" href="https://developpeurs-id.dropletmesh.app">${t.accueilLiens[0]}</a><a class="bouton secondaire" href="https://labs.dropletmesh.app">${t.accueilLiens[1]}</a></p>
</section>`;
  return gabarit({ langue, titre: 'Droplet ID', corps, test, chemin: '/', classe: 'large' });
}

// ── Aide, confidentialité, conditions ──────────────────────────────────
const DOCS = {
  aide: {
    fr: ['Aide', [
      ['Comment me connecter ?', "Sur le site, choisissez « Continuer avec Droplet ID ». Sur votre téléphone, ouvrez Droplet, puis Réglages › Droplet ID › Scanner. Visez le code, tapez le nombre affiché sur l'écran, et approuvez."],
      ['Pourquoi un nombre à taper ?', "Il prouve que vous êtes devant l'écran qui demande la connexion. Si quelqu'un vous envoie un code à scanner, vous ne verrez pas son nombre : refusez."],
      ['Je reste connecté ?', "Oui. Ce navigateur se souvient de vous pendant 14 jours : la prochaine fois, un seul geste suffit. Le site, lui, garde sa propre session."],
      ['Retirer un site', 'Dans Droplet : Réglages › Droplet ID › Sites connectés › Retirer. Le site est déconnecté partout.'],
      ['Téléphone perdu', "Dans Droplet sur un autre appareil, retirez le téléphone perdu. Écrivez à contact@dropletmesh.app si vous n'avez pas d'autre appareil."],
    ]],
    en: ['Help', [
      ['How do I sign in?', 'On the site, choose “Continue with Droplet ID”. On your phone, open Droplet, then Settings › Droplet ID › Scan. Point at the code, type the number shown on screen, and approve.'],
      ['Why a number to type?', 'It proves you are in front of the screen asking to sign in. If someone sends you a code to scan, you will not see their number: decline.'],
      ['Do I stay signed in?', 'Yes. This browser remembers you for 14 days: next time, one tap is enough. The site keeps its own session.'],
      ['Remove a site', 'In Droplet: Settings › Droplet ID › Connected sites › Remove. The site is signed out everywhere.'],
      ['Lost phone', 'In Droplet on another device, remove the lost phone. Write to contact@dropletmesh.app if you have no other device.'],
    ]],
  },
  confidentialite: {
    fr: ['Confidentialité', [
      ['Ce que Droplet ID garde', "Pour chaque compte : un identifiant tiré au hasard, la clé publique de chaque appareil et le nom que vous lui donnez, et la liste des sites que vous avez approuvés (avec le pseudo choisi pour chacun). Rien d'autre."],
      ['Ce que Droplet ID ne connaît pas', "Votre numéro, votre e-mail, votre nom, vos contacts, vos messages, votre position. Il n'existe aucun moyen de les demander."],
      ['Ce que reçoit un site', "Un identifiant qui ne vaut que pour lui, et le pseudo si vous acceptez de le partager. Deux sites ne peuvent pas savoir qu'il s'agit de la même personne."],
      ['Cookies', 'Un cookie de session, pour vous reconnaître dans ce navigateur pendant 14 jours au plus. Aucun cookie publicitaire ni de mesure d’audience.'],
      ['Journaux', "Notre hébergeur (Railway) tient des journaux techniques pour faire fonctionner le service. Ils ne sont pas utilisés pour vous identifier."],
      ['Vos droits', 'Selon la loi camerounaise n° 2024/017 du 23 décembre 2024, vous pouvez demander l’accès, la rectification ou l’effacement de vos données. Supprimer Droplet ID dans l’app efface votre appareil. Contact : contact@dropletmesh.app.'],
      ['Éditeur', 'Droplet Labs, initiative indépendante publiée par son fondateur, Yaoundé, Cameroun.'],
    ]],
    en: ['Privacy', [
      ['What Droplet ID keeps', 'For each account: a random identifier, the public key of each device and the name you give it, and the list of sites you approved (with the username chosen for each). Nothing else.'],
      ['What Droplet ID does not know', 'Your phone number, email, name, contacts, messages or location. There is no way to ask for them.'],
      ['What a site receives', 'An identifier that only works for it, and the username if you agree to share it. Two sites cannot tell it is the same person.'],
      ['Cookies', 'A session cookie, to recognise you in this browser for up to 14 days. No advertising or analytics cookies.'],
      ['Logs', 'Our host (Railway) keeps technical logs to run the service. They are not used to identify you.'],
      ['Your rights', 'Under Cameroonian Law No. 2024/017 of 23 December 2024, you can ask to access, correct or erase your data. Removing Droplet ID in the app erases your device. Contact: contact@dropletmesh.app.'],
      ['Publisher', 'Droplet Labs, an independent initiative published by its founder, Yaoundé, Cameroon.'],
    ]],
  },
  conditions: {
    fr: ['Conditions', [
      ['Le service', "Droplet ID permet de se connecter à des sites et des applications partenaires. Il est fourni gratuitement, en l'état, pendant sa phase de lancement."],
      ['Votre rôle', "Vous gardez votre téléphone verrouillé, et vous refusez toute demande que vous n'avez pas lancée vous-même."],
      ['Les sites partenaires', "Chaque site est responsable de ce qu'il fait de l'identifiant qu'il reçoit. Ils s'engagent à ne pas redemander de numéro ni d'e-mail pour se connecter."],
      ['Ce que Droplet ID n’est pas', "Ce n'est pas une pièce d'identité. Il ne remplace aucune vérification exigée par la loi."],
      ['Droit applicable', 'Droit de la République du Cameroun.'],
    ]],
    en: ['Terms', [
      ['The service', 'Droplet ID lets you sign in to partner websites and apps. It is provided free of charge, as is, during its launch phase.'],
      ['Your part', 'You keep your phone locked, and you decline any request you did not start yourself.'],
      ['Partner sites', 'Each site is responsible for what it does with the identifier it receives. They commit not to ask again for a phone number or email to sign in.'],
      ['What Droplet ID is not', 'It is not an identity document. It does not replace any check required by law.'],
      ['Governing law', 'Law of the Republic of Cameroon.'],
    ]],
  },
};

export function pageDocument({ nom, langue, test }) {
  const [titre, blocs] = DOCS[nom][langue];
  const corps = `<article class="document">
  <span class="tuile tuile-droplet">${GOUTTE}</span>
  <h1>${titre}</h1>
  ${blocs.map(([h, p]) => `<section><h2>${h}</h2><p>${p}</p></section>`).join('')}
  <p class="maj">${langue === 'fr' ? 'Mis à jour le 12 novembre 2026.' : 'Updated 12 November 2026.'}</p>
</article>`;
  return gabarit({ langue, titre, corps, test, chemin: `/${nom}`, classe: 'large' });
}

/** L'appareil de test : un « téléphone » dans le navigateur, en test seulement. */
export function pageAppareilTest({ langue }) {
  const fr = langue === 'fr';
  const corps = `
<section class="carte appareil" data-appareil data-langue="${langue}">
  <div class="telephone-test"><span class="tuile tuile-droplet">${GOUTTE}</span><span><b>${fr ? 'Appareil de test' : 'Test device'}</b><span>${fr ? 'Joue le rôle du téléphone. Clé Ed25519 gardée dans ce navigateur.' : 'Plays the phone. Ed25519 key kept in this browser.'}</span></span></div>

  <div data-pas-de-compte class="cache">
    <h1>${fr ? 'Créer un compte de test' : 'Create a test account'}</h1>
    <p class="texte">${fr ? 'Aucune donnée : juste une clé, créée ici.' : 'No data: just a key, created here.'}</p>
    <div class="actions"><button class="bouton principal" data-creer>${fr ? 'Créer le compte' : 'Create account'}</button></div>
  </div>

  <div data-compte class="cache">
    <p class="petit">${fr ? 'Appareil' : 'Device'} <code data-id></code></p>
    <div data-sans-demande>
      <h1>${fr ? 'Aucune demande' : 'No request'}</h1>
      <p class="texte">${fr ? 'Ouvrez cette page depuis « Approuver avec l’appareil de test », ou collez le lien de la demande.' : 'Open this page from “Approve with the test device”, or paste the request link.'}</p>
      <label class="champ">${fr ? 'Lien ou identifiant de la demande' : 'Request link or id'}<input type="text" data-saisie autocomplete="off"></label>
      <div class="actions"><button class="bouton secondaire" data-charger>${fr ? 'Ouvrir la demande' : 'Open request'}</button></div>
    </div>
    <div data-demande class="cache">
      <div class="liaison"><span class="tuile tuile-site" data-logo></span><span class="fil"><i></i><i></i><i></i></span><span class="tuile tuile-droplet">${GOUTTE}</span></div>
      <h1 data-titre></h1>
      <p class="sous" data-hote></p>
      <span class="cache" data-nom></span>
      <label class="champ centre">${fr ? 'Tapez le nombre affiché sur l’écran de connexion' : 'Type the number shown on the sign-in screen'}
        <input class="nombre-saisi" type="text" inputmode="numeric" pattern="[0-9]*" maxlength="2" autocomplete="off" data-code aria-describedby="aide-code"></label>
      <p class="petit" id="aide-code">${fr ? 'Pas d’écran de connexion devant vous ? Refusez : quelqu’un essaie peut-être d’entrer dans votre compte.' : 'No sign-in screen in front of you? Decline: someone may be trying to get into your account.'}</p>
      <div data-profil class="cache">
        <label class="interrupteur"><input type="checkbox" data-accepter-profil checked><span>${fr ? 'Partager un pseudo avec ce site' : 'Share a username with this site'}</span></label>
        <label class="champ">${fr ? 'Pseudo pour ce site' : 'Username for this site'}<input type="text" data-pseudo maxlength="40" autocomplete="off"></label>
      </div>
      <div class="actions">
        <button class="bouton principal" data-approuver disabled>${fr ? 'Approuver' : 'Approve'}</button>
        <button class="bouton secondaire" data-refuser>${fr ? 'Refuser' : 'Decline'}</button>
      </div>
    </div>
    <div class="etat cache" data-resultat role="status" aria-live="polite"><span class="point"></span><span data-texte></span></div>
    <details class="sites"><summary>${fr ? 'Sites connectés' : 'Connected sites'}</summary><ul class="liste" data-connexions></ul></details>
    <button class="lien-discret" data-oublier>${fr ? 'Oublier cet appareil' : 'Forget this device'}</button>
  </div>
</section>`;
  return gabarit({ langue, titre: fr ? 'Appareil de test' : 'Test device', corps, test: true, scripts: ['/static/appareil.js'], chemin: '/test/appareil' });
}
