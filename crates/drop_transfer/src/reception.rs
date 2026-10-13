//! Recevoir : écrire chaque tranche à sa place dans un fichier partiel,
//! vérifier chaque bloc, retenir la carte des blocs pour pouvoir reprendre,
//! vérifier le fichier entier, puis le poser dans le dossier de réception
//! sans jamais rien écraser.
//!
//! Les partiels vivent dans `<réception>/.droplet-drop/partiels/<clé>/` :
//!
//! * `etat.json` — le manifeste, l'expéditeur, la carte des blocs ;
//! * `<id>.part` — chaque fichier, à sa taille finale dès le départ.
//!
//! La clé dépend du manifeste ET de l'expéditeur : un autre appareil qui
//! enverrait le même fichier ne peut pas « compléter » un partiel qui
//! n'est pas le sien.

use std::io::SeekFrom;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};

use drop_core::{chemin_libre, verifier_fichier, CarteBlocs, FichierManifeste, Manifeste};
use serde::{Deserialize, Serialize};
use tokio::fs::{File, OpenOptions};
use tokio::io::{AsyncRead, AsyncSeekExt, AsyncWrite, AsyncWriteExt};

use crate::protocole::Controle;
use crate::suivi::{Etat, Suivi};
use crate::trame::{self, Trame};
use crate::Erreur;

const MAX_TOURS_VERIFICATION: u32 = 5;

#[derive(Serialize, Deserialize)]
struct EtatPartiel {
    expediteur: String,
    manifeste: Manifeste,
    cartes: Vec<CarteBlocs>,
}

pub struct Partiel {
    dossier: PathBuf,
    etat: EtatPartiel,
    sauve: Instant,
    pub reprise: bool,
}

pub fn dossier_partiels(reception: &Path) -> PathBuf {
    reception.join(".droplet-drop").join("partiels")
}

impl Partiel {
    /// Ouvre (ou crée) le partiel de ce manifeste venant de cet expéditeur.
    pub async fn ouvrir(reception: &Path, manifeste: &Manifeste, expediteur: &str) -> Result<Self, Erreur> {
        let cle = blake3::hash(format!("{}|{}", manifeste.cle(), expediteur).as_bytes()).to_hex()[..32].to_string();
        let dossier = dossier_partiels(reception).join(cle);
        let chemin_etat = dossier.join("etat.json");
        if let Ok(brut) = tokio::fs::read(&chemin_etat).await {
            if let Ok(e) = serde_json::from_slice::<EtatPartiel>(&brut) {
                let coherent = e.expediteur == expediteur
                    && e.manifeste == *manifeste
                    && e.cartes.len() == manifeste.fichiers.len()
                    && e.cartes.iter().zip(&manifeste.fichiers).all(|(c, f)| c.valide_pour(f.nombre_blocs()));
                if coherent {
                    return Ok(Self { dossier, etat: e, sauve: Instant::now(), reprise: true });
                }
            }
        }
        tokio::fs::create_dir_all(&dossier).await?;
        for f in &manifeste.fichiers {
            let p = dossier.join(format!("{}.part", f.id));
            let fichier = OpenOptions::new().create(true).write(true).truncate(false).open(&p).await?;
            fichier.set_len(f.taille).await?;
        }
        let etat = EtatPartiel {
            expediteur: expediteur.to_string(),
            manifeste: manifeste.clone(),
            cartes: manifeste.fichiers.iter().map(|f| CarteBlocs::vide(f.nombre_blocs())).collect(),
        };
        let mut p = Self { dossier, etat, sauve: Instant::now(), reprise: false };
        p.sauver().await?;
        Ok(p)
    }

    pub fn cartes(&self) -> Vec<CarteBlocs> {
        self.etat.cartes.clone()
    }

    pub fn octets_deja(&self) -> u64 {
        self.etat
            .manifeste
            .fichiers
            .iter()
            .zip(&self.etat.cartes)
            .map(|(f, c)| (0..f.nombre_blocs()).filter(|&i| c.a(i)).map(|i| f.taille_du_bloc(i) as u64).sum::<u64>())
            .sum()
    }

    async fn sauver(&mut self) -> Result<(), Erreur> {
        let j = serde_json::to_vec(&self.etat).map_err(|_| Erreur::Protocole("état"))?;
        let tmp = self.dossier.join("etat.json.tmp");
        tokio::fs::write(&tmp, j).await?;
        tokio::fs::rename(&tmp, self.dossier.join("etat.json")).await?;
        self.sauve = Instant::now();
        Ok(())
    }

    fn chemin_part(&self, id: u32) -> PathBuf {
        self.dossier.join(format!("{id}.part"))
    }

    pub async fn effacer(self) {
        let _ = tokio::fs::remove_dir_all(&self.dossier).await;
    }
}

/// L'espace libre suffit-il pour ce qui reste à recevoir ?
pub fn espace_suffisant(reception: &Path, besoin: u64) -> bool {
    match fs4::available_space(reception) {
        Ok(libre) => libre >= besoin.saturating_add(64 * 1024 * 1024),
        Err(_) => true, // inconnu : on tente, l'écriture échouera proprement
    }
}

struct BlocEnCours {
    fichier: u32,
    bloc: u32,
    attendu: u32,
    hacheur: blake3::Hasher,
    abime: bool,
}

/// Reçoit les données d'un envoi accepté, jusqu'au bout. Rend les chemins
/// des fichiers posés dans le dossier de réception.
pub async fn recevoir<R, W>(
    lecteur: &mut R,
    ecrivain: &mut W,
    mut partiel: Partiel,
    reception: &Path,
    suivi: &Arc<Suivi>,
) -> Result<Vec<PathBuf>, Erreur>
where
    R: AsyncRead + Unpin,
    W: AsyncWrite + Unpin,
{
    let manifeste = partiel.etat.manifeste.clone();
    let index: std::collections::HashMap<u32, usize> = manifeste.fichiers.iter().enumerate().map(|(i, f)| (f.id, i)).collect();
    let mut ouverts: std::collections::HashMap<u32, (File, u64)> = std::collections::HashMap::new();
    let mut en_cours: Option<BlocEnCours> = None;
    let mut tours = 0;
    let mut depuis_sauvegarde = 0u32;
    suivi.changer(Etat::Transfert);

    loop {
        if suivi.annule.load(std::sync::atomic::Ordering::Relaxed) {
            let _ = trame::ecrire_controle(ecrivain, &Controle::Annuler).await;
            partiel.effacer().await;
            return Err(Erreur::Annule);
        }
        if suivi.pause.load(std::sync::atomic::Ordering::Relaxed) {
            let _ = trame::ecrire_controle(ecrivain, &Controle::Pause).await;
            partiel.sauver().await?;
            return Err(Erreur::EnPause);
        }
        let t = match tokio::time::timeout(Duration::from_secs(60), trame::lire(lecteur)).await {
            Ok(Ok(t)) => t,
            Ok(Err(e)) => {
                let _ = partiel.sauver().await;
                return Err(e);
            }
            Err(_) => {
                let _ = partiel.sauver().await;
                return Err(Erreur::ConnexionInterrompue);
            }
        };
        match t {
            Trame::Donnees { fichier, bloc, decalage, octets } => {
                let Some(&i) = index.get(&fichier) else { return Err(Erreur::Protocole("fichier inconnu")) };
                let f = &manifeste.fichiers[i];
                if bloc >= f.nombre_blocs() {
                    return Err(Erreur::Protocole("bloc hors limites"));
                }
                let taille_bloc = f.taille_du_bloc(bloc);
                if decalage as u64 + octets.len() as u64 > taille_bloc as u64 {
                    return Err(Erreur::Protocole("tranche hors du bloc"));
                }
                // Une nouvelle tranche de bloc : on termine (mal) le précédent
                // s'il était incomplet.
                if decalage == 0 {
                    en_cours = Some(BlocEnCours { fichier, bloc, attendu: 0, hacheur: blake3::Hasher::new(), abime: false });
                }
                let Some(b) = en_cours.as_mut() else { return Err(Erreur::Protocole("tranche orpheline")) };
                if b.fichier != fichier || b.bloc != bloc || b.attendu != decalage {
                    b.abime = true;
                }
                b.hacheur.update(&octets);
                b.attendu = decalage + octets.len() as u32;

                // Écrire à sa place (le partiel a déjà sa taille finale).
                let position = f.decalage(bloc) + decalage as u64;
                let entree = match ouverts.entry(fichier) {
                    std::collections::hash_map::Entry::Occupied(o) => o.into_mut(),
                    std::collections::hash_map::Entry::Vacant(v) => {
                        let fh = OpenOptions::new().write(true).open(partiel.chemin_part(fichier)).await?;
                        v.insert((fh, u64::MAX))
                    }
                };
                if entree.1 != position {
                    entree.0.seek(SeekFrom::Start(position)).await?;
                }
                entree.0.write_all(&octets).await?;
                entree.1 = position + octets.len() as u64;
                suivi.ajouter(octets.len() as u64);

                if b.attendu == taille_bloc {
                    let b = en_cours.take().unwrap();
                    let bon = !b.abime && b.hacheur.finalize().as_bytes() == &f.blocs[bloc as usize].0;
                    if bon {
                        partiel.etat.cartes[i].marquer(bloc);
                    } else {
                        // Compté pour rien : on retire ces octets du compteur.
                        suivi.octets.fetch_sub(taille_bloc as u64, std::sync::atomic::Ordering::Relaxed);
                    }
                    depuis_sauvegarde += 1;
                    if depuis_sauvegarde >= 32 || partiel.sauve.elapsed() > Duration::from_secs(2) {
                        for (fh, _) in ouverts.values_mut() {
                            fh.flush().await?;
                        }
                        partiel.sauver().await?;
                        depuis_sauvegarde = 0;
                    }
                }
            }
            Trame::Controle(Controle::Fin) => {
                for (fh, _) in ouverts.values_mut() {
                    fh.sync_all().await?;
                }
                ouverts.clear();
                partiel.sauver().await?;
                // Ce qui manque encore (blocs abîmés en route).
                let mut manquants = Vec::new();
                for (i, f) in manifeste.fichiers.iter().enumerate() {
                    let m = partiel.etat.cartes[i].manquants();
                    if !m.is_empty() {
                        manquants.push((f.id, m));
                    }
                }
                // Tout est là : vérification complète, fichier par fichier.
                if manquants.is_empty() {
                    suivi.changer(Etat::Verification);
                    for (i, f) in manifeste.fichiers.iter().enumerate() {
                        let p = partiel.chemin_part(f.id);
                        let fm: FichierManifeste = f.clone();
                        let mauvais = tokio::task::spawn_blocking(move || verifier_fichier(&p, &fm))
                            .await
                            .map_err(|_| Erreur::Protocole("vérification"))?
                            .map_err(|e| Erreur::Io(std::io::Error::other(e.to_string())))?;
                        if !mauvais.is_empty() {
                            for &b in &mauvais {
                                partiel.etat.cartes[i].effacer(b);
                                suivi.octets.fetch_sub(f.taille_du_bloc(b) as u64, std::sync::atomic::Ordering::Relaxed);
                            }
                            manquants.push((f.id, mauvais));
                        }
                    }
                    partiel.sauver().await?;
                }
                if manquants.is_empty() {
                    let chemins = poser(&partiel, reception).await?;
                    trame::ecrire_controle(ecrivain, &Controle::Recu).await?;
                    partiel.effacer().await;
                    return Ok(chemins);
                }
                tours += 1;
                if tours > MAX_TOURS_VERIFICATION {
                    return Err(Erreur::Verification);
                }
                suivi.changer(Etat::Transfert);
                for (fichier, blocs) in manquants {
                    trame::ecrire_controle(ecrivain, &Controle::Manquants { fichier, blocs }).await?;
                }
            }
            Trame::Controle(Controle::Annuler) => {
                partiel.effacer().await;
                return Err(Erreur::AnnuleParLAutre);
            }
            Trame::Controle(Controle::Pause) => {
                partiel.sauver().await?;
                return Err(Erreur::EnPause);
            }
            Trame::Controle(_) => return Err(Erreur::Protocole("message inattendu")),
        }
    }
}

/// Déplace les fichiers vérifiés à leur place définitive.
async fn poser(partiel: &Partiel, reception: &Path) -> Result<Vec<PathBuf>, Erreur> {
    let mut chemins = Vec::new();
    for f in &partiel.etat.manifeste.fichiers {
        let destination = chemin_libre(reception, &f.chemin);
        if !destination.starts_with(reception) {
            return Err(Erreur::Protocole("chemin hors du dossier"));
        }
        if let Some(parent) = destination.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }
        let source = partiel.chemin_part(f.id);
        if tokio::fs::rename(&source, &destination).await.is_err() {
            // Autre volume : copie puis effacement.
            tokio::fs::copy(&source, &destination).await?;
            tokio::fs::remove_file(&source).await?;
        }
        chemins.push(destination);
    }
    Ok(chemins)
}
