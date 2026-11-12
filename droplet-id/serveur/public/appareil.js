// The test device: plays the phone's part, with an Ed25519 key kept in this
// browser. It is also the reference implementation of the device protocol
// (signed requests) in JavaScript.
(() => {
  const racine = document.querySelector('[data-appareil]');
  if (!racine) return;
  const fr = racine.dataset.langue === 'fr';
  const $ = (s) => racine.querySelector(s);
  const CLE = 'droplet-id-appareil-test';

  const b64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const hex = (buf) => [...new Uint8Array(buf)].map((x) => x.toString(16).padStart(2, '0')).join('');
  const lire = () => { try { return JSON.parse(localStorage.getItem(CLE)); } catch { return null; } };
  const ecrire = (v) => { try { v ? localStorage.setItem(CLE, JSON.stringify(v)) : localStorage.removeItem(CLE); } catch {} };

  let etat = lire(); // { appareilId, compteId, cleJwk, clePub }
  let demande = null;
  let codeChoisi = null;

  async function cleSecrete() {
    return crypto.subtle.importKey('jwk', etat.cleJwk, { name: 'Ed25519' }, false, ['sign']);
  }

  /** MÉTHODE \n chemin \n heure \n nonce \n sha256-hex(corps), signé en Ed25519. */
  async function appeler(methode, chemin, corps, { cle, clePub } = {}) {
    const texteCorps = corps ? JSON.stringify(corps) : '';
    const ts = Math.floor(Date.now() / 1000);
    const nonce = b64(crypto.getRandomValues(new Uint8Array(16)));
    const empreinte = hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(texteCorps)));
    const aSigner = `${methode}\n${chemin}\n${ts}\n${nonce}\n${empreinte}`;
    const sig = b64(await crypto.subtle.sign({ name: 'Ed25519' }, cle ?? (await cleSecrete()), new TextEncoder().encode(aSigner)));
    const entetes = { 'content-type': 'application/json', 'x-droplet-ts': String(ts), 'x-droplet-nonce': nonce, 'x-droplet-sig': sig };
    if (clePub) entetes['x-droplet-cle'] = clePub; else entetes['x-droplet-appareil'] = etat.appareilId;
    const r = await fetch(chemin, { method: methode, headers: entetes, body: texteCorps || undefined });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw Object.assign(new Error(j.erreur || String(r.status)), { code: j.erreur });
    return j;
  }

  function resultat(e, message) {
    const r = $('[data-resultat]');
    r.classList.remove('cache');
    r.dataset.etat = e;
    r.querySelector('[data-texte]').textContent = message;
  }

  async function creer() {
    let paire;
    try {
      paire = await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify']);
    } catch {
      return resultat('refusee', fr ? 'Ce navigateur ne sait pas créer de clé Ed25519. Essayez Chrome, Edge, Firefox ou Safari récents.' : 'This browser cannot create Ed25519 keys. Try a recent Chrome, Edge, Firefox or Safari.');
    }
    const clePub = b64(await crypto.subtle.exportKey('raw', paire.publicKey));
    const cleJwk = await crypto.subtle.exportKey('jwk', paire.privateKey);
    const j = await appeler('POST', '/v1/comptes', { nom: fr ? 'Appareil de test' : 'Test device' }, { cle: paire.privateKey, clePub });
    etat = { appareilId: j.appareil_id, compteId: j.compte_id, cleJwk, clePub };
    ecrire(etat);
    afficher();
  }

  function idDepuis(saisie) {
    const s = (saisie || '').trim();
    const m = s.match(/([A-Za-z0-9_-]{16,})\/?$/);
    return m ? m[1] : null;
  }

  async function charger(id) {
    if (!id) return;
    try {
      demande = await appeler('GET', `/v1/demandes/${id}`);
    } catch (e) {
      return resultat('refusee', (fr ? 'Demande introuvable ou expirée' : 'Request not found or expired') + ` (${e.code || e.message})`);
    }
    codeChoisi = null;
    $('[data-sans-demande]').classList.add('cache');
    $('[data-demande]').classList.remove('cache');
    $('[data-nom]').textContent = demande.client.nom;
    $('[data-hote]').textContent = demande.client.site || '';
    $('[data-logo]').textContent = demande.client.nom.charAt(0).toUpperCase();
    $('[data-titre]').textContent = fr ? `Se connecter à ${demande.client.nom} ?` : `Sign in to ${demande.client.nom}?`;
    const saisie = $('[data-code]');
    saisie.value = '';
    saisie.oninput = () => {
      saisie.value = saisie.value.replace(/\D/g, '').slice(0, 2);
      codeChoisi = saisie.value.length === 2 ? saisie.value : null;
      $('[data-approuver]').disabled = !codeChoisi;
    };
    saisie.focus();
    $('[data-profil]').classList.toggle('cache', !demande.portees.includes('profile'));
  }

  async function decider(decision) {
    const portees = demande.portees.filter((p) => p !== 'profile' || $('[data-accepter-profil]').checked);
    const corps = { decision, code: codeChoisi, portees, pseudo: $('[data-pseudo]').value.trim() || undefined };
    try {
      await appeler('POST', `/v1/demandes/${demande.id}/decision`, corps);
      resultat(decision === 'approuver' ? 'approuvee' : 'refusee',
        decision === 'approuver' ? (fr ? 'Approuvé. Revenez sur l’autre onglet.' : 'Approved. Go back to the other tab.') : (fr ? 'Refusé.' : 'Declined.'));
      $('[data-demande]').classList.add('cache');
      lister();
    } catch (e) {
      resultat('annulee', (fr ? 'Refusé par le service : ' : 'Rejected by the service: ') + (e.code || e.message));
    }
  }

  async function lister() {
    const ul = $('[data-connexions]');
    try {
      const { connexions } = await appeler('GET', '/v1/connexions');
      ul.replaceChildren(...connexions.map((c) => {
        const li = document.createElement('li');
        li.textContent = `${c.nom} — ${c.portees.join(', ')} `;
        const b = document.createElement('button');
        b.className = 'bouton discret';
        b.style.minHeight = '2.2rem';
        b.textContent = fr ? 'Retirer' : 'Remove';
        b.addEventListener('click', async () => { await appeler('DELETE', `/v1/connexions/${encodeURIComponent(c.client_id)}`); lister(); });
        li.append(b);
        return li;
      }));
      if (!connexions.length) ul.innerHTML = `<li class="petit">${fr ? 'Aucun site pour l’instant.' : 'No sites yet.'}</li>`;
    } catch {}
  }

  function afficher() {
    $('[data-pas-de-compte]').classList.toggle('cache', !!etat);
    $('[data-compte]').classList.toggle('cache', !etat);
    if (!etat) return;
    $('[data-id]').textContent = etat.appareilId;
    lister();
    const id = location.hash.slice(1);
    if (id) charger(id);
  }

  $('[data-creer]').addEventListener('click', () => creer().catch((e) => resultat('refusee', e.code || e.message)));
  $('[data-charger]').addEventListener('click', () => charger(idDepuis($('[data-saisie]').value)));
  $('[data-approuver]').addEventListener('click', () => decider('approuver'));
  $('[data-refuser]').addEventListener('click', () => decider('refuser'));
  $('[data-oublier]').addEventListener('click', () => { ecrire(null); etat = null; location.hash = ''; afficher(); });
  addEventListener('hashchange', () => etat && charger(location.hash.slice(1)));
  afficher();
})();
