// Petit programme d'essai du kit Node : `commencer` puis `terminer`.
import { DropletIdServeur } from '../node/src/index.js';
const [emetteur, clientId, retour, etape, urlRetour, attente] = process.argv.slice(2);
const did = await DropletIdServeur.creer({ clientId, redirectUri: retour, emetteur, portees: ['openid', 'profile'], _http: emetteur.startsWith('http:') });
if (etape === 'commencer') console.log(JSON.stringify(await did.commencer()));
else { const s = await did.terminer(urlRetour, JSON.parse(attente)); console.log(JSON.stringify({ sub: s.sub, pseudo: s.pseudo })); }
