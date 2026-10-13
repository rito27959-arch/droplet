// DROPLET LIQUID — la typographie.
//
// La police du système (SF sur Apple, Roboto sur Android, Segoe sur
// Windows, celle du bureau sur Linux) : elle est lisible, familière, et
// suit les réglages d'accessibilité. Une seule échelle, cinq tailles, trois
// graisses ; les chiffres qui bougent (progression, débit) sont à chasse
// fixe pour ne pas trembler.
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

class Typo {
  Typo._();

  static const _tabulaires = [FontFeature.tabularFigures()];

  static const TextStyle grandTitre = TextStyle(fontSize: 34, height: 1.12, fontWeight: FontWeight.w700, letterSpacing: -0.8);
  static const TextStyle titre = TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: -0.4);
  static const TextStyle titreCarte = TextStyle(fontSize: 17, height: 1.25, fontWeight: FontWeight.w600, letterSpacing: -0.2);
  static const TextStyle corps = TextStyle(fontSize: 16, height: 1.4, fontWeight: FontWeight.w400, letterSpacing: -0.1);
  static const TextStyle secondaire = TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w400);
  static const TextStyle legende = TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w500, letterSpacing: 0.1);
  static const TextStyle chiffres = TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w500, fontFeatures: _tabulaires);
  static const TextStyle grandChiffre = TextStyle(fontSize: 40, height: 1.0, fontWeight: FontWeight.w700, letterSpacing: -1.2, fontFeatures: _tabulaires);
}
