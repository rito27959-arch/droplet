// ============================================================================
// UN BANC À TROIS APPAREILS
// ----------------------------------------------------------------------------
// A ── B ── C     (A et C ne se voient PAS ; B est entre les deux)
//
// C'est la topologie qui justifie l'existence de Droplet, et celle qu'on
// ne peut pas éprouver avec un seul téléphone. On la simule ici : trois
// nœuds, des liens explicites, et un facteur qui ne délivre un paquet
// qu'entre voisins déclarés.
//
// ── ⚠️ CE QUE CE BANC PROUVE, ET CE QU'IL NE PROUVE PAS ───────────────
//
// Il prouve la LOGIQUE : qu'une annonce de routes se propage, qu'un
// message adressé à un inconnu trouve son relais, que le trajet est signé
// à chaque passage, que le compteur de sauts s'épuise, qu'un fichier
// suit le même chemin qu'un texte.
//
// Il ne prouve RIEN sur la radio : ni qu'une trame Bluetooth de 19 octets
// utiles achemine ces paquets, ni qu'une annonce survit à une liaison
// médiocre, ni ce que coûte le tout en batterie. Ces questions-là se
// tranchent avec trois vrais appareils, et ce banc ne les remplace pas —
// il évite seulement d'y aller avec des fautes de raisonnement.
// ============================================================================

import 'package:droplet/core/protocol/droplet_mesh_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un appareil du banc.
class _Noeud {
  _Noeud(this.id) : protocole = DropletMeshProtocol(myId: id);

  final String id;
  final DropletMeshProtocol protocole;

  /// Les voisins À PORTÉE RADIO — pas les destinations joignables.
  final Set<String> voisins = {};

  /// Ce que cet appareil a reçu POUR LUI.
  final List<Map<String, dynamic>> boiteAuxLettres = [];

  /// Les identifiants déjà vus, pour ne pas relayer deux fois.
  final Set<String> vus = {};

  String get court => id.substring(0, 8);
}

/// Le réseau : il ne délivre un paquet qu'entre voisins déclarés.
class _Banc {
  final Map<String, _Noeud> noeuds = {};

  /// Le compteur de sauts initial, comme dans `MeshRepository`.
  static const int ttl = 5;

  _Noeud ajouter(String id) => noeuds[id] = _Noeud(id);

  void relier(String a, String b) {
    noeuds[a]!.voisins.add(b);
    noeuds[b]!.voisins.add(a);
  }

  /// Chaque appareil annonce ce qu'il sait joindre ; ses voisins
  /// apprennent. Un tour = une vague d'annonces.
  void tourDAnnonces() {
    // On fige d'abord ce que chacun annonce : sans cela, un nœud traité
    // en premier propagerait dans le même tour ce qu'il vient
    // d'apprendre, et le banc converserait plus vite que la réalité.
    final annonces = <String, Map<String, int>>{};
    for (final n in noeuds.values) {
      final dests = <String, int>{};
      for (final v in n.voisins) {
        dests[v] = 1;
      }
      for (final r in n.protocole.snapshotRoutes()) {
        final actuel = dests[r.destination];
        if (actuel == null || r.hopCount < actuel) {
          dests[r.destination] = r.hopCount;
        }
      }
      dests.remove(n.id);
      annonces[n.id] = dests;
    }

    for (final emetteur in noeuds.values) {
      for (final nomVoisin in emetteur.voisins) {
        final voisin = noeuds[nomVoisin]!;
        annonces[emetteur.id]!.forEach((dest, sauts) {
          if (dest == voisin.id || dest == emetteur.id) return;
          if (sauts + 1 >= ttl) return;
          voisin.protocole.updateRoutingTable(
            dest,
            emetteur.id,
            sauts + 1,
            emetteur.protocole.computeLinkMetric(emetteur.id) * (sauts + 1),
          );
        });
      }
      // Un voisin direct reste connu en direct.
      for (final nomVoisin in emetteur.voisins) {
        emetteur.protocole.updateRoutingTable(nomVoisin, nomVoisin, 1, 10);
      }
    }
  }

  /// Envoie une enveloppe de [de] vers [vers], en la faisant relayer.
  ///
  /// Reproduit la logique de `_relayNow` : décrémentation du compteur,
  /// signature du passage, choix du prochain saut par la table.
  void envoyer(String de, String vers, Map<String, dynamic> enveloppe) {
    final depart = noeuds[de]!;
    _acheminer(depart, {
      ...enveloppe,
      's': de,
      't': vers,
      'm': enveloppe['m'] ?? 'msg-1',
    }, ttl);
  }

  void _acheminer(_Noeud courant, Map<String, dynamic> env, int sauts) {
    if (sauts <= 0) return;
    final cible = env['t'] as String;

    // Le prochain saut : direct si voisin, sinon par la table.
    String? prochain;
    if (courant.voisins.contains(cible)) {
      prochain = cible;
    } else {
      final route = courant.protocole.getRoute(cible);
      if (route != null && courant.voisins.contains(route.nextHop)) {
        prochain = route.nextHop;
      }
    }
    if (prochain == null) return; // aucune route : le message reste là

    final suivant = noeuds[prochain]!;
    final id = env['m'] as String;
    if (!suivant.vus.add(id)) return; // déjà passé par là

    if (suivant.id == cible) {
      suivant.boiteAuxLettres.add(Map<String, dynamic>.from(env));
      return;
    }

    // Relais : il signe son passage, puis fait suivre.
    final chemin = (env['p'] as List?)?.cast<String>() ?? <String>[];
    final signee = {
      ...env,
      if (!chemin.contains(suivant.court)) 'p': [...chemin, suivant.court],
    };
    _acheminer(suivant, signee, sauts - 1);
  }
}

void main() {
  late _Banc banc;

  setUp(() {
    banc = _Banc()
      ..ajouter('aaaaaaaa-appareil-A')
      ..ajouter('bbbbbbbb-appareil-B')
      ..ajouter('cccccccc-appareil-C');
    banc.relier('aaaaaaaa-appareil-A', 'bbbbbbbb-appareil-B');
    banc.relier('bbbbbbbb-appareil-B', 'cccccccc-appareil-C');
  });

  group('Découverte des routes', () {
    test('A n\'a aucune route vers C avant les annonces', () {
      expect(
        banc.noeuds['aaaaaaaa-appareil-A']!.protocole
            .getRoute('cccccccc-appareil-C'),
        isNull,
        reason: 'A et C ne se voient pas : sans annonce, C est inconnu',
      );
    });

    test('après un tour, A sait joindre C via B', () {
      banc.tourDAnnonces();

      final route = banc.noeuds['aaaaaaaa-appareil-A']!.protocole
          .getRoute('cccccccc-appareil-C');
      expect(route, isNotNull);
      expect(route!.nextHop, 'bbbbbbbb-appareil-B');
      expect(route.hopCount, 2);
    });
  });

  group('Acheminement', () {
    setUp(() => banc.tourDAnnonces());

    test('un message texte de A arrive à C', () {
      banc.envoyer('aaaaaaaa-appareil-A', 'cccccccc-appareil-C',
          {'c': 'Bonjour C', 'm': 'txt-1'});

      final recu = banc.noeuds['cccccccc-appareil-C']!.boiteAuxLettres;
      expect(recu, hasLength(1));
      expect(recu.first['c'], 'Bonjour C');
    });

    test('le trajet porte le relais traversé', () {
      banc.envoyer('aaaaaaaa-appareil-A', 'cccccccc-appareil-C',
          {'c': 'Bonjour', 'm': 'txt-2'});

      final chemin =
          (banc.noeuds['cccccccc-appareil-C']!.boiteAuxLettres.first['p']
                  as List)
              .cast<String>();
      // B a signé ; ni A ni C ne se comptent eux-mêmes.
      expect(chemin, ['bbbbbbbb']);
    });

    test('un fichier suit le même chemin qu\'un texte', () {
      // Un transfert de fichier n'est qu'une enveloppe de plus : s'il
      // empruntait une autre voie, la moitié des messages arriverait et
      // l'autre non.
      banc.envoyer('aaaaaaaa-appareil-A', 'cccccccc-appareil-C', {
        'c': 'photo.jpg',
        'm': 'fic-1',
        'f': {'nom': 'photo.jpg', 'taille': 204800},
      });

      final recu = banc.noeuds['cccccccc-appareil-C']!.boiteAuxLettres.first;
      expect(recu['f'], isNotNull);
      expect((recu['p'] as List).cast<String>(), ['bbbbbbbb']);
    });

    test('B ne garde pas un message qui ne lui est pas destiné', () {
      banc.envoyer('aaaaaaaa-appareil-A', 'cccccccc-appareil-C',
          {'c': 'privé', 'm': 'txt-3'});

      expect(banc.noeuds['bbbbbbbb-appareil-B']!.boiteAuxLettres, isEmpty,
          reason: 'un relais fait suivre, il ne lit pas');
    });

    test('le même message n\'est pas relayé deux fois', () {
      banc.envoyer('aaaaaaaa-appareil-A', 'cccccccc-appareil-C',
          {'c': 'un', 'm': 'txt-4'});
      banc.envoyer('aaaaaaaa-appareil-A', 'cccccccc-appareil-C',
          {'c': 'un', 'm': 'txt-4'});

      expect(banc.noeuds['cccccccc-appareil-C']!.boiteAuxLettres, hasLength(1),
          reason: 'la déduplication par identifiant doit tenir');
    });
  });

  group('Chaîne plus longue', () {
    test('A → B → C → D : le trajet porte les deux relais', () {
      banc.ajouter('dddddddd-appareil-D');
      banc.relier('cccccccc-appareil-C', 'dddddddd-appareil-D');
      // Deux tours : l'information doit traverser deux fois pour que A
      // apprenne D. C'est le rythme réel d'un vecteur de distance.
      banc.tourDAnnonces();
      banc.tourDAnnonces();

      banc.envoyer('aaaaaaaa-appareil-A', 'dddddddd-appareil-D',
          {'c': 'salut D', 'm': 'txt-5'});

      final boite = banc.noeuds['dddddddd-appareil-D']!.boiteAuxLettres;
      expect(boite, hasLength(1), reason: 'D doit recevoir via B puis C');
      expect((boite.first['p'] as List).cast<String>(),
          ['bbbbbbbb', 'cccccccc']);
    });
  });
}
