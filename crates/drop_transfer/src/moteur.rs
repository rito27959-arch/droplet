//! Le moteur : un appareil Droplet Drop.
//!
//! Il écoute sur un port TCP (TLS 1.3 mutuel), et :
//!
//! * **reçoit** — une offre arrive, l'interface demande à l'utilisateur
//!   (sauf appareil de confiance, ou reprise d'un transfert déjà accepté) ;
//! * **envoie** — à un ou plusieurs appareils à la fois ; chaque
//!   destinataire a son propre transfert, un appareil lent ne retient pas
//!   les autres, et le nombre de transferts simultanés est borné ;
//! * **héberge des sessions Group Drop** — les participants se connectent
//!   eux-mêmes avec l'invitation (QR code), ce qui marche aussi quand la
//!   découverte automatique est bloquée par le réseau ;
//! * **reprend** — une connexion perdue est retentée pendant 10 minutes ;
//!   le destinataire repart de sa carte des blocs.

use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use base64::Engine;
use drop_core::{construire_manifeste, Manifeste, SourceFichier, TAILLE_BLOC};
use drop_crypto::{config_client, config_serveur, egal_constant, empreinte_du_pair, nom_serveur, secret_aleatoire, EmpreinteAppareil, Identite};
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{broadcast, oneshot, Semaphore};
use tokio_rustls::{TlsAcceptor, TlsConnector};

use crate::envoi;
use crate::protocole::{Appareil, Controle, VERSION};
use crate::reception::{self, espace_suffisant, Partiel};
use crate::suivi::{Etat, Evenement, Pair, Sens, Suivi};
use crate::trame;
use crate::Erreur;

/// Le port par défaut (un autre est pris s'il est occupé).
pub const PORT_DEFAUT: u16 = 47321;

const DELAI_CONNEXION: Duration = Duration::from_secs(6);
const DELAI_POIGNEE: Duration = Duration::from_secs(15);
/// Une connexion perdue est retentée tant qu'on a progressé il y a moins
/// de 10 minutes.
const PATIENCE_REPRISE: Duration = Duration::from_secs(600);

#[derive(Clone, Debug)]
pub struct Config {
    pub nom: String,
    pub plateforme: String,
    /// Où garder l'identité de l'appareil.
    pub donnees: PathBuf,
    /// Où poser les fichiers reçus.
    pub reception: PathBuf,
    pub port: u16,
    /// Transferts sortants simultanés (envoi multiple, Group Drop).
    pub max_simultanes: usize,
    /// Combien de temps une offre attend la réponse de l'utilisateur.
    pub delai_reponse: Duration,
    /// Empreintes (hex) dont on accepte les envois sans demander.
    pub confiance: Vec<String>,
}

impl Config {
    pub fn simple(nom: &str, donnees: PathBuf, reception: PathBuf) -> Self {
        Self {
            nom: nom.into(),
            plateforme: std::env::consts::OS.into(),
            donnees,
            reception,
            port: PORT_DEFAUT,
            max_simultanes: 12,
            delai_reponse: Duration::from_secs(120),
            confiance: Vec::new(),
        }
    }
}

/// Un destinataire : ses adresses, et son empreinte quand on la connaît
/// (découverte, QR code) — elle est alors épinglée.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Cible {
    pub adresses: Vec<SocketAddr>,
    pub empreinte: Option<String>,
    pub nom: String,
}

/// L'invitation à une session Group Drop : tout ce qu'il faut pour la
/// rejoindre, et rien de devinable (jeton de 256 bits, durée limitée).
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Invitation {
    pub v: u32,
    /// Adresses de l'hôte.
    pub h: Vec<String>,
    pub p: u16,
    /// Empreinte de l'hôte (épinglée).
    pub fp: String,
    pub s: String,
    pub j: String,
    pub n: String,
    /// Expiration (secondes Unix).
    pub x: u64,
}

/// Le préfixe des liens d'invitation : une page web, pour qu'un code
/// scanné par l'appareil photo d'un téléphone SANS Droplet Drop mène
/// quelque part (la page explique, propose le téléchargement, et copie
/// l'invitation). Tout ce qui compte est après « # » : le navigateur ne
/// l'envoie jamais au serveur.
pub const LIEN_INVITATION: &str = "https://drop.dropletmesh.app/rejoindre/#";

impl Invitation {
    pub fn encoder(&self) -> String {
        let j = serde_json::to_vec(self).unwrap_or_default();
        format!("{LIEN_INVITATION}{}", base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(j))
    }

    pub fn decoder(texte: &str) -> Option<Self> {
        let t = texte.trim();
        let donnees = t.rsplit('#').next().unwrap_or(t);
        let brut = base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(donnees.trim_end_matches('=')).ok()?;
        if brut.len() > 4096 {
            return None;
        }
        let i: Invitation = serde_json::from_slice(&brut).ok()?;
        (i.v == 1 && i.s.len() == 32 && i.j.len() == 64 && EmpreinteAppareil::depuis_hex(&i.fp).is_some()).then_some(i)
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct InfoSession {
    pub id: String,
    pub invitation: String,
    pub expire: u64,
    pub total: u64,
    pub fichiers: Vec<(String, u64)>,
}

struct EnvoiPrepare {
    manifeste: Manifeste,
    sources: Vec<PathBuf>,
}

struct Session {
    id: String,
    jeton: String,
    expire: SystemTime,
    envoi: Arc<EnvoiPrepare>,
    demarree: AtomicBool,
    pause: AtomicBool,
    terminee: AtomicBool,
    participants: Mutex<HashMap<String, Arc<Suivi>>>,
    creneaux: Arc<Semaphore>,
}

struct Interne {
    config: RwLock<Config>,
    identite: Identite,
    acceptor: TlsAcceptor,
    port: u16,
    evenements: broadcast::Sender<Evenement>,
    suivis: Mutex<HashMap<String, Arc<Suivi>>>,
    offres: Mutex<HashMap<String, oneshot::Sender<bool>>>,
    sessions: Mutex<HashMap<String, Arc<Session>>>,
    creneaux: Arc<Semaphore>,
    echecs: Mutex<HashMap<IpAddr, (u32, Instant)>>,
    actif: AtomicBool,
    arret: tokio::sync::Notify,
    compteur: AtomicU64,
}

#[derive(Clone)]
pub struct Moteur(Arc<Interne>);

impl Moteur {
    pub async fn demarrer(config: Config) -> Result<Self, Erreur> {
        let identite = Identite::charger_ou_creer(&config.donnees).map_err(|e| Erreur::Tls(e.to_string()))?;
        let acceptor = TlsAcceptor::from(config_serveur(&identite).map_err(|e| Erreur::Tls(e.to_string()))?);
        let ecoute = match TcpListener::bind(("0.0.0.0", config.port)).await {
            Ok(l) => l,
            Err(_) => TcpListener::bind(("0.0.0.0", 0)).await?,
        };
        let port = ecoute.local_addr()?.port();
        tokio::fs::create_dir_all(&config.reception).await?;
        let (evenements, _) = broadcast::channel(4096);
        let creneaux = Arc::new(Semaphore::new(config.max_simultanes.max(1)));
        let m = Moteur(Arc::new(Interne {
            config: RwLock::new(config),
            identite,
            acceptor,
            port,
            evenements,
            suivis: Mutex::new(HashMap::new()),
            offres: Mutex::new(HashMap::new()),
            sessions: Mutex::new(HashMap::new()),
            creneaux,
            echecs: Mutex::new(HashMap::new()),
            actif: AtomicBool::new(true),
            arret: tokio::sync::Notify::new(),
            compteur: AtomicU64::new(0),
        }));
        let m2 = m.clone();
        tokio::spawn(async move { m2.ecouter(ecoute).await });
        let m3 = m.clone();
        tokio::spawn(async move { m3.raconter().await });
        Ok(m)
    }

    pub fn port(&self) -> u16 {
        self.0.port
    }

    pub fn empreinte(&self) -> EmpreinteAppareil {
        self.0.identite.empreinte
    }

    pub fn abonner(&self) -> broadcast::Receiver<Evenement> {
        self.0.evenements.subscribe()
    }

    /// Arrête l'appareil : plus d'écoute (le port est libéré), et les
    /// transferts en cours s'interrompent — leurs partiels restent.
    pub fn arreter(&self) {
        self.0.actif.store(false, Ordering::Relaxed);
        self.0.arret.notify_waiters();
        for s in self.0.suivis.lock().unwrap().values() {
            // Pause, pas annulation : les partiels sont gardés pour reprendre.
            s.pause.store(true, Ordering::Relaxed);
            s.reveil.notify_waiters();
        }
    }

    pub fn modifier(&self, f: impl FnOnce(&mut Config)) {
        f(&mut self.0.config.write().unwrap());
    }

    pub fn config(&self) -> Config {
        self.0.config.read().unwrap().clone()
    }

    fn nouvel_id(&self, prefixe: &str) -> String {
        let n = self.0.compteur.fetch_add(1, Ordering::Relaxed);
        format!("{prefixe}{n}-{}", &secret_aleatoire(4))
    }

    fn appareil(&self) -> Appareil {
        let c = self.0.config.read().unwrap();
        Appareil { nom: c.nom.clone(), plateforme: c.plateforme.clone() }
    }

    fn enregistrer(&self, s: Arc<Suivi>) -> Arc<Suivi> {
        self.0.suivis.lock().unwrap().insert(s.id.clone(), s.clone());
        s
    }

    // ══ COMMANDES ════════════════════════════════════════════════════════

    /// Répondre à une offre reçue.
    pub fn repondre(&self, offre: &str, accepter: bool) -> bool {
        match self.0.offres.lock().unwrap().remove(offre) {
            Some(tx) => tx.send(accepter).is_ok(),
            None => false,
        }
    }

    fn cibles_de(&self, id: &str) -> Vec<Arc<Suivi>> {
        self.0.suivis.lock().unwrap().values().filter(|s| s.id == id || s.groupe == id).cloned().collect()
    }

    pub fn pause(&self, id: &str) {
        if let Some(s) = self.0.sessions.lock().unwrap().get(id) {
            s.pause.store(true, Ordering::Relaxed);
        }
        for s in self.cibles_de(id) {
            if !s.etat().final_() {
                s.pause.store(true, Ordering::Relaxed);
            }
        }
    }

    pub fn reprendre(&self, id: &str) {
        if let Some(s) = self.0.sessions.lock().unwrap().get(id) {
            s.pause.store(false, Ordering::Relaxed);
            s.demarree.store(true, Ordering::Relaxed);
        }
        for s in self.cibles_de(id) {
            s.pause.store(false, Ordering::Relaxed);
            s.reveil.notify_waiters();
        }
    }

    pub fn annuler(&self, id: &str) {
        if let Some(s) = self.0.sessions.lock().unwrap().get(id) {
            s.terminee.store(true, Ordering::Relaxed);
        }
        for s in self.cibles_de(id) {
            s.annule.store(true, Ordering::Relaxed);
            s.reveil.notify_waiters();
            if matches!(s.etat(), Etat::EnAttente | Etat::Interrompu | Etat::AttenteReponse) {
                s.changer(Etat::Annule);
            }
        }
    }

    // ══ ENVOYER ══════════════════════════════════════════════════════════

    async fn preparer(&self, groupe: &str, sources: Vec<SourceFichier>) -> Result<EnvoiPrepare, Erreur> {
        let total: u64 = sources.iter().filter_map(|s| std::fs::metadata(&s.disque).ok()).map(|m| m.len()).sum();
        let tx = self.0.evenements.clone();
        let g = groupe.to_string();
        let disques: Vec<PathBuf> = sources.iter().map(|s| s.disque.clone()).collect();
        let manifeste = tokio::task::spawn_blocking(move || {
            let mut lu = 0u64;
            let mut dernier = Instant::now();
            construire_manifeste(&sources, TAILLE_BLOC, |n| {
                lu += n;
                if dernier.elapsed() > Duration::from_millis(200) {
                    dernier = Instant::now();
                    let _ = tx.send(Evenement::Preparation { groupe: g.clone(), octets: lu, total });
                }
            })
        })
        .await
        .map_err(|_| Erreur::Protocole("préparation"))?
        .map_err(|_| Erreur::FichierIntrouvable)?;
        let _ = self.0.evenements.send(Evenement::Preparation { groupe: groupe.to_string(), octets: total, total });
        Ok(EnvoiPrepare { manifeste, sources: disques })
    }

    /// Envoie ces fichiers à ces appareils. Rend l'identifiant du groupe ;
    /// chaque destinataire a son propre suivi (même groupe).
    pub fn envoyer(&self, sources: Vec<SourceFichier>, cibles: Vec<Cible>) -> String {
        let groupe = self.nouvel_id("e");
        let suivis: Vec<(Cible, Arc<Suivi>)> = cibles
            .into_iter()
            .map(|c| {
                let s = Arc::new(Suivi::nouveau(self.nouvel_id("t"), groupe.clone(), Sens::Envoi));
                *s.pair.lock().unwrap() = Pair {
                    nom: c.nom.clone(),
                    plateforme: String::new(),
                    empreinte: c.empreinte.clone().unwrap_or_default(),
                    courte: c.empreinte.as_deref().and_then(EmpreinteAppareil::depuis_hex).map(|e| e.courte()).unwrap_or_default(),
                };
                (c, self.enregistrer(s))
            })
            .collect();
        let m = self.clone();
        let g = groupe.clone();
        tokio::spawn(async move {
            let envoi = match m.preparer(&g, sources).await {
                Ok(e) => Arc::new(e),
                Err(e) => {
                    for (_, s) in &suivis {
                        s.echouer(e.code());
                    }
                    return;
                }
            };
            let fichiers: Vec<(String, u64)> = envoi.manifeste.fichiers.iter().map(|f| (f.chemin.clone(), f.taille)).collect();
            for (cible, s) in suivis {
                s.total.store(envoi.manifeste.taille_totale(), Ordering::Relaxed);
                *s.fichiers.lock().unwrap() = fichiers.clone();
                let m = m.clone();
                let envoi = envoi.clone();
                let g = g.clone();
                tokio::spawn(async move { m.envoyer_a(cible, envoi, g, s).await });
            }
        });
        groupe
    }

    async fn envoyer_a(&self, cible: Cible, envoi: Arc<EnvoiPrepare>, offre: String, s: Arc<Suivi>) {
        let mut derniere_avancee = Instant::now();
        let mut pause_attente = Duration::from_secs(1);
        loop {
            if !self.0.actif.load(Ordering::Relaxed) {
                s.changer(Etat::Interrompu);
                return;
            }
            if s.annule.load(Ordering::Relaxed) {
                s.changer(Etat::Annule);
                return;
            }
            if s.pause.load(Ordering::Relaxed) {
                s.changer(Etat::Interrompu);
                s.reveil.notified().await;
                continue;
            }
            // Un créneau parmi les transferts simultanés.
            let _creneau = match self.0.creneaux.clone().acquire_owned().await {
                Ok(c) => c,
                Err(_) => return,
            };
            let avant = s.octets.load(Ordering::Relaxed);
            let r = self.une_tentative_envoi(&cible, &envoi, &offre, &s).await;
            drop(_creneau);
            if s.octets.load(Ordering::Relaxed) > avant {
                derniere_avancee = Instant::now();
                pause_attente = Duration::from_secs(1);
            }
            match r {
                Ok(()) => {
                    s.changer(Etat::Termine);
                    return;
                }
                Err(Erreur::Refuse) => {
                    s.changer(Etat::Refuse);
                    return;
                }
                Err(Erreur::Annule) | Err(Erreur::AnnuleParLAutre) => {
                    s.changer(Etat::Annule);
                    return;
                }
                Err(Erreur::EnPause) if s.pause.load(Ordering::Relaxed) => continue,
                Err(e) if (e.passagere() || matches!(e, Erreur::EnPause)) && derniere_avancee.elapsed() < PATIENCE_REPRISE => {
                    *s.erreur.lock().unwrap() = Some(e.code().to_string());
                    s.changer(Etat::Interrompu);
                    tokio::select! {
                        _ = tokio::time::sleep(pause_attente) => {}
                        _ = s.reveil.notified() => {}
                    }
                    pause_attente = (pause_attente * 2).min(Duration::from_secs(15));
                    s.changer(Etat::Reprise);
                }
                Err(e) => {
                    s.echouer(e.code());
                    return;
                }
            }
        }
    }

    async fn connecter(&self, cible: &Cible) -> Result<(tokio_rustls::client::TlsStream<TcpStream>, EmpreinteAppareil), Erreur> {
        let attendue = cible.empreinte.as_deref().and_then(EmpreinteAppareil::depuis_hex);
        let conf = config_client(&self.0.identite, attendue).map_err(|e| Erreur::Tls(e.to_string()))?;
        let connecteur = TlsConnector::from(conf);
        let mut derniere = Erreur::Injoignable;
        for a in &cible.adresses {
            let tcp = match tokio::time::timeout(DELAI_CONNEXION, TcpStream::connect(a)).await {
                Ok(Ok(t)) => t,
                _ => continue,
            };
            let _ = tcp.set_nodelay(true);
            match tokio::time::timeout(DELAI_POIGNEE, connecteur.connect(nom_serveur(), tcp)).await {
                Ok(Ok(tls)) => {
                    let fp = empreinte_du_pair(tls.get_ref().1.peer_certificates()).ok_or(Erreur::EmpreinteInvalide)?;
                    return Ok((tls, fp));
                }
                Ok(Err(e)) => {
                    let certificat = e
                        .get_ref()
                        .and_then(|x| x.downcast_ref::<rustls::Error>())
                        .is_some_and(|r| matches!(r, rustls::Error::InvalidCertificate(_)));
                    derniere = if certificat { Erreur::EmpreinteInvalide } else { Erreur::Tls(e.to_string()) };
                    if certificat {
                        return Err(derniere);
                    }
                }
                Err(_) => derniere = Erreur::Injoignable,
            }
        }
        Err(derniere)
    }

    async fn bonjour<R: AsyncRead + Unpin, W: AsyncWrite + Unpin>(&self, r: &mut R, w: &mut W) -> Result<Appareil, Erreur> {
        trame::ecrire_controle(w, &Controle::Bonjour { v: VERSION, appareil: self.appareil() }).await?;
        match tokio::time::timeout(DELAI_POIGNEE, trame::lire_controle(r)).await {
            Ok(Ok(Controle::Bonjour { appareil, .. })) => Ok(nettoyer_appareil(appareil)),
            Ok(Ok(_)) => Err(Erreur::Protocole("bonjour attendu")),
            Ok(Err(e)) => Err(e),
            Err(_) => Err(Erreur::ConnexionInterrompue),
        }
    }

    async fn une_tentative_envoi(&self, cible: &Cible, envoi: &EnvoiPrepare, offre: &str, s: &Arc<Suivi>) -> Result<(), Erreur> {
        s.changer(Etat::Connexion);
        let (tls, fp) = self.connecter(cible).await?;
        let (mut r, mut w) = tokio::io::split(tls);
        let autre = self.bonjour(&mut r, &mut w).await?;
        *s.pair.lock().unwrap() = Pair { nom: autre.nom, plateforme: autre.plateforme, empreinte: fp.hex(), courte: fp.courte() };
        trame::ecrire_controle(&mut w, &Controle::Offre { offre: offre.to_string(), manifeste: envoi.manifeste.clone() }).await?;
        s.changer(Etat::AttenteReponse);
        let delai = self.0.config.read().unwrap().delai_reponse + Duration::from_secs(30);
        let reponse = loop {
            let lu = tokio::select! {
                r = tokio::time::timeout(delai, trame::lire_controle(&mut r)) => r,
                _ = s.reveil.notified() => {
                    if s.annule.load(Ordering::Relaxed) {
                        let _ = trame::ecrire_controle(&mut w, &Controle::Annuler).await;
                        return Err(Erreur::Annule);
                    }
                    continue;
                }
            };
            break lu;
        };
        match reponse {
            Ok(Ok(Controle::Reponse { acceptee: true, deja, .. })) => {
                let deja = coherentes(deja, &envoi.manifeste);
                let fait: u64 = envoi
                    .manifeste
                    .fichiers
                    .iter()
                    .zip(&deja)
                    .map(|(f, c)| (0..f.nombre_blocs()).filter(|&b| c.a(b)).map(|b| f.taille_du_bloc(b) as u64).sum::<u64>())
                    .sum();
                s.octets.store(fait, Ordering::Relaxed);
                envoi::envoyer(r, &mut w, &envoi.manifeste, &envoi.sources, &deja, s).await
            }
            Ok(Ok(Controle::Reponse { acceptee: false, raison, .. })) => match raison.as_deref() {
                Some("espace_insuffisant") => Err(Erreur::EspaceInsuffisant),
                _ => Err(Erreur::Refuse),
            },
            Ok(Ok(_)) => Err(Erreur::Protocole("réponse attendue")),
            Ok(Err(e)) => Err(e),
            Err(_) => Err(Erreur::Refuse),
        }
    }

    // ══ GROUP DROP : HÔTE ═════════════════════════════════════════════════

    /// Crée une session de distribution. Les participants la rejoignent
    /// avec l'invitation ; la distribution commence quand [demarrer] est
    /// vrai, ou à l'appel de `reprendre(session)`.
    pub async fn creer_session(&self, sources: Vec<SourceFichier>, duree: Duration, demarrer: bool) -> Result<InfoSession, Erreur> {
        let id = secret_aleatoire(16);
        let envoi = Arc::new(self.preparer(&id, sources).await?);
        let jeton = secret_aleatoire(32);
        let expire = SystemTime::now() + duree;
        let max = self.0.config.read().unwrap().max_simultanes;
        let session = Arc::new(Session {
            id: id.clone(),
            jeton: jeton.clone(),
            expire,
            envoi: envoi.clone(),
            demarree: AtomicBool::new(demarrer),
            pause: AtomicBool::new(false),
            terminee: AtomicBool::new(false),
            participants: Mutex::new(HashMap::new()),
            creneaux: Arc::new(Semaphore::new(max.max(1))),
        });
        self.0.sessions.lock().unwrap().insert(id.clone(), session);
        let x = expire.duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
        let invitation = Invitation {
            v: 1,
            h: adresses_locales(),
            p: self.0.port,
            fp: self.0.identite.empreinte.hex(),
            s: id.clone(),
            j: jeton,
            n: self.0.config.read().unwrap().nom.clone(),
            x,
        };
        Ok(InfoSession {
            id,
            invitation: invitation.encoder(),
            expire: x,
            total: envoi.manifeste.taille_totale(),
            fichiers: envoi.manifeste.fichiers.iter().map(|f| (f.chemin.clone(), f.taille)).collect(),
        })
    }

    async fn heberger<R, W>(&self, mut r: R, mut w: W, session: String, jeton: String, fp: EmpreinteAppareil, autre: Appareil, ip: IpAddr) -> Result<(), Erreur>
    where
        R: AsyncRead + Unpin + Send + 'static,
        W: AsyncWrite + Unpin,
    {
        let s = self.0.sessions.lock().unwrap().get(&session).cloned();
        let Some(s) = s.filter(|s| egal_constant(&s.jeton, &jeton)) else {
            self.noter_echec(ip);
            trame::ecrire_controle(&mut w, &Controle::Refus { raison: "session_invalide".into() }).await?;
            return Err(Erreur::SessionInvalide);
        };
        if s.terminee.load(Ordering::Relaxed) {
            trame::ecrire_controle(&mut w, &Controle::Refus { raison: "session_terminee".into() }).await?;
            return Ok(());
        }
        // Le participant (nouveau ou qui revient), décidé sans rien attendre
        // pendant que la liste est verrouillée.
        let trouve: Option<Arc<Suivi>> = {
            let mut parts = s.participants.lock().unwrap();
            match parts.get(&fp.hex()).cloned() {
                Some(p) => Some(p),
                // Une nouvelle entrée après l'expiration : refusée. Un
                // participant déjà là peut toujours reprendre.
                None if SystemTime::now() > s.expire => None,
                None => {
                    let p = Arc::new(Suivi::nouveau(self.nouvel_id("t"), s.id.clone(), Sens::Envoi));
                    p.total.store(s.envoi.manifeste.taille_totale(), Ordering::Relaxed);
                    *p.fichiers.lock().unwrap() = s.envoi.manifeste.fichiers.iter().map(|f| (f.chemin.clone(), f.taille)).collect();
                    parts.insert(fp.hex(), p.clone());
                    Some(p)
                }
            }
        };
        let Some(p) = trouve else {
            trame::ecrire_controle(&mut w, &Controle::Refus { raison: "session_expiree".into() }).await?;
            return Err(Erreur::SessionExpiree);
        };
        *p.pair.lock().unwrap() = Pair { nom: autre.nom.clone(), plateforme: autre.plateforme.clone(), empreinte: fp.hex(), courte: fp.courte() };
        self.enregistrer(p.clone());
        if p.etat() == Etat::Termine {
            trame::ecrire_controle(&mut w, &Controle::Refus { raison: "deja_recu".into() }).await?;
            return Ok(());
        }
        p.annule.store(false, Ordering::Relaxed);
        // Pas encore lancée, ou en pause : le participant revient plus tard.
        if !s.demarree.load(Ordering::Relaxed) || s.pause.load(Ordering::Relaxed) {
            p.changer(Etat::EnAttente);
            trame::ecrire_controle(&mut w, &Controle::Refus { raison: "attente".into() }).await?;
            return Ok(());
        }
        p.changer(Etat::EnAttente);
        trame::ecrire_controle(&mut w, &Controle::Attente).await?;
        let _creneau = s.creneaux.clone().acquire_owned().await.map_err(|_| Erreur::Annule)?;
        if s.terminee.load(Ordering::Relaxed) {
            trame::ecrire_controle(&mut w, &Controle::Annuler).await?;
            return Err(Erreur::Annule);
        }
        p.changer(Etat::Connexion);
        trame::ecrire_controle(&mut w, &Controle::Offre { offre: s.id.clone(), manifeste: s.envoi.manifeste.clone() }).await?;
        let rep = tokio::time::timeout(Duration::from_secs(60), trame::lire_controle(&mut r)).await;
        let deja = match rep {
            Ok(Ok(Controle::Reponse { acceptee: true, deja, .. })) => coherentes(deja, &s.envoi.manifeste),
            Ok(Ok(Controle::Reponse { acceptee: false, raison, .. })) => {
                if raison.as_deref() == Some("espace_insuffisant") {
                    p.echouer("espace_insuffisant");
                } else {
                    p.changer(Etat::Refuse);
                }
                return Ok(());
            }
            _ => return Err(Erreur::ConnexionInterrompue),
        };
        let fait: u64 = s
            .envoi
            .manifeste
            .fichiers
            .iter()
            .zip(&deja)
            .map(|(f, c)| (0..f.nombre_blocs()).filter(|&b| c.a(b)).map(|b| f.taille_du_bloc(b) as u64).sum::<u64>())
            .sum();
        p.octets.store(fait, Ordering::Relaxed);
        // La pause de session suspend tous les participants.
        let surveillance = {
            let p = p.clone();
            let s = s.clone();
            tokio::spawn(async move {
                loop {
                    tokio::time::sleep(Duration::from_millis(200)).await;
                    if p.etat().final_() {
                        break;
                    }
                    if s.pause.load(Ordering::Relaxed) {
                        p.pause.store(true, Ordering::Relaxed);
                    }
                    if s.terminee.load(Ordering::Relaxed) {
                        p.annule.store(true, Ordering::Relaxed);
                    }
                }
            })
        };
        let r2 = envoi::envoyer(r, &mut w, &s.envoi.manifeste, &s.envoi.sources, &deja, &p).await;
        surveillance.abort();
        match r2 {
            Ok(()) => {
                p.changer(Etat::Termine);
                Ok(())
            }
            Err(Erreur::EnPause) => {
                p.pause.store(false, Ordering::Relaxed);
                p.changer(Etat::Interrompu);
                Ok(())
            }
            Err(Erreur::Annule) | Err(Erreur::AnnuleParLAutre) => {
                p.changer(Etat::Annule);
                Ok(())
            }
            Err(e) => {
                p.changer(Etat::Interrompu);
                *p.erreur.lock().unwrap() = Some(e.code().into());
                Err(e)
            }
        }
    }

    // ══ GROUP DROP : PARTICIPANT ══════════════════════════════════════════

    /// Rejoint une session à partir de son invitation (QR code, lien).
    /// [adresse] : une adresse saisie à la main, quand celles de
    /// l'invitation ne sont pas joignables.
    pub fn rejoindre(&self, invitation: &str, adresse: Option<SocketAddr>) -> Result<String, Erreur> {
        let inv = Invitation::decoder(invitation).ok_or(Erreur::SessionInvalide)?;
        let maintenant = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
        if inv.x < maintenant {
            return Err(Erreur::SessionExpiree);
        }
        let mut adresses: Vec<SocketAddr> = adresse.into_iter().collect();
        adresses.extend(inv.h.iter().filter_map(|h| h.parse::<IpAddr>().ok()).map(|ip| SocketAddr::new(ip, inv.p)));
        let cible = Cible { adresses, empreinte: Some(inv.fp.clone()), nom: inv.n.clone() };
        let s = self.enregistrer(Arc::new(Suivi::nouveau(self.nouvel_id("t"), inv.s.clone(), Sens::Reception)));
        *s.pair.lock().unwrap() = Pair {
            nom: inv.n.clone(),
            plateforme: String::new(),
            empreinte: inv.fp.clone(),
            courte: EmpreinteAppareil::depuis_hex(&inv.fp).map(|e| e.courte()).unwrap_or_default(),
        };
        let id = s.id.clone();
        let m = self.clone();
        tokio::spawn(async move { m.participer(cible, inv, s).await });
        Ok(id)
    }

    async fn participer(&self, cible: Cible, inv: Invitation, s: Arc<Suivi>) {
        let mut derniere_avancee = Instant::now();
        let mut attente = Duration::from_secs(1);
        loop {
            if !self.0.actif.load(Ordering::Relaxed) {
                s.changer(Etat::Interrompu);
                return;
            }
            if s.annule.load(Ordering::Relaxed) {
                s.changer(Etat::Annule);
                return;
            }
            let avant = s.octets.load(Ordering::Relaxed);
            let r = self.une_participation(&cible, &inv, &s).await;
            if s.octets.load(Ordering::Relaxed) > avant {
                derniere_avancee = Instant::now();
                attente = Duration::from_secs(1);
            }
            match r {
                Ok(true) => {
                    s.changer(Etat::Termine);
                    return;
                }
                // L'hôte n'a pas encore lancé la distribution (ou l'a mise en
                // pause) : on patiente sans limite tant que la session vit.
                Ok(false) => {
                    derniere_avancee = Instant::now();
                    tokio::select! {
                        _ = tokio::time::sleep(Duration::from_secs(2)) => {}
                        _ = s.reveil.notified() => {}
                    }
                }
                Err(Erreur::Annule) | Err(Erreur::AnnuleParLAutre) => {
                    s.changer(Etat::Annule);
                    return;
                }
                Err(e) if (e.passagere() || matches!(e, Erreur::EnPause)) && derniere_avancee.elapsed() < PATIENCE_REPRISE => {
                    *s.erreur.lock().unwrap() = Some(e.code().into());
                    s.changer(Etat::Interrompu);
                    tokio::select! {
                        _ = tokio::time::sleep(attente) => {}
                        _ = s.reveil.notified() => {}
                    }
                    attente = (attente * 2).min(Duration::from_secs(15));
                }
                Err(e) => {
                    s.echouer(e.code());
                    return;
                }
            }
        }
    }

    /// Une connexion à l'hôte. `Ok(true)` : tout est reçu ; `Ok(false)` :
    /// pas encore notre tour.
    async fn une_participation(&self, cible: &Cible, inv: &Invitation, s: &Arc<Suivi>) -> Result<bool, Erreur> {
        if !matches!(s.etat(), Etat::EnAttente) {
            s.changer(Etat::Connexion);
        }
        let (tls, _) = self.connecter(cible).await?;
        let (mut r, mut w) = tokio::io::split(tls);
        let autre = self.bonjour(&mut r, &mut w).await?;
        {
            let mut p = s.pair.lock().unwrap();
            p.nom = autre.nom;
            p.plateforme = autre.plateforme;
        }
        trame::ecrire_controle(&mut w, &Controle::Rejoindre { session: inv.s.clone(), jeton: inv.j.clone() }).await?;
        let manifeste = loop {
            let m = tokio::select! {
                m = trame::lire_controle(&mut r) => m?,
                _ = s.reveil.notified() => {
                    if s.annule.load(Ordering::Relaxed) {
                        return Err(Erreur::Annule);
                    }
                    continue;
                }
            };
            match m {
                Controle::Attente => s.changer(Etat::EnAttente),
                Controle::Refus { raison } => {
                    return match raison.as_str() {
                        "attente" => {
                            s.changer(Etat::EnAttente);
                            Ok(false)
                        }
                        "deja_recu" => Ok(true),
                        "session_expiree" => Err(Erreur::SessionExpiree),
                        _ => Err(Erreur::SessionInvalide),
                    };
                }
                Controle::Offre { manifeste, .. } => break manifeste,
                Controle::Annuler => return Err(Erreur::AnnuleParLAutre),
                _ => return Err(Erreur::Protocole("offre attendue")),
            }
        };
        let manifeste = manifeste.valider().map_err(|_| Erreur::Protocole("manifeste invalide"))?;
        self.recevoir_accepte(&mut r, &mut w, manifeste, &inv.fp, s).await.map(|_| true)
    }

    // ══ RECEVOIR ══════════════════════════════════════════════════════════

    async fn recevoir_accepte<R: AsyncRead + Unpin, W: AsyncWrite + Unpin>(
        &self,
        r: &mut R,
        w: &mut W,
        manifeste: Manifeste,
        expediteur: &str,
        s: &Arc<Suivi>,
    ) -> Result<(), Erreur> {
        let reception = self.0.config.read().unwrap().reception.clone();
        s.total.store(manifeste.taille_totale(), Ordering::Relaxed);
        *s.fichiers.lock().unwrap() = manifeste.fichiers.iter().map(|f| (f.chemin.clone(), f.taille)).collect();
        let partiel = Partiel::ouvrir(&reception, &manifeste, expediteur).await?;
        let deja = partiel.octets_deja();
        if !espace_suffisant(&reception, manifeste.taille_totale().saturating_sub(deja)) && !partiel.reprise {
            trame::ecrire_controle(w, &Controle::Reponse { acceptee: false, deja: vec![], raison: Some("espace_insuffisant".into()) }).await?;
            partiel.effacer().await;
            return Err(Erreur::EspaceInsuffisant);
        }
        s.octets.store(deja, Ordering::Relaxed);
        if partiel.reprise {
            s.changer(Etat::Reprise);
        }
        trame::ecrire_controle(w, &Controle::Reponse { acceptee: true, deja: partiel.cartes(), raison: None }).await?;
        let chemins = reception::recevoir(r, w, partiel, &reception, s).await?;
        *s.chemins.lock().unwrap() = chemins.iter().map(|p| p.to_string_lossy().into_owned()).collect();
        Ok(())
    }

    // ══ ÉCOUTER ═══════════════════════════════════════════════════════════

    fn noter_echec(&self, ip: IpAddr) {
        let mut e = self.0.echecs.lock().unwrap();
        let x = e.entry(ip).or_insert((0, Instant::now()));
        if x.1.elapsed() > Duration::from_secs(60) {
            *x = (0, Instant::now());
        }
        x.0 += 1;
    }

    /// Trop de tentatives ratées depuis cette adresse dans la minute.
    fn bloque(&self, ip: IpAddr) -> bool {
        let e = self.0.echecs.lock().unwrap();
        e.get(&ip).is_some_and(|x| x.0 >= 20 && x.1.elapsed() < Duration::from_secs(60))
    }

    async fn ecouter(self, ecoute: TcpListener) {
        let poignees = Arc::new(Semaphore::new(128));
        while self.0.actif.load(Ordering::Relaxed) {
            let accepte = tokio::select! {
                a = ecoute.accept() => a,
                _ = self.0.arret.notified() => break,
            };
            let Ok((tcp, adresse)) = accepte else { continue };
            if self.bloque(adresse.ip()) {
                continue;
            }
            let Ok(permis) = poignees.clone().try_acquire_owned() else { continue };
            let m = self.clone();
            tokio::spawn(async move {
                let _ = tcp.set_nodelay(true);
                let tls = match tokio::time::timeout(DELAI_POIGNEE, m.0.acceptor.accept(tcp)).await {
                    Ok(Ok(t)) => t,
                    _ => {
                        m.noter_echec(adresse.ip());
                        return;
                    }
                };
                drop(permis);
                let Some(fp) = empreinte_du_pair(tls.get_ref().1.peer_certificates()) else { return };
                let (mut r, mut w) = tokio::io::split(tls);
                let Ok(autre) = m.bonjour(&mut r, &mut w).await else { return };
                let premier = match tokio::time::timeout(DELAI_POIGNEE, trame::lire_controle(&mut r)).await {
                    Ok(Ok(c)) => c,
                    _ => return,
                };
                match premier {
                    Controle::Offre { offre, manifeste } => {
                        let _ = m.recevoir_offre(r, w, offre, manifeste, fp, autre).await;
                    }
                    Controle::Rejoindre { session, jeton } => {
                        let _ = m.heberger(r, w, session, jeton, fp, autre, adresse.ip()).await;
                    }
                    _ => m.noter_echec(adresse.ip()),
                }
            });
        }
    }

    async fn recevoir_offre<R: AsyncRead + Unpin, W: AsyncWrite + Unpin>(
        &self,
        mut r: R,
        mut w: W,
        offre: String,
        manifeste: Manifeste,
        fp: EmpreinteAppareil,
        autre: Appareil,
    ) -> Result<(), Erreur> {
        let Ok(manifeste) = manifeste.valider() else {
            trame::ecrire_controle(&mut w, &Controle::Reponse { acceptee: false, deja: vec![], raison: Some("manifeste_invalide".into()) }).await?;
            return Err(Erreur::Protocole("manifeste invalide"));
        };
        let reception = self.0.config.read().unwrap().reception.clone();
        let pair = Pair { nom: autre.nom, plateforme: autre.plateforme, empreinte: fp.hex(), courte: fp.courte() };
        // Une reprise : le partiel existe déjà, l'utilisateur avait accepté.
        let deja_accepte = existe_partiel(&reception, &manifeste, &fp.hex()).await;
        // Le même envoi qui revient après une coupure garde son suivi.
        let existant = self
            .0
            .suivis
            .lock()
            .unwrap()
            .values()
            .find(|s| s.sens == Sens::Reception && s.groupe == offre && s.pair.lock().unwrap().empreinte == pair.empreinte && !s.etat().final_())
            .cloned();
        let s = existant.unwrap_or_else(|| self.enregistrer(Arc::new(Suivi::nouveau(self.nouvel_id("t"), offre.clone(), Sens::Reception))));
        *s.pair.lock().unwrap() = pair.clone();
        s.total.store(manifeste.taille_totale(), Ordering::Relaxed);
        let fichiers: Vec<(String, u64)> = manifeste.fichiers.iter().map(|f| (f.chemin.clone(), f.taille)).collect();
        *s.fichiers.lock().unwrap() = fichiers.clone();

        let confiance = self.0.config.read().unwrap().confiance.iter().any(|c| egal_constant(c, &fp.hex()));
        if !deja_accepte && !confiance {
            s.changer(Etat::AttenteReponse);
            let (tx, rx) = oneshot::channel();
            let cle = s.id.clone();
            self.0.offres.lock().unwrap().insert(cle.clone(), tx);
            let _ = self.0.evenements.send(Evenement::Offre { offre: cle.clone(), de: pair, fichiers, total: manifeste.taille_totale() });
            let delai = self.0.config.read().unwrap().delai_reponse;
            let accepte = matches!(tokio::time::timeout(delai, rx).await, Ok(Ok(true)));
            if self.0.offres.lock().unwrap().remove(&cle).is_some() {
                let _ = self.0.evenements.send(Evenement::OffreRetiree { offre: cle });
            }
            if !accepte {
                trame::ecrire_controle(&mut w, &Controle::Reponse { acceptee: false, deja: vec![], raison: None }).await?;
                s.changer(Etat::Refuse);
                return Ok(());
            }
        }
        match self.recevoir_accepte(&mut r, &mut w, manifeste, &fp.hex(), &s).await {
            Ok(()) => {
                s.changer(Etat::Termine);
                Ok(())
            }
            Err(Erreur::Annule) | Err(Erreur::AnnuleParLAutre) => {
                s.changer(Etat::Annule);
                Ok(())
            }
            Err(e @ (Erreur::Verification | Erreur::EspaceInsuffisant | Erreur::Protocole(_))) => {
                s.echouer(e.code());
                Err(e)
            }
            Err(e) => {
                // Coupure : le partiel est gardé, l'expéditeur reviendra.
                *s.erreur.lock().unwrap() = Some(e.code().into());
                s.changer(Etat::Interrompu);
                Err(e)
            }
        }
    }

    // ══ RACONTER ══════════════════════════════════════════════════════════

    /// Quatre fois par seconde : l'état de chaque transfert vivant, avec
    /// son débit mesuré et le temps restant qui en découle.
    async fn raconter(self) {
        let mut precedents: HashMap<String, (u64, Instant, f64)> = HashMap::new();
        let mut finis: std::collections::HashSet<String> = std::collections::HashSet::new();
        let mut sessions_dites: HashMap<String, (usize, usize, String)> = HashMap::new();
        while self.0.actif.load(Ordering::Relaxed) {
            tokio::time::sleep(Duration::from_millis(250)).await;
            let suivis: Vec<Arc<Suivi>> = self.0.suivis.lock().unwrap().values().cloned().collect();
            for s in suivis {
                if finis.contains(&s.id) {
                    continue;
                }
                let etat = s.etat();
                let octets = s.octets.load(Ordering::Relaxed);
                let total = s.total.load(Ordering::Relaxed);
                let maintenant = Instant::now();
                let (av, t, moyenne) = precedents.get(&s.id).copied().unwrap_or((octets, maintenant, 0.0));
                let dt = maintenant.duration_since(t).as_secs_f64();
                let instant = if dt > 0.0 { octets.saturating_sub(av) as f64 / dt } else { 0.0 };
                let debit = if matches!(etat, Etat::Transfert) { if moyenne == 0.0 { instant } else { moyenne * 0.7 + instant * 0.3 } } else { 0.0 };
                precedents.insert(s.id.clone(), (octets, maintenant, debit));
                let restant = (debit > 1024.0 && total > octets).then(|| ((total - octets) as f64 / debit).ceil() as u64);
                let _ = self.0.evenements.send(Evenement::Transfert {
                    id: s.id.clone(),
                    groupe: s.groupe.clone(),
                    sens: s.sens,
                    pair: s.pair.lock().unwrap().clone(),
                    etat,
                    octets,
                    total,
                    debit: debit as u64,
                    restant,
                    erreur: s.erreur.lock().unwrap().clone(),
                    chemins: s.chemins.lock().unwrap().clone(),
                    fichiers: s.fichiers.lock().unwrap().clone(),
                });
                if etat.final_() {
                    finis.insert(s.id.clone());
                }
            }
            let sessions: Vec<Arc<Session>> = self.0.sessions.lock().unwrap().values().cloned().collect();
            for s in sessions {
                let parts = s.participants.lock().unwrap();
                let n = parts.len();
                let fin = parts.values().filter(|p| p.etat() == Etat::Termine).count();
                let etat = if s.terminee.load(Ordering::Relaxed) {
                    "terminee"
                } else if s.pause.load(Ordering::Relaxed) {
                    "pause"
                } else if s.demarree.load(Ordering::Relaxed) {
                    "en_cours"
                } else {
                    "ouverte"
                };
                let dit = (n, fin, etat.to_string());
                if sessions_dites.get(&s.id) != Some(&dit) {
                    sessions_dites.insert(s.id.clone(), dit);
                    let _ = self.0.evenements.send(Evenement::Session { session: s.id.clone(), etat: etat.into(), participants: n, termines: fin });
                }
            }
        }
    }
}

/// Le partiel de ce manifeste, venant de cet expéditeur, existe-t-il ?
async fn existe_partiel(reception: &std::path::Path, manifeste: &Manifeste, expediteur: &str) -> bool {
    let cle = blake3::hash(format!("{}|{}", manifeste.cle(), expediteur).as_bytes()).to_hex()[..32].to_string();
    tokio::fs::metadata(reception::dossier_partiels(reception).join(cle).join("etat.json")).await.is_ok()
}

/// Les cartes reçues d'un pair, rendues cohérentes avec le manifeste
/// (une carte invalide compte comme vide).
fn coherentes(deja: Vec<drop_core::CarteBlocs>, m: &Manifeste) -> Vec<drop_core::CarteBlocs> {
    m.fichiers
        .iter()
        .enumerate()
        .map(|(i, f)| match deja.get(i) {
            Some(c) if c.valide_pour(f.nombre_blocs()) => c.clone(),
            _ => drop_core::CarteBlocs::vide(f.nombre_blocs()),
        })
        .collect()
}

fn nettoyer_appareil(a: Appareil) -> Appareil {
    let propre = |s: String, max: usize| -> String { s.chars().filter(|c| !c.is_control()).take(max).collect() };
    Appareil { nom: propre(a.nom, 64), plateforme: propre(a.plateforme, 24) }
}

/// Les adresses IPv4 locales de cet appareil (hors boucle locale).
pub fn adresses_locales() -> Vec<String> {
    let mut v: Vec<String> = if_addrs::get_if_addrs()
        .map(|l| {
            l.into_iter()
                .filter(|i| !i.is_loopback())
                .filter_map(|i| match i.ip() {
                    IpAddr::V4(a) if !a.is_link_local() => Some(a.to_string()),
                    _ => None,
                })
                .collect()
        })
        .unwrap_or_default();
    v.sort();
    v.dedup();
    v.truncate(6);
    if v.is_empty() {
        v.push("127.0.0.1".into());
    }
    v
}

#[cfg(test)]
mod tests_invitation {
    use super::*;

    fn exemple() -> Invitation {
        Invitation { v: 1, h: vec!["192.168.1.12".into()], p: 47321, fp: "ab".repeat(32), s: "0".repeat(32), j: "f".repeat(64), n: "Cours".into(), x: 2_000_000_000 }
    }

    /// Le lien web, l'ancien lien, et l'invitation nue : les trois se lisent.
    #[test]
    fn liens_web_et_anciens() {
        let lien = exemple().encoder();
        assert!(lien.starts_with("https://drop.dropletmesh.app/rejoindre/#"));
        let charge = lien.rsplit('#').next().unwrap();
        for texte in [lien.clone(), format!("dropletdrop://rejoindre#{charge}"), charge.to_string(), format!("  {lien}\n")] {
            let i = Invitation::decoder(&texte).expect("invitation lisible");
            assert_eq!(i.n, "Cours");
            assert_eq!(i.p, 47321);
        }
        assert!(Invitation::decoder("https://drop.dropletmesh.app/rejoindre/#abc").is_none());
    }
}
