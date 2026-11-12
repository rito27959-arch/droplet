// ============================================================================
// Stockage en mémoire : pour le développement et les tests seulement.
// Même interface que postgres.js.
// ============================================================================

const maintenant = () => Math.floor(Date.now() / 1000);

export function stockageMemoire() {
  const oidc = new Map(); // `${modele}:${id}` → { donnees, expire, grantId, uid, userCode, consomme }
  const comptes = new Map();
  const appareils = new Map();
  const demandes = new Map();
  const accords = new Map(); // `${compte}:${client}` → accord
  const nonces = new Map();

  const vivant = (e) => e && (!e.expire || e.expire > maintenant());

  return {
    nom: 'mémoire',

    // ── Les modèles d'oidc-provider ──────────────────────────────────
    adaptateur(modele) {
      const cle = (id) => `${modele}:${id}`;
      return {
        async upsert(id, donnees, expireDans) {
          oidc.set(cle(id), {
            donnees,
            expire: expireDans ? maintenant() + expireDans : null,
            grantId: donnees.grantId ?? null,
            uid: donnees.uid ?? null,
            userCode: donnees.userCode ?? null,
          });
        },
        async find(id) {
          const e = oidc.get(cle(id));
          if (!vivant(e)) return undefined;
          return e.consomme ? { ...e.donnees, consumed: e.consomme } : e.donnees;
        },
        async findByUid(uid) {
          for (const [k, e] of oidc) if (k.startsWith(`${modele}:`) && e.uid === uid && vivant(e)) return e.donnees;
          return undefined;
        },
        async findByUserCode(code) {
          for (const [k, e] of oidc) if (k.startsWith(`${modele}:`) && e.userCode === code && vivant(e)) return e.donnees;
          return undefined;
        },
        async consume(id) {
          const e = oidc.get(cle(id));
          if (e) e.consomme = maintenant();
        },
        async destroy(id) {
          oidc.delete(cle(id));
        },
        async revokeByGrantId(grantId) {
          for (const [k, e] of oidc) if (e.grantId === grantId) oidc.delete(k);
        },
      };
    },

    async grantsDe(compteId, clientId) {
      const ids = [];
      for (const [k, e] of oidc) {
        if (k.startsWith('Grant:') && e.donnees.accountId === compteId && e.donnees.clientId === clientId) ids.push(k.slice(6));
      }
      return ids;
    },

    // ── Comptes et appareils ────────────────────────────────────────
    async creerCompte(compte, appareil) {
      comptes.set(compte.compteId, compte);
      appareils.set(appareil.appareilId, appareil);
    },
    async compte(id) {
      return comptes.get(id) ?? null;
    },
    async appareil(id) {
      return appareils.get(id) ?? null;
    },
    async appareilParCle(clePub) {
      for (const a of appareils.values()) if (a.clePub === clePub) return a;
      return null;
    },
    async appareilsDe(compteId) {
      return [...appareils.values()].filter((a) => a.compteId === compteId);
    },
    async revoquerAppareil(id) {
      const a = appareils.get(id);
      if (a && !a.revoqueLe) a.revoqueLe = new Date().toISOString();
    },

    // ── Demandes de connexion ───────────────────────────────────────
    async enregistrerDemande(d) {
      demandes.set(d.demandeId, { ...d });
    },
    async demande(id) {
      const d = demandes.get(id);
      return d ? { ...d } : null;
    },
    async demandeParUid(uid) {
      let derniere = null;
      for (const d of demandes.values()) if (d.uid === uid && (!derniere || d.creeLe > derniere.creeLe)) derniere = d;
      return derniere ? { ...derniere } : null;
    },
    /** Change l'état seulement s'il est encore `attendu` (pas de double décision). */
    async deciderDemande(id, attendu, changements) {
      const d = demandes.get(id);
      if (!d || d.etat !== attendu) return false;
      Object.assign(d, changements);
      return true;
    },
    async purgerDemandes() {
      const limite = Date.now() - 10 * 60 * 1000;
      for (const [k, d] of demandes) if (Date.parse(d.creeLe) < limite) demandes.delete(k);
    },

    // ── Accords (sites connectés) ───────────────────────────────────
    async enregistrerAccord(a) {
      accords.set(`${a.compteId}:${a.clientId}`, { ...a });
    },
    async accord(compteId, clientId) {
      return accords.get(`${compteId}:${clientId}`) ?? null;
    },
    async accordsDe(compteId) {
      return [...accords.values()].filter((a) => a.compteId === compteId);
    },
    async retirerAccord(compteId, clientId) {
      accords.delete(`${compteId}:${clientId}`);
    },

    // ── Anti-rejeu ──────────────────────────────────────────────────
    /** Vrai si le nonce est neuf (et le retient), faux s'il a déjà servi. */
    async nonceNeuf(nonce, expireDans) {
      const t = maintenant();
      for (const [k, v] of nonces) if (v < t) nonces.delete(k);
      if (nonces.has(nonce)) return false;
      nonces.set(nonce, t + expireDans);
      return true;
    },

    async fermer() {},
  };
}
