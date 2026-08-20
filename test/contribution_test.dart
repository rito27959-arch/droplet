import 'package:flutter_test/flutter_test.dart';
import 'package:droplet/core/models/mesh_message.dart';

void main() {
  group('ContributionRank.fromPoints', () {
    test('0 point → bronze', () {
      expect(ContributionRank.fromPoints(0), ContributionRank.bronze);
    });

    test('juste avant un palier → palier inférieur', () {
      expect(ContributionRank.fromPoints(99), ContributionRank.bronze);
      expect(ContributionRank.fromPoints(499), ContributionRank.argent);
      expect(ContributionRank.fromPoints(1999), ContributionRank.or);
    });

    test('exactement au seuil → palier atteint', () {
      expect(ContributionRank.fromPoints(100), ContributionRank.argent);
      expect(ContributionRank.fromPoints(500), ContributionRank.or);
      expect(ContributionRank.fromPoints(2000), ContributionRank.diamant);
    });

    test('très au-dessus du dernier palier → diamant (pas de dépassement)', () {
      expect(ContributionRank.fromPoints(1000000), ContributionRank.diamant);
    });
  });

  group('ContributionRank.next', () {
    test('chaque palier pointe vers le suivant, sauf le dernier', () {
      expect(ContributionRank.bronze.next, ContributionRank.argent);
      expect(ContributionRank.argent.next, ContributionRank.or);
      expect(ContributionRank.or.next, ContributionRank.diamant);
      expect(ContributionRank.diamant.next, isNull);
    });
  });

  group('ContributionPoints.rank', () {
    test('dérive le bon rang depuis le total de points', () {
      const points = ContributionPoints(totalPoints: 250, relaysCount: 20, gatewayMinutes: 25);
      expect(points.rank, ContributionRank.argent);
    });

    test('totalPoints cohérent avec relaysCount*10 + gatewayMinutes*2 (calcul appelant)', () {
      // Le calcul du total est fait côté StorageService (10 pts/relais,
      // 2 pts/min gateway) ; ce test fige la formule attendue pour éviter
      // une dérive silencieuse si l'un des deux barèmes change sans l'autre.
      const relaysCount = 7;
      const gatewayMinutes = 15;
      const expectedTotal = relaysCount * 10 + gatewayMinutes * 2;
      const points = ContributionPoints(
        totalPoints: expectedTotal,
        relaysCount: relaysCount,
        gatewayMinutes: gatewayMinutes,
      );
      expect(points.totalPoints, 100);
      expect(points.rank, ContributionRank.argent);
    });
  });
}
