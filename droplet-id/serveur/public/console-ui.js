// Console: copy buttons, code tabs, confirmations, live preview of the sign-in screen.
(() => {
  // Copy
  document.addEventListener('click', async (ev) => {
    const b = ev.target.closest('[data-copier]');
    if (!b) return;
    try {
      await navigator.clipboard.writeText(b.dataset.copier);
    } catch {
      const t = document.createElement('textarea');
      t.value = b.dataset.copier;
      document.body.append(t);
      t.select();
      document.execCommand('copy');
      t.remove();
    }
    const s = b.querySelector('span');
    const avant = s?.textContent;
    b.dataset.copie = '';
    if (s) s.textContent = 'Copié';
    setTimeout(() => {
      delete b.dataset.copie;
      if (s) s.textContent = avant;
    }, 1600);
  });

  // Tabs (keyboard: left/right)
  for (const liste of document.querySelectorAll('[role=tablist]')) {
    const onglets = [...liste.querySelectorAll('[role=tab]')];
    const choisir = (o) => {
      for (const x of onglets) {
        const oui = x === o;
        x.setAttribute('aria-selected', String(oui));
        x.tabIndex = oui ? 0 : -1;
        document.getElementById(x.getAttribute('aria-controls')).hidden = !oui;
      }
      o.focus();
    };
    onglets.forEach((o, i) => {
      o.tabIndex = i ? -1 : 0;
      o.addEventListener('click', () => choisir(o));
      o.addEventListener('keydown', (ev) => {
        const d = { ArrowRight: 1, ArrowLeft: -1 }[ev.key];
        if (d) choisir(onglets[(i + d + onglets.length) % onglets.length]);
      });
    });
  }

  // Confirm before a destructive form
  for (const f of document.querySelectorAll('form[data-confirmer]')) {
    f.addEventListener('submit', (ev) => {
      if (!confirm(f.dataset.confirmer)) ev.preventDefault();
    });
  }

  // Delete: enabled only once the name is typed
  const saisie = document.querySelector('[data-doit-valoir]');
  const bouton = document.querySelector('[data-active-si-valide]');
  if (saisie && bouton) {
    const maj = () => (bouton.disabled = saisie.value.trim() !== saisie.dataset.doitValoir);
    saisie.addEventListener('input', maj);
    maj();
  }

  // Live preview of the sign-in screen
  const nom = document.querySelector('#c-nom');
  const site = document.querySelector('#c-site');
  const apercuNom = document.querySelector('[data-apercu-nom]');
  const apercuHote = document.querySelector('[data-apercu-hote]');
  if (nom && apercuNom) nom.addEventListener('input', () => (apercuNom.textContent = nom.value || '…'));
  if (site && apercuHote)
    site.addEventListener('input', () => {
      try {
        apercuHote.textContent = new URL(site.value).host;
      } catch {
        apercuHote.textContent = '';
      }
    });
})();
