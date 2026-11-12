import { DropletId, boutonDropletId, EMETTEUR_TEST } from './droplet-id.js';

// Tabs.
const onglets = [...document.querySelectorAll('[role=tab]')];
const choisir = (t) => {
  onglets.forEach((o) => {
    const actif = o === t;
    o.setAttribute('aria-selected', String(actif));
    o.tabIndex = actif ? 0 : -1;
    document.getElementById(o.getAttribute('aria-controls')).hidden = !actif;
  });
};
onglets.forEach((t, i) => {
  t.addEventListener('click', () => choisir(t));
  t.addEventListener('keydown', (e) => {
    const d = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
    if (!d) return;
    const n = onglets[(i + d + onglets.length) % onglets.length];
    choisir(n);
    n.focus();
  });
});

// Sandbox: a real sign-in with the JavaScript kit, then show what arrived.
const local = location.hostname === 'localhost';
const did = new DropletId({
  clientId: 'bac-a-sable',
  redirectUri: `${location.origin}/bac-a-sable`,
  emetteur: local ? 'http://localhost:8080' : EMETTEUR_TEST,
  portees: ['openid', 'profile'],
});
const action = document.querySelector('[data-sable-action]');
const vide = document.querySelector('[data-sable-vide]');
const sortie = document.querySelector('[data-sable-claims]');

function montrer(session) {
  const claims = JSON.parse(atob(session.idToken.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
  vide.classList.add('cache');
  sortie.classList.remove('cache');
  sortie.textContent = JSON.stringify({ id_token: claims, userinfo: { sub: session.sub, preferred_username: session.pseudo } }, null, 2);
  action.replaceChildren(Object.assign(document.createElement('button'), {
    className: 'lien', textContent: 'Recommencer', onclick: () => { did.deconnecter(); location.assign('/#bac-a-sable'); },
  }));
}

action.append(boutonDropletId({ variante: 'bleu', onClick: () => did.connecter() }));

if (did.estUnRetour()) {
  did.terminerConnexion()
    .then((s) => { montrer(s); history.replaceState(null, '', '/#bac-a-sable'); document.getElementById('bac-a-sable').scrollIntoView(); })
    .catch((e) => { vide.textContent = `La connexion n’a pas abouti : ${e.code ?? e.message}`; history.replaceState(null, '', '/#bac-a-sable'); });
} else {
  try { const s = JSON.parse(localStorage.getItem('droplet-id:session')); if (s?.idToken) montrer(s); } catch {}
}
