// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LES RÈGLES DU DESIGN, RENDUES EXÉCUTABLES.
//
// ── Pourquoi ce fichier existe ────────────────────────────────────────
//
// `design_tokens.dart`, `ouro_pressable.dart` et `ouro_scroll_behavior.dart`
// énoncent trois règles très claires : pas d'onde Material, pas de courbe
// qui rebondit, un seul comportement de défilement. Elles étaient écrites
// en commentaire — c'est-à-dire nulle part, du point de vue de l'outillage.
//
// Le résultat était mesurable : au moment d'écrire ce test, l'application
// contenait encore trois `InkWell` et cinq `Curves.elasticOut` en dehors du
// système de design, dont un dans la bulle de conversation — l'élément le
// plus regardé de l'app. Chacun avait été introduit par quelqu'un qui ne
// pouvait pas savoir, parce que rien ne le lui disait.
//
// Un commentaire ne défend pas une règle. Un test, si.
//
// ── Ce que ce fichier NE fait pas ─────────────────────────────────────
//
// Il ne juge pas si une animation est belle : c'est irréductiblement
// humain. Il vérifie seulement les trois interdits mécaniques, ceux dont
// la violation est visible à l'œil nu et détectable sans exécuter l'app.
// C'est un filet, pas un jury.
// ============================================================================

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:droplet/design_system/design_tokens.dart';

/// Les fichiers Dart de l'application, hors code généré.
List<File> _sourcesApplicatives({String racine = 'lib'}) {
  return Directory(racine)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      // Le code généré par Drift fait 5 463 lignes et n'obéit à aucune
      // règle de design — il n'en contient aucune non plus.
      .where((f) => !f.path.endsWith('.g.dart'))
      .where((f) => !f.path.endsWith('.freezed.dart'))
      .toList();
}

/// Les lignes de [fichier] qui contiennent [motif], hors commentaires.
///
/// ⚠️ LE FILTRE DES COMMENTAIRES EST INDISPENSABLE. Le système de design
/// explique longuement POURQUOI il refuse `InkWell` et `elasticOut` — en
/// nommant ces classes. Sans ce filtre, le test échouerait sur la
/// documentation même de la règle qu'il fait respecter.
List<String> _occurrences(File fichier, Pattern motif) {
  final resultats = <String>[];
  final lignes = fichier.readAsLinesSync();
  for (var i = 0; i < lignes.length; i++) {
    final ligne = lignes[i];
    final nue = ligne.trimLeft();
    if (nue.startsWith('//') || nue.startsWith('///') || nue.startsWith('*')) {
      continue;
    }
    if (ligne.contains(motif)) {
      resultats.add('${fichier.path}:${i + 1}  ${nue.trim()}');
    }
  }
  return resultats;
}

void main() {
  group('Empreinte gestuelle — les interdits du système de design', () {
    test("aucune onde Material (« ripple ») hors du système de design", () {
      // iOS enfonce l'élément touché ; Android propage une onde depuis le
      // point de contact. Les deux réponses dans la même app, c'est la
      // sensation qui change d'un écran à l'autre — pire que d'avoir
      // partout la même, même mauvaise. Voir `ouro_pressable.dart`.
      final coupables = <String>[];
      for (final fichier in _sourcesApplicatives()) {
        // Le système de design a le droit de nommer ce qu'il remplace.
        if (fichier.path.contains('design_system')) continue;
        coupables.addAll(_occurrences(fichier, RegExp(r'\bInkWell\b')));
        coupables.addAll(_occurrences(fichier, RegExp(r'\bInkResponse\b')));
      }
      expect(
        coupables,
        isEmpty,
        reason: 'Utiliser `OuroPressable` (enfoncement iOS) plutôt que '
            'l\'onde de Material :\n${coupables.join('\n')}',
      );
    });

    test('aucune courbe qui dépasse sa cible', () {
      // `elasticOut` et `bounceOut` font dépasser l'élément puis revenir.
      // C'est ce qui « paraît vivant » au premier coup d'œil et devient
      // insupportable au bout de dix minutes : à chaque interaction, on
      // attend que le rebond finisse avant de lire ce qu'on attendait.
      // Apple ne le fait jamais dans son interface système.
      final coupables = <String>[];
      for (final fichier in _sourcesApplicatives()) {
        if (fichier.path.contains('design_system')) continue;
        coupables.addAll(
          _occurrences(fichier, RegExp(r'Curves\.(elastic|bounce)\w*')),
        );
      }
      expect(
        coupables,
        isEmpty,
        reason: 'Utiliser `DesignTokens.curveEnter` / `curveStandard`, ou un '
            'ressort de `DesignTokens` si le mouvement suit le doigt :\n'
            '${coupables.join('\n')}',
      );
    });

    test('aucun halo de défilement Android', () {
      // Le rebond élastique dit déjà qu'on est arrivé au bout ; le halo
      // d'Android par-dessus ferait doublon, et c'est l'un des deux ou
      // trois gestes par lesquels on reconnaît la plateforme les yeux
      // fermés. Voir `ouro_scroll_behavior.dart`.
      final coupables = <String>[];
      for (final fichier in _sourcesApplicatives()) {
        if (fichier.path.contains('design_system')) continue;
        coupables.addAll(
          _occurrences(fichier, RegExp(r'GlowingOverscrollIndicator|'
              r'ClampingScrollPhysics')),
        );
      }
      expect(coupables, isEmpty,
          reason: 'Le défilement est posé une fois pour toute l\'app dans '
              '`OuroScrollBehavior` :\n${coupables.join('\n')}');
    });
  });

  group('Moteur de mouvement — les courbes elles-mêmes', () {
    test('aucune courbe des tokens ne dépasse sa valeur finale', () {
      // La règle n'est pas « ne pas écrire elasticOut » : c'est « aucun
      // mouvement ne dépasse sa cible ». On la vérifie donc sur les
      // courbes réellement exposées, en les échantillonnant — ce qui
      // attraperait aussi une courbe personnalisée mal réglée.
      final courbes = <String, Curve>{
        'curveStandard': DesignTokens.curveStandard,
        'curveEnter': DesignTokens.curveEnter,
        'curveExit': DesignTokens.curveExit,
        'curveInteractive': DesignTokens.curveInteractive,
        'curveSpring': DesignTokens.curveSpring,
        'curveBounce': DesignTokens.curveBounce,
        'curveDefault': DesignTokens.curveDefault,
        'curveEmphasis': DesignTokens.curveEmphasis,
        'curveFastOut': DesignTokens.curveFastOut,
      };

      for (final entree in courbes.entries) {
        for (var i = 0; i <= 100; i++) {
          final t = i / 100;
          final valeur = entree.value.transform(t);
          expect(
            valeur,
            lessThanOrEqualTo(1.0001),
            reason: '${entree.key} dépasse 1,0 à t=$t (valeur $valeur) : '
                'le mouvement rebondit.',
          );
          expect(
            valeur,
            greaterThanOrEqualTo(-0.0001),
            reason: '${entree.key} passe sous 0 à t=$t (valeur $valeur) : '
                'le mouvement recule avant de partir.',
          );
        }
      }
    });

    test('les durées restent dans la fenêtre iOS', () {
      // Au-delà de 350 ms pour une transition ordinaire, on n'a plus
      // l'impression que l'interface répond : on attend qu'elle finisse.
      expect(DesignTokens.durationInstant.inMilliseconds, lessThanOrEqualTo(120));
      expect(DesignTokens.durationFast.inMilliseconds, lessThanOrEqualTo(250));
      expect(DesignTokens.durationStandard.inMilliseconds, lessThanOrEqualTo(400));
      expect(DesignTokens.durationSheet.inMilliseconds, lessThanOrEqualTo(500));
    });

    test('le ressort « smooth » ne rebondit pas, le « snappy » à peine', () {
      // Rapport d'amortissement = c / (2 × √(k × m)). À 1,0 la masse
      // rejoint sa cible sans jamais la dépasser : c'est la définition du
      // ressort « smooth » de SwiftUI, et la raison pour laquelle on peut
      // s'en servir partout sans risque de rebond.
      final lisse = DesignTokens.springSmooth;
      final ratioLisse =
          lisse.damping / (2 * math.sqrt(lisse.stiffness * lisse.mass));
      expect(ratioLisse, closeTo(1.0, 0.01));

      // Assez amorti pour ne pas osciller visiblement, assez souple pour
      // qu'un geste direct ait l'air de retomber plutôt que de s'arrêter
      // net.
      final vif = DesignTokens.springSnappy;
      final ratioVif = vif.damping / (2 * math.sqrt(vif.stiffness * vif.mass));
      expect(ratioVif, greaterThan(0.8));
      expect(ratioVif, lessThan(1.0));
    });
  });
}
