//! # L'identité et le chiffrement de Droplet Drop
//!
//! Aucun algorithme maison : TLS 1.3 (rustls, fournisseur `ring`),
//! certificats ECDSA P-256 (rcgen), empreintes SHA-256.
//!
//! ## L'identité d'un appareil
//!
//! Au premier lancement, chaque appareil fabrique un certificat
//! auto-signé et sa clé privée, gardés dans son dossier de données. Son
//! **empreinte** (SHA-256 du certificat) est son identité : elle voyage
//! dans les annonces de découverte (mDNS) et dans les codes QR
//! d'invitation.
//!
//! ## Les connexions
//!
//! Toute connexion est en TLS 1.3, **mutuelle** : les deux côtés
//! présentent leur certificat et prouvent qu'ils en détiennent la clé
//! (signature de la poignée de main, vérifiée normalement par rustls).
//! Il n'y a pas d'autorité de certification : à la place, celui qui se
//! connecte **épingle** l'empreinte qu'il attend (celle de l'annonce ou du
//! QR code). Un appareil qui se ferait passer pour un autre, sur le même
//! réseau, est refusé à la poignée de main.
//!
//! Celui qui reçoit la connexion apprend l'empreinte de l'autre : c'est
//! elle qui s'affiche (« A3F9-2C1B ») et qui sert aux règles de confiance.

use std::path::Path;
use std::sync::Arc;

use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::{verify_tls12_signature, verify_tls13_signature, CryptoProvider};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer, ServerName, UnixTime};
use rustls::server::danger::{ClientCertVerified, ClientCertVerifier};
use rustls::{DigitallySignedStruct, DistinguishedName, SignatureScheme};
use sha2::{Digest, Sha256};

#[derive(Debug, thiserror::Error)]
pub enum ErreurCrypto {
    #[error("entrée/sortie : {0}")]
    Io(#[from] std::io::Error),
    #[error("certificat : {0}")]
    Certificat(String),
    #[error("tls : {0}")]
    Tls(#[from] rustls::Error),
}

/// L'empreinte d'un appareil : SHA-256 de son certificat.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct EmpreinteAppareil(pub [u8; 32]);

impl EmpreinteAppareil {
    pub fn de_certificat(der: &[u8]) -> Self {
        Self(Sha256::digest(der).into())
    }

    pub fn hex(&self) -> String {
        hex::encode(self.0)
    }

    pub fn depuis_hex(t: &str) -> Option<Self> {
        let v = hex::decode(t.trim()).ok()?;
        Some(Self(v.try_into().ok()?))
    }

    /// La forme courte, lisible et comparable à voix haute : « A3F9-2C1B ».
    pub fn courte(&self) -> String {
        let h = hex::encode_upper(&self.0[..4]);
        format!("{}-{}", &h[..4], &h[4..])
    }
}

/// Le certificat et la clé de cet appareil.
#[derive(Clone)]
pub struct Identite {
    pub certificat: CertificateDer<'static>,
    cle: Arc<PrivatePkcs8KeyDer<'static>>,
    pub empreinte: EmpreinteAppareil,
}

impl Identite {
    pub fn nouvelle() -> Result<Self, ErreurCrypto> {
        let paire = rcgen::KeyPair::generate_for(&rcgen::PKCS_ECDSA_P256_SHA256).map_err(|e| ErreurCrypto::Certificat(e.to_string()))?;
        let mut params = rcgen::CertificateParams::new(vec!["droplet-drop.local".to_string()]).map_err(|e| ErreurCrypto::Certificat(e.to_string()))?;
        params.distinguished_name.push(rcgen::DnType::CommonName, "Droplet Drop");
        // Valable longtemps : l'identité est épinglée, pas vérifiée par date.
        params.not_before = rcgen::date_time_ymd(2024, 1, 1);
        params.not_after = rcgen::date_time_ymd(2124, 1, 1);
        let cert = params.self_signed(&paire).map_err(|e| ErreurCrypto::Certificat(e.to_string()))?;
        Ok(Self::depuis_der(cert.der().to_vec(), paire.serialize_der()))
    }

    fn depuis_der(cert: Vec<u8>, cle: Vec<u8>) -> Self {
        let empreinte = EmpreinteAppareil::de_certificat(&cert);
        Self { certificat: CertificateDer::from(cert), cle: Arc::new(PrivatePkcs8KeyDer::from(cle)), empreinte }
    }

    /// Charge l'identité gardée dans [dossier], ou en crée une.
    pub fn charger_ou_creer(dossier: &Path) -> Result<Self, ErreurCrypto> {
        let pc = dossier.join("identite.cert.der");
        let pk = dossier.join("identite.cle.der");
        if let (Ok(c), Ok(k)) = (std::fs::read(&pc), std::fs::read(&pk)) {
            return Ok(Self::depuis_der(c, k));
        }
        std::fs::create_dir_all(dossier)?;
        let id = Self::nouvelle()?;
        std::fs::write(&pc, id.certificat.as_ref())?;
        ecrire_prive(&pk, id.cle.secret_pkcs8_der())?;
        Ok(id)
    }

    fn cle(&self) -> PrivateKeyDer<'static> {
        PrivateKeyDer::Pkcs8(self.cle.as_ref().clone_key())
    }
}

/// La clé privée n'est lisible que par l'utilisateur (Unix).
fn ecrire_prive(p: &Path, octets: &[u8]) -> std::io::Result<()> {
    #[cfg(unix)]
    {
        use std::io::Write;
        use std::os::unix::fs::OpenOptionsExt;
        let mut f = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(p)?;
        f.write_all(octets)
    }
    #[cfg(not(unix))]
    {
        std::fs::write(p, octets)
    }
}

pub fn fournisseur() -> Arc<CryptoProvider> {
    Arc::new(rustls::crypto::ring::default_provider())
}

/// Côté serveur : TLS 1.3 seulement, certificat client OBLIGATOIRE
/// (n'importe lequel, auto-signé : c'est son empreinte qui compte).
pub fn config_serveur(id: &Identite) -> Result<Arc<rustls::ServerConfig>, ErreurCrypto> {
    let f = fournisseur();
    let mut c = rustls::ServerConfig::builder_with_provider(f.clone())
        .with_protocol_versions(&[&rustls::version::TLS13])?
        .with_client_cert_verifier(Arc::new(ToutCertificatPresente(f)))
        .with_single_cert(vec![id.certificat.clone()], id.cle())?;
    c.alpn_protocols = vec![b"droplet-drop/1".to_vec()];
    Ok(Arc::new(c))
}

/// Côté client : TLS 1.3, notre certificat présenté, et l'empreinte du
/// serveur épinglée quand on la connaît.
pub fn config_client(id: &Identite, attendue: Option<EmpreinteAppareil>) -> Result<Arc<rustls::ClientConfig>, ErreurCrypto> {
    let f = fournisseur();
    let mut c = rustls::ClientConfig::builder_with_provider(f.clone())
        .with_protocol_versions(&[&rustls::version::TLS13])?
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(Epinglage { attendue, fournisseur: f }))
        .with_client_auth_cert(vec![id.certificat.clone()], id.cle())?;
    c.alpn_protocols = vec![b"droplet-drop/1".to_vec()];
    Ok(Arc::new(c))
}

/// Le nom présenté dans la poignée de main (il n'est pas vérifié : c'est
/// l'empreinte qui l'est).
pub fn nom_serveur() -> ServerName<'static> {
    ServerName::try_from("droplet-drop.local").expect("nom fixe valide")
}

/// L'empreinte du pair d'une connexion établie.
pub fn empreinte_du_pair(certs: Option<&[CertificateDer<'_>]>) -> Option<EmpreinteAppareil> {
    certs.and_then(|c| c.first()).map(|c| EmpreinteAppareil::de_certificat(c.as_ref()))
}

#[derive(Debug)]
struct Epinglage {
    attendue: Option<EmpreinteAppareil>,
    fournisseur: Arc<CryptoProvider>,
}

impl ServerCertVerifier for Epinglage {
    fn verify_server_cert(
        &self,
        cert: &CertificateDer<'_>,
        _: &[CertificateDer<'_>],
        _: &ServerName<'_>,
        _: &[u8],
        _: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        match self.attendue {
            Some(e) if EmpreinteAppareil::de_certificat(cert.as_ref()) != e => {
                Err(rustls::Error::InvalidCertificate(rustls::CertificateError::ApplicationVerificationFailure))
            }
            _ => Ok(ServerCertVerified::assertion()),
        }
    }

    fn verify_tls12_signature(&self, m: &[u8], c: &CertificateDer<'_>, d: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls12_signature(m, c, d, &self.fournisseur.signature_verification_algorithms)
    }

    fn verify_tls13_signature(&self, m: &[u8], c: &CertificateDer<'_>, d: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls13_signature(m, c, d, &self.fournisseur.signature_verification_algorithms)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.fournisseur.signature_verification_algorithms.supported_schemes()
    }
}

#[derive(Debug)]
struct ToutCertificatPresente(Arc<CryptoProvider>);

impl ClientCertVerifier for ToutCertificatPresente {
    fn root_hint_subjects(&self) -> &[DistinguishedName] {
        &[]
    }

    fn verify_client_cert(&self, _: &CertificateDer<'_>, _: &[CertificateDer<'_>], _: UnixTime) -> Result<ClientCertVerified, rustls::Error> {
        Ok(ClientCertVerified::assertion())
    }

    fn client_auth_mandatory(&self) -> bool {
        true
    }

    fn verify_tls12_signature(&self, m: &[u8], c: &CertificateDer<'_>, d: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls12_signature(m, c, d, &self.0.signature_verification_algorithms)
    }

    fn verify_tls13_signature(&self, m: &[u8], c: &CertificateDer<'_>, d: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls13_signature(m, c, d, &self.0.signature_verification_algorithms)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.0.signature_verification_algorithms.supported_schemes()
    }
}

/// Un secret imprévisible, en hexadécimal (jetons de session).
pub fn secret_aleatoire(octets: usize) -> String {
    use rand::RngCore;
    let mut v = vec![0u8; octets];
    rand::rng().fill_bytes(&mut v);
    hex::encode(v)
}

/// Comparaison à temps constant (jetons).
pub fn egal_constant(a: &str, b: &str) -> bool {
    let (a, b) = (a.as_bytes(), b.as_bytes());
    if a.len() != b.len() {
        return false;
    }
    a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identite_persistante() {
        let d = tempfile::tempdir().unwrap();
        let a = Identite::charger_ou_creer(d.path()).unwrap();
        let b = Identite::charger_ou_creer(d.path()).unwrap();
        assert_eq!(a.empreinte, b.empreinte);
        assert_eq!(a.empreinte.courte().len(), 9);
        assert_eq!(EmpreinteAppareil::depuis_hex(&a.empreinte.hex()), Some(a.empreinte));
        assert!(config_serveur(&a).is_ok());
        assert!(config_client(&a, Some(b.empreinte)).is_ok());
        assert!(egal_constant("abc", "abc") && !egal_constant("abc", "abd"));
        assert_eq!(secret_aleatoire(32).len(), 64);
    }
}
