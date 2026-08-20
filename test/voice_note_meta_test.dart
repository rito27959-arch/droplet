// ============================================================================
// Ces tests protègent le FORMAT DE TRANSPORT des messages vocaux.
//
// La durée et la forme d'onde voyagent dans le nom du fichier. Si
// l'encodage et le décodage cessaient de se correspondre, les vocaux
// continueraient d'arriver — mais avec une durée fausse et un dessin
// aléatoire, sans que rien ne plante. C'est exactement le genre de
// régression qu'un test attrape et qu'un lancement de l'app ne montre
// pas tout de suite.
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:droplet/core/models/voice_note_meta.dart';

void main() {
  group('VoiceNoteMeta — aller-retour', () {
    test('la durée survit à l\'encodage puis au décodage', () {
      final name = VoiceNoteMeta.encodeFileName(
        duration: const Duration(seconds: 12, milliseconds: 340),
        samples: const [0.1, 0.5, 0.9],
      );

      final parsed = VoiceNoteMeta.tryParse(name);

      expect(parsed, isNotNull);
      expect(parsed!.duration, const Duration(seconds: 12, milliseconds: 340));
    });

    test('la forme d\'onde fait toujours le nombre de barres attendu', () {
      // Trois relevés en entrée, 48 barres en sortie : le rééchantillonnage
      // doit combler, jamais tronquer.
      final name = VoiceNoteMeta.encodeFileName(
        duration: const Duration(seconds: 3),
        samples: const [0.1, 0.5, 0.9],
      );

      expect(
        VoiceNoteMeta.tryParse(name)!.waveform.length,
        VoiceNoteMeta.bars,
      );
    });

    test('un relevé très long est ramené à 48 barres sans perdre les pics',
        () {
      // Un silence, un pic, un silence : le pic doit rester visible.
      final samples = <double>[
        ...List.filled(300, 0.05),
        ...List.filled(100, 1.0),
        ...List.filled(300, 0.05),
      ];

      final parsed = VoiceNoteMeta.tryParse(
        VoiceNoteMeta.encodeFileName(
          duration: const Duration(seconds: 56),
          samples: samples,
        ),
      )!;

      expect(parsed.waveform.length, VoiceNoteMeta.bars);
      expect(parsed.waveform.reduce((a, b) => a > b ? a : b), greaterThan(0.8));
      expect(parsed.waveform.first, lessThan(0.2));
      expect(parsed.waveform.last, lessThan(0.2));
    });

    test('les valeurs restent entre 0 et 1', () {
      final parsed = VoiceNoteMeta.tryParse(
        VoiceNoteMeta.encodeFileName(
          duration: const Duration(seconds: 5),
          // Volontairement hors bornes : le codec ne doit jamais produire
          // un caractère hors alphabet, même nourri de valeurs aberrantes.
          samples: const [-3.0, 0.5, 12.0, double.nan],
        ),
      );

      expect(parsed, isNotNull);
      for (final v in parsed!.waveform) {
        expect(v, inInclusiveRange(0.0, 1.0));
      }
    });

    test('un nom de fichier reste raisonnablement court', () {
      final name = VoiceNoteMeta.encodeFileName(
        duration: const Duration(minutes: 9, seconds: 59),
        samples: List.filled(5000, 0.7),
      );
      // Il voyage dans chaque paquet : au-delà de 80 caractères il
      // pèserait pour rien sur une liaison Bluetooth déjà lente.
      expect(name.length, lessThan(80));
    });
  });

  group('VoiceNoteMeta — robustesse', () {
    test('un fichier ordinaire n\'est pas pris pour un vocal', () {
      expect(VoiceNoteMeta.tryParse('rapport.pdf'), isNull);
      expect(VoiceNoteMeta.tryParse('musique.m4a'), isNull);
      expect(VoiceNoteMeta.tryParse(null), isNull);
      expect(VoiceNoteMeta.isVoiceNote('musique.m4a'), isFalse);
    });

    test('un vocal d\'une ancienne version reste reconnu comme vocal', () {
      // `voix.m4a` était le nom fixe utilisé avant l'ajout des
      // métadonnées : il doit continuer à s'afficher comme un vocal,
      // simplement sans durée ni forme d'onde.
      expect(VoiceNoteMeta.isVoiceNote('voix.m4a'), isTrue);
      expect(VoiceNoteMeta.tryParse('voix.m4a'), isNull);
    });

    test('un nom abîmé ne fait pas planter le décodage', () {
      expect(VoiceNoteMeta.tryParse('voix~~.m4a'), isNull);
      expect(VoiceNoteMeta.tryParse('voix~zzzz.m4a'), isNull);
      expect(VoiceNoteMeta.tryParse('voix~3f~ab!cd.m4a'), isNull);
      expect(VoiceNoteMeta.tryParse('voix~'), isNull);
    });

    test('l\'aperçu affiche un libellé lisible, jamais le nom brut', () {
      final name = VoiceNoteMeta.encodeFileName(
        duration: const Duration(seconds: 75),
        samples: const [0.4],
      );

      final label = VoiceNoteMeta.describeAttachment(name);

      expect(label, contains('1:15'));
      expect(label, isNot(contains('~')));
      expect(VoiceNoteMeta.describeAttachment('rapport.pdf'), 'rapport.pdf');
    });
  });

  group('VoiceNoteMeta.normalizeDb — le bug de la forme d\'onde plate', () {
    test('le silence donne zéro, la saturation donne un', () {
      expect(VoiceNoteMeta.normalizeDb(-160), 0.0);
      expect(VoiceNoteMeta.normalizeDb(0), closeTo(1.0, 0.001));
    });

    test('une voix normale produit une barre bien visible', () {
      // C'est le cœur du bug corrigé : le micro renvoie des décibels
      // NÉGATIFS, et l'ancien `clamp(0, 1)` les écrasait tous à zéro.
      // Une conversation se situe autour de −20 dBFS.
      final v = VoiceNoteMeta.normalizeDb(-20);
      expect(v, greaterThan(0.4));
      expect(v, lessThan(1.0));
    });

    test('la conversion est croissante', () {
      expect(VoiceNoteMeta.normalizeDb(-40),
          lessThan(VoiceNoteMeta.normalizeDb(-20)));
      expect(VoiceNoteMeta.normalizeDb(-20),
          lessThan(VoiceNoteMeta.normalizeDb(-5)));
    });

    test('une valeur non finie ne casse rien', () {
      expect(VoiceNoteMeta.normalizeDb(double.nan), 0.0);
      expect(VoiceNoteMeta.normalizeDb(double.negativeInfinity), 0.0);
    });
  });
}
