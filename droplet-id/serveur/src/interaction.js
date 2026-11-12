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
//
// Chaque route exige le cookie d'interaction posé par oidc-provider : seul le
// navigateur qui a commencé la connexion peut la terminer.
// ============================================================================

import { randomBytes, randomInt } from 'node:crypto';
import QRCode from 'qrcode';
import { langueDe, pageConnexion, pageErreur } from './pages.js';

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

export function routesInteraction({ fournisseur, stockage, config, repondre }) {
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
    const m = chemin.match(/^\/interaction\/([A-Za-z0-9_-]+)(?:\/(etat|terminer|nouvelle|annuler))?$/);
    if (!m) return false;
    const [, uid, action] = m;
    const langue = langueDe(req.headers, url.searchParams.get('langue') || undefined);
    const d = await details(req, res);
    if (!d || d.uid !== uid) {
      if (!action) repondre(res, 400, pageErreur({ langue, detail: 'session_interaction_absente', test: config.environnementDeTest }), 'html');
      else repondre(res, 400, { erreur: 'session_interaction_absente' });
      return true;
    }

    // ── La page ──────────────────────────────────────────────────────
    if (!action && req.method === 'GET') {
      let demande = await stockage.demandeParUid(uid);
      if (!demande || etatReel(demande) === 'expiree') demande = await creerDemande(uid, d);
      const client = await fournisseur.Client.find(d.params.client_id);
      const lienApp = `${config.emetteur}/a/${demande.demandeId}`;
      const qrSvg = (await QRCode.toString(lienApp, { type: 'svg', errorCorrectionLevel: 'Q', margin: 0, color: { dark: '#0a1a24', light: '#ffffff' } }))
        .replace('<svg ', '<svg class="code" role="img" aria-label="QR" ');
      repondre(
        res,
        200,
        pageConnexion({ langue: langueDe(req.headers, url.searchParams.get('langue') || d.params.ui_locales), test: config.environnementDeTest, uid, demande, client, qrSvg, lienApp }),
        'html',
      );
      return true;
    }

    if (req.method !== 'POST' && action !== 'etat') {
      repondre(res, 405, { erreur: 'methode' });
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
      resultat = { login: { accountId: demande.compteId, amr: ['hwk', 'user'], remember: false }, consent: { grantId } };
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
