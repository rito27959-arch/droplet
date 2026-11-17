// ============================================================================
// Stockage PostgreSQL (production et environnement de test).
// Les tables sont créées au démarrage si elles n'existent pas.
//
// Volontairement ABSENTS : e-mail, téléphone, nom réel, adresse IP,
// localisation, modèle exact du téléphone.
// ============================================================================

import pg from 'pg';

const SCHEMA = `
create table if not exists oidc (
  modele      text not null,
  id          text not null,
  donnees     jsonb not null,
  grant_id    text,
  uid         text,
  user_code   text,
  consomme_le bigint,
  expire_le   timestamptz,
  primary key (modele, id)
);
create index if not exists oidc_grant on oidc (grant_id);
create index if not exists oidc_uid on oidc (uid);
create index if not exists oidc_expire on oidc (expire_le);

create table if not exists comptes (
  compte_id text primary key,
  cree_le   timestamptz not null default now()
);

create table if not exists appareils (
  appareil_id text primary key,
  compte_id   text not null references comptes on delete cascade,
  cle_pub     text not null unique,
  nom         text not null,
  ajoute_le   timestamptz not null default now(),
  revoque_le  timestamptz
);

create table if not exists demandes (
  demande_id text primary key,
  uid        text not null,
  client_id  text not null,
  portees    jsonb not null,
  code       text not null,
  codes      jsonb not null,
  etat       text not null,
  cree_le    timestamptz not null,
  expire_le  timestamptz not null,
  compte_id  text,
  appareil_id text,
  portees_acceptees jsonb,
  pseudo     text
);
create index if not exists demandes_uid on demandes (uid);

create table if not exists accords (
  compte_id text not null references comptes on delete cascade,
  client_id text not null,
  portees   jsonb not null,
  pseudo    text,
  accorde_le timestamptz not null default now(),
  primary key (compte_id, client_id)
);

-- La console développeurs : les apps, leurs connexions par jour, leur journal.
create table if not exists apps (
  client_id    text primary key,
  proprietaire text not null,
  statut       text not null default 'test',
  infos        jsonb not null,
  cree_le      timestamptz not null default now(),
  maj_le       timestamptz not null default now()
);
create index if not exists apps_proprietaire on apps (proprietaire);
create table if not exists connexions_jour (
  client_id text not null,
  jour      date not null,
  nombre    integer not null default 0,
  primary key (client_id, jour)
);
create table if not exists journal_apps (
  id        bigserial primary key,
  client_id text not null,
  quand     timestamptz not null default now(),
  quoi      text not null
);
create index if not exists journal_apps_client on journal_apps (client_id, quand desc);

create table if not exists nonces (
  nonce     text primary key,
  expire_le timestamptz not null
);
`;

const versDemande = (r) =>
  r && {
    demandeId: r.demande_id,
    uid: r.uid,
    clientId: r.client_id,
    portees: r.portees,
    code: r.code,
    codes: r.codes,
    etat: r.etat,
    creeLe: r.cree_le.toISOString(),
    expireLe: r.expire_le.toISOString(),
    compteId: r.compte_id,
    appareilId: r.appareil_id,
    porteesAcceptees: r.portees_acceptees,
    pseudo: r.pseudo,
  };

const versAppareil = (r) =>
  r && {
    appareilId: r.appareil_id,
    compteId: r.compte_id,
    clePub: r.cle_pub,
    nom: r.nom,
    ajouteLe: r.ajoute_le.toISOString(),
    revoqueLe: r.revoque_le?.toISOString() ?? null,
  };

const versApp = (r) =>
  r && { clientId: r.client_id, proprietaire: r.proprietaire, statut: r.statut, infos: r.infos, creeLe: r.cree_le.toISOString(), majLe: r.maj_le.toISOString() };

const versAccord = (r) =>
  r && { compteId: r.compte_id, clientId: r.client_id, portees: r.portees, pseudo: r.pseudo, accordeLe: r.accorde_le.toISOString() };

export async function stockagePostgres(url) {
  const pool = new pg.Pool({ connectionString: url, max: 10 });
  await pool.query(SCHEMA);
  const q = (texte, valeurs) => pool.query(texte, valeurs);

  // Ménage régulier : jetons expirés, nonces passés, vieilles demandes.
  const menage = setInterval(() => {
    q(`delete from oidc where expire_le < now()`).catch(() => {});
    q(`delete from nonces where expire_le < now()`).catch(() => {});
    q(`delete from demandes where cree_le < now() - interval '10 minutes'`).catch(() => {});
  }, 60_000);
  menage.unref();

  return {
    nom: 'postgres',

    adaptateur(modele) {
      return {
        async upsert(id, donnees, expireDans) {
          await q(
            `insert into oidc (modele, id, donnees, grant_id, uid, user_code, expire_le)
             values ($1,$2,$3,$4,$5,$6, case when $7::int is null then null else now() + make_interval(secs => $7::int) end)
             on conflict (modele, id) do update set donnees = excluded.donnees, grant_id = excluded.grant_id,
               uid = excluded.uid, user_code = excluded.user_code, expire_le = excluded.expire_le`,
            [modele, id, donnees, donnees.grantId ?? null, donnees.uid ?? null, donnees.userCode ?? null, expireDans ?? null],
          );
        },
        async find(id) {
          const { rows } = await q(
            `select donnees, consomme_le from oidc where modele=$1 and id=$2 and (expire_le is null or expire_le > now())`,
            [modele, id],
          );
          if (!rows[0]) return undefined;
          return rows[0].consomme_le ? { ...rows[0].donnees, consumed: Number(rows[0].consomme_le) } : rows[0].donnees;
        },
        async findByUid(uid) {
          const { rows } = await q(`select donnees from oidc where modele=$1 and uid=$2 and (expire_le is null or expire_le > now())`, [modele, uid]);
          return rows[0]?.donnees;
        },
        async findByUserCode(code) {
          const { rows } = await q(`select donnees from oidc where modele=$1 and user_code=$2 and (expire_le is null or expire_le > now())`, [modele, code]);
          return rows[0]?.donnees;
        },
        async consume(id) {
          await q(`update oidc set consomme_le = extract(epoch from now())::bigint where modele=$1 and id=$2`, [modele, id]);
        },
        async destroy(id) {
          await q(`delete from oidc where modele=$1 and id=$2`, [modele, id]);
        },
        async revokeByGrantId(grantId) {
          await q(`delete from oidc where grant_id=$1`, [grantId]);
        },
      };
    },

    async grantsDe(compteId, clientId) {
      const { rows } = await q(
        `select id from oidc where modele='Grant' and donnees->>'accountId'=$1 and donnees->>'clientId'=$2`,
        [compteId, clientId],
      );
      return rows.map((r) => r.id);
    },

    async creerCompte(compte, appareil) {
      const c = await pool.connect();
      try {
        await c.query('begin');
        await c.query(`insert into comptes (compte_id) values ($1)`, [compte.compteId]);
        await c.query(`insert into appareils (appareil_id, compte_id, cle_pub, nom) values ($1,$2,$3,$4)`, [
          appareil.appareilId, appareil.compteId, appareil.clePub, appareil.nom,
        ]);
        await c.query('commit');
      } catch (e) {
        await c.query('rollback');
        throw e;
      } finally {
        c.release();
      }
    },
    async compte(id) {
      const { rows } = await q(`select compte_id from comptes where compte_id=$1`, [id]);
      return rows[0] ? { compteId: rows[0].compte_id } : null;
    },
    async appareil(id) {
      const { rows } = await q(`select * from appareils where appareil_id=$1`, [id]);
      return versAppareil(rows[0]) ?? null;
    },
    async appareilParCle(clePub) {
      const { rows } = await q(`select * from appareils where cle_pub=$1`, [clePub]);
      return versAppareil(rows[0]) ?? null;
    },
    async appareilsDe(compteId) {
      const { rows } = await q(`select * from appareils where compte_id=$1 order by ajoute_le`, [compteId]);
      return rows.map(versAppareil);
    },
    async revoquerAppareil(id) {
      await q(`update appareils set revoque_le = now() where appareil_id=$1 and revoque_le is null`, [id]);
    },

    async enregistrerDemande(d) {
      await q(
        `insert into demandes (demande_id, uid, client_id, portees, code, codes, etat, cree_le, expire_le)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
        [d.demandeId, d.uid, d.clientId, JSON.stringify(d.portees), d.code, JSON.stringify(d.codes), d.etat, d.creeLe, d.expireLe],
      );
    },
    async demande(id) {
      const { rows } = await q(`select * from demandes where demande_id=$1`, [id]);
      return versDemande(rows[0]) ?? null;
    },
    async demandeParUid(uid) {
      const { rows } = await q(`select * from demandes where uid=$1 order by cree_le desc limit 1`, [uid]);
      return versDemande(rows[0]) ?? null;
    },
    async deciderDemande(id, attendu, ch) {
      const { rowCount } = await q(
        `update demandes set etat=$3, compte_id=coalesce($4, compte_id), appareil_id=coalesce($5, appareil_id),
           portees_acceptees=coalesce($6, portees_acceptees), pseudo=coalesce($7, pseudo)
         where demande_id=$1 and etat=$2`,
        [id, attendu, ch.etat, ch.compteId ?? null, ch.appareilId ?? null, ch.porteesAcceptees ? JSON.stringify(ch.porteesAcceptees) : null, ch.pseudo ?? null],
      );
      return rowCount === 1;
    },
    async purgerDemandes() {},

    async enregistrerAccord(a) {
      await q(
        `insert into accords (compte_id, client_id, portees, pseudo) values ($1,$2,$3,$4)
         on conflict (compte_id, client_id) do update set portees=excluded.portees, pseudo=excluded.pseudo, accorde_le=now()`,
        [a.compteId, a.clientId, JSON.stringify(a.portees), a.pseudo ?? null],
      );
    },
    async accord(compteId, clientId) {
      const { rows } = await q(`select * from accords where compte_id=$1 and client_id=$2`, [compteId, clientId]);
      return versAccord(rows[0]) ?? null;
    },
    async accordsDe(compteId) {
      const { rows } = await q(`select * from accords where compte_id=$1 order by accorde_le desc`, [compteId]);
      return rows.map(versAccord);
    },
    async retirerAccord(compteId, clientId) {
      await q(`delete from accords where compte_id=$1 and client_id=$2`, [compteId, clientId]);
    },

    async nonceNeuf(nonce, expireDans) {
      const { rowCount } = await q(
        `insert into nonces (nonce, expire_le) values ($1, now() + make_interval(secs => $2::int)) on conflict do nothing`,
        [nonce, expireDans],
      );
      return rowCount === 1;
    },

    // ── Console développeurs ─────────────────────────────────────────
    async creerApp(a) {
      await q(`insert into apps (client_id, proprietaire, statut, infos) values ($1,$2,$3,$4)`, [a.clientId, a.proprietaire, a.statut ?? 'test', a.infos]);
    },
    async app(clientId) {
      const { rows } = await q(`select * from apps where client_id=$1`, [clientId]);
      return versApp(rows[0]) ?? null;
    },
    async appsDe(proprietaire) {
      const { rows } = await q(`select * from apps where proprietaire=$1 order by cree_le desc`, [proprietaire]);
      return rows.map(versApp);
    },
    async majApp(clientId, { infos, statut }) {
      await q(`update apps set infos=coalesce($2, infos), statut=coalesce($3, statut), maj_le=now() where client_id=$1`, [clientId, infos ?? null, statut ?? null]);
    },
    async supprimerApp(clientId) {
      await q(`delete from apps where client_id=$1`, [clientId]);
      await q(`delete from accords where client_id=$1`, [clientId]);
      await q(`delete from oidc where donnees->>'clientId'=$1 or (modele='Client' and id=$1)`, [clientId]);
    },
    async noterConnexion(clientId) {
      await q(`insert into connexions_jour (client_id, jour, nombre) values ($1, current_date, 1)
               on conflict (client_id, jour) do update set nombre = connexions_jour.nombre + 1`, [clientId]);
    },
    /** Les connexions des `jours` derniers jours, du plus ancien au plus récent (jours sans connexion inclus). */
    async connexionsParJour(clientId, jours) {
      const { rows } = await q(
        `select to_char(j, 'YYYY-MM-DD') as jour, coalesce(c.nombre, 0) as nombre
         from generate_series(current_date - ($2::int - 1), current_date, interval '1 day') j
         left join connexions_jour c on c.client_id=$1 and c.jour=j::date order by j`,
        [clientId, jours],
      );
      return rows.map((r) => ({ jour: r.jour, nombre: Number(r.nombre) }));
    },
    async utilisateursDe(clientId) {
      const { rows } = await q(`select count(*)::int as n from accords where client_id=$1`, [clientId]);
      return rows[0].n;
    },
    async journaliser(clientId, quoi) {
      await q(`insert into journal_apps (client_id, quoi) values ($1,$2)`, [clientId, quoi]);
    },
    async journalDe(clientId, combien = 50) {
      const { rows } = await q(`select quand, quoi from journal_apps where client_id=$1 order by quand desc, id desc limit $2`, [clientId, combien]);
      return rows.map((r) => ({ quand: r.quand.toISOString(), quoi: r.quoi }));
    },

    /** Efface toutes les données (comptes, appareils, sites, sessions, jetons, apps) ; garde les tables. */
    async viderTout() {
      await q('truncate table oidc, accords, demandes, appareils, comptes, nonces, apps, connexions_jour, journal_apps');
    },
    async fermer() {
      clearInterval(menage);
      await pool.end();
    },
  };
}
