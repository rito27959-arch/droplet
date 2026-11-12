// ============================================================================
// L'API DES APPAREILS (/v1) — toutes les requêtes sont signées (signature.js).
//
//   POST   /v1/comptes                    créer un compte (premier appareil)
//   GET    /v1/demandes/:id               lire une demande de connexion
//   POST   /v1/demandes/:id/decision      approuver ou refuser
//   GET    /v1/connexions                 les sites connectés
//   DELETE /v1/connexions/:client         retirer un site (révoque ses jetons)
//   GET    /v1/appareils                  les appareils du compte
//   DELETE /v1/appareils/:id              retirer un appareil
// ============================================================================

import { randomBytes } from 'node:crypto';
import { ErreurSignature, verifierRequete, clePublique } from './signature.js';
import { etatReel } from './interaction.js';

const MAX_CORPS = 16 * 1024;

async function lireCorps(req) {
  const morceaux = [];
  let taille = 0;
  for await (const m of req) {
    taille += m.length;
    if (taille > MAX_CORPS) throw new ErreurSignature('corps_trop_gros');
    morceaux.push(m);
  }
  return Buffer.concat(morceaux).toString('utf8');
}

export function routesApi({ fournisseur, stockage, config, repondre }) {
  const nomClient = async (id) => {
    const c = await fournisseur.Client.find(id);
    return c ? { nom: c.clientName || id, site: c.clientUri ? new URL(c.clientUri).host : new URL(c.redirectUris[0]).host, logo: c.logoUri ?? null } : null;
  };

  return async function api(req, res, chemin) {
    if (!chemin.startsWith('/v1/')) return false;
    let corps = '';
    let qui;
    try {
      corps = await lireCorps(req);
      qui = await verifierRequete({
        methode: req.method,
        chemin,
        entetes: req.headers,
        corps,
        stockage,
        fenetre: config.fenetreSignature,
      });
    } catch (e) {
      repondre(res, e instanceof ErreurSignature ? 401 : 400, { erreur: e.code ?? 'requete_invalide' });
      return true;
    }
    let donnees = {};
    if (corps) {
      try {
        donnees = JSON.parse(corps);
      } catch {
        repondre(res, 400, { erreur: 'json_invalide' });
        return true;
      }
    }

    // ── Créer un compte ──────────────────────────────────────────────
    if (req.method === 'POST' && chemin === '/v1/comptes') {
      if (!qui.clePub) return repondre(res, 400, { erreur: 'utiliser_x_droplet_cle' }), true;
      clePublique(qui.clePub);
      if (await stockage.appareilParCle(qui.clePub)) return repondre(res, 409, { erreur: 'cle_deja_enregistree' }), true;
      const compteId = randomBytes(16).toString('base64url');
      const appareilId = randomBytes(16).toString('base64url');
      const nom = String(donnees.nom ?? 'Appareil').slice(0, 40);
      await stockage.creerCompte({ compteId }, { appareilId, compteId, clePub: qui.clePub, nom });
      return repondre(res, 201, { compte_id: compteId, appareil_id: appareilId }), true;
    }

    if (!qui.appareil) return repondre(res, 401, { erreur: 'appareil_requis' }), true;
    const { compteId } = qui.appareil;

    // ── Lire une demande ─────────────────────────────────────────────
    let m = chemin.match(/^\/v1\/demandes\/([A-Za-z0-9_-]{16,64})$/);
    if (m && req.method === 'GET') {
      const d = await stockage.demande(m[1]);
      const e = etatReel(d);
      if (!d || (e !== 'attente' && e !== 'vue')) return repondre(res, 410, { erreur: 'demande_expiree' }), true;
      if (d.etat === 'attente') await stockage.deciderDemande(d.demandeId, 'attente', { etat: 'vue' });
      return repondre(res, 200, {
        id: d.demandeId,
        client: { id: d.clientId, ...(await nomClient(d.clientId)) },
        portees: d.portees,
        // Le nombre affiché sur l'écran de connexion se TAPE sur le téléphone
        // (2 chiffres : 1 chance sur 90 au hasard), il n'est jamais envoyé ici.
        chiffres_a_taper: 2,
        expire_le: d.expireLe,
      }), true;
    }

    // ── Décider ──────────────────────────────────────────────────────
    m = chemin.match(/^\/v1\/demandes\/([A-Za-z0-9_-]{16,64})\/decision$/);
    if (m && req.method === 'POST') {
      const d = await stockage.demande(m[1]);
      const e = etatReel(d);
      if (!d || (e !== 'attente' && e !== 'vue')) return repondre(res, 410, { erreur: 'demande_expiree' }), true;

      if (donnees.decision === 'refuser') {
        await stockage.deciderDemande(d.demandeId, d.etat, { etat: 'refusee', compteId, appareilId: qui.appareil.appareilId });
        return repondre(res, 200, { etat: 'refusee' }), true;
      }
      if (donnees.decision !== 'approuver') return repondre(res, 400, { erreur: 'decision_invalide' }), true;

      // Le code de correspondance : une seule chance.
      if (String(donnees.code) !== d.code) {
        await stockage.deciderDemande(d.demandeId, d.etat, { etat: 'annulee' });
        return repondre(res, 403, { erreur: 'mauvais_code' }), true;
      }
      const acceptees = ['openid', ...(Array.isArray(donnees.portees) ? donnees.portees : []).filter((p) => d.portees.includes(p) && p !== 'openid')];
      const pseudo = acceptees.includes('profile') && donnees.pseudo ? String(donnees.pseudo).trim().slice(0, 40) : null;
      const ok = await stockage.deciderDemande(d.demandeId, d.etat, {
        etat: 'approuvee',
        compteId,
        appareilId: qui.appareil.appareilId,
        porteesAcceptees: acceptees,
        pseudo,
      });
      if (!ok) return repondre(res, 409, { erreur: 'deja_decidee' }), true;
      await stockage.enregistrerAccord({ compteId, clientId: d.clientId, portees: acceptees, pseudo });
      return repondre(res, 200, { etat: 'approuvee' }), true;
    }

    // ── Sites connectés ──────────────────────────────────────────────
    if (req.method === 'GET' && chemin === '/v1/connexions') {
      const accords = await stockage.accordsDe(compteId);
      const connexions = [];
      for (const a of accords) connexions.push({ client_id: a.clientId, nom: (await nomClient(a.clientId))?.nom ?? a.clientId, portees: a.portees, accorde_le: a.accordeLe });
      return repondre(res, 200, { connexions }), true;
    }
    m = chemin.match(/^\/v1\/connexions\/([^/]+)$/);
    if (m && req.method === 'DELETE') {
      const clientId = decodeURIComponent(m[1]);
      for (const g of await stockage.grantsDe(compteId, clientId)) {
        await stockage.adaptateur('Grant').revokeByGrantId(g); // jetons émis avec cet accord
        await stockage.adaptateur('Grant').destroy(g);
      }
      await stockage.retirerAccord(compteId, clientId);
      return repondre(res, 200, { ok: true }), true;
    }

    // ── Appareils ────────────────────────────────────────────────────
    if (req.method === 'GET' && chemin === '/v1/appareils') {
      const liste = await stockage.appareilsDe(compteId);
      return repondre(res, 200, {
        appareils: liste.map((a) => ({ id: a.appareilId, nom: a.nom, ajoute_le: a.ajouteLe, revoque_le: a.revoqueLe, celui_ci: a.appareilId === qui.appareil.appareilId })),
      }), true;
    }
    m = chemin.match(/^\/v1\/appareils\/([A-Za-z0-9_-]+)$/);
    if (m && req.method === 'DELETE') {
      const a = await stockage.appareil(m[1]);
      if (!a || a.compteId !== compteId) return repondre(res, 404, { erreur: 'appareil_inconnu' }), true;
      await stockage.revoquerAppareil(a.appareilId);
      return repondre(res, 200, { ok: true }), true;
    }

    repondre(res, 404, { erreur: 'introuvable' });
    return true;
  };
}
