//! Le manifeste d'un envoi.

use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{chemins::nettoyer_chemin, ErreurCoeur, MAX_FICHIERS, MAX_TAILLE_TOTALE, TAILLE_TRANCHE};

/// Une empreinte BLAKE3 (32 octets), écrite en hexadécimal dans le JSON.
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct Empreinte(pub [u8; 32]);

impl std::fmt::Debug for Empreinte {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", &hex::encode(self.0)[..12])
    }
}

impl Serialize for Empreinte {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&hex::encode(self.0))
    }
}

impl<'de> Deserialize<'de> for Empreinte {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let t = String::deserialize(d)?;
        let v = hex::decode(t).map_err(serde::de::Error::custom)?;
        let a: [u8; 32] = v.try_into().map_err(|_| serde::de::Error::custom("empreinte de 32 octets attendue"))?;
        Ok(Empreinte(a))
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct FichierManifeste {
    pub id: u32,
    /// Chemin relatif, avec des « / » (déjà nettoyé à l'envoi, et
    /// RE-nettoyé à la réception : on ne fait jamais confiance à l'autre).
    pub chemin: String,
    pub taille: u64,
    pub taille_bloc: u32,
    /// Une empreinte par bloc, dans l'ordre.
    pub blocs: Vec<Empreinte>,
    /// L'empreinte du fichier entier.
    pub totale: Empreinte,
}

impl FichierManifeste {
    pub fn nombre_blocs(&self) -> u32 {
        self.blocs.len() as u32
    }

    /// Taille réelle du bloc [i] (le dernier est souvent plus court).
    pub fn taille_du_bloc(&self, i: u32) -> u32 {
        let debut = i as u64 * self.taille_bloc as u64;
        (self.taille.saturating_sub(debut)).min(self.taille_bloc as u64) as u32
    }

    pub fn decalage(&self, i: u32) -> u64 {
        i as u64 * self.taille_bloc as u64
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Manifeste {
    pub fichiers: Vec<FichierManifeste>,
}

impl Manifeste {
    pub fn taille_totale(&self) -> u64 {
        self.fichiers.iter().map(|f| f.taille).sum()
    }

    /// L'identité stable de ce manifeste : c'est elle qui permet de
    /// retrouver un transfert partiel pour le reprendre.
    pub fn cle(&self) -> String {
        let j = serde_json::to_vec(self).unwrap_or_default();
        blake3::hash(&j).to_hex().to_string()
    }

    /// Vérifie qu'un manifeste reçu du réseau est cohérent : tailles,
    /// nombres de blocs, chemins, bornes. Rend le manifeste avec des
    /// chemins RE-nettoyés.
    pub fn valider(mut self) -> Result<Self, ErreurCoeur> {
        if self.fichiers.is_empty() {
            return Err(ErreurCoeur::ManifesteInvalide("aucun fichier"));
        }
        if self.fichiers.len() > MAX_FICHIERS {
            return Err(ErreurCoeur::ManifesteInvalide("trop de fichiers"));
        }
        let mut total: u64 = 0;
        let mut ids = std::collections::HashSet::new();
        for f in &mut self.fichiers {
            if !ids.insert(f.id) {
                return Err(ErreurCoeur::ManifesteInvalide("identifiant de fichier en double"));
            }
            if f.taille_bloc < 64 * 1024 || f.taille_bloc > 64 * 1024 * 1024 {
                return Err(ErreurCoeur::ManifesteInvalide("taille de bloc hors limites"));
            }
            let attendus = if f.taille == 0 { 0 } else { f.taille.div_ceil(f.taille_bloc as u64) };
            if attendus != f.blocs.len() as u64 {
                return Err(ErreurCoeur::ManifesteInvalide("nombre de blocs incohérent"));
            }
            total = total.checked_add(f.taille).ok_or(ErreurCoeur::ManifesteInvalide("taille démesurée"))?;
            f.chemin = nettoyer_chemin(&f.chemin).ok_or(ErreurCoeur::ManifesteInvalide("nom de fichier vide"))?;
        }
        if total > MAX_TAILLE_TOTALE {
            return Err(ErreurCoeur::ManifesteInvalide("envoi trop volumineux"));
        }
        Ok(self)
    }
}

/// Un fichier à envoyer : où il est sur le disque, et le nom qu'il aura
/// chez le destinataire (avec ses dossiers, pour un dossier envoyé).
#[derive(Clone, Debug)]
pub struct SourceFichier {
    pub disque: PathBuf,
    pub nom: String,
}

/// Lit chaque fichier une fois, par tranches, et calcule l'empreinte de
/// chaque bloc et du fichier entier. [progres] reçoit les octets lus.
pub fn construire_manifeste(sources: &[SourceFichier], taille_bloc: u32, mut progres: impl FnMut(u64)) -> Result<Manifeste, ErreurCoeur> {
    let mut fichiers = Vec::with_capacity(sources.len());
    let mut tampon = vec![0u8; TAILLE_TRANCHE];
    for (id, s) in sources.iter().enumerate() {
        let chemin = nettoyer_chemin(&s.nom).ok_or(ErreurCoeur::ManifesteInvalide("nom de fichier vide"))?;
        let mut f = File::open(&s.disque)?;
        let taille = f.metadata()?.len();
        let mut blocs = Vec::new();
        let mut total = blake3::Hasher::new();
        let mut bloc = blake3::Hasher::new();
        let mut dans_bloc: u64 = 0;
        loop {
            let reste_bloc = (taille_bloc as u64 - dans_bloc) as usize;
            let n = f.read(&mut tampon[..TAILLE_TRANCHE.min(reste_bloc)])?;
            if n == 0 {
                break;
            }
            total.update(&tampon[..n]);
            bloc.update(&tampon[..n]);
            dans_bloc += n as u64;
            progres(n as u64);
            if dans_bloc == taille_bloc as u64 {
                blocs.push(Empreinte(*bloc.finalize().as_bytes()));
                bloc = blake3::Hasher::new();
                dans_bloc = 0;
            }
        }
        if dans_bloc > 0 {
            blocs.push(Empreinte(*bloc.finalize().as_bytes()));
        }
        fichiers.push(FichierManifeste { id: id as u32, chemin, taille, taille_bloc, blocs, totale: Empreinte(*total.finalize().as_bytes()) });
    }
    Ok(Manifeste { fichiers })
}

/// Relit un fichier reçu et rend les blocs qui ne correspondent pas au
/// manifeste (vide = fichier parfait). Vérifie aussi l'empreinte totale.
pub fn verifier_fichier(chemin: &Path, f: &FichierManifeste) -> Result<Vec<u32>, ErreurCoeur> {
    let mut fichier = File::open(chemin)?;
    if fichier.metadata()?.len() < f.taille {
        return Ok((0..f.nombre_blocs()).collect());
    }
    let mut tampon = vec![0u8; TAILLE_TRANCHE];
    let mut mauvais = Vec::new();
    let mut total = blake3::Hasher::new();
    for i in 0..f.nombre_blocs() {
        fichier.seek(SeekFrom::Start(f.decalage(i)))?;
        let mut reste = f.taille_du_bloc(i) as usize;
        let mut h = blake3::Hasher::new();
        while reste > 0 {
            let n = fichier.read(&mut tampon[..reste.min(TAILLE_TRANCHE)])?;
            if n == 0 {
                break;
            }
            h.update(&tampon[..n]);
            total.update(&tampon[..n]);
            reste -= n;
        }
        if reste > 0 || h.finalize().as_bytes() != &f.blocs[i as usize].0 {
            mauvais.push(i);
        }
    }
    if mauvais.is_empty() && total.finalize().as_bytes() != &f.totale.0 {
        // Tous les blocs bons mais pas le tout : impossible sauf manifeste
        // incohérent. On redemande tout plutôt que de livrer un faux fichier.
        return Ok((0..f.nombre_blocs()).collect());
    }
    Ok(mauvais)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[test]
    fn manifeste_et_verification() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("a.bin");
        let mut f = File::create(&p).unwrap();
        let donnees: Vec<u8> = (0..(1_500_000u32)).map(|i| (i % 251) as u8).collect();
        f.write_all(&donnees).unwrap();
        drop(f);
        let m = construire_manifeste(&[SourceFichier { disque: p.clone(), nom: "x/a.bin".into() }], 1 << 19, |_| {}).unwrap();
        let fm = &m.fichiers[0];
        assert_eq!(fm.nombre_blocs(), 3);
        assert_eq!(fm.taille_du_bloc(2), 1_500_000 - 2 * (1 << 19));
        assert!(verifier_fichier(&p, fm).unwrap().is_empty());
        // On abîme un octet du bloc 1 : seul lui est signalé.
        let mut donnees2 = donnees.clone();
        donnees2[600_000] ^= 1;
        std::fs::write(&p, &donnees2).unwrap();
        assert_eq!(verifier_fichier(&p, fm).unwrap(), vec![1]);
        let v = serde_json::to_string(&m).unwrap();
        let m2: Manifeste = serde_json::from_str(&v).unwrap();
        assert_eq!(m2.cle(), m.cle());
        assert!(m2.valider().is_ok());
    }

    #[test]
    fn refuse_un_manifeste_incoherent() {
        let m = Manifeste {
            fichiers: vec![FichierManifeste {
                id: 0,
                chemin: "../../a".into(),
                taille: 10_000_000,
                taille_bloc: 1 << 20,
                blocs: vec![Empreinte([0; 32]); 3],
                totale: Empreinte([0; 32]),
            }],
        };
        assert!(m.valider().is_err());
        let ok = Manifeste {
            fichiers: vec![FichierManifeste {
                id: 0,
                chemin: "../../a".into(),
                taille: 3 << 20,
                taille_bloc: 1 << 20,
                blocs: vec![Empreinte([0; 32]); 3],
                totale: Empreinte([0; 32]),
            }],
        }
        .valider()
        .unwrap();
        assert_eq!(ok.fichiers[0].chemin, "a");
    }
}
