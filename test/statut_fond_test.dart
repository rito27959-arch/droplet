// ============================================================================
// CE QUE CES TESTS PROTÈGENT
// ----------------------------------------------------------------------------
// LA COULEUR DE FOND D'UN STATUT DOIT ARRIVER CHEZ LE DESTINATAIRE.
//
// Un statut de texte n'est QUE du texte sur une couleur. Si la couleur
// se perd en route, l'auteur voit son statut turquoise, tout le monde
// en voit un autre — et personne ne s'en aperçoit, parce que chacun
// regarde son propre écran. C'est un défaut invisible depuis
// l'appareil qui publie, donc impossible à trouver en s'essayant
// soi-même.
//
// Le trajet compte quatre étapes, chacune capable de perdre la couleur :
//
//   1. le compositeur la met dans `StatusMedia.backgroundColor` ;
//   2. `sendStatus` n'attache le bloc `media` QUE si le statut n'est
//      pas « purement textuel » — un statut coloré doit donc compter
//      comme non purement textuel, sinon la couleur ne part jamais ;
//   3. `toJson` la sérialise sous la clé `bg` ;
//   4. `fromJson` la relit chez le destinataire.
//
// L'étape 2 est la plus sournoise : elle est correcte aujourd'hui, mais
// une future optimisation de bande passante qui élargirait « purement
// textuel » ferait disparaître toutes les couleurs d'un coup, sans
// erreur ni avertissement.
// ============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:droplet/core/models/status_media.dart';

/// Les couleurs proposées par le compositeur (`status_composer.dart`).
///
/// Recopiées ici volontairement : si quelqu'un en ajoute une là-bas
/// sans la faire passer par ce test, le test ne la couvrira pas — mais
/// il continuera de garantir que le MÉCANISME transporte bien une
/// couleur, ce qui est ce qu'on protège.
const List<int> palette = [
  0xFF14B8C4, 0xFF4FB8F5, 0xFF3B6EF5, 0xFF7FBFA0,
  0xFF3FBF63, 0xFF8A9440, 0xFFD4B315, 0xFFE8A33D,
];

void main() {
  group('Le fond d\'un statut', () {
    test('un statut coloré n\'est PAS « purement textuel »', () {
      // ⚠️ LE TEST LE PLUS IMPORTANT DU FICHIER.
      //
      // `sendStatus` s'appuie sur `isPlainText` pour décider s'il joint
      // le bloc `media` à l'annonce. Si un statut coloré était considéré
      // comme purement textuel, la couleur ne quitterait jamais
      // l'appareil — et rien ne le signalerait.
      const colore = StatusMedia(backgroundColor: 0xFF3B6EF5);
      expect(colore.isPlainText, isFalse,
          reason: 'sans cela, `sendStatus` n\'attache pas le bloc media '
              'et la couleur ne part pas');

      // Et l'inverse : un texte sans rien reste léger.
      expect(const StatusMedia().isPlainText, isTrue,
          reason: 'un statut sans couleur ni média ne doit pas alourdir '
              'l\'annonce d\'un objet vide');
    });

    test('la couleur survit à l\'aller-retour JSON', () {
      for (final couleur in palette) {
        final envoye = StatusMedia(backgroundColor: couleur);

        // Exactement ce que fait `sendStatus` : encodage JSON réel, pas
        // une simple copie d'objet. C'est l'encodage qui perd les
        // choses, pas la structure.
        final surLeFil = jsonEncode(envoye.toJson());
        final recu = StatusMedia.fromJson(
          jsonDecode(surLeFil) as Map<String, dynamic>,
        );

        expect(recu.backgroundColor, couleur,
            reason: 'couleur 0x${couleur.toRadixString(16).toUpperCase()} '
                'altérée en route');
      }
    });

    test('le canal alpha n\'est pas rogné', () {
      // ⚠️ Une couleur ARGB opaque dépasse 2³¹ (0xFF14B8C4 vaut
      // 4 279 979 204). Sur une plateforme où les entiers JSON
      // passeraient par un flottant, les bits de poids fort sauteraient
      // et le fond deviendrait transparent — donc noir à l'écran.
      const opaque = 0xFF14B8C4;
      expect(opaque, greaterThan(2147483647),
          reason: 'si cette valeur tenait sur 32 bits signés, le test '
              'ne prouverait rien');

      final recu = StatusMedia.fromJson(
        jsonDecode(jsonEncode(const StatusMedia(backgroundColor: opaque)
            .toJson())) as Map<String, dynamic>,
      );
      expect(recu.backgroundColor, opaque);
      expect((recu.backgroundColor! >> 24) & 0xFF, 0xFF,
          reason: 'le statut doit rester opaque');
    });

    test('une couleur avec un média coexiste sans se perdre', () {
      // Le cas d'un vocal sur fond coloré : les deux doivent voyager.
      const envoye = StatusMedia(
        kind: StatusMediaKind.voice,
        fileId: 'abc123',
        durationMs: 4200,
        backgroundColor: 0xFFD4B315,
      );
      final recu = StatusMedia.fromJson(
        jsonDecode(jsonEncode(envoye.toJson())) as Map<String, dynamic>,
      );
      expect(recu.backgroundColor, 0xFFD4B315);
      expect(recu.kind, StatusMediaKind.voice);
      expect(recu.fileId, 'abc123');
      expect(recu.durationMs, 4200);
    });

    test('une annonce sans bloc media ne casse rien', () {
      // Ce que reçoit un appareil d'une version antérieure, ou un
      // statut purement textuel : aucune clé `bg`.
      final recu = StatusMedia.fromJson(
        jsonDecode('{}') as Map<String, dynamic>,
      );
      expect(recu.backgroundColor, isNull);
      expect(recu.kind, StatusMediaKind.none);
      expect(recu.isPlainText, isTrue);
    });
  });
}
