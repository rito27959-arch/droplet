//! Les messages de contrôle (JSON, champ `t`).
//!
//! Envoi direct (« push ») — l'expéditeur se connecte au destinataire :
//!
//! ```text
//!   E → D  Bonjour            D → E  Bonjour
//!   E → D  Offre              D → E  Reponse (acceptée + blocs déjà reçus)
//!   E → D  tranches…  Fin
//!   D → E  Manquants (s'il en reste après vérification)  → E renvoie, Fin
//!   D → E  Recu                                          (terminé)
//! ```
//!
//! Group Drop (« pull ») — chaque participant se connecte à l'hôte et
//! rejoint la session avec son jeton ; ensuite, l'hôte joue le rôle de
//! l'expéditeur ci-dessus :
//!
//! ```text
//!   P → H  Bonjour            H → P  Bonjour
//!   P → H  Rejoindre          H → P  Offre | Refus
//!   P → H  Reponse            H → P  tranches…  Fin   …   P → H  Recu
//! ```
//!
//! À tout moment : `Annuler`, `Pause` (la connexion se ferme, le transfert
//! partiel est gardé et reprendra par la carte des blocs).

use drop_core::{CarteBlocs, Manifeste};
use serde::{Deserialize, Serialize};

pub const VERSION: u32 = 1;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct Appareil {
    pub nom: String,
    pub plateforme: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "t", rename_all = "snake_case")]
pub enum Controle {
    Bonjour { v: u32, appareil: Appareil },
    Offre { offre: String, manifeste: Manifeste },
    Reponse {
        acceptee: bool,
        /// Pour chaque fichier du manifeste, dans l'ordre : ce qui est déjà là.
        #[serde(default)]
        deja: Vec<CarteBlocs>,
        #[serde(default)]
        raison: Option<String>,
    },
    Fin,
    Manquants { fichier: u32, blocs: Vec<u32> },
    Recu,
    Rejoindre { session: String, jeton: String },
    Refus { raison: String },
    /// L'hôte d'une session : « patientez, votre tour arrive ».
    Attente,
    Pause,
    Annuler,
}
