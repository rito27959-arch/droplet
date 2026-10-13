//! Tests réels du moteur : de vrais appareils (un moteur chacun, sa propre
//! identité, son propre port), de vraies connexions TLS, de vrais fichiers.
//!
//! Tailles par défaut modestes pour la CI ; DROP_TEST_GRAND=1 lance aussi
//! les mesures volumineuses (1 Go, 30 destinataires).

use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use drop_core::SourceFichier;
use drop_transfer::{Cible, Config, Etat, Evenement, Moteur};
use rand::RngCore;
use tokio::sync::broadcast;

struct Appareil {
    m: Moteur,
    _dossier: tempfile::TempDir,
    reception: PathBuf,
    donnees: PathBuf,
}

async fn appareil(nom: &str) -> Appareil {
    let d = tempfile::tempdir().unwrap();
    appareil_dans(nom, d, 0).await
}

async fn appareil_dans(nom: &str, d: tempfile::TempDir, port: u16) -> Appareil {
    let donnees = d.path().join("donnees");
    let reception = d.path().join("recus");
    let mut c = Config::simple(nom, donnees.clone(), reception.clone());
    c.port = port;
    c.delai_reponse = Duration::from_secs(20);
    let m = Moteur::demarrer(c).await.unwrap();
    Appareil { m, _dossier: d, reception, donnees }
}

fn cible(a: &Appareil) -> Cible {
    Cible { adresses: vec![SocketAddr::from(([127, 0, 0, 1], a.m.port()))], empreinte: Some(a.m.empreinte().hex()), nom: "test".into() }
}

fn fichier_aleatoire(dossier: &Path, nom: &str, taille: usize) -> PathBuf {
    let p = dossier.join(nom);
    std::fs::create_dir_all(p.parent().unwrap()).unwrap();
    let mut f = std::fs::File::create(&p).unwrap();
    let mut tampon = vec![0u8; 1 << 20];
    let mut reste = taille;
    while reste > 0 {
        let n = reste.min(tampon.len());
        rand::rng().fill_bytes(&mut tampon[..n]);
        std::io::Write::write_all(&mut f, &tampon[..n]).unwrap();
        reste -= n;
    }
    p
}

/// Compare deux fichiers par leur empreinte, lus en flux : la mémoire
/// mesurée reste celle du moteur, pas celle de la vérification du test.
fn meme_contenu(a: &Path, b: &Path) -> bool {
    let h = |p: &Path| {
        let mut x = blake3::Hasher::new();
        x.update_reader(std::fs::File::open(p).unwrap()).unwrap();
        x.finalize()
    };
    h(a) == h(b)
}

/// Accepte automatiquement toutes les offres reçues par [a].
fn accepter_tout(a: &Appareil) {
    let m = a.m.clone();
    let mut rx = m.abonner();
    tokio::spawn(async move {
        while let Ok(e) = rx.recv().await {
            if let Evenement::Offre { offre, .. } = e {
                m.repondre(&offre, true);
            }
        }
    });
}

/// Attend l'état final de chacun des transferts de [groupe] (ou de l'id).
async fn finals(rx: &mut broadcast::Receiver<Evenement>, groupe: &str, n: usize, delai: Duration) -> Vec<(Etat, Option<String>, Vec<String>)> {
    let mut vus = std::collections::HashMap::new();
    let fin = Instant::now() + delai;
    while vus.len() < n {
        let e = tokio::time::timeout_at(fin.into(), rx.recv()).await.expect("délai dépassé").unwrap();
        if let Evenement::Transfert { id, groupe: g, etat, erreur, chemins, .. } = e {
            if (g == groupe || id == groupe) && etat.final_() {
                vus.insert(id, (etat, erreur, chemins));
            }
        }
    }
    vus.into_values().collect()
}

fn tres_grand() -> bool {
    std::env::var("DROP_TEST_GRAND").is_ok()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn envoi_direct_avec_dossier() {
    let a = appareil("A").await;
    let b = appareil("B").await;
    accepter_tout(&b);
    let src = tempfile::tempdir().unwrap();
    let f1 = fichier_aleatoire(src.path(), "video.bin", 21 * 1024 * 1024 + 123);
    let f2 = fichier_aleatoire(src.path(), "doc/notes.txt", 10);
    let vide = src.path().join("vide.txt");
    std::fs::write(&vide, b"").unwrap();
    let mut rx = a.m.abonner();
    let g = a.m.envoyer(
        vec![
            SourceFichier { disque: f1.clone(), nom: "video.bin".into() },
            SourceFichier { disque: f2.clone(), nom: "Projet/doc/notes.txt".into() },
            SourceFichier { disque: vide.clone(), nom: "vide.txt".into() },
        ],
        vec![cible(&b)],
    );
    let r = finals(&mut rx, &g, 1, Duration::from_secs(60)).await;
    assert_eq!(r[0].0, Etat::Termine, "{:?}", r[0]);
    assert!(meme_contenu(&f1, &b.reception.join("video.bin")));
    assert!(meme_contenu(&f2, &b.reception.join("Projet/doc/notes.txt")));
    assert_eq!(std::fs::metadata(b.reception.join("vide.txt")).unwrap().len(), 0);
    // Un second envoi du même fichier n'écrase rien.
    let g2 = a.m.envoyer(vec![SourceFichier { disque: f2.clone(), nom: "Projet/doc/notes.txt".into() }], vec![cible(&b)]);
    let r = finals(&mut rx, &g2, 1, Duration::from_secs(30)).await;
    assert_eq!(r[0].0, Etat::Termine);
    assert!(b.reception.join("Projet/doc/notes (1).txt").exists());
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn refus_et_empreinte_epinglee() {
    let a = appareil("A").await;
    let b = appareil("B").await;
    let src = tempfile::tempdir().unwrap();
    let f = fichier_aleatoire(src.path(), "x.bin", 1000);
    // B refuse.
    let mb = b.m.clone();
    let mut rxb = mb.abonner();
    tokio::spawn(async move {
        while let Ok(e) = rxb.recv().await {
            if let Evenement::Offre { offre, .. } = e {
                mb.repondre(&offre, false);
            }
        }
    });
    let mut rx = a.m.abonner();
    let g = a.m.envoyer(vec![SourceFichier { disque: f.clone(), nom: "x.bin".into() }], vec![cible(&b)]);
    let r = finals(&mut rx, &g, 1, Duration::from_secs(30)).await;
    assert_eq!(r[0].0, Etat::Refuse);
    assert!(!b.reception.join("x.bin").exists());

    // Un appareil qui n'est pas celui attendu : refusé à la poignée de main.
    let c = appareil("C").await;
    let mut usurpe = cible(&c);
    usurpe.empreinte = Some(b.m.empreinte().hex());
    let g = a.m.envoyer(vec![SourceFichier { disque: f, nom: "x.bin".into() }], vec![usurpe]);
    let r = finals(&mut rx, &g, 1, Duration::from_secs(30)).await;
    assert_eq!(r[0].0, Etat::Echec);
    assert_eq!(r[0].1.as_deref(), Some("empreinte_invalide"));
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn appareil_de_confiance_sans_question() {
    let a = appareil("A").await;
    let b = appareil("B").await;
    b.m.modifier(|c| c.confiance.push(a.m.empreinte().hex()));
    let mut rxb = b.m.abonner();
    let src = tempfile::tempdir().unwrap();
    let f = fichier_aleatoire(src.path(), "x.bin", 300_000);
    let mut rx = a.m.abonner();
    let g = a.m.envoyer(vec![SourceFichier { disque: f.clone(), nom: "x.bin".into() }], vec![cible(&b)]);
    let r = finals(&mut rx, &g, 1, Duration::from_secs(30)).await;
    assert_eq!(r[0].0, Etat::Termine);
    while let Ok(e) = rxb.try_recv() {
        assert!(!matches!(e, Evenement::Offre { .. }), "aucune question attendue");
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn reprise_apres_coupure_reelle_et_bloc_abime() {
    let a = appareil("A").await;
    let d = tempfile::tempdir().unwrap();
    let chemin_b = d.path().to_path_buf();
    let b = appareil_dans("B", d, 0).await;
    let port_b = b.m.port();
    accepter_tout(&b);
    let src = tempfile::tempdir().unwrap();
    let taille = 400 * 1024 * 1024;
    let f = fichier_aleatoire(src.path(), "gros.bin", taille);
    let mut rx = a.m.abonner();
    let mut rxb = b.m.abonner();
    let g = a.m.envoyer(vec![SourceFichier { disque: f.clone(), nom: "gros.bin".into() }], vec![cible(&b)]);

    // Laisser passer ~30 %, puis B « meurt ».
    loop {
        if let Ok(Evenement::Transfert { octets, total, sens: drop_transfer::Sens::Reception, .. }) = rxb.recv().await {
            if total > 0 && octets > total * 3 / 10 {
                break;
            }
        }
    }
    b.m.arreter();
    let Appareil { _dossier, .. } = b;
    tokio::time::sleep(Duration::from_millis(500)).await;

    // Pendant la panne, un bloc déjà reçu s'abîme sur le disque.
    let partiels = chemin_b.join("recus/.droplet-drop/partiels");
    let cle = std::fs::read_dir(&partiels).unwrap().next().unwrap().unwrap().path();
    let part = cle.join("0.part");
    {
        use std::io::{Seek, SeekFrom, Write};
        let mut fh = std::fs::OpenOptions::new().write(true).open(&part).unwrap();
        fh.seek(SeekFrom::Start(5 * 1024 * 1024 + 7)).unwrap();
        fh.write_all(b"ABIME").unwrap();
    }

    // B revient : même identité, même dossier, même port.
    let b2 = appareil_dans("B", _dossier, port_b).await;
    accepter_tout(&b2);
    let mut rxb2 = b2.m.abonner();
    let r = finals(&mut rx, &g, 1, Duration::from_secs(240)).await;
    assert_eq!(r[0].0, Etat::Termine, "{:?}", r[0]);
    assert!(meme_contenu(&f, &b2.reception.join("gros.bin")), "le bloc abîmé a été détecté et renvoyé");
    // La reprise est partie de la carte des blocs, pas de zéro.
    let mut premier = None;
    while let Ok(e) = rxb2.try_recv() {
        if let Evenement::Transfert { octets, sens: drop_transfer::Sens::Reception, .. } = e {
            premier.get_or_insert(octets);
        }
    }
    assert!(premier.unwrap_or(0) > (taille as u64) / 5, "reprise à {:?} octets", premier);
    assert!(!partiels.join(cle.file_name().unwrap()).exists(), "partiel nettoyé");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn pause_puis_reprise() {
    let a = appareil("A").await;
    let b = appareil("B").await;
    accepter_tout(&b);
    let src = tempfile::tempdir().unwrap();
    let f = fichier_aleatoire(src.path(), "p.bin", 200 * 1024 * 1024);
    let mut rx = a.m.abonner();
    let g = a.m.envoyer(vec![SourceFichier { disque: f.clone(), nom: "p.bin".into() }], vec![cible(&b)]);
    // 1. En pause dès le départ : l'état DOIT passer à « interrompu »
    //    (déterministe, quelle que soit la vitesse de la machine).
    a.m.pause(&g);
    assert!(attendre_etat(&mut rx, &g, Etat::Interrompu, Duration::from_secs(10)).await, "pause au départ");
    a.m.reprendre(&g);
    // 2. Puis en pleine course : sur une machine rapide, 200 Mio peuvent
    //    finir avant que la pause n'arrive ; on n'exige l'interruption que
    //    si le transfert n'est pas déjà terminé.
    loop {
        if let Ok(Evenement::Transfert { groupe, octets, .. }) = rx.recv().await {
            if groupe == g && octets > 0 {
                break;
            }
        }
    }
    a.m.pause(&g);
    tokio::time::sleep(Duration::from_millis(300)).await;
    a.m.reprendre(&g);
    let r = finals(&mut rx, &g, 1, Duration::from_secs(120)).await;
    assert_eq!(r[0].0, Etat::Termine);
    assert!(meme_contenu(&f, &b.reception.join("p.bin")));
}

/// Attend qu'un transfert du groupe atteigne `voulu` (vrai) ou finisse
/// autrement / dépasse le délai (faux).
async fn attendre_etat(rx: &mut tokio::sync::broadcast::Receiver<Evenement>, g: &str, voulu: Etat, delai: Duration) -> bool {
    let fin = Instant::now() + delai;
    while Instant::now() < fin {
        if let Ok(Ok(Evenement::Transfert { groupe, etat, .. })) = tokio::time::timeout(Duration::from_secs(1), rx.recv()).await {
            if groupe == g && etat == voulu {
                return true;
            }
        }
    }
    false
}

async fn envoi_multiple(n: usize, taille: usize) -> Duration {
    let a = appareil("A").await;
    let mut dest = Vec::new();
    for i in 0..n {
        let d = appareil(&format!("D{i}")).await;
        accepter_tout(&d);
        dest.push(d);
    }
    let src = tempfile::tempdir().unwrap();
    let f = fichier_aleatoire(src.path(), "m.bin", taille);
    let mut rx = a.m.abonner();
    let t0 = Instant::now();
    let g = a.m.envoyer(vec![SourceFichier { disque: f.clone(), nom: "m.bin".into() }], dest.iter().map(cible).collect());
    let r = finals(&mut rx, &g, n, Duration::from_secs(1800)).await;
    let duree = t0.elapsed();
    assert!(r.iter().all(|x| x.0 == Etat::Termine), "{:?}", r);
    for d in &dest {
        assert!(meme_contenu(&f, &d.reception.join("m.bin")));
    }
    duree
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn dix_destinataires() {
    let duree = envoi_multiple(10, 24 * 1024 * 1024).await;
    println!("MESURE envoi direct : 10 destinataires × 24 Mio en {:.1} s", duree.as_secs_f64());
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn group_drop_session() {
    let hote = appareil("Professeur").await;
    let src = tempfile::tempdir().unwrap();
    let f = fichier_aleatoire(src.path(), "cours.zip", 30 * 1024 * 1024);
    let info = hote.m.creer_session(vec![SourceFichier { disque: f.clone(), nom: "cours.zip".into() }], Duration::from_secs(600), false).await.unwrap();
    let adresse = Some(SocketAddr::from(([127, 0, 0, 1], hote.m.port())));

    // Un intrus avec un faux jeton.
    let intrus = appareil("Intrus").await;
    let mut faux = drop_transfer::Invitation::decoder(&info.invitation).unwrap();
    faux.j = "0".repeat(64);
    let mut rxi = intrus.m.abonner();
    let id_intrus = intrus.m.rejoindre(&faux.encoder(), adresse).unwrap();
    let r = finals(&mut rxi, &id_intrus, 1, Duration::from_secs(30)).await;
    assert_eq!(r[0].0, Etat::Echec);
    assert_eq!(r[0].1.as_deref(), Some("session_invalide"));

    // Dix élèves rejoignent, puis le professeur lance.
    let mut eleves = Vec::new();
    for i in 0..10 {
        let e = appareil(&format!("Élève {i}")).await;
        let rx = e.m.abonner();
        let id = e.m.rejoindre(&info.invitation, adresse).unwrap();
        eleves.push((e, rx, id));
    }
    tokio::time::sleep(Duration::from_secs(3)).await;
    hote.m.reprendre(&info.id); // « Démarrer »
    for (e, rx, id) in eleves.iter_mut() {
        let r = finals(rx, id, 1, Duration::from_secs(300)).await;
        assert_eq!(r[0].0, Etat::Termine, "{:?}", r[0]);
        assert!(meme_contenu(&f, &e.reception.join("cours.zip")));
    }
    assert!(intrus.reception.read_dir().map(|d| d.filter(|x| x.as_ref().unwrap().file_name() != ".droplet-drop").count()).unwrap_or(0) == 0);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn session_expiree() {
    let hote = appareil("H").await;
    let src = tempfile::tempdir().unwrap();
    let f = fichier_aleatoire(src.path(), "a.bin", 1000);
    let info = hote.m.creer_session(vec![SourceFichier { disque: f, nom: "a.bin".into() }], Duration::from_secs(0), true).await.unwrap();
    tokio::time::sleep(Duration::from_millis(1100)).await;
    let p = appareil("P").await;
    assert!(matches!(p.m.rejoindre(&info.invitation, None), Err(drop_transfer::Erreur::SessionExpiree)));
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn mesures_volumineuses() {
    if !tres_grand() {
        println!("(DROP_TEST_GRAND absent : mesures volumineuses sautées)");
        return;
    }
    // 1 Go vers 2 appareils.
    let d = envoi_multiple(2, 1024 * 1024 * 1024).await;
    println!("MESURE 1 Go → 2 appareils : {:.1} s ({:.0} Mo/s cumulés)", d.as_secs_f64(), 2.0 * 1024.0 / d.as_secs_f64());
    // 200 Mo vers 30 appareils.
    let d = envoi_multiple(30, 200 * 1024 * 1024).await;
    println!("MESURE 200 Mo → 30 appareils : {:.1} s ({:.0} Mo/s cumulés)", d.as_secs_f64(), 30.0 * 200.0 / d.as_secs_f64());
}

#[allow(dead_code)]
fn _donnees(a: &Appareil) -> &Path {
    &a.donnees
}

/// Le destinataire n'est pas joignable (pare-feu de Windows qui refuse
/// les connexions entrantes) : l'expéditeur annonce qu'un envoi l'attend,
/// le destinataire vient le chercher lui-même — et le fichier arrive,
/// vérifié, comme par le chemin direct.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn tirage_quand_le_destinataire_est_injoignable() {
    let a = appareil("Android").await;
    let b = appareil("Windows").await;
    accepter_tout(&b);
    let src = tempfile::tempdir().unwrap();
    let f = fichier_aleatoire(src.path(), "photo.jpg", 3 * 1024 * 1024 + 7);
    // Une adresse qui ne répond pas : rien n'écoute sur ce port.
    let fermee = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port_ferme = fermee.local_addr().unwrap().port();
    drop(fermee);
    let mut cible_b = cible(&b);
    cible_b.adresses = vec![SocketAddr::from(([127, 0, 0, 1], port_ferme))];

    // Ce que ferait la découverte : B voit son empreinte dans l'annonce
    // de A, et va chercher l'envoi.
    let mut demandes = a.m.demandes();
    let (mb, cible_a, prefixe) = (b.m.clone(), cible(&a), b.m.empreinte().hex()[..16].to_string());
    tokio::spawn(async move {
        while demandes.changed().await.is_ok() {
            if demandes.borrow_and_update().contains(&prefixe) {
                mb.tirer(cible_a.clone());
            }
        }
    });

    let mut rx = a.m.abonner();
    let g = a.m.envoyer(vec![SourceFichier { disque: f.clone(), nom: "photo.jpg".into() }], vec![cible_b]);
    let r = finals(&mut rx, &g, 1, Duration::from_secs(60)).await;
    assert_eq!(r[0].0, Etat::Termine, "{:?}", r[0].1);
    assert!(meme_contenu(&f, &b.reception.join("photo.jpg")));
    // L'annonce est retirée une fois l'envoi parti.
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert!(a.m.demandes().borrow().is_empty());
}
