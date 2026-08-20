// ============================================================================
// CE QUE CES TESTS PROTÈGENT
// ----------------------------------------------------------------------------
// L'animation de la dernière page d'accueil ne décore pas : elle
// DÉMONTRE quelque chose, et la démonstration tient à un enchaînement
// précis.
//
//   1. on est seul, on ne joint personne ;
//   2. quelques voisins arrivent, on en joint quatre ;
//   3. un second groupe apparaît — et le compteur NE BOUGE PAS, parce
//      qu'il est hors d'atteinte ;
//   4. une seule personne s'installe entre les deux, et le compteur
//      saute de quatre à dix.
//
// C'est l'étape 3 qui fait tout le travail. Sans elle, l'animation
// montre juste des points qui s'allument. Et c'est aussi la plus fragile :
// il suffit d'avancer un peu l'apparition du pont, ou de reculer celle du
// groupe de droite, pour que les deux se chevauchent — le saut
// disparaîtrait alors sans que rien ne casse, ni à la compilation ni à
// l'analyse. Personne ne s'en apercevrait avant de regarder l'écran.
//
// Ces tests figent donc le RÉCIT, pas les valeurs : ils vérifient qu'il
// existe un moment où l'on voit des gens qu'on ne peut pas joindre, et
// que le pont fait bien plus que doubler le nombre de joignables.
// ============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:droplet/features/onboarding/onboarding_animations.dart';

void main() {
  group('Croissance du réseau', () {
    test('chaque point a une heure d\'apparition', () {
      expect(
        MeshGrowthModel.apparitions.length,
        MeshGrowthModel.noeuds.length,
        reason: 'un point sans horaire n\'apparaîtrait jamais',
      );
    });

    test('aucun point ne reste isolé du graphe', () {
      // Un point dessiné que rien ne relie ressemblerait à une erreur
      // d'affichage, pas à quelqu'un hors de portée.
      for (var i = 0; i < MeshGrowthModel.noeuds.length; i++) {
        final relie = MeshGrowthModel.liens.any((l) => l.contains(i));
        expect(relie, isTrue, reason: 'le point $i n\'est relié à rien');
      }
    });

    test('au tout début, on est seul', () {
      // Juste après l'apparition du point de départ, avant le premier
      // voisin.
      expect(MeshGrowthModel.atteignables(0.03), 1);
    });

    test('le premier groupe se forme, sans plus', () {
      final n = MeshGrowthModel.atteignables(0.30);
      expect(n, 4, reason: 'le groupe de gauche compte quatre personnes');
    });

    test('LE MOMENT CLÉ : des gens visibles et hors d\'atteinte', () {
      // Tout le groupe de droite est apparu, le pont n'est pas encore là.
      const avantLePont = 0.66;

      final joignables = MeshGrowthModel.atteignables(avantLePont);
      final presents = [
        for (var i = 0; i < MeshGrowthModel.noeuds.length; i++)
          if (avantLePont >= MeshGrowthModel.apparitions[i]) i,
      ].length;

      expect(joignables, 4,
          reason: 'le groupe de droite ne doit PAS être joignable');
      expect(presents, greaterThan(joignables),
          reason: 'il faut voir des gens qu\'on ne peut pas joindre — '
              'sans ce contraste, l\'animation ne démontre rien');
    });

    test('le pont fait basculer tout le réseau d\'un coup', () {
      const avant = 0.66;
      const apres = 0.76;

      final n1 = MeshGrowthModel.atteignables(avant);
      final n2 = MeshGrowthModel.atteignables(apres);

      expect(n2, 10, reason: 'tout le monde devient joignable');
      // Le saut doit être SPECTACULAIRE, pas progressif : c'est ce qui
      // se remarque à l'écran. Une personne de plus qui en apporte cinq
      // est une démonstration ; une personne de plus qui en apporte une
      // est une addition.
      expect(n2 - n1, greaterThanOrEqualTo(5),
          reason: 'un seul nouvel arrivant doit en rendre au moins cinq '
              'joignables — sinon il n\'y a plus d\'effet de réseau à voir');
    });

    test('un point absent n\'est jamais compté', () {
      // Avant la toute première apparition, il n'y a rien — pas même
      // soi-même.
      expect(MeshGrowthModel.atteignables(0.0), 0);
      expect(MeshGrowthModel.presence(0.0, 5), 0);
    });

    test('tout s\'efface avant que la boucle ne reprenne', () {
      // Sans cette sortie, le redémarrage se lirait comme un bug
      // d'affichage plutôt que comme une reprise.
      expect(MeshGrowthModel.presence(0.999, 0), lessThan(0.05));
    });
  });
}
