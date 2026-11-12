// ============================================================================
// @droplet/id-react — Droplet ID pour React.
//
//   <DropletIdProvider clientId="mon-site" redirectUri={location.origin + '/'}>
//     <App />
//   </DropletIdProvider>
//
//   const { utilisateur, connecter, deconnecter, chargement, erreur } = useDropletId();
//   <DropletIdButton />
// ============================================================================

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { DropletId, GOUTTE_SVG, STYLE_BOUTON } from '@droplet/id';

const Contexte = createContext(null);

export function DropletIdProvider({ children, clientId, redirectUri, emetteur, portees, langue }) {
  const did = useMemo(() => new DropletId({ clientId, redirectUri, emetteur, portees, langue }), [clientId, redirectUri, emetteur, (portees ?? []).join(' '), langue]);
  const [utilisateur, setUtilisateur] = useState(() => did.utilisateur());
  const [chargement, setChargement] = useState(() => did.estUnRetour());
  const [erreur, setErreur] = useState(null);
  const fait = useRef(false);

  // Au retour de Droplet ID : une seule fois (React rejoue les effets en dev).
  useEffect(() => {
    if (fait.current || !did.estUnRetour()) return;
    fait.current = true;
    did
      .terminerConnexion()
      .then((s) => setUtilisateur({ sub: s.sub, pseudo: s.pseudo }))
      .catch((e) => setErreur(e))
      .finally(() => setChargement(false));
  }, [did]);

  const connecter = useCallback(async () => {
    setErreur(null);
    try { await did.connecter(); } catch (e) { setErreur(e); }
  }, [did]);
  const deconnecter = useCallback(async (o) => { await did.deconnecter(o); setUtilisateur(null); }, [did]);

  const valeur = useMemo(() => ({ utilisateur, chargement, erreur, connecter, deconnecter, client: did }), [utilisateur, chargement, erreur, connecter, deconnecter, did]);
  return <Contexte.Provider value={valeur}>{children}</Contexte.Provider>;
}

export function useDropletId() {
  const v = useContext(Contexte);
  if (!v) throw new Error('useDropletId doit être utilisé dans <DropletIdProvider>');
  return v;
}

let styleInjecte = false;
function useStyleBouton() {
  useEffect(() => {
    if (styleInjecte || document.getElementById('droplet-id-style')) return;
    const s = document.createElement('style');
    s.id = 'droplet-id-style';
    s.textContent = STYLE_BOUTON;
    document.head.append(s);
    styleInjecte = true;
  }, []);
}

const TEXTES = { fr: 'Continuer avec Droplet ID', en: 'Continue with Droplet ID' };

/** Le bouton officiel. variante : 'sombre' | 'clair' | 'bleu' ; taille : 'petit' | 'moyen' | 'grand'. */
export function DropletIdButton({ langue = 'fr', variante = 'sombre', taille = 'moyen', pleineLargeur = false, className, children, ...reste }) {
  useStyleBouton();
  const { connecter, chargement } = useDropletId();
  const [occupe, setOccupe] = useState(false);
  return (
    <button
      type="button"
      className={['droplet-id-bouton', className].filter(Boolean).join(' ')}
      data-variante={variante}
      data-taille={taille}
      data-pleine-largeur={pleineLargeur ? '' : undefined}
      aria-busy={occupe || chargement ? 'true' : undefined}
      onClick={async () => { setOccupe(true); try { await connecter(); } finally { setOccupe(false); } }}
      {...reste}
    >
      <span dangerouslySetInnerHTML={{ __html: GOUTTE_SVG }} style={{ display: 'contents' }} />
      <span>{children ?? TEXTES[langue] ?? TEXTES.fr}</span>
    </button>
  );
}
