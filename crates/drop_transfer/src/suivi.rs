//! Le suivi d'un transfert : ce que l'interface affiche, et les commandes
//! qu'elle donne (pause, annulation).
//!
//! La boucle de transfert ne fait qu'incrémenter un compteur atomique ;
//! c'est le moteur qui, quatre fois par seconde, en déduit le débit et le
//! temps restant et prévient l'interface. Un transfert ne ralentit jamais
//! pour l'affichage.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::Instant;

use serde::{Deserialize, Serialize};
use tokio::sync::Notify;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Etat {
    /// Préparation (calcul des empreintes) ou attente d'un créneau.
    EnAttente,
    Connexion,
    /// Le destinataire doit accepter.
    AttenteReponse,
    Transfert,
    /// Connexion perdue ou mise en pause : le partiel est gardé.
    Interrompu,
    Reprise,
    Verification,
    Termine,
    Refuse,
    Annule,
    Echec,
}

impl Etat {
    pub fn final_(&self) -> bool {
        matches!(self, Etat::Termine | Etat::Refuse | Etat::Annule | Etat::Echec)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Sens {
    Envoi,
    Reception,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Pair {
    pub nom: String,
    pub plateforme: String,
    /// Empreinte complète (hex) et forme courte (« A3F9-2C1B »).
    pub empreinte: String,
    pub courte: String,
}

pub struct Suivi {
    pub id: String,
    /// Les transferts d'un même envoi (plusieurs destinataires) ou d'une
    /// même session Group Drop partagent ce groupe.
    pub groupe: String,
    pub sens: Sens,
    pub pair: Mutex<Pair>,
    pub total: AtomicU64,
    pub octets: AtomicU64,
    pub etat: Mutex<Etat>,
    pub erreur: Mutex<Option<String>>,
    pub chemins: Mutex<Vec<String>>,
    pub fichiers: Mutex<Vec<(String, u64)>>,
    pub pause: AtomicBool,
    pub annule: AtomicBool,
    pub reveil: Notify,
    pub debut: Instant,
}

impl Suivi {
    pub fn nouveau(id: String, groupe: String, sens: Sens) -> Self {
        Self {
            id,
            groupe,
            sens,
            pair: Mutex::new(Pair::default()),
            total: AtomicU64::new(0),
            octets: AtomicU64::new(0),
            etat: Mutex::new(Etat::EnAttente),
            erreur: Mutex::new(None),
            chemins: Mutex::new(Vec::new()),
            fichiers: Mutex::new(Vec::new()),
            pause: AtomicBool::new(false),
            annule: AtomicBool::new(false),
            reveil: Notify::new(),
            debut: Instant::now(),
        }
    }

    pub fn etat(&self) -> Etat {
        *self.etat.lock().unwrap()
    }

    pub fn changer(&self, e: Etat) {
        let mut x = self.etat.lock().unwrap();
        if !x.final_() {
            *x = e;
        }
    }

    pub fn echouer(&self, code: &str) {
        *self.erreur.lock().unwrap() = Some(code.to_string());
        self.changer(Etat::Echec);
    }

    pub fn ajouter(&self, n: u64) {
        self.octets.fetch_add(n, Ordering::Relaxed);
    }

    pub fn arret_demande(&self) -> bool {
        self.annule.load(Ordering::Relaxed) || self.pause.load(Ordering::Relaxed)
    }
}

/// Ce que l'interface reçoit.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Evenement {
    /// Quelqu'un propose des fichiers : il faut accepter ou refuser.
    Offre { offre: String, de: Pair, fichiers: Vec<(String, u64)>, total: u64 },
    /// L'offre n'attend plus de réponse (expirée, annulée par l'expéditeur).
    OffreRetiree { offre: String },
    Transfert {
        id: String,
        groupe: String,
        sens: Sens,
        pair: Pair,
        etat: Etat,
        octets: u64,
        total: u64,
        /// Octets par seconde (moyenne glissante).
        debit: u64,
        /// Secondes restantes estimées à partir du débit mesuré.
        restant: Option<u64>,
        erreur: Option<String>,
        chemins: Vec<String>,
        fichiers: Vec<(String, u64)>,
    },
    /// La préparation d'un envoi (lecture et empreintes des fichiers).
    Preparation { groupe: String, octets: u64, total: u64 },
    Session { session: String, etat: String, participants: usize, termines: usize },
}
