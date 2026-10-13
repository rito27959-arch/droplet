//! La carte des blocs reçus d'un fichier : un bit par bloc.

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CarteBlocs {
    nombre: u32,
    #[serde(with = "hex_vec")]
    bits: Vec<u8>,
}

impl CarteBlocs {
    pub fn vide(nombre: u32) -> Self {
        Self { nombre, bits: vec![0; (nombre as usize).div_ceil(8)] }
    }

    pub fn pleine(nombre: u32) -> Self {
        let mut c = Self::vide(nombre);
        for i in 0..nombre {
            c.marquer(i);
        }
        c
    }

    pub fn nombre(&self) -> u32 {
        self.nombre
    }

    pub fn a(&self, i: u32) -> bool {
        i < self.nombre && self.bits[(i / 8) as usize] & (1 << (i % 8)) != 0
    }

    pub fn marquer(&mut self, i: u32) {
        if i < self.nombre {
            self.bits[(i / 8) as usize] |= 1 << (i % 8);
        }
    }

    pub fn effacer(&mut self, i: u32) {
        if i < self.nombre {
            self.bits[(i / 8) as usize] &= !(1 << (i % 8));
        }
    }

    pub fn compte(&self) -> u32 {
        (0..self.nombre).filter(|&i| self.a(i)).count() as u32
    }

    pub fn complete(&self) -> bool {
        self.compte() == self.nombre
    }

    /// Les blocs qui manquent, dans l'ordre.
    pub fn manquants(&self) -> Vec<u32> {
        (0..self.nombre).filter(|&i| !self.a(i)).collect()
    }

    /// Une carte reçue du réseau est-elle cohérente avec ce nombre de blocs ?
    pub fn valide_pour(&self, nombre: u32) -> bool {
        self.nombre == nombre && self.bits.len() == (nombre as usize).div_ceil(8)
    }
}

mod hex_vec {
    use serde::{Deserialize, Deserializer, Serializer};
    pub fn serialize<S: Serializer>(v: &[u8], s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&hex::encode(v))
    }
    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<u8>, D::Error> {
        let t = String::deserialize(d)?;
        hex::decode(t).map_err(serde::de::Error::custom)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn marquer_et_compter() {
        let mut c = CarteBlocs::vide(11);
        assert_eq!(c.compte(), 0);
        c.marquer(0);
        c.marquer(10);
        c.marquer(42); // hors limites : ignoré
        assert!(c.a(0) && c.a(10) && !c.a(5));
        assert_eq!(c.manquants().len(), 9);
        c.effacer(0);
        assert!(!c.a(0));
        assert!(CarteBlocs::pleine(11).complete());
        let j = serde_json::to_string(&c).unwrap();
        assert_eq!(serde_json::from_str::<CarteBlocs>(&j).unwrap(), c);
    }
}
