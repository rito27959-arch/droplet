// GÉNÉRÉ par droplet-site/design/generer.mjs à partir de droplet-design.json
// (Droplet Design 1.0.0). Ne pas modifier à la main : modifier le JSON,
// relancer le générateur, recopier la sortie dans chaque app.

// ignore_for_file: constant_identifier_names

import 'package:flutter/animation.dart' show Cubic;
import 'package:flutter/painting.dart';

/// La version du système, affichable dans « À propos ».
const String versionDropletDesign = '1.0.0';

/// La couleur de chaque produit.
abstract final class DDMarque {
  static const Color goutte = Color(0xFFFF2D55);
  static const Color drop = Color(0xFF168BFF);
  static const Color drop2 = Color(0xFF34D8FF);
}

/// Une couleur d'accent, en version claire et sombre.
class DDAccent {
  const DDAccent(this.cle, this.clair, this.sombre);
  final String cle;
  final Color clair;
  final Color sombre;
  Color pour({required bool sombre}) => sombre ? this.sombre : clair;
}

/// Les accents proposés à l'utilisateur, dans l'ordre de la famille.
abstract final class DDAccents {
  static const List<DDAccent> liste = [
    DDAccent('rose', Color(0xFFFF2D55), Color(0xFFFF375F)),
    DDAccent('bleu', Color(0xFF007AFF), Color(0xFF0A84FF)),
    DDAccent('indigo', Color(0xFF5856D6), Color(0xFF5E5CE6)),
    DDAccent('violet', Color(0xFFAF52DE), Color(0xFFBF5AF2)),
    DDAccent('rouge', Color(0xFFFF3B30), Color(0xFFFF453A)),
    DDAccent('orange', Color(0xFFFF9500), Color(0xFFFF9F0A)),
    DDAccent('vert', Color(0xFF34C759), Color(0xFF30D158)),
    DDAccent('menthe', Color(0xFF00C7BE), Color(0xFF63E6E2)),
    DDAccent('cyan', Color(0xFF32ADE6), Color(0xFF64D2FF)),
    DDAccent('graphite', Color(0xFF8E8E93), Color(0xFF98989D)),
  ];
  static const String defaut = 'rose';
  static DDAccent parCle(String? cle) => liste.firstWhere((a) => a.cle == cle, orElse: () => liste.firstWhere((a) => a.cle == defaut));
}

/// Les neutres « système », en clair.
abstract final class DDClair {
  static const Color fond = Color(0xFFFFFFFF);
  static const Color fondGroupe = Color(0xFFF5F5F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceHaute = Color(0xFFF2F2F7);
  static const Color texte = Color(0xFF1D1D1F);
  static const Color texte2 = Color(0xFF6E6E73);
  static const Color texte3 = Color(0xFF86868B);
  static const Color trait = Color(0x1A000000);
}

/// Les neutres « système », en sombre.
abstract final class DDSombre {
  static const Color fond = Color(0xFF000000);
  static const Color fondGroupe = Color(0xFF000000);
  static const Color surface = Color(0xFF1C1C1E);
  static const Color surfaceHaute = Color(0xFF2C2C2E);
  static const Color texte = Color(0xFFF5F5F7);
  static const Color texte2 = Color(0xFFA1A1A6);
  static const Color texte3 = Color(0xFF86868B);
  static const Color trait = Color(0x1FFFFFFF);
}

/// Les neutres « scène » : la nuit des moments de marque.
abstract final class DDScene {
  static const Color nuit = Color(0xFF05070C);
  static const Color nuitEleve = Color(0xFF0A0E17);
  static const Color verre = Color(0xFF10151F);
  static const Color verreHaut = Color(0xFF1A2130);
  static const Color texte = Color(0xFFF7F9FC);
  static const Color texte2 = Color(0xFFA5B0C1);
  static const Color texte3 = Color(0xFF7D889B);
  static const Color trait = Color(0x14FFFFFF);
}

/// Les couleurs d'état sur fond clair.
abstract final class DDEtatsClair {
  static const Color succes = Color(0xFF107A43);
  static const Color attention = Color(0xFF9F5300);
  static const Color erreur = Color(0xFFD12B21);
}

/// Les couleurs d'état sur fond sombre.
abstract final class DDEtatsSombre {
  static const Color succes = Color(0xFF30D158);
  static const Color attention = Color(0xFFFF9F0A);
  static const Color erreur = Color(0xFFFF453A);
}

/// La typographie : Inter Tight pour les titres, Inter pour le texte.
abstract final class DDTypo {
  static const String titres = 'Inter Tight';
  static const String texte = 'Inter';
  static const List<String> secours = ['SF Pro Display', 'Segoe UI', 'Roboto', 'Noto Sans', 'Noto Sans Arabic', 'Noto Sans Devanagari', 'PingFang SC', 'Microsoft YaHei'];

  static const TextStyle hero = TextStyle(fontFamily: titres, fontFamilyFallback: secours, fontSize: 34.0, fontWeight: FontWeight.w700, height: 1.06, letterSpacing: -0.748);
  static const TextStyle grandTitre = TextStyle(fontFamily: titres, fontFamilyFallback: secours, fontSize: 34.0, fontWeight: FontWeight.w700, height: 1.1, letterSpacing: -0.748);
  static const TextStyle titre1 = TextStyle(fontFamily: titres, fontFamilyFallback: secours, fontSize: 28.0, fontWeight: FontWeight.w700, height: 1.14, letterSpacing: -0.56);
  static const TextStyle titre2 = TextStyle(fontFamily: titres, fontFamilyFallback: secours, fontSize: 22.0, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.352);
  static const TextStyle titre3 = TextStyle(fontFamily: titres, fontFamilyFallback: secours, fontSize: 20.0, fontWeight: FontWeight.w600, height: 1.25, letterSpacing: -0.24);
  static const TextStyle manchette = TextStyle(fontFamily: texte, fontFamilyFallback: secours, fontSize: 17.0, fontWeight: FontWeight.w600, height: 1.29, letterSpacing: -0.408);
  static const TextStyle corps = TextStyle(fontFamily: texte, fontFamilyFallback: secours, fontSize: 17.0, fontWeight: FontWeight.w400, height: 1.29, letterSpacing: -0.408);
  static const TextStyle appel = TextStyle(fontFamily: texte, fontFamilyFallback: secours, fontSize: 16.0, fontWeight: FontWeight.w400, height: 1.31, letterSpacing: -0.32);
  static const TextStyle sousTitre = TextStyle(fontFamily: texte, fontFamilyFallback: secours, fontSize: 15.0, fontWeight: FontWeight.w400, height: 1.33, letterSpacing: -0.24);
  static const TextStyle note = TextStyle(fontFamily: texte, fontFamilyFallback: secours, fontSize: 13.0, fontWeight: FontWeight.w400, height: 1.38, letterSpacing: -0.078);
  static const TextStyle legende = TextStyle(fontFamily: texte, fontFamilyFallback: secours, fontSize: 12.0, fontWeight: FontWeight.w500, height: 1.33, letterSpacing: 0);
  static const TextStyle grandChiffre = TextStyle(fontFamily: titres, fontFamilyFallback: secours, fontSize: 40.0, fontWeight: FontWeight.w700, height: 1, letterSpacing: -1.2, fontFeatures: [FontFeature.tabularFigures()]);
}

/// Les espacements (grille de 4 points).
abstract final class DDEspace {
  static const double e1 = 4.0;
  static const double e2 = 8.0;
  static const double e3 = 12.0;
  static const double e4 = 16.0;
  static const double e5 = 20.0;
  static const double e6 = 24.0;
  static const double e8 = 32.0;
  static const double e10 = 40.0;
  static const double e12 = 48.0;
  static const double e16 = 64.0;
  static const double marge = 16.0;
  static const double cible = 44.0;
}

/// Les arrondis.
abstract final class DDRayons {
  static const double petit = 8.0;
  static const double controle = 12.0;
  static const double champ = 14.0;
  static const double carte = 20.0;
  static const double carteGrande = 24.0;
  static const double feuille = 28.0;
  static const double bulle = 19.0;
  static const double bulleQueue = 6.0;
  static const double icone = 22.5;
  static const double gelule = 999.0;
}

/// Le mouvement.
abstract final class DDMouvement {
  static const Duration instant = Duration(milliseconds: 100);
  static const Duration rapide = Duration(milliseconds: 200);
  static const Duration standard = Duration(milliseconds: 300);
  static const Duration lent = Duration(milliseconds: 450);
  static const Duration scene = Duration(milliseconds: 700);
  static const Cubic courbe = Cubic(0.25, 0.1, 0.25, 1);
  static const Cubic sortie = Cubic(0.16, 1, 0.3, 1);
}

/// La lueur, signature de la famille.
abstract final class DDLueur {
  static const double opacite = 0.35;
  static const double flou = 48.0;
  static const double etoiles = 0.55;
}
