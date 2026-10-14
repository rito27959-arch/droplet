//! # La découverte des appareils autour de soi (mDNS / DNS-SD)
//!
//! Chaque appareil s'annonce sous `_droplet-drop._tcp.local.` avec :
//!
//! * `n` — son nom (« MacBook de Léa ») ;
//! * `p` — sa plateforme (android, ios, windows, macos, linux) ;
//! * `fp` — l'empreinte de son certificat : c'est elle qui sera ÉPINGLÉE à
//!   la connexion. Un appareil qui annoncerait l'empreinte d'un autre ne
//!   pourrait pas finir la poignée de main TLS sans sa clé privée.
//! * `v` — la version du protocole ;
//! * `t` — (facultatif) les appareils à qui cet appareil essaie d'envoyer
//!   sans parvenir à les joindre : les 16 premiers caractères de leur
//!   empreinte, séparés par des virgules. Un appareil qui s'y reconnaît
//!   vient chercher l'envoi lui-même (son pare-feu bloque l'entrant, pas
//!   le sortant).
//!
//! ⚠️ La découverte n'est pas garantie : beaucoup de réseaux (Wi-Fi
//! d'entreprise, d'école, « isolation des clients ») bloquent le
//! multicast. L'application propose donc toujours le QR code et l'adresse
//! manuelle — et le dit clairement à l'utilisateur.

use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::sync::{Arc, Mutex};

use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};
use serde::{Deserialize, Serialize};

pub const TYPE_SERVICE: &str = "_droplet-drop._tcp.local.";

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppareilVu {
    /// Identifiant stable de l'annonce (nom complet mDNS).
    pub id: String,
    pub nom: String,
    pub plateforme: String,
    pub empreinte: String,
    pub adresses: Vec<SocketAddr>,
    /// Les débuts d'empreinte des appareils que celui-ci attend (`t`).
    #[serde(default)]
    pub tirage: Vec<String>,
    /// Les distributions Group Drop que cet appareil ouvre à ses voisins
    /// (`g`) : les huit premiers caractères de leur identifiant, rien de
    /// secret. Pour en obtenir l'invitation, il faut le code à six
    /// chiffres affiché sur l'écran de l'hôte.
    #[serde(default)]
    pub distributions: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Decouverte {
    Trouve(AppareilVu),
    Perdu { id: String },
}

pub struct Annonceur {
    demon: ServiceDaemon,
    nom_complet: String,
    annonce: Mutex<Annonce>,
    vus: Arc<Mutex<HashMap<String, AppareilVu>>>,
}

#[derive(Debug)]
pub struct ErreurDecouverte(pub String);

impl std::fmt::Display for ErreurDecouverte {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "découverte : {}", self.0)
    }
}

impl std::error::Error for ErreurDecouverte {}

fn err(e: impl std::fmt::Display) -> ErreurDecouverte {
    ErreurDecouverte(e.to_string())
}

/// De quoi refaire l'annonce quand la liste `t` change.
struct Annonce {
    instance: String,
    hote: String,
    nom: String,
    plateforme: String,
    empreinte: String,
    port: u16,
    tirage: String,
    distributions: String,
}

impl Annonce {
    fn info(&self) -> Result<ServiceInfo, ErreurDecouverte> {
        let mut proprietes = vec![("n", self.nom.as_str()), ("p", self.plateforme.as_str()), ("fp", self.empreinte.as_str()), ("v", "1")];
        if !self.tirage.is_empty() {
            proprietes.push(("t", self.tirage.as_str()));
        }
        if !self.distributions.is_empty() {
            proprietes.push(("g", self.distributions.as_str()));
        }
        Ok(ServiceInfo::new(TYPE_SERVICE, &self.instance, &self.hote, "", self.port, &proprietes[..]).map_err(err)?.enable_addr_auto())
    }
}

impl Annonceur {
    /// S'annonce et commence à chercher les autres. [rappel] reçoit chaque
    /// apparition et disparition (depuis un fil à part).
    pub fn demarrer(nom: &str, plateforme: &str, empreinte: &str, port: u16, rappel: impl Fn(Decouverte) + Send + 'static) -> Result<Self, ErreurDecouverte> {
        let demon = ServiceDaemon::new().map_err(err)?;
        // Un nom d'instance unique et sans données personnelles inutiles :
        // le début de l'empreinte.
        let instance = format!("droplet-{}", &empreinte[..12.min(empreinte.len())]);
        let hote = format!("{instance}.local.");
        let annonce = Annonce {
            instance,
            hote,
            nom: nom.to_string(),
            plateforme: plateforme.to_string(),
            empreinte: empreinte.to_string(),
            port,
            tirage: String::new(),
            distributions: String::new(),
        };
        let info = annonce.info()?;
        let nom_complet = info.get_fullname().to_string();
        demon.register(info).map_err(err)?;

        let vus: Arc<Mutex<HashMap<String, AppareilVu>>> = Arc::default();
        let recepteur = demon.browse(TYPE_SERVICE).map_err(err)?;
        let moi = nom_complet.clone();
        let vus2 = vus.clone();
        std::thread::Builder::new()
            .name("droplet-decouverte".into())
            .spawn(move || {
                while let Ok(e) = recepteur.recv() {
                    match e {
                        ServiceEvent::ServiceResolved(r) => {
                            if r.fullname == moi {
                                continue;
                            }
                            let txt = |k: &str| r.txt_properties.get_property_val_str(k).unwrap_or("").to_string();
                            let empreinte = txt("fp");
                            if empreinte.len() != 64 || txt("v") != "1" {
                                continue;
                            }
                            let mut adresses: Vec<SocketAddr> = r
                                .addresses
                                .iter()
                                .map(|a| a.to_ip_addr())
                                .filter(|ip| matches!(ip, IpAddr::V4(_)))
                                .map(|ip| SocketAddr::new(ip, r.port))
                                .collect();
                            adresses.sort();
                            let vu = AppareilVu {
                                id: r.fullname.clone(),
                                nom: txt("n").chars().filter(|c| !c.is_control()).take(64).collect(),
                                plateforme: txt("p").chars().take(24).collect(),
                                empreinte,
                                adresses,
                                tirage: txt("t")
                                    .split(',')
                                    .filter(|x| x.len() == 16 && x.chars().all(|c| c.is_ascii_hexdigit()))
                                    .take(16)
                                    .map(String::from)
                                    .collect(),
                                distributions: txt("g")
                                    .split(',')
                                    .filter(|x| x.len() == 8 && x.chars().all(|c| c.is_ascii_hexdigit()))
                                    .take(8)
                                    .map(String::from)
                                    .collect(),
                            };
                            let nouveau = vus2.lock().unwrap().insert(vu.id.clone(), vu.clone()).as_ref() != Some(&vu);
                            if nouveau {
                                rappel(Decouverte::Trouve(vu));
                            }
                        }
                        ServiceEvent::ServiceRemoved(_, nom) => {
                            if vus2.lock().unwrap().remove(&nom).is_some() {
                                rappel(Decouverte::Perdu { id: nom });
                            }
                        }
                        _ => {}
                    }
                }
            })
            .map_err(err)?;
        Ok(Self { demon, nom_complet, annonce: Mutex::new(annonce), vus })
    }

    /// Annonce les appareils qu'on attend (débuts d'empreinte, voir `t`).
    pub fn signaler(&self, tirage: &[String]) {
        let mut a = self.annonce.lock().unwrap();
        let t = tirage.iter().take(8).cloned().collect::<Vec<_>>().join(",");
        if a.tirage == t {
            return;
        }
        a.tirage = t;
        if let Ok(info) = a.info() {
            let _ = self.demon.register(info);
        }
    }

    /// Change le nom annoncé.
    /// Les distributions ouvertes aux voisins (débuts d'identifiant, 8
    /// caractères hexadécimaux) ; une liste vide les retire de l'annonce.
    pub fn distributions(&self, ids: &[String]) {
        let mut a = self.annonce.lock().unwrap();
        let g = ids.iter().filter(|x| x.len() == 8).take(8).cloned().collect::<Vec<_>>().join(",");
        if a.distributions == g {
            return;
        }
        a.distributions = g;
        if let Ok(info) = a.info() {
            let _ = self.demon.register(info);
        }
    }

    pub fn renommer(&self, nom: &str) {
        let mut a = self.annonce.lock().unwrap();
        a.nom = nom.to_string();
        if let Ok(info) = a.info() {
            let _ = self.demon.register(info);
        }
    }

    pub fn appareils(&self) -> Vec<AppareilVu> {
        self.vus.lock().unwrap().values().cloned().collect()
    }

    pub fn arreter(self) {
        let _ = self.demon.unregister(&self.nom_complet);
        let _ = self.demon.shutdown();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;
    use std::time::Duration;

    /// Deux appareils sur la même machine se trouvent — quand le réseau
    /// (ou le conteneur) laisse passer le multicast. Sinon, le test le dit
    /// et ne conclut rien : c'est exactement le cas où l'application
    /// propose le QR code.
    #[test]
    fn deux_appareils_se_trouvent() {
        let (tx, rx) = mpsc::channel();
        let fa = "a".repeat(64);
        let fb = "b".repeat(64);
        let a = Annonceur::demarrer("Appareil A", "linux", &fa, 47001, |_| {}).unwrap();
        let b = Annonceur::demarrer("Appareil B", "linux", &fb, 47002, move |d| {
            let _ = tx.send(d);
        })
        .unwrap();
        let mut trouve = false;
        while let Ok(d) = rx.recv_timeout(Duration::from_secs(8)) {
            if let Decouverte::Trouve(v) = d {
                if v.empreinte == fa {
                    assert_eq!(v.nom, "Appareil A");
                    assert!(v.adresses.iter().all(|x| x.port() == 47001));
                    trouve = true;
                    break;
                }
            }
        }
        if !trouve {
            println!("MULTICAST INDISPONIBLE ici : découverte non vérifiée (repli QR / adresse)");
        } else {
            // A annonce qu'il attend B : B le voit dans `t`.
            a.signaler(&[fb[..16].to_string()]);
            let mut vu = false;
            while let Ok(d) = rx.recv_timeout(Duration::from_secs(8)) {
                if let Decouverte::Trouve(v) = d {
                    if v.empreinte == fa && v.tirage == vec![fb[..16].to_string()] {
                        vu = true;
                        break;
                    }
                }
            }
            assert!(vu, "l'annonce `t` n'est pas arrivée");
        }
        a.arreter();
        b.arreter();
    }
}
