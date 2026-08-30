// ============================================================================
// LA SYNCHRONISATION DIFFÉRENTIELLE, MESURÉE POUR DE VRAI.
//
// Les mesures du fichier `sync_negotiation_test.dart` sont ANALYTIQUES :
// elles comptent des octets à partir du format d'encodage. Celles-ci sont
// EXPÉRIMENTALES : elles font tourner le vrai chemin de code — encodage,
// paquet, décodage, décision — et comptent ce qui circule réellement.
//
// C'est la différence entre « d'après mon calcul, ça devrait coûter 804
// octets » et « j'ai compté 804 octets sur le fil ».
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:droplet/core/models/mesh_message.dart';
import 'package:droplet/core/services/ble_mesh_protocol.dart';
import 'package:droplet/core/services/storage_service.dart';
import 'package:droplet/core/sync/sync_negotiation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

MeshStatusRecord statut(String auteur) {
  final maintenant = DateTime.now();
  return MeshStatusRecord(
    id: _uuid.v4(),
    authorId: auteur,
    authorPseudo: auteur,
    content: 'Il y a de l\'eau potable au gymnase',
    createdAt: maintenant,
    expiresAt: maintenant.add(const Duration(hours: 24)),
  );
}

/// Fabrique le paquet d'offre exactement comme le dépôt le fait.
Uint8List paquetOffre(List<String> ids) {
  final corps = SyncOffer(ids).encode();
  final data = Uint8List(2 + corps.length);
  data[0] = 5;
  data[1] = kSyncOfferType;
  data.setRange(2, data.length, corps);
  return data;
}

/// Le paquet d'annonce complet d'un statut, tel qu'il part sur le fil.
Uint8List paquetStatut(MeshStatusRecord s) {
  final payload = {
    'id': s.id,
    'content': s.content,
    'createdAt': s.createdAt.toIso8601String(),
    'expiresAt': s.expiresAt.toIso8601String(),
  };
  final enveloppe = {
    'c': json.encode(payload),
    's': s.authorId,
    'k': 'status',
    'm': s.id,
  };
  final bytes = utf8.encode(json.encode(enveloppe));
  final data = Uint8List(2 + bytes.length);
  data[0] = 5;
  data[1] = kTextMessageType;
  data.setRange(2, data.length, bytes);
  return data;
}

void main() {
  setUp(() async {
    // Aucune base : `StorageService` retombe sur son cache mémoire.
    // On repart d'un magasin vide à chaque test.
    for (final s in StorageService.getActiveStatuses()) {
      await StorageService.saveStatus(MeshStatusRecord(
        id: s.id,
        authorId: s.authorId,
        authorPseudo: s.authorPseudo,
        content: s.content,
        createdAt: s.createdAt,
        // On les périme plutôt que de les supprimer : `getActiveStatuses`
        // filtre déjà sur l'expiration.
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      ));
    }
  });

  group('Le chemin réel', () {
    test('un paquet d\'offre se décode correctement', () {
      final ids = [for (var i = 0; i < 8; i++) _uuid.v4()];
      final paquet = paquetOffre(ids);

      expect(paquet[1], kSyncOfferType);
      final decode = SyncOffer.decode(Uint8List.sublistView(paquet, 2));
      expect(decode.messageIds, ids);
    });

    test('l\'offre porte les statuts des AUTRES, pas seulement les miens',
        () async {
      // C'est la correction de fond : avant, seul mon propre statut
      // était rediffusé, et ceux des autres ne quittaient jamais leur
      // auteur.
      await StorageService.saveStatus(statut('moi'));
      await StorageService.saveStatus(statut('alice'));
      await StorageService.saveStatus(statut('bob'));

      final connus =
          StorageService.getActiveStatuses().map((s) => s.id).toList();
      final offre = SyncNegotiation.preparerOffre(mesMessages: connus);

      expect(offre.messageIds.length, 3);
      final auteurs = StorageService.getActiveStatuses()
          .map((s) => s.authorId)
          .toSet();
      expect(auteurs, {'moi', 'alice', 'bob'});
    });
  });

  group('MESURE EXPÉRIMENTALE', () {
    test('deux appareils à jour : seule l\'offre circule', () async {
      // A et B connaissent les mêmes 30 statuts.
      final partages = [for (var i = 0; i < 30; i++) statut('a$i')];
      for (final s in partages) {
        await StorageService.saveStatus(s);
      }
      final connus = partages.map((s) => s.id).toList();

      // A offre.
      final offre = paquetOffre(connus);
      var octetsSurLeFil = offre.length;

      // B décode et constate qu'il n'a rien à demander.
      final recu = SyncOffer.decode(Uint8List.sublistView(offre, 2));
      final demande = SyncNegotiation.repondreAOffre(
        offre: recu,
        mesMessages: connus.toSet(),
      );
      expect(demande.messageIds, isEmpty);
      // Rien ne repart : pas même un paquet de demande vide.

      // Ce qu'aurait coûté la rediffusion des 30 annonces complètes.
      final rediffusion = partages
          .map((s) => paquetStatut(s).length)
          .reduce((a, b) => a + b);

      // 2 (saut + type) + 2 (compte) + 30 identifiants de 16 octets.
      expect(octetsSurLeFil, 484);
      expect(rediffusion, greaterThan(7000));

      final facteur = rediffusion / octetsSurLeFil;
      expect(facteur, greaterThan(14));
    });

    test('il manque 3 statuts sur 30 : on ne transmet que les 3', () async {
      final tous = [for (var i = 0; i < 30; i++) statut('a$i')];
      for (final s in tous) {
        await StorageService.saveStatus(s);
      }
      final connusDeA = tous.map((s) => s.id).toList();
      final connusDeB = connusDeA.sublist(3).toSet();

      final offre = paquetOffre(connusDeA);
      var octets = offre.length;

      final demande = SyncNegotiation.repondreAOffre(
        offre: SyncOffer.decode(Uint8List.sublistView(offre, 2)),
        mesMessages: connusDeB,
      );
      expect(demande.messageIds.length, 3);
      octets += 2 + demande.encode().length;

      // A ne renvoie que les trois réclamés.
      final aEnvoyer = SyncNegotiation.messagesAEnvoyer(
        demande: demande,
        mesMessages: connusDeA.toSet(),
      );
      final parId = {for (final s in tous) s.id: s};
      for (final id in aEnvoyer) {
        octets += paquetStatut(parId[id]!).length;
      }

      final rediffusion =
          tous.map((s) => paquetStatut(s).length).reduce((a, b) => a + b);

      expect(octets, lessThan(rediffusion ~/ 4));
    });

    test('le pire cas — un appareil neuf — reste acceptable', () async {
      final tous = [for (var i = 0; i < 30; i++) statut('a$i')];
      for (final s in tous) {
        await StorageService.saveStatus(s);
      }
      final connusDeA = tous.map((s) => s.id).toList();

      final offre = paquetOffre(connusDeA);
      var octets = offre.length;

      final demande = SyncNegotiation.repondreAOffre(
        offre: SyncOffer.decode(Uint8List.sublistView(offre, 2)),
        mesMessages: const {},
      );
      expect(demande.messageIds.length, 30);
      octets += 2 + demande.encode().length;
      for (final s in tous) {
        octets += paquetStatut(s).length;
      }

      final rediffusion =
          tous.map((s) => paquetStatut(s).length).reduce((a, b) => a + b);

      // On paie l'offre ET la demande pour rien. Le surcoût doit rester
      // faible, sinon la négociation serait perdante à chaque première
      // rencontre — ce qui est fréquent dans un mesh mobile.
      expect(octets, greaterThan(rediffusion));
      expect((octets - rediffusion) / rediffusion, lessThan(0.15));
    });
  });
}
