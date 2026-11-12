// ============================================================================
// Essai de bout en bout de CHAQUE kit serveur contre un vrai service Droplet ID
// (lancé ici, en mémoire) et un appareil qui approuve avec sa clé Ed25519.
//
//   node e2e.mjs            → tous les kits dont le langage est installé
//
// Pour chaque kit : il fabrique l'adresse de connexion ; un « navigateur »
// la suit ; l'appareil lit la demande et tape le bon nombre ; le kit reçoit
// le retour, échange le code et VÉRIFIE l'ID token. On contrôle que le `sub`
// est stable pour un même site et que le pseudo choisi arrive.
// ============================================================================

import { execFileSync, execFile } from 'node:child_process';
import { promisify } from 'node:util';
const executer = promisify(execFile);
import { demarrer } from '../../serveur/src/serveur.js';
import { nouvelleCleDeSignature } from '../../serveur/src/config.js';
import { nouvelAppareil, nouveauNavigateur } from '../../serveur/test/outils.js';

const PORT = 18900;
const BASE = `http://localhost:${PORT}`;
const ici = new URL('.', import.meta.url).pathname;

const KITS = [
  { nom: 'node', cmd: ['node', [`${ici}node_cli.mjs`]] },
  { nom: 'python', cmd: ['python3', [`${ici}python_cli.py`]] },
  { nom: 'php', cmd: ['php', [`${ici}php_cli.php`]] },
  { nom: 'go', cmd: ['go', ['run', '.']], cwd: `${ici}go`, test: ['go', ['list', '-m', 'github.com/coreos/go-oidc/v3']], testCwd: `${ici}go` },
];

const present = (k) => {
  try { execFileSync(...(k.test ?? [k.cmd[0], ['--version']]), { stdio: 'ignore', cwd: k.testCwd }); return true; } catch { return false; }
};

const clients = KITS.map((k, i) => ({ client_id: `kit-${k.nom}`, client_name: `Kit ${k.nom}`, redirect_uris: [`http://localhost:${7100 + i}/retour`] }));
const service = await demarrer({
  port: PORT, emetteur: BASE, baseDeDonnees: process.env.TEST_DATABASE_URL ?? null,
  jwks: { keys: [nouvelleCleDeSignature('e2e')] }, clesCookies: ['cle-e2e-0123456789abcdef0123456789'], selPairwise: 'sel-e2e',
  clients, environnementDeTest: true, dureeDemande: 120, fenetreSignature: 300, derriereProxy: false,
});

const tel = nouvelAppareil(BASE);
await tel.creerCompte();
let echecs = 0;

for (const [i, k] of KITS.entries()) {
  if (!present(k)) { console.log(`– ${k.nom} : non installé ici (essayé en CI)`); continue; }
  const client = clients[i];
  // Asynchrone : le service tourne dans CE processus (un appel bloquant le figerait).
  const lancer = async (...args) => JSON.parse((await executer(k.cmd[0], [...k.cmd[1], BASE, client.client_id, client.redirect_uris[0], ...args], { cwd: k.cwd, encoding: 'utf8' })).stdout.trim().split('\n').pop());
  const connexion = async (pseudo) => {
    const { url, attente } = await lancer('commencer');
    const nav = nouveauNavigateur();
    const r1 = await nav.aller(url);
    const inter = new URL(r1.headers.get('location'), BASE);
    const page = await (await nav.aller(inter.href)).text();
    const demande = page.match(/\/a\/([A-Za-z0-9_-]{16,})/)[1];
    const code = page.match(/class="chiffres" aria-label="(\d\d)"/)[1];
    await tel.appeler('GET', `/v1/demandes/${demande}`);
    const d = await tel.appeler('POST', `/v1/demandes/${demande}/decision`, { decision: 'approuver', code, portees: ['openid', 'profile'], pseudo });
    if (d.statut !== 200) throw new Error(`décision ${d.statut}`);
    const { redirection } = await (await nav.aller(`${inter.href}/terminer`, { method: 'POST' })).json();
    let r = await nav.aller(new URL(redirection, BASE).href);
    while (!r.headers.get('location').startsWith(client.redirect_uris[0])) r = await nav.aller(new URL(r.headers.get('location'), BASE).href);
    return lancer('terminer', r.headers.get('location'), JSON.stringify(attente));
  };
  try {
    const a = await connexion(`Effi-${k.nom}`);
    const b = await connexion(`Effi-${k.nom}`);
    if (!a.sub || a.sub !== b.sub) throw new Error('sub instable');
    if (a.pseudo !== `Effi-${k.nom}`) throw new Error(`pseudo reçu : ${a.pseudo}`);
    if (a.sub === tel.compteId) throw new Error('le site voit l’identifiant interne');
    console.log(`✓ ${k.nom} : connexion vérifiée, sub ${a.sub.slice(0, 10)}…, pseudo ${a.pseudo}`);
  } catch (e) {
    echecs++;
    console.log(`✗ ${k.nom} : ${String(e.stderr ?? e.message).trim().split('\n').slice(-3).join(' | ')}`);
  }
}
await service.arreter();
process.exit(echecs ? 1 : 0);
