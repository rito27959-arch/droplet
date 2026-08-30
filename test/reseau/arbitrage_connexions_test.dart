// ============================================================================
// LE TEST QUI COMPTE : la règle d'arbitrage est-elle SYMÉTRIQUE ?
//
// C'est là que le réseau devenait instable. L'ancienne règle — « garder
// la plus récente » — semblait raisonnable, mais chacun l'appliquait de
// son côté et désignait la connexion de l'autre. Les deux tombaient.
//
// Une règle d'arbitrage n'est correcte que si les DEUX appareils
// arrivent à la même conclusion. C'est exactement ce qu'on vérifie ici,
// et c'est une propriété qui se teste sans la moindre connexion.
// ============================================================================

import 'package:droplet/core/services/local_wifi_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rejoue une rencontre entre deux appareils et renvoie qui chacun
/// désigne comme vainqueur.
({String selonA, String selonB}) rencontre({
  required String nonceA,
  required String nonceB,
  String idA = 'alice',
  String idB = 'bob',
}) {
  // A raisonne avec SON nonce et celui de B ; B fait l'inverse. C'est
  // toute la difficulté : les deux n'ont pas le même point de vue, et
  // doivent pourtant conclure pareil.
  final aGagne =
      LocalWifiTransport.monNonceLEmporte(nonceA, nonceB, idA, idB);
  final bGagne =
      LocalWifiTransport.monNonceLEmporte(nonceB, nonceA, idB, idA);

  return (
    selonA: aGagne ? idA : idB,
    selonB: bGagne ? idB : idA,
  );
}

void main() {
  group('Symétrie de la règle', () {
    test('les deux appareils désignent le MÊME vainqueur', () {
      final r = rencontre(nonceA: 'ffffffffffffffff', nonceB: '0000000000000001');
      expect(r.selonA, r.selonB);
      expect(r.selonA, 'alice');
    });

    test('symétrie quand c\'est l\'autre qui gagne', () {
      final r = rencontre(nonceA: '0000000000000001', nonceB: 'ffffffffffffffff');
      expect(r.selonA, r.selonB);
      expect(r.selonA, 'bob');
    });

    test('en cas d\'égalité de nonce, l\'identifiant départage', () {
      // Improbable sur huit octets, mais une règle d'arbitrage doit être
      // TOTALE : deux valeurs égales ne doivent jamais laisser les deux
      // appareils sans conclusion, sinon on retombe exactement dans le
      // bug d'origine.
      final r = rencontre(nonceA: 'aaaaaaaaaaaaaaaa', nonceB: 'aaaaaaaaaaaaaaaa');
      expect(r.selonA, r.selonB);
    });

    test('mille rencontres aléatoires, aucun désaccord', () {
      var desaccords = 0;
      for (var i = 0; i < 1000; i++) {
        final r = rencontre(
          nonceA: i.toRadixString(16).padLeft(16, '0'),
          nonceB: (i * 7919 % 65536).toRadixString(16).padLeft(16, '0'),
          idA: 'noeud-$i',
          idB: 'noeud-${i + 1}',
        );
        if (r.selonA != r.selonB) desaccords++;
      }
      expect(desaccords, 0);
    });
  });

  group('L\'ancienne règle, pour mémoire', () {
    test('« garder la plus récente » fait tomber les DEUX connexions', () {
      // On rejoue le raisonnement d'origine pour documenter la panne.
      //
      // Chacun voit arriver la carte de visite de l'autre sur sa
      // connexion ENTRANTE, la juge « plus récente », et ferme donc sa
      // propre sortante.
      const aFerme = 'A→B'; // A ferme sa sortante
      const bFerme = 'B→A'; // B ferme la sienne

      // Il ne reste rien : A gardait B→A, que B vient de fermer ; B
      // gardait A→B, que A vient de fermer.
      final survivantes = <String>{'A→B', 'B→A'}
        ..remove(aFerme)
        ..remove(bFerme);

      expect(survivantes, isEmpty,
          reason: 'la panne : zéro connexion survit à la rencontre');
    });
  });
}
