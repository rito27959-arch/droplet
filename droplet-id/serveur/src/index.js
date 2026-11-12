import { config } from './config.js';
import { demarrer } from './serveur.js';

const s = await demarrer(config);
// Remise à zéro du service de TEST seulement (VIDER_DONNEES_TEST=1, à retirer
// aussitôt après) : refusé en production.
if (process.env.VIDER_DONNEES_TEST === '1') {
  if (!config.environnementDeTest) throw new Error('VIDER_DONNEES_TEST refusé : ce n\'est pas le service de test');
  await s.stockage.viderTout();
  console.log('[droplet-id] données de test effacées (comptes, appareils, sites connectés, sessions, jetons)');
}
console.log(`[droplet-id] ${config.emetteur} — port ${config.port}, stockage ${s.stockage.nom}${config.environnementDeTest ? ', ENVIRONNEMENT DE TEST' : ''}`);
for (const sig of ['SIGTERM', 'SIGINT']) process.on(sig, () => s.arreter().then(() => process.exit(0)));
