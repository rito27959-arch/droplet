import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { DropletIdProvider } from '@droplet/id-react';
import { EMETTEUR_TEST } from '@droplet/id';
import App from './App.jsx';
import './kola.css';

const local = location.hostname === 'localhost';

createRoot(document.getElementById('app')).render(
  <StrictMode>
    <DropletIdProvider
      clientId="demo-kola"
      redirectUri={`${location.origin}/`}
      emetteur={local ? 'http://localhost:8080' : EMETTEUR_TEST}
      portees={['openid', 'profile']}
      langue="fr"
    >
      <App />
    </DropletIdProvider>
  </StrictMode>,
);
