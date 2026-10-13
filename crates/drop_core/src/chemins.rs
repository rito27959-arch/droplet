//! Les chemins sûrs.
//!
//! Un nom de fichier arrive d'un autre appareil : il peut être maladroit
//! (« rapport:final?.pdf » sous Windows) ou malveillant
//! (« ../../.bashrc », « C:\Windows\… », « CON »). Règles :
//!
//! * seul un chemin RELATIF est accepté, découpé en composants ;
//! * « . », « .. », les composants vides et les racines sont refusés ;
//! * les caractères interdits sur l'une des cinq plateformes sont remplacés ;
//! * les noms réservés de Windows sont préfixés ;
//! * la profondeur et la longueur sont bornées.
//!
//! Le résultat est TOUJOURS sous le dossier de réception.

use std::path::{Path, PathBuf};

const MAX_PROFONDEUR: usize = 32;
const MAX_COMPOSANT: usize = 200;

const RESERVES_WINDOWS: &[&str] = &[
    "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7",
    "LPT8", "LPT9",
];

/// Rend un chemin relatif propre (« dossier/sous-dossier/nom.ext », avec
/// des « / »), ou `None` s'il ne reste rien d'utilisable.
pub fn nettoyer_chemin(brut: &str) -> Option<String> {
    let mut composants = Vec::new();
    for morceau in brut.split(['/', '\\']) {
        let mut c: String = morceau
            .chars()
            .map(|ch| match ch {
                '<' | '>' | ':' | '"' | '|' | '?' | '*' => '_',
                ch if (ch as u32) < 0x20 || ch == '\u{7f}' => '_',
                ch => ch,
            })
            .collect();
        // Windows ignore les points et espaces finaux : « a. » devient « a ».
        while c.ends_with('.') || c.ends_with(' ') {
            c.pop();
        }
        let c = c.trim_start().to_string();
        if c.is_empty() || c == "." || c == ".." {
            continue;
        }
        let base = c.split('.').next().unwrap_or("").to_ascii_uppercase();
        let c = if RESERVES_WINDOWS.contains(&base.as_str()) { format!("_{c}") } else { c };
        composants.push(tronquer(&c, MAX_COMPOSANT));
        if composants.len() > MAX_PROFONDEUR {
            return None;
        }
    }
    if composants.is_empty() {
        None
    } else {
        Some(composants.join("/"))
    }
}

/// Coupe à [max] octets sans casser un caractère, en gardant l'extension.
fn tronquer(s: &str, max: usize) -> String {
    if s.len() <= max {
        return s.to_string();
    }
    let (nom, ext) = match s.rfind('.') {
        Some(i) if s.len() - i <= 16 => (&s[..i], &s[i..]),
        _ => (s, ""),
    };
    let mut fin = max.saturating_sub(ext.len());
    while !nom.is_char_boundary(fin) {
        fin -= 1;
    }
    format!("{}{}", &nom[..fin.min(nom.len())], ext)
}

/// Le chemin où écrire [relatif] dans [dossier], sans écraser ce qui
/// existe : « photo.jpg », puis « photo (1).jpg », « photo (2).jpg »…
pub fn chemin_libre(dossier: &Path, relatif: &str) -> PathBuf {
    let mut chemin = dossier.to_path_buf();
    for c in relatif.split('/') {
        chemin.push(c);
    }
    if !chemin.exists() {
        return chemin;
    }
    let parent = chemin.parent().map(Path::to_path_buf).unwrap_or_else(|| dossier.to_path_buf());
    let nom = chemin.file_name().and_then(|n| n.to_str()).unwrap_or("fichier").to_string();
    let (base, ext) = match nom.rfind('.') {
        Some(i) if i > 0 => (nom[..i].to_string(), nom[i..].to_string()),
        _ => (nom.clone(), String::new()),
    };
    for n in 1..100_000 {
        let candidat = parent.join(format!("{base} ({n}){ext}"));
        if !candidat.exists() {
            return candidat;
        }
    }
    parent.join(format!("{base} ({}){ext}", std::process::id()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refuse_les_evasions() {
        assert_eq!(nettoyer_chemin("../../etc/passwd").as_deref(), Some("etc/passwd"));
        assert_eq!(nettoyer_chemin("/etc/passwd").as_deref(), Some("etc/passwd"));
        assert_eq!(nettoyer_chemin("C:\\Windows\\system32\\a.dll").as_deref(), Some("C_/Windows/system32/a.dll"));
        assert_eq!(nettoyer_chemin("..").as_deref(), None);
        assert_eq!(nettoyer_chemin("").as_deref(), None);
        assert_eq!(nettoyer_chemin("./././").as_deref(), None);
    }

    #[test]
    fn noms_difficiles() {
        assert_eq!(nettoyer_chemin("CON.txt").as_deref(), Some("_CON.txt"));
        assert_eq!(nettoyer_chemin("rapport:final?.pdf").as_deref(), Some("rapport_final_.pdf"));
        assert_eq!(nettoyer_chemin("fin. ").as_deref(), Some("fin"));
        assert_eq!(nettoyer_chemin("a\u{0}b").as_deref(), Some("a_b"));
        let long = format!("{}.mp4", "é".repeat(300));
        let r = nettoyer_chemin(&long).unwrap();
        assert!(r.len() <= MAX_COMPOSANT && r.ends_with(".mp4"));
        let profond = vec!["d"; 40].join("/");
        assert!(nettoyer_chemin(&profond).is_none());
    }

    #[test]
    fn ne_jamais_ecraser() {
        let d = tempfile::tempdir().unwrap();
        let p1 = chemin_libre(d.path(), "photo.jpg");
        std::fs::write(&p1, b"x").unwrap();
        let p2 = chemin_libre(d.path(), "photo.jpg");
        assert_eq!(p2.file_name().unwrap(), "photo (1).jpg");
        assert!(p2.starts_with(d.path()));
    }
}
