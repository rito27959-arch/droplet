//! Un appareil malveillant parle le protocole à la main : chemins piégés,
//! trames démesurées, données hors limites. Le récepteur doit rester
//! debout, n'écrire QUE dans son dossier de réception, et ne rien livrer
//! de faux.

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use drop_core::{Empreinte, FichierManifeste, Manifeste};
use drop_crypto::{config_client, nom_serveur, Identite};
use drop_transfer::protocole::{Appareil, Controle};
use drop_transfer::{trame, Config, Evenement, Moteur};
use tokio::io::AsyncWriteExt;
use tokio::net::TcpStream;
use tokio_rustls::TlsConnector;

async fn recepteur() -> (Moteur, tempfile::TempDir) {
    let d = tempfile::tempdir().unwrap();
    let mut c = Config::simple("Victime", d.path().join("donnees"), d.path().join("recus"));
    c.port = 0;
    let m = Moteur::demarrer(c).await.unwrap();
    let m2 = m.clone();
    let mut rx = m.abonner();
    tokio::spawn(async move {
        while let Ok(e) = rx.recv().await {
            if let Evenement::Offre { offre, .. } = e {
                m2.repondre(&offre, true);
            }
        }
    });
    (m, d)
}

async fn connexion(m: &Moteur) -> tokio_rustls::client::TlsStream<TcpStream> {
    let id = Identite::nouvelle().unwrap();
    let conf = config_client(&id, Some(m.empreinte())).unwrap();
    let tcp = TcpStream::connect(SocketAddr::from(([127, 0, 0, 1], m.port()))).await.unwrap();
    TlsConnector::from(conf).connect(nom_serveur(), tcp).await.unwrap()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn chemin_piege_reste_dans_le_dossier() {
    let (m, d) = recepteur().await;
    let mut tls = connexion(&m).await;
    let contenu = b"pas de fuite".to_vec();
    let bloc = Empreinte(*blake3::hash(&contenu).as_bytes());
    let manifeste = Manifeste {
        fichiers: vec![FichierManifeste {
            id: 0,
            chemin: "../../../../tmp/evade.txt".into(),
            taille: contenu.len() as u64,
            taille_bloc: 1 << 20,
            blocs: vec![bloc],
            totale: bloc,
        }],
    };
    trame::ecrire_controle(&mut tls, &Controle::Bonjour { v: 1, appareil: Appareil { nom: "Pirate".into(), plateforme: "linux".into() } }).await.unwrap();
    let _ = trame::lire_controle(&mut tls).await.unwrap();
    trame::ecrire_controle(&mut tls, &Controle::Offre { offre: "o".into(), manifeste }).await.unwrap();
    match trame::lire_controle(&mut tls).await.unwrap() {
        Controle::Reponse { acceptee: true, .. } => {}
        autre => panic!("réponse inattendue {autre:?}"),
    }
    trame::ecrire_donnees(&mut tls, 0, 0, 0, &contenu).await.unwrap();
    trame::ecrire_controle(&mut tls, &Controle::Fin).await.unwrap();
    assert!(matches!(trame::lire_controle(&mut tls).await.unwrap(), Controle::Recu));
    let recus = d.path().join("recus");
    assert_eq!(std::fs::read(recus.join("tmp/evade.txt")).unwrap(), contenu);
    assert!(!std::path::Path::new("/tmp/evade.txt").exists() || std::fs::read("/tmp/evade.txt").unwrap() != contenu);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn donnees_fausses_jamais_livrees() {
    let (m, d) = recepteur().await;
    let mut tls = connexion(&m).await;
    let vrai = vec![7u8; 100_000];
    let bloc = Empreinte(*blake3::hash(&vrai).as_bytes());
    let manifeste = Manifeste {
        fichiers: vec![FichierManifeste { id: 0, chemin: "a.bin".into(), taille: vrai.len() as u64, taille_bloc: 1 << 20, blocs: vec![bloc], totale: bloc }],
    };
    trame::ecrire_controle(&mut tls, &Controle::Bonjour { v: 1, appareil: Appareil { nom: "P".into(), plateforme: "x".into() } }).await.unwrap();
    let _ = trame::lire_controle(&mut tls).await.unwrap();
    trame::ecrire_controle(&mut tls, &Controle::Offre { offre: "o".into(), manifeste }).await.unwrap();
    let _ = trame::lire_controle(&mut tls).await.unwrap();
    // Des données qui ne correspondent pas à l'empreinte annoncée.
    trame::ecrire_donnees(&mut tls, 0, 0, 0, &vec![8u8; 100_000]).await.unwrap();
    trame::ecrire_controle(&mut tls, &Controle::Fin).await.unwrap();
    match trame::lire_controle(&mut tls).await.unwrap() {
        Controle::Manquants { fichier: 0, blocs } => assert_eq!(blocs, vec![0]),
        autre => panic!("le bloc faux devait être redemandé : {autre:?}"),
    }
    assert!(!d.path().join("recus/a.bin").exists(), "rien de faux n'est livré");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn trames_demesurees_et_manifeste_absurde() {
    let (m, _d) = recepteur().await;
    // Une trame qui annonce 4 Go : connexion coupée, pas d'allocation.
    let mut tls = connexion(&m).await;
    trame::ecrire_controle(&mut tls, &Controle::Bonjour { v: 1, appareil: Appareil { nom: "P".into(), plateforme: "x".into() } }).await.unwrap();
    let _ = trame::lire_controle(&mut tls).await.unwrap();
    tls.write_all(&[1, 0xff, 0xff, 0xff, 0xff]).await.unwrap();
    tls.flush().await.unwrap();
    let r = tokio::time::timeout(Duration::from_secs(5), trame::lire_controle(&mut tls)).await;
    assert!(matches!(r, Ok(Err(_))), "connexion fermée");

    // Un manifeste incohérent : refusé proprement.
    let mut tls = connexion(&m).await;
    trame::ecrire_controle(&mut tls, &Controle::Bonjour { v: 1, appareil: Appareil { nom: "P".into(), plateforme: "x".into() } }).await.unwrap();
    let _ = trame::lire_controle(&mut tls).await.unwrap();
    let absurde = Manifeste {
        fichiers: vec![FichierManifeste { id: 0, chemin: "x".into(), taille: u64::MAX / 2, taille_bloc: 1 << 20, blocs: vec![], totale: Empreinte([0; 32]) }],
    };
    trame::ecrire_controle(&mut tls, &Controle::Offre { offre: "o".into(), manifeste: absurde }).await.unwrap();
    assert!(matches!(trame::lire_controle(&mut tls).await.unwrap(), Controle::Reponse { acceptee: false, .. }));

    // Toujours debout : un appareil honnête est encore servi.
    let mut tls = connexion(&m).await;
    trame::ecrire_controle(&mut tls, &Controle::Bonjour { v: 1, appareil: Appareil { nom: "P".into(), plateforme: "x".into() } }).await.unwrap();
    assert!(matches!(trame::lire_controle(&mut tls).await.unwrap(), Controle::Bonjour { .. }));
    let _ = Arc::new(());
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn sans_certificat_client_refuse() {
    let (m, _d) = recepteur().await;
    // Un client TLS sans certificat : la poignée de main échoue.
    let fournisseur = drop_crypto::fournisseur();
    let id = Identite::nouvelle().unwrap();
    let avec = config_client(&id, Some(m.empreinte())).unwrap();
    let mut sans = (*avec).clone();
    sans.client_auth_cert_resolver = Arc::new(rustls::client::AlwaysResolvesClientRawPublicKeys::new(Arc::new(rustls::sign::CertifiedKey::new(
        vec![],
        fournisseur.key_provider.load_private_key(rustls::pki_types::PrivateKeyDer::Pkcs8(rcgen::KeyPair::generate().unwrap().serialize_der().into())).unwrap(),
    ))));
    let tcp = TcpStream::connect(SocketAddr::from(([127, 0, 0, 1], m.port()))).await.unwrap();
    let r = TlsConnector::from(Arc::new(sans)).connect(nom_serveur(), tcp).await;
    let refuse = match r {
        Err(_) => true,
        Ok(mut t) => trame::lire_controle(&mut t).await.is_err(),
    };
    assert!(refuse);
}
