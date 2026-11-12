import { useEffect, useState } from 'react';
import { DropletIdButton, useDropletId } from '@droplet/id-react';

const TAMPONS = 8;
const MENU = [
  { nom: 'Café noir', detail: 'Arabica des hauts plateaux de l’Ouest', prix: 500 },
  { nom: 'Café au lait', detail: 'Lait entier, mousse épaisse', prix: 700 },
  { nom: 'Kola glacée', detail: 'Infusion de noix de kola, citron vert', prix: 800 },
  { nom: 'Beignets-haricots', detail: 'La portion, avec piment à part', prix: 600 },
];
const fcfa = (n) => `${n.toLocaleString('fr-FR')} FCFA`;

// Les tampons sont gardés dans CE navigateur, rangés sous l'identifiant
// Droplet ID (une vraie boutique les garderait sur son serveur, sous ce même
// identifiant — c'est tout ce qu'il lui faut).
const lire = (sub) => { try { return Number(localStorage.getItem(`kola:${sub}`)) || 0; } catch { return 0; } };
const ecrire = (sub, n) => { try { localStorage.setItem(`kola:${sub}`, String(n)); } catch {} };

function Noix({ pleine, i }) {
  return (
    <svg className="noix" data-pleine={pleine || undefined} style={{ '--i': i }} viewBox="0 0 40 40" aria-hidden="true">
      <path d="M20 4c8.6 0 14 7.2 14 16s-5.4 16-14 16S6 28.8 6 20 11.4 4 20 4Z" />
      <path className="fente" d="M20 6.5c-2.4 4.5-3 8.8-1.8 13 1.2 4.1.9 8.6-.9 13" />
    </svg>
  );
}

function Carte({ utilisateur }) {
  const [n, setN] = useState(0);
  useEffect(() => { if (utilisateur) setN(lire(utilisateur.sub)); }, [utilisateur]);
  const commander = () => {
    const suivant = n >= TAMPONS ? 0 : n + 1;
    ecrire(utilisateur.sub, suivant);
    setN(suivant);
  };
  const offert = n >= TAMPONS;
  return (
    <section className="carte" data-active={utilisateur ? '' : undefined} aria-label="Carte de fidélité">
      <div className="carte-haut">
        <span className="carte-marque">Kola Café</span>
        <span className="carte-type">Carte de fidélité</span>
      </div>
      <div className="tampons" role="img" aria-label={`${Math.min(n, TAMPONS)} tampons sur ${TAMPONS}`}>
        {Array.from({ length: TAMPONS }, (_, i) => <Noix key={i} i={i} pleine={utilisateur && i < n} />)}
      </div>
      {utilisateur ? (
        <div className="carte-bas">
          <p>{offert ? <strong>Votre prochain café est offert.</strong> : <>Encore <strong>{TAMPONS - n}</strong> {TAMPONS - n > 1 ? 'cafés' : 'café'} avant le café offert.</>}</p>
          <button className="commande" onClick={commander}>{offert ? 'Prendre le café offert' : 'Commander un café noir'}</button>
        </div>
      ) : (
        <div className="carte-bas"><p>Connectez-vous pour activer votre carte.</p></div>
      )}
    </section>
  );
}

function CeQueNousSavons({ utilisateur, onQuitter }) {
  return (
    <section className="savoir" aria-labelledby="savoir-titre">
      <h2 id="savoir-titre">Ce que Kola Café sait de vous</h2>
      <dl>
        <div><dt>Identifiant Droplet ID</dt><dd><code>{utilisateur.sub}</code></dd></div>
        <div><dt>Pseudo</dt><dd>{utilisateur.pseudo ?? <span className="rien">non partagé</span>}</dd></div>
      </dl>
      <ul className="jamais">
        <li>Pas de numéro de téléphone</li>
        <li>Pas d’e-mail</li>
        <li>Pas de nom</li>
      </ul>
      <p className="note">Cet identifiant ne vaut que pour Kola Café : un autre site reçoit un identifiant différent, impossible à recouper avec celui-ci.</p>
      <button className="lien" onClick={onQuitter}>Se déconnecter</button>
    </section>
  );
}

export default function App() {
  const { utilisateur, chargement, erreur, deconnecter } = useDropletId();
  return (
    <>
      <div className="demo">Site de démonstration — Kola Café est un café imaginaire, créé pour montrer Droplet ID.</div>
      <header className="entete">
        <a className="logo" href="/"><Noix pleine i={0} /><span>Kola Café</span></a>
        <span className="lieu">Yaoundé</span>
      </header>

      <main>
        <section className="ouverture">
          <div className="texte">
            {utilisateur ? (
              <>
                <h1>Bon retour{utilisateur.pseudo ? `, ${utilisateur.pseudo}` : ''}.</h1>
                <p className="chapo">Votre carte est là où vous l’avez laissée. Huit cafés, le neuvième est pour nous.</p>
              </>
            ) : (
              <>
                <h1>Votre carte de fidélité, sans donner votre numéro.</h1>
                <p className="chapo">Huit cafés, le neuvième est pour nous. Pour vous reconnaître, il nous faut seulement Droplet ID : ni téléphone, ni e-mail, ni nom.</p>
                <div className="action">
                  <DropletIdButton taille="grand" />
                  {chargement && <p className="etat">Connexion en cours…</p>}
                  {erreur && <p className="etat erreur">{erreur.code === 'access_denied' ? 'Connexion annulée. Vous pouvez réessayer.' : `La connexion n’a pas abouti (${erreur.code ?? erreur.message}).`}</p>}
                </div>
              </>
            )}
          </div>
          <Carte utilisateur={utilisateur} />
        </section>

        {utilisateur && <CeQueNousSavons utilisateur={utilisateur} onQuitter={() => deconnecter()} />}

        <section className="menu" aria-labelledby="menu-titre">
          <h2 id="menu-titre">Au comptoir</h2>
          <ul>
            {MENU.map((m) => (
              <li key={m.nom}><span className="nom">{m.nom}</span><span className="detail">{m.detail}</span><span className="prix">{fcfa(m.prix)}</span></li>
            ))}
          </ul>
        </section>
      </main>

      <footer className="pied">
        <p>Démonstration de <a href="https://developpeurs-id.dropletmesh.app">Droplet ID</a>, en environnement de test. Les tampons restent dans ce navigateur.</p>
      </footer>
    </>
  );
}
