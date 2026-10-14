// DROPLET DESIGN — la typographie de Droplet Drop.
//
// Celle de toute la famille (voir droplet_design.dart, généré depuis
// droplet-site/design) : Inter Tight pour les titres, larges et serrés comme
// sur les sites ; Inter pour le texte. Les chiffres qui bougent (progression,
// débit) sont à chasse fixe pour ne pas trembler.
//
// Les noms ci-dessous sont ceux des écrans de Drop ; chacun pointe sur un
// cran de l'échelle commune, pour qu'aucun écran n'invente sa taille.

import 'package:flutter/material.dart';

import 'droplet_design.dart';

class Typo {
  Typo._();

  static const _tabulaires = [FontFeature.tabularFigures()];

  /// Le titre de l'accueil, comme le héros des sites.
  static const TextStyle hero = DDTypo.hero;
  static const TextStyle grandTitre = DDTypo.grandTitre;

  /// Le titre d'un écran ou d'une feuille (« iPhone de Karim veut vous envoyer »).
  static const TextStyle titre = DDTypo.titre2;
  static const TextStyle titreCarte = DDTypo.manchette;
  static const TextStyle corps = DDTypo.appel;
  static const TextStyle secondaire = DDTypo.sousTitre;
  static const TextStyle legende = DDTypo.legende;
  static const TextStyle chiffres = TextStyle(fontFamily: DDTypo.texte, fontFamilyFallback: DDTypo.secours, fontSize: 15, height: 1.33, fontWeight: FontWeight.w500, letterSpacing: -0.24, fontFeatures: _tabulaires);
  static const TextStyle grandChiffre = DDTypo.grandChiffre;
}
