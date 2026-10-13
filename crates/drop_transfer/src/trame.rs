//! Les trames : `[genre: u8][longueur: u32 BE][contenu]`.
//!
//! * genre 1 — un message de contrôle, en JSON (voir `protocole.rs`) ;
//! * genre 2 — une tranche de données :
//!   `[fichier: u32][bloc: u32][décalage dans le bloc: u32][octets…]`.
//!
//! Les longueurs sont bornées à la lecture : un pair malveillant ne peut
//! pas faire allouer des gigaoctets avec un en-tête menteur.

use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

use crate::protocole::Controle;
use crate::Erreur;

pub const GENRE_CONTROLE: u8 = 1;
pub const GENRE_DONNEES: u8 = 2;

/// Un message de contrôle ne dépasse pas 32 Mio (un manifeste de 100 000
/// fichiers tient largement).
const MAX_CONTROLE: u32 = 32 * 1024 * 1024;
const MAX_DONNEES: u32 = 12 + 1024 * 1024;

pub enum Trame {
    Controle(Controle),
    Donnees { fichier: u32, bloc: u32, decalage: u32, octets: Vec<u8> },
}

pub async fn ecrire_controle<W: AsyncWrite + Unpin>(w: &mut W, c: &Controle) -> Result<(), Erreur> {
    let j = serde_json::to_vec(c).map_err(|_| Erreur::Protocole("encodage"))?;
    let mut entete = [0u8; 5];
    entete[0] = GENRE_CONTROLE;
    entete[1..].copy_from_slice(&(j.len() as u32).to_be_bytes());
    w.write_all(&entete).await?;
    w.write_all(&j).await?;
    w.flush().await?;
    Ok(())
}

pub async fn ecrire_donnees<W: AsyncWrite + Unpin>(w: &mut W, fichier: u32, bloc: u32, decalage: u32, octets: &[u8]) -> Result<(), Erreur> {
    let mut entete = [0u8; 17];
    entete[0] = GENRE_DONNEES;
    entete[1..5].copy_from_slice(&((12 + octets.len()) as u32).to_be_bytes());
    entete[5..9].copy_from_slice(&fichier.to_be_bytes());
    entete[9..13].copy_from_slice(&bloc.to_be_bytes());
    entete[13..17].copy_from_slice(&decalage.to_be_bytes());
    w.write_all(&entete).await?;
    w.write_all(octets).await?;
    Ok(())
}

pub async fn lire<R: AsyncRead + Unpin>(r: &mut R) -> Result<Trame, Erreur> {
    let mut entete = [0u8; 5];
    r.read_exact(&mut entete).await?;
    let longueur = u32::from_be_bytes([entete[1], entete[2], entete[3], entete[4]]);
    match entete[0] {
        GENRE_CONTROLE => {
            if longueur > MAX_CONTROLE {
                return Err(Erreur::Protocole("message trop long"));
            }
            let mut v = vec![0u8; longueur as usize];
            r.read_exact(&mut v).await?;
            let c = serde_json::from_slice(&v).map_err(|_| Erreur::Protocole("message illisible"))?;
            Ok(Trame::Controle(c))
        }
        GENRE_DONNEES => {
            if !(12..=MAX_DONNEES).contains(&longueur) {
                return Err(Erreur::Protocole("tranche de taille invalide"));
            }
            let mut t = [0u8; 12];
            r.read_exact(&mut t).await?;
            let mut octets = vec![0u8; (longueur - 12) as usize];
            r.read_exact(&mut octets).await?;
            Ok(Trame::Donnees {
                fichier: u32::from_be_bytes([t[0], t[1], t[2], t[3]]),
                bloc: u32::from_be_bytes([t[4], t[5], t[6], t[7]]),
                decalage: u32::from_be_bytes([t[8], t[9], t[10], t[11]]),
                octets,
            })
        }
        _ => Err(Erreur::Protocole("genre de trame inconnu")),
    }
}

pub async fn lire_controle<R: AsyncRead + Unpin>(r: &mut R) -> Result<Controle, Erreur> {
    match lire(r).await? {
        Trame::Controle(c) => Ok(c),
        Trame::Donnees { .. } => Err(Erreur::Protocole("données inattendues")),
    }
}
