// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LES GARDE-FOUS DE L'EXPÉRIENCE NEXUS — l'animation jouée sur les DEUX
// téléphones quand ils se rencontrent pour la première fois.
//
// ── Pourquoi ces tests-là et pas d'autres ─────────────────────────────
//
// On ne peut pas tester « est-ce que c'est beau », ni exécuter un shader
// sans processeur graphique. En revanche, les trois choses qui ont
// réellement cassé cette fonctionnalité sont, elles, parfaitement
// testables sans écran :
//
//   1. Le décalage entre le shader et le code Dart qui l'alimente. Les
//      uniformes sont adressés par POSITION : ajouter une ligne dans le
//      `.frag` sans ajouter le `setFloat` correspondant produit une image
//      absurde, ou rien du tout, sans aucune erreur.
//
//   2. La désynchronisation des deux appareils. Toute la promesse du
//      Nexus est que les deux écrans montrent la même chose au même
//      instant : même couleur, même forme, même réseau de points. Cela
//      repose entièrement sur deux fonctions déterministes.
//
//   3. La table des durées. `overallProgress` — donc l'horloge des
//      particules — se calcule à partir du total. Ajouter une phase sans
//      corriger le total fausse silencieusement toute l'animation.
// ============================================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:droplet/features/nexus_connection/nexus_controller.dart';
import 'package:droplet/features/nexus_connection/nexus_event.dart';

void main() {
  group('Nexus — le contrat entre le shader et le Dart', () {
    test('autant de setFloat que d\'uniformes déclarés dans le shader', () {
      // ⚠️ LE TEST LE PLUS IMPORTANT DE CE FICHIER.
      //
      // `nexus.frag` déclarait un `uDpr` que Dart envoyait en 16ᵉ
      // position, et s'en servait pour une normalisation fautive : toute
      // la scène se retrouvait écrasée dans le coin de l'écran, et
      // l'effet paraissait « ne pas marcher ». Une fois `uDpr` retiré du
      // shader, oublier de retirer le `setFloat(15)` correspondant aurait
      // levé une exception à la première image.
      //
      // Ce test compte les deux côtés et exige qu'ils correspondent.
      final frag = File('shaders/nexus.frag').readAsStringSync();
      final dart = File('lib/features/nexus_connection/nexus_shader.dart')
          .readAsStringSync();

      var floatsAttendus = 0;
      for (final ligne in frag.split('\n')) {
        final nue = ligne.trimLeft();
        if (!nue.startsWith('uniform ')) continue;
        // Un `vec2` occupe deux emplacements de float, un `float` un seul.
        if (nue.startsWith('uniform vec2')) {
          floatsAttendus += 2;
        } else if (nue.startsWith('uniform vec3')) {
          floatsAttendus += 3;
        } else if (nue.startsWith('uniform vec4')) {
          floatsAttendus += 4;
        } else if (nue.startsWith('uniform float')) {
          floatsAttendus += 1;
        }
      }

      final indices = <int>{};
      for (final m in RegExp(r'setFloat\(\s*(\d+)\s*,').allMatches(dart)) {
        indices.add(int.parse(m.group(1)!));
      }

      expect(
        indices.length,
        floatsAttendus,
        reason: 'Le shader déclare $floatsAttendus emplacements de float, le '
            'painter en écrit ${indices.length}. Les uniformes sont '
            'positionnels : tout écart produit une image fausse, ou une '
            'exception à chaque image.',
      );
      // Les index doivent former une suite continue depuis 0 : un trou
      // signifie qu'un uniforme n'est jamais alimenté.
      expect(
        indices.toList()..sort(),
        List<int>.generate(floatsAttendus, (i) => i),
        reason: 'Les index de setFloat doivent aller de 0 à '
            '${floatsAttendus - 1} sans trou.',
      );
    });

    test('le shader lit tous les uniformes qu\'il déclare', () {
      // Un uniforme déclaré mais jamais lu peut être supprimé par le
      // compilateur — et toute la numérotation positionnelle se décale
      // derrière lui. C'était le cas de `uSeedZ`, `uSeedW`, `uColorA` et
      // `uOverallProgress` : quatre bombes à retardement, plus la moitié
      // de la seed jetée alors qu'elle sert précisément à ce que les deux
      // téléphones voient la même chose.
      final lignes = File('shaders/nexus.frag').readAsLinesSync();
      final declares = <String>[];
      final corps = StringBuffer();

      for (final ligne in lignes) {
        final nue = ligne.trimLeft();
        if (nue.startsWith('//')) continue;
        final m = RegExp(r'^uniform\s+\w+\s+(\w+)\s*;').firstMatch(nue);
        if (m != null) {
          declares.add(m.group(1)!);
        } else {
          corps.writeln(ligne.split('//').first);
        }
      }

      expect(declares, isNotEmpty);
      final jamaisLus = declares
          .where((u) => !RegExp('\\b$u\\b').hasMatch(corps.toString()))
          .toList();
      expect(jamaisLus, isEmpty,
          reason: 'Uniformes déclarés mais jamais lus : $jamaisLus');
    });

    test('les coordonnées ne sont pas divisées deux fois par la densité', () {
      // La régression exacte qui a cassé l'effet. `FlutterFragCoord()`
      // rend déjà des coordonnées logiques ; les diviser par la densité
      // d'écran en plus de `uSize` écrase la scène dans un coin.
      final frag = File('shaders/nexus.frag').readAsStringSync();
      expect(
        frag.contains(RegExp(r'FlutterFragCoord\(\)\.xy\s*/\s*uSize\s*;')),
        isTrue,
        reason: 'La normalisation doit rester `FlutterFragCoord().xy / uSize`, '
            'comme dans shaders/liquid.frag.',
      );
    });
  });

  group('Nexus — les deux téléphones doivent voir la même chose', () {
    test('la couleur ne dépend pas de qui a détecté l\'autre en premier', () {
      // Chaque appareil calcule la couleur de son côté, avec les deux
      // identifiants dans l'ordre où il les connaît. Si la fonction
      // n'était pas symétrique, les deux écrans afficheraient deux
      // couleurs différentes pendant la même rencontre.
      const a = 'peer-alice-0001';
      const b = 'peer-bob-0002';
      expect(
        NexusEvent.deriveColorSignature(a, b),
        NexusEvent.deriveColorSignature(b, a),
      );
    });

    test('la couleur reste dans la palette lumineuse de Droplet', () {
      // Jamais de rouge ni d'orange : la teinte est contrainte entre le
      // cyan et le violet. Un rouge plein écran pendant une rencontre
      // réussie enverrait exactement le mauvais signal.
      for (var i = 0; i < 200; i++) {
        final argb = NexusEvent.deriveColorSignature('a$i', 'b$i');
        final r = (argb >> 16) & 0xFF;
        final b = argb & 0xFF;
        expect(b, greaterThanOrEqualTo(r),
            reason: 'Teinte hors palette (rouge dominant) pour la paire $i.');
        expect((argb >> 24) & 0xFF, 0xFF, reason: 'La couleur doit être opaque.');
      }
    });

    test('la seed est hexadécimale et assez longue pour le shader', () {
      // `NexusShaderPainter` lit les quatre premiers octets de la seed en
      // hexadécimal. Une seed plus courte, ou non hexadécimale, le
      // ferait retomber sur une valeur neutre — et les deux téléphones
      // afficheraient alors la même animation générique au lieu de la
      // leur.
      for (var i = 0; i < 20; i++) {
        final seed = NexusEvent.generateSeed();
        expect(seed.length, greaterThanOrEqualTo(8));
        expect(RegExp(r'^[0-9a-f]+$').hasMatch(seed), isTrue,
            reason: 'Seed non hexadécimale : $seed');
      }
    });

    test('deux seeds successives diffèrent', () {
      expect(NexusEvent.generateSeed(), isNot(NexusEvent.generateSeed()));
    });
  });

  group('Nexus — la table des durées', () {
    test('le total est exactement la somme des phases', () {
      // `overallProgress` — donc l'horloge des particules — est calculé à
      // partir de ce total. Ajouter une phase sans corriger le total ferait
      // avancer les particules à une vitesse fausse, sans rien casser de
      // visible dans le code.
      final somme = NexusDurations.awakening +
          NexusDurations.dropletBirth +
          NexusDurations.connectionWave +
          NexusDurations.dualSync +
          NexusDurations.identity +
          NexusDurations.complete;
      expect(NexusDurations.total, somme);
    });

    test('la séquence reste courte', () {
      // Une rencontre entre deux téléphones ne doit pas confisquer
      // l'écran : au-delà d'une dizaine de secondes, une animation qu'on
      // n'a pas demandée devient une interruption.
      expect(NexusDurations.total.inSeconds, lessThanOrEqualTo(10));
    });
  });
}
