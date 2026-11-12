// The sign-in page: follows the request until the phone answers.
(() => {
  const carte = document.querySelector('[data-connexion]');
  if (!carte) return;
  const uid = carte.dataset.uid;
  const textes = JSON.parse(document.getElementById('textes').textContent);
  const etat = carte.querySelector('.etat');
  const texte = etat.querySelector('[data-texte]');
  const qr = carte.querySelector('[data-qr]');
  const anneau = qr.querySelector('.temps rect');
  const nouveau = carte.querySelector('[data-nouveau]');
  const expire = Date.parse(carte.dataset.expire);
  const duree = Number(carte.dataset.duree) * 1000;
  let fini = false;
  let echecs = 0;
  let prochain;

  const afficher = (e) => {
    etat.dataset.etat = e;
    texte.textContent = textes[e] ?? textes.attente;
  };

  const expirer = () => {
    fini = true;
    qr.dataset.expire = '';
    afficher('expiree');
    nouveau.classList.remove('cache');
  };

  // The remaining time runs around the QR frame.
  const minuter = () => {
    if (fini) return;
    const reste = Math.max(0, expire - Date.now());
    anneau.style.strokeDashoffset = String(100 - (reste / duree) * 100);
    if (reste <= 0) return expirer();
    setTimeout(minuter, 1000);
  };

  const terminer = async () => {
    const r = await fetch(`/interaction/${uid}/terminer`, { method: 'POST', headers: { accept: 'application/json' } });
    const j = await r.json().catch(() => ({}));
    if (j.redirection) location.assign(j.redirection);
  };

  const suivre = async () => {
    if (fini) return;
    try {
      const r = await fetch(`/interaction/${uid}/etat`, { headers: { accept: 'application/json' }, cache: 'no-store' });
      if (!r.ok) throw new Error(String(r.status));
      const { etat: e } = await r.json();
      echecs = 0;
      if (e === 'expiree') return expirer();
      afficher(e);
      if (e === 'approuvee') { fini = true; return terminer(); }
      if (e === 'refusee' || e === 'annulee') { fini = true; return terminer(); }
    } catch {
      echecs += 1;
      if (echecs > 2) afficher('erreur');
    }
    prochain = setTimeout(suivre, 1500);
  };

  // Android: open the app directly (intent link, with the web page as fallback).
  const ouvrir = carte.querySelector('[data-android]');
  if (ouvrir && /Android/i.test(navigator.userAgent)) ouvrir.href = ouvrir.dataset.android;

  // Back from the app: check at once (timers sleep while the tab is hidden).
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && !fini) { clearTimeout(prochain); suivre(); }
  });

  // On a phone: the QR is folded away behind "Approve from another phone".
  carte.querySelector('[data-montrer-qr]')?.addEventListener('click', () => {
    carte.dataset.qrOuvert = '';
    carte.querySelector('[data-scan]').scrollIntoView({ behavior: 'smooth', block: 'center' });
  });

  nouveau.addEventListener('click', async () => {
    await fetch(`/interaction/${uid}/nouvelle`, { method: 'POST' });
    location.reload();
  });

  minuter();
  suivre();
})();
