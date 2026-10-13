//! # Le cœur de Droplet Drop
//!
//! Ce qui ne dépend ni du réseau ni de la plateforme :
//!
//! * le **manifeste** d'un envoi — la liste des fichiers, leur taille, et
//!   l'empreinte BLAKE3 de chacun de leurs blocs. C'est lui qui permet de
//!   vérifier chaque bloc à l'arrivée, de reprendre un transfert interrompu
//!   là où il s'était arrêté, et (plus tard) de récupérer des blocs auprès
//!   d'autres participants sans leur faire confiance ;
//! * les **chemins sûrs** — un nom de fichier venu d'ailleurs ne doit jamais
//!   pouvoir écrire hors du dossier de réception, ni écraser un fichier ;
//! * la **carte des blocs** reçus.
//!
//! Aucun fichier n'est jamais chargé en entier en mémoire : on lit et on
//! hache par tranches.

pub mod bitmap;
pub mod chemins;
pub mod manifeste;

pub use bitmap::CarteBlocs;
pub use chemins::{chemin_libre, nettoyer_chemin};
pub use manifeste::{construire_manifeste, verifier_fichier, Empreinte, FichierManifeste, Manifeste, SourceFichier};

/// Taille des blocs par défaut : 4 Mio. Assez grand pour que le manifeste
/// d'un fichier de 10 Go reste petit (2 560 empreintes, 80 Ko), assez petit
/// pour qu'un bloc abîmé ne coûte presque rien à renvoyer.
pub const TAILLE_BLOC: u32 = 4 * 1024 * 1024;

/// Taille d'une tranche de lecture/écriture : la mémoire utilisée par un
/// transfert ne dépasse pas quelques tranches, quelle que soit la taille du
/// fichier.
pub const TAILLE_TRANCHE: usize = 256 * 1024;

/// Garde-fous contre les manifestes démesurés ou malveillants.
pub const MAX_FICHIERS: usize = 100_000;
pub const MAX_TAILLE_TOTALE: u64 = 4 * 1024 * 1024 * 1024 * 1024; // 4 Tio

#[derive(Debug, thiserror::Error)]
pub enum ErreurCoeur {
    #[error("entrée/sortie : {0}")]
    Io(#[from] std::io::Error),
    #[error("manifeste invalide : {0}")]
    ManifesteInvalide(&'static str),
}
