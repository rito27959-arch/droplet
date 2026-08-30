// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LES RÉPONSES TAPÉES PENDANT QUE L'APPLICATION ÉTAIT FERMÉE.
//
// ── ⚠️ POURQUOI ELLES NE PEUVENT PAS PARTIR TOUT DE SUITE ─────────────
//
// Quand Android réveille l'application pour traiter un appui sur
// « Répondre » alors que son processus est mort, il ne la démarre pas :
// il lance un ISOLATE séparé, minuscule, qui ne contient que la
// fonction désignée. Ni maillage, ni providers, ni base ouverte, ni
// radio Bluetooth allumée. Rien de ce qu'il faudrait pour envoyer.
//
// Écrire le message directement en base depuis cet isolate serait
// possible, mais dangereux : deux isolates écrivant dans le même
// fichier SQLite, sans coordination, est la recette classique de la
// base corrompue — et ici la base contient les conversations, qu'aucun
// serveur ne peut restituer.
//
// On écrit donc dans un simple fichier JSON, que le processus principal
// relit à son démarrage. Deux isolates qui n'écrivent jamais au même
// endroit ne peuvent pas se marcher dessus.
//
// ── ⚠️ ET POURQUOI ON NE PROMET RIEN À L'UTILISATEUR ──────────────────
//
// La notification disparaît dès l'appui : Android l'exige pour que le
// clavier se referme. On ne peut donc pas afficher « en attente » à cet
// endroit — et c'est aussi bien, parce qu'on ne saurait pas quoi
// promettre : sans pair à portée, le message attendra de toute façon.
//
// La vérité s'affichera dans le fil de discussion, à la prochaine
// ouverture, avec le vrai état du message.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Une réponse écrite hors de l'application, en attente d'envoi.
class ReponseDifferee {
  const ReponseDifferee({
    required this.route,
    required this.texte,
    required this.quand,
  });

  /// La route de la conversation (`/chat/<id>` ou `/group/<id>`).
  final String route;
  final String texte;
  final DateTime quand;

  Map<String, dynamic> toJson() => {
        'r': route,
        't': texte,
        'q': quand.toIso8601String(),
      };

  static ReponseDifferee? fromJson(Map<String, dynamic> j) {
    final r = j['r'] as String?;
    final t = j['t'] as String?;
    if (r == null || t == null || r.isEmpty || t.isEmpty) return null;
    return ReponseDifferee(
      route: r,
      texte: t,
      quand: DateTime.tryParse(j['q'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class ReponsesDifferees {
  ReponsesDifferees._();

  /// Ce que le processus principal fait d'une réponse retrouvée.
  ///
  /// Branché depuis `main.dart`. Tant qu'il vaut `null`, [rejouer] ne
  /// touche à rien — les réponses restent sur le disque plutôt que
  /// d'être perdues.
  static Future<void> Function(ReponseDifferee)? onRejouer;

  /// ⚠️ AU-DELÀ, ON REFUSE D'ENREGISTRER.
  ///
  /// Le fichier est écrit par un isolate qui ne sait pas si le
  /// principal le relira un jour. Sans borne, une notification restée
  /// affichée des semaines pourrait accumuler des centaines d'entrées —
  /// et le jour où l'application redémarre, elle enverrait tout d'un
  /// coup, ce que personne n'a demandé.
  static const int _maximum = 50;

  static Future<File> _fichier() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/reponses_differees.json');
  }

  /// Met une réponse de côté.
  static Future<void> ajouter(String route, String texte) async {
    try {
      final f = await _fichier();
      final liste = await _lire(f);
      if (liste.length >= _maximum) {
        debugPrint('[Réponses] file pleine, réponse ignorée');
        return;
      }
      liste.add(ReponseDifferee(
        route: route,
        texte: texte,
        quand: DateTime.now(),
      ));
      await f.writeAsString(
        jsonEncode(liste.map((e) => e.toJson()).toList()),
        flush: true,
      );
      debugPrint('[Réponses] mise de côté pour $route');
    } catch (e) {
      debugPrint('[Réponses] écriture impossible: $e');
    }
  }

  /// Renvoie tout ce qui attendait, puis vide la file.
  ///
  /// ⚠️ LE FICHIER N'EST EFFACÉ QU'APRÈS TRAITEMENT RÉUSSI. Le vider
  /// d'abord ferait perdre les messages si l'envoi échouait — et un
  /// message écrit par quelqu'un qui disparaît sans laisser de trace est
  /// exactement ce que cette application promet de ne jamais faire.
  static Future<void> rejouer() async {
    final f = await _fichier();
    if (!await f.exists()) return;

    final rappel = onRejouer;
    if (rappel == null) return;

    final liste = await _lire(f);
    if (liste.isEmpty) {
      await _effacer(f);
      return;
    }

    // Dans l'ordre où elles ont été écrites : deux réponses à la même
    // conversation doivent arriver comme elles ont été tapées.
    liste.sort((a, b) => a.quand.compareTo(b.quand));

    var traitees = 0;
    for (final r in liste) {
      try {
        await rappel(r);
        traitees++;
      } catch (e) {
        debugPrint('[Réponses] échec sur ${r.route}: $e');
        break;
      }
    }

    if (traitees == liste.length) {
      await _effacer(f);
    } else {
      // On ne garde que ce qui n'est pas passé.
      final reste = liste.sublist(traitees);
      await f.writeAsString(
        jsonEncode(reste.map((e) => e.toJson()).toList()),
        flush: true,
      );
    }
    debugPrint('[Réponses] $traitees rejouée(s) sur ${liste.length}');
  }

  static Future<List<ReponseDifferee>> _lire(File f) async {
    if (!await f.exists()) return [];
    try {
      final brut = await f.readAsString();
      if (brut.trim().isEmpty) return [];
      return (jsonDecode(brut) as List)
          .map((e) => ReponseDifferee.fromJson(e as Map<String, dynamic>))
          .whereType<ReponseDifferee>()
          .toList();
    } catch (e) {
      // Fichier illisible : on repart de zéro plutôt que d'empêcher
      // l'application de démarrer.
      debugPrint('[Réponses] fichier illisible, remis à zéro: $e');
      return [];
    }
  }

  static Future<void> _effacer(File f) async {
    try {
      await f.delete();
    } catch (_) {}
  }
}
