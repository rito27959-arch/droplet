import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

// Les kits sont pris directement dans le dépôt (../../kits), comme un
// paquet npm publié le serait.
const kit = (p) => fileURLToPath(new URL(`../../kits/${p}`, import.meta.url));

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@droplet/id-react': kit('react/src/index.jsx'),
      '@droplet/id': kit('js/src/droplet-id.js'),
    },
  },
  server: { port: 5173, fs: { allow: ['../..'] } },
});
