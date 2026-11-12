// ============================================================================
// L'INTERACTION : ce que voit le navigateur pendant qu'on approuve sur le
// téléphone.
//
//   GET  /interaction/:uid           la page (QR + code de correspondance)
//   GET  /interaction/:uid/etat      où en est la demande (interrogé ~1,5 s)
//   POST /interaction/:uid/terminer  une fois approuvée/refusée : la réponse
//                                    au site (code ou access_denied)
//   POST /interaction/:uid/nouvelle  nouveau code après expiration
//   POST /interaction/:uid/annuler   la personne abandonne
//   POST /interaction/:uid/continuer déjà connecté dans ce navigateur : un
//                                    nouveau site en un geste, sans téléphone
//
// Chaque route exige le cookie d'interaction posé par oidc-provider : seul le
// navigateur qui a commencé la connexion peut la terminer.
// ============================================================================

import { randomBytes, randomInt } from 'node:crypto';
import QRCode from 'qrcode';
import { langueDe, pageConnexion, pageContinuer, pageErreur } from './pages.js';

const PORTEES_CONNUES = ['openid', 'profile', 'offline_access'];

function nouveauxCodes() {
  const code = String(randomInt(10, 100));
  const codes = new Set([code]);
  while (codes.size < 3) codes.add(String(randomInt(10, 100)));
  const melange = [...codes];
  for (let i = melange.length - 1; i > 0; i--) {
    const j = randomInt(0, i + 1);
    [melange[i], melange[j]] = [melange[j], melange[i]];
  }
  return { code, codes: melange };
}

export function etatReel(d) {
  if (!d) return 'expiree';
  if ((d.etat === 'attente' || d.etat === 'vue') && Date.parse(d.expireLe) < Date.now()) return 'expiree';
  return d.etat;
}

export function routesInteraction({ fournisseur, stockage, config, repondre, logos }) {
  async function creerDemande(uid, details) {
    const portees = String(details.params.scope || 'openid')
      .split(' ')
      .filter((p) => PORTEES_CONNUES.includes(p));
    const { code, codes } = nouveauxCodes();
    const maintenant = Date.now();
    const d = {
      demandeId: randomBytes(16).toString('base64url'),
      uid,
      clientId: details.params.client_id,
      portees,
      code,
      codes,
      etat: 'attente',
      creeLe: new Date(maintenant).toISOString(),
      expireLe: new Date(maintenant + config.dureeDemande * 1000).toISOString(),
    };
    await stockage.enregistrerDemande(d);
    return d;
  }

  async function details(req, res) {
    try {
      return await fournisseur.interactionDetails(req, res);
    } catch {
      return null;
    }
  }

  return async function interaction(req, res, chemin, url) {
    const m = chemin.match(/^\/interaction\/([A-Za-z0-9_-]+)(?:\/(etat|terminer|nouvelle|annuler|continuer))?$/);
    if (!m) return false;
    const [, uid, action] = m;
    const langue = langueDe(req.headers, url.searchParams.get('langue') || undefined);
    const d = await details(req, res);
    if (!d || d.uid !== uid) {
      if (!action) repondre(res, 400, pageErreur({ langue, detail: 'session_interaction_absente', test: config.environnementDeTest }), 'html');
      else repondre(res, 400, { erreur: 'session_interaction_absente' });
      return true;
    }

    // Déjà connecté dans ce navigateur (cookie de session, 14 jours) et un
    // appareil toujours actif : « Continuer vers … » sans sortir le téléphone.
    const sessionActive = async () => {
      const compteId = d.session?.accountId;
      if (!compteId || d.prompt?.name !== 'consent') return null;
      const appareils = (await stockage.appareilsDe(compteId)).filter((a) => !a.revoqueLe);
      return appareils.length ? { compteId, appareil: appareils[0] } : null;
    };

    // ── La page ──────────────────────────────────────────────────────
    if (!action && req.method === 'GET') {
      const pageLangue = langueDe(req.headers, url.searchParams.get('langue') || d.params.ui_locales);
      const deja = url.searchParams.get('autre') ? null : await sessionActive();
      if (deja) {
        const client = await fournisseur.Client.find(d.params.client_id);
        const portees = String(d.params.scope || 'openid').split(' ').filter((p) => PORTEES_CONNUES.includes(p));
        repondre(
          res,
          200,
          pageContinuer({ langue: pageLangue, test: config.environnementDeTest, uid, client, logo: await logos.adresse(client), portees, appareil: deja.appareil.nom, depuis: deja.appareil.ajouteLe }),
          'html',
        );
        return true;
      }
      let demande = await stockage.demandeParUid(uid);
      if (!demande || etatReel(demande) === 'expiree') demande = await creerDemande(uid, d);
      const client = await fournisseur.Client.find(d.params.client_id);
      const lienApp = `${config.emetteur}/a/${demande.demandeId}`;
      const qrSvg = (await QRCode.toString(lienApp, { type: 'svg', errorCorrectionLevel: 'Q', margin: 0, color: { dark: '#0a1a24', light: '#ffffff' } }))
        .replace('<svg ', '<svg class="code" role="img" aria-label="QR" ');
      repondre(
        res,
        200,
        pageConnexion({ langue: pageLangue, test: config.environnementDeTest, uid, demande, client, logo: await logos.adresse(client), qrSvg, lienApp }),
        'html',
      );
      return true;
    }

    if (req.method !== 'POST' && action !== 'etat') {
      repondre(res, 405, { erreur: 'methode' });
      return true;
    }

    if (action === 'continuer') {
      const deja = await sessionActive();
      if (!deja) {
        res.writeHead(303, { location: `/interaction/${uid}` });
        res.end();
        return true;
      }
      const form = new URLSearchParams(await lireCorps(req));
      const portees = String(d.params.scope || 'openid').split(' ').filter((p) => PORTEES_CONNUES.includes(p));
      const acceptees = portees.filter((p) => p !== 'profile' || form.get('profil') === '1');
      if (!acceptees.includes('openid')) acceptees.unshift('openid');
      const pseudo = acceptees.includes('profile') && form.get('pseudo') ? form.get('pseudo').trim().slice(0, 40) || null : null;
      const grant = new fournisseur.Grant({ accountId: deja.compteId, clientId: d.params.client_id });
      for (const p of portees) {
        if (acceptees.includes(p)) grant.addOIDCScope(p);
        else grant.rejectOIDCScope(p);
      }
      const grantId = await grant.save();
      await stockage.enregistrerAccord({ compteId: deja.compteId, clientId: d.params.client_id, portees: acceptees, pseudo });
      const redirection = await fournisseur.interactionResult(req, res, { consent: { grantId } }, { mergeWithLastSubmission: true });
      res.writeHead(303, { location: redirection });
      res.end();
      return true;
    }

    const demande = await stockage.demandeParUid(uid);

    if (action === 'etat') {
      repondre(res, 200, { etat: etatReel(demande) });
      return true;
    }

    if (action === 'nouvelle') {
      if (!demande || ['attente', 'vue', 'expiree'].includes(etatReel(demande))) {
        if (demande && etatReel(demande) !== 'expiree') await stockage.deciderDemande(demande.demandeId, demande.etat, { etat: 'remplacee' });
        await creerDemande(uid, d);
      }
      repondre(res, 200, { ok: true });
      return true;
    }

    if (action === 'annuler') {
      if (demande) await stockage.deciderDemande(demande.demandeId, demande.etat, { etat: 'abandonnee' });
      const redirection = await fournisseur.interactionResult(req, res, { error: 'access_denied', error_description: 'abandon' }, { mergeWithLastSubmission: false });
      res.writeHead(303, { location: redirection });
      res.end();
      return true;
    }

    // ── terminer ─────────────────────────────────────────────────────
    const e = etatReel(demande);
    let resultat;
    if (e === 'approuvee') {
      // Une seule fois : approuvee → terminee.
      if (!(await stockage.deciderDemande(demande.demandeId, 'approuvee', { etat: 'terminee' }))) {
        repondre(res, 409, { erreur: 'deja_terminee' });
        return true;
      }
      const grant = new fournisseur.Grant({ accountId: demande.compteId, clientId: demande.clientId });
      for (const p of demande.portees) {
        if (demande.porteesAcceptees.includes(p)) grant.addOIDCScope(p);
        else grant.rejectOIDCScope(p);
      }
      const grantId = await grant.save();
      resultat = { login: { accountId: demande.compteId, amr: ['hwk', 'user'], remember: true }, consent: { grantId } };
    } else if (e === 'refusee' || e === 'annulee') {
      await stockage.deciderDemande(demande.demandeId, demande.etat, { etat: 'terminee' });
      resultat = { error: 'access_denied', error_description: e === 'annulee' ? 'mauvais_code' : 'refus' };
    } else {
      repondre(res, 409, { erreur: 'pas_encore', etat: e });
      return true;
    }
    const redirection = await fournisseur.interactionResult(req, res, resultat, { mergeWithLastSubmission: false });
    repondre(res, 200, { redirection });
    return true;
  };
}

// Corps d'un formulaire (petit : quelques champs).
function lireCorps(req) {
  return new Promise((ok, ko) => {
    let corps = '';
    req.setEncoding('utf8');
    req.on('data', (x) => {
      corps += x;
      if (corps.length > 4096) { ko(new Error('corps_trop_grand')); req.destroy(); }
    });
    req.on('end', () => ok(corps));
    req.on('error', ko);
  });
}
