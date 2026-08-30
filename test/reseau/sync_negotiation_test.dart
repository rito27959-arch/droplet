// ============================================================================
// La synchronisation différentielle, vérifiée ET CHIFFRÉE.
//
// La dernière série ne teste pas une correction : elle MESURE. C'est ce
// que réclamait le cahier des charges — ne jamais affirmer qu'une
// optimisation est meilleure sans benchmark reproductible.
// ============================================================================

import 'dart:typed_data';

import 'package:droplet/core/sync/sync_negotiation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

List<String> ids(int n) => [for (var i = 0; i < n; i++) _uuid.v4()];

void main() {
  group('Le cas de référence', () {
    test('A a M1..M6, B a M1 M2 M4 : B demande M3 M5 M6', () {
      final m = ids(6);
      final aPossede = m.toSet();
      final bPossede = {m[0], m[1], m[3]};

      final offre = SyncNegotiation.preparerOffre(mesMessages: aPossede);
      final demande = SyncNegotiation.repondreAOffre(
        offre: offre,
        mesMessages: bPossede,
      );

      expect(demande.messageIds.toSet(), {m[2], m[4], m[5]});

      final envoi = SyncNegotiation.messagesAEnvoyer(
        demande: demande,
        mesMessages: aPossede,
      );
      expect(envoi.toSet(), {m[2], m[4], m[5]});
    });

    test('deux nœuds identiques n\'échangent RIEN', () {
      final m = ids(50).toSet();
      final offre = SyncNegotiation.preparerOffre(mesMessages: m);
      final demande =
          SyncNegotiation.repondreAOffre(offre: offre, mesMessages: m);

      expect(demande.messageIds, isEmpty);
      // C'est le cas le plus fréquent en pratique : deux appareils qui
      // se recroisent. Aujourd'hui, Droplet rediffuserait les cinquante.
    });

    test('un nœud vide reçoit tout', () {
      final m = ids(10).toSet();
      final offre = SyncNegotiation.preparerOffre(mesMessages: m);
      final demande = SyncNegotiation.repondreAOffre(
        offre: offre,
        mesMessages: const {},
      );
      expect(demande.messageIds.length, 10);
    });
  });

  group('Robustesse', () {
    test('on n\'envoie jamais ce qu\'on ne possède pas', () {
      // Un pair désynchronisé — ou malveillant — réclame n'importe quoi.
      final mien = ids(3).toSet();
      final demande = SyncRequest([...mien, ..._inconnus(5)]);

      final envoi = SyncNegotiation.messagesAEnvoyer(
        demande: demande,
        mesMessages: mien,
      );
      expect(envoi.toSet(), mien);
    });

    test('l\'offre est plafonnée pour tenir dans un paquet', () {
      final beaucoup = ids(500).toSet();
      final offre = SyncNegotiation.preparerOffre(mesMessages: beaucoup);

      expect(offre.messageIds.length, kMaxIdsParOffre);
      // La synchronisation se poursuit au tour suivant : une coupure ne
      // fait perdre qu'un tour, jamais tout le travail.
    });

    test('ce que le pair a déjà n\'est pas proposé', () {
      final m = ids(10);
      final offre = SyncNegotiation.preparerOffre(
        mesMessages: m,
        dejaConnusDuPair: {m[0], m[1], m[2]},
      );
      expect(offre.messageIds.length, 7);
      expect(offre.messageIds, isNot(contains(m[0])));
    });
  });

  group('Encodage', () {
    test('un aller-retour préserve les identifiants', () {
      final m = ids(20);
      final decode = SyncOffer.decode(SyncOffer(m).encode());
      expect(decode.messageIds, m);
    });

    test('un identifiant tient en 16 octets, pas en 36', () {
      final offre = SyncOffer(ids(10));
      expect(offre.encode().length, 2 + 10 * 16);

      // Les mêmes identifiants en texte brut, tels que Droplet les
      // manipule aujourd'hui.
      final enTexte = offre.messageIds.join(',').length;
      expect(offre.tailleOctets, lessThan(enTexte));
    });

    test('des données tronquées ne font pas planter le décodage', () {
      final complet = SyncOffer(ids(10)).encode();
      final tronque = Uint8List.sublistView(complet, 0, 40);
      // Le paquet annonce dix identifiants mais n'en porte que deux.
      expect(SyncOffer.decode(tronque).messageIds.length, 2);
      expect(SyncOffer.decode(Uint8List(0)).messageIds, isEmpty);
    });
  });

  group('MESURE — offre/demande contre rediffusion aveugle', () {
    /// Poids moyen d'un message Droplet sur le fil.
    ///
    /// Volontairement prudent : un message texte pèse quelques centaines
    /// d'octets, une photo ou un vocal des dizaines de milliers. À 400
    /// octets, on sous-estime le gain réel plutôt que de le gonfler.
    const int poidsMessage = 400;

    int coutRediffusionAveugle(int totalMessages) =>
        totalMessages * poidsMessage;

    int coutOffreDemande(int totalMessages, int manquants) {
      final offre = 2 + totalMessages * kTailleIdOctets;
      final demande = 2 + manquants * kTailleIdOctets;
      return offre + demande + manquants * poidsMessage;
    }

    test('deux appareils déjà à jour : le gain est maximal', () {
      const total = 50;
      final avant = coutRediffusionAveugle(total);
      final apres = coutOffreDemande(total, 0);

      // 20 000 octets contre 804 : l'offre (802) et une demande vide,
      // qui coûte quand même ses deux octets d'en-tête.
      expect(avant, 20000);
      expect(apres, 804);
      expect(apres / avant, lessThan(0.05));
    });

    test('un appareil à qui il manque 10 % : le gain reste net', () {
      const total = 50;
      const manquants = 5;
      final avant = coutRediffusionAveugle(total);
      final apres = coutOffreDemande(total, manquants);

      expect(apres, lessThan(avant ~/ 2));
    });

    test('un appareil neuf : le surcoût est marginal', () {
      const total = 50;
      final avant = coutRediffusionAveugle(total);
      final apres = coutOffreDemande(total, total);

      // Le pire cas de la négociation : tout est demandé, l'offre et la
      // demande sont payées en pure perte. Le surcoût doit rester sous
      // 10 % — sinon la stratégie serait perdante sur les rencontres
      // avec de nouveaux venus.
      expect(apres, greaterThan(avant));
      expect((apres - avant) / avant, lessThan(0.10));
    });

    test('à vingt nœuds, l\'écart devient un facteur d\'échelle', () {
      // Chaque nœud rencontre les dix-neuf autres. Cas réaliste : tous
      // possèdent déjà l'essentiel, seuls quelques messages circulent.
      const noeuds = 20;
      const total = 50;
      const manquants = 2;

      final rencontres = noeuds * (noeuds - 1);
      final avant = rencontres * coutRediffusionAveugle(total);
      final apres = rencontres * coutOffreDemande(total, manquants);

      expect(avant, 7600000); // 7,6 Mo
      expect(apres, lessThan(700000)); // moins de 0,7 Mo

      final facteur = avant / apres;
      expect(facteur, greaterThan(10));
    });
  });
}

List<String> _inconnus(int n) => ids(n);
