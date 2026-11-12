import { config } from './config.js';
import { demarrer } from './serveur.js';

const s = await demarrer(config);
console.log(`[droplet-id] ${config.emetteur} — port ${config.port}, stockage ${s.stockage.nom}${config.environnementDeTest ? ', ENVIRONNEMENT DE TEST' : ''}`);
for (const sig of ['SIGTERM', 'SIGINT']) process.on(sig, () => s.arreter().then(() => process.exit(0)));
