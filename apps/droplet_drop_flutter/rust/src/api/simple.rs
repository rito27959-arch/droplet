//! L'interface entre l'application Flutter et le moteur Rust.
//!
//! Volontairement simple : des chaînes, des nombres, et du JSON pour les
//! structures riches (les événements, les listes). Le moteur tourne dans
//! son propre runtime tokio ; l'interface ne fait qu'appeler et écouter.
//!
//! Les événements (un seul flux) sont des objets JSON avec un champ
//! `type` : `offre`, `offre_retiree`, `transfert`, `preparation`,
//! `session`, `appareil_trouve`, `appareil_perdu`.

use std::collections::HashSet;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use drop_core::SourceFichier;
use drop_discovery::{Annonceur, Decouverte};
use drop_storage::{Entree, Historique};
use drop_transfer::{Cible, Config, Etat, Evenement, Moteur, Sens};

use crate::frb_generated::StreamSink;

struct Global {
    rt: tokio::runtime::Runtime,
    moteur: Moteur,
    annonceur: Mutex<Option<Annonceur>>,
    historique: Mutex<Historique>,
    abonnes: Arc<Mutex<Vec<StreamSink<String>>>>,
    /// La page ouverte aux navigateurs (une à la fois).
    web: Mutex<Option<drop_web::PartageWeb>>,
}

static GLOBAL: OnceLock<Global> = OnceLock::new();

fn g() -> anyhow::Result<&'static Global> {
    GLOBAL.get().ok_or_else(|| anyhow::anyhow!("moteur non démarré"))
}

fn diffuser(abonnes: &Arc<Mutex<Vec<StreamSink<String>>>>, json: String) {
    let mut l = abonnes.lock().unwrap();
    l.retain(|s| s.add(json.clone()).is_ok());
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// Ce que l'appareil sait de lui-même.
pub struct InfoAppareil {
    pub empreinte: String,
    pub courte: String,
    pub port: u16,
    pub adresses: Vec<String>,
}

/// Démarre le moteur (une seule fois), la découverte et l'historique.
pub fn demarrer(nom: String, plateforme: String, donnees: String, reception: String) -> anyhow::Result<InfoAppareil> {
    if let Some(gl) = GLOBAL.get() {
        return Ok(info(&gl.moteur));
    }
    let rt = tokio::runtime::Builder::new_multi_thread().worker_threads(4).enable_all().thread_name("droplet-moteur").build()?;
    let mut config = Config::simple(&nom, PathBuf::from(&donnees), PathBuf::from(&reception));
    config.plateforme = plateforme.clone();
    let moteur = rt.block_on(Moteur::demarrer(config))?;
    std::fs::create_dir_all(&donnees)?;
    let historique = Historique::ouvrir(&PathBuf::from(&donnees).join("historique.db"))?;
    let abonnes: Arc<Mutex<Vec<StreamSink<String>>>> = Arc::default();

    // Les événements du moteur → l'interface, et l'historique au passage.
    let mut rx = moteur.abonner();
    let ab = abonnes.clone();
    rt.spawn(async move {
        let mut inscrits: HashSet<String> = HashSet::new();
        loop {
            let e = match rx.recv().await {
                Ok(e) => e,
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(_) => break,
            };
            if let Evenement::Transfert { id, sens, pair, etat, total, chemins, fichiers, .. } = &e {
                if etat.final_() && inscrits.insert(id.clone()) {
                    if let Some(gl) = GLOBAL.get() {
                        let maintenant = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0);
                        let titre = match fichiers.len() {
                            0 => String::new(),
                            1 => fichiers[0].0.rsplit('/').next().unwrap_or("").to_string(),
                            n => format!("{} +{}", fichiers[0].0.rsplit('/').next().unwrap_or(""), n - 1),
                        };
                        let _ = gl.historique.lock().unwrap().enregistrer(&Entree {
                            id: id.clone(),
                            sens: if *sens == Sens::Envoi { "envoi".into() } else { "reception".into() },
                            titre,
                            fichiers: fichiers.len() as u32,
                            taille: *total,
                            appareil: pair.nom.clone(),
                            empreinte: pair.empreinte.clone(),
                            etat: serde_json::to_value(etat).ok().and_then(|v| v.as_str().map(String::from)).unwrap_or_default(),
                            debut: maintenant,
                            fin: maintenant,
                            chemins: chemins.join("\n"),
                        });
                    }
                }
            }
            if let Ok(j) = serde_json::to_string(&e) {
                diffuser(&ab, j);
            }
        }
    });

    // La découverte : facultative (certains réseaux bloquent le multicast).
    let ab = abonnes.clone();
    let moi = moteur.empreinte().hex()[..16].to_string();
    let annonceur = Annonceur::demarrer(&nom, &plateforme, &moteur.empreinte().hex(), moteur.port(), move |d| {
        let j = match d {
            Decouverte::Trouve(a) => {
                // Cet appareil a un envoi pour nous mais ne nous joint pas :
                // on va le chercher.
                if a.tirage.contains(&moi) {
                    tirer(&a);
                }
                serde_json::json!({ "type": "appareil_trouve", "appareil": a })
            }
            Decouverte::Perdu { id } => {
                serde_json::json!({ "type": "appareil_perdu", "id": id })
            }
        };
        diffuser(&ab, j.to_string());
    })
    .ok();

    // Nos envois en attente d'un appareil injoignable → l'annonce `t`.
    let mut demandes = moteur.demandes();
    rt.spawn(async move {
        while demandes.changed().await.is_ok() {
            let l = demandes.borrow_and_update().clone();
            if let Some(a) = GLOBAL.get().and_then(|gl| gl.annonceur.lock().ok()) {
                if let Some(a) = a.as_ref() {
                    a.signaler(&l);
                }
            }
        }
    });
    // Filet de sécurité : une annonce manquée (multicast capricieux) est
    // rattrapée en relisant régulièrement les appareils vus.
    let moi = moteur.empreinte().hex()[..16].to_string();
    rt.spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(3)).await;
            let Some(gl) = GLOBAL.get() else { continue };
            let vus = gl.annonceur.lock().unwrap().as_ref().map(|a| a.appareils()).unwrap_or_default();
            for a in vus.iter().filter(|a| a.tirage.contains(&moi)) {
                tirer(a);
            }
        }
    });

    let i = info(&moteur);
    let _ = GLOBAL.set(Global { rt, moteur, annonceur: Mutex::new(annonceur), historique: Mutex::new(historique), abonnes, web: Mutex::new(None) });
    Ok(i)
}

fn tirer(a: &drop_discovery::AppareilVu) {
    if let Some(gl) = GLOBAL.get() {
        let _guard = gl.rt.enter();
        gl.moteur.tirer(Cible { adresses: a.adresses.clone(), empreinte: Some(a.empreinte.clone()), nom: a.nom.clone() });
    }
}

fn info(m: &Moteur) -> InfoAppareil {
    InfoAppareil { empreinte: m.empreinte().hex(), courte: m.empreinte().courte(), port: m.port(), adresses: drop_transfer::adresses_locales() }
}

/// Le flux des événements (plusieurs écouteurs possibles).
pub fn evenements(sink: StreamSink<String>) -> anyhow::Result<()> {
    g()?.abonnes.lock().unwrap().push(sink);
    Ok(())
}

/// Les appareils découverts en ce moment (JSON : liste).
#[flutter_rust_bridge::frb(sync)]
pub fn appareils() -> String {
    let v = GLOBAL.get().and_then(|gl| gl.annonceur.lock().unwrap().as_ref().map(|a| a.appareils())).unwrap_or_default();
    serde_json::to_string(&v).unwrap_or_else(|_| "[]".into())
}

/// La découverte marche-t-elle sur ce réseau / cette plateforme ?
#[flutter_rust_bridge::frb(sync)]
pub fn decouverte_active() -> bool {
    GLOBAL.get().is_some_and(|gl| gl.annonceur.lock().unwrap().is_some())
}

fn sources(chemins: Vec<String>, noms: Vec<String>) -> anyhow::Result<Vec<SourceFichier>> {
    anyhow::ensure!(chemins.len() == noms.len() && !chemins.is_empty(), "liste de fichiers invalide");
    Ok(chemins.into_iter().zip(noms).map(|(c, n)| SourceFichier { disque: PathBuf::from(c), nom: n }).collect())
}

/// Envoie des fichiers à un ou plusieurs appareils. [cibles] : JSON,
/// `[{"adresses":["192.168.1.12:47321"],"empreinte":"…","nom":"…"}]`.
/// Rend l'identifiant du groupe d'envoi.
pub fn envoyer(chemins: Vec<String>, noms: Vec<String>, cibles: String) -> anyhow::Result<String> {
    let gl = g()?;
    let cibles: Vec<Cible> = serde_json::from_str(&cibles)?;
    anyhow::ensure!(!cibles.is_empty(), "aucun destinataire");
    let s = sources(chemins, noms)?;
    let _guard = gl.rt.enter();
    Ok(gl.moteur.envoyer(s, cibles))
}

/// Une adresse saisie à la main (« 192.168.1.12 » ou « 192.168.1.12:47321 »).
#[flutter_rust_bridge::frb(sync)]
pub fn cible_manuelle(adresse: String, empreinte: Option<String>) -> anyhow::Result<String> {
    let a = adresse.trim();
    let sa: SocketAddr = a.parse().or_else(|_| format!("{a}:{}", drop_transfer::moteur::PORT_DEFAUT).parse())?;
    Ok(serde_json::to_string(&vec![Cible { adresses: vec![sa], empreinte: empreinte.filter(|e| e.len() == 64), nom: a.to_string() }])?)
}

#[flutter_rust_bridge::frb(sync)]
pub fn repondre(offre: String, accepter: bool) -> bool {
    GLOBAL.get().is_some_and(|gl| gl.moteur.repondre(&offre, accepter))
}

#[flutter_rust_bridge::frb(sync)]
pub fn pause(id: String) {
    if let Some(gl) = GLOBAL.get() {
        gl.moteur.pause(&id);
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn reprendre(id: String) {
    if let Some(gl) = GLOBAL.get() {
        gl.moteur.reprendre(&id);
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn annuler(id: String) {
    if let Some(gl) = GLOBAL.get() {
        gl.moteur.annuler(&id);
    }
}

/// Crée une session Group Drop ; rend son JSON (`id`, `invitation`,
/// `expire`, `total`, `fichiers`).
pub fn creer_session(chemins: Vec<String>, noms: Vec<String>, minutes: u32, demarrer: bool) -> anyhow::Result<String> {
    let gl = g()?;
    let s = sources(chemins, noms)?;
    let info = gl.rt.block_on(gl.moteur.creer_session(s, Duration::from_secs(minutes.clamp(1, 24 * 60) as u64 * 60), demarrer))?;
    Ok(serde_json::to_string(&info)?)
}

/// Rejoint une session à partir de son invitation (QR code ou lien).
pub fn rejoindre(invitation: String, adresse: Option<String>) -> anyhow::Result<String> {
    let gl = g()?;
    let adresse = adresse.and_then(|a| {
        let a = a.trim().to_string();
        a.parse::<SocketAddr>().ok().or_else(|| format!("{a}:{}", drop_transfer::moteur::PORT_DEFAUT).parse().ok())
    });
    let _guard = gl.rt.enter();
    Ok(gl.moteur.rejoindre(&invitation, adresse)?)
}

/// Lit une invitation sans la rejoindre (pour l'aperçu) : JSON ou erreur.
#[flutter_rust_bridge::frb(sync)]
pub fn lire_invitation(invitation: String) -> anyhow::Result<String> {
    let i = drop_transfer::Invitation::decoder(&invitation).ok_or_else(|| anyhow::anyhow!("invitation invalide"))?;
    Ok(serde_json::json!({ "nom": i.n, "expire": i.x, "empreinte": i.fp }).to_string())
}

// ── Réglages ─────────────────────────────────────────────────────────────

#[flutter_rust_bridge::frb(sync)]
pub fn definir_nom(nom: String) {
    if let Some(gl) = GLOBAL.get() {
        let nom: String = nom.chars().filter(|c| !c.is_control()).take(64).collect();
        if let Some(a) = gl.annonceur.lock().unwrap().as_ref() {
            a.renommer(&nom);
        }
        gl.moteur.modifier(|c| c.nom = nom);
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn definir_reception(dossier: String) {
    if let Some(gl) = GLOBAL.get() {
        let _ = std::fs::create_dir_all(&dossier);
        gl.moteur.modifier(|c| c.reception = PathBuf::from(dossier));
    }
}

/// Faire confiance (ou plus) aux envois de cet appareil.
#[flutter_rust_bridge::frb(sync)]
pub fn definir_confiance(empreinte: String, confiance: bool) {
    if let Some(gl) = GLOBAL.get() {
        gl.moteur.modifier(|c| {
            c.confiance.retain(|e| e != &empreinte);
            if confiance && empreinte.len() == 64 {
                c.confiance.push(empreinte);
            }
        });
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn confiance() -> Vec<String> {
    GLOBAL.get().map(|gl| gl.moteur.config().confiance).unwrap_or_default()
}

// ── Historique ───────────────────────────────────────────────────────────

#[flutter_rust_bridge::frb(sync)]
pub fn historique(recherche: String) -> String {
    let v = GLOBAL.get().and_then(|gl| gl.historique.lock().unwrap().lister(&recherche, 500).ok()).unwrap_or_default();
    serde_json::to_string(&v).unwrap_or_else(|_| "[]".into())
}

#[flutter_rust_bridge::frb(sync)]
pub fn effacer_historique(id: Option<String>) {
    if let Some(gl) = GLOBAL.get() {
        let h = gl.historique.lock().unwrap();
        let _ = match id {
            Some(i) => h.supprimer(&i),
            None => h.tout_effacer(),
        };
    }
}

/// Les états finaux, pour l'interface.
#[flutter_rust_bridge::frb(sync)]
pub fn version() -> String {
    let _ = Etat::Termine;
    env!("CARGO_PKG_VERSION").to_string()
}

// ── Échanger avec un navigateur ──────────────────────────────────────────

/// Ouvre la page pour les navigateurs : [chemins]/[noms] à télécharger, et
/// si [recevoir], le dépôt de fichiers vers le dossier de réception.
/// [textes] : JSON des textes de la page (dans la langue de l'app).
/// Rend `{"port":…,"jeton":"…","adresses":[…]}`.
pub fn partage_web_demarrer(chemins: Vec<String>, noms: Vec<String>, recevoir: bool, textes: String) -> anyhow::Result<String> {
    let gl = g()?;
    anyhow::ensure!(chemins.len() == noms.len(), "liste de fichiers invalide");
    let jeton = drop_crypto::secret_aleatoire(16);
    let config = drop_web::Config {
        fichiers: chemins.into_iter().map(PathBuf::from).zip(noms).collect(),
        reception: recevoir.then(|| gl.moteur.config().reception),
        jeton: jeton.clone(),
        textes: serde_json::from_str(&textes).unwrap_or_default(),
        nom_appareil: gl.moteur.config().nom,
        port: 47380,
    };
    let ab = gl.abonnes.clone();
    let rappel: drop_web::Rappel = Arc::new(move |v| diffuser(&ab, v.to_string()));
    // L'ancienne page se ferme d'abord.
    if let Some(ancienne) = gl.web.lock().unwrap().take() {
        ancienne.arreter();
    }
    let partage = gl.rt.block_on(drop_web::demarrer(config, rappel))?;
    let port = partage.port;
    *gl.web.lock().unwrap() = Some(partage);
    Ok(serde_json::json!({ "port": port, "jeton": jeton, "adresses": drop_transfer::adresses_locales() }).to_string())
}

#[flutter_rust_bridge::frb(sync)]
pub fn partage_web_arreter() {
    if let Some(gl) = GLOBAL.get() {
        if let Some(p) = gl.web.lock().unwrap().take() {
            p.arreter();
        }
    }
}
