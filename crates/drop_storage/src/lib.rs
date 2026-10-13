//! # L'historique des transferts (SQLite)
//!
//! Une ligne par transfert terminé (ou abandonné) : sens, fichiers, taille,
//! appareil, état final, dates, emplacement. Rien n'est effacé du disque
//! quand on efface l'historique : seulement la ligne.

use std::path::Path;

use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Entree {
    pub id: String,
    /// « envoi » ou « reception ».
    pub sens: String,
    pub titre: String,
    pub fichiers: u32,
    pub taille: u64,
    pub appareil: String,
    pub empreinte: String,
    /// « termine », « refuse », « annule », « echec ».
    pub etat: String,
    pub debut: i64,
    pub fin: i64,
    /// Chemins des fichiers reçus (séparés par des sauts de ligne).
    pub chemins: String,
}

pub struct Historique {
    db: Connection,
}

impl Historique {
    pub fn ouvrir(fichier: &Path) -> rusqlite::Result<Self> {
        let db = Connection::open(fichier)?;
        db.execute_batch(
            "PRAGMA journal_mode = WAL;
             CREATE TABLE IF NOT EXISTS historique (
               id TEXT PRIMARY KEY, sens TEXT NOT NULL, titre TEXT NOT NULL,
               fichiers INTEGER NOT NULL, taille INTEGER NOT NULL,
               appareil TEXT NOT NULL, empreinte TEXT NOT NULL, etat TEXT NOT NULL,
               debut INTEGER NOT NULL, fin INTEGER NOT NULL, chemins TEXT NOT NULL DEFAULT ''
             );
             CREATE INDEX IF NOT EXISTS historique_fin ON historique (fin DESC);",
        )?;
        Ok(Self { db })
    }

    pub fn enregistrer(&self, e: &Entree) -> rusqlite::Result<()> {
        self.db.execute(
            "INSERT OR REPLACE INTO historique (id, sens, titre, fichiers, taille, appareil, empreinte, etat, debut, fin, chemins)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
            params![e.id, e.sens, e.titre, e.fichiers, e.taille as i64, e.appareil, e.empreinte, e.etat, e.debut, e.fin, e.chemins],
        )?;
        Ok(())
    }

    /// Les plus récentes d'abord ; [recherche] filtre sur le titre, les
    /// chemins et l'appareil.
    pub fn lister(&self, recherche: &str, limite: u32) -> rusqlite::Result<Vec<Entree>> {
        let motif = format!("%{}%", recherche.replace('%', "").replace('_', ""));
        let mut st = self.db.prepare(
            "SELECT id, sens, titre, fichiers, taille, appareil, empreinte, etat, debut, fin, chemins FROM historique
             WHERE titre LIKE ?1 OR appareil LIKE ?1 OR chemins LIKE ?1 ORDER BY fin DESC LIMIT ?2",
        )?;
        let lignes = st.query_map(params![motif, limite], |r| {
            Ok(Entree {
                id: r.get(0)?,
                sens: r.get(1)?,
                titre: r.get(2)?,
                fichiers: r.get(3)?,
                taille: r.get::<_, i64>(4)? as u64,
                appareil: r.get(5)?,
                empreinte: r.get(6)?,
                etat: r.get(7)?,
                debut: r.get(8)?,
                fin: r.get(9)?,
                chemins: r.get(10)?,
            })
        })?;
        lignes.collect()
    }

    pub fn supprimer(&self, id: &str) -> rusqlite::Result<()> {
        self.db.execute("DELETE FROM historique WHERE id = ?1", params![id])?;
        Ok(())
    }

    pub fn tout_effacer(&self) -> rusqlite::Result<()> {
        self.db.execute("DELETE FROM historique", [])?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enregistrer_chercher_effacer() {
        let d = tempfile::tempdir().unwrap();
        let h = Historique::ouvrir(&d.path().join("h.db")).unwrap();
        let e = |id: &str, titre: &str, fin: i64| Entree {
            id: id.into(),
            sens: "reception".into(),
            titre: titre.into(),
            fichiers: 1,
            taille: 5_000_000_000,
            appareil: "PC de la salle 3".into(),
            empreinte: "ab".into(),
            etat: "termine".into(),
            debut: fin - 10,
            fin,
            chemins: format!("/recus/{titre}"),
        };
        h.enregistrer(&e("1", "Android Studio.zip", 100)).unwrap();
        h.enregistrer(&e("2", "cours.pdf", 200)).unwrap();
        let tout = h.lister("", 50).unwrap();
        assert_eq!(tout.len(), 2);
        assert_eq!(tout[0].id, "2");
        assert_eq!(tout[1].taille, 5_000_000_000);
        assert_eq!(h.lister("studio", 50).unwrap().len(), 1);
        h.supprimer("1").unwrap();
        assert_eq!(h.lister("", 50).unwrap().len(), 1);
        h.tout_effacer().unwrap();
        assert!(h.lister("", 50).unwrap().is_empty());
    }
}
