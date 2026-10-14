//! # Le moteur de transfert de Droplet Drop
//!
//! * `trame` et `protocole` — ce qui circule sur la connexion TLS ;
//! * `reception` et `envoi` — les deux bouts d'un transfert, avec reprise
//!   et vérification ;
//! * `moteur` — l'appareil : il écoute, propose, envoie à plusieurs, tient
//!   les sessions Group Drop, et raconte tout à l'interface.

pub mod envoi;
pub mod moteur;
pub mod protocole;
pub mod reception;
pub mod suivi;
pub mod trame;

pub use moteur::{adresses_locales, Cible, Config, InfoSession, Invitation, Moteur};
pub use suivi::{Etat, Evenement, Pair, Sens};

#[derive(Debug, thiserror::Error)]
pub enum Erreur {
    #[error("entrée/sortie : {0}")]
    Io(#[from] std::io::Error),
    #[error("protocole : {0}")]
    Protocole(&'static str),
    #[error("connexion interrompue")]
    ConnexionInterrompue,
    #[error("appareil injoignable")]
    Injoignable,
    #[error("l'appareil n'est pas celui attendu")]
    EmpreinteInvalide,
    #[error("refusé")]
    Refuse,
    #[error("espace insuffisant")]
    EspaceInsuffisant,
    #[error("session invalide")]
    SessionInvalide,
    #[error("session expirée")]
    SessionExpiree,
    #[error("code incorrect")]
    CodeIncorrect,
    #[error("fichier introuvable")]
    FichierIntrouvable,
    #[error("vérification échouée")]
    Verification,
    #[error("annulé")]
    Annule,
    #[error("annulé par l'autre appareil")]
    AnnuleParLAutre,
    #[error("en pause")]
    EnPause,
    #[error("tls : {0}")]
    Tls(String),
}

impl Erreur {
    /// Le code stable que l'interface traduit en phrase claire, dans la
    /// langue de l'utilisateur (« Connexion interrompue — le transfert
    /// reprendra… »). Jamais de message technique à l'écran.
    pub fn code(&self) -> &'static str {
        match self {
            Erreur::Io(e) if e.kind() == std::io::ErrorKind::StorageFull => "espace_insuffisant",
            Erreur::Io(e) if e.kind() == std::io::ErrorKind::PermissionDenied => "acces_refuse",
            Erreur::Io(_) | Erreur::ConnexionInterrompue => "connexion_interrompue",
            Erreur::Protocole(_) => "protocole",
            Erreur::Injoignable => "injoignable",
            Erreur::EmpreinteInvalide => "empreinte_invalide",
            Erreur::Refuse => "refuse",
            Erreur::EspaceInsuffisant => "espace_insuffisant",
            Erreur::SessionInvalide => "session_invalide",
            Erreur::SessionExpiree => "session_expiree",
            Erreur::CodeIncorrect => "code_incorrect",
            Erreur::FichierIntrouvable => "fichier_introuvable",
            Erreur::Verification => "verification",
            Erreur::Annule | Erreur::AnnuleParLAutre => "annule",
            Erreur::EnPause => "pause",
            Erreur::Tls(_) => "connexion_securisee",
        }
    }

    /// Une erreur passagère : on retentera tout seul.
    pub fn passagere(&self) -> bool {
        matches!(self, Erreur::Io(_) | Erreur::ConnexionInterrompue | Erreur::Injoignable | Erreur::Tls(_))
    }
}
