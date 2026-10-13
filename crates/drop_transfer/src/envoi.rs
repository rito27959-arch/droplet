//! Envoyer : lire chaque bloc manquant par tranches et l'écrire sur la
//! connexion, puis renvoyer ce que le destinataire signale encore manquant
//! après sa vérification, jusqu'à son « Recu ».
//!
//! Les messages du destinataire (Annuler, Pause, Manquants, Recu) sont lus
//! par une tâche à part : on les voit même au milieu d'un gros bloc.

use std::collections::VecDeque;
use std::io::SeekFrom;
use std::path::PathBuf;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::Duration;

use drop_core::{CarteBlocs, Manifeste, TAILLE_TRANCHE};
use tokio::fs::File;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncSeekExt, AsyncWrite, AsyncWriteExt};
use tokio::sync::mpsc;

use crate::protocole::Controle;
use crate::suivi::{Etat, Suivi};
use crate::trame;
use crate::Erreur;

/// [sources] : le fichier sur le disque de chaque entrée du manifeste
/// (même ordre).
pub async fn envoyer<R, W>(
    lecteur: R,
    ecrivain: &mut W,
    manifeste: &Manifeste,
    sources: &[PathBuf],
    deja: &[CarteBlocs],
    suivi: &Arc<Suivi>,
) -> Result<(), Erreur>
where
    R: AsyncRead + Unpin + Send + 'static,
    W: AsyncWrite + Unpin,
{
    let (tx, mut rx) = mpsc::channel::<Result<Controle, Erreur>>(64);
    let lecture = tokio::spawn(async move {
        let mut lecteur = lecteur;
        loop {
            let r = trame::lire_controle(&mut lecteur).await;
            let fin = r.is_err();
            if tx.send(r).await.is_err() || fin {
                break;
            }
        }
    });
    let resultat = boucle(&mut rx, ecrivain, manifeste, sources, deja, suivi).await;
    lecture.abort();
    resultat
}

async fn boucle<W: AsyncWrite + Unpin>(
    rx: &mut mpsc::Receiver<Result<Controle, Erreur>>,
    ecrivain: &mut W,
    manifeste: &Manifeste,
    sources: &[PathBuf],
    deja: &[CarteBlocs],
    suivi: &Arc<Suivi>,
) -> Result<(), Erreur> {
    // La file de ce qui reste à envoyer : (index du fichier, bloc).
    let mut file: VecDeque<(usize, u32)> = VecDeque::new();
    for (i, f) in manifeste.fichiers.iter().enumerate() {
        for b in 0..f.nombre_blocs() {
            if !deja.get(i).is_some_and(|c| c.a(b)) {
                file.push_back((i, b));
            }
        }
    }
    let mut tampon = vec![0u8; TAILLE_TRANCHE];
    let mut ouvert: Option<(usize, File, u64)> = None;
    suivi.changer(Etat::Transfert);

    loop {
        while let Some((i, b)) = file.pop_front() {
            // Les messages du destinataire, sans attendre.
            while let Ok(m) = rx.try_recv() {
                traiter(m?, manifeste, &mut file)?;
            }
            if suivi.annule.load(Ordering::Relaxed) {
                let _ = trame::ecrire_controle(ecrivain, &Controle::Annuler).await;
                return Err(Erreur::Annule);
            }
            if suivi.pause.load(Ordering::Relaxed) {
                let _ = trame::ecrire_controle(ecrivain, &Controle::Pause).await;
                return Err(Erreur::EnPause);
            }
            let f = &manifeste.fichiers[i];
            if ouvert.as_ref().map(|o| o.0) != Some(i) {
                let fh = File::open(&sources[i]).await.map_err(|_| Erreur::FichierIntrouvable)?;
                ouvert = Some((i, fh, u64::MAX));
            }
            let (_, fh, pos) = ouvert.as_mut().unwrap();
            let debut = f.decalage(b);
            if *pos != debut {
                fh.seek(SeekFrom::Start(debut)).await?;
            }
            let taille = f.taille_du_bloc(b) as usize;
            let mut fait = 0usize;
            while fait < taille {
                let n = (taille - fait).min(TAILLE_TRANCHE);
                fh.read_exact(&mut tampon[..n]).await.map_err(|_| Erreur::FichierIntrouvable)?;
                trame::ecrire_donnees(ecrivain, f.id, b, fait as u32, &tampon[..n]).await?;
                fait += n;
                suivi.ajouter(n as u64);
            }
            *pos = debut + taille as u64;
        }
        ecrivain.flush().await?;
        trame::ecrire_controle(ecrivain, &Controle::Fin).await?;
        suivi.changer(Etat::Verification);

        // Attendre le verdict : Recu, ou des blocs à renvoyer. Le
        // destinataire peut mettre un moment à tout revérifier (10 Go ≈ 10 s).
        loop {
            let m = match tokio::time::timeout(Duration::from_secs(600), rx.recv()).await {
                Ok(Some(m)) => m?,
                Ok(None) => return Err(Erreur::ConnexionInterrompue),
                Err(_) => return Err(Erreur::ConnexionInterrompue),
            };
            if let Controle::Recu = m {
                return Ok(());
            }
            let avait = file.len();
            traiter(m, manifeste, &mut file)?;
            if file.len() > avait {
                // Laisser arriver les autres listes de manquants.
                tokio::time::sleep(Duration::from_millis(50)).await;
                while let Ok(m) = rx.try_recv() {
                    traiter(m?, manifeste, &mut file)?;
                }
                suivi.changer(Etat::Transfert);
                break;
            }
        }
    }
}

fn traiter(m: Controle, manifeste: &Manifeste, file: &mut VecDeque<(usize, u32)>) -> Result<(), Erreur> {
    match m {
        Controle::Manquants { fichier, blocs } => {
            let Some(i) = manifeste.fichiers.iter().position(|f| f.id == fichier) else {
                return Err(Erreur::Protocole("fichier inconnu"));
            };
            let n = manifeste.fichiers[i].nombre_blocs();
            if blocs.len() > n as usize {
                return Err(Erreur::Protocole("trop de blocs demandés"));
            }
            for b in blocs {
                if b < n && !file.contains(&(i, b)) {
                    file.push_back((i, b));
                }
            }
            Ok(())
        }
        Controle::Annuler => Err(Erreur::AnnuleParLAutre),
        Controle::Pause => Err(Erreur::EnPause),
        Controle::Recu => Ok(()),
        _ => Err(Erreur::Protocole("message inattendu")),
    }
}
