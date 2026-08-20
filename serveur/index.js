/**
 * ════════════════════════════════════════════════════════════════════
 * LE DÉLIVREUR DE LICENCES DROPLET
 * ────────────────────────────────────────────────────────────────────
 * Un Cloudflare Worker. Il fait une seule chose : constater qu'un
 * paiement Mobile Money est réellement arrivé, puis signer la licence
 * correspondante.
 *
 * ── ⚠️ CE SERVEUR NE TOUCHE PAS AU MESH ────────────────────────────
 *
 * Droplet fait passer ses messages de téléphone en téléphone, sans
 * aucun serveur. Cela ne change pas, et il faut que ce soit dit
 * clairement : ce Worker ne voit jamais un message, ne connaît aucun
 * contact, n'a aucune clé de conversation. Il encaisse, et il signe.
 * Éteignez-le : la messagerie continue de fonctionner à l'identique,
 * seules les nouvelles licences cessent d'être délivrées.
 *
 * ── ⚠️ POURQUOI IL FAUT UN SERVEUR POUR ÇA, ET PAS AILLEURS ─────────
 *
 * Vérifier un paiement demande de parler à CamPay avec une clé
 * secrète. Mettre cette clé dans l'application serait la publier :
 * un APK se décompresse, les chaînes s'y lisent. N'importe qui
 * pourrait alors interroger votre compte marchand, voire déclencher
 * des encaissements en votre nom.
 *
 * Et laisser l'application dire elle-même « j'ai payé » ne vaut rien :
 * c'est le téléphone de l'acheteur, il en fait ce qu'il veut.
 *
 * La seule chose qui ne peut pas être falsifiée est une SIGNATURE
 * fabriquée ailleurs. D'où ce Worker : il est le seul à détenir la
 * clé privée, et l'application ne fait que vérifier — exactement
 * comme avant, avec le même code.
 *
 * ── LES QUATRE VÉRIFICATIONS QUI COMPTENT ──────────────────────────
 *
 * 1. La transaction est bien SUCCESSFUL chez CamPay ;
 * 2. le MONTANT reçu correspond à l'offre demandée — sans quoi on
 *    paierait 5 F pour réclamer une licence Pro ;
 * 3. l'offre et l'appareil sont relus depuis la RÉFÉRENCE ENREGISTRÉE
 *    CHEZ L'OPÉRATEUR au moment de l'encaissement, jamais depuis ce que le
 *    téléphone raconte au moment de réclamer ;
 * 4. la référence n'a pas déjà servi (voir le KV `DEJA_SERVI`).
 *
 * ── ⚠️ POURQUOI FAPSHI ET PLUS CAMPAY ──────────────────────────────
 *
 * La quasi-totalité des passerelles Mobile Money camerounaises —
 * CamPay, CinetPay, Monetbil, Tranzak — exigent une ENTREPRISE
 * LÉGALEMENT ENREGISTRÉE. Pour une application qu'une personne écrit
 * seule, c'est un mur : registre du commerce, statuts, numéro
 * contribuable, avant d'avoir encaissé le premier billet de 500 F.
 *
 * Fapshi accepte explicitement l'option « not legally registered » :
 * l'activation se fait avec une pièce d'identité (recto, verso, et un
 * selfie en la tenant). C'est la seule raison de ce changement — le
 * reste du fichier est identique, parce que la sécurité ne dépendait
 * jamais de la passerelle.
 *
 * ── Trois différences avec CamPay, toutes vérifiées contre l'API ────
 *
 *   • le numéro se donne en NEUF CHIFFRES LOCAUX (678963221), pas en
 *     237678963221 — l'API refuse le format international ;
 *   • le montant minimum est de 100 XAF ;
 *   • l'identifiant de transaction s'appelle `transId`, et l'état se
 *     lit sur `GET /payment-status/{transId}`.
 *
 * ── Déploiement ────────────────────────────────────────────────────
 *   cd serveur
 *   npx wrangler kv namespace create DEJA_SERVI
 *   npx wrangler secret put FAPSHI_USER      # apiuser
 *   npx wrangler secret put FAPSHI_KEY       # apikey
 *   npx wrangler secret put LICENCE_D        # graine privée, base64url
 *   npx wrangler secret put LICENCE_X        # clé publique, base64url
 *   npx wrangler deploy
 * ════════════════════════════════════════════════════════════════════
 */

const PREFIXE = 'DROP1';

/**
 * Les offres, et leur prix EXACT en francs CFA.
 *
 * ⚠️ Fapshi refuse toute transaction sous 100 XAF. Les deux offres
 * passent largement, mais une future offre à 50 F échouerait chez
 * l'opérateur avec un message que personne ne comprendrait.
 */
const OFFRES = {
  pack: 500,
  pro: 1000,
};

const MONTANT_MINIMUM = 100;

/** Combien de temps une demande de paiement reste réclamable. */
const FENETRE_SECONDES = 60 * 30;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // L'application est native : pas de navigateur, donc pas de CORS à
    // ouvrir. On le laisse fermé — c'est une surface d'attaque en moins.
    if (request.method === 'OPTIONS') {
      return json({ erreur: 'non pris en charge' }, 405);
    }

    try {
      switch (url.pathname) {
        case '/payer':
          return await demanderPaiement(request, env);
        case '/licence':
          return await reclamerLicence(request, env);
        case '/sante':
          return json({ ok: true });
        default:
          return json({ erreur: 'introuvable' }, 404);
      }
    } catch (e) {
      // On ne renvoie JAMAIS le détail d'une erreur interne : il
      // renseignerait gratuitement quelqu'un qui cherche à contourner.
      console.error(e);
      return json({ erreur: 'panne interne' }, 500);
    }
  },
};

// ══════════════════════════════════════════════════════════════════
//  1. DEMANDER LE PAIEMENT
// ══════════════════════════════════════════════════════════════════

async function demanderPaiement(request, env) {
  if (request.method !== 'POST') return json({ erreur: 'méthode' }, 405);

  const corps = await request.json().catch(() => null);
  if (!corps) return json({ erreur: 'corps illisible' }, 400);

  const appareil = normaliserAppareil(corps.appareil);
  const offre = String(corps.offre || '');
  const telephone = normaliserTelephone(corps.telephone);

  if (!appareil) return json({ erreur: 'code appareil invalide' }, 400);
  if (!(offre in OFFRES)) return json({ erreur: 'offre inconnue' }, 400);
  if (OFFRES[offre] < MONTANT_MINIMUM) {
    // Garde-fou pour le jour où une offre bon marché serait ajoutée :
    // mieux vaut refuser ici, avec un message clair dans les journaux,
    // que laisser l'opérateur refuser plus loin.
    console.error(`offre ${offre} sous le minimum de ${MONTANT_MINIMUM} XAF`);
    return json({ erreur: 'offre mal configurée' }, 500);
  }
  if (!telephone) {
    return json({ erreur: 'numéro invalide — attendu 6XXXXXXXX' }, 400);
  }

  // ⚠️ L'APPAREIL ET L'OFFRE SONT SCELLÉS DANS LA RÉFÉRENCE, ICI.
  //
  // C'est la pièce qui empêche de payer le pack et de réclamer Pro :
  // au moment de délivrer la licence, on ne relit PAS ce que le
  // téléphone demande, on relit ce qui a été enregistré chez CamPay
  // à l'instant de l'encaissement. Le client ne peut plus rien
  // changer après coup.
  // Des tirets plutôt que des deux-points : `externalId` voyage dans
  // des URL et des tableaux de bord, et un séparateur sans surprise
  // évite d'avoir à l'échapper partout.
  const externe = `${appareil}-${offre}-${Date.now()}`;

  const rep = await fapshi(env, 'direct-pay', {
    method: 'POST',
    body: JSON.stringify({
      amount: OFFRES[offre],
      phone: telephone,
      externalId: externe,
      message: offre === 'pro' ? 'Droplet Pro' : 'Droplet — pack',
    }),
  });

  const data = await rep.json().catch(() => ({}));
  if (!rep.ok || !data.transId) {
    console.error('direct-pay refusé', rep.status, JSON.stringify(data));
    // Le message de l'opérateur est renvoyé tel quel quand il est
    // compréhensible — « numéro MTN ou Orange invalide » aide la
    // personne, « erreur 400 » ne l'aide pas.
    return json({ erreur: data.message || 'le paiement n\'a pas pu être lancé' }, 502);
  }

  return json({ reference: data.transId });
}

// ══════════════════════════════════════════════════════════════════
//  2. RÉCLAMER LA LICENCE
// ══════════════════════════════════════════════════════════════════

async function reclamerLicence(request, env) {
  const url = new URL(request.url);
  const reference = (url.searchParams.get('reference') || '').trim();
  if (!/^[A-Za-z0-9_-]{6,80}$/.test(reference)) {
    return json({ erreur: 'référence invalide' }, 400);
  }

  const rep = await fapshi(env, `payment-status/${encodeURIComponent(reference)}`);
  if (!rep.ok) return json({ erreur: 'transaction introuvable' }, 404);

  const t = await rep.json();
  const statut = String(t.status || '').toUpperCase();

  // ⚠️ CREATED ET PENDING SONT DEUX ATTENTES, PAS UN ÉCHEC.
  // `CREATED` signifie que la demande est partie mais que l'invite n'a
  // pas encore atteint le téléphone ; `PENDING`, que la personne ne l'a
  // pas encore validée. Traiter l'une des deux comme un échec ferait
  // abandonner des paiements en cours — et l'argent, lui, partirait
  // quand même.
  if (statut === 'CREATED' || statut === 'PENDING') {
    return json({ etat: 'attente' });
  }
  if (statut !== 'SUCCESSFUL') return json({ etat: 'echec' });

  // ── Vérification 3 : d'où viennent l'appareil et l'offre ──
  const parts = String(t.externalId || '').split('-');
  if (parts.length < 3) return json({ erreur: 'référence corrompue' }, 409);
  const [appareil, offre, horodatage] = parts;

  if (!normaliserAppareil(appareil)) return json({ erreur: 'appareil' }, 409);
  if (!(offre in OFFRES)) return json({ erreur: 'offre' }, 409);

  // ── Vérification 2 : le montant ──
  //
  // Sans elle, on pourrait demander un encaissement de 5 F en le
  // marquant « pro » — CamPay le confirmerait, et on délivrerait la
  // licence la plus chère pour presque rien.
  const paye = Number(t.amount);
  if (!Number.isFinite(paye) || paye < OFFRES[offre]) {
    return json({ erreur: 'montant insuffisant' }, 409);
  }

  // ── Fenêtre de validité ──
  const age = (Date.now() - Number(horodatage)) / 1000;
  if (!Number.isFinite(age) || age > FENETRE_SECONDES) {
    return json({ erreur: 'demande expirée' }, 409);
  }

  // ── Vérification 4 : une référence ne sert qu'une fois ──
  //
  // Une licence est liée à un appareil, donc la rejouer ne donnerait
  // rien de plus à personne — mais on refuse quand même, parce qu'un
  // point d'entrée qui accepte d'être rejoué indéfiniment est une
  // invitation à le marteler.
  if (env.DEJA_SERVI) {
    const vu = await env.DEJA_SERVI.get(reference);
    if (vu) return json({ etat: 'ok', licence: vu });
  }

  const licence = await signerLicence(env, appareil, offre);

  if (env.DEJA_SERVI) {
    // Gardée un mois : assez pour qu'une personne qui a perdu son code
    // le retrouve en relançant l'application, pas assez pour faire
    // grossir le stockage indéfiniment.
    await env.DEJA_SERVI.put(reference, licence, {
      expirationTtl: 60 * 60 * 24 * 31,
    });
  }

  return json({ etat: 'ok', licence });
}

// ══════════════════════════════════════════════════════════════════
//  LA SIGNATURE
// ══════════════════════════════════════════════════════════════════

/**
 * Fabrique exactement le même format que `tool/licence.dart`.
 *
 * ⚠️ SI CE FORMAT CHANGE ICI, IL DOIT CHANGER AUX TROIS ENDROITS :
 * ce fichier, `tool/licence.dart`, et `PremiumService` côté
 * application. Une divergence produit des licences qui ne débloquent
 * rien, et le symptôme — « j'ai payé et ça ne marche pas » — est le
 * pire qu'on puisse infliger à quelqu'un.
 */
export async function signerLicence(env, appareil, offre) {
  const charge = JSON.stringify({
    d: appareil,
    k: offre,
    t: Math.floor(Date.now() / 1000),
  });
  const chargeB64 = b64url(new TextEncoder().encode(charge));

  const cle = await crypto.subtle.importKey(
    'jwk',
    { kty: 'OKP', crv: 'Ed25519', d: env.LICENCE_D, x: env.LICENCE_X },
    { name: 'Ed25519' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'Ed25519',
    cle,
    new TextEncoder().encode(`${PREFIXE}.${chargeB64}`),
  );

  return `${PREFIXE}.${chargeB64}.${b64url(new Uint8Array(signature))}`;
}

// ══════════════════════════════════════════════════════════════════
//  OUTILS
// ══════════════════════════════════════════════════════════════════

/**
 * Un appel à Fapshi.
 *
 * L'authentification passe par deux en-têtes propres à eux, `apiuser`
 * et `apikey` — ni Bearer, ni Basic. Les deux vivent en secrets du
 * Worker, jamais dans le dépôt et jamais dans l'application.
 */
function fapshi(env, chemin, init = {}) {
  // ⚠️ Par défaut le BAC À SABLE, pas la production.
  // Un Worker déployé sans `FAPSHI_BASE` ne doit pas se mettre à
  // encaisser de l'argent réel par accident : on préfère qu'il ne
  // débloque rien plutôt qu'il débite quelqu'un pendant un essai.
  const base = env.FAPSHI_BASE || 'https://sandbox.fapshi.com/';
  return fetch(base + chemin, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      apiuser: env.FAPSHI_USER,
      apikey: env.FAPSHI_KEY,
      ...(init.headers || {}),
    },
  });
}

/** Seize caractères hexadécimaux, tirets et espaces retirés. */
export function normaliserAppareil(v) {
  const net = String(v || '').replace(/[^0-9a-fA-F]/g, '').toLowerCase();
  return net.length === 16 ? net : null;
}

/**
 * Un numéro camerounais au format attendu par Fapshi.
 *
 * ⚠️ NEUF CHIFFRES, SANS INDICATIF. Vérifié contre l'API : envoyer
 * `237678963221` fait répondre « Phone number must be a valid MTN or
 * Orange ». C'est exactement le genre de détail qu'on ne devine pas et
 * qui ne se voit qu'en production, sur un message d'erreur que
 * l'utilisateur attribue à son propre numéro.
 *
 * On accepte l'indicatif en ENTRÉE — les gens collent volontiers un
 * numéro copié de leurs contacts — et on le retire avant l'envoi.
 */
export function normaliserTelephone(v) {
  let net = String(v || '').replace(/\D/g, '');
  if (net.startsWith('237')) net = net.slice(3);
  return /^6\d{8}$/.test(net) ? net : null;
}

function b64url(octets) {
  let s = '';
  for (const o of octets) s += String.fromCharCode(o);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function json(corps, statut = 200) {
  return new Response(JSON.stringify(corps), {
    status: statut,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}
