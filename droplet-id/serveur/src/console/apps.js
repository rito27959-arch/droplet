// ============================================================================
// Les apps de la console : vérification de ce que le développeur saisit, et
// traduction en « client » OpenID Connect pour oidc-provider.
//
// Une app de la console est enregistrée comme client dynamique (modèle
// `Client` du stockage) : oidc-provider la lit à chaque connexion, une
// modification prend donc effet tout de suite, sans redémarrage.
// ============================================================================

import { randomBytes } from 'node:crypto';

export const TYPES = {
  serveur: { methode: 'client_secret_basic', application: 'web' },
  navigateur: { methode: 'none', application: 'web' },
  mobile: { methode: 'none', application: 'native' },
};

export const MAX_APPS = 20;
export const MAX_ADRESSES = 10;

export const nouvelIdentifiant = () => `app_${randomBytes(12).toString('base64url')}`;
export const nouveauSecret = () => `dsec_${randomBytes(32).toString('base64url')}`;

const local = (u) => ['localhost', '127.0.0.1', '[::1]'].includes(u.hostname);

/** Une adresse web (https, ou http pour localhost seulement). */
function adresseWeb(texte, { obligatoire = false } = {}) {
  const t = String(texte ?? '').trim();
  if (!t) return obligatoire ? { erreur: 'obligatoire' } : { valeur: undefined };
  let u;
  try {
    u = new URL(t);
  } catch {
    return { erreur: 'adresse_invalide' };
  }
  if (u.protocol === 'https:' || (u.protocol === 'http:' && local(u))) {
    if (u.username || u.password) return { erreur: 'adresse_invalide' };
    return { valeur: u.href };
  }
  return { erreur: 'https_obligatoire' };
}

/** Une adresse de retour. Mobile : aussi un schéma inversé (com.exemple.app:/retour). */
function adresseRetour(texte, type) {
  let u;
  try {
    u = new URL(texte);
  } catch {
    return { erreur: 'adresse_invalide' };
  }
  if (u.hash) return { erreur: 'sans_fragment' };
  if (type === 'mobile' && /^[a-z][a-z0-9+.-]*\.[a-z0-9+.-]+:$/.test(u.protocol) && !u.host) return { valeur: texte.trim() };
  return adresseWeb(texte);
}

const lignes = (t) =>
  String(t ?? '')
    .split(/[\n,]+/)
    .map((x) => x.trim())
    .filter(Boolean);

/**
 * Vérifie le formulaire. Rend { infos } ou { erreurs: { champ: code } }.
 * `infos` est ce que la console garde (et ce qu'elle réaffiche).
 */
export function verifierInfos(f, avant = {}) {
  const erreurs = {};
  const infos = { ...avant };

  if (f.nom !== undefined) {
    const nom = String(f.nom).trim().replace(/\s+/g, ' ');
    if (nom.length < 2 || nom.length > 40) erreurs.nom = 'longueur_nom';
    infos.nom = nom;
  }
  if (f.type !== undefined) {
    if (!TYPES[f.type]) erreurs.type = 'type_inconnu';
    infos.type = f.type;
  }
  for (const [champ, cle] of [
    ['site', 'site'],
    ['logo', 'logo'],
    ['politique', 'politique'],
    ['conditions', 'conditions'],
  ]) {
    if (f[champ] === undefined) continue;
    const r = adresseWeb(f[champ], { obligatoire: champ === 'site' });
    if (r.erreur) erreurs[champ] = r.erreur;
    else infos[cle] = r.valeur;
  }
  if (f.profil !== undefined) infos.profil = f.profil === '1' || f.profil === true;

  for (const [champ, obligatoire] of [
    ['redirections', true],
    ['deconnexions', false],
  ]) {
    if (f[champ] === undefined) continue;
    const liste = [...new Set(lignes(f[champ]))];
    if (obligatoire && !liste.length) erreurs[champ] = 'obligatoire';
    else if (liste.length > MAX_ADRESSES) erreurs[champ] = 'trop_d_adresses';
    else {
      const ok = [];
      for (const a of liste) {
        const r = champ === 'redirections' ? adresseRetour(a, infos.type) : adresseWeb(a);
        if (r.erreur) {
          erreurs[champ] = `${r.erreur}:${a}`;
          break;
        }
        ok.push(r.valeur);
      }
      infos[champ] = ok;
    }
  }
  return Object.keys(erreurs).length ? { erreurs, infos } : { infos };
}

/** Les hôtes des adresses de retour (pour le « secteur » pairwise). */
export const hotesDe = (infos) => new Set((infos.redirections ?? []).map((a) => new URL(a).host));

/**
 * Les métadonnées OpenID Connect du client.
 * `secret` : pour une app « serveur » seulement.
 */
export function metadonnees(clientId, infos, { secret, emetteur }) {
  const t = TYPES[infos.type];
  const m = {
    client_id: clientId,
    client_name: infos.nom,
    client_uri: infos.site,
    redirect_uris: infos.redirections,
    post_logout_redirect_uris: infos.deconnexions ?? [],
    application_type: t.application,
    token_endpoint_auth_method: t.methode,
    grant_types: ['authorization_code', 'refresh_token'],
    response_types: ['code'],
    subject_type: 'pairwise',
    id_token_signed_response_alg: 'ES256',
  };
  if (infos.logo) m.logo_uri = infos.logo;
  if (infos.politique) m.policy_uri = infos.politique;
  if (infos.conditions) m.tos_uri = infos.conditions;
  if (t.methode !== 'none') m.client_secret = secret;
  // Plusieurs domaines (ex. localhost + le vrai site) : OpenID exige un
  // « sector_identifier_uri ». Le service le publie lui-même (/console/secteur/…) ;
  // l'identifiant de la personne est calculé à partir de l'app, pas du domaine.
  if (hotesDe(infos).size > 1) m.sector_identifier_uri = `${emetteur}/console/secteur/${clientId}`;
  return m;
}
