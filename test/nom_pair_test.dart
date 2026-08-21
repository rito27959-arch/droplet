// ============================================================================
// CE QUE CES TESTS PROTÈGENT
// ----------------------------------------------------------------------------
// QU'AUCUN UTILISATEUR NE VOIE JAMAIS UNE EMPREINTE DE CLÉ PUBLIQUE À LA
// PLACE D'UN NOM.
//
// Le défaut existait vraiment, à plusieurs endroits et sous deux formes
// différentes :
//
//   • le résolveur central terminait par `return … ?? peerId` — soit
//     soixante-quatre caractères hexadécimaux affichés dans le journal
//     d'appels, la liste des pairs et les groupes ;
//   • d'anciennes versions ENREGISTRAIENT l'identifiant comme
//     pseudonyme, si bien qu'une fiche « valide » contenait un faux nom
//     que rien ne détectait.
//
// Le second cas est le plus vicieux : un simple contrôle de nullité le
// laisse passer. C'est pourquoi la règle vit dans un seul fichier, et
// pourquoi ces tests portent sur elle plutôt que sur chaque écran.
// ============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:droplet/core/services/nom_pair.dart';

/// Une empreinte plausible : Droplet utilise de l'hexadécimal.
const String empreinte =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

void main() {
  group('Ce qui est un vrai nom', () {
    test('un pseudonyme ordinaire passe', () {
      expect(pseudoValide('Amina', empreinte), 'Amina');
      expect(pseudoValide('  Michel  ', empreinte), 'Michel',
          reason: 'les espaces autour sont retirés, pas le nom');
    });

    test('le vide et les espaces ne sont pas des noms', () {
      expect(pseudoValide(null, empreinte), isNull);
      expect(pseudoValide('', empreinte), isNull);
      expect(pseudoValide('   ', empreinte), isNull);
    });

    test('L\'IDENTIFIANT N\'EST PAS UN NOM, même enregistré comme tel', () {
      // ⚠️ LE TEST CENTRAL DU FICHIER.
      //
      // D'anciennes fiches portent l'empreinte dans le champ pseudonyme.
      // Un contrôle de nullité les accepterait, et l'écran afficherait
      // soixante-quatre caractères hexadécimaux en guise de nom.
      expect(pseudoValide(empreinte, empreinte), isNull);
      expect(pseudoValide(empreinte.toUpperCase(), empreinte), isNull,
          reason: 'la casse ne doit pas suffire à faire passer un faux nom');
      expect(pseudoValide('  $empreinte  ', empreinte), isNull,
          reason: 'ni les espaces autour');
    });
  });

  group('Le nom affiché', () {
    test('la première proposition valable gagne', () {
      expect(
        nomDuPair(empreinte, [null, '', 'Amina', 'Michel']),
        'Amina',
        reason: 'l\'ordre des propositions est celui de la confiance : '
            'nom vivant, puis fiche, puis message',
      );
    });

    test('sans aucun nom, on abrège au lieu de tout afficher', () {
      final n = nomDuPair(empreinte, [null, empreinte, '']);
      expect(n, 'Pair a1b2c3d4');
      expect(n.length, lessThan(16),
          reason: 'il doit tenir dans une barre de titre');
      expect(n, isNot(contains(empreinte)),
          reason: 'l\'empreinte entière ne doit jamais s\'afficher');
    });

    test('le nom abrégé est STABLE pour un même pair', () {
      // Deux appels manqués du même inconnu doivent porter le même
      // libellé, sinon on ne peut pas savoir qui rappeler.
      expect(nomDuPair(empreinte, const []),
          nomDuPair(empreinte, const []));
    });

    test('deux pairs différents ne portent pas le même nom abrégé', () {
      const autre =
          'ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100';
      expect(nomDuPair(empreinte, const []),
          isNot(nomDuPair(autre, const [])));
    });

    test('un identifiant très court est affiché tel quel', () {
      // Cas limite : rien à abréger. Il ne doit pas planter sur
      // `substring`.
      expect(nomDuPair('abc', const []), 'abc');
      expect(nomDuPair('', const []), '');
    });
  });
}
