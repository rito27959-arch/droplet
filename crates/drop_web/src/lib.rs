//! # Échanger avec un navigateur
//!
//! Quand l'autre appareil n'a pas Droplet Drop (un ordinateur de bureau, un
//! iPhone…), celui-ci ouvre une petite page sur le réseau local : on y
//! télécharge les fichiers proposés, et — si l'utilisateur l'a permis — on y
//! dépose des fichiers qui arrivent dans le dossier de réception.
//!
//! * **Un jeton** de 128 bits, dans l'adresse (`?k=…`), est exigé pour
//!   chaque requête ; il est comparé en temps constant.
//! * **Ce n'est pas chiffré** : HTTP simple, sur le réseau local (ou la
//!   connexion directe). L'application le dit à l'utilisateur. Entre deux
//!   appareils Droplet Drop, on reste en TLS 1.3.
//! * La page ne vit que tant que l'écran de partage est ouvert.
//! * HTTP/1.1 minimal, une requête par connexion : GET de la page, GET d'un
//!   fichier (en flux), POST d'un fichier (en flux, taille annoncée).

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::Notify;

/// Ce que la page propose, et où vont les fichiers déposés.
pub struct Config {
    /// (fichier sur le disque, nom affiché).
    pub fichiers: Vec<(PathBuf, String)>,
    /// `Some(dossier)` : la page permet aussi d'envoyer vers l'appareil.
    pub reception: Option<PathBuf>,
    pub jeton: String,
    /// Les textes de la page, dans la langue de l'utilisateur.
    pub textes: serde_json::Value,
    pub nom_appareil: String,
    pub port: u16,
}

/// Ce qui se passe sur la page : `{"type":"web_telecharge","nom":…}` ou
/// `{"type":"web_recu","nom":…,"chemin":…}`.
pub type Rappel = Arc<dyn Fn(serde_json::Value) + Send + Sync>;

pub struct PartageWeb {
    pub port: u16,
    arret: Arc<Notify>,
    actif: Arc<AtomicBool>,
}

impl PartageWeb {
    pub fn arreter(&self) {
        self.actif.store(false, Ordering::Relaxed);
        self.arret.notify_waiters();
    }
}

impl Drop for PartageWeb {
    fn drop(&mut self) {
        self.arreter();
    }
}

pub async fn demarrer(config: Config, rappel: Rappel) -> std::io::Result<PartageWeb> {
    let ecoute = match TcpListener::bind(("0.0.0.0", config.port)).await {
        Ok(l) => l,
        Err(_) => TcpListener::bind(("0.0.0.0", 0)).await?,
    };
    let port = ecoute.local_addr()?.port();
    let arret = Arc::new(Notify::new());
    let actif = Arc::new(AtomicBool::new(true));
    let config = Arc::new(config);
    let (a, ac) = (arret.clone(), actif.clone());
    tokio::spawn(async move {
        while ac.load(Ordering::Relaxed) {
            let r = tokio::select! {
                r = ecoute.accept() => r,
                _ = a.notified() => break,
            };
            let Ok((tcp, _)) = r else { continue };
            let (c, rp) = (config.clone(), rappel.clone());
            tokio::spawn(async move {
                let _ = tokio::time::timeout(std::time::Duration::from_secs(6 * 3600), servir(tcp, &c, &rp)).await;
            });
        }
    });
    Ok(PartageWeb { port, arret, actif })
}

/// Comparaison en temps constant.
fn egal(a: &str, b: &str) -> bool {
    a.len() == b.len() && a.bytes().zip(b.bytes()).fold(0u8, |x, (p, q)| x | (p ^ q)) == 0
}

fn decoder(s: &str) -> String {
    let b = s.as_bytes();
    let mut sortie = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        match b[i] {
            b'+' => sortie.push(b' '),
            b'%' if i + 2 < b.len() => {
                if let Ok(v) = u8::from_str_radix(std::str::from_utf8(&b[i + 1..i + 3]).unwrap_or("zz"), 16) {
                    sortie.push(v);
                    i += 2;
                } else {
                    sortie.push(b'%');
                }
            }
            c => sortie.push(c),
        }
        i += 1;
    }
    String::from_utf8_lossy(&sortie).into_owned()
}

fn parametre(requete: &str, cle: &str) -> Option<String> {
    let q = requete.split_once('?')?.1;
    q.split('&').find_map(|p| {
        let (k, v) = p.split_once('=')?;
        (k == cle).then(|| decoder(v))
    })
}

/// Un nom de fichier sûr : pas de dossier, pas de caractère interdit.
pub fn nom_sur(nom: &str) -> String {
    let n: String = nom
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or("")
        .chars()
        .filter(|c| !c.is_control() && !matches!(c, '<' | '>' | ':' | '"' | '|' | '?' | '*'))
        .take(180)
        .collect();
    let n = n.trim().trim_start_matches('.').to_string();
    if n.is_empty() {
        "fichier".into()
    } else {
        n
    }
}

/// Un nom libre dans le dossier : « photo.jpg », sinon « photo (1).jpg »…
fn libre(dossier: &Path, nom: &str) -> PathBuf {
    let p = dossier.join(nom);
    if !p.exists() {
        return p;
    }
    let (base, ext) = match nom.rsplit_once('.') {
        Some((b, e)) if !b.is_empty() => (b.to_string(), format!(".{e}")),
        _ => (nom.to_string(), String::new()),
    };
    (1..10_000).map(|i| dossier.join(format!("{base} ({i}){ext}"))).find(|p| !p.exists()).unwrap_or(p)
}

async fn repondre(tcp: &mut TcpStream, statut: &str, type_: &str, corps: &[u8]) -> std::io::Result<()> {
    let tete = format!(
        "HTTP/1.1 {statut}\r\nContent-Type: {type_}\r\nContent-Length: {}\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n",
        corps.len()
    );
    tcp.write_all(tete.as_bytes()).await?;
    tcp.write_all(corps).await?;
    tcp.flush().await
}

async fn servir(mut tcp: TcpStream, c: &Config, rappel: &Rappel) -> std::io::Result<()> {
    // L'en-tête : jusqu'à la ligne vide (16 Kio au plus).
    let mut tampon = Vec::with_capacity(4096);
    let mut morceau = [0u8; 4096];
    let fin_tete = loop {
        let n = tcp.read(&mut morceau).await?;
        if n == 0 {
            return Ok(());
        }
        tampon.extend_from_slice(&morceau[..n]);
        if let Some(p) = tampon.windows(4).position(|w| w == b"\r\n\r\n") {
            break p + 4;
        }
        if tampon.len() > 16 * 1024 {
            return repondre(&mut tcp, "431 Request Header Fields Too Large", "text/plain", b"").await;
        }
    };
    let tete = String::from_utf8_lossy(&tampon[..fin_tete]).into_owned();
    let mut lignes = tete.lines();
    let premiere = lignes.next().unwrap_or("");
    let mut parties = premiere.split(' ');
    let methode = parties.next().unwrap_or("");
    let cible = parties.next().unwrap_or("/");
    let longueur: u64 = lignes
        .filter_map(|l| l.split_once(':'))
        .find(|(k, _)| k.trim().eq_ignore_ascii_case("content-length"))
        .and_then(|(_, v)| v.trim().parse().ok())
        .unwrap_or(0);
    let chemin = cible.split('?').next().unwrap_or("/");

    if chemin == "/favicon.ico" {
        return repondre(&mut tcp, "404 Not Found", "text/plain", b"").await;
    }
    let jeton_ok = parametre(cible, "k").is_some_and(|k| egal(&k, &c.jeton));
    if !jeton_ok {
        return repondre(&mut tcp, "403 Forbidden", "text/plain; charset=utf-8", b"Lien invalide ou expir\xc3\xa9.").await;
    }

    match (methode, chemin) {
        ("GET", "/") => {
            let page = page(c);
            repondre(&mut tcp, "200 OK", "text/html; charset=utf-8", page.as_bytes()).await
        }
        ("GET", p) if p.starts_with("/f/") => {
            let Some(i) = p[3..].parse::<usize>().ok().filter(|i| *i < c.fichiers.len()) else {
                return repondre(&mut tcp, "404 Not Found", "text/plain", b"").await;
            };
            let (disque, nom) = &c.fichiers[i];
            let mut f = tokio::fs::File::open(disque).await?;
            let taille = f.metadata().await?.len();
            let nom_ascii: String = nom.chars().map(|x| if x.is_ascii_alphanumeric() || ".-_ ()".contains(x) { x } else { '_' }).collect();
            let nom_utf8: String = nom.bytes().map(|b| if b.is_ascii_alphanumeric() || b".-_".contains(&b) { (b as char).to_string() } else { format!("%{b:02X}") }).collect();
            let tete = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: {taille}\r\nContent-Disposition: attachment; filename=\"{nom_ascii}\"; filename*=UTF-8''{nom_utf8}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
            );
            tcp.write_all(tete.as_bytes()).await?;
            tokio::io::copy(&mut f, &mut tcp).await?;
            tcp.flush().await?;
            rappel(serde_json::json!({ "type": "web_telecharge", "nom": nom }));
            Ok(())
        }
        ("POST", "/r") => {
            let Some(dossier) = &c.reception else {
                return repondre(&mut tcp, "403 Forbidden", "text/plain", b"").await;
            };
            let nom = nom_sur(&parametre(cible, "n").unwrap_or_default());
            if longueur == 0 {
                return repondre(&mut tcp, "400 Bad Request", "text/plain", b"").await;
            }
            tokio::fs::create_dir_all(dossier).await?;
            // D'abord dans un fichier caché ; renommé une fois complet.
            let temp = dossier.join(format!(".web-{}.partiel", c.jeton.get(..8).unwrap_or("x")));
            let temp = libre(dossier, temp.file_name().and_then(|n| n.to_str()).unwrap_or(".web.partiel"));
            let mut f = tokio::fs::File::create(&temp).await?;
            let deja = &tampon[fin_tete..];
            let mut recu = deja.len() as u64;
            f.write_all(&deja[..deja.len().min(longueur as usize)]).await?;
            let mut buf = vec![0u8; 1 << 16];
            while recu < longueur {
                let n = tcp.read(&mut buf[..((longueur - recu).min(1 << 16)) as usize]).await?;
                if n == 0 {
                    drop(f);
                    let _ = tokio::fs::remove_file(&temp).await;
                    return Ok(());
                }
                f.write_all(&buf[..n]).await?;
                recu += n as u64;
            }
            f.flush().await?;
            drop(f);
            let final_ = libre(dossier, &nom);
            tokio::fs::rename(&temp, &final_).await?;
            rappel(serde_json::json!({ "type": "web_recu", "nom": nom, "chemin": final_.to_string_lossy(), "taille": longueur }));
            repondre(&mut tcp, "200 OK", "application/json", b"{\"ok\":true}").await
        }
        _ => repondre(&mut tcp, "404 Not Found", "text/plain", b"").await,
    }
}

fn echapper(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

/// La page : sobre, lisible sur téléphone comme sur ordinateur, claire ou
/// sombre selon l'appareil. Aucune ressource externe.
fn page(c: &Config) -> String {
    let t = |k: &str| echapper(c.textes.get(k).and_then(|v| v.as_str()).unwrap_or(k));
    let k = &c.jeton;
    let mut lignes = String::new();
    for (i, (disque, nom)) in c.fichiers.iter().enumerate() {
        let taille = std::fs::metadata(disque).map(|m| m.len()).unwrap_or(0);
        lignes.push_str(&format!(
            r#"<li><span class="ico">{ico}</span><span class="nom"><b>{n}</b><small data-o="{taille}"></small></span><a class="btn" href="/f/{i}?k={k}" download>{dl}</a></li>"#,
            ico = icone(nom),
            n = echapper(nom),
            dl = t("telecharger"),
        ));
    }
    let fichiers = if c.fichiers.is_empty() {
        String::new()
    } else {
        format!(
            r#"<section><div class="tete"><h2>{titre}</h2><button class="lien" id="tout">{tout}</button></div><ul>{lignes}</ul></section>"#,
            titre = t("a_telecharger"),
            tout = t("tout_telecharger"),
        )
    };
    let depot = if c.reception.is_some() {
        format!(
            r#"<section><h2>{titre}</h2><label class="depot" id="depot"><input type="file" id="choix" multiple hidden><span class="plus">+</span><b>{choisir}</b><small>{glisser}</small></label><ul id="envois"></ul></section>"#,
            titre = t("envoyer_vers").replace("{nom}", &echapper(&c.nom_appareil)),
            choisir = t("choisir_fichiers"),
            glisser = t("ou_glisser"),
        )
    } else {
        String::new()
    };
    format!(
        r##"<!doctype html><html lang="{langue}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Droplet Drop</title>
<style>
:root{{--fond:#f5f5f7;--carte:#fff;--texte:#1d1d1f;--texte2:#6e6e73;--trait:rgba(0,0,0,.08);--accent:#168bff;--accent2:#34d8ff}}
@media(prefers-color-scheme:dark){{:root{{--fond:#05070c;--carte:#14161c;--texte:#f5f5f7;--texte2:#a1a1a6;--trait:rgba(255,255,255,.1)}}}}
*{{box-sizing:border-box}}body{{margin:0;font:16px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:var(--fond);color:var(--texte);-webkit-font-smoothing:antialiased}}
main{{max-width:640px;margin:0 auto;padding:40px 16px 60px}}
header{{text-align:center;margin-bottom:28px}}.logo{{width:64px;height:64px;border-radius:15px;margin:0 auto 14px;background:linear-gradient(135deg,var(--accent),var(--accent2));display:grid;place-items:center;box-shadow:0 12px 30px rgba(22,139,255,.35)}}
.logo svg{{width:34px;height:34px}}h1{{font-size:28px;letter-spacing:-.02em;margin:0 0 6px}}header p{{margin:0;color:var(--texte2)}}
section{{background:var(--carte);border-radius:18px;padding:18px;margin-bottom:16px;box-shadow:0 1px 0 var(--trait)}}
h2{{font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:var(--texte2);margin:0 0 10px}}.tete{{display:flex;justify-content:space-between;align-items:center}}
ul{{list-style:none;margin:0;padding:0}}li{{display:flex;align-items:center;gap:12px;padding:10px 0;border-top:1px solid var(--trait)}}li:first-child{{border-top:0}}
.ico{{width:40px;height:40px;border-radius:10px;background:var(--fond);display:grid;place-items:center;font-size:20px;flex:none}}
.nom{{flex:1;min-width:0}}.nom b{{display:block;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}}.nom small{{color:var(--texte2)}}
.btn{{background:linear-gradient(135deg,var(--accent),var(--accent2));color:#fff;text-decoration:none;font-weight:600;padding:8px 14px;border-radius:99px;font-size:14px;white-space:nowrap}}
.lien{{background:none;border:0;color:var(--accent);font:inherit;font-weight:600;cursor:pointer;padding:0}}
.depot{{display:flex;flex-direction:column;align-items:center;gap:4px;padding:28px 12px;border:2px dashed var(--trait);border-radius:14px;cursor:pointer;text-align:center}}
.depot.survol{{border-color:var(--accent);background:rgba(22,139,255,.06)}}.plus{{font-size:30px;color:var(--accent);line-height:1}}.depot small{{color:var(--texte2)}}
.barre{{height:4px;border-radius:2px;background:var(--trait);margin-top:6px;overflow:hidden}}.barre i{{display:block;height:100%;width:0;background:linear-gradient(90deg,var(--accent),var(--accent2))}}
footer{{text-align:center;color:var(--texte2);font-size:13px;margin-top:22px}}
</style></head><body><main>
<header><div class="logo"><svg viewBox="0 0 24 24" fill="#fff"><path d="M12 2.5C15 7 18.5 10.4 18.5 14.5a6.5 6.5 0 0 1-13 0C5.5 10.4 9 7 12 2.5Z"/></svg></div><h1>{appareil}</h1><p>{sous}</p></header>
{fichiers}{depot}
<footer>{pied}</footer></main>
<script>
const K={k:?};const T={textes};
function taille(o){{const u=T.unites||['B','KB','MB','GB','TB'];let i=0;while(o>=1000&&i<u.length-1){{o/=1000;i++}}return (i&&o<100?o.toFixed(1):Math.round(o))+' '+u[i]}}
document.querySelectorAll('small[data-o]').forEach(s=>s.textContent=taille(+s.dataset.o));
const tout=document.getElementById('tout');if(tout)tout.onclick=()=>{{const a=[...document.querySelectorAll('a.btn')];a.forEach((x,i)=>setTimeout(()=>x.click(),i*700))}};
const depot=document.getElementById('depot'),choix=document.getElementById('choix'),envois=document.getElementById('envois');
function envoyer(f){{const li=document.createElement('li');li.innerHTML='<span class="ico">⬆︎</span><span class="nom"><b></b><small></small><div class="barre"><i></i></div></span>';li.querySelector('b').textContent=f.name;const s=li.querySelector('small'),b=li.querySelector('.barre i');envois.prepend(li);
const x=new XMLHttpRequest();x.open('POST','/r?k='+K+'&n='+encodeURIComponent(f.name));x.upload.onprogress=e=>{{if(e.lengthComputable){{b.style.width=(e.loaded/e.total*100)+'%';s.textContent=taille(e.loaded)+' / '+taille(e.total)}}}};
x.onload=()=>{{b.style.width='100%';s.textContent=x.status==200?T.envoye:T.echec}};x.onerror=()=>{{s.textContent=T.echec}};x.send(f)}}
if(depot){{choix.onchange=()=>{{[...choix.files].forEach(envoyer);choix.value=''}};
['dragenter','dragover'].forEach(e=>depot.addEventListener(e,v=>{{v.preventDefault();depot.classList.add('survol')}}));
['dragleave','drop'].forEach(e=>depot.addEventListener(e,v=>{{v.preventDefault();depot.classList.remove('survol')}}));
depot.addEventListener('drop',v=>[...v.dataTransfer.files].forEach(envoyer))}}
</script></body></html>"##,
        langue = t("langue"),
        appareil = echapper(&c.nom_appareil),
        sous = t("sous_titre"),
        pied = t("pied"),
        textes = serde_json::json!({
            "envoye": c.textes.get("envoye").cloned().unwrap_or_default(),
            "echec": c.textes.get("echec").cloned().unwrap_or_default(),
            "unites": c.textes.get("unites").cloned().unwrap_or_default(),
        }),
    )
}

fn icone(nom: &str) -> &'static str {
    let ext = nom.rsplit_once('.').map(|(_, e)| e.to_ascii_lowercase()).unwrap_or_default();
    match ext.as_str() {
        "jpg" | "jpeg" | "png" | "gif" | "heic" | "webp" => "🖼️",
        "mp4" | "mov" | "mkv" | "avi" | "webm" => "🎬",
        "mp3" | "wav" | "m4a" | "flac" | "ogg" => "🎵",
        "apk" => "📦",
        "pdf" => "📕",
        "zip" | "rar" | "7z" => "🗜️",
        _ => "📄",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    async fn requete(port: u16, brut: &[u8]) -> String {
        let mut t = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
        t.write_all(brut).await.unwrap();
        let mut r = Vec::new();
        t.read_to_end(&mut r).await.unwrap();
        String::from_utf8_lossy(&r).into_owned()
    }

    #[tokio::test]
    async fn page_telechargement_depot_et_jeton() {
        let d = tempfile::tempdir().unwrap();
        let f = d.path().join("photo.jpg");
        std::fs::write(&f, b"0123456789").unwrap();
        let recus = d.path().join("recus");
        let evts = Arc::new(std::sync::Mutex::new(Vec::new()));
        let e2 = evts.clone();
        let p = demarrer(
            Config {
                fichiers: vec![(f.clone(), "Été 2031.jpg".into())],
                reception: Some(recus.clone()),
                jeton: "a".repeat(32),
                textes: serde_json::json!({"telecharger": "Télécharger"}),
                nom_appareil: "Pixel <de> Léa".into(),
                port: 0,
            },
            Arc::new(move |v| e2.lock().unwrap().push(v)),
        )
        .await
        .unwrap();
        let k = "a".repeat(32);
        // Sans jeton : refusé.
        assert!(requete(p.port, b"GET / HTTP/1.1\r\n\r\n").await.starts_with("HTTP/1.1 403"));
        assert!(requete(p.port, format!("GET /?k={} HTTP/1.1\r\n\r\n", "b".repeat(32)).as_bytes()).await.starts_with("HTTP/1.1 403"));
        // La page : échappée, avec le fichier.
        let r = requete(p.port, format!("GET /?k={k} HTTP/1.1\r\n\r\n").as_bytes()).await;
        assert!(r.starts_with("HTTP/1.1 200"));
        assert!(r.contains("Pixel &lt;de&gt; Léa") && r.contains("Été 2031.jpg"));
        // Le fichier.
        let r = requete(p.port, format!("GET /f/0?k={k} HTTP/1.1\r\n\r\n").as_bytes()).await;
        assert!(r.contains("Content-Length: 10") && r.ends_with("0123456789"));
        assert!(r.contains("filename*=UTF-8''%C3%89t%C3%A9%202031.jpg"));
        // Un dépôt, avec un nom piégé : il reste dans le dossier.
        let corps = b"bonjour";
        let mut brut = format!("POST /r?k={k}&n=..%2F..%2Fpi%C3%A8ge.txt HTTP/1.1\r\nContent-Length: {}\r\n\r\n", corps.len()).into_bytes();
        brut.extend_from_slice(corps);
        assert!(requete(p.port, &brut).await.starts_with("HTTP/1.1 200"));
        assert_eq!(std::fs::read(recus.join("piège.txt")).unwrap(), b"bonjour");
        // Le même nom une seconde fois : rien n'est écrasé.
        assert!(requete(p.port, &brut).await.starts_with("HTTP/1.1 200"));
        assert!(recus.join("piège (1).txt").exists());
        let e = evts.lock().unwrap();
        assert!(e.iter().any(|v| v["type"] == "web_telecharge"));
        assert_eq!(e.iter().filter(|v| v["type"] == "web_recu").count(), 2);
        // Pas de fichier partiel qui traîne.
        assert!(std::fs::read_dir(&recus).unwrap().all(|x| !x.unwrap().file_name().to_string_lossy().ends_with(".partiel")));
    }
}
